#!/usr/bin/env bash
# Scripts/release_quality.sh
#
# Quality on a commit, for the Release workflow (forsgren#221, step 2 of 2).
#
#   Scripts/release_quality.sh check <sha>
#       Quality (quality.yml) must be green on <sha>: a completed run with the
#       conclusion success. A run still going is waited for; no run at all, or
#       only runs that ended in anything but success, is a red.
#   Scripts/release_quality.sh head <sha>
#       Main's head (GITHUB_REPOSITORY, read through gh) must still be <sha>,
#       the commit Quality was proved green on (forsgren#237, step 5a): a red
#       naming both shas when main has moved, or when the head cannot be read.
#
# The wait is bounded: RELEASE_QUALITY_TRIES polls (default 120), RELEASE_QUALITY_DELAY
# seconds apart (default 30). Running out of tries is a red naming the commit.
# Exit: 0 green, 1 red or timed out, 2 usage. gh reads GH_TOKEN.
# Self-test: Scripts/test_release_quality.sh (a stub gh on PATH).

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_quality.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

usage() {
  echo "usage: Scripts/release_quality.sh check <sha> | head <sha>" >&2
  COMPLETED=1
  exit 2
}

red() {
  echo "❌ FAIL: release quality: $*"
  COMPLETED=1
  exit 1
}

MODE="${1:-}"
SHA="${2:-}"
case "$MODE" in
  check) [ "$#" -eq 2 ] || usage ;;
  head) [ "$#" -eq 2 ] || usage ;;
  *) usage ;;
esac
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || usage
if [ "$MODE" = head ]; then
  # forsgren#237, step 5a: a release tags the commit Quality was proved green
  # on, so main must still be at it.
  REPO="${GITHUB_REPOSITORY:-}"
  [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
  HEAD_SHA="$(gh api "repos/${REPO}/git/ref/heads/main" --jq '.object.sha' 2> /dev/null || true)"
  [[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || red "could not read the head of main in ${REPO}: nothing is tagged"
  if [ "$HEAD_SHA" != "$SHA" ]; then
    red "main has moved: its head is ${HEAD_SHA}, not ${SHA}. Quality was proved green on ${SHA}, which is no longer what main is: nothing is tagged, start the release again"
  fi
  echo "OK: main's head is ${SHA}, the commit Quality was proved green on"
  COMPLETED=1
  exit 0
fi
TRIES="${RELEASE_QUALITY_TRIES:-120}"
DELAY="${RELEASE_QUALITY_DELAY:-30}"
[[ "$TRIES" =~ ^[1-9][0-9]*$ && "$DELAY" =~ ^[0-9]+$ ]] || usage

try=0
state="no run"
while [ "$try" -lt "$TRIES" ]; do
  try=$((try + 1))
  runs="$(gh run list --workflow quality.yml --commit "$SHA" --limit 20 --json status,conclusion,url \
    --jq '.[] | [.status, .conclusion, .url] | @tsv')" || red "gh could not list the Quality runs of ${SHA}"
  pending=0
  failed=""
  while IFS="$(printf '\t')" read -r status conclusion url; do
    [ -n "$status" ] || continue
    if [ "$status" = completed ] && [ "$conclusion" = success ]; then
      echo "OK: Quality is green on ${SHA} (${url}, poll ${try})"
      COMPLETED=1
      exit 0
    elif [ "$status" = completed ]; then
      failed="${failed}${failed:+, }${url} (${conclusion})"
    else
      pending=1
    fi
  done <<< "$runs"
  if [ "$pending" -eq 1 ]; then
    state="a run is still going"
  elif [ -n "$failed" ]; then
    red "Quality is not green on ${SHA}: ${failed}"
  else
    red "no Quality run on ${SHA}: start quality.yml on main by hand, then run the release again"
  fi
  if [ "$try" -lt "$TRIES" ]; then sleep "$DELAY"; fi
done
red "gave up after ${TRIES} polls of ${DELAY}s: ${state} on ${SHA}"
