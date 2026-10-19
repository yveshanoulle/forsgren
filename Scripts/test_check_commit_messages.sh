#!/usr/bin/env bash
# Scripts/test_check_commit_messages.sh
#
# Self-test for Scripts/check_commit_messages.sh, Scripts/dco_pr_commits.sh
# and the --fresh mode of Scripts/dco_push_commits.sh (forsgren#213).
# forsgren's own, not canon. The private-names gate keeps the names out of
# the tree and out of the message FBP.sh is about to commit; this proves the
# check .github/workflows/dco.yml adds, that the message of every commit a
# push or a pull request brings is judged by the same matcher and list
# (Scripts/check_private_names.sh --message -), because a commit that did not
# pass through FBP.sh (a pull request, a hand-made push) is judged by nothing
# else. Every name below is made up (acme-secret-repo, globex-internal).
#
# The check reads the lines Scripts/check_dco.sh reads,
#   <sha> <author account> <base64 of the author email> <base64 of the message>
# from a file or stdin. Cases:
#   1. a range whose middle commit names a listed name   -> red, naming that
#                                                           commit alone
#   2. the same hit in another letter case, and in the
#      body of a message                                  -> red
#   3. a clean range                                      -> green, the count
#   4. the output never holds a name or the message text
#   5. no commit at all; a malformed line                 -> red
#   6. in GitHub Actions, no list or a list with no names
#      -> exit 2 naming the Actions secret: --message alone passes without a
#      list, and CI must never pass for that reason
#   7. a new branch (all-zero before): every commit that is on no other branch
#      or tag is checked, one named, one already on another branch left out
#   8. a before the checkout does not have (a force-push): the same rule
#   9. a hit in a commit already on another branch -> not judged again
#  10. Scripts/dco_pr_commits.sh asks gh for the pull request's commits
# Mutation proofs: a check that judges only the LAST commit turns case 1
# green, so it is red because every commit is judged; a listing that skips the
# range when before is not available turns case 8 into something that does not
# name the commit, so it is caught for its reason.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
selftest_begin "commit messages self-test"

CHECK="./Scripts/check_commit_messages.sh"
LISTER="./Scripts/dco_push_commits.sh"
PRLIST="./Scripts/dco_pr_commits.sh"
NAME_A="acme-secret-repo"
NAME_B="globex-internal"
for file in "$CHECK" "$LISTER" "$PRLIST" Scripts/check_private_names.sh Scripts/lib_private_names.sh; do
  [[ -f "$file" ]] || selftest_abort "${file} does not exist"
done

export FORSGREN_PRIVATE_NAMES="${NAME_A}"$'\n'"${NAME_B}"
unset FORSGREN_PRIVATE_NAMES_EXTRA FORSGREN_PRIVATE_NAMES_EXTRA_FILE FORSGREN_PRIVATE_NAMES_FILE GITHUB_ACTIONS
export HOME="${TMP}/home"
mkdir -p "$HOME"

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

# line <sha> <message>: one input line, the account -.
line() {
  printf '%s - %s %s\n' "$1" "$(b64 "ada@example.org")" "$(b64 "$2")"
}

# revealed <text...>: succeeds when OUT holds one of the texts.
revealed() {
  local text
  for text in "$@"; do
    if grep -qiF -- "$text" <<< "$OUT"; then
      REVEALED="$text"
      return 0
    fi
  done
  return 1
}

want_not_revealed() {
  local case_name="$1"
  shift
  if revealed "$@"; then
    fail "${case_name}: the output reveals '${REVEALED}'. Output: ${OUT}"
  else
    echo "  ok: ${case_name}: the output holds no name and no message text"
  fi
}

SHA1=1111111111111111111111111111111111111111
SHA2=2222222222222222222222222222222222222222
SHA3=3333333333333333333333333333333333333333
SHORT2="${SHA2:0:12}"

# --- The check, on lines written by hand (a pull request's shape).
{
  line "$SHA1" "Add the chart"
  line "$SHA2" "Touch the Pre-acme-secret-repo notes"
  line "$SHA3" "Tidy the template"
} > "$TMP/range.txt"
capture "$CHECK" "$TMP/range.txt"
want_red "1. a hit in the middle commit is red, naming that commit" "commit ${SHORT2} names a private name"
if grep -q "${SHA1:0:12}\|${SHA3:0:12}" <<< "$OUT"; then
  fail "1. the output names a clean commit too. Output: ${OUT}"
else
  echo "  ok: 1. only the commit with the name is named"
fi
want_not_revealed "4. a hit" "$NAME_A" "$NAME_B" "notes" "Pre-" "Add the chart" "Tidy the template"

{
  line "$SHA1" "Add the chart"
  line "$SHA2" $'Subject line\n\nThe body mentions GLOBEX-Internal in passing.\n'
  line "$SHA3" "Tidy the template"
} > "$TMP/body.txt"
capture "$CHECK" "$TMP/body.txt"
want_red "2. a name in the body, in other letter case, is red" "commit ${SHORT2} names a private name"
want_not_revealed "4. a body hit" "$NAME_A" "$NAME_B" "passing"

{
  line "$SHA1" "Add the chart"
  line "$SHA2" "Fix the legend"
  line "$SHA3" "Tidy the template"
} > "$TMP/clean.txt"
capture "$CHECK" "$TMP/clean.txt"
want_green "3. a clean range is green, with the count" "OK: 3 commit messages"
from_stdin() { "$CHECK" < "$1"; }
capture from_stdin "$TMP/clean.txt"
want_green "3. the lines on stdin" "OK: 3 commit messages"

: > "$TMP/empty.txt"
capture "$CHECK" "$TMP/empty.txt"
want_red "5. no commit is red: nothing checked is not clean" "no commit"
printf 'not a commit line\n' > "$TMP/bad.txt"
capture "$CHECK" "$TMP/bad.txt"
want_red "5. a malformed line is red" "malformed line 1"
capture "$CHECK" "$TMP/missing.txt"
want_exit "5. a missing input file is exit 2" 2 "input file not found"

capture env -u FORSGREN_PRIVATE_NAMES GITHUB_ACTIONS=true "$CHECK" "$TMP/clean.txt"
want_exit "6. in Actions, no list at all is exit 2, naming the secret" 2 "FORSGREN_PRIVATE_NAMES"
capture env FORSGREN_PRIVATE_NAMES=$'# only a comment\n' GITHUB_ACTIONS=true "$CHECK" "$TMP/clean.txt"
want_exit "6. in Actions, a list with no names is exit 2" 2 "FORSGREN_PRIVATE_NAMES"
capture env GITHUB_ACTIONS=true "$CHECK" "$TMP/clean.txt"
want_green "6. in Actions, a list with names is judged" "OK: 3 commit messages"

# --- The commits of a push, listed from git by Scripts/dco_push_commits.sh.
# Four commits; c0 is on another branch already (refs/remotes/origin/other),
# the pushed main (refs/remotes/origin/main, the push itself) is not counted
# as "another branch".
REPO="$TMP/repo"
git init -q -b main "$REPO"
commit() {
  GIT_AUTHOR_NAME="Ada Example" GIT_AUTHOR_EMAIL="ada@example.org" \
    GIT_COMMITTER_NAME="Ada Example" GIT_COMMITTER_EMAIL="ada@example.org" \
    git -C "$REPO" -c commit.gpgsign=false commit -q --allow-empty -m "$1"
}
commit "Start the repository"
C0="$(git -C "$REPO" rev-parse HEAD)"
commit "Add the chart"
commit "Touch the acme-secret-repo notes"
C2="$(git -C "$REPO" rev-parse HEAD)"
commit "Tidy the template"
C3="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" update-ref refs/remotes/origin/other "$C0"
git -C "$REPO" update-ref refs/remotes/origin/main "$C3"
ZEROS="0000000000000000000000000000000000000000"
GONE="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

# push_check <lister> <before> <after>: the workflow's pipeline, the listing
# into a file and the check on it. A listing that fails is the run's output.
push_check() {
  local lister="$1" listing
  if ! listing="$("$lister" --fresh "$2" "$3" "$REPO" 2>&1)"; then
    OUT="$listing"
    RC=1
    return 0
  fi
  printf '%s\n' "$listing" > "$TMP/push.txt"
  capture "$CHECK" "$TMP/push.txt"
}

push_check "$LISTER" "$C0" "$C3"
want_red "1. a push range with a hit in a middle commit is red" "commit ${C2:0:12} names a private name"

push_check "$LISTER" "$ZEROS" "$C3"
want_red "7. a new branch (all-zero before) checks every commit on no other branch" "commit ${C2:0:12} names a private name"
want_not_revealed "7. a new branch" "$NAME_A" "$NAME_B" "notes"

push_check "$LISTER" "$GONE" "$C3"
want_red "8. a before the checkout does not have still checks those commits" "commit ${C2:0:12} names a private name"
want_not_revealed "8. an unavailable before" "$NAME_A" "$NAME_B" "notes"

OUT="$("$LISTER" --fresh "$ZEROS" "$C3" "$REPO" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" -eq 0 && "$(wc -l <<< "$OUT" | tr -d ' ')" -eq 3 ]] && ! grep -q "^${C0} " <<< "$OUT"; then
  echo "  ok: 7. three commits listed, none of those already on another branch"
else
  fail "7. want the three commits after c0, oldest first (exit ${RC}). Output: ${OUT}"
fi

# A hit only in a commit another branch already holds is not judged again.
REPO2="$TMP/repo2"
git init -q -b main "$REPO2"
REPO_SAVE="$REPO"
REPO="$REPO2"
commit "Mention globex-internal in the first commit"
D0="$(git -C "$REPO" rev-parse HEAD)"
commit "Add the chart"
commit "Tidy the template"
D2="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" update-ref refs/remotes/origin/other "$D0"
git -C "$REPO" update-ref refs/remotes/origin/main "$D2"
push_check "$LISTER" "$ZEROS" "$D2"
want_green "9. a hit in a commit already on another branch is not judged again" "OK: 2 commit messages"
REPO="$REPO_SAVE"

# A repository with no other branch: every commit is new.
REPO3="$TMP/repo3"
git init -q -b main "$REPO3"
REPO="$REPO3"
commit "Mention acme-secret-repo in the very first commit"
commit "Add the chart"
E1="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" update-ref refs/remotes/origin/main "$E1"
push_check "$LISTER" "$ZEROS" "$E1"
want_red "7. with no other branch the whole history is new" "names a private name"
REPO="$REPO_SAVE"

# Without --fresh the listing is the DCO's, unchanged: a before git does not
# have is an error there (Scripts/test_check_dco.sh pins the rest).
capture "$LISTER" "$GONE" "$C3" "$REPO"
want_red "8. without --fresh an unavailable before is still the DCO listing's error" "git could not list"

# --- Scripts/dco_pr_commits.sh: gh, stubbed, is asked for the pull request's
# commits; its --jq is gh's own, so the stub only shows what it was asked.
STUB="$TMP/stub"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${GH_ARGS_FILE}"
printf 'abc1234 - Zm9v YmFy\n'
STUBEOF
chmod +x "$STUB/gh"
# The listing run with the stub gh first on PATH; a function, so the call
# stands where a command stands.
pr_list() {
  PATH="${STUB}:${PATH}" GH_ARGS_FILE="$TMP/gh_args" GH_TOKEN=x ./Scripts/dco_pr_commits.sh "$@"
}
capture pr_list acme/web 7
want_green "10. the pull request's commit list is gh's output" "abc1234 - Zm9v YmFy"
if grep -q "api --paginate repos/acme/web/pulls/7/commits --jq" "$TMP/gh_args" 2>/dev/null; then
  echo "  ok: 10. gh was asked for repos/acme/web/pulls/7/commits, paginated, with its own --jq"
else
  fail "10. gh was not asked for the pull request's commits. Arguments: $(cat "$TMP/gh_args" 2>/dev/null)"
fi
capture pr_list acme/web
want_red "10. a wrong call is an error" "usage"

# --- Mutation proof for case 1: a check that judges only the last commit.
# The mutant needs the gate and its library beside it.
MUTANT="$TMP/mutant-last/Scripts/check_commit_messages.sh"
if selftest_mutant "$CHECK" "$MUTANT" 's/^for ((i = 0; i < total; i++)); do$/for ((i = total - 1; i < total; i++)); do/'; then
  cp Scripts/check_private_names.sh Scripts/lib_private_names.sh "$TMP/mutant-last/Scripts/"
  capture "$MUTANT" "$TMP/range.txt"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: judging only the last commit, case 1 is green, so it is red because every commit is judged"
  else
    fail "mutation proof: a check that judges only the last commit is still red on case 1 (exit ${RC}) — case 1 is red for another reason. Output: ${OUT}"
  fi
fi

# --- Mutation proof for case 8: a listing that skips the range when before
# is not available lists nothing and exits 0; the check must then not name
# the commit.
MUTANT="$TMP/mutant-skip/Scripts/dco_push_commits.sh"
if selftest_mutant "$LISTER" "$MUTANT" 's/^\( *\)shas="[$](git rev-list --reverse "[$]AFTER" --not .*$/\1exit 0/'; then
  push_check "$MUTANT" "$GONE" "$C3"
  if grep -qF "commit ${C2:0:12} names a private name" <<< "$OUT"; then
    fail "mutation proof: a listing that skips the range when before is unavailable still names the commit — case 8 is not caught for its reason. Output: ${OUT}"
  else
    echo "  ok: mutation proof: skipping the range when before is unavailable, case 8 no longer names the commit, so it is red because that range is listed"
  fi
fi

selftest_end "the commit-message check does not judge every commit a push or a pull request brings with the private-names matcher, or lets a new branch, a missing before or a missing list pass silently" \
  "commit-message check is red naming the commit alone (never a name or the message text) when any commit of a range names a private name, in any letter case and in a body, green on a clean range, red on no commit, on a malformed line, exit 2 on a missing file and, in Actions, on no list or a list with no names, checks every commit on no other branch of a new branch and of an unavailable before (leaving out those another branch holds), leaves the DCO listing as it was, and its every-commit loop and its listing of an unavailable before are what redden cases 1 and 8"
