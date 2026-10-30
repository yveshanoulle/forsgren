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
# One structural rule, over the files git tracks and the untracked ones it does
# not ignore (Scripts/lib_repo_files.sh, read NUL-separated, forsgren#204):
#
#   Installation config or data outside testdata/. A file whose
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
# UNTRACKED FILES COUNT (forsgren#204): FBP commits after its gates run, so a
# new data file is still untracked while this gate judges it, and a gate that
# looked only at tracked files would let the commit that adds it through. A
# file git ignores is left alone: it will never be committed.
#
# Red-on-zero: no file at all is red (the walk broke).
#
# Usage: Scripts/check_data_guard.sh [repo-dir]   (default: the repo root)
# Exit: 0 clean, 1 a finding or a scan over nothing.
# Fixture: Scripts/test_check_data_guard.sh.

set -uo pipefail

# The script's own directory, resolved before the cd: a relative $0 (run from
# inside Scripts/) no longer names it afterwards.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# shellcheck source=Scripts/lib_repo_files.sh
source "${SCRIPT_DIR}/lib_repo_files.sh"

ROOT_DIR="${1:-.}"
cd "$ROOT_DIR" || {
  echo "❌ FAIL: directory not found: ${ROOT_DIR}"
  exit 1
}

# The list is read NUL-separated (-z), so a non-ASCII or otherwise unusual path
# reaches the arms as it is, unquoted, and a FAIL line prints the real path.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if ! repo_files . -z > "$TMP/listed" 2> "$TMP/err"; then
  echo "❌ FAIL: git ls-files failed in ${ROOT_DIR}: $(cat "$TMP/err")"
  exit 1
fi

if [ ! -s "$TMP/listed" ]; then
  echo "❌ FAIL: no files found — the walk over git ls-files found nothing to check"
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
# Every data file the Go code names (a `const <Name>File = "<name>.csv"` in
# internal/collect) has an arm here: Scripts/test_check_data_guard.sh reads
# those constants and fails when one is not guarded (forsgren#143), so a data
# file added later cannot be forgotten.
#
# One arm per line, `<pattern>) why="..." ;;`: Scripts/test_check_data_guard.sh
# mutates this list by that shape (it deletes the history.csv arm, then the
# deployments.csv arm, then the commits.csv arm, then the failures.csv arm,
# then the issues.csv arm, then the issues_full.csv, failures_read.csv,
# failures_withdrawn.csv, issue_bugs.csv, issue_bugs_cut.csv, reach.csv, cut_runs.csv, starts_checked.csv, commits_backfilled.csv, pulls.csv, pulls_read.csv, pulls_denied.csv, pushes.csv, pushes_read.csv, pushes_denied.csv, pushes_cut.csv, pushes_checked.csv, pushes_fill.csv, pushes_github_end.csv, push_commits.csv, pull_commits.csv, pull_commits_filled.csv, push_commits_filled.csv, pulls_bot_filled.csv, commit_files.csv, commit_files_filled.csv and push_files_filled.csv arms, and quotes every arm whose pattern holds a
# `*` so that it matches only literally).
guarded_reason() {
  local why=""
  case "$1" in
    history.csv) why="the metric history an installation accumulates run after run" ;;
    deployments.csv) why="the deployment history forsgren collect keeps (data/deployments.csv in an installation)" ;;
    commits.csv) why="the commits of each deployment forsgren collect keeps for lead time (data/commits.csv in an installation)" ;;
    failures.csv) why="the failure issues forsgren collect keeps for change fail rate (data/failures.csv in an installation)" ;;
    issues.csv) why="the issue events forsgren collect keeps for the days and issues pages (data/issues.csv in an installation)" ;;
    issues_full.csv) why="the note of each repository whose issues were read in full, which forsgren collect keeps (data/issues_full.csv in an installation)" ;;
    failures_read.csv) why="when each repository's failure and issue lists were last read, which forsgren collect keeps (data/failures_read.csv in an installation)" ;;
    failures_withdrawn.csv) why="which failure issues were withdrawn, which forsgren collect keeps for change fail rate (data/failures_withdrawn.csv in an installation)" ;;
    issue_bugs.csv) why="which issues carry the bug label, which forsgren collect keeps for the Open bugs column (data/issue_bugs.csv in an installation)" ;;
    issue_bugs_cut.csv) why="which repositories' bug reads stopped at the page cap, which forsgren collect keeps for the Open bugs column (data/issue_bugs_cut.csv in an installation)" ;;
    cut_runs.csv) why="since when each repository has been cut short at the request budget without progress, which forsgren collect keeps (data/cut_runs.csv in an installation)" ;;
    starts_checked.csv) why="which repositories had their failure starts caught up from the issues' comments, which forsgren collect keeps (data/starts_checked.csv in an installation)" ;;
    commits_backfilled.csv) why="which repositories had the author, parents and committer date of their legacy commits backfilled, which forsgren collect keeps (data/commits_backfilled.csv in an installation)" ;;
    reach.csv) why="how far back each repository's deployments were read, which forsgren collect keeps (data/reach.csv in an installation)" ;;
    pulls.csv) why="the merged pull requests forsgren collect keeps for PR Lead Time and Bot PR Lead Time (data/pulls.csv in an installation)" ;;
    pulls_read.csv) why="when each repository's closed pull requests were last read, which forsgren collect keeps (data/pulls_read.csv in an installation)" ;;
    pulls_denied.csv) why="which repositories' pull request reads GitHub refused, and which token, which forsgren collect keeps (data/pulls_denied.csv in an installation)" ;;
    pushes.csv) why="the pushes to each repository's main branch forsgren collect keeps for time to main and batch size (data/pushes.csv in an installation)" ;;
    pushes_read.csv) why="when each repository's pushes were last read, which forsgren collect keeps (data/pushes_read.csv in an installation)" ;;
    pushes_denied.csv) why="which repositories' push reads GitHub refused, and which token, which forsgren collect keeps (data/pushes_denied.csv in an installation)" ;;
    pushes_cut.csv) why="which repositories' push reads stopped at the page cap, and how far back they reached, which forsgren collect keeps (data/pushes_cut.csv in an installation)" ;;
    pushes_checked.csv) why="which repositories had the reach of their stored pushes checked once, which forsgren collect keeps (data/pushes_checked.csv in an installation)" ;;
    pushes_fill.csv) why="where each repository's fill of its older pushes goes on, which forsgren collect keeps (data/pushes_fill.csv in an installation)" ;;
    pushes_github_end.csv) why="which repositories' activity lists GitHub keeps only back to a push, which forsgren collect keeps (data/pushes_github_end.csv in an installation)" ;;
    push_commits.csv) why="the commits each push to a repository's main branch brought, which forsgren collect keeps (data/push_commits.csv in an installation)" ;;
    pull_commits.csv) why="the commits of each merged pull request, which forsgren collect keeps for Mainline Lead Time (data/pull_commits.csv in an installation)" ;;
    push_commits_filled.csv) why="which repositories had the lines of their stored merge pushes filled, which forsgren collect keeps (data/push_commits_filled.csv in an installation)" ;;
    commit_files.csv) why="the files each deployed commit changes, which forsgren collect keeps for the service rows (data/commit_files.csv in an installation)" ;;
    commit_files_filled.csv) why="which repositories had the files of their stored commits read, which forsgren collect keeps (data/commit_files_filled.csv in an installation)" ;;
    push_files_filled.csv) why="which repositories had the files of all their pushed commits read, which forsgren collect keeps (data/push_files_filled.csv in an installation)" ;;
    pull_commits_filled.csv) why="which repositories had the commits of their stored pull requests filled, which forsgren collect keeps (data/pull_commits_filled.csv in an installation)" ;;
    pulls_bot_filled.csv) why="which repositories had the bot status of their stored pull requests filled, which forsgren collect keeps (data/pulls_bot_filled.csv in an installation)" ;;
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
while IFS= read -r -d '' f; do
  count=$((count + 1))
  in_testdata "$f" && continue
  reason="$(guarded_path_reason "$f")"
  [ -n "$reason" ] || reason="$(guarded_reason "$(basename "$f")")"
  if [ -n "$reason" ]; then
    echo "❌ FAIL: ${f} — looks like installation config or data (${reason}); it belongs in the installation's private data repository, passed to forsgren as a path, or under testdata/ if it is a made-up fixture"
    FAIL=1
  fi
done < "$TMP/listed"

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "OK: ${count} files hold no installation config or data outside testdata/"
