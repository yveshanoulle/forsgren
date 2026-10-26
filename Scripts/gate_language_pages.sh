#!/usr/bin/env bash
# Scripts/gate_language_pages.sh (forsgren#220)
#
# The language gate over every page forsgren ships: the generated metrics site
# (.build/site) and the starter page (.build/starter, forsgren#132). The canon
# gate, Scripts/gate_language.sh, checks one directory, and a row of the order
# file names a script, not a command line, so this wrapper puts both in one
# temporary directory (the starter page as starter/index.html) and runs the
# gate on it. One run, one baseline, one report: a finding on the starter page
# is keyed by the page starter/index.html. The exit status and the output are
# the gate's own.
#
# The built site renders the TBD page with the median only (the default), so
# the all-figures table, with its own header aria-labels, was never read
# (forsgren#452). The golden page of that table (internal/page/testdata, pinned
# byte for byte to what forsgren renders with tbd_figures: all) goes in too, as
# golden/tbd.all.html: no extra build, so no change of the order of the gates.
#
# Usage: Scripts/gate_language_pages.sh [site-dir [starter-dir [golden-page]]]
#        (default: .build/site, .build/starter and
#        internal/page/testdata/tbd.all.golden.html)
# Fixture: Scripts/test_gate_language_pages.sh.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

SITE="${1:-.build/site}"
STARTER="${2:-.build/starter}"
GOLDEN="${3:-internal/page/testdata/tbd.all.golden.html}"

PAGES="$(mktemp -d)"
# On bash 3.2 an abort (an unbound variable under set -eu) ends a script with
# an EXIT trap with status 0. COMPLETED, set as the very last statement, is the
# only way out with 0: an exit of 0 without it is an abort and becomes exit 1.
COMPLETED=0
finish() {
  local rc=$?
  rm -rf "$PAGES"
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: gate_language_pages.sh aborted before completing (COMPLETED was never set)" >&2
    exit 1
  fi
}
trap finish EXIT

[[ -d "$SITE" ]] || { echo "❌ language gate: site dir not found: ${SITE}" >&2; exit 2; }
[[ -f "${STARTER}/index.html" ]] || { echo "❌ language gate: starter page not found: ${STARTER}/index.html" >&2; exit 2; }
[[ -f "$GOLDEN" ]] || { echo "❌ language gate: all-figures TBD golden page not found: ${GOLDEN}" >&2; exit 2; }

cp -R "${SITE}/." "$PAGES/"
mkdir -p "${PAGES}/starter"
cp "${STARTER}/index.html" "${PAGES}/starter/index.html"
mkdir -p "${PAGES}/golden"
cp "$GOLDEN" "${PAGES}/golden/tbd.all.html"

# GATE_LANGUAGE_PAGES_GATE is the testing seam: the self-test points it at a
# stub that records the directory it is given.
set +e
if [[ -n "${GATE_LANGUAGE_PAGES_GATE:-}" ]]; then
  "$GATE_LANGUAGE_PAGES_GATE" "$PAGES"
else
  ./Scripts/gate_language.sh "$PAGES"
fi
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi
COMPLETED=1
