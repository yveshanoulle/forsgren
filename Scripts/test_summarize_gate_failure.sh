#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Ported unchanged from another estate repository 2026-10-01 (forsgren#1); "here" in
# the history below means another estate repository.
#
# Pins for Scripts/summarize_gate_failure.sh — unit 404, ported from
# coachretreat-website (its unit 402), where another estate repository's gate-parity axis now
# reports this gate MISSING here until it lands.
#
# sfl's end-of-run block prints "Errors:" and then the NAMES of the gates that
# failed. Its own comment claims this saves "a scroll-back read". It does not:
# the name tells you which gate, never why, so the reason is still somewhere up
# the log among every passing gate's output.
#
# THE FAILURE MODE THIS GUARDS. A summarizer that finds nothing must SAY it
# found nothing. Printing an empty reason reads as "no reason given", which is
# indistinguishable from "the gate failed silently" — and a summary that
# quietly degrades to the thing it replaced is worse than not having one,
# because it stops anyone looking further.

SUM="./Scripts/summarize_gate_failure.sh"

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: gate-failure summary pins aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

failed=0
fail() { echo "❌ FAIL: $*"; failed=1; }

want() {
  local what="$1" needle="$2" hay="$3"
  if grep -qF -- "$needle" <<< "$hay"; then
    echo "  ok: ${what}"
  else
    fail "${what} — expected to find: ${needle}"
  fi
}
want_not() {
  local what="$1" needle="$2" hay="$3"
  if grep -qF -- "$needle" <<< "$hay"; then
    fail "${what} — did NOT expect: ${needle}"
  else
    echo "  ok: ${what}"
  fi
}

# Case 1: the marked lines are the reason, and the passing noise around them
# is not. This is the whole point — one failure among a dozen ok: lines.
log1="${TMP}/marked.log"
{
  echo "  ok: 'persist-credentials removed' correctly rejected"
  echo "❌ FAIL: the SHIPPED order file makes the renderer exit non-zero"
  echo "  ok: rows render in declared order"
  echo "❌ FAIL: a trailing declared row killed the exit status"
} > "$log1"
out1="$("$SUM" "$log1")"
want     "the marked failure lines are returned" "the SHIPPED order file makes the renderer exit non-zero" "$out1"
want     "and every one of them, not just the first" "a trailing declared row killed the exit status" "$out1"
want_not "the passing lines are left out"        "correctly rejected" "$out1"

# Case 2: not every fixture in the estate has been swept to ❌ yet — 86 of them
# still print a bare FAIL:. A summarizer that only understands the new marker
# would go silent on exactly the scripts that have not been modernised.
log2="${TMP}/plain.log"
{
  echo "checking things"
  echo "FAIL: bootstrap-server.yml never invokes inspect_sudoers_allowlist.sh"
} > "$log2"
out2="$("$SUM" "$log2")"
want "an unswept fixture's plain FAIL: is still found" "never invokes inspect_sudoers_allowlist.sh" "$out2"

# Case 3: a gate that dies without either marker — a syntax error, a missing
# binary, a `set -e` abort. The last lines are all there is, and they are far
# better than nothing.
log3="${TMP}/crash.log"
{
  echo "starting"
  echo "./Scripts/thing.sh: line 12: jq: command not found"
} > "$log3"
out3="$("$SUM" "$log3")"
want "a gate that crashed without a marker still reports its tail" "jq: command not found" "$out3"

# Case 4: SILENCE IS NOT AN ANSWER. An empty log must produce a stated
# not-found, never an empty string that renders as a blank line under the gate
# name and reads as "no reason".
log4="${TMP}/empty.log"; : > "$log4"
out4="$("$SUM" "$log4")"
if [ -z "${out4//[[:space:]]/}" ]; then
  fail "an empty log produced empty output — under a gate name that renders as a blank line, which reads as 'failed for no reason' and stops anyone looking further"
else
  echo "  ok: an empty log says so rather than printing nothing"
fi
want "and it names the log so it can be opened" "$log4" "$out4"

# Case 5: the summary must stay a summary. Reprinting a 400-line log under the
# gate name recreates the scroll-back this replaces.
log5="${TMP}/many.log"
: > "$log5"
i=1
while [ "$i" -le 40 ]; do echo "❌ FAIL: problem number ${i}" >> "$log5"; i=$((i + 1)); done
out5="$("$SUM" "$log5" 5)"
n5="$(printf '%s\n' "$out5" | grep -c 'problem number' || true)"
if [ "$n5" -le 5 ]; then
  echo "  ok: the summary is capped at the requested number of lines"
else
  fail "the cap was ignored — ${n5} reason lines returned when 5 were asked for, which reprints the log the summary exists to replace"
fi
want "and it says how many it left out" "35 more" "$out5"

COMPLETED=1
if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: gate-failure summary pins"
  exit 1
fi
echo "OK: gate-failure summary (marked and plain failures found, a crash tail reported, an empty log stated rather than silent, and the cap honoured)"
