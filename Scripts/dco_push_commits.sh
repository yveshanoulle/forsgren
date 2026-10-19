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
# --fresh (forsgren#213, for Scripts/check_commit_messages.sh): the commits
# the push is NEW with, judged on their messages. A range before..after is
# listed as above; but an all-zero before (a new branch) or a before this
# checkout does not have (a force-push removed it) says nothing about which
# commits are new, and listing the head commit alone (or nothing) would let
# the rest pass unseen. Then every commit of <after> that is on no other
# remote branch and no tag is listed: refs/remotes/*/ except HEAD and main
# (main is the branch pushed to) and refs/tags. A commit another branch or a
# tag already holds was pushed before and is not judged again; a repository
# with no other branch has all its history new. Still an error, never an
# empty list, when none is left.
#
# Usage: Scripts/dco_push_commits.sh [--fresh] <before> <after> [repo-dir]
#   (default repo-dir: the repository root)
# Exit: 0 and the lines on stdout; 1 on a wrong call, a repo that is not
# found, a range git cannot resolve, or a range with no commit in it.
# Fixture: Scripts/test_check_dco.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

FRESH=0
if [ "${1:-}" = "--fresh" ]; then
  FRESH=1
  shift
fi
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "❌ FAIL: usage: Scripts/dco_push_commits.sh [--fresh] <before> <after> [repo-dir]"
  exit 1
fi
BEFORE="$1"
AFTER="$2"
cd "${3:-.}" || {
  echo "❌ FAIL: directory not found: ${3}"
  exit 1
}

# before_available: before names a commit this checkout has.
before_available() {
  [[ "$BEFORE" =~ ^0+$ ]] && return 1
  git rev-parse --verify --quiet "${BEFORE}^{commit}" > /dev/null
}

if [ "$FRESH" -eq 1 ] && ! before_available; then
  range="${AFTER}, on no other branch or tag"
  git rev-parse --verify --quiet "${AFTER}^{commit}" > /dev/null || {
    echo "❌ FAIL: git could not resolve ${AFTER} to a commit"
    exit 1
  }
  others=()
  while IFS= read -r ref; do
    others+=("$ref")
  done < <(git for-each-ref --format='%(refname)' refs/remotes refs/tags | grep -vE '^refs/remotes/[^/]+/(HEAD|main)$' || true)
  shas="$(git rev-list --reverse "$AFTER" --not ${others[@]+"${others[@]}"})"
elif [[ "$BEFORE" =~ ^0+$ ]]; then
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
