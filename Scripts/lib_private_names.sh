#!/usr/bin/env bash
# canon: lib_private_names v2
# Scripts/lib_private_names.sh
#
# (refactor): the one reading of the private-names list, shared
# by the gate (Scripts/check_private_names.sh) and the secret sync
# (Scripts/sync_private_names_secrets.sh), which used to carry a copy each.
# It parses list TEXT; the callers choose the source (the gate takes env
# FORSGREN_PRIVATE_NAMES first, the sync only ever the file).
#
# SOURCED, never run. It judges nothing on its own: the self-tests of its two
# consumers are what test it. It sets no shell options and no traps; the
# sourcing script owns those, and must turn tracing off (`set +x`) BEFORE it
# sources this file, so no name it handles can reach a trace. It prints
# nothing: the names stay in variables.

# private_names_file: prints the path of the local list file,
# FORSGREN_PRIVATE_NAMES_FILE, else ${HOME}/.config/forsgren/private-names.
# A path, never a name.
private_names_file() {
  printf '%s' "${FORSGREN_PRIVATE_NAMES_FILE:-${HOME:-/nonexistent}/.config/forsgren/private-names}"
}

# private_names_file_given: succeeds when FORSGREN_PRIVATE_NAMES_FILE names a
# file. An EMPTY variable names none: it counts as unset, here and in
# private_names_file's fallback, so the gate and the pre-flight helper
# agree.
private_names_file_given() {
  [[ -n "${FORSGREN_PRIVATE_NAMES_FILE:-}" ]]
}

# origin_repo_name <repo-dir>: prints the basename of the origin remote URL of
# <repo-dir> without .git (https, scp and ssh forms). Returns non-zero,
# printing nothing, when there is no origin or no name in it. The one parse,
# used by the extra-list lookup and by the gate's own-name rule.
origin_repo_name() {
  local url name
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  name="${url##*/}"
  name="${name##*:}"
  name="${name%.git}"
  [[ -n "$name" ]] || return 1
  printf '%s' "$name"
}

# private_names_extra_file <repo-dir>: prints the path of the repository's
# EXTRA list file: FORSGREN_PRIVATE_NAMES_EXTRA_FILE when set and not empty,
# else ${HOME}/.config/forsgren/private-names-extra/<name>, <name> being the
# basename of the origin remote URL of <repo-dir> without .git. Returns
# non-zero, printing nothing, when there is no variable and no origin to name
# the file after. A path, never a name.
private_names_extra_file() {
  local name
  if [[ -n "${FORSGREN_PRIVATE_NAMES_EXTRA_FILE:-}" ]]; then
    printf '%s' "$FORSGREN_PRIVATE_NAMES_EXTRA_FILE"
    return 0
  fi
  name="$(origin_repo_name "$1")" || return 1
  printf '%s' "${HOME:-/nonexistent}/.config/forsgren/private-names-extra/${name}"
}

# private_names_extra_read <repo-dir> <variable>: the raw text of the EXTRA
# list in the shell variable named <variable>: env FORSGREN_PRIVATE_NAMES_EXTRA
# (the CI secret) and the extra file, when each is there, one after the
# other. An absent extra list is not an error and leaves the variable empty.
# Returns non-zero, printing nothing, when the extra file exists but cannot be
# read.
private_names_extra_read() {
  local file text="" part
  file="$(private_names_extra_file "$1")" || file=""
  if [[ -n "${FORSGREN_PRIVATE_NAMES_EXTRA:-}" ]]; then
    text="$FORSGREN_PRIVATE_NAMES_EXTRA"
  fi
  if [[ -n "$file" && -e "$file" ]]; then
    part="$(cat "$file" 2>/dev/null)" || return 1
    text+=$'\n'"$part"
  fi
  printf -v "$2" '%s' "$text"
}

# private_names_read <file> <variable>: the raw text of <file> in the shell
# variable named <variable>. Returns non-zero, printing nothing (cat's own
# message would name the path; the callers print their own one FAIL line),
# when <file> cannot be read.
private_names_read() {
  local text
  text="$(cat "$1" 2>/dev/null)" || return 1
  printf -v "$2" '%s' "$text"
}

# private_names_parse <text>: the names in <text>, one per line, each
# followed by a newline, in PRIVATE_NAMES; their number in
# PRIVATE_NAMES_COUNT. A trailing \r and surrounding whitespace are stripped;
# blank lines and lines starting with # are not names.
private_names_parse() {
  local line
  PRIVATE_NAMES=""
  PRIVATE_NAMES_COUNT=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    PRIVATE_NAMES+="${line}"$'\n'
    PRIVATE_NAMES_COUNT=$((PRIVATE_NAMES_COUNT + 1))
  done <<< "$1"
}
