#!/usr/bin/env bash
# Scripts/test_fbp_push_or_rebase.sh
#
# Self-test for FBP.sh's refused-push handling (forsgren#283, step 1 of 2),
# ported from the estate canon's test_fbp_push_or_rebase v2. When the final
# `git push` is refused because the remote moved during the run, FBP.sh
# fetches, compares the files the incoming commits changed with the files the
# local commits changed, and
#   - no overlap: rebases onto the upstream (the sign-off kept), pushes, and
#     shows a ⚠️ git row naming the short shas rebased onto, saying CI tests
#     that combination, not this run;
#   - overlap, or a rebase conflict: aborts any rebase, leaves the local
#     commits as they were, names the overlapping files and the command to
#     run, and exits non-zero.
#
# forsgren's form, not the canon's byte for byte: the canon runs the push block
# extracted from the wrapper; this drives a COPY of the real FBP.sh end to end,
# the way Scripts/test_fbp_no_push.sh does: a throwaway repository with a bare
# origin, a stub sfl.sh, a stub `say`, a generic stub for every other
# ./Scripts/<name>.sh FBP.sh calls (parsed from it), and the REAL
# Scripts/fbp_push_or_rebase.sh (or the mutant under test) beside it. The
# remote moves DURING the run: the stub sfl.sh, in its post phase, runs the
# case's move script, which pushes the "incoming" commit from a second clone.
# No machine-wide git config; nothing here touches this repository or a network.
#
#   a. incoming commit on an unrelated file: pushed, exit 0, the ⚠️ row names
#      the short sha and says CI tests the combination; origin holds both
#      commits; the pushed local commit keeps its author and its
#      Signed-off-by trailer (DCO), and sits on the incoming commit
#   b. incoming commit on the same file (other lines, so a rebase WOULD
#      succeed): not pushed, exit 1, the local commit unchanged, no rebase left
#      behind, the ❌ lines name the file and the command, the git row is red
#   c. nothing incoming: the ordinary push, no ⚠️ row
#   d. the push is refused for another reason (a pre-receive hook): exit 1,
#      the red row, and a message that it is not a non-fast-forward refusal
#   e. the remote moves again during the rebased push: attempt 2 pushes, the
#      row names the shas of both attempts
#   f. the remote moves on every push: stops after the 3rd push, exit 1, the
#      red row, the local commit kept, rebased, never on origin
# Mutation proof: a copy of the helper with the overlap check removed pushes
# case b, and case b's scenario fails on it for that reason (the file is not
# named and origin moved).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "FBP push-or-rebase self-test"

FBP=FBP.sh
HELPER=fbp_push_or_rebase.sh
[[ -f "$FBP" ]] || selftest_abort "${FBP} is missing — there is no script to validate"
FBP_SRC="$(pwd)/${FBP}"
HELPER_SRC="$(pwd)/Scripts/${HELPER}"
if [[ ! -f "$HELPER_SRC" ]]; then
  fail "Scripts/${HELPER} does not exist — FBP.sh has no refused-push handling to copy into the sandbox"
fi

# A stub `say` so the done cue is silent, first on PATH for every case.
mkdir -p "${TMP}/bin"
printf '#!/bin/sh\nexit 0\n' > "${TMP}/bin/say"
chmod +x "${TMP}/bin/say"

# Commits and pushes in the sandbox use only what is set here. GIT_CONFIG_NOSYSTEM
# too (forsgren#292): Apple's git reads a built-in gitconfig of its own (Xcode's,
# init.defaultBranch=main) that GIT_CONFIG_SYSTEM=/dev/null does not turn off,
# so without it the fixture passed on a Mac with Apple's git and failed on
# GitHub's hosted Mac, whose Homebrew git has no such file.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@example.invalid
export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@example.invalid
SIGNOFF="Signed-off-by: tester <tester@example.invalid>"

# Twenty lines, so two commits can touch the same file at its two ends and
# still rebase cleanly: the overlap check, not git, must be what stops it.
TWENTY="$(seq 1 20 | sed 's/^/line /')"

# stub_helpers <root>: a stub for every ./Scripts/<name>.sh the FBP.sh copy in
# <root> invokes, except sfl.sh (its own stub) and the helper under test (the
# real copy), and lines that only source a file or are comments. A stub exits
# 0; when the caller sets SITE_PAGE_COUNT_FILE (the build's sink) it writes 1
# there, so the build row is green.
stub_helpers() {
  local root="$1" name
  mkdir -p "${root}/Scripts"
  while IFS= read -r name; do
    [[ -n "$name" && "$name" != "sfl.sh" && "$name" != "$HELPER" ]] || continue
    cat > "${root}/Scripts/${name}" <<'STUB'
#!/usr/bin/env bash
if [ -n "${SITE_PAGE_COUNT_FILE:-}" ]; then mkdir -p "$(dirname "$SITE_PAGE_COUNT_FILE")"; echo 1 > "$SITE_PAGE_COUNT_FILE"; fi
exit 0
STUB
    chmod +x "${root}/Scripts/${name}"
  done < <(grep -vE '^[[:space:]]*#|^[[:space:]]*(source|\.)[[:space:]]' "${root}/${FBP}" \
    | grep -oE '(\./)?Scripts/[A-Za-z0-9_.-]+\.sh' | sed 's|.*/||' | sort -u)
}

# world <name> <helper>: <dir>/origin.git, a clone <dir>/work with the FBP.sh
# copy, the helper copy (when it exists), the stubs and one pushed commit, and
# a clone <dir>/other at the same commit. The stub sfl.sh runs <dir>/move.sh
# in its post phase when the case wrote one. Echoes <dir>.
world() {
  local dir="${TMP}/$1"
  local root="${dir}/work"
  mkdir -p "$root"
  # main named on the bare origin too, never git's default (forsgren#292):
  # with an origin HEAD on an unborn master, the "other" clone checks out
  # nothing, its incoming commit is a root commit on master and its push of
  # main is refused, so the remote never moves.
  git init -q --bare -b main "${dir}/origin.git"
  git -C "$root" init -q -b main
  cp "$FBP_SRC" "${root}/${FBP}"
  chmod +x "${root}/${FBP}"
  stub_helpers "$root"
  if [[ -f "$2" ]]; then
    cp "$2" "${root}/Scripts/${HELPER}"
    chmod +x "${root}/Scripts/${HELPER}"
  fi
  cat > "${root}/sfl.sh" <<'SFL'
#!/usr/bin/env bash
if [ "$1" = post ] && [ -x ../move.sh ]; then ../move.sh; fi
exit 0
SFL
  chmod +x "${root}/sfl.sh"
  printf '.build/\n' > "${root}/.gitignore"
  printf '%s\n' "$TWENTY" > "${root}/shared.txt"
  git -C "$root" add -A
  git -C "$root" commit -q -m "initial"
  git -C "$root" remote add origin "${dir}/origin.git"
  git -C "$root" push -q -u origin main 2>/dev/null
  git clone -q "${dir}/origin.git" "${dir}/other" 2>/dev/null
  echo "$dir"
}

# move_new_file <dir> <file>: during the run, the "other" clone pushes one
# commit adding <file>.
move_new_file() {
  cat > "$1/move.sh" <<MOVE
#!/usr/bin/env bash
printf 'incoming\n' > "$1/other/$2"
git -C "$1/other" add -A
git -C "$1/other" commit -q -m "incoming $2"
git -C "$1/other" push -q origin main 2>/dev/null
MOVE
  chmod +x "$1/move.sh"
}

# move_shared_top <dir>: during the run, the "other" clone pushes a change to
# line 1 of shared.txt.
move_shared_top() {
  cat > "$1/move.sh" <<MOVE
#!/usr/bin/env bash
sed -i.bak '1s/.*/incoming first line/' "$1/other/shared.txt"
rm -f "$1/other/shared.txt.bak"
git -C "$1/other" commit -q -am "incoming shared"
git -C "$1/other" push -q origin main 2>/dev/null
MOVE
  chmod +x "$1/move.sh"
}

# change_shared_bottom <dir>: the run's change, line 20 of shared.txt.
change_shared_bottom() {
  sed -i.bak '20s/.*/local last line/' "$1/work/shared.txt"
  rm -f "$1/work/shared.txt.bak"
}
# change_new_file <dir>: the run's change, a new file local.txt.
change_new_file() {
  printf 'local\n' > "$1/work/local.txt"
}

origin_head() { git -C "${1}/origin.git" rev-parse refs/heads/main; }
work_head() { git -C "${1}/work" rev-parse HEAD; }
other_short() { git -C "${1}/other" rev-parse --short HEAD; }

# fbp_in <dir> <message>: runs the sandbox's FBP.sh copy with <message>.
fbp_in() {
  capture env PATH="${TMP}/bin:${PATH}" "${1}/work/${FBP}" "$2"
}

# git_row: the git row of the last run's summary.
git_row() {
  awk 'index($0, "  git ") == 1 { print; exit }' <<< "$OUT"
}

# no_rebase_left <dir>: the work clone has no rebase in progress.
no_rebase_left() {
  [[ ! -d "${1}/work/.git/rebase-merge" && ! -d "${1}/work/.git/rebase-apply" ]]
}

# scenario_overlap <helper>: SCEN_OK=1 when a run whose remote moved on the
# SAME file is stopped: exit 1, a red git row, the file and the command named,
# nothing pushed, the local commit the run made unchanged (on the initial
# commit, not rebased), and no rebase left behind.
scenario_overlap() {
  local dir initial before_origin
  SCEN_OK=0
  dir="$(world "ov-$$-$RANDOM" "$1")"
  initial="$(work_head "$dir")"
  change_shared_bottom "$dir"
  move_shared_top "$dir"
  fbp_in "$dir" "local shared"
  before_origin="$(git -C "${dir}/other" rev-parse HEAD)"
  if [[ "$RC" -eq 1 ]] \
    && grep -qF '❌ (push refused, remote moved — see above)' <<< "$(git_row)" \
    && grep -qF '   shared.txt' <<< "$OUT" \
    && grep -qF 'git pull --rebase --autostash' <<< "$OUT" \
    && [[ "$(git -C "${dir}/work" rev-parse HEAD~1)" == "$initial" ]] \
    && [[ "$(git -C "${dir}/work" log -1 --format=%s)" == "local shared" ]] \
    && [[ "$(origin_head "$dir")" == "$before_origin" ]] \
    && no_rebase_left "$dir"; then
    SCEN_OK=1
  fi
}

# --- a. unrelated incoming file: rebased, pushed, ⚠️ row, sign-off kept
D="$(world unrelated "$HELPER_SRC")"
change_new_file "$D"
move_new_file "$D" theirs.txt
fbp_in "$D" "add local file"
INCOMING_SHA="$(other_short "$D")"
want_exit "an unrelated incoming file is rebased over and pushed, exit 0" 0 "All checks passed"
ROW="$(git_row)"
if grep -qF "⚠️ (pushed after rebasing onto ${INCOMING_SHA}; this combination is tested by CI, not by this run)" <<< "$ROW"; then
  echo "  ok: the git row is the ⚠️ one, names the sha rebased onto and says CI tests the combination"
else
  fail "the git row is not the ⚠️ rebase row naming ${INCOMING_SHA}: '${ROW}'. Output: ${OUT}"
fi
if git -C "${D}/origin.git" show refs/heads/main:theirs.txt > /dev/null 2>&1 \
  && git -C "${D}/origin.git" show refs/heads/main:local.txt > /dev/null 2>&1 \
  && [[ "$(origin_head "$D")" == "$(work_head "$D")" ]]; then
  echo "  ok: origin holds the incoming and the local commit"
else
  fail "origin lacks one of the two commits after the rebase push. Output: ${OUT}"
fi
TIP_BODY="$(git -C "${D}/origin.git" log -1 --format=%B refs/heads/main)"
TIP_AUTHOR="$(git -C "${D}/origin.git" log -1 --format=%ae refs/heads/main)"
TIP_PARENT="$(git -C "${D}/origin.git" rev-parse --short refs/heads/main~1)"
if grep -qxF "$SIGNOFF" <<< "$TIP_BODY" && [[ "$TIP_AUTHOR" == "tester@example.invalid" && "$TIP_PARENT" == "$INCOMING_SHA" ]]; then
  echo "  ok: the rebased commit on origin sits on the incoming one and keeps its author and its Signed-off-by trailer (DCO)"
else
  fail "the pushed commit lost its sign-off or author, or is not rebased onto ${INCOMING_SHA} (parent ${TIP_PARENT}, author ${TIP_AUTHOR}). Message: ${TIP_BODY}"
fi

# --- b. same file: stopped, local commit untouched, the file named
scenario_overlap "$HELPER_SRC"
if [[ "$SCEN_OK" -eq 1 ]]; then
  echo "  ok: an incoming commit on the same file stops the push, exit 1, names the file and the command, leaves the local commit and origin alone"
else
  fail "the same-file case was not stopped as required (exit ${RC}, git row '$(git_row)'). Output: ${OUT}"
fi
want_said "the overlap failure carries the red cross" "❌ FAIL: the push was refused"

# --- c. nothing incoming: the ordinary push
D="$(world plain "$HELPER_SRC")"
change_new_file "$D"
fbp_in "$D" "add local file"
want_exit "with nothing incoming the push is the ordinary one" 0 "All checks passed"
if grep -qF 'rebasing' <<< "$(git_row)"; then
  fail "an ordinary push reported a rebase: '$(git_row)'"
else
  echo "  ok: no rebase row for an ordinary push"
fi
if [[ "$(origin_head "$D")" == "$(work_head "$D")" ]]; then
  echo "  ok: origin has the local commit"
else
  fail "the ordinary push did not reach origin. Output: ${OUT}"
fi

# --- d. refused for another reason
D="$(world otherreason "$HELPER_SRC")"
change_new_file "$D"
mkdir -p "${D}/origin.git/hooks"
printf '#!/bin/sh\necho refused by hook\nexit 1\n' > "${D}/origin.git/hooks/pre-receive"
chmod +x "${D}/origin.git/hooks/pre-receive"
fbp_in "$D" "add local file"
want_exit "a push refused for another reason says it is not a non-fast-forward refusal, exit 1" 1 "not a non-fast-forward refusal"
if grep -qF '❌ (push refused, remote moved — see above)' <<< "$(git_row)"; then
  echo "  ok: that run's git row is the red one"
else
  fail "a push refused for another reason did not show the red git row: '$(git_row)'"
fi

# --- e/f. the remote moves again while the rebased push is in flight
# install_hook <dir> <mode>: a pre-receive hook on the bare origin, armed by the
# case's move script once its incoming push is in (so that push is not counted
# or refused). On each push that reaches it armed (the natural refusal never
# does: the client knows the remote moved) it commits one unrelated file to the
# origin's main and refuses the push, once (mode once) or every time (mode
# always).
install_hook() {
  mkdir -p "${1}/origin.git/hooks"
  printf '%s\n' "$2" > "${1}/origin.git/hooks/mode"
  printf 'touch "%s/origin.git/hooks/armed"\n' "$1" >> "${1}/move.sh"
  cat > "${1}/origin.git/hooks/pre-receive" <<'HOOK_EOF'
#!/bin/sh
[ -f hooks/armed ] || exit 0
n=$(cat hooks/count 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > hooks/count

mode=$(cat hooks/mode)
if [ "$mode" = once ] && [ "$n" -ne 1 ]; then exit 0; fi
unset GIT_QUARANTINE_PATH GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
blob=$(echo "moved $n" | git hash-object -w --stdin)
tree=$( { git ls-tree refs/heads/main; printf '100644 blob %s\tmoved%s.txt\n' "$blob" "$n"; } | git mktree)
c=$(git commit-tree "$tree" -p refs/heads/main -m "moved $n")
git update-ref refs/heads/main "$c"
echo "remote moved again"
exit 1
HOOK_EOF
  chmod +x "${1}/origin.git/hooks/pre-receive"
}

# e. moved once more: attempt 2 pushes, the row names both shas
D="$(world movesonce "$HELPER_SRC")"
change_new_file "$D"
move_new_file "$D" theirs.txt
install_hook "$D" once
fbp_in "$D" "add local file"
FIRST_SHA="$(other_short "$D")"
want_exit "a remote that moves again is rebased over again and pushed, exit 0" 0 "All checks passed"
MOVED_SHA="$(git -C "${D}/origin.git" rev-parse --short refs/heads/main~1)"
if grep -qF "rebasing onto ${FIRST_SHA} ${MOVED_SHA};" <<< "$(git_row)"; then
  echo "  ok: the row names the shas of both attempts"
else
  fail "the row does not name ${FIRST_SHA} and ${MOVED_SHA}: '$(git_row)'. Output: ${OUT}"
fi
if git -C "${D}/origin.git" show refs/heads/main:moved1.txt > /dev/null 2>&1 \
  && git -C "${D}/origin.git" show refs/heads/main:theirs.txt > /dev/null 2>&1 \
  && git -C "${D}/origin.git" show refs/heads/main:local.txt > /dev/null 2>&1 \
  && [[ "$(origin_head "$D")" == "$(work_head "$D")" ]]; then
  echo "  ok: origin holds both incoming commits and the local commit"
else
  fail "origin lacks one of the three commits after the second attempt. Output: ${OUT}"
fi

# f. moved every time: stops after the 3rd push, the local commit kept rebased
D="$(world movesalways "$HELPER_SRC")"
INITIAL="$(work_head "$D")"
change_new_file "$D"
move_new_file "$D" theirs.txt
install_hook "$D" always
fbp_in "$D" "add local file"
want_exit "a remote that keeps moving stops the run, exit 1, and says why" 1 "push refused 3 times, remote keeps moving"
if grep -qF '❌ (push refused, remote moved — see above)' <<< "$(git_row)"; then
  echo "  ok: that run's git row is the red one"
else
  fail "a remote that keeps moving did not show the red git row: '$(git_row)'"
fi
if [[ "$(git -C "${D}/work" log -1 --format=%s)" == "add local file" && "$(git -C "${D}/work" rev-parse HEAD~1)" != "$INITIAL" ]] \
  && ! git -C "${D}/origin.git" show refs/heads/main:local.txt > /dev/null 2>&1; then
  echo "  ok: the local commit stays, rebased, and never reached origin"
else
  fail "after three refusals the local commit is not the rebased tip, or reached origin. Output: ${OUT}"
fi
PUSHES_SEEN="$(cat "${D}/origin.git/hooks/count" 2>/dev/null || echo 0)"
if [[ "$PUSHES_SEEN" -eq 2 ]]; then
  echo "  ok: 3 pushes in total: the refused original and exactly two rebase pushes at the origin"
else
  fail "the origin saw ${PUSHES_SEEN} pushes, expected 2 (3 pushes in total: the refused original, which never reaches the hook, and two rebase pushes)"
fi

# --- Mutation proof: no overlap check, the same-file case is pushed
scenario_overlap "$HELPER_SRC"
if [[ "$SCEN_OK" -ne 1 ]]; then
  fail "the overlap scenario fails on the real helper, so the mutation proof proves nothing"
elif [[ -f "$HELPER_SRC" ]]; then
  MUT="${TMP}/mutant/${HELPER}"
  # The overlap list is emptied at its one call site, the `# overlap-check` line.
  if selftest_mutant "$HELPER_SRC" "$MUT" 's/^\( *overlap=\).*# overlap-check$/\1""/'; then
    scenario_overlap "$MUT"
    if [[ "$SCEN_OK" -eq 0 && "$RC" -eq 0 ]] && ! grep -qF '   shared.txt' <<< "$OUT"; then
      echo "  ok: mutation proof: without the overlap check the same-file case is pushed, and the scenario fails on the missing file name"
    else
      fail "mutation proof: the helper without the overlap check did not push the same-file case (exit ${RC}). Output: ${OUT}"
    fi
  fi
fi

selftest_end "FBP push-or-rebase" "a refused push is rebased over unrelated incoming files, signed off, and reported, stopped on overlapping files with the local commits untouched, stopped after 3 pushes, and the overlap check is what stops it"
