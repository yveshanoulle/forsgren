#!/usr/bin/env bash
# Scripts/test_check_starter_links.sh
#
# Self-test for Scripts/check_starter_links.sh (forsgren#132), run in pre
# before the gate it validates. forsgren's own. Every repository and host
# name here is made up (acme/app, example.org).
#   1. anchors, forsgren (root, a blob path, an anchor), forsgren-template
#      and forsgren.forsgren.be                       -> green
#   2. a link into another repository                  -> red, naming file:line
#      and the host, and never printing the path
#   3. another host                                    -> red
#   4. lookalikes: forsgren-templates, forsgrenx and
#      forsgren.forsgren.be.example.org                -> red, each
#   5. an http link to an allowed host                 -> red
#   6. a relative link                                 -> red
#   7. a src outside the list                          -> red
#   8. a directory with no .html page                  -> red: a scan over nothing
#   9. a missing directory                             -> exit 2, never 0
#  10. the real starter page, built here              -> green
#  11. MUTATION PROOF: case 2 against a copy of the gate whose ALLOWED
#      pattern matches everything is green: case 2 is red BECAUSE of the
#      allowlist, not because of something else in its page.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_starter_links.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "starter-page links self-test"

[[ -x "$GATE" ]] || selftest_abort "the link check ${GATE} is missing (or not executable): nothing holds the starter page to its three destinations"

# new_page <name> <body> — a one-page directory whose body is <body>.
new_page() {
  PAGE="${TMP}/$1"
  mkdir -p "$PAGE"
  printf '<!DOCTYPE html>\n<html lang="en">\n<head><title>t</title></head>\n<body>\n%s\n</body>\n</html>\n' "$2" > "${PAGE}/index.html"
}

new_page clean '<a href="#usage">a</a> <a href="https://github.com/yveshanoulle/forsgren">b</a>
<a href="https://github.com/yveshanoulle/forsgren/blob/main/docs/ci.md#x">c</a>
<a href="https://github.com/yveshanoulle/forsgren-template">d</a>
<a href="https://forsgren.forsgren.be">e</a> <a href="https://forsgren.forsgren.be/standard/">f</a>'
capture "$GATE" "$PAGE"
want_green "1. the three destinations and anchors are clean" "6 link(s)"

new_page repo '<a href="https://github.com/acme/app/issues/7">x</a>'
capture "$GATE" "$PAGE"
want_exit "2. a link into another repository is red, naming file:line and the host" 1 "index.html:5 — a link to github.com"
if grep -q "acme/app" <<< "$OUT"; then
  fail "2. the output prints the path it matched"
else
  echo "  ok: 2. the output never prints the link's path"
fi
REPO_PAGE="$PAGE"

new_page host '<a href="https://example.org/a">x</a>'
capture "$GATE" "$PAGE"
want_exit "3. another host is red" 1 "a link to example.org"

for lookalike in \
  'https://github.com/yveshanoulle/forsgren-templates' \
  'https://github.com/yveshanoulle/forsgrenx' \
  'https://forsgren.forsgren.be.example.org/'; do
  new_page lookalike "<a href=\"${lookalike}\">x</a>"
  capture "$GATE" "$PAGE"
  want_rc "4. the lookalike ${lookalike} is red" 1
done

new_page http '<a href="http://forsgren.forsgren.be">x</a>'
capture "$GATE" "$PAGE"
want_exit "5. an http link to an allowed host is red" 1 "a link to forsgren.forsgren.be"

new_page relative '<a href="docs/ci.md">x</a>'
capture "$GATE" "$PAGE"
want_exit "6. a relative link is red" 1 "a relative or non-web link"

new_page src '<img src="https://example.org/a.png" alt="">'
capture "$GATE" "$PAGE"
want_exit "7. a src outside the list is red" 1 "a link to example.org"

mkdir -p "${TMP}/empty"
capture "$GATE" "${TMP}/empty"
want_exit "8. a directory with no page is red" 1 "no .html page"

capture "$GATE" "${TMP}/missing"
want_rc "9. a missing directory is exit 2" 2

capture ./Scripts/build_starter_page.sh "${TMP}/real"
want_green "10a. the real starter page builds" "index.html and CNAME"
capture "$GATE" "${TMP}/real"
want_green "10b. the real starter page is clean" "starter page links:"

if selftest_mutant "$GATE" "${TMP}/mutant/Scripts/check_starter_links.sh" "s#^ALLOWED=.*#ALLOWED='.*'#"; then
  capture "${TMP}/mutant/Scripts/check_starter_links.sh" "$REPO_PAGE"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: with an allowlist that matches everything case 2 is green"
  else
    fail "mutation proof: case 2 stays red without the allowlist (exit ${RC}). Output: ${OUT}"
  fi
fi

selftest_end "the starter-page links self-test found failures" "starter-page links self-test (cases and a mutation proof)"
