#!/usr/bin/env bash
# canon: check_markdown_links v1
# Scripts/check_markdown_links.sh
#
# The markdown-links gate, byte-identical across the estate's
# repositories. Red when
# a relative link in a listed Markdown file points at nothing listed (listed:
# tracked, or untracked and not ignored, Scripts/lib_repo_files.sh):
# every listed *.md, SHIPPED.md included (its history links must still resolve:
# a file moved is a link moved).
#
# A relative link is an inline [text](path) or [text](path#anchor), or a
# reference definition [label]: path, outside a fenced block, an HTML comment
# and an inline code span (Scripts/extract_markdown_links.awk). Not checked:
# a link with a scheme (https:, mailto:, ...), a protocol-relative //host
# link. The path is resolved against the directory of the
# file that holds the link (a leading / against the repository root), with
# ./ and ../ folded, and must name a LISTED file or a directory that holds a
# listed file, spelled with the right case. A ../ that leaves
# the repository is red. A ?query is cut before resolving.
#
# Anchors: a link to a Markdown file with a #anchor, and a pure #anchor (the
# file itself), must name a heading of that file by GitHub's rules
# (Scripts/markdown_heading_slugs.awk): ATX "#" headings only, outside
# fences and comments, lower case, spaces to hyphens, punctuation dropped,
# a repeated heading numbered -1, -2. NOT supported, so a link to one is
# red: a setext heading (text over === or ---) and an HTML id or name. Not
# checked: an anchor into a directory or a file that is not Markdown (a line
# anchor like #L10), an anchor with a non-ASCII byte (an accented letter, an
# emoji), an anchor that starts with user-content-.
#
# Why a gate: the other link checks walk the generated html and css, or only
# Scripts paths. A doc moved or renamed left its links dead, and nothing
# noticed. An absolute path such as /home/me/x.md resolves against the
# repository root, so a link into one person's checkout is red.
#
# The FAIL line names file:line and the link as written. Every link is
# checked, so one run reports every finding. Red-on-zero: a root with no
# listed Markdown file, or no relative link at all, is red.
#
# Usage: Scripts/check_markdown_links.sh [root-dir]   (default: the repo root)
# Exit: 0 clean, 1 a finding or a scan over nothing, 2 root missing or not a
# git work tree.
# Fixture: Scripts/test_check_markdown_links.sh. The three settings below start
# at column 0: its mutation proofs replace each.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

ROOT="${1:-$REPO}"

# shellcheck source=Scripts/lib_repo_files.sh
source "$REPO/Scripts/lib_repo_files.sh"

# The link reader (Scripts/extract_markdown_links.awk).
LINK_READER="$REPO/Scripts/extract_markdown_links.awk"
# The heading reader (Scripts/markdown_heading_slugs.awk), run with LC_ALL=C.
HEADING_SLUGS="$REPO/Scripts/markdown_heading_slugs.awk"
# A target that is not a relative path: a scheme or //host.
NOT_RELATIVE='^([A-Za-z][A-Za-z0-9+.-]*:|//)'

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

# The listed files, and every directory that holds one, one per line.
LISTED="$TMPDIR_GATE/listed"
repo_files "$ROOT" | awk '
  { print }
  { p = $0; while ((i = match(p, /\/[^\/]*$/)) > 0) { p = substr(p, 1, i - 1); print p } }
' | sort -u > "$LISTED"

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

# check_anchor <listed path> <anchor>: succeeds when there is nothing to
# check (no anchor, not a Markdown file on disk, an anchor the reader cannot
# judge) or the file has a heading with that anchor.
check_anchor() {
  [ -n "$2" ] || return 0
  case "$1" in *.md) ;; *) return 0 ;; esac
  [ -f "$ROOT/$1" ] || return 0
  case "$2" in user-content-* | *%*) return 0 ;; esac
  if LC_ALL=C grep -q '[^ -~]' <<<"$2"; then return 0; fi
  local slugs
  slugs="$(LC_ALL=C awk -f "$HEADING_SLUGS" "$ROOT/$1")"
  grep -qxF -- "$2" <<<"$slugs"
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
    anchor=""
    case "$target" in *"#"*) anchor="${target#*#}" ;; esac
    if [ -z "$path" ]; then
      resolved="$md"
    else
      resolved="$(normalize "$dir" "$path")"
      if [ -z "$resolved" ] || ! grep -qxF -- "$resolved" "$LISTED"; then
        echo "❌ FAIL: ${md}:${line} links ${target}, which is not a tracked file or directory"
        findings=$((findings + 1))
        continue
      fi
    fi
    if check_anchor "$resolved" "$anchor"; then continue; fi
    echo "❌ FAIL: ${md}:${line} links ${target}, but ${resolved} has no heading with the anchor #${anchor} (ATX headings only: a setext heading or an HTML id is not seen)"
    findings=$((findings + 1))
  done < <(awk -f "$LINK_READER" "$ROOT/$md")
done < <(repo_files "$ROOT" '*.md')

if [ "$files" -eq 0 ]; then
  echo "❌ FAIL: no Markdown file in ${ROOT} — a scan over nothing is not a clean scan"
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
echo "OK: markdown links: ${links} relative link(s) in ${files} tracked Markdown file(s) all resolve to a tracked file or directory, and every #anchor to a heading"
exit 0
