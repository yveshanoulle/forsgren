#!/usr/bin/env bash
# Scripts/release_quality.sh
#
# Quality on a commit, for the Release workflow (forsgren#221, step 2 of 2).
#
#   Scripts/release_quality.sh check <sha>
#       Quality (quality.yml) must be green on <sha>: a completed run with the
#       conclusion success. A run still going is waited for; no run at all, or
#       only runs that ended in anything but success, is a red.
#   Scripts/release_quality.sh dispatch <sha> <ref>
#       Starts quality.yml on <ref> (a workflow_dispatch: a push by the job's
#       token starts no run, a dispatch by it does), then waits as `check` does
#       for a run on <sha>; a run that has not appeared yet is waited for too.
#
#   Scripts/release_quality.sh dispatch-bump <sha> <ref> <green-parent> <old-version> <new-version>
#       The same, for the bump commit of a release (forsgren#230, step 2): the
#       dispatch carries scope=bump and the green parent, the old and the new
#       version as inputs, so quality.yml runs the short Quality: the bump diff
#       check first (Scripts/release_bump_diff.sh), then only the gates of
#       Scripts/quality_bump_gates.txt and the site build.
#
# The wait is bounded: RELEASE_QUALITY_TRIES polls (default 120), RELEASE_QUALITY_DELAY
# seconds apart (default 30). Running out of tries is a red naming the commit.
# Exit: 0 green, 1 red or timed out, 2 usage. gh reads GH_TOKEN.
# Self-test: Scripts/test_release_quality.sh (a stub gh on PATH).

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_quality.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

usage() {
  echo "usage: Scripts/release_quality.sh check <sha> | dispatch <sha> <ref> | dispatch-bump <sha> <ref> <green-parent> <old-version> <new-version>" >&2
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
  dispatch) [ "$#" -eq 3 ] || usage ;;
  dispatch-bump) [ "$#" -eq 6 ] || usage ;;
  *) usage ;;
esac
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || usage
if [ "$MODE" = dispatch-bump ]; then
  [[ "$4" =~ ^[0-9a-f]{40}$ ]] || usage
  [[ "$5" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$6" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
fi
TRIES="${RELEASE_QUALITY_TRIES:-120}"
DELAY="${RELEASE_QUALITY_DELAY:-30}"
[[ "$TRIES" =~ ^[1-9][0-9]*$ && "$DELAY" =~ ^[0-9]+$ ]] || usage

if [ "$MODE" = dispatch ]; then
  gh workflow run quality.yml --ref "$3" || red "could not start quality.yml on ${3}"
  echo "started quality.yml on ${3}, waiting for its run on ${SHA}"
elif [ "$MODE" = dispatch-bump ]; then
  gh workflow run quality.yml --ref "$3" -f scope=bump -f green_parent="$4" -f old_version="$5" -f new_version="$6" \
    || red "could not start the short quality.yml (scope=bump) on ${3}"
  echo "started the short quality.yml (scope=bump) on ${3}, waiting for its run on ${SHA}"
fi

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
  elif [ "$MODE" = check ]; then
    red "no Quality run on ${SHA}: start quality.yml on main by hand, then run the release again"
  else
    state="no run yet"
  fi
  if [ "$try" -lt "$TRIES" ]; then sleep "$DELAY"; fi
done
red "gave up after ${TRIES} polls of ${DELAY}s: ${state} on ${SHA}"
