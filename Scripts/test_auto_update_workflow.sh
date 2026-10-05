#!/usr/bin/env bash
# Scripts/test_auto_update_workflow.sh
#
# Pins .github/workflows/auto_update.yml (forsgren#58, ladder steps 17 to
# 19), the REUSABLE workflow an installation's caller, forsgren-update.yml,
# calls on a Dependabot pull request: it asks `forsgren check-update`
# whether the pull request may be merged, merges it, and starts the
# installation's forsgren.yml. Nothing in forsgren itself runs it, so this
# pin is what proves it, in sfl and Quality, on every run.
#
# Grown one behaviour per cycle, each its own red then green:
#   17a  the file exists and triggers on workflow_call and on nothing else
#        (forsgren's own repository never runs it, no pull request can);
#   17b  no permissions block at workflow or job level (the caller grants);
#   17c  forsgren is installed from this workflow's own commit: the same
#        setup-go as metrics.yml, then the install step, its commit and
#        repository from the job context through env: only;
#   (the later cycles are listed in forsgren#58 and add their pins here.)
#
# Read with awk, not a YAML parser, as Scripts/test_metrics_workflow.sh is,
# for its reason: PyYAML is a module, not a command, and nothing here
# installs it.
#
# Usage: Scripts/test_auto_update_workflow.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "the auto-update workflow pin"

WF=".github/workflows/auto_update.yml"
METRICS=".github/workflows/metrics.yml"
GO_STEP="Set up Go"
INSTALL_STEP="Install forsgren from this workflow's own commit"
# The opening of a GitHub expression, in double quotes with the dollar
# escaped, so no reader (shellcheck included) takes it for an expansion.
EXPR_OPEN="\${{"

# The helpers below are COPIES of Scripts/test_metrics_workflow.sh's, for the
# refactor step of forsgren#58 to move into one shared library.

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

# step_text <file> <step name>: every line of that step, the dash line
# included; nothing when there is no such step.
step_text() {
  awk -v name="$2" '
    /^      - / { instep = ($0 == "      - name: " name) }
    instep { print }
  ' "$1"
}

# line_of <file> <fixed text>: the line number of its first occurrence.
line_of() {
  grep -nF -- "$2" "$1" | head -1 | cut -d: -f1
}

# later <line> <other line>: true when both are known and the first comes
# after the second.
later() {
  [[ -n "$1" && -n "$2" && "$1" -gt "$2" ]]
}

# on_events <file>: the event names of the column-0 `on:` block, one per line.
on_events() {
  awk '
    /^on:[[:space:]]*$/ { inon=1; next }
    inon && /^[^[:space:]#]/ { inon=0 }
    inon && /^  [A-Za-z_]+:/ { s=$0; sub(/^  /, "", s); sub(/:.*$/, "", s); print s }
  ' "$1"
}

# Pin 1: the workflow exists and triggers on workflow_call alone.
if [[ ! -f "$WF" ]]; then
  fail "pin 1: ${WF} does not exist"
else
  events="$(on_events "$WF" | paste -sd, -)"
  if [[ "$events" == "workflow_call" ]]; then
    echo "  ok: ${WF} triggers on workflow_call only"
  else
    fail "pin 1: ${WF} triggers on '${events:-nothing}', not on workflow_call only"
  fi
fi

# Pin 2: no `permissions:` key, at workflow level (column 0) or on a job
# (four spaces in). A STANDING FACT, as metrics.yml's header explains: a
# called workflow can only keep or narrow the permissions its caller's job
# grants, never widen them, so any block here would cut what the caller
# grants (contents: write, pull-requests: write, actions: write) to what the
# block names, and the merge or the dispatch would fail with a 403. Without
# a block the job takes exactly what the caller grants.
if [[ -f "$WF" ]]; then
  found="$(grep -nE '^( {0,4})permissions:' "$WF" | paste -sd' ' - || true)"
  if [[ -z "$found" ]]; then
    echo "  ok: ${WF} has no permissions block"
  else
    fail "pin 2: ${WF} has a permissions block (line ${found}); the caller grants them, and a block here would cut them"
  fi
fi

# Pin 3: forsgren is installed from THIS workflow's own commit, exactly as
# metrics.yml does (STANDING FACTS, ruling on forsgren#4: the caller's one
# `uses: ...@<commit> # vX.Y.Z` line is the only version, so nothing takes a
# version as input):
#   - the step "Set up Go" is metrics.yml's own, line for line (the same
#     commit-pinned actions/setup-go, the same go-version, cache: false), so
#     the two workflows build with one Go and one setup-go;
#   - the install step follows it, and its env: sets FORSGREN_SHA to
#     job.workflow_sha and FORSGREN_REPOSITORY to job.workflow_repository, the
#     called workflow's own commit and repository (the github context is the
#     CALLER's in a called workflow, so it would install the caller's commit);
#   - no run: block expands a ${{ }} expression: values reach the shell
#     through env: only, never as text pasted into the script (template
#     injection, zizmor).
if [[ -f "$WF" ]]; then
  want_go="$(step_text "$METRICS" "$GO_STEP")"
  have_go="$(step_text "$WF" "$GO_STEP")"
  install="$(step_text "$WF" "$INSTALL_STEP")"
  if [[ -z "$have_go" ]]; then
    fail "pin 3: ${WF} has no step '${GO_STEP}'"
  elif [[ "$have_go" != "$want_go" ]]; then
    fail "pin 3: the step '${GO_STEP}' of ${WF} is not the one of ${METRICS}"
  else
    echo "  ok: ${WF} sets up Go as ${METRICS} does"
  fi
  if [[ -z "$install" ]]; then
    fail "pin 3: ${WF} has no step '${INSTALL_STEP}'"
  else
    for want in "FORSGREN_SHA: ${EXPR_OPEN} job.workflow_sha }}" "FORSGREN_REPOSITORY: ${EXPR_OPEN} job.workflow_repository }}"; do
      if grep -qF -- "$want" <<< "$install"; then
        echo "  ok: the install step sets ${want}"
      else
        fail "pin 3: the step '${INSTALL_STEP}' does not set '${want}'"
      fi
    done
    if later "$(line_of "$WF" "$INSTALL_STEP")" "$(line_of "$WF" "$GO_STEP")"; then
      echo "  ok: the install step comes after setup-go"
    else
      fail "pin 3: the step '${INSTALL_STEP}' is not after '${GO_STEP}'"
    fi
  fi
  injected="$(run_blocks "$WF" | grep -F -- "${EXPR_OPEN}" | paste -sd' ' - || true)"
  if [[ -z "$injected" ]]; then
    echo "  ok: no run: block expands a GitHub expression"
  else
    fail "pin 3: a run: block of ${WF} expands a GitHub expression, pass it through env: (line ${injected})"
  fi
fi

selftest_end "auto_update.yml is not the reusable workflow forsgren#58 rules" \
  "auto_update.yml runs on workflow_call only"
