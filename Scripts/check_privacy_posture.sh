#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# check_privacy_posture.sh — does this site collect anything?
#
# WHY. Scripts/gate_report_order.txt declares `privacy pages|n/a` on the
# grounds that nothing is collected here: no forms, no analytics or tracking,
# no cookies or storage, no third-party assets or embeds. That is true the day
# it is written. Nothing else stops a Google Fonts link or an analytics
# snippet arriving the next day and leaving a false exemption on the record.
#
# Yves ruled privacy into the canon (web-infra unit 394) so every site must
# ANSWER the question rather than only the site that thought of it. This is the
# other half: the answer is checked. An exemption nothing enforces is a belief.
#
# NOT konenki's check_privacy_pages.sh, which validates the CONTENT of a
# privacy page, for a site that needs privacy pages. This asserts
# there is nothing to write a page about, which is this site's position.
#
# WHAT IS DELIBERATELY NOT A FINDING: outbound links. forsgren's page links
# nowhere off itself today (in coachretreat-website, where this copy is from,
# ticketing goes to pretix.eu and the footer to social platforms). A link
# transmits nothing until someone clicks it, and then they are plainly
# somewhere else; a new one is listed below on the next run. What
# matters is what the page loads or stores WITHOUT being asked — which is also
# why a third-party font stylesheet IS a finding: it sends every visitor's IP
# before anything is clicked, and it looks exactly like a local style link.
#
# Exit: 0 clean, 1 finding, 2 target missing.
# Usage: check_privacy_posture.sh [site-dir]  (default: .build/site)

SITE="${1:-.build/site}"

if [ ! -d "$SITE" ]; then
  echo "privacy-posture: site dir not found: $SITE" >&2
  exit 2
fi

findings=0

report() {
  # report <what> <why> <matches>
  echo "FINDING: $1" >&2
  echo "  $2" >&2
  printf '%s\n' "$3" | sed 's/^/    /' >&2
  findings=$((findings + 1))
}

scan() {
  # scan <pattern> — HTML and CSS, filenames included so a finding is locatable
  grep -rInE "$1" "$SITE" --include='*.html' --include='*.css' 2>/dev/null || true
}

hits="$(scan '<form[[:space:]>]')"
[ -n "$hits" ] && report "a form collects input" \
  "A form makes this site a collector. The n/a in gate_report_order.txt says it is not." "$hits"

hits="$(scan '<iframe')"
[ -n "$hits" ] && report "an embedded third party" \
  "An iframe loads from another party on page view, before any click." "$hits"

hits="$(scan '<(script|link)[^>]+(src|href)="https?://')"
[ -n "$hits" ] && report "a third-party asset is loaded" \
  "A script or stylesheet from another host sends every visitor's IP there on page view. Self-host it, as the fonts in this repo are." "$hits"

hits="$(scan 'url\([\"'"'"']?https?://')"
[ -n "$hits" ] && report "a stylesheet fetches from another host" \
  "An @font-face or background url() pointing off-site transmits on render." "$hits"

hits="$(scan 'document\.cookie|localStorage|sessionStorage')"
[ -n "$hits" ] && report "cookies or browser storage" \
  "Storing anything on the visitor's device is exactly what the exemption says this site does not do." "$hits"

hits="$(scan 'gtag\(|googletagmanager|google-analytics|matomo|plausible\.io|hotjar|segment\.(io|com)|clarity\.ms')"
[ -n "$hits" ] && report "an analytics or tracking snippet" \
  "Inline analytics carries no src attribute, so it hides from the third-party-asset check above." "$hits"

if [ "$findings" -ne 0 ]; then
  echo "" >&2
  echo "privacy-posture: ${findings} finding(s) in ${SITE}." >&2
  echo "  This site declares 'privacy pages|n/a' in Scripts/gate_report_order.txt" >&2
  echo "  because it collects nothing. That is no longer true. Either remove the" >&2
  echo "  collection, or replace the n/a with a real privacy page and say what is" >&2
  echo "  collected and by whom." >&2
  exit 1
fi

# --- INFORMATION, not findings. None of the below fails the gate.
#
# "No third-party assets" is a claim about an ABSENCE, and an absence is the
# hardest thing for a reader to check. Showing the fonts this repo serves and
# the hosts visitors are sent to makes the verdict inspectable rather than
# trusted — the same reason the duplication ratchet prints its percentage on a
# green run. It also means a NEW outbound destination shows up in the report
# the day it lands, without the gate having to decide whether it is acceptable.
echo ""
echo "INFO — what this site loads and where it points (none of this is a finding):"

font_files="$(find "$SITE" -type f \( -name '*.woff' -o -name '*.woff2' -o -name '*.otf' -o -name '*.ttf' -o -name '*.eot' \) 2>/dev/null | wc -l | tr -d ' ')"
font_faces="$(grep -rhoE '@font-face' "$SITE" --include='*.css' --include='*.html' 2>/dev/null | wc -l | tr -d ' ')"
echo "  fonts   ${font_faces} @font-face rule(s), ${font_files} font file(s) served from this repo"
echo "          (self-hosted: a font stylesheet from another host would send every"
echo "           visitor's IP there on page view, which is why that IS a finding)"

echo "  links   outbound destinations visitors can choose to follow:"
outbound="$(grep -rhoE '<a[^>]+href="https?://[^"]+"' "$SITE" --include='*.html' 2>/dev/null \
  | grep -oE 'https?://[a-zA-Z0-9.-]+' \
  | sed -E 's#https?://##' \
  | sort | uniq -c | sort -rn || true)"
if [ -z "$outbound" ]; then
  # An empty list must SAY it is empty. A header with nothing under it reads
  # as a rendering failure, and "no outbound links at all" is a real and
  # unusual property worth stating rather than leaving as whitespace.
  echo "            (none — this site links nowhere off itself)"
else
  printf '%s\n' "$outbound" | while read -r n host; do
    printf '            %-34s %s link(s)\n' "$host" "$n"
  done
fi

echo ""
echo "OK: privacy posture (no forms, no third-party assets, no cookies or storage, no analytics in ${SITE})"
exit 0
