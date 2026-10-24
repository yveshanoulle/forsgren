#!/usr/bin/env bash
# Scripts/release_verify_install.sh
#
# After a release is published and before any pin moves (forsgren#237, step 5a):
# `go install github.com/<owner>/<name>/cmd/forsgren@<sha>` of the released sha
# must report the release, vX.Y.Z, as its module version, not a pseudo-version.
# The pins of an installation name a commit, and with no bump commit the version
# an installation shows comes from the go tool's build information for that
# commit, which is the tag only when the tag is known to the module proxy.
#
# Usage: Scripts/release_verify_install.sh <X.Y.Z> <sha>   (GITHUB_REPOSITORY=owner/name)
# The install goes to a temporary GOBIN, GOPATH and GOCACHE, never the caller's.
# The module proxy may lag the tag: the check is repeated RELEASE_VERIFY_TRIES
# times (default 5), RELEASE_VERIFY_DELAY seconds apart (default 30). A failure
# prints an ::error:: that says what installations show meanwhile (dev, a
# development build that names no release), that `resume: pins` reruns the
# check and that no pin may move before it passes.
# Exit: 0 reports the release, 1 red, 2 usage. Self-test:
# Scripts/test_release_verify_install.sh (a stub go).

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_verify_install.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

usage() {
  echo "usage: GITHUB_REPOSITORY=owner/name Scripts/release_verify_install.sh <X.Y.Z> <sha>" >&2
  COMPLETED=1
  exit 2
}

[ "$#" -eq 2 ] || usage
VERSION="$1"
SHA="$2"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || usage
REPO="${GITHUB_REPOSITORY:-}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
TRIES="${RELEASE_VERIFY_TRIES:-5}"
DELAY="${RELEASE_VERIFY_DELAY:-30}"
[[ "$TRIES" =~ ^[1-9][0-9]*$ && "$DELAY" =~ ^[0-9]+$ ]] || usage
cd "$(dirname "$0")/.." || exit 1

WORK="$(mktemp -d "${TMPDIR:-/tmp}/forsgren-verify.XXXXXX")"
trap 'rm -rf "$WORK"; [ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_verify_install.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

fail() {
  echo "$1"
  COMPLETED=1
  exit 1
}

found=""
try=0
while [ "$try" -lt "$TRIES" ]; do
  try=$((try + 1))
  rm -rf "${WORK:?}/bin"
  if ! (cd "$WORK" && GOBIN="${WORK}/bin" GOPATH="${WORK}/gopath" GOCACHE="${WORK}/cache" \
    go install "github.com/${REPO}/cmd/forsgren@${SHA}" > "${WORK}/install.log" 2>&1); then
    fail "❌ FAIL: release verify install: go install failed for ${REPO} at ${SHA}: $(tail -n 5 "${WORK}/install.log")"
  fi
  found="$(go version -m "${WORK}/bin/forsgren" | sed -n 's/^[[:space:]]*mod[[:space:]][^[:space:]]*[[:space:]]\([^[:space:]]*\).*/\1/p' | head -n 1)"
  if [ "$found" = "v${VERSION}" ]; then
    echo "OK: go install at ${SHA} reports v${VERSION} (try ${try})"
    COMPLETED=1
    exit 0
  fi
  if [ "$try" -lt "$TRIES" ]; then sleep "$DELAY"; fi
done
echo "::error::❌ go install of ${REPO} at ${SHA} reports ${found:-no module version}, not v${VERSION}, after ${TRIES} tries. Until it reports the release, installations show dev (a development build that names no release; forsgren#340), not ${VERSION}. Do not move any pin onto this sha: run the release again with resume: pins, which reruns this check, once the module proxy knows the tag."
fail "❌ FAIL: release verify install: ${SHA} reports ${found:-no module version}, not v${VERSION}, after ${TRIES} tries"
