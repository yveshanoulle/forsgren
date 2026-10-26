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
#   - --allow-parallel-runners (forsgren#437): golangci-lint takes a
#     machine-wide file lock by default, so two gates in two checkouts at once
#     refused each other; the flag lets them run side by side. A lock refusal
#     that still comes is a tooling error naming the lock, never a verdict.
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

# The tool path comes from stdout alone (Scripts/lib_go_tool.sh, forsgren#216):
# on a fresh runner go prints its "go: downloading ..." lines on stderr
# (forsgren#210), which stay on stderr, in the log, and never reach BIN. `go
# tool -n` builds the tool before it prints the path; the executable-file check
# makes a path that is not a built binary red here, not an exit 127 further
# down.
# shellcheck source=Scripts/lib_go_tool.sh
source Scripts/lib_go_tool.sh
go_tool_path golangci-lint
tool_rc=$?
BIN="$GO_TOOL_BIN"
if [ "$tool_rc" -eq 1 ]; then
  echo "❌ FAIL: golangci-lint is not pinned in ${ROOT}/go.mod: go tool -n golangci-lint failed (add it: go get -tool github.com/golangci/golangci-lint/v2/cmd/golangci-lint@<version>)"
  exit 1
fi
if [ "$tool_rc" -ne 0 ]; then
  echo "❌ FAIL: go tool -n golangci-lint printed ${BIN}, which is not an executable: the pinned golangci-lint was not built"
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

out="$(go_tool_run run --allow-parallel-runners -c "$CONFIG" ./...)"
rc=$?

if [ "$rc" -eq 0 ]; then
  echo "OK: golangci-lint ($("$BIN" version --short 2>/dev/null)) found no issue in ${MODULE_DIR}"
  exit 0
fi

printf '%s\n' "$out"
# golangci-lint's machine-wide lock (forsgren#437): another run holds it, so
# this one never looked at the code. --allow-parallel-runners above keeps that
# from happening; a refusal that still comes is named, never counted as lint.
if grep -qF -- "parallel golangci-lint is running" <<< "$out"; then
  echo "❌ FAIL: another golangci-lint run holds golangci-lint's machine-wide lock (exit ${rc}):" \
    "a tooling error, not a verdict on the code; run the gate again when that run has ended"
  exit 1
fi
if [ "$rc" -ne 1 ]; then
  echo "❌ FAIL: golangci-lint could not run (exit ${rc}) — a linter that did not run is not a clean result"
  exit 1
fi

# golangci-lint's own total ("11 issues:"): counting `(linter)` line ends
# would also count a quoted source line that happens to end in parentheses.
count="$(printf '%s\n' "$out" | sed -nE 's/^([0-9]+) issues?:$/\1/p' | tail -1)"
echo "❌ FAIL: golangci-lint found ${count:-an unknown number of} issue(s) in ${MODULE_DIR} — fix each in the code; an exclusion or //nolint needs Yves's approved issue"
exit 1
