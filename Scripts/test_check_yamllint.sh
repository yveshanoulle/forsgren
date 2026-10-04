#!/usr/bin/env bash
# Fixture test for Scripts/check_yamllint.sh — forsgren's own (no repo of the
# estate has one), in the shape of another estate repository's Scripts/test_check_shellcheck.sh.
#
# Drives the checker against synthetic git trees (via YAMLLINT_ROOT), with
# this repository's real .yamllint.yml as the config, so the pins never
# depend on which YAML files forsgren happens to track today.
#
# Pinned behaviours:
#   1. a clean synthetic tree (a well-formed .yml and .yaml)     -> exit 0
#   2. a tracked .yml with a real yamllint finding (a duplicate
#      key) at the root                                           -> exit 1,
#      naming that file
#   3. the same finding in a NESTED .yaml file (any directory, any
#      depth, either extension)                                   -> exit 1,
#      naming that file
#   4. a broken .yml that is on disk but NOT tracked is left
#      alone: targets come from the index                         -> exit 0
#   5. a tree with no tracked YAML at all                         -> exit 1,
#      with the reason that nothing was found, never a green over nothing
#   6. this repository's own tracked YAML passes                  -> exit 0

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

# 4. A broken file on disk but not in the index is not a target.
D="$TMP/untracked_broken"
make_case "$D"
add_file "$D" "config.yml" "$CLEAN_YML"
write_file "$D" "scratch.yml" "$BROKEN_YML"
run_guard "$D"
if [ "$RC" -eq 0 ]; then
  ok "an untracked broken .yml is left alone"
else
  fail "an untracked .yml should not be linted, got exit $RC"
  indent_out "$OUT"
fi

# 5. No tracked YAML at all: red, and it says why.
E="$TMP/no_yaml"
make_case "$E"
add_file "$E" "README.md" "no yaml here
"
run_guard "$E"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'no tracked .yml or .yaml file found'; then
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

if [ "$failed" -ne 0 ]; then
  echo "❌ check_yamllint fixture failed"
  exit 1
fi
echo "✅ check_yamllint fixture passed"
