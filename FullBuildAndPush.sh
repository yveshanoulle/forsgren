#!/usr/bin/env bash
# FullBuildAndPush.sh — temporary forwarder (estate issue 610). The full build
# script is FBP.sh; this name stays only as a safety net during the move and
# goes in the last step of #610. It only hands over: every argument unchanged,
# and FBP.sh's own exit status.
exec "$(dirname "$0")/FBP.sh" "$@"
