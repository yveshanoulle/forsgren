#!/usr/bin/env bash
# Scripts/check_govulncheck.sh
#
# The Go vulnerability gate: govulncheck over a Go module. Red when the code
# reaches a symbol the Go vulnerability database lists as vulnerable.
#
# PORTED (forsgren#1, ladder step 23) from another estate repository, where sfl runs
# `govulncheck ./...` in each Go module (ios-app/sfl.sh, run_go_vuln_check)
# and CI runs the same, both behind the same probe: when vuln.go.dev does not
# answer `curl -sf --max-time 5` the check is skipped, not failed. Adapted:
#   - govulncheck is the one pinned by go.mod's `tool` line plus go.sum
#     (Yves's ruling on forsgren#1), never `go install ...@latest` as
#     another estate repository does: `go tool -n govulncheck`, run in this repository, builds
#     the pinned version once and prints its path on stdout (its download
#     lines go to stderr, forsgren#210), and the gate runs that
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
#     ::warning:: annotation, as another estate repository's CI does. It never prints the OK
#     line: a skip is not a pass, and the report says so. When the probe
#     answers, govulncheck runs, and anything it cannot do from there is red.
#   - red on a govulncheck that could not run (an exit other than 0 or 3:
#     govulncheck exits 3 for findings), and on a module with no Go package.
#
#   - FORSGREN_VULN_DB_REQUIRED=1 turns that skip into a red (forsgren#87): the
#     scheduled run (.github/workflows/vulncheck.yml) exists to give a verdict
#     every day, so a database it cannot reach fails the run; a found
#     vulnerability stays a finding (its own ❌ line naming the IDs), never a
#     network failure. Unset, the gate skips as above.
#
# Usage: Scripts/check_govulncheck.sh [module-dir]   (default: the repo root)
#        FORSGREN_VULN_DB=<url> overrides the database (https:// or file://).
#        FORSGREN_VULN_DB_REQUIRED=1: an unreachable database is red, not a skip.
# Fixture: Scripts/test_check_govulncheck.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"

MODULE_DIR="${1:-.}"
DB="${FORSGREN_VULN_DB:-https://vuln.go.dev}"

# The tool path comes from stdout alone (Scripts/lib_go_tool.sh, forsgren#216):
# on a fresh runner go prints its "go: downloading ..." lines on stderr
# (forsgren#210), which stay on stderr, in the log, and never reach BIN. `go
# tool -n` builds the tool before it prints the path; the executable-file check
# makes a path that is not a built binary red here, not an exit 127 further
# down.
# shellcheck source=Scripts/lib_go_tool.sh
source Scripts/lib_go_tool.sh
go_tool_path govulncheck
tool_rc=$?
BIN="$GO_TOOL_BIN"
if [ "$tool_rc" -eq 1 ]; then
  echo "❌ FAIL: govulncheck is not pinned in ${ROOT}/go.mod: go tool -n govulncheck failed (add it: go get -tool golang.org/x/vuln/cmd/govulncheck@<version>)"
  exit 1
fi
if [ "$tool_rc" -ne 0 ]; then
  echo "❌ FAIL: go tool -n govulncheck printed ${BIN}, which is not an executable: the pinned govulncheck was not built"
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
  if [ "${FORSGREN_VULN_DB_REQUIRED:-}" = "1" ]; then
    echo "❌ FAIL: govulncheck did not run — the vulnerability database ${DB} is unreachable (curl ${DB}/index/db.json failed) and FORSGREN_VULN_DB_REQUIRED=1 asks for a verdict: no verdict is no pass"
    exit 1
  fi
  echo "⚠️ SKIP: govulncheck did not run — the vulnerability database ${DB} is unreachable (curl ${DB}/index/db.json failed): offline, so there is no verdict for ${MODULE_DIR}; this is not a pass"
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::warning::govulncheck skipped: ${DB} unreachable"
  fi
  exit 0
fi

out="$(go_tool_run -db "$DB" ./...)"
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
