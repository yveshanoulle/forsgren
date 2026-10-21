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
#  40. a mixed push                                   -> the direct commit alone named
#  41. no commit, a malformed line, a wrong call      -> red
# One mutation proof per condition (the DCO run's success, merged, this
# repository, membership, committer, verification, second parent, committer
# email, a failed call not an exit): without it its case is green, so the
# case is red BECAUSE of it.
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

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

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
printf '%s\n' "$path" >> "${GH_FX}/.calls"
file="${GH_FX}/$(printf '%s' "$path" | tr '/?=&' '____')"
if [ ! -f "$file" ]; then
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi
if grep -q '^FAIL ' "$file"; then
  sed 's/^FAIL //' "$file" >&2
  exit 1
fi
jq -r "$expr" "$file"
STUBEOF
chmod +x "$PSTUB/gh"

# push_check <commits-file> [script]: the push check with the stub gh.
export DCO_GH="$PSTUB/gh" GH_FX="$FX" DCO_CHECK="$PWD/Scripts/check_dco.sh" GH_TOKEN=x
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
DEP_MSG=$'Bump example-lib from 1.0.0 to 1.0.1\n\nBumps example-lib.\n\nSigned-off-by: dependabot[bot] <support@github.com>'
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
want_red "32. a commit of a merged pull request whose DCO run failed is judged strictly" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) is signed off, but not by its author"
capture push_check "$TMP/pull-merge.txt"
want_red "32. the merge commit of a pull request whose DCO run failed is judged strictly" "commit ${SHORT_MERGE} (${MERGE_SUBJECT}) has no Signed-off-by trailer"
fx_put "repos/acme/app/commits/${APP_HEAD}/check-runs?per_page=100" '{"check_runs":[{"name":"Quality gates","conclusion":"success","app":{"slug":"github-actions"}}]}'
capture push_check "$TMP/pull-dep.txt"
want_red "32b. a commit of a merged pull request with no DCO run is judged strictly" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) is signed off, but not by its author"
fx_runs "$APP_HEAD" success some-other-app
capture push_check "$TMP/pull-dep.txt"
want_red "32c. a green check run of that name made by another app is no DCO run" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) is signed off, but not by its author"

# 33: a pull request that is not merged; 34: another repository's.
fx_merged_pull
fx_pulls "$APP_HEAD" 7 null "acme/app" "$APP_HEAD"
capture push_check "$TMP/pull-dep.txt"
want_red "33. a commit of a pull request that is not merged is judged strictly" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) is signed off, but not by its author"
fx_merged_pull
fx_pulls "$APP_HEAD" 7 "2026-10-21T19:53:21Z" "acme/other" "$APP_HEAD"
capture push_check "$TMP/pull-dep.txt"
want_red "34. a commit of a merged pull request of another repository is judged strictly" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) is signed off, but not by its author"

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
want_red "38. a commit the pull request's own DCO run never saw is judged strictly" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) is signed off, but not by its author"

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

# 40: one commit already judged, one direct and unsigned: the direct one is
# named alone, and the other said to be skipped.
fx_merged_pull
fx_put "repos/acme/app/commits/${APP_DIRECT}/pulls" "[]"
cat "$TMP/pull-dep.txt" "$TMP/direct-unsigned.txt" > "$TMP/pull-mixed.txt"
capture push_check "$TMP/pull-mixed.txt"
want_red "40. a mixed push names the direct unsigned commit" "commit d1d1d1d1d1d1 (Tidy the template) has no Signed-off-by trailer"
want_said "40. and says the pull request's commit is not judged again" "commit ${SHORT_HEAD} (${DEP_SUBJECT}) is not judged again"
if grep 'FAIL' <<< "$OUT" | grep -q "${SHORT_HEAD}"; then
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

# Mutation proofs for the push check (forsgren#267). Each mutant is a copy
# of Scripts/dco_push_check.sh with one condition removed, rewritten by the
# exact text of its line, and must turn green on the case that condition
# makes red: the case is then red BECAUSE of that condition.
# mutant_green <name> <sed expression> <commits file> <ok text> <fail text>
mutant_green() {
  local mutant="$TMP/mutant-$1/Scripts/dco_push_check.sh"
  if selftest_mutant ./Scripts/dco_push_check.sh "$mutant" "$2"; then
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
mutant_green "success" 's/^\( *\)if printf .*grep -qx .success.; then$/\1if true; then/' "$TMP/pull-dep.txt" \
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

selftest_end "the DCO check does not hold every commit to a Signed-off-by trailer from its author, or exempts a commit on anything but the Bot account that opened the pull request, or does not judge a push as the push check says" \
  "DCO check is green on commits signed off by their authors (any case, among other trailers, CRLF), red naming the unsigned commit alone, on no commit, on a Signed-off-by in the body, mid-line or as the subject, on a sign-off by someone else (no email printed), on no author email and on a malformed line, exits 2 on a missing file, reads stdin, exempts only the unsigned commits of the Bot account that opened the pull request (never by a bot-looking email, for a User or no account, another opener or none), names the human commit alone in a mixed pull request, and its last-paragraph rule, email comparison, account rule and opener comparison are what redden cases 4, 7, 15 and 17"
