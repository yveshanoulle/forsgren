#!/usr/bin/env bash
# Scripts/release_metrics.sh
#
# Finishes the metrics update of a release (forsgren#221, step 5): the release
# is done only when the metrics site runs the new version. After
# Scripts/release_pins.sh metrics opened (or found) the pin pull request in
# forsgren-metrics, this
#   1. finds the pull request of the release branch forsgren-release-vX.Y.Z (a
#      MERGED one first, else an OPEN one; closed ones do not count),
#   2. for an OPEN one reads its files with Scripts/release_verify_pin.sh (only
#      the forsgren pins of both callers, to this release's sha: any other
#      change is a red and nothing is merged) and squash-merges it, deleting
#      its branch, as the auto-update workflow does,
#   3. makes sure a run of forsgren.yml that started AFTER the merge is green on
#      the default branch: a green one is done; one still going is waited for;
#      none (or only red ones) starts one with workflow_dispatch and waits for
#      it. The wait is bounded: RELEASE_METRICS_TRIES polls (default 40) of
#      RELEASE_METRICS_DELAY seconds (default 30), about 20 minutes.
# It is safe to repeat (a resumed run): a merged pull request skips to step 3,
# a green run after the merge is "already done", and no second run is started
# while one is green or going. With no pull request at all it accepts pins that
# are already on the default branch (merged another way) and judges the runs
# after the commit that changed forsgren.yml; otherwise it is a red.
# Output: `pull=<number>`, `run=<url>`, then `OK: metrics: PR #N merged, forsgren
# run <url> green`. Red: a ❌ line with the run's URL when the run failed.
#
# Usage: Scripts/release_metrics.sh <version> <sha>. Needs FORSGREN_RELEASE_TOKEN
# (Contents, Pull requests and Actions read and write, Workflows on the
# repository) and GITHUB_REPOSITORY; RELEASE_METRICS_REPO overrides
# <owner>/forsgren-metrics. Exit 0 done, 1 red, 2 usage.
# Self-test: Scripts/test_release_metrics.sh (a stub gh).

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_metrics.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

cd "$(dirname "$0")/.." || exit 1

usage() {
  echo "usage: Scripts/release_metrics.sh <version> <sha>" >&2
  COMPLETED=1
  exit 2
}

red() {
  echo "❌ FAIL: release metrics: $*"
  COMPLETED=1
  exit 1
}

[ "$#" -eq 2 ] || usage
VERSION="$1"
SHA="$2"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || usage
REPO="${GITHUB_REPOSITORY:-}"
[[ "$REPO" =~ ^([A-Za-z0-9_.-]+)/[A-Za-z0-9_.-]+$ ]] || usage
OWNER="${BASH_REMATCH[1]}"
TARGET="${RELEASE_METRICS_REPO:-${OWNER}/forsgren-metrics}"
TRIES="${RELEASE_METRICS_TRIES:-40}"
DELAY="${RELEASE_METRICS_DELAY:-30}"
[[ "$TRIES" =~ ^[1-9][0-9]*$ && "$DELAY" =~ ^[0-9]+$ ]] || usage

TOKEN="${FORSGREN_RELEASE_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  echo "::error::FORSGREN_RELEASE_TOKEN is not set: the metrics step needs the fine-grained token (docs/updating-and-releases.md). The step did not run."
  COMPLETED=1
  exit 1
fi
ghr() { GH_TOKEN="$TOKEN" gh "$@"; }

BRANCH="forsgren-release-v${VERSION}"
DEFAULT="$(ghr api "repos/${TARGET}" --jq '.default_branch')" || red "cannot read ${TARGET}: does the token reach it?"
[ -n "$DEFAULT" ] || red "${TARGET} has no default branch"

# 1. The pull request of the release branch.
PRS="$(ghr pr list --repo "$TARGET" --head "$BRANCH" --state all --json number,state,url,mergedAt \
  --jq '.[] | [.number, .state, .url, (.mergedAt // "")] | @tsv')" || red "cannot list the pull requests of ${TARGET}"
MERGED_LINE=""
OPEN_LINE=""
while IFS= read -r row; do
  [ -n "$row" ] || continue
  state="$(printf '%s' "$row" | cut -f2)"
  if [ "$state" = MERGED ] && [ -z "$MERGED_LINE" ]; then MERGED_LINE="$row"; fi
  if [ "$state" = OPEN ] && [ -z "$OPEN_LINE" ]; then OPEN_LINE="$row"; fi
done <<< "$PRS"

PULL=""
CUTOFF=""
if [ -n "$MERGED_LINE" ]; then
  PULL="$(printf '%s' "$MERGED_LINE" | cut -f1)"
  CUTOFF="$(printf '%s' "$MERGED_LINE" | cut -f4)"
  echo "pull request #${PULL} is already merged"
elif [ -n "$OPEN_LINE" ]; then
  PULL="$(printf '%s' "$OPEN_LINE" | cut -f1)"
  # 2. Only the pins, or nothing is merged.
  ghr api --paginate "repos/${TARGET}/pulls/${PULL}/files" \
    | ./Scripts/release_verify_pin.sh "$VERSION" "$SHA" \
    || red "pull request #${PULL} changes more than the forsgren pins of this release: it was not merged"
  ghr pr merge "$PULL" --repo "$TARGET" --squash --delete-branch > /dev/null \
    || red "pull request #${PULL} could not be merged"
  CUTOFF="$(ghr pr view "$PULL" --repo "$TARGET" --json mergedAt --jq '.mergedAt')" \
    || red "cannot read when pull request #${PULL} was merged"
  [ -n "$CUTOFF" ] || red "pull request #${PULL} was merged, but GitHub names no merge time"
  echo "pull request #${PULL} merged"
else
  PINNED="$(ghr api "repos/${TARGET}/contents/.github/workflows/forsgren.yml?ref=${DEFAULT}" --jq '.content' | base64 --decode | grep -cF "@${SHA} # v${VERSION}" || true)"
  [ "${PINNED:-0}" -ge 1 ] || red "no pull request for ${BRANCH} in ${TARGET}, and ${DEFAULT} does not pin v${VERSION}: open the pin pull request first"
  CUTOFF="$(ghr api "repos/${TARGET}/commits?path=.github/workflows/forsgren.yml&per_page=1" --jq '.[0].commit.committer.date')" \
    || red "cannot read when forsgren.yml changed in ${TARGET}"
  echo "${DEFAULT} of ${TARGET} already pins v${VERSION}; judging the runs after ${CUTOFF}"
fi

# 3. A green forsgren.yml run after the merge.
# runs: the forsgren.yml runs on the default branch, newest first, as
# id, status, conclusion, url and creation time lines, split by a unit
# separator (a tab is white space to read, which would swallow an empty
# conclusion).
SEP="$(printf '\037')"
runs() {
  ghr run list --repo "$TARGET" --workflow forsgren.yml --branch "$DEFAULT" --limit 30 \
    --json databaseId,status,conclusion,url,createdAt \
    --jq '.[] | [.databaseId, .status, (.conclusion // ""), .url, .createdAt] | @tsv' \
    | tr '\t' "$SEP" || red "cannot list the forsgren.yml runs of ${TARGET}"
}
# after_cutoff <createdAt>: 0 when the run started after the merge.
after_cutoff() { [[ "$1" > "$CUTOFF" ]]; }

finish() {
  echo "pull=${PULL:-none}"
  echo "run=$1"
  echo "OK: metrics: PR #${PULL:-none} merged, forsgren run $1 green"
  COMPLETED=1
  exit 0
}

RUNS="$(runs)" || { printf '%s\n' "$RUNS"; COMPLETED=1; exit 1; }
GOING=""
BEFORE=""
while IFS="$SEP" read -r id status conclusion url created; do
  [ -n "$id" ] || continue
  BEFORE="${BEFORE} ${id} "
  after_cutoff "$created" || continue
  if [ "$status" = completed ] && [ "$conclusion" = success ]; then
    echo "a forsgren.yml run after the merge is already green"
    finish "$url"
  elif [ "$status" != completed ] && [ -z "$GOING" ]; then
    GOING="$id"
  fi
done <<< "$RUNS"

if [ -z "$GOING" ]; then
  ghr workflow run forsgren.yml --repo "$TARGET" --ref "$DEFAULT" || red "cannot start forsgren.yml in ${TARGET} (does the token have Actions: Read and write?)"
  echo "started forsgren.yml in ${TARGET} on ${DEFAULT}"
fi

# Wait for the run: the one going, or the new one the dispatch makes.
try=0
while [ "$try" -lt "$TRIES" ]; do
  try=$((try + 1))
  FOUND=""
  RUNS="$(runs)" || { printf '%s\n' "$RUNS"; COMPLETED=1; exit 1; }
  while IFS="$SEP" read -r id status conclusion url created; do
    [ -n "$id" ] || continue
    after_cutoff "$created" || continue
    if [ -n "$GOING" ]; then
      [ "$id" = "$GOING" ] || continue
    else
      case "$BEFORE" in *" ${id} "*) continue ;; esac
    fi
    FOUND="$id"
    if [ "$status" = completed ]; then
      if [ "$conclusion" = success ]; then finish "$url"; fi
      red "the forsgren.yml run ${url} in ${TARGET} ended as ${conclusion:-unknown}: the metrics site does not run v${VERSION} yet"
    fi
  done <<< "$RUNS"
  if [ "$try" -lt "$TRIES" ]; then sleep "$DELAY"; fi
done
red "gave up after ${TRIES} polls of ${DELAY}s: the forsgren.yml run of ${TARGET} ${FOUND:+is still going}${FOUND:-has not appeared}"
