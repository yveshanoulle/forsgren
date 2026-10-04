#!/usr/bin/env bash
set -uo pipefail

# Ported unchanged from konenki-website 2026-10-01 (forsgren#1); "this repo"
# in the history below means konenki-website.
#
# Prints WHY a gate failed, for sfl's end-of-run block and FullBuildAndPush's
# summary — unit 404, ported from coachretreat-website (its unit 402).
#
# Before this, both ended with gate NAMES only. `run_gate`'s own comment
# claimed that saved "a scroll-back read"; it did not. The name says which
# gate, never why, so the reason stayed up the log among every passing gate's
# output — and FBP's summary, the genuinely last thing on screen, did not even
# carry the names.
#
# Usage: ./Scripts/summarize_gate_failure.sh <log-file> [max-lines]
#
# Output is indented four spaces so it nests under the gate name.

LOG="${1:?usage: summarize_gate_failure.sh <log-file> [max-lines]}"
MAX="${2:-6}"

if [ ! -f "$LOG" ]; then
  echo "    (the gate failed and no log was captured at ${LOG})"
  exit 0
fi

# THREE SHAPES, in order of how much they tell you.
#
# 1. The ❌ marker, added 2026-09-01 so a failure is findable by eye.
# 2. A bare `FAIL:`. Most of the estate still prints this — 86 fixtures across
#    the four repos were unswept at the time of writing. A summarizer that only
#    understood the new marker would go silent on exactly the scripts nobody
#    has modernised, which is the worst place to lose the reason. In THIS repo
#    check_privacy_pages.sh prints `FAIL ` with no colon at all, which is why
#    the match is on `^[[:space:]]*FAIL` and not on `FAIL:`.
# 3. Neither: a syntax error, a missing binary, a `set -e` abort. The tail is
#    all there is, and it beats a blank line.
reasons="$(grep -F '❌' "$LOG" || true)"
if [ -z "$reasons" ]; then
  reasons="$(grep -E '^[[:space:]]*FAIL' "$LOG" || true)"
fi
if [ -z "$reasons" ]; then
  reasons="$(grep -vE '^[[:space:]]*$' "$LOG" | tail -n "$MAX" || true)"
fi

# SILENCE IS NOT AN ANSWER. An empty result renders as a blank line under the
# gate name and reads as "it failed for no reason", which stops the reader
# looking further. Say that nothing was captured, and name the log.
if [ -z "$reasons" ]; then
  echo "    (the gate failed and said nothing — empty log: ${LOG})"
  exit 0
fi

total="$(printf '%s\n' "$reasons" | grep -c '')"
head -n "$MAX" <<<"$reasons" | sed 's/^/    /'
if [ "$total" -gt "$MAX" ]; then
  echo "    … ${total} lines in all, $((total - MAX)) more above"
fi
