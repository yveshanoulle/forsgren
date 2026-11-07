#!/usr/bin/env bash
# canon: gate_browser v5 + forsgren#642 (the default baseline per platform, Scripts/lib_browser_baseline.sh)
# v5 (estate issue 629, step 2): a non-zero end always names its reason: an engine killed by a signal, or one that ended with no FAIL line, gets one from the wrapper; the engine (browser_gate v16) flushes its output before it exits
# v4 merges the two lines of the canon (estate issue 629): v3 (the exit-trap idiom of forsgren#381, temp names through lib_tmp.sh) and the sites' v2 (the same idiom as the local fix of site issue 34, with plain mktemp); the wrapper is v3 as it was
# Scripts/gate_browser.sh (forsgren#205)
#
# The browser gate (POST): serves the built site on 127.0.0.1 and opens every
# page of the required-pages manifest in the installed Chrome; the checks are
# in Scripts/browser_gate.mjs and are listed in its header. Self-test:
# Scripts/test_gate_browser.sh.
#
# axe-core is an automated accessibility gate, not proof of complete WCAG
# compliance.
#
# Usage: gate_browser.sh [site-dir [manifest [exceptions [baseline [variants]]]]]
# Defaults: site_dir and required_pages_manifest of Scripts/site_settings.txt,
# Scripts/browser_gate_exceptions.txt, the shrink-only baseline of estate issue
# 305 of this platform (forsgren#642: Scripts/browser_gate_baseline.txt on
# macOS, Scripts/browser_gate_baseline_linux.txt on Linux, any other platform
# exit 2; fonts render differently, so the widths differ) and Scripts/browser_gate_variants.txt
# (the looks of the site, each checked on its own). A missing file is exit 2, never a
# guess. Chrome is the one installed (FORSGREN_CHROME names another); none is
# exit 2.

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_tmp.sh
source Scripts/lib_tmp.sh
OUT_FILE="$(tmp_file gate_browser_out_file)"
FIFO_DIR="$(tmp_dir gate_browser_fifo_dir)"
NODE_PID=""
# On bash 3.2 an abort (an unbound variable under set -eu) ends a script with
# an EXIT trap with status 0. COMPLETED, set as the very last statement, is the
# only way out with 0: an exit of 0 without it is an abort and becomes exit 1.
COMPLETED=0
finish() {
  local rc=$?
  rm -f "$OUT_FILE"
  rm -rf "$FIFO_DIR"
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: gate_browser.sh aborted before completing (COMPLETED was never set)" >&2
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
if [[ -z "$SITE_DIR" ]]; then
  SITE_DIR="$(site_settings_get Scripts/site_settings.txt site_dir)" || exit 2
fi
MANIFEST="${2:-}"
if [[ -z "$MANIFEST" ]]; then
  MANIFEST="$(site_settings_get Scripts/site_settings.txt required_pages_manifest)" || exit 2
fi
EXCEPTIONS="${3:-Scripts/browser_gate_exceptions.txt}"
# shellcheck source=Scripts/lib_browser_baseline.sh
source Scripts/lib_browser_baseline.sh
BASELINE="${4:-}"
if [[ -z "$BASELINE" ]]; then
  BASELINE="$(browser_baseline Scripts/browser_gate_baseline.txt Scripts/browser_gate_baseline_linux.txt)" || exit 2
fi
VARIANTS="${5:-Scripts/browser_gate_variants.txt}"

if ! command -v node >/dev/null 2>&1; then
  echo "browser gate: node not found" >&2
  exit 2
fi
if [[ ! -d node_modules/puppeteer-core || ! -d node_modules/axe-core ]]; then
  echo "browser gate: puppeteer-core or axe-core missing from node_modules (npm ci)" >&2
  exit 2
fi

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
  # A gate that ends non-zero always says why (estate issue 629, step 2). The
  # engine names its own reasons; one that was killed, or ended with nothing
  # the gate can recognise as a reason, is named here.
  if [[ "$rc" -gt 128 ]]; then
    echo "FAIL: browser gate: the engine was killed by signal $(kill -l "$((rc - 128))" 2>/dev/null || echo "$((rc - 128))") (exit ${rc}); it printed no reason" >&2
  elif ! grep -Eq '^(FAIL: |browser-gate: |browser gate: )' "$OUT_FILE"; then
    echo "FAIL: browser gate: the engine ended with exit ${rc} and printed no reason" >&2
  fi
  exit "$rc"
fi
COMPLETED=1
