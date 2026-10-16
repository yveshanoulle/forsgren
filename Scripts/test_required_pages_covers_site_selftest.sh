#!/usr/bin/env bash
# canon: test_required_pages_covers_site_selftest v1
# Scripts/test_required_pages_covers_site_selftest.sh
#
# Self-test for Scripts/test_required_pages_covers_site.sh, the "manifest
# covers site" post gate, run in PRE before the gate it
# validates. The gate's own name already starts with test_, hence the
# _selftest suffix here. A gate that stopped reading the manifest, or a site
# directory that went empty, would otherwise sit green on the one real site.
#
# Every case builds a throwaway site and manifest and passes both as the
# gate's arguments; nothing here reads .build/site.
#   1. the manifest lists exactly the site's pages  -> green
#   2. a page served but not declared               -> red, naming the page
#   3. a page declared but not generated            -> red, naming the path
#   4. a site directory that does not exist         -> red, "not found"
#   5. a site directory with no .html in it         -> red, "no .html page"
#   6. a manifest that does not exist               -> red, "not found"
#   7. pages in subfolders, declared as /dir/       -> green 
#   8. a subfolder page that is not declared        -> red, naming the page
#   9. a subfolder page declared but not generated  -> red, naming the path
#  10. the site directory given with a trailing /  -> green
#  11. a page listed in the exclusions file           -> green, skipped by name
#  12. an exclusions file that does not exist         -> red, "not found"
#  13. an exclusion row without a reason              -> red, naming the line
# Mutation proofs:
#   A. case 5 against a copy of the gate without its zero-pages check must
#      lose the "no .html page" reason, so that reason comes from that check
#      (the copy still exits 1, silently: see the gate's header);
#   B. case 4 against a copy of the gate without its site-directory check
#      must lose the "not found" reason, so that reason comes from that check;
#   C. case 2 against a copy of the gate that never reds an undeclared page
#      must exit 0;
#   D. case 3 against a copy of the gate that never reds a declared page that
#      does not exist must exit 0;
#   E. case 11 against a copy of the gate that ignores the exclusions file
#      must be red, so the page is skipped BECAUSE of its row.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="Scripts/test_required_pages_covers_site.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "manifest-covers-site self-test"

# new_site <name> [page ...] — a site directory holding the named pages.
new_site() {
  SITE="${TMP}/sites/$1"
  mkdir -p "$SITE"
  shift
  local page
  for page in "$@"; do
    mkdir -p "$(dirname "${SITE}/${page}")"
    printf '<!doctype html>\n<title>acme</title>\n' > "${SITE}/${page}"
  done
}

# new_manifest <name> <json> — a manifest file.
new_manifest() {
  MANIFEST="${TMP}/$1.json"
  printf '%s\n' "$2" > "$MANIFEST"
}

# run_gate <gate> <site> <manifest> [exclusions] — sets RC and OUT. Without an
# exclusions argument the gate reads the repository's own file.
run_gate() {
  capture "$1" "$2" "$3" ${4:+"$4"}
}

# mutant <name> <sed-expression> — a copy of the gate with one check removed,
# in a root of its own (the gate works from its parent directory and sources the
# settings reader there); MUTANT is its path. Refuses a sed that changed nothing.
mutant() {
  local root="${TMP}/mutants/$1"
  mkdir -p "${root}/Scripts"
  cp Scripts/lib_site_settings.sh Scripts/site_settings.txt Scripts/required_pages_exclusions.txt "${root}/Scripts/"
  MUTANT="${root}/Scripts/test_required_pages_covers_site.sh"
  selftest_mutant "$GATE" "$MUTANT" "$2"
}

# --- 1. manifest and site agree -> green ------------------------------------
new_site match index.html status.html
new_manifest match '{"requiredPages":["/","/status.html"]}'
run_gate "$GATE" "$SITE" "$MANIFEST"
want_exit "1. the manifest lists exactly the site's pages" 0 \
  "OK: manifest matches the site (2 pages declared, all present, none unlisted)"

# --- 2. served but not declared -> red --------------------------------------
new_site unlisted index.html status.html
new_manifest unlisted '{"requiredPages":["/"]}'
run_gate "$GATE" "$SITE" "$MANIFEST"
want_exit "2. a page served but not declared" 1 \
  "${SITE}/status.html is served but not declared"

# --- 3. declared but not generated -> red -----------------------------------
new_site absent index.html
new_manifest absent '{"requiredPages":["/","/status.html"]}'
run_gate "$GATE" "$SITE" "$MANIFEST"
want_exit "3. a page declared but not generated" 1 \
  "declares /status.html but ${SITE}/status.html does not exist"

# --- 4. no site directory -> red --------------------------------------------
new_manifest nosite '{"requiredPages":["/"]}'
NOSITE="${TMP}/sites/does-not-exist"
run_gate "$GATE" "$NOSITE" "$MANIFEST"
want_exit "4. a site directory that does not exist" 1 "FAIL: ${NOSITE} not found"

# --- 5. a site with no .html -> red -----------------------------------------
# Against an EMPTY manifest, so no declared page can red it: an older copy
# died here with exit 1 and no output at all.
new_site empty
printf 'body {\n  margin: 0;\n}\n' > "${SITE}/styles.css"
new_manifest empty '{"requiredPages":[]}'
EMPTY_SITE="$SITE"
EMPTY_MANIFEST="$MANIFEST"
run_gate "$GATE" "$EMPTY_SITE" "$EMPTY_MANIFEST"
want_exit "5. a site directory with no .html in it" 1 \
  "FAIL: no .html page in ${EMPTY_SITE} — a site with nothing in it covers nothing"

# --- 6. no manifest -> red --------------------------------------------------
new_site nomanifest index.html
run_gate "$GATE" "$SITE" "${TMP}/does-not-exist.json"
want_exit "6. a manifest that does not exist" 1 \
  "FAIL: ${TMP}/does-not-exist.json not found"

# --- 7. pages in subfolders -> green ----------------------------------------
new_site folders index.html standard/index.html numbers/index.html
new_manifest folders '{"requiredPages":["/","/standard/","/numbers/"]}'
run_gate "$GATE" "$SITE" "$MANIFEST"
want_exit "7. pages in subfolders, declared as /dir/" 0 \
  "OK: manifest matches the site (3 pages declared, all present, none unlisted)"

# --- 8. a subfolder page that is not declared -> red -------------------------
new_site folder-unlisted index.html numbers/index.html
new_manifest folder-unlisted '{"requiredPages":["/"]}'
run_gate "$GATE" "$SITE" "$MANIFEST"
want_exit "8. a subfolder page that is not declared" 1 \
  "${SITE}/numbers/index.html is served but not declared"

# --- 9. a subfolder page declared but not generated -> red -------------------
new_site folder-absent index.html
new_manifest folder-absent '{"requiredPages":["/","/numbers/"]}'
run_gate "$GATE" "$SITE" "$MANIFEST"
want_exit "9. a subfolder page declared but not generated" 1 \
  "declares /numbers/ but ${SITE}/numbers/index.html does not exist"

# --- 10. the site directory given with a trailing / -> green ----------------
new_site trailing-slash index.html standard/index.html
new_manifest trailing-slash '{"requiredPages":["/","/standard/"]}'
run_gate "$GATE" "${SITE}/" "$MANIFEST"
want_exit "10. the site directory given with a trailing /" 0 \
  "OK: manifest matches the site (2 pages declared, all present, none unlisted)"

# --- 11. an excluded page is skipped by its row -> green --------------------
new_site excluded index.html orphan.html
new_manifest excluded '{"requiredPages":["/"]}'
EXCLUSIONS_OK="${TMP}/exclusions-ok.txt"
printf '# a comment\n\norphan.html|an orphan page, on purpose\n' > "$EXCLUSIONS_OK"
EXCLUDED_SITE="$SITE"
EXCLUDED_MANIFEST="$MANIFEST"
run_gate "$GATE" "$EXCLUDED_SITE" "$EXCLUDED_MANIFEST" "$EXCLUSIONS_OK"
want_exit "11. a page listed in the exclusions file" 0 "skip: orphan.html (declared exclusion)"
run_gate "$GATE" "$EXCLUDED_SITE" "$EXCLUDED_MANIFEST" "${TMP}/exclusions-empty.txt"
want_exit "11b. the same page with no exclusions file is red" 1 "FAIL: ${TMP}/exclusions-empty.txt not found"
printf '# no exclusions\n' > "${TMP}/exclusions-none.txt"
run_gate "$GATE" "$EXCLUDED_SITE" "$EXCLUDED_MANIFEST" "${TMP}/exclusions-none.txt"
want_exit "11c. the same page with no exclusion row is red" 1 \
  "${EXCLUDED_SITE}/orphan.html is served but not declared"

# --- 12. no exclusions file -> red ------------------------------------------
new_site noexclusions index.html
new_manifest noexclusions '{"requiredPages":["/"]}'
run_gate "$GATE" "$SITE" "$MANIFEST" "${TMP}/absent-exclusions.txt"
want_exit "12. an exclusions file that does not exist" 1 \
  "FAIL: ${TMP}/absent-exclusions.txt not found"

# --- 13. an exclusion row without a reason -> red ----------------------------
printf '# a comment\norphan.html|\n' > "${TMP}/exclusions-noreason.txt"
run_gate "$GATE" "$EXCLUDED_SITE" "$EXCLUDED_MANIFEST" "${TMP}/exclusions-noreason.txt"
want_exit "13. an exclusion row without a reason" 1 \
  "exclusions-noreason.txt line 2 is not page|reason"

# --- Mutation proof A: the zero-pages check names case 5's reason ----------
if mutant no-zero-check 's/if \[\[ "[$]html_count" -eq 0 \]\]; then/if false; then/'; then
  run_gate "$MUTANT" "$EMPTY_SITE" "$EMPTY_MANIFEST"
  if grep -Fq -- "no .html page" <<< "$OUT"; then
    fail "mutation proof A: case 5 still says 'no .html page' with the zero-pages check removed, so that reason does not come from that check. Output: ${OUT}"
  else
    echo "  ok: mutation proof A: case 5 loses its 'no .html page' reason with the zero-pages check removed"
  fi
fi

# --- Mutation proof B: the site-directory check names case 4's reason -------
if mutant no-site-check 's/if \[\[ ! -d "[$]SITE_DIR" \]\]; then/if false; then/'; then
  new_manifest nosite-mutant '{"requiredPages":["/"]}'
  run_gate "$MUTANT" "$NOSITE" "$MANIFEST"
  if grep -Fq -- "${NOSITE} not found" <<< "$OUT"; then
    fail "mutation proof B: case 4 still says '${NOSITE} not found' with the site-directory check removed, so that reason does not come from that check. Output: ${OUT}"
  else
    echo "  ok: mutation proof B: case 4 loses its 'not found' reason with the site-directory check removed"
  fi
fi

# --- Mutation proof C: an undeclared page that never reds ------------------
if mutant no-direction-1 's/if ! grep -qx -- "[$]path" <<< "[$]listed"; then/if false; then/'; then
  new_site unlisted-mutant index.html status.html
  new_manifest unlisted-mutant '{"requiredPages":["/"]}'
  run_gate "$MUTANT" "$SITE" "$MANIFEST"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof C: with the undeclared-page check removed case 2 exits 0, so that red comes from that check"
  else
    fail "mutation proof C: the gate without its undeclared-page check still exited ${RC}. Output: ${OUT}"
  fi
fi

# --- Mutation proof D: a declared page that does not exist never reds -------
if mutant no-direction-2 's/if \[\[ ! -f "[$]f" \]\]; then/if false; then/'; then
  new_site absent-mutant index.html
  new_manifest absent-mutant '{"requiredPages":["/","/status.html"]}'
  run_gate "$MUTANT" "$SITE" "$MANIFEST"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof D: with the missing-page check removed case 3 exits 0, so that red comes from that check"
  else
    fail "mutation proof D: the gate without its missing-page check still exited ${RC}. Output: ${OUT}"
  fi
fi

# --- Mutation proof E: the exclusions file is ignored -----------------------
if mutant ignores-exclusions 's/^    excluded="[$]{excluded}[$]{row%%|\*}"[$]'"'"'\\n'"'"'$/    :/'; then
  run_gate "$MUTANT" "$EXCLUDED_SITE" "$EXCLUDED_MANIFEST" "$EXCLUSIONS_OK"
  if [[ "$RC" -ne 0 ]]; then
    echo "  ok: mutation proof E: case 11 is red once the exclusions are ignored, so the page is skipped because of its row"
  else
    fail "mutation proof E: case 11 still exits 0 with the exclusions ignored. Output: ${OUT}"
  fi
fi

selftest_end "manifest-covers-site self-test" \
  "manifest-covers-site gate passes a matching site, and is red on an unlisted page, a missing page, a subfolder page unlisted or missing, a missing site, a site with no pages, a missing manifest, a missing exclusions file and an exclusion row without a reason; an excluded page is skipped by its row"
