#!/usr/bin/env bash
# Scripts/test_selftests_failure_issue.sh (forsgren#686)
#
# Self-test of Scripts/open_selftests_failure_issue.sh, the one issue of a red
# Self-tests run on main, against a stub gh on PATH that records its arguments
# and answers as the case asks (no network, no token). Cases:
#   1. no open issue of the run: one `gh issue create` in the repository, the
#      title naming the run and the short sha, the body the full sha and the
#      run's link, no label (a red self-test must not feed the change fail rate)
#   2. the same title already open (a rerun of the run): no second issue, exit 0
#   3. an open issue of another run whose number starts the same: still opened
#   4. the list fails: exit 1, named, nothing opened
#   5. the create fails: exit 1, named
#   6. each input missing or malformed: exit 64, named, gh never called
# Mutation proofs:
#   A. the already-open check removed: case 2 opens a second issue
#   B. a label added to the create: case 1 sees it

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "self-tests failure issue self-test"

TARGET="${REPO}/Scripts/open_selftests_failure_issue.sh"
[[ -x "$TARGET" ]] || selftest_abort "${TARGET} is missing or not executable"

SHA="0123456789abcdef0123456789abcdef01234567"
TITLE="Self-tests failed on main: run 123 (0123456)"
mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/gh" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LOG}"
case "$1 $2" in
  "issue list")
    [[ "${STUB_LIST_RC:-0}" == 0 ]] || exit "${STUB_LIST_RC}"
    printf '%s' "${STUB_OPEN_TITLES:-}"
    ;;
  "issue create")
    [[ "${STUB_CREATE_RC:-0}" == 0 ]] || exit "${STUB_CREATE_RC}"
    for a in "$@"; do printf '%s\n' "$a"; done > "${STUB_CREATED}"
    echo "https://github.com/acme/widget/issues/7"
    ;;
esac
STUB
chmod +x "${TMP}/bin/gh"

# run_issue <script> [VAR=value...]: the script with the stub gh and the good
# inputs, each overridable; OUT, RC, and the stub's log and create record.
run_issue() {
  local script="$1"
  shift
  rm -f "${TMP}/log" "${TMP}/created"
  : > "${TMP}/log"
  capture env PATH="${TMP}/bin:${PATH}" STUB_LOG="${TMP}/log" STUB_CREATED="${TMP}/created" \
    SELFTESTS_REPOSITORY=acme/widget SELFTESTS_RUN_ID=123 SELFTESTS_SHA="$SHA" \
    SELFTESTS_SERVER_URL=https://github.com "$@" "$script"
}
created() { [[ -s "${TMP}/created" ]]; }
creates() { grep -c '^issue create' "${TMP}/log" || true; }

# Case 1
run_issue "$TARGET"
want_green "1. a red run with no open issue opens one" "Opened https://github.com/acme/widget/issues/7"
if created && grep -qxF -- "$TITLE" "${TMP}/created"; then echo "  ok: 1. the title names the run and the short sha"; else fail "1. the issue's title is not '${TITLE}': $(cat "${TMP}/created" 2> /dev/null)"; fi
if grep -qxF -- "-R" "${TMP}/created" && grep -qxF -- "acme/widget" "${TMP}/created"; then echo "  ok: 1. the issue is opened in the repository given"; else fail "1. the create does not name acme/widget: $(cat "${TMP}/created" 2> /dev/null)"; fi
if grep -qF -- "${SHA}" "${TMP}/created" && grep -qF -- "https://github.com/acme/widget/actions/runs/123" "${TMP}/created"; then echo "  ok: 1. the body names the commit and links the run"; else fail "1. the body lacks the sha or the run link: $(cat "${TMP}/created" 2> /dev/null)"; fi
if grep -qE -- '^--label|^-l$' "${TMP}/created"; then fail "1. the issue carries a label: a red self-test would feed the change fail rate"; else echo "  ok: 1. no label"; fi

# Case 2
run_issue "$TARGET" STUB_OPEN_TITLES="Something else"$'\n'"${TITLE}"
want_green "2. a rerun of the same run" "already open"
if [[ "$(creates)" == 0 ]]; then echo "  ok: 2. no second issue"; else fail "2. a second issue was opened for the same run"; fi

# Case 3
run_issue "$TARGET" STUB_OPEN_TITLES="Self-tests failed on main: run 1234 (abcdef0)"
want_green "3. an open issue of another run" "Opened"
if [[ "$(creates)" == 1 ]]; then echo "  ok: 3. the issue of this run is opened"; else fail "3. the issue of run 1234 kept run 123's from being opened"; fi

# Case 4
run_issue "$TARGET" STUB_LIST_RC=1
want_exit "4. a list that fails is red, named" 1 "gh could not list the open issues of acme/widget"
if [[ "$(creates)" == 0 ]]; then echo "  ok: 4. nothing opened"; else fail "4. an issue was opened although the list failed"; fi

# Case 5
run_issue "$TARGET" STUB_CREATE_RC=1
want_exit "5. a create that fails is red, named" 1 "gh could not open the issue '${TITLE}' in acme/widget"

# Case 6
for bad in "SELFTESTS_REPOSITORY=acme" "SELFTESTS_RUN_ID=12a" "SELFTESTS_SHA=0123456" "SELFTESTS_SERVER_URL=http://github.com" "SELFTESTS_RUN_ID="; do
  run_issue "$TARGET" "$bad"
  want_exit "6. ${bad} is refused" 64 "${bad%%=*}"
  if [[ -s "${TMP}/log" ]]; then fail "6. gh was called with ${bad}"; fi
done

# Mutation proofs.
M="${TMP}/mut"
if selftest_mutant "$TARGET" "${M}/A/open_selftests_failure_issue.sh" 's/^if grep -qxF -- "[$]title" <<< "[$]open_titles"; then$/if false; then/'; then
  run_issue "${M}/A/open_selftests_failure_issue.sh" STUB_OPEN_TITLES="$TITLE"
  if [[ "$(creates)" == 1 ]]; then echo "  ok: mutation proof A: without the already-open check a rerun opens a second issue, which case 2 catches"; else fail "mutation proof A: the mutant opened no second issue"; fi
fi
if selftest_mutant "$TARGET" "${M}/B/open_selftests_failure_issue.sh" 's/--title "[$]title" --body/--label failure &/'; then
  run_issue "${M}/B/open_selftests_failure_issue.sh"
  if grep -qxF -- "--label" "${TMP}/created"; then echo "  ok: mutation proof B: a label on the create is seen, which case 1 catches"; else fail "mutation proof B: the label did not reach the stub"; fi
fi

selftest_end "the failure issue of a red Self-tests run is not opened once, unlabelled, in the right repository" "self-tests failure issue: a red run opens one unlabelled issue naming the run, the commit and its link, a rerun opens none, a failing gh is red, and a malformed input is refused"
