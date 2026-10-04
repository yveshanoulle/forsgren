#!/usr/bin/env bash
# Scripts/check_private_names.sh
#
# forsgren#52. This repository is public, so no tracked or untracked file
# (one git add -A would stage) may name a private repository. The names live OUTSIDE the repository (Yves's ruling,
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
# It searches the CONTENT and the PATH of every tracked file (git ls-files) and
# of every untracked, not-ignored file (git ls-files -o --exclude-standard:
# exactly what git add -A would stage; an untracked symlink is judged by its
# readlink target, like a tracked one), case-insensitively, for a SUBSTRING: a listed name anywhere inside a longer
# token is a hit (so `acme-secret-repo` is found inside `acme-secret-repository`,
# `my-acme-secret-repo` and `apply-acme-secret-repo.yml`). Yves's ruling: the
# gate takes over the data guard's `grep -iF` matching.
#
# The FAIL lines name `file:line` for a content hit (`tracked path #N:line`
# when the path itself names a private name) and `tracked path #N in
# git ls-files` for a path hit, NEVER the name and never a matching path:
# sfl and FBP.sh quote FAIL lines and CI prints them on the job summary.
#
# Exit 0 clean. Exit 1 a name found. Exit 2 no list, a list with no names,
# or no file at all: a scan for nothing never passes.

set -euo pipefail
# Tracing off: the list must never reach a trace (bash -x, or a CI debug run).
set +x

# The list parsing, shared with Scripts/sync_private_names_secrets.sh.
# Sourced from beside this script, before the cd below into the repository.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=Scripts/lib_private_names.sh
source "${ROOT}/Scripts/lib_private_names.sh"

REPO="${1:-.}"
cd "$REPO" || { echo "❌ FAIL: cannot enter ${REPO}"; exit 2; }

# read_list: the raw list text in LIST, from the first source that has one.
read_list() {
  if [[ -n "${FORSGREN_PRIVATE_NAMES:-}" ]]; then
    LIST="$FORSGREN_PRIVATE_NAMES"
    return 0
  fi
  local file
  file="$(private_names_file)"
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

# build_patterns <file>: one ERE per name into <file>, regex-escaped, no
# boundary (a substring match). Sets COUNT to the number of names; exit 2 on none.
build_patterns() {
  private_names_parse "$LIST"
  COUNT="$PRIVATE_NAMES_COUNT"
  printf '%s' "$PRIVATE_NAMES" | sed 's/[][\.*^$+?(){}|/]/\\&/g' > "$1"
  if [[ "$COUNT" -eq 0 ]]; then
    echo "❌ FAIL: the list of private names has no names in it: a scan for nothing is not a clean scan"
    exit 2
  fi
}

# judge_path <patterns> <path> <link-target-or-empty> <is-link 0|1>: judges one
# path, its symlink target text and its content; counts it in N (the numbering
# runs over the tracked list, then the untracked one). Sets FOUND to 1 on a hit.
judge_path() {
  local patterns="$1" path="$2" target="$3" islink="$4" shown hits hit lineno
  N=$((N + 1))
  shown="$path"
  # A here-string, not a pipe: under pipefail, grep -q closing the pipe early
  # can SIGPIPE the printf and turn a match into a miss.
  if grep -q -i -E -f "$patterns" <<< "$path"; then
    echo "❌ FAIL: tracked path #${N} in git ls-files names a private name"
    FOUND=1
    shown="tracked path #${N}"
  fi
  # A symlink is judged by its target text, which may dangle.
  if [[ "$islink" -eq 1 ]] && grep -q -i -E -f "$patterns" <<< "$target"; then
    echo "❌ FAIL: tracked path #${N} (link target) names a private name"
    FOUND=1
  fi
  [[ -f "$path" ]] || return 0
  hits="$(grep -a -n -i -E -f "$patterns" -- "$path" || true)"
  [[ -z "$hits" ]] && return 0
  while IFS= read -r hit; do
    lineno=${hit%%:*}
    echo "❌ FAIL: ${shown}:${lineno} names a private name"
    FOUND=1
  done <<< "$hits"
}

# scan_tracked <patterns>: judges every tracked file (git ls-files), then every
# untracked, not-ignored one (git ls-files -o --exclude-standard: exactly what
# git add -A would stage). Sets N to the number of paths and FOUND to 1 on any hit.
scan_tracked() {
  local patterns="$1" entry path mode sha target
  FOUND=0
  N=0
  while IFS= read -r -d '' entry; do
    path="${entry#*$'\t'}"
    mode="${entry%% *}"
    sha="${entry#* }"
    sha="${sha%% *}"
    target=""
    [[ "$mode" == 120000 ]] && target="$(git cat-file blob "$sha")"
    judge_path "$patterns" "$path" "$target" "$([[ "$mode" == 120000 ]] && echo 1 || echo 0)"
  done < <(git ls-files -s -z)
  while IFS= read -r -d '' path; do
    target=""
    if [[ -L "$path" ]]; then
      target="$(readlink -- "$path")"
      judge_path "$patterns" "$path" "$target" 1
    else
      judge_path "$patterns" "$path" "" 0
    fi
  done < <(git ls-files -o --exclude-standard -z)
}

LIST=""
read_list

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
build_patterns "${TMP}/patterns"
scan_tracked "${TMP}/patterns"

if [[ "$N" -eq 0 ]]; then
  echo "❌ FAIL: no tracked or untracked files: the scan read nothing"
  exit 2
fi

if [[ "$FOUND" -ne 0 ]]; then
  exit 1
fi
echo "OK: no private name in ${N} tracked and untracked paths and files (${COUNT} names searched)"
