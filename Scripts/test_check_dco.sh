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
# The exemption (forsgren#725; before it, ruled 2026-10-02, any Bot account
# that opened the pull request). A commit is exempt only when its author is
# an identity of the list of exempt automation identities AND GitHub
# authenticated that same account, id and login, as the one that opened the
# pull request or pushed to main. A commit's author email, name and message
# are its maker's to write, and GitHub links a commit to an account by its
# author email, so neither is proof:
#  14. an unsigned commit by the listed Bot account
#      that opened the pull request                -> green, the commit named
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
#  21. an account not in the <type>:<login>[:<id>]
#      shape                                       -> red
#  22. an author account not in the shape          -> red, malformed
# The one signer pair (forsgren#676, option A): GitHub records a Dependabot
# squash merge as authored by Dependabot's noreply email, while Dependabot
# signs off with another address; that one pair counts as the same signer,
# on a push too (account -), and nothing else:
#  22a. the pair: that author, Dependabot's sign-off -> green
#  22b. the same sign-off, another bot's noreply
#       author                                       -> red, mismatch
#  22c. the same sign-off, a person's author         -> red, mismatch
#  22d. the same sign-off, the pair's author email
#       in another case                              -> red, mismatch
#  22e. that author, a person's sign-off             -> red, mismatch
#  22f. that author, the sign-off email with
#       another name                                 -> red, mismatch
#  22g. that author, the sign-off name with another
#       email                                        -> red, mismatch
#  22h. that author, the sign-off in another case    -> red, mismatch
#  22i. that author, the sign-off in the body        -> red, no trailer
#  22j. that author, no sign-off                     -> red, no trailer
# The push check, Scripts/dco_push_check.sh (forsgren#267, decision #268), with
# a stub gh (DCO_GH) answering from fixture files, offline:
#  28. a direct push commit, no sign-off              -> red as ever; signed -> green
#  29. a Dependabot commit of a merged pull request
#      whose DCO run succeeded                        -> not judged again, said
#  30. the merge commit GitHub made for it            -> exempt, said
#  31. both, the real push                            -> green
#  32. the DCO run failed, is missing or another
#      app's                                          -> judged strictly
#  33. the pull request is not merged                 -> judged strictly
#  34. the pull request is another repository's       -> judged strictly
#  35-37. a merge commit not committed by GitHub, not
#      verified, with another second parent or
#      committer email                                -> judged strictly
#  38. not one of the pull request's commits          -> judged strictly
#  39. a failed API call (any of the four)            -> red with its reason
#  39e-g. a call that fails once and then answers -> green, one warning
#      naming the first failure; fails twice -> red naming both reasons; a
#      call that answers is asked once (forsgren#287)
#  40. a mixed push                                   -> the direct commit alone named
#  41. no commit, a malformed line, a wrong call      -> red
# Registered automation identities (forsgren#725), a made-up agent with the
# id 4242 in a made-up list:
#  42. the agent pushed its own unsigned commit       -> green, exempt, said
#  43. IMPERSONATION: a person pushed a commit that
#      names the agent as its author, unsigned        -> red
#  43b. the same, pushed by another listed identity   -> red
#  43c. the same, signed off under the agent's email  -> red
#  43d. the same in a pull request the person opened,
#       GitHub linking the commit to the agent        -> red
#  44. an identity that is not in the list pushed its
#      own commit, unsigned or signed off             -> red
#  44c. the agent's login under another account id    -> red
#  45. the agent's own commit WITH a sign-off         -> red
#  45b. Dependabot's commit with the sign-off line
#       GitHub's service writes, in its pull request  -> green, exempt
#  45c. Dependabot's commit with any other sign-off   -> red
#  46. the agent pushed a person's commit: unsigned   -> red, that commit
#      alone; signed off -> green
#  47. no list, a list that is not there, a malformed
#      line, a person in the list, an account without
#      its id, an unknown role                        -> red
#  48. the push check reads the list as it was BEFORE the push, through the
#      API, and only for a Bot's push; a list changed in the same push is
#      not honoured; a list that cannot be read is red
#  49. the workflow hands over the authenticated account and the base list
# One mutation proof per condition of the exemption: resting on the listed
# author email alone (43 and 17 green), without the pusher comparison (43b),
# without the list (44), without the linked account (15), without the
# actor (10b), with a sign-off allowed on an exempt commit (45) or on an
# unlisted bot's (43c), and with the list read from the pushed tree (48b).
# One mutation proof per condition (the DCO run's success, merged, this
# repository, membership, committer, verification, second parent, committer
# email, a failed call not an exit): without it its case is green, so the
# case is red BECAUSE of it. And one for the retry (forsgren#287): without it
# case 39e is red, naming the first failure.
# Mutation proofs: case 4 against a copy of the check that reads every
# paragraph after the subject as trailers must turn green, so case 4 is red
# BECAUSE only the last paragraph counts; case 7 against a copy that skips
# the email comparison must turn green, so case 7 is red BECAUSE the emails
# differ.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh

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

# --- The exemption. The list is made up but for Dependabot's line, which is
# GitHub's own account; the agent is an invented GitHub App's bot.
DEPENDABOT="Bot:dependabot[bot]"
DEPENDABOT_ACTOR="Bot:dependabot[bot]:49699333"
BOT_EMAIL="49699333+dependabot[bot]@users.noreply.github.com"
BUMP=$'Bump example-lib from 1.0.0 to 1.0.1\n\nBumps example-lib from 1.0.0 to 1.0.1.'
LIST="$TMP/list.conf"
printf '%s\n' '# made-up list' '' '49699333|dependabot[bot]' '4242|example-agent[bot]' > "$LIST"
MALLORY="User:mallory-example:99"

commit 141414141414eeee "$BOT_EMAIL" "$BUMP" "$DEPENDABOT" > "$TMP/bot.txt"
capture "$CHECK" "$TMP/bot.txt" "$DEPENDABOT_ACTOR" "$LIST"
want_green "14. an unsigned commit by the listed Bot account that opened the pull request" "commit 141414141414 (Bump example-lib from 1.0.0 to 1.0.1) is exempt: authored by the registered automation identity dependabot[bot], which opened this pull request"

commit 151515151515ffff "$BOT_EMAIL" "$BUMP" "User:mallory-example" > "$TMP/spoof-user.txt"
capture "$CHECK" "$TMP/spoof-user.txt" "$DEPENDABOT_ACTOR" "$LIST"
want_red "15. a bot-looking email linked to a User account" "commit 151515151515 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

commit 161616161616aaaa "$BOT_EMAIL" "$BUMP" > "$TMP/spoof-none.txt"
capture "$CHECK" "$TMP/spoof-none.txt" "$DEPENDABOT_ACTOR" "$LIST"
want_red "16. a bot-looking email linked to no account" "commit 161616161616 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

commit 171717171717bbbb "$BOT_EMAIL" "$BUMP" "$DEPENDABOT" > "$TMP/spoof-opener.txt"
capture "$CHECK" "$TMP/spoof-opener.txt" "$MALLORY" "$LIST"
want_red "17. linked to a Bot account, in a pull request a User opened" "commit 171717171717 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

capture "$CHECK" "$TMP/spoof-opener.txt" "Bot:renovate[bot]:12345678" "$LIST"
want_red "18. linked to a Bot account, in a pull request another Bot opened" "commit 171717171717 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

capture "$CHECK" "$TMP/spoof-opener.txt" "" "$LIST"
want_red "19. linked to a Bot account, no opener given" "commit 171717171717 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

{
  commit 202020202020cccc "$BOT_EMAIL" "$BUMP" "$DEPENDABOT"
  commit 212121212121dddd bo@example.org "$UNSIGNED" "User:bo-example"
} > "$TMP/mixed.txt"
capture "$CHECK" "$TMP/mixed.txt" "$DEPENDABOT_ACTOR" "$LIST"
want_red "20. the opening bot's unsigned commit and an unsigned human commit" "commit 212121212121 (Tidy the template) has no Signed-off-by trailer"
if grep 'FAIL' <<< "$OUT" | has -q '202020202020'; then
  fail "20. a FAIL line names the bot's exempt commit too. Output: ${OUT}"
else
  echo "  ok: 20. only the human commit is named as a failure"
fi

capture "$CHECK" "$TMP/bot.txt" "dependabot[bot]" "$LIST"
want_red "21. an account not in the <type>:<login>[:<id>] shape" "is not <type>:<login>[:<id>]"

printf '%s %s %s %s\n' 222222222222eeee 'Bot:dependabot[bot]x' "$(b64 "$BOT_EMAIL")" "$(b64 "$BUMP")" > "$TMP/badaccount.txt"
capture "$CHECK" "$TMP/badaccount.txt" "$DEPENDABOT_ACTOR" "$LIST"
want_red "22. an author account not in the shape" "malformed line 1"

# --- The one signer pair (forsgren#676). The messages end as Dependabot's
# squash merges do: its sign-off, then a Co-authored-by trailer.
PAIR_SIGNOFF='Signed-off-by: dependabot[bot] <support@github.com>'
PAIR_CO='Co-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>'
pair_msg() {
  printf 'Bump example-lib from 1.0.0 to 1.0.1\n\nBumps example-lib from 1.0.0 to 1.0.1.\n\n%s\n%s' "$1" "$PAIR_CO"
}
MISMATCH="is signed off, but not by its author"

commit 22a22a22a22a1111 "$BOT_EMAIL" "$(pair_msg "$PAIR_SIGNOFF")" > "$TMP/pair.txt"
capture "$CHECK" "$TMP/pair.txt"
want_green "22a. the signer pair: Dependabot's noreply author, Dependabot's sign-off" "every one signed off"

commit 22b22b22b22b1111 "12345678+renovate[bot]@users.noreply.github.com" "$(pair_msg "$PAIR_SIGNOFF")" > "$TMP/pair-otherbot.txt"
capture "$CHECK" "$TMP/pair-otherbot.txt"
want_red "22b. Dependabot's sign-off on another bot's noreply author" "commit 22b22b22b22b (Bump example-lib from 1.0.0 to 1.0.1) ${MISMATCH}"

commit 22c22c22c22c1111 ada@example.org "$(pair_msg "$PAIR_SIGNOFF")" > "$TMP/pair-person.txt"
capture "$CHECK" "$TMP/pair-person.txt"
want_red "22c. Dependabot's sign-off on a person's author" "commit 22c22c22c22c (Bump example-lib from 1.0.0 to 1.0.1) ${MISMATCH}"

commit 22d22d22d22d1111 "49699333+Dependabot[bot]@users.noreply.github.com" "$(pair_msg "$PAIR_SIGNOFF")" > "$TMP/pair-authorcase.txt"
capture "$CHECK" "$TMP/pair-authorcase.txt"
want_red "22d. the pair's author email in another case" "commit 22d22d22d22d (Bump example-lib from 1.0.0 to 1.0.1) ${MISMATCH}"

# pair_red <case> <sha> <sign-off line> <description>: that author, another
# sign-off, red as a mismatch.
pair_red() {
  commit "$2" "$BOT_EMAIL" "$(pair_msg "$3")" > "$TMP/pair-$1.txt"
  capture "$CHECK" "$TMP/pair-$1.txt"
  want_red "$1. $4" "commit ${2:0:12} (Bump example-lib from 1.0.0 to 1.0.1) ${MISMATCH}"
}
pair_red 22e 22e22e22e22e1111 'Signed-off-by: Ada Example <ada@example.org>' "Dependabot's noreply author, a person's sign-off"
pair_red 22f 22f22f22f22f1111 'Signed-off-by: renovate[bot] <support@github.com>' "Dependabot's noreply author, the sign-off email with another name"
pair_red 22g 22a9a9a9a9a91111 'Signed-off-by: dependabot[bot] <support@github.com.example.org>' "Dependabot's noreply author, the sign-off name with another email"
pair_red 22h 22a8a8a8a8a81111 'Signed-off-by: Dependabot[bot] <Support@GitHub.com>' "Dependabot's noreply author, the sign-off in another case"

commit 22a7a7a7a7a71111 "$BOT_EMAIL" $'Bump example-lib from 1.0.0 to 1.0.1\n\nSigned-off-by: dependabot[bot] <support@github.com>\n\nBumps example-lib from 1.0.0 to 1.0.1.' > "$TMP/pair-body.txt"
capture "$CHECK" "$TMP/pair-body.txt"
want_red "22i. Dependabot's noreply author, the sign-off in the body" "commit 22a7a7a7a7a7 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

commit 22a6a6a6a6a61111 "$BOT_EMAIL" "$BUMP" > "$TMP/pair-none.txt"
capture "$CHECK" "$TMP/pair-none.txt"
want_red "22j. Dependabot's noreply author, no sign-off" "commit 22a6a6a6a6a6 (Bump example-lib from 1.0.0 to 1.0.1) has no Signed-off-by trailer"

# --- The commits of a push (Scripts/dco_push_commits.sh, forsgren#81): the
# same input lines, built from git for the range before..after, so the check
# can judge a push to main as it judges a pull request. A throwaway
# repository with made-up people; the account is - (a push names none).
PUSH_REPO="$TMP/push-repo"
git init -q -b main "$PUSH_REPO"
push_commit() {
  GIT_AUTHOR_NAME="$2" GIT_AUTHOR_EMAIL="$3" GIT_COMMITTER_NAME="$2" GIT_COMMITTER_EMAIL="$3" \
    git -C "$PUSH_REPO" -c commit.gpgsign=false commit -q --allow-empty -m "$1" -m "${4:-}"
}
push_commit "Start the repository" "Ada Example" "ada@example.org" "Signed-off-by: Ada Example <ada@example.org>"
PUSH_BEFORE="$(git -C "$PUSH_REPO" rev-parse HEAD)"
push_commit "Add the chart" "Ada Example" "ada@example.org" "Signed-off-by: Ada Example <ada@example.org>"
push_commit "Tidy the template" "Bo Example" "bo@example.org" "No sign-off here."
PUSH_AFTER="$(git -C "$PUSH_REPO" rev-parse HEAD)"

# Run as a command substitution (capture's own words are not a command word
# to Scripts/test_gate_wiring.sh, which looks for the helper being run here).
OUT="$(./Scripts/dco_push_commits.sh "$PUSH_BEFORE" "$PUSH_AFTER" "$PUSH_REPO" 2>&1)" && RC=0 || RC=$?
want_green "23. the push lists the two commits after before, oldest first, in the check's line shape" ""
if [[ "$(grep -cE '^[0-9a-f]{40} - [A-Za-z0-9+/=]* [A-Za-z0-9+/=]+$' <<< "$OUT")" -eq 2 ]] \
   && ! grep -q "${PUSH_BEFORE}" <<< "$OUT"; then
  echo "  ok: 23. two lines, none for the commit before the range"
else
  fail "23. want two commit lines and none for the commit before the range. Output: ${OUT}"
fi
printf '%s\n' "$OUT" > "$TMP/push.txt"
capture "$CHECK" "$TMP/push.txt"
want_red "24. the check on a push's commits names the unsigned one" "commit $(git -C "$PUSH_REPO" rev-parse --short=12 HEAD) (Tidy the template) has no Signed-off-by trailer"
if grep -q 'Add the chart' <<< "$OUT"; then
  fail "24. the output names the signed commit too. Output: ${OUT}"
else
  echo "  ok: 24. only the unsigned commit is named"
fi

ZEROS="0000000000000000000000000000000000000000"
capture ./Scripts/dco_push_commits.sh "$ZEROS" "$PUSH_AFTER" "$PUSH_REPO"
want_green "25. an all-zero before (a new branch) lists the head commit" "$PUSH_AFTER"
if [[ "$(wc -l <<< "$OUT" | tr -d ' ')" -eq 1 ]]; then
  echo "  ok: 25. only the head commit, not the history behind it"
else
  fail "25. want the head commit alone. Output: ${OUT}"
fi

capture ./Scripts/dco_push_commits.sh "$PUSH_AFTER" "$PUSH_AFTER" "$PUSH_REPO"
want_red "26. before equal to after lists nothing and is an error" "❌ FAIL: no commit in"

capture ./Scripts/dco_push_commits.sh "$PUSH_AFTER" "$PUSH_BEFORE" "$PUSH_REPO"
want_red "27. an after that brings nothing over before is an error" "❌ FAIL: no commit in"

# --- The push check (Scripts/dco_push_check.sh, forsgren#267, decision #268):
# a pushed commit of a MERGED pull request of this repository whose DCO run
# succeeded on the pull request's head is not judged again, and the merge
# commit GitHub made for it is exempt; everything else keeps the strict rule,
# and a failed API call is red. gh is stubbed (DCO_GH): the stub answers each
# `gh api <path> --jq <expr>` from a fixture file named after the path and
# runs the expression with jq, so the script's own --jq is exercised offline.
# Every sha, name and address is made up.
FX="$TMP/gh-fixtures"
PSTUB="$TMP/push-stub"
mkdir -p "$PSTUB"
cat > "$PSTUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
shift
path=""
expr="."
while [ $# -gt 0 ]; do
  case "$1" in
    --paginate) ;;
    --jq) shift; expr="$1" ;;
    *) path="$1" ;;
  esac
  shift
done
# n: this call's number for this path (forsgren#287: the retry asks again).
n="$(grep -cxF -- "$path" "${GH_FX}/.calls" 2>/dev/null)"
n=$(( ${n:-0} + 1 ))
printf '%s\n' "$path" >> "${GH_FX}/.calls"
file="${GH_FX}/$(printf '%s' "$path" | tr '/?=&' '____')"
if [ ! -f "$file" ]; then
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi
# ONCE <reason>: the first call fails with it, a later one gets the answer
# below it. FAIL <reason> lines: every call fails, call n with the n-th
# line, a call after the last line with the last one.
if [ "$n" -eq 1 ] && grep -q '^ONCE ' "$file"; then
  sed -n 's/^ONCE //p' "$file" >&2
  exit 1
fi
fails="$(grep -c '^FAIL ' "$file")"
if [ "$fails" -gt 0 ]; then
  [ "$n" -le "$fails" ] || n="$fails"
  sed -n 's/^FAIL //p' "$file" | sed -n "${n}p" >&2
  exit 1
fi
grep -v '^ONCE ' "$file" | jq -r "$expr"
STUBEOF
chmod +x "$PSTUB/gh"

# push_check <commits-file> [script]: the push check with the stub gh.
# DCO_RETRY_PAUSE=0: the retry after a failed call (forsgren#287) does not
# sleep here.
export DCO_GH="$PSTUB/gh" GH_FX="$FX" DCO_CHECK="$PWD/Scripts/check_dco.sh" GH_TOKEN=x DCO_RETRY_PAUSE=0
push_check() {
  # The real script is written out in its own branch: Scripts/test_gate_wiring.sh
  # looks for it as a command word here.
  if [[ -n "${2:-}" ]]; then
    "$2" acme/app "$1"
  else
    ./Scripts/dco_push_check.sh acme/app "$1"
  fi
}

APP_HEAD="acea3e92934dddf15e59d01602feb943ff477c42"
APP_MERGE="e85d564a7c3a00000000000000000000000000aa"
APP_FIRST="e57bcd13e13821218649eb0095d43c557c4f39ee"
APP_DIRECT="d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1"
# Dependabot's commit as its security updates write it, with no sign-off:
# red when judged strictly. (Its sign-off as the signer pair writes it would
# be green on its own since forsgren#676, so the strict cases below would
# no longer show their condition.)
DEP_MSG=$'Bump example-lib from 1.0.0 to 1.0.1\n\nBumps example-lib.'
MERGE_MSG=$'Merge pull request #7 from acme/app/dependabot/example-lib\n\nBump example-lib from 1.0.0 to 1.0.1'
MAINTAINER_EMAIL="1234+maintainer-example@users.noreply.github.com"
DEP_SUBJECT="Bump example-lib from 1.0.0 to 1.0.1"
MERGE_SUBJECT="Merge pull request #7 from acme/app/dependabot/example-lib"
SHORT_HEAD="acea3e92934d"
SHORT_MERGE="e85d564a7c3a"

# fx_put <api path> <content>: one fixture answer.
fx_put() {
  printf '%s\n' "$2" > "$FX/$(printf '%s' "$1" | tr '/?=&' '____')"
}
# fx_pulls <sha> <number> <merged_at or null> <base repo> <head sha>
fx_pulls() {
  local merged="null"
  [[ "$3" == "null" ]] || merged="\"$3\""
  fx_put "repos/acme/app/commits/$1/pulls" "[{\"number\":$2,\"merged_at\":${merged},\"base\":{\"repo\":{\"full_name\":\"$4\"}},\"head\":{\"sha\":\"$5\"}}]"
}
# fx_runs <head sha> <conclusion> [app slug]: the head's check runs.
fx_runs() {
  fx_put "repos/acme/app/commits/$1/check-runs?per_page=100" "{\"check_runs\":[{\"name\":\"Quality gates\",\"conclusion\":\"failure\",\"app\":{\"slug\":\"github-actions\"}},{\"name\":\"DCO sign-off\",\"conclusion\":\"$2\",\"app\":{\"slug\":\"${3:-github-actions}\"}}]}"
}
# fx_commit <sha> <verified> <committer login> <committer email> <second parent>
fx_commit() {
  fx_put "repos/acme/app/commits/$1" "{\"commit\":{\"verification\":{\"verified\":$2},\"committer\":{\"email\":\"$4\"}},\"committer\":{\"login\":\"$3\"},\"parents\":[{\"sha\":\"${APP_FIRST}\"},{\"sha\":\"$5\"}]}"
}
# fx_merged_pull: the real failing case, Dependabot pull request 7 merged
# with GitHub's merge button: both pushed commits belong to it, its head
# carries a green DCO run, its commits are the head alone, and the merge
# commit is verified, committed by GitHub, with the head as second parent.
fx_merged_pull() {
  rm -rf "$FX"
  mkdir -p "$FX"
  fx_pulls "$APP_HEAD" 7 "2026-10-21T19:53:21Z" "acme/app" "$APP_HEAD"
  fx_pulls "$APP_MERGE" 7 "2026-10-21T19:53:21Z" "acme/app" "$APP_HEAD"
  fx_runs "$APP_HEAD" success
  fx_put "repos/acme/app/pulls/7/commits" "[{\"sha\":\"${APP_HEAD}\"}]"
  fx_commit "$APP_MERGE" true web-flow noreply@github.com "$APP_HEAD"
}

commit "$APP_HEAD" "$BOT_EMAIL" "$DEP_MSG" > "$TMP/pull-dep.txt"
commit "$APP_MERGE" "$MAINTAINER_EMAIL" "$MERGE_MSG" > "$TMP/pull-merge.txt"
cat "$TMP/pull-dep.txt" "$TMP/pull-merge.txt" > "$TMP/pull-both.txt"

# 28 to 28b: a direct push gains no exemption.
fx_merged_pull
fx_put "repos/acme/app/commits/${APP_DIRECT}/pulls" "[]"
commit "$APP_DIRECT" ada@example.org "$UNSIGNED" > "$TMP/direct-unsigned.txt"
capture push_check "$TMP/direct-unsigned.txt"
want_red "28. a direct push commit without a sign-off" "commit d1d1d1d1d1d1 (Tidy the template) has no Signed-off-by trailer"
if grep -qx "repos/acme/app/commits/${APP_DIRECT}/pulls" "$FX/.calls"; then
  echo "  ok: 28. the API was asked which pull requests the commit belongs to"
else
  fail "28. the API was never asked about the commit's pull requests. Calls: $(cat "$FX/.calls" 2>/dev/null)"
fi
commit "$APP_DIRECT" ada@example.org "$SIGNED_A" > "$TMP/direct-signed.txt"
capture push_check "$TMP/direct-signed.txt"
want_green "28b. a signed-off direct push commit" "every one signed off"

# 29: Dependabot's commit of the merged pull request, its DCO run green.
fx_merged_pull
capture push_check "$TMP/pull-dep.txt"
want_green "29. a Dependabot commit of a merged pull request with a green DCO run is not judged again" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) is not judged again: it belongs to pull request #7, merged, whose own DCO run succeeded on its head"

# 30: the merge commit GitHub made for it.
fx_merged_pull
capture push_check "$TMP/pull-merge.txt"
want_green "30. the merge commit GitHub made for that pull request is exempt" "commit ${SHORT_MERGE} (${MERGE_SUBJECT}) is exempt: the merge commit GitHub made"

# 31: the real push, both commits together.
fx_merged_pull
capture push_check "$TMP/pull-both.txt"
want_green "31. the real push after merging Dependabot's pull request, both commits" "✅ DCO: 2 commit(s), none judged again here: 1 by the DCO run of the merged pull request they belong to, 1 the merge commit GitHub made for one"

# 32: the DCO run failed, is missing, or is not this workflow's.
fx_merged_pull
fx_runs "$APP_HEAD" failure
capture push_check "$TMP/pull-dep.txt"
want_red "32. a commit of a merged pull request whose DCO run failed is judged strictly" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) has no Signed-off-by trailer"
capture push_check "$TMP/pull-merge.txt"
want_red "32. the merge commit of a pull request whose DCO run failed is judged strictly" "commit ${SHORT_MERGE} (${MERGE_SUBJECT}) has no Signed-off-by trailer"
fx_put "repos/acme/app/commits/${APP_HEAD}/check-runs?per_page=100" '{"check_runs":[{"name":"Quality gates","conclusion":"success","app":{"slug":"github-actions"}}]}'
capture push_check "$TMP/pull-dep.txt"
want_red "32b. a commit of a merged pull request with no DCO run is judged strictly" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) has no Signed-off-by trailer"
fx_runs "$APP_HEAD" success some-other-app
capture push_check "$TMP/pull-dep.txt"
want_red "32c. a green check run of that name made by another app is no DCO run" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) has no Signed-off-by trailer"

# 33: a pull request that is not merged; 34: another repository's.
fx_merged_pull
fx_pulls "$APP_HEAD" 7 null "acme/app" "$APP_HEAD"
capture push_check "$TMP/pull-dep.txt"
want_red "33. a commit of a pull request that is not merged is judged strictly" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) has no Signed-off-by trailer"
fx_merged_pull
fx_pulls "$APP_HEAD" 7 "2026-10-21T19:53:21Z" "acme/other" "$APP_HEAD"
capture push_check "$TMP/pull-dep.txt"
want_red "34. a commit of a merged pull request of another repository is judged strictly" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) has no Signed-off-by trailer"

# 35 to 37: a merge commit not made by GitHub, not verified, wrong second parent.
fx_merged_pull
fx_commit "$APP_MERGE" true someone-example noreply@github.com "$APP_HEAD"
capture push_check "$TMP/pull-merge.txt"
want_red "35. a merge commit not committed by GitHub is judged strictly" "commit ${SHORT_MERGE} (${MERGE_SUBJECT}) has no Signed-off-by trailer"
fx_commit "$APP_MERGE" false web-flow noreply@github.com "$APP_HEAD"
capture push_check "$TMP/pull-merge.txt"
want_red "36. a merge commit GitHub did not verify is judged strictly" "commit ${SHORT_MERGE} (${MERGE_SUBJECT}) has no Signed-off-by trailer"
fx_commit "$APP_MERGE" true web-flow noreply@github.com "$APP_DIRECT"
capture push_check "$TMP/pull-merge.txt"
want_red "37. a merge commit whose second parent is not the pull request's head is judged strictly" "commit ${SHORT_MERGE} (${MERGE_SUBJECT}) has no Signed-off-by trailer"

# 38: a commit that is not one of the pull request's commits (a squash or a
# rebase commit GitHub lists under the pull request) is judged strictly.
fx_merged_pull
fx_put "repos/acme/app/pulls/7/commits" "[{\"sha\":\"${APP_DIRECT}\"}]"
fx_commit "$APP_HEAD" true someone-example noreply@github.com "$APP_DIRECT"
capture push_check "$TMP/pull-dep.txt"
want_red "38. a commit the pull request's own DCO run never saw is judged strictly" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) has no Signed-off-by trailer"

# 39: a failed API call is red with its reason, never a pass: the commit is
# signed off, so only the failed call can turn it red.
fx_merged_pull
fx_put "repos/acme/app/commits/${APP_DIRECT}/pulls" "FAIL gh: HTTP 502: Bad Gateway"
capture push_check "$TMP/direct-signed.txt"
want_red "39. a failed pull request lookup is red with gh's reason" "the GitHub API call for the pull requests of commit d1d1d1d1d1d1 failed: gh: HTTP 502: Bad Gateway"
fx_merged_pull
fx_put "repos/acme/app/commits/${APP_HEAD}/check-runs?per_page=100" "FAIL gh: HTTP 403: Resource not accessible by integration"
capture push_check "$TMP/pull-dep.txt"
want_red "39b. a failed check run lookup is red with gh's reason" "the GitHub API call for the check runs of ${SHORT_HEAD} failed: gh: HTTP 403: Resource not accessible by integration"
fx_merged_pull
rm -f "$FX/repos_acme_app_commits_${APP_MERGE}"
capture push_check "$TMP/pull-merge.txt"
want_red "39c. a failed commit lookup is red" "the GitHub API call for commit ${SHORT_MERGE} failed: gh: Not Found (HTTP 404)"
fx_merged_pull
fx_put "repos/acme/app/pulls/7/commits" "FAIL gh: HTTP 500: Server Error"
capture push_check "$TMP/pull-dep.txt"
want_red "39d. a failed pull request commit lookup is red" "the GitHub API call for the commits of pull request #7 failed: gh: HTTP 500: Server Error"

# 39e to 39g (forsgren#287): a failed call is asked once more. One empty
# answer from GitHub (gh --jq: unexpected end of JSON input) turned a signed
# push red; a retry that answers goes on, with one warning naming the first
# failure; a second failure is red naming both; a call that answers is asked
# once.
# warnings: the number of warning lines in the last capture.
warnings() {
  grep -c '⚠️' <<< "$OUT" || true
}
# calls <api path>: how often the stub gh was asked for it since the last
# fx_merged_pull.
calls() {
  grep -cxF -- "$1" "$FX/.calls" || true
}
DIRECT_PULLS="repos/acme/app/commits/${APP_DIRECT}/pulls"
fx_merged_pull
fx_put "$DIRECT_PULLS" $'ONCE unexpected end of JSON input\n[]'
capture push_check "$TMP/direct-signed.txt"
want_green "39e. a pull request lookup that fails once and answers on the retry is green" "every one signed off"
want_said "39e. and its warning names the first failure" "⚠️  DCO: the GitHub API call for the pull requests of commit d1d1d1d1d1d1 failed: unexpected end of JSON input; the retry answered"
if [[ "$(warnings)" -eq 1 ]] && [[ "$(calls "$DIRECT_PULLS")" -eq 2 ]]; then
  echo "  ok: 39e. exactly one warning line, and gh was asked twice"
else
  fail "39e. wanted one warning line and two calls, got $(warnings) and $(calls "$DIRECT_PULLS"). Output: ${OUT}"
fi
fx_merged_pull
fx_put "$DIRECT_PULLS" $'FAIL gh: HTTP 502: Bad Gateway\nFAIL gh: HTTP 504: Gateway Timeout'
capture push_check "$TMP/direct-signed.txt"
want_red "39f. a pull request lookup that fails twice is red naming both reasons" "the GitHub API call for the pull requests of commit d1d1d1d1d1d1 failed: gh: HTTP 502: Bad Gateway; the retry failed too: gh: HTTP 504: Gateway Timeout"
if [[ "$(warnings)" -eq 0 ]] && [[ "$(calls "$DIRECT_PULLS")" -eq 2 ]]; then
  echo "  ok: 39f. no warning line, and gh was asked twice, not more"
else
  fail "39f. wanted no warning line and two calls, got $(warnings) and $(calls "$DIRECT_PULLS"). Output: ${OUT}"
fi
fx_merged_pull
fx_put "$DIRECT_PULLS" "[]"
capture push_check "$TMP/direct-signed.txt"
want_green "39g. a pull request lookup that answers at once is green" "every one signed off"
if [[ "$(warnings)" -eq 0 ]] && [[ "$(calls "$DIRECT_PULLS")" -eq 1 ]]; then
  echo "  ok: 39g. no warning line, and gh was asked once"
else
  fail "39g. wanted no warning line and one call, got $(warnings) and $(calls "$DIRECT_PULLS"). Output: ${OUT}"
fi

# 40: one commit already judged, one direct and unsigned: the direct one is
# named alone, and the other said to be skipped.
fx_merged_pull
fx_put "repos/acme/app/commits/${APP_DIRECT}/pulls" "[]"
cat "$TMP/pull-dep.txt" "$TMP/direct-unsigned.txt" > "$TMP/pull-mixed.txt"
capture push_check "$TMP/pull-mixed.txt"
want_red "40. a mixed push names the direct unsigned commit" "commit d1d1d1d1d1d1 (Tidy the template) has no Signed-off-by trailer"
want_said "40. and says the pull request's commit is not judged again" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) is not judged again"
if grep 'FAIL' <<< "$OUT" | has -q "${SHORT_HEAD}"; then
  fail "40. a FAIL line names the commit already judged too. Output: ${OUT}"
else
  echo "  ok: 40. only the direct commit is named as a failure"
fi

# 41: no commit at all, a malformed line, a wrong call.
: > "$TMP/push-empty.txt"
capture push_check "$TMP/push-empty.txt"
want_red "41. no commit at all is red" "no commit to check"
printf 'not a commit line\n' > "$TMP/push-malformed.txt"
capture push_check "$TMP/push-malformed.txt"
want_red "41b. a line not in the commit shape reaches the check" "malformed line 1"
capture ./Scripts/dco_push_check.sh acme/app
want_red "41c. a wrong call is an error" "usage"

# --- Registered automation identities (forsgren#725). The agent is a made-up
# GitHub App's bot, id 4242, in the made-up list above; the commits are a
# push's (account -), judged with the account that pushed.
AGENT="Bot:example-agent[bot]:4242"
AGENT_EMAIL="4242+example-agent[bot]@users.noreply.github.com"
AGENT_MSG=$'Add the weekly view\n\nThe view reads the history file.'
AGENT_SUBJECT="Add the weekly view"
NOT_EXEMPT="its author is an automation identity that is not exempt here"

commit 424242424242aaaa "$AGENT_EMAIL" "$AGENT_MSG" > "$TMP/agent.txt"
capture "$CHECK" "$TMP/agent.txt" "$AGENT" "$LIST" pusher
want_green "42. the listed agent pushed its own unsigned commit" "commit 424242424242 (${AGENT_SUBJECT}) is exempt: authored by the registered automation identity example-agent[bot], which pushed it"
want_said "42. and the verdict says an exemption, not a sign-off" "1 by a registered automation identity that GitHub authenticated, exempt"

capture "$CHECK" "$TMP/agent.txt" "$MALLORY" "$LIST" pusher
want_red "43. impersonation: a person pushed a commit that names the listed agent as its author" "commit 424242424242 (${AGENT_SUBJECT}) has no Signed-off-by trailer, and ${NOT_EXEMPT}"
if grep -q 'is exempt' <<< "$OUT"; then
  fail "43. the impersonating commit is named as exempt. Output: ${OUT}"
else
  echo "  ok: 43. the impersonating commit is not named as exempt"
fi

capture "$CHECK" "$TMP/agent.txt" "$DEPENDABOT_ACTOR" "$LIST" pusher
want_red "43b. impersonation: another listed identity pushed the agent's commit" "commit 424242424242 (${AGENT_SUBJECT}) has no Signed-off-by trailer, and ${NOT_EXEMPT}"

AGENT_SIGNED="${AGENT_MSG}"$'\n\n'"Signed-off-by: example-agent[bot] <${AGENT_EMAIL}>"
commit 434343434343cccc "$AGENT_EMAIL" "$AGENT_SIGNED" > "$TMP/agent-signed.txt"
capture "$CHECK" "$TMP/agent-signed.txt" "$MALLORY" "$LIST" pusher
want_red "43c. impersonation, signed off under the agent's own email" "commit 434343434343 (${AGENT_SUBJECT}) is signed off by an automation identity, which certifies nothing"

commit 434343434343dddd "$AGENT_EMAIL" "$AGENT_MSG" "Bot:example-agent[bot]" > "$TMP/agent-pull.txt"
capture "$CHECK" "$TMP/agent-pull.txt" "$MALLORY" "$LIST" opener
want_red "43d. impersonation in a pull request a person opened, the commit linked to the agent's account" "commit 434343434343 (${AGENT_SUBJECT}) has no Signed-off-by trailer, and ${NOT_EXEMPT}"
capture "$CHECK" "$TMP/agent-pull.txt" "$AGENT" "$LIST" opener
want_green "43e. the same commit in a pull request the agent opened" "is exempt: authored by the registered automation identity example-agent[bot], which opened this pull request"

UNKNOWN="Bot:unknown-agent[bot]:777"
UNKNOWN_EMAIL="777+unknown-agent[bot]@users.noreply.github.com"
commit 444444444444aaaa "$UNKNOWN_EMAIL" "$AGENT_MSG" > "$TMP/unknown.txt"
capture "$CHECK" "$TMP/unknown.txt" "$UNKNOWN" "$LIST" pusher
want_red "44. an identity that is not in the list pushed its own unsigned commit" "commit 444444444444 (${AGENT_SUBJECT}) has no Signed-off-by trailer, and ${NOT_EXEMPT}"
commit 444444444444bbbb "$UNKNOWN_EMAIL" "${AGENT_MSG}"$'\n\n'"Signed-off-by: unknown-agent[bot] <${UNKNOWN_EMAIL}>" > "$TMP/unknown-signed.txt"
capture "$CHECK" "$TMP/unknown-signed.txt" "$UNKNOWN" "$LIST" pusher
want_red "44b. an identity that is not in the list does not pass by signing off" "commit 444444444444 (${AGENT_SUBJECT}) is signed off by an automation identity, which certifies nothing"
commit 444444444444cccc "5555+example-agent[bot]@users.noreply.github.com" "$AGENT_MSG" > "$TMP/agent-otherid.txt"
capture "$CHECK" "$TMP/agent-otherid.txt" "Bot:example-agent[bot]:5555" "$LIST" pusher
want_red "44c. the listed agent's login under another account id is not the listed identity" "commit 444444444444 (${AGENT_SUBJECT}) has no Signed-off-by trailer, and ${NOT_EXEMPT}"

capture "$CHECK" "$TMP/agent-signed.txt" "$AGENT" "$LIST" pusher
want_red "45. the listed agent's own commit with a sign-off" "commit 434343434343 (${AGENT_SUBJECT}) is by the automation identity example-agent[bot] and carries a Signed-off-by trailer"
commit 454545454545aaaa "$AGENT_EMAIL" "${AGENT_MSG}"$'\n\n'"Signed-off-by: Ada Example <ada@example.org>" > "$TMP/agent-signed-person.txt"
capture "$CHECK" "$TMP/agent-signed-person.txt" "$AGENT" "$LIST" pusher
want_red "45a. the listed agent's own commit with a person's sign-off" "carries a Signed-off-by trailer"

commit 454545454545bbbb "$BOT_EMAIL" "$(pair_msg "$PAIR_SIGNOFF")" "$DEPENDABOT" > "$TMP/dependabot-own.txt"
capture "$CHECK" "$TMP/dependabot-own.txt" "$DEPENDABOT_ACTOR" "$LIST"
want_green "45b. Dependabot's commit with the sign-off line GitHub's service writes, in its own pull request" "commit 454545454545 (Bump example-lib from 1.0.0 to 1.0.1) is exempt"
commit 454545454545cccc "$BOT_EMAIL" "$(pair_msg "Signed-off-by: dependabot[bot] <${BOT_EMAIL}>")" "$DEPENDABOT" > "$TMP/dependabot-self.txt"
capture "$CHECK" "$TMP/dependabot-self.txt" "$DEPENDABOT_ACTOR" "$LIST"
want_red "45c. Dependabot's commit with any other sign-off than that line" "carries a Signed-off-by trailer"

{
  commit 464646464646aaaa "$AGENT_EMAIL" "$AGENT_MSG"
  commit 464646464646bbbb bo@example.org "$UNSIGNED"
} > "$TMP/agent-mixed.txt"
capture "$CHECK" "$TMP/agent-mixed.txt" "$AGENT" "$LIST" pusher
want_red "46. the agent pushed a person's unsigned commit with its own" "commit 464646464646 (Tidy the template) has no Signed-off-by trailer — add one"
if grep 'FAIL' <<< "$OUT" | has -q "${AGENT_SUBJECT}"; then
  fail "46. a FAIL line names the agent's exempt commit too. Output: ${OUT}"
else
  echo "  ok: 46. only the person's commit is named as a failure"
fi
{
  commit 464646464646aaaa "$AGENT_EMAIL" "$AGENT_MSG"
  commit 464646464646cccc ada@example.org "$SIGNED_A"
} > "$TMP/agent-mixed-signed.txt"
capture "$CHECK" "$TMP/agent-mixed-signed.txt" "$AGENT" "$LIST" pusher
want_green "46b. the agent pushed a person's signed-off commit with its own" "2 commit(s): 1 signed off by its author, 1 by a registered automation identity"

capture "$CHECK" "$TMP/agent.txt" "$AGENT"
want_red "47. no list: nobody is exempt" "${NOT_EXEMPT}"
capture "$CHECK" "$TMP/agent.txt" "$AGENT" "$TMP/no-such-list.conf" pusher
want_red "47a. a list that is not there: nobody is exempt" "${NOT_EXEMPT}"
printf '%s\n' '# a list' '4242|example-agent[bot]' '4242 example-agent[bot]' > "$TMP/list-malformed.conf"
capture "$CHECK" "$TMP/agent.txt" "$AGENT" "$TMP/list-malformed.conf" pusher
want_red "47b. a malformed line turns the whole list red, the good line above it included" "line 3 of the list of exempt automation identities is not <id>|<login>[bot]"
printf '%s\n' '99|mallory-example' > "$TMP/list-person.conf"
commit 474747474747aaaa "99+mallory-example@users.noreply.github.com" "$UNSIGNED" > "$TMP/person.txt"
capture "$CHECK" "$TMP/person.txt" "$MALLORY" "$TMP/list-person.conf" pusher
want_red "47c. a person cannot be listed: the line is malformed" "line 1 of the list of exempt automation identities is not <id>|<login>[bot]"
capture "$CHECK" "$TMP/agent.txt" "Bot:example-agent[bot]" "$LIST" pusher
want_red "47d. an account without its id is not the listed identity" "${NOT_EXEMPT}"
capture "$CHECK" "$TMP/agent.txt" "$AGENT" "$LIST" author
want_red "47e. an unknown role" "the account's role is neither opener nor pusher"
capture "$CHECK" "$TMP/one.txt" "$MALLORY" .github/dco-exempt-identities.conf pusher
want_green "47f. this repository's own list is one the check can read" "every one signed off"

# 48: the push check hands the pusher and the list on. The list is the one
# the API answers for the sha main was at BEFORE the push, base64 as the
# contents API gives it; the pushed tree's own file is never read.
APP_AGENT="a9e27a9e27a9e27a9e27a9e27a9e27a9e27a9e27"
APP_BEFORE="bef02ebef02ebef02ebef02ebef02ebef02ebef0"
LIST_CALL="repos/acme/app/contents/.github/dco-exempt-identities.conf?ref=${APP_BEFORE}"
# push_check_as <commits-file> <pusher> <before> [script]
push_check_as() {
  if [[ -n "${4:-}" ]]; then
    "$4" acme/app "$1" "$2" "$3"
  else
    ./Scripts/dco_push_check.sh acme/app "$1" "$2" "$3"
  fi
}
# fx_agent_push [list file]: a direct push of the agent's one commit, and
# the list as it was at APP_BEFORE; with no file, no list is there.
fx_agent_push() {
  fx_merged_pull
  fx_put "repos/acme/app/commits/${APP_AGENT}/pulls" "[]"
  if [[ -n "${1:-}" ]]; then
    fx_put "$LIST_CALL" "{\"content\":\"$(base64 < "$1" | tr -d '\n')\"}"
  fi
}
commit "$APP_AGENT" "$AGENT_EMAIL" "$AGENT_MSG" > "$TMP/push-agent.txt"
printf '%s\n' '49699333|dependabot[bot]' > "$TMP/list-before.conf"

fx_agent_push "$LIST"
capture push_check_as "$TMP/push-agent.txt" "$AGENT" "$APP_BEFORE"
want_green "48. the listed agent's direct push of its own unsigned commit" "commit a9e27a9e27a9 (${AGENT_SUBJECT}) is exempt: authored by the registered automation identity example-agent[bot], which pushed it"
if [[ "$(calls "$LIST_CALL")" -eq 1 ]]; then
  echo "  ok: 48. the list was asked for once, at the sha main was at before the push"
else
  fail "48. the list was not asked for at the sha before the push. Calls: $(cat "$FX/.calls" 2>/dev/null)"
fi

fx_agent_push "$LIST"
capture push_check_as "$TMP/push-agent.txt" "$MALLORY" "$APP_BEFORE"
want_red "48a. impersonation on a push: a person pushed the agent's commit" "commit a9e27a9e27a9 (${AGENT_SUBJECT}) has no Signed-off-by trailer, and ${NOT_EXEMPT}"
if [[ "$(calls "$LIST_CALL")" -eq 0 ]]; then
  echo "  ok: 48a. a person's push never asks for the list"
else
  fail "48a. a person's push asked for the list. Calls: $(cat "$FX/.calls" 2>/dev/null)"
fi
capture push_check "$TMP/push-agent.txt"
want_red "48a. the agent's commit with no pusher given" "${NOT_EXEMPT}"

# 48b: the push adds the agent to the list. A copy of the push check stands
# in a tree whose own list (the pushed one) names the agent, while the list
# before the push does not: not honoured.
PUSHED="$TMP/pushed-tree"
mkdir -p "$PUSHED/Scripts" "$PUSHED/.github"
cp Scripts/dco_push_check.sh Scripts/lib_dco_api.sh "$PUSHED/Scripts/"
cp "$LIST" "$PUSHED/.github/dco-exempt-identities.conf"
fx_agent_push "$TMP/list-before.conf"
capture push_check_as "$TMP/push-agent.txt" "$AGENT" "$APP_BEFORE" "$PUSHED/Scripts/dco_push_check.sh"
want_red "48b. a push that adds its own pusher to the list is judged with the list as it was" "commit a9e27a9e27a9 (${AGENT_SUBJECT}) has no Signed-off-by trailer, and ${NOT_EXEMPT}"
# The sed script is script source, read from a quoted here-doc so nothing
# in it is expanded here; with read, not a command substitution, whose
# parser in an older bash stops on the odd number of quotes.
IFS= read -r PUSHED_LIST_SED <<'SED'
s/^\( *\)listed="[$](api .*$/\1listed="$(base64 < "$LIST_PATH")" || exit 1/
SED
if selftest_mutant ./Scripts/dco_push_check.sh "$PUSHED/Scripts/mutant_push_check.sh" "$PUSHED_LIST_SED"; then
  capture push_check_as "$TMP/push-agent.txt" "$AGENT" "$APP_BEFORE" "$PUSHED/Scripts/mutant_push_check.sh"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: reading the list from the pushed tree, case 48b is green, so it is red because the list is read as it was before the push"
  else
    fail "mutation proof: a push check that reads the pushed tree's list is still red on case 48b (exit ${RC}) — the case is red for another reason. Output: ${OUT}"
  fi
fi

fx_agent_push
capture push_check_as "$TMP/push-agent.txt" "$AGENT" "$APP_BEFORE"
want_red "48c. a list that cannot be read is red, never an empty list" "the GitHub API call for the list of exempt automation identities before the push failed: gh: Not Found (HTTP 404)"
fx_agent_push "$LIST"
capture push_check_as "$TMP/push-agent.txt" "$AGENT" "$ZEROS"
want_red "48d. an all-zero before names no list to read" "the push names no commit main was at before it"
fx_agent_push
fx_put "$LIST_CALL" '{"content":"***"}'
capture push_check_as "$TMP/push-agent.txt" "$AGENT" "$APP_BEFORE"
want_red "48e. a list that does not decode is red" "does not decode"
capture push_check_as "$TMP/push-agent.txt" "example-agent[bot]" "$APP_BEFORE"
want_red "48f. a pusher not in the <type>:<login>:<id> shape" "the pusher is not <type>:<login>:<id>"
capture push_check_as "$TMP/push-agent.txt" "Bot:example-agent[bot]" "$APP_BEFORE"
want_red "48g. a pusher without its id" "the pusher is not <type>:<login>:<id>"

# 49: the workflow hands the check what GitHub authenticated, and the list
# of the base: the opener and the sender with their ids, the before sha, and
# the list in the checkout of the base commit.
WF=".github/workflows/dco.yml"
# wf_has <case> <fixed text>: a line of the workflow holds it.
wf_has() {
  if grep -qF -- "$2" "$WF"; then
    echo "  ok: 49. $1"
  else
    fail "49. $1: ${WF} has no line with: $2"
  fi
}
wf_has "the opener is the pull request's user, with its id" "PR_OPENER: \${{ github.event.pull_request.user.type }}:\${{ github.event.pull_request.user.login }}:\${{ github.event.pull_request.user.id }}"
wf_has "the pull request is judged with the list in the checkout" "./Scripts/check_dco.sh \"\$commits\" \"\$PR_OPENER\" .github/dco-exempt-identities.conf opener"
wf_has "that checkout is the base commit's" "ref: \${{ github.event.pull_request.base.sha }}"
wf_has "the pusher is the push event's sender, with its id" "PUSHER: \${{ github.event.sender.type }}:\${{ github.event.sender.login }}:\${{ github.event.sender.id }}"
wf_has "the push check gets the pusher and the sha before the push" "./Scripts/dco_push_check.sh \"\$REPO\" \"\$commits\" \"\$PUSHER\" \"\$BEFORE\""
if [[ "$(grep -cE '^[[:space:]]+\.github/dco-exempt-identities\.conf$' "$WF")" -eq 1 ]]; then
  echo "  ok: 49. the DCO job's sparse checkout holds the list"
else
  fail "49. ${WF} does not check the list out in the DCO job — a pull request would be judged with no list"
fi
if grep -q 'pull_request_target' <<< "$(grep -v '^[[:space:]]*#' "$WF")"; then
  fail "49. ${WF} triggers on pull_request_target — the checkout would no longer be the guard"
else
  echo "  ok: 49. no pull_request_target trigger"
fi

# Mutation proofs for the exemption (forsgren#725): each rewrites one
# condition of exempt_identity, or one of the two sign-off refusals, by its
# exact text; [$] matches a dollar sign, so nothing here reads as an
# expansion. The mutant must turn green on the case its condition reddens.
# exempt_mutant <name> <sed expression> <commits file> <account> <role> <ok text> <fail text>
exempt_mutant() {
  local mutant="$TMP/mutant-$1/Scripts/check_dco.sh"
  if selftest_mutant "$CHECK" "$mutant" "$2"; then
    capture "$mutant" "$3" "$4" "$LIST" "$5"
    if [[ "$RC" -eq 0 ]]; then
      echo "  ok: mutation proof: $6"
    else
      fail "mutation proof: $7 (exit ${RC}) — the case is red for another reason. Output: ${OUT}"
    fi
  fi
}
NO_ACTOR='s/^  \[ -n "[$]actor_email" \] || return 1$/  :/'
NO_LISTED='s/^  grep -qxF -- "[$]email" <<< "[$]listed_emails" || return 1$/  :/'
NO_SAME='s/^  \[ "[$]email" = "[$]actor_email" \] || return 1$/  :/'
NO_LINKED='s/^  \[ "[$]ROLE" = "pusher" \] || \[ "[$]account" = "Bot:[$]{actor_login}" \] || return 1$/  :/'

exempt_mutant byemail "${NO_ACTOR};${NO_SAME};${NO_LINKED}" "$TMP/agent.txt" "$MALLORY" pusher \
  "exempting by the listed author email alone, case 43 is green, so the impersonation is red because GitHub authenticated someone else" \
  "a check that exempts by the listed author email alone is still red on case 43"
capture "$TMP/mutant-byemail/Scripts/check_dco.sh" "$TMP/spoof-opener.txt" "$MALLORY" "$LIST"
if [[ "$RC" -eq 0 ]]; then
  echo "  ok: mutation proof: exempting by the listed author email alone, case 17 is green, so it is red because a User opened the pull request"
else
  fail "mutation proof: a check that exempts by the listed author email alone is still red on case 17 (exit ${RC}) — case 17 is red for another reason. Output: ${OUT}"
fi
exempt_mutant same "$NO_SAME" "$TMP/agent.txt" "$DEPENDABOT_ACTOR" pusher \
  "without the comparison of the author with the authenticated account, case 43b is green, so it is red because another identity pushed" \
  "a check that takes any listed pusher for any listed author is still red on case 43b"
exempt_mutant listed "$NO_LISTED" "$TMP/unknown.txt" "$UNKNOWN" pusher \
  "without the list, case 44 is green, so it is red because the identity is not listed" \
  "a check that exempts any bot that pushed its own commit is still red on case 44"
exempt_mutant linked "$NO_LINKED" "$TMP/spoof-user.txt" "$DEPENDABOT_ACTOR" opener \
  "without the linked account, case 15 is green, so it is red because its account is a User" \
  "a check that ignores the linked account is still red on case 15"
commit 101010101010eeee "" "$UNSIGNED" > "$TMP/noauthor-unsigned.txt"
capture "$CHECK" "$TMP/noauthor-unsigned.txt" "" "$LIST" pusher
want_red "10b. an unsigned commit with no author email, in a push with no account" "commit 101010101010 (Tidy the template) has no author email"
exempt_mutant actor "$NO_ACTOR" "$TMP/noauthor-unsigned.txt" "" pusher \
  "without the authenticated account, case 10b is green, so a commit with no author email is not exempt because no account was authenticated" \
  "a check that needs no authenticated account is still red on case 10b"
exempt_mutant signoff 's/^\( *\)if \[ -n "[$]signoffs" \] && ! platform_signoff; then$/\1if false; then/' "$TMP/agent-signed.txt" "$AGENT" pusher \
  "allowing a sign-off on an exempt commit, case 45 is green, so it is red because an automation identity signed off" \
  "a check that allows a sign-off on an exempt commit is still red on case 45"
exempt_mutant botsigned 's/^\( *\)if bot_author && ! platform_signoff; then$/\1if false; then/' "$TMP/agent-signed.txt" "$MALLORY" pusher \
  "letting any author pass by signing off, case 43c is green, so it is red because the author is an automation identity" \
  "a check that lets a bot's noreply author pass by signing off is still red on case 43c"

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

# Mutation proofs for the signer pair (forsgren#676): a copy of the check
# without the pair line must be red on case 22a, so 22a is green BECAUSE of
# the pair; and a copy whose pair takes any bot's noreply author must be
# green on case 22b, so 22b catches a pair widened to every bot. Since
# forsgren#725 a bot's noreply author does not pass by a sign-off either,
# the pair's aside, so that mutant widens the pair in both places.
PAIR_LINE='s|^\( *\)if (author == pair_author && trailer == pair_signoff) matched = 1$|'
MUTANT="$TMP/mutant-nopair/Scripts/check_dco.sh"
if selftest_mutant "$CHECK" "$MUTANT" "${PAIR_LINE}"'\1matched = matched|'; then
  capture "$MUTANT" "$TMP/pair.txt"
  if [[ "$RC" -ne 0 ]]; then
    echo "  ok: mutation proof: without the signer pair, case 22a is red, so it is green because of the pair"
  else
    fail "mutation proof: a check without the signer pair is still green on case 22a — case 22a is green for another reason. Output: ${OUT}"
  fi
fi
MUTANT="$TMP/mutant-anybot/Scripts/check_dco.sh"
IFS= read -r ANY_AUTHOR_SED <<'SED'
s/^  \[ "[$]email" = "[$]SIGNER_PAIR_AUTHOR" \] && \[ "[$]signoffs" = "[$]SIGNER_PAIR_SIGNOFF" \]$/  [ "$signoffs" = "$SIGNER_PAIR_SIGNOFF" ]/
SED
if selftest_mutant "$CHECK" "$MUTANT" "${PAIR_LINE}"'\1if (author ~ /\\[bot\\]@users\\.noreply\\.github\\.com$/ \&\& trailer == pair_signoff) matched = 1|;'"${ANY_AUTHOR_SED}"; then
  capture "$MUTANT" "$TMP/pair-otherbot.txt"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: a pair widened to any bot's noreply author is green on case 22b, so case 22b catches the widening"
  else
    fail "mutation proof: a pair widened to any bot's noreply author is still red on case 22b (exit ${RC}) — case 22b does not catch the widening. Output: ${OUT}"
  fi
fi

# Mutation proofs for the push check (forsgren#267). Each mutant is a copy
# of Scripts/dco_push_check.sh with one condition removed, rewritten by the
# exact text of its line, and must turn green on the case that condition
# makes red: the case is then red BECAUSE of that condition.
# mutant_green <name> <sed expression> <commits file> <ok text> <fail text>
# The mutant sources Scripts/lib_dco_api.sh from beside it: a plain copy.
mutant_green() {
  local mutant="$TMP/mutant-$1/Scripts/dco_push_check.sh"
  if selftest_mutant ./Scripts/dco_push_check.sh "$mutant" "$2"; then
    cp Scripts/lib_dco_api.sh "$(dirname "$mutant")/"
    capture push_check "$3" "$mutant"
    if [[ "$RC" -eq 0 ]]; then
      echo "  ok: mutation proof: $4"
    else
      fail "mutation proof: $5 (exit ${RC}) — the case is red for another reason. Output: ${OUT}"
    fi
  fi
}

fx_merged_pull
fx_runs "$APP_HEAD" failure
mutant_green "success" 's/^\( *\)if grep -qx .success. <<< .*; then$/\1if true; then/' "$TMP/pull-dep.txt" \
  "without the DCO-success check, case 32 is green, so it is red because that pull request's DCO run failed" \
  "a push check that never reads the DCO run is still red on case 32"

fx_merged_pull
fx_pulls "$APP_HEAD" 7 null "acme/app" "$APP_HEAD"
mutant_green "merged" 's/^\( *\)\[ "[$]merged_at" != "-" \] || continue$/\1:/' "$TMP/pull-dep.txt" \
  "without the merged check, case 33 is green, so it is red because the pull request is not merged" \
  "a push check that accepts a pull request that is not merged is still red on case 33"

fx_merged_pull
fx_pulls "$APP_HEAD" 7 "2026-10-21T19:53:21Z" "acme/other" "$APP_HEAD"
mutant_green "repo" 's/^\( *\)\[ "[$](printf .*REPO_LOWER" \] || continue$/\1:/' "$TMP/pull-dep.txt" \
  "without the repository check, case 34 is green, so it is red because the pull request belongs to another repository" \
  "a push check that accepts another repository's pull request is still red on case 34"

fx_merged_pull
fx_put "repos/acme/app/pulls/7/commits" "[{\"sha\":\"${APP_DIRECT}\"}]"
fx_commit "$APP_HEAD" true someone-example noreply@github.com "$APP_DIRECT"
mutant_green "member" 's/^\( *\)if in_pull .*; then$/\1if true; then/' "$TMP/pull-dep.txt" \
  "without the membership check, case 38 is green, so it is red because the commit is not one the pull request's DCO run judged" \
  "a push check that accepts any commit the API lists under the pull request is still red on case 38"

fx_merged_pull
fx_commit "$APP_MERGE" true someone-example noreply@github.com "$APP_HEAD"
mutant_green "login" 's/^\( *\)\[ "[$]login" = "web-flow" \] || return 1$/\1:/' "$TMP/pull-merge.txt" \
  "without the committer check, case 35 is green, so it is red because GitHub did not commit it" \
  "a push check that exempts a merge commit by anyone is still red on case 35"

fx_merged_pull
fx_commit "$APP_MERGE" false web-flow noreply@github.com "$APP_HEAD"
mutant_green "verified" 's/^\( *\)\[ "[$]verified" = "true" \] || return 1$/\1:/' "$TMP/pull-merge.txt" \
  "without the verification check, case 36 is green, so it is red because GitHub did not verify the commit" \
  "a push check that exempts an unverified merge commit is still red on case 36"

fx_merged_pull
fx_commit "$APP_MERGE" true web-flow noreply@github.com "$APP_DIRECT"
mutant_green "parent" 's/^\( *\)\[ "[$]second" = "[$]head" \] || return 1$/\1:/' "$TMP/pull-merge.txt" \
  "without the second parent check, case 37 is green, so it is red because that parent is not the pull request's head" \
  "a push check that exempts a merge commit of any parent is still red on case 37"

fx_merged_pull
fx_commit "$APP_MERGE" true web-flow someone@example.org "$APP_HEAD"
capture push_check "$TMP/pull-merge.txt"
want_red "37b. a merge commit with another committer email is judged strictly" "commit ${SHORT_MERGE} (${MERGE_SUBJECT}) has no Signed-off-by trailer"
mutant_green "email" 's/^\( *\)\[ "[$]email" = "noreply@github.com" \] || return 1$/\1:/' "$TMP/pull-merge.txt" \
  "without the committer email check, case 37b is green, so it is red because the committer email is not GitHub's" \
  "a push check that ignores the committer email is still red on case 37b"

fx_merged_pull
fx_put "repos/acme/app/commits/${APP_DIRECT}/pulls" "FAIL gh: HTTP 502: Bad Gateway"
mutant_green "apifail" 's/^    exit 1$/    return 0/' "$TMP/direct-signed.txt" \
  "when a failed API call is not an exit, case 39 is green, so it is red because the call failed" \
  "a push check that goes on after a failed API call is still red on case 39"

# Mutation proof for case 39e (forsgren#287): a copy of the helper whose
# first failure is final, the retry line made `if true`, is red on it, naming
# the empty answer: case 39e is green BECAUSE the call is asked once more.
fx_merged_pull
fx_put "$DIRECT_PULLS" $'ONCE unexpected end of JSON input\n[]'
if selftest_lib_mutant ./Scripts/dco_push_check.sh ./Scripts/lib_dco_api.sh "$TMP/mutant-retry" \
  's/^    if ! dco_api_try "[$]dir" "[$]@"; then$/    if true; then/'; then
  capture push_check "$TMP/direct-signed.txt" "$MUTANT"
  want_red "mutation proof: without the retry, case 39e is red because the first call failed" \
    "the GitHub API call for the pull requests of commit d1d1d1d1d1d1 failed: unexpected end of JSON input"
fi

selftest_end "the DCO check does not hold every commit to a Signed-off-by trailer from its author, or exempts a commit on anything but a listed automation identity that GitHub authenticated as its pusher or its pull request's opener, or lets an automation identity pass by signing off, or does not judge a push as the push check says" \
  "DCO check is green on commits signed off by their authors (any case, among other trailers, CRLF), red naming the unsigned commit alone, on no commit, on a Signed-off-by in the body, mid-line or as the subject, on a sign-off by someone else (no email printed), on no author email and on a malformed line, exits 2 on a missing file, reads stdin, exempts only the unsigned commits of a listed automation identity that GitHub authenticated as the pusher or the pull request's opener (never by a bot-looking email, for a User or no account, another opener or pusher, an unlisted identity, another id, or with a sign-off), is red on an impersonated agent and on a list changed in the same push, names the human commit alone in a mixed pull request or push, takes Dependabot's sign-off for its squash-merge author and no other pair, and its last-paragraph rule, email comparison and each condition of the exemption are what redden their cases, and the signer pair what greens case 22a"
