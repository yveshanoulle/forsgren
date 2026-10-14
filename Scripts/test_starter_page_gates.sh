#!/usr/bin/env bash
# Scripts/test_starter_page_gates.sh
#
# Self-test for Scripts/gate_htmlhint_starter.sh and
# Scripts/check_privacy_posture_starter.sh (forsgren#132), run in pre before
# the rows that lint the starter page. forsgren's own. The wrappers anchor
# themselves with `cd "$(dirname "$0")/.."`, so each case runs copies of them
# and of the gates they call from a throwaway root, with the repository's
# .htmlhintrc and a symlink to its node_modules (the REAL htmlhint, as
# Scripts/test_gate_htmlhint.sh does).
#   1. a well-formed starter page            -> both wrappers green
#   2. a page with an unpaired tag           -> HTMLHint wrapper red, tag-pair
#   3. a page with a form                    -> privacy wrapper red, the form
#   4. a missing .build/starter              -> both wrappers exit 2
#   5. an explicit directory argument        -> read instead of the default
# Mutation proof: case 2 against a copy of the HTMLHint wrapper that defaults
# to .build/site is green (the throwaway root holds a good page there), so
# case 2 is red BECAUSE the wrapper points at .build/starter.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "starter-page gates self-test"

for need in Scripts/gate_htmlhint_starter.sh Scripts/check_privacy_posture_starter.sh \
  .htmlhintrc node_modules/.bin/htmlhint; do
  [[ -e "$need" ]] || selftest_abort "${need} does not exist — the starter page gates cannot be validated (run npm ci)"
done

GOOD='<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>acme</title>
</head>
<body>
  <main>
    <p>acme/app</p>
  </main>
</body>
</html>
'

# new_root <name> — a throwaway root with the wrappers, the gates they call,
# the config and node_modules. ROOT is set.
new_root() {
  ROOT="${TMP}/$1"
  mkdir -p "${ROOT}/Scripts"
  cp Scripts/gate_htmlhint_starter.sh Scripts/gate_htmlhint.sh \
    Scripts/check_privacy_posture_starter.sh Scripts/check_privacy_posture.sh "${ROOT}/Scripts/"
  cp .htmlhintrc "$ROOT/"
  ln -s "${REPO_ROOT}/node_modules" "${ROOT}/node_modules"
}

# put_page <dir under ROOT> <html>
put_page() {
  mkdir -p "${ROOT}/$1"
  printf '%s' "$2" > "${ROOT}/$1/index.html"
}

new_root good
put_page .build/starter "$GOOD"
capture "${ROOT}/Scripts/gate_htmlhint_starter.sh"
want_green "1. a well-formed page passes HTMLHint" "Scanned 1 files, no errors found"
capture "${ROOT}/Scripts/check_privacy_posture_starter.sh"
want_green_ok "1. a well-formed page passes the privacy posture"

new_root unpaired
put_page .build/starter "${GOOD/<main>/<main><div>}"
put_page .build/site "$GOOD"
capture "${ROOT}/Scripts/gate_htmlhint_starter.sh"
want_red "2. an unpaired tag fails HTMLHint" "tag-pair"
UNPAIRED="$ROOT"

new_root form
put_page .build/starter "${GOOD/<main>/<main><form action=\"/x\"></form>}"
capture "${ROOT}/Scripts/check_privacy_posture_starter.sh"
want_exit "3. a form fails the privacy posture" 1 "a form collects input"

new_root missing
capture "${ROOT}/Scripts/gate_htmlhint_starter.sh"
want_exit "4. no .build/starter fails HTMLHint with exit 2" 2 "site dir not found"
capture "${ROOT}/Scripts/check_privacy_posture_starter.sh"
want_exit "4. no .build/starter fails the privacy posture with exit 2" 2 "site dir not found"

put_page elsewhere "$GOOD"
capture "${ROOT}/Scripts/gate_htmlhint_starter.sh" "${ROOT}/elsewhere"
want_green "5. an explicit directory is read instead" "Scanned 1 files, no errors found"

if selftest_mutant Scripts/gate_htmlhint_starter.sh "${UNPAIRED}/Scripts/gate_htmlhint_starter.sh" 's#\.build/starter#.build/site#'; then
  capture "${UNPAIRED}/Scripts/gate_htmlhint_starter.sh"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: a wrapper that defaults to .build/site passes case 2's page"
  else
    fail "mutation proof: case 2 stays red under a wrapper that defaults to .build/site (exit ${RC}). Output: ${OUT}"
  fi
fi

selftest_end "the starter-page gates self-test found failures" "starter-page gates self-test (cases and a mutation proof)"
