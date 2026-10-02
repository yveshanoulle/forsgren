#!/usr/bin/env bash
# Scripts/check_test_dupl.sh
#
# Gate: red when a Go module's TEST code has duplication.
#
# Runs the SAME tool and rule as the production duplication check
# (golangci-lint `dupl`, threshold 80, in .golangci.yml), but targets
# _test.go files instead of excluding them: the inverse `path-except` of the
# production config's exclusion. .golangci.yml leaves test dupl to this gate,
# so test code is judged once.
#
# PORTED (forsgren#1, ladder step 20) from
# MenoPower/Scripts/common/check_test_dupl.sh. Adapted:
#   - golangci-lint is the one pinned by go.mod's `tool` line, found with
#     `go tool -n golangci-lint` in this repository (see
#     Scripts/check_go_lint.sh), never Homebrew's.
#   - forsgren's FAIL lines, and an OK line on green.
#   - red on a module with no _test.go file: a scan over no test code is no
#     pass (MenoPower reports that as clean).
#
# Exit codes (MenoPower's):
#   0 — no test-code duplication
#   1 — duplication found (findings printed), or no test file to check
#   2 — tooling error (no pinned golangci-lint, bad module dir, golangci
#       failure)
#
# Usage: Scripts/check_test_dupl.sh [module-dir] [threshold]
#        (default: the repo root, 80)
# Fixture: Scripts/test_check_test_dupl.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

MODULE_DIR="${1:-.}"
THRESHOLD="${2:-80}"

if ! BIN="$(go tool -n golangci-lint 2>&1)"; then
  printf '%s\n' "$BIN" >&2
  echo "❌ FAIL: golangci-lint is not pinned in go.mod: go tool -n golangci-lint failed" >&2
  exit 2
fi

cd "$MODULE_DIR" 2>/dev/null || {
  echo "❌ FAIL: module directory not found: ${MODULE_DIR}" >&2
  exit 2
}

tests="$(go list -f '{{len .TestGoFiles}} {{len .XTestGoFiles}}' ./... 2>/dev/null \
  | awk '{ n += $1 + $2 } END { print n + 0 }')"
if [ "$tests" -eq 0 ]; then
  echo "❌ FAIL: no _test.go file to check in ${MODULE_DIR} — a scan over no test code is no pass"
  exit 1
fi

# The config file MUST end in .yml — golangci-lint (viper) infers the format
# from the extension. macOS `mktemp -t ...yml` does NOT preserve the suffix,
# so mktemp a dir and put a real .yml inside it.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
CONFIG="$TMP_DIR/test_dupl.golangci.yml"
cat >"$CONFIG" <<YAML
version: "2"
run:
  # Report paths relative to the module (working dir), not this temp config.
  relative-path-mode: wd
issues:
  max-issues-per-linter: 0
  max-same-issues: 0
linters:
  default: none
  enable:
    - dupl
  settings:
    dupl:
      threshold: ${THRESHOLD}
  exclusions:
    rules:
      # Inverse of the production config: keep ONLY _test.go dupl findings.
      - path-except: _test\.go
        linters:
          - dupl
YAML

status=0
out="$("$BIN" run -c "$CONFIG" ./... 2>&1)" || status=$?

# golangci-lint exits 0 (clean) or 1 (issues found). Any other code is a real
# error — never mistake a non-running linter for a clean result.
if [ "$status" -ne 0 ] && [ "$status" -ne 1 ]; then
  echo "❌ FAIL: golangci-lint error (exit $status):" >&2
  printf '%s\n' "$out" >&2
  exit 2
fi

count="$(printf '%s\n' "$out" | grep -c '(dupl)' || true)"
if [ "$count" -eq 0 ]; then
  echo "OK: no test-code duplication in ${MODULE_DIR} (${tests} test files, threshold ${THRESHOLD} tokens)"
  exit 0
fi

printf '%s\n' "$out" | grep '(dupl)'
echo "❌ FAIL: test-code duplication findings: $count (threshold ${THRESHOLD} tokens)"
exit 1
