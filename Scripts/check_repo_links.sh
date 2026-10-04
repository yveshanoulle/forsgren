#!/usr/bin/env bash
# Scripts/check_repo_links.sh
#
# The repository-links gate (forsgren#1, ladder step 10). Not canon:
# forsgren's own, a direct consequence of its design rule that the public page
# shows numbers and dates only, with no links into private repositories.
#
# Red on any github.com/<owner>/<repo> path in a generated .html or .css file,
# linked or not: an href, a src, a url() or plain text. The gate cannot tell a
# private repository from a public one (which repositories an installation
# measures is its own config, kept outside this repository), and the page has
# no reason to point into any repository, so every repository path is a
# finding. A github.com link to an owner alone (github.com/<owner>) is not a
# path into a repository and is not a finding here; check_privacy_posture.sh
# lists it among the outbound hosts on a green run.
#
# The FAIL line names the file and line, NEVER the path it matched: sfl
# quotes FAIL lines into its summary, FBP.sh into its own, and CI puts every
# gate's output on the job's summary page, so a printed private repository
# name would be copied wherever those go (the rule
# Scripts/check_data_guard.sh follows for the same reason).
#
# One narrow exception (Yves's ruling on forsgren#41): the tool's own
# public repository. An href to exactly https://github.com/yveshanoulle/forsgren,
# with an optional #anchor, is not a finding: the page footer links the tool
# that made it. Nothing else is
# exempt: forsgren-data, forsgren-template (its footer link left in
# forsgren#45), forsgren/issues, forsgren/blob/..., another owner, and
# the same path as plain text or in a url() all stay findings.
#
# Red-on-zero: a site with no .html page is red. Nothing scanned is not clean.
#
# Usage: Scripts/check_repo_links.sh [site-dir]   (default: .build/site)
# Exit: 0 clean, 1 a finding or a scan over nothing, 2 site dir missing.
# Fixture: Scripts/test_check_repo_links.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

SITE="${1:-.build/site}"

# The one pattern: a github.com/<owner>/<repo> path. The row starts at
# column 0 with REPO_PATH=: Scripts/test_check_repo_links.sh's mutation proof
# replaces it by that anchor.
REPO_PATH='github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+'

# The exception: a sed expression that removes an allowed href before the scan.
# The row starts at column 0 with OWN_LINK=: Scripts/test_check_repo_links.sh's
# mutation proof replaces it by that anchor. The closing quote right after the
# optional anchor is what keeps forsgren-data and forsgren/issues findings.
OWN_LINK='s#href="https://github\.com/yveshanoulle/forsgren(\#[A-Za-z0-9_.-]*)?"##g'

if [ ! -d "$SITE" ]; then
  echo "❌ FAIL: site dir not found: ${SITE}"
  exit 2
fi

PAGES="$(find "$SITE" -type f -name '*.html' | wc -l | tr -d '[:space:]')"
if [ "$PAGES" -eq 0 ]; then
  echo "❌ FAIL: no .html page in ${SITE} — a scan over nothing is not a clean scan"
  exit 1
fi

findings=0
# file:line only; the matched path never reaches stdout. The allowed href is
# cut out of each line first.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "❌ FAIL: ${hit} — a github.com/<owner>/<repo> path on the public page (the path is not printed here, so it cannot reach a commit message); the page shows numbers and dates only, never links into repositories"
  findings=$((findings + 1))
done < <(
  while IFS= read -r file; do
    sed -E -e "$OWN_LINK" "$file" | grep -nE "$REPO_PATH" | cut -d: -f1 | sed "s#^#${file}:#"
  done < <(find "$SITE" -type f \( -name '*.html' -o -name '*.css' \))
)

if [ "$findings" -ne 0 ]; then
  echo ""
  echo "repository links: ${findings} finding(s) in ${SITE}. Fix the template under internal/page/."
  exit 1
fi

echo "✅ repository links: no github.com/<owner>/<repo> path in ${PAGES} page(s) and their stylesheets in ${SITE}"
exit 0
