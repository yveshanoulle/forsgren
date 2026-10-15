#!/usr/bin/env bash
# Scripts/test_check_markdown_links.sh
#
# Self-test for Scripts/check_markdown_links.sh (forsgren#147), run in pre
# before the gate it validates. forsgren's own. Each fixture is a git work
# tree (the gate reads git ls-files); each case asserts the exit code AND the
# reason, so a red for another cause proves nothing.
#   1. good links: file, ./file, dir, ../ from a subfolder, #anchor on a
#      file, reference definition, <angle> target, title        -> green
#   2. a broken inline link                                      -> red, file:line
#   3. a broken link from a subfolder (../ and plain)            -> red
#   4. a reference definition to nothing                         -> red
#   5. a file that exists but is not tracked                     -> red
#   6. a wrong-case spelling                                     -> red
#   7. ../ out of the repository                                 -> red
#   8. a broken link inside a fence, a comment, a code span      -> green
#   9. http(s), mailto and a pure #anchor to nothing             -> green
#  10. every finding in one run                                  -> two lines
#  11. no Markdown file, or no relative link                     -> red (zero)
#  12. a missing root, a root that is no git work tree           -> exit 2
# Mutation proofs: the link reader replaced by one that strips nothing turns
# the fence, comment and code-span fixture red; the not-relative pattern
# replaced by one that never matches turns the http fixture red.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

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

[up](../README.md) [sibling](b.md) [self](#top) [root](/README.md)'
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
put "$ROOT" README.md '# T [ok](README.md) [new](new.md)'
track "$ROOT"
put "$ROOT" new.md '# new, never added'
capture "$GATE" "$ROOT"
want_red "5. rejects a file that exists but is not tracked" "README.md:1 links new.md"

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

[web](https://example.org/x.md) [plain](http://example.org/y.md) [mail](mailto:a@b.c) [anchor](#nowhere) [proto](//example.org/z.md) [ref]'
put "$ROOT" docs/a.md '# A [ok](../README.md)'
track "$ROOT"
capture "$GATE" "$ROOT"
want_green_ok "9. http(s), mailto, //host and a pure #anchor are not checked"

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
want_red "11a. a root with no tracked Markdown file is red" "no tracked Markdown file"

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

# Mutation proofs. The mutant sits in its own Scripts/, and gets the real
# reader beside it unless the mutation replaces the reader.
mutate() {
  # mutate <name> <sed-expression> <fixture-root> <case> <expected>
  mkdir -p "$TMP/mutant-$1/Scripts"
  cp Scripts/extract_markdown_links.awk "$TMP/mutant-$1/Scripts/"
  selftest_mutant "$GATE" "$TMP/mutant-$1/Scripts/check_markdown_links.sh" "$2" || return 0
  capture "$TMP/mutant-$1/Scripts/check_markdown_links.sh" "$3"
  want_red "mutation proof: $4" "$5"
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

selftest_end "the markdown-links gate does not hold the relative links of the Markdown files" \
  "markdown-links gate is red on a broken inline link, reference definition, untracked file, wrong case and a ../ out of the repository, with file:line named, reports every finding in one run, is red on a scan over nothing, exits 2 on a missing root or no git work tree, is green on good links and ignores fences, comments, code spans, external links and pure anchors, and its reader and not-relative pattern are what decide its cases"
