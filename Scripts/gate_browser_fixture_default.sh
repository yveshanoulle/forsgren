#!/usr/bin/env bash
# Scripts/gate_browser_fixture_default.sh (forsgren#626). Not canon: forsgren only.
#
# The fixture browser gate (Scripts/gate_browser_fixture.sh) renders the fixture site
# with tbd_figures: all, so the TBD page's default layout was never gated. This runs
# the same gate on the TBD page rendered from Scripts/testdata/fixture_site_default,
# the same fixture without tbd_figures (same data), with its own manifest (only
# /tbd.html) and its own shrink-only baseline: the default TBD table must not grow
# horizontally. Self-test: Scripts/test_gate_browser_fixture_default.sh.
#
# Usage: gate_browser_fixture_default.sh [site-dir [baseline]]

set -euo pipefail

cd "$(dirname "$0")/.."

FORSGREN_FIXTURE_DIR=Scripts/testdata/fixture_site_default \
  Scripts/gate_browser_fixture.sh "${1:-}" Scripts/browser_gate_fixture_default_manifest.json \
  Scripts/browser_gate_exceptions.txt "${2:-Scripts/browser_gate_fixture_default_baseline.txt}"
