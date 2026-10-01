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

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: repository-links self-test aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

failures=0
check() { # <name> <expected-rc> <actual-rc>
  if [[ "$2" == "$3" ]]; then echo "  ✅ $1"; else echo "  ❌ $1 — expected exit $2, got $3"; failures=$((failures+1)); fi
}
run() { set +e; OUT="$("$@" 2>&1)"; RC=$?; set -e; }

# new_site <name> — a clean one-page site with a local stylesheet.
new_site() {
  SITE="$TMP/$1"
  mkdir -p "$SITE"
  printf '<!doctype html>\n<html lang="en"><head><link rel="stylesheet" href="styles.css"></head>\n<body><p>3 deploys</p></body></html>\n' > "$SITE/index.html"
  printf 'body { margin: 0; }\n' > "$SITE/styles.css"
}

echo "test_check_repo_links"

new_site clean
run "$GATE" "$SITE"
check "1. a page with no repository path is clean" 0 "$RC"

new_site href
printf '<a href="https://github.com/acme/app/issues/7">7</a>\n' >> "$SITE/index.html"
run "$GATE" "$SITE"
check "2. rejects an href into a repository" 1 "$RC"
grep -q "index.html:4" <<<"$OUT" \
  || { echo "  ❌ 2. the finding does not name index.html:4. Output: $OUT"; failures=$((failures+1)); }
if grep -q "acme/app" <<<"$OUT"; then
  echo "  ❌ 3. the output prints the repository path it matched"; failures=$((failures+1))
else
  echo "  ✅ 3. the output never prints the repository path"
fi

new_site text
printf '<p>source: github.com/acme/app</p>\n' >> "$SITE/index.html"
run "$GATE" "$SITE"
check "4. rejects a repository path as plain text" 1 "$RC"

new_site css
printf '.x { background: url("https://github.com/acme/app/raw/main/a.png"); }\n' >> "$SITE/styles.css"
run "$GATE" "$SITE"
check "5. rejects a url() into a repository in a stylesheet" 1 "$RC"

new_site owner
printf '<a href="https://github.com/acme">acme</a>\n' >> "$SITE/index.html"
run "$GATE" "$SITE"
check "6. a link to an owner alone is not a finding" 0 "$RC"

SITE="$TMP/empty"; mkdir -p "$SITE"
printf 'body { margin: 0; }\n' > "$SITE/styles.css"
run "$GATE" "$SITE"
check "7. rejects a site with no .html page" 1 "$RC"
grep -q "scan over nothing" <<<"$OUT" \
  || { echo "  ❌ 7. the finding does not say it scanned nothing. Output: $OUT"; failures=$((failures+1)); }

run "$GATE" "$TMP/does-not-exist"
check "8. exits 2 on a missing site dir, never 0" 2 "$RC"

set +e
SITE_PAGE_COUNT_FILE="$TMP/built.count" FORSGREN_BIN_DIR="$TMP/bin" \
  ./Scripts/build_site.sh "$TMP/built" > "$TMP/built.log" 2>&1
BUILD_RC=$?
set -e
[[ "$BUILD_RC" -eq 0 ]] || sed 's/^/    /' "$TMP/built.log"
run "$GATE" "$TMP/built"
check "9. the generated site links into no repository" 0 "$RC"
[[ "$RC" -eq 0 ]] || printf '%s\n' "$OUT" | sed 's/^/    /'

# Mutation proof for case 2: the same site against a copy of the gate whose
# REPO_PATH pattern can never match must be green.
MUTANT="$TMP/check_repo_links.mutant.sh"
sed "s/^REPO_PATH=.*/REPO_PATH='NEVER-MATCHES-ANY-REPOSITORY-PATH'/" "$GATE" > "$MUTANT"
chmod +x "$MUTANT"
if cmp -s "$GATE" "$MUTANT"; then
  echo "  ❌ mutation proof: replacing the '^REPO_PATH=' row changed nothing in ${GATE} — the anchor no longer matches, so this proof proves nothing"
  failures=$((failures+1))
else
  # The mutant cds to its own dir's parent; give it the same layout.
  mkdir -p "$TMP/mutant/Scripts"
  mv "$MUTANT" "$TMP/mutant/Scripts/check_repo_links.sh"
  run "$TMP/mutant/Scripts/check_repo_links.sh" "$TMP/href"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ✅ mutation proof: without the REPO_PATH pattern case 2 is green, so it is red because of that pattern"
  else
    echo "  ❌ mutation proof: a gate whose REPO_PATH never matches is still red on case 2 (exit $RC) — case 2 is red for another reason. Output: $OUT"
    failures=$((failures+1))
  fi
fi

COMPLETED=1
if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "❌ FAIL: check_repo_links contract (${failures} failed)"
  exit 1
fi
echo ""
echo "✅ test_check_repo_links"
