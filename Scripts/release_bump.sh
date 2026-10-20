#!/usr/bin/env bash
# Scripts/release_bump.sh
#
# The version bump of a release (forsgren#221, step 1 of 2), done in the
# working tree exactly as the manual bump commits do (1.9.2 and 1.9.3):
#
#   - `var version` in cmd/forsgren/main.go, the one source of the version
#   - nothing in the tests or the golden pages: they run as a fixed test
#     version (forsgren#237), so a release does not touch them
#   - nothing in the docs: they name no running version (forsgren#237)
# The files it may change are listed once, in Scripts/release_bump_scope.txt,
# which Scripts/release_bump_diff.sh (forsgren#230) holds a bump commit to.
# Not touched, as in the manual commits: SHIPPED.md (its entry is prose, written
# per release) and the npm files (their versions are dependencies).
#
# Then it checks its own work: no file under cmd/forsgren or internal/page
# (tests and golden pages included) still holds the old version; a file that
# does is a red naming it. It runs no tests: the caller runs `go test ./...`
# (the self-test does, on a copy).
#
# Usage: Scripts/release_bump.sh <new-version>    e.g. 1.9.4
# A new major also needs a new proof run of each agent file; the release plan
# (Scripts/release_plan.sh) refuses a major until they exist (forsgren#237).
# Exit: 0 bumped and checked, 1 a file still holds the old version,
#       2 usage (no argument, not X.Y.Z, not greater than the current one).
# It works on the repository the script lives in. Self-test:
# Scripts/test_release_bump.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_bump.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

cd "$(dirname "$0")/.." || exit 1
# shellcheck source=Scripts/lib_release_bump_scope.sh
source Scripts/lib_release_bump_scope.sh

usage() {
  echo "usage: Scripts/release_bump.sh <new-version>   (X.Y.Z, greater than the current one)" >&2
  COMPLETED=1
  exit 2
}

refuse() {
  echo "❌ FAIL: release bump: $*" >&2
  COMPLETED=1
  exit 2
}

[ "$#" -eq 1 ] || usage
NEW="$1"
SEMVER='^([0-9]+)\.([0-9]+)\.([0-9]+)$'
[[ "$NEW" =~ $SEMVER ]] || refuse "'${NEW}' is not X.Y.Z"
N_MAJOR="${BASH_REMATCH[1]}"
N_MINOR="${BASH_REMATCH[2]}"
N_PATCH="${BASH_REMATCH[3]}"

MAIN="cmd/forsgren/main.go"
OLD="$(sed -n 's/^var version = "\([0-9.]*\)"$/\1/p' "$MAIN")"
[[ "$OLD" =~ $SEMVER ]] || refuse "${MAIN} has no var version = \"X.Y.Z\""
O_MAJOR="${BASH_REMATCH[1]}"
O_MINOR="${BASH_REMATCH[2]}"
O_PATCH="${BASH_REMATCH[3]}"

if (( N_MAJOR < O_MAJOR || (N_MAJOR == O_MAJOR && (N_MINOR < O_MINOR || (N_MINOR == O_MINOR && N_PATCH <= O_PATCH))) )); then
  refuse "${NEW} is not greater than the current ${OLD}"
fi

OLD_EXAMPLE="${O_MAJOR}.${O_MINOR}.$((O_PATCH + 1))"
NEW_EXAMPLE="${N_MAJOR}.${N_MINOR}.$((N_PATCH + 1))"

# The version as a whole token: not part of 11.9.3, 1.9.30 or 1.9.3.1.
token() { printf '(?<![0-9.])%s(?![0-9]|\\.[0-9])' "${1//./\\.}"; }

CHANGED=0
rewrite() {
  # rewrite <file> <perl substitutions...>: in place, counts the file when it changed
  local file="$1" before
  shift
  before="$(cksum < "$file")"
  perl -0777 -pi -e "$*" "$file" || refuse "perl failed on ${file}"
  if [ "$before" != "$(cksum < "$file")" ]; then
    CHANGED=$((CHANGED + 1))
    echo "  changed: ${file}"
  fi
}

# The source that holds var version.
while IFS= read -r file; do
  rewrite "$file" "s/$(token "$OLD_EXAMPLE")/${NEW_EXAMPLE}/g; s/$(token "$OLD")/${NEW}/g"
done < <(bump_scope_list code)

# verify_nothing_missed: the bump's own check, independent of the rewrite
# above (it lists every file of the two directories, whatever its type).
verify_nothing_missed() {
  local left=0 file
  while IFS= read -r file; do
    echo "❌ FAIL: release bump: ${file} still holds ${OLD}"
    left=1
  done < <(grep -rlE "(^|[^0-9.])${OLD//./\\.}($|[^0-9]|\\.[^0-9])" cmd/forsgren internal/page | sort)
  grep -qF "var version = \"${NEW}\"" "$MAIN" || {
    echo "❌ FAIL: release bump: ${MAIN} does not say version ${NEW}"
    left=1
  }
  return "$left"
}
verify_nothing_missed
VERIFIED=$?
if [ "$VERIFIED" -ne 0 ]; then
  COMPLETED=1
  exit 1
fi

echo "OK: bumped ${OLD} to ${NEW} (${CHANGED} files changed, newer-release examples ${OLD_EXAMPLE} to ${NEW_EXAMPLE})"
COMPLETED=1
