#!/usr/bin/env bash
# Scripts/test_quality_jobs.sh
#
# Pins the job layout of .github/workflows/quality.yml (forsgren#259, decision
# #260) and, since forsgren#686, of .github/workflows/selftests.yml, forsgren's
# own: Quality runs the real gates in parallel jobs of ONE workflow and stays
# one verdict; Self-tests runs the self-test rows in jobs of its own, gates
# nothing and opens one issue when it is red. The pins, each proved by a mutant
# of the real file that breaks it and must be named:
#   1. every gate job of both workflows has the main job's setup: checkout at
#      the same pin with the full history, the gate environment, Node, its tool
#      install and npm ci, in that order; the Linux jobs (ubuntu-latest: lint,
#      workflows and browser_3 in Quality, selftest_linux, isolation_1,
#      isolation_2, summary, browser_1 and browser_2 in Self-tests) start with
#      actions/setup-go reading go.mod, cache on, pinned to a commit
#      (forsgren#573); the macOS jobs (macos-latest: quality and quality_2 in
#      Quality, selftest_mac_1 and selftest_mac_2 in Self-tests) install with
#      Scripts/install_tools.sh
#   2. each job runs exactly its own `run_ci_phase.sh <phase> "$ROWS" "$DETAILS"
#      <job>` calls: the main job (id quality) `main` in both phases; browser_3
#      (no PRE row since forsgren#686) its own site build, then post; every
#      other job one pre call; no step of either file names a gate itself (the
#      order file and Scripts/ci_job_groups.txt decide which gates a job runs,
#      so one gate is never in two jobs or none)
#   3. Scripts/ci_job_groups.txt gives each job its rows (the list below):
#      the git sandbox isolation self-test in two shards (isolation_1 --shard
#      1/2, isolation_2 --shard 2/2, forsgren#426), the step summary isolation
#      gate to summary (forsgren#425), the browser gate self-test in two shards
#      to browser_1 and browser_2 with the fixture site self-test in browser_1
#      and the process self-test in browser_2 (forsgren#641, #686), the two
#      browser gates to browser_3, the lint gates to lint, the workflow pins to
#      workflows, five long gates to quality_2 (Go coverage with the Go tests
#      whose profile it reads), and the self-test rows to selftest_mac_1,
#      selftest_mac_2 and selftest_linux by the runner they ran on before
#      forsgren#686; every gate is in exactly one job (union_findings: a gate
#      left out of its group, a row twice and a gate in two jobs are each
#      named), a job that runs only its pre rows holds pre rows only, browser_3
#      post rows only (pin 8 of Scripts/test_gate_wiring.sh holds each row to
#      the workflow its kind names)
#   3g. the tools each job installs from its own list
#      (Scripts/required_tools_<job>_gates.txt, forsgren#447 step 4): quality_2,
#      selftest_mac_1 go, jq and node, selftest_mac_2 the main job's five (read
#      as the main job's gates are), browser_1 go and
#      node, browser_2 node, browser_3 go and node; no gate of a job names a
#      tool of Scripts/required_tools.txt that its list lacks (a missing tool
#      must fail the gate, not skip it); lint and selftest_linux install the
#      four Linux lint tools (Scripts/required_tools_linux.txt), workflows,
#      isolation and summary Scripts/required_tools_linux_gates.txt; the main
#      job its list Scripts/required_tools_quality_gates.txt: gitleaks, go, jq,
#      languagetool and node (main_tools_findings: no script a main gate
#      reaches, other than another job's gate, runs a tool the list lacks)
#   3h. the shards of the browser gate self-test (forsgren#641): with
#      --shard N/M --list each shard lists at least one case or proof, the
#      shards together list every one of the whole run once, and every case_
#      and mutant_ function and SERIAL_CASES id of the script is listed
#   4. each job hands its rows over: an upload of quality-report-<job id>,
#      `if: always()`, with a commit-pinned actions/upload-artifact
#   5. each workflow's report job needs EVERY gate job of its workflow (not the
#      preview, not the failure issue, not report_start), `if: always()`, on ubuntu-latest,
#      downloads every quality-report-* hand-over, cuts the order and group
#      files to exactly its workflow's jobs with Scripts/merge_quality_report.sh
#      view, merges, renders the gate table on that view and ends with the
#      verdict of every gate job's result (QS_<JOB>_RESULT from
#      needs.<job>.result); Quality's report also renders the summary on the
#      view and takes QS_JOB_STATUS from the merge script's status of every
#      job's result (5b)
#   6. the preview job of quality.yml needs every job of Quality, the report
#      included (Scripts/test_preview_workflow.sh holds the generic pin)
#   7. ONE Quality verdict: quality.yml is the only workflow named Quality, no
#      job or step of either workflow softens a failure (continue-on-error),
#      and Scripts/release_quality.sh reads a run's own status and conclusion,
#      which GitHub sets from ALL its jobs, never a job
#   9. the failure issue of Self-tests (forsgren#686): a job that needs every
#      gate job and the report, runs `if: failure() && github.event_name ==
#      'push'`, alone holds `issues: write` (the workflow stays contents: read)
#      and runs Scripts/open_selftests_failure_issue.sh with the job's token
# A workflow is read with the awk readers of Scripts/lib_workflow_steps.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_gate_select.sh
source Scripts/lib_gate_select.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
# shellcheck source=Scripts/lib_parallel_mutants.sh
source Scripts/lib_parallel_mutants.sh
selftest_begin "quality jobs pin"

# The folder the job files of one findings run are cut into (job_findings): the temp
# root for the real file, a folder of its own for each mutant (forsgren#569), so
# mutants run side by side never share a path.
JOBS_TMP="$TMP"
WORKFLOW=".github/workflows/quality.yml"
SELFTESTS=".github/workflows/selftests.yml"
GROUPS_FILE="Scripts/ci_job_groups.txt"
ORDER="Scripts/gate_report_order.txt"
RELEASE_CHECK="Scripts/release_quality.sh"
[[ -f "$WORKFLOW" ]] || selftest_abort "${WORKFLOW} does not exist"
[[ -f "$SELFTESTS" ]] || selftest_abort "${SELFTESTS} does not exist"

DOLLAR='$'

# The jobs of each workflow that run gates (the report, preview and failure
# issue jobs run none).
QUALITY_GATE_JOBS="quality quality_2 lint browser_3 workflows"
SELFTEST_GATE_JOBS="selftest_mac_1 selftest_mac_2 selftest_linux isolation_1 isolation_2 summary browser_1 browser_2"

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

# go_setup_findings <job file> <id> <step names>: forsgren#573. A Linux job
# gets the go.mod toolchain ONCE, cached and verified, by actions/setup-go
# (go-version-file: go.mod, its module and build cache on: no `cache: false`),
# as the first step after the checkout and before the gate environment, so no
# gate downloads the toolchain from the network (a sum.golang.org lookup failure
# made go mod tidy red in run 40811450730). The gate environment step still
# exports GOTOOLCHAIN from go.mod's toolchain line, which now names the Go that
# setup-go installed, so go finds it locally. The step has no continue-on-error:
# a failed setup is a red job, never a skipped gate.
go_setup_findings() {
  local job="$1" id="$2" names="$3" step
  [[ "$names" == "Set up Go|Set up the gate environment|Set up Node|Install tools|Install dependencies|"* ]] \
    || echo "setup: the ${id} job's steps start ${names}, not Set up Go, the gate environment, Node, tools and dependencies"
  step="$(awk '/^      - name: Set up Go$/ { on = 1; print; next } on && /^      - / { exit } on { print }' "$job")"
  grep -qE '^        uses: actions/setup-go@[0-9a-f]{40}( |$)' <<< "$step" \
    || echo "setup-go: the ${id} job's Set up Go step does not use actions/setup-go pinned to a full commit"
  grep -qxF '          go-version-file: go.mod' <<< "$step" \
    || echo "setup-go: the ${id} job's Set up Go step does not read go.mod (go-version-file: go.mod)"
  if grep -qE '^          cache: *false' <<< "$step"; then
    echo "setup-go: the ${id} job's Set up Go step turns the cache off"
  fi
  if grep -q 'continue-on-error' <<< "$step"; then
    echo "setup-go: the ${id} job's Set up Go step has continue-on-error, so a failed setup would not be a red job"
  fi
  return 0
}

# setup_findings <job file> <id> [runner] [install-command]: pin 1. The runner
# is macos-latest unless given, the install command Scripts/install_tools.sh.
setup_findings() {
  local job="$1" id="$2" runner="${3:-macos-latest}" installer names want got
  installer="          ./${4:-Scripts/install_tools.sh}"
  if [[ ! -s "$job" ]]; then
    echo "job: the file has no ${id} job"
    return 0
  fi
  grep -qxF "    runs-on: ${runner}" "$job" || echo "runs-on: the ${id} job is not on ${runner}"
  want="$(pin_of "${JOBS_TMP}/main.yml")"
  got="$(pin_of "$job")"
  [[ -n "$want" && "$got" == "$want" ]] || echo "pin of checkout: the ${id} job has ${got:-none}, the main job ${want:-none}"
  grep -qF 'fetch-depth: 0' "$job" || echo "checkout: the ${id} job does not fetch the full history, as the main job does"
  grep -qF 'persist-credentials: false' "$job" || echo "checkout: the ${id} job persists credentials"
  names="$(step_names "$job" | tr '\n' '|')"
  if [[ "$runner" == ubuntu-latest ]]; then
    go_setup_findings "$job" "$id" "$names"
  else
    [[ "$names" == "Set up the gate environment|Set up Node|Install tools|Install dependencies|"* ]] \
      || echo "setup: the ${id} job's steps start ${names}, not the main job's gate environment, Node, tools and dependencies"
  fi
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

# LINUX_GATES_INSTALL: the Install tools command of the Linux gate jobs other
# than lint and selftest_linux (forsgren#447, step 3): the pinned Linux
# installer with the list of the tools their gates run (shellcheck and
# yamllint, for the self-tests the isolation shards run).
LINUX_GATES_INSTALL="Scripts/install_tools_linux.sh Scripts/required_tools_linux_gates.txt"
# LINT_INSTALL: lint and selftest_linux, the four Linux lint tools.
LINT_INSTALL="Scripts/install_tools_linux.sh Scripts/required_tools_linux.txt"

# tools_file_of <job>: the tools list of a gate job (forsgren#447, step 4),
# named after the job; the main job's id is quality (forsgren#591 step 2).
tools_file_of() {
  echo "Scripts/required_tools_${1}_gates.txt"
}

# TOOLS_DIR: where tools_file_findings reads the lists from (a mutant points it
# at a copy); the lists are Scripts/required_tools_<job>_gates.txt.
TOOLS_DIR="Scripts"

# listed_tools <file>: the tools of a list as Scripts/install_tools.sh and
# Scripts/install_tools_linux.sh read it
# (comments and blanks left out), sorted, each followed by a space.
listed_tools() {
  { sed -e 's/#.*//' "$1" | tr -d '[:blank:]' | grep . | LC_ALL=C sort | tr '\n' ' '; } || true
}

# tool_pattern <tool>: how a gate script calls it. Node also reaches it as npm
# or npx; Go is named by its subcommands, as the word go is also prose.
tool_pattern() {
  case "$1" in
    go) printf '%s\n' '\bgo (run|test|build|list|vet|mod|tool|env|install)\b' ;;
    node) printf '%s\n' '\b(node|npm|npx)\b' ;;
    *) printf '\\b%s\\b\n' "$1" ;;
  esac
}

# OWN_LIST_JOBS: the jobs that install from a list of their own.
OWN_LIST_JOBS="quality_2 selftest_mac_1 selftest_mac_2 browser_1 browser_2 browser_3"

# tools_file_findings: pin 3g, the lists. Each exists and holds exactly the
# tools its job needs, and no gate of the job, nor a script it names however
# deep (forsgren#447, step 9), calls a tool of the full list that the job's list lacks.
tools_file_findings() {
  local job file want listed missing tool script reached
  for job in $OWN_LIST_JOBS; do
    file="${TOOLS_DIR}/$(basename "$(tools_file_of "$job")")"
    if [[ ! -s "$file" ]]; then
      echo "tools: ${file} does not exist or is empty"
      continue
    fi
    case "$job" in
      quality_2 | selftest_mac_1) want='go jq node ' ;;
      # The main job's self-tests keep the main job's tools (forsgren#686), and
      # are read as the main job's gates are: a line that runs a tool, not one
      # that names it in a stub or a fixture (run_pattern).
      selftest_mac_2) want="$MAIN_WANT" ;;
      browser_2) want='node ' ;;
      *) want='go node ' ;;
    esac
    listed="$(listed_tools "$file")"
    [[ "$listed" == "$want" ]] || echo "tools: ${file} lists '${listed}', the ${job} job needs '${want}'"
    missing=""
    for tool in $(listed_tools Scripts/required_tools.txt); do
      [[ " ${listed}" == *" ${tool} "* ]] || missing+="${tool} "
    done
    for script in $(gates_of "$job"); do
      # The gate's script and every script it names, transitively (closure, as
      # Scripts/test_gate_inputs.sh reads it): a tool needed deeper is the gate's too.
      # Only scripts under Scripts/: the push wrappers FBP.sh and sfl.sh, which a gate
      # may probe (it runs FBP.sh with --no-commit and it aborts before any step), no
      # gate reads (gate_inputs.txt lists them as out), and FBP.sh's text names gitleaks.
      for reached in $(closure "Scripts/${script}.sh" | grep '^Scripts/.*[.]sh$'); do
        # selftest_mac_2, as main_reach: a script that is another row's gate is
        # read as text there (the row that runs it has its own job and tools).
        if [[ "$job" == selftest_mac_2 && "$reached" != "Scripts/${script}.sh" ]] \
          && grep -v '^#' "$ORDER" | cut -d'|' -f2 | has -xF -- "$reached"; then
          continue
        fi
        for tool in $missing; do
          if [[ "$job" == selftest_mac_2 ]]; then
            code "$reached" | has -E "$(run_pattern "$tool")" || continue
          else
            code "$reached" | has -E "$(tool_pattern "$tool")" || continue
          fi
          if [[ "$reached" == "Scripts/${script}.sh" ]]; then
            echo "tools: the ${job} gate ${script} calls ${tool}, which ${file} does not list"
          else
            echo "tools: the ${job} gate ${script} reaches ${tool} in ${reached}, which ${file} does not list"
          fi
        done
      done
    done
  done
}

# LINT_GATES: the scripts of the lint gates and their self-tests, which no step
# of either workflow may name.
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

# gates_pattern <job>...: an extended regex of the scripts of those jobs' rows.
gates_pattern() {
  local j
  for j in "$@"; do gates_of "$j"; done | sort -u | paste -sd'|' -
}

# MAIN_WANT: the tools of the main job's list (forsgren#591 step 2), sorted as
# listed_tools prints them: the secret scan's gitleaks, the language gate's
# languagetool, npm audit's jq, and go and node for the build and the Go and
# npm gates. The four lint tools are left out: their gates run in the lint job.
MAIN_WANT='gitleaks go jq languagetool node '

# run_pattern <tool>: a line that runs the tool as a command with an argument
# (at the start of a command, after if, then, do, !, $( or command -v), not one
# that only names it (a fixture's stub, a file name, a list, a word alone on a
# line of a here-document, prose in parentheses): the main job's gates name the
# lint tools in their fixtures and in other jobs' gate scripts they read as text.
run_pattern() {
  printf '%s%s%s\n' '(^|[;&|{!]|\$\(|(then|do|if|else|exec|time|command -v))[[:space:]]*' "$1" '[[:space:]]+[^[:space:]]'
}

# main_gates: the scripts of the main job's rows, every row of the order file
# with a script that the group file gives to no other job.
main_gates() {
  local grouped label script
  grouped="$(grep -v '^#' "$GROUPS_FILE" | grep . | cut -d'|' -f2)"
  while IFS='|' read -r label script _rest; do
    [[ "$script" == Scripts/*.sh ]] || continue
    has -xF -- "$label" <<< "$grouped" && continue
    echo "$script"
  done < <(grep -v '^#' "$ORDER" | grep .)
}

# other_job_gates: the scripts of the rows the group file gives to another job.
other_job_gates() {
  local label
  while IFS='|' read -r _job label _args; do
    awk -F'|' -v l="$label" '$1 == l { print $2 }' <(grep -v '^#' "$ORDER")
  done < <(grep -v '^#' "$GROUPS_FILE" | grep .) | sort -u
}

# main_reach: one line per main gate and script it reaches, "<gate> <script>",
# the closure as tools_file_findings reads it, less the scripts that are
# another job's gates (a main gate that names check_shellcheck.sh, the lint
# job's gate, reads it as text; the lint job runs it with its own tools).
main_reach() {
  local others gate reached
  others="$(other_job_gates)"
  for gate in $(main_gates); do
    for reached in $(closure "$gate" | grep '^Scripts/.*[.]sh$'); do
      [[ "$reached" != "$gate" ]] && has -xF -- "$reached" <<< "$others" && continue
      echo "${gate} ${reached}"
    done
  done
}

# main_tools_findings [reach-file]: pin 3g for the main job (forsgren#591 step 2).
# Its list exists and holds exactly MAIN_WANT, every tool of it is in
# Scripts/required_tools.txt (the list sfl installs), and no script a main gate
# reaches runs a tool of the full list that the main list lacks. The reach is
# read from the file when given (main_reach's lines), else computed.
main_tools_findings() {
  local file listed missing tool gate reached reach
  file="${TOOLS_DIR}/$(basename "$(tools_file_of quality)")"
  if [[ ! -s "$file" ]]; then
    echo "tools: ${file} does not exist or is empty"
    return 0
  fi
  listed="$(listed_tools "$file")"
  [[ "$listed" == "$MAIN_WANT" ]] || echo "tools: ${file} lists '${listed}', the quality job needs '${MAIN_WANT}'"
  missing=""
  for tool in $(listed_tools Scripts/required_tools.txt); do
    [[ " ${listed}" == *" ${tool} "* ]] || missing+="${tool} "
  done
  for tool in $listed; do
    [[ " $(listed_tools Scripts/required_tools.txt)" == *" ${tool} "* ]] \
      || echo "tools: ${file} lists ${tool}, which Scripts/required_tools.txt does not"
  done
  if [[ -n "${1:-}" ]]; then reach="$(cat "$1")"; else reach="$(main_reach)"; fi
  while read -r gate reached; do
    [[ -n "$reached" ]] || continue
    for tool in $missing; do
      code "$reached" | has -E "$(run_pattern "$tool")" || continue
      echo "tools: the quality gate $(basename "$gate" .sh) runs ${tool} in ${reached}, which ${file} does not list"
    done
  done <<< "$reach"
}

# phase_calls <job file>: the run_ci_phase.sh call lines.
phase_calls() {
  code "$1" | grep -E '^[[:space:]]*\./Scripts/run_ci_phase\.sh ' || true
}

# workflow_phase_jobs <workflow>: the jobs its run_ci_phase.sh calls name, once
# each, sorted (the reading of Scripts/selftest_rows.sh and pin 8).
workflow_phase_jobs() {
  code "$1" | sed -nE 's#^[[:space:]]*\./Scripts/run_ci_phase\.sh (pre|post) "[$]ROWS" "[$]DETAILS" ([A-Za-z0-9_-]+)[[:space:]]*$#\2#p' | LC_ALL=C sort -u
}

# one_pre_call_findings <job file> <id>: pin 2, a job that runs exactly
# `run_ci_phase.sh pre "$ROWS" "$DETAILS" <id>` and nothing else of the runner.
one_pre_call_findings() {
  local calls
  [[ -s "$1" ]] || return 0
  calls="$(phase_calls "$1")"
  [[ "$calls" == *"run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" ${2}" && "$(wc -l <<< "$calls" | tr -d ' ')" == 1 ]] \
    || echo "${2}: the ${2} job must run exactly ./Scripts/run_ci_phase.sh pre \"\$ROWS\" \"\$DETAILS\" ${2}, got: ${calls:-none}"
}

# job_findings <quality.yml> <selftests.yml>: pins 1 to 5 and 9.
job_findings() {
  local wf="$1" st="$2" main b3 rep srep fi_job calls id file n pre_job build_line post_line
  main="${JOBS_TMP}/main.yml"
  job_of "$wf" quality > "$main"
  code "$main" | has -xF "          ./Scripts/install_tools.sh $(tools_file_of quality)" \
    || echo "setup: the quality job does not run Scripts/install_tools.sh $(tools_file_of quality)"
  handover_findings "$main" quality
  calls="$(phase_calls "$main")"
  [[ "$(grep -cE " \"[$]DETAILS\" main( |\$)" <<< "$calls")" == 2 ]] \
    || echo "main: both run_ci_phase.sh calls of the main job must end with the job name main, got: ${calls:-none}"

  # The macOS jobs with a list of their own: quality_2 in Quality, the two
  # macOS self-test jobs in Self-tests.
  for id in quality_2 selftest_mac_1 selftest_mac_2; do
    case "$id" in quality_2) file="$wf" ;; *) file="$st" ;; esac
    job_of "$file" "$id" > "${JOBS_TMP}/${id}.yml"
    setup_findings "${JOBS_TMP}/${id}.yml" "$id" macos-latest "Scripts/install_tools.sh $(tools_file_of "$id")"
    handover_findings "${JOBS_TMP}/${id}.yml" "$id"
    one_pre_call_findings "${JOBS_TMP}/${id}.yml" "$id"
    if code "$file" | has -E "($(gates_pattern "$id"))"; then
      echo "${id}: a step names a ${id} gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
    fi
  done

  # The Linux jobs.
  job_of "$wf" lint > "${JOBS_TMP}/lint.yml"
  setup_findings "${JOBS_TMP}/lint.yml" lint ubuntu-latest "$LINT_INSTALL"
  job_of "$st" selftest_linux > "${JOBS_TMP}/selftest_linux.yml"
  setup_findings "${JOBS_TMP}/selftest_linux.yml" selftest_linux ubuntu-latest "$LINT_INSTALL"
  job_of "$wf" workflows > "${JOBS_TMP}/workflows.yml"
  setup_findings "${JOBS_TMP}/workflows.yml" workflows ubuntu-latest "$LINUX_GATES_INSTALL"
  for id in isolation_1 isolation_2 summary; do
    job_of "$st" "$id" > "${JOBS_TMP}/${id}.yml"
    setup_findings "${JOBS_TMP}/${id}.yml" "$id" ubuntu-latest "$LINUX_GATES_INSTALL"
  done
  for n in 1 2; do
    job_of "$st" "browser_${n}" > "${JOBS_TMP}/browser_${n}.yml"
  done
  job_of "$wf" browser_3 > "${JOBS_TMP}/browser_3.yml"
  for n in 1 2 3; do
    setup_findings "${JOBS_TMP}/browser_${n}.yml" "browser_${n}" ubuntu-latest "Scripts/install_tools_linux.sh $(tools_file_of "browser_${n}")"
  done
  for id in lint selftest_linux workflows isolation_1 isolation_2 summary browser_1 browser_2 browser_3; do
    handover_findings "${JOBS_TMP}/${id}.yml" "$id"
  done
  for id in lint selftest_linux workflows isolation_1 isolation_2 summary browser_1 browser_2; do
    one_pre_call_findings "${JOBS_TMP}/${id}.yml" "$id"
  done

  b3="${JOBS_TMP}/browser_3.yml"
  if [[ -s "$b3" ]]; then
    calls="$(phase_calls "$b3")"
    [[ "$calls" == *"run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_3" && "$(wc -l <<< "$calls" | tr -d ' ')" == 1 ]] \
      || echo "browser_3: the browser_3 job must run exactly ./Scripts/run_ci_phase.sh post \"\$ROWS\" \"\$DETAILS\" browser_3 (its gates are post rows), got: ${calls:-none}"
    build_line="$(line_of "$b3" './Scripts/build_site.sh')"
    post_line="$(line_of "$b3" './Scripts/run_ci_phase.sh post')"
    if [[ -z "$build_line" ]] || ! later "$post_line" "$build_line"; then
      echo "browser_3: the browser_3 job must run its own site build (Scripts/build_site.sh), then POST: the browser gate reads the built site"
    fi
  fi
  for n in 1 2; do
    pre_job="${JOBS_TMP}/browser_${n}.yml"
    [[ -s "$pre_job" ]] || continue
    if code "$pre_job" | has -F './Scripts/build_site.sh'; then
      echo "browser_${n}: the browser_${n} job builds a site; its gates are PRE rows that read no built site"
    fi
  done
  if { code "$wf"; code "$st"; } | has -E 'test_gate_browser|gate_browser'; then
    echo "browser: a step names a browser gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi
  if code "$wf" | has -E "($(gates_pattern workflows))"; then
    echo "workflows: a step names a workflows gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi
  if { code "$wf"; code "$st"; } | has -E "$LINT_GATES"; then
    echo "lint: a step names a lint gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi
  if code "$st" | has -E "($(gates_pattern isolation_1 isolation_2 summary))"; then
    echo "isolation: a step names an isolation gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi
  if code "$st" | has -E "($(gates_pattern selftest_linux))"; then
    echo "selftest_linux: a step names a selftest_linux gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi
  if { code "$wf"; code "$st"; } | has -E 'continue-on-error'; then
    echo "verdict: continue-on-error softens a failure, so a workflow could be green with a red job"
  fi

  # Each gate job in the workflow it belongs to: a job of the other workflow
  # in this file would run its gates twice, or in the wrong verdict.
  for id in $SELFTEST_GATE_JOBS; do
    job_ids "$wf" | has -xF -- "$id" && echo "split: the self-test job ${id} is a job of ${WORKFLOW}"
  done
  for id in $QUALITY_GATE_JOBS; do
    job_ids "$st" | has -xF -- "$id" && echo "split: the Quality job ${id} is a job of ${SELFTESTS}"
  done

  # pin 5
  rep="${JOBS_TMP}/report.yml"
  job_of "$wf" report > "$rep"
  # report_start sends the run's start (Scripts/dispatch_report.sh), as in
  # Self-tests: no gate job, so the report neither needs nor judges it.
  report_findings "$rep" "$wf" "Quality" "$(job_ids "$wf" | grep -vxE 'report|preview|report_start' || true)"
  if [[ -s "$rep" ]]; then
    code "$rep" | has -E 'QS_JOB_STATUS="?\$\(\./Scripts/merge_quality_report\.sh status' \
      || echo "report: QS_JOB_STATUS is not taken from Scripts/merge_quality_report.sh status of the jobs' results"
    status_findings "$rep" "$(job_ids "$wf" | grep -vxE 'report|preview|report_start' || true)"
    code "$rep" | has -E '\./Scripts/render_quality_summary\.sh "[$]rows" "[$]details" "[$]order"' \
      || echo "report: the Quality report job does not render the summary on its view of the order file"
    code "$rep" | has -xF "          export QS_JOB_GROUPS=\"${DOLLAR}groups\"" \
      || echo "report: the Quality report job does not pass its view of the group file as QS_JOB_GROUPS"
  fi
  srep="${JOBS_TMP}/selftests_report.yml"
  job_of "$st" report > "$srep"
  # report_start sends the run's start (Scripts/dispatch_report.sh): no gate
  # job, so the report neither needs nor judges it.
  report_findings "$srep" "$st" "Self-tests" "$(job_ids "$st" | grep -vxE 'report|failure_issue|report_start' || true)"

  # pin 9
  fi_job="${JOBS_TMP}/failure_issue.yml"
  job_of "$st" failure_issue > "$fi_job"
  failure_issue_findings "$fi_job" "$st"
}

# joined <file>: the file's code with continued lines (a trailing backslash)
# joined, one command a line.
joined() {
  code "$1" | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta'
}

# report_findings <report job file> <workflow> <name> <gate job ids>: pin 5.
report_findings() {
  local rep="$1" wf="$2" name="$3" others="$4" needs listed id var call want got
  if [[ ! -s "$rep" ]]; then
    echo "report: the ${name} file has no report job"
    return 0
  fi
  needs="$(grep -E '^    needs:' "$rep" | head -1 | sed -E 's/^    needs:[[:space:]]*//' || true)"
  for id in $others; do
    grep -qE "(\[|, *)${id}(\]|,)" <<< "$needs" || echo "report: the gate job ${id} is not in the ${name} report job's needs:"
  done
  listed="$(tr -d '[] ' <<< "$needs" | tr ',' '\n')"
  for id in $listed; do
    grep -qx "$id" <<< "$others" || echo "report: ${id} in the ${name} report job's needs: is not a gate job"
  done
  grep -qE '^    if: (always\(\)|\$\{\{ always\(\) \}\})[[:space:]]*$' "$rep" \
    || echo "report: the ${name} report job is not if: always(), so a red gate job leaves no report"
  grep -qxF '    runs-on: ubuntu-latest' "$rep" || echo "report: the ${name} report job is not on ubuntu-latest"
  grep -qE 'uses: actions/download-artifact@[0-9a-f]{40}  # v[0-9]' "$rep" \
    || echo "report: the ${name} report job does not download with a commit-pinned actions/download-artifact"
  grep -qxF '          pattern: quality-report-*' "$rep" || echo "report: the ${name} report job does not download every quality-report-* hand-over"
  code "$rep" | has -E '^[[:space:]]*\./Scripts/merge_quality_report\.sh merge ' \
    || echo "report: the ${name} report job does not merge the hand-overs with Scripts/merge_quality_report.sh merge"
  code "$rep" | has -E '\./Scripts/render_quality_report\.sh "[$]rows" "[$]details" "[$]order"' \
    || echo "report: the ${name} report job does not render the gate table on its view of the order file"
  # The view: exactly the jobs this workflow's run_ci_phase.sh calls name.
  call="$(joined "$rep" | grep -E 'merge_quality_report\.sh view ' || true)"
  if [[ -z "$call" ]]; then
    echo "report: the ${name} report job makes no view (Scripts/merge_quality_report.sh view), so the other workflow's rows would show as unmeasured"
  else
    want="$(workflow_phase_jobs "$wf" | tr '\n' ' ')"
    got="$(sed -E 's/.*merge_quality_report\.sh view [^ ]+ [^ ]+ "[$]groups" "[$]order" //; s/ *[|][|].*//' <<< "$call" | tr ' ' '\n' | grep . | LC_ALL=C sort -u | tr '\n' ' ')"
    [[ "$got" == "$want" ]] || echo "report: the ${name} report job's view names the jobs '${got}', its workflow runs '${want}'"
  fi
  # The verdict: every gate job's result, read from needs.
  call="$(joined "$rep" | grep -E 'merge_quality_report\.sh verdict' || true)"
  for id in $others; do
    var="QS_$(tr '[:lower:]-' '[:upper:]_' <<< "$id")_RESULT"
    grep -qxF "          ${var}: ${DOLLAR}{{ needs.${id}.result }}" "$rep" \
      || echo "report: the ${name} report job has no ${var} from needs.${id}.result, so the gate job ${id} is not judged"
    grep -qF "\"${id}=${DOLLAR}${var}\"" <<< "$call" \
      || echo "report: the ${name} verdict does not pass \"${id}=\$${var}\", so a red ${id} job would leave the report green"
  done
}

# status_findings <report job file> <gate job ids>: pin 5b. Each gate job's
# result reaches the status call: the status call passes "$QS_<ID>_RESULT".
status_findings() {
  local rep="$1" ids="$2" id var call
  call="$(joined "$rep" | grep -E 'merge_quality_report\.sh status' || true)"
  for id in $ids; do
    var="QS_$(tr '[:lower:]-' '[:upper:]_' <<< "$id")_RESULT"
    grep -qF "\"${DOLLAR}${var}\"" <<< "$call" \
      || echo "report: the status call does not pass \"\$${var}\", so a red ${id} job would not make the report's status failed"
  done
}

# failure_issue_findings <job file> <selftests.yml>: pin 9.
failure_issue_findings() {
  local job="$1" st="$2" needs id others
  if [[ ! -s "$job" ]]; then
    echo "failure issue: ${SELFTESTS} has no failure_issue job, so a red Self-tests run on main is seen by nobody"
    return 0
  fi
  others="$(job_ids "$st" | grep -vxE 'failure_issue' || true)"
  needs="$(grep -E '^    needs:' "$job" | head -1 | sed -E 's/^    needs:[[:space:]]*//' || true)"
  for id in $others; do
    grep -qE "(\[|, *)${id}(\]|,)" <<< "$needs" || echo "failure issue: the job ${id} is not in the failure_issue job's needs:"
  done
  grep -qxF "    if: failure() && github.event_name == 'push'" "$job" \
    || echo "failure issue: the failure_issue job is not if: failure() && github.event_name == 'push'"
  grep -qxF '    runs-on: ubuntu-latest' "$job" || echo "failure issue: the failure_issue job is not on ubuntu-latest"
  grep -qE '^      issues: write' "$job" || echo "failure issue: the failure_issue job does not hold issues: write"
  if code "$st" | grep -vF -- "$(grep -E '^      issues: write' "$job" | head -1)" | has -E 'issues: write'; then
    echo "failure issue: another part of ${SELFTESTS} holds issues: write; only the failure_issue job may"
  fi
  code "$st" | awk '/^permissions:/ { on = 1; next } on && /^[^[:space:]]/ { on = 0 } on' | has -xE '  contents: read' \
    || echo "failure issue: ${SELFTESTS} does not keep the workflow's permissions at contents: read"
  code "$job" | has -xF '        run: ./Scripts/open_selftests_failure_issue.sh' \
    || echo "failure issue: the failure_issue job does not run Scripts/open_selftests_failure_issue.sh"
  code "$job" | has -xF "          GH_TOKEN: ${DOLLAR}{{ github.token }}" \
    || echo "failure issue: the failure_issue job does not give gh the job's own token"
}

# groups_findings: pin 3.
# Q2_ROWS: the gates the quality_2 job runs (forsgren#447): the Go tests with
# the Go coverage gate that reads their profile (.build/go-coverage.out), and
# three more long PRE gates that need no built site, on macOS.
Q2_ROWS=('quality_2|Go tests' 'quality_2|Go coverage' 'quality_2|golden pages'
  'quality_2|exit-trap completion behaviour' 'quality_2|quality-run summary')

# M1_ROWS, M2_ROWS, SL_ROWS: the self-test jobs (forsgren#686), each row on the
# runner it ran on in Quality before the split.
M1_ROWS=('selftest_mac_1|sfl pull rebase self-test' 'selftest_mac_1|required-pages self-test'
  'selftest_mac_1|html-duplication self-test' 'selftest_mac_1|FBP --no-push self-test'
  'selftest_mac_1|FBP push-or-rebase self-test' 'selftest_mac_1|bare mktemp self-test'
  'selftest_mac_1|tmp failure stops self-test' 'selftest_mac_1|Go coverage self-test'
  'selftest_mac_1|npm-audit self-test' 'selftest_mac_1|privacy-posture self-test'
  'selftest_mac_1|build-site self-test' 'selftest_mac_1|workflow-triggers self-test'
  'selftest_mac_1|browser gate (TBD tables) self-test' 'selftest_mac_1|browser gate (default TBD fixture) self-test'
  'selftest_mac_1|browser gate inputs self-test')
M2_ROWS=('selftest_mac_2|data guard self-test' 'selftest_mac_2|private-names self-test'
  'selftest_mac_2|gofmt self-test' 'selftest_mac_2|private-names secret sync self-test'
  'selftest_mac_2|private-names local file self-test' 'selftest_mac_2|sfl self-test skip self-test'
  'selftest_mac_2|npm manifest policy self-test' 'selftest_mac_2|tool install self-test'
  'selftest_mac_2|Linux tool install self-test' 'selftest_mac_2|npm install sync self-test'
  'selftest_mac_2|site-settings self-test' 'selftest_mac_2|HTMLHint self-test'
  'selftest_mac_2|Stylelint self-test' 'selftest_mac_2|Stylelint source-fix self-test'
  'selftest_mac_2|language gate self-test' 'selftest_mac_2|language pages wrapper self-test'
  'selftest_mac_2|baseline report self-test' 'selftest_mac_2|html duplication, generated page self-test'
  'selftest_mac_2|golden-pages self-test' 'selftest_mac_2|temp helper self-test'
  'selftest_mac_2|local hook self-test' 'selftest_mac_2|CI phase runner self-test'
  'selftest_mac_2|go mod tidy self-test' 'selftest_mac_2|Go tool helper self-test'
  'selftest_mac_2|Go file length self-test' 'selftest_mac_2|Go dead code self-test'
  'selftest_mac_2|lint-coverage self-test' 'selftest_mac_2|manifest-covers-site self-test'
  'selftest_mac_2|repository-links self-test' 'selftest_mac_2|exit-trap completion self-test'
  'selftest_mac_2|pipe into grep -q self-test' 'selftest_mac_2|markdown-links self-test'
  'selftest_mac_2|script references self-test' 'selftest_mac_2|Node pin self-test'
  'selftest_mac_2|Node pin gate self-test' 'selftest_mac_2|Go toolchain pin self-test'
  'selftest_mac_2|starter page build self-test' 'selftest_mac_2|starter page links self-test'
  'selftest_mac_2|starter page gates self-test' 'selftest_mac_2|dependabot merge policy self-test'
  'selftest_mac_2|dependabot pull-request comment self-test' 'selftest_mac_2|npm lockfile sync self-test'
  'selftest_mac_2|dispatch preview self-test' 'selftest_mac_2|parallel mutants library self-test'
  'selftest_mac_2|browser gate baseline choice self-test' 'selftest_mac_2|browser gate skip self-test'
  'selftest_mac_2|live check self-test' 'selftest_mac_2|release quality self-test'
  'selftest_mac_2|release publish self-test' 'selftest_mac_2|release resume self-test'
  'selftest_mac_2|release token expiry self-test' 'selftest_mac_2|token expiry probe self-test'
  'selftest_mac_2|release verify pin self-test' 'selftest_mac_2|release verify install self-test'
  'selftest_mac_2|release agent proofs self-test' 'selftest_mac_2|merge quality report self-test'
  'selftest_mac_2|self-tests failure issue self-test' 'selftest_mac_2|git sandbox isolation scope self-test'
  'selftest_mac_2|git sandbox guard self-test' 'selftest_mac_2|static block self-test'
  'selftest_mac_2|commit messages self-test')
SL_ROWS=('selftest_linux|actionlint self-test' 'selftest_linux|actionlint forsgren cases self-test'
  'selftest_linux|shellcheck self-test' 'selftest_linux|yamllint self-test'
  'selftest_linux|zizmor self-test' 'selftest_linux|Go lint self-test'
  'selftest_linux|mutation: checkout pins' 'selftest_linux|Go test duplication self-test'
  'selftest_linux|Go vulnerabilities self-test' 'selftest_linux|release pins self-test'
  'selftest_linux|browser gate selection self-test' 'selftest_linux|Go tests self-test'
  'selftest_linux|release precheck self-test' 'selftest_linux|community-files self-test'
  'selftest_linux|DCO sign-off self-test' 'selftest_linux|release plan self-test'
  'selftest_linux|release report self-test' 'selftest_linux|release check self-test'
  'selftest_linux|release metrics self-test' 'selftest_linux|report dispatch self-test')

groups_findings() {
  local rows labels
  labels="$(printf '%s\n' 'isolation_1|git sandbox isolation self-test|--shard 1/2' 'isolation_2|git sandbox isolation self-test|--shard 2/2' 'summary|step summary isolation' \
    'browser_1|browser gate self-test|--shard 1/2' 'browser_1|browser gate (fixture site) self-test' \
    'browser_2|browser gate self-test|--shard 2/2' 'browser_2|browser gate process self-test' \
    'browser_3|browser gate' 'browser_3|browser gate (fixture site)' \
    'lint|actionlint' 'lint|shellcheck' 'lint|yamllint' 'lint|zizmor' 'lint|Go lint' 'lint|Go test duplication' \
    "${Q2_ROWS[@]}" "${M1_ROWS[@]}" "${M2_ROWS[@]}" "${SL_ROWS[@]}" \
    'workflows|gate wiring' 'workflows|metrics workflow' 'workflows|release workflow' \
    'workflows|starter page workflow' 'workflows|quality jobs pin' 'workflows|preview workflow' \
    'workflows|vulncheck workflow' 'workflows|auto-update workflow' \
    'workflows|go mod tidy' 'workflows|sfl drives from the order file' \
    | LC_ALL=C sort | tr '\n' ';')"
  [[ -f "$GROUPS_FILE" ]] || { echo "groups: ${GROUPS_FILE} does not exist"; return 0; }
  rows="$(grep -v '^#' "$GROUPS_FILE" | grep . | LC_ALL=C sort | tr '\n' ';')"
  [[ "$rows" == "$labels" ]] \
    || echo "groups: ${GROUPS_FILE} must give the two isolation jobs the git sandbox isolation self-test, one shard each (isolation_1 with --shard 1/2, isolation_2 with --shard 2/2), the summary job the step summary isolation gate, the browser_1 job the browser gate self-test --shard 1/2 and the fixture site self-test, the browser_2 job its --shard 2/2 and the browser gate process self-test, the browser_3 job the two browser gates, the lint job actionlint, shellcheck, yamllint, zizmor, Go lint and the Go test duplication gate, the quality_2 job the five gates of forsgren#447 (the Go tests with the Go coverage gate, three more), the workflows job gate wiring, the pins of the metrics, release, starter page, vulncheck, auto-update and preview workflows and of this job layout, go mod tidy and sfl drives from the order file, and the self-test jobs selftest_mac_1, selftest_mac_2 and selftest_linux the self-test rows of forsgren#686, got: ${rows:-none}"
  while IFS='|' read -r job label _args; do
    awk -F'|' -v l="$label" '$1 == l && ($3 == "pre" || $3 == "post")' <(grep -v '^#' "$ORDER") | has . \
      || echo "groups: '${label}' is no pre or post row of ${ORDER}"
    # browser_3 calls run_ci_phase.sh post only (forsgren#686), every other
    # named job pre only, so a row of the other phase would run in no job.
    case "$job" in
      browser_3)
        awk -F'|' -v l="$label" '$1 == l && $3 == "post"' <(grep -v '^#' "$ORDER") | has . \
          || echo "groups: the ${job} gate '${label}' is no post row of ${ORDER}; the ${job} job runs only its post rows, so the gate would run in no job"
        ;;
      *)
        awk -F'|' -v l="$label" '$1 == l && $3 == "pre"' <(grep -v '^#' "$ORDER") | has . \
          || echo "groups: the ${job} gate '${label}' is no pre row of ${ORDER}; the ${job} job runs only its pre rows, so the gate would run in no job"
        ;;
    esac
  done < <(grep -v '^#' "$GROUPS_FILE" | grep .)
  union_findings
}

# union_findings: the jobs' gates together are the order file's pre and post
# rows, each once (forsgren#447): the main job runs every row the group file
# does not list, so the main job's rows and the group file's labels (a sharded
# label once) must be the order file's rows, none in two jobs and none in no
# job. A gate is in two jobs only as one shard each (forsgren#641: the browser
# gate self-test is in browser_1 and browser_2, as the isolation self-test of
# forsgren#426 is in isolation_1 and isolation_2): every row of a label listed
# more than once carries --shard, and no two the same shard. The same
# `<job>|<label>` twice is named on its own (forsgren#672): it is one job, not
# two, and Scripts/run_ci_phase.sh refuses the group file for it.
union_findings() {
  local all grouped main both twice dup
  all="$(grep -v '^#' "$ORDER" | grep . | awk -F'|' '$3 == "pre" || $3 == "post" { print $1 }' | LC_ALL=C sort)"
  grouped="$(grep -v '^#' "$GROUPS_FILE" | grep . | cut -d'|' -f2 | LC_ALL=C sort -u)"
  main="$(LC_ALL=C comm -23 <(printf '%s\n' "$all" | LC_ALL=C sort -u) <(printf '%s\n' "$grouped"))"
  both="$( { printf '%s\n' "$main"; printf '%s\n' "$grouped"; } | grep . | LC_ALL=C sort)"
  [[ "$both" == "$(printf '%s\n' "$all" | LC_ALL=C sort)" ]] \
    || echo "union: the main job's gates and the group file's gates are not the order file's pre and post rows, each once"
  dup="$(grep -v '^#' "$GROUPS_FILE" | grep . | awk -F'|' 'seen[$1 "|" $2]++ == 1 { print $1 "|" $2 }' | paste -sd',' -)"
  [[ -z "$dup" ]] || echo "union: a gate is given to the same job twice: ${dup}"
  twice="$(grep -v '^#' "$GROUPS_FILE" | grep . | awk -F'|' '{ if (seen[$1 "|" $2]++) next; n[$2]++; if ($3 !~ /^--shard [1-9][0-9]*\/[1-9][0-9]*$/ || s[$2 "|" $3]++) bad[$2] = 1 } END { for (l in bad) if (n[l] > 1) print l }')"
  [[ -z "$twice" ]] || echo "union: a gate is in two jobs, not as one shard each: ${twice}"
}

# BROWSER_SELFTEST: the sharded browser gate self-test of pin 3h (forsgren#641),
# read through its --list mode, which prints the cases and proofs a run would
# start and stops before it needs Chrome; a mutant points it at a copy.
BROWSER_SELFTEST="Scripts/test_gate_browser.sh"
BROWSER_SHARDED="browser gate self-test"

# listed_ids <args...>: what the browser gate self-test lists with these
# arguments and --list, one id per line, sorted; a run that fails says so.
listed_ids() {
  local out
  if ! out="$(bash "$BROWSER_SELFTEST" "$@" --list 2>&1 < /dev/null)"; then
    echo "shard: ${BROWSER_SELFTEST} $* --list failed: ${out}" >&2
    return 1
  fi
  printf '%s\n' "$out" | grep . | LC_ALL=C sort || true
}

# shard_findings: pin 3h. The group file's rows of the browser gate self-test,
# each listed with its own arguments, together list every case and proof of the
# whole run once (a row without arguments lists the whole run), each row at
# least one, and the whole run lists every case_ and mutant_ function of the
# script (mutant_engine, the proofs' helper, is no proof) and every id of its
# SERIAL_CASES (the cases written inline, run one after the other).
shard_findings() {
  local rows args argv full all part defined
  # One line per row, `row:<arguments>`, so a row without arguments is a line too.
  rows="$(grep -v '^#' "$GROUPS_FILE" | awk -F'|' -v l="$BROWSER_SHARDED" '$2 == l { print "row:" $3 }')"
  [[ -n "$rows" ]] || { echo "shard: ${GROUPS_FILE} has no row of the ${BROWSER_SHARDED}"; return 0; }
  full="$(listed_ids 2>&1)" || { echo "$full"; return 0; }
  [[ -n "$full" ]] || { echo "shard: ${BROWSER_SELFTEST} --list lists no case"; return 0; }
  all=""
  while IFS= read -r args; do
    args="${args#row:}"
    # The arguments are words (--shard N/M), split as run_ci_phase.sh splits them.
    read -r -a argv <<< "$args"
    part="$(listed_ids ${argv[@]+"${argv[@]}"} 2>&1)" || { echo "$part"; return 0; }
    [[ -n "$part" ]] || echo "shard: the row '${args}' of the ${BROWSER_SHARDED} lists no case"
    all+="${part}"$'\n'
  done <<< "$rows"
  all="$(grep . <<< "$all" | LC_ALL=C sort || true)"
  part="$(uniq -d <<< "$all" | tr '\n' ' ')"
  [[ -z "$part" ]] || echo "shard: the cases ${part}run in two jobs of the ${BROWSER_SHARDED}"
  part="$(LC_ALL=C comm -23 <(printf '%s\n' "$full") <(uniq <<< "$all") | tr '\n' ' ')"
  [[ -z "$part" ]] || echo "shard: the cases ${part}run in no job of the ${BROWSER_SHARDED}"
  part="$(LC_ALL=C comm -13 <(printf '%s\n' "$full") <(uniq <<< "$all") | tr '\n' ' ')"
  [[ -z "$part" ]] || echo "shard: a shard lists ${part}which the whole run of the ${BROWSER_SHARDED} does not"
  defined="$( { sed -nE 's/^((case|mutant)_[A-Za-z0-9]+)\(\) \{.*/\1/p' "$BROWSER_SELFTEST" | grep -vx 'mutant_engine'
    sed -nE 's/^SERIAL_CASES=\((.*)\)$/\1/p' "$BROWSER_SELFTEST" | tr ' ' '\n' | grep . | sed 's/^/serial_/'; } | LC_ALL=C sort -u)"
  part="$(LC_ALL=C comm -23 <(printf '%s\n' "$defined") <(printf '%s\n' "$full") | tr '\n' ' ')"
  [[ -z "$part" ]] || echo "shard: ${part}are in ${BROWSER_SELFTEST} but in no list of its whole run"
  # Every row of the weights file names a case or proof of the run, serial or
  # the default, so a renamed or removed case leaves no stale weight behind.
  part="$(LC_ALL=C comm -23 \
    <(sed -e 's/#.*//' "$(dirname "$BROWSER_SELFTEST")/browser_gate_selftest_weights.txt" | awk 'NF { print $1 }' | grep -vxE 'default|serial' | LC_ALL=C sort -u) \
    <(printf '%s\n' "$full") | tr '\n' ' ')"
  [[ -z "$part" ]] || echo "shard: the weights rows ${part}name no case or proof of ${BROWSER_SELFTEST}"
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

# findings <quality.yml> <selftests.yml>
findings() {
  job_findings "$1" "$2"
  groups_findings
  verdict_findings
}

OUT="$(findings "$WORKFLOW" "$SELFTESTS")"
if [[ -z "$OUT" ]]; then
  echo "  ok: the real workflows hold every pin"
else
  fail "the real workflows break a pin:"$'\n'"$OUT"
fi

OUT="$(tools_file_findings)"
if [[ -z "$OUT" ]]; then
  echo "  ok: the tools lists of the quality_2, macOS self-test and browser jobs hold every pin"
else
  fail "the tools lists break a pin:"$'\n'"$OUT"
fi

OUT="$(shard_findings)"
if [[ -z "$OUT" ]]; then
  echo "  ok: the shards of the browser gate self-test run every case once"
else
  fail "the shards of the browser gate self-test break a pin:"$'\n'"$OUT"
fi

# The main job's list (forsgren#591 step 2). The reach of its gates is read once
# and shared with the list mutants below, which change only the list.
MAIN_REACH="${TMP}/main_reach.txt"
main_reach > "$MAIN_REACH"
[[ -s "$MAIN_REACH" ]] || fail "the main job's gates reach no script: main_reach read no row"
OUT="$(main_tools_findings "$MAIN_REACH")"
if [[ -z "$OUT" ]]; then
  echo "  ok: the main job's tools list holds every pin"
else
  fail "the main job's tools list breaks a pin:"$'\n'"$OUT"
fi

# mutant_case <name> <sed-expression> <finding> [selftests]: one mutation proof,
# in the folder of its own (MUTANT_DIR) that Scripts/lib_parallel_mutants.sh
# gives it; the fourth argument mutates selftests.yml instead of quality.yml.
mutant_case() {
  local file="${MUTANT_DIR}/mutated.yml" src="$WORKFLOW" q="${MUTANT_DIR}/mutated.yml" s="$SELFTESTS"
  JOBS_TMP="$MUTANT_DIR"
  if [[ "${4:-}" == selftests ]]; then
    src="$SELFTESTS"
    q="$WORKFLOW"
    s="$file"
  fi
  sed "$2" "$src" > "$file"
  if cmp -s "$src" "$file"; then
    fail "the mutation $2 changed nothing: the proof of '$1' would be vacuous"
    return 0
  fi
  OUT="$(findings "$q" "$s")"
  if grep -qF -- "$3" <<< "$OUT"; then
    echo "  ok: mutation proof: $1"
  else
    fail "mutation proof: '$1' was not named '$3'. Findings: ${OUT:-none}"
  fi
}

# mutant <name> <sed-expression> <finding> [selftests]: starts the proof side by
# side with the others (mutants_wait below prints them in this order).
mutants_init "$TMP"
mutant() {
  mutant_run mutant_case "$@"
}

# The job ranges of quality.yml ...
Q='/^  quality:/,/^  quality_2:/'
Q2='/^  quality_2:/,/^  lint:/'
L='/^  lint:/,/^  browser_3:/'
B3='/^  browser_3:/,/^  workflows:/'
W='/^  workflows:/,/^  report:/'
R='/^  report:/,/^  preview:/'
# ... and of selftests.yml.
M1='/^  selftest_mac_1:/,/^  selftest_mac_2:/'
M2='/^  selftest_mac_2:/,/^  selftest_linux:/'
SL='/^  selftest_linux:/,/^  isolation_1:/'
I1='/^  isolation_1:/,/^  isolation_2:/'
I2='/^  isolation_2:/,/^  summary:/'
S='/^  summary:/,/^  browser_1:/'
B1='/^  browser_1:/,/^  browser_2:/'
B2='/^  browser_2:/,/^  report:/'
SR='/^  report:/,/^  failure_issue:/'
FI='/^  failure_issue:/,$'

# Every gate job: on its runner, with npm ci, handing over, judged by its
# report. <id>:<range>:<file>:<runner>
GATE_JOBS=(
  "quality_2@${Q2}@quality@macos-latest"
  "lint@${L}@quality@ubuntu-latest"
  "browser_3@${B3}@quality@ubuntu-latest"
  "workflows@${W}@quality@ubuntu-latest"
  "selftest_mac_1@${M1}@selftests@macos-latest"
  "selftest_mac_2@${M2}@selftests@macos-latest"
  "selftest_linux@${SL}@selftests@ubuntu-latest"
  "isolation_1@${I1}@selftests@ubuntu-latest"
  "isolation_2@${I2}@selftests@ubuntu-latest"
  "summary@${S}@selftests@ubuntu-latest"
  "browser_1@${B1}@selftests@ubuntu-latest"
  "browser_2@${B2}@selftests@ubuntu-latest"
)
for entry in "${GATE_JOBS[@]}"; do
  IFS='@' read -r j range wfile runner <<< "$entry"
  where=""
  rr="$R"
  if [[ "$wfile" == selftests ]]; then where=selftests; rr="$SR"; fi
  case "$runner" in macos-latest) other=ubuntu-latest ;; *) other=macos-latest ;; esac
  var="QS_$(tr '[:lower:]-' '[:upper:]_' <<< "$j")_RESULT"
  mutant "no ${j} job" "s/^  ${j}:/  ${j}_gone:/" "job: the file has no ${j} job" $where
  mutant "${j} on another runner" "${range}s/runs-on: ${runner}/runs-on: ${other}/" "runs-on: the ${j} job is not on ${runner}" $where
  mutant "${j} without npm ci" "${range}"'s/run: npm ci/run: true/' "setup: the ${j} job does not run npm ci" $where
  mutant "${j} without Node" "${range}"'s/- name: Set up Node/- name: Set up something/' "setup: the ${j} job's steps start" $where
  mutant "${j} hand-over not always" "${range}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the ${j} job's" $where
  mutant "${j} hand-over under another name" "${range}s/name: quality-report-${j}\$/name: quality-report-other/" "handover: the ${j} job does not upload the artifact quality-report-${j}" $where
  mutant "report without ${j} in needs" "${rr}s/^\\(    needs: \\[\\)${j}, /\\1/;${rr}s/^\\(    needs: .*\\) ${j},/\\1/;${rr}s/^\\(    needs: .*\\), ${j}\\]/\\1]/" "the gate job ${j} is not in the" $where
  mutant "report without the ${j} result" "${rr}"'{/'"${var}"':/d;}' "report job has no ${var} from needs.${j}.result" $where
  mutant "verdict without the ${j} result" "${rr}s/ \"${j}=[$]${var}\"//" "verdict does not pass \"${j}=\$${var}\"" $where
  if [[ "$runner" == ubuntu-latest ]]; then
    mutant "${j} without setup-go" "${range}"'s/- name: Set up Go$/- name: Set up something else/' "setup: the ${j} job's steps start" $where
    mutant "${j} setup-go not reading go.mod" "${range}"'s/go-version-file: go.mod/go-version: 1.27.3/' "setup-go: the ${j} job's Set up Go step does not read go.mod" $where
    mutant "${j} setup-go with the cache off" "${range}"'s/^\(          go-version-file: go.mod\)$/\1\
          cache: false/' "setup-go: the ${j} job's Set up Go step turns the cache off" $where
    mutant "${j} setup-go not pinned" "${range}"'s#\(actions/setup-go@\)[0-9a-f]\{40\}#\1v7#' "setup-go: the ${j} job's Set up Go step does not use actions/setup-go pinned" $where
    mutant "${j} setup-go may fail silently" "${range}"'s/^\(        uses: actions\/setup-go@.*\)$/\1\
        continue-on-error: true/' "setup-go: the ${j} job's Set up Go step has continue-on-error" $where
  fi
  if [[ "$j" != browser_3 ]]; then
    mutant "${j} runs the main job's gates" "${range}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" ${j}\$/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "${j}: the ${j} job must run exactly" $where
  fi
done
# Twins run their own job's rows, not the other's.
mutant "isolation_1 runs the other shard's job" "${I1}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation_1/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation_2/" "isolation_1: the isolation_1 job must run exactly" selftests
mutant "browser_2 runs the other shard's job" "${B2}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_2/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_1/" "browser_2: the browser_2 job must run exactly" selftests
mutant "selftest_mac_1 runs the other macOS job's rows" "${M1}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" selftest_mac_1/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" selftest_mac_2/" "selftest_mac_1: the selftest_mac_1 job must run exactly" selftests
# The install commands (pin 3g).
mutant "isolation_2 with the lint job's tools" "${I2}"'s#required_tools_linux_gates\.txt#required_tools_linux.txt#' "setup: the isolation_2 job does not run ${LINUX_GATES_INSTALL}" selftests
mutant "summary using the Homebrew installer" "${S}"'s#install_tools_linux\.sh Scripts/required_tools_linux_gates\.txt#install_tools.sh#' "setup: the summary job does not run ${LINUX_GATES_INSTALL}" selftests
mutant "workflows using the Homebrew installer" "${W}"'s#install_tools_linux\.sh Scripts/required_tools_linux_gates\.txt#install_tools.sh#' "setup: the workflows job does not run ${LINUX_GATES_INSTALL}"
mutant "lint using the Homebrew installer" "${L}"'s#install_tools_linux\.sh#install_tools.sh#' "setup: the lint job does not run ${LINT_INSTALL}"
mutant "lint on another Linux image" "${L}"'s/runs-on: ubuntu-latest/runs-on: ubuntu-22.04/' "runs-on: the lint job is not on ubuntu-latest"
mutant "selftest_linux with the isolation jobs' tools" "${SL}"'s#required_tools_linux\.txt#required_tools_linux_gates.txt#' "setup: the selftest_linux job does not run ${LINT_INSTALL}" selftests
for j in quality_2@"$Q2"@quality selftest_mac_1@"$M1"@selftests selftest_mac_2@"$M2"@selftests; do
  IFS='@' read -r jid jrange wfile <<< "$j"
  where=""
  [[ "$wfile" == selftests ]] && where=selftests
  mutant "${jid} installing the full tool list" "${jrange}"'s#install_tools\.sh Scripts/required_tools_[a-z0-9_]*_gates\.txt#install_tools.sh#' \
    "setup: the ${jid} job does not run Scripts/install_tools.sh $(tools_file_of "$jid")" $where
  mutant "${jid} installing another job's list" "${jrange}"'s#required_tools_[a-z0-9_]*_gates\.txt#required_tools_linux_gates.txt#' \
    "setup: the ${jid} job does not run Scripts/install_tools.sh $(tools_file_of "$jid")" $where
done
mutant "selftest_mac_2 installing the selftest_mac_1 list" "${M2}"'s#required_tools_selftest_mac_2_gates\.txt#required_tools_selftest_mac_1_gates.txt#' \
  "setup: the selftest_mac_2 job does not run Scripts/install_tools.sh $(tools_file_of selftest_mac_2)" selftests
for j in browser_1@"$B1"@selftests browser_2@"$B2"@selftests browser_3@"$B3"@quality; do
  IFS='@' read -r jid jrange wfile <<< "$j"
  where=""
  [[ "$wfile" == selftests ]] && where=selftests
  mutant "${jid} installing the full Linux tool list" "${jrange}"'s#install_tools_linux\.sh Scripts/required_tools_[a-z0-9_]*_gates\.txt#install_tools_linux.sh#' \
    "setup: the ${jid} job does not run Scripts/install_tools_linux.sh $(tools_file_of "$jid")" $where
  mutant "${jid} installing another job's list" "${jrange}"'s#required_tools_[a-z0-9_]*_gates\.txt#required_tools_linux_gates.txt#' \
    "setup: the ${jid} job does not run Scripts/install_tools_linux.sh $(tools_file_of "$jid")" $where
done
mutant "main installing the full tool list" "${Q}"'s#install_tools\.sh Scripts/required_tools_quality_gates\.txt#install_tools.sh#' \
  "setup: the quality job does not run Scripts/install_tools.sh $(tools_file_of quality)"
mutant "main installing another job's list" "${Q}"'s#required_tools_quality_gates\.txt#required_tools_browser_gates.txt#' \
  "setup: the quality job does not run Scripts/install_tools.sh $(tools_file_of quality)"
# The calls (pin 2).
mutant "main without its job name" "${Q}s/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\"/" "main: both run_ci_phase.sh calls of the main job"
mutant "main hand-over under another name" "${Q}"'s/name: quality-report-quality$/name: quality-report-other/' "handover: the quality job does not upload the artifact quality-report-quality"
mutant "browser_3 without its site build" "${B3}"'s#\./Scripts/build_site.sh#./Scripts/other.sh#' "browser_3: the browser_3 job must run its own site build"
mutant "browser_3 running the main job's gates" "${B3}s/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_3/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "browser_3: the browser_3 job must run exactly"
mutant "browser_3 with a PRE call again" "${B3}s#^          \\./Scripts/run_ci_phase.sh post \"[$]ROWS\" \"[$]DETAILS\" browser_3\$#          ./Scripts/run_ci_phase.sh pre \"\$ROWS\" \"\$DETAILS\" browser_3\\
          ./Scripts/run_ci_phase.sh post \"\$ROWS\" \"\$DETAILS\" browser_3#" "browser_3: the browser_3 job must run exactly"
for n in 1 2; do
  case "$n" in 1) BP="$B1" ;; *) BP="$B2" ;; esac
  mutant "browser_${n} builds a site" "${BP}"'s#\./Scripts/install_tools_linux.sh#./Scripts/install_tools_linux.sh; ./Scripts/build_site.sh#' "browser_${n}: the browser_${n} job builds a site" selftests
  mutant "a step naming the browser_${n} gate" "${BP}"'s#\./Scripts/install_tools_linux.sh#./Scripts/install_tools_linux.sh; ./Scripts/test_gate_browser.sh#' "browser: a step names a browser gate itself" selftests
done
mutant "a step naming a browser gate" "${B3}"'s#\./Scripts/install_tools_linux.sh#./Scripts/install_tools_linux.sh; ./Scripts/gate_browser.sh#' "browser: a step names a browser gate itself"
FIRST_SUM_GATE="$(gates_of summary | sed -n 1p)"
mutant "a step naming the summary gate" "${S}"'s#\./Scripts/install_tools_linux\.sh Scripts/required_tools_linux_gates\.txt#./Scripts/install_tools_linux.sh Scripts/required_tools_linux_gates.txt; ./Scripts/'"${FIRST_SUM_GATE}"'.sh#' "isolation: a step names an isolation gate itself" selftests
FIRST_ISO_GATE="$(gates_of isolation_1 | sed -n 1p)"
mutant "a step naming an isolation gate" "${I1}"'s#\./Scripts/install_tools_linux\.sh Scripts/required_tools_linux_gates\.txt#./Scripts/install_tools_linux.sh Scripts/required_tools_linux_gates.txt; ./Scripts/'"${FIRST_ISO_GATE}"'.sh#' "isolation: a step names an isolation gate itself" selftests
mutant "a step naming a lint gate" "${L}"'s#\./Scripts/install_tools_linux.sh#./Scripts/install_tools_linux.sh; ./Scripts/check_shellcheck.sh#' "lint: a step names a lint gate itself"
mutant "a step naming a lint self-test" "${SL}"'s#\./Scripts/install_tools_linux.sh#./Scripts/install_tools_linux.sh; ./Scripts/test_check_shellcheck.sh#' "lint: a step names a lint gate itself" selftests
FIRST_WF_GATE="$(gates_of workflows | sed -n 1p)"
mutant "a step naming a workflows gate" "${W}"'s#\./Scripts/install_tools_linux\.sh Scripts/required_tools_linux_gates\.txt#./Scripts/install_tools_linux.sh Scripts/required_tools_linux_gates.txt; ./Scripts/'"${FIRST_WF_GATE}"'.sh#' "workflows: a step names a workflows gate itself"
FIRST_SL_GATE="$(gates_of selftest_linux | grep -vE "$LINT_GATES" | sed -n 1p)"
mutant "a step naming a selftest_linux gate" "${SL}"'s#\./Scripts/install_tools_linux.sh#./Scripts/install_tools_linux.sh; ./Scripts/'"${FIRST_SL_GATE}"'.sh#' "selftest_linux: a step names a selftest_linux gate itself" selftests
for id in quality_2 selftest_mac_1 selftest_mac_2; do
  case "$id" in quality_2) rng="$Q2"; where="" ;; selftest_mac_1) rng="$M1"; where=selftests ;; *) rng="$M2"; where=selftests ;; esac
  FIRST_QN_GATE="$(gates_of "$id" | sed -n 1p)"
  mutant "a step naming a ${id} gate" "${rng}"'s#\./Scripts/install_tools.sh#./Scripts/install_tools.sh; ./Scripts/'"${FIRST_QN_GATE}"'.sh#' "${id}: a step names a ${id} gate itself" $where
done
# The split: a job in the other workflow.
mutant "a self-test job in Quality" 's/^  workflows:$/  isolation_1:/' "split: the self-test job isolation_1 is a job of ${WORKFLOW}"
mutant "a Quality job in Self-tests" 's/^  summary:$/  lint:/' "split: the Quality job lint is a job of ${SELFTESTS}" selftests
# The reports (pin 5).
mutant "report not always" "${R}"'s/^    if: always()/    if: success()/' "report: the Quality report job is not if: always()"
mutant "report on another runner" "${R}"'s/runs-on: ubuntu-latest/runs-on: macos-latest/' "report: the Quality report job is not on ubuntu-latest"
mutant "report needing report_start" "${R}"'s/needs: \[quality, quality_2,/needs: [report_start, quality, quality_2,/' "report: report_start in the Quality report job's needs: is not a gate job"
mutant "report without the merge" "${R}"'s#merge_quality_report.sh merge#merge_quality_report.sh combine#' "report: the Quality report job does not merge the hand-overs"
mutant "report status not merged" "${R}"'s#merge_quality_report.sh status#merge_quality_report.sh state#' "report: QS_JOB_STATUS is not taken from"
mutant "status without the lint result" "${R}"'s/ "[$]QS_LINT_RESULT"//' "report: the status call does not pass \"\$QS_LINT_RESULT\""
mutant "report without its view" "${R}"'s#merge_quality_report.sh view#merge_quality_report.sh glance#' "report: the Quality report job makes no view"
mutant "report viewing a self-test job" "${R}"'s#            main quality_2 lint browser_3 workflows#            main quality_2 lint browser_3 workflows summary#' "report: the Quality report job's view names the jobs"
mutant "report viewing no main job" "${R}"'s#            main quality_2 lint#            quality_2 lint#' "report: the Quality report job's view names the jobs"
mutant "report rendering the whole order file" "${R}"'s#\(render_quality_report.sh "[$]rows" "[$]details"\) "[$]order"#\1#' "report: the Quality report job does not render the gate table on its view"
mutant "summary on the whole order file" "${R}"'s#\(render_quality_summary.sh "[$]rows" "[$]details"\) "[$]order"#\1#' "report: the Quality report job does not render the summary on its view"
mutant "summary on the whole group file" "${R}"'{/export QS_JOB_GROUPS=/d;}' "report: the Quality report job does not pass its view of the group file as QS_JOB_GROUPS"
mutant "selftests report not always" "${SR}"'s/^    if: always()/    if: success()/' "report: the Self-tests report job is not if: always()" selftests
mutant "selftests report without the merge" "${SR}"'s#merge_quality_report.sh merge#merge_quality_report.sh combine#' "report: the Self-tests report job does not merge the hand-overs" selftests
mutant "selftests report without its view" "${SR}"'s#merge_quality_report.sh view#merge_quality_report.sh glance#' "report: the Self-tests report job makes no view" selftests
mutant "selftests report viewing the main job" "${SR}"'s#            selftest_mac_1 selftest_mac_2#            main selftest_mac_1 selftest_mac_2#' "report: the Self-tests report job's view names the jobs" selftests
mutant "selftests report needing a ghost" "${SR}"'s/needs: \[selftest_mac_1,/needs: [ghost, selftest_mac_1,/' "report: ghost in the Self-tests report job's needs: is not a gate job" selftests
mutant "a softened job" "${I1}"'s/^    runs-on: ubuntu-latest/    continue-on-error: true\
    runs-on: ubuntu-latest/' "verdict: continue-on-error softens a failure" selftests
# The failure issue (pin 9).
mutant "no failure issue job" 's/^  failure_issue:/  failure_issue_gone:/' "failure issue: ${SELFTESTS} has no failure_issue job" selftests
mutant "failure issue on every red run" "${FI}"'s/^    if: failure() \&\& github.event_name == .push.$/    if: failure()/' "failure issue: the failure_issue job is not if: failure() && github.event_name == 'push'" selftests
mutant "failure issue before the report" "${FI}"'s/, report\]/]/' "failure issue: the job report is not in the failure_issue job's needs:" selftests
mutant "failure issue without the write" "${FI}"'{/issues: write/d;}' "failure issue: the failure_issue job does not hold issues: write" selftests
mutant "issues: write for the whole workflow" 's/^  contents: read$/  contents: read\
  issues: write/' "failure issue: another part of ${SELFTESTS} holds issues: write" selftests
mutant "failure issue without its script" "${FI}"'s#run: ./Scripts/open_selftests_failure_issue.sh#run: echo red#' "failure issue: the failure_issue job does not run Scripts/open_selftests_failure_issue.sh" selftests
mutant "failure issue with another token" "${FI}"'s/GH_TOKEN: [$]{{ github.token }}/GH_TOKEN: some-other-token/' "failure issue: the failure_issue job does not give gh the job's own token" selftests
mutants_wait

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
sed 's#^isolation_2|\(.*\)|--shard 2/2$#isolation_2|\1|--shard 1/2#' "$GROUPS_FILE" > "${VERDICT_TMP}/twice.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/twice.txt" groups_findings)"
expect_named "a group file whose two isolation jobs run the same shard" "one shard each"
sed 's#^isolation_2|git sandbox isolation self-test|--shard 2/2$#isolation_2|git sandbox isolation self-test#' "$GROUPS_FILE" > "${VERDICT_TMP}/noargs.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/noargs.txt" groups_findings)"
expect_named "a group file whose second isolation job runs no shard" "one shard each"
grep -v '^lint|' "$GROUPS_FILE" > "${VERDICT_TMP}/nolint.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nolint.txt" groups_findings)"
expect_named "a group file that leaves the lint rows in the main job" "the lint job actionlint, shellcheck, yamllint, zizmor"
grep -v '^summary|' "$GROUPS_FILE" > "${VERDICT_TMP}/nosummary.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nosummary.txt" groups_findings)"
expect_named "a group file that leaves the step summary gate in the main job" "the summary job the step summary isolation gate"
grep -v '^workflows|' "$GROUPS_FILE" > "${VERDICT_TMP}/noworkflows.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/noworkflows.txt" groups_findings)"
expect_named "a group file that leaves the workflow pins in the main job" "the workflows job gate wiring"
grep -v '^quality_2|Go coverage$' "$GROUPS_FILE" > "${VERDICT_TMP}/nocov.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nocov.txt" groups_findings)"
expect_named "a group file that leaves Go coverage apart from Go tests" "the quality_2 job the five gates"
grep -vx 'selftest_mac_2|private-names self-test' "$GROUPS_FILE" > "${VERDICT_TMP}/nom2gate.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nom2gate.txt" groups_findings)"
expect_named "a self-test left out of its group (back in Quality's main job)" "the self-test jobs selftest_mac_1, selftest_mac_2 and selftest_linux"
{ cat "$GROUPS_FILE"; echo 'selftest_mac_1|privacy-posture self-test'; } > "${VERDICT_TMP}/m1dup.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/m1dup.txt" groups_findings)"
expect_named "a self-test given to its job twice" "union: a gate is given to the same job twice: selftest_mac_1|privacy-posture self-test"
if grep -qF 'union: a gate is in two jobs' <<< "$OUT"; then
  fail "mutation proof: a self-test given to its job twice was named as a gate in two jobs. Findings: ${OUT}"
fi
{ cat "$GROUPS_FILE"; echo 'selftest_mac_2|privacy-posture self-test'; } > "${VERDICT_TMP}/m1twojobs.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/m1twojobs.txt" groups_findings)"
expect_named "a self-test in two self-test jobs" "union: a gate is in two jobs, not as one shard each: privacy-posture self-test"
mkdir -p "${VERDICT_TMP}/order"
sed 's/^privacy-posture self-test|\(Scripts\/[a-z_]*\.sh\)|pre|/privacy-posture self-test|\1|post|/' "$ORDER" > "${VERDICT_TMP}/order/m1post.txt"
cmp -s "$ORDER" "${VERDICT_TMP}/order/m1post.txt" && fail "the mutation of the privacy-posture self-test's phase changed nothing"
OUT="$(ORDER="${VERDICT_TMP}/order/m1post.txt" groups_findings)"
expect_named "a selftest_mac_1 gate that is a post row" "the selftest_mac_1 gate 'privacy-posture self-test' is no pre row"
sed 's/^browser gate|\(Scripts\/[a-z_]*\.sh\)|post|/browser gate|\1|pre|/' "$ORDER" > "${VERDICT_TMP}/order/b3pre.txt"
cmp -s "$ORDER" "${VERDICT_TMP}/order/b3pre.txt" && fail "the mutation of the browser gate's phase changed nothing"
OUT="$(ORDER="${VERDICT_TMP}/order/b3pre.txt" groups_findings)"
expect_named "a browser_3 gate that is a pre row" "the browser_3 gate 'browser gate' is no post row"
{ cat "$GROUPS_FILE"; echo 'lint|golden pages'; } > "${VERDICT_TMP}/twojobs.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/twojobs.txt" groups_findings)"
expect_named "a gate in quality_2 and in another job" "union: a gate is in two jobs, not as one shard each: golden pages"
sed 's#^browser_1|browser gate self-test|--shard 1/2$#browser_1|browser gate self-test#; s#^browser_2|browser gate self-test|--shard 2/2$#browser_2|browser gate self-test#' "$GROUPS_FILE" > "${VERDICT_TMP}/nob1.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nob1.txt" groups_findings)"
expect_named "the browser gate self-test whole in browser_1 and in browser_2" "union: a gate is in two jobs, not as one shard each: browser gate self-test"
sed 's#^browser_2|browser gate self-test|--shard 2/2$#browser_2|browser gate self-test|--shard 1/2#' "$GROUPS_FILE" > "${VERDICT_TMP}/b1same.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/b1same.txt" groups_findings)"
expect_named "the two browser jobs running the same shard of the browser gate self-test" "union: a gate is in two jobs, not as one shard each: browser gate self-test"
sed 's/^browser_1|browser gate (fixture site) self-test$/browser_3|browser gate (fixture site) self-test/' "$GROUPS_FILE" > "${VERDICT_TMP}/nofx.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nofx.txt" groups_findings)"
expect_named "a group file that moves the fixture site self-test back to browser_3" "the browser_1 job the browser gate self-test --shard 1/2 and the fixture site self-test"
sed 's/^browser_2|browser gate process self-test$/browser_3|browser gate process self-test/' "$GROUPS_FILE" > "${VERDICT_TMP}/noproc.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/noproc.txt" groups_findings)"
expect_named "a group file that moves the process self-test to browser_3" "the browser_2 job its --shard 2/2 and the browser gate process self-test"
{ cat "$GROUPS_FILE"; echo 'browser_3|browser gate self-test'; } > "${VERDICT_TMP}/b1twice.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/b1twice.txt" groups_findings)"
expect_named "the browser gate self-test whole in browser_3 besides its shards" "union: a gate is in two jobs, not as one shard each: browser gate self-test"
# Pin 3g, the lists: each mutant is a copy of the lists in a directory of its own.
for j in $OWN_LIST_JOBS; do
  f="$(tools_file_of "$j")"
  [[ -f "$f" ]] && cp "$f" "${VERDICT_TMP}/"
done
mkdir -p "${VERDICT_TMP}/nojq" "${VERDICT_TMP}/nonode" "${VERDICT_TMP}/extra" "${VERDICT_TMP}/empty" "${VERDICT_TMP}/m1nojq"
for d in nojq nonode extra empty m1nojq; do
  cp "${VERDICT_TMP}"/required_tools_*_gates.txt "${VERDICT_TMP}/${d}/" 2> /dev/null || true
done
OUT="$(TOOLS_DIR="${VERDICT_TMP}/none" tools_file_findings)"
expect_named "no tools lists" "does not exist or is empty"
grep -vx 'jq' "$(tools_file_of quality_2)" > "${VERDICT_TMP}/nojq/required_tools_quality_2_gates.txt" || true
OUT="$(TOOLS_DIR="${VERDICT_TMP}/nojq" tools_file_findings)"
expect_named "a quality_2 list without jq" "lists 'go node ', the quality_2 job needs 'go jq node '"
expect_named "the Go coverage gate that calls jq" "the quality_2 gate check_coverage calls jq"
grep -vx 'jq' "$(tools_file_of selftest_mac_1)" > "${VERDICT_TMP}/m1nojq/required_tools_selftest_mac_1_gates.txt" || true
OUT="$(TOOLS_DIR="${VERDICT_TMP}/m1nojq" tools_file_findings)"
expect_named "a selftest_mac_1 list without jq" "lists 'go node ', the selftest_mac_1 job needs 'go jq node '"
expect_named "the Go coverage self-test that reaches jq" "the selftest_mac_1 gate test_check_coverage reaches jq in Scripts/check_coverage.sh"
grep -vx 'node' "$(tools_file_of browser_3)" > "${VERDICT_TMP}/nonode/required_tools_browser_3_gates.txt" || true
OUT="$(TOOLS_DIR="${VERDICT_TMP}/nonode" tools_file_findings)"
expect_named "a browser_3 list without node" "lists 'go ', the browser_3 job needs 'go node '"
expect_named "the browser gate that calls node" "the browser_3 gate gate_browser calls node"
grep -vx 'node' "$(tools_file_of browser_2)" > "${VERDICT_TMP}/nonode/required_tools_browser_2_gates.txt" || true
OUT="$(TOOLS_DIR="${VERDICT_TMP}/nonode" tools_file_findings)"
expect_named "a browser_2 list without node" "lists '', the browser_2 job needs 'node '"
expect_named "the process self-test that calls node" "the browser_2 gate test_gate_browser_process calls node"
{ cat "$(tools_file_of browser_1)" 2> /dev/null || true; echo 'jq'; } > "${VERDICT_TMP}/extra/required_tools_browser_1_gates.txt"
OUT="$(TOOLS_DIR="${VERDICT_TMP}/extra" tools_file_findings)"
expect_named "a browser_1 list with a tool its gates do not need" "lists 'go jq node ', the browser_1 job needs 'go node '"
grep -vx 'go' "$(tools_file_of browser_1)" > "${VERDICT_TMP}/extra/required_tools_browser_1_gates.txt" || true
OUT="$(TOOLS_DIR="${VERDICT_TMP}/extra" tools_file_findings)"
expect_named "a browser_1 list without go, which its fixture site self-test needs" "lists 'node ', the browser_1 job needs 'go node '"
expect_named "the fixture site self-test that reaches go" "the browser_1 gate test_gate_browser_fixture reaches go"
: > "${VERDICT_TMP}/empty/required_tools_browser_1_gates.txt"
OUT="$(TOOLS_DIR="${VERDICT_TMP}/empty" tools_file_findings)"
expect_named "an empty browser_1 list" "required_tools_browser_1_gates.txt does not exist or is empty"

# A tool needed two calls deep (forsgren#447, step 9): a copy of Scripts/ where the browser_2
# gate calls a script that calls a script that runs jq, which the browser_2 list lacks.
DEEP="${VERDICT_TMP}/deep"
mkdir -p "$DEEP"
cp -R Scripts "${DEEP}/Scripts"
printf '%s\n' './Scripts/zz_deep_mid.sh' >> "${DEEP}/Scripts/test_gate_browser.sh"
printf '%s\n' '#!/usr/bin/env bash' './Scripts/zz_deep_end.sh' > "${DEEP}/Scripts/zz_deep_mid.sh"
printf '%s\n' '#!/usr/bin/env bash' 'jq . /dev/null' > "${DEEP}/Scripts/zz_deep_end.sh"
OUT="$(cd "$DEEP" && tools_file_findings)"
expect_named "a tool two calls below a gate" "the browser_2 gate test_gate_browser reaches jq in Scripts/zz_deep_end.sh"

# Pin 3h, the shards (forsgren#641): each mutant is a copy of the browser gate
# self-test, with the two files its --list reads, in a folder of its own.
shard_copy() {
  mkdir -p "${VERDICT_TMP}/$1/Scripts"
  cp Scripts/test_gate_browser.sh Scripts/lib_isolation_shard.sh Scripts/browser_gate_selftest_weights.txt "${VERDICT_TMP}/$1/Scripts/"
  echo "${VERDICT_TMP}/$1/Scripts/test_gate_browser.sh"
}
# shard_sed_mutant <folder> <label> <sed-expression>: OUT is what shard_findings
# says of a copy (SHARD_MUT) whose self-test the sed changed; a sed that changed
# nothing fails, since it would prove nothing.
shard_sed_mutant() {
  SHARD_MUT="$(shard_copy "$1")"
  sed -i.bak "$3" "$SHARD_MUT"
  if cmp -s "$SHARD_MUT" Scripts/test_gate_browser.sh; then
    fail "the shard mutant '${2}' changed nothing"
  fi
  OUT="$(BROWSER_SELFTEST="$SHARD_MUT" shard_findings)"
}
shard_sed_mutant shard_all "every shard deals shard 1" 's/shard_assign "[$]SHARD_N" /shard_assign 1 /'
expect_named "every shard running the cases of shard 1" "run in two jobs of the browser gate self-test"
shard_sed_mutant shard_nofollow "no followers of case 8" 's/tr . . .[\]n. <<< "[$]{entry#[*] }"/:/'
expect_named "the cases that wait for case 8 dealt to no shard" "the cases case_19 case_20 case_21 mutant_b run in no job of the browser gate self-test"
SHARD_MUT="$(shard_copy shard_unlisted)"
printf '%s\n' 'case_99() { :; }' >> "$SHARD_MUT"
OUT="$(BROWSER_SELFTEST="$SHARD_MUT" shard_findings)"
expect_named "a case function in no list of the run" "shard: case_99 are in ${SHARD_MUT} but in no list of its whole run"
sed 's#^browser_2|browser gate self-test|--shard 2/2$#browser_2|browser gate self-test#' "$GROUPS_FILE" > "${VERDICT_TMP}/oneshard.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/oneshard.txt" shard_findings)"
expect_named "a group file that runs one shard and the whole self-test" "run in two jobs of the browser gate self-test"
SHARD_MUT="$(shard_copy shard_ghostrow)"
printf '%s\n' 'case_ghost 5' >> "${SHARD_MUT%/*}/browser_gate_selftest_weights.txt"
OUT="$(BROWSER_SELFTEST="$SHARD_MUT" shard_findings)"
expect_named "a weights row for a case the self-test does not have" "shard: the weights rows case_ghost name no case or proof"

# The main job's list (forsgren#591 step 2): each mutant a copy of the list in a
# directory of its own, read against the reach of the real gates.
mkdir -p "${VERDICT_TMP}/nolt" "${VERDICT_TMP}/mainextra" "${VERDICT_TMP}/mainnone"
grep -vx 'languagetool' "$(tools_file_of quality)" > "${VERDICT_TMP}/nolt/required_tools_quality_gates.txt" || true
OUT="$(TOOLS_DIR="${VERDICT_TMP}/nolt" main_tools_findings "$MAIN_REACH")"
expect_named "a main list without languagetool" "lists 'gitleaks go jq node ', the quality job needs '${MAIN_WANT}'"
expect_named "the language gate that runs languagetool" "the quality gate gate_language_pages runs languagetool in Scripts/gate_language.sh"
{ cat "$(tools_file_of quality)" 2> /dev/null || true; echo 'shellcheck'; } > "${VERDICT_TMP}/mainextra/required_tools_quality_gates.txt"
OUT="$(TOOLS_DIR="${VERDICT_TMP}/mainextra" main_tools_findings "$MAIN_REACH")"
expect_named "a main list with a lint tool its gates do not run" "lists 'gitleaks go jq languagetool node shellcheck ', the quality job needs '${MAIN_WANT}'"
OUT="$(TOOLS_DIR="${VERDICT_TMP}/mainnone" main_tools_findings "$MAIN_REACH")"
expect_named "no main list" "required_tools_quality_gates.txt does not exist or is empty"
# A lint tool run two calls below a main gate: a copy of Scripts/ where the
# community files gate calls a script that runs shellcheck, read through an
# order file of that one row, so the reach is computed in the copy.
MDEEP="${VERDICT_TMP}/maindeep"
mkdir -p "$MDEEP"
cp -R Scripts "${MDEEP}/Scripts"
printf '%s\n' './Scripts/zz_main_mid.sh' >> "${MDEEP}/Scripts/check_community_files.sh"
printf '%s\n' '#!/usr/bin/env bash' './Scripts/zz_main_end.sh' > "${MDEEP}/Scripts/zz_main_mid.sh"
printf '%s\n' '#!/usr/bin/env bash' 'shellcheck -x Scripts/zz_main_mid.sh' > "${MDEEP}/Scripts/zz_main_end.sh"
grep -F 'community files|Scripts/check_community_files.sh|' "$ORDER" > "${MDEEP}/order.txt"
OUT="$(cd "$MDEEP" && ORDER="${MDEEP}/order.txt" main_tools_findings)"
expect_named "a lint tool two calls below a main gate" "the quality gate check_community_files runs shellcheck in Scripts/zz_main_end.sh"

sed 's/^shellcheck|Scripts\/check_shellcheck.sh|pre|/shellcheck|Scripts\/check_shellcheck.sh|post|/' "$ORDER" > "${VERDICT_TMP}/order/gate_report_order.txt"
OUT="$(ORDER="${VERDICT_TMP}/order/gate_report_order.txt" groups_findings)"
expect_named "a lint row moved to post" "the lint gate 'shellcheck' is no pre row"

mkdir -p "${VERDICT_TMP}/rq"
sed 's/--json status,conclusion,url/--json status,conclusion,url,jobs/' "$RELEASE_CHECK" > "${VERDICT_TMP}/rq/release_quality.sh"
OUT="$(RELEASE_CHECK="${VERDICT_TMP}/rq/release_quality.sh" verdict_findings)"
expect_named "a release check that reads a job" "reads a job, not the run"

selftest_end "the quality jobs pin found failures" "quality jobs pin (the real workflows hold every pin; each mutant is named)"
