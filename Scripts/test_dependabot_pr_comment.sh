#!/usr/bin/env bash
# Scripts/test_dependabot_pr_comment.sh
#
# Self-test for Scripts/dependabot_pr_comment.sh (forsgren#664, step 1). No
# network: a fake gh on PATH.
#   1. no comment yet: one is posted, its body the marker then the record
#   2. its own marked comment: updated in place, nothing posted
#   3. its marked comment on the second page of the listing: found, updated
#   4. a marked comment of someone else: left alone, a new one posted
#   5. a failed listing, or one that is not JSON: exit 1, nothing written
#   6. a failed post: exit 1
#   7. usage: no body file exits 2
# Mutation proofs: the author filter dropped (someone else's comment
# overwritten), a failed listing ignored (a duplicate posted), the listing
# read without --paginate (a comment on page two missed).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "dependabot pull-request comment self-test"

COMMENT="Scripts/dependabot_pr_comment.sh"
[[ -x "$COMMENT" ]] || selftest_abort "${COMMENT} does not exist or is not executable — each completion would add a comment, or none would be kept"
MARKER="<!-- dependabot-merge-policy -->"
# D stands for a dollar sign inside double quotes.
D='$'

# The fake gh: logs each call; "api --paginate <path>" prints pages.json,
# "api -X <method> <path> -F body=@<file>" keeps the body it was given;
# fail.list or fail.write makes that kind of call fail.
mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/gh" << 'FAKE'
#!/usr/bin/env bash
D="$FAKE_GH_DIR"
echo "$*" >> "$D/calls.log"
if [ "$1 $2" = "api --paginate" ]; then
  [ ! -e "$D/fail.list" ] || exit 1
  cat "$D/pages.json"
elif [ "$1 $2" = "api -X" ]; then
  [ ! -e "$D/fail.write" ] || exit 1
  cp "${6#body=@}" "$D/sent.md"
  echo '{}'
else
  echo "fake gh: unexpected call: $*" >&2
  exit 64
fi
FAKE
chmod +x "${TMP}/bin/gh"
echo "the record" > "${TMP}/body.md"

N=0
# new_case <pages>: a fresh case whose comment listing is the pages (JSON
# arrays, one per page); leaves it in d.
new_case() {
  N=$((N + 1))
  d="${TMP}/case${N}"
  mkdir -p "$d"
  : > "$d/calls.log"
  printf '%s\n' "$1" > "$d/pages.json"
}
# run_case: runs ${SCRIPT:-$COMMENT} on pull request 7; OUT and RC as
# capture leaves them.
run_case() {
  capture env FAKE_GH_DIR="$d" PATH="${TMP}/bin:${PATH}" GITHUB_REPOSITORY=owner/repo "${SCRIPT:-$COMMENT}" 7 "${TMP}/body.md"
}
calls() { tr '\n' ';' < "$d/calls.log"; }
mine() { jq -cn --arg id "$1" --arg m "$MARKER" '{id: ($id | tonumber), user: {login: "github-actions[bot]"}, body: ($m + "\nold record")}'; }

# The cases, as functions, so the mutation proofs run them again.
case_none() {
  new_case '[]'
  run_case
}
case_own() {
  new_case "[{\"id\": 1, \"user\": {\"login\": \"someone\"}, \"body\": \"hello\"}, $(mine 42)]"
  run_case
}
case_page_two() {
  new_case "[{\"id\": 1, \"user\": {\"login\": \"someone\"}, \"body\": \"hello\"}]
[$(mine 99)]"
  run_case
}
case_other() {
  new_case "[{\"id\": 5, \"user\": {\"login\": \"someone\"}, \"body\": \"$MARKER copied\"}]"
  run_case
}
case_list_fails() {
  new_case '[]'
  touch "$d/fail.list"
  run_case
}
page_two_holds() { [[ "$RC" -eq 0 ]] && grep -q '^api -X PATCH repos/owner/repo/issues/comments/99 ' "$d/calls.log"; }
other_holds() { [[ "$RC" -eq 0 ]] && grep -q '^api -X POST ' "$d/calls.log" && ! grep -q PATCH "$d/calls.log"; }
list_fails_holds() { [[ "$RC" -eq 1 ]] && ! grep -q -- '-X' "$d/calls.log"; }

# 1
case_none
if [[ "$RC" -eq 0 ]] && grep -q "^api -X POST repos/owner/repo/issues/7/comments -F body=@" "$d/calls.log"; then
  echo "  ok: 1. no comment yet: posts one"
else
  fail "1. no comment yet: exit ${RC}, calls: $(calls)"
fi
if [[ "$(head -1 "$d/sent.md")" == "$MARKER" ]] && grep -qxF "the record" "$d/sent.md"; then echo "  ok: 1. the body starts with the marker and holds the record"; else fail "1. the body lacks the marker or the record"; fi

# 2
case_own
if [[ "$RC" -eq 0 ]] && grep -q '^api -X PATCH repos/owner/repo/issues/comments/42 ' "$d/calls.log" && ! grep -q POST "$d/calls.log"; then
  echo "  ok: 2. its own marked comment: updates it in place"
else
  fail "2. its own comment: exit ${RC}, calls: $(calls)"
fi

# 3
case_page_two
if page_two_holds; then echo "  ok: 3. a marked comment on the second page is found"; else fail "3. second page: exit ${RC}, calls: $(calls)"; fi

# 4
case_other
if other_holds; then echo "  ok: 4. a marked comment of someone else is left alone"; else fail "4. someone else's marker: exit ${RC}, calls: $(calls)"; fi

# 5
case_list_fails
if list_fails_holds; then echo "  ok: 5. a failed listing fails and writes nothing"; else fail "5. failed listing: exit ${RC}, calls: $(calls)"; fi
new_case 'not json'
run_case
if [[ "$RC" -eq 1 ]] && ! grep -q -- '-X' "$d/calls.log"; then echo "  ok: 5. a listing that is not JSON fails and writes nothing"; else fail "5. a listing that is not JSON: exit ${RC}"; fi

# 6
new_case '[]'
touch "$d/fail.write"
run_case
want_rc "6. a failed post fails" 1

# 7
capture env FAKE_GH_DIR="$d" PATH="${TMP}/bin:${PATH}" GITHUB_REPOSITORY=owner/repo "$COMMENT" 7
want_exit "7. no body file exits 2" 2 "usage:"

# Mutation proofs: each mutant must break the case that guards it.
# comment_mutant <name> <sed> <case function> <holds function> <what>
comment_mutant() {
  if selftest_mutant "$COMMENT" "${TMP}/mut/$1/Scripts/dependabot_pr_comment.sh" "$2"; then
    SCRIPT="${TMP}/mut/$1/Scripts/dependabot_pr_comment.sh"
    "$3"
    unset SCRIPT
    if "$4"; then fail "mutation proof: $5 is not caught"; else echo "  ok: mutation proof: $5 is caught"; fi
  fi
}
comment_mutant author "s/\\.user\\.login == \\${D}b and //" case_other other_holds "the author filter dropped"
comment_mutant listfail '/could not list/{n;s/exit 1/:/;}' case_list_fails list_fails_holds "a failed listing ignored"
comment_mutant paginate 's/gh api --paginate /gh api /' case_page_two page_two_holds "the listing read without --paginate"

selftest_end "the Dependabot pull-request comment does not hold" \
  "dependabot pull-request comment: its own marked comment updated in place on any page, someone else's left alone, every failed call red; mutation proven"
