#!/usr/bin/env bash
# Scripts/check_golden_pages.sh
#
# The page gates over the golden pages (forsgren#12, step 8). forsgren's
# own; no repository of the estate renders one page from data.
#
# WHY. Scripts/build_site.sh renders the page without an installation's
# config or history: forsgren's own build has neither. So HTMLHint, the
# privacy-posture check and the generated-page duplication ratchet, which
# scan .build/site, only ever see the placeholder, never the page WITH data
# (each project's deployment frequency) or the no-projects line. The golden
# pages of internal/page/testdata are those pages: the Go tests pin each one
# byte for byte to what forsgren renders (internal/page/page_test.go, and
# cmd/forsgren/render_data_test.go for the page with data, from a made-up
# history).
#
# WHAT. Every *.golden.html file of the directory, each staged ALONE as the
# index.html of its own temp directory, as the site's one page is, is run
# through Scripts/gate_htmlhint.sh, Scripts/check_privacy_posture.sh and
# Scripts/check_html_dupl_site.sh. Alone, because the goldens share the page
# chrome, and two of them side by side would be clones of each other that no
# published site holds. Every finding names the golden page and the gate,
# and every gate runs on every page, so one run reports every finding.
#
# Red on zero: a directory with no *.golden.html is red, nothing scanned is
# not clean; a directory that does not exist exits 2, as the gates it calls
# do.
#
# Usage: check_golden_pages.sh [golden-dir]  (default: internal/page/testdata)
# Self-test: Scripts/test_check_golden_pages.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

GOLDEN_DIR="${1:-internal/page/testdata}"

if [[ ! -d "$GOLDEN_DIR" ]]; then
  echo "golden-pages: directory not found: ${GOLDEN_DIR}" >&2
  exit 2
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# gate <label> <script> <site-dir>: runs one gate on one staged page; its
# output is shown only when it is red.
gate() {
  local out rc=0
  out="$("$2" "$3" 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "❌ FAIL: ${GOLDEN_NAME}: $1 is red (exit ${rc})"
    printf '%s\n' "$out" | sed 's/^/    /'
    FAILED=1
  fi
}

FAILED=0
PAGES=0
for golden in "$GOLDEN_DIR"/*.golden.html; do
  [[ -f "$golden" ]] || continue
  PAGES=$((PAGES + 1))
  GOLDEN_NAME="$(basename "$golden")"
  site="${STAGE}/${PAGES}"
  mkdir -p "$site"
  cp "$golden" "${site}/index.html"
  gate "HTMLHint" Scripts/gate_htmlhint.sh "$site"
  gate "privacy posture" Scripts/check_privacy_posture.sh "$site"
  gate "html duplication" Scripts/check_html_dupl_site.sh "$site"
done

if [[ "$PAGES" -eq 0 ]]; then
  echo "❌ FAIL: no *.golden.html under ${GOLDEN_DIR} — nothing scanned is not clean"
  exit 1
fi
if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
echo "OK: ${PAGES} golden page(s) under ${GOLDEN_DIR} pass HTMLHint, privacy posture and html duplication, each alone"
