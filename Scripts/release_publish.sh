#!/usr/bin/env bash
# Scripts/release_publish.sh
#
# The tag and the GitHub release, for the Release workflow (forsgren#221, step
# 2 of 2).
#
#   Scripts/release_publish.sh free <version>
#       Red when the tag vX.Y.Z or a release for it already exists. Run before
#       the bump commit is pushed, so a version that was released (or half
#       released) is never bumped again.
#   Scripts/release_publish.sh create <version> <sha> <notes-file>
#       `gh release create vX.Y.Z --target <sha> --latest` with the notes. The
#       tag is made only by this one call, with the release it belongs to, so a
#       tag never exists without its release; if the call fails, the script
#       looks for a tag it may have left and says so rather than hiding it.
#
# Needs GITHUB_REPOSITORY (owner/name) and gh's GH_TOKEN. Exit 0 done, 1 red,
# 2 usage. Self-test: Scripts/test_release_publish.sh (a stub gh).

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_publish.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

usage() {
  echo "usage: Scripts/release_publish.sh free <version> | create <version> <sha> <notes-file>" >&2
  COMPLETED=1
  exit 2
}

red() {
  echo "❌ FAIL: release publish: $*"
  COMPLETED=1
  exit 1
}

MODE="${1:-}"
VERSION="${2:-}"
case "$MODE" in
  free) [ "$#" -eq 2 ] || usage ;;
  create) [ "$#" -eq 4 ] || usage ;;
  *) usage ;;
esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
REPO="${GITHUB_REPOSITORY:-}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
TAG="v${VERSION}"

# tag_exists: 0 when the repository has the exact tag (matching-refs matches prefixes).
tag_exists() {
  local found
  found="$(gh api "repos/${REPO}/git/matching-refs/tags/${TAG}" --jq ".[] | select(.ref == \"refs/tags/${TAG}\") | .ref")" \
    || red "gh could not look up the tag ${TAG}"
  [ -n "$found" ]
}

release_exists() {
  gh release view "$TAG" --repo "$REPO" --json tagName --jq '.tagName' > /dev/null 2>&1
}

if [ "$MODE" = free ]; then
  if tag_exists; then red "the tag ${TAG} already exists, ${VERSION} is not a new version"; fi
  if release_exists; then red "a release ${TAG} already exists, ${VERSION} is not a new version"; fi
  echo "OK: ${TAG} is free: no tag and no release of that name"
  COMPLETED=1
  exit 0
fi

SHA="$3"
NOTES="$4"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || usage
[ -s "$NOTES" ] || red "the notes file ${NOTES} is missing or empty, nothing was created"

if gh release create "$TAG" --repo "$REPO" --target "$SHA" --title "forsgren ${VERSION}" \
  --notes-file "$NOTES" --latest; then
  release_exists || red "gh release create said it was done, but release ${TAG} cannot be read"
  echo "OK: released ${TAG} at ${SHA}, marked Latest"
  COMPLETED=1
  exit 0
fi

if tag_exists; then
  red "gh release create failed and the tag ${TAG} exists: a tag without its release, to be deleted by hand before the next run"
fi
red "gh release create failed; no tag ${TAG} was left behind"
