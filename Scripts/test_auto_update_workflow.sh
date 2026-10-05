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

selftest_end "auto_update.yml is not the reusable workflow forsgren#58 rules" \
  "auto_update.yml runs on workflow_call only"
