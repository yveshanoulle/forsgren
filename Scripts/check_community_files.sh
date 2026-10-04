#!/usr/bin/env bash
# Scripts/check_community_files.sh
#
# The community-files gate (forsgren#43, extended by #44). Red unless the
# repository has a usable code of conduct and security policy, and says so
# in its README:
#   1. CODE_OF_CONDUCT.md exists at the repository root and names the
#      reporting address conduct@hanoulle.be,
#   2. SECURITY.md exists at the repository root and names the private
#      reporting route: "Report a vulnerability" or the advisories URL,
#   3. neither has a template placeholder left: a bracketed instruction such
#      as [INSERT CONTACT METHOD] or [Please provide ...], or any [...] that
#      is not a Markdown link (a bracket left open at the end of a line
#      counts),
#   4. README.md links to both in plain Markdown: a link inside a fenced code
#      block, an inline code span or an HTML comment is not a link.
#
# Why a gate: the Contributor Covenant ships with a placeholder where the
# reporting address goes. Nothing else notices a placeholder that was never
# filled, a route that was later edited out, or a README link that went
# stale; a policy nobody can report to is worse than none.
#
# The FAIL line names the file and the reason. Every check runs, so one run
# reports every finding.
#
# Usage: Scripts/check_community_files.sh [root-dir]   (default: the repo root)
# Exit: 0 clean, 1 a finding, 2 root dir missing.
# Fixture: Scripts/test_check_community_files.sh. The seven settings below
# start at column 0: its mutation proofs replace each by one that never
# matches (or always matches, or for README_STRIP and SECURITY_STRIP, by a program that strips
# nothing).

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

ROOT="${1:-$REPO}"

ADDRESS='conduct@hanoulle\.be'
SECURITY_ROUTE='Report a vulnerability|security/advisories/new'
# A bracket pair not followed by "(" is not a Markdown link; a "[" with no
# "]" after it on its line is an instruction that runs on.
PLACEHOLDER='\[[^]]*\]([^(]|$)|\[[^]]*$'
# The awk program that removes what is not Markdown prose from the README
# before the link patterns are looked for: fenced blocks, HTML comments,
# inline code spans (Scripts/strip_markdown_code.awk).
README_STRIP="Scripts/strip_markdown_code.awk"
# The same program, applied to SECURITY.md before the route is looked for: a
# route only inside a code block, a code span or a comment does not tell a
# reader how to report.
SECURITY_STRIP="Scripts/strip_markdown_code.awk"
README_LINK='\]\((\./)?CODE_OF_CONDUCT\.md(#[^)]*)?\)'
SECURITY_LINK='\]\((\./)?SECURITY\.md(#[^)]*)?\)'

if [ ! -d "$ROOT" ]; then
  echo "❌ FAIL: root dir not found: ${ROOT}"
  exit 2
fi

findings=0
finding() {
  echo "❌ FAIL: $1"
  findings=$((findings + 1))
}

# check_file <name> <route-pattern> <route-words> [strip-program]: <name>
# exists, matches <route-pattern> (after the strip program, if given) and has
# no placeholder.
check_file() {
  local file="$ROOT/$1"
  if [ ! -f "$file" ]; then
    finding "$1 is missing at the repository root"
    return
  fi
  local prose
  if [ -n "${4-}" ]; then prose="$(awk -f "$4" "$file")"; else prose="$(cat "$file")"; fi
  if ! grep -qE "$2" <<<"$prose"; then
    finding "$1 does not name the $3"
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    finding "$1:${line} has a placeholder left (a bracket that is not a Markdown link)"
  done < <(grep -nE "$PLACEHOLDER" "$file" | cut -d: -f1)
}

# check_readme_link <name> <link-pattern> <stripped-readme>: the stripped
# README links <name>.
check_readme_link() {
  if ! grep -qE "$2" <<<"$3"; then
    finding "README.md does not link to $1"
  fi
}

check_file CODE_OF_CONDUCT.md "$ADDRESS" "reporting address conduct@hanoulle.be"
check_file SECURITY.md "$SECURITY_ROUTE" "private reporting route (Report a vulnerability, or the advisories URL)" "$SECURITY_STRIP"

if [ ! -f "$ROOT/README.md" ]; then
  finding "README.md is missing, so it cannot link to CODE_OF_CONDUCT.md or SECURITY.md"
else
  stripped="$(awk -f "$README_STRIP" "$ROOT/README.md")"
  check_readme_link CODE_OF_CONDUCT.md "$README_LINK" "$stripped"
  check_readme_link SECURITY.md "$SECURITY_LINK" "$stripped"
fi

if [ "$findings" -ne 0 ]; then
  echo ""
  echo "community files: ${findings} finding(s) in ${ROOT}."
  exit 1
fi

echo "OK: community files: CODE_OF_CONDUCT.md names conduct@hanoulle.be, SECURITY.md names the private reporting route, neither has a placeholder left, and README.md links to both"
exit 0
