#!/usr/bin/env bash
# canon: run_ci_phase v2
# v2 (forsgren#426): a group row may carry arguments, so one gate runs as shards in several jobs.
# Scripts/run_ci_phase.sh <pre|post> <rows-file> <details-dir> [job]
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
#     red row in whichever phase runs, named, never skipped: a typo in the
#     phase field would otherwise drop the gate from BOTH phases unseen;
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
# JOBS (forsgren#259, decision #260). Quality runs its slowest gates in
# parallel jobs of one workflow. The optional fourth argument names the job
# (default main); Scripts/ci_job_groups.txt lists `<job>|<label>` for the gates
# that belong to a job other than main, and every gate it does not list is
# main's, so a gate runs in exactly one job and a new gate is never in none.
# A group file that names a label the order file does not have is red in every
# job, and a job the group file does not name is a usage error (64). A
# malformed row is red in the main job only.
#
# SHARDS (forsgren#426). A group row may carry a third field, the arguments the
# job runs the gate with: `<job>|<label>|--shard 1/2`. Several jobs may name the
# same label, each with its own arguments; the gate then runs in each of those
# jobs and in no other, with the arguments as separate words, and the row it
# records is named for them, `<label> (shard 1/2)` (the arguments without their
# leading dashes), so a red names its shard and the report job can join the
# shards of one gate (Scripts/merge_quality_report.sh). A row with no third
# field is the plain `<job>|<label>` it always was.
#
# Exit: 0 all rows of the phase passed; 1 a row failed, or the phase has no
# row at all (a phase that ran nothing is not green); 2 a secret-class row
# failed; 64 bad usage.
#
# Testing seam: RUN_CI_PHASE_ROOT replaces the repository root, so
# Scripts/test_run_ci_phase.sh can run the loop over a synthetic order file
# and stub gates.

set -uo pipefail

ROOT="${RUN_CI_PHASE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

ORDER="Scripts/gate_report_order.txt"

JOB_GROUPS="Scripts/ci_job_groups.txt"

usage() {
  echo "usage: run_ci_phase.sh <pre|post> <rows-file> <details-dir> [job]" >&2
  exit 64
}

[ "$#" -eq 3 ] || [ "$#" -eq 4 ] || usage
PHASE="$1"
ROWS="$2"
DETAILS="$3"
JOB="${4:-main}"
case "$PHASE" in
  pre|post) ;;
  *) usage ;;
esac

if [ ! -f "$ORDER" ]; then
  echo "❌ FAIL: ${ORDER} is missing — every gate is declared there, so without it no gate runs" >&2
  exit 1
fi

# in_job <label>: succeeds when the gate runs in this job. The main job runs
# every gate the group file does not list; another job runs the gates it lists.
in_job() {
  if [ "$JOB" = "main" ]; then
    [ ! -f "$JOB_GROUPS" ] || ! awk -F'|' -v l="$1" '$0 !~ /^#/ && $2 == l { f = 1 } END { exit !f }' "$JOB_GROUPS"
  else
    [ -f "$JOB_GROUPS" ] && awk -F'|' -v j="$JOB" -v l="$1" '$0 !~ /^#/ && $1 == j && $2 == l { f = 1 } END { exit !f }' "$JOB_GROUPS"
  fi
}

# job_args <label>: the arguments this job runs the gate with (the group row's
# third field), empty for the main job and for a row without one.
job_args() {
  [ "$JOB" != "main" ] && [ -f "$JOB_GROUPS" ] || return 0
  awk -F'|' -v j="$JOB" -v l="$1" '$0 !~ /^#/ && $1 == j && $2 == l { print $3; exit }' "$JOB_GROUPS"
}

# The job must exist, and every gate the group file names must be a row of
# the order file: a typo there would take the gate out of every job unseen.
if [ "$JOB" != "main" ]; then
  if [ ! -f "$JOB_GROUPS" ] || ! awk -F'|' -v j="$JOB" '$0 !~ /^#/ && $1 == j { f = 1 } END { exit !f }' "$JOB_GROUPS"; then
    echo "❌ FAIL: the job '${JOB}' has no gate in ${JOB_GROUPS}" >&2
    usage
  fi
fi
if [ -f "$JOB_GROUPS" ]; then
  while IFS='|' read -r group_job group_label _group_args || [ -n "${group_job:-}${group_label:-}" ]; do
    case "$group_job" in \#*|'') continue ;; esac
    if [ -z "${group_label:-}" ] || ! awk -F'|' -v l="$group_label" '$0 !~ /^#/ && $1 == l && $2 != "" { f = 1 } END { exit !f }' "$ORDER"; then
      echo "❌ FAIL: ${JOB_GROUPS} names the gate '${group_label:-}' for the job ${group_job}, which is no row of ${ORDER} — the gate would run in no job" >&2
      exit 1
    fi
  done < "$JOB_GROUPS"
fi

mkdir -p "$DETAILS" || exit 1
touch "$ROWS" || exit 1

# record <label> <rc> <output>: the row and the details file for one gate.
record() {
  local label="$1" rc="$2" out="$3" mark slug
  if [ "$rc" -eq 0 ]; then mark="✅"; else mark="❌"; fi
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

JOB_NOTE=""
[ "$JOB" = "main" ] || JOB_NOTE=" for the job ${JOB}"
ran=0
failed=0
secret_failed=0
failed_labels=""
args=""

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
  else
    [ "$JOB" = "main" ] || continue
  fi

  ran=$((ran + 1))
  args="$(job_args "$label")"
  if [ -n "$args" ]; then
    label="${label} ($(printf '%s' "$args" | sed 's/^-*//'))"
  fi
  echo "::group::${label}"

  if [ -n "$bad" ]; then
    out="❌ ${label} is a malformed row of ${ORDER}: ${bad}"
    rc=1
  elif [ ! -e "$script" ]; then
    out="❌ ${label} declares ${script}, which does not exist"
    rc=1
  elif [ ! -x "$script" ]; then
    out="❌ ${label} declares ${script}, which is not an executable script"
    rc=1
  else
    # shellcheck disable=SC2086 # the group row's arguments are words on purpose
    out="$("./${script}" $args < /dev/null 2>&1)" && rc=0 || rc=$?

    if ! tree_after="$(git status --porcelain 2>&1)"; then
      out="${out}"$'\n'"❌ FAIL: git status failed after ${label}: ${tree_after}"
      rc=1
    elif [ "$tree_after" != "$tree_before" ]; then
      out="${out}"$'\n'"❌ FAIL: ${label} changed the checked-out tree — CI is check-only and reports what the commit contains, not what a gate could fix it into. Run the repository's FBP locally and commit the result. git status --porcelain after it:"$'\n'"${tree_after}"
      [ "$rc" -ne 0 ] || rc=1
      tree_before="$tree_after"
    fi
  fi

  echo "$out"
  echo "::endgroup::"
  record "$label" "$rc" "$out"

  if [ "$rc" -ne 0 ]; then
    failed=$((failed + 1))
    failed_labels="${failed_labels}  ${label} ❌"$'\n'
    echo "::error title=${label}::${label} failed (exit ${rc}); its output is in the step summary"
    if [ "${gate_class:-}" = "secret-class" ]; then
      secret_failed=1
    fi
  fi
done < "$ORDER"

if [ "$ran" -eq 0 ]; then
  echo "❌ FAIL: ${ORDER} declares no ${PHASE} row${JOB_NOTE} — a CI phase that ran nothing is not green" >&2
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
echo "✅ CI ${PHASE}: all ${ran} gates passed"
