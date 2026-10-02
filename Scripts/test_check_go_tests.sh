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
#   6. Go code under node_modules/ (npm ships some, e.g. flatted/golang,
#      without its own go.mod), go.mod not ignoring it
#                               -> red, naming the package: Go counts it as
#                                  one of the module's own packages
#   7. the same tree with this repository's own go.mod `ignore` lines
#                               -> green, and no node_modules package in the
#                                  output: go.mod is the one place that keeps
#                                  npm's tree out of every ./... tool

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_go_tests.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "Go-test gate self-test"

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
  capture "$GATE" "$MOD"
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

# add_node_modules_go — Go code under node_modules/ without its own go.mod,
# as npm's flatted ships it in node_modules/flatted/golang/pkg/flatted.
add_node_modules_go() {
  mkdir -p "${MOD}/node_modules/flatted/golang/pkg/flatted"
  printf 'package flatted\n\n// F is npm-shipped Go.\nfunc F() int { return 1 }\n' \
    > "${MOD}/node_modules/flatted/golang/pkg/flatted/flatted.go"
}

new_module "node-modules-not-ignored"
add_test 'if Two() != 2 { t.Fatal("want 2") }'
add_node_modules_go
run_gate
want_red "Go code under node_modules/ that go.mod does not ignore is red" \
  "example.com/m/node_modules/flatted/golang/pkg/flatted"
want_red "and the reason names the go.mod ignore directive" \
  "go.mod must ignore node_modules"

new_module "node-modules-ignored"
add_test 'if Two() != 2 { t.Fatal("want 2") }'
add_node_modules_go
grep -E '^ignore[[:space:]]' go.mod >> "${MOD}/go.mod" || true
run_gate
if [[ "$RC" -ne 0 ]]; then
  fail "this repository's go.mod ignore lines: the gate exited ${RC}. Output: ${OUT}"
elif grep -qF "node_modules" <<< "$OUT"; then
  fail "this repository's go.mod ignore lines: the gate's output still names node_modules. Output: ${OUT}"
else
  echo "  ok: this repository's go.mod keeps node_modules out of ./..."
fi

selftest_end "the Go-test gate does not tell green from red" \
  "Go-test gate is red on a failing test, on zero tests found, on a skipped-only run and on Go code under node_modules/, green on a passing one, and this repository's go.mod keeps node_modules out of ./..."
