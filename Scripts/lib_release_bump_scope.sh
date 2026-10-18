#!/usr/bin/env bash
# Scripts/lib_release_bump_scope.sh
#
# forsgren#230: the files a release bump may change, read from
# Scripts/release_bump_scope.txt, so the bump that rewrites them
# (Scripts/release_bump.sh) and the check of the bump commit
# (Scripts/release_bump_diff.sh) share one list.
#
# SOURCED, never run. It sets no shell options. It works relative to the
# current directory, the repository root, which both callers cd to.

BUMP_SCOPE_FILE="$(dirname "${BASH_SOURCE[0]}")/release_bump_scope.txt"

# bump_scope_rows [kind...]: the rows of the scope file (kind|path|pattern),
# only of the kinds given, all of them without an argument.
bump_scope_rows() {
  local row kind want
  while IFS= read -r row; do
    case "$row" in '#'* | '') continue ;; esac
    kind="${row%%|*}"
    if [ "$#" -eq 0 ]; then
      printf '%s\n' "$row"
      continue
    fi
    for want in "$@"; do
      if [ "$kind" = "$want" ]; then printf '%s\n' "$row"; fi
    done
  done < "$BUMP_SCOPE_FILE"
}

# bump_scope_list [kind...]: the existing files of those rows, sorted, once.
bump_scope_list() {
  local row kind rest path pattern
  while IFS= read -r row; do
    kind="${row%%|*}"
    rest="${row#*|}"
    path="${rest%%|*}"
    pattern="${rest#*|}"
    case "$kind" in
      tree) find "$path" -type f -name "*${pattern}" ;;
      dir) find "$path" -maxdepth 1 -type f -name "*${pattern}" ;;
      file) if [ -f "$path" ]; then printf '%s\n' "$path"; fi ;;
    esac
  done < <(bump_scope_rows "$@") | LC_ALL=C sort -u
}

# bump_scope_allows <path>: 0 when the bump may change that file.
bump_scope_allows() {
  local target="$1" row kind rest path pattern name
  name="${target##*/}"
  while IFS= read -r row; do
    kind="${row%%|*}"
    rest="${row#*|}"
    path="${rest%%|*}"
    pattern="${rest#*|}"
    case "$kind" in
      tree) case "$target" in "${path}/"*) [[ "$name" == *"$pattern" ]] && return 0 ;; esac ;;
      dir) [ "${target%/*}" = "$path" ] && [[ "$name" == *"$pattern" ]] && return 0 ;;
      file) [ "$target" = "$path" ] && return 0 ;;
    esac
  done < <(bump_scope_rows)
  return 1
}
