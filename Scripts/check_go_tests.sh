#!/usr/bin/env bash
# Scripts/check_go_tests.sh
#
# The Go-test gate: `go test -v ./...` over the module. Red when go test
# fails, AND red when it ran no tests at all: a green over zero tests is a
# false clean (no test files, a broken package pattern, every test skipped),
# and it looks exactly like a pass.
#
# Red, too, when ./... matches a package under node_modules/: npm ships Go
# code without its own go.mod (node_modules/flatted/golang), and Go then
# counts it as one of the module's own packages, for every ./... tool, not
# only this one (forsgren#1). The one place that keeps npm's tree out is
# go.mod's `ignore node_modules` directive, which the go command applies to
# every package pattern and to `go mod tidy`; this check is its guard.
#
# The run writes the coverage profile to <module-dir>/.build/go-coverage.out
# for Scripts/check_coverage.sh, the next row, so coverage costs no second
# test run (forsgren#1, ladder step 22). The profile is removed before the
# run and again whenever this gate is red, so it only ever holds a green run
# of the current tree: a red run must never leave coverage behind to be
# judged as if it were green.
#
# Usage: Scripts/check_go_tests.sh [module-dir]   (default: the repo root)
# Fixture: Scripts/test_check_go_tests.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

MODULE_DIR="${1:-.}"
cd "$MODULE_DIR" || {
  echo "❌ FAIL: module directory not found: ${MODULE_DIR}"
  exit 1
}

npm_pkgs="$(go list -e ./... 2>/dev/null | grep -F '/node_modules/' || true)"
if [ -n "$npm_pkgs" ]; then
  while IFS= read -r pkg; do
    echo "❌ ${pkg}"
  done <<< "$npm_pkgs"
  echo "❌ FAIL: go.mod must ignore node_modules: ./... matches the package(s) above, npm's Go code, as the module's own (add: ignore node_modules)"
  exit 1
fi

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

PROFILE=".build/go-coverage.out"
rm -f "$PROFILE"
mkdir -p .build

go test -v -coverprofile="$PROFILE" ./... 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

if [ "$rc" -ne 0 ]; then
  rm -f "$PROFILE"
  echo
  grep -E '^--- FAIL: ' "$LOG" | sed 's/^/❌ /' || true
  echo "❌ FAIL: go test ./... exited ${rc}"
  exit 1
fi

# Top-level tests only: a subtest's `--- PASS` is indented.
passed="$(grep -cE '^--- PASS: ' "$LOG" || true)"
if [ "$passed" -eq 0 ]; then
  rm -f "$PROFILE"
  echo
  echo "❌ FAIL: go test ./... ran no tests — a green over zero tests measures nothing"
  exit 1
fi

echo
echo "OK: go test ./... — ${passed} tests passed"
