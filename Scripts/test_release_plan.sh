#!/usr/bin/env bash
# Scripts/test_release_plan.sh
#
# Self-test for Scripts/release_plan.sh (forsgren#221, step 1 of 2): what a
# release would be, from the latest release and the issues closed since it.
# No network and no gh: the data comes through RELEASE_PLAN_DATA, a file in
# the shape the script reads (first line: tag, TAB, publish time; then one
# line per closed issue: number, title, labels, closed time, state reason,
# TAB separated). Each case asserts the OK line or the red line that NAMES
# its reason, so a red for the wrong reason fails.
#   1. patch issues, patch asked                  -> 1.9.4, a note per issue
#   2. a minor issue, minor asked                 -> 1.10.0, notes grouped
#   3. a major issue, major asked                 -> 2.0.0
#   4. a bump above the required one              -> the asked bump
#   5. patch asked, a minor or major issue closed -> red naming those issues
#   6. nothing closed since the release           -> red, also when every
#      closed issue is older than the publish time
#   7. decision / duplicate / invalid / wontfix / question issues and issues
#      closed as not planned                      -> never count, never raise
#   8. an issue without a patch, minor or major label -> red, every such
#      issue named, followed by "label it patch, minor or major"
#   8b. an issue that an earlier release's notes name -> never listed again
#      (RELEASE_PLAN_NOTES stands for the notes of the earlier releases)
#   9. --notes writes the notes to a file
#  9b. an OPEN issue with a commit on main since the release -> red, every
#      such issue named, ascending (RELEASE_PLAN_OPEN: number TAB title per
#      open issue; RELEASE_PLAN_COMMITS: one commit subject per line); open
#      issues without commits, ones an earlier release named, release-bump
#      commits and other repositories' references never count
#  11. a machine line per blocking issue, besides the human line:
#      blocking=<N> TAB <kind> TAB <title> TAB <latest tag>, kind unlabelled,
#      open-with-commits or needs-<bump> (forsgren#232)
#  13. a major (asked, or required with auto under --all) is refused until every
#      agent file has a proof run on the new major (forsgren#237, step 5b)
#  10. usage errors, a latest tag that is no vX.Y.Z -> exit 2
#  14. tools issues (forsgren#289, Yves's ruling: a tooling update needs no
#      release): an issue labelled tools and none of patch, minor or major
#      needs no bump and is not unlabelled; only tools issues closed -> exit 0,
#      nothing to release, every one named, `release=none` and `tools=#N ...`,
#      no version and no tag; tools with a feature issue -> the feature's bump,
#      the tools issues under ### Tooling after the bump headings (notes file
#      too) and in `tools=`; tools plus a bump label counts by the bump label;
#      an OPEN tools issue with commits is no red, an open feature issue (or
#      tools plus a bump label) still is (RELEASE_PLAN_OPEN's optional third
#      field: the labels, comma separated); --all prints a ready line per tools
#      issue with the bump `tools`
# Mutation proofs: a copy that accepts a lower bump, one that accepts nothing
# closed, one without the exclusion, one that judges a tools issue unlabelled,
# one that releases a tools-only set, one without the ### Tooling notes, one
# that lets an open tools issue with commits stop the plan, one without the publish-time filter, one
# that lets an unlabelled issue pass and one that lists an issue an earlier
# release named, one that names only the first open issue with commits and one
# that ignores the earlier releases for open issues, and one that never asks for
# the agent proofs of a major must each let the case they exist for pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release plan self-test"

PLAN="Scripts/release_plan.sh"
[[ -f "$PLAN" ]] || selftest_abort "${PLAN} does not exist — nothing checks a release against the issues closed since the last one"

TAB=$'\t'
PUBLISHED="2026-10-17T05:06:23Z"
AFTER="2026-10-17T09:00:00Z"
BEFORE="2026-10-16T09:00:00Z"

# data <issue-line>...: the fixture, the latest release first.
data() {
  { printf 'v1.9.3%s%s\n' "$TAB" "$PUBLISHED"; for line in "$@"; do printf '%s\n' "$line"; done; } > "${TMP}/data.tsv"
}

# issue <number> <title> <labels> [closed [reason]]: one fixture line.
issue() {
  printf '%s%s%s%s%s%s%s%s%s' "$1" "$TAB" "$2" "$TAB" "$3" "$TAB" "${4:-$AFTER}" "$TAB" "${5:-completed}"
}

# The agent files a major release checks (forsgren#237, step 5b): fixtures in
# the shape of the real ones, one set already proved on major 2, one still on
# major 1. RELEASE_AGENT_FILES stands for the repository's agent-*.md.
mkdir -p "${TMP}/agents_ready" "${TMP}/agents_old"
printf '# Agent\n\nTested with: forsgren v2.0.1, Claude Code, model claude-sonnet-5-5.\n' > "${TMP}/agents_ready/agent-one.md"
printf '# Agent\n\nTested with: forsgren v0.8.5 \xe2\x86\x92 v2.0.0, Claude Code, model claude-sonnet-5-5.\n' > "${TMP}/agents_ready/agent-two.md"
printf '# Agent\n\nTested with: forsgren v1.3.2, Claude Code, model claude-sonnet-5-5.\n' > "${TMP}/agents_old/agent-one.md"
printf '# Agent\n\nTested with: forsgren v0.8.5 \xe2\x86\x92 v1.3.0, Claude Code, model claude-sonnet-5-5.\n' > "${TMP}/agents_old/agent-two.md"
printf '# Agent\n\nNo proof line.\n' > "${TMP}/agents_old/agent-three.md"
AGENTS_READY="${TMP}/agents_ready/agent-one.md ${TMP}/agents_ready/agent-two.md"

# plan <script> <args>...: capture the script on the fixture. The agent files
# are proved on major 2 unless AGENTS says otherwise.
plan() {
  local script="$1"
  shift
  RELEASE_AGENT_FILES="${AGENTS:-$AGENTS_READY}" RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "$script" "$@"
}

# 1
data "$(issue 5 'Fix the thing' patch)" "$(issue 3 'Fix another thing' patch)"
plan "$PLAN" patch
want_green "patch issues, patch asked" "OK: next version 1.9.4"
want_said "the version line is machine readable" "version=1.9.4"
want_said "the tag line is machine readable" "tag=v1.9.4"
want_said "a note per issue, as #N title" "- #5 Fix the thing"
want_said "the notes are in issue order" "- #3 Fix another thing"
if [[ "$(grep -n -F -- '- #3 ' <<< "$OUT" | cut -d: -f1)" -ge "$(grep -n -F -- '- #5 ' <<< "$OUT" | cut -d: -f1)" ]]; then
  fail "the notes are not in issue order (#3 before #5). Output: ${OUT}"
fi

# 2
data "$(issue 7 'Add a view' minor)" "$(issue 8 'Fix a typo' patch)"
plan "$PLAN" minor
want_green "a minor issue, minor asked" "OK: next version 1.10.0"
want_said "the minor group has its heading" "### Minor"
want_said "the patch group has its heading" "### Patch"

# 3
data "$(issue 9 'Rename a flag' major)"
plan "$PLAN" major
want_green "a major issue, major asked" "OK: next version 2.0.0"

# 4
data "$(issue 5 'Fix the thing' patch)"
plan "$PLAN" minor
want_green "minor asked for a patch-only set" "OK: next version 1.10.0"
plan "$PLAN" major
want_green "major asked for a patch-only set" "OK: next version 2.0.0"

# 5
data "$(issue 5 'Fix the thing' patch)" "$(issue 12 'Add a view' minor)" "$(issue 15 'Rename a flag' major)"
plan "$PLAN" patch
want_red "patch asked, minor and major issues closed" "requested patch is lower than required major"
want_said "the minor issue is named" "#12"
want_said "the major issue is named" "#15"
data "$(issue 5 'Fix the thing' patch)" "$(issue 12 'Add a view' minor)" "$(issue 15 'Rename a flag' major)"
plan "$PLAN" minor
want_red "minor asked, a major issue closed" "requested minor is lower than required major: #15"
if grep -qF '#12' <<< "$OUT"; then fail "the minor issue is named although minor was asked. Output: ${OUT}"; fi
data "$(issue 12 'Add a view' minor)"
plan "$PLAN" patch
want_red "patch asked, a minor issue closed" "requested patch is lower than required minor: #12"

# 6
data
plan "$PLAN" patch
want_red "nothing closed since the release" "nothing was closed since v1.9.3"
data "$(issue 5 'Fix the thing' patch "$BEFORE")" "$(issue 6 'Fix it at the same second' patch "$PUBLISHED")"
plan "$PLAN" patch
want_red "only issues closed before or at the publish time" "nothing was closed since v1.9.3"

# 7
data "$(issue 20 'A ruling' 'decision,major')" "$(issue 21 'Same thing' 'duplicate,minor')" \
  "$(issue 22 'Not a bug' 'invalid,minor')" "$(issue 23 'Never' 'wontfix,minor')" \
  "$(issue 24 'A question' 'question,minor')" "$(issue 25 'Dropped' 'minor' "$AFTER" not_planned)"
plan "$PLAN" patch
want_red "only excluded issues" "nothing was closed since v1.9.3"
data "$(issue 20 'A ruling' 'decision,major')" "$(issue 25 'Dropped' 'minor' "$AFTER" NOT_PLANNED)" "$(issue 5 'Fix the thing' patch)"
plan "$PLAN" patch
want_green "excluded issues never raise the required bump" "OK: next version 1.9.4"
if grep -qE '#20|#25' <<< "$OUT"; then fail "an excluded issue is in the output. Output: ${OUT}"; fi

# 8
data "$(issue 30 'No label' '')" "$(issue 31 'Other label' 'docs')" "$(issue 5 'Fix the thing' patch)"
plan "$PLAN" patch
want_red "issues without a bump label" "#30 No label: label it patch, minor or major"
want_said "every unlabelled issue is named" "#31 Other label: label it patch, minor or major"
if grep -qF '#5 ' <<< "$OUT"; then fail "a labelled issue is named among the unlabelled ones. Output: ${OUT}"; fi
if grep -qF 'OK:' <<< "$OUT"; then fail "the plan says OK although issues have no label. Output: ${OUT}"; fi
data "$(issue 30 'No label' 'decision')"
plan "$PLAN" patch
want_red "an excluded issue without a bump label is no reason to stop" "nothing was closed since v1.9.3"

# 8b
printf 'forsgren 1.9.3\n\n- Favicon ([#218](https://github.com/acme/app/issues/218)).\nFrom #209 and #210.\n' > "${TMP}/notes_before.md"
data "$(issue 218 'Favicon' patch)" "$(issue 223 'Live check' patch)" "$(issue 2090 'Not 209' patch)"
RELEASE_PLAN_NOTES="${TMP}/notes_before.md" plan "$PLAN" patch
want_green "an issue an earlier release named" "OK: next version 1.9.4"
want_said "the others are listed" "- #223 Live check"
want_said "an issue number that only starts like a named one is listed" "- #2090 Not 209"
if grep -qF '#218' <<< "$OUT"; then fail "#218 was named by an earlier release and is listed again. Output: ${OUT}"; fi
data "$(issue 218 'Favicon' patch)" "$(issue 209 'Gates' 'minor')"
RELEASE_PLAN_NOTES="${TMP}/notes_before.md" plan "$PLAN" patch
want_red "only issues earlier releases named" "nothing was closed since v1.9.3"
data "$(issue 5 'Fix the thing' patch)"
RELEASE_PLAN_NOTES="${TMP}/notes_before.md" plan "$PLAN" patch
want_said "the issue numbers are a machine readable line" "issues=#5"

data "$(issue 32 'No label, old' '' "$BEFORE")"
plan "$PLAN" patch
want_red "an issue without labels is still judged by its closed time" "nothing was closed since v1.9.3"

# 9
data "$(issue 5 'Fix the thing' patch)"
plan "$PLAN" patch --notes "${TMP}/notes.md"
want_green "--notes" "OK: next version 1.9.4"
if [[ "$(cat "${TMP}/notes.md")" != $'### Patch\n- #5 Fix the thing' ]]; then
  fail "--notes did not write the grouped notes. File: $(cat "${TMP}/notes.md")"
else
  echo "  ok: the notes file holds the grouped notes"
fi

# 9b
printf '%s\t%s\n' 40 'Half landed' 41 'Also half landed' 42 'No commits yet' 218 'Named before' > "${TMP}/open.tsv"
printf 'Step 1 of #40 (1/2): first part\nrelease 1.9.4 for #42\nfixes forsgren#41 too\nother-repo#42 only\nacme/app#42 only\nwork on #218\n' > "${TMP}/commits.txt"
open_plan() { RELEASE_PLAN_OPEN="${TMP}/open.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits.txt" plan "$@"; }
data "$(issue 5 'Fix the thing' patch)"
printf 'From #218.\n' > "${TMP}/notes_open.md"
RELEASE_PLAN_NOTES="${TMP}/notes_open.md" open_plan "$PLAN" patch
want_red "an open issue with a commit on main" "release plan: #40 Half landed is still open but has commits on main since v1.9.3: close it, or split it (close the landed part as its own issue, move the rest to a new one)"
want_said "the forsgren#N form counts, every issue is named" "release plan: #41 Also half landed is still open but has commits on main since v1.9.3"
if grep -qE '#42|#218|OK:' <<< "$OUT"; then fail "#42 (bump or other repository only), #218 (named earlier) or OK: is in the output. Output: ${OUT}"; fi
if [[ "$(grep -n -F -- '#40 ' <<< "$OUT" | cut -d: -f1)" -ge "$(grep -n -F -- '#41 ' <<< "$OUT" | cut -d: -f1)" ]]; then
  fail "the open issues are not in ascending order. Output: ${OUT}"
fi
printf '%s\t%s\n' 50 'Only one' 51 'No commit' > "${TMP}/open_one.tsv"
printf 'First #50\n' > "${TMP}/commits_one.txt"
RELEASE_PLAN_OPEN="${TMP}/open_one.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits_one.txt" plan "$PLAN" patch
want_red "one open issue with a commit" "release plan: #50 Only one is still open but has commits on main since v1.9.3"
if grep -qF '#51' <<< "$OUT"; then fail "an open issue without commits is named. Output: ${OUT}"; fi
printf 'Work on #99\n' > "${TMP}/commits_none.txt"
RELEASE_PLAN_OPEN="${TMP}/open_one.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits_none.txt" plan "$PLAN" patch
want_green "open issues without commits on main" "OK: next version 1.9.4"
data "$(issue 50 'Only one' patch)"
RELEASE_PLAN_OPEN="${TMP}/open_one.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits_one.txt" plan "$PLAN" patch
want_red "the same number open again does not matter, the open list rules" "release plan: #50 Only one is still open"
: > "${TMP}/open_none.tsv"
RELEASE_PLAN_OPEN="${TMP}/open_none.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits_one.txt" plan "$PLAN" patch
want_green "a closed issue with a commit is unaffected" "OK: next version 1.9.4"

# 9c: a source that cannot be read is red, never an empty list
data "$(issue 5 'Fix the thing' patch)"
RELEASE_PLAN_OPEN="${TMP}/open_one.tsv" RELEASE_PLAN_COMMITS="${TMP}/does_not_exist.txt" plan "$PLAN" patch
want_red "the commits cannot be read" "release plan: git could not read the commits since v1.9.3"
RELEASE_PLAN_OPEN="${TMP}/does_not_exist.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits_one.txt" plan "$PLAN" patch
want_red "the open issues cannot be read" "release plan: gh could not list the open issues"
RELEASE_PLAN_NOTES="${TMP}/does_not_exist.md" plan "$PLAN" patch
want_red "the earlier releases' notes cannot be read" "release plan: gh could not read the notes of the earlier releases"
plan "$PLAN" patch
want_green "RELEASE_PLAN_NOTES unset means no earlier notes" "OK: next version 1.9.4"
RELEASE_PLAN_NOTES="${TMP}/does_not_exist.md" plan "$PLAN" patch
if grep -qF 'OK:' <<< "$OUT"; then fail "the plan says OK although a source could not be read. Output: ${OUT}"; fi

# 10
plan "$PLAN"
want_exit "no bump" 2 "usage"
plan "$PLAN" huge
want_exit "unknown bump" 2 "usage"
plan "$PLAN" patch --unknown
want_exit "unknown option" 2 "usage"
printf 'latest\t%s\n' "$PUBLISHED" > "${TMP}/data.tsv"
plan "$PLAN" patch
want_exit "latest release that is no vX.Y.Z" 2 "not a vX.Y.Z tag"
: > "${TMP}/data.tsv"
plan "$PLAN" patch
want_exit "no latest release at all" 2 "no latest release"

# 11: one machine line per blocking issue, besides the human line:
# blocking=<N> TAB <kind> TAB <title> TAB <latest tag>
blocking() { printf 'blocking=%s%s%s%s%s%s%s' "$1" "$TAB" "$2" "$TAB" "$3" "$TAB" "v1.9.3"; }
data "$(issue 30 'No label' '')" "$(issue 31 'Other label' 'docs')" "$(issue 5 'Fix the thing' patch)"
plan "$PLAN" patch
want_said "unlabelled: the human line is unchanged" "release plan: #30 No label: label it patch, minor or major"
want_said "unlabelled: the first machine line" "$(blocking 30 unlabelled 'No label')"
want_said "unlabelled: the second machine line" "$(blocking 31 unlabelled 'Other label')"
if grep -qF 'blocking=5'"$TAB" <<< "$OUT"; then fail "a labelled issue has a machine line. Output: ${OUT}"; fi
printf '%s\t%s\n' 40 'Half landed' 41 'Also half landed' 42 'No commits yet' > "${TMP}/open.tsv"
printf 'Step 1 of #40\nfixes forsgren#41 too\n' > "${TMP}/commits.txt"
data "$(issue 5 'Fix the thing' patch)"
RELEASE_PLAN_OPEN="${TMP}/open.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits.txt" plan "$PLAN" patch
want_said "open with commits: the human line is unchanged" "release plan: #40 Half landed is still open but has commits on main since v1.9.3: close it, or split it"
want_said "open with commits: the first machine line" "$(blocking 40 open-with-commits 'Half landed')"
want_said "open with commits: the second machine line" "$(blocking 41 open-with-commits 'Also half landed')"
if grep -qF 'blocking=42'"$TAB" <<< "$OUT"; then fail "an open issue without commits has a machine line. Output: ${OUT}"; fi
data "$(issue 5 'Fix the thing' patch)" "$(issue 12 'Add a view' minor)" "$(issue 15 'Rename a flag' major)"
plan "$PLAN" patch
want_red "bump too low: the human line is unchanged" "requested patch is lower than required major: #12 (minor) Add a view, #15 (major) Rename a flag"
want_said "bump too low: the minor issue" "$(blocking 12 needs-minor 'Add a view')"
want_said "bump too low: the major issue" "$(blocking 15 needs-major 'Rename a flag')"
if grep -qF 'blocking=5'"$TAB" <<< "$OUT"; then fail "a patch issue has a machine line although patch was asked. Output: ${OUT}"; fi
plan "$PLAN" minor
want_said "bump too low: only the issue that requires more" "$(blocking 15 needs-major 'Rename a flag')"
if grep -qF 'blocking=12'"$TAB" <<< "$OUT"; then fail "the minor issue has a machine line although minor was asked. Output: ${OUT}"; fi
data
plan "$PLAN" patch
if grep -qF 'blocking=' <<< "$OUT"; then fail "nothing closed names an issue. Output: ${OUT}"; fi
data "$(issue 5 'Fix the thing' patch)"
plan "$PLAN" patch
if grep -qF 'blocking=' <<< "$OUT"; then fail "a green plan has a machine line. Output: ${OUT}"; fi

# 14. tools issues need no release (forsgren#289)
data "$(issue 60 'Gate tweak' tools)" "$(issue 61 'CI fix' tools)"
plan "$PLAN" patch
want_exit "only tools issues closed: nothing to release, not a failure" 0 "OK: nothing to release: only tools issues were closed since v1.9.3: #60 Gate tweak, #61 CI fix"
want_said "only tools issues: the machine line says there is no release" "release=none"
want_said "only tools issues: they are named in a machine line" "tools=#60 #61"
if grep -qE '^(version|tag|issues)=|label it' <<< "$OUT"; then fail "a tools-only set planned a version or called a tools issue unlabelled. Output: ${OUT}"; else echo "  ok: a tools-only set plans no version and no tag"; fi
plan "$PLAN" major
want_exit "only tools issues, major asked: still nothing to release" 0 "OK: nothing to release"
data "$(issue 60 'Gate tweak' tools)"
plan "$PLAN" patch --notes "${TMP}/notes_tools_only.md"
want_exit "only tools issues with --notes" 0 "OK: nothing to release"
if [[ -e "${TMP}/notes_tools_only.md" ]]; then fail "nothing to release still wrote a notes file"; else echo "  ok: nothing to release writes no notes file"; fi
data "$(issue 5 'Fix the thing' patch)" "$(issue 60 'Gate tweak' tools)" "$(issue 4 'Old CI fix' tools)"
plan "$PLAN" patch --notes "${TMP}/notes_tools.md"
want_green "a patch issue and tools issues: a patch" "OK: next version 1.9.4"
want_said "a patch and tools: the patch issue is listed" "- #5 Fix the thing"
want_said "a patch and tools: the tools issues are listed" "- #60 Gate tweak"
want_said "a patch and tools: the issues line holds the patch issue" "issues=#5"
want_said "a patch and tools: the tools line holds the tools issues" "tools=#4 #60"
if [[ "$(cat "${TMP}/notes_tools.md" 2> /dev/null)" != $'### Patch\n- #5 Fix the thing\n### Tooling\n- #4 Old CI fix\n- #60 Gate tweak' ]]; then
  fail "the notes do not put the tools issues under ### Tooling after the bump headings. File: $(cat "${TMP}/notes_tools.md" 2> /dev/null)"
else
  echo "  ok: the notes put the tools issues under ### Tooling, after the bump headings"
fi
data "$(issue 62 'Both' 'tools,minor')" "$(issue 60 'Gate tweak' tools)"
plan "$PLAN" minor
want_green "tools and minor on one issue: it counts by the bump label" "OK: next version 1.10.0"
if [[ "$(grep -A1 -xF '### Minor' <<< "$OUT" | tail -n 1)" == "- #62 Both" ]]; then echo "  ok: tools and minor on one issue: listed under Minor"; else fail "tools and minor on one issue: #62 is not under ### Minor. Output: ${OUT}"; fi
plan "$PLAN" patch
want_red "tools and minor on one issue, patch asked" "requested patch is lower than required minor: #62 (minor) Both"
data "$(issue 5 'Fix the thing' patch)"
printf '70\tTooling work\ttools\n' > "${TMP}/open_tools.tsv"
printf 'forsgren#70 (1/2): gate work\n' > "${TMP}/commits_tools.txt"
RELEASE_PLAN_OPEN="${TMP}/open_tools.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits_tools.txt" plan "$PLAN" patch
want_green "an open tools issue with commits is no red" "OK: next version 1.9.4"
if grep -qF '#70' <<< "$OUT"; then fail "an open tools issue with commits is named. Output: ${OUT}"; fi
printf '71\tFeature work\tminor\n72\tBoth work\ttools,patch\n73\tNo labels\t\n' > "${TMP}/open_feature.tsv"
printf 'forsgren#71 (1/2): view\nforsgren#72 (1/2): both\nforsgren#73 (1/2): bare\n' > "${TMP}/commits_feature.txt"
RELEASE_PLAN_OPEN="${TMP}/open_feature.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits_feature.txt" plan "$PLAN" patch
want_red "an open feature issue with commits is still red" "release plan: #71 Feature work is still open but has commits on main since v1.9.3"
want_said "an open tools and patch issue with commits is still red" "release plan: #72 Both work is still open but has commits on main since v1.9.3"
want_said "an open issue without labels is still red" "release plan: #73 No labels is still open but has commits on main since v1.9.3"
data "$(issue 60 'Gate tweak' tools)"
RELEASE_PLAN_OPEN="${TMP}/open_feature.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits_feature.txt" plan "$PLAN" patch
want_red "only tools closed but an open feature issue with commits: still red" "release plan: #71 Feature work is still open"
if grep -qF 'release=none' <<< "$OUT"; then fail "a red plan also said nothing to release. Output: ${OUT}"; fi
data "$(issue 5 'Fix the thing' patch)" "$(issue 60 'Gate tweak' tools)"
plan "$PLAN" auto --all
want_green "--all: a tools issue is ready" "ready=60${TAB}tools${TAB}Gate tweak${TAB}v1.9.3"
want_said "--all: the patch issue is ready" "ready=5${TAB}patch${TAB}Fix the thing${TAB}v1.9.3"
data "$(issue 60 'Gate tweak' tools)"
plan "$PLAN" auto --all
want_exit "--all, only tools issues: nothing to release" 0 "release=none"
want_said "--all, only tools issues: the ready line" "ready=60${TAB}tools${TAB}Gate tweak${TAB}v1.9.3"

# Mutation proofs: each mutant must let its case pass.
mutant_runs() {
  # <name> <sed> <case> <reason>: the mutant on the fixture the case uses
  local name="$1" expr="$2"
  selftest_mutant "$PLAN" "${TMP}/mut/${name}/release_plan.sh" "$expr" || return 1
  RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "${TMP}/mut/${name}/release_plan.sh" "${@:3}"
}

data "$(issue 12 'Add a view' minor)"
if mutant_runs lower 's/if (( requested_rank < required_rank )); then/if (( 0 )); then/' patch; then
  if [[ "$RC" -eq 0 ]] && grep -qF "OK: next version 1.9.4" <<< "$OUT"; then
    echo "  ok: mutation proof: without the comparison a patch is accepted for a minor issue"
  else
    fail "mutation proof: the mutant without the comparison still refused (exit ${RC}). Output: ${OUT}"
  fi
fi

data
if mutant_runs empty 's/if (( count == 0 )); then/if (( 0 )); then/' patch; then
  if grep -qF "nothing was closed" <<< "$OUT"; then
    fail "mutation proof: the mutant without the nothing-closed check still said it. Output: ${OUT}"
  else
    echo "  ok: mutation proof: without the check nothing closed is no longer refused"
  fi
fi

data "$(issue 20 'A ruling' 'decision,major')"
if mutant_runs excl 's/if is_excluded ".labels" ".reason"; then/if false; then/' patch; then
  want_red "mutation proof: without the exclusion a decision issue raises the bump" "requested patch is lower than required major: #20"
fi

data "$(issue 5 'Fix the thing' patch "$BEFORE")"
if mutant_runs timefilter 's/\[\[ ".closed" > ".published" \]\] || continue/true || continue/' patch; then
  want_green "mutation proof: without the publish-time filter an old issue is released again" "OK: next version 1.9.4"
fi

data "$(issue 30 'No label' '')"
if mutant_runs unlabelled "s/if \[ \".bump\" = other \]; then/if false; then/" patch; then
  if [[ "$RC" -eq 0 ]] && grep -qF "OK: next version" <<< "$OUT"; then
    echo "  ok: mutation proof: without the check an unlabelled issue passes"
  else
    fail "mutation proof: the mutant without the label check still refused (exit ${RC}). Output: ${OUT}"
  fi
fi

data "$(issue 218 'Favicon' patch)"
if selftest_mutant "$PLAN" "${TMP}/mut/named/release_plan.sh" "s/if is_named \".number\"; then/if false; then/"; then
  RELEASE_PLAN_NOTES="${TMP}/notes_before.md" RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "${TMP}/mut/named/release_plan.sh" patch
  want_green "mutation proof: without the filter an issue an earlier release named is released again" "- #218 Favicon"
fi

printf '%s\t%s\n' 40 'Half landed' 41 'Also half landed' > "${TMP}/open.tsv"
printf 'Step of #40\nStep of #41\n' > "${TMP}/commits.txt"
data "$(issue 5 'Fix the thing' patch)"
if selftest_mutant "$PLAN" "${TMP}/mut/first/release_plan.sh" "/^open_hits=/,/^done/ s/^\"\$/\"; break/"; then :; fi
RELEASE_PLAN_OPEN="${TMP}/open.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits.txt" RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "${TMP}/mut/first/release_plan.sh" patch
if grep -qF '#41' <<< "$OUT"; then
  fail "mutation proof: the mutant that stops at the first open issue still named the second. Output: ${OUT}"
else
  echo "  ok: mutation proof: a plan that names only the first open issue leaves the second out"
fi
printf 'From #218.\n' > "${TMP}/notes_open.md"
printf '%s\t%s\n' 218 'Named before' > "${TMP}/open.tsv"
printf 'Work on #218\n' > "${TMP}/commits.txt"
if selftest_mutant "$PLAN" "${TMP}/mut/openNamed/release_plan.sh" "/^open_hits=/,/^done/ s/if is_named \".number\"; then/if false; then/"; then
  RELEASE_PLAN_NOTES="${TMP}/notes_open.md" RELEASE_PLAN_OPEN="${TMP}/open.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits.txt" RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "${TMP}/mut/openNamed/release_plan.sh" patch
  want_red "mutation proof: without the exclusion an open issue an earlier release named stops the plan" "release plan: #218 Named before is still open"
fi

data "$(issue 5 'Fix the thing' patch)"
if selftest_mutant "$PLAN" "${TMP}/mut/unread/release_plan.sh" "s/ || stop \"git could not read.*/ || COMMIT_RAW=\"\"/"; then
  RELEASE_PLAN_OPEN="${TMP}/open_one.tsv" RELEASE_PLAN_COMMITS="${TMP}/does_not_exist.txt" RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "${TMP}/mut/unread/release_plan.sh" patch
  if [[ "$RC" -eq 0 ]] && ! grep -qF "git could not read the commits" <<< "$OUT"; then
    echo "  ok: mutation proof: with a fallback an unreadable commit source passes unchecked"
  else
    fail "mutation proof: the mutant with the fallback still stopped (exit ${RC}). Output: ${OUT}"
  fi
fi

if selftest_mutant "$PLAN" "${TMP}/mut/notes/release_plan.sh" "s/ || stop \"gh could not read the notes.*/ || NOTES_RAW=\"\"/"; then
  RELEASE_PLAN_NOTES="${TMP}/does_not_exist.md" RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "${TMP}/mut/notes/release_plan.sh" patch
  if [[ "$RC" -eq 0 ]] && ! grep -qF "gh could not read the notes" <<< "$OUT"; then
    echo "  ok: mutation proof: with a fallback unreadable earlier notes pass unchecked"
  else
    fail "mutation proof: the mutant with the fallback still stopped (exit ${RC}). Output: ${OUT}"
  fi
fi

# The machine line of an open issue with commits is dropped: the case above
# (11) names the missing issue.
printf '%s\t%s\n' 40 'Half landed' > "${TMP}/open.tsv"
printf 'Step 1 of #40\n' > "${TMP}/commits.txt"
data "$(issue 5 'Fix the thing' patch)"
if selftest_mutant "$PLAN" "${TMP}/mut/nomachine/release_plan.sh" "s/machine_line \"\$number\" open-with-commits/:/"; then
  RELEASE_PLAN_OPEN="${TMP}/open.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits.txt" RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "${TMP}/mut/nomachine/release_plan.sh" patch
  if grep -qF "$(blocking 40 open-with-commits 'Half landed')" <<< "$OUT"; then
    fail "mutation proof: the mutant still has the machine line of #40. Output: ${OUT}"
  else
    echo "  ok: mutation proof: a plan without the machine line leaves #40 out, and case 11 names it"
  fi
fi

# 13. A major release needs a proof run of every agent file on the new major
# (forsgren#237, step 5b; it was a Go test on the version in main.go, which no
# release bumps any more): the plan refuses a major until each agent file has
# one, naming each file, and plans nothing.
data "$(issue 9 'Rename a flag' major)"
AGENTS="${TMP}/agents_old/agent-one.md ${TMP}/agents_old/agent-two.md" plan "$PLAN" major
want_red "a major, the agent files proved on major 1" "a major release (2.0.0) needs a proof run of every agent file on major 2"
want_said "the first stale file is named with its major" "agent-one.md was tested on forsgren major 1"
want_said "the arrow form reads its last version" "agent-two.md was tested on forsgren major 1"
want_said "it says what to do" "run a new proof and update its Tested-with line"
if grep -qE '^(OK|version=)' <<< "$OUT"; then fail "a refused major still printed a version. Output: ${OUT}"; else echo "  ok: a refused major plans no version"; fi
AGENTS="${TMP}/agents_old/agent-three.md" plan "$PLAN" major
want_red "a major, an agent file with no Tested-with line" "agent-three.md has no Tested-with line to read a major from"
data "$(issue 9 'Rename a flag' major)"
plan "$PLAN" major
want_green "a major, every agent file proved on major 2" "OK: next version 2.0.0"
data "$(issue 5 'Fix the thing' patch)"
AGENTS="${TMP}/agents_old/agent-one.md" plan "$PLAN" patch
want_green "a patch ignores the agent files" "OK: next version 1.9.4"
AGENTS="${TMP}/agents_old/agent-one.md" plan "$PLAN" minor
want_green "a minor ignores the agent files" "OK: next version 1.10.0"
data "$(issue 9 'Rename a flag' major)"
AGENTS="${TMP}/agents_old/agent-one.md" plan "$PLAN" patch
want_red "a major issue with patch asked still names the bump first" "requested patch is lower than required major"
AGENTS="${TMP}/agents_old/agent-one.md" plan "$PLAN" auto --all
want_exit "--all with auto: the major the labels require is refused too" 1 "a major release (2.0.0) needs a proof run of every agent file on major 2"
want_said "--all with auto still prints a ready line" "ready=9${TAB}major${TAB}Rename a flag${TAB}v1.9.3"

# 12. --all (forsgren#231, step 3): every kind of block at once, a ready line
# per labelled issue; without --all the same data stops at the first kind.
data "$(issue 5 'Fix the thing' patch)" "$(issue 6 'Unlabelled thing' '')" "$(issue 7 'New feature' minor)"
printf '9%sHalf landed\n' "$TAB" > "${TMP}/open12.tsv"
printf 'forsgren#9 (1/1): work\n' > "${TMP}/commits12.txt"
RELEASE_PLAN_OPEN="${TMP}/open12.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits12.txt" plan "$PLAN" patch --all
want_exit "--all names the open issue with commits" 1 "blocking=9"
want_said "--all names the unlabelled issue too" "blocking=6${TAB}unlabelled"
want_said "--all names the issue that needs more too" "blocking=7${TAB}needs-minor"
want_said "--all prints a ready line per labelled issue" "ready=5${TAB}patch${TAB}Fix the thing${TAB}v1.9.3"
RELEASE_PLAN_OPEN="${TMP}/open12.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits12.txt" plan "$PLAN" patch
if grep -qF "blocking=6" <<< "$OUT"; then fail "without --all the plan named a second kind of block"; else echo "  ok: without --all the plan stops at the first kind, as the Release needs"; fi

# A plan that never asks for the agent proofs plans a major on stale agent files.
data "$(issue 9 'Rename a flag' major)"
if selftest_mutant "$PLAN" "${TMP}/mut/noproofs/release_plan.sh" 's/^if \[ "[$]REQUESTED" = major \]; then$/if false; then/'; then
  RELEASE_AGENT_FILES="${TMP}/agents_old/agent-one.md" RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "${TMP}/mut/noproofs/release_plan.sh" major
  want_green "mutation proof: without the agent proof check a major is planned on stale agent files" "OK: next version 2.0.0"
fi

# Tools issues (forsgren#289): each mutant must let its case pass, for the reason.
data "$(issue 60 'Gate tweak' tools)"
if mutant_runs toolsUnlabelled 's/^  if is_tools_only "[$]labels"; then$/  if false; then/' patch; then
  want_red "mutation proof: without the tools rule a tools issue is unlabelled" "release plan: #60 Gate tweak: label it patch, minor or major"
fi
if mutant_runs toolsReleased 's/^  nothing_to_release$/  :/' patch; then
  if [[ "$RC" -eq 0 ]] && grep -qxF "version=1.9.4" <<< "$OUT" && ! grep -qxF "release=none" <<< "$OUT"; then
    echo "  ok: mutation proof: without nothing to release a tools-only set is released as 1.9.4"
  else
    fail "mutation proof: the mutant without nothing to release did not release the tools-only set (exit ${RC}). Output: ${OUT}"
  fi
fi
data "$(issue 5 'Fix the thing' patch)" "$(issue 60 'Gate tweak' tools)"
if mutant_runs noTooling 's/^if \[ -n "[$]tools_rows" \]; then$/if false; then/' patch --notes "${TMP}/notes_mut.md"; then
  if [[ "$RC" -eq 0 ]] && grep -qxF '### Patch' "${TMP}/notes_mut.md" && ! grep -qF '### Tooling' "${TMP}/notes_mut.md"; then
    echo "  ok: mutation proof: without the Tooling notes the tools issue is missing from the notes"
  else
    fail "mutation proof: the mutant without the Tooling notes still wrote them (exit ${RC}). File: $(cat "${TMP}/notes_mut.md" 2> /dev/null)"
  fi
fi
printf '70\tTooling work\ttools\n' > "${TMP}/open_tools.tsv"
printf 'forsgren#70 (1/2): gate work\n' > "${TMP}/commits_tools.txt"
if selftest_mutant "$PLAN" "${TMP}/mut/openTools/release_plan.sh" 's/^  if is_tools_only "[$]labels"; then continue; fi$/  :/'; then
  RELEASE_PLAN_OPEN="${TMP}/open_tools.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits_tools.txt" RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "${TMP}/mut/openTools/release_plan.sh" patch
  want_red "mutation proof: without the open tools rule an open tools issue with commits stops the plan" "release plan: #70 Tooling work is still open but has commits on main since v1.9.3"
fi
data "$(issue 62 'Both' 'tools,minor')" "$(issue 60 'Gate tweak' tools)"
if mutant_runs toolsWins 's/^  \[ "[$](label_bump "[$]1")" = other \] || return 1$/  :/' minor; then
  want_exit "mutation proof: when tools wins over a bump label the minor issue is lost" 0 "OK: nothing to release: only tools issues were closed since v1.9.3: #60 Gate tweak, #62 Both"
fi

selftest_end "the release plan does not hold" "release plan: the bump check, the closed-issue filter, the notes and the version arithmetic all held"
