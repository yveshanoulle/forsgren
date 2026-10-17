#!/usr/bin/env bash
# Scripts/release_plan.sh
#
# What a release would be (forsgren#221, step 1 of 2): from the latest release
# and the issues closed since it, the bump the labels require, the check of
# the requested bump against it, the next version and the release notes.
#
# Usage: Scripts/release_plan.sh <patch|minor|major> [--notes <file>]
#
# The issues considered are the ones of this repository (gh runs in the
# checkout) closed AFTER the publish time of the latest release, minus the
# ones that are not part of a release:
#   - labelled decision, duplicate, invalid, wontfix or question
#   - closed as not planned
#   - named in the notes of an earlier release (a `#N` in the body of any of
#     the last 100 releases): an issue closed after its release was published
#     is never released twice
# Each remaining issue requires the bump of its label: patch, minor or major
# (the highest of its labels). The highest requirement wins. An issue with
# none of the three labels cannot be judged: the plan stops and names every
# such issue.
#
# Red (exit 1, a ❌ line that names the reason):
#   - nothing was closed since the latest release
#   - an issue has no patch, minor or major label: every one is named, followed
#     by "label it patch, minor or major"
#   - the requested bump is lower than the required one; the line names the
#     issues that require more
# Green (exit 0): `OK: next version X.Y.Z`, then the lines `version=X.Y.Z` and
# `tag=vX.Y.Z` and `issues=#3 #5` (the numbers, ascending), then the release
# notes: one `- #N title` line per issue, grouped under ### Major, ### Minor
# and ### Patch.
# With --notes the same notes are written to <file>.
# Exit 2: a usage error, or a latest release that is no vX.Y.Z tag.
#
# Data: from gh (latest release, closed issues, the bodies of the earlier
# releases). The seam for the self-test is RELEASE_PLAN_DATA, a file read
# instead of gh (RELEASE_PLAN_NOTES, a file with the earlier releases' notes,
# stands for their bodies; none when unset): the first line is the latest
# tag, TAB, its publish time (UTC, 2026-10-17T05:06:23Z); every other line is
# number, title, labels (comma separated), closed time, state reason, TAB
# separated.
#
# Self-test: Scripts/test_release_plan.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_plan.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

usage() {
  echo "usage: Scripts/release_plan.sh <patch|minor|major> [--notes <file>]" >&2
  COMPLETED=1
  exit 2
}

stop() {
  echo "❌ FAIL: release plan: $*"
  COMPLETED=1
  exit 1
}

refuse() {
  echo "❌ FAIL: release plan: $*" >&2
  COMPLETED=1
  exit 2
}

REQUESTED="${1:-}"
[ "$#" -ge 1 ] && shift
NOTES_FILE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --notes)
      [ "$#" -ge 2 ] || usage
      NOTES_FILE="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

rank_of() {
  case "$1" in
    major) echo 3 ;;
    minor) echo 2 ;;
    *) echo 1 ;;
  esac
}

case "$REQUESTED" in
  patch | minor | major) ;;
  *) usage ;;
esac

# fetch: the data in the shape described above, from the seam or from gh.
fetch() {
  if [ -n "${RELEASE_PLAN_DATA:-}" ]; then
    cat "$RELEASE_PLAN_DATA"
    return
  fi
  local latest published
  latest="$(gh release view --json tagName,publishedAt --jq '[.tagName, .publishedAt] | @tsv')" \
    || refuse "gh could not read the latest release"
  printf '%s\n' "$latest"
  published="$(printf '%s' "$latest" | cut -f2)"
  gh issue list --state closed --limit 1000 --search "closed:>=${published%%T*}" \
    --json number,title,labels,closedAt,stateReason \
    --jq '.[] | [.number, (.title | gsub("[\t\n]"; " ")), ([.labels[].name] | join(",")), .closedAt, (.stateReason // "")] | @tsv' \
    || refuse "gh could not list the closed issues"
}

# earlier_notes: the notes of the earlier releases, from the seam or from gh.
earlier_notes() {
  if [ -n "${RELEASE_PLAN_DATA:-}" ]; then
    if [ -n "${RELEASE_PLAN_NOTES:-}" ]; then cat "$RELEASE_PLAN_NOTES"; fi
    return
  fi
  local tags tag
  tags="$(gh release list --limit 100 --json tagName --jq '.[].tagName')" \
    || refuse "gh could not list the releases"
  for tag in $tags; do
    gh release view "$tag" --json body --jq '.body' || refuse "gh could not read the notes of ${tag}"
  done
}

# is_named <number>: 0 when an earlier release's notes name the issue.
is_named() {
  printf '%s\n' "$NAMED" | grep -qxF "#$1"
}

# is_excluded <labels> <reason>: 0 when the issue is not part of a release.
is_excluded() {
  case ",$1," in
    *,decision,* | *,duplicate,* | *,invalid,* | *,wontfix,* | *,question,*) return 0 ;;
  esac
  [ "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" = "not_planned" ]
}

# label_bump <labels>: the highest of patch, minor, major in it; "other" when none.
label_bump() {
  case ",$1," in
    *,major,*) echo major ;;
    *,minor,*) echo minor ;;
    *,patch,*) echo patch ;;
    *) echo other ;;
  esac
}

RAW="$(fetch)" || { COMPLETED=1; exit 2; }
[ -n "$RAW" ] || refuse "no latest release found"
HEAD_LINE="$(printf '%s\n' "$RAW" | head -n 1)"
TAG="$(printf '%s' "$HEAD_LINE" | cut -f1)"
published="$(printf '%s' "$HEAD_LINE" | cut -f2)"
[ -n "$TAG" ] || refuse "no latest release found"
if ! [[ "$TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  refuse "the latest release '${TAG}' is not a vX.Y.Z tag"
fi
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

# A tab is white space to read, which would swallow an empty labels field: the
# fields are split on a unit separator instead.
SEP="$(printf '\037')"
NAMED="$(earlier_notes | grep -oE '#[0-9]+' | sort -u)" || NAMED="$(true)"
count=0
unlabelled=""
required_rank=1
rows=""
while IFS="$SEP" read -r number title labels closed reason; do
  [ -n "$number" ] || continue
  [[ "$closed" > "$published" ]] || continue
  if is_excluded "$labels" "$reason"; then
    continue
  fi
  if is_named "$number"; then
    continue
  fi
  bump="$(label_bump "$labels")"
  count=$((count + 1))
  if [ "$bump" = other ]; then
    unlabelled="${unlabelled}#${number} ${title}: label it patch, minor or major
"
    continue
  fi
  rank="$(rank_of "$bump")"
  if (( rank > required_rank )); then required_rank="$rank"; fi
  rows="${rows}${bump}	${number}	${title}
"
done <<< "$(printf '%s\n' "$RAW" | tail -n +2 | tr '\t' "$SEP")"

if (( count == 0 )); then
  stop "nothing was closed since ${TAG}"
fi

if [ -n "$unlabelled" ]; then
  printf '%s' "$unlabelled" | while IFS= read -r line; do
    echo "❌ FAIL: release plan: ${line}"
  done
  COMPLETED=1
  exit 1
fi

requested_rank="$(rank_of "$REQUESTED")"
required="patch"
[ "$required_rank" -eq 2 ] && required="minor"
[ "$required_rank" -eq 3 ] && required="major"

if (( requested_rank < required_rank )); then
  more=""
  while IFS="$(printf '\t')" read -r bump number title; do
    [ -n "$number" ] || continue
    if [ "$(rank_of "$bump")" -gt "$requested_rank" ]; then
      more="${more}${more:+, }#${number} (${bump}) ${title}"
    fi
  done <<< "$rows"
  stop "requested ${REQUESTED} is lower than required ${required}: ${more}"
fi

case "$REQUESTED" in
  major) NEXT="$((MAJOR + 1)).0.0" ;;
  minor) NEXT="${MAJOR}.$((MINOR + 1)).0" ;;
  *) NEXT="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
esac

NOTES=""
for group in major minor patch; do
  lines="$(printf '%s' "$rows" | awk -F'\t' -v g="$group" '$1 == g { printf "%08d\t- #%s %s\n", $2, $2, $3 }' | sort | cut -f2-)"
  [ -n "$lines" ] || continue
  heading="$(printf '%s' "$group" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')"
  NOTES="${NOTES}${NOTES:+
}### ${heading}
${lines}"
done

if [ -n "$NOTES_FILE" ]; then
  printf '%s\n' "$NOTES" > "$NOTES_FILE" || refuse "cannot write ${NOTES_FILE}"
fi

echo "OK: next version ${NEXT} (${count} issues closed since ${TAG}, ${REQUESTED} requested, ${required} required)"
echo "version=${NEXT}"
echo "tag=v${NEXT}"
echo "issues=$(printf '%s' "$rows" | awk -F'\t' '{ printf "%08d\t#%s\n", $2, $2 }' | sort | cut -f2 | tr '\n' ' ' | sed 's/ $//')"
echo "release notes:"
printf '%s\n' "$NOTES"
COMPLETED=1
