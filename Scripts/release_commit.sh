#!/usr/bin/env bash
# Scripts/release_commit.sh
#
# The bump commit of a release, for the Release workflow (forsgren#221, step 2
# of 2): the version bump is in the working tree (Scripts/release_bump.sh);
# this commits it as github-actions[bot] with a DCO sign-off and pushes it to
# main.
#
# Usage: Scripts/release_commit.sh <version> <issues> <remote>
#   <issues>  the issue numbers of the release, "#209 #210", as release_plan.sh
#             prints them on its issues= line
#   <remote>  where to push: a URL (the workflow's carries the job's token and
#             is never printed) or a remote name
#
# The subject is `release X.Y.Z (1/1): bump to X.Y.Z, #209 #210`, the shape of
# the manual bump commits; `git commit -s` adds the sign-off as the last
# paragraph, the author's own, which is what Scripts/check_dco.sh asks of a
# push to main. The message goes through Scripts/check_private_names.sh
# --message before anything is committed. Only changes to tracked files are
# committed; an untracked file or no change at all is a red. The push is a
# plain fast-forward of main: if main moved since the run began, it is
# refused, and nothing on main has changed.
# The branch is main unless RELEASE_BRANCH says otherwise (the self-test).
#
# Output: `sha=<commit>` and an OK line. Exit 0 pushed, 1 refused or red,
# 2 usage. Self-test: Scripts/test_release_commit.sh (a local bare remote).

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_commit.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

cd "$(dirname "$0")/.." || exit 1

usage() {
  echo "usage: Scripts/release_commit.sh <version> <issues> <remote>" >&2
  COMPLETED=1
  exit 2
}

red() {
  echo "❌ FAIL: release commit: $*"
  COMPLETED=1
  exit 1
}

[ "$#" -eq 3 ] || usage
VERSION="$1"
ISSUES="$2"
REMOTE="$3"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[[ "$ISSUES" =~ ^(#[0-9]+)?( #[0-9]+)*$ ]] || usage
[ -n "$REMOTE" ] || usage
BRANCH="${RELEASE_BRANCH:-main}"

SUBJECT="release ${VERSION} (1/1): bump to ${VERSION}${ISSUES:+, ${ISSUES}}"

printf '%s\n' "$SUBJECT" | ./Scripts/check_private_names.sh --message - > /dev/null \
  || red "the commit message does not pass Scripts/check_private_names.sh --message, nothing was committed"

if [ -n "$(git status --porcelain --untracked-files=all | grep '^??' || true)" ]; then
  red "the bump left untracked files, nothing was committed: $(git status --porcelain --untracked-files=all | grep '^??' | head -3 | tr '\n' ' ')"
fi
git add -u || red "git add failed"
if git diff --cached --quiet; then
  red "the working tree holds no change to commit: the bump did nothing"
fi

NAME="github-actions[bot]"
EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
# The four GIT_* variables win over git config, and a wrapper such as FBP
# exports its own user's identity in them: the script sets them itself, so
# the bot is the author, the committer and the sign-off wherever it runs.
GIT_AUTHOR_NAME="$NAME" GIT_AUTHOR_EMAIL="$EMAIL" GIT_COMMITTER_NAME="$NAME" GIT_COMMITTER_EMAIL="$EMAIL" \
  git -c "user.name=${NAME}" -c "user.email=${EMAIL}" commit -s -q -m "$SUBJECT" \
  || red "git commit failed"
SHA="$(git rev-parse HEAD)"

if ! GIT_TERMINAL_PROMPT=0 git push -q "$REMOTE" "HEAD:refs/heads/${BRANCH}" > /dev/null 2>&1; then
  red "the push of ${SHA} to ${BRANCH} was refused (has ${BRANCH} moved since the run began?): nothing on ${BRANCH} changed, no tag or release was made"
fi

echo "sha=${SHA}"
echo "OK: committed and pushed ${SHA} to ${BRANCH}: ${SUBJECT}"
COMPLETED=1
