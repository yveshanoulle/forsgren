#!/usr/bin/env bash
# Scripts/test_gate_stylelint.sh
#
# Self-test for Scripts/gate_stylelint.sh, the Stylelint post gate (forsgren#1,
# ladder step 8), run in PRE before the gate it validates.
#
# NEW IN forsgren. No repo of the estate has a self-test for its Stylelint
# gate: there it runs unvalidated, and a gate that never loaded its config, or
# whose glob matched nothing, would sit green. forsgren's rule is that a
# ported gate comes with its fixtures, seen green, plus one mutation seen red,
# so this file is forsgren's own.
#
# The REAL stylelint from node_modules/.bin (sfl's `npm ci` puts it there),
# never a fake: this pins what the gate does with the actual tool and the
# actual .stylelintrc.json. The gate anchors itself with
# `cd "$(dirname "$0")/.."`, so each case runs a copy of it from Scripts/ of a
# throwaway root that holds a copy of .stylelintrc.json and a symlink to the
# repository's node_modules (where the shared configs it extends resolve).
#   1. a clean stylesheet                       -> green
#   2. #ffffff where the standard config wants #fff
#                                               -> red, naming color-hex-length
#   3. a site directory with no .css in it      -> red, nothing linted
#   4. a site directory that does not exist     -> exit 2
# Mutation proof: case 2 under a .stylelintrc.json with color-hex-length
# turned off must turn green, so case 2 is red BECAUSE the gate loads that
# config (color-hex-length comes from stylelint-config-standard, which it
# extends), not because of something else in the stylesheet.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
GATE="${REPO_ROOT}/Scripts/gate_stylelint.sh"
CONFIG="${REPO_ROOT}/.stylelintrc.json"

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: Stylelint self-test aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

for need in "$GATE" "$CONFIG" "${REPO_ROOT}/node_modules/.bin/stylelint"; do
  if [[ ! -e "$need" ]]; then
    fail "${need} does not exist — the Stylelint gate cannot be validated (run npm ci)"
    COMPLETED=1
    exit 1
  fi
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

# new_root <name> [config-copy] — a throwaway root with the gate at
# Scripts/gate_stylelint.sh, the config (or the given copy) at
# .stylelintrc.json, and the repository's node_modules linked in.
new_root() {
  ROOT="${TMP}/$1"
  mkdir -p "${ROOT}/Scripts"
  cp "$GATE" "${ROOT}/Scripts/gate_stylelint.sh"
  chmod +x "${ROOT}/Scripts/gate_stylelint.sh"
  cp "${2:-$CONFIG}" "${ROOT}/.stylelintrc.json"
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

# run_gate [site-dir] — runs the root's copy of the gate; sets RC and OUT.
run_gate() {
  set +e
  OUT="$("${ROOT}/Scripts/gate_stylelint.sh" "${1:-$SITE}" 2>&1)"
  RC=$?
  set -e
}

# expect_green <case>
expect_green() {
  if [[ "$RC" -ne 0 ]]; then
    fail "$1: the gate exited ${RC} — want green. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# expect_red <case> <needle> [rc] — the gate failed (with rc, when given) and
# its output carries needle.
expect_red() {
  if [[ "$RC" -eq 0 ]]; then
    fail "$1: the gate passed — want red. Output: ${OUT}"
  elif [[ -n "${3:-}" && "$RC" -ne "$3" ]]; then
    fail "$1: the gate exited ${RC} — want ${3}. Output: ${OUT}"
  elif ! grep -Fq -- "$2" <<< "$OUT"; then
    fail "$1: the gate failed, but its output does not carry '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# --- 1. a clean stylesheet -> green ----------------------------------------
new_root good
new_site good "$GOOD_CSS"
run_gate
expect_green "1. a clean stylesheet"

# --- 2. a standard-config violation -> red, naming the rule ----------------
new_root bad
new_site bad "$BAD_CSS"
run_gate
expect_red "2. #ffffff where the standard config wants #fff" "color-hex-length"

# --- 3. no .css under the site -> red --------------------------------------
new_root empty
new_site empty
printf '<!doctype html>\n<title>acme</title>\n' > "${SITE}/index.html"
run_gate
expect_red "3. a site directory with no .css in it" "No files matching the pattern"

# --- 4. a missing site directory -> exit 2 ---------------------------------
new_root missing
run_gate "${TMP}/sites/does-not-exist"
expect_red "4. a site directory that does not exist" "stylelint: site dir not found" 2

# --- Mutation proof: the config's rule is what reds case 2 -----------------
MUTANT_CONFIG="${TMP}/stylelintrc.no-color-hex-length.json"
sed 's/"rules": {/"rules": {\
    "color-hex-length": null,/' "$CONFIG" > "$MUTANT_CONFIG"
if cmp -s "$CONFIG" "$MUTANT_CONFIG"; then
  fail "mutation proof: turning color-hex-length off changed nothing in ${CONFIG} — the sed no longer matches, so this proof proves nothing"
else
  new_root mutant "$MUTANT_CONFIG"
  new_site mutant "$BAD_CSS"
  run_gate
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof: case 2 is still red with color-hex-length turned off, so its red does not come from the config's rule. Output: ${OUT}"
  else
    echo "  ok: mutation proof: case 2 turns green with color-hex-length turned off in .stylelintrc.json"
  fi
fi

COMPLETED=1
if [[ "$failed" -ne 0 ]]; then
  echo "❌ FAIL: Stylelint self-test"
  exit 1
fi
echo "OK: Stylelint gate passes a clean stylesheet, loads .stylelintrc.json, and is red on a violation, on zero files linted and on a missing site"
