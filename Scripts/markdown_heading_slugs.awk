# canon: markdown_heading_slugs_awk v1
# Scripts/markdown_heading_slugs.awk
#
# The markdown-links gate's reader of a link's #anchor: prints
# the GitHub anchor of every heading of a Markdown file, one per line, in
# file order. Run it with LC_ALL=C, so a byte is a character.
# The rules, as GitHub renders them:
#   - an ATX heading only: 1 to 6 "#", a space, the text, an optional closing
#     run of "#". NOT supported: a setext heading (text over === or ---) and
#     an id="..." or <a name="..."> in HTML; a link to either is reported.
#   - not a heading: a line in a fenced block (``` or ~~~) or an HTML comment.
#   - the text: a link [t](u) counts as t, a backtick is dropped, upper case
#     becomes lower case, a space becomes a hyphen, and everything else but
#     a letter, digit, hyphen or underscore is dropped. A byte above ASCII is
#     dropped too: an em dash or an emoji drops as GitHub drops it, but an
#     accented letter would be dropped where GitHub keeps it (the gate skips
#     a link whose anchor has such a byte).
#   - the same heading again gets -1, then -2, ... after its anchor.
# Usage: LC_ALL=C awk -f Scripts/markdown_heading_slugs.awk docs/a.md
# Bash 3.2 / BSD awk safe: index, substr, match, gsub, tolower and length only.
{
  line = $0
  if (incomment) {
    if (index(line, "-->")) incomment = 0
    next
  }
  if (line ~ /^ *(```|~~~)/) {
    if (!infence) { infence = 1; fence = substr(line, match(line, /[`~]/), 1) }
    else if (index(line, fence fence fence)) infence = 0
    next
  }
  if (infence) next
  if (index(line, "<!--") && !index(line, "-->")) { incomment = 1; next }
  if (line !~ /^ ? ? ?#(#?#?#?#?#?)([ \t]|$)/) next
  sub(/^ ? ? ?#+[ \t]*/, "", line)
  sub(/[ \t]+#+[ \t]*$/, "", line)
  while ((i = match(line, /\[[^]]*\]\([^)]*\)/)) > 0) {
    seg = substr(line, i, RLENGTH)
    txt = substr(seg, 2, index(seg, "]") - 2)
    line = substr(line, 1, i - 1) txt substr(line, i + RLENGTH)
  }
  line = tolower(line)
  gsub(/`/, "", line)
  gsub(/[ \t]/, "-", line)
  gsub(/[^a-z0-9_-]/, "", line)
  n = seen[line]++
  if (n > 0) line = line "-" n
  print line
}
