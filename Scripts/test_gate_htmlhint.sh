#!/usr/bin/env bash
# Scripts/test_gate_htmlhint.sh
#
# Self-test for Scripts/gate_htmlhint.sh, the HTMLHint post gate (forsgren#1,
# ladder step 8), run in PRE before the gate it validates.
#
# NEW IN forsgren. No repo of the estate has a self-test for its HTMLHint
# gate: there it runs unvalidated, and a gate that never read its config, or
# whose glob matched nothing, would sit green. forsgren's rule is that a
# ported gate comes with its fixtures, seen green, plus one mutation seen red,
# so this file is forsgren's own.
#
# The REAL htmlhint from node_modules/.bin (sfl's `npm ci` puts it there),
# never a fake: this pins what the gate does with the actual tool and the
# actual .htmlhintrc. The gate anchors itself with `cd "$(dirname "$0")/.."`,
# so each case runs a copy of it from Scripts/ of a throwaway root that holds
# a copy of .htmlhintrc and a symlink to the repository's node_modules.
#   1. a well-formed page                        -> green, 1 file scanned
#   2. an unpaired tag                           -> red, naming tag-pair
#   3. a site directory with no .html in it      -> exit 2, nothing linted
#   4. a site directory that does not exist      -> exit 2
# Mutation proofs:
#   A. case 2 under an .htmlhintrc with tag-pair turned off must turn green,
#      so case 2 is red BECAUSE the gate reads that config's rule;
#   B. case 3 against a copy of the gate without its zero-files check must
#      turn green, so case 3 is red BECAUSE of that check.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
GATE="${REPO_ROOT}/Scripts/gate_htmlhint.sh"
CONFIG="${REPO_ROOT}/.htmlhintrc"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "HTMLHint self-test"

for need in "$GATE" "$CONFIG" "${REPO_ROOT}/node_modules/.bin/htmlhint"; do
  [[ -e "$need" ]] || selftest_abort "${need} does not exist — the HTMLHint gate cannot be validated (run npm ci)"
done

GOOD_PAGE='<!doctype html>
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
BAD_PAGE='<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>acme</title>
</head>
<body>
  <main>
    <p>acme/app
  </main>
</body>
</html>
'

# new_root <name> [gate-copy] [config-copy] — a throwaway root with the gate
# (or the given copy) at Scripts/gate_htmlhint.sh, the config (or the given
# copy) at .htmlhintrc, and the repository's node_modules linked in.
new_root() {
  ROOT="${TMP}/$1"
  mkdir -p "${ROOT}/Scripts"
  cp "${2:-$GATE}" "${ROOT}/Scripts/gate_htmlhint.sh"
  chmod +x "${ROOT}/Scripts/gate_htmlhint.sh"
  cp "${3:-$CONFIG}" "${ROOT}/.htmlhintrc"
  ln -s "${REPO_ROOT}/node_modules" "${ROOT}/node_modules"
}

# new_site <name> [page-content] — a site directory, with index.html when
# content is given.
new_site() {
  SITE="${TMP}/sites/$1"
  mkdir -p "$SITE"
  if [[ -n "${2:-}" ]]; then
    printf '%s' "$2" > "${SITE}/index.html"
  fi
}

# run_gate [site-dir] — runs the root's copy of the gate; sets RC and OUT.
run_gate() {
  capture "${ROOT}/Scripts/gate_htmlhint.sh" "${1:-$SITE}"
}

# --- 1. a well-formed page -> green ----------------------------------------
new_root good
new_site good "$GOOD_PAGE"
run_gate
want_exit "1. a well-formed page" 0 "Scanned 1 files, no errors found"

# --- 2. an unpaired tag -> red, naming the rule ----------------------------
new_root bad
new_site bad "$BAD_PAGE"
run_gate
want_exit "2. an unpaired tag" 1 "(tag-pair)"

# --- 3. no .html under the site -> exit 2 ----------------------------------
new_root empty
new_site empty
printf 'body {\n  margin: 0;\n}\n' > "${SITE}/styles.css"
run_gate
want_exit "3. a site directory with no .html in it" 2 \
  "scanned 0 files under ${SITE} — nothing linted is not clean"

# --- 4. a missing site directory -> exit 2 ---------------------------------
new_root missing
run_gate "${TMP}/sites/does-not-exist"
want_exit "4. a site directory that does not exist" 2 "htmlhint: site dir not found"

# --- Mutation proof A: the config's rule is what reds case 2 ---------------
MUTANT_CONFIG="${TMP}/htmlhintrc.no-tag-pair"
if selftest_mutant "$CONFIG" "$MUTANT_CONFIG" 's/"tag-pair": true/"tag-pair": false/'; then
  new_root mutant-config "$GATE" "$MUTANT_CONFIG"
  new_site mutant-config "$BAD_PAGE"
  run_gate
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof A: case 2 is still red with tag-pair turned off, so its red does not come from the config's rule. Output: ${OUT}"
  else
    echo "  ok: mutation proof A: case 2 turns green with tag-pair turned off in .htmlhintrc"
  fi
fi

# --- Mutation proof B: the zero-files check is what reds case 3 ------------
MUTANT_GATE="${TMP}/gate_htmlhint.no-zero-check.sh"
if selftest_mutant "$GATE" "$MUTANT_GATE" "s/'Scanned 0 files'/'no-such-line'/"; then
  new_root mutant-gate "$MUTANT_GATE"
  new_site mutant-gate
  run_gate
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof B: case 3 is still red with the zero-files check removed, so its red does not come from that check. Output: ${OUT}"
  else
    echo "  ok: mutation proof B: case 3 turns green with the zero-files check removed"
  fi
fi

selftest_end "HTMLHint self-test" \
  "HTMLHint gate passes a well-formed page, reads .htmlhintrc, and is red on a broken page, on zero files linted and on a missing site"
