#!/usr/bin/env bash
# Scripts/check_data_guard.sh
#
# The data guard (forsgren#1, ladder step 6). Yves's design rule: forsgren
# holds CODE only. An installation's configuration (its repositories,
# services, workflow names, labels, health URL) and its data (history.csv,
# raw events) live OUTSIDE this repository, in a separate private data
# repository made from a template, and are passed to forsgren as paths. This
# repository is meant to become open source, so anything an installation
# owns that lands here is a leak waiting for the day it goes public.
#
# One structural rule, over the files git TRACKS (git ls-files):
#
#   Installation config or data outside testdata/. A tracked file whose
#   name matches an arm of guarded_reason below, or whose path matches an
#   arm of guarded_path_reason (anything under a top-level data/),
#   anywhere but under a directory named testdata (at any depth, Go's
#   convention), is red.
#   Fixtures under testdata/ are made up and are allowed to look like real
#   config.
#
# Private names are NOT this gate's business: Scripts/check_private_names.sh
# owns all private-name detection (forsgren#52), in every tracked path and
# file.
#
# SECRET-CLASS (Yves's ruling, 2026-10-02, forsgren#1 step 12.2): this gate's
# row in Scripts/gate_report_order.txt carries `secret-class`, like the
# secret scan's, so a finding here blocks the commit itself, not only the
# push. It is the row's class that does this, not this script's exit code
# (1 on a finding).
#
# TRACKED ONLY, deliberately: untracked scratch in a working tree is not
# judged. The other side of that: a NEW file is invisible to this gate until
# git knows it, so `git add` it (or `git add -N` it) before running the gates.
#
# Red-on-zero: no tracked files at all is red (the walk broke).
#
# Usage: Scripts/check_data_guard.sh [repo-dir]   (default: the repo root)
# Exit: 0 clean, 1 a finding or a scan over nothing.
# Fixture: Scripts/test_check_data_guard.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

ROOT_DIR="${1:-.}"
cd "$ROOT_DIR" || {
  echo "❌ FAIL: directory not found: ${ROOT_DIR}"
  exit 1
}

if ! TRACKED="$(git ls-files --cached 2>&1)"; then
  echo "❌ FAIL: git ls-files failed in ${ROOT_DIR}: ${TRACKED}"
  exit 1
fi

if [ -z "$TRACKED" ]; then
  echo "❌ FAIL: no tracked files found — the walk over git ls-files found nothing to check"
  exit 1
fi

FAIL=0

# in_testdata <path> — true when a path component is a directory named testdata.
in_testdata() {
  case "$1" in
    testdata/*|*/testdata/*) return 0 ;;
  esac
  return 1
}

# guarded_reason <basename> — THE ONE LIST of file names that look like
# installation config or data: each arm is a glob matched against the file's
# basename, with why it is here. Prints the reason of the first arm that
# matches; prints nothing when none does.
#
# Literal patterns in the code, not rows of a table read at runtime (Yves's
# ruling, 2026-10-02, forsgren#1 step 12.2, option c): a pattern held in a
# variable has to be expanded unquoted to keep its glob, which needs an
# SC2254 suppression; a pattern written as an arm is a glob as it stands,
# with nothing to suppress.
#
# One arm per line, `<pattern>) why="..." ;;`: Scripts/test_check_data_guard.sh
# mutates this list by that shape (it deletes the history.csv arm, then the
# deployments.csv arm, then the commits.csv arm, then the failures.csv arm,
# and quotes every arm whose pattern holds a `*` so that it matches only
# literally).
guarded_reason() {
  local why=""
  case "$1" in
    history.csv) why="the metric history an installation accumulates run after run" ;;
    deployments.csv) why="the deployment history forsgren collect keeps (data/deployments.csv in an installation)" ;;
    commits.csv) why="the commits of each deployment forsgren collect keeps for lead time (data/commits.csv in an installation)" ;;
    failures.csv) why="the failure issues forsgren collect keeps for change fail rate (data/failures.csv in an installation)" ;;
    *.history.csv) why="a per-service or per-installation history file" ;;
    forsgren.config.*) why="an installation's forsgren configuration, by its own name" ;;
    forsgren-config.*) why="the same configuration, hyphenated" ;;
    config.yml) why="a generic config name: forsgren keeps no config of its own, so one here is an installation's" ;;
    config.yaml) why="a generic config name: forsgren keeps no config of its own, so one here is an installation's" ;;
    config.json) why="a generic config name: forsgren keeps no config of its own, so one here is an installation's" ;;
    *.jsonl) why="raw events fetched from GitHub (one JSON object per line), which are installation data" ;;
  esac
  printf '%s' "$why"
}

# guarded_path_reason <path> — like guarded_reason, but over the whole path:
# forsgren creates data/ in an installation's data repository when it first
# stores history (forsgren#9, #12), so ANY tracked file under a top-level
# data/ is installation data. Only the top level: a data directory deeper in
# the tree (internal/data/) is code. Same arm shape as guarded_reason, and
# Scripts/test_check_data_guard.sh deletes the data/* arm by it.
guarded_path_reason() {
  local why=""
  case "$1" in
    data/*) why="everything under a top-level data/ is the history forsgren stores in an installation's data repository" ;;
  esac
  printf '%s' "$why"
}

# --- installation config or data outside testdata/ -------------------------
count=0
while IFS= read -r f; do
  count=$((count + 1))
  in_testdata "$f" && continue
  reason="$(guarded_path_reason "$f")"
  [ -n "$reason" ] || reason="$(guarded_reason "$(basename "$f")")"
  if [ -n "$reason" ]; then
    echo "❌ FAIL: ${f} — looks like installation config or data (${reason}); it belongs in the installation's private data repository, passed to forsgren as a path, or under testdata/ if it is a made-up fixture"
    FAIL=1
  fi
done <<< "$TRACKED"

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "OK: ${count} tracked files hold no installation config or data outside testdata/"
