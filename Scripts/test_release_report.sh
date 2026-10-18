#!/usr/bin/env bash
# Scripts/test_release_report.sh
#
# Self-test for Scripts/release_report.sh (forsgren#221, step 2 of 2).
#   1. every step logged, status success -> the done list, no ::error::
#   2. the run failed after the commit    -> ::error:: naming the step whose
#      outcome is failure, the done steps (with their details) and the steps
#      not done
#   3. the token check failed, the log empty (forsgren#221, the first real run)
#      -> the token check is named, never "quality"
#   4. a cancelled step is named; no outcomes given, or none that failed ->
#      the failed step is said to be unknown, never inferred from the log
#   4b. a resumed run (RELEASE_RESUME=pins) expects token, resume, template and
#      metrics only
#   4d. what to do next, one case per stage: before anything is pushed (the
#      cause per step, start again with the same bump), the bump commit on main
#      with no release (resume = publish, a plain rerun cannot work), released
#      with a pin step failed (resume = pins, never by hand); one ::notice::
#   5. the same text goes to GITHUB_STEP_SUMMARY; usage
# The failed step is read from the outcomes of the steps (RELEASE_STEP_OUTCOMES,
# one `<id>=<outcome>` line per step, the workflow passes steps.<id>.outcome).
# Mutation proofs: a copy that reports a failure as success, one that forgets
# the not-done list and one that infers the failed step from the log (a failed
# token check reported as "quality") must each be caught.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release report self-test"

REPORT="Scripts/release_report.sh"
[[ -f "$REPORT" ]] || selftest_abort "${REPORT} does not exist — a failed release would not say what was done"

LOG="${TMP}/release.log"
D='$'
LOGGED=(token quality plan free bump test commit quality-bump publish template metrics-pr metrics)
export GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=acme/app RELEASE_BUMP=minor
SHA40=0123456789abcdef0123456789abcdef01234567
ALL_STEPS=(main checkout setup-go log token resume quality plan free bump test commit quality-bump publish template metrics-pr metrics)

# logged <id>...: the log with those steps recorded.
logged() {
  : > "$LOG"
  local step
  for step in "$@"; do echo "${step}: did ${step}" >> "$LOG"; done
}

# outcomes <failed id> <outcome>: every step success before it, that outcome
# for it, skipped after it; empty arguments: all success. In RELEASE_STEP_OUTCOMES.
outcomes() {
  local step state=success
  RELEASE_STEP_OUTCOMES=""
  for step in "${ALL_STEPS[@]}"; do
    if [[ "$step" == "${1:-}" ]]; then
      RELEASE_STEP_OUTCOMES+="${step}=${2}"$'\n'
      state=skipped
    else
      RELEASE_STEP_OUTCOMES+="${step}=${state}"$'\n'
    fi
  done
  export RELEASE_STEP_OUTCOMES
}
report() { capture "${SCRIPT:-$REPORT}" "$@"; }

# 1
logged "${LOGGED[@]}"
outcomes
report "$LOG" success
want_green "a successful run" "Release run finished"
if grep -q '::error::' <<< "$OUT"; then fail "a successful run printed an error. Output: ${OUT}"; fi
want_said "it lists the last step" "- metrics: did metrics"
grep -v '^metrics: ' "$LOG" > "${LOG}.new" && mv "${LOG}.new" "$LOG"
echo "metrics: PR #19 merged, forsgren run https://example.test/run/9 green" >> "$LOG"
report "$LOG" success
want_said "the metrics line says the pull request and the run" "- metrics: PR #19 merged, forsgren run https://example.test/run/9 green"
want_said "it lists the token check" "- token: did token"

# 2
logged token quality plan free bump test commit
outcomes quality-bump failure
report "$LOG" failure
want_green "a failed run is only reported"
want_said "the failed step is named" "::error::The release run ended as failure at the step 'Quality is green on the bump commit' (quality-bump)."
want_said "the done steps are listed" "- commit: did commit"
want_said "the steps not done are listed" "Not done: quality-bump, publish, template, metrics-pr, metrics"

# 3: the first real run
logged
outcomes token failure
report "$LOG" failure
want_said "a failed token check is named" "at the step 'Check the release token is set' (token)."
if grep -qF "'quality'" <<< "$OUT" || grep -qF "Quality is green on main" <<< "$OUT"; then fail "a failed token check is reported as another step. Output: ${OUT}"; else echo "  ok: the report does not name quality"; fi
want_said "nothing was done" "- nothing"

# 4
logged token quality
outcomes plan cancelled
report "$LOG" cancelled
want_said "a cancelled step is named" "ended as cancelled at the step 'Plan the release' (plan)."
logged token quality
unset RELEASE_STEP_OUTCOMES
report "$LOG" failure
want_said "no outcomes: the step is unknown" "the failed step is unknown"
if grep -qF "'plan'" <<< "$OUT"; then fail "the failed step was inferred from the log. Output: ${OUT}"; else echo "  ok: nothing is inferred from the log"; fi
outcomes
report "$LOG" failure
want_said "no step failed" "no step reports a failure"

# 4b: a resumed run (RELEASE_RESUME=pins) only expects token, resume, template, metrics
logged token resume
outcomes template failure
RELEASE_RESUME=pins report "$LOG" failure
want_said "a resumed run names its failed step" "at the step 'Move the pins and README of forsgren-template' (template)."
want_said "a resumed run expects only its own steps" "Not done: template, metrics-pr, metrics"
if grep -qF "quality" <<< "$OUT"; then fail "a resumed run lists the skipped steps as not done. Output: ${OUT}"; else echo "  ok: the skipped steps are not listed"; fi
logged token resume template metrics-pr metrics
outcomes
RELEASE_RESUME=pins report "$LOG" success
want_green "a resumed run that finished" "- resume: did resume"

# 4c: what to do next, per stage of the failure
unset RELEASE_RESUME
advice_case() { # <what> <failed id> <log steps...>: report a failure of that step
  local what="$1" failed="$2"
  shift 2
  logged "$@"
  outcomes "$failed" failure
  report "$LOG" failure
  CASE="$what"
}
no_hand() {
  if grep -qiE 'by hand|manually' <<< "$OUT"; then fail "$CASE: the advice suggests doing a step by hand. Output: ${OUT}"; fi
}
one_notice() {
  if [[ "$(grep -c '^::notice::' <<< "$OUT")" -ne 1 ]]; then fail "$CASE: want exactly one ::notice:: line. Output: ${OUT}"; else echo "  ok: ${CASE}: one ::notice:: line"; fi
}

# before anything was pushed
advice_case "token" token
want_said "$CASE: nothing was released" "Nothing was released and nothing was pushed to main."
want_said "$CASE: start again with the same bump" "fix the cause and start Release again with the same bump (minor)"
want_said "$CASE: the secret is named" "FORSGREN_RELEASE_TOKEN"
one_notice
no_hand
advice_case "plan" plan token quality
want_said "$CASE: the cause" "label the issues the plan names patch, minor or major"
want_said "$CASE: the cause names open issues with commits on main" "close or split every open issue it names that already has commits on main"
want_said "$CASE: start again" "start Release again with the same bump (minor)"
advice_case "free" free token quality plan
want_said "$CASE: the cause" "that version already exists as a tag or a release"
advice_case "quality" quality token
want_said "$CASE: the link" "https://github.com/acme/app/actions/workflows/quality.yml"
advice_case "bump" bump token quality plan free
want_said "$CASE: start again" "start Release again with the same bump (minor)"
advice_case "commit" commit token quality plan free bump test
want_said "$CASE: nothing pushed" "Nothing was released and nothing was pushed to main."

# the bump commit is on main, no release
logged token quality plan free bump test commit
echo "commit: sha=${SHA40} pushed to main" >> "$LOG"
outcomes quality-bump failure
report "$LOG" failure
CASE="quality-bump"
want_said "$CASE: the commit is on main" "The bump commit ${SHA40} is on main and no release exists."
want_said "$CASE: a rerun cannot work" "Do not start Release again with a bump: the version is already bumped and the bump step would refuse it."
want_said "$CASE: resume publish" "start Release with resume = publish: gh workflow run release.yml -f resume=publish"
want_said "$CASE: only while main has not moved" "if main has moved on, fix main and run a new release instead"
want_said "$CASE: the UI path" "Actions → Release → Run workflow → resume: publish"
want_said "$CASE: the quality link" "https://github.com/acme/app/actions/workflows/quality.yml"
one_notice
no_hand
outcomes publish failure
report "$LOG" failure
CASE="publish"
want_said "$CASE: the commit is on main" "The bump commit ${SHA40} is on main and no release exists."
want_said "$CASE: resume publish" "-f resume=publish"
no_hand

# released, a pin step failed
logged token quality plan free bump test commit quality-bump
echo "publish: tag and release v1.9.5 at ${SHA40}, Latest" >> "$LOG"
outcomes template failure
report "$LOG" failure
CASE="template"
want_said "$CASE: it is released" "v1.9.5 is released."
want_said "$CASE: the 403 cause" "for a 403: the token's Workflows permission"
want_said "$CASE: resume pins" "start Release with resume = pins: gh workflow run release.yml -f resume=pins"
want_said "$CASE: the UI path" "Actions → Release → Run workflow → resume: pins"
one_notice
no_hand
outcomes metrics-pr failure
report "$LOG" failure
CASE="metrics-pr"
want_said "$CASE: it is released" "v1.9.5 is released."
want_said "$CASE: resume pins" "-f resume=pins"
no_hand
outcomes metrics failure
report "$LOG" failure
CASE="metrics (the merge or the forsgren run)"
want_said "$CASE: the step is named" "at the step 'Merge the pin pull request and run forsgren in forsgren-metrics' (metrics)."
want_said "$CASE: it is released" "v1.9.5 is released."
want_said "$CASE: resume pins" "-f resume=pins"
no_hand
# a resumed run that fails again
logged token resume
echo "resume: tag=v1.9.4 at ${SHA40}" >> "$LOG"
outcomes template failure
RELEASE_RESUME=pins report "$LOG" failure
CASE="resumed template"
want_said "$CASE: the released version" "v1.9.4 is released."
want_said "$CASE: resume pins again" "-f resume=pins"
# a failed resume before the pins
logged token
outcomes resume failure
RELEASE_RESUME=pins report "$LOG" failure
want_said "the resume step itself failed" "start the same resume again"
# the summary, and a success has no advice
all_ok() { logged "${LOGGED[@]}"; outcomes; }
all_ok
report "$LOG" success
if grep -q 'What to do next\|::notice::' <<< "$OUT"; then fail "a successful run gives advice. Output: ${OUT}"; else echo "  ok: a successful run gives no advice"; fi
logged token quality plan free bump test commit quality-bump
echo "publish: tag and release v1.9.5 at ${SHA40}, Latest" >> "$LOG"
outcomes template failure
GITHUB_STEP_SUMMARY="${TMP}/summary2.md" report "$LOG" failure
if grep -qF "What to do next" "${TMP}/summary2.md" && grep -qF -- "-f resume=pins" "${TMP}/summary2.md"; then echo "  ok: the advice is in the job summary"; else fail "the advice is not in the job summary"; fi

# 5
logged "${LOGGED[@]}"
outcomes
GITHUB_STEP_SUMMARY="${TMP}/summary.md" report "$LOG" success
if grep -qF "Release run finished" "${TMP}/summary.md"; then echo "  ok: the report goes to the step summary"; else fail "nothing was written to GITHUB_STEP_SUMMARY"; fi
report
want_exit "no arguments" 2 "usage"

# Mutation proofs.
mutant() {
  selftest_mutant "$REPORT" "${TMP}/mut/$1/release_report.sh" "$2" || return 1
  SCRIPT="${TMP}/mut/$1/release_report.sh"
}

logged token quality
outcomes plan failure
if mutant success "s/if \[ \".STATUS\" = success \]; then/if true; then/"; then
  report "$LOG" failure
  if grep -q '::error::' <<< "$OUT"; then fail "mutation proof: the mutant still reports the failure"; else echo "  ok: mutation proof: a failure reported as success has no ::error::"; fi
fi
if mutant notdone 's/^    echo "Not done: .*$/    true/'; then
  report "$LOG" failure
  if grep -q 'Not done' <<< "$OUT"; then fail "mutation proof: the mutant still lists what was not done"; else echo "  ok: mutation proof: without the list a half-made release is a guess"; fi
fi
# The old inference: the first step the log does not show, over the steps
# that were logged then (no token check). A failed token check, with an empty
# log, is then reported as the quality wait.
logged
outcomes token failure
if mutant infer "s/^for step in .ALL_IDS; do\$/for step in quality plan free bump commit quality-bump publish template metrics; do/;s/^  if \[ \".outcome\" = failure \] || \[ \".outcome\" = cancelled \]; then\$/  if ! grep -q \"^${D}{step}: \" \"${D}LOG\" 2> \/dev\/null; then/"; then
  report "$LOG" failure
  if grep -qF "at the step 'Quality is green on main' (quality)" <<< "$OUT"; then
    echo "  ok: mutation proof: a failed token check reported as quality is what the log inference gives, and the case above catches it"
  else
    fail "mutation proof: the log-inference mutant did not report the token check as quality. Output: ${OUT}"
  fi
fi
# A template failure without the resume instruction must be caught: the
# mutant drops it, and the case above (the instruction is said) fails on it.
logged token quality plan free bump test commit quality-bump
echo "publish: tag and release v1.9.5 at ${SHA40}, Latest" >> "$LOG"
outcomes template failure
if mutant noresume 's/resume = pins/resume = nothing/;s/-f resume=pins/-f resume=nothing/'; then
  report "$LOG" failure
  if grep -qF -- "-f resume=pins" <<< "$OUT"; then
    fail "mutation proof: the mutant without the resume instruction still gives it"
  else
    echo "  ok: mutation proof: a template failure without the resume instruction is what the case above catches"
  fi
fi
unset SCRIPT RELEASE_STEP_OUTCOMES

selftest_end "the release report does not hold" "release report: done steps, the step that failed (read from its outcome) and what was not done are all said"
