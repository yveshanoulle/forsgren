#!/usr/bin/env bash
# Scripts/check_govulncheck.sh
#
# The Go vulnerability gate: govulncheck over a Go module. Red when the code
# reaches a symbol the Go vulnerability database lists as vulnerable.
#
# PORTED (forsgren#1, ladder step 23) from MenoPower, where sfl runs
# `govulncheck ./...` in each Go module (ios-app/sfl.sh, run_go_vuln_check)
# and CI runs the same, both behind the same probe: when vuln.go.dev does not
# answer `curl -sf --max-time 5` the check is skipped, not failed. Adapted:
#   - govulncheck is the one pinned by go.mod's `tool` line plus go.sum
#     (Yves's ruling on forsgren#1), never `go install ...@latest` as
#     MenoPower does: `go tool -n govulncheck`, run in this repository, builds
#     the pinned version once and prints its path, and the gate runs that
#     binary in the module it scans.
#   - the database is FORSGREN_VULN_DB (default https://vuln.go.dev), passed
#     to govulncheck as -db and probed at <db>/index/db.json, the file
#     govulncheck itself reads first. So Scripts/test_check_govulncheck.sh
#     can run every case offline against a file:// database it writes.
#   - THE OFFLINE RULE, and how offline is detected: one probe,
#       curl -sf --max-time 5 <db>/index/db.json
#     Any failure of it (no route, refused, DNS, a timeout, an HTTP error) is
#     "offline": the gate prints a ⚠️ SKIP line naming the database and exits
#     0, so sfl and CI go on, and in GitHub Actions it also prints a
#     ::warning:: annotation, as MenoPower's CI does. It never prints the OK
#     line: a skip is not a pass, and the report says so. When the probe
#     answers, govulncheck runs, and anything it cannot do from there is red.
#   - red on a govulncheck that could not run (an exit other than 0 or 3:
#     govulncheck exits 3 for findings), and on a module with no Go package.
#
# Usage: Scripts/check_govulncheck.sh [module-dir]   (default: the repo root)
#        FORSGREN_VULN_DB=<url> overrides the database (https:// or file://).
# Fixture: Scripts/test_check_govulncheck.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"

MODULE_DIR="${1:-.}"
DB="${FORSGREN_VULN_DB:-https://vuln.go.dev}"

if ! BIN="$(go tool -n govulncheck 2>&1)"; then
  printf '%s\n' "$BIN"
  echo "❌ FAIL: govulncheck is not pinned in ${ROOT}/go.mod: go tool -n govulncheck failed (add it: go get -tool golang.org/x/vuln/cmd/govulncheck@<version>)"
  exit 1
fi

cd "$MODULE_DIR" 2>/dev/null || {
  echo "❌ FAIL: module directory not found: ${MODULE_DIR}"
  exit 1
}

if [ -z "$(go list ./... 2>/dev/null)" ]; then
  echo "❌ FAIL: no Go package to scan in ${MODULE_DIR} — a scan over nothing is no pass"
  exit 1
fi

if ! curl -sf --max-time 5 "${DB}/index/db.json" -o /dev/null; then
  echo "⚠️ SKIP: govulncheck did not run — the vulnerability database ${DB} is unreachable (curl ${DB}/index/db.json failed): offline, so there is no verdict for ${MODULE_DIR}; this is not a pass"
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::warning::govulncheck skipped: ${DB} unreachable"
  fi
  exit 0
fi

out="$("$BIN" -db "$DB" ./... 2>&1)"
rc=$?

if [ "$rc" -eq 0 ]; then
  version="$(go version -m "$BIN" 2>/dev/null | awk '$1 == "mod" { print $3; exit }')"
  echo "OK: govulncheck (golang.org/x/vuln ${version:-unknown}) found no vulnerability the code in ${MODULE_DIR} reaches (database ${DB})"
  exit 0
fi

printf '%s\n' "$out"
if [ "$rc" -ne 3 ]; then
  echo "❌ FAIL: govulncheck could not run (exit ${rc}) — a scan that did not run is not a clean result"
  exit 1
fi

ids="$(printf '%s\n' "$out" | sed -nE 's/^Vulnerability #[0-9]+: ([A-Z]+-[0-9]+-[0-9]+)$/\1/p' | paste -sd ' ' -)"
echo "❌ FAIL: govulncheck found vulnerabilities the code in ${MODULE_DIR} reaches: ${ids:-see above} — upgrade the module (or Go) to the fixed version"
exit 1
