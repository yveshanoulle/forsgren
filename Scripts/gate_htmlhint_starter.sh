#!/usr/bin/env bash
# Scripts/gate_htmlhint_starter.sh
#
# The HTMLHint post gate for the starter page (forsgren#132): the same gate
# and the same .htmlhintrc as Scripts/gate_htmlhint.sh, pointed at
# .build/starter, where Scripts/build_starter_page.sh renders the page. A row
# of the order file names a script, not a command line, so the directory
# lives here.
#
# Usage: Scripts/gate_htmlhint_starter.sh [dir]   (default: .build/starter)
# Fixture: Scripts/test_starter_page_gates.sh.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

exec ./Scripts/gate_htmlhint.sh "${1:-.build/starter}"
