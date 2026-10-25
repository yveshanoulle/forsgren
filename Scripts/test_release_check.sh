#!/usr/bin/env bash
# Scripts/test_release_check.sh
#
# Self-test of the release check (forsgren#445): what the maintainer runs
# before the last FBP of a release. No network and no gh: the data comes
# through the plan's seams (RELEASE_PLAN_DATA, RELEASE_PLAN_OPEN,
# RELEASE_PLAN_COMMITS) and the check's own seam for the commits with their
# bodies (RELEASE_CHECK_LOG). The script under test is named from this file's
# own name, and the plan it calls is the one beside it, so no script name is
# spelled here. Cases:
#   1. patch and minor issues, nothing wrong -> exit 0,
#      `release check: OK, bump=patch` / `bump=minor` (the plan's own bump)
#   2. a closed issue without patch, minor, major or tools -> one line naming
#      it, exit 1, no OK line
#   3. an open non-tools issue named by #N in a commit subject -> one line,
#      exit 1; an open tools issue named the same way is no finding
#   4. a commit whose subject is `*** RED ****` alone -> one line naming the
#      commit and the issue its body names (`no issue` when it names none),
#      exit 1; a subject that holds more than the marker, and a body that
#      mentions the marker, are no finding
#   5. several findings at once -> one line each, exit 1
#   6. only tools issues closed -> OK, bump=none; nothing closed -> a finding
#   7. read-only: the working tree is as it was; arguments -> usage, exit 2;
#      a latest tag that is no vX.Y.Z -> the plan could not judge, exit 2
# Mutation proofs: a check that never looks for the red commit, one that
# takes a subject that merely holds the marker for the marker alone, one that
# names no issue of the red commit, one that drops the plan's findings, one
# that exits 0 with findings and one with a fixed bump must each let the case
# they exist for pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release check self-test"

SELF="$(basename "$0")"
CHECK="${REPO}/Scripts/${SELF#test_}"
[[ -x "$CHECK" ]] || selftest_abort "${CHECK} is missing or not executable: nothing checks a release before its last FBP"

TAB=$'\t'
PUBLISHED="2026-10-17T05:06:23Z"
AFTER="2026-10-17T09:00:00Z"
RED='*** RED ****'

# data <issue-line>...: the fixture, the latest release first.
data() {
  { printf 'v1.9.3%s%s\n' "$TAB" "$PUBLISHED"; for line in "$@"; do printf '%s\n' "$line"; done; } > "${TMP}/data.tsv"
}
issue() {
  printf '%s%s%s%s%s%s%s%s%s' "$1" "$TAB" "$2" "$TAB" "$3" "$TAB" "$AFTER" "$TAB" "completed"
}
# log <sha> <subject> <body>...: the commits since the tag, in the shape of the check's seam.
log() {
  : > "${TMP}/log.txt"
  while [[ "$#" -ge 3 ]]; do
    printf '%s\037%s\037%s\036\n' "$1" "$2" "$3" >> "${TMP}/log.txt"
    shift 3
  done
}
: > "${TMP}/open.tsv"
: > "${TMP}/commits.txt"

# run <script> [args]: the script on the fixture, plan beside the real one.
run() {
  local script="$1"
  shift
  RELEASE_CHECK_SCRIPTS="${REPO}/Scripts" RELEASE_PLAN_DATA="${TMP}/data.tsv" RELEASE_PLAN_OPEN="${TMP}/open.tsv" \
    RELEASE_PLAN_COMMITS="${TMP}/commits.txt" RELEASE_CHECK_LOG="${TMP}/log.txt" capture "$script" "$@"
}
# lines_of <text>: how many lines of the output start with the check's red mark.
findings_count() {
  grep -c '^❌ release check: ' <<< "$OUT" || true
}

# 1
data "$(issue 5 'Fix the thing' patch)" "$(issue 3 'Fix another thing' patch)"
log abc1234 'forsgren#5: fix' ''
run "$CHECK"
want_green "patch issues, nothing wrong" "release check: OK, bump=patch"
data "$(issue 5 'Fix the thing' patch)" "$(issue 7 'Add a view' minor)"
run "$CHECK"
want_green "a minor issue raises the bump" "release check: OK, bump=minor"
if [[ "$(findings_count)" -ne 0 ]]; then fail "a clean release has findings. Output: ${OUT}"; fi

# 2
data "$(issue 5 'Fix the thing' patch)" "$(issue 31 'Forgot the label' '')" "$(issue 32 'Forgot it too' enhancement)"
run "$CHECK"
want_red "closed issues without a bump label" "#31 Forgot the label: label it patch, minor or major"
want_said "every unlabelled issue is named" "#32 Forgot it too: label it patch, minor or major"
if grep -qF 'release check: OK' <<< "$OUT"; then fail "the check says OK although issues have no label. Output: ${OUT}"; fi
data "$(issue 5 'Fix the thing' patch)" "$(issue 33 'Tooling only' tools)"
run "$CHECK"
want_green "a tools issue needs no bump label" "release check: OK, bump=patch"

# 3
data "$(issue 5 'Fix the thing' patch)"
printf '50\tOpen feature\tfeature\n51\tOpen tooling\ttools\n52\tOpen untouched\tfeature\n' > "${TMP}/open.tsv"
printf 'forsgren#50 (1/2): half of it\nforsgren#51: a tool\n' > "${TMP}/commits.txt"
run "$CHECK"
want_red "an open non-tools issue named in a commit subject" "#50 Open feature is still open but has commits on main"
if grep -qF '#51' <<< "$OUT"; then fail "an open tools issue is a finding. Output: ${OUT}"; fi
if grep -qF '#52' <<< "$OUT"; then fail "an open issue without a commit is a finding. Output: ${OUT}"; fi
: > "${TMP}/open.tsv"
: > "${TMP}/commits.txt"

# 4
data "$(issue 5 'Fix the thing' patch)"
log abc1234 "$RED" 'forsgren#394 (3/3): a project with no data' def5678 'forsgren#5: fix' ''
run "$CHECK"
want_red "a RED commit alone on main" "commit abc1234 on main since v1.9.3 is a ${RED} commit alone, its body names #394"
if [[ "$(findings_count)" -ne 1 ]]; then fail "the green commit is also a finding, or the RED one is missing. Output: ${OUT}"; fi
log abc1234 "$RED" 'no issue in this body'
run "$CHECK"
want_red "a RED commit whose body names no issue" "its body names no issue"
log abc1234 "${RED} forsgren#5: fix" 'forsgren#5: fix' def5678 'forsgren#5: fix' "this one once was a ${RED} commit, forsgren#394"
run "$CHECK"
want_green "a subject that holds more than the marker, a body that mentions it" "release check: OK, bump=patch"

# 5
data "$(issue 5 'Fix the thing' patch)" "$(issue 31 'Forgot the label' '')"
printf '50\tOpen feature\tfeature\n' > "${TMP}/open.tsv"
printf 'forsgren#50: half\n' > "${TMP}/commits.txt"
log abc1234 "$RED" 'forsgren#394: x' def5678 "$RED" 'forsgren#395: y'
run "$CHECK"
want_rc "several findings at once" 1
if [[ "$(findings_count)" -ne 4 ]]; then fail "expected 4 findings, one line each (open #50, unlabelled #31, two RED commits). Output: ${OUT}"; fi
: > "${TMP}/open.tsv"
: > "${TMP}/commits.txt"

# 6
data "$(issue 33 'Tooling only' tools)"
log abc1234 'forsgren#33: tool' ''
run "$CHECK"
want_green "only tools issues closed" "release check: OK, bump=none"
data
run "$CHECK"
want_red "nothing closed since the tag" "nothing was closed since v1.9.3"

# 7
data "$(issue 5 'Fix the thing' patch)"
log abc1234 'forsgren#5: fix' ''
BEFORE_TREE="$(git status --porcelain)"
run "$CHECK"
if [[ "$(git status --porcelain)" != "$BEFORE_TREE" ]]; then fail "the check changed the working tree"; else echo "  ok: read-only: the working tree is as it was"; fi
run "$CHECK" now
want_exit "an argument" 2 "usage"
printf 'latest\t%s\n' "$PUBLISHED" > "${TMP}/data.tsv"
run "$CHECK"
want_exit "a latest tag that is no vX.Y.Z" 2 "the plan could not judge"

# Mutation proofs: each mutant must let its case pass.
mutant_runs() {
  # <name> <sed>: the mutant, run on the current fixture
  selftest_mutant "$CHECK" "${TMP}/mut/$1/check.sh" "$2" || return 1
  run "${TMP}/mut/$1/check.sh"
}

data "$(issue 5 'Fix the thing' patch)"
log abc1234 "$RED" 'forsgren#394: x'
if mutant_runs nored 's/^if \[ -n "[$]TAG" \]; then red_findings "[$]TAG"; fi$/:/'; then
  want_green "mutation proof: without the look for RED commits a RED commit passes" "release check: OK, bump=patch"
fi
log abc1234 "${RED} forsgren#5: fix" 'forsgren#5: fix'
HOLDS_EXPR="$(cat <<'SED'
s/\[ "[$]subject" = "[*][*][*] RED [*][*][*][*]" \] || continue/[[ "$subject" == *RED* ]] || continue/
SED
)"
if mutant_runs holds "$HOLDS_EXPR"; then
  want_red "mutation proof: a subject that merely holds the marker is taken for the marker alone" "is a ${RED} commit alone"
fi
log abc1234 "$RED" 'forsgren#394: x'
if mutant_runs noissue 's/issue="#[$]{BASH_REMATCH\[1\]}"/issue="no issue"/'; then
  want_red "mutation proof: the issue of the RED body is not named" "its body names no issue"
fi
log
data "$(issue 31 'Forgot the label' '')"
if mutant_runs dropplan 's/"❌ FAIL: release plan: "\*) finding .*;;$/"❌ FAIL: release plan: "*) : ;;/'; then
  want_green "mutation proof: without the plan's findings an unlabelled issue passes" "release check: OK"
fi
if mutant_runs exitzero 's/^if \[ "[$]FINDINGS" -gt 0 \]; then exit 1; fi$/:/'; then
  want_green "mutation proof: findings with exit 0" "release check: OK"
fi
data "$(issue 7 'Add a view' minor)"
if mutant_runs fixedbump 's/^  BUMP="[$](sed .*)"$/  BUMP="patch"/'; then
  want_green "mutation proof: a fixed bump says patch for a minor issue" "bump=patch"
fi

selftest_end "the release check does not hold" "the release check finds what the Release plan would stop on and the stray RED commits, and says the bump"
