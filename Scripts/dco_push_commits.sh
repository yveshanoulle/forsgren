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
# base64 keeps a message with any content on one line, as in the check.
#
# Usage: Scripts/dco_push_commits.sh <before> <after> [repo-dir]
#   (default repo-dir: the repository root)
# Exit: 0 and the lines on stdout; 1 on a wrong call, a repo that is not
# found, or a range git cannot resolve (nothing printed that could pass).
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

if ! shas="$(git rev-list --reverse "${BEFORE}..${AFTER}" 2>&1)"; then
  echo "❌ FAIL: git could not list ${BEFORE}..${AFTER}: ${shas}"
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
