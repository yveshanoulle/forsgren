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
# Two checks, both over the files git TRACKS (git ls-files):
#
#   a. Installation config or data outside testdata/. A tracked file whose
#      name matches an arm of guarded_reason below, anywhere but under a
#      directory named testdata (at any depth, Go's convention), is red.
#      Fixtures under testdata/ are made up and are allowed to look like real
#      config.
#
#   b. The owner's real names in fixtures and tests. Every tracked file under
#      testdata/ and every test file (*_test.go, test_*.sh) is searched,
#      case-insensitively, for the names listed in the file that
#      FORSGREN_PRIVATE_NAMES_FILE points to: the owner's real repository,
#      organisation and domain names, one per line, `#` starting a comment.
#      That list is NOT in this repository: writing the names here to keep
#      them out of here would publish them. When the variable is unset or the
#      file does not exist, this part is skipped with a one-line ⚠️ warning
#      and passes; a names file that exists but lists no names is red (a scan
#      for nothing is not a clean scan). A relative path is taken from the
#      directory the gate was invoked from.
#      The FAIL line names the file and line, NEVER the name it matched: sfl
#      quotes FAIL lines into its summary and FBP.sh into the commit message,
#      so printing the name would copy it into git history.
#
# TRACKED ONLY, deliberately: untracked scratch in a working tree is not
# judged. The other side of that: a NEW file is invisible to this gate until
# git knows it, so `git add` it (or `git add -N` it) before running the gates.
#
# Red-on-zero: no tracked files at all is red (the walk broke), and with a
# names file given, no fixture or test file to search is red too.
#
# Usage: Scripts/check_data_guard.sh [repo-dir]   (default: the repo root)
# Exit: 0 clean, 1 a finding or a scan over nothing.
# Fixture: Scripts/test_check_data_guard.sh.

set -uo pipefail

INVOKED_FROM="$(pwd)"

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
# mutates this list by that shape (it deletes the history.csv arm, and quotes
# every arm whose pattern holds a `*` so that it matches only literally).
guarded_reason() {
  local why=""
  case "$1" in
    history.csv) why="the metric history an installation accumulates run after run" ;;
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

# --- a. installation config or data outside testdata/ ----------------------
count=0
while IFS= read -r f; do
  count=$((count + 1))
  in_testdata "$f" && continue
  reason="$(guarded_reason "$(basename "$f")")"
  if [ -n "$reason" ]; then
    echo "❌ FAIL: ${f} — looks like installation config or data (${reason}); it belongs in the installation's private data repository, passed to forsgren as a path, or under testdata/ if it is a made-up fixture"
    FAIL=1
  fi
done <<< "$TRACKED"

# --- b. the owner's real names in fixtures and tests -----------------------
NAMES_FILE="${FORSGREN_PRIVATE_NAMES_FILE:-}"
case "$NAMES_FILE" in
  ''|/*) ;;
  *) NAMES_FILE="${INVOKED_FROM}/${NAMES_FILE}" ;;
esac

scanned=0
if [ -z "${FORSGREN_PRIVATE_NAMES_FILE:-}" ]; then
  echo "⚠️ private-name scan skipped: FORSGREN_PRIVATE_NAMES_FILE is not set"
elif [ ! -f "$NAMES_FILE" ]; then
  echo "⚠️ private-name scan skipped: FORSGREN_PRIVATE_NAMES_FILE names a file that does not exist"
else
  NAMES="$(mktemp)"
  trap 'rm -f "$NAMES"' EXIT
  # Comments and blank lines out, surrounding whitespace trimmed.
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$NAMES_FILE" \
    | grep -v '^$' > "$NAMES" || true

  if [ ! -s "$NAMES" ]; then
    echo "❌ FAIL: no names in FORSGREN_PRIVATE_NAMES_FILE — a scan for nothing is not a clean scan; list the names or unset the variable"
    FAIL=1
  else
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      if ! in_testdata "$f"; then
        case "$(basename "$f")" in
          *_test.go|test_*.sh) ;;
          *) continue ;;
        esac
      fi
      scanned=$((scanned + 1))
      # -I skips binary files; only the line numbers are kept, never the text.
      lines="$(grep -nIiF -f "$NAMES" -- "$f" | cut -d: -f1 | paste -sd, -)"
      if [ -n "$lines" ]; then
        echo "❌ FAIL: ${f}:${lines} — mentions a name listed in FORSGREN_PRIVATE_NAMES_FILE (the name is not printed here, so it cannot reach a commit message); use a made-up one such as acme/app"
        FAIL=1
      fi
    done <<< "$TRACKED"

    if [ "$scanned" -eq 0 ]; then
      echo "❌ FAIL: no fixture or test files found to search for private names — the walk found nothing under testdata/ and no *_test.go or test_*.sh"
      FAIL=1
    fi
  fi
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

if [ "$scanned" -gt 0 ]; then
  echo "OK: ${count} tracked files hold no installation config or data outside testdata/, and ${scanned} fixture and test files name no private name"
else
  echo "OK: ${count} tracked files hold no installation config or data outside testdata/"
fi
