#!/usr/bin/env bash
# Scripts/test_check_code_of_conduct.sh
#
# Self-test for Scripts/check_code_of_conduct.sh (forsgren#43), run in pre
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
# Mutation proofs: the address, placeholder and README-link patterns each
# replaced by one that never matches (address and link: one that always
# does) turn their red case green, so each case is red BECAUSE of its pattern.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_code_of_conduct.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "code-of-conduct self-test"

GOOD_COC='# Code of Conduct

To report a violation, email conduct@hanoulle.be. See [the Covenant](https://www.contributor-covenant.org/version/3/0/).
'
GOOD_README='# forsgren

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
'

# new_root <name> [coc-text] [readme-text] — a root with the good files, or
# the given text; an empty-string argument "-" leaves that file out.
new_root() {
  ROOT="$TMP/$1"
  mkdir -p "$ROOT"
  if [[ "${2-$GOOD_COC}" != "-" ]]; then printf '%s' "${2-$GOOD_COC}" > "$ROOT/CODE_OF_CONDUCT.md"; fi
  if [[ "${3-$GOOD_README}" != "-" ]]; then printf '%s' "${3-$GOOD_README}" > "$ROOT/README.md"; fi
}

new_root good
capture "$GATE" "$ROOT"
want_green_ok "1. a good file and a README that links it are clean"

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
"
capture "$GATE" "$ROOT"
want_red "6a. rejects a README that does not link the file" "README.md does not link to CODE_OF_CONDUCT.md"
new_root noreadme "$GOOD_COC" -
capture "$GATE" "$ROOT"
want_red "6b. rejects a missing README" "README.md is missing"

new_root dotlink "$GOOD_COC" "[conduct](./CODE_OF_CONDUCT.md) and [again](CODE_OF_CONDUCT.md#reporting)
"
capture "$GATE" "$ROOT"
want_green_ok "7. a ./ link and an anchor link are links"

capture "$GATE" "$TMP/does-not-exist"
want_rc "8. exits 2 on a missing root dir, never 0" 2

capture "$GATE"
want_green_ok "9. this repository has a code of conduct naming the address, and the README links it"

# Mutation proofs. The mutant cds to its own dir's parent, so it gets the
# same layout.
mutate() {
  # mutate <var> <value> <fixture> <reason> <proof text>
  selftest_mutant_green "$GATE" "$TMP/mutant-$1/Scripts/check_code_of_conduct.sh" \
    "s/^$1=.*/$1='$2'/" "$TMP/$3" "$5" \
    "with $1 neutralised the fixture $3 is still red; expected green, it was red for: $4"
}
mutate ADDRESS '.' noaddr "does not name the reporting address" \
  "an address pattern that matches anything turns case 5a green, so it is red because of the address"
mutate PLACEHOLDER 'NEVER-MATCHES-ANY-PLACEHOLDER' ph1 "has a placeholder" \
  "a placeholder pattern that never matches turns case 3.1 green, so it is red because of the pattern"
mutate README_LINK '.' nolink "does not link to CODE_OF_CONDUCT.md" \
  "a link pattern that matches anything turns case 6a green, so it is red because of the pattern"

selftest_end "the code-of-conduct gate does not hold the code of conduct to its four rules" \
  "code-of-conduct gate is red on a missing file, a placeholder of every kind, a missing or other address, a README without the link and a missing README, with each reason named, exits 2 on a missing root, is green on a good file, on Markdown links and on ./ and anchor links, and its three patterns are what redden their cases"
