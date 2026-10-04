#!/usr/bin/env bash
# Scripts/check_private_names.sh
#
# forsgren#52. This repository is public, so no tracked or untracked file
# (one git add -A would stage) may name a private repository. The names live OUTSIDE the repository (Yves's ruling,
# 2026-10-04); writing them here to keep them out of here would publish them.
#
# Usage: Scripts/check_private_names.sh [repo-dir]   (default: the current directory)
#        Scripts/check_private_names.sh --message <file>
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
# readlink target; a tracked symlink is judged by the WORKING TREE too, which
# is what git add -A stages, plus its index entry when that is a link, so a
# staged link that was changed since is judged both ways; no content is read
# through a link: git commits the link text, not the target's content),
# case-insensitively, for a SUBSTRING: a listed name anywhere inside a longer
# token is a hit (so `acme-secret-repo` is found inside `acme-secret-repository`,
# `my-acme-secret-repo` and `apply-acme-secret-repo.yml`). Yves's ruling: the
# gate takes over the data guard's `grep -iF` matching.
#
# The FAIL lines name `file:line` for a content hit (`tracked path #N:line`
# when the path itself names a private name) and `tracked path #N in
# git ls-files` for a path hit, NEVER the name and never a matching path:
# sfl and FBP.sh quote FAIL lines and CI prints them on the job summary.
#
# --message <file> (FBP.sh, before anything else): searches only the text of
# <file>, a commit message, with the same list sources and the same substring,
# case-insensitive matching, and no repository scan. It prints nothing when
# the message is clean and ONE FAIL line, never the name nor the message, on a
# hit (exit 1). A message cannot be judged without a list, so no list at all,
# an env list or a names file with no names all pass (exit 0): locally FBP.sh
# makes an empty list itself, and CI never commits through FBP.sh. Exit 2 only
# when <file> cannot be read. FBP.sh hands the message in a temp file, never
# as an argument, so no trace or process list shows it.
#
# Exit 0 clean. Exit 1 a name found. Exit 2 when:
#   - there is no list at all (no env list, no names file);
#   - the env list FORSGREN_PRIVATE_NAMES has no names (an emptied CI secret);
#   - the names file FORSGREN_PRIVATE_NAMES_FILE names does not exist;
#   - there is no tracked or untracked file (the scan read nothing);
#   - a tracked or untracked path (or the blob of a tracked symlink) could not
#     be read: `tracked path #N could not be read`, by number only, since
#     grep's own message would print the path (its stderr is discarded).
#     A scan that could not read is not a clean scan. Precedence: when a name
#     was also found, exit 1 stays (a name found outranks an unreadable file).
# An EXISTING names file with no names (zero bytes, blanks, comments) is not
# an error: the scan still lists every path (so the count and the `scan read
# nothing` check stay right) but searches nothing, finds nothing and exits 0
# with `0 names searched`. With no names nothing is searched, so the result does
# not depend on how a grep treats an empty pattern list (some match every
# line). No file's content is read then either, so an unreadable FILE is not
# reported. A symlink is different: its target text is read while the paths
# are listed, before any name is searched, so a tracked symlink whose blob
# cannot be read (or an untracked one whose readlink fails) is still reported
# as `could not be read` and exits 2 at 0 names. In CI the secret is the only
# source, so CI always fails without it or with an emptied one (fork pull
# requests included).
#
# The names never touch the disk: they are held in a variable and handed to
# grep through a process substitution (-f /dev/fd/N), so no process list,
# trace or temp file shows them, and no temp file is left behind when the
# gate is killed.
#
# Known limit: names are matched as BYTES in the file's own encoding. A file
# in an encoding that is not ASCII-compatible (UTF-16 or UTF-32, with or
# without a byte-order mark; EBCDIC) stores an ASCII name as other bytes (in
# UTF-16 a zero byte between the letters), so the gate does not search such a
# file effectively: a name in it is not found, and the file passes.

set -euo pipefail
# Tracing off: the list must never reach a trace (bash -x, or a CI debug run).
set +x

# The list parsing, shared with Scripts/sync_private_names_secrets.sh.
# Sourced from beside this script, before the cd below into the repository.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=Scripts/lib_private_names.sh
source "${ROOT}/Scripts/lib_private_names.sh"

# 1 in --message mode: a missing or empty list passes (see the header).
MESSAGE_MODE=0

# read_list: the raw list text in LIST, from the first source that has one;
# SOURCE is env or file.
read_list() {
  if [[ -n "${FORSGREN_PRIVATE_NAMES:-}" ]]; then
    LIST="$FORSGREN_PRIVATE_NAMES"
    SOURCE="env"
    return 0
  fi
  local file
  file="$(private_names_file)"
  if [[ ! -f "$file" ]]; then
    [[ "$MESSAGE_MODE" -eq 1 ]] && exit 0
    if [[ -n "${FORSGREN_PRIVATE_NAMES_FILE:-}" ]]; then
      echo "❌ FAIL: the private-names file ${file} does not exist"
    else
      echo "❌ FAIL: no list of private names: set FORSGREN_PRIVATE_NAMES (newline-separated) or FORSGREN_PRIVATE_NAMES_FILE, or create ~/.config/forsgren/private-names"
    fi
    exit 2
  fi
  LIST="$(cat "$file")"
  SOURCE="file"
}

# build_patterns: one ERE per name, newline-separated, in PATTERNS,
# regex-escaped, no boundary (a substring match). Sets COUNT to the number of
# names; exit 2 on none in an env list. The patterns stay in this variable and
# never touch the disk: grep reads them through match_names below. An existing
# file with no names gives empty PATTERNS, which are never handed to grep
# (judge_path and check_message skip them at 0 names).
build_patterns() {
  private_names_parse "$LIST"
  COUNT="$PRIVATE_NAMES_COUNT"
  PATTERNS="$(printf '%s' "$PRIVATE_NAMES" | sed 's/[][\.*^$+?(){}|/]/\\&/g')"
  if [[ "$COUNT" -eq 0 && "$SOURCE" == env && "$MESSAGE_MODE" -eq 0 ]]; then
    echo "❌ FAIL: the list of private names in FORSGREN_PRIVATE_NAMES has no names in it: an emptied secret is not a clean scan"
    exit 2
  fi
}

# match_names <grep options...>: grep -i -E with the escaped names as its
# pattern list and the caller's options and operands. The list goes in through
# a process substitution (-f /dev/fd/N), never as an argument and never as a
# file: a process list shows no name, and a SIGKILL leaves none on disk.
# PATTERNS holds no trailing newline (command substitution strips it), so the
# pattern list holds no empty line, which would match every line.
match_names() {
  grep -i -E -f <(printf '%s\n' "$PATTERNS") "$@"
}

# judge_path <path> <link-target-or-empty> <is-link 0|1> [index-target]: judges
# one path, its symlink target text (the working tree's, and the index
# entry's when given) and its content (not for a link); counts it in N (the numbering
# runs over the tracked list, then the untracked one). Sets FOUND to 1 on a hit.
judge_path() {
  local path="$1" target="$2" islink="$3" shown hits hit lineno rc
  N=$((N + 1))
  # No names: nothing to search, and grep is not asked (see the header).
  [[ "$COUNT" -eq 0 ]] && return 0
  shown="$path"
  # A here-string, not a pipe: under pipefail, grep -q closing the pipe early
  # can SIGPIPE the printf and turn a match into a miss.
  if match_names -q <<< "$path" 2>/dev/null; then
    echo "❌ FAIL: tracked path #${N} in git ls-files names a private name"
    FOUND=1
    shown="tracked path #${N}"
  fi
  # A symlink is judged by its target text, which may dangle.
  if [[ "$islink" -eq 1 ]] && match_names -q <<< "$target" 2>/dev/null; then
    echo "❌ FAIL: tracked path #${N} (link target) names a private name"
    FOUND=1
  elif [[ -n "${4:-}" ]] && match_names -q <<< "$4" 2>/dev/null; then
    echo "❌ FAIL: tracked path #${N} (link target) names a private name"
    FOUND=1
  fi
  # No content through a link: git commits the link text, not the target file.
  [[ "$islink" -eq 1 ]] && return 0
  [[ -f "$path" ]] || return 0
  # grep exits 0 on a hit, 1 on none, above 1 when it could not read the file.
  # Its stderr names the path, so it goes nowhere; the failure is told by number.
  rc=0
  hits="$(match_names -a -n -- "$path" 2>/dev/null)" || rc=$?
  if [[ "$rc" -gt 1 ]]; then
    echo "❌ FAIL: tracked path #${N} could not be read: a file that cannot be read cannot be judged"
    UNREAD=1
    return 0
  fi
  [[ -z "$hits" ]] && return 0
  while IFS= read -r hit; do
    lineno=${hit%%:*}
    echo "❌ FAIL: ${shown}:${lineno} names a private name"
    FOUND=1
  done <<< "$hits"
}

# scan_tracked: judges every tracked file (git ls-files), then every
# untracked, not-ignored one (git ls-files -o --exclude-standard: exactly what
# git add -A would stage). Sets N to the number of paths and FOUND to 1 on any hit.
scan_tracked() {
  local entry path mode sha target idx islink
  FOUND=0
  UNREAD=0
  N=0
  while IFS= read -r -d '' entry; do
    path="${entry#*$'\t'}"
    mode="${entry%% *}"
    sha="${entry#* }"
    sha="${sha%% *}"
    target=""
    idx=""
    islink=0
    if [[ -L "$path" ]]; then
      islink=1
      target="$(readlink -- "$path" 2>/dev/null)" || {
        N=$((N + 1))
        echo "❌ FAIL: tracked path #${N} could not be read: a file that cannot be read cannot be judged"
        UNREAD=1
        continue
      }
    fi
    if [[ "$mode" == 120000 ]]; then
      idx="$(git cat-file blob "$sha" 2>/dev/null)" || {
        N=$((N + 1))
        echo "❌ FAIL: tracked path #${N} could not be read: a file that cannot be read cannot be judged"
        UNREAD=1
        continue
      }
    fi
    judge_path "$path" "$target" "$islink" "$idx"
  done < <(git ls-files -s -z)
  while IFS= read -r -d '' path; do
    target=""
    if [[ -L "$path" ]]; then
      target="$(readlink -- "$path" 2>/dev/null)" || {
        N=$((N + 1))
        echo "❌ FAIL: tracked path #${N} could not be read: a file that cannot be read cannot be judged"
        UNREAD=1
        continue
      }
      judge_path "$path" "$target" 1
    else
      judge_path "$path" "" 0
    fi
  done < <(git ls-files -o --exclude-standard -z)
}

# check_message <file>: the --message mode; exits, never returns.
check_message() {
  local msg="$1"
  MESSAGE_MODE=1
  [[ -f "$msg" && -r "$msg" ]] || { echo "❌ FAIL: cannot read the commit message file"; exit 2; }
  read_list
  build_patterns
  [[ "$COUNT" -eq 0 ]] && exit 0
  local rc=0
  match_names -a -q -- "$msg" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "❌ FAIL: the commit message names a private name: reword it (Scripts/check_private_names.sh)"
    exit 1
  fi
  if [[ "$rc" -gt 1 ]]; then
    echo "❌ FAIL: the commit message file could not be read"
    exit 2
  fi
  exit 0
}

if [[ "${1:-}" == "--message" ]]; then
  check_message "${2:-}"
fi

REPO="${1:-.}"
cd "$REPO" || { echo "❌ FAIL: cannot enter ${REPO}"; exit 2; }

LIST=""
SOURCE=""
PATTERNS=""
read_list

build_patterns
scan_tracked

if [[ "$N" -eq 0 ]]; then
  echo "❌ FAIL: no tracked or untracked files: the scan read nothing"
  exit 2
fi

if [[ "$FOUND" -ne 0 ]]; then
  exit 1
fi
if [[ "$UNREAD" -ne 0 ]]; then
  exit 2
fi
echo "OK: no private name in ${N} tracked and untracked paths and files (${COUNT} names searched)"
