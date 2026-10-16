#!/usr/bin/env bash
# canon: gate_stylelint v1
# Scripts/gate_stylelint.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# Stylelint gate. Wrapper, same reason as gate_htmlhint.sh: the order file names
# a path, not a command line with a quoted glob in it.
#
# The canon version, byte-identical across the estate's repositories
# What differs per repository is DATA:
#   1. The default site directory is the site_dir of Scripts/site_settings.txt,
#      read through Scripts/lib_site_settings.sh. A missing or invalid settings
#      file is exit 2, never a guessed default. The argument stays, so a caller
#      can lint another directory.
#   2. A missing site directory is exit 2.
#   3. A glob that matches nothing is red (stylelint's NoFilesFoundError, exit 1,
#      "No files matching the pattern"); the gate does not soften it.
#   4. CHECK-ONLY by default. Only GATE_FIX=1 adds --fix. sfl.sh exports it, so
#      FullBuildAndPush fixes what stylelint can fix; CI never sets it, so CI
#      reports what the commit CONTAINS and never changes a file.
#
# Self-test: Scripts/test_gate_stylelint.sh.
#
# Usage: gate_stylelint.sh [site-dir]  (default: site_dir from site_settings.txt)

SITE_DIR="${1:-}"
if [[ -z "$SITE_DIR" ]]; then
  # shellcheck source=Scripts/lib_site_settings.sh
  source Scripts/lib_site_settings.sh
  SITE_DIR="$(site_settings_get Scripts/site_settings.txt site_dir)" || exit 2
fi

if [[ ! -d "$SITE_DIR" ]]; then
  echo "stylelint: site dir not found: $SITE_DIR" >&2
  exit 2
fi

if [[ "${GATE_FIX:-}" == "1" ]]; then
  exec node_modules/.bin/stylelint --fix "${SITE_DIR}/**/*.css"
fi
exec node_modules/.bin/stylelint "${SITE_DIR}/**/*.css"
