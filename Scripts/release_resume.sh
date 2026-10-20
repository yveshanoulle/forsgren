#!/usr/bin/env bash
# Scripts/release_resume.sh
#
# Finds what a resumed Release run continues with (forsgren#221, the workflow
# input `resume: pins`). A run that stopped after the release was published
# (the install check, the template or the metrics step failed) cannot be
# started again: the version is no longer free. With `resume: pins` the
# workflow skips Quality, the plan, the head check and the publish, and runs
# the install check and the two pin steps for the release that exists; this
# script says which one that is.
#
#   Scripts/release_resume.sh pins
#
# There is no resume: publish (forsgren#237, step 5b): the release tags the
# Quality-green head of main and nothing is committed first, so a run that
# stopped before the publish made nothing and is started again.
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
  echo "usage: GITHUB_REPOSITORY=owner/name Scripts/release_resume.sh pins" >&2
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
case "$MODE" in pins) ;; *) usage ;; esac
cd "$(dirname "$0")/.." || exit 1
REPO="${GITHUB_REPOSITORY:-}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage

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
