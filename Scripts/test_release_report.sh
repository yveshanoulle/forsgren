#!/usr/bin/env bash
# Scripts/test_release_report.sh
#
# Self-test for Scripts/release_report.sh (forsgren#221, step 2 of 2).
#   1. every step logged, status success -> the done list, no ::error::
#   2. the run failed after the commit    -> ::error:: naming the first step
#      missing, the done steps (with their details) and the steps not done
#   3. an empty or missing log, failed    -> "nothing" done, the first step named
#   4. the same text goes to GITHUB_STEP_SUMMARY
#   5. usage
# Mutation proofs: a copy that reports a failure as success and one that
# forgets the not-done list must each be caught.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release report self-test"

REPORT="Scripts/release_report.sh"
[[ -f "$REPORT" ]] || selftest_abort "${REPORT} does not exist — a failed release would not say what was done"

LOG="${TMP}/release.log"
all() {
  : > "$LOG"
  local step
  for step in quality plan free bump commit quality-bump publish template metrics; do
    echo "${step}: did ${step}" >> "$LOG"
  done
}

all
capture "$REPORT" "$LOG" success
want_green "a successful run" "Release run finished"
if grep -q '::error::' <<< "$OUT"; then fail "a successful run printed an error. Output: ${OUT}"; fi
want_said "it lists the last step" "- metrics: did metrics"

: > "$LOG"
for step in quality plan free bump commit; do echo "${step}: did ${step}" >> "$LOG"; done
capture "$REPORT" "$LOG" failure
want_green "a failed run is only reported"
want_said "the first missing step is named" "::error::The release run ended as failure at the step 'quality-bump'"
want_said "the done steps are listed" "- commit: did commit"
want_said "the steps not done are listed" "Not done: quality-bump, publish, template, metrics"

capture "$REPORT" "${TMP}/none.log" cancelled
want_said "no log" "- nothing"
want_said "the first step is named" "at the step 'quality'"

all
GITHUB_STEP_SUMMARY="${TMP}/summary.md" capture "$REPORT" "$LOG" success
if grep -qF "Release run finished" "${TMP}/summary.md"; then echo "  ok: the report goes to the step summary"; else fail "nothing was written to GITHUB_STEP_SUMMARY"; fi

capture "$REPORT"
want_exit "no arguments" 2 "usage"

# Mutation proofs.
selftest_mutant "$REPORT" "${TMP}/mut/a/release_report.sh" "s/if \[ \".STATUS\" = success \]; then/if true; then/" || true
: > "$LOG"
echo "quality: did quality" >> "$LOG"
capture "${TMP}/mut/a/release_report.sh" "$LOG" failure
if grep -q '::error::' <<< "$OUT"; then fail "mutation proof: the mutant still reports the failure"; else echo "  ok: mutation proof: a failure reported as success has no ::error::"; fi
selftest_mutant "$REPORT" "${TMP}/mut/b/release_report.sh" 's/^    echo "Not done: .*$/    true/' || true
capture "${TMP}/mut/b/release_report.sh" "$LOG" failure
if grep -q 'Not done' <<< "$OUT"; then fail "mutation proof: the mutant still lists what was not done"; else echo "  ok: mutation proof: without the list a half-made release is a guess"; fi

selftest_end "the release report does not hold" "release report: done steps, the first missing step and what was not done are all said"
