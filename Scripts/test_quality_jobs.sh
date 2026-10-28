#!/usr/bin/env bash
# Scripts/test_quality_jobs.sh
#
# Pins the job layout of .github/workflows/quality.yml (forsgren#259, decision
# #260), forsgren's own: Quality runs its slowest gates in parallel jobs of ONE
# workflow, and stays one verdict. Steps 2 and 3: the isolation job and the
# browser job; forsgren#282: the lint job. The pins, each proved by a mutant of the real file that breaks it
# and must be named:
#   1. an isolation job exists, on macos-latest, with the same setup as the
#      main job: checkout at the same pin, the gate environment, Node, tool
#      install and npm ci, in that order
#   2. it runs Scripts/run_ci_phase.sh pre for the job `isolation_1` and the job
#      `isolation_2` (forsgren#426: the git sandbox isolation self-test in two
#      shards, one job each); the main
#      job passes `main` on both of its calls; no step of the file names the
#      two isolation gates itself (the order file and Scripts/ci_job_groups.txt
#      decide which gates a job runs, so one gate is never in two jobs or none)
#   3. Scripts/ci_job_groups.txt gives the two isolation jobs the git sandbox
#      isolation self-test, one shard each (forsgren#426: isolation_1 with
#      --shard 1/2, isolation_2 with --shard 2/2; forsgren#425: the step summary isolation
#      gate has the summary job), a row of the order file
#   3a. the summary job (forsgren#425) is the isolation job's twin: the same
#      setup, exactly run_ci_phase.sh pre for the job `summary`; the group file
#      gives it the step summary isolation gate alone and the isolation job the
#      git sandbox isolation self-test alone, so the two gates run in two
#      jobs and the longest of them is no longer both
#   3b. the browser job (step 3) has the same setup, runs run_ci_phase.sh pre,
#      then Scripts/build_site.sh (its own site build), then run_ci_phase.sh
#      post, both for the job `browser`; no step names a browser gate itself;
#      the group file gives it the browser gate self-test, its process self-test
#      (forsgren#386), the browser gate and
#      the browser gate (fixture site) with its self-test
#   4. the job hands its rows over: an upload of quality-report-isolation_1 and quality-report-isolation_2,
#      `if: always()`, and the main job does the same under quality-report-main
#   5. a report job needs EVERY gate job (not the preview), `if: always()`,
#      downloads the hand-overs, merges them with Scripts/merge_quality_report.sh
#      and renders the one Quality report (summary, then the gate table); its
#      QS_JOB_STATUS comes from the merge script's status of the jobs' results
#   6. the preview job needs every job, the report included (the generic pin of
#      Scripts/test_preview_workflow.sh, held here for the new jobs by name)
#   3c. the lint job (forsgren#282) has the same setup (on ubuntu-latest since
#      forsgren#427, installing from Scripts/required_tools_linux.txt) and runs exactly
#      run_ci_phase.sh pre for the job `lint`; no step names a lint gate
#      itself; the group file gives it actionlint, shellcheck, yamllint and
#      zizmor with their self-tests, so the main job no longer runs them (the
#      order file is unchanged: the rows keep their pre phase and place)
#   3d. the workflows job (forsgren#408) has the same setup and runs exactly
#      run_ci_phase.sh pre for the job `workflows`; no step names one of its
#      gates itself; the group file gives it the gates that read only the
#      workflows and the wiring of the gates (gate wiring, the checkout pins
#      and their mutations, the metrics, release, starter page, vulncheck,
#      auto-update and preview workflow pins and this pin), about 260 s that the
#      main job no longer runs, so the main job is no longer the critical path
#   3e. the quality_2 job (forsgren#447) has the same setup and runs exactly
#      run_ci_phase.sh pre for the job `quality_2`; no step names one of its
#      gates itself; the group file gives it twelve gates of the main job and
#      the Go coverage gate (it reads the profile the Go tests gate writes, so
#      the two stay together), about 306 s; the jobs' gates together are the
#      order file's rows, each once (union_findings)
#   5b. the report job takes every gate job's result into QS_JOB_STATUS:
#      a QS_<JOB>_RESULT from needs.<job>.result per gate job, each passed to
#      Scripts/merge_quality_report.sh status, so a red lint job is a failed
#      report, not a succeeded one
#   7. ONE Quality verdict: quality.yml is the only workflow named Quality, no
#      job or step softens a failure (continue-on-error), and
#      Scripts/release_quality.sh reads a run's own status and conclusion, which
#      GitHub sets from ALL its jobs (any failed or cancelled job is a
#      conclusion other than success), never a job
# A workflow is read with the awk readers of Scripts/lib_workflow_steps.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
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

# setup_findings <job file> <id> [runner] [install-command]: pin 1. The runner
# is macos-latest unless given, the install command Scripts/install_tools.sh.
# The lint job runs on ubuntu-latest (forsgren#427) and installs its four tools
# with Scripts/install_tools_linux.sh and the Linux list.
setup_findings() {
  local job="$1" id="$2" runner="${3:-macos-latest}" installer names want got
  installer="          ./${4:-Scripts/install_tools.sh}"
  if [[ ! -s "$job" ]]; then
    echo "job: the file has no ${id} job"
    return 0
  fi
  grep -qxF "    runs-on: ${runner}" "$job" || echo "runs-on: the ${id} job is not on ${runner}"
  want="$(pin_of "${TMP}/main.yml")"
  got="$(pin_of "$job")"
  [[ -n "$want" && "$got" == "$want" ]] || echo "pin of checkout: the ${id} job has ${got:-none}, the main job ${want:-none}"
  grep -qF 'fetch-depth: 0' "$job" || echo "checkout: the ${id} job does not fetch the full history, as the main job does"
  grep -qF 'persist-credentials: false' "$job" || echo "checkout: the ${id} job persists credentials"
  names="$(step_names "$job" | tr '\n' '|')"
  [[ "$names" == "Set up the gate environment|Set up Node|Install tools|Install dependencies|"* ]] \
    || echo "setup: the ${id} job's steps start ${names}, not the main job's gate environment, Node, tools and dependencies"
  code "$job" | has -F 'uses: actions/setup-node@' || echo "setup: the ${id} job does not set up Node"
  code "$job" | has -xF "$installer" || echo "setup: the ${id} job does not run ${4:-Scripts/install_tools.sh}"
  code "$job" | has -xF '        run: npm ci' || echo "setup: the ${id} job does not run npm ci"
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

# LINT_GATES: the scripts of the lint job's rows, which no step may name.
LINT_GATES='(test_)?check_(actionlint|shellcheck|yamllint|zizmor)|test_check_actionlint_forsgren'

# gates_of <job>: the scripts of that job's rows, read from the group file and
# the order file, so this file names none of them (a name written here would
# put that script in the closure of the step summary isolation gate).
gates_of() {
  local want="$1" job label
  while IFS='|' read -r job label _args; do
    [[ "$job" == "$want" ]] || continue
    awk -F'|' -v l="$label" '$1 == l { print $2 }' <(grep -v '^#' "$ORDER") | sed -E 's#^Scripts/##; s#\.sh$##'
  done < <(grep -v '^#' "$GROUPS_FILE" | grep .)
}

workflows_gates() { gates_of workflows; }

# phase_calls <job file>: the run_ci_phase.sh call lines.
phase_calls() {
  code "$1" | grep -E '^[[:space:]]*\./Scripts/run_ci_phase\.sh ' || true
}

# job_findings <file>: pins 1 to 5.
job_findings() {
  local wf="$1" main q2 lnt iso sum brw wfl rep calls id others needs listed pre_line build_line post_line n
  main="${TMP}/main.yml"
  q2="${TMP}/quality_2.yml"
  lnt="${TMP}/lint.yml"
  sum="${TMP}/summary.yml"
  brw="${TMP}/browser.yml"
  wfl="${TMP}/workflows.yml"
  rep="${TMP}/report.yml"
  job_of "$wf" quality > "$main"
  job_of "$wf" quality_2 > "$q2"
  job_of "$wf" lint > "$lnt"
  for n in 1 2; do
    job_of "$wf" "isolation_${n}" > "${TMP}/isolation_${n}.yml"
  done
  job_of "$wf" summary > "$sum"
  job_of "$wf" browser > "$brw"
  job_of "$wf" workflows > "$wfl"
  job_of "$wf" report > "$rep"

  setup_findings "$q2" quality_2
  setup_findings "$lnt" lint ubuntu-latest "Scripts/install_tools_linux.sh Scripts/required_tools_linux.txt"
  for n in 1 2; do
    setup_findings "${TMP}/isolation_${n}.yml" "isolation_${n}"
  done
  setup_findings "$sum" summary
  setup_findings "$brw" browser
  setup_findings "$wfl" workflows
  handover_findings "$main" quality
  handover_findings "$q2" quality_2
  handover_findings "$lnt" lint
  for n in 1 2; do
    handover_findings "${TMP}/isolation_${n}.yml" "isolation_${n}"
  done
  handover_findings "$sum" summary
  handover_findings "$brw" browser
  handover_findings "$wfl" workflows

  if [[ -s "$brw" ]]; then
    calls="$(phase_calls "$brw")"
    [[ "$(grep -cE " \"[$]DETAILS\" browser( |\$)" <<< "$calls")" == 2 && "$(wc -l <<< "$calls" | tr -d ' ')" == 2 ]] \
      || echo "browser: the browser job must run run_ci_phase.sh pre and post, each ending with the job name browser, got: ${calls:-none}"
    pre_line="$(line_of "$brw" './Scripts/run_ci_phase.sh pre')"
    build_line="$(line_of "$brw" './Scripts/build_site.sh')"
    post_line="$(line_of "$brw" './Scripts/run_ci_phase.sh post')"
    if [[ -z "$build_line" ]] || ! later "$build_line" "$pre_line" || ! later "$post_line" "$build_line"; then
      echo "browser: the browser job must run PRE, then its own site build (Scripts/build_site.sh), then POST: the browser gate reads the built site"
    fi
  fi
  if code "$wf" | has -E 'test_gate_browser|gate_browser'; then
    echo "browser: a step names a browser gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi

  calls="$(phase_calls "$main")"
  [[ "$(grep -cE " \"[$]DETAILS\" main( |\$)" <<< "$calls")" == 2 ]] \
    || echo "main: both run_ci_phase.sh calls of the main job must end with the job name main, got: ${calls:-none}"
  for n in 1 2; do
    iso="${TMP}/isolation_${n}.yml"
    if [[ -s "$iso" ]]; then
      calls="$(phase_calls "$iso")"
      [[ "$calls" == *"run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation_${n}" && "$(wc -l <<< "$calls" | tr -d ' ')" == 1 ]] \
        || echo "isolation: the isolation_${n} job must run exactly ./Scripts/run_ci_phase.sh pre \"\$ROWS\" \"\$DETAILS\" isolation_${n}, got: ${calls:-none}"
    fi
  done
  if [[ -s "$sum" ]]; then
    calls="$(phase_calls "$sum")"
    [[ "$calls" == *"run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" summary" && "$(wc -l <<< "$calls" | tr -d ' ')" == 1 ]] \
      || echo "summary: the summary job must run exactly ./Scripts/run_ci_phase.sh pre \"\$ROWS\" \"\$DETAILS\" summary, got: ${calls:-none}"
  fi
  if [[ -s "$q2" ]]; then
    calls="$(phase_calls "$q2")"
    [[ "$calls" == *"run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" quality_2" && "$(wc -l <<< "$calls" | tr -d ' ')" == 1 ]] \
      || echo "quality_2: the quality_2 job must run exactly ./Scripts/run_ci_phase.sh pre \"\$ROWS\" \"\$DETAILS\" quality_2, got: ${calls:-none}"
  fi
  if code "$wf" | has -E "($(gates_of quality_2 | paste -sd'|' -))"; then
    echo "quality_2: a step names a quality_2 gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi
  if [[ -s "$lnt" ]]; then
    calls="$(phase_calls "$lnt")"
    [[ "$calls" == *"run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" lint" && "$(wc -l <<< "$calls" | tr -d ' ')" == 1 ]] \
      || echo "lint: the lint job must run exactly ./Scripts/run_ci_phase.sh pre \"\$ROWS\" \"\$DETAILS\" lint, got: ${calls:-none}"
  fi
  if [[ -s "$wfl" ]]; then
    calls="$(phase_calls "$wfl")"
    [[ "$calls" == *"run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" workflows" && "$(wc -l <<< "$calls" | tr -d ' ')" == 1 ]] \
      || echo "workflows: the workflows job must run exactly ./Scripts/run_ci_phase.sh pre \"\$ROWS\" \"\$DETAILS\" workflows, got: ${calls:-none}"
  fi
  if code "$wf" | has -E "($(workflows_gates | paste -sd'|' -))"; then
    echo "workflows: a step names a workflows gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi
  if code "$wf" | has -E "$LINT_GATES"; then
    echo "lint: a step names a lint gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi
  if code "$wf" | has -E "($( { gates_of isolation_1; gates_of isolation_2; gates_of summary; } | paste -sd'|' -))"; then
    echo "isolation: a step names an isolation gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi
  if code "$wf" | has -E 'continue-on-error'; then
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
    code "$rep" | has -E '^[[:space:]]*\./Scripts/merge_quality_report\.sh merge ' \
      || echo "report: the report job does not merge the hand-overs with Scripts/merge_quality_report.sh merge"
    code "$rep" | has -E 'QS_JOB_STATUS="?\$\(\./Scripts/merge_quality_report\.sh status' \
      || echo "report: QS_JOB_STATUS is not taken from Scripts/merge_quality_report.sh status of the jobs' results"
    status_findings "$rep" "$others"
    code "$rep" | has -F './Scripts/render_quality_summary.sh' || echo "report: the report job does not render the summary"
    code "$rep" | has -F './Scripts/render_quality_report.sh' || echo "report: the report job does not render the gate table"
  fi
}

# status_findings <report job file> <gate job ids>: pin 5b. Each gate job's
# result reaches the status call: QS_<ID>_RESULT from needs.<id>.result, and
# the status call passes "$QS_<ID>_RESULT".
status_findings() {
  local rep="$1" ids="$2" id var call
  # The call may continue on the next lines after a trailing backslash (a line
  # of 200 characters or more breaks the yamllint line-length rule, forsgren#426).
  call="$(code "$rep" | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta' | grep -E 'merge_quality_report\.sh status' || true)"
  for id in $ids; do
    var="QS_$(tr '[:lower:]-' '[:upper:]_' <<< "$id")_RESULT"
    grep -qxF "          ${var}: ${DOLLAR}{{ needs.${id}.result }}" "$rep" \
      || echo "report: the report job has no ${var} from needs.${id}.result, so the gate job ${id} is not in the run's status"
    grep -qF "\"${DOLLAR}${var}\"" <<< "$call" \
      || echo "report: the status call does not pass \"\$${var}\", so a red ${id} job would not make the report's status failed"
  done
}

# groups_findings: pin 3.
# Q2_ROWS: the gates the quality_2 job runs (forsgren#447): the Go lint pair,
# the Go tests with the Go coverage gate that reads their profile
# (.build/go-coverage.out), and the long tail of the main job, all PRE rows
# that need no built site.
Q2_ROWS=('quality_2|Go lint self-test' 'quality_2|Go lint' 'quality_2|Go tests' 'quality_2|Go coverage'
  'quality_2|browser gate inputs self-test' 'quality_2|golden pages'
  'quality_2|git sandbox isolation scope self-test' 'quality_2|exit-trap completion behaviour'
  'quality_2|CI phase runner self-test' 'quality_2|quality-run summary'
  'quality_2|markdown-links self-test' 'quality_2|HTMLHint self-test'
  'quality_2|html duplication, generated page self-test')

groups_findings() {
  local rows labels
  labels="$(printf '%s\n' 'isolation_1|git sandbox isolation self-test|--shard 1/2' 'isolation_2|git sandbox isolation self-test|--shard 2/2' 'summary|step summary isolation' \
    'browser|browser gate self-test' 'browser|browser gate process self-test' 'browser|browser gate' 'browser|browser gate (fixture site) self-test' 'browser|browser gate (fixture site)' \
    'lint|actionlint self-test' 'lint|actionlint forsgren cases self-test' 'lint|actionlint' \
    'lint|shellcheck self-test' 'lint|shellcheck' 'lint|yamllint self-test' 'lint|yamllint' \
    'lint|zizmor self-test' 'lint|zizmor' \
    "${Q2_ROWS[@]}" \
    'workflows|gate wiring' 'workflows|mutation: checkout pins' 'workflows|metrics workflow' 'workflows|release workflow' \
    'workflows|starter page workflow' 'workflows|quality jobs pin' 'workflows|preview workflow' \
    'workflows|vulncheck workflow' 'workflows|auto-update workflow' \
    | LC_ALL=C sort | tr '\n' ';')"
  [[ -f "$GROUPS_FILE" ]] || { echo "groups: ${GROUPS_FILE} does not exist"; return 0; }
  rows="$(grep -v '^#' "$GROUPS_FILE" | grep . | LC_ALL=C sort | tr '\n' ';')"
  [[ "$rows" == "$labels" ]] \
    || echo "groups: ${GROUPS_FILE} must give the two isolation jobs the git sandbox isolation self-test, one shard each (isolation_1 with --shard 1/2, isolation_2 with --shard 2/2), the summary job the step summary isolation gate, the browser job the two browser gates and their self-tests, the lint job actionlint, shellcheck, yamllint and zizmor with their self-tests, the quality_2 job the twelve gates of forsgren#447 and the Go coverage gate, and the workflows job gate wiring, the checkout pins mutations and the pins of the metrics, release, starter page, vulncheck, auto-update and preview workflows and of this job layout, got: ${rows:-none}"
  while IFS='|' read -r job label _args; do
    awk -F'|' -v l="$label" '$1 == l && ($3 == "pre" || $3 == "post")' <(grep -v '^#' "$ORDER") | has . \
      || echo "groups: '${label}' is no pre or post row of ${ORDER}"
    if [[ "$job" == lint ]] && ! awk -F'|' -v l="$label" '$1 == l && $3 == "pre"' <(grep -v '^#' "$ORDER") | has .; then
      echo "groups: the lint gate '${label}' is no pre row of ${ORDER}; the lint rows keep their pre phase"
    fi
  done < <(grep -v '^#' "$GROUPS_FILE" | grep .)
  union_findings
}

# union_findings: the jobs' gates together are the order file's pre and post
# rows, each once (forsgren#447): the main job runs every row the group file
# does not list, so the main job's rows and the group file's labels (a sharded
# label once) must be the order file's rows, none in two jobs and none in no
# job. A quality_2 row must also be in no other job.
union_findings() {
  local all grouped main both q2dup
  all="$(grep -v '^#' "$ORDER" | grep . | awk -F'|' '$3 == "pre" || $3 == "post" { print $1 }' | LC_ALL=C sort)"
  grouped="$(grep -v '^#' "$GROUPS_FILE" | grep . | cut -d'|' -f2 | LC_ALL=C sort -u)"
  main="$(LC_ALL=C comm -23 <(printf '%s\n' "$all" | LC_ALL=C sort -u) <(printf '%s\n' "$grouped"))"
  both="$( { printf '%s\n' "$main"; printf '%s\n' "$grouped"; } | grep . | LC_ALL=C sort)"
  [[ "$both" == "$(printf '%s\n' "$all" | LC_ALL=C sort)" ]] \
    || echo "union: the main job's gates and the group file's gates are not the order file's pre and post rows, each once"
  q2dup="$(grep -v '^#' "$GROUPS_FILE" | grep . | awk -F'|' '{ n[$2]++; if ($1 == "quality_2") q[$2] = 1 } END { for (l in q) if (n[l] > 1) print l }')"
  [[ -z "$q2dup" ]] || echo "union: a quality_2 gate is also in another job: ${q2dup}"
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

Q='/^  quality:/,/^  quality_2:/'
L='/^  lint:/,/^  isolation_1:/'
I1='/^  isolation_1:/,/^  isolation_2:/'
I2='/^  isolation_2:/,/^  summary:/'
Q2='/^  quality_2:/,/^  lint:/'
S='/^  summary:/,/^  browser:/'
B='/^  browser:/,/^  workflows:/'
W='/^  workflows:/,/^  report:/'
R='/^  report:/,/^  preview:/'
for n in 1 2; do
  case "$n" in 1) I="$I1" ;; *) I="$I2" ;; esac
  mutant "no isolation_${n} job" "s/^  isolation_${n}:/  isolation_${n}_gone:/" "job: the file has no isolation_${n} job"
  mutant "isolation_${n} on another runner" "${I}"'s/runs-on: macos-latest/runs-on: ubuntu-latest/' "runs-on: the isolation_${n} job is not on macos-latest"
  mutant "isolation_${n} without npm ci" "${I}"'s/run: npm ci/run: true/' "setup: the isolation_${n} job does not run npm ci"
  mutant "isolation_${n} without Node" "${I}"'s/- name: Set up Node/- name: Set up something/' "setup: the isolation_${n} job's steps start"
  mutant "isolation_${n} runs the main job's gates" "${I}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation_${n}/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "isolation: the isolation_${n} job must run exactly"
  mutant "isolation_${n} runs the other shard's job" "${I}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation_${n}/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation_$((3 - n))/" "isolation: the isolation_${n} job must run exactly"
  mutant "isolation_${n} hand-over not always" "${I}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the isolation_${n} job's"
  mutant "isolation_${n} hand-over under another name" "${I}"'s/name: quality-report-isolation_'"${n}"'/name: quality-report-other/' "handover: the isolation_${n} job does not upload the artifact quality-report-isolation_${n}"
  mutant "report without isolation_${n} in needs" "${R}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser, workflows\]/needs: [quality, quality_2, lint, '"$( [[ $n == 1 ]] && echo isolation_2 || echo isolation_1 )"', summary, browser, workflows]/' "report: the gate job isolation_${n} is not in the report job's needs:"
  mutant "report without the isolation_${n} result" "${R}"'{/QS_ISOLATION_'"${n}"'_RESULT:/d;}' "report: the report job has no QS_ISOLATION_${n}_RESULT from needs.isolation_${n}.result"
  mutant "status without the isolation_${n} result" "${R}"'s/ "[$]QS_ISOLATION_'"${n}"'_RESULT"//' "report: the status call does not pass"
done
mutant "summary on another runner" "${S}"'s/runs-on: macos-latest/runs-on: ubuntu-latest/' "runs-on: the summary job is not on macos-latest"
mutant "summary without npm ci" "${S}"'s/run: npm ci/run: true/' "setup: the summary job does not run npm ci"
mutant "summary without Node" "${S}"'s/- name: Set up Node/- name: Set up something/' "setup: the summary job's steps start"
mutant "no summary job" 's/^  summary:/  summary_gone:/' "job: the file has no summary job"
mutant "summary runs the main job's gates" "${S}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" summary/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "summary: the summary job must run exactly"
FIRST_SUM_GATE="$(gates_of summary | sed -n 1p)"
mutant "a step naming the summary gate" "${S}"'s#\./Scripts/install_tools.sh#./Scripts/install_tools.sh; ./Scripts/'"${FIRST_SUM_GATE}"'.sh#' "isolation: a step names an isolation gate itself"
mutant "summary hand-over not always" "${S}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the summary job's"
mutant "summary hand-over under another name" "${S}"'s/name: quality-report-summary/name: quality-report-other/' "handover: the summary job does not upload the artifact quality-report-summary"
mutant "report without summary in needs" "${R}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser, workflows\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, browser, workflows]/' "report: the gate job summary is not in the report job's needs:"
mutant "report without the summary result" "${R}"'{/QS_SUMMARY_RESULT:/d;}' "report: the report job has no QS_SUMMARY_RESULT from needs.summary.result"
mutant "status without the summary result" "${R}"'s/ "[$]QS_SUMMARY_RESULT"//' "report: the status call does not pass"
mutant "main without its job name" "${Q}s/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\"/" "main: both run_ci_phase.sh calls of the main job"
FIRST_ISO_GATE="$(gates_of isolation_1 | sed -n 1p)"
mutant "a step naming an isolation gate" "${I1}"'s#\./Scripts/install_tools.sh#./Scripts/install_tools.sh; ./Scripts/'"${FIRST_ISO_GATE}"'.sh#' "isolation: a step names an isolation gate itself"
mutant "main hand-over under another name" "${Q}"'s/name: quality-report-quality/name: quality-report-other/' "handover: the quality job does not upload the artifact quality-report-quality"
mutant "report without browser in needs" "${R}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser, workflows\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, summary, workflows]/' "report: the gate job browser is not in the report job's needs:"
mutant "report without lint in needs" "${R}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser, workflows\]/needs: [quality, quality_2, isolation_1, isolation_2, summary, browser, workflows]/' "report: the gate job lint is not in the report job's needs:"
mutant "report without the lint result" "${R}"'{/QS_LINT_RESULT:/d;}' "report: the report job has no QS_LINT_RESULT from needs.lint.result"
mutant "status without the lint result" "${R}"'s/ "[$]QS_LINT_RESULT"//' "report: the status call does not pass"
mutant "no lint job" 's/^  lint:/  lint_gone:/' "job: the file has no lint job"
mutant "lint on another runner" "${L}"'s/runs-on: ubuntu-latest/runs-on: macos-latest/' \
  "runs-on: the lint job is not on ubuntu-latest"
mutant "lint on another Linux image" "${L}"'s/runs-on: ubuntu-latest/runs-on: ubuntu-22.04/' \
  "runs-on: the lint job is not on ubuntu-latest"
mutant "lint using the Homebrew installer" "${L}"'s#install_tools_linux\.sh#install_tools.sh#' \
  "setup: the lint job does not run Scripts/install_tools_linux.sh Scripts/required_tools_linux.txt"
mutant "lint without npm ci" "${L}"'s/run: npm ci/run: true/' "setup: the lint job does not run npm ci"
mutant "lint runs the main job's gates" "${L}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" lint/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "lint: the lint job must run exactly"
mutant "a step naming a lint gate" \
  "${L}"'s#\./Scripts/install_tools_linux.sh#./Scripts/install_tools_linux.sh; ./Scripts/check_shellcheck.sh#' \
  "lint: a step names a lint gate itself"
mutant "lint hand-over not always" "${L}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the lint job's"
mutant "lint hand-over under another name" "${L}"'s/name: quality-report-lint/name: quality-report-other/' "handover: the lint job does not upload the artifact quality-report-lint"
mutant "report without quality_2 in needs" "${R}"'s/needs: \[quality, quality_2, lint,/needs: [quality, lint,/' "report: the gate job quality_2 is not in the report job's needs:"
mutant "report without the quality_2 result" "${R}"'{/QS_QUALITY_2_RESULT:/d;}' "report: the report job has no QS_QUALITY_2_RESULT from needs.quality_2.result"
mutant "status without the quality_2 result" "${R}"'s/ "[$]QS_QUALITY_2_RESULT"//' "report: the status call does not pass"
mutant "no quality_2 job" 's/^  quality_2:/  quality_2_gone:/' "job: the file has no quality_2 job"
mutant "quality_2 on another runner" "${Q2}"'s/runs-on: macos-latest/runs-on: ubuntu-latest/' "runs-on: the quality_2 job is not on macos-latest"
mutant "quality_2 without npm ci" "${Q2}"'s/run: npm ci/run: true/' "setup: the quality_2 job does not run npm ci"
mutant "quality_2 runs the main job's gates" "${Q2}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" quality_2/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "quality_2: the quality_2 job must run exactly"
FIRST_Q2_GATE="$(gates_of quality_2 | sed -n 1p)"
mutant "a step naming a quality_2 gate" "${Q2}"'s#\./Scripts/install_tools.sh#./Scripts/install_tools.sh; ./Scripts/'"${FIRST_Q2_GATE}"'.sh#' "quality_2: a step names a quality_2 gate itself"
mutant "quality_2 hand-over not always" "${Q2}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the quality_2 job's"
mutant "quality_2 hand-over under another name" "${Q2}"'s/name: quality-report-quality_2/name: quality-report-other/' "handover: the quality_2 job does not upload the artifact quality-report-quality_2"
mutant "no browser job" 's/^  browser:/  browser_gone:/' "job: the file has no browser job"
mutant "browser on another runner" "${B}"'s/runs-on: macos-latest/runs-on: ubuntu-latest/' "runs-on: the browser job is not on macos-latest"
mutant "browser without npm ci" "${B}"'s/run: npm ci/run: true/' "setup: the browser job does not run npm ci"
mutant "browser without its site build" "${B}"'s#\./Scripts/build_site.sh#./Scripts/other.sh#' "browser: the browser job must run PRE, then its own site build"
mutant "browser running the main job's gates" "${B}s/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "browser: the browser job must run run_ci_phase.sh pre and post"
mutant "a step naming a browser gate" "${B}"'s#\./Scripts/install_tools.sh#./Scripts/install_tools.sh; ./Scripts/gate_browser.sh#' "browser: a step names a browser gate itself"
mutant "browser hand-over not always" "${B}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the browser job's"
mutant "report without workflows in needs" "${R}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser, workflows\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, summary, browser]/' "report: the gate job workflows is not in the report job's needs:"
mutant "report without the workflows result" "${R}"'{/QS_WORKFLOWS_RESULT:/d;}' "report: the report job has no QS_WORKFLOWS_RESULT from needs.workflows.result"
mutant "status without the workflows result" "${R}"'s/ "[$]QS_WORKFLOWS_RESULT"//' "report: the status call does not pass"
mutant "no workflows job" 's/^  workflows:/  workflows_gone:/' "job: the file has no workflows job"
mutant "workflows on another runner" "${W}"'s/runs-on: macos-latest/runs-on: ubuntu-latest/' "runs-on: the workflows job is not on macos-latest"
mutant "workflows without npm ci" "${W}"'s/run: npm ci/run: true/' "setup: the workflows job does not run npm ci"
mutant "workflows runs the main job's gates" "${W}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" workflows/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "workflows: the workflows job must run exactly"
FIRST_WF_GATE="$(workflows_gates | sed -n 1p)"
mutant "a step naming a workflows gate" "${W}"'s#\./Scripts/install_tools.sh#./Scripts/install_tools.sh; ./Scripts/'"${FIRST_WF_GATE}"'.sh#' "workflows: a step names a workflows gate itself"
mutant "workflows hand-over not always" "${W}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the workflows job's"
mutant "workflows hand-over under another name" "${W}"'s/name: quality-report-workflows/name: quality-report-other/' "handover: the workflows job does not upload the artifact quality-report-workflows"
mutant "report not always" "${R}"'s/^    if: always()/    if: success()/' "report: the report job is not if: always()"
mutant "report without the merge" "${R}"'s#merge_quality_report.sh merge#merge_quality_report.sh combine#' "report: the report job does not merge the hand-overs"
mutant "report status not merged" "${R}"'s#merge_quality_report.sh status#merge_quality_report.sh state#' "report: QS_JOB_STATUS is not taken from"
mutant "a softened job" "${I1}"'s/^    runs-on: macos-latest/    continue-on-error: true\
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
expect_named "a group file with one gate" "must give the two isolation jobs"
printf 'isolation|git sandbox isolation self-test\nsummary|step summary isolation\nisolation|ghost\n' > "${VERDICT_TMP}/three.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/three.txt" groups_findings)"
expect_named "a group file with an extra gate" "must give the two isolation jobs"
sed 's#^isolation_2|\(.*\)|--shard 2/2$#isolation_2|\1|--shard 1/2#' "$GROUPS_FILE" > "${VERDICT_TMP}/twice.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/twice.txt" groups_findings)"
expect_named "a group file whose two isolation jobs run the same shard" "one shard each"
sed 's#|--shard 2/2$##' "$GROUPS_FILE" > "${VERDICT_TMP}/noargs.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/noargs.txt" groups_findings)"
expect_named "a group file whose second isolation job runs no shard" "one shard each"
grep -v '^lint|' "$GROUPS_FILE" > "${VERDICT_TMP}/nolint.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nolint.txt" groups_findings)"
expect_named "a group file that leaves the lint rows in the main job" "the lint job actionlint, shellcheck, yamllint and zizmor"
grep -v '^summary|' "$GROUPS_FILE" > "${VERDICT_TMP}/nosummary.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nosummary.txt" groups_findings)"
expect_named "a group file that leaves the step summary gate in the main job" "the summary job the step summary isolation gate"
grep -v '^workflows|' "$GROUPS_FILE" > "${VERDICT_TMP}/noworkflows.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/noworkflows.txt" groups_findings)"
expect_named "a group file that leaves the workflow pins in the main job" "and the workflows job gate wiring"
grep -v '^quality_2|' "$GROUPS_FILE" > "${VERDICT_TMP}/noq2.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/noq2.txt" groups_findings)"
expect_named "a group file that leaves the quality_2 gates in the main job" "the quality_2 job the twelve gates"
grep -v '^quality_2|Go coverage$' "$GROUPS_FILE" > "${VERDICT_TMP}/nocov.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nocov.txt" groups_findings)"
expect_named "a group file that leaves Go coverage apart from Go tests" "the quality_2 job the twelve gates"
{ cat "$GROUPS_FILE"; echo 'lint|golden pages'; } > "${VERDICT_TMP}/twojobs.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/twojobs.txt" groups_findings)"
expect_named "a gate in quality_2 and in another job" "union: a quality_2 gate is also in another job"
mkdir -p "${VERDICT_TMP}/order"
sed 's/^shellcheck|Scripts\/check_shellcheck.sh|pre|/shellcheck|Scripts\/check_shellcheck.sh|post|/' "$ORDER" > "${VERDICT_TMP}/order/gate_report_order.txt"
OUT="$(ORDER="${VERDICT_TMP}/order/gate_report_order.txt" groups_findings)"
expect_named "a lint row moved to post" "the lint gate 'shellcheck' is no pre row"

mkdir -p "${VERDICT_TMP}/rq"
sed 's/--json status,conclusion,url/--json status,conclusion,url,jobs/' "$RELEASE_CHECK" > "${VERDICT_TMP}/rq/release_quality.sh"
OUT="$(RELEASE_CHECK="${VERDICT_TMP}/rq/release_quality.sh" verdict_findings)"
expect_named "a release check that reads a job" "reads a job, not the run"

selftest_end "the quality jobs pin found failures" "quality jobs pin (the real workflow holds every pin; each mutant is named)"
