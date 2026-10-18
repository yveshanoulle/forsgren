#!/usr/bin/env bash
# canon: test_fbp_no_push v3
# Scripts/test_fbp_no_push.sh
#
# Self-test for the --no-push flag of the repository's FullBuildAndPush script.
# The canon version, byte-identical across the
# estate's repositories: it finds the script as the one of FullBuildAndPush.sh
# and FBP.sh that exists (neither, or both, aborts).
#
# Every case runs a COPY of the real script in a throwaway git repository with
# a bare origin, a stub sfl.sh whose verdict the case sets, a stub `say`, a
# generic stub for every other ./Scripts/<name>.sh the script under test calls
# (parsed from the script itself; each stub records its call and exits 0, so
# the same file works in repositories whose script calls different helpers),
# and no machine-wide git config. Nothing here touches this repository or a network.
#
#   1. --no-push, green run: the commit exists locally, origin is unchanged,
#      exit 0, and the summary says `committed locally, push skipped (--no-push)`
#   2. no flag, green run: the commit is pushed (origin == local)
#   3. --no-push, red run: committed with the *** RED **** subject, origin
#      unchanged, exit 1
#   4. --no-push with nothing to commit but an unpushed commit already local:
#      origin unchanged, exit 0
#   5. --no-push together with --no-commit: rejected (exit 1), nothing committed
#   6. every alias of the flag leaves origin unchanged
#   7. the usage text names the flag
#   8. fbp_agent_friend.sh hands the flag on to the script untouched
#   9. genericity: a script copy with an invented extra helper call still runs
#      under --no-push, the helper stubbed and its call recorded
# Mutation proofs: a copy of the script that ignores the flag (pushes anyway)
# must fail case 1, so case 1 holds BECAUSE the flag is honoured; a stub
# generator that skips a parsed helper name must fail case 9 with the helper
# missing.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "FBP --no-push self-test"

FBP=""
for candidate in FullBuildAndPush.sh FBP.sh; do
  if [[ -f "$candidate" ]]; then
    [[ -z "$FBP" ]] || selftest_abort "both ${FBP} and ${candidate} exist — the script under test is ambiguous"
    FBP="$candidate"
  fi
done
[[ -n "$FBP" ]] || selftest_abort "neither FullBuildAndPush.sh nor FBP.sh exists — there is no script to validate"
FBP_SRC="$(pwd)/${FBP}"
FRIEND_SRC="$(pwd)/Scripts/fbp_agent_friend.sh"

# A stub `say` so the done cue is silent, first on PATH for every case.
mkdir -p "${TMP}/bin"
printf '#!/bin/sh\nexit 0\n' > "${TMP}/bin/say"
chmod +x "${TMP}/bin/say"

# Commits and pushes in the sandbox use only what is set here.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@example.invalid
export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@example.invalid

# stub_helpers <root>: a stub for every ./Scripts/<name>.sh (or Scripts/<name>.sh)
# the script copy in <root> invokes, except sfl.sh (its own stub) and lines
# that only source a file or are comments. A stub appends its name and
# arguments to <root>/../stub_calls.log and exits 0; when the caller sets
# SITE_PAGE_COUNT_FILE (a build helper's result sink) it also writes 1 there. SKIP_STUB, when set, names
# one helper the generator leaves out (used by the mutation proof only).
stub_helpers() {
  local root="$1" name
  while IFS= read -r name; do
    [[ -n "$name" && "$name" != "sfl.sh" && "$name" != "${SKIP_STUB:-}" ]] || continue
    mkdir -p "${root}/Scripts"
    # The escaped \$ expand when the stub runs; name and log path expand here.
    cat > "${root}/Scripts/${name}" <<STUB
#!/usr/bin/env bash
echo "${name} \$*" >> "${root}/../stub_calls.log"
if [ -n "\${SITE_PAGE_COUNT_FILE:-}" ]; then mkdir -p "\$(dirname "\$SITE_PAGE_COUNT_FILE")"; echo 1 > "\$SITE_PAGE_COUNT_FILE"; fi
exit 0
STUB
    chmod +x "${root}/Scripts/${name}"
  done < <(grep -vE '^[[:space:]]*#|^[[:space:]]*(source|\.)[[:space:]]' "${root}/${FBP}" \
    | grep -oE '(\./)?Scripts/[A-Za-z0-9_.-]+\.sh' | sed 's|.*/||' | sort -u)
}

# sandbox <name> <script>: a repository with the script copy, a stub sfl.sh
# (red while the file sfl_red exists), one pushed commit, and a bare origin.
# Echoes the repository path.
sandbox() {
  local root="${TMP}/$1/work"
  local origin="${TMP}/$1/origin.git"
  mkdir -p "$root"
  git init -q --bare "$origin"
  git -C "$root" init -q -b main
  cp "$2" "${root}/${FBP}"
  chmod +x "${root}/${FBP}"
  printf '#!/usr/bin/env bash\n[ -f sfl_red ] && { echo "Errors:"; echo "stub gate failed"; exit 1; }\nexit 0\n' > "${root}/sfl.sh"
  chmod +x "${root}/sfl.sh"
  stub_helpers "$root"
  printf '.build/\nsfl_red\n' > "${root}/.gitignore"
  git -C "$root" add -A
  git -C "$root" commit -q -m "initial"
  git -C "$root" remote add origin "$origin"
  git -C "$root" push -q -u origin main
  echo "$root"
}

# holds <ok message> <fail message> <command...>: one case, green when the command succeeds.
holds() {
  local ok_message="$1"
  local fail_message="$2"
  shift 2
  if "$@"; then
    echo "  ok: ${ok_message}"
  else
    fail "$fail_message"
  fi
}

origin_head() { git -C "${1}/../origin.git" rev-parse refs/heads/main; }
local_head() { git -C "$1" rev-parse HEAD; }

# fbp_in <root> <args...>: runs the sandbox's script copy.
fbp_in() {
  local root="$1"
  shift
  capture env PATH="${TMP}/bin:${PATH}" "${root}/${FBP}" "$@"
}

# scenario_green_no_push <script>: SCEN_OK=1 when a green --no-push run
# commits locally and leaves origin alone. The script under test and its
# mutant go through the same checks.
scenario_green_no_push() {
  local root before
  SCEN_OK=0
  root="$(sandbox "scen-$$-$RANDOM" "$1")"
  before="$(origin_head "$root")"
  printf 'change\n' > "${root}/change.txt"
  fbp_in "$root" --no-push "add change"
  if [[ "$RC" -eq 0 \
    && "$(git -C "$root" log -1 --format=%s)" == "add change" \
    && "$(origin_head "$root")" == "$before" \
    && "$(local_head "$root")" != "$before" ]]; then
    SCEN_OK=1
  fi
}

# --- 1. green, --no-push
R="$(sandbox green-nopush "$FBP_SRC")"
BEFORE="$(origin_head "$R")"
printf 'change\n' > "${R}/change.txt"
fbp_in "$R" --no-push "add change"
want_exit "--no-push green run exits 0 and says the commit stayed local" 0 "committed locally, push skipped (--no-push)"
holds "the commit exists locally with the given subject" "the commit is missing locally or has the wrong subject: $(git -C "$R" log -1 --format=%s)" test "$(git -C "$R" log -1 --format=%s)" = "add change"
holds "origin is unchanged" "--no-push reached origin" test "$(origin_head "$R")" = "$BEFORE"
if grep -q "Aborted" <<< "$OUT"; then
  fail "a green --no-push run was reported as aborted (counted red). Output: ${OUT}"
else
  echo "  ok: the skipped push is not counted as red"
fi

# --- 2. green, no flag: still pushes
R="$(sandbox green-push "$FBP_SRC")"
printf 'change\n' > "${R}/change.txt"
fbp_in "$R" "add change"
want_rc "a green run without the flag exits 0" 0
holds "without the flag the commit is pushed" "a green run without --no-push did not push" test "$(origin_head "$R")" = "$(local_head "$R")"

# --- 3. red, --no-push
R="$(sandbox red-nopush "$FBP_SRC")"
BEFORE="$(origin_head "$R")"
printf 'change\n' > "${R}/change.txt"
touch "${R}/sfl_red"
fbp_in "$R" --no-push "add change"
want_rc "a red --no-push run exits 1" 1
holds "the red run committed with the RED subject" "the red run's subject is not the RED marker: $(git -C "$R" log -1 --format=%s)" test "$(git -C "$R" log -1 --format=%s)" = "*** RED ****"
holds "the red run did not push" "a red --no-push run reached origin" test "$(origin_head "$R")" = "$BEFORE"

# --- 4. nothing new to commit, an unpushed commit already local
R="$(sandbox existing "$FBP_SRC")"
BEFORE="$(origin_head "$R")"
printf 'earlier\n' > "${R}/earlier.txt"
git -C "$R" add -A
git -C "$R" commit -q -m "earlier local commit"
fbp_in "$R" --no-push "nothing new"
want_exit "--no-push with nothing to commit exits 0 and says so" 0 "push skipped (--no-push)"
holds "an already-local commit is not pushed either" "--no-push pushed an existing local commit" test "$(origin_head "$R")" = "$BEFORE"

# --- 5. --no-push with --no-commit is rejected
R="$(sandbox combined "$FBP_SRC")"
BEFORE="$(local_head "$R")"
printf 'change\n' > "${R}/change.txt"
fbp_in "$R" --no-push --no-commit
want_exit "--no-push with --no-commit is rejected" 1 "cannot be combined"
holds "the rejected pair committed nothing" "the rejected pair still committed" test "$(local_head "$R")" = "$BEFORE"

# --- 6. every alias
for alias in -no-push --nopush -nopush /noPush /no-push; do
  R="$(sandbox "alias-${alias//\//_}" "$FBP_SRC")"
  BEFORE="$(origin_head "$R")"
  printf 'change\n' > "${R}/change.txt"
  fbp_in "$R" "$alias" "add change"
  if [[ "$RC" -eq 0 && "$(origin_head "$R")" == "$BEFORE" && "$(local_head "$R")" != "$BEFORE" ]]; then
    echo "  ok: the alias ${alias} commits and does not push"
  else
    fail "the alias ${alias} did not behave as --no-push (exit ${RC}). Output: ${OUT}"
  fi
done

# --- 7. usage
R="$(sandbox usage "$FBP_SRC")"
fbp_in "$R"
want_exit "the usage text names the flag" 1 "--no-push"

# --- 8. fbp_agent_friend.sh hands the flag on
if [[ -f "$FRIEND_SRC" ]]; then
  FR="${TMP}/friend"
  mkdir -p "${FR}/Scripts"
  cp "$FRIEND_SRC" "${FR}/Scripts/fbp_agent_friend.sh"
  printf '#!/usr/bin/env bash\nprintf "ARG:%%s\\n" "$@"\n' > "${FR}/${FBP}"
  chmod +x "${FR}/${FBP}"
  : > "${FR}/key"
  capture env AGENT_FRIEND_SIGNING_KEY="${FR}/key" "${FR}/Scripts/fbp_agent_friend.sh" --no-push "a message"
  if grep -qxF "ARG:--no-push" <<< "$OUT" && grep -qxF "ARG:a message" <<< "$OUT"; then
    echo "  ok: fbp_agent_friend.sh passes --no-push and the message through"
  else
    fail "fbp_agent_friend.sh did not hand --no-push and the message on. Output: ${OUT}"
  fi
fi

# --- 9. genericity: an invented helper call is stubbed and recorded
# scenario_extra_helper: SCEN_OK=1 when a --no-push run of a script copy that
# also calls ./Scripts/check_extra_helper.sh (injected before its first ./sfl.sh call) succeeds and the helper's call was
# recorded.
scenario_extra_helper() {
  local root extra
  SCEN_OK=0
  extra="${TMP}/extra_fbp.sh"
  # The anchor every repo's script has: the first unindented ./sfl.sh call,
  # which every run reaches. The helper call goes in just before it.
  awk '!done && /^\.\/sfl\.sh/ { print "./Scripts/check_extra_helper.sh --probe"; done = 1 } { print }' "$FBP_SRC" > "$extra"
  grep -q 'check_extra_helper.sh' "$extra" || selftest_abort "could not inject the extra helper call: ${FBP} has no unindented ./sfl.sh line"
  root="$(sandbox "extra-$$-$RANDOM" "$extra")"
  printf 'change\n' > "${root}/change.txt"
  fbp_in "$root" --no-push "add change"
  if [[ "$RC" -eq 0 ]] && grep -qxF "check_extra_helper.sh --probe" "${root}/../stub_calls.log" 2>/dev/null; then
    SCEN_OK=1
  fi
}
scenario_extra_helper
if [[ "$SCEN_OK" -eq 1 ]]; then
  echo "  ok: an extra helper call in the script is stubbed, run and recorded"
else
  fail "a script calling an extra helper did not run under --no-push with the helper stubbed and recorded (exit ${RC}). Output: ${OUT}"
fi

# --- Mutation proof: a script that ignores the flag is caught
scenario_green_no_push "$FBP_SRC"
if [[ "$SCEN_OK" -eq 1 ]]; then
  echo "  ok: the real script passes the scenario the mutant must fail"
else
  fail "the scenario fails on the real script, so it proves nothing"
fi
MUT="${TMP}/mutant_fbp.sh"
if selftest_mutant "$FBP_SRC" "$MUT" 's/^      NO_PUSH=true/      NO_PUSH=false/'; then
  scenario_green_no_push "$MUT"
  if [[ "$SCEN_OK" -eq 0 ]]; then
    echo "  ok: mutation proof: a script that ignores --no-push pushes, and the scenario catches it"
  else
    fail "mutation proof: the script that ignores --no-push passed the scenario"
  fi
fi

# Mutation proof: a generator that skips a parsed helper name is caught
SKIP_STUB="check_extra_helper.sh" scenario_extra_helper
if [[ "$SCEN_OK" -eq 0 ]]; then
  echo "  ok: mutation proof: a generator that skips a parsed helper leaves it missing, and the extra-helper case catches it"
else
  fail "mutation proof: the extra-helper case passed although its stub was skipped"
fi

selftest_end "FBP --no-push" "--no-push commits without pushing, a plain run still pushes, red commits RED, the pair with --no-commit is rejected, a script that ignores the flag is caught"
