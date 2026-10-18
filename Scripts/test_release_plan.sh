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
#  10. usage errors, a latest tag that is no vX.Y.Z -> exit 2
# Mutation proofs: a copy that accepts a lower bump, one that accepts nothing
# closed, one without the exclusion, one without the publish-time filter, one
# that lets an unlabelled issue pass and one that lists an issue an earlier
# release named, one that names only the first open issue with commits and one
# that ignores the earlier releases for open issues must each let the case
# they exist for pass.

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

# plan <script> <args>...: capture the script on the fixture.
plan() {
  local script="$1"
  shift
  RELEASE_PLAN_DATA="${TMP}/data.tsv" capture "$script" "$@"
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
data "$(issue 30 'No label' '')" "$(issue 31 'Other label' 'tools')" "$(issue 5 'Fix the thing' patch)"
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
data "$(issue 30 'No label' '')" "$(issue 31 'Other label' 'tools')" "$(issue 5 'Fix the thing' patch)"
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

selftest_end "the release plan does not hold" "release plan: the bump check, the closed-issue filter, the notes and the version arithmetic all held"
