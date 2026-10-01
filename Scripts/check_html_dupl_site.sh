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
# Ceiling 0.00% — measured 2026-10-01 with the pinned jscpd 4.2.4 against
# .build/site: 1 file, 0 clones. Direction DOWN, as for the template ceiling.
# KNOWN LIMIT, measured the same day: the rendered header chrome alone is a
# 112-token clone, over jscpd's 50-token minimum, so a SECOND generated page
# reds this ceiling (a copy of index.html with another <h1> measured 34.21%)
# although the templates stay at 0.00%. What the ceiling does then is a ruling
# on forsgren#1, not a raise made to clear the red.
#
# Usage: check_html_dupl_site.sh [site-dir]  (default: .build/site)

SITE_DIR="${1:-.build/site}"
SITE_MAX_PCT="0.00"

exec ./Scripts/check_html_dupl.sh "$SITE_DIR" "$SITE_MAX_PCT"
