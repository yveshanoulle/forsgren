#!/usr/bin/env bash
# Scripts/test_quality_jobs.sh
#
# Pins the job layout of .github/workflows/quality.yml (forsgren#259, decision
# #260), forsgren's own: Quality runs its slowest gates in parallel jobs of ONE
# workflow, and stays one verdict. Step 2: the isolation job. The pins, each
# proved by a mutant of the real file that breaks it and must be named:
#   1. an isolation job exists, on macos-latest, with the same setup as the
#      main job: checkout at the same pin, the gate environment, Node, tool
#      install and npm ci, in that order
#   2. it runs Scripts/run_ci_phase.sh pre for the job `isolation`; the main
#      job passes `main` on both of its calls; no step of the file names the
#      two isolation gates itself (the order file and Scripts/ci_job_groups.txt
#      decide which gates a job runs, so one gate is never in two jobs or none)
#   3. Scripts/ci_job_groups.txt gives the isolation job exactly the git
#      sandbox isolation self-test and the step summary isolation gate, both
#      rows of the order file
#   4. the job hands its rows over: an upload of quality-report-isolation,
#      `if: always()`, and the main job does the same under quality-report-main
#   5. a report job needs EVERY gate job (not the preview), `if: always()`,
#      downloads the hand-overs, merges them with Scripts/merge_quality_report.sh
#      and renders the one Quality report (summary, then the gate table); its
#      QS_JOB_STATUS comes from the merge script's status of the jobs' results
#   6. the preview job needs every job, the report included (the generic pin of
#      Scripts/test_preview_workflow.sh, held here for the new jobs by name)
#   7. ONE Quality verdict: quality.yml is the only workflow named Quality, no
#      job or step softens a failure (continue-on-error), and
#      Scripts/release_quality.sh reads a run's own status and conclusion, which
#      GitHub sets from ALL its jobs (any failed or cancelled job is a
#      conclusion other than success), never a job
# A workflow is read with the awk readers of Scripts/lib_workflow_steps.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
selftest_begin "quality jobs pin"

WORKFLOW=".github/workflows/quality.yml"
GROUPS_FILE="Scripts/ci_job_groups.txt"
ORDER="Scripts/gate_report_order.txt"
RELEASE_CHECK="Scripts/release_quality.sh"
[[ -f "$WORKFLOW" ]] || selftest_abort "${WORKFLOW} does not exist"

DOLLAR='$'

code() {
  grep -vE '^[[:space:]]*#' "$1"
}

job_ids() {
  code "$1" | awk '/^jobs:/ { injobs=1; next } injobs && /^[^[:space:]]/ { injobs=0 } injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { id=$0; sub(/^  /, "", id); sub(/:.*$/, "", id); print id }'
}

# job_of <file> <id>: the lines of that job, comments included (the step
# readers need the file as written).
job_of() {
  awk -v id="$2" '
    /^jobs:/ { injobs=1; next }
    injobs && /^[^[:space:]]/ { injobs=0 }
    injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { on = ($0 == "  " id ":") }
    injobs && on { print }
  ' "$1"
}

# step_names <job file>: the names of its steps, in order.
step_names() {
  sed -n 's/^      - name: //p' "$1"
}

pin_of() {
  grep -E 'uses: actions/checkout@' "$1" | grep -vE '^[[:space:]]*#' | head -1 | sed -E 's/.*@([0-9a-f]{40}).*/\1/'
}

# setup_findings <job file> <id>: pin 1.
setup_findings() {
  local job="$1" id="$2" names want got
  if [[ ! -s "$job" ]]; then
    echo "job: the file has no ${id} job"
    return 0
  fi
  grep -qxF '    runs-on: macos-latest' "$job" || echo "runs-on: the ${id} job is not on macos-latest"
  want="$(pin_of "${TMP}/main.yml")"
  got="$(pin_of "$job")"
  [[ -n "$want" && "$got" == "$want" ]] || echo "pin of checkout: the ${id} job has ${got:-none}, the main job ${want:-none}"
  grep -qF 'fetch-depth: 0' "$job" || echo "checkout: the ${id} job does not fetch the full history, as the main job does"
  grep -qF 'persist-credentials: false' "$job" || echo "checkout: the ${id} job persists credentials"
  names="$(step_names "$job" | tr '\n' '|')"
  [[ "$names" == "Set up the gate environment|Set up Node|Install tools|Install dependencies|"* ]] \
    || echo "setup: the ${id} job's steps start ${names}, not the main job's gate environment, Node, tools and dependencies"
  code "$job" | grep -qF 'uses: actions/setup-node@' || echo "setup: the ${id} job does not set up Node"
  code "$job" | grep -qxF '          ./Scripts/install_tools.sh' || echo "setup: the ${id} job does not run Scripts/install_tools.sh"
  code "$job" | grep -qxF '        run: npm ci' || echo "setup: the ${id} job does not run npm ci"
}

# handover_findings <job file> <id>: pin 4.
handover_findings() {
  local job="$1" id="$2" step="Hand over the gate report" text
  [[ -s "$job" ]] || return 0
  text="$(step_text "$job" "$step")"
  [[ -n "$text" ]] || { echo "handover: the ${id} job has no step '${step}'"; return 0; }
  grep -qE '^        if: (always\(\)|\$\{\{ always\(\) \}\})[[:space:]]*$' <<< "$text" \
    || echo "handover: the ${id} job's '${step}' is not if: always(), so a red job hands nothing over"
  grep -qE 'uses: actions/upload-artifact@[0-9a-f]{40}  # v[0-9]' <<< "$text" \
    || echo "handover: the ${id} job does not upload with a commit-pinned actions/upload-artifact"
  grep -qxF "          name: quality-report-${id}" <<< "$text" \
    || echo "handover: the ${id} job does not upload the artifact quality-report-${id}"
}

# phase_calls <job file>: the run_ci_phase.sh call lines.
phase_calls() {
  code "$1" | grep -E '^[[:space:]]*\./Scripts/run_ci_phase\.sh ' || true
}

# job_findings <file>: pins 1 to 5.
job_findings() {
  local wf="$1" main iso rep calls id others needs listed
  main="${TMP}/main.yml"
  iso="${TMP}/isolation.yml"
  rep="${TMP}/report.yml"
  job_of "$wf" quality > "$main"
  job_of "$wf" isolation > "$iso"
  job_of "$wf" report > "$rep"

  setup_findings "$iso" isolation
  handover_findings "$main" quality
  handover_findings "$iso" isolation

  calls="$(phase_calls "$main")"
  [[ "$(grep -cE " \"[$]DETAILS\" main( |\$)" <<< "$calls")" == 2 ]] \
    || echo "main: both run_ci_phase.sh calls of the main job must end with the job name main, got: ${calls:-none}"
  if [[ -s "$iso" ]]; then
    calls="$(phase_calls "$iso")"
    [[ "$calls" == *"run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation" && "$(wc -l <<< "$calls" | tr -d ' ')" == 1 ]] \
      || echo "isolation: the isolation job must run exactly ./Scripts/run_ci_phase.sh pre \"\$ROWS\" \"\$DETAILS\" isolation, got: ${calls:-none}"
  fi
  if code "$wf" | grep -qE 'test_git_sandbox_isolation|test_step_summary_isolation'; then
    echo "isolation: a step names an isolation gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi
  if code "$wf" | grep -qE 'continue-on-error'; then
    echo "verdict: continue-on-error softens a failure, so Quality could be green with a red job"
  fi

  # pin 5
  if [[ ! -s "$rep" ]]; then
    echo "report: the file has no report job"
  else
    others="$(job_ids "$wf" | grep -vxE 'report|preview' || true)"
    needs="$(grep -E '^    needs:' "$rep" | head -1 | sed -E 's/^    needs:[[:space:]]*//' || true)"
    for id in $others; do
      grep -qE "(\[|, *)${id}(\]|,)" <<< "$needs" || echo "report: the gate job ${id} is not in the report job's needs:"
    done
    listed="$(tr -d '[] ' <<< "$needs" | tr ',' '\n')"
    for id in $listed; do
      grep -qx "$id" <<< "$others" || echo "report: ${id} in the report job's needs: is not a gate job"
    done
    grep -qE '^    if: (always\(\)|\$\{\{ always\(\) \}\})[[:space:]]*$' "$rep" \
      || echo "report: the report job is not if: always(), so a red gate job leaves no report"
    grep -qxF '    runs-on: macos-latest' "$rep" || echo "report: the report job is not on macos-latest"
    grep -qE 'uses: actions/download-artifact@[0-9a-f]{40}  # v[0-9]' "$rep" \
      || echo "report: the report job does not download with a commit-pinned actions/download-artifact"
    grep -qxF '          pattern: quality-report-*' "$rep" || echo "report: the report job does not download every quality-report-* hand-over"
    code "$rep" | grep -qE '^[[:space:]]*\./Scripts/merge_quality_report\.sh merge ' \
      || echo "report: the report job does not merge the hand-overs with Scripts/merge_quality_report.sh merge"
    code "$rep" | grep -qE 'QS_JOB_STATUS="?\$\(\./Scripts/merge_quality_report\.sh status' \
      || echo "report: QS_JOB_STATUS is not taken from Scripts/merge_quality_report.sh status of the jobs' results"
    code "$rep" | grep -qF './Scripts/render_quality_summary.sh' || echo "report: the report job does not render the summary"
    code "$rep" | grep -qF './Scripts/render_quality_report.sh' || echo "report: the report job does not render the gate table"
  fi
}

# groups_findings: pin 3.
groups_findings() {
  local rows labels
  [[ -f "$GROUPS_FILE" ]] || { echo "groups: ${GROUPS_FILE} does not exist"; return 0; }
  rows="$(grep -v '^#' "$GROUPS_FILE" | grep . | LC_ALL=C sort | tr '\n' ';')"
  labels='isolation|git sandbox isolation self-test;isolation|step summary isolation;'
  [[ "$rows" == "$labels" ]] \
    || echo "groups: ${GROUPS_FILE} must give the isolation job exactly the git sandbox isolation self-test and the step summary isolation gate, got: ${rows:-none}"
  while IFS='|' read -r _job label; do
    awk -F'|' -v l="$label" '$1 == l && $3 == "pre"' <(grep -v '^#' "$ORDER") | grep -q . \
      || echo "groups: '${label}' is no pre row of ${ORDER}"
  done < <(grep -v '^#' "$GROUPS_FILE" | grep .)
}

# verdict_findings: pin 7, the repository side.
verdict_findings() {
  local named
  named="$(grep -lE '^name: Quality[[:space:]]*$' .github/workflows/*.yml | tr '\n' ' ')"
  [[ "$named" == "${WORKFLOW} " ]] || echo "verdict: the workflows named Quality are ${named:-none}; Quality is one workflow, so the Release reads one conclusion"
  if [[ ! -f "$RELEASE_CHECK" ]]; then
    echo "verdict: ${RELEASE_CHECK} does not exist"
  else
    grep -qF -- '--json status,conclusion,url' "$RELEASE_CHECK" \
      || echo "verdict: ${RELEASE_CHECK} does not read the run's own status and conclusion"
    if grep -qE 'gh run view|--json[^|]*jobs|gh api[^|]*jobs' "$RELEASE_CHECK"; then
      echo "verdict: ${RELEASE_CHECK} reads a job, not the run: with several jobs it would judge one of them"
    fi
  fi
}

findings() {
  job_findings "$1"
  groups_findings
  verdict_findings
}

OUT="$(findings "$WORKFLOW")"
if [[ -z "$OUT" ]]; then
  echo "  ok: the real workflow holds every pin"
else
  fail "the real workflow breaks a pin:"$'\n'"$OUT"
fi

# mutant <name> <sed-expression> <finding>
mutant() {
  local file="${TMP}/$1.yml"
  sed "$2" "$WORKFLOW" > "$file"
  if cmp -s "$WORKFLOW" "$file"; then
    fail "the mutation $2 changed nothing: the proof of '$1' would be vacuous"
    return 0
  fi
  OUT="$(findings "$file")"
  if grep -qF -- "$3" <<< "$OUT"; then
    echo "  ok: mutation proof: $1"
  else
    fail "mutation proof: '$1' was not named '$3'. Findings: ${OUT:-none}"
  fi
}

I='/^  isolation:/,/^  report:/'
R='/^  report:/,/^  preview:/'
mutant "no isolation job" 's/^  isolation:/  isolation_gone:/' "job: the file has no isolation job"
mutant "isolation on another runner" "${I}"'s/runs-on: macos-latest/runs-on: ubuntu-latest/' "runs-on: the isolation job is not on macos-latest"
mutant "isolation without npm ci" "${I}"'s/run: npm ci/run: true/' "setup: the isolation job does not run npm ci"
mutant "isolation without Node" "${I}"'s/- name: Set up Node/- name: Set up something/' "setup: the isolation job's steps start"
mutant "isolation runs the main job's gates" "${I}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "isolation: the isolation job must run exactly"
mutant "main without its job name" "/^  quality:/,/^  isolation:/s/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\"/" "main: both run_ci_phase.sh calls of the main job"
mutant "a step naming an isolation gate" "${I}"'s#\./Scripts/install_tools.sh#./Scripts/install_tools.sh; ./Scripts/test_git_sandbox_isolation.sh#' "isolation: a step names an isolation gate itself"
mutant "isolation hand-over not always" "${I}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the isolation job's"
mutant "main hand-over under another name" '/^  quality:/,/^  isolation:/s/name: quality-report-quality/name: quality-report-other/' "handover: the quality job does not upload the artifact quality-report-quality"
mutant "report without isolation in needs" "${R}"'s/needs: \[quality, isolation\]/needs: [quality]/' "report: the gate job isolation is not in the report job's needs:"
mutant "report not always" "${R}"'s/^    if: always()/    if: success()/' "report: the report job is not if: always()"
mutant "report without the merge" "${R}"'s#merge_quality_report.sh merge#merge_quality_report.sh combine#' "report: the report job does not merge the hand-overs"
mutant "report status not merged" "${R}"'s#merge_quality_report.sh status#merge_quality_report.sh state#' "report: QS_JOB_STATUS is not taken from"
mutant "a softened job" "${I}"'s/^    runs-on: macos-latest/    continue-on-error: true\
    runs-on: macos-latest/' "verdict: continue-on-error softens a failure"

# expect_named <what> <finding>: OUT, the findings of the last mutant, names it.
expect_named() {
  if grep -qF -- "$2" <<< "$OUT"; then
    echo "  ok: mutation proof: ${1} is named"
  else
    fail "mutation proof: ${1} was not named '${2}'. Findings: ${OUT:-none}"
  fi
}

# The groups file and the release check are separate files: each mutant is a copy.
VERDICT_TMP="${TMP}/verdict"
mkdir -p "$VERDICT_TMP"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/none.txt" groups_findings)"
expect_named "no group file" "does not exist"
printf 'isolation|git sandbox isolation self-test\n' > "${VERDICT_TMP}/one.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/one.txt" groups_findings)"
expect_named "a group file with one gate" "must give the isolation job exactly"
printf 'isolation|git sandbox isolation self-test\nisolation|step summary isolation\nisolation|ghost\n' > "${VERDICT_TMP}/three.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/three.txt" groups_findings)"
expect_named "a group file with an extra gate" "must give the isolation job exactly"

mkdir -p "${VERDICT_TMP}/rq"
sed 's/--json status,conclusion,url/--json status,conclusion,url,jobs/' "$RELEASE_CHECK" > "${VERDICT_TMP}/rq/release_quality.sh"
OUT="$(RELEASE_CHECK="${VERDICT_TMP}/rq/release_quality.sh" verdict_findings)"
expect_named "a release check that reads a job" "reads a job, not the run"

selftest_end "the quality jobs pin found failures" "quality jobs pin (the real workflow holds every pin; each mutant is named)"
