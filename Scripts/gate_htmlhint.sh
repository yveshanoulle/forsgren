#!/usr/bin/env bash
# Scripts/gate_htmlhint.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# HTMLHint gate — unit 409 step 3.
#
# A wrapper so Scripts/gate_report_order.txt can name a PATH rather than a
# command line. This was one of the last two raw `node_modules/.bin/...`
# invocations in sfl, and its argument is a quoted glob: as text in a data file
# it would need eval or an unquoted expansion to rebuild argv, with the glob
# surviving unexpanded. Here it is just argv, and the estate's own rule already
# says a command body belongs in a tested script.
#
# Ported from konenki-website 2026-10-01 (forsgren#1, ladder step 8). Two
# changes, both forsgren's own:
#   1. The default site directory is .build/site, where Scripts/build_site.sh
#      renders the site; forsgren commits no generated output. The argument
#      stays, so a caller can lint another build.
#   2. ZERO FILES SCANNED IS RED (exit 2). htmlhint reports
#      "Scanned 0 files, no errors found" and exits 0 when its glob matches
#      nothing, so a site whose HTML moved out of the glob's reach would pass
#      this gate with nothing linted. Stylelint already refuses an empty match
#      (NoFilesFoundError); this makes the two gates agree.
#      check_lint_coverage.sh does not cover it: it runs its OWN htmlhint over
#      its own copy of the glob, so it proves that invocation's reach, not
#      this one's. Self-test: Scripts/test_gate_htmlhint.sh.
#
# Usage: gate_htmlhint.sh [site-dir]  (default: .build/site)

SITE_DIR="${1:-.build/site}"

if [[ ! -d "$SITE_DIR" ]]; then
  echo "htmlhint: site dir not found: $SITE_DIR" >&2
  exit 2
fi

# Not exec: the scanned-file count has to be read after htmlhint exits. Its
# output is shown as it runs and kept for that read.
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

set +e
node_modules/.bin/htmlhint \
  --config .htmlhintrc \
  "${SITE_DIR}/**/*.html" 2>&1 | tee "$OUT"
rc=${PIPESTATUS[0]}
set -e

if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi

if grep -qE 'Scanned 0 files' "$OUT"; then
  echo "htmlhint: scanned 0 files under ${SITE_DIR} — nothing linted is not clean" >&2
  exit 2
fi
