#!/usr/bin/env bash
# Scripts/test_gate_browser_tbd_tables.sh (forsgren#626, step 1). Not canon: forsgren only.
#
# Self-test that the browser gate measures the TBD page's two tables each on its
# own, with the gate as it is (Scripts/browser_gate.mjs is not changed): the page
# has "table 1", the TBD table, and "table 2", the Integration table (decision
# #623, C), and an overflow of table 2 is red, at 1280x800 and at 390x844, named
# "table 2", whatever table 1 does. The real Chrome and the real axe-core, a
# fixture site on 127.0.0.1, never a fake. The page here has the shape of the
# TBD page: two tables, each in its own scroll box.
#   1. both tables fit                       -> green
#   2. table 2 wider than its box at both widths, table 1 fits
#                                            -> red at 1280x800 and at 390x844,
#                                               naming table 2 and never table 1
#   3. table 2 wider than its box at the phone width only
#                                            -> red at 390x844 only, naming table 2
#   4. table 1 wider than its box, table 2 fits
#                                            -> red naming table 1 and never table 2
#   5. the fixture page really has two tables, each in a scroll box
# Mutation proofs (each case is red BECAUSE of the line mutated):
#   A. the sideways check removed: case 2 turns green;
#   B. every table numbered 1 (table 2 not told apart): case 2 no longer names table 2.
#
# Runs in CI from the repository's validate workflow.
# Local invocation: ./Scripts/test_gate_browser_tbd_tables.sh

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
GATE="${REPO_ROOT}/Scripts/gate_browser.sh"
ENGINE="${REPO_ROOT}/Scripts/browser_gate.mjs"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_gate_browser_selftest.sh
source Scripts/lib_gate_browser_selftest.sh
selftest_begin "browser gate (TBD tables) self-test"

browser_selftest_require "$GATE" "$ENGINE" \
  "${REPO_ROOT}/node_modules/puppeteer-core" "${REPO_ROOT}/node_modules/axe-core"

# box <label> <id> <width>: one table in its own scroll box.
box() {
  printf '<div style="overflow-x: auto" role="region" aria-label="%s" tabindex="0"><table id="%s" style="width: %spx"><tr><th scope="col">%s</th></tr></table></div>' "$1" "$2" "$3" "$1"
}
# tbd_page <width of table 1> <width of table 2>: the TBD page's shape, two
# tables in two scroll boxes. The body has no margin, so an overflow is the
# table's width less the window's: 1500 - 1280 = 220 px, 1500 - 390 = 1110 px.
tbd_page() {
  page "$(box 'TBD table' tbd "$1")$(box 'Integration table' integration "$2")" '<style>body { margin: 0; }</style>'
}

run_gate() {
  FORSGREN_CLS_LOADS=1 FORSGREN_CLS_INTERVAL_MS=300 capture "$GATE" "${TMP}/$1/site" "${TMP}/$1/manifest.json" "${TMP}/$1/exceptions.txt" "${TMP}/$1/baseline.txt" "${TMP}/$1/variants.txt"
}
# run_engine <engine> <fixture>: a mutated engine copy on that fixture.
run_engine() {
  FORSGREN_NODE_ROOT="$REPO_ROOT" FORSGREN_CLS_LOADS=1 FORSGREN_CLS_INTERVAL_MS=300 capture node "$1" "${TMP}/$2/site" "${TMP}/$2/manifest.json" "${TMP}/$2/exceptions.txt" "${TMP}/$2/baseline.txt" "${TMP}/$2/variants.txt"
}
# never_said <name> <text>: the output of the last run does not contain the text.
never_said() {
  if grep -qF -- "$2" <<< "$OUT"; then
    fail "$1: the output has \"$2\". Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

make_site fits "$(tbd_page 300 300)"
make_site t2both "$(tbd_page 300 1500)"
make_site t2phone "$(tbd_page 300 600)"
make_site t1only "$(tbd_page 1500 300)"

# 5: the fixture page has two tables, each in a scroll box, the TBD one first.
PAGE_HTML="$(cat "${TMP}/t2both/site/index.html")"
TABLES="$(grep -o '<table ' <<< "$PAGE_HTML" | wc -l | tr -d ' ')"
BOXES="$(grep -o 'overflow-x: auto' <<< "$PAGE_HTML" | wc -l | tr -d ' ')"
if [[ "$TABLES" == 2 && "$BOXES" == 2 ]] && grep -q 'id="tbd".*id="integration"' <<< "$PAGE_HTML"; then
  echo "  ok: 5: the page has two tables, the TBD table first and the Integration table second, each in a scroll box"
else
  fail "5: the fixture page does not have the two tables (tables ${TABLES}, boxes ${BOXES})"
fi

run_gate fits
want_green "1: both tables fit" "no new sideways scroll at 1280x800 and 390x844 (0 baselined)"

run_gate t2both
want_red "2: table 2 wider than its box at the laptop width" "FAIL: light /: scrolls sideways at 1280x800: table 2 is 220 px wider than its box"
want_said "2b: and at the phone width" "FAIL: light /: scrolls sideways at 390x844: table 2 is 1110 px wider than its box"
never_said "2c: table 1, which fits, is never blamed" "table 1 is"

run_gate t2phone
want_red "3: table 2 wider than its box at the phone width" "FAIL: light /: scrolls sideways at 390x844: table 2 is 210 px wider than its box"
never_said "3b: the laptop width is clean" "at 1280x800"

run_gate t1only
want_red "4: table 1 wider than its box" "FAIL: light /: scrolls sideways at 390x844: table 1 is"
never_said "4b: table 2, which fits, is never blamed" "table 2 is"

# Mutation proofs: the engine copied, one line changed.
MUTANT="${TMP}/engine.mjs"

# A: the sideways check removed -> case 2 turns green.
if selftest_mutant "$ENGINE" "$MUTANT" "s/^    await check.checkSideways();/    \/\/ removed/"; then
  run_engine "$MUTANT" t2both
  want_green "mutation proof A: without the sideways check case 2 turns green" "OK:"
fi

# B: every table named table 1 -> table 2's overflow is no longer told apart.
# shellcheck disable=SC2016 # a sed expression: the backticks and ${} are the engine's text
if selftest_mutant "$ENGINE" "$MUTANT" 's/`table ${index + 1}`/`table 1`/'; then
  run_engine "$MUTANT" t2both
  never_said "mutation proof B: without the table number case 2 never names table 2" "table 2 is"
fi

selftest_end "the browser gate (TBD tables) self-test failed" "browser gate (TBD tables): table 2's overflow is red on its own at both widths, two mutations seen"
