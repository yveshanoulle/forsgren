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
#  10. usage errors, a latest tag that is no vX.Y.Z -> exit 2
# Mutation proofs: a copy that accepts a lower bump, one that accepts nothing
# closed, one without the exclusion, one without the publish-time filter, one
# that lets an unlabelled issue pass and one that lists an issue an earlier
# release named must each let the case they exist for pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

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

selftest_end "the release plan does not hold" "release plan: the bump check, the closed-issue filter, the notes and the version arithmetic all held"
