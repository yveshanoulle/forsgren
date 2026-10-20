#!/usr/bin/env bash
# canon: test_render_quality_report v3
set -euo pipefail

cd "$(dirname "$0")/.."

# Pins for Scripts/render_quality_report.sh — unit 406, ported from another
# estate repository (its unit 401), where the estate's gate-parity axis had
# been reporting this gate MISSING here since unit 403 put it in the canon.
#
# THE ONE THAT MATTERS IS THE EXIT STATUS. The renderer runs with
# `set -uo pipefail` and no -e, so nothing aborts and the step's result is
# whatever the LAST command returned. The last command is a `while` loop whose
# body ends in `[ -f "${DETAILS}/${slug}.md" ] && cat ...` — so if the final
# declared gate has no details file, the loop returns 1, the group returns 1,
# and the step FAILS while every gate passed.
#
# NOT the defect this repo has — this repo's last declared row is a real gate, so
# the exit-status bug never fired here. What this repo has instead is worse in a
# quieter way: `cat "$ROWS"` and `cat "$DETAILS"` render in RUN order while
# gate_report_order.txt exists precisely to fix that, so the table and the body
# can disagree about sequence. The pins below carry both properties, because the
# estate runs one renderer and it has to hold in every repo.
#
# In the source repository that is not hypothetical. Two `n/a` rows at the end of
# Scripts/gate_report_order.txt describe gates that do not exist here and can
# never write a details file, so the report has exited 1 on every run since
# they were added — while sfl stayed green, because nothing local ran it.
#
# A REPORT THAT FAILS FOR A REASON UNRELATED TO WHAT IT REPORTS is worse than
# no report: it trains you to ignore the one step whose job is to tell you when
# something is wrong.
#
# Ported from another estate repository 2026-10-01 (forsgren#1, ladder step 14); "this
# repo" above means the repository it was ported to. forsgren's change: case 6
# at the end, for the renderer's forsgren change (n/a rows are not counted as
# unreported gates, and show as n/a in the table), seen red against the
# unchanged renderer first.
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
want "the rendered table is still produced" "| secret scan | not counted | ✅ |" "$out"
want_not "a green gate's details are left out of the page (v3)" "#### ✅ secret scan"  "$out"

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
table_order="$(grep -oE '^\| [a-z]+' <<< "$out2" | tr -d '| ' | tr '\n' ' ' || true)"
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
want_not "and it is not an empty pass table" "| Gate | Checks | Result |"  "$out3"

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
# declared row, so that repository, with two n/a rows, reads "N of N+2
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
want     "the n/a row is shown as n/a in the table" "| privacy pages | n/a | n/a |" "$out6"

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

# Case 7, MUTATION PROOF built here: a renderer that
# DROPS a row from the table (the line that prints a gate's row is removed) must
# not satisfy the declared-order case. Without this the table cases could pass
# against a renderer that prints no rows at all.
mkdir -p "${TMP}/mutant/Scripts"
sed "/mark\" \\]/s/.*/    continue/" "$RENDER" > "${TMP}/mutant/Scripts/render_quality_report.sh"
if cmp -s "$RENDER" "${TMP}/mutant/Scripts/render_quality_report.sh"; then
  fail "the drop-a-row mutation changed nothing — case 7 is matching a line that is not in the renderer"
else
  chmod +x "${TMP}/mutant/Scripts/render_quality_report.sh"
  out7="$("${TMP}/mutant/Scripts/render_quality_report.sh" "$rows2" "$details2" "$order2" 2>&1)" || true
  table7="$(grep -oE '^\| [a-z]+' <<< "$out7" | tr -d '| ' | tr '\n' ' ' || true)"
  if [ "$table7" = "alpha beta gamma " ]; then
    fail "a renderer that drops every row still satisfies the declared-order case — the table cases prove nothing"
  else
    echo "  ok: a renderer that drops a row fails the declared-order case (table: '${table7}')"
  fi
fi

# Cases 8-12 (forsgren#219): the Checks column, the plain gate labels, and the CONTRIBUTING.md list kept in sync with the order file.
#
# Case 8: Checks counts the gate's own `ok:` and `✅` lines. The heading line
# the runner writes ("#### ✅ label"), prose that merely contains ok: and the
# uppercase verdict OK: are not checks. No countable line is `not counted`,
# never 0; a reported gate with no details file is `not readable`.
order8="${TMP}/order8"
{
  echo "counted gate|Scripts/a.sh|pre|"
  echo "silent gate|Scripts/b.sh|pre|"
  echo "lost gate|Scripts/c.sh|pre|"
  echo "Go test coverage (90)|Scripts/d.sh|post|"
  echo "privacy pages|n/a|nothing is collected here"
} > "$order8"
rows8="${TMP}/rows8"; printf 'counted gate|✅\nsilent gate|✅\nlost gate|❌\nGo test coverage (90)|✅\n' > "$rows8"
details8="${TMP}/details8"; mkdir -p "$details8"
{
  echo ""; echo "#### ✅ counted gate"; echo ""; echo '```'
  echo "  ok: first"; echo "ok: second"; echo "✅ third"; echo "this line says ok: but is prose"; echo "OK: the verdict is not a check"
  echo '```'
} > "${details8}/counted_gate.md"
{ echo ""; echo "#### ✅ silent gate"; echo ""; echo "_no output_"; } > "${details8}/silent_gate.md"
{ echo ""; echo "#### ✅ Go test coverage (90)"; echo ""; echo '```'; echo "ok: one"; echo '```'; } > "${details8}/Go_test_coverage__90_.md"
out8="$("$RENDER" "$rows8" "$details8" "$order8" 2>&1)" || true
want     "Checks counts the ok: and check-mark lines of the gate's output" "| counted gate | 3 | ✅ |" "$out8"
want     "a gate with no countable line says not counted"                  "| silent gate | not counted | ✅ |" "$out8"
want_not "and never shows 0 for it"                                        "| 0 |" "$out8"
want     "a reported gate whose details cannot be read says not readable"  "| lost gate | not readable | ❌ |" "$out8"
want     "the table has the Checks column"                                 "| Gate | Checks | Result |" "$out8"
want     "the table's rule line is the three-column rule"                  "|---|--:|:-:|" "$out8"

# Case 9 (forsgren#219): GitHub keeps neither an in-page link nor an explicit
# <a id> in a job summary (a real run showed the labels as links that do
# nothing), so the Gate cell is the plain label and the output holds no anchor
# line. A gate with a details section, a gate without one and a label with
# spaces and punctuation are all plain.
linked_rows() { grep -E '^\|.*\]\(#' <<< "$1" || true; }
anchor_lines() { grep -F '<a id=' <<< "$1" || true; }
want     "a gate with a section is its plain label"                    "| Go test coverage (90) | 1 | ✅ |" "$out8"
want     "a gate without a section is its plain label"                 "| lost gate | not readable | ❌ |" "$out8"
want_not "the details section of a green gate is left out (v3)"        "#### ✅ counted gate" "$out8"
rows_linked="$(linked_rows "$out8")"
if [ -z "$rows_linked" ]; then echo "  ok: no table row links to an in-page anchor"; else fail "a table row still links a label: ${rows_linked}"; fi
anchors_found="$(anchor_lines "$out8")"
if [ -z "$anchors_found" ]; then echo "  ok: the output holds no <a id= line"; else fail "the output still holds an anchor line: ${anchors_found}"; fi

# Case 10: the CONTRIBUTING.md list is the generator's output for the real
# order file, between the two markers.
GL="./Scripts/render_gate_list.sh"
gl_order="${TMP}/gl_order"
{ echo "# c"; echo "alpha|Scripts/a.sh|pre|"; echo "na gate|n/a|reason"; echo "beta|Scripts/b.sh|post|secret-class"; } > "$gl_order"
gl_out="$("$GL" "$gl_order" 2>&1)" || fail "the list generator exited non-zero on a plain order file"
bt="$(printf '\140')"
want     "the list names a gate, its script and its phase" "- alpha (${bt}Scripts/a.sh${bt}, pre)" "$gl_out"
want     "and the next gate in declared order"              "- beta (${bt}Scripts/b.sh${bt}, post)" "$gl_out"
want_not "an n/a row is not listed"                        "na gate" "$gl_out"
want_not "a comment is not listed"                         "# c" "$gl_out"
expected_list="$(./Scripts/render_gate_list.sh)" || fail "the list generator failed on the shipped order file"
actual_list="$(awk '/<!-- gate-list:start -->/{f=1; next} /<!-- gate-list:end -->/{f=0} f' CONTRIBUTING.md | sed '/^$/d')"
if [ -n "$expected_list" ] && [ "$expected_list" = "$actual_list" ]; then
  echo "  ok: CONTRIBUTING.md lists exactly the gates of the order file"
else
  fail "the list between the gate-list markers of CONTRIBUTING.md differs from ./Scripts/render_gate_list.sh — paste its output between the markers"
fi

# Case 11, MUTATION PROOFS (forsgren#219), each judged by the case it is aimed at.
mutate() { # <name> <sed-expr>
  local dir="${TMP}/mut_$1"
  mkdir -p "${dir}/Scripts"
  sed "$2" "$RENDER" > "${dir}/Scripts/render_quality_report.sh"
  if cmp -s "$RENDER" "${dir}/Scripts/render_quality_report.sh"; then
    fail "mutation $1 changed nothing — its sed expression matches no line of the renderer"
    return 1
  fi
  chmod +x "${dir}/Scripts/render_quality_report.sh"
  mut_out="$("${dir}/Scripts/render_quality_report.sh" "$rows8" "$details8" "$order8" 2>&1)" || true
}
if mutate zero 's/checks="not counted"/checks="0"/'; then
  if grep -qF -- "| silent gate | not counted | ✅ |" <<< "$mut_out"; then fail "a renderer that shows 0 for a gate with no countable line still satisfies case 8"; else echo "  ok: a gate with no countable line rendered as 0 is caught"; fi
fi
dl="$(printf '\044')"
if mutate link "s#echo \"| ${dl}{[a-z]*} | ${dl}{checks}#echo \"| [${dl}{label}](\#gate-${dl}{slug}) | ${dl}{checks}#"; then
  mut_linked="$(linked_rows "$mut_out")"
  if grep -qF -- "[counted gate](#gate-counted_gate)" <<< "$mut_linked"; then echo "  ok: a renderer that still links a label is caught, naming: counted gate"; else fail "a renderer that links the labels still satisfies case 9 (rows seen: ${mut_linked:-none})"; fi
fi
if mutate unreadable 's/checks="not readable"/checks="not counted"/'; then
  if grep -qF -- "| lost gate | not readable | ❌ |" <<< "$mut_out"; then fail "a renderer that calls an unreadable gate not counted still satisfies case 8"; else echo "  ok: an unreadable gate rendered as not counted is caught"; fi
fi
if mutate verdict "s/ok:|✅/ok:|✅|OK:/"; then
  if grep -qF -- "| counted gate | 3 | ✅ |" <<< "$mut_out"; then fail "a renderer that counts OK: verdict lines still satisfies case 8"; else echo "  ok: a renderer counting the verdict line is caught"; fi
fi

# Case 13 (v3): the page shows the table, then the details of
# the gates that are NOT green only. A green gate's output (thousands of lines
# on a real run) stays in the job log. A run with one green and one red gate
# renders the red gate's details and none of the green gate's.
order13="${TMP}/order13"
{ echo "green gate|Scripts/a.sh|pre|"; echo "red gate|Scripts/b.sh|pre|"; } > "$order13"
rows13="${TMP}/rows13"; printf 'green gate|✅\nred gate|❌\n' > "$rows13"
details13="${TMP}/details13"; mkdir -p "$details13"
{ echo ""; echo "#### ✅ green gate"; echo ""; echo '```'; echo "ok: green gate output line"; echo '```'; } > "${details13}/green_gate.md"
{ echo ""; echo "#### ❌ red gate"; echo ""; echo '```'; echo "ok: red gate passing line"; echo "❌ FAIL: red gate reason"; echo '```'; } > "${details13}/red_gate.md"
out13="$("$RENDER" "$rows13" "$details13" "$order13" 2>&1)" || true
want     "the table still lists the green gate, with its count"  "| green gate | 1 | ✅ |" "$out13"
want     "and the red gate"                                       "| red gate | 1 | ❌ |" "$out13"
want     "the red gate's details are shown"                       "#### ❌ red gate" "$out13"
want     "with its reason"                                        "❌ FAIL: red gate reason" "$out13"
want_not "the green gate's details are left out"                  "green gate output line" "$out13"
want_not "and its heading"                                        "#### ✅ green gate" "$out13"

# A green run ends after the table: no details at all.
rows13g="${TMP}/rows13g"; printf 'green gate|✅\n' > "$rows13g"
details13g="${TMP}/details13g"; mkdir -p "$details13g"; cp "${details13}/green_gate.md" "$details13g/"
out13g="$("$RENDER" "$rows13g" "$details13g" "$order13" 2>&1)" || true
want_not "a run with only green gates has no details section"     "####" "$out13g"

# Case 14, MUTATION PROOF: a renderer that prints every gate's details is caught,
# and the failure names the green gate.
mut14="${TMP}/mut_all/Scripts"; mkdir -p "$mut14"
sed 's/\[ "[$]mark" != "✅" \] && //' "$RENDER" > "${mut14}/render_quality_report.sh"
if cmp -s "$RENDER" "${mut14}/render_quality_report.sh"; then
  fail "the print-every-gate mutation changed nothing — case 14 matches a line that is not in the renderer"
else
  chmod +x "${mut14}/render_quality_report.sh"
  out14="$("${mut14}/render_quality_report.sh" "$rows13" "$details13" "$order13" 2>&1)" || true
  if grep -qF -- "#### ✅ green gate" <<< "$out14"; then
    echo "  ok: a renderer that prints every gate's details is caught, naming: green gate"
  else
    fail "a renderer that prints every gate's details still satisfies case 13 (the green gate's details are not in its output)"
  fi
fi

COMPLETED=1
if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: quality-report render pins"
  exit 1
fi
echo "OK: quality-report render (exit status survives a detail-less trailing row, declared order honoured, empty and partial runs told apart from clean, Checks counted from the gates output, plain gate labels without links or anchors, CONTRIBUTING list in sync)"
