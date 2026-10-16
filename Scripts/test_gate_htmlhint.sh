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
#   5. one page per rule of .htmlhintrc (forsgren#207, forsgren#208): each
#      page breaks only that rule -> red, naming that rule and no other
# Mutation proofs:
#   A. case 2 under an .htmlhintrc with tag-pair turned off must turn green,
#      so case 2 is red BECAUSE the gate reads that config's rule;
#   C. for each row of case 5, the .htmlhintrc with only that rule turned off
#      must stop naming the rule (and turn green, unless the row has an
#      unavoidable companion rule), so every row is red BECAUSE of its rule;
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
  <meta name="description" content="acme">
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
  <meta name="description" content="acme">
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

# --- 5. one page per rule of .htmlhintrc (forsgren#207, forsgren#208) -----
# RC_RULES are the 30 rules of .htmlhintrc: the 28 shared with the estate's
# other public sites, plus inline-style-disabled (forsgren#207) and
# meta-description-require (forsgren#208).
# Each row is a minimal page that breaks only that rule, built from GOOD_PAGE;
# the page must be red, name the rule, and name no other rule. This replaces
# the single meta-charset case of forsgren#206.
# A page that loses its meta charset still passes Lighthouse when the server
# sends a charset header; htmlhint reads the file itself.
# tagname-specialchars is the one row with a companion: a start tag only
# matches [A-Za-z0-9_:-], so a special character can only sit in an end tag,
# and an end tag with no start tag is always a tag-pair error as well.
RC_RULES=(
  attr-lowercase attr-no-duplication attr-no-unnecessary-whitespace
  attr-unsafe-chars attr-value-double-quotes attr-value-no-duplication
  attr-whitespace alt-require doctype-first doctype-html5 form-method-require
  frame-title-require head-script-disabled html-lang-require
  id-class-ad-disabled id-unique inline-script-disabled inline-style-disabled
  input-requires-label main-require meta-charset-require meta-description-require
  space-tab-mixed-disabled spec-char-escape src-not-empty tag-no-obsolete
  tag-pair tagname-lowercase tagname-specialchars title-require
)

# rule_companions <rule> — the other rule the row's page cannot avoid breaking.
rule_companions() {
  case "$1" in
    tagname-specialchars) echo "tag-pair" ;;
    *) echo "" ;;
  esac
}

# bad_page <rule> — GOOD_PAGE with exactly one thing wrong.
bad_page() {
  case "$1" in
    attr-lowercase) printf '%s' "${GOOD_PAGE/<p>/<p CLASS=\"x\">}" ;;
    attr-no-duplication) printf '%s' "${GOOD_PAGE/<p>/<p class=\"x\" class=\"y\">}" ;;
    attr-no-unnecessary-whitespace) printf '%s' "${GOOD_PAGE/<p>/<p class = \"x\">}" ;;
    attr-unsafe-chars) printf '%s' "${GOOD_PAGE/<p>/<p title=\"a$(printf '\001')b\">}" ;;
    attr-value-double-quotes) printf '%s' "${GOOD_PAGE/<p>/<p class='x'>}" ;;
    attr-value-no-duplication) printf '%s' "${GOOD_PAGE/<p>/<p class=\"x x\">}" ;;
    attr-whitespace) printf '%s' "${GOOD_PAGE/<p>/<p class=\" x\">}" ;;
    alt-require) printf '%s' "${GOOD_PAGE/<p>acme\/app<\/p>/<img src=\"a.png\">}" ;;
    doctype-first) printf '%s' "${GOOD_PAGE/<!doctype html>/<title>x</title>}" ;;
    doctype-html5) printf '%s' "${GOOD_PAGE/<!doctype html>/<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\">}" ;;
    form-method-require) printf '%s' "${GOOD_PAGE/<p>acme\/app<\/p>/<form action=\"/x\"></form>}" ;;
    frame-title-require) printf '%s' "${GOOD_PAGE/<p>acme\/app<\/p>/<iframe src=\"a.html\"></iframe>}" ;;
    head-script-disabled) printf '%s' "${GOOD_PAGE/<\/head>/  <script src=\"a.js\"></script>
</head>}" ;;
    html-lang-require) printf '%s' "${GOOD_PAGE/ lang=\"en\"/}" ;;
    id-class-ad-disabled) printf '%s' "${GOOD_PAGE/<p>/<p class=\"ad\">}" ;;
    id-unique) printf '%s' "${GOOD_PAGE/<p>acme\/app<\/p>/<p id=\"a\">x</p><p id=\"a\">y</p>}" ;;
    inline-script-disabled) printf '%s' "${GOOD_PAGE/<p>/<p onclick=\"go\">}" ;;
    inline-style-disabled) printf '%s' "${GOOD_PAGE/<p>/<p style=\"color:red\">}" ;;
    input-requires-label) printf '%s' "${GOOD_PAGE/<p>acme\/app<\/p>/<input type=\"text\" id=\"q\">}" ;;
    main-require) printf '%s' "${GOOD_PAGE//main>/div>}" ;;
    meta-charset-require) printf '%s' "${GOOD_PAGE/  <meta charset=\"utf-8\">
/}" ;;
    meta-description-require) printf '%s' "${GOOD_PAGE/  <meta name=\"description\" content=\"acme\">
/}" ;;
    space-tab-mixed-disabled) printf '%s' "${GOOD_PAGE/    <p>/ $(printf '\t')<p>}" ;;
    spec-char-escape) printf '%s' "${GOOD_PAGE/<p>acme\/app/<p>a < b}" ;;
    src-not-empty) printf '%s' "${GOOD_PAGE/<p>acme\/app<\/p>/<img src=\"\" alt=\"x\">}" ;;
    tag-no-obsolete) printf '%s' "${GOOD_PAGE/<p>acme\/app<\/p>/<center>x</center>}" ;;
    tag-pair) printf '%s' "${GOOD_PAGE/<\/p>/}" ;;
    tagname-lowercase) printf '%s' "${GOOD_PAGE/<p>acme\/app<\/p>/<P>acme/app</P>}" ;;
    tagname-specialchars) printf '%s' "${GOOD_PAGE/<\/p>/</p></p!>}" ;;
    title-require) printf '%s' "${GOOD_PAGE/  <title>acme<\/title>
/}" ;;
    *) selftest_abort "bad_page: no page for rule $1" ;;
  esac
}

# rule_ids — the rule ids named in OUT, sorted, one per line.
rule_ids() {
  grep -o '([a-z0-9]*-[a-z0-9-]*)' <<< "$OUT" | tr -d '()' | sort -u || true
}

if [[ "$(grep -c '": true' "$CONFIG")" -ne "${#RC_RULES[@]}" ]]; then
  fail "5. .htmlhintrc does not hold exactly the ${#RC_RULES[@]} rules of the shared set"
fi
for rule in "${RC_RULES[@]}"; do
  new_root "rule-${rule}"
  new_site "rule-${rule}" "$(bad_page "$rule")
"
  run_gate
  companion="$(rule_companions "$rule")"
  want_ids="$(printf '%s\n%s\n' "$rule" "$companion" | sed '/^$/d' | sort -u)"
  if [[ "$RC" -eq 1 && "$(rule_ids)" == "$want_ids" ]]; then
    echo "  ok: 5. a page that breaks only ${rule}"
  else
    fail "5. a page that breaks only ${rule} — expected exit 1 naming only: $(tr '\n' ' ' <<< "$want_ids"); got exit ${RC} naming: $(rule_ids | tr '\n' ' '). Output: ${OUT}"
  fi
done

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

# --- Mutation proof C: each rule of the set reds its own row ---------------
# The rc with only that rule turned off must no longer name it, and must turn
# green unless the row has a companion rule that stays red.
for rule in "${RC_RULES[@]}"; do
  MUTANT_RULE_CONFIG="${TMP}/htmlhintrc.no-${rule}"
  if selftest_mutant "$CONFIG" "$MUTANT_RULE_CONFIG" "s/\"${rule}\": true/\"${rule}\": false/"; then
    new_root "mutant-${rule}" "$GATE" "$MUTANT_RULE_CONFIG"
    new_site "mutant-${rule}" "$(bad_page "$rule")
"
    run_gate
    companion="$(rule_companions "$rule")"
    if [[ -z "$companion" && "$RC" -ne 0 ]]; then
      fail "mutation proof C: the ${rule} row is still red with ${rule} turned off in .htmlhintrc, so its red does not come from the config's rule. Output: ${OUT}"
    elif [[ -n "$companion" && "$(rule_ids)" != "$companion" ]]; then
      fail "mutation proof C: the ${rule} row names '$(rule_ids | tr '\n' ' ')' with ${rule} turned off, expected only its companion ${companion}. Output: ${OUT}"
    else
      echo "  ok: mutation proof C: the ${rule} row no longer names ${rule} with it turned off in .htmlhintrc"
    fi
  fi
done

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
