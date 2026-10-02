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
# Mutation proof: case 2 against a copy of the gate whose REPO_PATH pattern
# never matches must turn green, so case 2 is red BECAUSE of that pattern,
# not because of something else in its site.

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

# Mutation proof for case 2: the same site against a copy of the gate whose
# REPO_PATH pattern can never match must be green.
# The mutant cds to its own dir's parent; give it the same layout.
MUTANT="$TMP/mutant/Scripts/check_repo_links.sh"
if selftest_mutant "$GATE" "$MUTANT" "s/^REPO_PATH=.*/REPO_PATH='NEVER-MATCHES-ANY-REPOSITORY-PATH'/"; then
  capture "$MUTANT" "$TMP/href"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: without the REPO_PATH pattern case 2 is green, so it is red because of that pattern"
  else
    fail "mutation proof: a gate whose REPO_PATH never matches is still red on case 2 (exit $RC) — case 2 is red for another reason. Output: $OUT"
  fi
fi

selftest_end "the repository-links gate does not keep repository paths off the page" \
  "repository-links gate is red on a repository path in an href, in plain text and in a stylesheet url(), naming file:line and never the path, and on a site with no page, exits 2 on a missing site, is green on an owner link and on the generated site, and its REPO_PATH pattern is what reddens case 2"
