#!/usr/bin/env bash
# Scripts/fix_source_css.sh [css-file]
#
# The source-CSS fix step of FBP.sh (forsgren#215). Not canon: forsgren's own,
# and deliberately OUTSIDE the canonical Stylelint gate (Scripts/gate_stylelint.sh),
# which stays byte-identical across the estate.
#
# Why it exists. The estate's Stylelint gate adds --fix to the generated site
# under GATE_FIX=1. forsgren's CSS is not authored in the site directory: it is
# internal/page/styles.css, embedded with go:embed and copied into
# .build/site on every build. A fix applied to the generated copy is lost on
# the next build, and the committed source stays unfixed, so CI (which only
# checks) is red on a source nobody fixed. So the fix goes to the SOURCE, here,
# and FBP.sh runs it before the build; the build then copies the fixed source,
# and the gate has nothing left to fix.
#
# FIX MODE ONLY. Without GATE_FIX=1 this script changes nothing and says so,
# exit 0: CI never sets GATE_FIX and never runs this script (it is no row of
# Scripts/gate_report_order.txt, and no workflow names it), and a stray call
# without the variable must not rewrite a file. FBP.sh runs it with GATE_FIX=1.
# The generated .build/site is never touched.
#
# Exit 0 nothing to do or everything fixed; otherwise stylelint's own exit
# (it could not fix every finding: the Stylelint gate then says what is left).
# Self-test: Scripts/test_fix_source_css.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

CSS="${1:-internal/page/styles.css}"

if [[ "${GATE_FIX:-}" != "1" ]]; then
  echo "fix_source_css: GATE_FIX is not 1, so nothing is fixed (CI only checks; FBP.sh fixes the source CSS before the build)"
  exit 0
fi

if [[ ! -f "$CSS" ]]; then
  echo "fix_source_css: source CSS not found: ${CSS}" >&2
  exit 2
fi

if [[ ! -x node_modules/.bin/stylelint ]]; then
  echo "fix_source_css: node_modules/.bin/stylelint is missing — run npm ci" >&2
  exit 2
fi

exec node_modules/.bin/stylelint --fix "$CSS"
