#!/usr/bin/env bash
# Scripts/build_starter_page.sh
#
# Builds forsgren's starter page (forsgren#132): README.md rendered to one
# HTML page by ./cmd/readmepage, with the CNAME file GitHub Pages reads for
# the custom domain. The page is forsgren.be.
#
# Usage: Scripts/build_starter_page.sh [out-dir]   (default: .build/starter)
#
# STARTER_README names another Markdown file to render (default README.md),
# so Scripts/test_build_starter_page.sh can feed it a README the renderer
# refuses. A failed build writes nothing into out-dir: the page is rendered
# into a staging directory first and copied only once it is whole.
# Fixture: Scripts/test_build_starter_page.sh.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

VERSION=1

OUTPUT_DIR="${1:-.build/starter}"
README="${STARTER_README:-README.md}"
DOMAIN="forsgren.be"

# fail <reason> — prints why the build failed and stops it before the copy.
fail() {
  echo "❌ build-starter-page: $1" >&2
  exit 1
}

echo "build_starter_page v${VERSION}"

STAGE="$(mktemp -d)"
# Issue forsgren#137. On bash 3.2 an abort (an unbound variable under set -eu)
# ends a script with an EXIT trap with status 0, and $? in the trap is 0 too.
# COMPLETED, set as the very last statement, is the only way out with 0: an
# exit of 0 without it is an abort and becomes exit 1. Gate:
# Scripts/check_exit_trap_completion.sh.
COMPLETED=0
finish() {
  local rc=$?
  rm -rf "$STAGE"
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: build_starter_page.sh aborted before completing (COMPLETED was never set)" >&2
    exit 1
  fi
}
trap finish EXIT

go run ./cmd/readmepage --readme "$README" --out "$STAGE" || fail "readmepage could not render ${README}"
[ -s "${STAGE}/index.html" ] || fail "readmepage wrote no index.html"
printf '%s\n' "$DOMAIN" > "${STAGE}/CNAME"

mkdir -p "$OUTPUT_DIR" 2>/dev/null || fail "cannot create the output directory ${OUTPUT_DIR}"
cp -R "$STAGE"/. "$OUTPUT_DIR"/ || fail "cannot copy the page into ${OUTPUT_DIR}"

echo ""
echo "✅ build_starter_page v${VERSION} — index.html and CNAME (${DOMAIN}) in ${OUTPUT_DIR}"
COMPLETED=1
