#!/usr/bin/env bash
# Scripts/check_npm_lock_sync.sh
#
# The npm lockfile sync gate (forsgren#2, ladder step 1): package.json and
# package-lock.json must agree. The lockfile repeats the manifest's
# dependencies under packages[""]; when the two differ, the lockfile no longer
# describes the manifest and `npm ci` will refuse it. CI finds that out at its
# Install dependencies step; locally, sfl only ran `npm ci` when node_modules
# was missing, so the mismatch went unseen. This gate says it in the PRE phase.
#
# Compared, by name and exact version string: dependencies, devDependencies,
# optionalDependencies and peerDependencies of package.json against the same
# four of the lockfile's root entry packages[""]. Offline: two JSON files and
# jq, no registry. It does NOT judge node_modules (that is a separate step of
# forsgren#2) or exact pinning (Scripts/check_guardrail_packages.sh).
#
# Usage: Scripts/check_npm_lock_sync.sh [dir]   (default: the repo root)
# Exit: 0 in sync, 1 a difference, a missing file or no jq.
# Fixture: Scripts/test_check_npm_lock_sync.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: check_npm_lock_sync.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

DIR="${1:-.}"
cd "$DIR" || {
  echo "❌ FAIL: directory not found: ${DIR}"
  COMPLETED=1
  exit 1
}

FIX="npm install --package-lock-only"

fail_now() {
  echo "❌ FAIL: $*"
  COMPLETED=1
  exit 1
}

command -v jq >/dev/null 2>&1 || fail_now "jq not found on PATH — the lockfile cannot be compared"

for f in package.json package-lock.json; do
  [ -f "$f" ] || fail_now "${f} is missing — nothing to compare"
  jq -e . "$f" >/dev/null 2>&1 || fail_now "${f} is not valid JSON"
done

if ! jq -e '.packages[""]' package-lock.json >/dev/null 2>&1; then
  fail_now "package-lock.json has no root package entry (packages[\"\"]) — regenerate it: ${FIX}"
fi

# One message per difference, from jq. A section/name pair is looked up on
# both sides; a spec present on one side only is a missing or an extra entry.
report="$(jq -r -n --slurpfile pkg package.json --slurpfile lock package-lock.json '
  def flat(o): [ ("dependencies","devDependencies","optionalDependencies","peerDependencies") as $s
                 | (o[$s] // {}) | to_entries[] | { key: "\($s) \(.key)", sec: $s, name: .key, v: .value } ];
  def compared:
    (flat($pkg[0])) as $a | (flat($lock[0].packages[""])) as $b
    | ( $a[] | . as $x
        | ($b | map(select(.key == $x.key)) | first) as $y
        | if $y == null then "\($x.sec) \($x.name): package.json says \($x.v), package-lock.json does not list it"
          elif $y.v != $x.v then "\($x.sec) \($x.name): package.json says \($x.v), package-lock.json says \($y.v)"
          else empty end ),
      ( $b[] | . as $y
        | if ($a | map(select(.key == $y.key)) | length) == 0
          then "\($y.sec) \($y.name): package-lock.json says \($y.v), package.json does not list it"
          else empty end );
  compared
')" || fail_now "jq could not compare package.json and package-lock.json"

if [ -n "$report" ]; then
  echo "❌ FAIL: package-lock.json does not match package.json:"
  printf '       %s\n' "${report//$'\n'/$'\n'       }"
  echo "       fix: ${FIX}"
  COMPLETED=1
  exit 1
fi

COMPLETED=1
echo "OK: package-lock.json matches package.json (dependencies, devDependencies, optionalDependencies, peerDependencies)"
