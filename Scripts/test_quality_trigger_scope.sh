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
#   3. a pull_request trigger on main exists, also with no `paths:` and no
#      `paths-ignore:` filter, and there is no pull_request_target;
#   4. workflow_dispatch exists, so a run can be started by hand;
#   5. every job runs on `macos-latest`, GitHub's hosted macOS image.
#
# PINS 3 AND 5 GO TOGETHER (Yves's rulings on forsgren#1, road to public,
# the runner swap). Quality runs on GitHub's `macos-latest`, a throwaway
# virtual machine per run, so a contributor's pull request shows the same
# gate results as a local FBP run. pull_request, NEVER pull_request_target:
# a fork's pull request then gets a read-only token and no secrets, and its
# code runs on a machine that is thrown away after the job. This is
# konenki's second pin (it requires a pull_request trigger), which forsgren
# did not port while Quality ran on a self-hosted runner. The runner pin is
# what keeps pin 3 safe: Scripts/check_workflow_triggers.sh would also turn
# red on a pull_request trigger with a job off GitHub-hosted runners, over
# every workflow, but this check names the one runner Quality must have, so a
# swap to another hosted image (or back to a self-hosted one) is a decision
# made here first.
#
# Self-proving: the same judge runs against synthetic workflows at the end,
# a narrow paths filter, a paths-ignore filter, a missing push trigger, a
# missing or filtered pull_request trigger, a pull_request_target trigger,
# a self-hosted runner and another hosted image, and MUST reject each, and
# must accept the right shape. Without that this file would pass the moment
# its matcher broke and could never be shown failing again.

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
# Read with awk rather than a YAML parser on purpose: PyYAML is a module,
# not a command, so Scripts/required_tools.txt cannot declare it and nothing
# installs it on the hosted runner, and a fixture that dies on a missing
# module is a gate that stopped gating. The shape it reads is the one this
# repo writes: `on:` at column 0, each event two spaces in, its keys four;
# a job's runs-on four spaces in.

# event_block <workflow-file> <event>: that event's own keys, up to the next
# event or top-level key.
event_block() {
  awk -v ev="$2" '
    $0 ~ ("^  " ev ":[[:space:]]*$") { inev=1; next }
    inev && /^  [a-z_]+:/ { inev=0 }
    inev && /^[a-z]/      { inev=0 }
    inev                  { print }
  ' "$1"
}

# judge_event <workflow-file> <event> <why>: the event must run on
# branches ["main"], with no paths and no paths-ignore filter.
judge_event() {
  local wf="$1" ev="$2" why="$3" block
  block="$(event_block "$wf" "$ev")"
  if ! grep -qE '^    branches:[[:space:]]*\[[[:space:]]*"?main"?[[:space:]]*\][[:space:]]*$' <<< "$block"; then
    echo "${ev}: does not run on branches [\"main\"] — ${why}"
  fi
  if grep -qE '^    paths:' <<< "$block"; then
    echo "${ev}: has a paths filter — the secret scan, the data guard, stray tracked files and script references read every tracked file, so any filter leaves a change that runs no gate at all"
  fi
  if grep -qE '^    paths-ignore:' <<< "$block"; then
    echo "${ev}: has a paths-ignore filter — the secret scan, the data guard, stray tracked files and script references read every tracked file, so an ignored path is one a secret or a stray file can arrive through unchecked"
  fi
}

# judge <workflow-file> -> prints one problem per line; silent when the
# trigger and the runner are right.
judge() {
  local wf="$1" runners runner
  if ! grep -qE '^  push:[[:space:]]*$' "$wf"; then
    echo "has no push trigger — nothing runs on a push to main, and a CI that never ran looks exactly like a CI that passed"
  else
    judge_event "$wf" push "every commit on main must run the gates"
  fi

  if ! grep -qE '^  pull_request:[[:space:]]*$' "$wf"; then
    echo "has no pull_request trigger — a contributor's pull request would show no gate result, only the DCO check (forsgren#1: Quality runs on pull requests)"
  else
    judge_event "$wf" pull_request "every pull request into main must run the gates"
  fi
  if grep -qE '^  pull_request_target:' "$wf"; then
    echo "has a pull_request_target trigger — it runs with the base repository's token and secrets while a fork's code is checked out; Quality uses pull_request only"
  fi

  if ! grep -qE '^  workflow_dispatch:' "$wf"; then
    echo "has no workflow_dispatch trigger — a run cannot be started by hand, so checking the runner means pushing a commit"
  fi

  runners="$(sed -nE 's/^    runs-on:[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p' "$wf")"
  if [[ -z "$runners" ]]; then
    echo "has no job with a runs-on this check can read — Quality must run on macos-latest"
  fi
  while IFS= read -r runner; do
    [[ -n "$runner" ]] || continue
    if [[ "$runner" != "macos-latest" ]]; then
      echo "has a job on runs-on: ${runner}, not macos-latest — Quality runs on GitHub's hosted macOS image (forsgren#1, the runner swap), a throwaway machine per run, which is what makes its pull_request trigger safe"
    fi
  done <<< "$runners"
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
  echo "  ok: ${WF} runs on every push to and pull request into main, with no paths filter, and by hand, on macos-latest"
fi

# --- Self-proof: each wrong shape MUST be rejected, the right one accepted.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; finish' EXIT

# write_workflow <name> <on-block> [runs-on]: a minimal workflow with that
# `on:` block, its one job on macos-latest unless a runs-on is given.
write_workflow() {
  {
    echo "name: Sample"
    echo "on:"
    printf '%s\n' "$2"
    echo "jobs:"
    echo "  lint:"
    echo "    runs-on: ${3:-macos-latest}"
    echo "    steps:"
    echo "      - run: echo hi"
  } > "${TMP}/$1.yml"
}

write_workflow narrow '  push:
    branches: ["main"]
    paths:
      - "Scripts/**"
  pull_request:
    branches: ["main"]
  workflow_dispatch:'
write_workflow ignore '  push:
    branches: ["main"]
    paths-ignore:
      - "**.md"
  pull_request:
    branches: ["main"]
  workflow_dispatch:'
write_workflow nopush '  pull_request:
    branches: ["main"]
  workflow_dispatch:'
write_workflow nodispatch '  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]'
write_workflow nopr '  push:
    branches: ["main"]
  workflow_dispatch:'
write_workflow prnarrow '  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
    paths:
      - "internal/**"
  workflow_dispatch:'
write_workflow prtarget '  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
  pull_request_target:
    branches: ["main"]
  workflow_dispatch:'
write_workflow selfhosted '  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
  workflow_dispatch:' '[self-hosted, macOS, ARM64]'
write_workflow ubuntu '  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
  workflow_dispatch:' 'ubuntu-latest'
write_workflow right '  push:
    branches: ["main"]
  pull_request:
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
rejects nopr       "has no pull_request trigger"   "no pull_request trigger"
rejects prnarrow   "pull_request: has a paths filter" "a paths filter on pull_request"
rejects prtarget   "has a pull_request_target"     "a pull_request_target trigger"
rejects selfhosted "not macos-latest"              "a self-hosted runner"
rejects ubuntu     "runs-on: ubuntu-latest, not macos-latest" "another GitHub-hosted image"

right_verdict="$(judge "${TMP}/right.yml")"
if [[ -z "$right_verdict" ]]; then
  echo "  ok: push to and pull_request into main with no filter, plus workflow_dispatch, on macos-latest, is accepted"
else
  fail "the synthetic workflow with the right trigger was REJECTED (${right_verdict}) — the judge would keep this check red on a correct quality.yml"
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: quality.yml's trigger or runner is not the shape forsgren#1 rules: every push to and pull request into main, and by hand, on macos-latest"
  exit 1
fi

echo "OK: quality.yml runs on every push to main, every pull request into it and by hand, on macos-latest, with no paths filter to leave a change unchecked (and each wrong shape is still detected)"
