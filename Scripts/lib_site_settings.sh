#!/usr/bin/env bash
# canon: lib_site_settings v2
# Scripts/lib_site_settings.sh
#
# The one reader of Scripts/site_settings.txt, the per-repo VALUES the shared
# gate scripts need. This file is byte-identical across
# the site repos and holds no repo value: a repo's values live in its
# site_settings.txt, and a gate asks for them here instead of carrying them as
# argument defaults.
#
# SOURCED, never run. It sets no shell options.
#
#   site_settings_get <file> <key>   prints the value of <key>
#
# The format is minimal: one `key=value` per line, blank lines and lines
# starting with `#` are ignored. The whole file is validated on every call, and
# the call fails (status 1, a reason on stderr) when:
#   - the file is missing: there is no default and no fallback
#   - a required key is missing
#   - a key is unknown, a line is malformed, or a key is repeated
#   - a value is invalid for its key
#   - the key asked for is not a known key
#
# THE KEY SET IS CLOSED. A later step that needs a new key adds it to
# SITE_SETTINGS_KEYS here and to every repo's file in the same change. Every
# known key is required.

SITE_SETTINGS_KEYS="site_dir html_dupl_target html_dupl_ceiling required_pages_manifest"

# _site_settings_value_ok <key> <value>
_site_settings_value_ok() {
  case "$1" in
    html_dupl_ceiling) [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] ;;
    *)                 [[ "$2" =~ ^(\.?[A-Za-z0-9_][A-Za-z0-9_.-]*)(/\.?[A-Za-z0-9_][A-Za-z0-9_.-]*)*$ ]] ;;
  esac
}

site_settings_get() {
  local file="${1:-}" want="${2:-}" line key value n=0 seen=" " k found=""

  [ -f "$file" ] || { echo "site settings: file is missing: ${file}" >&2; return 1; }
  case " ${SITE_SETTINGS_KEYS} " in
    *" ${want} "*) ;;
    *) echo "site settings: unknown key '${want}' requested" >&2; return 1 ;;
  esac

  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in '' | '#'*) continue ;; esac
    if ! [[ "$line" =~ ^[a-z][a-z0-9_]*=[^[:space:]]+$ ]]; then
      echo "site settings: malformed line ${n} in ${file}: ${line}" >&2
      return 1
    fi
    key="${line%%=*}"
    value="${line#*=}"
    case " ${SITE_SETTINGS_KEYS} " in
      *" ${key} "*) ;;
      *) echo "site settings: unknown key '${key}' (line ${n} of ${file})" >&2; return 1 ;;
    esac
    case "$seen" in
      *" ${key} "*) echo "site settings: duplicate key '${key}' (line ${n} of ${file})" >&2; return 1 ;;
    esac
    if ! _site_settings_value_ok "$key" "$value"; then
      echo "site settings: invalid value for '${key}' (line ${n} of ${file}): ${value}" >&2
      return 1
    fi
    seen="${seen}${key} "
    [ "$key" = "$want" ] && found="$value"
  done < "$file"

  for k in $SITE_SETTINGS_KEYS; do
    case "$seen" in
      *" ${k} "*) ;;
      *) echo "site settings: required key '${k}' is missing from ${file}" >&2; return 1 ;;
    esac
  done

  printf '%s\n' "$found"
}
