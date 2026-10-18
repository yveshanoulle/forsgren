#!/usr/bin/env bash
# canon: test_check_markdown_links v1
# Scripts/test_check_markdown_links.sh
#
# Self-test for Scripts/check_markdown_links.sh, run in pre
# before the gate it validates. Each fixture is a git work
# tree (the gate reads git ls-files); each case asserts the exit code AND the
# reason, so a red for another cause proves nothing.
#   1. good links: file, ./file, dir, ../ from a subfolder, #anchor on a
#      file, reference definition, <angle> target, title        -> green
#   2. a broken inline link                                      -> red, file:line
#   3. a broken link from a subfolder (../ and plain)            -> red
#   4. a reference definition to nothing                         -> red
#   5. a link to an ignored file                                 -> red; to a
#      new, untracked, not-ignored file -> resolves; a new untracked
#      Markdown file with a broken link           -> red, named
#   6. a wrong-case spelling                                     -> red
#   7. ../ out of the repository                                 -> red
#   8. a broken link inside a fence, a comment, a code span      -> green
#   9. http(s), mailto and //host to nothing                     -> green
#  10. every finding in one run                                  -> two lines
#  11. no Markdown file, or no relative link                     -> red (zero)
#  12. a missing root, a root that is no git work tree           -> exit 2
#  13. this repository                                           -> green
#  14. good anchors: plain, repeated -1, code span, dash, underscore, linked
#      text, closing #s, a directory, a line anchor, a % escape, a pure
#      #anchor; a heading only in a fence                        -> one red, named
#  16. an absolute path (a link into one checkout)             -> red
#  15. a broken anchor, a broken pure #anchor, a setext heading, a heading in
#      a comment                                                 -> red, file:line + anchor
# Mutation proofs: the link reader replaced by one that strips nothing turns
# the fence, comment and code-span fixture red; the not-relative pattern
# replaced by one that never matches turns the http fixture red; a heading
# reader that numbers no repeat turns the -1 anchor red.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

GATE="./Scripts/check_markdown_links.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "markdown-links self-test"

# put <root> <path> <text>: a file in the fixture root.
put() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
}

# track <root>: a git work tree with everything tracked.
track() {
  git -C "$1" init -q
  git -C "$1" add -A
}

GOOD_README='# Title

[a](docs/a.md) [b](./docs/a.md) [dir](docs) [anchor](docs/a.md#top) <https://example.org>
[ref]: docs/a.md
[angle](<docs/a.md> "a title") and [titled](docs/a.md "a title").'

ROOT="$TMP/good"
put "$ROOT" README.md "$GOOD_README"
put "$ROOT" docs/a.md '# A

[up](../README.md) [sibling](b.md) [self](#top) [root](/README.md)

## Top'
put "$ROOT" docs/b.md '# B'
track "$ROOT"
capture "$GATE" "$ROOT"
want_green_ok "1. file, ./file, dir, ../, anchor, reference, angle and titled links all resolve"

ROOT="$TMP/broken"
put "$ROOT" README.md '# T

fine, then [gone](docs/gone.md) here.'
track "$ROOT"
capture "$GATE" "$ROOT"
want_red "2. rejects a broken inline link, naming file:line" "README.md:3 links docs/gone.md"

ROOT="$TMP/sub"
put "$ROOT" README.md '# T [ok](docs/a.md)'
put "$ROOT" docs/a.md '[x](../missing.md)

[y](nope.md#h)'
track "$ROOT"
capture "$GATE" "$ROOT"
want_red "3a. rejects a broken ../ link from a subfolder" "docs/a.md:1 links ../missing.md"
want_said "3b. and a broken plain link with an anchor, its anchor cut" "docs/a.md:3 links nope.md#h"

ROOT="$TMP/refdef"
put "$ROOT" README.md '# T [ok](README.md)

[label]: elsewhere.md'
track "$ROOT"
capture "$GATE" "$ROOT"
want_red "4. rejects a reference definition to nothing" "README.md:3 links elsewhere.md"

ROOT="$TMP/untracked"
put "$ROOT" README.md '# T [ok](README.md) [new](new.md) [ign](scratch/ign.md)'
put "$ROOT" .gitignore 'scratch/'
track "$ROOT"
put "$ROOT" new.md '# new, never added'
put "$ROOT" scratch/ign.md '# ignored'
capture "$GATE" "$ROOT"
want_red "5a. rejects a link to a file that git ignores, which will never be committed" "README.md:1 links scratch/ign.md"
if grep -qF -- "links new.md" <<< "$OUT"; then
  fail "5b. a link to a new file, untracked and not ignored, was refused: it is in the commit that adds the link. Output: ${OUT}"
else
  echo "  ok: 5b. a link to a new, untracked, not-ignored file resolves"
fi

ROOT="$TMP/untracked-md"
put "$ROOT" README.md '# T [ok](README.md)'
track "$ROOT"
put "$ROOT" docs/new.md '# new

[gone](gone.md)'
capture "$GATE" "$ROOT"
want_red "5c. reads a new Markdown file too, untracked and not ignored" "docs/new.md:3 links gone.md"

ROOT="$TMP/case"
put "$ROOT" README.md '# T [ok](README.md) [c](Docs/A.md)'
put "$ROOT" docs/a.md '# A'
track "$ROOT"
capture "$GATE" "$ROOT"
want_red "6. rejects a wrong-case spelling, whatever the filesystem forgives" "README.md:1 links Docs/A.md"

ROOT="$TMP/climb"
put "$ROOT" README.md '# T [ok](README.md) [out](../outside.md)'
track "$ROOT"
capture "$GATE" "$ROOT"
want_red "7. rejects a ../ that leaves the repository" "README.md:1 links ../outside.md"

ROOT="$TMP/notlinks"
mkdir -p "$ROOT"
cat > "$ROOT/README.md" <<'MD'
# T [ok](README.md)

```
[in fence](gone-fence.md)
```

~~~
[in tilde fence](gone-tilde.md)
~~~

<!--
[in comment](gone-comment.md)
-->

Write `[in span](gone-span.md)` to link, and <!-- [one line](gone-one.md) --> too.

[after](README.md)
MD
track "$ROOT"
capture "$GATE" "$ROOT"
want_green_ok "8. a broken link in a fence, a comment or a code span is not a link"

ROOT="$TMP/external"
put "$ROOT" README.md '# T [ok](README.md)

[web](https://example.org/x.md) [plain](http://example.org/y.md) [mail](mailto:a@b.c) [proto](//example.org/z.md) [ref]'
put "$ROOT" docs/a.md '# A [ok](../README.md)'
track "$ROOT"
capture "$GATE" "$ROOT"
want_green_ok "9. http(s), mailto and //host are not checked"

ROOT="$TMP/many"
put "$ROOT" README.md '# T [ok](README.md)

[one](gone1.md)
[two](gone2.md)'
track "$ROOT"
capture "$GATE" "$ROOT"
want_said "10a. reports the first of two findings" "README.md:3 links gone1.md"
want_said "10b. and the second, in the same run" "README.md:4 links gone2.md"

ROOT="$TMP/nomd"
mkdir -p "$ROOT"
printf 'x\n' > "$ROOT/file.txt"
track "$ROOT"
capture "$GATE" "$ROOT"
want_red "11a. a root with no Markdown file is red" "no Markdown file"

ROOT="$TMP/nolinks"
put "$ROOT" README.md '# T

No relative link here, only [web](https://example.org).'
track "$ROOT"
capture "$GATE" "$ROOT"
want_red "11b. a root with no relative link is red" "no relative link"

capture "$GATE" "$TMP/does-not-exist"
want_rc "12a. exits 2 on a missing root, never 0" 2
mkdir -p "$TMP/nogit"
capture "$GATE" "$TMP/nogit"
want_exit "12b. exits 2 on a root that is no git work tree" 2 "is not a git work tree"

capture "$GATE"
want_green_ok "13. this repository's Markdown links all resolve"

# Anchors.
ROOT="$TMP/anchors"
put "$ROOT" README.md '# Title

[a](docs/a.md#plain-heading) [b](docs/a.md#same-twice) [c](docs/a.md#same-twice-1)
[d](docs/a.md#with-code-and--dash-a_b) [e](docs/a.md#linked-text) [f](docs/a.md#closed)
[g](docs) [h](docs#nothing-here) [i](LICENSE#L10) [j](docs/a.md#caf%C3%A9) [k](#title)
[l](docs/a.md#in-fence-only-x)'
put "$ROOT" LICENSE 'text'
mkdir -p "$ROOT/docs"
cat > "$ROOT/docs/a.md" <<'MD'
# Plain Heading

## Same twice
## Same twice

### With `code` and — dash? A_b

## [Linked](x.md) text
## Closed ##

```
# In fence only x
```
MD
track "$ROOT"
capture "$GATE" "$ROOT"
want_red "14a. an anchor in a fence is not a heading" "README.md:6 links docs/a.md#in-fence-only-x, but docs/a.md has no heading with the anchor #in-fence-only-x"
want_said "14b. the broken anchor is named with the file that lacks it" "has no heading with the anchor #in-fence-only-x (ATX headings only"
if grep -q "README.md:[1-5] " <<<"$OUT"; then
  fail "14c. a plain, repeated (-1), code, dash, underscore, linked, closed, directory, line, non-ASCII and self anchor is wrongly red. Output: $OUT"
else
  echo "  ok: 14c. plain, repeated (-1), code, dash, underscore, linked, closed, directory, line, non-ASCII and self anchors are not findings"
fi

ROOT="$TMP/badanchor"
put "$ROOT" README.md '# Title

[x](docs/a.md#missing) and [self](#nope)'
put "$ROOT" docs/a.md '# A

[up](../README.md#title) [setext](#underlined)

Underlined
==========

<!--
# In comment
-->
[c](../README.md#in-comment)'
track "$ROOT"
capture "$GATE" "$ROOT"
want_said "15a. a broken anchor to another file, file:line and the anchor" "README.md:3 links docs/a.md#missing, but docs/a.md has no heading with the anchor #missing"
want_said "15b. a broken pure #anchor in the same file" "README.md:3 links #nope, but README.md has no heading with the anchor #nope"
want_said "15c. a setext heading is not seen, and the message says ATX only" "docs/a.md:3 links #underlined"
want_said "15d. a heading in an HTML comment is not a heading" "docs/a.md:11 links ../README.md#in-comment"
if grep -q "docs/a.md:3 links ../README.md#title" <<<"$OUT"; then
  fail "15e. a good anchor into the other file is wrongly red. Output: $OUT"
else
  echo "  ok: 15e. a good anchor beside broken ones is not a finding"
fi

# An absolute path resolves against the repository root, so a link into one
# person's checkout names nothing the repository lists.
ROOT="$TMP/absolute"
put "$ROOT" README.md '# T [ok](README.md)

[checkout](/home/someone/work/repo/NOTES.md) and [root](/NOTES.md)'
put "$ROOT" NOTES.md '# Notes'
track "$ROOT"
capture "$GATE" "$ROOT"
want_red "16a. rejects an absolute path into a checkout, naming file:line" "README.md:3 links /home/someone/work/repo/NOTES.md"
if grep -qF -- "links /NOTES.md" <<< "$OUT"; then
  fail "16b. a /path that resolves against the repository root was refused. Output: ${OUT}"
else
  echo "  ok: 16b. a leading / resolves against the repository root"
fi

# Mutation proofs. The mutant sits in its own Scripts/, and gets the real
# reader beside it unless the mutation replaces the reader.
mutate() {
  # mutate <name> <sed-expression> <fixture-root> <case> <expected>
  mkdir -p "$TMP/mutant-$1/Scripts"
  cp Scripts/extract_markdown_links.awk Scripts/markdown_heading_slugs.awk Scripts/lib_repo_files.sh "$TMP/mutant-$1/Scripts/"
  selftest_mutant "$GATE" "$TMP/mutant-$1/Scripts/check_markdown_links.sh" "$2" || return 0
  capture "$TMP/mutant-$1/Scripts/check_markdown_links.sh" "$3"
  want_red "mutation proof: $4" "$5"
}
# mutate_green <name> <sed-expression> <fixture-root> <case>: the mutant is
# green on a fixture the real gate is red on, so the gate is red BECAUSE of the
# line the mutation removes.
mutate_green() {
  mkdir -p "$TMP/mutant-$1/Scripts"
  cp Scripts/extract_markdown_links.awk Scripts/markdown_heading_slugs.awk Scripts/lib_repo_files.sh "$TMP/mutant-$1/Scripts/"
  selftest_mutant "$GATE" "$TMP/mutant-$1/Scripts/check_markdown_links.sh" "$2" || return 0
  capture "$TMP/mutant-$1/Scripts/check_markdown_links.sh" "$3"
  want_green_ok "mutation proof: $4"
}
# A reader that strips nothing: every ](x) counts, in a fence or not.
cat > "$TMP/naive.awk" <<'AWK'
{ s = $0; while ((i = match(s, /\]\(/)) > 0) { s = substr(s, i + 2); j = index(s, ")"); if (!j) break; print NR ":" substr(s, 1, j - 1); s = substr(s, j + 1) } }
AWK
mutate reader "s|^LINK_READER=.*|LINK_READER='$TMP/naive.awk'|" "$TMP/notlinks" \
  "a reader that strips nothing turns the fence, comment and code-span fixture red, so it is green because of the strip" \
  "links gone-fence.md"
mutate notrel "s|^NOT_RELATIVE=.*|NOT_RELATIVE='NEVER-MATCHES-ANY-TARGET'|" "$TMP/external" \
  "a not-relative pattern that never matches turns the http fixture red, so it is green because of the pattern" \
  "links https://example.org/x.md"

# A heading reader that numbers nothing: a repeated heading has one anchor.
cat > "$TMP/unnumbered.awk" <<'AWK'
/^#/ { sub(/^#+ */, ""); s = tolower($0); gsub(/[ \t]/, "-", s); gsub(/[^a-z0-9_-]/, "", s); print s }
AWK
mutate slugs "s|^HEADING_SLUGS=.*|HEADING_SLUGS='$TMP/unnumbered.awk'|" "$TMP/anchors" \
  "a heading reader that does not number repeats turns the -1 anchor red, so it is green because of the numbering" \
  "README.md:3 links docs/a.md#same-twice-1"

# A gate that treats a leading / as not relative skips absolute targets: the
# absolute-path fixture turns green.
mutate_green absolute "s,^NOT_RELATIVE=.*,NOT_RELATIVE='^([A-Za-z][A-Za-z0-9+.-]*:|//|/)'," "$TMP/absolute" \
  "a gate that skips absolute targets is green on the absolute-path fixture, so it is red because they are checked"

# A gate that swallows its findings: it never takes the red branch, prints OK
# and exits 0 on the broken fixture.
mutate_green swallow 's/^if \[ "[$]findings" -ne 0 \]; then/if false; then/' "$TMP/many" \
  "a gate that swallows its findings exits 0 on the broken fixture, so the exit status is what makes it red"

selftest_end "the markdown-links gate does not hold the relative links of the Markdown files" \
  "markdown-links gate is red on a broken inline link, reference definition, untracked file, wrong case and a ../ out of the repository, with file:line named, reports every finding in one run, is red on a scan over nothing, exits 2 on a missing root or no git work tree, checks every #anchor against the headings of its file (ATX, fences and comments skipped, repeats numbered), is green on good links and ignores fences, comments, code spans, external links and pure anchors, and its reader and not-relative pattern are what decide its cases"
