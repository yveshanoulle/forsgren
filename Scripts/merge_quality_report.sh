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
#       SHARDS (forsgren#426): a gate that Scripts/ci_job_groups.txt splits over
#       jobs is reported by each of them as `<gate> (shard N/M)`
#       (Scripts/run_ci_phase.sh). The merge joins those rows into ONE row
#       under the gate's own label, the label the order file declares and the
#       renderers look up: green only when all M shards reported green, red
#       when one is red (the output names it: `<gate>: shard 2/2 failed`) or
#       reported no row at all (`<gate>: shard 2/2 reported no row`, so a job
#       that died early can never leave the gate green). The gate's details
#       file holds the details of every shard, each under its own heading.
#   Scripts/merge_quality_report.sh status <result>...
#       The run's status from the jobs' results (needs.<job>.result): prints
#       cancelled when any job was cancelled, else failure when any job is not
#       success (a skipped job included: it never judged its gates), else
#       success. It is the QS_JOB_STATUS of the run summary.
#   Scripts/merge_quality_report.sh verdict <job>=<result>...
#       (forsgren#561) Whether the report job itself is red: a ❌ line `<job>:
#       <result>` for every job whose result is not success (failure,
#       cancelled or skipped: no gate job is skipped by design, and a skipped
#       one never judged its gates), exit 1; all success prints nothing, exit
#       0. The report job runs it after the report is rendered, so the check
#       named Quality report is never green while a gate job is not.
#
# Exit: 0, 1 a gate reported twice or a gate job not success, 64 usage. Self-test:
# Scripts/test_merge_quality_report.sh.

set -uo pipefail

usage() {
  echo "usage: merge_quality_report.sh handover <rows> <details-dir> <out-dir> [page-count-file] | merge <artifacts-dir> <rows-out> <details-out> | status <result>... | verdict <job>=<result>..." >&2
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

# verdict <job>=<result>...: a ❌ line per job that is not success, exit 1.
verdict() {
  local arg name result failed=0
  [ "$#" -ge 1 ] || usage
  for arg in "$@"; do
    case "$arg" in *=*) ;; *) usage ;; esac
    name="${arg%%=*}"
    result="${arg#*=}"
    [ -n "$name" ] || usage
    case "$result" in
      success) ;;
      *) printf '❌ %s: %s\n' "$name" "${result:-no result}"; failed=1 ;;
    esac
  done
  return "$failed"
}

# shard_slug <label>: the details file name of a row (the runner's slug rule).
shard_slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }

# shard_state <info> <gate> <n>: ok, red or none for shard n of the gate.
shard_state() {
  printf '%s' "$1" | LC_ALL=C awk -F'|' -v b="$2" -v n="$3" '$1 == b && $2 == n { s = ($4 == "✅" ? "ok" : "red"); exit } END { print (s == "" ? "none" : s) }'
}

# join_shard <info> <gate> <details-dir>: sets JOINED_MARK to the one gate's mark
# (the red and missing shards are named on stdout) and writes its details file.
join_shard() {
  local info="$1" base="$2" details="$3" m i label f state mark="✅" out
  m="$(printf '%s' "$info" | awk -F'|' -v b="$base" '$1 == b { print $3; exit }')"
  out="${details}/$(shard_slug "$base").md"
  : > "$out"
  for ((i = 1; i <= m; i++)); do
    label="${base} (shard ${i}/${m})"
    f="${details}/$(shard_slug "$label").md"
    state="$(shard_state "$info" "$base" "$i")"
    [ "$state" = "ok" ] || mark="❌"
    case "$state" in
      red) echo "❌ ${base}: shard ${i}/${m} failed" ;;
      none) echo "❌ ${base}: shard ${i}/${m} reported no row" ;;
    esac
    if [ -f "$f" ]; then
      cat "$f" >> "$out"
      rm -f "$f"
    else
      printf '\n#### ❌ %s\n\n_reported no row_\n' "$label" >> "$out"
    fi
  done
  JOINED_MARK="$mark"
}

# join_shards <rows-file> <details-dir>: rewrites the rows file with the rows
# of one gate's shards joined into one row (see SHARDS above), at the place of
# the gate's first shard row, and writes the gate's details file.
join_shards() {
  local rows_out="$1" details="$2" re row label base line bases=$'\n' info="" out=""
  re='^(.*) \(shard ([0-9]+)/([0-9]+)\)$'
  while IFS= read -r row || [ -n "$row" ]; do
    label="${row%%|*}"
    if [[ "$label" =~ $re ]]; then
      base="${BASH_REMATCH[1]}"
      info="${info}${base}|${BASH_REMATCH[2]}|${BASH_REMATCH[3]}|${row#*|}"$'\n'
      case "$bases" in
        *$'\n'"${base}"$'\n'*) ;;
        *)
          bases="${bases}${base}"$'\n'
          out="${out}@@${base}"$'\n'
          ;;
      esac
    else
      out="${out}${row}"$'\n'
    fi
  done < "$rows_out"
  : > "$rows_out"
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    if [ "${line#@@}" = "$line" ]; then
      printf '%s\n' "$line" >> "$rows_out"
      continue
    fi
    base="${line#@@}"
    join_shard "$info" "$base" "$details"
    printf "%s|%s\n" "$base" "$JOINED_MARK" >> "$rows_out"
  done <<< "$out"
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
  join_shards "$rows_out" "$details_out"
  gates="$(grep -c . "$rows_out" || true)"
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
  verdict)
    shift
    verdict "$@"
    ;;
  *) usage ;;
esac
