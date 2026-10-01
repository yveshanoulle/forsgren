#!/usr/bin/env bash
# Scripts/test_render_step_table.sh
#
# Ported from konenki-website 2026-10-01 (forsgren#1); "this repo" in the
# history below means konenki-website. forsgren's change: the FBP pin reads
# FBP.sh, and a missing FBP.sh fails the pin instead of skipping it.

set -euo pipefail

cd "$(dirname "$0")/.."

# Pins for Scripts/render_step_table.sh — unit 405, extended by unit 408 here.
#
# THE REVERSE PORT. agilelean has carried a per-step DURATION since it built its
# table; this repo's unit 405 port dropped it, and coachretreat's unit 403 port
# took it back up. This closes the gap the other way: the estate should end up
# with the BEST shape in every repo, not the first one that happened to land.
#
# WHY A TABLE AT ALL (Yves, 2026-09-01): "in web infra we have a nice list at
# the end … we don't have that for konenki-website / with so many checks that
# starts to get useful / just like I think we don't have a counter". This repo
# runs many gates and printed nothing but their names as they went, so a passing
# run gave no sense of progress and a failed one gave no shape of the whole.
#
# THE PIN THAT MATTERS is that the table cannot disagree with the run. A
# summary is trusted more than the scroll-back it summarises, so a row count
# that drifts from the rows, or a "passed" total that is not the number of
# passes in the table, is worse than no table — it is a confident wrong answer.

RENDER="./Scripts/render_step_table.sh"

TMP="$(mktemp -d)"
COMPLETED=0

cleanup() {
  rm -rf "$TMP"

  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: step-table pins aborted before completing all cases" >&2
    exit 1
  fi
}

trap cleanup EXIT

failed=0

fail() {
  echo "❌ FAIL: $*"
  failed=1
}

want() {
  local what="$1"
  local needle="$2"
  local hay="$3"

  if grep -qF -- "$needle" <<< "$hay"; then
    echo "  ok: ${what}"
  else
    fail "${what} — expected to find: ${needle}"
  fi
}

# `<name><TAB><result><TAB><seconds>`. agilelean has carried the third column
# since it built its table; konenki's port dropped it, and a table that cannot
# say WHICH gate costs the twelve seconds is a table you stop reading.
rows="${TMP}/rows"
{
  printf 'secret scan\t✅ pass\t1\n'
  printf 'HTMLHint\t✅ pass\t0\n'
  printf 'gate wiring\t❌ FAIL\t12\n'
  printf 'privacy posture\t✅ pass\t0\n'
} >"$rows"

# 25 for the whole run, 12 for the slow gate: two DIFFERENT numbers, so a pin
# on either cannot be satisfied by the other. Reusing one value here would have
# let a renderer that prints only the total still pass the per-row pin.
out="$("$RENDER" "$rows" 25)"

# Case 1: a header, and one numbered row per gate in execution order.
want "the table has a header" "Step" "$out"
want "the first gate is numbered 1" "[ 1] secret scan" "$out"
want "the failing gate keeps its row" "gate wiring" "$out"
want "and its result travels with it" "❌ FAIL" "$out"
want "the last gate is numbered 4" "[ 4] privacy posture" "$out"

# Case 2: THE COUNTS MUST BE THE TABLE'S OWN COUNTS. Passing them in from the
# caller is how a summary starts disagreeing with the thing it summarises —
# konenki's CI report said "25 of 25" for weeks while the file it rendered
# declared 27. Derived here, from the rows, so they cannot drift.
want "the counts line totals the rows" "3 passed, 1 failed" "$out"
want "and reports the whole run's elapsed time" "(25s)" "$out"

# The duration belongs to its row. A total alone says the run took twelve
# seconds; it cannot say which gate spent them, which is the question anyone
# looking at a slow run actually has.
want "and the slow gate carries its own 12s" "(12s)" "$out"

if [ "$(printf '%s\n' "$out" | grep -c '(0s)')" -eq 2 ]; then
  echo "  ok: fast gates report their own duration too, not a blank"
else
  fail "a zero-second gate lost its duration column — a blank reads as unmeasured, not as fast"
fi

# Case 3: a run where nothing was recorded must SAY so. An empty table with a
# header reads as "there are no gates", which is the same false-clean shape as
# an all-clear over an unmeasured estate.
empty="${TMP}/empty"
: > "$empty"
out2="$("$RENDER" "$empty" 0)"
want "an empty run is stated, not drawn as an empty table" "no steps" "$out2"

# Case 4: alignment must survive a name longer than the column. A row that
# wraps or shoves the Result column sideways makes the table unreadable at
# exactly the moment it matters.
long="${TMP}/long"
printf 'mutation: deploy-feta pins and their checkout-pin siblings\t❌ FAIL\t3\n' >"$long"
out3="$("$RENDER" "$long" 1)"

if [ "$(printf '%s\n' "$out3" | grep -c 'FAIL')" -eq 1 ]; then
  echo "  ok: an over-long name keeps its result on the same line"
else
  fail "an over-long gate name split its row — the result no longer sits beside the gate it belongs to"
fi

# Case 5: the counts must also reach FullBuildAndPush's phase summary — unit
# 407, migrated when sfl became PRE and POST phases. A duration-only phase row
# cannot distinguish a run where gates were skipped from one where every gate
# passed.
#
# Written by the RENDERER, not recomputed by sfl or by FBP. Two places counting
# the same gates is how they start disagreeing, and the summary line is the one
# a reader trusts most because it is the shortest.
counts="${TMP}/counts"
out5="$("$RENDER" "$rows" 12 "$counts")"

if [ ! -s "$counts" ]; then
  fail "no counts were written for the summary line — FBP has nothing to show but a duration"
else
  got="$(cat "$counts")"

  if [ "$got" = "3 passed, 1 failed, 0 skipped (12s)" ]; then
    echo "  ok: the counts file carries passed/failed/skipped for the summary line"
  else
    fail "the counts file says '${got}', expected '3 passed, 1 failed, 0 skipped (12s)' — the sink and the footer must be one string, not two formats of one run"
  fi
fi

want "and the table itself is unchanged by asking for counts" "3 passed, 1 failed" "$out5"

# ZERO IS A MEASUREMENT — unit 415, the last site repo to take it. The suffix
# used to fall silent on a zero, which is right for a SUFFIX and wrong for a
# sentence: a missing clause reads as something nobody counted rather than as
# none. Yves, 2026-09-02: *"I would like to add skipped and failed even if 0."*
want "a clean run still names its skipped count" "0 skipped" "$out5"

# ONE SENTENCE, ONE PRODUCER. PRE and POST are separate sfl runs, so each phase
# must preserve its own renderer-produced count sentence. FBP must consume
# those sentences rather than recompute counts, and it must not append a second
# duration because the renderer-produced sentence already ends in one.
FBP="$(cd "$(dirname "$0")/.." && pwd)/FBP.sh"

if [ -f "$FBP" ]; then
  pre_row_fmt="$(grep -E 'printf .*"pre gates"' "$FBP" || true)"
  post_row_fmt="$(grep -E 'printf .*"post gates"' "$FBP" || true)"

  if [ -z "$pre_row_fmt" ]; then
    fail "no PRE-gates row found in FullBuildAndPush — this pin is measuring nothing"
  elif grep -qF '(%ss)' <<< "$pre_row_fmt"; then
    fail "FullBuildAndPush still formats its own duration onto the PRE row — the renderer sentence already ends in one: ${pre_row_fmt}"
  else
    echo "  ok: FBP PRE row prints the renderer sentence and no duration of its own"
  fi

  if [ -z "$post_row_fmt" ]; then
    fail "no POST-gates row found in FullBuildAndPush — this pin is measuring nothing"
  elif grep -qF '(%ss)' <<< "$post_row_fmt"; then
    fail "FullBuildAndPush still formats its own duration onto the POST row — the renderer sentence already ends in one: ${post_row_fmt}"
  else
    echo "  ok: FBP POST row prints the renderer sentence and no duration of its own"
  fi
else
  fail "FBP.sh not found at ${FBP} — the PRE/POST row pins measured nothing"
fi

# A skipped gate must be visible in that line too: a bare total over a run with
# two gates skipped reads as complete, which is how the estate lost sight of
# two Trivy scans for weeks.
rows2="${TMP}/rows2"
printf 'a\t✅ pass\t0\n' >"$rows2"
printf 'b\t⏭️ skip\t0\n' >>"$rows2"
counts2="${TMP}/counts2"
"$RENDER" "$rows2" 1 "$counts2" >/dev/null 2>&1 || true

# `|| true`: under set -e a missing file aborts the fixture here, and an aborted
# fixture reports nothing about the cases after it. That is what happened the
# first time these pins met a stub — they were written in a repo where the
# implementation already worked, so their behaviour on an EMPTY renderer had
# never been exercised. A check that dies on the first surprise stops telling
# you things at exactly the moment it has something to say.
got2="$(cat "$counts2" 2>/dev/null || true)"

if grep -qF 'skipped' <<< "$got2"; then
  echo "  ok: a skipped gate is named in the counts, not folded into the total"
else
  fail "the counts say '${got2}' and hide a skipped gate — a total that counts a skip as a pass reads as complete"
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: step-table pins"
  exit 1
fi

echo "OK: step table (numbered rows in execution order, counts derived from the rows, an empty run stated, long names aligned)"