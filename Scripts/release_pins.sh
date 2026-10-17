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
# Both are idempotent, so a resumed run (the Release workflow's `resume: pins`)
# can repeat them: a repository that already pins the version, or a pull request
# for it that is open or merged (any of those listed, in any order), is "already
# done" and exit 0, not an error. A pull request closed without merging is named
# in a note and a new one is opened (the branch reused or moved when it exists).
# A 403 names the permission: a fine-grained token needs Workflows: Read and write
# to write the workflow files, besides Contents and, for the pull request, Pull
# requests.
# Both need the secret FORSGREN_RELEASE_TOKEN in the environment: a fine-grained
# token, contents and workflows write on forsgren-template, contents, workflows and
# pull-requests write on forsgren-metrics. Without it the step fails with a ::error:: line naming the
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
  echo "::error::FORSGREN_RELEASE_TOKEN is not set: the secret is a fine-grained token with Contents and Workflows read and write on forsgren-template, and Contents, Workflows and Pull requests read and write on forsgren-metrics (docs/updating-and-releases.md). The ${MODE} step did not run."
  COMPLETED=1
  exit 1
fi
if [ "$MODE" = token ]; then
  echo "OK: FORSGREN_RELEASE_TOKEN is set"
  COMPLETED=1
  exit 0
fi
command -v jq > /dev/null || red "jq is not installed"

WORK="$(mktemp -d)"
ERRFILE="${WORK}/gh.err"

# ghr: gh with the release token; gh's stderr is shown and also kept, so a
# refusal can be explained (hint).
ghr() {
  local rc=0
  GH_TOKEN="$TOKEN" gh "$@" 2> "$ERRFILE" || rc=$?
  cat "$ERRFILE" >&2
  return "$rc"
}

# hint <repo>: the cause to add to a red when gh was refused with a 403. A
# fine-grained token needs Workflows: Read and write to write a file under
# .github/workflows, besides Contents and Pull requests.
hint() {
  if grep -qE 'HTTP 403|Resource not accessible' "$ERRFILE" 2> /dev/null; then
    printf ' (HTTP 403: the token needs Workflows: Read and write on %s, because the commit changes .github/workflows files, besides Contents: Read and write and, for forsgren-metrics, Pull requests: Read and write)' "$1"
  fi
}
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
if [ "$ENTRIES" = "[]" ]; then
  echo "OK: already done: ${TARGET} already pins ${VERSION}"
  COMPLETED=1
  exit 0
fi

# A metrics pull request from an earlier run: any open or merged one for the
# release branch means the step is done, whatever order they are listed in. One
# closed without merging is not: a new pull request is opened for it.
BRANCH="forsgren-release-v${VERSION}"
if [ "$MODE" = metrics ]; then
  PRS="$(ghr pr list --repo "$TARGET" --head "$BRANCH" --state all --json url,state \
    --jq '.[] | [.url, .state] | @tsv')" || red "cannot list the pull requests of ${TARGET}$(hint "$TARGET")"
  tab="$(printf '\t')"
  while IFS="$tab" read -r pr_url pr_state; do
    [ -n "$pr_url" ] || continue
    case "$pr_state" in
      OPEN | MERGED)
        echo "OK: already done: pull request ${pr_url} (${pr_state})"
        COMPLETED=1
        exit 0
        ;;
      *) echo "note: pull request ${pr_url} was closed without merging; opening a new one" ;;
    esac
  done <<< "$PRS"
fi

NEWTREE="$(jq -n --arg b "$TREE" --argjson e "$ENTRIES" '{base_tree: $b, tree: $e}' | ghr api "repos/${TARGET}/git/trees" --input - --jq '.sha')" \
  || red "cannot create the tree in ${TARGET}$(hint "$TARGET")"
COMMIT="$(jq -n --arg m "$MESSAGE" --arg t "$NEWTREE" --arg p "$BASE" '{message: $m, tree: $t, parents: [$p]}' | ghr api "repos/${TARGET}/git/commits" --input - --jq '.sha')" \
  || red "cannot create the commit in ${TARGET}$(hint "$TARGET")"

if [ "$MODE" = template ]; then
  jq -n --arg s "$COMMIT" '{sha: $s}' | ghr api -X PATCH "repos/${TARGET}/git/refs/heads/${DEFAULT}" --input - > /dev/null \
    || red "cannot move ${DEFAULT} of ${TARGET} to ${COMMIT} (a fast-forward only; has it moved?): the commit exists but nothing is pinned$(hint "$TARGET")"
  echo "OK: ${TARGET} ${DEFAULT} now pins ${VERSION} (${COMMIT})"
else
  # The branch may be left from a pull request closed without merging: reuse
  # it when it holds these pins, else move it to the new commit (it is this
  # release's own branch), else create it.
  if OLD="$(GH_TOKEN="$TOKEN" gh api "repos/${TARGET}/git/ref/heads/${BRANCH}" --jq '.object.sha' 2> /dev/null)" && [ -n "$OLD" ]; then
    OLDTREE="$(ghr api "repos/${TARGET}/git/commits/${OLD}" --jq '.tree.sha')" || red "cannot read the branch ${BRANCH} of ${TARGET}$(hint "$TARGET")"
    if [ "$OLDTREE" = "$NEWTREE" ]; then
      echo "note: branch ${BRANCH} already holds these pins; reusing it"
    else
      echo "note: branch ${BRANCH} holds other content; moving it to ${COMMIT}"
      jq -n --arg s "$COMMIT" '{sha: $s, force: true}' | ghr api -X PATCH "repos/${TARGET}/git/refs/heads/${BRANCH}" --input - > /dev/null \
        || red "cannot move the branch ${BRANCH} of ${TARGET}$(hint "$TARGET")"
    fi
  else
    jq -n --arg r "refs/heads/${BRANCH}" --arg s "$COMMIT" '{ref: $r, sha: $s}' | ghr api "repos/${TARGET}/git/refs" --input - > /dev/null \
      || red "cannot create the branch ${BRANCH} in ${TARGET}$(hint "$TARGET")"
  fi
  URL="$(ghr pr create --repo "$TARGET" --base "$DEFAULT" --head "$BRANCH" --title "forsgren: bump to ${VERSION}" \
    --body "Moves the forsgren pins to release v${VERSION} (${SHA}). Opened by the Release workflow of ${REPO}.")" \
    || red "the branch ${BRANCH} was pushed to ${TARGET}, but the pull request could not be opened$(hint "$TARGET")"
  echo "OK: ${TARGET} pull request for ${VERSION}: ${URL}"
fi
COMPLETED=1
