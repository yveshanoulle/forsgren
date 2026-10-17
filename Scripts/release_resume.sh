#!/usr/bin/env bash
# Scripts/release_resume.sh
#
# Finds what a resumed Release run continues with (forsgren#221, the workflow
# input `resume`: pins or publish). A run that stopped after the release was
# published (the template or metrics step failed) cannot be started again: the
# version is no longer free. With `resume: pins` the workflow skips the plan,
# the bump, the commit, Quality and the publish, and does the two pin steps for
# the release that exists; this script says which one that is.
#
#   Scripts/release_resume.sh pins
#   Scripts/release_resume.sh publish
#       The run stopped after the bump commit was pushed but before the release
#       (Quality on that commit, or the publish, failed). A plain rerun cannot
#       work: the version in main.go is already the new one and the bump step
#       refuses a version that is not greater. With `resume: publish` the run
#       skips the plan, bump and commit, dispatches Quality on the bump commit
#       again, publishes it and does the pins. This mode finds that commit: the
#       version is the one in cmd/forsgren/main.go, it must have no tag and no
#       release, and its bump commit (subject `release X.Y.Z (1/1): bump to
#       X.Y.Z...`) must be in the last 200 commits and must BE main's head. If
#       main has moved past it the mode refuses, naming both commits: a release
#       is made only at its bump commit, so fix main and run a new release
#       instead. Output as for pins; the sha is the bump commit.
#
# Mode pins:
# It reads the latest release of GITHUB_REPOSITORY and requires: it exists, it
# is not a draft or a prerelease, its tag is vX.Y.Z, the tag exists, and the
# commit the tag points at (an annotated tag is followed) is the commit the
# release was created for, when the release names a commit. Output: `version=`,
# `tag=` and `sha=` lines and an OK line. Exit 0, 1 red, 2 usage (an argument,
# no GITHUB_REPOSITORY, an unknown mode). Self-test: Scripts/test_release_resume.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_resume.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

usage() {
  echo "usage: GITHUB_REPOSITORY=owner/name Scripts/release_resume.sh pins|publish" >&2
  COMPLETED=1
  exit 2
}

red() {
  echo "❌ FAIL: release resume: $*"
  COMPLETED=1
  exit 1
}

[ "$#" -eq 1 ] || usage
MODE="$1"
case "$MODE" in pins | publish) ;; *) usage ;; esac
cd "$(dirname "$0")/.." || exit 1
REPO="${GITHUB_REPOSITORY:-}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage

if [ "$MODE" = publish ]; then
  VERSION="$(sed -n 's/^var version = "\([0-9][0-9.]*\)"$/\1/p' cmd/forsgren/main.go | head -n 1)"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || red "cmd/forsgren/main.go has no var version = \"X.Y.Z\""
  ./Scripts/release_publish.sh free "$VERSION" > /dev/null \
    || red "${VERSION} has already a tag or a release: a run that stopped after the publish continues with resume = pins"
  BUMP_SHA="$(git log -n 200 --format='%H %s' | grep -E " release ${VERSION//./\\.} \\(1/1\\): bump to ${VERSION//./\\.}(,|$)" | head -n 1 | cut -d' ' -f1)"
  [[ "$BUMP_SHA" =~ ^[0-9a-f]{40}$ ]] || red "no bump commit for ${VERSION} in the last 200 commits of main: nothing to publish"
  HEAD_SHA="$(git rev-parse HEAD)"
  if [ "$HEAD_SHA" != "$BUMP_SHA" ]; then
    red "main's head ${HEAD_SHA} is not the bump commit ${BUMP_SHA}: main has moved past it. Fix main and run a new release instead (a release is made only at its bump commit)"
  fi
  echo "version=${VERSION}"
  echo "tag=v${VERSION}"
  echo "sha=${BUMP_SHA}"
  echo "OK: resuming v${VERSION} at ${BUMP_SHA} (the bump commit is main's head, no release yet)"
  COMPLETED=1
  exit 0
fi

LATEST="$(gh release view --repo "$REPO" --json tagName,isDraft,isPrerelease,targetCommitish \
  --jq '[.tagName, (.isDraft | tostring), (.isPrerelease | tostring), .targetCommitish] | @tsv' 2> /dev/null)" \
  || red "no latest release found in ${REPO}: nothing to resume"
[ -n "$LATEST" ] || red "no latest release found in ${REPO}: nothing to resume"
IFS="$(printf '\t')" read -r TAG DRAFT PRERELEASE TARGET <<< "$LATEST"

[[ "$TAG" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || red "the latest release's tag '${TAG}' is not a vX.Y.Z tag"
VERSION="${BASH_REMATCH[1]}"
if [ "$DRAFT" = true ]; then red "the release ${TAG} is a draft"; fi
if [ "$PRERELEASE" = true ]; then red "the release ${TAG} is a prerelease"; fi

REF="$(gh api "repos/${REPO}/git/ref/tags/${TAG}" --jq '.object.type + " " + .object.sha' 2> /dev/null)" \
  || red "the release ${TAG} has no tag in ${REPO}"
TYPE="${REF%% *}"
SHA="${REF#* }"
if [ "$TYPE" = tag ]; then
  SHA="$(gh api "repos/${REPO}/git/tags/${SHA}" --jq '.object.sha' 2> /dev/null)" \
    || red "cannot follow the annotated tag ${TAG}"
fi
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || red "the tag ${TAG} points at '${SHA}', not at a commit"

if [[ "$TARGET" =~ ^[0-9a-f]{40}$ ]]; then
  [ "$TARGET" = "$SHA" ] || red "the tag ${TAG} is at ${SHA}, but the release targets ${TARGET}"
fi

echo "version=${VERSION}"
echo "tag=${TAG}"
echo "sha=${SHA}"
echo "OK: resuming ${TAG} at ${SHA}"
COMPLETED=1
