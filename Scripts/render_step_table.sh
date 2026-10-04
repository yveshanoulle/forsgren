#!/usr/bin/env bash
set -uo pipefail

# Ported unchanged from another estate repository 2026-10-01 (forsgren#1); "this repo"
# in the history below means another estate repository.
#
# Renders sfl's end-of-run step table — unit 405.
#
# Ported in SHAPE from another estate repository, which has had one since its unit 352, but not
# in form: there it is thirty lines inline in sfl.sh. Here it is a script with a
# fixture, per the presentation-script rule this repo adopted in unit 404. A
# renderer nobody tests is how coachretreat's CI report step exited 1 on every
# run for a day with sfl green throughout.
#
# Usage: ./Scripts/render_step_table.sh <rows-file> [elapsed-seconds]
#
# Rows are `<name><TAB><result><TAB><seconds>` in execution order.
#
# The third column is agilelean's, taken back up in unit 408. It has carried a
# per-step duration since it built its table; this repo's original port dropped
# it, and a table that cannot say WHICH gate cost the twelve seconds is a table
# you stop reading — at 31 steps, most of all.

ROWS="${1:?usage: render_step_table.sh <rows-file> [elapsed-seconds] [counts-file]}"
ELAPSED="${2:-0}"
# Unit 407. FullBuildAndPush's one-line summary read `sfl ✅ (11s)` — a glyph
# and a duration, so a run with four gates skipped looked exactly like one
# where all thirty passed. The counts are written HERE because this script
# already derives them from the rows; two places counting the same gates is how
# they start disagreeing, and the shortest line on screen is the one a reader
# trusts most.
COUNTS_FILE="${3:-}"

# A header over no rows reads as "there are no gates" — the same false-clean
# shape as an all-clear over an estate nothing measured. Say it instead.
if [ ! -s "$ROWS" ]; then
  echo "---"
  echo "no steps were recorded — sfl ended before it ran a gate"
  # The same sentence shape as a real run — unit 415. `0/0` was a second format
  # for the emptiest possible result, and the summary row would have read as a
  # ratio nobody can interpret rather than as a run that recorded nothing.
  if [ -n "$COUNTS_FILE" ]; then printf '0 passed, 0 failed, 0 skipped (%ss)\n' "$ELAPSED" > "$COUNTS_FILE"; fi
  exit 0
fi

COL=36
n=0
passed=0
failed=0
skipped=0

echo "---"
printf " #  %-${COL}s %s\n" "Step" "Result"
printf '%*s\n' "$((COL + 18))" '' | tr ' ' '─'

# THE COUNTS ARE THE TABLE'S OWN. Nothing is passed in by the caller: a total
# that comes from somewhere other than the rows is how a summary starts
# disagreeing with what it summarises, which is exactly what this repo's CI
# report did for weeks — "25 of 25" over a file declaring 27.
while IFS=$'\t' read -r name result secs; do
  [ -n "${name:-}" ] || continue
  n=$((n + 1))
  # %-COL pads but never truncates: an over-long name pushes Result right on
  # the SAME line rather than wrapping. A wrapped row separates a gate from its
  # verdict at exactly the moment the table matters.
  # A zero-second gate prints (0s), never a blank: a blank in this column reads
  # as unmeasured rather than as fast.
  printf "[%2d] %-${COL}s %s  (%ss)\n" "$n" "$name" "${result:-}" "${secs:-0}"
  case "${result:-}" in
    *pass*) passed=$((passed + 1)) ;;
    *FAIL*) failed=$((failed + 1)) ;;
    *skip*) skipped=$((skipped + 1)) ;;
  esac
done < "$ROWS"

printf '%*s\n' "$((COL + 18))" '' | tr ' ' '─'

# ONE SENTENCE, ONE PRODUCER — unit 415, the last site repo to take it. This
# footer and the counts sink were two formats describing one run: `3 passed, 1
# failed` here and `3/4` in the sink, which FullBuildAndPush then printed beside
# its OWN timing of the same step. Three numbers, one run, one screen.
#
# Built once and consumed twice, so they cannot disagree.
#
# ZERO IS A MEASUREMENT (Yves, 2026-09-02: *"I would like to add skipped and
# failed even if 0"*). Both halves fell silent on a zero skip, which is right for
# a SUFFIX and wrong for a sentence: a missing clause reads as something nobody
# counted rather than as none. The quiet-on-zero rule stands for the icon policy
# it came from and does not survive the move into prose.
SUMMARY_LINE="${passed} passed, ${failed} failed, ${skipped} skipped (${ELAPSED}s)"
echo "$SUMMARY_LINE"

if [ -n "$COUNTS_FILE" ]; then
  printf '%s\n' "$SUMMARY_LINE" > "$COUNTS_FILE"
fi
