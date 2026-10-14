#!/usr/bin/env bash
# Scripts/check_privacy_posture_starter.sh
#
# The privacy-posture post gate for the starter page (forsgren#132): the same
# gate as Scripts/check_privacy_posture.sh, pointed at .build/starter, where
# Scripts/build_starter_page.sh renders the page. A row of the order file
# names a script, not a command line, so the directory lives here.
#
# Usage: Scripts/check_privacy_posture_starter.sh [dir]   (default: .build/starter)
# Fixture: Scripts/test_starter_page_gates.sh.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

exec ./Scripts/check_privacy_posture.sh "${1:-.build/starter}"
