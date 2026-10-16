# canon: extract_markdown_links_awk v1
# Scripts/extract_markdown_links.awk
#
# The markdown-links gate's reader: prints "<line>:<target>"
# for every link in a Markdown file, outside code. Counted: an inline link
# [text](target) or [text](target "title") or [text](<target>), and a
# reference definition [label]: target. Not counted: what sits in a fenced
# block (``` or ~~~), an HTML comment (it may span lines) or an inline code
# span. Line numbers are those of the file (a stripped line stays a blank).
# The target is printed as written; the gate decides what is relative.
# Usage: awk -f Scripts/extract_markdown_links.awk README.md
# Bash 3.2 / BSD awk safe: index, substr, match, gsub and length only.
function first_token(s,    t) {
  sub(/^[ \t]+/, "", s)
  if (substr(s, 1, 1) == "<") {
    t = index(s, ">")
    if (t) return substr(s, 2, t - 2)
    return ""
  }
  t = match(s, /[ \t]/)
  if (t) return substr(s, 1, t - 1)
  return s
}
{
  line = $0
  if (!incomment && line ~ /^ *(```|~~~)/) {
    if (!infence) { infence = 1; fence = substr(line, match(line, /[`~]/), 1) }
    else if (index(line, fence fence fence)) infence = 0
    next
  }
  if (infence) next
  out = ""
  while (length(line) > 0) {
    if (incomment) {
      i = index(line, "-->")
      if (!i) { line = ""; break }
      line = substr(line, i + 3)
      incomment = 0
      continue
    }
    i = index(line, "<!--")
    if (!i) { out = out line; break }
    out = out substr(line, 1, i - 1)
    line = substr(line, i + 4)
    incomment = 1
  }
  gsub(/`[^`]*`/, "", out)
  if (out ~ /^ ? ? ?\[[^]]+\]:[ \t]*[^ \t]/) {
    s = out
    sub(/^ ? ? ?\[[^]]+\]:/, "", s)
    t = first_token(s)
    if (t != "") print NR ":" t
    next
  }
  while ((i = match(out, /\]\(/)) > 0) {
    out = substr(out, i + 2)
    j = index(out, ")")
    if (!j) break
    t = first_token(substr(out, 1, j - 1))
    if (t != "") print NR ":" t
    out = substr(out, j + 1)
  }
}
