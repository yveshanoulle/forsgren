#!/usr/bin/env bash
# Scripts/release_plan.sh
#
# What a release would be (forsgren#221, step 1 of 2): from the latest release
# and the issues closed since it, the bump the labels require, the check of
# the requested bump against it, the next version and the release notes.
#
# Usage: Scripts/release_plan.sh <patch|minor|major> [--notes <file>] [--all]
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
# (the highest of its labels). The highest requirement wins. An issue labelled
# tools and none of the three (forsgren#289, Yves's ruling: a tooling update
# needs no release) requires no bump and is no reason to stop: it is listed
# under ### Tooling in the notes of the next release, after the bump headings,
# and an issue with tools and a bump label counts by its bump label. An issue
# with none of patch, minor, major or tools cannot be judged: the plan stops
# and names every such issue.
#
# Red (exit 1, a ❌ line that names the reason):
#   - an OPEN issue of this repository has a commit on main since the latest
#     release (a `#N` or `forsgren#N` in the subject of a commit in
#     <latest tag>..HEAD; other repositories' references and the `release
#     X.Y.Z` bump commits do not count; an issue named in an earlier release's
#     notes does not count, nor an open tools issue without a bump label,
#     forsgren#289, whose code ships in the tag with no user-facing change):
#     every such issue is named, ascending, followed by
#     "close it, or split it (close the landed part as its own issue, move
#     the rest to a new one)". The release tags main as it is, so landed code
#     of an open issue ships while its notes and bump would miss it.
#   - nothing was closed since the latest release (tools issues included)
#   - an issue has no patch, minor, major or tools label: every one is named, followed
#     by "label it patch, minor or major"
#   - the requested bump is lower than the required one; the line names the
#     issues that require more
#   - a major (asked, or required with auto) while an agent file lacks a proof
#     run on the new major (forsgren#237, step 5b): every such file is named,
#     by Scripts/release_agent_proofs.sh
# Every red that names issues also prints one machine line per issue, from
# the same data (forsgren#232), for the run summary:
#   blocking=<N> TAB <kind> TAB <title> TAB <latest tag>
# kind: unlabelled, open-with-commits, or needs-<minor|major> (the issue's own
# bump label, one line per issue that requires more than was asked).
# Green (exit 0): `OK: next version X.Y.Z`, then the lines `version=X.Y.Z` and
# `tag=vX.Y.Z` and `issues=#3 #5` (the numbers, ascending) and `tools=#4 #6`
# (the tools issues, ascending; empty when none), then the release notes: one
# `- #N title` line per issue, grouped under ### Major, ### Minor, ### Patch
# and ### Tooling.
# With --notes the same notes are written to <file>.
# Nothing to release (exit 0, forsgren#289): only tools issues were closed
# since the latest release. `OK: nothing to release: only tools issues were
# closed since vX.Y.Z: #4 title, #6 title`, then `release=none` and
# `tools=#4 #6`; no version, no tag, no notes file. Release.yml skips every
# step that would tag or spread a release on `release=none`, and
# Scripts/release_precheck.sh says nothing to release. An open issue with
# commits (above) is still red first.
# With --all (forsgren#231, step 3, for Scripts/release_precheck.sh) the plan
# does not stop at the first kind of red: it names every open issue with
# commits, every unlabelled issue and every issue that needs more than was
# asked, prints one machine line per issue that is ready,
#   ready=<N> TAB <bump> TAB <title> TAB <latest tag>
# (a tools issue with the bump `tools`) and exits 1 when anything blocked, 0
# when not. The requested bump may then
# be `auto`: the bump the labels require. Without --all nothing changes. It
# reads and writes nothing else (the notes only with --notes).
# Exit 2: a usage error, or a latest release that is no vX.Y.Z tag.
#
# Data: from gh (latest release, closed issues, the bodies of the earlier
# releases). The seam for the self-test is RELEASE_PLAN_DATA, a file read
# instead of gh (RELEASE_PLAN_NOTES, a file with the earlier releases' notes,
# stands for their bodies; none when unset): the first line is the latest
# tag, TAB, its publish time (UTC, 2026-10-17T05:06:23Z); every other line is
# number, title, labels (comma separated), closed time, state reason, TAB
# separated.
# The open issues and the commits have a seam of their own, none when unset
# (while RELEASE_PLAN_DATA is set): RELEASE_PLAN_OPEN, a file with one open
# issue per line, number TAB title, and RELEASE_PLAN_COMMITS, a file with the
# subjects of the commits since the latest tag, one per line. An open issue
# line may carry a third field, its labels (comma separated). Without the seam
# they come from gh (open issues) and git log <latest tag>..HEAD.
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
ALL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --notes)
      [ "$#" -ge 2 ] || usage
      NOTES_FILE="$2"
      shift 2
      ;;
    --all)
      ALL=1
      shift
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
  auto) [ "$ALL" -eq 1 ] || usage ;;
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
    || return 1
  for tag in $tags; do
    gh release view "$tag" --json body --jq '.body' || return 1
  done
}

# open_issues: the open issues, number TAB title, from the seam or from gh.
open_issues() {
  if [ -n "${RELEASE_PLAN_DATA:-}" ]; then
    if [ -n "${RELEASE_PLAN_OPEN:-}" ]; then cat "$RELEASE_PLAN_OPEN"; fi
    return
  fi
  gh issue list --state open --limit 1000 --json number,title,labels \
    --jq '.[] | [.number, (.title | gsub("[\t\n]"; " ")), ([.labels[].name] | join(","))] | @tsv'
}

# commit_subjects <tag>: the subjects of the commits since the tag, from the seam or from git.
commit_subjects() {
  if [ -n "${RELEASE_PLAN_DATA:-}" ]; then
    if [ -n "${RELEASE_PLAN_COMMITS:-}" ]; then cat "$RELEASE_PLAN_COMMITS"; fi
    return
  fi
  git log --format=%s "${1}..HEAD"
}

# referenced: the issue numbers this repository's commit subjects name, as #N
# lines. The bump commits are skipped, and a reference with a prefix other
# than forsgren (another repository) is dropped.
referenced() {
  { grep -vE '^release [0-9]' || true; } \
    | sed -E 's/forsgren#/#/g; s/[A-Za-z0-9_.\/-]+#[0-9]+//g' \
    | { grep -oE '#[0-9]+' || true; } | sort -u
}

# is_named <number>: 0 when an earlier release's notes name the issue.
is_named() {
  grep -qxF -- "#$1" <<< "$NAMED"
}

# is_excluded <labels> <reason>: 0 when the issue is not part of a release.
is_excluded() {
  case ",$1," in
    *,decision,* | *,duplicate,* | *,invalid,* | *,wontfix,* | *,question,*) return 0 ;;
  esac
  [ "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" = "not_planned" ]
}

# machine_line <number> <kind> <title>: the machine form of a blocking issue,
# `blocking=<N> TAB <kind> TAB <title> TAB <latest tag>`. Every ❌ line that
# names an issue is printed together with it, from the same data, so the run
# summary (Scripts/release_report.sh) cannot disagree with the plan.
machine_line() {
  printf 'blocking=%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$TAG"
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

# is_tools_only <labels>: 0 when the issue is labelled tools and none of
# patch, minor or major (forsgren#289): it needs no bump and no release.
is_tools_only() {
  [ "$(label_bump "$1")" = other ] || return 1
  case ",$1," in
    *,tools,*) return 0 ;;
  esac
  return 1
}

# by_number: rows of `<kind> TAB <number> TAB <title>`, ascending by number.
by_number() {
  sort -t "$(printf '\t')" -k2,2n
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
NOTES_RAW="$(earlier_notes)" || stop "gh could not read the notes of the earlier releases"
NAMED="$({ grep -oE '#[0-9]+' <<< "$NOTES_RAW" || true; } | sort -u)"
count=0
unlabelled=""
required_rank=1
rows=""
tools_rows=""
while IFS="$SEP" read -r number title labels closed reason; do
  [ -n "$number" ] || continue
  [[ "$closed" > "$published" ]] || continue
  if is_excluded "$labels" "$reason"; then
    continue
  fi
  if is_named "$number"; then
    continue
  fi
  if is_tools_only "$labels"; then
    tools_rows="${tools_rows}tools	${number}	${title}
"
    continue
  fi
  bump="$(label_bump "$labels")"
  count=$((count + 1))
  if [ "$bump" = other ]; then
    unlabelled="${unlabelled}${number}	${title}
"
    continue
  fi
  rank="$(rank_of "$bump")"
  if (( rank > required_rank )); then required_rank="$rank"; fi
  rows="${rows}${bump}	${number}	${title}
"
done <<< "$(printf '%s\n' "$RAW" | tail -n +2 | tr '\t' "$SEP")"

# A source that cannot be read is red, never an empty list: the substitution
# runs at the top level so that stop can end the plan.
COMMIT_RAW="$(commit_subjects "$TAG")" || stop "git could not read the commits since ${TAG}"
OPEN_RAW="$(open_issues)" || stop "gh could not list the open issues"
COMMITTED="$(referenced <<< "$COMMIT_RAW")"
open_hits=""
while IFS="$SEP" read -r number title labels; do
  [ -n "$number" ] || continue
  grep -qxF -- "#${number}" <<< "$COMMITTED" || continue
  # An open tools issue ships in the tag with no user-facing change.
  if is_tools_only "$labels"; then continue; fi
  if is_named "$number"; then
    continue
  fi
  open_hits="${open_hits}❌ FAIL: release plan: #${number} ${title} is still open but has commits on main since ${TAG}: close it, or split it (close the landed part as its own issue, move the rest to a new one)
$(machine_line "$number" open-with-commits "$title")
"
done <<< "$(printf '%s\n' "$OPEN_RAW" | sort -t "$(printf '\t')" -k1,1n | tr '\t' "$SEP")"
# ready_lines: one machine line per labelled or tools issue, only under --all.
ready_lines() {
  [ "$ALL" -eq 1 ] || return 0
  while IFS="$(printf '\t')" read -r bump number title; do
    [ -n "$number" ] || continue
    printf 'ready=%s\t%s\t%s\t%s\n' "$number" "$bump" "$title" "$TAG"
  done <<< "$(printf '%s' "${rows}${tools_rows}" | by_number)"
}

# numbers_of <rows>: the issue numbers of the rows, `#3 #5`, ascending.
numbers_of() {
  printf '%s' "$1" | by_number | cut -f2 | sed 's/^/#/' | tr '\n' ' ' | sed 's/ $//'
}

# nothing_to_release: only tools issues were closed (forsgren#289), a green
# end with no version and no tag.
nothing_to_release() {
  local named
  named="$(printf '%s' "$tools_rows" | by_number | awk -F'\t' '{ printf "%s#%s %s", (NR > 1 ? ", " : ""), $2, $3 }')"
  echo "OK: nothing to release: only tools issues were closed since ${TAG}: ${named}"
  echo "release=none"
  echo "tools=$(numbers_of "$tools_rows")"
  ready_lines
  COMPLETED=1
  exit 0
}

ALL_RED=0
if [ -n "$open_hits" ]; then
  printf '%s' "$open_hits"
  if [ "$ALL" -ne 1 ]; then
    COMPLETED=1
    exit 1
  fi
  ALL_RED=1
fi

if (( count == 0 )); then
  [ -n "$tools_rows" ] || stop "nothing was closed since ${TAG}"
  if [ "$ALL_RED" -eq 1 ]; then
    ready_lines
    COMPLETED=1
    exit 1
  fi
  nothing_to_release
fi

if [ -n "$unlabelled" ]; then
  while IFS="$(printf '\t')" read -r number title; do
    [ -n "$number" ] || continue
    echo "❌ FAIL: release plan: #${number} ${title}: label it patch, minor or major"
    machine_line "$number" unlabelled "$title"
  done <<< "$unlabelled"
  if [ "$ALL" -ne 1 ]; then
    COMPLETED=1
    exit 1
  fi
  ALL_RED=1
fi

required="patch"
[ "$required_rank" -eq 2 ] && required="minor"
[ "$required_rank" -eq 3 ] && required="major"
if [ "$REQUESTED" = auto ]; then REQUESTED="$required"; fi
requested_rank="$(rank_of "$REQUESTED")"

if (( requested_rank < required_rank )); then
  more=""
  machine=""
  while IFS="$(printf '\t')" read -r bump number title; do
    [ -n "$number" ] || continue
    if [ "$(rank_of "$bump")" -gt "$requested_rank" ]; then
      more="${more}${more:+, }#${number} (${bump}) ${title}"
      machine="${machine}$(machine_line "$number" "needs-${bump}" "$title")
"
    fi
  done <<< "$rows"
  echo "❌ FAIL: release plan: requested ${REQUESTED} is lower than required ${required}: ${more}"
  printf '%s' "$machine"
  if [ "$ALL" -ne 1 ]; then
    COMPLETED=1
    exit 1
  fi
  ALL_RED=1
fi

# A major needs a proof run of every agent file on the new major
# (forsgren#237, step 5b): the rule lives where the major is decided, since no
# release bumps `var version` any more for a test to read.
if [ "$REQUESTED" = major ]; then
  NEW_MAJOR="$((MAJOR + 1))"
  if ! agent_out="$(./Scripts/release_agent_proofs.sh "$NEW_MAJOR" 2>&1)"; then
    echo "❌ FAIL: release plan: a major release (${NEW_MAJOR}.0.0) needs a proof run of every agent file on major ${NEW_MAJOR}:"
    printf '%s\n' "$agent_out"
    if [ "$ALL" -ne 1 ]; then
      COMPLETED=1
      exit 1
    fi
    ALL_RED=1
  fi
fi

if [ "$ALL_RED" -eq 1 ]; then
  ready_lines
  COMPLETED=1
  exit 1
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
if [ -n "$tools_rows" ]; then
  NOTES="${NOTES}
### Tooling
$(printf '%s' "$tools_rows" | by_number | awk -F'\t' '{ printf "- #%s %s\n", $2, $3 }')"
fi

if [ -n "$NOTES_FILE" ]; then
  printf '%s\n' "$NOTES" > "$NOTES_FILE" || refuse "cannot write ${NOTES_FILE}"
fi

tools_count="$(printf '%s' "$tools_rows" | grep -c . || true)"
tools_said=""
if [ "$tools_count" -gt 0 ]; then tools_said=", ${tools_count} tools issues"; fi
echo "OK: next version ${NEXT} (${count} issues closed since ${TAG}${tools_said}, ${REQUESTED} requested, ${required} required)"
echo "version=${NEXT}"
echo "tag=v${NEXT}"
echo "issues=$(numbers_of "$rows")"
echo "tools=$(numbers_of "$tools_rows")"
ready_lines
echo "release notes:"
printf '%s\n' "$NOTES"
COMPLETED=1
