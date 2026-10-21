#!/usr/bin/env bash
# Scripts/merge_quality_report.sh
#
# forsgren's own (forsgren#259, decision #260). Quality runs its gates in
# parallel jobs of one workflow; each job hands over what Scripts/run_ci_phase.sh
# wrote, as one artifact `quality-report-<job>` holding `rows.md` and a
# `details/` directory. The report job downloads them all into one directory
# (one subdirectory per artifact) and merges them here into the ONE rows file and
# details directory that Scripts/render_quality_summary.sh and
# Scripts/render_quality_report.sh read, so the run has one Quality report.
#
#   Scripts/merge_quality_report.sh handover <rows> <details-dir> <out-dir> [page-count-file]
#       What a job hands over (the directory its upload step sends): rows.md,
#       details/ and, when the job built the site, page-count.log. Any of the
#       inputs may be missing or empty (a job that stopped before its gates
#       ran): out-dir then holds an empty rows.md, so the report job names the
#       job as having handed over no rows, and the upload is never empty.
#   Scripts/merge_quality_report.sh merge <artifacts-dir> <rows-out> <details-out>
#       Appends every job's rows.md to <rows-out> and copies every job's
#       details files into <details-out>. A gate reported by two jobs is red
#       (exit 1, both jobs named): a gate runs in one job only, which
#       Scripts/ci_job_groups.txt and run_ci_phase.sh guarantee, so two rows
#       mean the split broke. A job that handed over no rows is named and the
#       merge goes on: its gates then show as unmeasured in the report, never
#       as passing.
#   Scripts/merge_quality_report.sh status <result>...
#       The run's status from the jobs' results (needs.<job>.result): prints
#       cancelled when any job was cancelled, else failure when any job is not
#       success (a skipped job included: it never judged its gates), else
#       success. It is the QS_JOB_STATUS of the run summary.
#
# Exit: 0, 1 a gate reported twice, 64 usage. Self-test:
# Scripts/test_merge_quality_report.sh.

set -uo pipefail

usage() {
  echo "usage: merge_quality_report.sh handover <rows> <details-dir> <out-dir> [page-count-file] | merge <artifacts-dir> <rows-out> <details-out> | status <result>..." >&2
  exit 64
}

status() {
  local result any_failed=0 any_cancelled=0
  [ "$#" -ge 1 ] || usage
  for result in "$@"; do
    [ -n "$result" ] || usage
    case "$result" in
      success) ;;
      cancelled) any_cancelled=1 ;;
      *) any_failed=1 ;;
    esac
  done
  if [ "$any_cancelled" -eq 1 ]; then
    echo cancelled
  elif [ "$any_failed" -eq 1 ]; then
    echo failure
  else
    echo success
  fi
}

merge() {
  local art="$1" rows_out="$2" details_out="$3" dir job row label prev seen=$'\n' gates=0 jobs=0 duplicates=0
  [ -d "$art" ] || usage
  mkdir -p "$details_out" || exit 1
  : > "$rows_out" || exit 1
  for dir in "$art"/*/; do
    [ -d "$dir" ] || continue
    job="$(basename "$dir")"
    jobs=$((jobs + 1))
    if [ ! -s "${dir}rows.md" ]; then
      echo "${job} handed over no rows: its gates are unmeasured, not passing"
    else
      while IFS= read -r row || [ -n "$row" ]; do
        [ -n "$row" ] || continue
        label="${row%%|*}"
        prev="$(printf '%s' "$seen" | awk -F'|' -v l="$label" '$1 == l { print $2; exit }')"
        if [ -n "$prev" ]; then
          echo "❌ FAIL: the gate '${label}' was reported by both ${prev} and ${job}: a gate runs in one job only"
          duplicates=1
        fi
        seen="${seen}${label}|${job}"$'\n'
        printf '%s\n' "$row" >> "$rows_out"
        gates=$((gates + 1))
      done < "${dir}rows.md"
    fi
    if [ -d "${dir}details" ]; then
      cp "${dir}details/"* "$details_out"/ 2> /dev/null || true
    fi
  done
  echo "merged ${gates} gates from ${jobs} jobs"
  [ "$duplicates" -eq 0 ] || exit 1
}

handover() {
  local rows="$1" details="$2" out="$3" count="${4:-}"
  rm -rf "$out" || exit 1
  mkdir -p "${out}/details" || exit 1
  : > "${out}/rows.md"
  if [ -n "$rows" ] && [ -f "$rows" ]; then cp "$rows" "${out}/rows.md" || exit 1; fi
  if [ -n "$details" ] && [ -d "$details" ]; then cp "$details"/* "${out}/details/" 2> /dev/null || true; fi
  if [ -n "$count" ] && [ -f "$count" ]; then cp "$count" "${out}/page-count.log" || exit 1; fi
  echo "handed over $(grep -c '|' "${out}/rows.md" || true) rows to ${out}"
}

case "${1:-}" in
  handover)
    [ "$#" -eq 4 ] || [ "$#" -eq 5 ] || usage
    handover "$2" "$3" "$4" "${5:-}"
    ;;
  merge)
    [ "$#" -eq 4 ] || usage
    merge "$2" "$3" "$4"
    ;;
  status)
    shift
    status "$@"
    ;;
  *) usage ;;
esac
