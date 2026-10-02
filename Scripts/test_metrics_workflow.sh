#!/usr/bin/env bash
# Scripts/test_metrics_workflow.sh
#
# Pins .github/workflows/metrics.yml, the REUSABLE workflow an installation's
# data repository calls once a day (forsgren#4, walking skeleton step 2 of
# #3). forsgren's own: no repo of the estate has a reusable workflow. It
# installs the forsgren release the caller names, renders the page and
# publishes it to the caller's GitHub Pages. Nothing in forsgren itself runs
# it, so no gate runs it either: this pin is what proves it, in sfl and
# Quality, on every run.
#
# THE PINS, on metrics.yml:
#   1. it triggers on workflow_call and on nothing else: forsgren's own
#      repository never runs it (it would publish forsgren's Pages), and no
#      pull request can;
#   2. its forsgren-version input is required: the caller always names the
#      release, there is no default to drift to;
#   3. no run: block expands a ${{ }} expression: the input reaches the
#      shell through env: only, never as text pasted into the script
#      (template injection);
#   4. the step "Check the forsgren version is a release tag" exists, and
#      its run: block, EXECUTED here with FORSGREN_VERSION set, accepts a
#      release tag vMAJOR.MINOR.PATCH and refuses everything else: latest, a
#      branch, a bare 0.0.1, v0.0, a pre-release, a commit hash, a tag with
#      a trailing newline or command, the empty string. Executed, not
#      grepped: the regex is pinned by what it does;
#   5. that check runs before the step that runs go install, so a refused
#      version never reaches the Go module proxy;
#   6. go install names github.com/yveshanoulle/forsgren/cmd/forsgren at
#      ${FORSGREN_VERSION}, the checked variable;
#   7. actions/setup-go installs exactly the Go of go.mod's toolchain line
#      (Scripts/go_toolchain.sh), the Go that sfl, FBP.sh and Quality build
#      with. setup-go exports GOTOOLCHAIN=local, so go install uses that Go
#      and never switches: the pin is the whole choice, and a toolchain bump
#      in go.mod without one here is red.
#
# WHY THE VERSION CHECK IS INLINE, NOT A Scripts/ FILE (the estate rule puts
# CI loop bodies in tested scripts). The job runs in the CALLER's repository
# and checks nothing out: forsgren's scripts are not on the runner. Fetching
# one would mean checking out forsgren at a ref, and the only ref the job
# knows is the very version it has not checked yet. The check is one regex
# test, and pin 4 executes that very block, so it is tested where it lives.
#
# Read with awk and grep, not a YAML parser, as
# Scripts/test_quality_trigger_scope.sh and Scripts/check_workflow_triggers.sh
# are, for their reason: PyYAML is a module, not a command, and nothing here
# installs it. The shape read is the one metrics.yml is written in: `on:` at
# column 0, its events two spaces in; a step starts at `      - `, its keys
# eight spaces in; a `run: |` block is every following line indented deeper
# than the `run:` key.
#
# Self-proving: each pin is shown failing on a mutant of the real metrics.yml,
# naming its own reason, so a broken matcher cannot pass in silence.
#
# Usage: Scripts/test_metrics_workflow.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "the metrics workflow pin"

WF=".github/workflows/metrics.yml"
CHECK_STEP="Check the forsgren version is a release tag"
# The opening of a GitHub expression, in double quotes with the dollar
# escaped, so no reader (shellcheck included) takes it for an expansion.
EXPR_OPEN="\${{"

# on_events <file>: the event names of the column-0 `on:` block, one per line.
on_events() {
  awk '
    /^on:[[:space:]]*$/ { inon=1; next }
    inon && /^[^[:space:]#]/ { inon=0 }
    inon && /^  [A-Za-z_]+:/ { s=$0; sub(/^  /, "", s); sub(/:.*$/, "", s); print s }
  ' "$1"
}

# input_block <file> <input>: the lines under that workflow_call input.
input_block() {
  awk -v name="$2" '
    $0 ~ ("^      " name ":[[:space:]]*$") { inb=1; next }
    inb && /^ {0,6}[^[:space:]]/ { inb=0 }
    inb { print }
  ' "$1"
}

# run_blocks <file>: every run: line and the lines of its block, as
# <lineno>:<text>, so a finding names its line.
run_blocks() {
  awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    inrun && $0 !~ /^[[:space:]]*$/ && indent($0) <= runind { inrun=0 }
    inrun { print NR ":" $0; next }
    /^[[:space:]]*(- )?run:/ {
      print NR ":" $0
      runind = indent($0)
      if ($0 ~ /- run:/) runind += 2
      if ($0 ~ /run:[[:space:]]*[|>][-+]?[[:space:]]*$/) inrun=1
    }
  ' "$1"
}

# step_run <file> <step name>: the run: | block of the step with that name,
# its lines dedented, ready to execute; nothing when there is no such step.
step_run() {
  awk -v name="$2" '
    function indent(s) { match(s, /^ */); return RLENGTH }
    /^      - / { instep = ($0 == "      - name: " name); inrun=0; next }
    instep && inrun && $0 !~ /^[[:space:]]*$/ && indent($0) <= 8 { inrun=0 }
    instep && inrun { if (!cut) { match($0, /^ */); cut = RLENGTH } print substr($0, cut + 1); next }
    instep && /^        run:[[:space:]]*\|[[:space:]]*$/ { inrun=1 }
  ' "$1"
}

# line_of <file> <fixed text>: the line number of its first occurrence.
line_of() {
  grep -nF -- "$2" "$1" | head -1 | cut -d: -f1
}

# version_verdict <script> <version>: accepted or refused.
version_verdict() {
  if FORSGREN_VERSION="$2" bash "$1" >/dev/null 2>&1; then
    echo accepted
  else
    echo refused
  fi
}

# judge <workflow-file>: one problem per line; silent when every pin holds.
judge() {
  local wf="$1" events block runs script check_line install_line v want got go_version toolchain
  events="$(on_events "$wf")"
  if [[ "$events" != "workflow_call" ]]; then
    echo "triggers on [$(printf '%s' "$events" | paste -sd, -)], not on workflow_call alone — forsgren's own repository must never run it, and no pull request may"
  fi

  block="$(input_block "$wf" forsgren-version)"
  if [[ -z "$block" ]]; then
    echo "has no forsgren-version input — the caller could not name the forsgren release it runs"
  elif ! grep -qE '^[[:space:]]+required:[[:space:]]*true[[:space:]]*$' <<< "$block"; then
    echo "forsgren-version is not required: true — a caller that forgets it must fail, not drift to a default"
  fi

  runs="$(run_blocks "$wf")"
  if grep -qF "$EXPR_OPEN" <<< "$runs"; then
    echo "expands a \${{ }} expression inside run: (line $(grep -F "$EXPR_OPEN" <<< "$runs" | head -1 | cut -d: -f1)) — the input reaches the shell through env: only (template injection)"
  fi

  script="${TMP}/check_version.sh"
  step_run "$wf" "$CHECK_STEP" > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${CHECK_STEP}' with a run: | block — nothing refuses latest or a branch"
  else
    for v in v0.0.1 v1.2.3 v10.20.300; do
      got="$(version_verdict "$script" "$v")"
      [[ "$got" == accepted ]] || echo "the version check refuses the release tag '${v}'"
    done
    for v in latest main 0.0.1 v0.0 v1 v0.0.1-rc.1 v0.0.1+meta V0.0.1 \
             e1b36d2 'v0.0.1 ' ' v0.0.1' 'v0.0.1;id' $'v0.0.1\nmain' ''; do
      got="$(version_verdict "$script" "$v")"
      want=refused
      [[ "$got" == "$want" ]] || echo "the version check accepts '$(printf '%q' "$v")', which is not a release tag vMAJOR.MINOR.PATCH"
    done
  fi

  check_line="$(line_of "$wf" "- name: ${CHECK_STEP}")"
  # The command, not a comment naming it: go install at the start of a line.
  install_line="$(grep -nE '^[[:space:]]+go install ' "$wf" | head -1 | cut -d: -f1)"
  if [[ -z "$install_line" ]]; then
    echo "runs no go install — the job installs no forsgren"
  else
    if [[ -n "$check_line" ]] && [[ "$check_line" -gt "$install_line" ]]; then
      echo "runs go install (line ${install_line}) before the version check (line ${check_line}) — a refused version would already have reached the module proxy"
    fi
    if ! grep -qF "go install \"github.com/yveshanoulle/forsgren/cmd/forsgren@\${FORSGREN_VERSION}\"" "$wf"; then
      echo "go install does not install github.com/yveshanoulle/forsgren/cmd/forsgren@\${FORSGREN_VERSION}, the version the check judged"
    fi
  fi

  go_version="$(awk '
    /uses:[[:space:]]*actions\/setup-go@/ { insg=1; next }
    insg && /^      - / { insg=0 }
    insg && /^[[:space:]]+go-version:/ { v=$0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/["\047]/, "", v); print v; exit }
  ' "$wf")"
  toolchain="$(./Scripts/go_toolchain.sh)"
  if [[ "$go_version" != "${toolchain#go}" ]]; then
    echo "actions/setup-go installs Go '${go_version:-none}', not ${toolchain#go} from go.mod's toolchain line — the release would be built with another Go than sfl, FBP.sh and Quality use"
  fi
}

if [[ ! -f "$WF" ]]; then
  selftest_abort "${WF} not found — an installation's data repository has no forsgren workflow to call"
fi

verdict="$(judge "$WF")"
if [[ -n "$verdict" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && fail "${WF} ${line}"
  done <<< "$verdict"
else
  echo "  ok: ${WF} is a workflow_call with a required forsgren-version, checked as a release tag before go install, through env: only, built with go.mod's Go"
fi

# --- Self-proof: each pin, on a mutant of the real metrics.yml, names its reason.
# proves <case> <reason> <sed-expression>
proves() {
  local mutant="${TMP}/mutants/$1.yml" got
  selftest_mutant "$WF" "$mutant" "$3" || return 0
  got="$(judge "$mutant")"
  if grep -qF -- "$2" <<< "$got"; then
    echo "  ok: $1 is rejected"
  else
    fail "the mutant with $1 was ACCEPTED (verdict: ${got:-none}) — this pin cannot detect the defect it exists for"
  fi
}

proves "a push trigger" "not on workflow_call alone" \
  's/^  workflow_call:$/  push:\n  workflow_call:/'
proves "an optional forsgren-version" "is not required: true" \
  's/^        required: true$/        required: false/'
proves "the input pasted into run:" "expands a \${{ }} expression inside run:" \
  "s/@\\\${FORSGREN_VERSION}\"/@\${{ inputs.forsgren-version }}\"/"
proves "no version check step" "has no step '${CHECK_STEP}'" \
  "s/- name: ${CHECK_STEP}\$/- name: Check something else/"
proves "a version check that accepts anything" "the version check accepts 'latest'" \
  's/^\( *\)exit 1$/\1exit 0/'
proves "a version check without its end anchor" "the version check accepts 'v0.0.1-rc.1'" \
  's/\[0-9\]+\$'"'"'$/[0-9]+'"'"'/'
proves "a version check that refuses releases" "refuses the release tag 'v0.0.1'" \
  's/\^v\[0-9\]/^x[0-9]/'
proves "go install at another version" "does not install github.com/yveshanoulle/forsgren/cmd/forsgren@" \
  "s/@\\\${FORSGREN_VERSION}\"/@\${FORSGREN_REF}\"/"
proves "setup-go on another Go" "actions/setup-go installs Go '1.0.0'" \
  "s/^\(          go-version: \).*\$/\1'1.0.0'/"

# The order pin: the check step moved below go install.
reorder="${TMP}/mutants/reorder.yml"
awk -v name="$CHECK_STEP" '
  /^      - / { if (instep) instep=0; if ($0 == "      - name: " name) instep=1 }
  instep { held = held $0 "\n"; next }
  { print }
  END { printf "%s", held }
' "$WF" > "$reorder"
got="$(judge "$reorder")"
if grep -qF "before the version check" <<< "$got"; then
  echo "  ok: go install before the version check is rejected"
else
  fail "the mutant with go install before the version check was ACCEPTED (verdict: ${got:-none}) — the order pin cannot detect it"
fi

selftest_end "metrics.yml is not the reusable workflow forsgren#4 rules" \
  "metrics.yml runs on workflow_call only, requires forsgren-version, refuses any version but a release tag before go install, passes it through env: only, and builds with go.mod's Go (and each wrong shape is still detected)"
