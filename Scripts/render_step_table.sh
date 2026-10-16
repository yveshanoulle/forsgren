#!/usr/bin/env bash
# canon: render_step_table v1
set -uo pipefail

# Renders sfl's end-of-run step table. It is byte-identical across the site
# repos; Scripts/test_render_step_table.sh pins it and proves each pin against a
# weakened copy.
#
# Usage: ./Scripts/render_step_table.sh <rows-file> [elapsed-seconds] [counts-file]
#
# Rows are `<name><TAB><result><TAB><seconds>` in execution order.
#
# The third column is a per-step duration: a table that cannot say WHICH gate
# cost the twelve seconds is a table you stop reading.

ROWS="${1:?usage: render_step_table.sh <rows-file> [elapsed-seconds] [counts-file]}"
ELAPSED="${2:-0}"
# FullBuildAndPush's one-line summary used to read `sfl ✅ (11s)`: a glyph and a
# duration, so a run with four gates skipped looked exactly like one where all
# thirty passed. The counts are written HERE because this script already
# derives them from the rows; two places counting the same gates is how they
# start disagreeing, and the shortest line on screen is the one a reader trusts
# most.
COUNTS_FILE="${3:-}"

# A header over no rows reads as "there are no gates" — the same false-clean
# shape as an all-clear over an estate nothing measured. Say it instead.
if [ ! -s "$ROWS" ]; then
  echo "---"
  echo "no steps were recorded — sfl ended before it ran a gate"
  # The same sentence shape as a real run. `0/0` was a second format for the
  # emptiest possible result, and the summary row would have read as a ratio
  # nobody can interpret rather than as a run that recorded nothing.
  if [ -n "$COUNTS_FILE" ]; then printf '0 passed, 0 warnings, 0 failed, 0 skipped (%ss)\n' "$ELAPSED" > "$COUNTS_FILE"; fi
  exit 0
fi

COL=40
n=0
passed=0
warned=0
failed=0
skipped=0

echo "---"
printf " #  %-${COL}s %s\n" "Step" "Result"
printf '%*s\n' "$((COL + 18))" '' | tr ' ' '─'

# THE COUNTS ARE THE TABLE'S OWN. Nothing is passed in by the caller: a total
# that comes from somewhere other than the rows is how a summary starts
# disagreeing with what it summarises ("25 of 25" over a file declaring 27).
while IFS=$'\t' read -r name result secs; do
  [ -n "${name:-}" ] || continue
  n=$((n + 1))
  # %-COL pads but never truncates: an over-long name pushes Result right on
  # the SAME line rather than wrapping. A wrapped row separates a gate from its
  # verdict at exactly the moment the table matters.
  # A zero-second gate prints (0s), never a blank: a blank in this column reads
  # as unmeasured rather than as fast.
  printf "[%2d] %-${COL}s %s  (%ss)\n" "$n" "$name" "${result:-}" "${secs:-0}"
  # THE WARNING CLASS. A row that warned and let the run continue must not be
  # counted as a pass: it would report a clean run over a step that did not
  # fully succeed. Nothing may fold it into the passed count, so it has its own.
  #
  # `⛔` counts as a failure, not as its own class — it is the secret-class red,
  # which differs in what it BLOCKS (the commit itself) rather than in whether
  # the run failed.
  case "${result:-}" in
    *pass*) passed=$((passed + 1)) ;;
    *warn*) warned=$((warned + 1)) ;;
    *FAIL*) failed=$((failed + 1)) ;;
    ⛔*)     failed=$((failed + 1)) ;;
    *skip*) skipped=$((skipped + 1)) ;;
  esac
done < "$ROWS"

printf '%*s\n' "$((COL + 18))" '' | tr ' ' '─'

# ONE SENTENCE, ONE PRODUCER. The footer used to say `30 passed (19s)` while the
# sink said `30/30`, and FullBuildAndPush printed the sink beside its OWN timing
# of the same step: three numbers for one run on one screen. Skipped and failed
# are counted even when 0.
#
# Built once and consumed twice, so they cannot disagree.
#
# ZERO IS A MEASUREMENT. Both halves used to fall silent on a zero skip, which
# is right for a SUFFIX and wrong for a sentence: a missing clause reads as
# something nobody counted rather than as none.
# Singular reads correctly: "1 warning", not "1 warnings". The other three
# counts are participles and take the same word either way; this one is a noun,
# and a summary line that cannot manage plain English gets read less carefully.
warn_word="warnings"
[ "$warned" -eq 1 ] && warn_word="warning"

SUMMARY_LINE="${passed} passed, ${warned} ${warn_word}, ${failed} failed, ${skipped} skipped (${ELAPSED}s)"
echo "$SUMMARY_LINE"

if [ -n "$COUNTS_FILE" ]; then
  printf '%s\n' "$SUMMARY_LINE" > "$COUNTS_FILE"
fi
