#!/usr/bin/env bash
# Scripts/check_private_names.sh
#
# forsgren#52. This repository is public, so no tracked file may name a
# private repository. The names live OUTSIDE the repository (Yves's ruling,
# 2026-10-04); writing them here to keep them out of here would publish them.
#
# Usage: Scripts/check_private_names.sh [repo-dir]   (default: the current directory)
#
# The list, the first source that is set and non-empty wins:
#   1. env FORSGREN_PRIVATE_NAMES, newline-separated (the CI Actions secret)
#   2. the file FORSGREN_PRIVATE_NAMES_FILE, else
#      ${HOME}/.config/forsgren/private-names; one name per line
# Blank lines and lines starting with # are not names.
#
# It searches the CONTENT and the PATH of every tracked file (git ls-files),
# case-insensitively, for a WHOLE name: the name must not be directly preceded
# or followed by a letter, a digit, `_` or `-` (so `acme-secret-repo` is not
# found inside `acme-secret-repository`).
#
# The FAIL lines name `file:line` for a content hit (`tracked path #N:line`
# when the path itself names a private name) and `tracked path #N in
# git ls-files` for a path hit, NEVER the name and never a matching path:
# sfl and FBP.sh quote FAIL lines and CI prints them on the job summary.
#
# Exit 0 clean. Exit 1 a name found. Exit 2 no list, a list with no names,
# or no tracked file: a scan for nothing never passes.

set -euo pipefail
# Tracing off: the list must never reach a trace (bash -x, or a CI debug run).
set +x

REPO="${1:-.}"
cd "$REPO" || { echo "❌ FAIL: cannot enter ${REPO}"; exit 2; }

# read_list: the raw list text in LIST, from the first source that has one.
read_list() {
  if [[ -n "${FORSGREN_PRIVATE_NAMES:-}" ]]; then
    LIST="$FORSGREN_PRIVATE_NAMES"
    return 0
  fi
  local file="${FORSGREN_PRIVATE_NAMES_FILE:-${HOME:-/nonexistent}/.config/forsgren/private-names}"
  if [[ ! -f "$file" ]]; then
    if [[ -n "${FORSGREN_PRIVATE_NAMES_FILE:-}" ]]; then
      echo "❌ FAIL: the private-names file ${file} does not exist"
    else
      echo "❌ FAIL: no list of private names: set FORSGREN_PRIVATE_NAMES (newline-separated) or FORSGREN_PRIVATE_NAMES_FILE, or create ~/.config/forsgren/private-names"
    fi
    exit 2
  fi
  LIST="$(cat "$file")"
}

# build_patterns <file>: one ERE per name into <file>, regex-escaped, with the
# whole-name boundaries. Sets COUNT to the number of names; exit 2 on none.
build_patterns() {
  local out="$1" line escaped
  COUNT=0
  : > "$out"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    escaped="$(printf '%s' "$line" | sed 's/[][\.*^$+?(){}|/]/\\&/g')"
    printf '(^|[^A-Za-z0-9_-])%s($|[^A-Za-z0-9_-])\n' "$escaped" >> "$out"
    COUNT=$((COUNT + 1))
  done <<< "$LIST"
  if [[ "$COUNT" -eq 0 ]]; then
    echo "❌ FAIL: the list of private names has no names in it: a scan for nothing is not a clean scan"
    exit 2
  fi
}

# scan_tracked <patterns>: judges the path and the content of every tracked
# file, and the target text of every tracked symlink. Sets N to the number of tracked paths and FOUND to 1 on any hit.
scan_tracked() {
  local patterns="$1" entry path mode sha shown hits hit lineno
  FOUND=0
  N=0
  while IFS= read -r -d '' entry; do
    path="${entry#*$'\t'}"
    mode="${entry%% *}"
    sha="${entry#* }"
    sha="${sha%% *}"
    N=$((N + 1))
    shown="$path"
    # A here-string, not a pipe: under pipefail, grep -q closing the pipe early
    # can SIGPIPE the printf and turn a match into a miss.
    if grep -q -i -E -f "$patterns" <<< "$path"; then
      echo "❌ FAIL: tracked path #${N} in git ls-files names a private name"
      FOUND=1
      shown="tracked path #${N}"
    fi
    # A symlink is stored as its target text, which may dangle: judge that text.
    if [[ "$mode" == 120000 ]] \
      && grep -q -i -E -f "$patterns" <<< "$(git cat-file blob "$sha")"; then
      echo "❌ FAIL: tracked path #${N} (link target) names a private name"
      FOUND=1
    fi
    [[ -f "$path" ]] || continue
    hits="$(grep -a -n -i -E -f "$patterns" -- "$path" || true)"
    [[ -z "$hits" ]] && continue
    while IFS= read -r hit; do
      lineno=${hit%%:*}
      echo "❌ FAIL: ${shown}:${lineno} names a private name"
      FOUND=1
    done <<< "$hits"
  done < <(git ls-files -s -z)
}

LIST=""
read_list

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
build_patterns "${TMP}/patterns"
scan_tracked "${TMP}/patterns"

if [[ "$N" -eq 0 ]]; then
  echo "❌ FAIL: no tracked files: the scan read nothing"
  exit 2
fi

if [[ "$FOUND" -ne 0 ]]; then
  exit 1
fi
echo "OK: no private name in ${N} tracked paths and files (${COUNT} names searched)"
