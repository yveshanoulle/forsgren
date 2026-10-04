# Scripts/strip_markdown_code.awk
#
# The community-files gate's (forsgren#43) view of a README: the Markdown with
# what is not prose removed, so a link inside it does not count as a link.
# Removed: a fenced block (the ``` or ~~~ lines and what is between them), an
# HTML comment (it may span lines) and an inline code span.
# Usage: awk -f Scripts/strip_markdown_code.awk README.md
# Bash 3.2 / BSD awk safe: index, substr, gsub and length only.
{
  line = $0
  if (!infence && !incomment && line ~ /^ *(```|~~~)/) { infence = 1; next }
  if (infence) {
    if (line ~ /^ *(```|~~~)/) infence = 0
    next
  }
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
  print out
}
