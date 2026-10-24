#!/usr/bin/env bash
# canon: gate_browser v3
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
# Scripts/browser_gate_exceptions.txt, Scripts/browser_gate_baseline.txt (the
# shrink-only baseline of estate issue 305) and Scripts/browser_gate_variants.txt
# (the looks of the site, each checked on its own). A missing file is exit 2, never a
# guess. Chrome is the one installed (FORSGREN_CHROME names another); none is
# exit 2.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT_FILE="$(mktemp)"
FIFO_DIR="$(mktemp -d)"
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
BASELINE="${4:-Scripts/browser_gate_baseline.txt}"
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
  exit "$rc"
fi
COMPLETED=1
