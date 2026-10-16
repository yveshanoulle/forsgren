#!/usr/bin/env bash
# canon: test_required_pages_covers_site v1
# Scripts/test_required_pages_covers_site.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# Does the manifest still describe the site?
#
# A manifest that is correct by attention, not by construction, rots. And the
# pages it declares can be legal surfaces (a privacy policy), so a page added to
# the site and left out of the manifest is not merely unverified, it is a
# surface nothing watches.
#
# Scripts/validate_required_pages.sh checks the manifest's SHAPE: valid JSON,
# root-relative entries, no duplicates, not empty. It cannot check the thing
# that actually rots: whether the manifest still matches the site it ships
# with. Both halves pass happily while drifting apart:
#
#   - a page added to the site and not listed is never verified on promote, so
#     the release can serve a broken new page and promote reports success
#   - a page listed but deleted makes every promote fail on a 404, which is
#     loud and therefore self-correcting, but it is checked here too, because
#     finding it at promote time means finding it during a deploy
#
# The first case is the dangerous one: it fails SILENTLY, by verifying less
# than it claims to. That is the exact failure this arc keeps meeting.
#
# Also red, and said: a site with no .html in it (nothing covered is not
# covered). Pages in subfolders count: a folder's index.html is served at the
# folder, so standard/index.html is /standard/, and one the manifest does not
# declare is as red as one at the root.
#
# THE VALUES ARE DATA, not code. With no arguments the site directory
# (site_dir) and the manifest (required_pages_manifest) come from
# Scripts/site_settings.txt through Scripts/lib_site_settings.sh, and the
# exclusions from Scripts/required_pages_exclusions.txt (page|reason, a missing
# file is red, a row without a reason is red). The arguments exist so a caller
# can check another build, and so the self-test can drive the gate with sites
# of its own:
#
#   test_required_pages_covers_site.sh [site-dir [manifest [exclusions]]]
#
# Self-test: Scripts/test_required_pages_covers_site_selftest.sh.

# shellcheck source=Scripts/lib_site_settings.sh
source Scripts/lib_site_settings.sh
SETTINGS="Scripts/site_settings.txt"

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

SITE_DIR="${1:-}"
[[ -n "$SITE_DIR" ]] || SITE_DIR="$(site_settings_get "$SETTINGS" site_dir)"
SITE_DIR="${SITE_DIR%/}"
MANIFEST="${2:-}"
[[ -n "$MANIFEST" ]] || MANIFEST="$(site_settings_get "$SETTINGS" required_pages_manifest)"
EXCLUSIONS="${3:-Scripts/required_pages_exclusions.txt}"

if [[ ! -d "$SITE_DIR" ]]; then
  echo "FAIL: $SITE_DIR not found" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "FAIL: $MANIFEST not found" >&2
  exit 1
fi

if [[ ! -f "$EXCLUSIONS" ]]; then
  echo "FAIL: $EXCLUSIONS not found" >&2
  exit 1
fi

# page -> why it is not a required page. One `page|reason` row per exclusion;
# a row without a reason is red, named, and the rest is still read.
excluded=""
row_pattern='^[^|[:space:]]+[|].*[^[:space:]]'
row_no=0
while IFS= read -r row || [[ -n "$row" ]]; do
  row_no=$((row_no + 1))
  case "$row" in '' | '#'*) continue ;; esac
  if [[ "$row" =~ $row_pattern ]]; then
    excluded="${excluded}${row%%|*}"$'\n'
  else
    fail "${EXCLUSIONS} line ${row_no} is not page|reason (a reason is required): ${row}"
  fi
done < "$EXCLUSIONS"

listed="$(python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    required_pages = json.load(manifest_file)["requiredPages"]

for entry in required_pages:
    print(entry)
PY
)"

# Zero pages is red, with its reason, before either direction runs.
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
  if grep -qx -- "$rel" <<< "$excluded"; then
    echo "  skip: ${rel} (declared exclusion)"
    continue
  fi

  # A folder's index.html is served at the folder:
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
