#!/usr/bin/env bash
# Scripts/test_check_npm_lock_sync.sh
#
# Self-test for Scripts/check_npm_lock_sync.sh, the npm lockfile sync gate
# (forsgren#2, ladder step 1), run before the gate it validates.
#
# Each case builds a throwaway directory with a package.json and a
# package-lock.json and runs the gate on it (the gate takes the directory as
# its argument):
#   1. manifest and lockfile root agree                    -> green
#   2. a version drifted (lockfile says 1.9.1)             -> red, names the
#                                                             package, both
#                                                             versions and the fix
#   3. a dependency missing from the lockfile              -> red, names it
#   4. a dependency only the lockfile has                  -> red, names it
#   5. the lockfile has no root package entry              -> red
#   6. no package-lock.json                                -> red
# Mutation proof: case 2 against a copy of the gate with the comparison
# removed must turn green, so case 2 is red BECAUSE of the comparison.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="$(pwd)/Scripts/check_npm_lock_sync.sh"
FIX="npm install --package-lock-only"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "npm lockfile sync self-test"

[[ -f "$GATE" ]] || selftest_abort "${GATE} does not exist — the npm lockfile sync has no gate to validate"

MANIFEST='{
  "name": "acme-app",
  "private": true,
  "devDependencies": {
    "htmlhint": "1.9.2",
    "stylelint": "17.14.1"
  }
}
'

# lock_with <root-devDependencies-json> — a lockfile whose root entry declares
# those devDependencies.
lock_with() {
  printf '{"name":"acme-app","lockfileVersion":3,"requires":true,"packages":{"":{"name":"acme-app","devDependencies":%s}}}\n' "$1"
}

# new_dir <name> <manifest> <lockfile-or-empty> — a directory with the files;
# sets DIR.
new_dir() {
  DIR="${TMP}/$1"
  mkdir -p "$DIR"
  printf '%s' "$2" > "${DIR}/package.json"
  if [[ -n "$3" ]]; then
    printf '%s' "$3" > "${DIR}/package-lock.json"
  fi
}

IN_SYNC="$(lock_with '{"htmlhint":"1.9.2","stylelint":"17.14.1"}')"

new_dir sync "$MANIFEST" "$IN_SYNC"
capture "$GATE" "$DIR"
want_green_ok "1. manifest and lockfile root agree"

DRIFT="$(lock_with '{"htmlhint":"1.9.1","stylelint":"17.14.1"}')"
new_dir drift "$MANIFEST" "$DRIFT"
capture "$GATE" "$DIR"
want_red "2. a version drifted: names both versions" "htmlhint: package.json says 1.9.2, package-lock.json says 1.9.1"
want_said "2. a version drifted: gives the fix" "$FIX"
DRIFT_DIR="$DIR"

MISSING="$(lock_with '{"htmlhint":"1.9.2"}')"
new_dir missing "$MANIFEST" "$MISSING"
capture "$GATE" "$DIR"
want_red "3. a dependency missing from the lockfile" "stylelint: package.json says 17.14.1, package-lock.json does not list it"
want_said "3. missing: gives the fix" "$FIX"

EXTRA="$(lock_with '{"htmlhint":"1.9.2","stylelint":"17.14.1","jscpd":"4.2.4"}')"
new_dir extra "$MANIFEST" "$EXTRA"
capture "$GATE" "$DIR"
want_red "4. a dependency only the lockfile has" "jscpd: package-lock.json says 4.2.4, package.json does not list it"
want_said "4. extra: gives the fix" "$FIX"

new_dir noroot "$MANIFEST" '{"name":"acme-app","lockfileVersion":3,"packages":{}}'
capture "$GATE" "$DIR"
want_red "5. the lockfile has no root package entry" "has no root package entry"

new_dir nolock "$MANIFEST" ""
capture "$GATE" "$DIR"
want_red "6. no package-lock.json" "package-lock.json is missing"

# --- mutation proof: no comparison -> the drift fixture turns green --------
NO_COMPARE="s/elif \\\$y.v != \\\$x.v then/elif false then/"
selftest_mutant_green "$GATE" "${TMP}/mutant/Scripts/check_npm_lock_sync.sh" \
  "$NO_COMPARE" "$DRIFT_DIR" \
  "without the comparison the drifted lockfile passes, so case 2 is red because of it" \
  "the comparison-less gate still failed the drifted lockfile"

selftest_end "the npm lockfile sync gate does not hold" \
  "npm lockfile sync gate: in sync green; drift, missing and extra dependency, no root entry and no lockfile red; mutation proven"
