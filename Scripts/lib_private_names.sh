#!/usr/bin/env bash
# Scripts/lib_private_names.sh
#
# forsgren#52 (refactor): the one reading of the private-names list, shared
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
