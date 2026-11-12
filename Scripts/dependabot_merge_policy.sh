#!/usr/bin/env bash
# Scripts/dependabot_merge_policy.sh <pull request number>   (forsgren#664)
#
# Decides whether a Dependabot pull request of this repository may merge on
# its own (run by .github/workflows/dependabot_merge.yml, whose merge step
# merges an ELIGIBLE one only when DEPENDABOT_AUTOMERGE is on). Fail
# closed: every condition below must hold, and any GitHub API error or answer
# it cannot read is NOT ELIGIBLE, with the reason.
#   - the pull request was opened by dependabot[bot], from a branch
#     dependabot/<ecosystem>/... of this repository (a head repository that
#     is another one, or unknown because it was deleted, blocks), and its
#     head is the commit the workflow run was for, when that is given;
#   - every dependency in the updated-dependencies block of the head commit's
#     message is allowed by .github/dependabot-merge.conf (a grouped pull
#     request only if every member is);
#   - every workflow the config expects has a completed, successful run for
#     the pull request's current head commit;
#   - the pull request is open, mergeable and clean;
#   - its head contains the current default branch (behind by 0).
# It reads the GitHub API only (gh api, GET); it never checks out or runs the
# pull request's code. The policy is generic: which updates may merge and
# which workflows must be green are data, in the config, never in this file.
#
# Prints the record (repository, pull request, dependencies old -> new, head
# commit, checks, reasons, decision) and appends it to $GITHUB_STEP_SUMMARY
# when that is set.
# Run:  GITHUB_REPOSITORY=owner/name Scripts/dependabot_merge_policy.sh <number>
# Exit: 0 eligible, 1 not eligible, 2 usage error.
# Env:  DEPENDABOT_MERGE_CONF (default .github/dependabot-merge.conf),
#       DEPENDABOT_MERGE_ATTEMPTS (3) and DEPENDABOT_MERGE_RETRY_SECONDS (5):
#       the reads of a pull request whose mergeability GitHub has not
#       computed yet; DEPENDABOT_MERGE_EXPECTED_HEAD (unset: not checked): the
#       head commit the workflow run was for, which the pull request's head
#       must still be.
# Self-test: Scripts/test_dependabot_merge_policy.sh.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=Scripts/lib_tmp.sh
source "$ROOT/Scripts/lib_tmp.sh"
CONF="${DEPENDABOT_MERGE_CONF:-$ROOT/.github/dependabot-merge.conf}"
ATTEMPTS="${DEPENDABOT_MERGE_ATTEMPTS:-3}"
RETRY_SECONDS="${DEPENDABOT_MERGE_RETRY_SECONDS:-5}"
EXPECTED_HEAD="${DEPENDABOT_MERGE_EXPECTED_HEAD:-}"
AUTHOR="dependabot[bot]"

usage() {
  echo "usage: GITHUB_REPOSITORY=owner/name $0 <pull request number>" >&2
  exit 2
}
[ "$#" -eq 1 ] && [[ "$1" =~ ^[1-9][0-9]*$ ]] || usage
[[ "${GITHUB_REPOSITORY:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
[[ "$ATTEMPTS" =~ ^[1-9][0-9]*$ ]] && [[ "$RETRY_SECONDS" =~ ^[0-9]+$ ]] || usage
PR="$1"
REPO="$GITHUB_REPOSITORY"
WORK="$(tmp_dir dependabot_merge_policy)" || { echo "❌ FAIL: dependabot_merge_policy.sh: cannot make a temp folder under ${TMPDIR:-/tmp}" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

REASONS=()
DEPS=()
CHECKS=()
TITLE="?"
HEAD_SHA="?"
COMPLETE=0
READS=0
block() { REASONS+=("$1"); }

# finish: prints the record and exits 0 only when every step ran and nothing
# blocked.
finish() {
  local decision=ELIGIBLE code=0 record
  if [ "$COMPLETE" -ne 1 ] || [ "${#REASONS[@]}" -ne 0 ]; then
    decision="NOT ELIGIBLE"
    code=1
  fi
  [ "${#REASONS[@]}" -ne 0 ] || REASONS=("every condition holds")
  [ "${#DEPS[@]}" -ne 0 ] || DEPS=("(none read)")
  [ "${#CHECKS[@]}" -ne 0 ] || CHECKS=("(none read)")
  record="$(
    echo "### Dependabot merge policy: $decision"
    echo
    echo "- Repository: $REPO"
    echo "- Pull request: #$PR $TITLE"
    echo "- Head commit: $HEAD_SHA"
    echo
    echo "Dependencies:"
    printf -- '- %s\n' "${DEPS[@]}"
    echo
    echo "Expected checks:"
    printf -- '- %s\n' "${CHECKS[@]}"
    echo
    echo "Reasons:"
    printf -- '- %s\n' "${REASONS[@]}"
    echo
    echo "Decision: $decision"
  )"
  echo "$record"
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "$record" >>"$GITHUB_STEP_SUMMARY"
  exit "$code"
}

# api <path> <file>: GET the path into the file; a gh failure or an answer
# that is not JSON blocks and returns 1.
api() {
  if ! gh api "repos/$REPO/$1" >"$2" 2>"$WORK/err"; then
    block "GitHub API read failed: GET $1: $(head -1 "$WORK/err")"
    return 1
  fi
  if ! jq -e . "$2" >/dev/null 2>&1; then
    block "GitHub API answer is not JSON: GET $1"
    return 1
  fi
}

# field <file> <jq filter>: one value as text ("null" when absent).
field() { jq -r "$2" "$1" 2>/dev/null || echo "null"; }

# The config: allow rules and expected workflows.
ALLOW=()
WORKFLOWS=()
read_config() {
  local kind rest
  [ -r "$CONF" ] || {
    block "config $CONF cannot be read"
    finish
  }
  while read -r kind rest; do
    case "$kind" in
      "" | \#*) ;;
      allow) ALLOW+=("$rest") ;;
      workflow) WORKFLOWS+=("$rest") ;;
      *)
        block "config line not understood: $kind $rest"
        finish
        ;;
    esac
  done <"$CONF"
  [ "${#ALLOW[@]}" -ne 0 ] && [ "${#WORKFLOWS[@]}" -ne 0 ] || {
    block "config $CONF names no allow rule or no workflow"
    finish
  }
}

# The pull request, read again while GitHub has not computed its
# mergeability yet.
read_pull_request() {
  local attempt=1 mergeable state
  while :; do
    api "pulls/$PR" "$WORK/pr.json" || finish
    mergeable="$(field "$WORK/pr.json" .mergeable)"
    state="$(field "$WORK/pr.json" .mergeable_state)"
    [ "$(field "$WORK/pr.json" .state)" = open ] || break
    [ "$mergeable" = null ] || [ "$state" = unknown ] || break
    [ "$attempt" -lt "$ATTEMPTS" ] || break
    attempt=$((attempt + 1))
    sleep "$RETRY_SECONDS"
  done
  READS="$attempt"
}

check_pull_request() {
  local f="$WORK/pr.json" login state base default mergeable mstate head_repo
  TITLE="$(field "$f" .title)"
  HEAD_SHA="$(field "$f" .head.sha)"
  HEAD_REF="$(field "$f" .head.ref)"
  login="$(field "$f" .user.login)"
  state="$(field "$f" .state)"
  base="$(field "$f" .base.ref)"
  DEFAULT_BRANCH="$(field "$f" .base.repo.default_branch)"
  default="$DEFAULT_BRANCH"
  mergeable="$(field "$f" .mergeable)"
  mstate="$(field "$f" .mergeable_state)"
  head_repo="$(field "$f" .head.repo.full_name)"
  [ "$login" = "$AUTHOR" ] || block "author is '$login', not $AUTHOR"
  if [ "$head_repo" = null ] || [ -z "$head_repo" ]; then
    block "head repository unknown (deleted or not readable), not $REPO"
  elif [ "$head_repo" != "$REPO" ]; then
    block "head repository is '$head_repo', not $REPO"
  fi
  [ "$state" = open ] || block "pull request is $state, not open"
  [ "$default" != null ] && [ "$base" = "$default" ] || block "base branch '$base' is not the default branch '$default'"
  if [ "$mergeable" = null ] || [ "$mstate" = unknown ]; then
    block "mergeability not computed by GitHub after $READS read(s) (mergeable $mergeable, state $mstate)"
  else
    [ "$mergeable" = true ] || block "not mergeable (mergeable $mergeable)"
    [ "$mstate" = clean ] || block "mergeable state is '$mstate', not clean"
  fi
  [[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || {
    block "head commit '$HEAD_SHA' is not a commit id"
    finish
  }
  if [ -n "$EXPECTED_HEAD" ] && [ "$HEAD_SHA" != "$EXPECTED_HEAD" ]; then
    block "head commit $HEAD_SHA is not the commit the run was for ($EXPECTED_HEAD); the pull request moved"
  fi
  if [[ "$HEAD_REF" =~ ^dependabot/([a-z_]+)/ ]]; then
    ECOSYSTEM="${BASH_REMATCH[1]}"
  else
    ECOSYSTEM="?"
    block "branch '$HEAD_REF' does not name a Dependabot ecosystem (dependabot/<ecosystem>/...)"
  fi
}

# parse_dependencies <message file>: the updated-dependencies block as lines
# name|type|update|version (a field Dependabot left out is empty; | separates
# because no package name or version holds one), or one line starting ERROR
# when the block is missing or holds a line it does not understand.
parse_dependencies() {
  awk '
    function unquote(v) { gsub(/^[ \t]+|[ \t\r]+$/, "", v); if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2); return v }
    function fail(why) { if (bad == "") bad = why }
    # Collected and printed only at the end, so a block with any error prints nothing but the ERROR line.
    function emit() {
      if (name == "") return
      if (index(name type upd ver, "|")) fail("a field holds |: " name)
      out = out name "|" type "|" upd "|" ver "\n"; n++; name = ""
    }
    /^updated-dependencies:[ \t\r]*$/ { if (seen) fail("more than one updated-dependencies block"); inblock = 1; seen = 1; next }
    inblock && /^\.\.\.[ \t\r]*$/ { emit(); inblock = 0; closed = 1; next }
    !inblock { next }
    /^- dependency-name:/ { emit(); name = unquote(substr($0, index($0, ":") + 1)); type = upd = ver = ""; next }
    /^  [a-z-]+:/ && name != "" {
      key = $1; sub(/:$/, "", key); val = unquote(substr($0, index($0, ":") + 1))
      if (key == "dependency-type") type = val
      else if (key == "update-type") upd = val
      else if (key == "dependency-version") ver = val
      next
    }
    { fail("line not understood: " $0); inblock = 0 }
    END {
      if (bad != "") { print "ERROR " bad; exit }
      if (!seen) { print "ERROR no updated-dependencies block"; exit }
      if (!closed) { print "ERROR updated-dependencies block not closed by ..."; exit }
      if (n == 0) { print "ERROR updated-dependencies block lists no dependency"; exit }
      printf "%s", out
    }
  ' "$1"
}

# versions <name> <text file>: "old → new" from Dependabot's "Bumps
# [name](...) from A to B" or "Updates `name` from A to B" line, or "?" when
# neither is there (the record only; the decision rests on the metadata block).
versions() {
  awk -v n="$1" '
    index($0, "Updates `" n "` from ") || index($0, "Bumps [" n "](") || index($0, "bump " n " from ") {
      if (match($0, / from [^ ]+ to [^ ]+/)) {
        split(substr($0, RSTART + 6, RLENGTH - 6), p, " to "); sub(/\.$/, "", p[2]); print p[1] " → " p[2]; found = 1; exit
      }
    }
    END { if (!found) print "?" }
  ' "$2"
}

# allowed <ecosystem> <dependency-type> <update-type>: 0 when an allow rule
# of the config matches.
allowed() {
  local rule eco type upd
  for rule in "${ALLOW[@]}"; do
    read -r eco type upd <<<"$rule"
    [ "$eco" = "$1" ] && { [ "$type" = "*" ] || [ "$type" = "$2" ]; } && [ "version-update:$upd" = "$3" ] && return 0
  done
  return 1
}

check_dependencies() {
  local parsed name type upd ver change
  api "commits/$HEAD_SHA" "$WORK/commit.json" || return
  # The metadata comes from the commit message only; the title and body only
  # add the old versions to the record.
  jq -r '.commit.message // empty' "$WORK/commit.json" >"$WORK/message"
  {
    cat "$WORK/message"
    jq -r '.title // empty, .body // empty' "$WORK/pr.json"
  } >"$WORK/text"
  parsed="$(parse_dependencies "$WORK/message")"
  if [[ "$parsed" == ERROR* ]]; then
    block "commit metadata unreadable: ${parsed#ERROR }"
    return
  fi
  while IFS='|' read -r name type upd ver; do
    change="$(versions "$name" "$WORK/text")"
    [ "$change" != "?" ] || change="? → ${ver:-?}"
    if allowed "$ECOSYSTEM" "$type" "$upd"; then
      DEPS+=("\`$name\` ($ECOSYSTEM, ${type:-no dependency-type}, ${upd:-no update-type}): $change, allowed")
    else
      DEPS+=("\`$name\` ($ECOSYSTEM, ${type:-no dependency-type}, ${upd:-no update-type}): $change, NOT allowed")
      block "\`$name\` is not an allowed update ($ECOSYSTEM, ${type:-no dependency-type}, ${upd:-no update-type})"
    fi
  done <<<"$parsed"
}

check_workflows() {
  local wf path name run status conclusion id
  api "actions/runs?head_sha=$HEAD_SHA&per_page=100" "$WORK/runs.json" || return
  jq -e '.workflow_runs | type == "array"' "$WORK/runs.json" >/dev/null 2>&1 || {
    block "workflow runs answer has no workflow_runs list"
    return
  }
  for wf in "${WORKFLOWS[@]}"; do
    read -r path name <<<"$wf"
    # The latest run of that workflow for exactly this head commit; a rerun
    # replaces its attempt in place.
    run="$(jq -c --arg p "$path" --arg n "$name" --arg s "$HEAD_SHA" \
      '[.workflow_runs[] | select(.path == $p and .name == $n and .head_sha == $s)] | sort_by(.id) | last // empty' "$WORK/runs.json")"
    if [ -z "$run" ]; then
      CHECKS+=("$name: missing, no run for the head commit")
      block "$name has no run for the head commit $HEAD_SHA"
      continue
    fi
    status="$(jq -r '.status' <<<"$run")"
    conclusion="$(jq -r '.conclusion' <<<"$run")"
    id="$(jq -r '.id' <<<"$run")"
    CHECKS+=("$name: $status, $conclusion (run $id)")
    [ "$status" = completed ] && [ "$conclusion" = success ] ||
      block "$name is $status, $conclusion, not completed with success (run $id)"
  done
}

check_fresh() {
  local behind
  api "compare/$DEFAULT_BRANCH...$HEAD_SHA" "$WORK/compare.json" || return
  behind="$(field "$WORK/compare.json" .behind_by)"
  if ! [[ "$behind" =~ ^[0-9]+$ ]]; then
    block "compare answer has no behind_by"
  elif [ "$behind" -ne 0 ]; then
    block "head is $behind commit(s) behind $DEFAULT_BRANCH; wait for Dependabot's rebase and a new green run"
  fi
}

read_config
read_pull_request
check_pull_request
check_dependencies
check_workflows
check_fresh
COMPLETE=1
finish
