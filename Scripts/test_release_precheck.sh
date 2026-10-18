#!/usr/bin/env bash
# Scripts/test_release_precheck.sh
#
# Self-test of Scripts/release_precheck.sh (forsgren#231, step 3): the
# read-only check before a Release. No network and no gh: the data comes
# through the plan's seams (RELEASE_PLAN_DATA, RELEASE_PLAN_OPEN,
# RELEASE_PLAN_COMMITS). Cases:
#   1. every kind of block at once: an open issue with commits, an unlabelled
#      closed issue and an issue that needs a higher bump are ALL named, the
#      ready issue is listed with its label, exit 1
#   2. only ready issues: exit 0 and "would pass the plan"
#   3. no bump given: the bump the labels require (a minor issue: 1.10.0)
#   4. PARITY: for each kind of block alone, the table the pre-check prints is
#      the table the Release run page prints from the plan of the same data
#      (Scripts/release_report.sh on the plan's output): the same lines
#   5. read-only: the working tree is unchanged by a run
#   6. a bump that is none of patch, minor, major: usage, exit 2
# Mutation proofs: a pre-check that does not ask the plan for every block
# (no --all), one that ignores open issues with commits, one that exits 0
# whatever the plan said, and one with its own hand-written table.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release precheck self-test"

PRECHECK="${REPO}/Scripts/release_precheck.sh"
[[ -x "$PRECHECK" ]] || selftest_abort "${PRECHECK} is missing or not executable: nothing checks a Release before it starts"

TAB=$'\t'
PUBLISHED="2026-10-17T05:06:23Z"
AFTER="2026-10-17T09:00:00Z"

# data <issue-line>...: the fixture, the latest release first.
data() {
  { printf 'v1.9.3%s%s\n' "$TAB" "$PUBLISHED"; for line in "$@"; do printf '%s\n' "$line"; done; } > "${TMP}/data.tsv"
}
issue() {
  printf '%s%s%s%s%s%s%s%s%s' "$1" "$TAB" "$2" "$TAB" "$3" "$TAB" "$AFTER" "$TAB" "completed"
}
# open_with_commit <number> <title>: an open issue and a commit that names it.
open_with_commit() {
  printf '%s%s%s\n' "$1" "$TAB" "$2" > "${TMP}/open.tsv"
  printf 'forsgren#%s (1/1): work\n' "$1" > "${TMP}/commits.txt"
}
no_open() {
  : > "${TMP}/open.tsv"
  : > "${TMP}/commits.txt"
}
# precheck <script> [args...]: capture it on the fixture.
precheck() {
  local script="$1"
  shift
  capture env RELEASE_PLAN_DATA="${TMP}/data.tsv" RELEASE_PLAN_OPEN="${TMP}/open.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits.txt" "$script" "$@"
}
# table_lines: the markdown table lines of the last capture.
table_lines() { grep '^|' <<< "$OUT" || true; }

# 1. every kind of block at once
data "$(issue 5 'Fix the thing' patch)" "$(issue 6 'Unlabelled thing' '')" "$(issue 7 'New feature' minor)"
open_with_commit 9 'Half landed'
precheck "$PRECHECK" patch
want_exit "1. a stopped plan exits 1" 1 "would stop at its plan"
want_said "1. the open issue with commits is named" "#9 Half landed"
want_said "1. the unlabelled issue is named" "#6 Unlabelled thing"
want_said "1. the issue that needs more is named" "#7 New feature"
want_said "1. the reason of the needs-minor row" "needs minor, the run asked for patch"
want_said "1. the ready issue is listed with its label" "- ✅ #5 Fix the thing (patch)"
want_said "1. the table has the Release run page's header" "|  | Issue | Blocks because | Do |"

# 2. only ready issues
data "$(issue 5 'Fix the thing' patch)" "$(issue 3 'Fix another thing' patch)"
no_open
precheck "$PRECHECK" patch
want_exit "2. a plan that passes exits 0" 0 "would pass the plan"
want_said "2. the plan's verdict is shown" "OK: next version 1.9.4"
want_said "2. the ready issues are listed" "- ✅ #3 Fix another thing (patch)"

# 3. no bump: the bump the labels require
data "$(issue 5 'Fix the thing' patch)" "$(issue 7 'New feature' minor)"
precheck "$PRECHECK"
want_exit "3. with no bump the labels decide" 0 "OK: next version 1.10.0"

# 4. parity with the Release run page, one kind of block at a time
# parity <case> <expected text>: the plan the Release runs, rendered by the
# Release's report, and the pre-check, on the same data.
parity() {
  local plan_out="${TMP}/plan-out.txt" report_log="${TMP}/report.log" release_table precheck_table
  RELEASE_PLAN_DATA="${TMP}/data.tsv" RELEASE_PLAN_OPEN="${TMP}/open.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits.txt" \
    "${REPO}/Scripts/release_plan.sh" patch > "$plan_out" 2>&1 || true
  : > "$report_log"
  OUT="$(RELEASE_STEP_OUTCOMES='plan=failure' RELEASE_PLAN_OUTPUT="$plan_out" RELEASE_BUMP=patch "${REPO}/Scripts/release_report.sh" "$report_log" failure 2>&1)" || true
  release_table="$(table_lines)"
  precheck "$PRECHECK" patch
  precheck_table="$(table_lines)"
  if [[ -n "$release_table" && "$release_table" == "$precheck_table" ]]; then
    echo "  ok: 4. ${1}: the pre-check prints the table of the Release run page, line for line"
  else
    fail "4. ${1}: the tables differ. Release page: ${release_table:-<none>}. Pre-check: ${precheck_table:-<none>}"
  fi
}
data "$(issue 6 'Unlabelled thing' '')"
no_open
parity "an unlabelled issue"
data "$(issue 5 'Fix the thing' patch)"
open_with_commit 9 'Half landed'
parity "an open issue with commits"
data "$(issue 7 'New feature' minor)"
no_open
parity "an issue that needs more"

# 5. read-only
before="$(git status --porcelain)"
data "$(issue 5 'Fix the thing' patch)"
no_open
precheck "$PRECHECK" patch
if [[ "$(git status --porcelain)" == "$before" ]]; then echo "  ok: 5. a run leaves the working tree as it was"; else fail "5. the pre-check changed the working tree"; fi

# 6. usage
precheck "$PRECHECK" huge
want_exit "6. an unknown bump is a usage error" 2 "usage: Scripts/release_precheck.sh"

# Mutation proofs: each must make the case it exists for fail.
# mutate <name> <sed expr>: a copy of the pre-check run on the all-blocks fixture.
mutate() {
  local m="${TMP}/mut/$1/release_precheck.sh"
  selftest_mutant "$PRECHECK" "$m" "$2" || return 1
  data "$(issue 5 'Fix the thing' patch)" "$(issue 6 'Unlabelled thing' '')" "$(issue 7 'New feature' minor)"
  open_with_commit 9 'Half landed'
  capture env RELEASE_PRECHECK_SCRIPTS="${REPO}/Scripts" RELEASE_PLAN_DATA="${TMP}/data.tsv" RELEASE_PLAN_OPEN="${TMP}/open.tsv" RELEASE_PLAN_COMMITS="${TMP}/commits.txt" "$m" patch
}
if mutate noall 's/ --all > / > /'; then
  if [[ "$RC" -eq 1 ]] && grep -qF "#6 Unlabelled thing" <<< "$OUT"; then
    fail "mutation proof: a pre-check without --all still named the unlabelled issue, so case 1 does not depend on it"
  else
    echo "  ok: mutation proof: a pre-check that does not ask for every block misses the unlabelled issue, which case 1 catches"
  fi
fi
if mutate noopen $'s/^rc=\\$?$/rc=$?; grep -vE "open-with-commits|still open but" "$PLAN_OUT" > "$PLAN_OUT.x"; mv "$PLAN_OUT.x" "$PLAN_OUT"/'; then
  if grep -qF "#9 Half landed" <<< "$(table_lines)"; then
    fail "mutation proof: a pre-check that ignores open issues with commits still named #9"
  else
    echo "  ok: mutation proof: a pre-check that ignores open issues with commits no longer names #9, which case 1 catches"
  fi
fi
if mutate exit0 $'s/^exit "\\$rc"$/exit 0/'; then
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: a pre-check that exits 0 whatever the plan said exits 0 on a stopped plan, which case 1 catches"
  else
    fail "mutation proof: the pre-check that exits 0 exited ${RC}"
  fi
fi
if mutate ownTable 's#^RELEASE_PLAN_OUTPUT=.* || {$#echo "| X | own table |"; true || {#'; then
  if grep -qF "#9 Half landed" <<< "$(table_lines)"; then
    fail "mutation proof: a hand-written table still named the issues"
  else
    echo "  ok: mutation proof: a pre-check with its own table does not print the Release page's table, which the parity cases catch"
  fi
fi

selftest_end "the release pre-check does not judge as the Release does" "release pre-check: every block named at once, ready issues listed, the Release run page's table, exit 0 or 1 as the plan, read-only"
