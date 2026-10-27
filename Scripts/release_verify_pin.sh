#!/usr/bin/env bash
# Scripts/release_verify_pin.sh
#
# Reads a pin pull request before the Release workflow merges it (forsgren#221,
# step 5). Usage: Scripts/release_verify_pin.sh <version> <sha>, with the
# pull request's files on stdin as GitHub lists them (GET
# /repos/{owner}/{repo}/pulls/{number}/files: a JSON array of {filename, patch}).
#
# The rule is that of `forsgren check-update` for the changed files
# (internal/update, Decide, which also judges the author, the config and the
# level, none of which a pull request opened by this workflow has to meet): the
# changed files are exactly the two caller workflows,
# .github/workflows/forsgren.yml and .github/workflows/forsgren-update.yml;
# each has one removed and one added line and nothing else (besides the header
# that names a release becoming the one that names none, forsgren#506), the removed line a
# pin of the workflow the caller calls (metrics.yml, auto_update.yml) of this
# repository (GITHUB_REPOSITORY) and the added line the same pin at <sha> with
# the comment v<version>. Anything else is a red naming it, and the caller
# does not merge.
# Exit 0 OK, 1 red (every finding a line), 2 usage.
# Self-test: Scripts/test_release_verify_pin.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_verify_pin.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

usage() {
  echo "usage: GITHUB_REPOSITORY=owner/forsgren Scripts/release_verify_pin.sh <version> <sha>   (the pull request's files as JSON on stdin)" >&2
  COMPLETED=1
  exit 2
}

[ "$#" -eq 2 ] || usage
VERSION="$1"
SHA="$2"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || usage
REPO="${GITHUB_REPOSITORY:-}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
REPO_RE="${REPO//./\\.}"

FILES="$(cat)"
NAMES="$(printf '%s' "$FILES" | jq -r '.[].filename')" || usage

CALLERS=".github/workflows/forsgren.yml .github/workflows/forsgren-update.yml"
workflow_of() {
  case "$1" in
    .github/workflows/forsgren.yml) echo metrics.yml ;;
    .github/workflows/forsgren-update.yml) echo auto_update.yml ;;
  esac
}

# The header that names a release (forsgren#506) may change besides the pin:
# a removed line that names the release (or, wrapped, starts with its version)
# and an added line with the wording that names none, nothing else.
HEADER_OLD_RE='^-# (.*pinned by the commit of release( v[0-9]+\.[0-9]+\.[0-9]+.*)?|v[0-9]+\.[0-9]+\.[0-9]+, the same commit as forsgren\.yml: Dependabot moves both lines together\.)$'
HEADER_NEW_RE='^\+# (.*pinned by a release commit,( named on the uses: line)?|named on the uses: line, the same commit as forsgren\.yml: Dependabot moves both lines together\.)$'

FINDINGS=""
find_out() { FINDINGS="${FINDINGS}❌ FAIL: release verify pin: $1
"; }

while IFS= read -r name; do
  [ -n "$name" ] || continue
  known=0
  for caller in $CALLERS; do
    if [ "$name" = "$caller" ]; then known=1; fi
  done
  if [ "$known" -eq 0 ]; then
    find_out "the pull request changes ${name}, which is no forsgren caller workflow"
  fi
done <<< "$NAMES"

for caller in $CALLERS; do
  if ! grep -qxF "$caller" <<< "$NAMES"; then
    find_out "the pull request does not change ${caller}"
    continue
  fi
  wf="$(workflow_of "$caller")"
  patch="$(printf '%s' "$FILES" | jq -r --arg f "$caller" '.[] | select(.filename == $f) | .patch // ""')"
  removed=()
  added=()
  header_removed=0
  header_added=0
  while IFS= read -r line; do
    case "$line" in
      -*)
        if [[ "$line" =~ $HEADER_OLD_RE ]]; then header_removed=$((header_removed + 1)); else removed+=("$line"); fi
        ;;
      +*)
        if [[ "$line" =~ $HEADER_NEW_RE ]]; then header_added=$((header_added + 1)); else added+=("$line"); fi
        ;;
    esac
  done <<< "$patch"
  if [ "${#removed[@]}" -ne 1 ] || [ "${#added[@]}" -ne 1 ]; then
    find_out "${caller}: want one removed and one added line besides the header, got ${#removed[@]} and ${#added[@]}"
    continue
  fi
  if [ "$header_removed" -ne "$header_added" ]; then
    find_out "${caller}: the header lines removed (${header_removed}) and added (${header_added}) do not match"
    continue
  fi
  removed_re="^-[[:space:]]*uses: ${REPO_RE}/\\.github/workflows/${wf//./\\.}@[0-9a-f]{40} # [^[:space:]]+\$"
  added_re="^\\+[[:space:]]*uses: ${REPO_RE}/\\.github/workflows/${wf//./\\.}@${SHA} # v${VERSION//./\\.}\$"
  if ! [[ "${removed[0]}" =~ $removed_re ]]; then
    find_out "${caller}: the removed line is not a pin of ${wf}"
  elif ! [[ "${added[0]}" =~ $added_re ]]; then
    find_out "${caller}: the added line is not the pin of ${wf} at v${VERSION} and ${SHA}"
  fi
done

if [ -n "$FINDINGS" ]; then
  printf '%s' "$FINDINGS"
  COMPLETED=1
  exit 1
fi
echo "OK: the pull request only moves the forsgren pins of both callers to v${VERSION} at ${SHA}"
COMPLETED=1
