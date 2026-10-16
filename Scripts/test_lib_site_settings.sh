#!/usr/bin/env bash
# canon: test_lib_site_settings v2
# Scripts/test_lib_site_settings.sh
#
# Self-test of Scripts/lib_site_settings.sh, the one reader of
# Scripts/site_settings.txt. The lib is byte-identical
# across the site repos; what differs per repo is the DATA. So a gate never
# carries a per-repo value as an argument default: it asks the lib.
#
# Cases, each red with its own message:
#   - a key is read
#   - the file is missing (fail closed: no default, no fallback)
#   - a required key is missing
#   - an unknown key
#   - a malformed line
#   - a duplicate key
#   - an invalid value, and a key the lib does not know being asked for
# And the real Scripts/site_settings.txt is valid.
#
# MUTATION PROOF, built here: a copy of the lib that falls back to a default
# when the file is missing must be caught by the missing-file case.
#
# Runs from sfl.sh via the order file. Local:
#   ./Scripts/test_lib_site_settings.sh

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

LIB="Scripts/lib_site_settings.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "site-settings self-test"

# get <lib> <file> <key>: the lib in a fresh shell, so no case leaks into the next.
probe() {
  # shellcheck source=Scripts/lib_site_settings.sh
  ( source "$1" && site_settings_get "$2" "$3" )
}
get() { capture probe "$1" "$2" "$3"; }

write_settings() { printf '%s\n' "$@" > "${TMP}/settings.txt"; }

GOOD=(
  '# a comment'
  ''
  'site_dir=pages'
  'html_dupl_target=pages'
  'html_dupl_ceiling=12.5'
  'required_pages_manifest=pages/required-pages.json'
)

# 1. Reading a key.
write_settings "${GOOD[@]}"
get "$LIB" "${TMP}/settings.txt" site_dir
want_green "reads site_dir" "pages"
get "$LIB" "${TMP}/settings.txt" html_dupl_ceiling
want_green "reads html_dupl_ceiling" "12.5"
get "$LIB" "${TMP}/settings.txt" required_pages_manifest
want_green "reads required_pages_manifest" "pages/required-pages.json"

# 2. A missing file fails closed.
get "$LIB" "${TMP}/absent.txt" site_dir
want_red "a missing file is red" "file is missing"

# 3. A missing required key.
write_settings 'site_dir=pages' 'html_dupl_target=pages'
get "$LIB" "${TMP}/settings.txt" site_dir
want_red "a missing required key is red" "required key 'html_dupl_ceiling' is missing"

# 4. An unknown key.
write_settings "${GOOD[@]}" 'colour=blue'
get "$LIB" "${TMP}/settings.txt" site_dir
want_red "an unknown key is red" "unknown key 'colour'"

# 5. A malformed line.
write_settings "${GOOD[@]}" 'site dir = pages'
get "$LIB" "${TMP}/settings.txt" site_dir
want_red "a malformed line is red" "malformed line 7"

# 6. A duplicate key.
write_settings "${GOOD[@]}" 'site_dir=other'
get "$LIB" "${TMP}/settings.txt" site_dir
want_red "a duplicate key is red" "duplicate key 'site_dir'"

# 7. An invalid value.
write_settings 'site_dir=pages' 'html_dupl_target=pages' 'html_dupl_ceiling=high' 'required_pages_manifest=m.json'
get "$LIB" "${TMP}/settings.txt" site_dir
want_red "a non-numeric ceiling is red" "invalid value for 'html_dupl_ceiling'"

# 8. Asking for a key the lib does not know.
write_settings "${GOOD[@]}"
get "$LIB" "${TMP}/settings.txt" colour
want_red "asking for an unknown key is red" "unknown key 'colour'"

# 9. Path values: one optional leading dot per component.
path_settings() {
  write_settings "site_dir=$1" 'html_dupl_target=pages' 'html_dupl_ceiling=12.5' 'required_pages_manifest=m.json'
  get "${2:-$LIB}" "${TMP}/settings.txt" site_dir
}
for ok in '.build/site' 'a/.hidden'; do
  path_settings "$ok"
  want_green "a path with a leading-dot component is accepted: ${ok}" "$ok"
done
for bad in '..' '.' './x' 'x/../y' '..x' 'x//y' '/abs' 'x/'; do
  path_settings "$bad"
  want_red "a bad path is red: ${bad}" "invalid value for 'site_dir'"
done

# 10. The real file is valid, for every key.
for key in site_dir html_dupl_target html_dupl_ceiling required_pages_manifest; do
  get "$LIB" Scripts/site_settings.txt "$key"
  want_green "the real Scripts/site_settings.txt has ${key}"
done

# Mutation proof: a lib that falls back to a default when the file is missing.
# Its missing-file run must EXIT 0, which case 2 above rejects.
if selftest_mutant "$LIB" "${TMP}/mutant/lib_site_settings.sh" \
     '/file is missing/s/return 1/echo Site; return 0/'; then
  get "${TMP}/mutant/lib_site_settings.sh" "${TMP}/absent.txt" site_dir
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: a lib that falls back to a default for a missing file exits 0, so case 2 rejects it"
  else
    fail "mutation proof: the fallback mutant still failed (exit ${RC}), so case 2 would not tell it from the real lib. Output: ${OUT}"
  fi
fi

# Mutation proofs of the path regex, each asserting its reason.
if selftest_mutant "$LIB" "${TMP}/mutant/no_dot.sh" 's/\\\.?//g'; then
  path_settings '.build/site' "${TMP}/mutant/no_dot.sh"
  if [[ "$RC" -ne 0 && "$OUT" == *"invalid value for 'site_dir'"* ]]; then
    echo "  ok: mutation proof: without the optional dot, .build/site is rejected as an invalid value"
  else
    fail "mutation proof: the no-dot mutant did not reject .build/site as an invalid value (exit ${RC}). Output: ${OUT}"
  fi
fi
if selftest_mutant "$LIB" "${TMP}/mutant/many_dots.sh" 's/\\\.?\[A-Za-z0-9_\]/\\.*[A-Za-z0-9_]/g'; then
  path_settings '..x' "${TMP}/mutant/many_dots.sh"
  if [[ "$RC" -eq 0 && "$OUT" == "..x" ]]; then
    echo "  ok: mutation proof: allowing any number of leading dots accepts ..x, so the ..x case rejects it"
  else
    fail "mutation proof: the many-dots mutant still rejected ..x (exit ${RC}), so the ..x case would not tell it from the real lib. Output: ${OUT}"
  fi
fi

selftest_end "the site-settings reader does not fail closed" \
  "site-settings reader (reads keys; a missing file, a missing, unknown or duplicate key, a malformed line and a bad value are each red)"
