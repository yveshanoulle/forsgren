#!/usr/bin/env bash
# Scripts/check_deadcode.sh
#
# The Go dead-code gate: `deadcode -test ./...` over a Go module. Red on any
# function no main package and no test can reach.
#
# PORTED (forsgren#1, ladder step 23) from another estate repository, where sfl runs
# `deadcode -test ./...` in each module with a main package
# (ios-app/sfl.sh, run_go_deadcode_check) and CI runs the same, red on any
# output (`test ! -s`). `-test` makes the tests roots as well as main, so a
# helper only a test calls is not reported (another estate repository's choice: its CI runs
# it that way, and sfl matched it). Adapted:
#   - deadcode is the one pinned by go.mod's `tool` line plus go.sum (Yves's
#     ruling on forsgren#1), never `go install ...@latest` as another estate repository does:
#     `go tool -n deadcode`, run in this repository, builds the pinned version
#     once (Go caches it) and prints its path, and the gate runs that binary
#     in the module it judges, so a fixture module needs no tool line of its
#     own. A tool built by go.mod's toolchain is rebuilt when the toolchain
#     moves, which is what another estate repository's sfl_ensure_go_tool.sh had to add.
#   - the module is an argument, so Scripts/test_check_deadcode.sh can hand
#     it fixture modules.
#   - red, not n/a, on a module with no main package: another estate repository marks such a
#     module n/a because its shared/ library has its own dead-exports check;
#     forsgren has one module, with a main, and a check over no root is no
#     pass.
#   - red on a deadcode that did not run (a non-zero exit: a module that does
#     not compile, say): a check that never ran is never a clean result.
#
# The fix for a red is to delete the function, never to call it from a test
# to keep it alive.
#
# Usage: Scripts/check_deadcode.sh [module-dir]   (default: the repo root)
# Fixture: Scripts/test_check_deadcode.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"

MODULE_DIR="${1:-.}"

if ! BIN="$(go tool -n deadcode 2>&1)"; then
  printf '%s\n' "$BIN"
  echo "❌ FAIL: deadcode is not pinned in ${ROOT}/go.mod: go tool -n deadcode failed (add it: go get -tool golang.org/x/tools/cmd/deadcode@<version>)"
  exit 1
fi

cd "$MODULE_DIR" 2>/dev/null || {
  echo "❌ FAIL: module directory not found: ${MODULE_DIR}"
  exit 1
}

mains="$(go list -f '{{if eq .Name "main"}}{{.ImportPath}}{{end}}' ./... 2>/dev/null)"
if [ -z "$mains" ]; then
  echo "❌ FAIL: no main package in ${MODULE_DIR} — deadcode has no root to reach from, and a check over nothing is no pass"
  exit 1
fi

out="$("$BIN" -test ./... 2>&1)"
rc=$?

if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$out"
  echo "❌ FAIL: deadcode could not run (exit ${rc}) — a check that did not run is not a clean result"
  exit 1
fi

if [ -z "$out" ]; then
  version="$(go version -m "$BIN" 2>/dev/null | awk '$1 == "mod" { print $3; exit }')"
  echo "OK: deadcode (golang.org/x/tools ${version:-unknown}) found no unreachable function in ${MODULE_DIR} (roots: main and the tests)"
  exit 0
fi

printf '%s\n' "$out"
count="$(printf '%s\n' "$out" | grep -c 'unreachable func:')"
echo "❌ FAIL: deadcode found ${count} unreachable function(s) in ${MODULE_DIR} — delete each; never call one from a test to keep it alive"
exit 1
