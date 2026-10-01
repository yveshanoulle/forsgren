#!/usr/bin/env bash
# Scripts/test_quality_trigger_scope.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# The gates must actually be reachable — unit 391, ported from
# coachretreat-website's unit 390 the day it was found there.
#
# Ported from konenki-website 2026-10-01 (forsgren#1, ladder step 14).
# konenki's history, which is why this check exists:
#
#   quality.yml was gated behind `paths: ["Site/**", ".github/workflows/
#   quality.yml"]`, so a commit touching only Scripts/ or sfl.sh triggered
#   nothing at all, and the file its fixtures pin (deploy-feta.yml) sat
#   outside the trigger of the workflow that checks it. A green CI then
#   means "nothing ran", which is indistinguishable from "everything
#   passed".
#
# THE RULE (konenki's): either Quality has no paths filter, or the filter
# covers every path the gates read or build from. A filter is allowed — an
# incorrect one is not.
#
# FORSGREN'S ANSWER TO THE RULE: no paths filter at all. Several gates here
# read EVERY tracked file, not a directory: the secret scan (the whole working
# tree), the data guard (installation config or data at any depth), stray
# tracked files (a .DS_Store or a workflow copy anywhere) and script
# references (every script, workflow, order file and doc). No glob list short
# of everything covers those, so the only filter that keeps the rule is none.
# konenki keeps a filter because a feta deploy chains off its Quality run and
# must not fire for a documentation edit; nothing chains off forsgren's.
# So this check pins, on .github/workflows/quality.yml:
#   1. a push trigger on main exists (without one nothing runs on a push, and
#      the absence passes every filter check silently);
#   2. the push trigger has no `paths:` and no `paths-ignore:` filter;
#   3. workflow_dispatch exists, so a run can be started by hand.
#
# NOT PORTED: konenki's second pin, which requires a pull_request trigger.
# forsgren is the opposite by Yves's ruling on forsgren#1: the job runs on a
# self-hosted runner, so Quality never triggers on pull_request or
# pull_request_target (a pull request from a fork would run its code on the
# runner the day the repository is public). That ban is its own gate, the
# next step of the forsgren#1 ladder; it is not checked here.
#
# Self-proving: the same judge runs against synthetic workflows at the end,
# a narrow paths filter, a paths-ignore filter and a missing push trigger,
# and MUST reject each, and must accept the right shape. Without that this
# file would pass the moment its matcher broke and could never be shown
# failing again.

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: quality trigger scope check aborted before completing" >&2
    exit 1
  fi
}

trap finish EXIT

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

# judge <workflow-file> -> prints one problem per line; silent when the
# trigger is right.
#
# Read with awk rather than a YAML parser on purpose: pyyaml is not
# guaranteed on the self-hosted runner, and a fixture that dies on a missing
# module is a gate that stopped gating. The shape it reads is the one this
# repo writes: `on:` at column 0, each event two spaces in, its keys four.
judge() {
  local wf="$1" push_block
  if ! grep -qE '^  push:[[:space:]]*$' "$wf"; then
    echo "has no push trigger — nothing runs on a push to main, and a CI that never ran looks exactly like a CI that passed"
    return 0
  fi

  # The push event's own keys, up to the next event or top-level key.
  push_block="$(awk '
    /^  push:[[:space:]]*$/ { inpush=1; next }
    inpush && /^  [a-z_]+:/ { inpush=0 }
    inpush && /^[a-z]/      { inpush=0 }
    inpush                  { print }
  ' "$wf")"

  if ! grep -qE '^    branches:[[:space:]]*\[[[:space:]]*"?main"?[[:space:]]*\][[:space:]]*$' <<< "$push_block"; then
    echo "push: does not run on branches [\"main\"] — every commit on main must run the gates"
  fi
  if grep -qE '^    paths:' <<< "$push_block"; then
    echo "push: has a paths filter — the secret scan, the data guard, stray tracked files and script references read every tracked file, so any filter leaves a change that runs no gate at all"
  fi
  if grep -qE '^    paths-ignore:' <<< "$push_block"; then
    echo "push: has a paths-ignore filter — the secret scan, the data guard, stray tracked files and script references read every tracked file, so an ignored path is one a secret or a stray file can arrive through unchecked"
  fi

  if ! grep -qE '^  workflow_dispatch:' "$wf"; then
    echo "has no workflow_dispatch trigger — a run cannot be started by hand, so checking the runner means pushing a commit"
  fi
}

WF=".github/workflows/quality.yml"
if [[ ! -f "$WF" ]]; then
  echo "FAIL: $WF not found" >&2
  exit 1
fi

out="$(judge "$WF")"
if [[ -n "$out" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && fail "${WF} ${line}"
  done <<< "$out"
else
  echo "  ok: ${WF} runs on every push to main, with no paths filter, and by hand"
fi

# --- Self-proof: each wrong shape MUST be rejected, the right one accepted.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; finish' EXIT

# write_workflow <name> <on-block>: a minimal workflow with that `on:` block.
write_workflow() {
  {
    echo "name: Sample"
    echo "on:"
    printf '%s\n' "$2"
    echo "jobs:"
    echo "  lint:"
    echo "    runs-on: ubuntu-latest"
    echo "    steps:"
    echo "      - run: echo hi"
  } > "${TMP}/$1.yml"
}

write_workflow narrow '  push:
    branches: ["main"]
    paths:
      - "Scripts/**"
  workflow_dispatch:'
write_workflow ignore '  push:
    branches: ["main"]
    paths-ignore:
      - "**.md"
  workflow_dispatch:'
write_workflow nopush '  workflow_dispatch:'
write_workflow nodispatch '  push:
    branches: ["main"]'
write_workflow right '  push:
    branches: ["main"]
  workflow_dispatch:'

# rejects <name> <expected> <what>: the judge must name <expected> for it.
rejects() {
  local verdict
  verdict="$(judge "${TMP}/$1.yml")"
  if grep -qF -- "$2" <<< "$verdict"; then
    echo "  ok: ${3} is rejected"
  else
    fail "the synthetic workflow with ${3} was ACCEPTED (verdict: ${verdict:-none}) — this check cannot detect the defect it exists for"
  fi
}

rejects narrow     "has a paths filter"            "a narrow paths filter"
rejects ignore     "has a paths-ignore filter"     "a paths-ignore filter"
rejects nopush     "has no push trigger"           "no push trigger"
rejects nodispatch "has no workflow_dispatch"      "no workflow_dispatch trigger"

right_verdict="$(judge "${TMP}/right.yml")"
if [[ -z "$right_verdict" ]]; then
  echo "  ok: push to main with no filter, plus workflow_dispatch, is accepted"
else
  fail "the synthetic workflow with the right trigger was REJECTED (${right_verdict}) — the judge would keep this check red on a correct quality.yml"
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: quality.yml's trigger does not reach everything its gates check"
  exit 1
fi

echo "OK: quality.yml runs on every push to main and by hand, with no paths filter to leave a change unchecked (and each wrong shape is still detected)"
