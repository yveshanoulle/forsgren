#!/usr/bin/env bash
# Scripts/check_code_of_conduct.sh
#
# The code-of-conduct gate (forsgren#43). Red unless the repository has a
# usable code of conduct and says so in its README:
#   1. CODE_OF_CONDUCT.md exists at the repository root,
#   2. it names the reporting address conduct@hanoulle.be,
#   3. it has no template placeholder left: a bracketed instruction such as
#      [INSERT CONTACT METHOD] or [Please provide ...], or any [...] that is
#      not a Markdown link (a bracket left open at the end of a line counts),
#   4. README.md links to it in plain Markdown: a link inside a fenced code
#      block, an inline code span or an HTML comment is not a link.
#
# Why a gate: the Contributor Covenant ships with a placeholder where the
# reporting address goes. Nothing else notices a placeholder that was never
# filled, an address that was later edited out, or a README link that went
# stale; a code of conduct nobody can report to is worse than none.
#
# The FAIL line names the file and the reason. Every check runs, so one run
# reports every finding.
#
# Usage: Scripts/check_code_of_conduct.sh [root-dir]   (default: the repo root)
# Exit: 0 clean, 1 a finding, 2 root dir missing.
# Fixture: Scripts/test_check_code_of_conduct.sh. The four settings below
# start at column 0: its mutation proofs replace each by one that never
# matches (or always matches, or for README_STRIP, by a program that strips
# nothing).

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

ROOT="${1:-$REPO}"

ADDRESS='conduct@hanoulle\.be'
# A bracket pair not followed by "(" is not a Markdown link; a "[" with no
# "]" after it on its line is an instruction that runs on.
PLACEHOLDER='\[[^]]*\]([^(]|$)|\[[^]]*$'
# The awk program that removes what is not Markdown prose from the README
# before README_LINK is looked for: fenced blocks, HTML comments, inline code
# spans (Scripts/strip_markdown_code.awk).
README_STRIP="Scripts/strip_markdown_code.awk"
README_LINK='\]\((\./)?CODE_OF_CONDUCT\.md(#[^)]*)?\)'

if [ ! -d "$ROOT" ]; then
  echo "❌ FAIL: root dir not found: ${ROOT}"
  exit 2
fi

findings=0
finding() {
  echo "❌ FAIL: $1"
  findings=$((findings + 1))
}

COC="$ROOT/CODE_OF_CONDUCT.md"
if [ ! -f "$COC" ]; then
  finding "CODE_OF_CONDUCT.md is missing at the repository root"
else
  if ! grep -qE "$ADDRESS" "$COC"; then
    finding "CODE_OF_CONDUCT.md does not name the reporting address conduct@hanoulle.be"
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    finding "CODE_OF_CONDUCT.md:${line} has a placeholder left (a bracket that is not a Markdown link)"
  done < <(grep -nE "$PLACEHOLDER" "$COC" | cut -d: -f1)
fi

if [ ! -f "$ROOT/README.md" ]; then
  finding "README.md is missing, so it cannot link to CODE_OF_CONDUCT.md"
elif ! awk -f "$README_STRIP" "$ROOT/README.md" | grep -qE "$README_LINK"; then
  finding "README.md does not link to CODE_OF_CONDUCT.md"
fi

if [ "$findings" -ne 0 ]; then
  echo ""
  echo "code of conduct: ${findings} finding(s) in ${ROOT}."
  exit 1
fi

echo "OK: code of conduct: CODE_OF_CONDUCT.md names conduct@hanoulle.be, has no placeholder left, and README.md links to it"
exit 0
