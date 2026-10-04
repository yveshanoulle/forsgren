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
# every *.html under the site, in subfolders too (found with find, as bash
# 3.2 has no globstar; Yves's ruling on forsgren#39, step 4), is staged ALONE
# as the index.html of its own temp directory, as
# Scripts/check_golden_pages.sh stages a golden page, and measured by
# Scripts/check_html_dupl.sh at the ceiling below. Duplication WITHIN a page
# is still held to it. A red names the page by its path in the site,
# "sub/x.html"; every page is measured, so one run reports every finding.
#
# Ceiling 0.00% — measured 2026-10-01 with the pinned jscpd 4.2.4 against
# .build/site: 1 file, 0 clones. Direction DOWN, as for the template ceiling.
# Unchanged by measuring per page, and never raised to clear a red.
#
# A site with no .html (or no such directory) is handed to check_html_dupl.sh
# as it is, so its exit 2 and its "scanned 0 .html files" reason stay its own.
# Exit: 0 every page at or under the ceiling, 1 a page over it, 2 a tooling
# failure: that script's exit 2 (tooling, nothing scanned), any other exit
# of it but 0 or 1, named, never reported as over the ceiling, and a
# `mktemp -d` that fails, said before anything is staged.
#
# Usage: check_html_dupl_site.sh [site-dir]  (default: .build/site)
# Self-test: Scripts/test_check_html_dupl.sh.

SITE_DIR="${1:-.build/site}"
SITE_DIR="${SITE_DIR%/}"
SITE_MAX_PCT="0.00"

pages=()
if [[ -d "$SITE_DIR" ]]; then
  while IFS= read -r page; do
    pages+=("$page")
  done < <(find "$SITE_DIR" -type f -name '*.html' | LC_ALL=C sort)
fi

if [[ "${#pages[@]}" -eq 0 ]]; then
  exec ./Scripts/check_html_dupl.sh "$SITE_DIR" "$SITE_MAX_PCT"
fi

if ! STAGE="$(mktemp -d)" || [[ -z "$STAGE" ]]; then
  echo "html-dupl: mktemp -d failed, so no page of ${SITE_DIR} can be staged — nothing measured is not clean" >&2
  exit 2
fi
trap 'rm -rf "$STAGE"' EXIT

failed=0
count=0
for page in "${pages[@]}"; do
  count=$((count + 1))
  name="${page#"$SITE_DIR"/}"
  mkdir -p "${STAGE}/${count}"
  cp "$page" "${STAGE}/${count}/index.html"
  rc=0
  out="$(./Scripts/check_html_dupl.sh "${STAGE}/${count}" "$SITE_MAX_PCT" 2>&1)" || rc=$?
  case "$rc" in
    0) ;;
    1)
      echo "html-dupl: ${name} in ${SITE_DIR} is over the ceiling (staged alone as index.html)"
      printf '%s\n' "$out"
      failed=1
      ;;
    2)
      printf '%s\n' "$out" >&2
      exit 2
      ;;
    *)
      echo "html-dupl: Scripts/check_html_dupl.sh ended with exit ${rc} on ${name} in ${SITE_DIR} — a tooling failure, nothing measured" >&2
      printf '%s\n' "$out" >&2
      exit 2
      ;;
  esac
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
echo "OK: html duplication at or under ${SITE_MAX_PCT}% in each of ${count} page(s) in ${SITE_DIR}, measured one page at a time — ratchet holds"
