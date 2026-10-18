#!/usr/bin/env bash
# Scripts/test_release_commit.sh
#
# Self-test for Scripts/release_commit.sh (forsgren#221, step 2 of 2), in a
# throwaway repository with a local bare repository as its origin.
#   1. a bump in the tree        -> one commit on top of main, pushed; the
#      subject is `release X.Y.Z (1/1): bump to X.Y.Z, #a #b`, the author is
#      github-actions[bot], and Scripts/check_dco.sh accepts the commit
#   1b. GIT_AUTHOR_* / GIT_COMMITTER_* exported by the caller -> the bot still
#      authors, commits and signs off (the script owns its identity)
#   2. a message that names a private name (the list is the self-test's) -> red, nothing committed or pushed
#   3. no change / an untracked file       -> red, nothing pushed
#   4. main moved on the remote            -> red, the remote is unchanged
#   5. usage errors                        -> exit 2
# Mutation proofs: a copy without the sign-off, one without the private-names
# check and one that pushes with --force must each let their case pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release commit self-test"
D='$'

COMMIT="Scripts/release_commit.sh"
[[ -f "$COMMIT" ]] || selftest_abort "${COMMIT} does not exist — the release bump would be committed by hand"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset FORSGREN_PRIVATE_NAMES_FILE FORSGREN_PRIVATE_NAMES_EXTRA_FILE FORSGREN_PRIVATE_NAMES_EXTRA || true
export FORSGREN_PRIVATE_NAMES="hiddenrepo"

# fresh <name>: a repository with main pushed to a bare origin; its path in W.
fresh() {
  W="${TMP}/$1"
  rm -rf "$W" "${TMP}/$1.git"
  git init -q --bare -b main "${TMP}/$1.git"
  git init -q -b main "$W"
  mkdir -p "$W/Scripts"
  cp Scripts/release_commit.sh Scripts/check_private_names.sh Scripts/lib_private_names.sh Scripts/check_dco.sh "$W/Scripts/"
  echo 'var version = "1.0.0"' > "$W/main.go"
  git -C "$W" add -A
  git -C "$W" -c user.name=t -c user.email=t@example.test commit -q -m "base"
  git -C "$W" remote add origin "${TMP}/$1.git"
  git -C "$W" push -q origin main
  BASE_SHA="$(git -C "$W" rev-parse HEAD)"
}

# commit <args>...: the script in the repository W.
commit() {
  (cd "$W" && "${SCRIPT:-./Scripts/release_commit.sh}" "$@") > "${TMP}/out.txt" 2>&1 && RC=0 || RC=$?
  OUT="$(cat "${TMP}/out.txt")"
}
remote_head() { git -C "${TMP}/$1.git" rev-parse main; }
bump() { echo 'var version = "1.0.1"' > "$W/main.go"; }

fresh a
bump
commit 1.0.1 "#3 #5" "${TMP}/a.git"
want_green "a bump commit" "OK: committed and pushed"
want_said "the subject names the version and the issues" "release 1.0.1 (1/1): bump to 1.0.1, #3 #5"
want_said "the sha is a machine readable line" "sha=$(git -C "$W" rev-parse HEAD)"
if [[ "$(remote_head a)" == "$(git -C "$W" rev-parse HEAD)" && "$(git -C "$W" rev-parse HEAD~1)" == "$BASE_SHA" ]]; then
  echo "  ok: the remote main is one commit on top of the old one"
else
  fail "the remote main is not the bump commit on top of the base"
fi
if [[ "$(git -C "$W" log -1 --format=%an)" == "github-actions[bot]" ]]; then echo "  ok: the author is github-actions[bot]"; else fail "the author is $(git -C "$W" log -1 --format=%an)"; fi
line="$(git -C "$W" log -1 --format=%H) - $(git -C "$W" log -1 --format=%ae | base64 | tr -d '\n') $(git -C "$W" log -1 --format=%B | base64 | tr -d '\n')"
printf '%s\n' "$line" > "${TMP}/dco.txt"
capture "$W/Scripts/check_dco.sh" "${TMP}/dco.txt"
want_green "Scripts/check_dco.sh accepts the commit"

# The FBP wrapper exports the identity of its own user in the four GIT_*
# variables, which win over git config: the script owns its identity.
fresh f
bump
GIT_AUTHOR_NAME=someone-else GIT_AUTHOR_EMAIL=someone@example.test \
  GIT_COMMITTER_NAME=someone-else GIT_COMMITTER_EMAIL=someone@example.test \
  commit 1.0.1 "#3" "${TMP}/f.git"
want_green "a leaked GIT_* identity" "OK: committed and pushed"
for field in an ae cn ce; do
  got="$(git -C "$W" log -1 --format=%${field})"
  case "$field" in
    an | cn) want="github-actions[bot]" ;;
    *) want="41898282+github-actions[bot]@users.noreply.github.com" ;;
  esac
  if [[ "$got" == "$want" ]]; then echo "  ok: ${field} is the bot under a leaked identity"; else fail "${field} is '${got}' under a leaked identity, want '${want}'"; fi
done
if git -C "$W" log -1 --format=%B | grep -qxF "Signed-off-by: github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>"; then
  echo "  ok: the sign-off is the bot's under a leaked identity"
else
  fail "the sign-off is not the bot's under a leaked identity: $(git -C "$W" log -1 --format=%B)"
fi

fresh b
bump
FORSGREN_PRIVATE_NAMES="bump to 1.0.1" commit 1.0.1 "#3" "${TMP}/b.git"
want_red "a message with a private name" "check_private_names"
if [[ "$(git -C "$W" rev-parse HEAD)" == "$BASE_SHA" && "$(remote_head b)" == "$BASE_SHA" ]]; then echo "  ok: nothing was committed or pushed"; else fail "a commit was made although the message was refused"; fi

fresh c
commit 1.0.1 "#3" "${TMP}/c.git"
want_red "no change in the tree" "holds no change to commit"
echo x > "$W/new.txt"
bump
commit 1.0.1 "#3" "${TMP}/c.git"
want_red "an untracked file" "untracked files"
if [[ "$(remote_head c)" == "$BASE_SHA" ]]; then echo "  ok: nothing was pushed"; else fail "something was pushed"; fi

fresh d
git clone -q "${TMP}/d.git" "${TMP}/d2"
echo other > "${TMP}/d2/other.txt"
git -C "${TMP}/d2" add -A
git -C "${TMP}/d2" -c user.name=t -c user.email=t@example.test commit -q -m other
git -C "${TMP}/d2" push -q origin main
MOVED="$(remote_head d)"
bump
commit 1.0.1 "#3" "${TMP}/d.git"
want_red "main moved on the remote" "was refused"
want_said "no tag or release was made" "no tag or release was made"
if [[ "$(remote_head d)" == "$MOVED" ]]; then echo "  ok: the remote main is unchanged"; else fail "the remote main changed"; fi

fresh e
commit
want_exit "no arguments" 2 "usage"
commit 1.0 "#3" "${TMP}/e.git"
want_exit "a malformed version" 2 "usage"
commit 1.0.1 "three" "${TMP}/e.git"
want_exit "a malformed issue list" 2 "usage"

# Mutation proofs.
mutant() {
  selftest_mutant "$COMMIT" "${TMP}/mut/$1/release_commit.sh" "$2" || return 1
  mkdir -p "$W/Scripts"
  cp "${TMP}/mut/$1/release_commit.sh" "$W/Scripts/mutant.sh"
  git -C "$W" add -N Scripts/mutant.sh
  SCRIPT="./Scripts/mutant.sh"
}

fresh m1
bump
if mutant nosignoff 's/commit -s -q/commit -q/'; then
  commit 1.0.1 "#3" "${TMP}/m1.git"
  line="$(git -C "$W" log -1 --format=%H) - $(git -C "$W" log -1 --format=%ae | base64 | tr -d '\n') $(git -C "$W" log -1 --format=%B | base64 | tr -d '\n')"
  printf '%s\n' "$line" > "${TMP}/dco.txt"
  capture "$W/Scripts/check_dco.sh" "${TMP}/dco.txt"
  want_red "mutation proof: without -s the DCO check refuses the commit" "Signed-off-by"
fi
unset SCRIPT

fresh m2
bump
if mutant nonames 's/\.\/Scripts\/check_private_names.sh --message - > \/dev\/null/true/'; then
  FORSGREN_PRIVATE_NAMES="bump to 1.0.1" commit 1.0.1 "#3" "${TMP}/m2.git"
  want_green "mutation proof: without the check a private name is committed" "OK: committed"
fi
unset SCRIPT

fresh m4
bump
if mutant noidentity 's/^GIT_AUTHOR_NAME=.* \\$//'; then
  GIT_AUTHOR_NAME=someone-else GIT_COMMITTER_NAME=someone-else commit 1.0.1 "#3" "${TMP}/m4.git"
  if [[ "$(git -C "$W" log -1 --format=%an)" == "someone-else" ]]; then
    echo "  ok: mutation proof: without the exported identity the leaked author wins"
  else
    fail "mutation proof: the mutant without the exported identity still has the bot as author"
  fi
fi
unset SCRIPT

fresh m3
git clone -q "${TMP}/m3.git" "${TMP}/m3b"
echo other > "${TMP}/m3b/other.txt"
git -C "${TMP}/m3b" add -A
git -C "${TMP}/m3b" -c user.name=t -c user.email=t@example.test commit -q -m other
git -C "${TMP}/m3b" push -q origin main
bump
if mutant force "s/git push -q \".REMOTE\"/git push -q --force \"${D}REMOTE\"/"; then
  commit 1.0.1 "#3" "${TMP}/m3.git"
  want_green "mutation proof: a forced push overwrites main, which the real script refuses" "OK: committed"
fi
unset SCRIPT

selftest_end "the release commit does not hold" "release commit: signed-off bot commit pushed to main, private names, empty trees and a moved main refused"
