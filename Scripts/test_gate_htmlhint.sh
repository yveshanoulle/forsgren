#!/usr/bin/env bash
# canon: test_gate_htmlhint v2
# Scripts/test_gate_htmlhint.sh
#
# Self-test for Scripts/gate_htmlhint.sh, the HTMLHint post gate, run in PRE
# before the gate it validates.
#
# Ported from forsgren (forsgren#207, forsgren#208). Until now this gate ran
# unvalidated here: a gate that never read its config would sit green, and a
# rule added to .htmlhintrc that nothing proves is a rule nobody knows works.
#
# The REAL htmlhint from node_modules/.bin (sfl's `npm ci` puts it there),
# never a fake: this pins what the gate does with the actual tool and the
# actual .htmlhintrc. The gate anchors itself with `cd "$(dirname "$0")/.."`,
# so each case runs a copy of it from Scripts/ of a throwaway root that holds
# a copy of .htmlhintrc, a symlink to the repository's node_modules and its
# own Site/ (the gate lints the fixed glob Site/**/*.html of its root).
#   1. a well-formed page                        -> green, 1 file scanned
#   2. an unpaired tag                           -> red, naming tag-pair
#   3. one page per rule of .htmlhintrc: each page breaks only that rule
#      -> red, naming that rule and no other rule
# Mutation proofs:
#   A. case 2 under an .htmlhintrc with tag-pair turned off must turn green,
#      so case 2 is red BECAUSE the gate reads that config's rule;
#   C. for each row of case 4, the .htmlhintrc with only that rule turned off
#      must stop naming the rule (and turn green, unless the row has an
#      unavoidable companion rule), so every row is red BECAUSE of its rule.
# The gate is the estate canon now (gate_htmlhint v1), so
# the cases forsgren's self-test holds for the gate's own behaviour are here too.
# The site dir comes from the argument, else from Scripts/site_settings.txt
# through Scripts/lib_site_settings.sh; each throwaway root carries a copy of
# both. Added cases, each seen red on the previous gate:
#   1b. no argument: the dir named by site_settings.txt is linted (a bad page
#       there, a good one in Site/: red proves the settings were read)
#   1c. an explicit argument wins over the settings (Site/ bad, the argument good)
#   1d. no argument and no settings file       -> exit 2, no guessed default
#   2b. a site dir with no .html under it       -> exit 2, nothing linted
#   2c. a site dir that does not exist          -> exit 2
#   2d. an abort that ends the script with status 0 before COMPLETED is set
#       (an injected `exit 0`) -> exit 1, not a silent green
# The RULE BASELINE. CANON_RULES below is the estate's
# HTMLHint rule set, and living in this shared test is what makes it canon. Every
# canon rule is on in .htmlhintrc OR a row `rule|reason` of
# Scripts/htmlhint_exceptions.txt (the reason is required); a canon rule in
# neither is red, and so is a rule that is both, a rule that is not canon, and
# an exception with no reason. The per-rule cases below run for every canon rule
# that is on, and are skipped for the excepted ones.
#   0. the baseline holds
# Mutation proofs:
#   E. an .htmlhintrc copy without h1-require is red, naming it;
#   F. an exceptions copy without its rows is red, naming the canon rule in neither;
#   G. an exceptions row with no reason is red.
# Mutation proofs:
#   B. case 2b against a copy without the zero-files check must turn green;
#   D. case 2c against a copy without the dir check must no longer say the dir
#      was not found (the zero-files check still reds it, with another reason).

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
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>acme</title>
</head>
<body>
  <main>
    <h1>acme</h1>
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
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>acme</title>
</head>
<body>
  <main>
    <h1>acme</h1>
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
  cp "${REPO_ROOT}/Scripts/lib_site_settings.sh" "${ROOT}/Scripts/"
  # A repository's own site_dir may not exist when this self-test runs (a build
  # output, absent in the pre phase), so the throwaway root states the Site/
  # these cases build instead of copying the repository's settings.
  printf 'site_dir=Site\nhtml_dupl_target=Site\nhtml_dupl_ceiling=1.0\nrequired_pages_manifest=m.json\n' > "${ROOT}/Scripts/site_settings.txt"
  ln -s "${REPO_ROOT}/node_modules" "${ROOT}/node_modules"
}

# new_site <page-content> — the current root's Site/index.html.
new_site() {
  mkdir -p "${ROOT}/Site"
  printf '%s' "$1" > "${ROOT}/Site/index.html"
}

# run_gate [args] — runs the root's copy of the gate; sets RC and OUT.
run_gate() {
  capture "${ROOT}/Scripts/gate_htmlhint.sh" "$@"
}

# --- 1. a well-formed page -> green ----------------------------------------
new_root good
new_site "$GOOD_PAGE"
run_gate
want_exit "1. a well-formed page" 0 "Scanned 1 files, no errors found"

# --- 2. an unpaired tag -> red, naming the rule ----------------------------
new_root bad
new_site "$BAD_PAGE"
run_gate
want_exit "2. an unpaired tag" 1 "(tag-pair)"

# --- 1b. no argument: the site dir comes from site_settings.txt -------------
new_root settings
new_site "$GOOD_PAGE"
mkdir -p "${ROOT}/pages"
printf '%s' "$BAD_PAGE" > "${ROOT}/pages/index.html"
printf 'site_dir=pages\nhtml_dupl_target=pages\nhtml_dupl_ceiling=1.0\nrequired_pages_manifest=m.json\n' > "${ROOT}/Scripts/site_settings.txt"
run_gate
want_exit "1b. the site dir from site_settings.txt" 1 "(tag-pair)"

# --- 1c. an explicit argument wins over the settings (Site/ is bad, other/ good)
new_root explicit
new_site "$BAD_PAGE"
mkdir -p "${ROOT}/other"
printf '%s' "$GOOD_PAGE" > "${ROOT}/other/index.html"
run_gate "${ROOT}/other"
want_exit "1c. an explicit site dir" 0 "Scanned 1 files, no errors found"

# --- 1d. no argument and no settings file -> exit 2, no guessed default -------
new_root nosettings
new_site "$GOOD_PAGE"
rm "${ROOT}/Scripts/site_settings.txt"
run_gate
want_exit "1d. no argument and no site_settings.txt" 2 "file is missing"

# --- 2b. no .html under the site -> exit 2 -----------------------------------
new_root empty
mkdir -p "${ROOT}/Site"
printf 'body {\n  margin: 0;\n}\n' > "${ROOT}/Site/styles.css"
run_gate
want_exit "2b. a site directory with no .html in it" 2 \
  "scanned 0 files under Site — nothing linted is not clean"

# --- 2c. a missing site directory -> exit 2 ----------------------------------
new_root missing
run_gate "${TMP}/does-not-exist"
want_exit "2c. a site directory that does not exist" 2 "htmlhint: site dir not found"

# --- 2d. an abort with status 0 is exit 1 ------------------------------------
if selftest_mutant "$GATE" "${TMP}/gate_htmlhint.abort.sh" 's/^COMPLETED=1$/exit 0/'; then
  new_root abort "${TMP}/gate_htmlhint.abort.sh"
  new_site "$GOOD_PAGE"
  run_gate
  want_exit "2d. an injected abort before COMPLETED is set" 1 "aborted before completing"
fi

# --- 3. one page per rule of .htmlhintrc -----------------------------------
# RC_RULES are the canon rules that are on in this repo's .htmlhintrc (below).
# Each row is a minimal page that breaks only that rule, built from GOOD_PAGE;
# the page must be red, name the rule, and name no other rule.
# tagname-specialchars is the one row with a companion: a start tag only
# matches [A-Za-z0-9_:-], so a special character can only sit in an end tag,
# and an end tag with no start tag is always a tag-pair error as well.
CANON_RULES=(
  attr-lowercase attr-no-duplication attr-no-unnecessary-whitespace
  attr-unsafe-chars attr-value-double-quotes attr-value-no-duplication
  attr-whitespace alt-require doctype-first doctype-html5 form-method-require
  frame-title-require h1-require head-script-disabled html-lang-require
  id-class-ad-disabled id-unique inline-script-disabled inline-style-disabled
  input-requires-label main-require meta-charset-require meta-description-require
  meta-viewport-require
  space-tab-mixed-disabled spec-char-escape src-not-empty tag-no-obsolete
  tag-pair tagname-lowercase tagname-specialchars title-require
)
EXCEPTIONS="${REPO_ROOT}/Scripts/htmlhint_exceptions.txt"

# exception_rows <file> — the rows of an exceptions file, comments and blanks gone.
exception_rows() {
  [[ -f "$1" ]] || return 0
  grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' || true
}

# is_canon <rule>
is_canon() { [[ " ${CANON_RULES[*]} " == *" $1 "* ]]; }

# baseline_problems <rc> <exceptions> — one line per problem; none = holds.
baseline_problems() {
  local rc="$1" exc="$2" row rule reason rc_rule listed=" " on
  [[ -f "$exc" ]] || echo "the exceptions file ${exc##*/} is missing"
  while IFS= read -r row; do
    rule="${row%%|*}"
    reason=""
    [[ "$row" == *"|"* ]] && reason="${row#*|}"
    is_canon "$rule" || echo "exception '${rule}' is not a canon rule"
    [[ -n "${reason//[[:space:]]/}" ]] || echo "exception '${rule}' has no reason (rule|reason)"
    listed="${listed}${rule} "
  done < <(exception_rows "$exc")
  for rule in "${CANON_RULES[@]}"; do
    on=0
    grep -qF "\"${rule}\": true" "$rc" && on=1
    if [[ "$on" -eq 1 && "$listed" == *" ${rule} "* ]]; then
      echo "canon rule '${rule}' is on in .htmlhintrc and also an exception"
    elif [[ "$on" -eq 0 && "$listed" != *" ${rule} "* ]]; then
      echo "canon rule '${rule}' is in neither .htmlhintrc nor the exceptions"
    fi
  done
  while IFS= read -r rc_rule; do
    is_canon "$rc_rule" || echo "rule '${rc_rule}' in .htmlhintrc is not a canon rule (add it to the canon list in every repo first)"
  done < <(grep -o '"[a-z0-9-]*": true' "$rc" | cut -d'"' -f2)
}

# --- 0. the baseline holds -----------------------------------------------------
problems="$(baseline_problems "$CONFIG" "$EXCEPTIONS")"
if [[ -n "$problems" ]]; then
  fail "0. the rule baseline does not hold: ${problems}"
else
  echo "  ok: 0. every canon rule is on in .htmlhintrc or an exception with a reason"
fi

# RC_RULES: the canon rules that are on here, i.e. not excepted.
RC_RULES=()
EXCEPTED_RULES="$(exception_rows "$EXCEPTIONS" | cut -d'|' -f1)"
for rule in "${CANON_RULES[@]}"; do
  grep -qxF "$rule" <<< "$EXCEPTED_RULES" || RC_RULES+=("$rule")
done

# Mutation proof E: a canon rule deleted from an .htmlhintrc copy is red.
if selftest_mutant "$CONFIG" "${TMP}/htmlhintrc.no-h1" '/"h1-require"/d'; then
  problems="$(baseline_problems "${TMP}/htmlhintrc.no-h1" "$EXCEPTIONS")"
  if grep -qF "canon rule 'h1-require' is in neither" <<< "$problems"; then
    echo "  ok: mutation proof E: h1-require deleted from .htmlhintrc is red, naming it"
  else
    fail "mutation proof E: deleting h1-require was not reported. Problems: ${problems:-none}"
  fi
fi

# Mutation proof F: the exceptions file without its rows leaves their rules in neither.
: > "${TMP}/exceptions.empty"
if [[ -n "$EXCEPTED_RULES" ]]; then
  problems="$(baseline_problems "$CONFIG" "${TMP}/exceptions.empty")"
  first_excepted="$(head -n 1 <<< "$EXCEPTED_RULES")"
  if grep -qF "canon rule '${first_excepted}' is in neither" <<< "$problems"; then
    echo "  ok: mutation proof F: without its exception row, ${first_excepted} is red as in neither"
  else
    fail "mutation proof F: removing the ${first_excepted} exception was not reported. Problems: ${problems:-none}"
  fi
fi

# Mutation proof G: an exceptions row with no reason is red.
printf 'inline-style-disabled|\nh1-require\n' > "${TMP}/exceptions.noreason"
problems="$(baseline_problems "$CONFIG" "${TMP}/exceptions.noreason")"
if grep -qF "exception 'inline-style-disabled' has no reason" <<< "$problems" \
   && grep -qF "exception 'h1-require' has no reason" <<< "$problems"; then
  echo "  ok: mutation proof G: an exception row with no reason is red"
else
  fail "mutation proof G: a reasonless exception row was not reported. Problems: ${problems:-none}"
fi

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
    h1-require) printf '%s' "${GOOD_PAGE/    <h1>acme<\/h1>
/}" ;;
    head-script-disabled) printf '%s' "${GOOD_PAGE/<\/head>/  <script src=\"a.js\"></script>
</head>}" ;;
    html-lang-require) printf '%s' "${GOOD_PAGE/ lang=\"en\"/}" ;;
    id-class-ad-disabled) printf '%s' "${GOOD_PAGE/<p>/<p class=\"ad\">}" ;;
    id-unique) printf '%s' "${GOOD_PAGE/<p>acme\/app<\/p>/<p id=\"a\">x</p><p id=\"a\">y</p>}" ;;
    inline-script-disabled) printf '%s' "${GOOD_PAGE/<p>/<p onclick=\"go\">}" ;;
    inline-style-disabled) printf '%s' "${GOOD_PAGE/<p>/<p style=\"color: red\">}" ;;
    input-requires-label) printf '%s' "${GOOD_PAGE/<p>acme\/app<\/p>/<input type=\"text\" id=\"q\">}" ;;
    main-require) printf '%s' "${GOOD_PAGE//main>/div>}" ;;
    meta-charset-require) printf '%s' "${GOOD_PAGE/  <meta charset=\"utf-8\">
/}" ;;
    meta-description-require) printf '%s' "${GOOD_PAGE/  <meta name=\"description\" content=\"acme\">
/}" ;;
    meta-viewport-require) printf '%s' "${GOOD_PAGE/  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
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

for rule in "${RC_RULES[@]}"; do
  new_root "rule-${rule}"
  new_site "$(bad_page "$rule")
"
  run_gate
  companion="$(rule_companions "$rule")"
  want_ids="$(printf '%s\n%s\n' "$rule" "$companion" | sed '/^$/d' | sort -u)"
  if [[ "$RC" -eq 1 && "$(rule_ids)" == "$want_ids" ]]; then
    echo "  ok: 3. a page that breaks only ${rule}"
  else
    fail "3. a page that breaks only ${rule} — expected exit 1 naming only: $(tr '\n' ' ' <<< "$want_ids"); got exit ${RC} naming: $(rule_ids | tr '\n' ' '). Output: ${OUT}"
  fi
done

# --- Mutation proof A: the config's rule is what reds case 2 ---------------
MUTANT_CONFIG="${TMP}/htmlhintrc.no-tag-pair"
if selftest_mutant "$CONFIG" "$MUTANT_CONFIG" 's/"tag-pair": true/"tag-pair": false/'; then
  new_root mutant-config "$GATE" "$MUTANT_CONFIG"
  new_site "$BAD_PAGE"
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
    new_site "$(bad_page "$rule")
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

# --- Mutation proof B: the zero-files check is what reds case 2b --------------
if selftest_mutant "$GATE" "${TMP}/gate_htmlhint.no-zero-check.sh" "s/'Scanned 0 files'/'no-such-line'/"; then
  new_root mutant-zero "${TMP}/gate_htmlhint.no-zero-check.sh"
  mkdir -p "${ROOT}/Site"
  printf 'body {\n  margin: 0;\n}\n' > "${ROOT}/Site/styles.css"
  run_gate
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof B: case 2b is still red with the zero-files check removed, so its red does not come from that check. Output: ${OUT}"
  else
    echo "  ok: mutation proof B: case 2b turns green with the zero-files check removed"
  fi
fi

# --- Mutation proof D: the dir check is what says case 2c's reason -------------
if selftest_mutant "$GATE" "${TMP}/gate_htmlhint.no-dir-check.sh" "/! -d /s/.*/if false; then/"; then
  new_root mutant-dir "${TMP}/gate_htmlhint.no-dir-check.sh"
  run_gate "${TMP}/does-not-exist"
  if grep -qF "site dir not found" <<< "$OUT"; then
    fail "mutation proof D: case 2c still says the dir was not found with the dir check removed. Output: ${OUT}"
  else
    echo "  ok: mutation proof D: case 2c loses its reason with the dir check removed"
  fi
fi

selftest_end "HTMLHint self-test" \
  "HTMLHint gate passes a well-formed page, reads .htmlhintrc and the site dir from settings, and is red on a broken page, on zero files linted, on a missing site dir and on an abort"
