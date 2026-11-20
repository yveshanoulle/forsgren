#!/usr/bin/env bash
# Scripts/selftest_rows.sh (forsgren#686, step 2)
#
# The rows a local sfl run skips by default: the runnable rows of the order file
# that run only in jobs of the self-tests' workflow. It decides nothing itself.
# forsgren#686 step 1 split the rows between two workflows through
# Scripts/ci_job_groups.txt (which job runs which row; a row it does not list
# runs in Quality's main job) and the workflows (a job belongs to the workflow
# whose step runs `./Scripts/run_ci_phase.sh <phase> "$ROWS" "$DETAILS" <job>`);
# pin 8 of Scripts/test_gate_wiring.sh holds that split to the kind of each row.
# This script reads the same files, so the rows CI runs in
# .github/workflows/selftests.yml after the push and the rows sfl leaves out are
# one set, kept in one place.
#
#   Scripts/selftest_rows.sh [<order-file> <groups-file> <selftests-workflow>]
#
# Defaults: Scripts/gate_report_order.txt, Scripts/ci_job_groups.txt,
# .github/workflows/selftests.yml. Prints one label per line, in the order
# file's order: every row whose script is not `n/a` and whose every row of the
# groups file names a job of the workflow (at least one). A row in no job (so
# in Quality's main job), or in a job of the other workflow, is not printed:
# sfl runs it.
#
# Exit 0, or 1 with the reason on stderr: a missing file, or a workflow that
# runs no job through Scripts/run_ci_phase.sh (an empty list would make sfl run
# every self-test again without a word). 64: usage.
# Self-test: Scripts/test_sfl_selftest_skip.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

if [ "$#" -ne 0 ] && [ "$#" -ne 3 ]; then
  echo "usage: selftest_rows.sh [<order-file> <groups-file> <selftests-workflow>]" >&2
  exit 64
fi
ORDER="${1:-Scripts/gate_report_order.txt}"
GROUPS_FILE="${2:-Scripts/ci_job_groups.txt}"
WORKFLOW="${3:-.github/workflows/selftests.yml}"

for f in "$ORDER" "$GROUPS_FILE" "$WORKFLOW"; do
  if [ ! -f "$f" ]; then
    echo "selftest_rows: ${f} is missing, so the self-test rows are unknown" >&2
    exit 1
  fi
done

# The jobs the workflow runs, the same reading as pin 8's phase_jobs.
JOBS="$(grep -vE '^[[:space:]]*#' "$WORKFLOW" \
  | sed -nE 's#^[[:space:]]*\./Scripts/run_ci_phase\.sh (pre|post) "[$]ROWS" "[$]DETAILS" ([A-Za-z0-9_-]+)[[:space:]]*$#\2#p' \
  | sort -u | tr '\n' ' ')"
if [ -z "$JOBS" ]; then
  echo "selftest_rows: ${WORKFLOW} runs no job through the CI phase runner, so the self-test rows are unknown" >&2
  exit 1
fi

awk -F'|' -v jobs="$JOBS" '
  BEGIN { n = split(jobs, a, " "); for (i = 1; i <= n; i++) st[a[i]] = 1 }
  /^#/ || !NF { next }
  FILENAME == ARGV[1] {
    if ($1 in st) inst[$2] = 1; else other[$2] = 1
    next
  }
  $2 == "" || $2 == "n/a" { next }
  ($1 in inst) && !($1 in other) { print $1 }
' "$GROUPS_FILE" "$ORDER"
