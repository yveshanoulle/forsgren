#!/usr/bin/env bash
# Scripts/lib_browser_baseline.sh (forsgren#642). Not canon: forsgren only.
# Sourced, never run.
#
# browser_baseline <macos-file> <linux-file>: prints the browser baseline file of
# the platform this runs on. The baselines hold widths in px, and fonts render
# differently on macOS and on Linux, so one file cannot hold both: Darwin (the
# local FBP) reads <macos-file>, Linux (Quality's browser jobs on
# ubuntu-latest) reads <linux-file>. Both files follow the same rules (exact
# match, shrink-only, a reason on every row). Any other platform is refused on
# stderr with status 2, the exit of a gate that cannot run: never the macOS file
# as a guess. The platform is `uname -s`, found on PATH, so a self-test can fake
# it (Scripts/test_gate_browser_baseline.sh).
browser_baseline() {
  local platform
  platform="$(uname -s)"
  case "$platform" in
    Darwin) printf '%s\n' "$1" ;;
    Linux) printf '%s\n' "$2" ;;
    *)
      echo "browser gate: no baseline for the platform '${platform}' (uname -s): the widths are measured per platform, Darwin reads $1 and Linux $2" >&2
      return 2
      ;;
  esac
}
