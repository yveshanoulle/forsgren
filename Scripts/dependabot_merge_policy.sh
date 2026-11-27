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
#   - its commits are Dependabot's own (author dependabot[bot], committed by
#     GitHub with a verified signature) and, on top of them, nothing but
#     merges of the base branch (GitHub's "Update branch"); any other commit
#     blocks, named;
#   - every dependency in the updated-dependencies block of the newest
#     Dependabot commit's message (not the head commit's: a merge on top has
#     none) is allowed by .github/dependabot-merge.conf (a grouped pull
#     request only if every member is; a rule that names a dependency allows
#     that dependency only), and no member matches a deny rule of the config,
#     whatever the allow rules say (forsgren#668);
#   - with a github_actions deny rule in the config, no uses: line the pull
#     request adds or removes in a workflow file (.github/workflows/*.yml or
#     .yaml, or a composite action's action.yml or action.yaml) names a
#     denied reference; a files list it cannot read whole, a workflow file
#     without a patch or a uses: line it cannot read blocks, since it cannot
#     tell (forsgren#668);
#   - every workflow the config expects has a completed, successful run for
#     the pull request's current head commit;
#   - the pull request is open, mergeable and clean;
#   - its head contains the current default branch (behind by 0).
# It reads the GitHub API only (gh api, GET); it never checks out or runs the
# pull request's code. The policy is generic: which updates may merge, which
# dependencies never do and which workflows must be green are data, in the
# config, never in this file.
#
# Prints the record (repository, pull request, dependencies old -> new, head
# commit, the metadata commit when that is another one, checks, reasons,
# decision) and appends it to $GITHUB_STEP_SUMMARY
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
META_SHA="?"
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
    [ "$META_SHA" = "?" ] || [ "$META_SHA" = "$HEAD_SHA" ] || echo "- Metadata commit: $META_SHA"
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

# The config: allow rules, deny rules and expected workflows.
ALLOW=()
DENY=()
WORKFLOWS=()
read_config() {
  local kind rest n
  [ -r "$CONF" ] || {
    block "config $CONF cannot be read"
    finish
  }
  while read -r kind rest; do
    case "$kind" in
      "" | \#*) ;;
      allow)
        # <ecosystem> <dependency-type> <update-type> [<dependency-name>]
        n="$(wc -w <<<"$rest")"
        [ "$n" -eq 3 ] || [ "$n" -eq 4 ] || {
          block "config line not understood: allow $rest"
          finish
        }
        ALLOW+=("$rest")
        ;;
      deny)
        # <ecosystem> <dependency-name, or a name prefix followed by *>
        n="$(wc -w <<<"$rest")"
        [ "$n" -eq 2 ] && [[ "${rest#* }" =~ ^[^*]*\*?$ ]] || {
          block "config line not understood: deny $rest"
          finish
        }
        DENY+=("$rest")
        ;;
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

# allowed <ecosystem> <dependency-type> <update-type> <dependency-name>: 0
# when an allow rule of the config matches; a rule that names a dependency
# matches that dependency only.
allowed() {
  local rule eco type upd name
  for rule in "${ALLOW[@]}"; do
    read -r eco type upd name <<<"$rule"
    [ "$eco" = "$1" ] && { [ "$type" = "*" ] || [ "$type" = "$2" ]; } && [ "version-update:$upd" = "$3" ] &&
      { [ -z "$name" ] || [ "$name" = "$4" ]; } && return 0
  done
  return 1
}

# lower <text>: the text in lower case.
lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }

# denied <ecosystem> <dependency-name>: 0 when a deny rule of the config
# matches, the rule then in DENIED_BY. The name is compared ignoring case, in
# every ecosystem, so a deny rule can only ever block more; a pattern that
# ends in * matches every name that starts with what comes before it.
DENIED_BY=""
denied() {
  local rule eco pattern name
  [ "${#DENY[@]}" -ne 0 ] || return 1
  name="$(lower "$2")"
  for rule in "${DENY[@]}"; do
    read -r eco pattern <<<"$rule"
    [ "$eco" = "$1" ] || continue
    pattern="$(lower "$pattern")"
    case "$pattern" in
      *\*) [[ "$name" == "${pattern%\*}"* ]] || continue ;;
      *) [ "$name" = "$pattern" ] || continue ;;
    esac
    DENIED_BY="deny $rule"
    return 0
  done
  return 1
}

# contained <commit>: 0 when the default branch contains the commit (compare
# <commit>...<default branch> is behind by 0); 1, blocking when the answer
# cannot be read, otherwise.
contained() {
  local behind
  api "compare/$1...$DEFAULT_BRANCH" "$WORK/contained.json" || return 1
  behind="$(field "$WORK/contained.json" .behind_by)"
  if ! [[ "$behind" =~ ^[0-9]+$ ]]; then
    block "compare answer for merge parent $1 has no behind_by"
    return 1
  fi
  [ "$behind" -eq 0 ]
}

# metadata_commit: writes the message of the commit that carries Dependabot's
# metadata to $WORK/message and its id to META_SHA; blocks and returns 1 when
# there is none or the pull request holds another commit. The head commit is
# not always Dependabot's: GitHub's "Update branch" (or a merge of the base
# branch) puts a merge commit on top, which carries no metadata. So it reads
# the pull request's commits (pulls/<n>/commits, one page of 100, so a list of
# 100 may be cut and blocks) and accepts two kinds only:
#   - Dependabot's own: author dependabot[bot], committer web-flow (GitHub),
#     verified signature, one parent;
#   - a merge of the base branch: exactly two parents, the second one a commit
#     the default branch contains.
# Any other commit (a person's or an agent's change) blocks, named. The newest
# Dependabot commit is the metadata commit. The head commit must be in the
# list (the pull request did not move between the reads). The changed-files
# and version checks still read the pull request's whole diff.
metadata_commit() {
  local f="$WORK/commits.json" n i sha author committer verified parents second foreign=0 meta=-1
  api "pulls/$PR/commits?per_page=100" "$f" || return 1
  n="$(jq -r 'if type == "array" then length else "none" end' "$f" 2>/dev/null || echo none)"
  case "$n" in
    none)
      block "pull request commits answer is not a list"
      return 1
      ;;
    0)
      block "pull request lists no commit"
      return 1
      ;;
  esac
  if [ "$n" -ge 100 ]; then
    block "pull request lists $n commits, the most one read returns: the list may be cut"
    return 1
  fi
  if ! jq -e --arg h "$HEAD_SHA" 'any(.[]; .sha == $h)' "$f" >/dev/null 2>&1; then
    block "head commit $HEAD_SHA is not among the pull request's commits (it moved)"
    return 1
  fi
  for ((i = 0; i < n; i++)); do
    sha="$(field "$f" ".[$i].sha")"
    author="$(field "$f" ".[$i].author.login")"
    committer="$(field "$f" ".[$i].committer.login")"
    verified="$(field "$f" ".[$i].commit.verification.verified")"
    parents="$(field "$f" ".[$i].parents | length")"
    second="$(field "$f" ".[$i].parents[1].sha")"
    if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
      block "pull request commit $((i + 1)) has no commit id ('$sha')"
      foreign=1
    elif [ "$author" = "$AUTHOR" ] && [ "$committer" = web-flow ] && [ "$verified" = true ] && [ "$parents" = 1 ]; then
      meta="$i"
    elif [ "$parents" = 2 ] && [[ "$second" =~ ^[0-9a-f]{40}$ ]] && contained "$second"; then
      :
    else
      block "commit $sha (author $author, committer $committer, verified $verified, $parents parent(s)) is neither Dependabot's nor a merge of $DEFAULT_BRANCH"
      foreign=1
    fi
  done
  [ "$foreign" -eq 0 ] || return 1
  if [ "$meta" -lt 0 ]; then
    block "commit metadata unreadable: no Dependabot commit (author $AUTHOR, committer web-flow, verified) in the pull request"
    return 1
  fi
  META_SHA="$(field "$f" ".[$meta].sha")"
  # The metadata comes from the commit message only.
  jq -r ".[$meta].commit.message // empty" "$f" >"$WORK/message"
}

check_dependencies() {
  local parsed name type upd ver change
  metadata_commit || return
  # The title and body only add the old versions to the record.
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
    # A deny rule wins over every allow rule, for each member of a group.
    if denied "$ECOSYSTEM" "$name"; then
      DEPS+=("\`$name\` ($ECOSYSTEM, ${type:-no dependency-type}, ${upd:-no update-type}): $change, DENIED ($DENIED_BY)")
      block "\`$name\` is denied by the rule '$DENIED_BY' ($ECOSYSTEM, ${type:-no dependency-type}, ${upd:-no update-type})"
    elif allowed "$ECOSYSTEM" "$type" "$upd" "$name"; then
      DEPS+=("\`$name\` ($ECOSYSTEM, ${type:-no dependency-type}, ${upd:-no update-type}): $change, allowed")
    else
      DEPS+=("\`$name\` ($ECOSYSTEM, ${type:-no dependency-type}, ${upd:-no update-type}): $change, NOT allowed")
      block "\`$name\` is not an allowed update ($ECOSYSTEM, ${type:-no dependency-type}, ${upd:-no update-type})"
    fi
  done <<<"$parsed"
}

# workflow_file <path>: 0 for a file whose uses: lines name GitHub Actions
# dependencies: a workflow under .github/workflows/ or a composite action's
# action.yml or action.yaml.
workflow_file() {
  case "$1" in
    .github/workflows/*.yml | .github/workflows/*.yaml | action.yml | action.yaml | */action.yml | */action.yaml) return 0 ;;
  esac
  return 1
}

# check_uses <path> <changed line>: blocks when the line is a uses: line that
# names a denied reference or that it cannot read. A comment, a local action
# (./...) and a docker:// image name no repository; owner/repo[/path]@ref is
# held to the github_actions deny rules as owner/repo (Dependabot's
# dependency name) and as written before the @.
check_uses() {
  local line="${2:1}" value ref
  local readable='^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+([^[:space:]#]+)([[:space:]]+#.*)?[[:space:]]*$'
  local repository='^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(/[^@]*)?@[^@]+$'
  [[ "$line" =~ ^[[:space:]]*# ]] && return 0
  # Any line with uses and a colon after it, in any case, quoted or in a
  # flow mapping, is a uses: line, read only in the plain form above.
  [[ "$(lower "$line")" == *uses*:* ]] || return 0
  if ! [[ "$line" =~ $readable ]]; then
    block "changed workflow file $1 has a uses: line it cannot read, so a denied dependency cannot be ruled out: $2"
    return 0
  fi
  value="${BASH_REMATCH[2]}"
  [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]] && value="${BASH_REMATCH[1]}"
  case "$value" in ./* | docker://*) return 0 ;; esac
  if ! [[ "$value" =~ $repository ]]; then
    block "changed workflow file $1 has a uses: line it cannot read, so a denied dependency cannot be ruled out: $2"
    return 0
  fi
  ref="${value%@*}"
  if denied github_actions "${BASH_REMATCH[1]}" || denied github_actions "$ref"; then
    block "changed workflow file $1 moves \`$ref\`, denied by the rule '$DENIED_BY'"
  fi
}

# check_workflow_files: with a github_actions deny rule, every uses: line the
# pull request adds or removes in a workflow file is held to the deny rules,
# so a denied reference that the metadata names otherwise, or not at all,
# still blocks. A list it cannot read whole, a workflow file without a patch
# or a uses: line it cannot read blocks: it cannot tell.
check_workflow_files() {
  local f="$WORK/files.json" rule n changed i path line any=0
  for rule in "${DENY[@]+"${DENY[@]}"}"; do
    [ "${rule%% *}" != github_actions ] || any=1
  done
  [ "$any" -eq 1 ] || return 0
  api "pulls/$PR/files?per_page=100" "$f" || return
  jq -e 'type == "array"' "$f" >/dev/null 2>&1 || {
    block "pull request files answer is not a list"
    return
  }
  n="$(jq length "$f")"
  changed="$(field "$WORK/pr.json" .changed_files)"
  if ! [[ "$changed" =~ ^[0-9]+$ ]] || [ "$changed" -ne "$n" ]; then
    block "pull request files not read whole ($n of $changed), so a denied uses: line cannot be ruled out"
    return
  fi
  for ((i = 0; i < n; i++)); do
    path="$(jq -r ".[$i].filename // empty" "$f")"
    [ -n "$path" ] || {
      block "pull request files answer names a file without a filename, so a denied uses: line cannot be ruled out"
      continue
    }
    workflow_file "$path" || continue
    if ! jq -e ".[$i].patch | type == \"string\"" "$f" >/dev/null 2>&1; then
      block "changed workflow file $path has no patch in GitHub's answer, so its uses: lines cannot be read"
      continue
    fi
    while IFS= read -r line; do
      case "$line" in
        [-+]*) check_uses "$path" "$line" ;;
      esac
    done < <(jq -r ".[$i].patch" "$f")
  done
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
check_workflow_files
check_workflows
check_fresh
COMPLETE=1
finish
