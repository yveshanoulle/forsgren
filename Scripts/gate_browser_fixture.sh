#!/usr/bin/env bash
# Scripts/gate_browser_fixture.sh (forsgren#226). Not canon: forsgren only.
#
# The browser gate (Scripts/gate_browser.sh, the sites' shared canon) opens the
# site the build renders, and that build has no config or history: its History
# page shows only "No history to show yet" and its Daily and Issues pages no
# rows, so their tables and charts were never opened by axe. This gate runs the
# same engine, Scripts/browser_gate.mjs, on the site rendered from the made-up
# fixture of Scripts/testdata/fixture_site (Scripts/build_fixture_site.sh,
# built into a temporary directory): the same checks (axe serious and critical,
# doctype, charset, console errors, failed requests, CLS exactly 0), the same
# manifest, exceptions and variants, and its own shrink-only baseline,
# Scripts/browser_gate_fixture_baseline.txt (only a ruling adds a row: today the
# sideways rows of decision #364, forsgren#350).
# Self-test: Scripts/test_gate_browser_fixture.sh.
#
# axe-core is an automated accessibility gate, not proof of complete WCAG
# compliance.
#
# Usage: gate_browser_fixture.sh [site-dir [manifest [exceptions [baseline [variants]]]]]
# Without site-dir the fixture site is built; site-dir names an already built one
# (the self-test). A missing file is exit 2, never a guess; so is a fixture site
# that cannot be built, no Chrome and no node_modules.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT_FILE="$(mktemp)"
BUILT_SITE=""
# On bash 3.2 an abort ends a script with an EXIT trap with status 0. COMPLETED,
# set as the very last statement, is the only way out with 0 (forsgren#137).
COMPLETED=0
finish() {
  local rc=$?
  rm -f "$OUT_FILE"
  if [[ -n "$BUILT_SITE" ]]; then rm -rf "$BUILT_SITE"; fi
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: gate_browser_fixture.sh aborted before completing (COMPLETED was never set)" >&2
    exit 1
  fi
}
trap finish EXIT

# shellcheck source=Scripts/lib_site_settings.sh
source Scripts/lib_site_settings.sh
SITE_DIR="${1:-}"
MANIFEST="${2:-}"
if [[ -z "$MANIFEST" ]]; then
  MANIFEST="$(site_settings_get Scripts/site_settings.txt required_pages_manifest)" || exit 2
fi
EXCEPTIONS="${3:-Scripts/browser_gate_exceptions.txt}"
BASELINE="${4:-Scripts/browser_gate_fixture_baseline.txt}"
VARIANTS="${5:-Scripts/browser_gate_variants.txt}"

if ! command -v node >/dev/null 2>&1; then
  echo "browser gate (fixture site): node not found" >&2
  exit 2
fi
if [[ ! -d node_modules/puppeteer-core || ! -d node_modules/axe-core ]]; then
  echo "browser gate (fixture site): puppeteer-core or axe-core missing from node_modules (npm ci)" >&2
  exit 2
fi

if [[ -z "$SITE_DIR" ]]; then
  BUILT_SITE="$(mktemp -d)"
  if ! Scripts/build_fixture_site.sh "$BUILT_SITE" > "$OUT_FILE" 2>&1; then
    cat "$OUT_FILE" >&2
    echo "browser gate (fixture site): the fixture site could not be built" >&2
    exit 2
  fi
  SITE_DIR="$BUILT_SITE"
fi

echo "browser gate: the site rendered from fixture data (forsgren#226)"
set +e
node Scripts/browser_gate.mjs "$SITE_DIR" "$MANIFEST" "$EXCEPTIONS" "$BASELINE" "$VARIANTS" 2>&1 | tee "$OUT_FILE"
rc=${PIPESTATUS[0]}
set -e

if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi
COMPLETED=1
