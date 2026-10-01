#!/usr/bin/env bash
# Scripts/test_check_go_tests.sh
#
# Self-test for Scripts/check_go_tests.sh, run before the gate it validates.
# Each case is a throwaway Go module under one temp root:
#   1. a passing test           -> green, and the count is reported
#   2. a failing test           -> red, naming the failing test
#   3. a package with no tests  -> red: zero tests found is not a pass
#   4. a module with no package -> red
#   5. every test skipped       -> red: nothing was measured

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_go_tests.sh"

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: Go-test gate self-test aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

# new_module <name> — a module with one package `m` and no test yet.
new_module() {
  MOD="${TMP}/$1"
  mkdir -p "$MOD"
  printf 'module example.com/m\n\ngo 1.26.1\n' > "${MOD}/go.mod"
  printf 'package m\n\n// Two returns 2.\nfunc Two() int { return 2 }\n' > "${MOD}/m.go"
}

# add_test <body> — adds m_test.go with one test whose body is <body>.
add_test() {
  printf 'package m\n\nimport "testing"\n\nfunc TestTwo(t *testing.T) {\n\t%s\n}\n' "$1" > "${MOD}/m_test.go"
}

# run_gate — runs the gate against $MOD; sets RC and OUT.
run_gate() {
  set +e
  OUT="$("$GATE" "$MOD" 2>&1)"
  RC=$?
  set -e
}

# want_red <case> <reason> — the last run failed and said <reason>.
want_red() {
  if [[ "$RC" -eq 0 ]]; then
    fail "$1: the gate exited 0. Output: ${OUT}"
  elif ! grep -qF -- "$2" <<< "$OUT"; then
    fail "$1: the gate failed without saying '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

new_module "passing"
add_test 'if Two() != 2 { t.Fatal("want 2") }'
run_gate
if [[ "$RC" -ne 0 ]]; then
  fail "a passing test: the gate exited ${RC}. Output: ${OUT}"
elif ! grep -qF "1 tests passed" <<< "$OUT"; then
  fail "a passing test: the gate did not report '1 tests passed'. Output: ${OUT}"
else
  echo "  ok: a passing test is green and counted"
fi

new_module "failing"
add_test 't.Fatal("deliberately red")'
run_gate
want_red "a failing test is red" "go test ./... exited"
want_red "and the failing test is named" "--- FAIL: TestTwo"

new_module "no-tests"
run_gate
want_red "a package with no tests is red" "ran no tests"

new_module "no-package"
rm "${MOD}/m.go"
run_gate
if [[ "$RC" -eq 0 ]]; then
  fail "a module with no package: the gate exited 0. Output: ${OUT}"
else
  echo "  ok: a module with no package is red"
fi

new_module "all-skipped"
add_test 't.Skip("nothing measured")'
run_gate
want_red "a run where every test is skipped is red" "ran no tests"

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: the Go-test gate does not tell green from red (see the FAIL lines above)"
  exit 1
fi

echo "OK: Go-test gate is red on a failing test, on zero tests found and on a skipped-only run, and green on a passing one"
