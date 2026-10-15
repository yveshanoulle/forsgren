#!/usr/bin/env bash
# Scripts/dco_push_commits.sh
#
# The commits of a push to main, in the shape Scripts/check_dco.sh reads
# (forsgren#81): .github/workflows/dco.yml pipes this into the check on a push,
# as it pipes the pull request's commit list on a pull request. One line per
# commit of before..after, oldest first:
#   <sha> - <base64 of the author email> <base64 of the message>
# The account is - on every line: a push names no GitHub account, so no commit
# is exempt as a bot's (the exemption needs a pull request's opener).
# A push that creates a branch has an all-zero <before>: only the head commit
# is listed then, the one the push is known to bring (the branch's older
# commits were pushed, and judged, before). A range with no commit in it
# (before equal to after, or an after that brings nothing over before) is an
# error, never an empty list: the check reads an empty list as red, but this
# fails at the source with its own reason, and a list of nothing is not a
# list of signed-off commits.
# base64 keeps a message with any content on one line, as in the check.
#
# Usage: Scripts/dco_push_commits.sh <before> <after> [repo-dir]
#   (default repo-dir: the repository root)
# Exit: 0 and the lines on stdout; 1 on a wrong call, a repo that is not
# found, a range git cannot resolve, or a range with no commit in it.
# Fixture: Scripts/test_check_dco.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "❌ FAIL: usage: Scripts/dco_push_commits.sh <before> <after> [repo-dir]"
  exit 1
fi
BEFORE="$1"
AFTER="$2"
cd "${3:-.}" || {
  echo "❌ FAIL: directory not found: ${3}"
  exit 1
}

if [[ "$BEFORE" =~ ^0+$ ]]; then
  range="${AFTER}"
  shas="$(git rev-parse --verify --quiet "${AFTER}^{commit}")" || {
    echo "❌ FAIL: git could not resolve ${AFTER} to a commit"
    exit 1
  }
else
  range="${BEFORE}..${AFTER}"
  if ! shas="$(git rev-list --reverse "$range" 2>&1)"; then
    echo "❌ FAIL: git could not list ${range}: ${shas}"
    exit 1
  fi
fi

if [ -z "$shas" ]; then
  echo "❌ FAIL: no commit in ${range} — a push that brings no commit has nothing to check"
  exit 1
fi

while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  email="$(git log -1 --format=%ae "$sha")"
  message="$(git log -1 --format=%B "$sha")"
  printf '%s - %s %s\n' "$sha" \
    "$(printf '%s' "$email" | base64 | tr -d '\n')" \
    "$(printf '%s' "$message" | base64 | tr -d '\n')"
done <<< "$shas"
