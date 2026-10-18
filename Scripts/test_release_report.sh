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
#   4e. the plan stopped on named issues (forsgren#232): a table
#      `|  | Issue | Blocks because | Do |` (a red ❌ first in every row), one row per blocking issue in the
#      plan's order, read from the plan's machine lines (RELEASE_PLAN_OUTPUT);
#      links when the repo is known; the annotation names the numbers; the
#      generic cause only when no issue is named
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
# GH_REPO wins over GITHUB_REPOSITORY for the links, so an ambient one must not leak in.
unset GH_REPO
export GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=acme/app RELEASE_BUMP=minor
SHA40=0123456789abcdef0123456789abcdef01234567
ALL_STEPS=(main checkout setup-go log token resume quality plan free bump test commit quality-bump quality-resumed publish template metrics-pr metrics)

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

# 4e: the plan stopped on named issues (forsgren#232): a table, one row per
# issue, from the plan's own machine lines (RELEASE_PLAN_OUTPUT)
TABS=$'\t'
PLAN_OUT="${TMP}/plan.txt"
plan_case() { # <log steps...>: a failed plan with the plan output in PLAN_OUT
  logged "$@"
  outcomes plan failure
  RELEASE_PLAN_OUTPUT="$PLAN_OUT" report "$LOG" failure
}
printf '%s\n' \
  '❌ FAIL: release plan: #221 No label yet: label it patch, minor or major' \
  "blocking=221${TABS}unlabelled${TABS}No label yet${TABS}v1.10.0" \
  "blocking=231${TABS}open-with-commits${TABS}Half | landed${TABS}v1.10.0" \
  "blocking=240${TABS}needs-minor${TABS}Add a view${TABS}v1.10.0" > "$PLAN_OUT"
plan_case token quality
CASE="plan with named issues"
want_said "$CASE: the table header" "| Issue | Blocks because | Do |"
want_said "$CASE: unlabelled row" "| ❌ | [#221](https://github.com/acme/app/issues/221) No label yet | closed since v1.10.0, no patch, minor or major label | label it patch, minor or major |"
want_said "$CASE: open row, a bar in the title is escaped" "| ❌ | [#231](https://github.com/acme/app/issues/231) Half \\| landed | open, with commits on main since v1.10.0 | close it, or split it (close the landed part as its own issue, move the rest to a new one) |"
want_said "$CASE: bump row" "| ❌ | [#240](https://github.com/acme/app/issues/240) Add a view | needs minor, the run asked for minor | start Release with bump = minor |"
if [[ "$(grep -n -F '#221](' <<< "$OUT" | cut -d: -f1)" -ge "$(grep -n -F '#231](' <<< "$OUT" | cut -d: -f1)" || "$(grep -n -F '#231](' <<< "$OUT" | cut -d: -f1)" -ge "$(grep -n -F '#240](' <<< "$OUT" | cut -d: -f1)" ]]; then fail "$CASE: the rows are not in the plan's order. Output: ${OUT}"; else echo "  ok: $CASE: the rows are in the plan's order"; fi
want_said "$CASE: the annotation names the numbers" "(plan), blocked by #221, #231, #240."
if grep -qF "label the issues the plan names" <<< "$OUT"; then fail "$CASE: the generic cause is said although issues are named. Output: ${OUT}"; else echo "  ok: $CASE: no generic cause"; fi
want_said "$CASE: start again" "start Release again"
# GitHub renders a table only after a blank line, and the line after it
# must be blank too, or the next line becomes a table row.
table_framed() { # <text>: blank line before the header, blank after the last row
  local text="$1" head last
  head="$(grep -nF '| Issue | Blocks because | Do |' <<< "$text" | head -n 1 | cut -d: -f1)"
  [[ -n "$head" ]] || return 1
  last="$(grep -n '^|' <<< "$text" | tail -n 1 | cut -d: -f1)"
  [[ -z "$(sed -n "$((head - 1))p" <<< "$text")" && "$head" -gt 1 ]] || return 1
  [[ "$(wc -l <<< "$text")" -gt "$last" && -z "$(sed -n "$((last + 1))p" <<< "$text")" ]]
}
# every row starts with the red cross and has 4 cells; the header names 4 columns
row_findings() { # <text>: one line per table row that is not "| ❌ | ... |" with 4 cells
  local row
  while IFS= read -r row; do
    [[ "$row" == "| ❌ | "* ]] || { echo "row without the red cross: ${row}"; continue; }
    [[ "$(grep -o ' | ' <<< "$row" | wc -l | tr -d ' ')" -ge 3 ]] || echo "row with fewer than 4 cells: ${row}"
  done < <(grep '^| ' <<< "$1" | grep -vF '|  | Issue |')
}
GITHUB_STEP_SUMMARY="${TMP}/summary4.md" plan_case token quality
SUMMARY4="$(cat "${TMP}/summary4.md")"
if [[ -n "$(row_findings "$SUMMARY4")" ]]; then fail "$CASE: $(row_findings "$SUMMARY4")"; else echo "  ok: $CASE: every row starts with the red cross and has 4 cells"; fi
want_said "$CASE: the header has the icon column" "|  | Issue | Blocks because | Do |"
if grep -qF '::' "${TMP}/summary4.md"; then fail "$CASE: the job summary holds workflow-command text ('::'). Summary: ${SUMMARY4}"; else echo "  ok: $CASE: no workflow command in the job summary"; fi
if [[ "$(head -n 1 "${TMP}/summary4.md")" == "❌ The release run ended as failure at the step 'Plan the release' (plan), blocked by #221, #231, #240." ]]; then echo "  ok: $CASE: the summary headline is a red cross"; else fail "$CASE: the summary headline is: $(head -n 1 "${TMP}/summary4.md")"; fi
if [[ "$(head -n 1 <<< "$OUT")" == "::error::The release run ended as failure"* ]]; then echo "  ok: $CASE: the log keeps the ::error:: annotation"; else fail "$CASE: the log has no ::error:: headline. Output: ${OUT}"; fi
if table_framed "$OUT"; then echo "  ok: $CASE: a blank line before and after the table"; else fail "$CASE: the table has no blank line before its header or after its last row (it would not render). Output: ${OUT}"; fi
if [[ "$(grep -cF '| Issue | Blocks because | Do |' <<< "$OUT")" -ne 1 ]]; then fail "$CASE: the table is not printed exactly once. Output: ${OUT}"; else echo "  ok: $CASE: the table is printed once"; fi
one_notice
no_hand
export RELEASE_BUMP=patch
plan_case token quality
want_said "$CASE: the run's own bump is in the reason" "needs minor, the run asked for patch"
export RELEASE_BUMP=minor
GITHUB_REPOSITORY="" GH_REPO="" plan_case token quality
want_said "$CASE: without a repo the issue is plain" "| ❌ | #221 No label yet | closed since v1.10.0"
if grep -qF 'issues/221' <<< "$OUT"; then fail "$CASE: a link without a known repo. Output: ${OUT}"; else echo "  ok: $CASE: no link without a repo"; fi
GH_REPO=other/repo GITHUB_REPOSITORY=acme/app plan_case token quality
want_said "$CASE: GH_REPO wins for links" "https://github.com/other/repo/issues/221"
GITHUB_STEP_SUMMARY="${TMP}/summary3.md" plan_case token quality
if grep -qF "| Issue | Blocks because | Do |" "${TMP}/summary3.md"; then echo "  ok: $CASE: the table is in the job summary"; else fail "$CASE: no table in the job summary"; fi
# no issue named: the generic sentence stays; nothing closed is one sentence
printf '%s\n' '❌ FAIL: release plan: nothing was closed since v1.10.0' > "$PLAN_OUT"
plan_case token quality
CASE="plan, nothing closed"
want_said "$CASE: one sentence" "Cause: nothing was closed since the last release."
if grep -qF "| Issue |" <<< "$OUT"; then fail "$CASE: a table. Output: ${OUT}"; else echo "  ok: $CASE: no table"; fi
CASE="plan, no issue named"
: > "$PLAN_OUT"
plan_case token quality
want_said "$CASE: the generic cause" "label the issues the plan names patch, minor or major"
if grep -qF "| Issue |" <<< "$OUT"; then fail "$CASE: a table. Output: ${OUT}"; else echo "  ok: $CASE: no table"; fi
rm -f "$PLAN_OUT"
plan_case token quality
want_said "$CASE: no plan output at all: the generic cause" "label the issues the plan names patch, minor or major"
# blocking lines of another step's failure are not used
printf 'blocking=221\tunlabelled\tX\tv1.10.0\n' > "$PLAN_OUT"
logged token quality plan
outcomes free failure
RELEASE_PLAN_OUTPUT="$PLAN_OUT" report "$LOG" failure
if grep -qF "| Issue |" <<< "$OUT"; then fail "a free failure shows the plan table. Output: ${OUT}"; else echo "  ok: only a failed plan step shows the table"; fi

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

# resume = publish runs the full Quality on the resumed bump commit (forsgren#230, step 2)
logged token resume
echo "resume: tag=v1.9.5 at ${SHA40}" >> "$LOG"
outcomes quality-resumed failure
RELEASE_RESUME=publish report "$LOG" failure
CASE="quality-resumed"
want_said "$CASE: the step is named" "at the step 'Quality is green on the resumed bump commit' (quality-resumed)."
want_said "$CASE: resume publish" "start Release with resume = publish: gh workflow run release.yml -f resume=publish"
want_said "$CASE: the steps not done" "Not done: quality-resumed, publish, template, metrics-pr, metrics"
no_hand
logged token resume quality-resumed publish template metrics-pr metrics
outcomes
RELEASE_RESUME=publish report "$LOG" success
want_green "a resumed publish that finished" "- quality-resumed: did quality-resumed"
# which Quality ran is in the report, from the step's own log line
logged token quality plan free bump test commit
echo "quality-bump: short Quality (bump) green on ${SHA40}: Quality is green on ${SHA40} (https://example.test/run/9, poll 2)" >> "$LOG"
outcomes
report "$LOG" success
want_said "the report says the short Quality ran, with its run" "short Quality (bump) green on ${SHA40}"
want_said "the report links the run" "https://example.test/run/9"

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
if mutant success "s/^if \\[ \".STATUS\" != success \\]; then\$/if false; then/"; then
  report "$LOG" failure
  if grep -q '::error::' <<< "$OUT"; then fail "mutation proof: the mutant still reports the failure"; else echo "  ok: mutation proof: a failure reported as success has no ::error::"; fi
fi
if mutant notdone '/^Not done: /d'; then
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
# A report that renders only the first blocking issue must be caught, naming
# the missing one.
printf '%s\n' "blocking=221${TABS}unlabelled${TABS}No label yet${TABS}v1.10.0" "blocking=231${TABS}open-with-commits${TABS}Half landed${TABS}v1.10.0" > "$PLAN_OUT"
if mutant firstonly "s/^    n_blocked=\\\$((n_blocked + 1))\$/    n_blocked=\$((n_blocked + 1)); break/"; then :; fi
logged token quality
outcomes plan failure
if [[ -x "${TMP}/mut/firstonly/release_report.sh" ]]; then
  RELEASE_PLAN_OUTPUT="$PLAN_OUT" report "$LOG" failure
  if grep -qF '#231' <<< "$OUT"; then fail "mutation proof: the mutant still renders #231. Output: ${OUT}"; else echo "  ok: mutation proof: a report that renders only the first issue leaves out #231, and case 4e names it"; fi
fi
# A table glued to the sentence above it (no blank line) must be caught.
printf '%s\n' "blocking=221${TABS}unlabelled${TABS}No label yet${TABS}v1.10.0" > "$PLAN_OUT"
if mutant glued '/^            cause="The plan stopped; these issues block the release:$/{n;d;}'; then
  logged token quality
  outcomes plan failure
  RELEASE_PLAN_OUTPUT="$PLAN_OUT" report "$LOG" failure
  if table_framed "$OUT"; then fail "mutation proof: the glued table was not caught. Output: ${OUT}"; else echo "  ok: mutation proof: a table without the blank line before it is caught by the framing case"; fi
fi
# ::error:: written into the job summary must be caught.
logged token quality
outcomes plan failure
if mutant summaryerr "s/'❌ %s/'::error::%s/"; then
  GITHUB_STEP_SUMMARY="${TMP}/summary5.md" RELEASE_PLAN_OUTPUT="$PLAN_OUT" report "$LOG" failure
  if grep -qF '::error::' "${TMP}/summary5.md"; then echo "  ok: mutation proof: an ::error:: line in the job summary is what case 4e catches"; else fail "mutation proof: the mutant did not write ::error:: into the summary"; fi
fi
# A row without the red cross must be caught, naming the issue.
if mutant nocross "s/}| ❌ | /}| /"; then
  GITHUB_STEP_SUMMARY="${TMP}/summary6.md" RELEASE_PLAN_OUTPUT="$PLAN_OUT" report "$LOG" failure
  found="$(row_findings "$(cat "${TMP}/summary6.md")")"
  if grep -qF '#221' <<< "$found"; then echo "  ok: mutation proof: a row without the red cross is caught, naming #221"; else fail "mutation proof: the row without the red cross was not caught. Findings: ${found}"; fi
fi
unset SCRIPT RELEASE_STEP_OUTCOMES

# --table (forsgren#231, step 3): only the table and the ready list.
printf 'blocking=6\tunlabelled\tUnlabelled thing\tv1.9.3\nready=5\tpatch\tFix the thing\tv1.9.3\n' > "${TMP}/table-plan.txt"
capture env GH_REPO= GITHUB_REPOSITORY= "$REPORT" --table "${TMP}/table-plan.txt"
want_green "--table renders the table" "| ❌ | #6 Unlabelled thing | closed since v1.9.3, no patch, minor or major label | label it patch, minor or major |"
want_said "--table lists the ready issue" "- ✅ #5 Fix the thing (patch)"
capture env -u GH_REPO GITHUB_REPOSITORY=acme/app GITHUB_SERVER_URL=https://github.com "$REPORT" --table "${TMP}/table-plan.txt"
want_said "--table links the issues when the repository is known" "[#6](https://github.com/acme/app/issues/6) Unlabelled thing"

selftest_end "the release report does not hold" "release report: done steps, the step that failed (read from its outcome) and what was not done are all said"
