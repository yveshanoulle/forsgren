#!/usr/bin/env bash
# Scripts/release_bump.sh
#
# The version bump of a release (forsgren#221, step 1 of 2), done in the
# working tree exactly as the manual bump commits do (1.9.2 and 1.9.3):
#
#   - `var version` in cmd/forsgren/main.go, the one source of the version
#   - every test and golden page under cmd/forsgren and internal/page that
#     pins the running version (Placeholder("1.9.3"), "Forsgren</a> 1.9.3",
#     the golden footers), old to new
#   - the newer-release examples in those tests: the patch after the old
#     version moves to the patch after the new one (1.9.3 to 1.9.4 for the
#     bump to 1.9.3), done first, so the examples stay newer than the version
#   - the running version in README.md and docs/*.md: "Forsgren X.Y.Z" (the
#     page footer), "forsgren X.Y.Z needs more configuration" (also across a
#     line break) and the "Built with" example. Release history in the docs
#     ("Upgrading to 1.9.2") stays.
# Not touched, as in the manual commits: SHIPPED.md (its entry is prose, written
# per release) and the npm files (their versions are dependencies).
#
# Then it checks its own work: no file under cmd/forsgren or internal/page
# still holds the old version, and no doc still names it as the running
# version; a file that does is a red naming it. It runs no tests: the caller
# runs `go test ./...` (the self-test does, on a copy).
#
# Usage: Scripts/release_bump.sh <new-version>    e.g. 1.9.4
# A new major also needs a new proof run of each agent file, which no script
# can do: the script says so, and go test names it.
# Exit: 0 bumped and checked, 1 a file still holds the old version,
#       2 usage (no argument, not X.Y.Z, not greater than the current one).
# It works on the repository the script lives in. Self-test:
# Scripts/test_release_bump.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_bump.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

cd "$(dirname "$0")/.." || exit 1

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

# The tests and the golden pages that pin the version.
while IFS= read -r file; do
  rewrite "$file" "s/$(token "$OLD_EXAMPLE")/${NEW_EXAMPLE}/g; s/$(token "$OLD")/${NEW}/g"
done < <(find cmd/forsgren internal/page -type f \( -name '*.go' -o -name '*.golden.html' \) | sort)

# The docs name the running version in three places.
for file in README.md docs/*.md; do
  rewrite "$file" "s/(Forsgren\\s+)$(token "$OLD")/\${1}${NEW}/g; s/(forsgren\\s+)$(token "$OLD")(\\s+needs more configuration)/\${1}${NEW}\${2}/g; s/(built the page, \"forsgren )$(token "$OLD")/\${1}${NEW}/g"
done

# verify_nothing_missed: the bump's own check, independent of the rewrite
# above (it lists every file of the two directories, whatever its type).
verify_nothing_missed() {
  local left=0 file
  while IFS= read -r file; do
    echo "❌ FAIL: release bump: ${file} still holds ${OLD}"
    left=1
  done < <(grep -rlE "(^|[^0-9.])${OLD//./\\.}($|[^0-9]|\\.[^0-9])" cmd/forsgren internal/page | sort)
  for file in README.md docs/*.md; do
    if tr -s '[:space:]' ' ' < "$file" | grep -qE "Forsgren ${OLD//./\\.}($|[^0-9.]|\\.[^0-9])|forsgren ${OLD//./\\.} needs more configuration"; then
      echo "❌ FAIL: release bump: ${file} still names ${OLD} as the running version"
      left=1
    fi
  done
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
if (( N_MAJOR > O_MAJOR )); then
  echo "NOTE: a new major needs a new proof run of each agent file (their Tested-with lines) before go test passes (forsgren#148)"
fi
COMPLETED=1
