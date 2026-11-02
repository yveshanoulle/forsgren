#!/usr/bin/env bash
# canon: lib_tmp v2
# Scripts/lib_tmp.sh
#
# The one way a script of this repository makes a temp folder or file, so the
# path honours TMPDIR (the estate sweep; forsgren#612). On macOS a mktemp
# whose template has no path (a bare call, or -t <prefix>) ignores TMPDIR and
# writes to the per-user folder `getconf DARWIN_USER_TEMP_DIR` names
# (/var/folders/..., the internal disk), even when TMPDIR points at the build
# volume. Only a template with the path in it is honoured, so both functions
# put "${TMPDIR:-/tmp}" in theirs.
#
# v2 (found in another estate repository): the folder is TMPDIR without
# its trailing slashes. The macOS default TMPDIR ends in a slash (/var/folders/.../T/), and
# mktemp prints the template as given, so v1 printed .../T//<name>.XXXXXX. The
# file system reads that as one slash, but a tool that compares the path as
# text does not: node's path.join writes it with one slash, so the browser
# gate self-test's pgrep -f on its own path found no Chrome at all.
#
#   tmp_dir <name>    prints the path of a new folder  ${TMPDIR:-/tmp}/<name>.XXXXXX
#   tmp_file <name>   prints the path of a new file    ${TMPDIR:-/tmp}/<name>.XXXXXX
#
# <name> is one path component: an empty name or one with a slash (which
# would put the path outside TMPDIR, ../x) is refused with status 2 and a ❌
# line on stderr, and nothing is made. Use it as
#   TMP="$(tmp_dir my_selftest)"
# so a refusal stops a `set -e` caller.
#
# SOURCED, never run. It sets no shell options and no traps; the sourcing
# script owns those. Scripts/test_lib_tmp.sh is its self-test, and
# Scripts/check_bare_mktemp.sh is the gate that keeps every other call
# templated.

# tmp__name_ok <function> <name>: status 0 for a usable name, else the ❌
# line and status 2.
tmp__name_ok() {
  case "$2" in
    '')
      echo "❌ $1: an empty name; give one path component, e.g. $1 my_selftest" >&2
      return 2
      ;;
    */*)
      echo "❌ $1: the name '$2' has a slash, so the path would leave TMPDIR; give one path component" >&2
      return 2
      ;;
  esac
}

# tmp__root: ${TMPDIR:-/tmp} without its trailing slashes (a TMPDIR of only
# slashes is the root, printed empty, so the template starts with /<name>).
tmp__root() {
  local root="${TMPDIR:-/tmp}"
  while [[ "$root" == */ ]]; do
    root="${root%/}"
  done
  printf '%s' "$root"
}

tmp_dir() {
  tmp__name_ok tmp_dir "${1:-}" || return 2
  local root
  root="$(tmp__root)"
  mktemp -d "${root}/${1}.XXXXXX"
}

tmp_file() {
  tmp__name_ok tmp_file "${1:-}" || return 2
  local root
  root="$(tmp__root)"
  mktemp "${root}/${1}.XXXXXX"
}
