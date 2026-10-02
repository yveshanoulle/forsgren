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
#   <sha> <author account> <base64 of the author email> <base64 of the message>
# where <author account> is <type>:<login> of the GitHub account the commit
# is linked to (the commits API's .author), or - when it is linked to none;
# the pull request's opener, <type>:<login>, is the second argument. So
# every case here is offline. Every name and address is made up.
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
# The bot exemption (ruled by Yves 2026-10-02: Dependabot's commits carry no
# Signed-off-by). A commit is exempt only on what GitHub asserts and no
# contributor writes: its linked account is of type Bot AND is the account
# that opened the pull request. A commit's author email, name and message
# are the contributor's to write, and GitHub links a commit to an account by
# its author email, so the linked account alone is not enough:
#  14. an unsigned commit by the Bot account that
#      opened the pull request                     -> green, the commit named
#                                                     as exempt
#  15. a bot-looking email, linked to a User       -> red
#  16. a bot-looking email, linked to no account   -> red
#  17. linked to a Bot, in a pull request a User
#      opened                                      -> red
#  18. linked to a Bot, in a pull request another
#      Bot opened                                  -> red
#  19. linked to a Bot, no opener given            -> red
#  20. the opening bot's unsigned commit and an
#      unsigned human commit                       -> red, naming the human
#                                                     commit alone
#  21. an opener not in the <type>:<login> shape   -> red
#  22. an author account not in the shape          -> red, malformed
# Mutation proofs: case 4 against a copy of the check that reads every
# paragraph after the subject as trailers must turn green, so case 4 is red
# BECAUSE only the last paragraph counts; case 7 against a copy that skips
# the email comparison must turn green, so case 7 is red BECAUSE the emails
# differ; case 15 against a copy that exempts by the author email instead
# of by the account must turn green, so case 15 is red BECAUSE the account
# is a User; case 17 against a copy that does not compare the account with
# the opener must turn green, so case 17 is red BECAUSE a User opened the
# pull request.

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

# commit <sha> <author-email> <message> [account]: one input line; the
# account defaults to - (linked to no GitHub account).
commit() {
  printf '%s %s %s %s\n' "$1" "${4:--}" "$(b64 "$2")" "$(b64 "$3")"
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

# --- The bot exemption.
DEPENDABOT="Bot:dependabot[bot]"
BOT_EMAIL="49699333+dependabot[bot]@users.noreply.github.com"
BUMP=$'Bump example-lib from 1.0.0 to 1.0.1\n\nBumps example-lib from 1.0.0 to 1.0.1.'

commit 141414141414eeee "$BOT_EMAIL" "$BUMP" "$DEPENDABOT" > "$TMP/bot.txt"
capture "$CHECK" "$TMP/bot.txt" "$DEPENDABOT"
want_green "14. an unsigned commit by the Bot account that opened the pull request" "commit 141414141414 (Bump example-lib from 1.0.0 to 1.0.1) is exempt: authored by the bot account dependabot[bot], which opened this pull request"

commit 151515151515ffff "$BOT_EMAIL" "$BUMP" "User:mallory-example" > "$TMP/spoof-user.txt"
capture "$CHECK" "$TMP/spoof-user.txt" "$DEPENDABOT"
want_red "15. a bot-looking email linked to a User account" "commit 151515151515 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

commit 161616161616aaaa "$BOT_EMAIL" "$BUMP" > "$TMP/spoof-none.txt"
capture "$CHECK" "$TMP/spoof-none.txt" "$DEPENDABOT"
want_red "16. a bot-looking email linked to no account" "commit 161616161616 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

commit 171717171717bbbb "$BOT_EMAIL" "$BUMP" "$DEPENDABOT" > "$TMP/spoof-opener.txt"
capture "$CHECK" "$TMP/spoof-opener.txt" "User:mallory-example"
want_red "17. linked to a Bot account, in a pull request a User opened" "commit 171717171717 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

capture "$CHECK" "$TMP/spoof-opener.txt" "Bot:renovate[bot]"
want_red "18. linked to a Bot account, in a pull request another Bot opened" "commit 171717171717 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

capture "$CHECK" "$TMP/spoof-opener.txt"
want_red "19. linked to a Bot account, no opener given" "commit 171717171717 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

{
  commit 202020202020cccc "$BOT_EMAIL" "$BUMP" "$DEPENDABOT"
  commit 212121212121dddd bo@example.org "$UNSIGNED" "User:bo-example"
} > "$TMP/mixed.txt"
capture "$CHECK" "$TMP/mixed.txt" "$DEPENDABOT"
want_red "20. the opening bot's unsigned commit and an unsigned human commit" "commit 212121212121 (Tidy the template) has no Signed-off-by trailer"
if grep 'FAIL' <<< "$OUT" | grep -q '202020202020'; then
  fail "20. a FAIL line names the bot's exempt commit too. Output: ${OUT}"
else
  echo "  ok: 20. only the human commit is named as a failure"
fi

capture "$CHECK" "$TMP/bot.txt" "dependabot[bot]"
want_red "21. an opener not in the <type>:<login> shape" "the pull request opener is not <type>:<login>"

printf '%s %s %s %s\n' 222222222222eeee 'Bot:dependabot[bot]x' "$(b64 "$BOT_EMAIL")" "$(b64 "$BUMP")" > "$TMP/badaccount.txt"
capture "$CHECK" "$TMP/badaccount.txt" "$DEPENDABOT"
want_red "22. an author account not in the shape" "malformed line 1"

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

# Mutation proof for case 15: a copy of the check that exempts a commit by
# its bot-looking author email, as a check resting on what a contributor
# writes would, must be green on it. Both proofs rewrite the exemption
# line of Scripts/check_dco.sh by its exact text; [$] matches its dollar
# signs, and \2 (the one captured) writes the mutant's, so no expression
# here reads as a shell expansion.
MUTANT="$TMP/mutant-byemail/Scripts/check_dco.sh"
if selftest_mutant "$CHECK" "$MUTANT" 's/^\( *\)if \[ "\([$]\)account" = "Bot:[$]{opener_login}" \] && \[ "[$]opener" = "Bot:[$]{opener_login}" \]; then$/\1if [[ "\2email" == *"[bot]@users.noreply.github.com" ]]; then/'; then
  capture "$MUTANT" "$TMP/spoof-user.txt" "$DEPENDABOT"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: exempting by the author email, case 15 is green, so it is red because its account is a User, whatever its email says"
  else
    fail "mutation proof: a check that exempts by the author email is still red on case 15 (exit ${RC}) — case 15 is red for another reason. Output: ${OUT}"
  fi
fi

# Mutation proof for case 17: a copy of the check that takes any Bot
# account, whoever opened the pull request, must be green on it.
MUTANT="$TMP/mutant-opener/Scripts/check_dco.sh"
if selftest_mutant "$CHECK" "$MUTANT" 's/^\( *\)if \[ "\([$]\)account" = "Bot:[$]{opener_login}" \] && \[ "[$]opener" = "Bot:[$]{opener_login}" \]; then$/\1if [ "\2{account%%:*}" = "Bot" ]; then/'; then
  capture "$MUTANT" "$TMP/spoof-opener.txt" "User:mallory-example"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: without the opener comparison, case 17 is green, so it is red because a User opened the pull request"
  else
    fail "mutation proof: a check that takes any Bot account is still red on case 17 (exit ${RC}) — case 17 is red for another reason. Output: ${OUT}"
  fi
fi

selftest_end "the DCO check does not hold every commit to a Signed-off-by trailer from its author, or exempts a commit on anything but the Bot account that opened the pull request" \
  "DCO check is green on commits signed off by their authors (any case, among other trailers, CRLF), red naming the unsigned commit alone, on no commit, on a Signed-off-by in the body, mid-line or as the subject, on a sign-off by someone else (no email printed), on no author email and on a malformed line, exits 2 on a missing file, reads stdin, exempts only the unsigned commits of the Bot account that opened the pull request (never by a bot-looking email, for a User or no account, another opener or none), names the human commit alone in a mixed pull request, and its last-paragraph rule, email comparison, account rule and opener comparison are what redden cases 4, 7, 15 and 17"
