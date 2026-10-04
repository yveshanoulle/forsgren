#!/usr/bin/env bash
# Scripts/build_site.sh
#
# Builds forsgren's static site: compiles ./cmd/forsgren into .build/bin/ and
# runs `forsgren render` into the output directory (default .build/site).
# FBP.sh's BUILD phase, between the pre and post gates.
#
# The page-count contract is another estate repository's (its issues #8 and #11): the
# count of generated pages goes to SITE_PAGE_COUNT_FILE (default
# .build/site-page-count.log), written ONLY once everything succeeded, so a
# failed build leaves no count and FBP.sh fails the build step by name.
#
# Usage: Scripts/build_site.sh [out-dir]
#
# FORSGREN_BIN_DIR moves the compiled binary (default .build/bin), so
# Scripts/test_build_site.sh can build without touching the repository's own.
# Fixture: Scripts/test_build_site.sh.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

VERSION=1

OUTPUT_DIR="${1:-.build/site}"
PAGE_COUNT_SINK="${SITE_PAGE_COUNT_FILE:-.build/site-page-count.log}"
BIN_DIR="${FORSGREN_BIN_DIR:-.build/bin}"
BIN="${BIN_DIR}/forsgren"

# fail <reason> — prints why the build failed and stops it before the sink.
fail() {
  echo "❌ build-site: $1" >&2
  exit 1
}

echo "build_site v${VERSION}"

mkdir -p "$BIN_DIR"
go build -o "$BIN" ./cmd/forsgren || fail "go build ./cmd/forsgren failed"

# Rendered into a fresh staging directory first, so the count is this run's
# pages and never a stale file already in OUTPUT_DIR.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

"$BIN" render --out "$STAGE" > /dev/null || fail "forsgren render failed"

PAGE_COUNT="$(find "$STAGE" -type f -name '*.html' | wc -l | tr -d '[:space:]')"
[ "$PAGE_COUNT" -gt 0 ] || fail "forsgren render wrote no pages"

mkdir -p "$OUTPUT_DIR" 2>/dev/null || fail "cannot create the output directory ${OUTPUT_DIR}"
cp -R "$STAGE"/. "$OUTPUT_DIR"/ || fail "cannot copy the site into ${OUTPUT_DIR}"

echo ""
echo "Generated files:"
(cd "$STAGE" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) | sed "s|^|  ${OUTPUT_DIR}/|"

# The sink, last: every failure above has already exited.
mkdir -p "$(dirname "$PAGE_COUNT_SINK")"
echo "$PAGE_COUNT" > "$PAGE_COUNT_SINK"

echo ""
echo "✅ build_site v${VERSION} — ${PAGE_COUNT} pages generated"
