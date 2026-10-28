#!/usr/bin/env bash
# Scripts/test_quality_runner_pins.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# forsgren's own pins on .github/workflows/quality.yml (forsgren#240, step 1).
#
# Not canon: forsgren only. Scripts/test_quality_trigger_scope.sh is the
# sites' shared gate, byte-identical (a filter must cover every path the gates
# read, or there is no filter); it handed over everything that is forsgren's own.
# The two together replace what that one script held before forsgren#240:
# the shared script keeps the trigger-scope rule (no filter, or a filter that
# covers every glob, and a pull_request trigger at all), and THIS script pins
# the exact shape forsgren rules for quality.yml.
#
# History (forsgren#1, ladder step 14; ported from another estate repository
# 2026-10-01): the gate exists because of what happened to konenki's Quality.
#
#   quality.yml was gated behind `paths: ["Site/**", ".github/workflows/
#   quality.yml"]`, so a commit touching only Scripts/ or sfl.sh triggered
#   nothing at all, and the file its fixtures pin sat
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
# a repository whose deploy chains off its Quality run may keep a filter, so a
# documentation edit does not fire the deploy; nothing chains off forsgren's.
# So this check pins, on .github/workflows/quality.yml:
#   1. a push trigger on main exists (without one nothing runs on a push, and
#      the absence passes every filter check silently);
#   2. the push trigger has no `paths:` and no `paths-ignore:` filter;
#   3. a pull_request trigger on main exists, also with no `paths:` and no
#      `paths-ignore:` filter, and there is no pull_request_target;
#   4. workflow_dispatch exists, so a run can be started by hand;
#   5. each job runs on exactly the image this check names for it: the Linux
#      jobs (LINUX_JOBS: `lint` since forsgren#427; `workflows`, `report`,
#      `summary`, `isolation_1` and `isolation_2` since forsgren#447, step 3)
#      on `ubuntu-latest`, every other job on `macos-latest`, GitHub's hosted
#      macOS image. No other image is allowed, and a Linux job back on macOS
#      is as red as a macOS job on Linux: the move is a decision made here;
#   6. at most MACOS_SLOTS (5) `macos-latest` jobs start together, the jobs
#      with no `needs:` (forsgren#447): GitHub runs at most 5 macOS jobs at
#      once for the account, so a sixth would wait in the queue for a slot.
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
    echo "FAIL: quality runner pins check aborted before completing" >&2
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

# LINUX_JOBS: the jobs that run on ubuntu-latest (pin 5); every other job runs
# on macos-latest. lint (forsgren#427): its four tools read files only.
# workflows, report, summary, isolation_1 and isolation_2 (forsgren#447, step
# 3): their gates read workflows and scripts or check a decoy repository and
# the step summary, and none needs bash 3.2, a BSD tool, sandbox-exec,
# LanguageTool, Homebrew's gitleaks or Chrome, which keep the other jobs on
# macOS.
LINUX_JOBS=(lint workflows report summary isolation_1 isolation_2)
# MACOS_SLOTS: GitHub's limit of macOS jobs running at once for the account
# (pin 6, forsgren#447: measured, 5 started and the sixth waited).
MACOS_SLOTS=5

# want_runner <job>: the image pin 5 names for that job.
want_runner() {
  local j
  for j in "${LINUX_JOBS[@]}"; do
    if [[ "$j" == "$1" ]]; then
      echo ubuntu-latest
      return 0
    fi
  done
  echo macos-latest
}

# job_runners <workflow-file>: one line per job, `<job> TAB <runs-on> TAB
# <needs>`: the job is the two-space key under `jobs:`, the runs-on its
# four-space key, and needs `yes` when the job has a four-space `needs:` key,
# else `no`.
job_runners() {
  awk '
    function flush() { if (job != "") print job "\t" r "\t" (needs ? "yes" : "no") }
    /^jobs:/ { injobs = 1; next }
    injobs && /^[^[:space:]]/ { injobs = 0 }
    injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); job = $1; sub(/:$/, "", job); r = ""; needs = 0 }
    injobs && /^    needs:/ { needs = 1 }
    injobs && /^    runs-on:/ {
      r = $0
      sub(/^    runs-on:[[:space:]]*/, "", r)
      sub(/[[:space:]]+$/, "", r)
    }
    END { flush() }
  ' "$1"
}

# judge <workflow-file> -> prints one problem per line; silent when the
# trigger and the runner are right.
judge() {
  local wf="$1" runners job runner
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

  runners="$(job_runners "$wf")"
  if [[ -z "$runners" ]]; then
    echo "has no job with a runs-on this check can read — Quality must run on macos-latest"
  fi
  local want needs starting=0
  while IFS=$'\t' read -r job runner needs; do
    [[ -n "$job" ]] || continue
    want="$(want_runner "$job")"
    if [[ "$runner" == "macos-latest" && "$needs" == "no" ]]; then
      starting=$((starting + 1))
    fi
    [[ "$runner" == "$want" ]] && continue
    echo "has a job (${job}) on runs-on: ${runner:-none}, not ${want} — Quality runs on GitHub's hosted images" \
      "(forsgren#1, the runner swap), a throwaway machine per run, which is what makes its pull_request" \
      "trigger safe; the jobs ${LINUX_JOBS[*]} run on ubuntu-latest (forsgren#427, forsgren#447) and every" \
      "other job on macos-latest"
  done <<< "$runners"
  if [[ "$starting" -gt "$MACOS_SLOTS" ]]; then
    echo "starts ${starting} macos-latest jobs together (jobs with no needs:), more than the ${MACOS_SLOTS}" \
      "macOS jobs GitHub runs at once for the account, so $((starting - MACOS_SLOTS)) would wait for a slot" \
      "(forsgren#447)"
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
  echo "  ok: ${WF} runs on every push to and pull request into main, with no paths filter, and by hand," \
    "the jobs ${LINUX_JOBS[*]} on ubuntu-latest and the others on macos-latest, at most ${MACOS_SLOTS} macOS" \
    "jobs starting together"
fi

# --- Self-proof: each wrong shape MUST be rejected, the right one accepted.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; finish' EXIT

# write_workflow <name> <on-block> [runs-on] [job]: a minimal workflow with
# that `on:` block, its one job (quality unless a job is given) on macos-latest
# unless a runs-on is given.
write_workflow() {
  {
    echo "name: Sample"
    echo "on:"
    printf '%s\n' "$2"
    echo "jobs:"
    echo "  ${4:-quality}:"
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
write_workflow ubuntuquality '  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
  workflow_dispatch:' 'ubuntu-latest' quality
write_workflow ubuntu2204 '  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
  workflow_dispatch:' 'ubuntu-22.04' lint
write_workflow lintubuntu '  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
  workflow_dispatch:' 'ubuntu-latest' lint
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
rejects ubuntuquality "(quality) on runs-on: ubuntu-latest, not macos-latest" "another job than lint on ubuntu-latest"
rejects ubuntu2204 "(lint) on runs-on: ubuntu-22.04, not ubuntu-latest" "the lint job on another hosted image"

TRIGGERS='  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
  workflow_dispatch:'

# Each Linux job of forsgren#447 back on macOS is red; on ubuntu-latest it is accepted.
for j in workflows report summary isolation_1 isolation_2; do
  write_workflow "${j}_mac" "$TRIGGERS" macos-latest "$j"
  rejects "${j}_mac" "(${j}) on runs-on: macos-latest, not ubuntu-latest" "the ${j} job back on macos-latest"
  write_workflow "${j}_ubuntu" "$TRIGGERS" ubuntu-latest "$j"
  verdict="$(judge "${TMP}/${j}_ubuntu.yml")"
  if [[ -z "$verdict" ]]; then
    echo "  ok: the ${j} job on ubuntu-latest is accepted (forsgren#447)"
  else
    fail "the synthetic workflow with the ${j} job on ubuntu-latest was REJECTED (${verdict})"
  fi
done

# write_jobs <name> <job:runner:needs>...: a workflow with the right triggers and
# one job per argument, on that runner, with `needs: [first]` when needs is yes.
write_jobs() {
  local name="$1" spec job runner needs
  shift
  {
    echo "name: Sample"
    echo "on:"
    printf '%s\n' "$TRIGGERS"
    echo "jobs:"
    for spec in "$@"; do
      IFS=: read -r job runner needs <<< "$spec"
      echo "  ${job}:"
      [[ "$needs" == yes ]] && echo "    needs: [quality]"
      echo "    runs-on: ${runner}"
      echo "    steps:"
      echo "      - run: echo hi"
    done
  } > "${TMP}/${name}.yml"
}

# Pin 6: six macOS jobs starting together are red; five, and a sixth that waits
# on a needs:, are accepted.
write_jobs six_macos quality:macos-latest:no quality_2:macos-latest:no browser_1:macos-latest:no \
  browser:macos-latest:no extra_1:macos-latest:no extra_2:macos-latest:no
rejects six_macos "starts 6 macos-latest jobs together" "six macOS jobs with no needs:"
write_jobs five_macos quality:macos-latest:no quality_2:macos-latest:no browser_1:macos-latest:no \
  browser:macos-latest:no extra_1:macos-latest:no preview:macos-latest:yes lint:ubuntu-latest:no
verdict="$(judge "${TMP}/five_macos.yml")"
if [[ -z "$verdict" ]]; then
  echo "  ok: five macOS jobs starting together, a sixth with needs: and a Linux job are accepted"
else
  fail "the synthetic workflow with five macOS jobs starting together was REJECTED (${verdict})"
fi

right_verdict="$(judge "${TMP}/right.yml")"
if [[ -z "$right_verdict" ]]; then
  echo "  ok: push to and pull_request into main with no filter, plus workflow_dispatch, on macos-latest, is accepted"
else
  fail "the synthetic workflow with the right trigger was REJECTED (${right_verdict}) — the judge would keep this check red on a correct quality.yml"
fi

lint_verdict="$(judge "${TMP}/lintubuntu.yml")"
if [[ -z "$lint_verdict" ]]; then
  echo "  ok: the lint job on ubuntu-latest is accepted (forsgren#427)"
else
  fail "the synthetic workflow with the lint job on ubuntu-latest was REJECTED (${lint_verdict}) —" \
    "the allowance for forsgren#427 does not work"
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: quality.yml's trigger or runner is not the shape forsgren#1 rules: every push to and pull" \
    "request into main, and by hand, the jobs ${LINUX_JOBS[*]} on ubuntu-latest and the others on" \
    "macos-latest, at most ${MACOS_SLOTS} macOS jobs starting together"
  exit 1
fi

echo "OK: quality.yml runs on every push to main, every pull request into it and by hand, the jobs" \
  "${LINUX_JOBS[*]} on ubuntu-latest and the others on macos-latest, at most ${MACOS_SLOTS} macOS jobs" \
  "starting together, with no paths filter to leave a change unchecked (and each wrong shape is still detected)"
