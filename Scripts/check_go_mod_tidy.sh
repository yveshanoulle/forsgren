#!/usr/bin/env bash
# Scripts/check_go_mod_tidy.sh
#
# The go mod tidy gate: red when go.mod or go.sum is not what `go mod tidy`
# would write: a require missing or unneeded, a go.sum line missing or
# stale. CHECK-ONLY: it never rewrites either file.
#
# PORTED (forsgren#1, ladder step 23) from MenoPower, where CI and the
# Makefiles run `go mod tidy` and then fail on
# `git status --porcelain go.mod go.sum`. Adapted:
#   - `go mod tidy -diff` (Go 1.23+) instead: it prints the change tidy would
#     make as a unified diff and exits non-zero, writing nothing. MenoPower's
#     form rewrites the files first, so in a local run the fix would ride
#     into the commit unseen, and it reads git, so it cannot judge a fixture
#     module outside a repository.
#   - the module is an argument, so Scripts/test_check_go_mod_tidy.sh can
#     hand it fixture modules.
#   - red, as a tool error, when tidy could not run at all (a go.mod it
#     cannot parse, a module it cannot fetch): a non-zero exit with no diff
#     is never read as "tidy".
#
# The fix for a red is `go mod tidy` in the module, committed with the change
# that needed it.
#
# Usage: Scripts/check_go_mod_tidy.sh [module-dir]   (default: the repo root)
# Fixture: Scripts/test_check_go_mod_tidy.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

MODULE_DIR="${1:-.}"

cd "$MODULE_DIR" 2>/dev/null || {
  echo "❌ FAIL: module directory not found: ${MODULE_DIR}"
  exit 1
}

if [ ! -f go.mod ]; then
  echo "❌ FAIL: no go.mod in ${MODULE_DIR} — there is no module to check"
  exit 1
fi

out="$(go mod tidy -diff 2>&1)"
rc=$?

if [ "$rc" -eq 0 ]; then
  echo "OK: go.mod and go.sum in ${MODULE_DIR} are tidy (go mod tidy -diff is empty)"
  exit 0
fi

printf '%s\n' "$out"
if ! grep -qE '^diff current/go\.(mod|sum) tidy/go\.(mod|sum)$' <<<"$out"; then
  echo "❌ FAIL: go mod tidy could not run (exit ${rc}) — a check that did not run is not a clean result"
  exit 1
fi

echo "❌ FAIL: go.mod and go.sum are not tidy in ${MODULE_DIR} — the diff above is what go mod tidy would change; run it there and commit the result"
exit 1
