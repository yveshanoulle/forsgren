#!/usr/bin/env bash
# Scripts/check_go_lint.sh
#
# The Go lint gate: golangci-lint over a Go module, under .golangci.yml.
#
# PORTED (forsgren#1, ladder step 20) from another estate repository, where sfl runs
# `golangci-lint run ./...` in each module (ios-app/sfl.sh,
# run_go_static_check) and CI does the same. Adapted:
#   - golangci-lint is the one pinned by go.mod's `tool` line plus go.sum
#     (Yves's ruling on forsgren#1, decision 2), never Homebrew's: another estate repository
#     `brew install`s it, so its version is whatever the formula published
#     that day. `go tool -n golangci-lint`, run in this repository, builds the
#     pinned version once (Go caches it) and prints its path, and the gate
#     runs that binary in the module it lints, so a fixture module needs no
#     tool line of its own.
#   - the module and the config are arguments, so
#     Scripts/test_check_go_lint.sh can hand it fixture modules and mutated
#     configs.
#   - red on a module with no Go package (a lint over nothing is no pass),
#     and on a golangci-lint that did not run (exit other than 0 or 1, as
#     source-repo/Scripts/common/check_test_dupl.sh guards it): a linter that
#     never ran is never mistaken for a clean result.
#
# Usage: Scripts/check_go_lint.sh [module-dir] [config]
#        (default: the repo root, and the repo's .golangci.yml)
# Fixture: Scripts/test_check_go_lint.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"

MODULE_DIR="${1:-.}"
CONFIG="${2:-.golangci.yml}"

if [ ! -f "$CONFIG" ]; then
  echo "❌ FAIL: config not found: ${CONFIG}"
  exit 1
fi
CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"

if ! BIN="$(go tool -n golangci-lint 2>&1)"; then
  printf '%s\n' "$BIN"
  echo "❌ FAIL: golangci-lint is not pinned in ${ROOT}/go.mod: go tool -n golangci-lint failed (add it: go get -tool github.com/golangci/golangci-lint/v2/cmd/golangci-lint@<version>)"
  exit 1
fi

cd "$MODULE_DIR" 2>/dev/null || {
  echo "❌ FAIL: module directory not found: ${MODULE_DIR}"
  exit 1
}

if [ -z "$(go list ./... 2>/dev/null)" ]; then
  echo "❌ FAIL: no Go package to lint in ${MODULE_DIR} — a lint over nothing is no pass"
  exit 1
fi

out="$("$BIN" run -c "$CONFIG" ./... 2>&1)"
rc=$?

if [ "$rc" -eq 0 ]; then
  echo "OK: golangci-lint ($("$BIN" version --short 2>/dev/null)) found no issue in ${MODULE_DIR}"
  exit 0
fi

printf '%s\n' "$out"
if [ "$rc" -ne 1 ]; then
  echo "❌ FAIL: golangci-lint could not run (exit ${rc}) — a linter that did not run is not a clean result"
  exit 1
fi

# golangci-lint's own total ("11 issues:"): counting `(linter)` line ends
# would also count a quoted source line that happens to end in parentheses.
count="$(printf '%s\n' "$out" | sed -nE 's/^([0-9]+) issues?:$/\1/p' | tail -1)"
echo "❌ FAIL: golangci-lint found ${count:-an unknown number of} issue(s) in ${MODULE_DIR} — fix each in the code; an exclusion or //nolint needs Yves's approved issue"
exit 1
