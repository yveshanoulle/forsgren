#!/usr/bin/env bash
# canon: test_render_step_table v3
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh

# Pins for Scripts/render_step_table.sh, the renderer of sfl's end-of-run step
# table. Having the table and having the check that keeps it are different
# things: inline in sfl.sh nothing would notice it breaking.
#
# THE PIN THAT MATTERS is that the table cannot disagree with the run. A
# summary is trusted more than the scroll-back it summarises, so a row count
# that drifts from the rows, or a "passed" total that is not the number of
# passes in the table, is worse than no table: it is a confident wrong answer.
#
# Four counts, not three: a row that warned and let the run continue must not be
# counted as a pass, so the warning class exists even while nothing produces it.
# A secret-class row (a leading no-entry sign) counts as a failure: it differs
# from an ordinary red in what it BLOCKS, not in whether the run failed.
#
# MUTATION PROOF, at the end: the same pins run against weakened copies of the
# renderer (a warning counted as a pass, a secret-class row not counted, a skip
# folded into the passes, no duration, an empty run drawn as an empty table, no
# counts file, a truncated name, ...), and each copy must be red for its own
# reason. The renderer under test is the optional first argument; without one it
# is the real renderer and the mutation proof runs.

RENDER="${1:-./Scripts/render_step_table.sh}"
SELF="${PWD}/Scripts/test_render_step_table.sh"

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
fail() { echo "❌ FAIL: $*"; failed=1; }

want() {
  local what="$1" needle="$2" hay="$3"
  if grep -qF -- "$needle" <<< "$hay"; then
    echo "  ok: ${what}"
  else
    fail "${what} — expected to find: ${needle}"
  fi
}

# `<name><TAB><result><TAB><seconds>`: the third column is the step's duration,
# because a table that cannot say WHICH gate costs the twelve seconds is a table
# you stop reading.
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
want "the table has a header"          "Step"            "$out"
want "the first gate is numbered 1"    "[ 1] secret scan" "$out"
want "the failing gate keeps its row"  "gate wiring"      "$out"
want "and its result travels with it"  "❌ FAIL"          "$out"
want "the last gate is numbered 4"     "[ 4] privacy posture" "$out"

# Case 2: THE COUNTS MUST BE THE TABLE'S OWN COUNTS. Passing them in from the
# caller is how a summary starts disagreeing with the thing it summarises.
# Derived here, from the rows, so they cannot drift.
want "the counts line totals the rows" "3 passed, 0 warnings, 1 failed" "$out"
want "and reports the whole run's elapsed time" "(25s)"       "$out"

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
# header reads as "there are no gates", the same false-clean shape as an
# all-clear over an unmeasured estate. Its counts sink carries the same
# sentence shape as a real run.
empty="${TMP}/empty"; : > "$empty"
empty_counts="${TMP}/empty_counts"
out2="$("$RENDER" "$empty" 0 "$empty_counts")"
want "an empty run is stated, not drawn as an empty table" "no steps" "$out2"
got_empty="$(cat "$empty_counts" 2>/dev/null || true)"
if [ "$got_empty" = "0 passed, 0 warnings, 0 failed, 0 skipped (0s)" ]; then
  echo "  ok: an empty run writes the same sentence shape as a real one"
else
  fail "the empty-run counts say '${got_empty}', expected '0 passed, 0 warnings, 0 failed, 0 skipped (0s)' — the emptiest result must not be a second format"
fi

# Case 4: alignment must survive a name longer than the column. A row that
# wraps or shoves the Result column sideways makes the table unreadable at
# exactly the moment it matters, and the name must still be printed in full.
long="${TMP}/long"
printf 'mutation: staging-alpha pins and their checkout-pin siblings\t❌ FAIL\t3\n' >"$long"
out3="$("$RENDER" "$long" 1)"
if [ "$(printf '%s\n' "$out3" | grep -c 'FAIL')" -eq 1 ]; then
  echo "  ok: an over-long name keeps its result on the same line"
else
  fail "an over-long gate name split its row — the result no longer sits beside the gate it belongs to"
fi
want "and an over-long name is printed in full" "mutation: staging-alpha pins and their checkout-pin siblings" "$out3"

# Case 5: the counts must also reach FullBuildAndPush's one-line summary. That
# line used to read `sfl ✅ (11s)` and say how long, never how much: a run where
# four gates were skipped looked identical to one where all thirty passed.
#
# Written by the RENDERER, not recomputed by sfl or by FBP. Two places counting
# the same gates is how they start disagreeing, and the summary line is the one
# a reader trusts most because it is the shortest. The sentence is built once,
# echoed and written, so the two cannot drift.
counts="${TMP}/counts"
out5="$("$RENDER" "$rows" 12 "$counts")"
if [ ! -s "$counts" ]; then
  fail "no counts were written for the summary line — FBP has nothing to show but a duration"
else
  got="$(cat "$counts")"
  if [ "$got" = "3 passed, 0 warnings, 1 failed, 0 skipped (12s)" ]; then
    echo "  ok: the sink carries the same sentence the table prints"
  else
    fail "the counts file says '${got}', expected '3 passed, 0 warnings, 1 failed, 0 skipped (12s)' — the sink and the footer must be one string, not two formats of one run"
  fi
fi
want "and the table itself is unchanged by asking for counts" "3 passed, 0 warnings, 1 failed" "$out5"

# ZERO IS A MEASUREMENT. The suffix used to fall silent on a zero, which is
# right for a suffix and wrong for a sentence: a missing clause reads as
# something nobody counted rather than as none.
want "a clean run still names its skipped count" "0 skipped" "$out5"
want "and its warning count"                       "0 warnings" "$out5"

# A skipped gate must be visible in that line too: a bare 30/30 over a run with
# two gates skipped reads as complete.
rows2="${TMP}/rows2"
printf 'a\t✅ pass\t0\n'  >"$rows2"
printf 'b\t⏭️ skip\t0\n' >>"$rows2"
counts2="${TMP}/counts2"
"$RENDER" "$rows2" 1 "$counts2" >/dev/null 2>&1 || true
# `|| true`: under set -e a missing file aborts the fixture here, and an aborted
# fixture reports nothing about the cases after it. A check that dies on the
# first surprise stops telling you things at exactly the moment it has
# something to say.
got2="$(cat "$counts2" 2>/dev/null || true)"
if [ "$got2" = "1 passed, 0 warnings, 0 failed, 1 skipped (1s)" ]; then
  echo "  ok: a skipped gate is named in the counts, not folded into the total"
else
  fail "a skipped gate is not named: the counts say '${got2}', expected '1 passed, 0 warnings, 0 failed, 1 skipped (1s)' — a total that counts a skip as a pass reads as complete"
fi

# And the sentence is the renderer's, not FullBuildAndPush's. FBP must print
# what it is handed and add no second duration beside it: two elapsed times on
# one row read as a disagreement rather than as one thing measured twice.
FBP="$(pwd)/FullBuildAndPush.sh"
if [ -f "$FBP" ]; then
  # Read the ROW's format string and ask whether it still carries a duration.
  # A pattern that required the duration to appear AFTER the label matched
  # nothing, because the format puts it before; the negation then made the pin
  # true and it reported a fix that never happened.
  sfl_row_fmt="$(grep -E 'printf .*"sfl"' "$FBP" || true)"
  if [ -n "$sfl_row_fmt" ]; then
    row_labels=("sfl")
  else
    row_labels=("pre gates" "post gates")
  fi
  for label in "${row_labels[@]}"; do
    row_fmt="$(grep -E "printf .*\"${label}\"" "$FBP" || true)"
    if [ -z "$row_fmt" ]; then
      fail "no ${label} row found in FullBuildAndPush — this pin is measuring nothing"
    elif grep -qF '(%ss)' <<< "$row_fmt"; then
      fail "FullBuildAndPush still formats its own duration onto the ${label} row — the sentence already ends in one, and two elapsed times on one row read as a disagreement: ${row_fmt}"
    else
      echo "  ok: FBP ${label} row prints the sentence and no duration of its own"
    fi
  done
fi

# Case 6: the warning class. A row that warned and let the run continue must
# not be counted as a pass. Singular reads correctly too: "1 warning", not
# "1 warnings". The other three counts are participles and stay the same word
# either way; this one is a noun.
rows3="${TMP}/rows3"
{
  printf 'git pull (origin sync)\t⚠️  warn\t0\n'
  printf 'secret scan\t✅ pass\t2\n'
} >"$rows3"
counts3="${TMP}/counts3"
out6="$("$RENDER" "$rows3" 3 "$counts3" 2>/dev/null || true)"
want "a warning is counted as a warning, not as a pass" "1 passed, 1 warning, 0 failed, 0 skipped" "$out6"
got3="$(cat "$counts3" 2>/dev/null || true)"
if [ "$got3" = "1 passed, 1 warning, 0 failed, 0 skipped (3s)" ]; then
  echo "  ok: the sink carries the warning too"
else
  fail "the warning is not in the sink: the counts say '${got3}', expected '1 passed, 1 warning, 0 failed, 0 skipped (3s)' — a warning that reaches the table and not the summary line is invisible where it is read most"
fi

# Case 7: a secret-class row counts as a failure, not as its own class and not
# as a pass.
rows4="${TMP}/rows4"
{
  printf 'secret scan\t⛔ FAIL (secret-class)\t1\n'
  printf 'HTMLHint\t✅ pass\t0\n'
} >"$rows4"
out7="$("$RENDER" "$rows4" 1 2>/dev/null || true)"
want "a secret-class row is counted as a failure" "1 passed, 0 warnings, 1 failed, 0 skipped" "$out7"
rows5="${TMP}/rows5"
printf 'secret scan\t⛔ blocked\t1\n' >"$rows5"
out8="$("$RENDER" "$rows5" 1 2>/dev/null || true)"
want "a secret-class row without the word FAIL is still a failure" "0 passed, 0 warnings, 1 failed, 0 skipped" "$out8"

# --- Mutation proof: weakened copies of the renderer must be red here, each for
# its own reason (the failure line the case prints).
if [[ $# -eq 0 ]]; then
  MUT="$(mktemp -d)"
  mutant_must_fail() { # <label> <sed-expression> <reason fragment>
    local m="$MUT/render_step_table_$RANDOM.sh" mout rc
    sed "$2" "$RENDER" > "$m"
    chmod +x "$m"
    if cmp -s "$RENDER" "$m"; then
      fail "mutation '$1' changed nothing: it proves nothing"
      return
    fi
    set +e
    mout="$("$SELF" "$m" 2>&1)"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      fail "mutation '$1' PASSED these pins: no case guards it"
    elif ! grep -qF -- "$3" <<< "$mout"; then
      fail "mutation '$1' was red, but not for the wanted reason (${3}): the case that should catch it does not"
    else
      echo "OK:   mutation '$1' is red (${3})"
    fi
  }
  mutant_must_fail "a warning is counted as a pass" \
    "s#\\*warn\\*) warned=\\\$((warned + 1))#*warn*) passed=\$((passed + 1))#" "a warning is counted as a warning"
  mutant_must_fail "a secret-class row is not counted" \
    '/^    ⛔\*)/d' "a secret-class row"
  mutant_must_fail "a skip is folded into the passes" \
    "s#\\*skip\\*) skipped=\\\$((skipped + 1))#*skip*) passed=\$((passed + 1))#" "a skipped gate is not named"
  mutant_must_fail "a failure is not counted" \
    '/^    \*FAIL\*)/d' "the counts line totals the rows"
  mutant_must_fail "the skipped clause is dropped from the sentence" \
    "s#, \\\${skipped} skipped##" "still names its skipped count"
  mutant_must_fail "the per-step duration is dropped" \
    "s#\"\\\${secs:-0}\"#\"-\"#" "the slow gate carries its own 12s"
  mutant_must_fail "an empty run is drawn as an empty table" \
    's#no steps were recorded#nothing to see#' "an empty run is stated"
  mutant_must_fail "the empty run writes another format to the sink" \
    "s#0 passed, 0 warnings, 0 failed, 0 skipped (%ss)#0/0 (%ss)#" "the empty-run counts say"
  mutant_must_fail "the counts file is never written" \
    "s#^  printf .%s\\\\n. \"\\\$SUMMARY_LINE\" > \"\\\$COUNTS_FILE\"#  :#" "no counts were written"
  mutant_must_fail "a long name is truncated" \
    "s#\\[%2d\\] %-\\\${COL}s#[%2d] %.12s#" "printed in full"
  mutant_must_fail "the numbering starts at 2" \
    "s#n=\\\$((n + 1))#n=\$((n + 2))#" "the first gate is numbered 1"
  mutant_must_fail "the elapsed time is not reported" \
    "s#(\\\${ELAPSED}s)#(0s)#" "elapsed time"
  mutant_must_fail "one warning reads as warnings" \
    "s#^\\[ \"\\\$warned\" -eq 1 \\] .*\$#:#" "a warning is counted as a warning"
  rm -rf "$MUT"
fi

COMPLETED=1
if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: step-table pins"
  exit 1
fi
echo "OK: step table (numbered rows in execution order, counts derived from the rows, warning and secret-class rows classed, an empty run stated, long names aligned and whole)"
