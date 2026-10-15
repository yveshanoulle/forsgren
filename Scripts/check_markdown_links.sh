#!/usr/bin/env bash
# Scripts/check_markdown_links.sh
#
# The markdown-links gate (forsgren#147). Not canon: forsgren's own. Red when
# a relative link in a tracked Markdown file points at nothing tracked:
# README.md, CLAUDE.md, docs/*.md, agent-*.md, SHIPPED.md and every other
# tracked *.md, SHIPPED.md included (its history links must still resolve:
# a file moved is a link moved).
#
# A relative link is an inline [text](path) or [text](path#anchor), or a
# reference definition [label]: path, outside a fenced block, an HTML comment
# and an inline code span (Scripts/extract_markdown_links.awk). Not checked:
# a link with a scheme (https:, mailto:, ...), a protocol-relative //host
# link, and a pure #anchor. The path is resolved against the directory of the
# file that holds the link (a leading / against the repository root), with
# ./ and ../ folded, and must name a TRACKED file or a directory that holds a
# tracked file (git ls-files), spelled with the right case. A ../ that leaves
# the repository is red. The #anchor and a ?query are cut before resolving;
# whether the anchor names a heading is not checked here.
#
# Why a gate: Scripts/check_repo_links.sh only walks the generated html and
# css, and check_script_references.sh only Scripts paths. A doc moved or
# renamed left its links dead, and nothing noticed.
#
# The FAIL line names file:line and the link as written. Every link is
# checked, so one run reports every finding. Red-on-zero: a root with no
# tracked Markdown file, or no relative link at all, is red.
#
# Usage: Scripts/check_markdown_links.sh [root-dir]   (default: the repo root)
# Exit: 0 clean, 1 a finding or a scan over nothing, 2 root missing or not a
# git work tree.
# Fixture: Scripts/test_check_markdown_links.sh. The two settings below start
# at column 0: its mutation proofs replace each.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

ROOT="${1:-$REPO}"

# The link reader (Scripts/extract_markdown_links.awk).
LINK_READER="$REPO/Scripts/extract_markdown_links.awk"
# A target that is not a relative path: a scheme, //host, or a pure #anchor.
NOT_RELATIVE='^([A-Za-z][A-Za-z0-9+.-]*:|//|#)'

if [ ! -d "$ROOT" ]; then
  echo "❌ FAIL: root dir not found: ${ROOT}"
  exit 2
fi
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ FAIL: ${ROOT} is not a git work tree, so there is no list of tracked files"
  exit 2
fi

TMPDIR_GATE="$(mktemp -d)"
COMPLETED=0
trap 'rm -rf "$TMPDIR_GATE"; if [ "$COMPLETED" -ne 1 ]; then echo "❌ FAIL: check_markdown_links.sh aborted before completing" >&2; exit 1; fi' EXIT

# The tracked files, and every directory that holds one, one per line.
TRACKED="$TMPDIR_GATE/tracked"
git -C "$ROOT" ls-files | awk '
  { print }
  { p = $0; while ((i = match(p, /\/[^\/]*$/)) > 0) { p = substr(p, 1, i - 1); print p } }
' | sort -u > "$TRACKED"

# normalize <dir> <target>: the target folded onto the directory ("" for the
# root), printed; empty output when it climbs out of the repository.
normalize() {
  local base="$1" target="$2" part
  local -a stack=()
  case "$target" in
    /*) base="" ;;
  esac
  local -a parts
  IFS=/ read -ra parts <<<"$base/$target"
  for part in "${parts[@]}"; do
    case "$part" in
      "" | .) ;;
      ..)
        if [ "${#stack[@]}" -eq 0 ]; then return 0; fi
        unset 'stack[${#stack[@]}-1]'
        ;;
      *) stack+=("$part") ;;
    esac
  done
  (IFS=/; echo "${stack[*]-}")
}

findings=0
links=0
files=0
while IFS= read -r md; do
  [ -n "$md" ] || continue
  [ -f "$ROOT/$md" ] || continue
  files=$((files + 1))
  dir="$(dirname "$md")"
  [ "$dir" = "." ] && dir=""
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    line="${hit%%:*}"
    target="${hit#*:}"
    if grep -qE "$NOT_RELATIVE" <<<"$target"; then continue; fi
    links=$((links + 1))
    path="${target%%#*}"
    path="${path%%\?*}"
    if [ -z "$path" ]; then continue; fi
    resolved="$(normalize "$dir" "$path")"
    if [ -z "$resolved" ] || ! grep -qxF -- "$resolved" "$TRACKED"; then
      echo "❌ FAIL: ${md}:${line} links ${target}, which is not a tracked file or directory"
      findings=$((findings + 1))
    fi
  done < <(awk -f "$LINK_READER" "$ROOT/$md")
done < <(git -C "$ROOT" ls-files '*.md')

if [ "$files" -eq 0 ]; then
  echo "❌ FAIL: no tracked Markdown file in ${ROOT} — a scan over nothing is not a clean scan"
  COMPLETED=1
  exit 1
fi
if [ "$links" -eq 0 ]; then
  echo "❌ FAIL: no relative link in ${files} Markdown file(s) of ${ROOT} — a scan over nothing is not a clean scan"
  COMPLETED=1
  exit 1
fi

if [ "$findings" -ne 0 ]; then
  echo ""
  echo "markdown links: ${findings} finding(s) in ${links} relative link(s) of ${files} file(s). Fix the link, or move the file back."
  COMPLETED=1
  exit 1
fi

COMPLETED=1
echo "OK: markdown links: ${links} relative link(s) in ${files} tracked Markdown file(s) all resolve to a tracked file or directory"
exit 0
