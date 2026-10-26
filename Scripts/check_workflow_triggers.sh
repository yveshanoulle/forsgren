#!/usr/bin/env bash
# canon: check_workflow_triggers v1
# Scripts/check_workflow_triggers.sh
#
# The workflow-trigger gate, byte-identical across the
# estate's repositories.
#
# THE RULE: a workflow with a job on a self-hosted runner never triggers on a
# pull-request event. On such a trigger a pull request from a fork runs its own
# code on that runner, a machine someone keeps, once the repository is public.
# On a GitHub-hosted runner it runs on a machine thrown away after the job.
# Scripts/test_quality_runner_pins.sh pins the shape quality.yml must have;
# this gate bans the one shape no workflow may have, whatever the file, except
# where a row of the exceptions file says otherwise.
#
# EXCEPTIONS are data, never edited copies: Scripts/workflow_trigger_exceptions.txt,
# one row per workflow file and event, workflow|event|reason. The reason is
# required (why the trigger stays, and the issue that makes it safe); a row
# without one is red. An exception covers exactly that file and that event: a
# NEW pull-request event in the same file, or the same event in another file,
# is a finding again. A row that excuses nothing (the trigger is gone, or the
# job moved to a hosted runner) is red too, so an exception cannot outlive its
# reason. A missing exceptions file is exit 2; a repository with none keeps the
# file with comments only.
#
# Pull-request events: pull_request and pull_request_target, the two the
# ruling names, plus pull_request_review and pull_request_review_comment.
# Those two also run for a fork's pull request and check out its merge commit
# by default, so they open the same door. Other events (workflow_run,
# issue_comment) run the default branch's workflow and code, and are not
# judged here.
#
# FAIL-CLOSED ON THE RUNNER. A job counts as GitHub-hosted only when its
# runs-on is one plain label of a GitHub-hosted image (ubuntu-*, windows-*,
# macos-*). Everything else is judged as if self-hosted: the self-hosted
# label, a list of labels, a custom label alone (only a self-hosted runner
# carries one), a runner group, an expression such as ${{ matrix.os }} (this
# gate cannot evaluate it), a job with no runs-on, and a reusable-workflow job
# (job-level uses:, whose runner is decided in the file it calls). A larger
# GitHub-hosted runner, named by its own label, is therefore red too; a
# workflow that needs one says so here first.
#
# READ WITH AWK, NOT A YAML PARSER, on purpose, as
# Scripts/test_quality_runner_pins.sh does. PyYAML is a Python module, not a command, so
# Scripts/required_tools.txt (commands only) cannot declare it and
# Scripts/install_tools.sh cannot install it, and a gate that dies on a
# missing module on another Mac or on a fresh hosted runner has stopped
# gating. The shapes it reads, and its limits:
#   - `on:` is a top-level key at column 0 (bare, "on" or 'on'); the trigger
#     section is the rest of that line plus every line after it up to the
#     next column-0 key. Comments are dropped (a # at line start or after
#     whitespace). What is left is split into words, and a word that is a
#     pull-request event name is a trigger. That reads the scalar, flow
#     list, flow map, block list and block map forms alike. Its limit is on
#     the safe side: a branch or path literally named pull_request inside the
#     section is red too.
#   - No `on:` key at column 0 is red: a trigger this gate cannot read is not
#     a trigger it has cleared.
#   - Jobs are the keys one level under the column-0 `jobs:`; a job's own
#     keys sit one level deeper (the indent of its first key). runs-on is read
#     at that level: inline, or as the block lines under it.
#
# Usage: Scripts/check_workflow_triggers.sh [workflows-dir [exceptions-file]]
#        (default: .github/workflows; the *.yml and *.yaml files directly in
#        it, the only ones GitHub runs)
# Exit: 0 clean, 1 a finding, a bad or unused exception row, or a scan over
# nothing, 2 workflows dir or exceptions file missing.
# Fixture: Scripts/test_check_workflow_triggers.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

DIR="${1:-.github/workflows}"
EXCEPTIONS="${2:-Scripts/workflow_trigger_exceptions.txt}"

# The pull-request events, one alternation for grep -xE. The row starts at
# column 0 with PR_EVENTS=: Scripts/test_check_workflow_triggers.sh's mutation
# proof replaces it by that anchor.
PR_EVENTS='pull_request|pull_request_target|pull_request_review|pull_request_review_comment'

# A GitHub-hosted image label, the one runs-on value judged as not
# self-hosted.
HOSTED_LABEL='^(ubuntu|windows|macos)-[A-Za-z0-9._-]+$'

if [ ! -d "$DIR" ]; then
  echo "❌ FAIL: workflows dir not found: ${DIR}"
  exit 2
fi
if [ ! -f "$EXCEPTIONS" ]; then
  echo "❌ FAIL: exceptions file not found: ${EXCEPTIONS} (keep it with comments only when there is no exception)"
  exit 2
fi

# The exception rows, workflow|event|reason. EXC_ROWS holds the valid ones; a
# row with a missing field or an empty reason is a finding. Strings, not
# arrays: an empty array under set -u is fatal on bash 3.2.
EXC_ROWS=""
EXC_USED=""
findings=0
while IFS= read -r row; do
  case "$row" in ''|\#*) continue ;; esac
  IFS='|' read -r ex_name ex_event ex_reason <<<"$row"
  ex_has_reason="$(printf '%s' "${ex_reason:-}" | tr -d '[:space:]')"
  if [ -z "${ex_name:-}" ] || [ -z "${ex_event:-}" ] || [ -z "$ex_has_reason" ]; then
    echo "❌ FAIL: ${EXCEPTIONS}: bad row '${row}' — wanted workflow|event|reason, with a reason"
    findings=$((findings + 1))
    continue
  fi
  EXC_ROWS="${EXC_ROWS}${ex_name}|${ex_event}|${ex_reason}"$'\n'
done < "$EXCEPTIONS"

# excepted <workflow> <event> — 0 when a row covers exactly this file and event.
excepted() {
  awk -F'|' -v n="$1" -v e="$2" '$1 == n && $2 == e { f = 1 } END { exit !f }' <<<"$EXC_ROWS"
}

# exception_reason <workflow> <event> — the row's reason.
exception_reason() {
  awk -F'|' -v n="$1" -v e="$2" '$1 == n && $2 == e { print $3; exit }' <<<"$EXC_ROWS"
}

# trigger_events <file> — the pull-request events its `on:` section names,
# one per line; NO_ON_KEY when the file has no `on:` key at column 0.
trigger_events() {
  local section
  section="$(awk -v q="'" '
    function uncomment(s) {
      if (s ~ /^[ \t]*#/) return ""
      sub(/[ \t]+#.*$/, "", s)
      return s
    }
    BEGIN { onkey = "^(on|\"on\"|" q "on" q "):" }
    state == 0 && $0 ~ onkey {
      found = 1; state = 1
      rest = $0; sub(/^[^:]*:/, "", rest)
      print uncomment(rest)
      next
    }
    state == 1 && $0 ~ /^[^ \t#]/ { state = 2 }
    state == 1 { print uncomment($0) }
    END { if (!found) print "NO_ON_KEY" }
  ' "$1")"
  if [ "$section" = "NO_ON_KEY" ]; then
    echo "NO_ON_KEY"
    return 0
  fi
  printf '%s\n' "$section" | tr -c 'A-Za-z0-9_-' '\n' | grep -xE "$PR_EVENTS" | sort -u
}

# job_runners <file> — one line per job: <job> TAB <runs-on>, where runs-on
# is the inline value, the block lines under it joined by spaces, USES for a
# reusable-workflow job, or NONE.
job_runners() {
  awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function uncomment(s) { sub(/[ \t]+#.*$/, "", s); return s }
    function flush() {
      if (job == "") return
      if (ro != "") v = ro; else if (uses) v = "USES"; else v = "NONE"
      print job "\t" v
      job = ""
    }
    BEGIN { state = "before"; J = -1 }
    state == "before" { if ($0 ~ /^jobs:[ \t]*$/) state = "jobs"; next }
    $0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]*#/ { next }
    {
      ind = indent($0)
      if (ind == 0) exit
      if (J < 0) J = ind
      if (ind < J) exit
      if (ind == J) {
        flush()
        job = trim($0); sub(/:.*$/, "", job); gsub(/["\047]/, "", job)
        K = -1; ro = ""; uses = 0; inro = 0
        next
      }
      if (K < 0) K = ind
      if (ind == K) {
        inro = 0
        line = trim(uncomment($0))
        if (line ~ /^runs-on:/) {
          sub(/^runs-on:[ \t]*/, "", line)
          if (line == "") inro = 1; else ro = line
        } else if (line ~ /^uses:/) {
          uses = 1
        }
        next
      }
      if (ind > K && inro) ro = trim(ro " " trim(uncomment($0)))
    }
    END { flush() }
  ' "$1"
}

# hosted <runs-on> — 0 when it is one GitHub-hosted image label.
hosted() {
  local label="$1"
  label="${label#\"}"; label="${label%\"}"
  label="${label#\'}"; label="${label%\'}"
  grep -qE "$HOSTED_LABEL" <<< "$label"
}

files=()
while IFS= read -r f; do
  [ -n "$f" ] && files+=("$f")
done < <(find "$DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "❌ FAIL: no .yml or .yaml workflow in ${DIR} — a scan over nothing is not a clean scan"
  exit 1
fi

selfhosted_files=""
for wf in "${files[@]}"; do
  name="$(basename "$wf")"
  events="$(trigger_events "$wf")"
  if [ "$events" = "NO_ON_KEY" ]; then
    echo "❌ FAIL: ${name}: no on: key at column 0 — this gate cannot read its triggers, and a trigger it cannot read is not one it has cleared"
    findings=$((findings + 1))
    continue
  fi

  runners="$(job_runners "$wf")"
  not_hosted=""
  while IFS=$'\t' read -r job ro; do
    [ -n "$job" ] || continue
    hosted "$ro" || not_hosted="${not_hosted}${job}"$'\t'"${ro}"$'\n'
  done <<<"$runners"
  if [ -z "$runners" ]; then
    not_hosted="(none)"$'\t'"no job found under jobs:"$'\n'
  fi
  [ -n "$not_hosted" ] && selfhosted_files="${selfhosted_files} ${name}"

  [ -n "$events" ] || continue
  [ -n "$not_hosted" ] || continue
  while IFS=$'\t' read -r job ro; do
    [ -n "$job" ] || continue
    case "$ro" in
      USES) runner="a reusable workflow (job-level uses:), whose runner this file does not show" ;;
      NONE) runner="no runs-on this gate could read" ;;
      *)    runner="runs-on ${ro}" ;;
    esac
    while IFS= read -r event; do
      [ -n "$event" ] || continue
      if excepted "$name" "$event"; then
        EXC_USED="${EXC_USED}${name}|${event}"$'\n'
        echo "excepted: ${name}: ${event} with job '${job}' (${runner}) — $(exception_reason "$name" "$event")"
        continue
      fi
      echo "❌ FAIL: ${name}: triggers on ${event} and job '${job}' has ${runner}, not a GitHub-hosted image label — a pull request from a fork would run its own code on the self-hosted runner. Remove the trigger, or record an exception row with its reason in ${EXCEPTIONS}."
      findings=$((findings + 1))
    done <<<"$events"
  done <<<"$not_hosted"
done

# An exception row nothing used excuses nothing: red.
while IFS='|' read -r ex_name ex_event ex_reason; do
  [ -n "$ex_name" ] || continue
  if ! grep -qxF -- "${ex_name}|${ex_event}" <<<"$EXC_USED"; then
    echo "❌ FAIL: ${EXCEPTIONS}: ${ex_name}|${ex_event} excuses no finding — the trigger is gone or its job is on a hosted runner; remove the row"
    findings=$((findings + 1))
  fi
done <<<"$EXC_ROWS"

if [ "$findings" -ne 0 ]; then
  echo ""
  echo "workflow triggers: ${findings} finding(s) in ${DIR}."
  exit 1
fi

echo "✅ workflow triggers: ${#files[@]} workflow file(s) in ${DIR}; no unexcused pull-request event reaches a job off GitHub-hosted runners (self-hosted or unproven runners in:${selfhosted_files:- none}; exceptions used: $(printf '%s' "$EXC_USED" | grep -c . || true))"
exit 0
