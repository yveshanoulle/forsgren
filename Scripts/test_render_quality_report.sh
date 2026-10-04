#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Pins for Scripts/render_quality_report.sh — unit 406, ported from
# coachretreat-website (its unit 401), where another estate repository's gate-parity axis has
# been reporting this gate MISSING here since unit 403 put it in the canon.
#
# THE ONE THAT MATTERS IS THE EXIT STATUS. The renderer runs with
# `set -uo pipefail` and no -e, so nothing aborts and the step's result is
# whatever the LAST command returned. The last command is a `while` loop whose
# body ends in `[ -f "${DETAILS}/${slug}.md" ] && cat ...` — so if the final
# declared gate has no details file, the loop returns 1, the group returns 1,
# and the step FAILS while every gate passed.
#
# NOT the defect this repo has — konenki's last declared row is a real gate, so
# the exit-status bug never fired here. What this repo has instead is worse in a
# quieter way: `cat "$ROWS"` and `cat "$DETAILS"` render in RUN order while
# gate_report_order.txt exists precisely to fix that, so the table and the body
# can disagree about sequence. The pins below carry both properties, because the
# estate runs one renderer and it has to hold in every repo.
#
# In coachretreat that is not hypothetical. Two `n/a` rows at the end of
# Scripts/gate_report_order.txt describe gates that do not exist here and can
# never write a details file, so the report has exited 1 on every run since
# they were added — while sfl stayed green, because nothing local ran it.
#
# A REPORT THAT FAILS FOR A REASON UNRELATED TO WHAT IT REPORTS is worse than
# no report: it trains you to ignore the one step whose job is to tell you when
# something is wrong.
#
# Ported from another estate repository 2026-10-01 (forsgren#1, ladder step 14); "this
# repo" above means konenki. forsgren's change: case 6 at the end, for the
# renderer's forsgren change (n/a rows are not counted as unreported gates,
# and show as n/a in the table), seen red against konenki's renderer first.
# Its two n/a rows sit at the end of forsgren's order file too, so case 5
# exercises the trailing-row property on what ships here.
#
# Runs from sfl.sh and from quality.yml through Scripts/run_ci_phase.sh, as
# the `quality-report render` row of Scripts/gate_report_order.txt.

RENDER="./Scripts/render_quality_report.sh"

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: quality-report render pins aborted before completing all cases" >&2
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

# Case 1: THE DEFECT. A declared row that never produces a details file — an
# `n/a` gate, or any gate the run never reached — must not turn a rendered
# report into a failed step.
order="${TMP}/order_trailing_na"
{
  echo "# comment line"
  echo "secret scan|-"
  echo "privacy pages|n/a|nothing is collected here"
} > "$order"
rows="${TMP}/rows1"; printf 'secret scan|✅\n' > "$rows"
details="${TMP}/details1"; mkdir -p "$details"
{ echo ""; echo "#### ✅ secret scan"; } > "${details}/secret_scan.md"

if out="$("$RENDER" "$rows" "$details" "$order" 2>&1)"; then
  echo "  ok: a trailing declared row with no details file still exits 0"
else
  fail "the renderer EXITED NON-ZERO on a report it rendered fine — the last declared row has no details file, and the loop's exit status became the step's. Every gate passed and the run went red"
fi
want "the rendered table is still produced" "| secret scan | ✅ |" "$out"
want "the detail body is still emitted"     "#### ✅ secret scan"  "$out"

# Case 2: declared order wins over the order rows arrived in. Gates run in
# glob order and the report must not inherit it — an index and the thing it
# indexes disagreeing is worse than either being wrong alone.
order2="${TMP}/order2"
{ echo "alpha|-"; echo "beta|-"; echo "gamma|-"; } > "$order2"
rows2="${TMP}/rows2"; printf 'gamma|✅\nalpha|✅\nbeta|❌\n' > "$rows2"
details2="${TMP}/details2"; mkdir -p "$details2"
out2="$("$RENDER" "$rows2" "$details2" "$order2" 2>&1)" || true
# `|| true` on the pipeline: grep exits 1 when it matches nothing, which under
# set -e aborts the fixture before the cases below ever run — what happened the
# first time these pins met a stub.
table_order="$(grep -o '^| [a-z]* |' <<< "$out2" | tr -d '| ' | tr '\n' ' ' || true)"
if [ "$table_order" = "alpha beta gamma " ]; then
  echo "  ok: rows render in declared order, not the order they arrived"
else
  fail "declared order not honoured — got: ${table_order}"
fi

# Case 3: a run that reported nothing says so, and says where to look. An
# empty table would read as an estate with no gates.
rows3="${TMP}/rows3"; : > "$rows3"
out3="$("$RENDER" "$rows3" "$details2" "$order2" 2>&1)" || fail "empty rows must still exit 0 — a job that died early still needs its report"
want     "no gate reported is stated"        "No gate reported"   "$out3"
want_not "and it is not an empty pass table" "| Gate | Result |"  "$out3"

# Case 4: fewer gates than declared is UNMEASURED, not clean. This is the
# estate rule that a check which did not run must never render as a check that
# passed.
out4="$("$RENDER" "$rows2" "$details2" "$order2" 2>&1)" || true
want "a partial run says so" "_3 of 3 gates reported._" "$out4"
rows5="${TMP}/rows5"; printf 'alpha|✅\n' > "$rows5"
out5="$("$RENDER" "$rows5" "$details2" "$order2" 2>&1)" || true
want "a short run is called unmeasured" "they are unmeasured" "$out5"

# Case 6 (forsgren#1, ladder step 14): an `n/a` row declares a gate this
# repo does not have, with the reason. It can never report, so it must not be
# counted as a gate that should have: another estate repository's renderer counts every
# declared row, so coachretreat-website, with two n/a rows, reads "N of N+2
# gates reported" and "unmeasured" on a run where every gate ran. Nor may it
# vanish from the table: the reader sees the n/a the order file declares.
order6="${TMP}/order6"
{
  echo "alpha|Scripts/alpha.sh|pre|"
  echo "privacy pages|n/a|nothing is collected here"
} > "$order6"
rows7="${TMP}/rows7"; printf 'alpha|✅\n' > "$rows7"
out6="$("$RENDER" "$rows7" "$details2" "$order6" 2>&1)" || true
want     "an n/a row is not counted as a gate that should have reported" "_1 of 1 gates reported._" "$out6"
want_not "a run where every runnable gate reported is not called unmeasured" "they are unmeasured" "$out6"
want     "the n/a row is shown as n/a in the table" "| privacy pages | n/a |" "$out6"

# Case 5: the REAL order file, with the repo's real trailing rows. Case 1
# proves the property on a fixture; this proves the property holds for what
# actually ships, which is where it was broken.
rows6="${TMP}/rows6"; printf 'secret scan|✅\n' > "$rows6"
details6="${TMP}/details6"; mkdir -p "$details6"
if "$RENDER" "$rows6" "$details6" >/dev/null 2>&1; then
  echo "  ok: the repo's own gate_report_order.txt renders and exits 0"
else
  fail "the SHIPPED order file makes the renderer exit non-zero — this is the CI failure, reproduced locally"
fi

COMPLETED=1
if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: quality-report render pins"
  exit 1
fi
echo "OK: quality-report render (exit status survives a detail-less trailing row, declared order honoured, empty and partial runs told apart from clean)"
