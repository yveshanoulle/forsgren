#!/usr/bin/env bash
# Scripts/gate_stylelint.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# Stylelint gate — unit 409 step 3. Wrapper, same reason as gate_htmlhint.sh:
# the order file names a path, not a command line with a quoted glob in it.
#
# Ported from konenki-website 2026-10-01 (forsgren#1, ladder step 8). The one
# change: the default site directory is .build/site, where
# Scripts/build_site.sh renders the site; forsgren commits no generated
# output. The argument stays, so a caller can lint another build.
# A glob that matches nothing is already red here (stylelint's
# NoFilesFoundError). Self-test: Scripts/test_gate_stylelint.sh.
#
# Usage: gate_stylelint.sh [site-dir]  (default: .build/site)

SITE_DIR="${1:-.build/site}"

if [[ ! -d "$SITE_DIR" ]]; then
  echo "stylelint: site dir not found: $SITE_DIR" >&2
  exit 2
fi

exec node_modules/.bin/stylelint "${SITE_DIR}/**/*.css"
