#!/usr/bin/env bash
# Scripts/release_check.sh
#
# Run by the maintainer before the last FBP of a release (forsgren#445): would
# the Release workflow's plan step pass, and is main free of a stray red
# commit? Read-only, on the maintainer's machine, with the local gh login.
#
# Usage: Scripts/release_check.sh
#
# It runs the SAME Scripts/release_plan.sh the Release runs, with `auto --all`
# (there is no second copy of its rules), so it finds, one line each:
#   - every issue closed since the latest release tag without a patch, minor
#     or major label (or tools),
#   - every open issue, not tools, named by #N in the subject of a commit
#     since the tag,
#   - nothing closed since the tag, a bump the labels do not allow, a major
#     without the agent proofs,
# and, which the plan does not say, every commit on main since the tag whose
# subject is `*** RED ****` alone, naming the issue its body names, and no later
# commit since the tag has a subject naming that issue (forsgren#458: a green
# commit on top replaces the red; a red whose body names no issue stays a finding).
#
# Exit 0: `release check: OK, bump=<kind>` (the bump the labels require; none
# when only tools issues were closed, the plan's release=none).
# Exit 1: at least one finding, each on its own line, `❌ release check: ...`.
# Exit 2: the plan could not judge (a latest tag that is no vX.Y.Z), or a usage error.
#
# Seams (the self-test): RELEASE_PLAN_DATA and its companions pass through to
# the plan; RELEASE_CHECK_SCRIPTS is the directory of the plan (default:
# beside this script); RELEASE_CHECK_LOG is a file with the commits since the
# tag in the shape of `git log --format='%h%x1f%s%x1f%b%x1e'` (read instead of
# git; without it and with RELEASE_PLAN_DATA set there are no commits).
#
# Self-test: the check's own test script, beside this one.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_check.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="${RELEASE_CHECK_SCRIPTS:-$HERE}"

if [ "$#" -ne 0 ]; then
  echo "usage: Scripts/release_check.sh" >&2
  COMPLETED=1
  exit 2
fi

FINDINGS=0

# finding <text>: one finding, one line.
finding() {
  echo "❌ release check: $1"
  FINDINGS=$((FINDINGS + 1))
}

# has <text> <line>: 0 when the text holds the line. A here-string, never a
# producer piped into grep -q (pipefail would fail the producer on the early exit).
has() {
  grep -qxF -- "$2" <<< "$1"
}

# tag_of <plan output>: the latest release tag the plan named, from the last
# field of a machine line, else from "since vX.Y.Z" in a line.
tag_of() {
  local tag since
  tag="$(awk -F'\t' '/^(blocking|ready)=/ { print $NF; exit }' <<< "$1")"
  if [ -z "$tag" ]; then
    since="$(grep -oE 'since v[0-9]+\.[0-9]+\.[0-9]+' <<< "$1" || true)"
    tag="${since#since }"
    tag="${tag%%$'\n'*}"
  fi
  printf '%s' "$tag"
}

# log_since <tag>: the commits since the tag, from the seam or from git.
log_since() {
  if [ -n "${RELEASE_CHECK_LOG:-}" ]; then
    cat "$RELEASE_CHECK_LOG"
    return
  fi
  if [ -n "${RELEASE_PLAN_DATA:-}" ]; then return 0; fi
  git log --format='%h%x1f%s%x1f%b%x1e' "${1}..HEAD"
}

# red_findings <tag>: a finding per commit whose subject is `*** RED ****`
# alone, unless a later commit (earlier in the log, which is newest first) has
# a subject naming the issue its body names.
red_findings() {
  local log rec sha rest subject body issue number later=""
  log="$(log_since "$1")" || { finding "git could not read the commits since ${1}"; return; }
  while IFS= read -r -d $'\036' rec; do
    rec="${rec#"${rec%%[!$'\n']*}"}"
    [ -n "$rec" ] || continue
    sha="${rec%%$'\037'*}"
    rest="${rec#*$'\037'}"
    subject="${rest%%$'\037'*}"
    body="${rest#*$'\037'}"
    if [ "$subject" != "*** RED ****" ]; then later+="${subject}"$'\n'; continue; fi
    issue="no issue"
    if [[ "$body" =~ \#([0-9]+) ]]; then
      number="${BASH_REMATCH[1]}"
      issue="#${number}"
      if [[ "$later" =~ \#${number}([^0-9]|$) ]]; then continue; fi
    fi
    finding "commit ${sha} on main since ${1} is a *** RED **** commit alone, its body names ${issue}: the red was never replaced by a green commit"
  done <<< "$log"
}

PLAN_OUT="$("${SCRIPTS}/release_plan.sh" auto --all 2>&1)"
rc=$?

if [ "$rc" -ge 2 ]; then
  echo "❌ release check: the plan could not judge (exit ${rc}): ${PLAN_OUT}"
  COMPLETED=1
  exit 2
fi

TAG="$(tag_of "$PLAN_OUT")"

BUMP="none"
if [ "$rc" -eq 1 ]; then
  while IFS= read -r line; do
    case "$line" in
      "❌ FAIL: release plan: "*) finding "${line#❌ FAIL: release plan: }" ;;
      blocking=* | ready=* | "") ;;
      *) echo "$line" ;;
    esac
  done <<< "$PLAN_OUT"
elif ! has "$PLAN_OUT" "release=none"; then
  BUMP="$(sed -nE 's/^OK: next version .*, ([a-z]+) required\)$/\1/p' <<< "$PLAN_OUT")"
  [ -n "$BUMP" ] || { finding "the plan said OK without the bump the labels require: ${PLAN_OUT}"; BUMP="unknown"; }
fi

if [ -n "$TAG" ]; then red_findings "$TAG"; fi

COMPLETED=1
if [ "$FINDINGS" -gt 0 ]; then exit 1; fi
echo "release check: OK, bump=${BUMP}"
exit 0
