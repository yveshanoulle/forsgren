#!/usr/bin/env bash
# Scripts/release_report.sh
#
# What a Release run did, for its last step (forsgren#221, step 2 of 2), which
# runs whatever happened. The earlier steps append one line each to a log file:
# `<step id>: <what was done>`. The steps, in order: quality, plan, free, bump,
# commit, quality-bump, publish, template, metrics.
#
# Usage: Scripts/release_report.sh <log-file> <job-status>
# On success it prints the done steps. On any other status it prints an
# ::error:: line that names the first step that did not finish and says what
# was already done and what was not, so a half-made release is never a guess:
# a pushed bump commit, a release, a template that still pins the old version.
# It writes the same text to $GITHUB_STEP_SUMMARY when that is set, and always
# exits 0: it reports, the failed step already failed the run.
# Self-test: Scripts/test_release_report.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_report.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

if [ "$#" -ne 2 ]; then
  echo "usage: Scripts/release_report.sh <log-file> <job-status>" >&2
  COMPLETED=1
  exit 2
fi
LOG="$1"
STATUS="$2"

STEPS="quality plan free bump commit quality-bump publish template metrics"
DONE=""
MISSING=""
for step in $STEPS; do
  line=""
  if [ -f "$LOG" ]; then line="$(grep -m1 "^${step}: " "$LOG" || true)"; fi
  if [ -n "$line" ]; then
    DONE="${DONE}- ${line}
"
  else
    MISSING="${MISSING}${MISSING:+, }${step}"
  fi
done

{
  if [ "$STATUS" = success ]; then
    echo "Release run finished. Done:"
    printf '%s' "$DONE"
  else
    first="${MISSING%%,*}"
    echo "::error::The release run ended as ${STATUS} at the step '${first:-unknown}'."
    echo "Already done:"
    if [ -n "$DONE" ]; then printf '%s' "$DONE"; else echo "- nothing"; fi
    echo "Not done: ${MISSING:-nothing}"
    echo "A bump commit that was pushed stays on main, a tag exists only together with its release."
  fi
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
COMPLETED=1
