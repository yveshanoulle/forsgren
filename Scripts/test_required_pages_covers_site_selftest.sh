#!/usr/bin/env bash
# Scripts/test_required_pages_covers_site_selftest.sh
#
# Self-test for Scripts/test_required_pages_covers_site.sh, the "manifest
# covers site" post gate (forsgren#1, ladder step 9), run in PRE before the
# gate it validates.
#
# NEW IN forsgren. No repo of the estate has a self-test for this gate: there
# it runs unvalidated against the one real site, so a gate that stopped
# reading the manifest, or a site directory that went empty, would sit green.
# forsgren's rule is that a ported gate comes with its fixtures, seen green,
# plus one mutation seen red, so this file is forsgren's own. (The gate's own
# name already starts with test_, hence the _selftest suffix here.)
#
# Every case builds a throwaway site and manifest and passes both as the
# gate's arguments; nothing here reads .build/site.
#   1. the manifest lists exactly the site's pages  -> green
#   2. a page served but not declared               -> red, naming the page
#   3. a page declared but not generated            -> red, naming the path
#   4. a site directory that does not exist         -> red, "not found"
#   5. a site directory with no .html in it         -> red, "no .html page"
#   6. a manifest that does not exist               -> red, "not found"
#   7. pages in subfolders, declared as /dir/       -> green (forsgren#46)
#   8. a subfolder page that is not declared        -> red, naming the page
#   9. a subfolder page declared but not generated  -> red, naming the path
#  10. the site directory given with a trailing /  -> green (forsgren#46),
#      as green as without it, as in Scripts/check_html_dupl_site.sh
# Mutation proofs:
#   A. case 5 against a copy of the gate without its zero-pages check must
#      lose the "no .html page" reason, so that reason comes from that check
#      (the copy still exits 1, silently: see the gate's header);
#   B. case 4 against a copy of the gate without its site-directory check
#      must lose the "not found" reason, so that reason comes from that check.

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

# run_gate <gate> <site> <manifest> — sets RC and OUT.
run_gate() {
  capture "$1" "$2" "$3"
}

# mutant <name> <sed-expression> — a copy of the gate with one check removed;
# MUTANT is its path. Refuses a sed that changed nothing.
mutant() {
  MUTANT="${TMP}/$1.sh"
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
# Against an EMPTY manifest, so no declared page can red it: konenki's copy
# dies here with exit 1 and no output at all.
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

selftest_end "manifest-covers-site self-test" \
  "manifest-covers-site gate passes a matching site, and is red on an unlisted page, a missing page, a subfolder page unlisted or missing, a missing site, a site with no pages and a missing manifest"
