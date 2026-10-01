#!/usr/bin/env bash
# Scripts/check_go_tests.sh
#
# The Go-test gate: `go test -v ./...` over the module. Red when go test
# fails, AND red when it ran no tests at all: a green over zero tests is a
# false clean (no test files, a broken package pattern, every test skipped),
# and it looks exactly like a pass.
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

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

go test -v ./... 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

if [ "$rc" -ne 0 ]; then
  echo
  grep -E '^--- FAIL: ' "$LOG" | sed 's/^/❌ /' || true
  echo "❌ FAIL: go test ./... exited ${rc}"
  exit 1
fi

# Top-level tests only: a subtest's `--- PASS` is indented.
passed="$(grep -cE '^--- PASS: ' "$LOG" || true)"
if [ "$passed" -eq 0 ]; then
  echo
  echo "❌ FAIL: go test ./... ran no tests — a green over zero tests measures nothing"
  exit 1
fi

echo
echo "OK: go test ./... — ${passed} tests passed"
