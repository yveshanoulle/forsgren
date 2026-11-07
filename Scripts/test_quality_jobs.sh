#!/usr/bin/env bash
# Scripts/test_quality_jobs.sh
#
# Pins the job layout of .github/workflows/quality.yml (forsgren#259, decision
# #260), forsgren's own: Quality runs its slowest gates in parallel jobs of ONE
# workflow, and stays one verdict. Steps 2 and 3: the isolation job and the
# browser job; forsgren#282: the lint job. The pins, each proved by a mutant of the real file that breaks it
# and must be named:
#   1. an isolation job exists, with the same setup as the main job:
#      checkout at the same pin, the gate environment, Node, tool install and
#      npm ci, in that order; on ubuntu-latest since forsgren#447, step 3, as
#      the summary, workflows and report jobs, installing the tools of
#      Scripts/required_tools_linux_gates.txt with Scripts/install_tools_linux.sh
#      (the main, quality_2, browser_1, browser_2 and browser_3 jobs stay on
#      macos-latest)
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
#   3b. the browser_3 job (step 3; `browser` up to forsgren#641) has the same
#      setup, runs run_ci_phase.sh pre, then Scripts/build_site.sh (its own
#      site build), then run_ci_phase.sh post, both for the job `browser_3`;
#      no step names a browser gate itself; the group file gives it the
#      browser gate and the browser gate (fixture site) with its self-test
#      (forsgren#641: the browser gate self-test is sharded over browser_1 and
#      browser_2, and the process self-test, forsgren#386, is in browser_2)
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
#      zizmor with their self-tests and, since forsgren#447 step 5, Go lint
#      with its self-test (Go ships with the Linux image), and, since forsgren#591,
#      the Go test duplication gate (the same go.mod golangci-lint as Go lint;
#      its self-test already ran on Linux in the workflows job), so the main job
#      no longer runs them (the order file is unchanged: the rows keep their pre
#      phase and place)
#   3d. the workflows job (forsgren#408) has the same setup and runs exactly
#      run_ci_phase.sh pre for the job `workflows`; no step names one of its
#      gates itself; the group file gives it the gates that read only the
#      workflows and the wiring of the gates (gate wiring, the checkout pins
#      and their mutations, the metrics, release, starter page, vulncheck,
#      auto-update and preview workflow pins and this pin, and, since
#      forsgren#447 step 6, go mod tidy and the Go test duplication and Go
#      vulnerabilities self-tests, and, since step 8b, eleven Linux-safe tail
#      gates of the main job, 85 s), about 260 s, 85 s and 85 s that the
#      main job no longer runs, so the main job is no longer the critical path
#   3e. the quality_2 job (forsgren#447) has the same setup and runs exactly
#      run_ci_phase.sh pre for the job `quality_2`; no step names one of its
#      gates itself; the group file gives it nine gates of the main job, the Go
#      tests and the Go coverage gate (it reads the profile the Go tests gate writes, so
#      the two stay together), about 180 s since step 5; the jobs' gates together are the
#      order file's rows, each once (union_findings)
#   3f. the browser_1 and browser_2 jobs (forsgren#447, #641) have the same
#      setup and each runs exactly run_ci_phase.sh pre for its own job name,
#      with no site build: the group file gives browser_1 the browser gate
#      self-test --shard 1/2 and browser_2 its --shard 2/2 with the browser
#      gate process self-test; a gate is in two jobs only as one shard each
#   3g. the tools each macOS job installs (forsgren#447, step 4): quality_2,
#      browser_1, browser_2 and browser_3 pass their own list,
#      Scripts/required_tools_<job>_gates.txt, which exists and lists exactly
#      the tools its gates need (node for browser_1 and browser_2, go and node
#      for browser_3, go, node and jq for quality_2), and no gate of a job
#      names a tool of Scripts/required_tools.txt that the job's list lacks (a
#      missing tool must fail the gate, not skip it); since forsgren#591 step 2
#      the main job (id `quality`) passes its list too,
#      Scripts/required_tools_quality_gates.txt: gitleaks, go, jq, languagetool
#      and node, the full list less the four lint tools, whose gates all run in
#      the lint job (main_tools_findings: no script a main gate reaches, other
#      than another job's gate, runs a tool the list lacks)
#   3h. the shards of the browser gate self-test (forsgren#641): the group
#      file runs it as --shard 1/2 and 2/2; `--list` makes the self-test print
#      the cases and proofs it would run and stop, so with --shard N/M --list
#      each shard lists at least one, the shards together list every case and
#      proof of the whole run once and none twice, and every case_ and mutant_
#      function of the script and every id of its SERIAL_CASES is listed
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
# The lint job runs on ubuntu-latest (forsgren#427) and installs its four tools
# with Scripts/install_tools_linux.sh and the Linux list; the workflows, summary
# and isolation jobs run on ubuntu-latest too (forsgren#447, step 3) and install
# with the same installer from their own list (LINUX_GATES_INSTALL).
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
# than lint (forsgren#447, step 3): the pinned Linux installer with the list of
# the tools their gates run (shellcheck and yamllint, for the self-tests the
# isolation shards run), not the lint job's list.
LINUX_GATES_INSTALL="Scripts/install_tools_linux.sh Scripts/required_tools_linux_gates.txt"

# tools_file_of <job>: the tools list of a macOS gate job (forsgren#447, step 4),
# named after the job; the main job's id is quality (forsgren#591 step 2).
tools_file_of() {
  echo "Scripts/required_tools_${1}_gates.txt"
}

# TOOLS_DIR: where tools_file_findings reads the lists from (a mutant points it
# at a copy); the lists are Scripts/required_tools_<job>_gates.txt.
TOOLS_DIR="Scripts"

# listed_tools <file>: the tools of a list as Scripts/install_tools.sh reads it
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

# tools_file_findings: pin 3g, the lists. Each exists and holds exactly the
# tools its job needs, and no gate of the job, nor a script it names however
# deep (forsgren#447, step 9), calls a tool of the full list that the job's list lacks.
tools_file_findings() {
  local job file want listed missing tool script reached
  for job in quality_2 browser_1 browser_2 browser_3; do
    file="${TOOLS_DIR}/$(basename "$(tools_file_of "$job")")"
    if [[ ! -s "$file" ]]; then
      echo "tools: ${file} does not exist or is empty"
      continue
    fi
    case "$job" in
      quality_2) want='go jq node ' ;;
      browser_1 | browser_2) want='node ' ;;
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
        for tool in $missing; do
          code "$reached" | has -E "$(tool_pattern "$tool")" || continue
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

# job_findings <file>: pins 1 to 5.
job_findings() {
  local wf="$1" main q2 lnt iso sum pre_job b3 wfl rep calls id others needs listed pre_line build_line post_line n
  main="${JOBS_TMP}/main.yml"
  q2="${JOBS_TMP}/quality_2.yml"
  lnt="${JOBS_TMP}/lint.yml"
  sum="${JOBS_TMP}/summary.yml"
  b3="${JOBS_TMP}/browser_3.yml"
  wfl="${JOBS_TMP}/workflows.yml"
  rep="${JOBS_TMP}/report.yml"
  job_of "$wf" quality > "$main"
  job_of "$wf" quality_2 > "$q2"
  job_of "$wf" lint > "$lnt"
  for n in 1 2; do
    job_of "$wf" "isolation_${n}" > "${JOBS_TMP}/isolation_${n}.yml"
  done
  job_of "$wf" summary > "$sum"
  for n in 1 2 3; do
    job_of "$wf" "browser_${n}" > "${JOBS_TMP}/browser_${n}.yml"
  done
  job_of "$wf" workflows > "$wfl"
  job_of "$wf" report > "$rep"

  setup_findings "$q2" quality_2 macos-latest "Scripts/install_tools.sh $(tools_file_of quality_2)"
  code "$main" | has -xF "          ./Scripts/install_tools.sh $(tools_file_of quality)" \
    || echo "setup: the quality job does not run Scripts/install_tools.sh $(tools_file_of quality)"
  setup_findings "$lnt" lint ubuntu-latest "Scripts/install_tools_linux.sh Scripts/required_tools_linux.txt"
  for n in 1 2; do
    setup_findings "${JOBS_TMP}/isolation_${n}.yml" "isolation_${n}" ubuntu-latest "$LINUX_GATES_INSTALL"
  done
  setup_findings "$sum" summary ubuntu-latest "$LINUX_GATES_INSTALL"
  for n in 1 2 3; do
    setup_findings "${JOBS_TMP}/browser_${n}.yml" "browser_${n}" macos-latest "Scripts/install_tools.sh $(tools_file_of "browser_${n}")"
  done
  setup_findings "$wfl" workflows ubuntu-latest "$LINUX_GATES_INSTALL"
  handover_findings "$main" quality
  handover_findings "$q2" quality_2
  handover_findings "$lnt" lint
  for n in 1 2; do
    handover_findings "${JOBS_TMP}/isolation_${n}.yml" "isolation_${n}"
  done
  handover_findings "$sum" summary
  for n in 1 2 3; do
    handover_findings "${JOBS_TMP}/browser_${n}.yml" "browser_${n}"
  done
  handover_findings "$wfl" workflows

  if [[ -s "$b3" ]]; then
    calls="$(phase_calls "$b3")"
    [[ "$(grep -cE " \"[$]DETAILS\" browser_3( |\$)" <<< "$calls")" == 2 && "$(wc -l <<< "$calls" | tr -d ' ')" == 2 ]] \
      || echo "browser_3: the browser_3 job must run run_ci_phase.sh pre and post, each ending with the job name browser_3, got: ${calls:-none}"
    pre_line="$(line_of "$b3" './Scripts/run_ci_phase.sh pre')"
    build_line="$(line_of "$b3" './Scripts/build_site.sh')"
    post_line="$(line_of "$b3" './Scripts/run_ci_phase.sh post')"
    if [[ -z "$build_line" ]] || ! later "$build_line" "$pre_line" || ! later "$post_line" "$build_line"; then
      echo "browser_3: the browser_3 job must run PRE, then its own site build (Scripts/build_site.sh), then POST: the browser gate reads the built site"
    fi
  fi
  for n in 1 2; do
    pre_job="${JOBS_TMP}/browser_${n}.yml"
    [[ -s "$pre_job" ]] || continue
    calls="$(phase_calls "$pre_job")"
    [[ "$calls" == *"run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_${n}" && "$(wc -l <<< "$calls" | tr -d ' ')" == 1 ]] \
      || echo "browser_${n}: the browser_${n} job must run exactly ./Scripts/run_ci_phase.sh pre \"\$ROWS\" \"\$DETAILS\" browser_${n}, got: ${calls:-none}"
    if code "$pre_job" | has -F './Scripts/build_site.sh'; then
      echo "browser_${n}: the browser_${n} job builds a site; its gates are PRE rows that read no built site"
    fi
  done
  if code "$wf" | has -E 'test_gate_browser|gate_browser'; then
    echo "browser: a step names a browser gate itself; ${GROUPS_FILE} and the order file decide which gates a job runs"
  fi

  calls="$(phase_calls "$main")"
  [[ "$(grep -cE " \"[$]DETAILS\" main( |\$)" <<< "$calls")" == 2 ]] \
    || echo "main: both run_ci_phase.sh calls of the main job must end with the job name main, got: ${calls:-none}"
  for n in 1 2; do
    iso="${JOBS_TMP}/isolation_${n}.yml"
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
    grep -qxF '    runs-on: ubuntu-latest' "$rep" || echo "report: the report job is not on ubuntu-latest"
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
# Q2_ROWS: the gates the quality_2 job runs (forsgren#447): the Go tests with
# the Go coverage gate that reads their profile (.build/go-coverage.out), and
# the long tail of the main job, all PRE rows that need no built site. The Go
# lint pair is in the lint job and go mod tidy with the two self-tests of the
# Go test duplication and Go vulnerabilities gates in the workflows job (steps
# 5 and 6): Go-only gates that run on Linux.
Q2_ROWS=('quality_2|Go tests' 'quality_2|Go coverage'
  'quality_2|browser gate inputs self-test' 'quality_2|golden pages'
  'quality_2|git sandbox isolation scope self-test' 'quality_2|exit-trap completion behaviour'
  'quality_2|CI phase runner self-test' 'quality_2|quality-run summary'
  'quality_2|markdown-links self-test' 'quality_2|HTMLHint self-test'
  'quality_2|html duplication, generated page self-test')

groups_findings() {
  local rows labels
  labels="$(printf '%s\n' 'isolation_1|git sandbox isolation self-test|--shard 1/2' 'isolation_2|git sandbox isolation self-test|--shard 2/2' 'summary|step summary isolation' \
    'browser_1|browser gate self-test|--shard 1/2' 'browser_2|browser gate self-test|--shard 2/2' 'browser_2|browser gate process self-test' \
    'browser_3|browser gate (fixture site) self-test' 'browser_3|browser gate' 'browser_3|browser gate (fixture site)' \
    'lint|actionlint self-test' 'lint|actionlint forsgren cases self-test' 'lint|actionlint' \
    'lint|shellcheck self-test' 'lint|shellcheck' 'lint|yamllint self-test' 'lint|yamllint' \
    'lint|zizmor self-test' 'lint|zizmor' 'lint|Go lint self-test' 'lint|Go lint' 'lint|Go test duplication' \
    "${Q2_ROWS[@]}" \
    'workflows|gate wiring' 'workflows|mutation: checkout pins' 'workflows|metrics workflow' 'workflows|release workflow' \
    'workflows|starter page workflow' 'workflows|quality jobs pin' 'workflows|preview workflow' \
    'workflows|vulncheck workflow' 'workflows|auto-update workflow' \
    'workflows|go mod tidy' 'workflows|Go test duplication self-test' 'workflows|Go vulnerabilities self-test' \
    'workflows|release pins self-test' 'workflows|browser gate selection self-test' 'workflows|Go tests self-test' \
    'workflows|release precheck self-test' 'workflows|community-files self-test' 'workflows|DCO sign-off self-test' \
    'workflows|sfl drives from the order file' 'workflows|release plan self-test' 'workflows|release report self-test' \
    'workflows|release check self-test' 'workflows|release metrics self-test' \
    | LC_ALL=C sort | tr '\n' ';')"
  [[ -f "$GROUPS_FILE" ]] || { echo "groups: ${GROUPS_FILE} does not exist"; return 0; }
  rows="$(grep -v '^#' "$GROUPS_FILE" | grep . | LC_ALL=C sort | tr '\n' ';')"
  [[ "$rows" == "$labels" ]] \
    || echo "groups: ${GROUPS_FILE} must give the two isolation jobs the git sandbox isolation self-test, one shard each (isolation_1 with --shard 1/2, isolation_2 with --shard 2/2), the summary job the step summary isolation gate, the browser_1 job the browser gate self-test --shard 1/2, the browser_2 job its --shard 2/2 and the browser gate process self-test, the browser_3 job the browser gate (fixture site) self-test and the two browser gates, the lint job actionlint, shellcheck, yamllint and zizmor with their self-tests and Go lint with its self-test and, since forsgren#591, the Go test duplication gate, the quality_2 job the eleven gates of forsgren#447 (the Go tests with the Go coverage gate, nine more), and the workflows job gate wiring, the checkout pins mutations and the pins of the metrics, release, starter page, vulncheck, auto-update and preview workflows and of this job layout, go mod tidy, the Go test duplication and Go vulnerabilities self-tests and, since step 8b, eleven Linux-safe tail gates of the main job (release pins, browser gate selection, Go tests, release precheck, community-files, DCO sign-off, release plan, release report, release check and release metrics self-tests, and sfl drives from the order file), got: ${rows:-none}"
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
# job. A gate is in two jobs only as one shard each (forsgren#641: the browser
# gate self-test is in browser_1 and browser_2, as the isolation self-test of
# forsgren#426 is in isolation_1 and isolation_2): every row of a label listed
# more than once carries --shard, and no two the same shard.
union_findings() {
  local all grouped main both twice
  all="$(grep -v '^#' "$ORDER" | grep . | awk -F'|' '$3 == "pre" || $3 == "post" { print $1 }' | LC_ALL=C sort)"
  grouped="$(grep -v '^#' "$GROUPS_FILE" | grep . | cut -d'|' -f2 | LC_ALL=C sort -u)"
  main="$(LC_ALL=C comm -23 <(printf '%s\n' "$all" | LC_ALL=C sort -u) <(printf '%s\n' "$grouped"))"
  both="$( { printf '%s\n' "$main"; printf '%s\n' "$grouped"; } | grep . | LC_ALL=C sort)"
  [[ "$both" == "$(printf '%s\n' "$all" | LC_ALL=C sort)" ]] \
    || echo "union: the main job's gates and the group file's gates are not the order file's pre and post rows, each once"
  twice="$(grep -v '^#' "$GROUPS_FILE" | grep . | awk -F'|' '{ n[$2]++; if ($3 !~ /^--shard [1-9][0-9]*\/[1-9][0-9]*$/ || s[$2 "|" $3]++) bad[$2] = 1 } END { for (l in bad) if (n[l] > 1) print l }')"
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

OUT="$(tools_file_findings)"
if [[ -z "$OUT" ]]; then
  echo "  ok: the tools lists of the macOS gate jobs hold every pin"
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

# mutant_case <name> <sed-expression> <finding>: one mutation proof, in the folder of
# its own (MUTANT_DIR) that Scripts/lib_parallel_mutants.sh gives it.
mutant_case() {
  local file="${MUTANT_DIR}/mutated.yml"
  JOBS_TMP="$MUTANT_DIR"
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

# mutant <name> <sed-expression> <finding>: starts the proof side by side with the
# others (mutants_wait below prints them in this order).
mutants_init "$TMP"
mutant() {
  mutant_run mutant_case "$@"
}

Q='/^  quality:/,/^  quality_2:/'
L='/^  lint:/,/^  isolation_1:/'
I1='/^  isolation_1:/,/^  isolation_2:/'
I2='/^  isolation_2:/,/^  summary:/'
Q2='/^  quality_2:/,/^  lint:/'
S='/^  summary:/,/^  browser_1:/'
B1='/^  browser_1:/,/^  browser_2:/'
B2='/^  browser_2:/,/^  browser_3:/'
B3='/^  browser_3:/,/^  workflows:/'
W='/^  workflows:/,/^  report:/'
R='/^  report:/,/^  preview:/'
for n in 1 2; do
  case "$n" in 1) I="$I1" ;; *) I="$I2" ;; esac
  mutant "no isolation_${n} job" "s/^  isolation_${n}:/  isolation_${n}_gone:/" "job: the file has no isolation_${n} job"
  mutant "isolation_${n} on another runner" "${I}"'s/runs-on: ubuntu-latest/runs-on: macos-latest/' "runs-on: the isolation_${n} job is not on ubuntu-latest"
  mutant "isolation_${n} with the lint job's tools" "${I}"'s#required_tools_linux_gates\.txt#required_tools_linux.txt#' "setup: the isolation_${n} job does not run ${LINUX_GATES_INSTALL}"
  mutant "isolation_${n} without npm ci" "${I}"'s/run: npm ci/run: true/' "setup: the isolation_${n} job does not run npm ci"
  mutant "isolation_${n} without Node" "${I}"'s/- name: Set up Node/- name: Set up something/' "setup: the isolation_${n} job's steps start"
  mutant "isolation_${n} runs the main job's gates" "${I}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation_${n}/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "isolation: the isolation_${n} job must run exactly"
  mutant "isolation_${n} runs the other shard's job" "${I}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation_${n}/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" isolation_$((3 - n))/" "isolation: the isolation_${n} job must run exactly"
  mutant "isolation_${n} hand-over not always" "${I}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the isolation_${n} job's"
  mutant "isolation_${n} hand-over under another name" "${I}"'s/name: quality-report-isolation_'"${n}"'/name: quality-report-other/' "handover: the isolation_${n} job does not upload the artifact quality-report-isolation_${n}"
  mutant "report without isolation_${n} in needs" "${R}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser_2, browser_3, workflows\]/needs: [quality, quality_2, lint, '"$( [[ $n == 1 ]] && echo isolation_2 || echo isolation_1 )"', summary, browser_1, browser_2, browser_3, workflows]/' "report: the gate job isolation_${n} is not in the report job's needs:"
  mutant "report without the isolation_${n} result" "${R}"'{/QS_ISOLATION_'"${n}"'_RESULT:/d;}' "report: the report job has no QS_ISOLATION_${n}_RESULT from needs.isolation_${n}.result"
  mutant "status without the isolation_${n} result" "${R}"'s/ "[$]QS_ISOLATION_'"${n}"'_RESULT"//' "report: the status call does not pass"
done
GO_JOBS=(
  "isolation_1:${I1}"
  "isolation_2:${I2}"
  "lint:${L}"
  "summary:${S}"
  "workflows:${W}"
)
for entry in "${GO_JOBS[@]}"; do
  j="${entry%%:*}"
  range="${entry#*:}"
  mutant "${j} without setup-go" "${range}"'s/- name: Set up Go$/- name: Set up something else/' "setup: the ${j} job's steps start"
  mutant "${j} setup-go not reading go.mod" "${range}"'s/go-version-file: go.mod/go-version: 1.27.3/' "setup-go: the ${j} job's Set up Go step does not read go.mod"
  mutant "${j} setup-go with the cache off" "${range}"'s/^\(          go-version-file: go.mod\)$/\1\
          cache: false/' "setup-go: the ${j} job's Set up Go step turns the cache off"
  mutant "${j} setup-go not pinned" "${range}"'s#\(actions/setup-go@\)[0-9a-f]\{40\}#\1v7#' "setup-go: the ${j} job's Set up Go step does not use actions/setup-go pinned"
  mutant "${j} setup-go may fail silently" "${range}"'s/^\(        uses: actions\/setup-go@.*\)$/\1\
        continue-on-error: true/' "setup-go: the ${j} job's Set up Go step has continue-on-error"
done
mutant "summary on another runner" "${S}"'s/runs-on: ubuntu-latest/runs-on: macos-latest/' "runs-on: the summary job is not on ubuntu-latest"
mutant "summary using the Homebrew installer" "${S}"'s#install_tools_linux\.sh Scripts/required_tools_linux_gates\.txt#install_tools.sh#' "setup: the summary job does not run ${LINUX_GATES_INSTALL}"
mutant "summary without npm ci" "${S}"'s/run: npm ci/run: true/' "setup: the summary job does not run npm ci"
mutant "summary without Node" "${S}"'s/- name: Set up Node/- name: Set up something/' "setup: the summary job's steps start"
mutant "no summary job" 's/^  summary:/  summary_gone:/' "job: the file has no summary job"
mutant "summary runs the main job's gates" "${S}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" summary/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "summary: the summary job must run exactly"
FIRST_SUM_GATE="$(gates_of summary | sed -n 1p)"
mutant "a step naming the summary gate" "${S}"'s#\./Scripts/install_tools_linux\.sh Scripts/required_tools_linux_gates\.txt#./Scripts/install_tools_linux.sh Scripts/required_tools_linux_gates.txt; ./Scripts/'"${FIRST_SUM_GATE}"'.sh#' "isolation: a step names an isolation gate itself"
mutant "summary hand-over not always" "${S}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the summary job's"
mutant "summary hand-over under another name" "${S}"'s/name: quality-report-summary/name: quality-report-other/' "handover: the summary job does not upload the artifact quality-report-summary"
mutant "report without summary in needs" "${R}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser_2, browser_3, workflows\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, browser_1, browser_2, browser_3, workflows]/' "report: the gate job summary is not in the report job's needs:"
mutant "report without the summary result" "${R}"'{/QS_SUMMARY_RESULT:/d;}' "report: the report job has no QS_SUMMARY_RESULT from needs.summary.result"
mutant "status without the summary result" "${R}"'s/ "[$]QS_SUMMARY_RESULT"//' "report: the status call does not pass"
mutant "main without its job name" "${Q}s/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\"/" "main: both run_ci_phase.sh calls of the main job"
FIRST_ISO_GATE="$(gates_of isolation_1 | sed -n 1p)"
mutant "a step naming an isolation gate" "${I1}"'s#\./Scripts/install_tools_linux\.sh Scripts/required_tools_linux_gates\.txt#./Scripts/install_tools_linux.sh Scripts/required_tools_linux_gates.txt; ./Scripts/'"${FIRST_ISO_GATE}"'.sh#' "isolation: a step names an isolation gate itself"
mutant "main hand-over under another name" "${Q}"'s/name: quality-report-quality/name: quality-report-other/' "handover: the quality job does not upload the artifact quality-report-quality"
mutant "report without lint in needs" "${R}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser_2, browser_3, workflows\]/needs: [quality, quality_2, isolation_1, isolation_2, summary, browser_1, browser_2, browser_3, workflows]/' "report: the gate job lint is not in the report job's needs:"
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
# The three browser jobs: what every gate job must hold, then what the two PRE
# jobs (browser_1, browser_2) and browser_3 each hold of their own.
browser_range() {
  case "$1" in 1) BP="$B1" ;; 2) BP="$B2" ;; *) BP="$B3" ;; esac
}
for n in 1 2 3; do
  browser_range "$n"
  mutant "report without browser_${n} in needs" "${R}"'s/ browser_'"${n}"',//' "report: the gate job browser_${n} is not in the report job's needs:"
  mutant "report without the browser_${n} result" "${R}"'{/QS_BROWSER_'"${n}"'_RESULT:/d;}' "report: the report job has no QS_BROWSER_${n}_RESULT from needs.browser_${n}.result"
  mutant "status without the browser_${n} result" "${R}"'s/ "[$]QS_BROWSER_'"${n}"'_RESULT"//' "report: the status call does not pass"
  mutant "no browser_${n} job" "s/^  browser_${n}:/  browser_${n}_gone:/" "job: the file has no browser_${n} job"
  mutant "browser_${n} on another runner" "${BP}"'s/runs-on: macos-latest/runs-on: ubuntu-latest/' "runs-on: the browser_${n} job is not on macos-latest"
  mutant "browser_${n} without npm ci" "${BP}"'s/run: npm ci/run: true/' "setup: the browser_${n} job does not run npm ci"
  mutant "browser_${n} hand-over not always" "${BP}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the browser_${n} job's"
  mutant "browser_${n} hand-over under another name" "${BP}"'s/name: quality-report-browser_'"${n}"'/name: quality-report-other/' "handover: the browser_${n} job does not upload the artifact quality-report-browser_${n}"
done
for n in 1 2; do
  browser_range "$n"
  mutant "browser_${n} runs the main job's gates" "${BP}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_${n}/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "browser_${n}: the browser_${n} job must run exactly"
  mutant "browser_${n} runs the other shard's job" "${BP}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_${n}/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_$((3 - n))/" "browser_${n}: the browser_${n} job must run exactly"
  mutant "browser_${n} runs the browser_3 job's gates" "${BP}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_${n}/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_3/" "browser_${n}: the browser_${n} job must run exactly"
  mutant "browser_${n} builds a site" "${BP}"'s#\./Scripts/install_tools.sh#./Scripts/install_tools.sh; ./Scripts/build_site.sh#' "browser_${n}: the browser_${n} job builds a site"
  mutant "a step naming the browser_${n} gate" "${BP}"'s#\./Scripts/install_tools.sh#./Scripts/install_tools.sh; ./Scripts/test_gate_browser.sh#' "browser: a step names a browser gate itself"
done
mutant "browser_3 without its site build" "${B3}"'s#\./Scripts/build_site.sh#./Scripts/other.sh#' "browser_3: the browser_3 job must run PRE, then its own site build"
mutant "browser_3 running the main job's gates" "${B3}s/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" browser_3/run_ci_phase.sh post \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "browser_3: the browser_3 job must run run_ci_phase.sh pre and post"
mutant "a step naming a browser gate" "${B3}"'s#\./Scripts/install_tools.sh#./Scripts/install_tools.sh; ./Scripts/gate_browser.sh#' "browser: a step names a browser gate itself"
mutant "report without workflows in needs" "${R}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser_2, browser_3, workflows\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser_2, browser_3]/' "report: the gate job workflows is not in the report job's needs:"
mutant "report without the workflows result" "${R}"'{/QS_WORKFLOWS_RESULT:/d;}' "report: the report job has no QS_WORKFLOWS_RESULT from needs.workflows.result"
mutant "status without the workflows result" "${R}"'s/ "[$]QS_WORKFLOWS_RESULT"//' "report: the status call does not pass"
mutant "no workflows job" 's/^  workflows:/  workflows_gone:/' "job: the file has no workflows job"
mutant "workflows on another runner" "${W}"'s/runs-on: ubuntu-latest/runs-on: macos-latest/' "runs-on: the workflows job is not on ubuntu-latest"
mutant "workflows using the Homebrew installer" "${W}"'s#install_tools_linux\.sh Scripts/required_tools_linux_gates\.txt#install_tools.sh#' "setup: the workflows job does not run ${LINUX_GATES_INSTALL}"
mutant "workflows without npm ci" "${W}"'s/run: npm ci/run: true/' "setup: the workflows job does not run npm ci"
mutant "workflows runs the main job's gates" "${W}s/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" workflows/run_ci_phase.sh pre \"${DOLLAR}ROWS\" \"${DOLLAR}DETAILS\" main/" "workflows: the workflows job must run exactly"
FIRST_WF_GATE="$(workflows_gates | sed -n 1p)"
mutant "a step naming a workflows gate" "${W}"'s#\./Scripts/install_tools_linux\.sh Scripts/required_tools_linux_gates\.txt#./Scripts/install_tools_linux.sh Scripts/required_tools_linux_gates.txt; ./Scripts/'"${FIRST_WF_GATE}"'.sh#' "workflows: a step names a workflows gate itself"
mutant "workflows hand-over not always" "${W}"'{/Hand over the gate report/,/uses:/s/if: always()/if: success()/;}' "handover: the workflows job's"
mutant "workflows hand-over under another name" "${W}"'s/name: quality-report-workflows/name: quality-report-other/' "handover: the workflows job does not upload the artifact quality-report-workflows"
mutant "report not always" "${R}"'s/^    if: always()/    if: success()/' "report: the report job is not if: always()"
mutant "report on another runner" "${R}"'s/runs-on: ubuntu-latest/runs-on: macos-latest/' "report: the report job is not on ubuntu-latest"
mutant "report without the merge" "${R}"'s#merge_quality_report.sh merge#merge_quality_report.sh combine#' "report: the report job does not merge the hand-overs"
mutant "report status not merged" "${R}"'s#merge_quality_report.sh status#merge_quality_report.sh state#' "report: QS_JOB_STATUS is not taken from"
mutant "a softened job" "${I1}"'s/^    runs-on: ubuntu-latest/    continue-on-error: true\
    runs-on: ubuntu-latest/' "verdict: continue-on-error softens a failure"

# Pin 3g, the install commands: each of the four jobs on the full installer,
# and the main job on a list.
for j in quality_2:"$Q2" browser_1:"$B1" browser_2:"$B2" browser_3:"$B3"; do
  jid="${j%%:*}"
  jrange="${j#*:}"
  mutant "${jid} installing the full tool list" "${jrange}"'s#install_tools\.sh Scripts/required_tools_[a-z0-9_]*_gates\.txt#install_tools.sh#' \
    "setup: the ${jid} job does not run Scripts/install_tools.sh $(tools_file_of "$jid")"
  mutant "${jid} installing another job's list" "${jrange}"'s#required_tools_[a-z0-9_]*_gates\.txt#required_tools_linux_gates.txt#' \
    "setup: the ${jid} job does not run Scripts/install_tools.sh $(tools_file_of "$jid")"
done
mutant "main installing the full tool list" "${Q}"'s#install_tools\.sh Scripts/required_tools_quality_gates\.txt#install_tools.sh#' \
  "setup: the quality job does not run Scripts/install_tools.sh $(tools_file_of quality)"
mutant "main installing another job's list" "${Q}"'s#required_tools_quality_gates\.txt#required_tools_browser_gates.txt#' \
  "setup: the quality job does not run Scripts/install_tools.sh $(tools_file_of quality)"
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
expect_named "a group file that leaves the quality_2 gates in the main job" "the quality_2 job the eleven gates"
grep -v '^quality_2|Go coverage$' "$GROUPS_FILE" > "${VERDICT_TMP}/nocov.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nocov.txt" groups_findings)"
expect_named "a group file that leaves Go coverage apart from Go tests" "the quality_2 job the eleven gates"
{ cat "$GROUPS_FILE"; echo 'lint|golden pages'; } > "${VERDICT_TMP}/twojobs.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/twojobs.txt" groups_findings)"
expect_named "a gate in quality_2 and in another job" "union: a gate is in two jobs, not as one shard each: golden pages"
sed 's#^browser_1|browser gate self-test|--shard 1/2$#browser_1|browser gate self-test#; s#^browser_2|browser gate self-test|--shard 2/2$#browser_2|browser gate self-test#' "$GROUPS_FILE" > "${VERDICT_TMP}/nob1.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nob1.txt" groups_findings)"
expect_named "the browser gate self-test whole in browser_1 and in browser_2" "union: a gate is in two jobs, not as one shard each: browser gate self-test"
sed 's#^browser_2|browser gate self-test|--shard 2/2$#browser_2|browser gate self-test|--shard 1/2#' "$GROUPS_FILE" > "${VERDICT_TMP}/b1same.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/b1same.txt" groups_findings)"
expect_named "the two browser jobs running the same shard of the browser gate self-test" "union: a gate is in two jobs, not as one shard each: browser gate self-test"
sed 's/^browser_3|browser gate (fixture site) self-test$/browser_2|browser gate (fixture site) self-test/' "$GROUPS_FILE" > "${VERDICT_TMP}/nofx.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/nofx.txt" groups_findings)"
expect_named "a group file that moves the fixture site self-test out of browser_3" "the browser_3 job the browser gate (fixture site) self-test and the two browser gates"
sed 's/^browser_2|browser gate process self-test$/browser_3|browser gate process self-test/' "$GROUPS_FILE" > "${VERDICT_TMP}/noproc.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/noproc.txt" groups_findings)"
expect_named "a group file that leaves the process self-test in browser_3" "the browser_2 job its --shard 2/2 and the browser gate process self-test"
{ cat "$GROUPS_FILE"; echo 'browser_3|browser gate self-test'; } > "${VERDICT_TMP}/b1twice.txt"
OUT="$(GROUPS_FILE="${VERDICT_TMP}/b1twice.txt" groups_findings)"
expect_named "the browser gate self-test whole in browser_3 besides its shards" "union: a gate is in two jobs, not as one shard each: browser gate self-test"
# Pin 3g, the lists: each mutant is a copy of the lists in a directory of its own.
for f in "$(tools_file_of quality_2)" "$(tools_file_of browser_1)" "$(tools_file_of browser_2)" "$(tools_file_of browser_3)"; do
  [[ -f "$f" ]] && cp "$f" "${VERDICT_TMP}/"
done
mkdir -p "${VERDICT_TMP}/nojq" "${VERDICT_TMP}/nonode" "${VERDICT_TMP}/extra" "${VERDICT_TMP}/empty"
for d in nojq nonode extra empty; do
  cp "${VERDICT_TMP}"/required_tools_*_gates.txt "${VERDICT_TMP}/${d}/" 2> /dev/null || true
done
OUT="$(TOOLS_DIR="${VERDICT_TMP}/none" tools_file_findings)"
expect_named "no tools lists" "does not exist or is empty"
grep -vx 'jq' "$(tools_file_of quality_2)" > "${VERDICT_TMP}/nojq/required_tools_quality_2_gates.txt" || true
OUT="$(TOOLS_DIR="${VERDICT_TMP}/nojq" tools_file_findings)"
expect_named "a quality_2 list without jq" "lists 'go node ', the quality_2 job needs 'go jq node '"
expect_named "the Go coverage gate that calls jq" "the quality_2 gate check_coverage calls jq"
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
expect_named "a browser_1 list with a tool its gate does not need" "lists 'jq node ', the browser_1 job needs 'node '"
grep -vx 'go' "$(tools_file_of browser_3)" > "${VERDICT_TMP}/extra/required_tools_browser_3_gates.txt" || true
OUT="$(TOOLS_DIR="${VERDICT_TMP}/extra" tools_file_findings)"
expect_named "a browser_3 list without go, which its fixture site self-test and site build need" "lists 'node ', the browser_3 job needs 'go node '"
expect_named "the fixture site self-test that reaches go" "the browser_3 gate test_gate_browser_fixture reaches go"
: > "${VERDICT_TMP}/empty/required_tools_browser_1_gates.txt"
OUT="$(TOOLS_DIR="${VERDICT_TMP}/empty" tools_file_findings)"
expect_named "an empty browser_1 list" "required_tools_browser_1_gates.txt does not exist or is empty"

# A tool needed two calls deep (forsgren#447, step 9): a copy of Scripts/ where the browser_1
# gate calls a script that calls a script that runs jq, which the browser_1 list lacks.
DEEP="${VERDICT_TMP}/deep"
mkdir -p "$DEEP"
cp -R Scripts "${DEEP}/Scripts"
printf '%s\n' './Scripts/zz_deep_mid.sh' >> "${DEEP}/Scripts/test_gate_browser.sh"
printf '%s\n' '#!/usr/bin/env bash' './Scripts/zz_deep_end.sh' > "${DEEP}/Scripts/zz_deep_mid.sh"
printf '%s\n' '#!/usr/bin/env bash' 'jq . /dev/null' > "${DEEP}/Scripts/zz_deep_end.sh"
OUT="$(cd "$DEEP" && tools_file_findings)"
expect_named "a tool two calls below a gate" "the browser_1 gate test_gate_browser reaches jq in Scripts/zz_deep_end.sh"

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

mkdir -p "${VERDICT_TMP}/order"
sed 's/^shellcheck|Scripts\/check_shellcheck.sh|pre|/shellcheck|Scripts\/check_shellcheck.sh|post|/' "$ORDER" > "${VERDICT_TMP}/order/gate_report_order.txt"
OUT="$(ORDER="${VERDICT_TMP}/order/gate_report_order.txt" groups_findings)"
expect_named "a lint row moved to post" "the lint gate 'shellcheck' is no pre row"

mkdir -p "${VERDICT_TMP}/rq"
sed 's/--json status,conclusion,url/--json status,conclusion,url,jobs/' "$RELEASE_CHECK" > "${VERDICT_TMP}/rq/release_quality.sh"
OUT="$(RELEASE_CHECK="${VERDICT_TMP}/rq/release_quality.sh" verdict_findings)"
expect_named "a release check that reads a job" "reads a job, not the run"

selftest_end "the quality jobs pin found failures" "quality jobs pin (the real workflow holds every pin; each mutant is named)"
