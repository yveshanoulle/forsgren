#!/usr/bin/env bash
# Scripts/check_html_dupl.sh

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# HTML duplication RATCHET — unit 397, adapted from MenoPower's
# Scripts/admin/check_html_dupl.sh.
#
# Ported from konenki-website 2026-10-01 (forsgren#1, ladder step 11). No repo
# of the estate keeps this file identical: konenki, coachretreat and agilelean
# each carry their own target and ceiling. Yves's ruling on forsgren#1: ported
# even with one page, measured on the templates AND on the generated page, not
# n/a. forsgren's changes:
#   1. Two targets, one script. The default target is the html/template files
#      under internal/page/templates, the authored source (konenki's choice:
#      shared chrome is written once there, in templates/layout/). The
#      generated page in .build/site is measured too, through
#      Scripts/check_html_dupl_site.sh, which calls this script with that
#      directory and its own ceiling: a clone the templates do not show (a
#      page template pasting the chrome instead of calling it) shows there.
#   2. jscpd is a pinned devDependency in package.json + package-lock.json,
#      invoked by path from node_modules/.bin, never `npx --yes`: forsgren's
#      rule for every npm tool (README, Installing and updating). Same version
#      as konenki's npx pin, 4.2.4, so the numbers compare across the estate.
#   3. ZERO FILES SCANNED IS RED (exit 2), with that reason. jscpd 4.2.4 over a
#      directory with no .html prints neither a percentage nor "Found 0
#      clones" and exits 0; konenki's script then reports "could not read a
#      percentage", a red that blames jscpd's output format for what is an
#      empty target. The count comes from jscpd's own JSON report
#      (statistics.total.sources), what jscpd OPENED, not a separate find.
#      Self-test: Scripts/test_check_html_dupl.sh.
#
# The bar is a CEILING at the measured value, and the direction is DOWN.
# Ceiling 0.00% for the templates — measured 2026-10-01 with the pinned jscpd
# 4.2.4: 3 files, 0 clones. The gate fails if duplication RISES. Lower MAX_PCT
# deliberately whenever the number improves; never raise it to make a red go
# away.
#
# TOOL VERSION IS PINNED, AND THAT IS LOAD-BEARING. A ratchet compares a
# measurement to a recorded constant, so the measurement must not depend on
# what happens to be installed. konenki measured its pre-template Site/ at
# 8.67% with jscpd 4.2.4 and 7.84% with 5.0.15, on the same files.
#
# jscpd MEASURES; this script GATES. It is run with -t 0 so the percentage
# always appears in the output, and the ceiling comparison happens here. That
# keeps the number visible on a passing run.
#
# Exit: 0 at or under the ceiling, 1 over it, 2 tooling or nothing scanned.
# Usage: check_html_dupl.sh [target-dir] [max-pct]

export NO_COLOR=1
export FORCE_COLOR=0

TARGET_DIR="${1:-internal/page/templates}"
MAX_PCT="${2:-0.00}"

JSCPD_PIN="jscpd@4.2.4"
JSCPD="$(pwd)/node_modules/.bin/jscpd"

REPORT_DIR="$(mktemp -d)"
trap 'rm -rf "$REPORT_DIR"' EXIT

run_jscpd() {
  # Pinned in package.json + package-lock.json and run by path, deliberately
  # NOT falling back to a PATH install or npx: a different version is a
  # different number, and a ratchet cannot float.
  if [ -x "$JSCPD" ]; then
    "$JSCPD" "$@"
  else
    return 127
  fi
}

if [ ! -d "$TARGET_DIR" ]; then
  echo "html-dupl: target dir not found: ${TARGET_DIR}" >&2
  exit 2
fi

# -t 0 makes jscpd report the percentage whether or not we would accept it.
# The json reporter writes what jscpd scanned, read below for the zero check.
out="$(cd "$TARGET_DIR" && run_jscpd -k 50 -t 0 -r consoleFull,json -o "$REPORT_DIR" . -p "**/*.html" 2>&1)"
status=$?

if [ "$status" -eq 127 ]; then
  echo "html-dupl: ${JSCPD_PIN} is not installed at node_modules/.bin/jscpd — cannot measure (run npm ci)." >&2
  echo "  This does not skip: an unmeasured ratchet is not a passing one." >&2
  exit 2
fi

plain="$(printf '%s\n' "$out" | sed -E 's/\x1b\[[0-9;]*m//g')"

# Nothing scanned is not clean. jscpd writes no report at all when its pattern
# matches no file, so a missing report counts as zero too.
sources="$(node -e 'process.stdout.write(String(require(process.argv[1]).statistics.total.sources))' \
  "${REPORT_DIR}/jscpd-report.json" 2>/dev/null)"
if [ -z "$sources" ] || [ "$sources" = "0" ]; then
  echo "html-dupl: ${JSCPD_PIN} scanned 0 .html files under ${TARGET_DIR} — nothing measured is not clean." >&2
  exit 2
fi

if printf '%s\n' "$plain" | grep -q 'Found 0 clones'; then
  pct="0.00"
else
  pct="$(printf '%s\n' "$plain" | sed -nE 's/.*duplicates \(([0-9]+\.?[0-9]*)%\).*/\1/p' | tail -1)"
fi

if [ -z "$pct" ]; then
  echo "html-dupl: could not read a percentage from ${JSCPD_PIN} — BLIND, not clean." >&2
  echo "  Its output format changed, so this ratchet is measuring nothing." >&2
  printf '%s\n' "$plain" | tail -20 >&2
  exit 2
fi

# The comparison is ours, not jscpd's: its own -t semantics differ between
# versions, and the whole point of the pin is that this number means one thing.
over="$(awk -v a="$pct" -v b="$MAX_PCT" 'BEGIN { print (a > b) ? 1 : 0 }')"

if [ "$over" -eq 1 ]; then
  printf '%s\n' "$plain"
  echo "html-dupl: duplication ${pct}% EXCEEDS the ${MAX_PCT}% ceiling." >&2
  echo "  The ceiling only ever moves DOWN. Do not raise it to clear this —" >&2
  echo "  remove the duplication from the templates under internal/page instead." >&2
  exit 1
fi

echo "OK: html duplication ${pct}% over ${sources} file(s) in ${TARGET_DIR} (ceiling ${MAX_PCT}%, ${JSCPD_PIN}) — ratchet holds"
exit 0
