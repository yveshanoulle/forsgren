#!/usr/bin/env bash
# canon: test_gate_stylelint v1
# Scripts/test_gate_stylelint.sh
#
# Self-test for Scripts/gate_stylelint.sh, the Stylelint post gate, run in PRE
# before the gate it validates. Ported from forsgren's
# self-test and extended with the fix mode.
#
# The REAL stylelint from node_modules/.bin (sfl's `npm ci` puts it there),
# never a fake: this pins what the gate does with the actual tool and the
# actual .stylelintrc.json. The gate anchors itself with
# `cd "$(dirname "$0")/.."`, so each case runs a copy of it from Scripts/ of a
# throwaway root that holds a copy of .stylelintrc.json, the settings lib and
# file, and a symlink to the repository's node_modules (where the shared
# configs it extends resolve). Every case runs with GATE_FIX unset unless it
# sets it: sfl.sh exports GATE_FIX=1 to the self-tests it runs, and a case that
# inherited it would test the wrong mode.
#   1. a clean stylesheet                       -> green
#   2. #ffffff where the standard config wants #fff
#                                               -> red, naming color-hex-length
#   3. a site directory with no .css in it      -> red (exit 1, stylelint's own), nothing linted
#   4. a site directory that does not exist     -> exit 2
#   5. no argument: the site dir comes from site_settings.txt
#   6. a default run is CHECK-ONLY: red, and the bad file is left unchanged
#   7. GATE_FIX=1 fixes the file and is green
# Mutation proofs:
#   A. case 2 under a .stylelintrc.json with color-hex-length turned off must
#      turn green, so case 2 is red BECAUSE the gate loads that config;
#   B. case 6 against a copy of the gate that always fixes must no longer
#      hold (the file changes and the run is green).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
GATE="${REPO_ROOT}/Scripts/gate_stylelint.sh"
CONFIG="${REPO_ROOT}/.stylelintrc.json"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "Stylelint self-test"

for need in "$GATE" "$CONFIG" "${REPO_ROOT}/node_modules/.bin/stylelint"; do
  [[ -e "$need" ]] || selftest_abort "${need} does not exist — the Stylelint gate cannot be validated (run npm ci)"
done

GOOD_CSS='body {
  margin: 0;
  color: #fff;
}
'
BAD_CSS='body {
  margin: 0;
  color: #ffffff;
}
'

# new_root <name> [config-copy] [gate-copy] — a throwaway root with the gate (or
# the given copy) at Scripts/gate_stylelint.sh, the config (or the given copy)
# at .stylelintrc.json, the settings lib and file, and node_modules linked in.
new_root() {
  ROOT="${TMP}/$1"
  mkdir -p "${ROOT}/Scripts"
  cp "${3:-$GATE}" "${ROOT}/Scripts/gate_stylelint.sh"
  chmod +x "${ROOT}/Scripts/gate_stylelint.sh"
  cp "${2:-$CONFIG}" "${ROOT}/.stylelintrc.json"
  cp "${REPO_ROOT}/Scripts/lib_site_settings.sh" "${REPO_ROOT}/Scripts/site_settings.txt" "${ROOT}/Scripts/"
  ln -s "${REPO_ROOT}/node_modules" "${ROOT}/node_modules"
}

# new_site <name> [css-content] — a site directory, with styles.css when
# content is given.
new_site() {
  SITE="${TMP}/sites/$1"
  mkdir -p "$SITE"
  if [[ -n "${2:-}" ]]; then
    printf '%s' "$2" > "${SITE}/styles.css"
  fi
}

# run_gate [site-dir] — runs the root's copy of the gate in check-only mode.
run_gate() {
  capture env -u GATE_FIX "${ROOT}/Scripts/gate_stylelint.sh" "${1:-$SITE}"
}

# run_gate_fix [site-dir] — the same with GATE_FIX=1.
run_gate_fix() {
  capture env GATE_FIX=1 "${ROOT}/Scripts/gate_stylelint.sh" "${1:-$SITE}"
}

# --- 1. a clean stylesheet -> green ----------------------------------------
new_root good
new_site good "$GOOD_CSS"
run_gate
want_green "1. a clean stylesheet"

# --- 2. a standard-config violation -> red, naming the rule ----------------
new_root bad
new_site bad "$BAD_CSS"
run_gate
want_red "2. #ffffff where the standard config wants #fff" "color-hex-length"

# --- 3. no .css under the site -> red --------------------------------------
new_root empty
new_site empty
printf '<!doctype html>\n<title>acme</title>\n' > "${SITE}/index.html"
run_gate
want_exit "3. a site directory with no .css in it" 1 "No files matching the pattern"

# --- 4. a missing site directory -> exit 2 ---------------------------------
new_root missing
run_gate "${TMP}/sites/does-not-exist"
want_exit "4. a site directory that does not exist" 2 "stylelint: site dir not found"

# --- 5. no argument: the site dir comes from site_settings.txt ---------------
new_root settings
mkdir -p "${ROOT}/pages"
printf '%s' "$BAD_CSS" > "${ROOT}/pages/styles.css"
printf 'site_dir=pages\nhtml_dupl_target=pages\nhtml_dupl_ceiling=1.0\nrequired_pages_manifest=m.json\n' > "${ROOT}/Scripts/site_settings.txt"
capture env -u GATE_FIX "${ROOT}/Scripts/gate_stylelint.sh"
want_red "5. the site dir from site_settings.txt" "color-hex-length"

# --- 6. a default run is check-only: red, file unchanged ---------------------
new_root checkonly
new_site checkonly "$BAD_CSS"
run_gate
want_red "6. a default run reports the violation" "color-hex-length"
if [[ "$(cat "${SITE}/styles.css")" == "$(printf '%s' "$BAD_CSS")" ]]; then
  echo "  ok: 6. a default run leaves the bad file unchanged"
else
  fail "6. a default run CHANGED the file: $(cat "${SITE}/styles.css")"
fi

# --- 7. GATE_FIX=1 fixes the file and is green --------------------------------
new_root fix
new_site fix "$BAD_CSS"
run_gate_fix
want_green "7. GATE_FIX=1 run is green"
if [[ "$(cat "${SITE}/styles.css")" == "$(printf '%s' "$GOOD_CSS")" ]]; then
  echo "  ok: 7. GATE_FIX=1 rewrote #ffffff to #fff"
else
  fail "7. GATE_FIX=1 did not fix the file: $(cat "${SITE}/styles.css")"
fi

# --- Mutation proof A: the config's rule is what reds case 2 ---------------
MUTANT_CONFIG="${TMP}/stylelintrc.no-color-hex-length.json"
if selftest_mutant "$CONFIG" "$MUTANT_CONFIG" 's/"rules": {/"rules": {\
    "color-hex-length": null,/'; then
  new_root mutant "$MUTANT_CONFIG"
  new_site mutant "$BAD_CSS"
  run_gate
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof A: case 2 is still red with color-hex-length turned off, so its red does not come from the config's rule. Output: ${OUT}"
  else
    echo "  ok: mutation proof A: case 2 turns green with color-hex-length turned off in .stylelintrc.json"
  fi
fi

# --- Mutation proof B: only GATE_FIX=1 makes the gate fix -------------------
if selftest_mutant "$GATE" "${TMP}/gate_stylelint.always-fix.sh" \
     "/^if \\[\\[ .*GATE_FIX/s/.*/if true; then/"; then
  new_root mutant-fix "$CONFIG" "${TMP}/gate_stylelint.always-fix.sh"
  new_site mutant-fix "$BAD_CSS"
  run_gate
  if [[ "$RC" -eq 0 && "$(cat "${SITE}/styles.css")" == "$(printf '%s' "$GOOD_CSS")" ]]; then
    echo "  ok: mutation proof B: a gate that always fixes turns case 6 green and rewrites the file"
  else
    fail "mutation proof B: the always-fix gate did not change case 6's outcome (exit ${RC}), so case 6 does not prove check-only. Output: ${OUT}"
  fi
fi

selftest_end "Stylelint self-test" \
  "Stylelint gate passes a clean stylesheet, loads .stylelintrc.json, is red on a violation, on zero files linted and on a missing site, checks only by default and fixes only under GATE_FIX=1"
