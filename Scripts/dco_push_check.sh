#!/usr/bin/env bash
# Scripts/dco_push_check.sh
#
# The DCO check of a push to main (forsgren#267, decision #268, option 1).
# .github/workflows/dco.yml runs this on a push, with the commit list that
# Scripts/dco_push_commits.sh wrote, instead of Scripts/check_dco.sh directly.
#
# Why: merging a pull request with GitHub's merge button puts the pull
# request's commits and a merge commit GitHub makes on main. The pull
# request's own DCO run already judged its commits (with the bot exemption a
# push cannot have: forsgren#81), and the merge commit has no sign-off by
# design. Judged again on the push, a merged Dependabot pull request turned
# DCO red although its own run was green.
#
# For each pushed commit this asks the API which pull requests it belongs to
# (GET /repos/{repo}/commits/{sha}/pulls). A commit is NOT judged again, and
# the output says so, when a pull request of THIS repository that is merged
# has a DCO check run (the job named DCO sign-off, made by the github-actions
# app) that succeeded on the pull request's head sha, and:
#   - the commit is one of the pull request's commits: its own DCO run judged
#     it; or
#   - it is the merge commit GitHub made for that pull request: committed by
#     GitHub's web-flow account, verified by GitHub, its second parent the
#     pull request's head sha. Exempt.
# Every other commit goes to Scripts/check_dco.sh, the strict rule unchanged:
# a direct push gains no exemption; a commit of a merged pull request whose
# DCO run failed or is missing, of a pull request that is not merged or is
# another repository's, a squash or rebase commit (not one of the pull
# request's commits), and a merge commit not made by GitHub, not verified or
# with another second parent, are judged strictly.
# Any failed API call is red with its reason, never a pass: a commit that
# cannot be looked up is not a commit judged.
#
# The commits come from a file in check_dco.sh's input shape (one line per
# commit, see Scripts/check_dco.sh). Reading the API needs, for the token,
# contents: read and pull-requests: read (commits/{sha}/pulls, a pull
# request's commits) and checks: read (a commit's check runs); the token
# reaches gh through GH_TOKEN. gh's own --jq does the parsing, so the runner
# needs no jq.
#
# Seams (the self-test needs no network): DCO_GH is the gh command (default
# gh), DCO_CHECK the strict check (default Scripts/check_dco.sh).
#
# Usage: Scripts/dco_push_check.sh <owner/repo> <commits-file>
# Exit: check_dco.sh's status for the commits not already judged; 0 when
# every commit was already judged; 1 on a wrong call, a failed API call or no
# commit; 2 the input file missing. Fixture: Scripts/test_check_dco.sh (gh
# stubbed).

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

if [ "$#" -ne 2 ]; then
  echo "❌ FAIL: usage: Scripts/dco_push_check.sh <owner/repo> <commits-file>"
  exit 1
fi
REPO="$1"
INPUT="$2"
if ! [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "❌ FAIL: DCO: the repository is not <owner>/<name> — no commit can be looked up"
  exit 1
fi
if [ ! -f "$INPUT" ]; then
  echo "❌ FAIL: DCO: input file not found: ${INPUT}"
  exit 2
fi
GH="${DCO_GH:-gh}"
CHECK="${DCO_CHECK:-./Scripts/check_dco.sh}"
REPO_LOWER="$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]')"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# api <what> <gh api arguments...>: the answer on stdout. A failed call is a
# red line with gh's own first line of reason, and the status 1; the callers
# run it as `x="$(api ...)" || exit 1`. The mutation proof in
# Scripts/test_check_dco.sh rewrites the `exit 1` line below: keep it alone.
api() {
  local what="$1" reason
  shift
  if ! "$GH" api "$@" > "$WORK/answer" 2> "$WORK/reason"; then
    reason="$(head -n 1 "$WORK/reason" | tr -d '\r')"
    [ -n "$reason" ] || reason="gh exited with an error"
    echo "❌ FAIL: DCO: the GitHub API call for ${what} failed: ${reason} — a commit that cannot be looked up is not judged, so this is red" >&2
    exit 1
  fi
  cat "$WORK/answer"
}

# dco_green <head sha>: the pull request's head carries a DCO check run of
# this repository's own workflow that succeeded. Answers cached per head. The
# mutation proof rewrites the grep line below: keep it alone.
dco_green() {
  local head="$1" runs
  if [ ! -f "$WORK/green.${head}" ]; then
    runs="$(api "the check runs of ${head:0:12}" --paginate \
      "repos/${REPO}/commits/${head}/check-runs?per_page=100" \
      --jq '.check_runs[] | select(.name == "DCO sign-off" and .app.slug == "github-actions") | .conclusion // "-"')" || exit 1
    if printf '%s\n' "$runs" | grep -qx 'success'; then
      echo yes > "$WORK/green.${head}"
    else
      echo no > "$WORK/green.${head}"
    fi
  fi
  [ "$(cat "$WORK/green.${head}")" = yes ]
}

# in_pull <number> <sha>: the sha is one of the pull request's commits.
in_pull() {
  local number="$1" sha="$2" list
  if [ ! -f "$WORK/commits.${number}" ]; then
    list="$(api "the commits of pull request #${number}" --paginate \
      "repos/${REPO}/pulls/${number}/commits" --jq '.[].sha')" || exit 1
    printf '%s\n' "$list" > "$WORK/commits.${number}"
  fi
  grep -qx "$sha" "$WORK/commits.${number}"
}

# github_merge <sha> <head sha>: the commit is the merge commit GitHub made
# for the pull request whose head is <head sha>. Each condition on its own
# line, for the mutation proofs in Scripts/test_check_dco.sh.
github_merge() {
  local sha="$1" head="$2" info verified login email second
  info="$(api "commit ${sha:0:12}" "repos/${REPO}/commits/${sha}" \
    --jq '"\(.commit.verification.verified) \(.committer.login // "-") \(.commit.committer.email // "-") \(.parents[1].sha // "-")"')" || exit 1
  read -r verified login email second <<< "$info"
  [ "$verified" = "true" ] || return 1
  [ "$login" = "web-flow" ] || return 1
  [ "$email" = "noreply@github.com" ] || return 1
  [ "$second" = "$head" ] || return 1
}

# subject <base64 message>: the subject as written.
subject() {
  printf '%s' "$1" | base64 -d 2> /dev/null | head -n 1 | tr -d '\r'
}

total=0
judged=0
exempt=0
: > "$WORK/remaining"
while IFS= read -r row || [ -n "$row" ]; do
  [ -n "$row" ] || continue
  # A line that is not a commit line goes to the check, which names it.
  if ! [[ "$row" =~ ^([0-9a-f]{7,64})\ [^\ ]+\ [^\ ]*\ ([A-Za-z0-9+/=]+)$ ]]; then
    printf '%s\n' "$row" >> "$WORK/remaining"
    continue
  fi
  sha="${BASH_REMATCH[1]}"
  msg="${BASH_REMATCH[2]}"
  short="${sha:0:12}"
  total=$((total + 1))
  pulls="$(api "the pull requests of commit ${short}" --paginate \
    "repos/${REPO}/commits/${sha}/pulls" \
    --jq '.[] | "\(.number) \(.merged_at // "-") \(.base.repo.full_name) \(.head.sha)"')" || exit 1
  verdict=""
  while read -r number merged_at base head; do
    [ -n "$number" ] || continue
    [[ "$number" =~ ^[0-9]+$ ]] || continue
    [[ "$head" =~ ^[0-9a-f]{40}$ ]] || continue
    [ "$merged_at" != "-" ] || continue
    [ "$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')" = "$REPO_LOWER" ] || continue
    dco_green "$head" || continue
    if in_pull "$number" "$sha"; then
      verdict="judged ${number}"
      break
    elif github_merge "$sha" "$head"; then
      verdict="merge ${number}"
      break
    fi
  done <<< "$pulls"
  case "$verdict" in
    judged\ *)
      echo "ℹ️  DCO: commit ${short} ($(subject "$msg")) is not judged again: it belongs to pull request #${verdict#judged }, merged, whose own DCO run succeeded on its head"
      judged=$((judged + 1))
      ;;
    merge\ *)
      echo "ℹ️  DCO: commit ${short} ($(subject "$msg")) is exempt: the merge commit GitHub made (verified, committed by GitHub) for pull request #${verdict#merge }, merged, whose DCO run succeeded on its head"
      exempt=$((exempt + 1))
      ;;
    *)
      printf '%s\n' "$row" >> "$WORK/remaining"
      ;;
  esac
done < "$INPUT"

if [ -s "$WORK/remaining" ] || [ "$total" -eq 0 ]; then
  "$CHECK" "$WORK/remaining"
  exit $?
fi
echo "✅ DCO: ${total} commit(s), none judged again here: ${judged} by the DCO run of the merged pull request they belong to, ${exempt} the merge commit GitHub made for one"
exit 0
