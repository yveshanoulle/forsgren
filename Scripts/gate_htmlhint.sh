#!/usr/bin/env bash
# canon: gate_htmlhint v1
# Scripts/gate_htmlhint.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# HTMLHint gate.
#
# A wrapper so Scripts/gate_report_order.txt can name a PATH rather than a
# command line. Its argument is a quoted glob: as text in a data file it would
# need eval or an unquoted expansion to rebuild argv, with the glob surviving
# unexpanded. Here it is just argv, and the estate's own rule already says a
# command body belongs in a tested script.
#
# The canon version, byte-identical across the estate's repositories
# What differs per repository is DATA:
#   1. The default site directory is the site_dir of Scripts/site_settings.txt,
#      read through Scripts/lib_site_settings.sh. A missing or invalid settings
#      file is exit 2, never a guessed default. The argument stays, so a caller
#      can lint another directory.
#   2. ZERO FILES SCANNED IS RED (exit 2). htmlhint reports
#      "Scanned 0 files, no errors found" and exits 0 when its glob matches
#      nothing, so a site whose HTML moved out of the glob's reach would pass
#      this gate with nothing linted. Stylelint already refuses an empty match
#      (NoFilesFoundError); this makes the two gates agree.
#      check_lint_coverage.sh does not cover it: it runs its OWN htmlhint over
#      its own copy of the glob, so it proves that invocation's reach, not
#      this one's. Self-test: Scripts/test_gate_htmlhint.sh.
#   3. A missing site directory is exit 2.
#   4. The rules are read from .htmlhintrc, named explicitly.
#
# Usage: gate_htmlhint.sh [site-dir]  (default: site_dir from site_settings.txt)

SITE_DIR="${1:-}"
if [[ -z "$SITE_DIR" ]]; then
  # shellcheck source=Scripts/lib_site_settings.sh
  source Scripts/lib_site_settings.sh
  SITE_DIR="$(site_settings_get Scripts/site_settings.txt site_dir)" || exit 2
fi

if [[ ! -d "$SITE_DIR" ]]; then
  echo "htmlhint: site dir not found: $SITE_DIR" >&2
  exit 2
fi

# Not exec: the scanned-file count has to be read after htmlhint exits. Its
# output is shown as it runs and kept for that read.
OUT="$(mktemp)"
# On bash 3.2 an abort (an unbound variable under set -eu) ends a script with
# an EXIT trap with status 0, and $? in the trap is 0 too. COMPLETED, set as
# the very last statement, is the only way out with 0: an exit of 0 without it
# is an abort and becomes exit 1.
COMPLETED=0
finish() {
  local rc=$?
  rm -f "$OUT"
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: gate_htmlhint.sh aborted before completing (COMPLETED was never set)" >&2
    exit 1
  fi
}
trap finish EXIT

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
COMPLETED=1
