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
# manifest, exceptions and variants, and its own shrink-only baseline of this
# platform, Scripts/browser_gate_fixture_baseline.txt on macOS (only a ruling adds
# a row: today the sideways rows of decision #364, forsgren#350) and
# Scripts/browser_gate_fixture_baseline_linux.txt on Linux (forsgren#642: fonts
# render differently, so the widths differ; any other platform is exit 2).
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

# shellcheck source=Scripts/lib_tmp.sh
source Scripts/lib_tmp.sh
OUT_FILE="$(tmp_file gate_browser_fixture_out_file)"
FIFO_DIR="$(tmp_dir gate_browser_fixture_fifo_dir)"
NODE_PID=""
BUILT_SITE=""
# On bash 3.2 an abort ends a script with an EXIT trap with status 0. COMPLETED,
# set as the very last statement, is the only way out with 0 (forsgren#137).
COMPLETED=0
finish() {
  local rc=$?
  rm -f "$OUT_FILE"
  rm -rf "$FIFO_DIR"
  if [[ -n "$BUILT_SITE" ]]; then rm -rf "$BUILT_SITE"; fi
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: gate_browser_fixture.sh aborted before completing (COMPLETED was never set)" >&2
    exit 1
  fi
}
trap finish EXIT

# A signal to this script goes to node, which closes Chrome and removes its
# profile folder (forsgren#381); this script waits for it, then ends with 128
# plus the signal number. Without that a killed wrapper leaves node and its
# Chrome running.
forward_signal() {
  local name="$1" code="$2"
  if [[ -n "$NODE_PID" ]]; then
    kill -s "$name" "$NODE_PID" 2>/dev/null || true
    wait "$NODE_PID" 2>/dev/null || true
  fi
  exit "$code"
}
trap 'forward_signal INT 130' INT
trap 'forward_signal TERM 143' TERM
trap 'forward_signal HUP 129' HUP

# shellcheck source=Scripts/lib_site_settings.sh
source Scripts/lib_site_settings.sh
SITE_DIR="${1:-}"
MANIFEST="${2:-}"
if [[ -z "$MANIFEST" ]]; then
  MANIFEST="$(site_settings_get Scripts/site_settings.txt required_pages_manifest)" || exit 2
fi
EXCEPTIONS="${3:-Scripts/browser_gate_exceptions.txt}"
# shellcheck source=Scripts/lib_browser_baseline.sh
source Scripts/lib_browser_baseline.sh
BASELINE="${4:-}"
if [[ -z "$BASELINE" ]]; then
  BASELINE="$(browser_baseline Scripts/browser_gate_fixture_baseline.txt Scripts/browser_gate_fixture_baseline_linux.txt)" || exit 2
fi
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
  BUILT_SITE="$(tmp_dir gate_browser_fixture_built_site)"
  if ! Scripts/build_fixture_site.sh "$BUILT_SITE" > "$OUT_FILE" 2>&1; then
    cat "$OUT_FILE" >&2
    echo "browser gate (fixture site): the fixture site could not be built" >&2
    exit 2
  fi
  SITE_DIR="$BUILT_SITE"
fi

echo "browser gate: the site rendered from fixture data (forsgren#226)"
# node runs in the background, its output through a fifo to tee, so that a
# signal reaches this script's traps while it waits.
mkfifo "$FIFO_DIR/out"
tee "$OUT_FILE" < "$FIFO_DIR/out" &
TEE_PID=$!
node Scripts/browser_gate.mjs "$SITE_DIR" "$MANIFEST" "$EXCEPTIONS" "$BASELINE" "$VARIANTS" > "$FIFO_DIR/out" 2>&1 &
NODE_PID=$!
set +e
wait "$NODE_PID"
rc=$?
wait "$TEE_PID"
set -e

if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi
# An exit of 0 is a pass only with the engine's OK line, exactly once, naming
# at least one page, one variant and pages x variants checks (site issue 94,
# forsgren#674): an engine that ended 0 without it, with 0 of any, or with a
# page or a variant skipped, proved nothing checked.
OK_SHAPE='^OK: browser gate: ([1-9][0-9]*) pages x ([1-9][0-9]*) variants .*, ([1-9][0-9]*) checks, '
OK_COUNT="$(grep -c '^OK: browser gate: ' "$OUT_FILE" || true)"
OK_LINE="$(grep '^OK: browser gate: ' "$OUT_FILE" || true)"
if [[ "$OK_COUNT" -ne 1 ]] || ! [[ "$OK_LINE" =~ $OK_SHAPE ]] || [[ "${BASH_REMATCH[3]}" -ne $((BASH_REMATCH[1] * BASH_REMATCH[2])) ]]; then
  echo "FAIL: browser gate (fixture site): the engine ended with exit 0 but printed no OK line naming at least one page, one variant and one check, pages x variants checks, exactly once (${OK_COUNT} OK lines${OK_LINE:+: ${OK_LINE%%, axe*}}); nothing is proven checked" >&2
  exit 2
fi
COMPLETED=1
