#!/usr/bin/env bash
# Scripts/test_gate_browser_fixture_default.sh (forsgren#626, step 2). Not canon: forsgren only.
#
# Self-test of the default-mode fixture variant of the TBD page
# (Scripts/gate_browser_fixture_default.sh): the fixture site sets tbd_figures: all,
# so the default layout was never gated; "the default TBD table must not grow
# horizontally" is checked for the default too. Real Chrome and axe-core, the real
# fixture site built from Scripts/testdata/fixture_site_default, never a fake.
#   1. the variant's config is the fixture's config without tbd_figures, and its
#      data is the fixture's data
#   2. the default TBD page with the variant's baseline -> green
#   3. the variant's baseline rows one pixel too small (the page grew) -> red at
#      1280x800 and at 390x844, naming the TBD page
#   4. the variant's rows cover /tbd.html only, at both widths
#   5. the same page rendered with tbd_figures: all is wider than the default
#      baseline -> red (the check sees the layout of the config it is given)
#
# Runs in CI from the repository's validate workflow.
# Local invocation: ./Scripts/test_gate_browser_fixture_default.sh

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
GATE="${REPO_ROOT}/Scripts/gate_browser_fixture_default.sh"
ENGINE="${REPO_ROOT}/Scripts/browser_gate.mjs"
VARIANT="Scripts/testdata/fixture_site_default"
BASELINE="Scripts/browser_gate_fixture_default_baseline.txt"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_gate_browser_selftest.sh
source Scripts/lib_gate_browser_selftest.sh
selftest_begin "browser gate (default fixture variant) self-test"

browser_selftest_require "$GATE" "$ENGINE" \
  "${REPO_ROOT}/node_modules/puppeteer-core" "${REPO_ROOT}/node_modules/axe-core"

# 1: the variant is the fixture without tbd_figures, on the same data.
if [[ -f "${VARIANT}/forsgren.config.yml" ]] \
  && ! grep -q '^tbd_figures' "${VARIANT}/forsgren.config.yml" \
  && diff <(grep -v '^tbd_figures' Scripts/testdata/fixture_site/forsgren.config.yml) "${VARIANT}/forsgren.config.yml" > /dev/null \
  && cmp -s Scripts/testdata/fixture_site/data/deployments.csv "${VARIANT}/data/deployments.csv"; then
  echo "  ok: 1: the variant is the fixture's config without tbd_figures, on the fixture's data"
else
  fail "1: ${VARIANT} is not the fixture's config without tbd_figures on the fixture's data"
fi

# 4: the variant's baseline holds /tbd.html rows only, one per width.
ROWS="$(grep -v '^#' "$BASELINE" 2>/dev/null | cut -d'|' -f1-4 | tr '\n' ' ' || true)"
if [[ "$ROWS" == "sideways|light|/tbd.html|1280x800 sideways|light|/tbd.html|390x844 " ]]; then
  echo "  ok: 4: the variant's baseline has the /tbd.html rows at both widths and no other"
else
  fail "4: the variant's baseline rows are \"${ROWS}\""
fi

# build <name> <fixture dir>: the fixture site of that dir.
build() {
  FORSGREN_FIXTURE_DIR="$2" Scripts/build_fixture_site.sh "${TMP}/$1" > "${TMP}/$1.log" 2>&1 \
    || fail "the site ${1} could not be built: $(cat "${TMP}/$1.log")"
}
# run_gate <site> <baseline>: the variant's gate on a built site.
run_gate() {
  FORSGREN_CLS_LOADS=1 FORSGREN_CLS_INTERVAL_MS=300 capture "$GATE" "$1" "$2"
}

build default "$VARIANT"
run_gate "${TMP}/default" "$BASELINE"
want_green "2: the default TBD page against the variant's baseline" "OK: browser gate: 1 pages x 1 variants (light)"

# 3: the rows one pixel too small -> the page "grew".
awk -F'|' 'BEGIN { OFS = "|" } /^#/ { next } { $6 = $6 - 1; print }' "$BASELINE" > "${TMP}/small.txt"
run_gate "${TMP}/default" "${TMP}/small.txt"
want_red "3: the default TBD table grown by a pixel at the laptop width" "FAIL: light /tbd.html: scrolls sideways at 1280x800"
want_said "3b: and at the phone width" "FAIL: light /tbd.html: scrolls sideways at 390x844"

# 5: the same fixture with tbd_figures: all is wider than the default baseline.
mkdir -p "${TMP}/allfixture"
cp "${VARIANT}/forsgren.config.yml" "${TMP}/allfixture/forsgren.config.yml"
printf 'tbd_figures: all\n' >> "${TMP}/allfixture/forsgren.config.yml"
ln -s "${REPO_ROOT}/Scripts/testdata/fixture_site/data" "${TMP}/allfixture/data"
build allsite "${TMP}/allfixture"
run_gate "${TMP}/allsite" "$BASELINE"
want_red "5: tbd_figures: all is wider than the default baseline" "FAIL: light /tbd.html: scrolls sideways at 390x844"

selftest_end "the browser gate (default fixture variant) self-test failed" "browser gate (default fixture variant): the default TBD table is gated at both widths and a grown table is red"
