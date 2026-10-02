#!/usr/bin/env bash
# Scripts/render_quality_summary.sh
#
# forsgren#8, forsgren's own: the run's key numbers at the top of every
# Quality run page, the numbers otherwise read in the logs. quality.yml's
# last step (`if: always()`, so also after a failure or a cancel) runs it
# first and Scripts/render_quality_report.sh after it, both appending to
# $GITHUB_STEP_SUMMARY, so this block sits above the gate table.
#
# It runs nothing and measures nothing itself: it reads what the run
# already wrote.
#   - the rows file and details directory of Scripts/run_ci_phase.sh: one
#     `<label>|✅` or `<label>|❌` row per gate that ran, one
#     `<slug>.md` per gate with its output. Each row's phase comes from the
#     order file, so the counts are per phase; an `n/a` row counts in
#     neither.
#   - in them, the outputs of the Go tests gate (its `OK: go test ./... —
#     N tests passed` line, or its `--- PASS:`/`--- FAIL:` lines when red)
#     and the Go coverage gate (its `total:` line and its FLOORWARN line,
#     Scripts/check_coverage.sh).
#   - Scripts/build_site.sh's page-count sink, SITE_PAGE_COUNT_FILE (default
#     .build/site-page-count.log), written only by a build that succeeded.
#   - the version in cmd/forsgren/main.go (QS_MAIN_GO moves it, for the
#     fixture), the one source of the version.
#   - env, from quality.yml, never from `${{ }}` inside run:
#       QS_JOB_STATUS   job.status: success, failure or cancelled
#       QS_PRE_OUTCOME, QS_BUILD_OUTCOME, QS_POST_OUTCOME
#                       the outcome of each phase's step: success, failure,
#                       cancelled, skipped, or empty when never reached
#       QS_SECRET_BLOCK true when PRE had a secret-class finding
#       QS_PR_NUMBER    the pull request's number, on a pull_request run
#       QS_STARTED_AT   epoch seconds, written by the job's first shell step
#       QS_NOW          epoch seconds for "now" (the fixture's seam; default
#                       the clock)
#       GITHUB_SHA, GITHUB_EVENT_NAME, GITHUB_REF_NAME, GitHub's own
#
# A NUMBER THAT DOES NOT EXIST IS NEVER 0. A phase that never ran, an output
# that is missing, a sink the build never wrote: each shows `— (<reason>)`.
# A 0 reads as measured, and a run that measured nothing would look clean.
# Gates of a phase that ran but never reported (the run was cancelled
# mid-phase) are counted as skipped, never as passed.
#
# TOTAL CHECKS, directly under Go tests, is the highest honest number: every
# individual check that ran, counted once. Per gate that reported, its case
# lines (read with the one case-line grammar below), each Go test once (the
# Go tests gate's `--- PASS:`/`--- FAIL:` lines, never the gate too), and a
# gate with no case line counts as one check, itself. A closing verdict is
# never a case. A phase with no gate that reported makes the cell `—`,
# naming that phase, never a partial sum that reads as complete; a gate of
# a phase that ran but never reported is named as skipped; a gate whose
# case lines are in a format the grammar does not know is named, not
# counted silently.
#
# Usage: Scripts/render_quality_summary.sh <rows-file> <details-dir> [order-file]
#   Either path may be empty or missing (the job stopped before quality.yml's
#   Start report step); the block still renders.
#
# Writes Markdown to stdout and exits 0 on whatever it is given, as the
# report renderer does: a summary that fails turns a run's page red for a
# reason unrelated to what it reports. `set -uo pipefail` and not -e for
# that reason.
# Fixture: Scripts/test_render_quality_summary.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

if [ "$#" -lt 2 ]; then
  echo "usage: render_quality_summary.sh <rows-file> <details-dir> [order-file]" >&2
  exit 64
fi

ROWS="$1"
DETAILS="$2"
ORDER="${3:-Scripts/gate_report_order.txt}"
MAIN_GO="${QS_MAIN_GO:-cmd/forsgren/main.go}"
PAGE_SINK="${SITE_PAGE_COUNT_FILE:-.build/site-page-count.log}"

JOB_STATUS="${QS_JOB_STATUS:-}"
PRE_OUTCOME="${QS_PRE_OUTCOME:-}"
BUILD_OUTCOME="${QS_BUILD_OUTCOME:-}"
POST_OUTCOME="${QS_POST_OUTCOME:-}"

# missing <reason>: the cell of a number that does not exist. THE one place
# that writes it, so no cell can fall back to a bare 0 (the mutation proof
# of the fixture replaces exactly this line).
missing() {
  printf '— (%s)' "$1"
}

# ran <outcome>: the step was reached (it succeeded, failed or was
# cancelled while running); skipped or empty means it never ran.
ran() {
  case "$1" in
    success|failure|cancelled) return 0 ;;
    *) return 1 ;;
  esac
}

# details_of <label>: the path of a gate's details file, slugged as
# run_ci_phase.sh slugs it.
details_of() {
  printf '%s/%s.md' "$DETAILS" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"
}

# --- status: how far the run got --------------------------------------------
furthest="setup, before the PRE gates"
ran "$PRE_OUTCOME" && furthest="PRE"
ran "$BUILD_OUTCOME" && furthest="the build"
ran "$POST_OUTCOME" && furthest="POST"

red=""
[ "$PRE_OUTCOME" = "failure" ] && red="${red:+${red}, }PRE"
[ "$BUILD_OUTCOME" = "failure" ] && red="${red:+${red}, }the build"
[ "$POST_OUTCOME" = "failure" ] && red="${red:+${red}, }POST"

case "$JOB_STATUS" in
  success)
    status="**✅ Succeeded** — PRE, build and POST all ran." ;;
  cancelled)
    status="**⏹️ Cancelled** — stopped in ${furthest}." ;;
  failure)
    if [ "$furthest" = "POST" ]; then
      status="**❌ Failed** — every phase ran; red in: ${red:-no phase step}."
    else
      status="**❌ Failed** — stopped in ${furthest}${red:+; red in: ${red}}."
    fi ;;
  *)
    status="**❔ Status unknown** — QS_JOB_STATUS is ${JOB_STATUS:-not set}." ;;
esac

# --- gates per phase ----------------------------------------------------------

# not_run_reason <phase>: why a phase recorded no gate.
not_run_reason() {
  if [ "$1" = "pre" ]; then
    if ran "$PRE_OUTCOME"; then echo "PRE ran but recorded no gate"
    elif [ "$JOB_STATUS" = "cancelled" ]; then echo "not run: the run was cancelled"
    else echo "not run: the job stopped in setup, before the gates"
    fi
    return
  fi
  if ran "$POST_OUTCOME"; then echo "POST ran but recorded no gate"
  elif [ "$JOB_STATUS" = "cancelled" ]; then echo "not run: the run was cancelled"
  elif [ "${QS_SECRET_BLOCK:-}" = "true" ]; then echo "not run: a secret-class finding in PRE skips the build and POST"
  elif [ "$BUILD_OUTCOME" = "failure" ]; then echo "not run: the build failed"
  elif ! ran "$PRE_OUTCOME"; then echo "not run: the job stopped in setup, before the gates"
  else echo "not run: the build did not run"
  fi
}

# phase_counts <phase>: `P F S` (passed, failed, skipped), counted from
# the rows against the order file's declared rows of that phase; nothing
# when no gate of the phase reported.
phase_counts() {
  local counts
  # LC_ALL=C: macOS awk compares strings with strcoll, and in a UTF-8 locale
  # ✅ and ❌ collate EQUAL, so every red row counted as passed. Bytes, here.
  counts="$(LC_ALL=C awk -F'|' -v phase="$1" '
    FNR == NR {
      if ($0 ~ /^#/ || $1 == "" || $2 == "n/a") next
      if ($3 == phase) { declared++; in_phase[$1] = 1 }
      next
    }
    ($1 in in_phase) && !($1 in seen) {
      seen[$1] = 1
      if ($2 == "✅") passed++; else failed++
    }
    END { printf "%d %d %d\n", declared, passed, failed }
  ' "$ORDER" "${rows_file}")"
  local declared passed failed
  read -r declared passed failed <<< "$counts"
  [ "$((passed + failed))" -eq 0 ] && return
  printf '%d %d %d' "$passed" "$failed" "$((declared - passed - failed))"
}

# A missing rows file is read as an empty one.
rows_file="$ROWS"
if [ -z "$rows_file" ] || [ ! -f "$rows_file" ]; then rows_file=/dev/null; fi

pre_counts="$(phase_counts pre)"
post_counts="$(phase_counts post)"

# phase_cell <phase> <counts>: the phase's counts, or — with why it has none.
phase_cell() {
  local passed failed skipped
  if [ -z "$2" ]; then missing "$(not_run_reason "$1")"; return; fi
  read -r passed failed skipped <<< "$2"
  printf '%d passed · %d failed · %d skipped' "$passed" "$failed" "$skipped"
}

# --- Go tests -----------------------------------------------------------------
go_tests_cell() {
  local f n pass fail
  f="$(details_of "Go tests")"
  if [ -z "$DETAILS" ] || [ ! -f "$f" ]; then
    missing "the Go tests gate did not report"
    return
  fi
  n="$(sed -n 's/^OK: go test \.\/\.\.\. — \([0-9][0-9]*\) tests passed$/\1/p' "$f" | tail -1)"
  if [ -n "$n" ]; then
    printf '%s passed' "$n"
    return
  fi
  pass="$(grep -cE '^--- PASS: ' "$f")"
  fail="$(grep -cE '^--- FAIL: ' "$f")"
  if [ "$((pass + fail))" -eq 0 ]; then
    missing "the Go tests gate was red before any test reported; see its output below"
    return
  fi
  printf '❌ %d passed · %d failed' "$pass" "$fail"
}

# --- Total checks -------------------------------------------------------------
# THE CASE-LINE GRAMMAR: one line of a gate's output is, in this order,
#   skipped    the details file's own lines: `#### ` header, ``` fence,
#              `_no output_`
#   a verdict  never a case: `OK: <claim>` (one space), `PASS`/`FAIL` alone,
#              `FAIL: …` (no mark), `All N cases passed`, a mark at column 0
#              that is not `❌ FAIL:` (`✅ test_x`, `❌ check_x fixture
#              failed`), go test's `ok  <package>` line, and the `❌ FAIL:`
#              lines that close a run: lib_selftest's `(see the FAIL lines
#              above)` and `aborted before completing`, and the count lines
#              of check_coverage, check_file_length, test_build_site,
#              check_deadcode, check_go_lint, check_test_dupl
#   passed     `  ok: ` (lib_selftest, and its `  ok:   ... and` follow-ups),
#              `  ✅ ` (the ported fixtures; check_coverage's floors),
#              `OK:   ` (two or more spaces: the ported shellcheck, yamllint
#              and install-tools fixtures), `OK   ` (no colon:
#              validate_required_pages, check_lint_coverage), `[N/M] `
#              (test_sfl_pull's steps)
#   failed     `  ❌ ` (the ported fixtures), `❌ FAIL: ` (every other)
#   unknown    any other line that starts with a pass or fail mark (✅ ❌ ✓
#              ✔ ✗ ✘ ok OK PASS FAIL pass fail): a case-line format this
#              grammar does not know, named in the cell.
# LC_ALL=C, as for the rows: the marks are compared as bytes.
#
# case_counts <label>: `P F U` (passed, failed and unknown case lines) of one
# gate's output. The Go tests gate counts its tests, each once: its
# `--- PASS:`/`--- FAIL:` lines, or its OK line's count when it printed
# none.
case_counts() {
  local f n
  f="$(details_of "$1")"
  if [ -z "$DETAILS" ] || [ ! -f "$f" ]; then echo "0 0 0"; return; fi
  if [ "$1" != "Go tests" ]; then
    LC_ALL=C awk '
      function verdict(l) {
        if (l ~ /^OK: [^ ]/ || l ~ /^(PASS|FAIL)$/ || l ~ /^FAIL: /) return 1
        if (l ~ /^All [0-9]+ cases passed/ || l ~ /^ok[ \t]+[^ \t]+\t/) return 1
        if (l ~ /^(✅|❌) / && l !~ /^❌ FAIL: /) return 1
        if (l !~ /^❌ FAIL: /) return 0
        return l ~ /\(see the FAIL lines above\)$/ || l ~ /aborted before completing/ ||
          l ~ /[0-9]+ (coverage finding|Go production file|failure|unreachable function)\(s\)/ ||
          l ~ /issue\(s\) in / || l ~ /findings: [0-9]/
      }
      function passed(l) {
        return l ~ /^  ok: / || l ~ /^  ✅ / || l ~ /^OK:  +[^ ]/ || l ~ /^OK  +[^ ]/ ||
          l ~ /^\[[0-9]+\/[0-9]+\] /
      }
      function failed(l) {
        return l ~ /^  ❌ / || l ~ /^❌ FAIL: /
      }
      function marker(l) {
        return l ~ /^[ \t]*(✅|❌|✓|✔|✗|✘|ok[: ]|OK|PASS|FAIL|pass[: ]|fail[: ])/
      }
      /^#### / || /^```$/ || /^_no output_$/ { next }
      verdict($0) { next }
      passed($0) { p++; next }
      failed($0) { f++; next }
      marker($0) { u++ }
      END { printf "%d %d %d\n", p, f, u }
      ' "$f"
    return
  fi
  n="$(grep -cE '^--- (PASS|FAIL): ' "$f")"
  if [ "$n" -gt 0 ]; then
    echo "$(grep -cE '^--- PASS: ' "$f") $(grep -cE '^--- FAIL: ' "$f") 0"
    return
  fi
  n="$(sed -n 's/^OK: go test \.\/\.\.\. — \([0-9][0-9]*\) tests passed$/\1/p' "$f" | tail -1)"
  echo "${n:-0} 0 0"
}

# reported_rows: `<label>|<mark>`, once per declared gate that reported.
reported_rows() {
  LC_ALL=C awk -F'|' '
    FNR == NR {
      if ($0 ~ /^#/ || $1 == "" || $2 == "n/a") next
      declared[$1] = 1
      next
    }
    ($1 in declared) && !($1 in seen) { seen[$1] = 1; print $1 "|" $2 }
  ' "$ORDER" "$rows_file"
}

checks_passed=0
checks_failed=0
unknown_gates=0
unknown_labels=""
while IFS='|' read -r label mark; do
  [ -n "$label" ] || continue
  read -r cp cf cu <<< "$(case_counts "$label")"
  # A gate with no case line is one check, itself; a red gate with no
  # failed case line (red for a tree it changed, say) adds itself as failed.
  if [ "$((cp + cf))" -eq 0 ]; then
    if [ "$mark" = "✅" ]; then cp=1; else cf=1; fi
  elif [ "$mark" != "✅" ] && [ "$cf" -eq 0 ]; then
    cf=1
  fi
  if [ "$cu" -gt 0 ]; then
    unknown_gates=$((unknown_gates + 1))
    unknown_labels="${unknown_labels:+${unknown_labels}, }${label}"
  fi
  checks_passed=$((checks_passed + cp))
  checks_failed=$((checks_failed + cf))
done <<< "$(reported_rows)"

total_cell() {
  local absent="" ps qs skipped
  [ -n "$pre_counts" ] || absent="the PRE gates"
  [ -n "$post_counts" ] || absent="${absent:+${absent} and }the POST gates"
  [ -z "$absent" ] || { missing "no total: ${absent} have no count"; return; }
  printf '%d passed · %d failed' "$checks_passed" "$checks_failed"
  read -r _ _ ps <<< "$pre_counts"
  read -r _ _ qs <<< "$post_counts"
  skipped=$((ps + qs))
  if [ "$skipped" -eq 1 ]; then
    printf ' · 1 gate skipped, its checks not counted'
  elif [ "$skipped" -gt 1 ]; then
    printf ' · %d gates skipped, their checks not counted' "$skipped"
  fi
  if [ "$unknown_gates" -eq 1 ]; then
    printf ' · ⚠️ case lines in an unknown format in 1 gate (%s), not counted' "$unknown_labels"
  elif [ "$unknown_gates" -gt 1 ]; then
    printf ' · ⚠️ case lines in an unknown format in %d gates (%s), not counted' "$unknown_gates" "$unknown_labels"
  fi
}

# --- Go coverage and floors to raise ------------------------------------------
cov_file="$(details_of "Go coverage")"
cov_total=""
cov_reason=""
if [ -z "$DETAILS" ] || [ ! -f "$cov_file" ]; then
  cov_reason="the Go coverage gate did not report"
else
  # `  ✅ total: 63.2% (floor 63.1%)` when met; `❌ FAIL: total: 61.0% is
  # below its floor 63.1%` when not.
  cov_total="$(sed -n 's/^  ✅ total: \([0-9.]*%\) (floor \([0-9.]*%\))$/\1 (floor \2)/p' "$cov_file" | tail -1)"
  if [ -z "$cov_total" ]; then
    below="$(sed -n 's/^❌ FAIL: total: \([0-9.]*%\) is below its floor \([0-9.]*%\)$/❌ \1 (floor \2), below its floor/p' "$cov_file" | tail -1)"
    if [ -n "$below" ]; then
      cov_total="$below"
    else
      cov_reason="the Go coverage gate measured no total; see its output below"
    fi
  fi
fi

coverage_cell() {
  if [ -n "$cov_total" ]; then printf '%s' "$cov_total"; else missing "$cov_reason"; fi
}

# FLOORWARN is printed only when a floor should be raised, so a gate that
# measured a total and printed none counts 0, a real measurement.
floors_cell() {
  if [ -z "$cov_total" ]; then
    missing "$cov_reason"
    return
  fi
  local n
  n="$(sed -n 's/^FLOORWARN: \([0-9][0-9]*\) coverage floor(s) should be raised.*/\1/p' "$cov_file" | tail -1)"
  printf '%s' "${n:-0}"
}

# --- pages, version, commit, trigger, duration -------------------------------
pages_cell() {
  if [ -n "$BUILD_OUTCOME" ] && [ "$BUILD_OUTCOME" != "success" ]; then
    if [ "$BUILD_OUTCOME" = "failure" ]; then missing "the build failed"; else missing "the build did not run"; fi
    return
  fi
  if [ -z "$BUILD_OUTCOME" ] && [ -n "$JOB_STATUS" ]; then
    missing "the build did not run"
    return
  fi
  local n=""
  [ -f "$PAGE_SINK" ] && n="$(tr -d '[:space:]' < "$PAGE_SINK")"
  case "$n" in
    ''|*[!0-9]*) missing "no page count: ${PAGE_SINK} was not written" ;;
    *) printf '%s' "$n" ;;
  esac
}

version_cell() {
  local v=""
  [ -f "$MAIN_GO" ] && v="$(sed -n 's/^var version = "\([^"]*\)"$/\1/p' "$MAIN_GO" | head -1)"
  if [ -n "$v" ]; then printf '%s' "$v"; else missing "no version in ${MAIN_GO}"; fi
}

commit_cell() {
  if [ -n "${GITHUB_SHA:-}" ]; then printf "\`%s\`" "${GITHUB_SHA:0:7}"; else missing "GITHUB_SHA not set"; fi
}

trigger_cell() {
  case "${GITHUB_EVENT_NAME:-}" in
    '') missing "GITHUB_EVENT_NAME not set" ;;
    push) printf 'push%s' "${GITHUB_REF_NAME:+ to ${GITHUB_REF_NAME}}" ;;
    pull_request) printf 'pull request%s' "${QS_PR_NUMBER:+ #${QS_PR_NUMBER}}" ;;
    workflow_dispatch) printf 'by hand' ;;
    *) printf '%s' "$GITHUB_EVENT_NAME" ;;
  esac
}

duration_cell() {
  local start="${QS_STARTED_AT:-}" now="${QS_NOW:-}" secs
  [ -n "$now" ] || now="$(date +%s)"
  case "$start" in
    ''|*[!0-9]*) missing "the start time was not recorded"; return ;;
  esac
  secs=$((now - start))
  if [ "$secs" -lt 0 ]; then missing "the start time is in the future"; return; fi
  if [ "$secs" -ge 60 ]; then
    printf '%dm %ds' "$((secs / 60))" "$((secs % 60))"
  else
    printf '%ds' "$secs"
  fi
}

# --- the block ----------------------------------------------------------------
echo "## Run summary"
echo ""
echo "$status"
echo ""
echo "| | |"
echo "|---|---|"
echo "| PRE gates | $(phase_cell pre "$pre_counts") |"
echo "| POST gates | $(phase_cell post "$post_counts") |"
echo "| Go tests | $(go_tests_cell) |"
echo "| Total checks | $(total_cell) |"
echo "| Go coverage | $(coverage_cell) |"
echo "| Floors to raise | $(floors_cell) |"
echo "| Pages generated | $(pages_cell) |"
echo "| forsgren version | $(version_cell) |"
echo "| Commit | $(commit_cell) |"
echo "| Trigger | $(trigger_cell) |"
echo "| Duration | $(duration_cell) |"
echo ""
