#!/usr/bin/env bash
# Scripts/test_required_pages_covers_site.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# Does the manifest still describe the site? — unit 392, ported from
# coachretreat-website where it was written as part of unit 367.
#
# The history below is another estate repository's: "this repo" means konenki, and
# Site/, SiteSource/, the privacy pages and promotion are konenki's.
# forsgren's changes are listed at the end of this header.
#
# This repo's manifest has been correct since it was written — by attention,
# not by construction. Nothing checked it. And the pages it declares are not
# ordinary pages: privacy.html and privacy_nl.html are where the App Store
# listing and the app point for the privacy policy, so a page added to the
# generated site and left out of the manifest is not merely unverified, it is
# a legal surface nothing watches.
#
# Scripts/validate_required_pages.sh checks the manifest's SHAPE: valid JSON,
# root-relative entries, no duplicates, not empty. It cannot check the thing
# that actually rots — whether the manifest still matches the site it ships
# with. Both halves pass happily while drifting apart:
#
#   - a page added to the generated site and not listed is never verified on
#     promote, so the release can serve a broken new page and promote reports
#     success
#   - a page listed but deleted makes every promote fail on a 404, which is
#     loud and therefore self-correcting — but it is checked here too, because
#     finding it at promote time means finding it during a deploy
#
# The first case is the dangerous one: it fails SILENTLY, by verifying less
# than it claims to. That is the exact failure this arc keeps meeting.
#
# A page that deliberately must not be verified (a partial, an error page)
# is a decision, not an oversight — record it in EXCLUDED below with a
# reason, so the next reader sees a choice instead of a gap.
#
# The site directory and manifest are separate inputs because CI builds the
# authored SiteSource/ files into a temporary directory. The independently
# authored release manifest remains Site/required-pages.json. With no
# arguments, this script preserves its original repository check.
#
# forsgren (ported 2026-10-01, forsgren#1 ladder step 9). Two changes, both
# forsgren's own (a third was added by forsgren#46, below):
#   1. The defaults: the site is .build/site, where Scripts/build_site.sh
#      renders it (forsgren commits no generated site), and the manifest is
#      the hand-authored internal/page/required-pages.json beside the
#      templates. Both arguments stay, so a caller can check another build.
#   2. A SITE WITH NO .html IN IT IS RED, AND SAYS SO. In konenki's copy an
#      empty site checked against an empty manifest reds only by accident:
#      the closing `grep -c .` counts nothing, exits 1 under set -e after
#      COMPLETED=1, and the run dies with no line at all. Against a non-empty
#      manifest it reds through a declared page it no longer finds, which
#      names a page, not the cause. Nothing covered is not covered, and the
#      red names that.
#   3. (forsgren#46) PAGES IN SUBFOLDERS COUNT. A view's page is served at
#      its folder, so standard/index.html is /standard/, and a page there
#      that the manifest does not declare is as red as one at the root.
# Self-test: Scripts/test_required_pages_covers_site_selftest.sh.

SITE_DIR="${1:-.build/site}"
SITE_DIR="${SITE_DIR%/}"
MANIFEST="${2:-internal/page/required-pages.json}"

# basename -> why it is not a required page. Empty today.
EXCLUDED=""

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: manifest/site coverage check aborted before completing" >&2
    exit 1
  fi
}

trap finish EXIT

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

if [[ ! -d "$SITE_DIR" ]]; then
  echo "FAIL: $SITE_DIR not found" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "FAIL: $MANIFEST not found" >&2
  exit 1
fi

listed="$(python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    required_pages = json.load(manifest_file)["requiredPages"]

for entry in required_pages:
    print(entry)
PY
)"

# forsgren change 2: zero pages is red, with its reason, before either
# direction runs.
html_count="$(find "$SITE_DIR" -type f -name '*.html' | wc -l | tr -d '[:space:]')"
if [[ "$html_count" -eq 0 ]]; then
  COMPLETED=1
  echo "FAIL: no .html page in ${SITE_DIR} — a site with nothing in it covers nothing" >&2
  exit 1
fi

# --- Direction 1: every servable page is declared.
while IFS= read -r f; do
  [ -f "$f" ] || continue
  rel="${f#"${SITE_DIR}"/}"
  if grep -qx "$rel" <<< "$EXCLUDED"; then
    echo "  skip: ${rel} (declared exclusion)"
    continue
  fi

  # A folder's index.html is served at the folder (forsgren#46):
  # standard/index.html is /standard/, index.html is /.
  path="/${rel}"
  [[ "$rel" == "index.html" || "$rel" == */index.html ]] && path="/${rel%index.html}"
  if ! grep -qx -- "$path" <<< "$listed"; then
    fail "${f} is served but not declared in ${MANIFEST} — promote will not verify it, and will still report success"
  fi
done < <(find "$SITE_DIR" -type f -name '*.html' | LC_ALL=C sort)

# --- Direction 2: every declared page exists.
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  if [[ "$path" == */ ]]; then
    f="${SITE_DIR}${path}index.html"
  else
    f="${SITE_DIR}${path}"
  fi

  if [[ ! -f "$f" ]]; then
    fail "${MANIFEST} declares ${path} but ${f} does not exist — every promote would fail on a 404"
  fi
done <<< "$listed"

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: the manifest and the site have drifted apart"
  exit 1
fi

n_listed="$(grep -c . <<< "$listed")"
echo "OK: manifest matches the site (${n_listed} pages declared, all present, none unlisted)"