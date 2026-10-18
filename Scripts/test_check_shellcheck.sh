#!/usr/bin/env bash
# canon: test_check_shellcheck v4
# Scripts/test_check_shellcheck.sh
#
# Fixture test for Scripts/check_shellcheck.sh — the guard that keeps every
# tracked shell script under shellcheck, not just the ones a human
# remembered to name.
#
# Drives the checker against synthetic git trees (via SHELLCHECK_ROOT), so
# the pins never depend on this repo's real file layout — and so a fixture
# in server/sbin/ with a real shellcheck error proves the coverage gap
# (server/sbin/*.sh was never checked before target collection was
# derived) is actually closed, not just described.
#
# Pinned behaviours:
#   1. a clean synthetic tree (well-formed scripts only)         -> exit 0
#   2. a server/sbin/*.sh fixture with a real shellcheck finding -> exit 1,
#      naming that file (the coverage gap this test exists for)
#   3. the same finding, but the file sits under Scripts/ instead
#      (the glob this check always had)                          -> exit 1
#   4. an extension-less tracked file with a bash shebang and a real
#      finding is caught too                                     -> exit 1
#   5. an extension-less tracked file with NO shebang (e.g. a data
#      file with no extension) is left alone, clean tree stays    -> exit 0
#   6. a *.sh file that is merely mentioned in another file's text
#      (a comment, a doc) but not itself tracked is not invented
#      out of thin air                                            -> exit 0
#   8. an UNTRACKED, not-ignored script with a finding, with and without an
#      extension                                    -> exit 1
#   9. the same finding in a gitignored file                      -> exit 0
#   7. an empty EXCLUDE_ALLOWED does not blow up on bash 3.2 under
#      `set -u` (an empty-string-not-array shape)
#  10. a script listed in Scripts/shellcheck_exclusions.txt is left out    -> exit 0
#  11. that data file missing                                    -> exit 1
#  12. a malformed line, or an entry that is not a file          -> exit 1
#  13. a finding writes the full report to .build/shellcheck.log
#  14. this repository, as it is, with its own exclusions file   -> exit 0
#  15. a tree with no shell script at all                        -> exit 1, never a green over nothing
#  16. a file list: a broken script outside the list is not judged -> exit 0;
#      the broken script in the list is                            -> exit 1, named
#  17. a listed path that is no file                             -> exit 1, named
#  18. a listed file that is in the exclusions file              -> exit 0
# Mutation proofs (a weakened COPY of the gate must turn a red case green):
#   A. the exit status swallowed: case 3
#   B. discovery back to a fixed Scripts/ list: case 2 (server/sbin)
#   C. the shebang source dropped: an extension-less wrapper (case 4)
#   D. the exclusions file ignored when missing: case 11
#   E. the exclusions entry check removed: case 12
#   F. zero targets passing: case 15
#   G. the file list ignored (the whole tree scanned): case 16 turns red

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=Scripts/lib_git_sandbox.sh
source "${ROOT}/Scripts/lib_git_sandbox.sh"
SCRIPT_UNDER_TEST="${ROOT}/Scripts/check_shellcheck.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failed=0
assert_log() { [[ -n "${ASSERTS_LOG:-}" ]] && echo "ASSERT: $1" >> "$ASSERTS_LOG" || true; }
ok()   { assert_log "check_shellcheck: $*"; echo "OK:   $*"; }
fail() { assert_log "check_shellcheck: $*"; echo "❌ FAIL: $*"; failed=1; }

indent_out() { echo "      ${1//$'\n'/$'\n'      }"; }

# make_case <case-dir> — an empty git repo (no identity needed: this check
# only ever calls `git ls-files`, never `git commit`).
make_case() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
}

# add_file <case-dir> <relative-path> <content> — writes and stages a file.
add_file() {
  local dir="$1" path="$2" content="$3"
  mkdir -p "$(dirname "${dir}/${path}")"
  printf '%s' "$content" > "${dir}/${path}"
  chmod +x "${dir}/${path}"
  git -C "$dir" add "$path"
}

# write_file <case-dir> <relative-path> <content> — writes a file, does not
# stage it: an untracked file, the state of a new file while the gates run.
write_file() {
  local dir="$1" path="$2" content="$3"
  mkdir -p "$(dirname "${dir}/${path}")"
  printf '%s' "$content" > "${dir}/${path}"
  chmod +x "${dir}/${path}"
}

# run_guard <case-dir> — sets RC and OUT.
run_guard() {
  local dir="$1"
  OUT="$(SHELLCHECK_ROOT="$dir" bash "$SCRIPT_UNDER_TEST" 2>&1)"
  RC=$?
}

CLEAN_SH='#!/usr/bin/env bash
set -euo pipefail
echo "hello"
'

# A finding real enough to fail the default invocation (SC2086: unquoted
# expansion) without needing any particular severity — any finding at all
# fails shellcheck's default exit code. The $1/$name below are literal
# fixture text being written to a file for the SCRIPT UNDER TEST to
# analyze, not a shell expansion in this test file: the quoted heredoc
# delimiter ('EOF') keeps them unexpanded. `read -d ''` keeps the trailing
# newline a `$(cat <<'EOF')` would strip, and returns 1 at end of input,
# hence `|| true`.
IFS= read -r -d '' BROKEN_SH <<'EOF' || true
#!/usr/bin/env bash
name=$1
echo $name
EOF

# 1. Clean synthetic tree.
A="$TMP/clean"
make_case "$A"
add_file "$A" "Scripts/ok.sh" "$CLEAN_SH"
add_file "$A" "server/sbin/ok.sh" "$CLEAN_SH"
run_guard "$A"
if [ "$RC" -eq 0 ]; then
  ok "a clean synthetic tree passes"
else
  fail "clean tree should pass, got exit $RC"
  indent_out "$OUT"
fi

# 2. The coverage gap this test exists for: server/sbin/*.sh was never
#    named anywhere in the old check, so a real error there went uncaught.
B="$TMP/sbin_broken"
make_case "$B"
add_file "$B" "Scripts/ok.sh" "$CLEAN_SH"
add_file "$B" "server/sbin/webinfra-example.sh" "$BROKEN_SH"
run_guard "$B"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'server/sbin/webinfra-example.sh'; then
  ok "a shellcheck error under server/sbin/ fails the guard, named"
else
  fail "server/sbin error should fail the guard and be named, got exit $RC"
  indent_out "$OUT"
fi

# 3. The same finding under Scripts/ — the glob this check always had,
#    pinned so target collection is proven on both an old and a new path.
C="$TMP/scripts_broken"
make_case "$C"
add_file "$C" "Scripts/broken.sh" "$BROKEN_SH"
run_guard "$C"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'Scripts/broken.sh'; then
  ok "a shellcheck error under Scripts/ still fails the guard, named"
else
  fail "Scripts/ error should fail the guard and be named, got exit $RC"
  indent_out "$OUT"
fi

# 4. Extension-less tracked file with a bash shebang: this check's second
#    target source. Its own name has no .sh to glob on.
D="$TMP/extensionless_broken"
make_case "$D"
add_file "$D" "server/sbin/webinfra-wrapper" "$BROKEN_SH"
run_guard "$D"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'server/sbin/webinfra-wrapper'; then
  ok "an extension-less bash-shebang file with a finding fails the guard, named"
else
  fail "extension-less shebang file should fail the guard and be named, got exit $RC"
  indent_out "$OUT"
fi

# 5. Extension-less tracked file with NO shebang (a data file, say) must
#    not be treated as a shell script — collection is shebang-gated, not
#    "every extension-less file".
E="$TMP/extensionless_data"
make_case "$E"
add_file "$E" "Scripts/ok.sh" "$CLEAN_SH"
add_file "$E" "data/manifest" "not a script, just data
"
run_guard "$E"
if [ "$RC" -eq 0 ]; then
  ok "an extension-less file with no shebang is left alone"
else
  fail "extension-less non-shebang file should not be shellchecked, got exit $RC"
  indent_out "$OUT"
fi

# 6. A *.sh name that only appears in another file's TEXT (a comment) but
#    is never itself written or staged must not be invented as a target —
#    collection reads `git ls-files`, not grep over file contents.
F="$TMP/mentioned_only"
make_case "$F"
add_file "$F" "Scripts/mentions.sh" '#!/usr/bin/env bash
# see also server/sbin/not-a-real-file.sh for details
echo "hi"
'
run_guard "$F"
if [ "$RC" -eq 0 ]; then
  ok "a filename only mentioned in a comment is not invented as a target"
else
  fail "comment-only filename should not be treated as a real target, got exit $RC"
  indent_out "$OUT"
fi

# 7. Empty EXCLUDE_ALLOWED does not trip an unbound-variable error on
#    bash 3.2 (checked against the last run's output — any of the passing
#    cases above already exercised this path).
if printf '%s\n' "$OUT" | grep -qi "unbound variable"; then
  fail "empty EXCLUDE_ALLOWED tripped an unbound-variable error"
  indent_out "$OUT"
else
  ok "empty EXCLUDE_ALLOWED expands safely"
fi

# 8. a NEW file is untracked while the gates run (FBP commits
#    after them), so an untracked, not-ignored script with a finding fails
#    the guard too, named: a script with an extension, and an extension-less
#    one with a bash shebang.
G="$TMP/untracked_broken"
make_case "$G"
add_file "$G" "Scripts/ok.sh" "$CLEAN_SH"
write_file "$G" "Scripts/new_broken.sh" "$BROKEN_SH"
write_file "$G" "Scripts/new-wrapper" "$BROKEN_SH"
run_guard "$G"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'Scripts/new_broken.sh' && printf '%s\n' "$OUT" | grep -q 'Scripts/new-wrapper'; then
  ok "an untracked script with a finding fails the guard, both forms named"
else
  fail "an untracked .sh and an untracked extension-less script with a finding should fail the guard and be named, got exit $RC"
  indent_out "$OUT"
fi

# 9. An untracked file that git ignores will never be committed: left alone.
H="$TMP/ignored_broken"
make_case "$H"
add_file "$H" "Scripts/ok.sh" "$CLEAN_SH"
add_file "$H" ".gitignore" "scratch/
"
write_file "$H" "scratch/broken.sh" "$BROKEN_SH"
run_guard "$H"
if [ "$RC" -eq 0 ]; then
  ok "an ignored broken script is left alone"
else
  fail "an ignored script should not be shellchecked, got exit $RC"
  indent_out "$OUT"
fi

# run_copy <case-dir> <exclusions-content|-> — runs a COPY of the checker (with its
# lib and an exclusions file) from <case-dir>/Scripts, so the data file is the
# fixture's own. "-" writes no exclusions file at all. Sets RC and OUT.
run_copy() {
  local dir="$1" excl="$2"
  mkdir -p "${dir}/Scripts"
  cp "$SCRIPT_UNDER_TEST" "${ROOT}/Scripts/lib_repo_files.sh" "${dir}/Scripts/"
  rm -f "${dir}/Scripts/shellcheck_exclusions.txt"
  [ "$excl" = "-" ] || printf '%s' "$excl" > "${dir}/Scripts/shellcheck_exclusions.txt"
  OUT="$(SHELLCHECK_ROOT="$dir" bash "${dir}/Scripts/check_shellcheck.sh" 2>&1)"
  RC=$?
}

# 10. A listed exclusion is left out: the same broken script is green.
X="$TMP/excluded"
make_case "$X"
add_file "$X" "legacy/broken.sh" "$BROKEN_SH"
run_copy "$X" "# one entry
legacy/broken.sh
"
if [ "$RC" -eq 0 ]; then
  ok "a script listed in the exclusions file is left out"
else
  fail "a listed exclusion should be skipped, got exit $RC"
  indent_out "$OUT"
fi

# 10b. The same tree without the entry is red: the exclusion, not the tree, made it green.
run_copy "$X" ""
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'legacy/broken.sh'; then
  ok "without the entry the same script is red, named"
else
  fail "the script should be red without its exclusion entry, got exit $RC"
  indent_out "$OUT"
fi

# 11. The data file is required: fail closed.
M="$TMP/no_exclusions_file"
make_case "$M"
add_file "$M" "Scripts/ok.sh" "$CLEAN_SH"
run_copy "$M" "-"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'shellcheck_exclusions.txt'; then
  ok "a missing exclusions file is red, named"
else
  fail "a missing exclusions file should be red, got exit $RC"
  indent_out "$OUT"
fi

# 12. A malformed line and a path that is no file are both red.
for bad in "two words" "../outside.sh" "does/not/exist.sh"; do
  N="$TMP/bad_exclusion_${bad//[^a-z]/_}"
  make_case "$N"
  add_file "$N" "Scripts/ok.sh" "$CLEAN_SH"
  run_copy "$N" "${bad}
"
  if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -qF "'${bad}'"; then
    ok "the exclusions entry '${bad}' is red, named"
  else
    fail "the exclusions entry '${bad}' should be red, got exit $RC"
    indent_out "$OUT"
  fi
done

# 13. The full report of a finding is written to .build/shellcheck.log.
if [ -s "$C/.build/shellcheck.log" ] && grep -qF "Scripts/broken.sh" "$C/.build/shellcheck.log"; then
  ok "the full report is written to .build/shellcheck.log"
else
  fail "the full report was not written to .build/shellcheck.log"
fi

# 14. This repository, as it is: its own tree and its own exclusions file.
OUT="$(bash "$SCRIPT_UNDER_TEST" 2>&1)"
RC=$?
if [ "$RC" -eq 0 ]; then
  ok "this repository's shell scripts pass"
else
  fail "this repository's shell scripts should pass, got exit $RC"
  indent_out "$OUT"
fi

# 15. No shell script anywhere: red, never a green over nothing.
Z="$TMP/no_scripts"
make_case "$Z"
add_file "$Z" "README.md" "no shell here
"
run_guard "$Z"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'no shell scripts found'; then
  ok "a tree with no shell script is red, with the reason"
else
  fail "zero shell scripts should be red and say so, got exit $RC"
  indent_out "$OUT"
fi

# run_list <case-dir> <file>... — the checker with a file list. Sets RC and OUT.
run_list() {
  local dir="$1"
  shift
  OUT="$(SHELLCHECK_ROOT="$dir" bash "$SCRIPT_UNDER_TEST" "$@" 2>&1)"
  RC=$?
}

# 16. A file list: only the listed files are judged.
L="$TMP/file_list"
make_case "$L"
add_file "$L" "Scripts/ok.sh" "$CLEAN_SH"
add_file "$L" "Scripts/broken.sh" "$BROKEN_SH"
run_list "$L" Scripts/ok.sh
if [ "$RC" -eq 0 ]; then
  ok "a file list: a broken script outside the list is not judged"
else
  fail "the broken script is outside the list and must not be judged, got exit $RC"
  indent_out "$OUT"
fi
run_list "$L" Scripts/broken.sh
if [ "$RC" -ne 0 ] && [[ "$OUT" == *"Scripts/broken.sh"* ]]; then
  ok "a file list: the broken script in the list is red, named"
else
  fail "the broken script in the list should be red and named, got exit $RC"
  indent_out "$OUT"
fi

# 17. A listed path that is no file is red, named.
run_list "$L" Scripts/ok.sh Scripts/missing.sh
if [ "$RC" -ne 0 ] && [[ "$OUT" == *"Scripts/missing.sh"* ]]; then
  ok "a file list naming a missing file is red, named"
else
  fail "a listed missing file should be red and named, got exit $RC"
  indent_out "$OUT"
fi

# 18. A listed file that is in the exclusions file is left out, as without a list.
run_copy "$X" "legacy/broken.sh
"
OUT="$(SHELLCHECK_ROOT="$X" bash "${X}/Scripts/check_shellcheck.sh" legacy/broken.sh 2>&1)"
RC=$?
if [ "$RC" -eq 0 ]; then
  ok "a file list keeps the exclusions: a listed excluded script is left out"
else
  fail "a listed excluded script should be left out, got exit $RC"
  indent_out "$OUT"
fi

# --- Mutation proofs. mutant_green <label> <sed-expr> <case-dir> <ok text>:
# writes a weakened copy of the gate (with its lib and the real exclusions
# file) and requires it to turn the red case in <case-dir> green. A sed that
# changes nothing is a failed proof, never a vacuous pass.
mutant_green() {
  local label="$1" expr="$2" case_dir="$3" text="$4" md="$TMP/mutant_$1" mrc mout
  mkdir -p "${md}/Scripts"
  cp "${ROOT}/Scripts/lib_repo_files.sh" "${ROOT}/Scripts/shellcheck_exclusions.txt" "${md}/Scripts/"
  sed "$expr" "$SCRIPT_UNDER_TEST" > "${md}/Scripts/check_shellcheck.sh"
  if cmp -s "$SCRIPT_UNDER_TEST" "${md}/Scripts/check_shellcheck.sh"; then
    fail "mutation ${label}: the sed changed nothing, the proof would be vacuous"
    return 0
  fi
  mout="$(SHELLCHECK_ROOT="$case_dir" bash "${md}/Scripts/check_shellcheck.sh" 2>&1)"
  mrc=$?
  if [ "$mrc" -eq 0 ]; then
    ok "mutation proof ${label}: ${text}"
  else
    fail "mutation proof ${label}: the weakened copy stayed red (exit ${mrc}), so the case is not red for the stated reason"
    indent_out "$mout"
  fi
}

mutant_green A 's/^exit "[$]rc"/exit 0/' "$C" \
  "a copy that swallows the exit status turns the Scripts/ finding green"
mutant_green B "s#repo_files \. '\\*\\.sh'#repo_files . 'Scripts/ok.sh'#" "$B" \
  "a copy that reads a fixed list does not see server/sbin, so any-depth discovery is what catches it"
E2="$TMP/mutant_wrapper_case"
make_case "$E2"
add_file "$E2" "Scripts/ok.sh" "$CLEAN_SH"
add_file "$E2" "bin/wrapper" "$BROKEN_SH"
mutant_green C 's/if \[\[ "[$]first_line" =~ .*\]\]; then/if false; then/' "$E2" \
  "a copy without the shebang source does not see an extension-less wrapper"
NM="$TMP/mutant_missing_case"
make_case "$NM"
add_file "$NM" "Scripts/ok.sh" "$CLEAN_SH"
# D needs the exclusions file absent: the mutant dir keeps a copy, so remove it after the copy.
md="$TMP/mutant_D"
mkdir -p "${md}/Scripts"
cp "${ROOT}/Scripts/lib_repo_files.sh" "${md}/Scripts/"
sed -e 's/if \[ ! -f "[$]EXCLUSIONS_FILE" \]; then/if false; then/' -e 's#^done < "[$]EXCLUSIONS_FILE"#done < /dev/null#' "$SCRIPT_UNDER_TEST" > "${md}/Scripts/check_shellcheck.sh"
if cmp -s "$SCRIPT_UNDER_TEST" "${md}/Scripts/check_shellcheck.sh"; then
  fail "mutation D: the sed changed nothing, the proof would be vacuous"
else
  mout="$(SHELLCHECK_ROOT="$M" bash "${md}/Scripts/check_shellcheck.sh" 2>&1)"
  mrc=$?
  if [ "$mrc" -eq 0 ]; then
    ok "mutation proof D: a copy that treats a missing exclusions file as empty turns case 11 green"
  else
    fail "mutation proof D: the weakened copy stayed red (exit ${mrc})"
    indent_out "$mout"
  fi
fi
# E: the bad-entry check removed; run on a fixture with a bad entry in the copy's own data file.
md="$TMP/mutant_E"
mkdir -p "${md}/Scripts"
cp "${ROOT}/Scripts/lib_repo_files.sh" "${md}/Scripts/"
printf 'does/not/exist.sh\n' > "${md}/Scripts/shellcheck_exclusions.txt"
sed 's/if ! \[\[ "[$]line" =~ .*\]\] || \[ ! -f "[$]ROOT\/[$]line" \]; then/if false; then/' "$SCRIPT_UNDER_TEST" > "${md}/Scripts/check_shellcheck.sh"
if cmp -s "$SCRIPT_UNDER_TEST" "${md}/Scripts/check_shellcheck.sh"; then
  fail "mutation E: the sed changed nothing, the proof would be vacuous"
else
  mout="$(SHELLCHECK_ROOT="$A" bash "${md}/Scripts/check_shellcheck.sh" 2>&1)"
  mrc=$?
  if [ "$mrc" -eq 0 ]; then
    ok "mutation proof E: a copy without the entry check lets a bad exclusions entry through"
  else
    fail "mutation proof E: the weakened copy stayed red (exit ${mrc})"
    indent_out "$mout"
  fi
fi
mutant_green F '/no shell scripts found/{n;s/exit 1/exit 0/;}' "$Z" \
  "a copy that passes on zero targets turns case 15 green"
# G: the file list ignored. The weakened copy scans the whole tree, so the
# listed clean script is no longer green: the broken one outside the list is judged.
md="$TMP/mutant_G"
mkdir -p "${md}/Scripts"
cp "${ROOT}/Scripts/lib_repo_files.sh" "${ROOT}/Scripts/shellcheck_exclusions.txt" "${md}/Scripts/"
sed 's/^if \[ "[$]#" -gt 0 \]; then$/if false; then/' "$SCRIPT_UNDER_TEST" > "${md}/Scripts/check_shellcheck.sh"
if cmp -s "$SCRIPT_UNDER_TEST" "${md}/Scripts/check_shellcheck.sh"; then
  fail "mutation G: the sed changed nothing, the proof would be vacuous"
else
  mout="$(SHELLCHECK_ROOT="$L" bash "${md}/Scripts/check_shellcheck.sh" Scripts/ok.sh 2>&1)"
  mrc=$?
  if [ "$mrc" -ne 0 ] && [[ "$mout" == *"Scripts/broken.sh"* ]]; then
    ok "mutation proof G: a copy that ignores the file list judges the script outside it, so case 16 is what catches that"
  else
    fail "mutation proof G: the weakened copy did not judge the script outside the list (exit ${mrc})"
    indent_out "$mout"
  fi
fi

if [ "$failed" -ne 0 ]; then
  echo "❌ check_shellcheck fixture failed"
  exit 1
fi
echo "✅ check_shellcheck fixture passed"
