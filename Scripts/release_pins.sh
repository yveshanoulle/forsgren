#!/usr/bin/env bash
# Scripts/release_pins.sh
#
# Moves the forsgren pins of the two public repositories that follow a release
# (forsgren#221, step 2 of 2), the way the manual release does it today:
#
#   Scripts/release_pins.sh rewrite <workflow|readme> <version> <sha>
#       stdin to stdout, the pure part. A workflow file: each `uses:` line of
#       this repository's reusable workflows becomes `@<sha> # vX.Y.Z`, and
#       "pinned by the commit of release vX.Y.Z" in the comments names the new
#       release (also when the comment wraps after "release"). A README: "written
#       by the daily run for forsgren X.Y.Z" names the new version. A file with
#       no such place is a red: a changed layout must never skip a pin silently.
#   Scripts/release_pins.sh token
#       Red (::error::) when FORSGREN_RELEASE_TOKEN is not set. The Release
#       workflow runs it first, so a missing secret stops the run before
#       anything is pushed, and template and metrics check it again.
#   Scripts/release_pins.sh template <version> <sha>
#       forsgren-template: its two workflow files and its README in ONE commit
#       ("forsgren X.Y.Z: pin and README") on the default branch, through the
#       git-data API (blobs, tree, commit, then a fast-forward of the branch).
#   Scripts/release_pins.sh metrics <version> <sha>
#       forsgren-metrics: its two workflow files in one commit on a new branch
#       forsgren-release-vX.Y.Z, and a pull request into the default branch.
#
# The two repositories are <owner>/forsgren-template and <owner>/forsgren-metrics,
# the owner being that of GITHUB_REPOSITORY (the repository that is released);
# RELEASE_TEMPLATE_REPO and RELEASE_METRICS_REPO override them (the self-test).
# Both need the secret FORSGREN_RELEASE_TOKEN in the environment: a fine-grained
# token, contents write on forsgren-template, contents and pull-requests write on
# forsgren-metrics. Without it the step fails with a ::error:: line naming the
# secret and what it needs; it never skips and never falls back to the job's
# own token, which cannot write to another repository.
# Exit 0 done, 1 red, 2 usage. Self-test: Scripts/test_release_pins.sh (a stub gh).

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_pins.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

usage() {
  echo "usage: Scripts/release_pins.sh token | rewrite <workflow|readme> <version> <sha> | template <version> <sha> | metrics <version> <sha>" >&2
  COMPLETED=1
  exit 2
}

red() {
  echo "❌ FAIL: release pins: $*"
  COMPLETED=1
  exit 1
}

MODE="${1:-}"
case "$MODE" in
  token) [ "$#" -eq 1 ] || usage ;;
  rewrite) [ "$#" -eq 4 ] || usage; KIND="$2"; shift ;;
  template | metrics) [ "$#" -eq 3 ] || usage ;;
  *) usage ;;
esac
VERSION="${2:-}"
SHA="${3:-}"
[ "$MODE" = token ] || [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[ "$MODE" = token ] || [[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || usage
REPO="${GITHUB_REPOSITORY:-}"
[ "$MODE" = token ] || [[ "$REPO" =~ ^([A-Za-z0-9_.-]+)/[A-Za-z0-9_.-]+$ ]] || usage
OWNER="${BASH_REMATCH[1]:-}"

# rewrite <kind>: stdin to stdout.
rewrite() {
  case "$1" in
    workflow)
      PIN_REPO="$REPO" PIN_VERSION="$VERSION" PIN_SHA="$SHA" perl -0777 -pe '
        s{(uses:\s*\Q$ENV{PIN_REPO}\E/\.github/workflows/[A-Za-z_]+\.yml)@[0-9a-f]{40}\s+#\s*v[0-9]+\.[0-9]+\.[0-9]+}{$1\@$ENV{PIN_SHA} # v$ENV{PIN_VERSION}}g;
        s{(commit of release\s+(?:#\s+)?)v[0-9]+\.[0-9]+\.[0-9]+}{$1v$ENV{PIN_VERSION}}g;'
      ;;
    readme)
      PIN_VERSION="$VERSION" perl -0777 -pe 's{(written by the daily run for forsgren )[0-9]+\.[0-9]+\.[0-9]+}{$1$ENV{PIN_VERSION}}g;'
      ;;
    *) usage ;;
  esac
}

# pinned <kind> <file>: 0 when the rewritten file holds the new pin.
pinned() {
  case "$1" in
    workflow) grep -qF "@${SHA} # v${VERSION}" "$2" ;;
    readme) grep -qF "written by the daily run for forsgren ${VERSION}" "$2" ;;
  esac
}

if [ "$MODE" = rewrite ]; then
  case "$KIND" in workflow | readme) ;; *) usage ;; esac
  TMPIN="$(mktemp)"
  TMPOUT="$(mktemp)"
  trap 'rm -f "$TMPIN" "$TMPOUT"; [ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_pins.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT
  cat > "$TMPIN"
  rewrite "$KIND" < "$TMPIN" > "$TMPOUT" || red "perl failed"
  pinned "$KIND" "$TMPOUT" || red "the ${KIND} file has no place that names the release: a pin would be skipped"
  cat "$TMPOUT"
  COMPLETED=1
  exit 0
fi

# From here: template or metrics, with the token.
TOKEN="${FORSGREN_RELEASE_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  echo "::error::FORSGREN_RELEASE_TOKEN is not set: the secret is a fine-grained token with contents write on forsgren-template and contents and pull-requests write on forsgren-metrics (docs/updating-and-releases.md). The ${MODE} step did not run."
  COMPLETED=1
  exit 1
fi
if [ "$MODE" = token ]; then
  echo "OK: FORSGREN_RELEASE_TOKEN is set"
  COMPLETED=1
  exit 0
fi
command -v jq > /dev/null || red "jq is not installed"

ghr() { GH_TOKEN="$TOKEN" gh "$@"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; [ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_pins.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

if [ "$MODE" = template ]; then
  TARGET="${RELEASE_TEMPLATE_REPO:-${OWNER}/forsgren-template}"
  FILES="workflow:.github/workflows/forsgren.yml workflow:.github/workflows/forsgren-update.yml readme:README.md"
  MESSAGE="forsgren ${VERSION}: pin and README"
else
  TARGET="${RELEASE_METRICS_REPO:-${OWNER}/forsgren-metrics}"
  FILES="workflow:.github/workflows/forsgren.yml workflow:.github/workflows/forsgren-update.yml"
  MESSAGE="forsgren: bump to ${VERSION}"
fi

DEFAULT="$(ghr api "repos/${TARGET}" --jq '.default_branch')" || red "cannot read ${TARGET}: does the token reach it?"
[ -n "$DEFAULT" ] || red "${TARGET} has no default branch"
BASE="$(ghr api "repos/${TARGET}/git/ref/heads/${DEFAULT}" --jq '.object.sha')" || red "cannot read ${DEFAULT} of ${TARGET}"
TREE="$(ghr api "repos/${TARGET}/git/commits/${BASE}" --jq '.tree.sha')" || red "cannot read the commit ${BASE} of ${TARGET}"

ENTRIES="[]"
for spec in $FILES; do
  kind="${spec%%:*}"
  path="${spec#*:}"
  ghr api "repos/${TARGET}/contents/${path}?ref=${BASE}" --jq '.content' | base64 --decode > "${WORK}/old" \
    || red "cannot read ${path} of ${TARGET}"
  rewrite "$kind" < "${WORK}/old" > "${WORK}/new" || red "perl failed on ${path}"
  pinned "$kind" "${WORK}/new" || red "${TARGET}:${path} has no place that names the release: a pin would be skipped, nothing was changed"
  if cmp -s "${WORK}/old" "${WORK}/new"; then
    echo "  unchanged: ${path} (already at ${VERSION})"
    continue
  fi
  blob="$(jq -n --rawfile c "${WORK}/new" '{content: $c, encoding: "utf-8"}' | ghr api "repos/${TARGET}/git/blobs" --input - --jq '.sha')" \
    || red "cannot create the blob of ${path} in ${TARGET}"
  ENTRIES="$(jq -c --arg p "$path" --arg s "$blob" '. + [{path: $p, mode: "100644", type: "blob", sha: $s}]' <<< "$ENTRIES")"
  echo "  changed: ${path}"
done
[ "$ENTRIES" != "[]" ] || red "no file of ${TARGET} needed a change: is ${VERSION} already pinned there?"

NEWTREE="$(jq -n --arg b "$TREE" --argjson e "$ENTRIES" '{base_tree: $b, tree: $e}' | ghr api "repos/${TARGET}/git/trees" --input - --jq '.sha')" \
  || red "cannot create the tree in ${TARGET}"
COMMIT="$(jq -n --arg m "$MESSAGE" --arg t "$NEWTREE" --arg p "$BASE" '{message: $m, tree: $t, parents: [$p]}' | ghr api "repos/${TARGET}/git/commits" --input - --jq '.sha')" \
  || red "cannot create the commit in ${TARGET}"

if [ "$MODE" = template ]; then
  jq -n --arg s "$COMMIT" '{sha: $s}' | ghr api -X PATCH "repos/${TARGET}/git/refs/heads/${DEFAULT}" --input - > /dev/null \
    || red "cannot move ${DEFAULT} of ${TARGET} to ${COMMIT} (a fast-forward only; has it moved?): the commit exists but nothing is pinned"
  echo "OK: ${TARGET} ${DEFAULT} now pins ${VERSION} (${COMMIT})"
else
  BRANCH="forsgren-release-v${VERSION}"
  jq -n --arg r "refs/heads/${BRANCH}" --arg s "$COMMIT" '{ref: $r, sha: $s}' | ghr api "repos/${TARGET}/git/refs" --input - > /dev/null \
    || red "cannot create the branch ${BRANCH} in ${TARGET} (does it exist from an earlier run?)"
  URL="$(ghr pr create --repo "$TARGET" --base "$DEFAULT" --head "$BRANCH" --title "forsgren: bump to ${VERSION}" \
    --body "Moves the forsgren pins to release v${VERSION} (${SHA}). Opened by the Release workflow of ${REPO}.")" \
    || red "the branch ${BRANCH} was pushed to ${TARGET}, but the pull request could not be opened"
  echo "OK: ${TARGET} pull request for ${VERSION}: ${URL}"
fi
COMPLETED=1
