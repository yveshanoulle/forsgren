#!/usr/bin/env bash
# Scripts/check_starter_links.sh
#
# The starter-page link check (forsgren#132, Yves's ruling on decision #149).
# forsgren's own. The starter page is rendered from README.md and links into
# the project: its repository, forsgren-template and the live example. This
# check allows exactly those three destinations and nothing else, so a README
# that grows a link to anywhere else (a private repository, a tracker, a
# stray host) turns the page red instead of being published.
#
# It is a NEW check, not an exemption of Scripts/check_repo_links.sh: that
# gate keeps its rule for the metrics site (no github.com/<owner>/<repo> path
# at all) and is never run on the starter page.
#
# Every href and src of every .html file under the directory must be an
# #anchor, the page's own stylesheet or icon (exactly styles.css or favicon.svg), or an https link to
#   github.com/yveshanoulle/forsgren           (and any path or anchor in it)
#   github.com/yveshanoulle/forsgren-template  (the same)
#   forsgren.forsgren.be                       (the same)
# The allowed names end at the end of the host or the repository name: a
# forsgren-templates or forsgren.forsgren.be.example.org is not forsgren.
# A relative link, an http link, a mailto and a src outside the list are
# findings too.
#
# The FAIL line names file:line and the link's host, NEVER the link: sfl
# quotes FAIL lines into its summary and FBP.sh into its own, and CI puts
# every gate's output on the job's summary page, so a printed private
# repository path would be copied wherever those go (the rule
# Scripts/check_repo_links.sh follows for the same reason).
#
# Red-on-zero: a directory with no .html page is red. Nothing scanned is not
# clean.
#
# Usage: Scripts/check_starter_links.sh [dir]   (default: .build/starter)
# Exit: 0 clean, 1 a finding or a scan over nothing, 2 dir missing.
# Fixture: Scripts/test_check_starter_links.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

DIR="${1:-.build/starter}"

# The one pattern: an allowed link. The row starts at column 0 with ALLOWED=:
# Scripts/test_check_starter_links.sh's mutation proof replaces it by a
# pattern that matches everything.
ALLOWED='^(#.*|styles\.css|favicon\.svg|https://(github\.com/yveshanoulle/(forsgren|forsgren-template)|forsgren\.forsgren\.be)([/#?].*)?)$'

if [ ! -d "$DIR" ]; then
  echo "❌ FAIL: starter page dir not found: ${DIR}"
  exit 2
fi

PAGES="$(find "$DIR" -type f -name '*.html' | wc -l | tr -d '[:space:]')"
if [ "$PAGES" -eq 0 ]; then
  echo "❌ FAIL: no .html page in ${DIR} — a scan over nothing is not a clean scan"
  exit 1
fi

# host_of <link> — the part to print instead of the link.
host_of() {
  case "$1" in
    https://* | http://*) echo "$1" | sed -E 's#^https?://([^/?\#]*).*#\1#' ;;
    *) echo "(a relative or non-web link)" ;;
  esac
}

findings=0
links=0
while IFS= read -r file; do
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    line="${hit%%:*}"
    link="${hit#*:}"
    link="${link#*=\"}"
    link="${link%\"}"
    links=$((links + 1))
    if ! grep -qE "$ALLOWED" <<< "$link"; then
      echo "❌ FAIL: ${file}:${line} — a link to $(host_of "$link"), which the starter page may not link to (allowed: github.com/yveshanoulle/forsgren, github.com/yveshanoulle/forsgren-template, forsgren.forsgren.be; the link is not printed here)"
      findings=$((findings + 1))
    fi
  done < <(grep -noE '(href|src)="[^"]*"' "$file" || true)
done < <(find "$DIR" -type f -name '*.html')

if [ "$findings" -ne 0 ]; then
  echo ""
  echo "starter page links: ${findings} finding(s) in ${DIR}. Fix the link in README.md, or add the destination to ALLOWED in this script with Yves's yes."
  exit 1
fi

echo "✅ starter page links: ${links} link(s) in ${PAGES} page(s) of ${DIR}, every one an anchor, forsgren, forsgren-template or forsgren.forsgren.be"
exit 0
