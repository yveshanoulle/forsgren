#!/usr/bin/env bash
# Scripts/check_html_dupl_site.sh

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# HTML duplication ratchet over the GENERATED page (forsgren#1, ladder step 11).
#
# forsgren's own, a wrapper so Scripts/gate_report_order.txt can name a PATH:
# an order-file row carries no arguments, and this ratchet needs a second
# target and its own ceiling. All measuring and gating is
# Scripts/check_html_dupl.sh's; see its header.
#
# Why the generated page too (Yves's ruling on forsgren#1): the template scan
# sees each template once, so a page template that pastes the header markup
# instead of calling {{template "header"}} is a clone only the rendered pages
# show. konenki-website scans its authored source only, because there the
# generated pages repeat the composed chrome by design.
#
# EACH PAGE ALONE (forsgren#39, step 1). Pages rendered from one layout repeat
# its chrome (the rendered header alone is a 112-token clone, over jscpd's
# 50-token minimum), which is duplication in the OUTPUT of two pages, not in
# any page and not in the source: the template scan above stays as it is. So
# every *.html of the site is staged ALONE as the index.html of its own temp
# directory, as Scripts/check_golden_pages.sh stages a golden page, and
# measured by Scripts/check_html_dupl.sh at the ceiling below. Duplication
# WITHIN a page is still held to it. A red names the page; every page is
# measured, so one run reports every finding.
#
# Ceiling 0.00% — measured 2026-10-01 with the pinned jscpd 4.2.4 against
# .build/site: 1 file, 0 clones. Direction DOWN, as for the template ceiling.
# Unchanged by measuring per page, and never raised to clear a red.
#
# A site with no .html (or no such directory) is handed to check_html_dupl.sh
# as it is, so its exit 2 and its "scanned 0 .html files" reason stay its own.
# Exit: 0 every page at or under the ceiling, 1 a page over it, 2 as that
# script's (tooling, nothing scanned).
#
# Usage: check_html_dupl_site.sh [site-dir]  (default: .build/site)
# Self-test: Scripts/test_check_html_dupl.sh.

SITE_DIR="${1:-.build/site}"
SITE_MAX_PCT="0.00"

shopt -s nullglob
pages=("$SITE_DIR"/*.html)
shopt -u nullglob

if [[ ! -d "$SITE_DIR" || "${#pages[@]}" -eq 0 ]]; then
  exec ./Scripts/check_html_dupl.sh "$SITE_DIR" "$SITE_MAX_PCT"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

failed=0
count=0
for page in "${pages[@]}"; do
  count=$((count + 1))
  name="$(basename "$page")"
  mkdir -p "${STAGE}/${count}"
  cp "$page" "${STAGE}/${count}/index.html"
  rc=0
  out="$(./Scripts/check_html_dupl.sh "${STAGE}/${count}" "$SITE_MAX_PCT" 2>&1)" || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    printf '%s\n' "$out" >&2
    exit 2
  fi
  if [[ "$rc" -ne 0 ]]; then
    echo "html-dupl: ${name} in ${SITE_DIR} is over the ceiling (staged alone as index.html)"
    printf '%s\n' "$out"
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
echo "OK: html duplication at or under ${SITE_MAX_PCT}% in each of ${count} page(s) in ${SITE_DIR}, measured one page at a time — ratchet holds"
