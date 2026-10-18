#!/usr/bin/env bash
# Scripts/release_precheck.sh
#
# Before you start a Release (forsgren#231, step 3): one read-only command that
# says whether a Release with this bump would pass its plan, and if not, which
# issues stop it. It writes nothing and changes nothing: it reads the latest
# release, the issues and the commits through gh and git, as the plan does.
#
# Usage: Scripts/release_precheck.sh [patch|minor|major]
# With no bump it judges the bump the labels require.
#
# It runs the SAME Scripts/release_plan.sh the Release runs, with --all so that
# the plan names every kind of block at once instead of the first kind:
#   - every open issue with commits on main since the latest release,
#   - every closed issue since it without a patch, minor or major label,
#   - every issue that needs a higher bump than the one asked,
# and, as a ✅ list, the issues that are ready (with their label). The table is
# rendered by Scripts/release_report.sh --table, the code that renders the
# Release run page (| Issue | Blocks because | Do |, with an icon column). There
# is no second implementation of either, so the pre-check and the Release
# cannot disagree: Scripts/test_release_precheck.sh feeds both the same data.
#
# Exit 0: a Release with that bump would pass the plan. Exit 1: it would stop.
# Exit 2: the plan could not judge (gh or git could not be read, a latest tag
# that is no vX.Y.Z, a usage error).
#
# Seams (the self-test): RELEASE_PLAN_DATA and its companions of
# release_plan.sh pass through; RELEASE_PRECHECK_SCRIPTS is the directory of the
# two scripts it calls (default: beside this one).
#
# Local invocation: ./Scripts/release_precheck.sh [patch|minor|major]

set -uo pipefail

COMPLETED=0
PLAN_OUT=""
trap '[ -z "$PLAN_OUT" ] || rm -f "$PLAN_OUT"; [ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_precheck.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="${RELEASE_PRECHECK_SCRIPTS:-$HERE}"

BUMP="${1:-auto}"
case "$BUMP" in
  patch | minor | major | auto) ;;
  *)
    echo "usage: Scripts/release_precheck.sh [patch|minor|major]" >&2
    COMPLETED=1
    exit 2
    ;;
esac
if [ "$#" -gt 1 ]; then
  echo "usage: Scripts/release_precheck.sh [patch|minor|major]" >&2
  COMPLETED=1
  exit 2
fi

# The issue links of the table need the repository; gh reads it. With the plan
# data seam there is no repository, and the issues are plain #N.
if [ -z "${GH_REPO:-}" ] && [ -z "${RELEASE_PLAN_DATA:-}" ] && command -v gh > /dev/null 2>&1; then
  GH_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2> /dev/null)" || GH_REPO=""
  export GH_REPO
fi

# The bump the table says the run asked for, as the Release run page does.
ASKED="$BUMP"
if [ "$BUMP" = auto ]; then ASKED="the bump the labels require"; fi

PLAN_OUT="$(mktemp)" || { echo "❌ FAIL: cannot create a temporary file" >&2; exit 2; }

"${SCRIPTS}/release_plan.sh" "$BUMP" --all > "$PLAN_OUT" 2>&1
rc=$?

echo "release precheck: bump ${BUMP}$([ "$BUMP" = auto ] && echo ' (the bump the labels require)')"
# The plan's own words, without its machine lines.
grep -vE '^(blocking|ready)=' "$PLAN_OUT" || true
echo
RELEASE_PLAN_OUTPUT="$PLAN_OUT" RELEASE_BUMP="$ASKED" "${SCRIPTS}/release_report.sh" --table "$PLAN_OUT" || {
  echo "❌ FAIL: release_report.sh --table could not render the plan's output"
  COMPLETED=1
  exit 2
}
echo

case "$rc" in
  0) echo "✅ a Release with this bump would pass the plan" ;;
  1) echo "❌ a Release with this bump would stop at its plan: do what the table says first" ;;
  *) echo "❌ the plan could not judge (exit ${rc}): read its output above" ;;
esac
COMPLETED=1
exit "$rc"
