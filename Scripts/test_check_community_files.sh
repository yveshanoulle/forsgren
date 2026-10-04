#!/usr/bin/env bash
# Scripts/test_check_community_files.sh
#
# Self-test for Scripts/check_community_files.sh (forsgren#43, #44), run in pre
# before the gate it validates. forsgren's own. Each case asserts the exit
# code AND the reason, so a red for another cause proves nothing.
#   1. a good file and a README that links it        -> green
#   2. no CODE_OF_CONDUCT.md                         -> red, "is missing"
#   3. a placeholder: [Please provide, [INSERT, [insert, any other [...]
#      that is not a link, and a bracket left open   -> red, "placeholder"
#   4. Markdown links                                -> green (not placeholders)
#   5. no reporting address, or another address      -> red, "reporting address"
#   6. README without the link, README missing       -> red, "README.md"
#   7. a link to the file with ./ or an anchor       -> green
#   8. a missing root dir                            -> exit 2, never 0
#   9. this repository                               -> green
#  10. SECURITY.md: missing, without the private route, with a placeholder,
#      or not linked from the README                 -> red, each reason named
# Mutation proofs: the address, security route and link patterns replaced by
# one that always matches, the placeholder pattern by one that never matches,
# and the README strip by one that strips nothing, turn their red case green,
# so each case is red BECAUSE of its pattern.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_community_files.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "community-files self-test"

GOOD_COC='# Code of Conduct

To report a violation, email conduct@hanoulle.be. See [the Covenant](https://www.contributor-covenant.org/version/3/0/).
'
GOOD_SECURITY='# Security policy

Report it through "Report a vulnerability" on the Security tab.
'
GOOD_README='# forsgren

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) and [SECURITY.md](SECURITY.md).
'

# write_unless_dash <text> <path>: write the text, or nothing for "-".
write_unless_dash() {
  if [[ "$1" != "-" ]]; then printf '%s' "$1" > "$2"; fi
}

# new_root <name> [coc-text] [readme-text] [security-text] — a root with the
# good files, or the given text; an argument "-" leaves that file out.
new_root() {
  ROOT="$TMP/$1"
  mkdir -p "$ROOT"
  write_unless_dash "${2-$GOOD_COC}" "$ROOT/CODE_OF_CONDUCT.md"
  write_unless_dash "${3-$GOOD_README}" "$ROOT/README.md"
  write_unless_dash "${4-$GOOD_SECURITY}" "$ROOT/SECURITY.md"
}

new_root good
capture "$GATE" "$ROOT"
want_green_ok "1. good files and a README that links them are clean"

new_root nofile - "$GOOD_README"
capture "$GATE" "$ROOT"
want_red "2. rejects a missing CODE_OF_CONDUCT.md" "CODE_OF_CONDUCT.md is missing"

placeholders=(
  "[Please provide a way to report]"
  "[INSERT CONTACT METHOD]"
  "[insert contact method]"
  "[some other instruction]"
  "[Please provide an address"
)
for i in "${!placeholders[@]}"; do
  new_root "ph$i" "$GOOD_COC
Report to ${placeholders[$i]} here.
"
  capture "$GATE" "$ROOT"
  want_red "3.$i. rejects the placeholder ${placeholders[$i]}" "CODE_OF_CONDUCT.md:5 has a placeholder"
done

new_root links "$GOOD_COC
Read [one](a.md), [two](https://example.org/x) and [three](#anchor).
"
capture "$GATE" "$ROOT"
want_green_ok "4. Markdown links are not placeholders"

new_root noaddr "# Code of Conduct

Be kind.
"
capture "$GATE" "$ROOT"
want_red "5a. rejects a file that names no reporting address" "does not name the reporting address"
new_root otheraddr "# Code of Conduct

Report to conduct@example.org.
"
capture "$GATE" "$ROOT"
want_red "5b. rejects another address" "does not name the reporting address"

new_root nolink "$GOOD_COC" "# forsgren

Nothing about conduct here, only CODE_OF_CONDUCT.md as plain text.

[security](SECURITY.md)
"
capture "$GATE" "$ROOT"
want_red "6a. rejects a README that does not link the file" "README.md does not link to CODE_OF_CONDUCT.md"
new_root noreadme "$GOOD_COC" -
capture "$GATE" "$ROOT"
want_red "6b. rejects a missing README" "README.md is missing"

new_root dotlink "$GOOD_COC" "[conduct](./CODE_OF_CONDUCT.md) and [again](CODE_OF_CONDUCT.md#reporting), [sec](./SECURITY.md) and [again](SECURITY.md#reporting)
"
capture "$GATE" "$ROOT"
want_green_ok "7. a ./ link and an anchor link are links, for both files"

new_root fencelink "$GOOD_COC" '# forsgren

```
[conduct](CODE_OF_CONDUCT.md)
```

[security](SECURITY.md)
'
capture "$GATE" "$ROOT"
want_red "7b. rejects a README whose only link to the file is inside a fenced code block" "README.md does not link to CODE_OF_CONDUCT.md"

new_root spanlink "$GOOD_COC" "# forsgren

Write \`[conduct](CODE_OF_CONDUCT.md)\` to link it.

[security](SECURITY.md)
"
capture "$GATE" "$ROOT"
want_red "7c. rejects a README whose only link to the file is in an inline code span" "README.md does not link to CODE_OF_CONDUCT.md"

new_root commentlink "$GOOD_COC" '# forsgren

<!--
[conduct](CODE_OF_CONDUCT.md)
-->

[security](SECURITY.md)
'
capture "$GATE" "$ROOT"
want_red "7d. rejects a README whose only link to the file is in an HTML comment" "README.md does not link to CODE_OF_CONDUCT.md"

new_root strippedok "$GOOD_COC" "# forsgren

\`\`\`
code
\`\`\`
<!-- a note --> and \`code\`, then [conduct](CODE_OF_CONDUCT.md) and [sec](SECURITY.md).
"
capture "$GATE" "$ROOT"
want_green_ok "7e. a plain link after a fence, a comment and a code span still counts"

capture "$GATE" "$TMP/does-not-exist"
want_rc "8. exits 2 on a missing root dir, never 0" 2

capture "$GATE"
want_green_ok "9. this repository has a code of conduct naming the address, and the README links it"

# SECURITY.md (forsgren#44): the same four rules.
new_root nosecurity "$GOOD_COC" "$GOOD_README" -
capture "$GATE" "$ROOT"
want_red "10a. rejects a root with no SECURITY.md" "SECURITY.md is missing"

new_root noroute "$GOOD_COC" "$GOOD_README" "# Security policy

Be careful.
"
capture "$GATE" "$ROOT"
want_red "10b. rejects a SECURITY.md that names no private reporting route" "SECURITY.md does not name the private reporting route"

new_root secph "$GOOD_COC" "$GOOD_README" "$GOOD_SECURITY
Or write to [INSERT CONTACT METHOD] here.
"
capture "$GATE" "$ROOT"
want_red "10c. rejects a placeholder in SECURITY.md" "SECURITY.md:5 has a placeholder"

new_root seclink "$GOOD_COC" "# forsgren

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md); SECURITY.md as plain text.
"
capture "$GATE" "$ROOT"
want_red "10d. rejects a README that does not link SECURITY.md" "README.md does not link to SECURITY.md"

new_root routecode "$GOOD_COC" "$GOOD_README" "# Security policy

\`\`\`
Report a vulnerability
\`\`\`

<!-- security/advisories/new -->

Write \`Report a vulnerability\` to see it.
"
capture "$GATE" "$ROOT"
want_red "10e. rejects a SECURITY.md whose only route is inside a code block, a comment or a code span" "SECURITY.md does not name the private reporting route"

# Mutation proofs. The mutant cds to its own dir's parent, so it gets the
# same layout.
mutate() {
  # mutate <var> <value> <fixture> <reason> <proof text>; the mutant gets the
  # real awk program beside it, as the gate finds it at Scripts/.
  mkdir -p "$TMP/mutant-$1/Scripts"
  cp Scripts/strip_markdown_code.awk "$TMP/mutant-$1/Scripts/"
  selftest_mutant_green "$GATE" "$TMP/mutant-$1/Scripts/check_community_files.sh" \
    "s|^$1=.*|$1='$2'|" "$TMP/$3" "$5" \
    "with $1 neutralised the fixture $3 is still red; expected green, it was red for: $4"
}
mutate ADDRESS '.' noaddr "does not name the reporting address" \
  "an address pattern that matches anything turns case 5a green, so it is red because of the address"
mutate PLACEHOLDER 'NEVER-MATCHES-ANY-PLACEHOLDER' ph1 "has a placeholder" \
  "a placeholder pattern that never matches turns case 3.1 green, so it is red because of the pattern"
mutate PLACEHOLDER 'NEVER-MATCHES-ANY-PLACEHOLDER' secph "has a placeholder in SECURITY.md" \
  "a placeholder pattern that never matches turns case 10c green, so SECURITY.md is held to it too"
mutate SECURITY_ROUTE '.' noroute "does not name the private reporting route" \
  "a route pattern that matches anything turns case 10b green, so it is red because of the route"
mutate SECURITY_LINK '.' seclink "does not link to SECURITY.md" \
  "a link pattern that matches anything turns case 10d green, so it is red because of the pattern"
mutate README_LINK '.' nolink "does not link to CODE_OF_CONDUCT.md" \
  "a link pattern that matches anything turns case 6a green, so it is red because of the pattern"
printf '{ print }\n' > "$TMP/strip-nothing.awk"
mutate SECURITY_STRIP "$TMP/strip-nothing.awk" routecode "does not name the private reporting route" \
  "a SECURITY_STRIP that strips nothing turns the routecode case green, so it is red because of the strip"
for fx in fencelink spanlink commentlink; do
  mutate README_STRIP "$TMP/strip-nothing.awk" "$fx" "does not link to CODE_OF_CONDUCT.md" \
    "a README_STRIP that strips nothing turns the $fx case green, so it is red because of the strip"
done

selftest_end "the community-files gate does not hold the code of conduct and the security policy to their rules" \
  "community-files gate is red on a missing file, a placeholder of every kind, a missing or other address, a SECURITY.md without the private route, a README without either link and a missing README, with each reason named, exits 2 on a missing root, is green on good files, on Markdown links and on ./ and anchor links, and its patterns are what redden their cases"
