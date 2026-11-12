#!/usr/bin/env bash
# Scripts/dependabot_pr_comment.sh <pull request number> <body file>   (forsgren#664)
#
# Keeps one comment of the Dependabot merge workflow
# (.github/workflows/dependabot_merge.yml) on a pull request: the comment of
# github-actions[bot] that carries the hidden marker is updated in place,
# else a new one is posted, so a pull request whose expected workflows
# complete several times still holds one record, not one per completion.
# Run:  GITHUB_REPOSITORY=owner/name Scripts/dependabot_pr_comment.sh <number> <body file>
# Exit: 0 posted or updated, 1 a gh call failed, 2 usage error.
# Self-test: Scripts/test_dependabot_pr_comment.sh.

set -uo pipefail

MARKER="<!-- dependabot-merge-policy -->"
BOT="github-actions[bot]"

[ "$#" -eq 2 ] && [[ "$1" =~ ^[1-9][0-9]*$ ]] && [ -r "$2" ] &&
  [[ "${GITHUB_REPOSITORY:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo "usage: GITHUB_REPOSITORY=owner/name $0 <pull request number> <body file>" >&2
  exit 2
}
PR="$1"
REPO="$GITHUB_REPOSITORY"
# shellcheck source=Scripts/lib_tmp.sh
source "$(dirname "$0")/lib_tmp.sh"
WORK="$(tmp_dir dependabot_pr_comment)" || { echo "❌ FAIL: dependabot_pr_comment.sh: cannot make a temp folder under ${TMPDIR:-/tmp}" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

{
  echo "$MARKER"
  cat "$2"
} >"$WORK/body"

# --paginate prints one JSON array per page; jq -s joins them.
if ! gh api --paginate "repos/$REPO/issues/$PR/comments?per_page=100" >"$WORK/pages"; then
  echo "❌ could not list the comments of #$PR" >&2
  exit 1
fi
if ! ID="$(jq -rs --arg m "$MARKER" --arg b "$BOT" \
  '[.[][] | select(.user.login == $b and (.body | contains($m))) | .id] | first // empty' "$WORK/pages")"; then
  echo "❌ the comments of #$PR are not JSON" >&2
  exit 1
fi

if [ -n "$ID" ]; then
  gh api -X PATCH "repos/$REPO/issues/comments/$ID" -F "body=@$WORK/body" >/dev/null || exit 1
  echo "Updated comment $ID on #$PR"
else
  gh api -X POST "repos/$REPO/issues/$PR/comments" -F "body=@$WORK/body" >/dev/null || exit 1
  echo "Posted a comment on #$PR"
fi
