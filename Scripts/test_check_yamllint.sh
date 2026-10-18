#!/usr/bin/env bash
# canon: test_check_yamllint v4
# Scripts/test_check_yamllint.sh
#
# Fixture test for Scripts/check_yamllint.sh, in the shape of
# Scripts/test_check_shellcheck.sh.
#
# Drives the checker against synthetic git trees (via YAMLLINT_ROOT), with
# this repository's real .yamllint.yml as the config, so the pins never
# depend on which YAML files this repository happens to track today.
#
# Pinned behaviours:
#   1. a clean synthetic tree (a well-formed .yml and .yaml)     -> exit 0
#   2. a tracked .yml with a real yamllint finding (a duplicate
#      key) at the root                                           -> exit 1,
#      naming that file
#   3. the same finding in a NESTED .yaml file (any directory, any
#      depth, either extension)                                   -> exit 1,
#      naming that file
#   4. a broken .yml that is on disk, NOT tracked and not ignored
#      is a target (a new file); an ignored one is
#      left alone                                                 -> exit 1 / 0
#   5. a tree with no tracked YAML at all                         -> exit 1,
#      with the reason that nothing was found, never a green over nothing
#   6. this repository's own tracked YAML passes                  -> exit 0
#   7. a file list: a broken file outside the list is not judged  -> exit 0;
#      the broken file in the list is                             -> exit 1, named
#   8. a listed path that is no file                              -> exit 1, named
# Mutation proofs (a weakened COPY of the gate must turn a red case green):
#   A. the exit status swallowed: case 2
#   B. discovery back to a fixed file: case 3 (nested .yaml)
#   C. zero targets passing: case 5
#   D. the file list ignored (the whole tree linted): case 7 turns red

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=Scripts/lib_git_sandbox.sh
source "${ROOT}/Scripts/lib_git_sandbox.sh"
SCRIPT_UNDER_TEST="${ROOT}/Scripts/check_yamllint.sh"

# An inherited GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE (a hook, a wrapper)
# would point the scratch `git init` and `git add` below at THIS repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failed=0
ok()   { echo "OK:   $*"; }
fail() { echo "❌ FAIL: $*"; failed=1; }

indent_out() { echo "      ${1//$'\n'/$'\n'      }"; }

# make_case <case-dir> — an empty git repo (no identity needed: the checker
# only ever calls `git ls-files`, which reads the index).
make_case() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
}

# write_file <case-dir> <relative-path> <content> — writes, does not stage.
write_file() {
  local dir="$1" path="$2" content="$3"
  mkdir -p "$(dirname "${dir}/${path}")"
  printf '%s' "$content" > "${dir}/${path}"
}

# add_file <case-dir> <relative-path> <content> — writes and stages a file.
add_file() {
  write_file "$@"
  git -C "$1" add "$2"
}

# run_guard <case-dir> — sets RC and OUT.
run_guard() {
  local dir="$1"
  OUT="$(YAMLLINT_ROOT="$dir" bash "$SCRIPT_UNDER_TEST" 2>&1)"
  RC=$?
}

CLEAN_YML='name: clean
items:
  - one
  - two
'

# A duplicate key: valid YAML to most parsers (the last one silently wins),
# and exactly the kind of finding yamllint exists for.
BROKEN_YML='name: first
name: second
'

# 1. Clean synthetic tree.
A="$TMP/clean"
make_case "$A"
add_file "$A" "config.yml" "$CLEAN_YML"
add_file "$A" "deep/er/other.yaml" "$CLEAN_YML"
run_guard "$A"
if [ "$RC" -eq 0 ]; then
  ok "a clean synthetic tree passes"
else
  fail "clean tree should pass, got exit $RC"
  indent_out "$OUT"
fi

# 2. A tracked root .yml with a finding.
B="$TMP/root_broken"
make_case "$B"
add_file "$B" "config.yml" "$CLEAN_YML"
add_file "$B" "broken.yml" "$BROKEN_YML"
run_guard "$B"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'broken.yml'; then
  ok "a yamllint finding in a tracked .yml fails the gate, named"
else
  fail "a tracked .yml with a duplicate key should fail the gate and be named, got exit $RC"
  indent_out "$OUT"
fi

# 3. The same finding, nested and with the .yaml extension.
C="$TMP/nested_broken"
make_case "$C"
add_file "$C" "config.yml" "$CLEAN_YML"
add_file "$C" "a/b/workflow.yaml" "$BROKEN_YML"
run_guard "$C"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'a/b/workflow.yaml'; then
  ok "a yamllint finding in a nested tracked .yaml fails the gate, named"
else
  fail "a nested tracked .yaml with a duplicate key should fail the gate and be named, got exit $RC"
  indent_out "$OUT"
fi

# 4. a NEW file is untracked while the gates run (FBP commits
#    after them), so a broken file on disk, not in the index and not ignored,
#    is a target too.
D="$TMP/untracked_broken"
make_case "$D"
add_file "$D" "config.yml" "$CLEAN_YML"
write_file "$D" "new/scratch.yml" "$BROKEN_YML"
run_guard "$D"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'new/scratch.yml'; then
  ok "an untracked, not-ignored broken .yml fails the gate, named"
else
  fail "an untracked .yml with a duplicate key should fail the gate and be named, got exit $RC"
  indent_out "$OUT"
fi

# 4b. A broken file that git ignores will never be committed: left alone.
D2="$TMP/ignored_broken"
make_case "$D2"
add_file "$D2" "config.yml" "$CLEAN_YML"
add_file "$D2" ".gitignore" "scratch/
"
write_file "$D2" "scratch/broken.yml" "$BROKEN_YML"
run_guard "$D2"
if [ "$RC" -eq 0 ]; then
  ok "an ignored broken .yml is left alone"
else
  fail "an ignored .yml should not be linted, got exit $RC"
  indent_out "$OUT"
fi

# 5. No tracked YAML at all: red, and it says why.
E="$TMP/no_yaml"
make_case "$E"
add_file "$E" "README.md" "no yaml here
"
run_guard "$E"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'no .yml or .yaml file found'; then
  ok "a tree with no tracked YAML is red, with the reason"
else
  fail "zero tracked YAML should be red and say so, got exit $RC"
  indent_out "$OUT"
fi

# 6. This repository, as it is.
OUT="$(bash "$SCRIPT_UNDER_TEST" 2>&1)"
RC=$?
if [ "$RC" -eq 0 ]; then
  ok "this repository's tracked YAML passes"
else
  fail "this repository's tracked YAML should pass, got exit $RC"
  indent_out "$OUT"
fi

# run_list <case-dir> <file>... — the checker with a file list. Sets RC and OUT.
run_list() {
  local dir="$1"
  shift
  OUT="$(YAMLLINT_ROOT="$dir" bash "$SCRIPT_UNDER_TEST" "$@" 2>&1)"
  RC=$?
}

# 7. A file list: only the listed files are judged.
L="$TMP/file_list"
make_case "$L"
add_file "$L" "ok.yml" "$CLEAN_YML"
add_file "$L" "broken.yml" "$BROKEN_YML"
run_list "$L" ok.yml
if [ "$RC" -eq 0 ]; then
  ok "a file list: a broken file outside the list is not judged"
else
  fail "the broken file is outside the list and must not be judged, got exit $RC"
  indent_out "$OUT"
fi
run_list "$L" broken.yml
if [ "$RC" -ne 0 ] && [[ "$OUT" == *"broken.yml"* ]]; then
  ok "a file list: the broken file in the list is red, named"
else
  fail "the broken file in the list should be red and named, got exit $RC"
  indent_out "$OUT"
fi

# 8. A listed path that is no file is red, named.
run_list "$L" ok.yml missing.yml
if [ "$RC" -ne 0 ] && [[ "$OUT" == *"missing.yml"* ]]; then
  ok "a file list naming a missing file is red, named"
else
  fail "a listed missing file should be red and named, got exit $RC"
  indent_out "$OUT"
fi

# --- Mutation proofs. mutant_green <label> <sed-expr> <case-dir> <ok text>:
# a weakened copy of the gate (with its lib and the real config) must turn the
# red case green. A sed that changes nothing is a failed proof.
mutant_green() {
  local label="$1" expr="$2" case_dir="$3" text="$4" md="$TMP/mutant_$1" mrc mout
  mkdir -p "${md}/Scripts"
  cp "${ROOT}/Scripts/lib_repo_files.sh" "${md}/Scripts/"
  cp "${ROOT}/.yamllint.yml" "${md}/.yamllint.yml"
  sed "$expr" "$SCRIPT_UNDER_TEST" > "${md}/Scripts/check_yamllint.sh"
  if cmp -s "$SCRIPT_UNDER_TEST" "${md}/Scripts/check_yamllint.sh"; then
    fail "mutation ${label}: the sed changed nothing, the proof would be vacuous"
    return 0
  fi
  mout="$(YAMLLINT_ROOT="$case_dir" bash "${md}/Scripts/check_yamllint.sh" 2>&1)"
  mrc=$?
  if [ "$mrc" -eq 0 ]; then
    ok "mutation proof ${label}: ${text}"
  else
    fail "mutation proof ${label}: the weakened copy stayed red (exit ${mrc}), so the case is not red for the stated reason"
    indent_out "$mout"
  fi
}

mutant_green A 's/^exit "[$]rc"/exit 0/' "$B" \
  "a copy that swallows the exit status turns the root finding green"
mutant_green B "s#repo_files \. '\\*\\.yml' '\\*\\.yaml'#repo_files . 'config.yml'#" "$C" \
  "a copy that reads a fixed file does not see the nested .yaml, so any-depth discovery is what catches it"
mutant_green C '/no \.yml or \.yaml file found/{n;s/exit 1/exit 0/;}' "$E" \
  "a copy that passes on zero targets turns case 5 green"
# D: the file list ignored. The weakened copy lints the whole tree, so the
# listed clean file is no longer green: the broken one outside the list is judged.
md="$TMP/mutant_D"
mkdir -p "${md}/Scripts"
cp "${ROOT}/Scripts/lib_repo_files.sh" "${md}/Scripts/"
cp "${ROOT}/.yamllint.yml" "${md}/.yamllint.yml"
sed 's/^if \[ "[$]#" -gt 0 \]; then$/if false; then/' "$SCRIPT_UNDER_TEST" > "${md}/Scripts/check_yamllint.sh"
if cmp -s "$SCRIPT_UNDER_TEST" "${md}/Scripts/check_yamllint.sh"; then
  fail "mutation D: the sed changed nothing, the proof would be vacuous"
else
  mout="$(YAMLLINT_ROOT="$L" bash "${md}/Scripts/check_yamllint.sh" ok.yml 2>&1)"
  mrc=$?
  if [ "$mrc" -ne 0 ] && [[ "$mout" == *"broken.yml"* ]]; then
    ok "mutation proof D: a copy that ignores the file list judges the file outside it, so case 7 is what catches that"
  else
    fail "mutation proof D: the weakened copy did not judge the file outside the list (exit ${mrc})"
    indent_out "$mout"
  fi
fi

if [ "$failed" -ne 0 ]; then
  echo "❌ check_yamllint fixture failed"
  exit 1
fi
echo "✅ check_yamllint fixture passed"
