#!/usr/bin/env bash
# Scripts/test_check_repo_links.sh
#
# Self-test for Scripts/check_repo_links.sh, run in pre before the gate it
# validates. forsgren's own: the gate is forsgren's, so no repo of the estate
# has a fixture for it. Every repository name here is made up (acme/app).
#   1. a page with no repository path            -> green
#   2. an href into a repository                 -> red, naming file:line
#   3. the FAIL line never prints the path       -> the made-up repo name is
#                                                   absent from the output
#   4. a repository path as plain text           -> red
#   5. a url() into a repository in a stylesheet -> red
#   6. a link to an owner alone (github.com/acme) -> green
#   7. a site with no .html page                 -> red: a scan over nothing
#   8. a missing site dir                        -> exit 2, never 0
#   9. the generated site                        -> green (built here, since
#                                                   pre runs before
#                                                   Scripts/build_site.sh)
#  10. forsgren's own public repository, no longer an exception
#      (forsgren#162: the footer links forsgren.be): an href to its root
#      and to it with an anchor, each line named               -> red
#  11. forsgren-template, no longer an exception (forsgren#45): an href to
#      exactly https://github.com/yveshanoulle/forsgren-template -> red
#  12. the footer link https://forsgren.be/ (forsgren#162)    -> green
# Mutation proof: cases 2, 10 and 11 against a copy of the gate whose
# REPO_PATH pattern never matches must turn green, so each is red BECAUSE of
# that pattern, not because of something else in its site.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_repo_links.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "repository-links self-test"

# new_site <name> — a clean one-page site with a local stylesheet.
new_site() {
  SITE="$TMP/$1"
  mkdir -p "$SITE"
  printf '<!doctype html>\n<html lang="en"><head><link rel="stylesheet" href="styles.css"></head>\n<body><p>3 deploys</p></body></html>\n' > "$SITE/index.html"
  printf 'body { margin: 0; }\n' > "$SITE/styles.css"
}

new_site clean
capture "$GATE" "$SITE"
want_rc "1. a page with no repository path is clean" 0

new_site href
printf '<a href="https://github.com/acme/app/issues/7">7</a>\n' >> "$SITE/index.html"
capture "$GATE" "$SITE"
want_rc "2. rejects an href into a repository" 1
grep -q "index.html:4" <<<"$OUT" \
  || fail "2. the finding does not name index.html:4. Output: $OUT"
if grep -q "acme/app" <<<"$OUT"; then
  fail "3. the output prints the repository path it matched"
else
  echo "  ok: 3. the output never prints the repository path"
fi

new_site text
printf '<p>source: github.com/acme/app</p>\n' >> "$SITE/index.html"
capture "$GATE" "$SITE"
want_rc "4. rejects a repository path as plain text" 1

new_site css
printf '.x { background: url("https://github.com/acme/app/raw/main/a.png"); }\n' >> "$SITE/styles.css"
capture "$GATE" "$SITE"
want_rc "5. rejects a url() into a repository in a stylesheet" 1

new_site owner
printf '<a href="https://github.com/acme">acme</a>\n' >> "$SITE/index.html"
capture "$GATE" "$SITE"
want_rc "6. a link to an owner alone is not a finding" 0

SITE="$TMP/empty"; mkdir -p "$SITE"
printf 'body { margin: 0; }\n' > "$SITE/styles.css"
capture "$GATE" "$SITE"
want_rc "7. rejects a site with no .html page" 1
grep -q "scan over nothing" <<<"$OUT" \
  || fail "7. the finding does not say it scanned nothing. Output: $OUT"

capture "$GATE" "$TMP/does-not-exist"
want_rc "8. exits 2 on a missing site dir, never 0" 2

set +e
SITE_PAGE_COUNT_FILE="$TMP/built.count" FORSGREN_BIN_DIR="$TMP/bin" \
  ./Scripts/build_site.sh "$TMP/built" > "$TMP/built.log" 2>&1
BUILD_RC=$?
set -e
[[ "$BUILD_RC" -eq 0 ]] || sed 's/^/    /' "$TMP/built.log"
capture "$GATE" "$TMP/built"
want_rc "9. the generated site links into no repository" 0
[[ "$RC" -eq 0 ]] || printf '%s\n' "$OUT" | sed 's/^/    /'

new_site own
printf '<p><a href="https://github.com/yveshanoulle/forsgren">Forsgren</a></p>\n' >> "$SITE/index.html"
printf '<p><a href="https://github.com/yveshanoulle/forsgren#installing-and-updating">Install</a></p>\n' >> "$SITE/index.html"
capture "$GATE" "$SITE"
want_rc "10. forsgren's own repository, root and anchor, is a finding (forsgren#162)" 1
for line in 4 5; do
  grep -q "index.html:${line}" <<<"$OUT" \
    || fail "10. the findings do not name index.html:${line}. Output: $OUT"
done

new_site template
printf '<p><a href="https://github.com/yveshanoulle/forsgren-template">Install</a></p>\n' >> "$SITE/index.html"
capture "$GATE" "$SITE"
want_rc "11. forsgren-template is a finding again (forsgren#45)" 1

new_site footer
printf '<p><a href="https://forsgren.be/">Forsgren</a> 1.3.2</p>\n' >> "$SITE/index.html"
capture "$GATE" "$SITE"
want_rc "12. the footer link to forsgren.be is no repository path (forsgren#162)" 0

# Mutation proof for cases 2, 10 and 11: the same sites against a copy of
# the gate whose REPO_PATH pattern can never match must be green.
# The mutant cds to its own dir's parent; give it the same layout.
MUTANT="$TMP/mutant/Scripts/check_repo_links.sh"
selftest_mutant_green "$GATE" "$MUTANT" \
  "s/^REPO_PATH=.*/REPO_PATH='NEVER-MATCHES-ANY-REPOSITORY-PATH'/" "$TMP/href" \
  "without the REPO_PATH pattern case 2 is green, so it is red because of that pattern" \
  "a gate whose REPO_PATH never matches is still red on case 2, so case 2 is red for another reason"
for pinned in "10 own" "11 template"; do
  capture "$MUTANT" "$TMP/${pinned#* }"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: without the REPO_PATH pattern case ${pinned% *} is green, so it is red because of that pattern"
  else
    fail "mutation proof: a gate whose REPO_PATH never matches is still red on case ${pinned% *} (exit $RC). Output: $OUT"
  fi
done

selftest_end "the repository-links gate does not keep repository paths off the page" \
  "repository-links gate is red on a repository path in an href, in plain text and in a stylesheet url(), naming file:line and never the path, and on a site with no page, exits 2 on a missing site, is green on an owner link, on the forsgren.be footer link and on the generated site, red on forsgren's own repository and on forsgren-template, which have no exception, and its REPO_PATH pattern is what reddens cases 2, 10 and 11"
