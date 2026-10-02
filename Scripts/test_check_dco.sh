#!/usr/bin/env bash
# Scripts/test_check_dco.sh
#
# Self-test for Scripts/check_dco.sh, the DCO sign-off check
# .github/workflows/dco.yml runs on every pull request (road to public, step
# 4; the ruling on forsgren#1: EUPL-1.2 plus a DCO sign-off on every commit).
# forsgren's own: no repo of the estate has a DCO check. It runs in pre, in
# sfl and in Quality, although the check itself runs only on pull requests:
# a check nobody validated is worth nothing, and a pull request is the one
# place a broken one would wave a commit through.
#
# The check reads commits from a file (or stdin), one line per commit, in
# the shape the workflow writes from the pull request's commit list:
#   <sha> <base64 of the author email> <base64 of the message>
# so every case here is offline. Every name and address is made up.
#   1. one commit, signed off by its author        -> green
#   2. three commits, the middle one unsigned      -> red, naming that commit
#                                                     and only that one
#   3. no commit at all                            -> red: nothing checked is
#                                                     not signed off
#   4. Signed-off-by in the body, not the trailers -> red: no trailer
#   5. Signed-off-by mid-line in the last paragraph-> red: no trailer
#   6. a message that is only a Signed-off-by line -> red: the subject is
#                                                     never a trailer
#   7. sign-off by someone else than the author    -> red, the email not
#                                                     printed
#   8. the same email in another case              -> green
#   9. among other trailers, CRLF, blank lines at
#      the end                                     -> green
#  10. a commit with no author email               -> red
#  11. a line not in the commit shape              -> red, malformed
#  12. a missing input file                        -> exit 2, never 0
#  13. the commits on stdin                        -> green
# Mutation proofs: case 4 against a copy of the check that reads every
# paragraph after the subject as trailers must turn green, so case 4 is red
# BECAUSE only the last paragraph counts; case 7 against a copy that skips
# the email comparison must turn green, so case 7 is red BECAUSE the emails
# differ.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

CHECK="./Scripts/check_dco.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "DCO sign-off self-test"

[[ -x "$CHECK" ]] \
  || selftest_abort "DCO sign-off self-test: ${CHECK} is missing or not executable — nothing checks the sign-off on a pull request's commits"

b64() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

# commit <sha> <author-email> <message>: one input line.
commit() {
  printf '%s %s %s\n' "$1" "$(b64 "$2")" "$(b64 "$3")"
}

SIGNED_A=$'Add the chart\n\nThe chart reads the history file.\n\nSigned-off-by: Ada Example <ada@example.org>'
SIGNED_B=$'Fix the axis\n\nSigned-off-by: Bo Example <bo@example.org>'
UNSIGNED=$'Tidy the template\n\nNo sign-off here.'

commit aaaaaaaaaaaa1111 ada@example.org "$SIGNED_A" > "$TMP/one.txt"
capture "$CHECK" "$TMP/one.txt"
want_green "1. one commit signed off by its author" "every one signed off"

{
  commit aaaaaaaaaaaa1111 ada@example.org "$SIGNED_A"
  commit bbbbbbbbbbbb2222 bo@example.org "$UNSIGNED"
  commit cccccccccccc3333 bo@example.org "$SIGNED_B"
} > "$TMP/three.txt"
capture "$CHECK" "$TMP/three.txt"
want_red "2. one unsigned commit among three" "commit bbbbbbbbbbbb (Tidy the template) has no Signed-off-by trailer"
if grep -qE 'aaaaaaaaaaaa|cccccccccccc' <<< "$OUT"; then
  fail "2. the output names a signed commit too. Output: ${OUT}"
else
  echo "  ok: 2. only the unsigned commit is named"
fi

: > "$TMP/empty.txt"
capture "$CHECK" "$TMP/empty.txt"
want_red "3. no commit at all" "no commit to check"

commit dddddddddddd4444 ada@example.org $'Add the chart\n\nSigned-off-by: Ada Example <ada@example.org>\n\nMore text after it.' > "$TMP/body.txt"
capture "$CHECK" "$TMP/body.txt"
want_red "4. a Signed-off-by in the body, not in the trailers" "commit dddddddddddd (Add the chart) has no Signed-off-by trailer"

commit eeeeeeeeeeee5555 ada@example.org $'Add the chart\n\nAs agreed, Signed-off-by: Ada Example <ada@example.org>' > "$TMP/midline.txt"
capture "$CHECK" "$TMP/midline.txt"
want_red "5. a Signed-off-by mid-line" "commit eeeeeeeeeeee (Add the chart) has no Signed-off-by trailer"

commit ffffffffffff6666 ada@example.org $'Signed-off-by: Ada Example <ada@example.org>' > "$TMP/subject.txt"
capture "$CHECK" "$TMP/subject.txt"
want_red "6. a message that is only a Signed-off-by line" "commit ffffffffffff (Signed-off-by: Ada Example <ada@example.org>) has no Signed-off-by trailer"

commit 777777777777aaaa ada@example.org "$SIGNED_B" > "$TMP/other.txt"
capture "$CHECK" "$TMP/other.txt"
want_red "7. a sign-off by someone else than the author" "commit 777777777777 (Fix the axis) is signed off, but not by its author"
if grep -qE 'ada@example\.org|bo@example\.org' <<< "$OUT"; then
  fail "7. the output prints an email address. Output: ${OUT}"
else
  echo "  ok: 7. the output prints no email address"
fi

commit 888888888888bbbb Ada@Example.ORG "$SIGNED_A" > "$TMP/case.txt"
capture "$CHECK" "$TMP/case.txt"
want_green "8. the author's email in another case" "every one signed off"

commit 999999999999cccc ada@example.org $'Add the chart\r\n\r\nBody.\r\n\r\nCo-Authored-By: Bo Example <bo@example.org>\r\nSigned-off-by: Ada Example <ada@example.org>\r\n\r\n\r\n' > "$TMP/trailers.txt"
capture "$CHECK" "$TMP/trailers.txt"
want_green "9. among other trailers, CRLF, blank lines at the end" "every one signed off"

commit 101010101010dddd "" "$SIGNED_A" > "$TMP/noauthor.txt"
capture "$CHECK" "$TMP/noauthor.txt"
want_red "10. a commit with no author email" "commit 101010101010 (Add the chart) has no author email"

printf 'not a commit line\n' > "$TMP/malformed.txt"
capture "$CHECK" "$TMP/malformed.txt"
want_red "11. a line not in the commit shape" "malformed line 1"

capture "$CHECK" "$TMP/does-not-exist.txt"
want_rc "12. exits 2 on a missing input file, never 0" 2

capture bash -c "\"$CHECK\" < \"$TMP/one.txt\""
want_green "13. the commits on stdin" "every one signed off"

# Mutation proof for case 4: a copy of the check whose trailer block starts
# right after the subject, not at the last paragraph, must be green on it.
# The mutant cds to its own dir's parent; give it the same layout.
MUTANT="$TMP/mutant-paragraph/Scripts/check_dco.sh"
if selftest_mutant "$CHECK" "$MUTANT" 's/^\( *\)while (start > 1 .*$/\1start = first + 1/'; then
  capture "$MUTANT" "$TMP/body.txt"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: reading every paragraph after the subject, case 4 is green, so it is red because only the last paragraph holds trailers"
  else
    fail "mutation proof: a check that reads every paragraph after the subject is still red on case 4 (exit ${RC}) — case 4 is red for another reason. Output: ${OUT}"
  fi
fi

# Mutation proof for case 7: a copy of the check that takes any sign-off,
# whoever's, must be green on it.
MUTANT="$TMP/mutant-email/Scripts/check_dco.sh"
if selftest_mutant "$CHECK" "$MUTANT" 's/if (tolower(email) == tolower(author)) matched = 1/matched = 1/'; then
  capture "$MUTANT" "$TMP/other.txt"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: without the email comparison, case 7 is green, so it is red because the emails differ"
  else
    fail "mutation proof: a check with no email comparison is still red on case 7 (exit ${RC}) — case 7 is red for another reason. Output: ${OUT}"
  fi
fi

selftest_end "the DCO check does not hold every commit to a Signed-off-by trailer from its author" \
  "DCO check is green on commits signed off by their authors (any case, among other trailers, CRLF), red naming the unsigned commit alone, on no commit, on a Signed-off-by in the body, mid-line or as the subject, on a sign-off by someone else (no email printed), on no author email and on a malformed line, exits 2 on a missing file, reads stdin, and its last-paragraph rule and email comparison are what redden cases 4 and 7"
