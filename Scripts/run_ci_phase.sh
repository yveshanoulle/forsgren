#!/usr/bin/env bash
# canon: run_ci_phase v8
# v8 (forsgren#646, decision #647 A; canon home forsgren): one runner for every site. It joins the two lines that split after v1: forsgren's v2 to v4 (group row arguments as shards, forsgren#426; the report folder per run and the cancel, forsgren#574; the capture file unlinked at once, forsgren#614) and the sites' v2 to v7 (the build-volume TMPDIR, the job argument, the report folder and cancel, gate selection, the unlinked capture file). New in v8: the arguments are split with `read -r -a` and held to a safe character set, a named job may run post rows, the default job runs the rows no job lists, and the build-volume TMPDIR and gate selection apply only where the repository has their scripts.
# Scripts/run_ci_phase.sh <pre|post> <rows-file> <details-dir> [<job>]
# Scripts/run_ci_phase.sh report-dir
#
# CI's gate loop. .github/workflows/quality.yml calls it
# twice, `pre` before the build step (if the repository has one) and `post`
# after it, the way FBP calls `./sfl.sh pre` and `./sfl.sh post` around the same
# build. The loop reads Scripts/gate_report_order.txt with sfl.sh's own row
# rules, so sfl and CI run the same rows, in the same order, under the same
# labels, by construction rather than by two lists kept in step:
#   - `#` lines and blank lines are skipped;
#   - a row whose script is `n/a` is skipped (it declares a gate this repo
#     does not have, with the reason);
#   - a row runs only in the phase its third field names;
#   - a last line with no trailing newline is still read;
#   - a malformed row (no label, no script, a script path that is not
#     Scripts/<name>.sh, a phase other than pre or post, an unknown class) is a
#     red row in whichever phase and job runs, named, never skipped: a typo in
#     the phase field would otherwise drop the gate from BOTH phases unseen,
#     and it has no reliable label to be given to a job by;
#   - a declared script that is missing, or exists but is not executable, is a
#     red row, named, never skipped;
#   - a failing gate does NOT stop the phase: every row of the phase runs, so
#     one run reports every failure, as sfl does;
#   - a failure on a `secret-class` row makes the exit 2, as sfl's does.
# Scripts/test_run_ci_phase.sh pins all of this, at runtime, against stub gates
# and with mutated copies of this runner.
#
# Extracted from the workflow rather than written inline in it: a loop in YAML
# is a loop nothing outside CI ever runs (estate rule after another estate repository's
# deploy-i18n.yml, 2026-06-11).
#
# THE ONE THING CI DOES THAT sfl DOES NOT: it is check-only, and it checks
# that it was. sfl may fix (it exports GATE_FIX=1, under which the gates that
# can heal do, and the change rides into the commit); CI never sets it and
# must report what the
# commit CONTAINS, not what it could be fixed into. So after each gate the
# runner compares `git status --porcelain` with what it was before that gate,
# and a gate that changed the checked-out tree is a red row, named, even when
# it exited 0. No gate list is kept for this: any gate that writes is caught.
#
# Per gate: the output captured guarded, so it survives
# GitHub's `shell: bash` (`bash --noprofile --norc -e -o pipefail`), echoed to
# the log, one `<label>|<mark>` line appended to <rows-file>, and
# <details-dir>/<slug>.md written (slug: the label with every character
# outside A-Za-z0-9 turned into _). Scripts/render_quality_report.sh renders
# both into the step summary, in declared order.
#
# Each gate gets /dev/null as stdin: the loop reads the order file on stdin,
# and a gate that read its own stdin would swallow the rows after it.
#
# JOBS. Quality runs its gates in parallel jobs of one workflow, and
# Scripts/ci_job_groups.txt says which job runs which gate, one
# `<job>|<label>[|<arguments>]` row each (the label exactly as the order file
# has it; the phase comes from the order file). The optional fourth argument
# names the job:
#   - no job (or `main`, the name forsgren's workflow gives it) is the default
#     job: it runs, in either phase, every row the group file gives to no job,
#     and with no group file every row. So a gate is in exactly one job and a
#     new gate is never in none. A site that gives every pre row to a job calls
#     its post phase with no job and runs every post row, as it always did;
#   - a named job runs, in the phase it is called with, the rows the group file
#     gives to it, pre or post (a job that builds its own site runs its own
#     post gates). A job with no row in that phase is the empty phase, red.
# A job name is letters, digits, _ and -; any other, or a job the group file
# does not name, is a usage error (64), named. A missing group file with a job
# is red. The group file itself is checked before any gate, in every job: a
# label that is no row of the order file, a job name with another character,
# a row for the job `main` (the default job is not listed) and the same
# `<job>|<label>` twice are each red, named, since each would take a gate out
# of its job unseen.
#
# SHARDS (group row arguments, forsgren#426, decision #644 A). The third field
# of a group row is the arguments its job runs the gate with:
# `<job>|<label>|--shard 1/2`. Several jobs may name the same label, each with
# its own arguments; the gate then runs in each of those jobs and in no other.
# The field may hold only letters, digits, _ . / = - and spaces; it is split
# into words by `read -r -a`, never by eval or an unquoted expansion, so no
# quote, glob, variable or command in it is ever expanded. Any other character
# makes the row red in its job, named, its gate not run, while the job's other
# gates still run. The row a gate with arguments records is named for them,
# `<label> (shard 1/2)` (the words, the first without its leading dashes), so
# a red names its shard and the report job can join the shards of one gate
# (Scripts/merge_quality_report.sh). A row with no third field, or an empty
# one, is the plain `<job>|<label>` it always was.
#
# Exit: 0 all rows of the phase passed; 1 a row failed, the phase has no row at
# all (a phase that ran nothing is not green), the group file is wrong or no
# temp file can be made; 2 a secret-class row failed; 64 bad usage.
#
# TMPDIR (estate issue 386, where Scripts/builds_tmpdir.sh exists): a
# self-hosted runner's .env TMPDIR reaches the runner process but not the job
# steps, whose temp files went to the default folder on the internal disk. So
# in a repository that has Scripts/builds_tmpdir.sh the runner, before its
# first gate, exports the temp folder that script prints, with the same
# `canon-block: builds-tmpdir v2` export block sfl.sh and FBP.sh carry there:
# the build volume's folder when it is mounted and writable, else the default
# TMPDIR with the ⚠️ line, and the phase runs on (estate decision 388); a
# failing script or an empty answer stops the phase before any gate. The
# summary block names the folder in the log and, when GITHUB_STEP_SUMMARY is
# set, on the run page. A repository without the script (a GitHub-hosted
# runner has no build volume) keeps the TMPDIR it was given, and the runner
# says nothing about it: that is the normal case there, not a fallback.
#
# REPORT FOLDER AND CANCEL (forsgren#574): a self-hosted runner reuses its
# temp folder, and a cancelled job's loop used to keep running and append its
# rows into the NEXT run's fixed quality_rows.md. Two fixes:
#   - `report-dir` prints the folder a job keeps its rows (quality_rows.md),
#     details (quality_details/) and any hand-over (handover/) in:
#     $RUNNER_TEMP/quality_<run id>_<run attempt>_<job>. An older loop writes
#     to its own folder and cannot touch a newer run's. An unset or empty
#     RUNNER_TEMP, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT or GITHUB_JOB is exit 64.
#   - on SIGTERM or SIGINT (the runner's cancel) the loop kills its gate and
#     everything the gate started, writes no row (its capture file is unlinked at once) and
#     exits 143 or 130. Each gate therefore runs in the background and the loop
#     waits for it: bash runs a trap only between commands, never while it
#     waits on a foreground command.
#
# GATE SELECTION (estate decision 565, where the repository has the CI gate
# selection library, lib_ci_gate_select.sh beside this runner): on a push the
# runner asks the FBP's own selector (that library over the FBP's gate
# selection library and its gate inputs file) about the push's change set, from CI_GATE_EVENT
# (github.event_name) and CI_GATE_BASE (github.event.before). A gate it skips
# is not run: its row is `<label>|⏭ not run (selector: <reason>)`, its details
# file says so, and the phase counts it as not run, never as passed.
# Everything else runs every gate, and the one place that decides is
# ci_gate_select_init: an event other than push, a new branch, a force-push, a
# before this checkout cannot reach, an empty range or any failure to list the
# range. Without the library every gate runs: never a skipped gate. That full
# run is silent when the repository has no library and its workflow asks for
# no selection (no CI_GATE_EVENT); a library that is there but cannot be read,
# or a workflow that sets CI_GATE_EVENT without one, is named in the log and
# the step summary.
#
# Testing seam: RUN_CI_PHASE_ROOT replaces the repository root, so
# Scripts/test_run_ci_phase.sh can run the loop over a synthetic order file
# and stub gates.

set -uo pipefail

# shellcheck source=Scripts/lib_tmp.sh
source "$(dirname "$0")/lib_tmp.sh"
ROOT="${RUN_CI_PHASE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

ORDER="Scripts/gate_report_order.txt"
JOB_GROUPS="Scripts/ci_job_groups.txt"

usage() {
  echo "usage: run_ci_phase.sh <pre|post> <rows-file> <details-dir> [<job>]" >&2
  exit 64
}

if [ "$#" -eq 1 ] && [ "$1" = "report-dir" ]; then
  for v in RUNNER_TEMP GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_JOB; do
    [ -n "${!v:-}" ] || { echo "report-dir: ${v} is not set" >&2; exit 64; }
  done
  printf '%s/quality_%s_%s_%s\n' "$RUNNER_TEMP" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" "$GITHUB_JOB"
  exit 0
fi

[ "$#" -eq 3 ] || [ "$#" -eq 4 ] || usage
PHASE="$1"
ROWS="$2"
DETAILS="$3"
JOB="${4:-}"
case "$PHASE" in
  pre|post) ;;
  *) echo "❌ FAIL: the phase '${PHASE}' is neither pre nor post" >&2; usage ;;
esac
if [ "$#" -eq 4 ]; then
  case "$JOB" in
    ''|*[!A-Za-z0-9_-]*) echo "❌ FAIL: the job name '${JOB}' is empty or holds a character other than letters, digits, _ and -" >&2; usage ;;
  esac
fi
# `main` is the default job's name in forsgren's workflow.
[ "$JOB" != "main" ] || JOB=""

BUILDS_TMPDIR=""
BUILDS_TMPDIR_WARNING=""
if [ -e ./Scripts/builds_tmpdir.sh ]; then
  # canon-block: builds-tmpdir v2 begin (export)
  # estate issue 386: temp files go on the build volume when it is mounted and
  # writable, else to the default TMPDIR with a ⚠️ line (estate decision 388:
  # keep working the old way, never silently). Before the first script this file
  # runs, so every gate and every tool it starts inherits TMPDIR. The ⚠️ line is
  # kept for the summary. An empty answer or a failed script stops the run.
  BUILDS_TMPDIR_WARNING_FILE="$(mktemp "${TMPDIR:-/tmp}/builds_tmpdir_warning.XXXXXX")"
  BUILDS_TMPDIR="$(./Scripts/builds_tmpdir.sh 2>"$BUILDS_TMPDIR_WARNING_FILE")" || BUILDS_TMPDIR=""
  BUILDS_TMPDIR_WARNING="$(cat "$BUILDS_TMPDIR_WARNING_FILE")"
  rm -f "$BUILDS_TMPDIR_WARNING_FILE"
  [ -z "$BUILDS_TMPDIR_WARNING" ] || printf '%s\n' "$BUILDS_TMPDIR_WARNING" >&2
  if [ -z "$BUILDS_TMPDIR" ]; then
    echo "❌ Scripts/builds_tmpdir.sh failed or named no temp folder; no gate ran" >&2
    exit 1
  fi
  export TMPDIR="$BUILDS_TMPDIR"
  # canon-block: builds-tmpdir v2 end
fi

# tmpdir_summary: the temp folder row, and the ⚠️ line on a fallback.
tmpdir_summary() {
  # canon-block: builds-tmpdir v2 begin (summary)
  printf '  %-16s %s\n' "temp folder" "${BUILDS_TMPDIR:-}"
  [ -z "${BUILDS_TMPDIR_WARNING:-}" ] || printf '  %s\n' "$BUILDS_TMPDIR_WARNING"
  # canon-block: builds-tmpdir v2 end
}
if [ -n "$BUILDS_TMPDIR" ]; then
  tmpdir_summary
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    if ! { printf '**CI %s**\n\n```\n' "$PHASE"; tmpdir_summary; printf '```\n\n'; } >> "$GITHUB_STEP_SUMMARY"; then
      echo "❌ FAIL: could not append the temp folder to the step summary ${GITHUB_STEP_SUMMARY}" >&2
      exit 1
    fi
  fi
fi

if [ ! -f "$ORDER" ]; then
  echo "❌ FAIL: ${ORDER} is missing — every gate is declared there, so without it no gate runs" >&2
  exit 1
fi

if [ -n "$JOB" ] && [ ! -f "$JOB_GROUPS" ]; then
  echo "❌ FAIL: ${JOB_GROUPS} is missing — it assigns each gate to a job, so without it job ${JOB} has no gate to run" >&2
  exit 1
fi

# The group file, before any gate and in every job: a wrong row would take a
# gate out of its job unseen.
if [ -f "$JOB_GROUPS" ]; then
  while IFS='|' read -r group_job group_label _group_args || [ -n "${group_job:-}${group_label:-}" ]; do
    case "$group_job" in \#*|'') continue ;; esac
    case "$group_job" in
      main) echo "❌ FAIL: ${JOB_GROUPS} gives the gate '${group_label:-}' to the job main, the default job, which runs the gates no row gives to a job — leave the gate out instead" >&2; exit 1 ;;
      *[!A-Za-z0-9_-]*) echo "❌ FAIL: ${JOB_GROUPS} names the job '${group_job}', which holds a character other than letters, digits, _ and -" >&2; exit 1 ;;
    esac
    if [ -z "${group_label:-}" ] || ! awk -F'|' -v l="$group_label" '$0 !~ /^#/ && $1 == l && $2 != "" { f = 1 } END { exit !f }' "$ORDER"; then
      echo "❌ FAIL: ${JOB_GROUPS} names the gate '${group_label:-}' for the job ${group_job}, which is no row of ${ORDER} — the gate would run in no job" >&2
      exit 1
    fi
  done < "$JOB_GROUPS"
  twice="$(awk -F'|' '$0 !~ /^#/ && $1 != "" && seen[$1 "|" $2]++ == 1 { print $1 "|" $2 }' "$JOB_GROUPS")"
  if [ -n "$twice" ]; then
    echo "❌ FAIL: ${JOB_GROUPS} gives a gate to the same job twice: ${twice//$'\n'/, }" >&2
    exit 1
  fi
fi

if [ -n "$JOB" ] && ! awk -F'|' -v j="$JOB" '$0 !~ /^#/ && $1 == j { f = 1 } END { exit !f }' "$JOB_GROUPS"; then
  echo "❌ FAIL: the job '${JOB}' has no gate in ${JOB_GROUPS}" >&2
  usage
fi

# in_job <label>: succeeds when the gate runs in this job. The default job runs
# every gate the group file does not list; a named job runs the gates it lists.
in_job() {
  if [ -z "$JOB" ]; then
    [ ! -f "$JOB_GROUPS" ] || ! awk -F'|' -v l="$1" '$0 !~ /^#/ && $2 == l { f = 1 } END { exit !f }' "$JOB_GROUPS"
  else
    awk -F'|' -v j="$JOB" -v l="$1" '$0 !~ /^#/ && $1 == j && $2 == l { f = 1 } END { exit !f }' "$JOB_GROUPS"
  fi
}

# job_args <label>: the third field of this job's row for the gate, as written
# (everything after the second |), empty for the default job and a plain row.
job_args() {
  [ -n "$JOB" ] || return 0
  awk -F'|' -v j="$JOB" -v l="$1" '$0 !~ /^#/ && $1 == j && $2 == l {
    s = $0; sub(/^[^|]*\|[^|]*\|?/, "", s); print s; exit }' "$JOB_GROUPS"
}

mkdir -p "$DETAILS" || exit 1
touch "$ROWS" || exit 1

# Gate selection, where the repository has the library. The library is this
# script's own, the data is the root's.
SELECT_NOTE=""
SELECT_LIB="$(dirname "$0")/lib_ci_gate_select.sh"
# shellcheck source=/dev/null # present only in a repository that uses gate selection
if [ -r "$SELECT_LIB" ] && source "$SELECT_LIB" 2> /dev/null; then
  ci_gate_select_init "${CI_GATE_EVENT:-}" "${CI_GATE_BASE:-}"
  SELECT_NOTE="$CI_SELECT_NOTE"
else
  ci_gate_select() { echo "run: [selector_unreadable] full run (the CI gate selection library ${SELECT_LIB} cannot be read)"; }
  if [ -e "$SELECT_LIB" ] || [ -n "${CI_GATE_EVENT:-}" ]; then
    SELECT_NOTE="the CI gate selection library ${SELECT_LIB} cannot be read, so every gate runs"
  fi
fi
if [ -n "$SELECT_NOTE" ]; then
  echo "Gate selection: ${SELECT_NOTE}"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    if ! printf '**Gate selection (%s):** %s\n\n' "$PHASE" "$SELECT_NOTE" >> "$GITHUB_STEP_SUMMARY"; then
      echo "❌ FAIL: could not append the gate selection to the step summary ${GITHUB_STEP_SUMMARY}" >&2
      exit 1
    fi
  fi
fi

# record <label> <rc> <output> [<mark>]: the row and the details file for one
# gate. A mark is given only for a gate the selector skipped.
record() {
  local label="$1" rc="$2" out="$3" mark="${4:-}" slug
  if [ -n "$mark" ]; then
    :
  elif [ "$rc" -eq 0 ]; then mark="✅"; else mark="❌"; fi
  printf '%s|%s\n' "$label" "$mark" >> "$ROWS"
  slug="$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')"
  {
    echo ""
    echo "#### ${mark} ${label}"
    echo ""
    if [ -n "$out" ]; then
      echo '```'
      echo "$out"
      echo '```'
    else
      echo "_no output_"
    fi
  } > "${DETAILS}/${slug}.md"
}

if ! tree_before="$(git status --porcelain 2>&1)"; then
  echo "❌ FAIL: git status failed in ${ROOT} — without it a gate that changes the tree cannot be told apart from one that does not: ${tree_before}" >&2
  exit 1
fi

# kill_descendants <pid>: SIGTERM to every process below <pid>, deepest first.
kill_descendants() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do
    kill_descendants "$child"
    kill -TERM "$child" 2>/dev/null || true
  done
}

# cancelled <exit code>: the runner's cancel. Stop the gate and what it
# started, write nothing more, exit. (The gate's capture file is already
# unlinked, forsgren#614, so there is nothing to remove.)
cancelled() {
  trap '' TERM INT
  kill_descendants "$$"
  echo "::warning::CI ${PHASE} cancelled; its gate was stopped and no more rows were written" >&2
  exit "$1"
}
trap 'cancelled 143' TERM
trap 'cancelled 130' INT

ran=0
not_run=0
failed=0
secret_failed=0
failed_labels=""

while IFS='|' read -r label script phase gate_class || [ -n "${label:-}${script:-}" ]; do
  case "$label" in
    \#*) continue ;;
    '') [ -z "${script:-}${phase:-}${gate_class:-}" ] && continue ;;
  esac
  [ "${script:-}" = "n/a" ] && continue

  # Validate the row before the phase filter: a row that fits no phase must be
  # red, not invisible.
  bad=""
  if [ -z "${label:-}" ]; then
    label="(row with no label)"
    bad="the row has no label"
  elif [ -z "${script:-}" ]; then
    bad="the row names no script"
  else
    case "$script" in
      Scripts/*.sh) ;;
      *) bad="its script ${script} is not a Scripts/<name>.sh path" ;;
    esac
    case "$script" in
      *..*|*[!A-Za-z0-9_./-]*) bad="its script ${script} is not a plain Scripts/<name>.sh path" ;;
    esac
  fi
  if [ -z "$bad" ]; then
    case "${phase:-}" in
      pre|post) ;;
      *) bad="its phase '${phase:-}' is neither pre nor post, so no phase would ever run it" ;;
    esac
    case "${gate_class:-}" in
      ''|empty|secret-class) ;;
      *) bad="its class '${gate_class:-}' is neither empty nor secret-class" ;;
    esac
  fi
  if [ -z "$bad" ]; then
    [ "$phase" = "$PHASE" ] || continue
    in_job "$label" || continue
  fi

  ran=$((ran + 1))
  # The group row's arguments: the safe set, then words by read -r -a.
  args=""
  bad_args=""
  gate_args=()
  shown="$label"
  if [ -z "$bad" ]; then
    args="$(job_args "$label")"
    case "$args" in
      *[!A-Za-z0-9_./=\ -]*) bad_args="its arguments '${args}' in ${JOB_GROUPS} hold a character other than letters, digits, _ . / = - and spaces" ;;
      *) [ -z "$args" ] || read -r -a gate_args <<< "$args" ;;
    esac
    words="${gate_args[*]:-}"
    if [ -z "$bad_args" ] && [ -n "$words" ]; then
      shown="${label} ($(printf '%s' "$words" | sed 's/^-*//'))"
    fi
  fi
  echo "::group::${shown}"
  skip_mark=""

  if [ -n "$bad" ]; then
    out="❌ ${label} is a malformed row of ${ORDER}: ${bad}"
    rc=1
  elif [ -n "$bad_args" ]; then
    out="❌ ${label} is not run in job ${JOB}: ${bad_args}"
    rc=1
  elif [ ! -e "$script" ]; then
    out="❌ ${shown} declares ${script}, which does not exist"
    rc=1
  elif [ ! -x "$script" ]; then
    out="❌ ${shown} declares ${script}, which is not an executable script"
    rc=1
  elif selected="$(ci_gate_select "$label")" && [[ "$selected" == skip:* ]]; then
    reason="$(printf '%s' "${selected#skip: }" | tr '|\r\n' '   ')"
    skip_mark="⏭ not run (selector: ${reason})"
    out="${skip_mark}"$'\n'"${shown} was not run: that is not a pass, this run did not measure it."
    rc=0
    not_run=$((not_run + 1))
  else
    # forsgren#614: the gate writes through fd 3 and the loop reads through
    # fd 4 (its own offset) of a file unlinked at once, so the name exists for
    # an instant and no exit path, SIGKILL included, can leave it in TMPDIR.
    capture_path="$(tmp_file run_ci_phase_capture)" || { echo "❌ FAIL: run_ci_phase.sh: cannot make a temp file under ${TMPDIR:-/tmp}" >&2; exit 1; }
    # shellcheck disable=SC2094 # one file, opened twice on purpose: fd 3 writes, fd 4 reads
    exec 3>"$capture_path" 4<"$capture_path"
    rm -f "$capture_path"
    "./${script}" ${gate_args[@]+"${gate_args[@]}"} < /dev/null >&3 2>&1 &
    wait "$!" && rc=0 || rc=$?
    out="$(cat <&4)"
    exec 3>&- 4<&-

    if ! tree_after="$(git status --porcelain 2>&1)"; then
      out="${out}"$'\n'"❌ FAIL: git status failed after ${shown}: ${tree_after}"
      rc=1
    elif [ "$tree_after" != "$tree_before" ]; then
      out="${out}"$'\n'"❌ FAIL: ${shown} changed the checked-out tree — CI is check-only and reports what the commit contains, not what a gate could fix it into. Run the repository's FBP locally and commit the result. git status --porcelain after it:"$'\n'"${tree_after}"
      [ "$rc" -ne 0 ] || rc=1
      tree_before="$tree_after"
    fi
  fi

  echo "$out"
  echo "::endgroup::"
  record "$shown" "$rc" "$out" "$skip_mark"

  if [ "$rc" -ne 0 ]; then
    failed=$((failed + 1))
    failed_labels="${failed_labels}  ${shown} ❌"$'\n'
    echo "::error title=${shown}::${shown} failed (exit ${rc}); its output is in the step summary"
    if [ "${gate_class:-}" = "secret-class" ]; then
      secret_failed=1
    fi
  fi
done < "$ORDER"

if [ "$ran" -eq 0 ]; then
  echo "❌ FAIL: ${ORDER} declares no ${PHASE} row${JOB:+ that ${JOB_GROUPS} gives to job ${JOB}} — a CI phase that ran nothing is not green" >&2
  exit 1
fi

if [ "$failed" -ne 0 ]; then
  echo ""
  echo "Errors:"
  printf '%s' "$failed_labels"
  if [ "$secret_failed" -ne 0 ]; then
    echo "⛔ CI ${PHASE}: ${failed} of ${ran} gates failed, one of them SECRET-CLASS — exit 2"
    exit 2
  fi
  echo "❌ CI ${PHASE}: ${failed} of ${ran} gates failed"
  exit 1
fi

echo ""
if [ "$not_run" -ne 0 ]; then
  echo "✅ CI ${PHASE}${JOB:+ (${JOB})}: $((ran - not_run)) of ${ran} gates passed, none red; ⏭ ${not_run} not run (selector), not passed"
else
  echo "✅ CI ${PHASE}${JOB:+ (${JOB})}: all ${ran} gates passed"
fi
