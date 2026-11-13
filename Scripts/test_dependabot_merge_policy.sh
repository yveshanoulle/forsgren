#!/usr/bin/env bash
# Scripts/test_dependabot_merge_policy.sh
#
# Self-test for Scripts/dependabot_merge_policy.sh (forsgren#664) and
# for the pin of .github/workflows/dependabot_merge.yml (the caller) and
# .github/dependabot-merge.conf. No network: a fake gh on PATH answers each
# API read from a fixture, and every case must give its exit code and name
# its reason.
#   1. eligible: an Actions patch or minor pin, an npm development patch, a
#      group whose members are all allowed; the record names the repository,
#      each dependency old -> new, the head commit and each check, and goes to
#      the step summary too
#   2. not an allowed update: a group with one runtime member, an npm
#      development minor, an npm runtime patch, a major, Docker, a Go module,
#      an indirect npm update, a branch outside dependabot/<ecosystem>/
#   3. an author other than dependabot[bot]; 3b. a head repository that is
#      another one or deleted (null), an ecosystem-shaped branch outside
#      dependabot/, a head that moved since the run (and one that did not)
#   4. expected checks: failed, cancelled, skipped, timed out, action
#      required, queued, in progress, pending, a success on a run not
#      completed, missing, stale (an old head commit only), a run of the same
#      name from another file, an older green run under a newer red one
#   5. mergeability and freshness: behind main, not mergeable, not clean, not
#      computed after the retries (read 3 times), computed on the second read,
#      closed
#   6. API errors and unreadable answers: a failed read of each kind, an
#      answer that is not JSON, a runs answer without its list, a compare
#      answer without behind_by, commit metadata missing, unclosed, with a line
#      it does not understand (also in a group's last member), two blocks, a
#      member without update-type, a head that is not a commit id
#   7. the config missing, without a workflow, with a line not understood
#   8. usage: no number, a number that is not one, no GITHUB_REPOSITORY
#   9. read only: every gh call of every case is a plain GET
#  10. this repository's config and its merge workflow, a caller of the
#      reusable .github/workflows/dependabot_merge_policy.yml (forsgren#666,
#      whose own pin is Scripts/test_dependabot_merge_policy_workflow.sh):
#      every expected workflow file exists under its name and runs on
#      pull_request; every workflow that runs on pull_request is expected;
#      Go modules, Docker and majors are not allowed; the caller starts on
#      exactly the expected workflows, completed, has no other trigger
#      (never workflow_call, so it cannot be taken for auto_update.yml), the
#      minimal three permissions, exactly one zizmor ignore,
#      dangerous-triggers on the workflow_run: line, one job that calls the
#      local reusable file and has no steps of its own, this repository's
#      config as settings-file, DEPENDABOT_AUTOMERGE as the mode, and
#      DEPENDABOT_MERGE_TOKEN passed by name as its only secret (never
#      secrets: inherit)
#  11. the merge token check (.github/workflows/dependabot_merge_token_check.yml):
#      workflow_dispatch only, contents: read alone, DEPENDABOT_MERGE_TOKEN
#      through env: and no other secret, never printed or traced, its length,
#      prefix and push permission reported, no API write, ubuntu-latest
# Mutation proofs: copies of the policy with one condition weakened (a check
# not completed with success taken as green, every update allowed, a head
# behind main taken as fresh, any author, any head repository, any branch
# prefix, a head that moved, a state other than clean, a failed
# read that does not block, the oldest run deciding) must each turn a red case
# green; copies of the caller (among them: a write permission, another
# trigger, the zizmor ignore moved or doubled, steps of its own, a call of a
# branch, the switch forced on, secrets: inherit) and of the token check
# with one rule broken must each be judged red.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
selftest_begin "dependabot merge policy self-test"

POLICY="Scripts/dependabot_merge_policy.sh"
CONF=".github/dependabot-merge.conf"
MERGE_WF=".github/workflows/dependabot_merge.yml"
CALLED_WF=".github/workflows/dependabot_merge_policy.yml"
[[ -x "$POLICY" ]] || selftest_abort "${POLICY} does not exist or is not executable — no Dependabot pull request would ever be judged"
REPO_ROOT="$(pwd)"
# D and B stand for a dollar sign and a backtick inside double quotes, so the
# expected texts read as written without a shellcheck suppression.
D='$'
B='`'

SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OLD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

# The fake gh: logs its arguments, fails a read when fail.<kind> exists, and
# answers the n-th read of a kind with <kind>.<n>.json when that exists, else
# <kind>.json.
mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/gh" << 'FAKE'
#!/usr/bin/env bash
D="$FAKE_GH_DIR"
echo "$*" >> "$D/calls.log"
[ "$1" = api ] && [ "$#" -eq 2 ] || { echo "fake gh: unexpected call: $*" >&2; exit 64; }
case "$2" in
  */pulls/*) kind=pr ;;
  */commits/*) kind=commit ;;
  */actions/runs*) kind=runs ;;
  */compare/*) kind=compare ;;
  *) echo "fake gh: unexpected path $2" >&2; exit 64 ;;
esac
n=$(($(cat "$D/count.$kind" 2> /dev/null || echo 0) + 1))
echo "$n" > "$D/count.$kind"
[ ! -e "$D/fail.$kind" ] || { echo "HTTP 502: Bad Gateway (fake)" >&2; exit 1; }
if [ -e "$D/$kind.$n.json" ]; then cat "$D/$kind.$n.json"; else cat "$D/$kind.json"; fi
FAKE
chmod +x "${TMP}/bin/gh"

# message <member...>: a Dependabot commit message whose updated-dependencies
# block lists one member per argument "name|type|update|from|to".
message() {
  local m name type upd from to
  echo "bump dependencies"
  echo
  for m in "$@"; do
    IFS='|' read -r name type upd from to <<< "$m"
    echo "Updates \`$name\` from $from to $to"
  done
  echo "---"
  echo "updated-dependencies:"
  for m in "$@"; do
    IFS='|' read -r name type upd from to <<< "$m"
    printf -- '- dependency-name: "%s"\n  dependency-version: %s\n  dependency-type: %s\n  update-type: version-update:%s\n' \
      "$name" "$to" "$type" "$upd"
  done
  echo "..."
  echo
  echo "Signed-off-by: dependabot[bot] <support@github.com>"
}

# fixture <case dir> <branch> <member...>: an eligible pull request on that
# branch with those members, both expected workflows green for the head
# commit, mergeable, clean and not behind main.
fixture() {
  local d="$1" branch="$2"
  shift 2
  mkdir -p "$d"
  jq -n --arg sha "$SHA" --arg ref "$branch" '{number: 7, title: "bump dependencies", state: "open",
    user: {login: "dependabot[bot]"}, head: {sha: $sha, ref: $ref, repo: {full_name: "owner/repo"}}, base: {ref: "main", repo: {default_branch: "main"}},
    mergeable: true, mergeable_state: "clean", body: "Dependabot pull request"}' > "$d/pr.json"
  jq -n --arg msg "$(message "$@")" '{commit: {message: $msg}}' > "$d/commit.json"
  jq -n --arg sha "$SHA" '{workflow_runs: [
    {id: 11, name: "Quality", path: ".github/workflows/quality.yml", head_sha: $sha, status: "completed", conclusion: "success"},
    {id: 12, name: "DCO", path: ".github/workflows/dco.yml", head_sha: $sha, status: "completed", conclusion: "success"}]}' > "$d/runs.json"
  echo '{"behind_by": 0, "ahead_by": 1}' > "$d/compare.json"
}
ACTIONS_BRANCH=dependabot/github_actions/actions/checkout-7.0.2
NPM_BRANCH=dependabot/npm_and_yarn/npm-tooling-0123456789
ACTIONS_PATCH="actions/checkout|direct:production|semver-patch|7.0.1|7.0.2"
NPM_DEV_PATCH="htmlhint|direct:development|semver-patch|1.9.2|1.9.3"

# edit <file> <jq filter>: changes a fixture in place.
edit() { jq "$2" "$1" > "$1.new" && mv "$1.new" "$1"; }

N=0
# new_case <branch> <member...>: a fresh eligible fixture in a new directory,
# which it leaves in d.
new_case() {
  N=$((N + 1))
  d="${TMP}/case${N}"
  fixture "$d" "$@"
}

# run_policy <case dir> [conf]: runs ${SCRIPT:-$POLICY} on pull request 7 with
# the fake gh; OUT and RC as capture leaves them, the output also in out.txt.
run_policy() {
  capture env FAKE_GH_DIR="$1" PATH="${TMP}/bin:${PATH}" GITHUB_REPOSITORY=owner/repo \
    DEPENDABOT_MERGE_RETRY_SECONDS=0 DEPENDABOT_MERGE_CONF="${2:-$REPO_ROOT/$CONF}" \
    DEPENDABOT_MERGE_EXPECTED_HEAD="${EXPECT_HEAD:-}" GITHUB_STEP_SUMMARY="$1/summary.md" "${SCRIPT:-$POLICY}" 7
  printf '%s\n' "$OUT" > "$1/out.txt"
}

# expect <case dir> <exit code> <text the record must hold> <label>
expect() {
  run_policy "$1"
  want_exit "$4" "$2" "$3"
}

# 1 eligible
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
expect "$d" 0 "Decision: ELIGIBLE" "1. an Actions patch pin with everything green is eligible"
if grep -qF "${B}actions/checkout${B} (github_actions, direct:production, version-update:semver-patch): 7.0.1 → 7.0.2, allowed" "$d/out.txt" &&
  grep -qF "Head commit: $SHA" "$d/out.txt" && grep -qF "Quality: completed, success (run 11)" "$d/out.txt" &&
  grep -qF "DCO: completed, success (run 12)" "$d/out.txt" && grep -qF "Repository: owner/repo" "$d/out.txt"; then
  echo "  ok: 1. the record names the repository, the dependency old → new, the head commit and each check"
else
  fail "1. the record lacks a field: $(cat "$d/out.txt")"
fi
if cmp -s "$d/out.txt" "$d/summary.md"; then echo "  ok: 1. the record goes to the step summary too"; else fail "1. the step summary differs from the record"; fi
new_case "$ACTIONS_BRANCH" "actions/setup-node|direct:production|semver-minor|6.0.0|6.1.0"
expect "$d" 0 "Decision: ELIGIBLE" "1. an Actions minor pin is eligible"
new_case "$NPM_BRANCH" "$NPM_DEV_PATCH"
expect "$d" 0 "Decision: ELIGIBLE" "1. an npm development patch is eligible"
new_case "$NPM_BRANCH" "$NPM_DEV_PATCH" "jscpd|direct:development|semver-patch|5.4.2|5.4.3"
expect "$d" 0 "Decision: ELIGIBLE" "1. a grouped pull request whose members are all allowed is eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH" "actions/setup-go|direct:production|semver-minor|6.0.0|6.1.0"
expect "$d" 0 "Decision: ELIGIBLE" "1. a grouped Actions pull request of a patch and a minor is eligible"

# 2 not an allowed update
new_case "$NPM_BRANCH" "$NPM_DEV_PATCH" "left-pad|direct:production|semver-patch|1.3.0|1.3.1"
expect "$d" 1 "${B}left-pad${B} is not an allowed update (npm_and_yarn, direct:production" "2. a group with one runtime member is not eligible"
new_case "$NPM_BRANCH" "htmlhint|direct:development|semver-minor|1.9.2|1.10.0"
expect "$d" 1 "${B}htmlhint${B} is not an allowed update (npm_and_yarn, direct:development, version-update:semver-minor)" "2. an npm development minor is not eligible"
new_case "$NPM_BRANCH" "left-pad|direct:production|semver-patch|1.3.0|1.3.1"
expect "$d" 1 "${B}left-pad${B} is not an allowed update" "2. an npm runtime patch is not eligible"
new_case "$ACTIONS_BRANCH" "actions/checkout|direct:production|semver-major|5.1.0|7.0.1"
expect "$d" 1 "version-update:semver-major" "2. a major update is not eligible"
new_case "dependabot/docker/node-26.1" "node|direct:production|semver-patch|26.0|26.1"
expect "$d" 1 "${B}node${B} is not an allowed update (docker" "2. a Docker update is not eligible"
new_case "dependabot/go_modules/go-modules-0123456789" "golang.org/x/net|direct:production|semver-patch|0.40.0|0.40.1"
expect "$d" 1 "${B}golang.org/x/net${B} is not an allowed update (go_modules" "2. a Go module update is not eligible"
new_case "dependabot/go_modules/go-1.27.5" "go|direct:production|semver-patch|1.27.4|1.27.5"
expect "$d" 1 "${B}go${B} is not an allowed update (go_modules" "2. a Go toolchain update is not eligible"
new_case "$NPM_BRANCH" "glob|indirect|semver-patch|14.0.3|14.0.4"
expect "$d" 1 "${B}glob${B} is not an allowed update (npm_and_yarn, indirect" "2. an indirect npm update is not eligible"
new_case "dependabot/npm_and_yarn/x" "$NPM_DEV_PATCH"
edit "$d/pr.json" '.head.ref = "renovate/htmlhint"'
expect "$d" 1 "does not name a Dependabot ecosystem" "2. a branch outside dependabot/<ecosystem>/ is not eligible"

# 3 author
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/pr.json" '.user.login = "someone"'
expect "$d" 1 "author is 'someone', not dependabot[bot]" "3. an author other than dependabot[bot] is not eligible"
AUTHOR_CASE="$d"

# 3b head repository, branch and head commit
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/pr.json" '.head.repo.full_name = "someone/repo"'
expect "$d" 1 "head repository is 'someone/repo', not owner/repo" "3b. a head repository that is another one is not eligible"
REPO_CASE="$d"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/pr.json" '.head.repo = null'
expect "$d" 1 "head repository unknown (deleted or not readable), not owner/repo" "3b. a deleted head repository (null) is not eligible"
new_case "renovate/github_actions/actions/checkout-7.0.2" "$ACTIONS_PATCH"
expect "$d" 1 "branch 'renovate/github_actions/actions/checkout-7.0.2' does not name a Dependabot ecosystem" "3b. an ecosystem-shaped branch outside dependabot/ is not eligible"
BRANCH_CASE="$d"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
EXPECT_HEAD="$SHA" expect "$d" 0 "Decision: ELIGIBLE" "3b. a head that is still the commit the run was for is eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
EXPECT_HEAD="$OLD" expect "$d" 1 "head commit $SHA is not the commit the run was for ($OLD); the pull request moved" "3b. a pull request whose head moved since the run is not eligible"
MOVED_CASE="$d"

# 4 expected checks
for result in failure cancelled skipped timed_out action_required; do
  new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
  edit "$d/runs.json" "(.workflow_runs[] | select(.name == \"DCO\") | .conclusion) = \"$result\""
  expect "$d" 1 "DCO is completed, $result, not completed with success (run 12)" "4. a $result check is not eligible"
done
FAILED_CASE="${TMP}/case$((N - 4))"
for status in queued in_progress pending; do
  new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
  edit "$d/runs.json" "(.workflow_runs[] | select(.name == \"Quality\")) |= (.status = \"$status\" | .conclusion = null)"
  expect "$d" 1 "Quality is $status, null, not completed with success (run 11)" "4. a $status check is not eligible"
done
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/runs.json" '(.workflow_runs[] | select(.name == "Quality") | .status) = "in_progress"'
expect "$d" 1 "Quality is in_progress, success, not completed with success" "4. a success conclusion on a run not completed (an ambiguous answer) is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/runs.json" 'del(.workflow_runs[] | select(.name == "DCO"))'
expect "$d" 1 "DCO has no run for the head commit $SHA" "4. a missing check is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
jq --arg old "$OLD" '(.workflow_runs[] | select(.name == "Quality") | .head_sha) = $old' "$d/runs.json" > "$d/runs.new" && mv "$d/runs.new" "$d/runs.json"
expect "$d" 1 "Quality has no run for the head commit $SHA" "4. a green run for an old head commit only (stale) is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/runs.json" '(.workflow_runs[] | select(.name == "Quality") | .path) = ".github/workflows/other.yml"'
expect "$d" 1 "Quality has no run for the head commit" "4. a run named Quality from another workflow file does not count"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/runs.json" '.workflow_runs += [{id: 21, name: "Quality", path: ".github/workflows/quality.yml", head_sha: .workflow_runs[0].head_sha, status: "completed", conclusion: "failure"}]'
expect "$d" 1 "Quality is completed, failure, not completed with success (run 21)" "4. the latest run of a workflow decides, not an older green one"
LATEST_CASE="$d"

# 5 mergeability and freshness
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/compare.json" '.behind_by = 2'
expect "$d" 1 "head is 2 commit(s) behind main" "5. a head behind main is not eligible"
BEHIND_CASE="$d"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/pr.json" '.mergeable = false | .mergeable_state = "dirty"'
expect "$d" 1 "not mergeable (mergeable false)" "5. mergeable false is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/pr.json" '.mergeable_state = "unstable"'
expect "$d" 1 "mergeable state is 'unstable', not clean" "5. a mergeable state other than clean is not eligible"
UNCLEAN_CASE="$d"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/pr.json" '.mergeable = null | .mergeable_state = "unknown"'
expect "$d" 1 "mergeability not computed by GitHub after 3 read(s)" "5. mergeable null after the retries is not eligible"
if [[ "$(cat "$d/count.pr")" == 3 ]]; then echo "  ok: 5. an uncomputed mergeability is read 3 times"; else fail "5. the pull request was read $(cat "$d/count.pr") times, not 3"; fi
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
jq '.mergeable = null | .mergeable_state = "unknown"' "$d/pr.json" > "$d/pr.1.json"
expect "$d" 0 "Decision: ELIGIBLE" "5. a mergeability computed on the second read is used"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/pr.json" '.state = "closed" | .mergeable = null | .mergeable_state = "unknown"'
expect "$d" 1 "pull request is closed, not open" "5. a closed pull request is not eligible"

# 6 API errors and unreadable answers
for kind in pr commit runs compare; do
  new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
  touch "$d/fail.$kind"
  expect "$d" 1 "GitHub API read failed:" "6. a failing gh read of the $kind is not eligible"
  [[ "$kind" != commit ]] || COMMIT_FAIL_CASE="$d"
done
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
echo "<html>502</html>" > "$d/runs.json"
expect "$d" 1 "GitHub API answer is not JSON: GET actions/runs" "6. an answer that is not JSON is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
echo '{"message": "no runs"}' > "$d/runs.json"
expect "$d" 1 "workflow runs answer has no workflow_runs list" "6. a runs answer without its list is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
echo '{"status": "diverged"}' > "$d/compare.json"
expect "$d" 1 "compare answer has no behind_by" "6. a compare answer without behind_by is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/commit.json" '.commit.message = "bump actions/checkout from 7.0.1 to 7.0.2"'
expect "$d" 1 "commit metadata unreadable: no updated-dependencies block" "6. a commit message without metadata is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/commit.json" '.commit.message |= sub("\n\\.\\.\\.\n\nSigned-off-by: [^\n]*"; "")'
expect "$d" 1 "commit metadata unreadable: updated-dependencies block not closed" "6. an unclosed metadata block is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/commit.json" '.commit.message |= sub("  update-type"; "update-type")'
expect "$d" 1 "commit metadata unreadable: line not understood" "6. a metadata line it does not understand is not eligible"
new_case "$NPM_BRANCH" "$NPM_DEV_PATCH" "jscpd|direct:development|semver-patch|5.4.2|5.4.3"
edit "$d/commit.json" '.commit.message |= sub("  dependency-type: direct:development\n  update-type: version-update:semver-patch\n\\.\\.\\."; "dependency-type: x\n...")'
expect "$d" 1 "commit metadata unreadable: line not understood: dependency-type: x" "6. a bad line in the last member of a group is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/commit.json" '.commit.message += "\nupdated-dependencies:\n- dependency-name: x\n  update-type: version-update:semver-patch\n...\n"'
expect "$d" 1 "commit metadata unreadable: more than one updated-dependencies block" "6. two metadata blocks are not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/commit.json" '.commit.message |= sub("  update-type: [^\n]*\n"; "")'
expect "$d" 1 "no update-type" "6. a member without update-type is not eligible"
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
edit "$d/pr.json" '.head.sha = "main"'
expect "$d" 1 "head commit 'main' is not a commit id" "6. a head that is not a commit id is not eligible"

# 7 config
new_case "$ACTIONS_BRANCH" "$ACTIONS_PATCH"
run_policy "$d" "$d/none.conf"
want_exit "7. a missing config is not eligible" 1 "cannot be read"
printf 'allow github_actions * semver-patch\n' > "$d/noworkflow.conf"
run_policy "$d" "$d/noworkflow.conf"
want_exit "7. a config without workflows is not eligible" 1 "names no allow rule or no workflow"
printf 'allow github_actions * semver-patch\nworkflow .github/workflows/quality.yml Quality\nallwo npm_and_yarn * semver-patch\n' > "$d/typo.conf"
run_policy "$d" "$d/typo.conf"
want_exit "7. a config line not understood is not eligible" 1 "config line not understood: allwo"

# 8 usage
capture env PATH="${TMP}/bin:${PATH}" GITHUB_REPOSITORY=owner/repo "$POLICY"
want_rc "8. no pull request number exits 2" 2
capture env PATH="${TMP}/bin:${PATH}" GITHUB_REPOSITORY=owner/repo "$POLICY" 7x
want_rc "8. a pull request number that is not a number exits 2" 2
capture env -u GITHUB_REPOSITORY PATH="${TMP}/bin:${PATH}" "$POLICY" 7
want_rc "8. no GITHUB_REPOSITORY exits 2" 2

# 9 read only: every gh call of every case was "api <path>" (the fake rejects
# anything else with exit 64, and a write needs -X, -f, -F or --method).
if cat "$TMP"/case*/calls.log | has -qvE '^api repos/owner/repo/[^ ]+$'; then
  fail "9. the policy made a gh call that is not a plain API read: $(cat "$TMP"/case*/calls.log | grep -vE '^api repos/owner/repo/[^ ]+$' | head -1)"
else
  echo "  ok: 9. the policy only reads the GitHub API"
fi

# 10 this repository's config and workflow
# on_events <workflow>: the top-level trigger names, sorted, one line.
on_events() {
  awk '/^on:/{i=1;next} i&&/^[^[:space:]#]/{i=0} i&&/^  [a-z_]+:/{s=$1;sub(/:/,"",s);print s}' "$1" | LC_ALL=C sort | tr '\n' ' '
}
NAMES=()
while read -r kind path name; do
  [[ "$kind" == workflow ]] || continue
  NAMES+=("$name")
  if [[ -f "$path" ]] && grep -qxF "name: $name" "$path"; then echo "  ok: 10. expected workflow $path is named $name"; else fail "10. expected workflow $path is missing or not named $name"; fi
  if [[ -f "$path" ]] && [[ " $(on_events "$path")" == *" pull_request "* ]]; then echo "  ok: 10. expected workflow $path runs on pull_request"; else fail "10. expected workflow $path does not run on pull_request, so it would never be green for a Dependabot head commit"; fi
done < "$CONF"
for wf in .github/workflows/*.yml; do
  [[ " $(on_events "$wf")" == *" pull_request "* ]] || continue
  if grep -qE "^workflow ${wf//./\\.} " "$CONF"; then
    echo "  ok: 10. ${wf} runs on pull_request and is expected"
  else
    fail "10. ${wf} runs on pull_request and ${CONF} does not expect it: a red run of it would not hold a merge back"
  fi
done
if grep -qE '^allow (go_modules|docker)[[:space:]]' "$CONF" || grep -qE '^allow .*semver-major' "$CONF"; then
  fail "10. ${CONF} allows Go modules, Docker or a major update: those stay manual merges"
else
  echo "  ok: 10. Go modules (the toolchain included), Docker and majors are not allowed"
fi

# judge_workflow <file>: one line per rule the caller, this repository's
# merge workflow, breaks; no output when it holds them all. Every step and
# safeguard is in the called workflow, which
# Scripts/test_dependabot_merge_policy_workflow.sh pins; the caller starts
# it on exactly the expected workflows and hands it this repository's
# settings, the switch and the one secret, by name. It reads a copy without
# comment lines, in TMP.
judge_workflow() {
  local f want perms
  f="${TMP}/judged.$(basename "$1").code"
  # Comment lines are not code: the header may name what the file must not do.
  grep -vE '^[[:space:]]*#' "$1" > "$f" || true
  want="    workflows: [$(printf '%s, ' "${NAMES[@]}" | sed 's/, $//')]"
  grep -qxF "$want" "$f" || echo "it does not start on exactly the expected workflows ($want)"
  [[ "$(on_events "$f")" == "workflow_run " ]] || echo "its triggers are '$(on_events "$f")', not workflow_run alone"
  grep -qxF '    types: [completed]' "$f" || echo "it does not start on completed runs only"
  # The one zizmor ignore: counted in the file as written, comments included.
  [[ "$(grep -c 'zizmor: ignore' "$1")" -eq 1 ]] || echo "it carries $(grep -c 'zizmor: ignore' "$1") zizmor ignores, not exactly one"
  grep -qxF '  workflow_run:  # zizmor: ignore[dangerous-triggers]' "$1" || echo "its zizmor ignore is not dangerous-triggers on the workflow_run: line"
  ! grep -qE 'pull_request_target|workflow_call' "$f" || echo "it names pull_request_target or workflow_call"
  perms="$(sed -n '/^permissions:/,/^$/p' "$f" | sed '1d;/^$/d' | tr -d ' ' | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$perms" == "actions:read contents:read pull-requests:write " ]] || echo "its permissions are '$perms', not the minimal three"
  [[ "$(grep -cE '^[[:space:]]+uses:' "$f")" -eq 1 ]] && grep -qxF "    uses: ./${CALLED_WF}" "$f" ||
    echo "it does not call ./${CALLED_WF} as its one job, from this commit"
  ! grep -qE '^[[:space:]]+(runs-on|steps):' "$f" || echo "it has steps of its own: every step belongs in the called workflow"
  grep -qxF "      settings-file: ${CONF}" "$f" || echo "it does not hand the called workflow ${CONF}"
  grep -qxF "      mode: ${D}{{ vars.DEPENDABOT_AUTOMERGE }}" "$f" || echo "it does not hand the kill switch DEPENDABOT_AUTOMERGE over as the mode"
  [[ "$(grep -c 'secrets\.' "$f")" -eq 1 ]] && grep -qxF "      DEPENDABOT_MERGE_TOKEN: ${D}{{ secrets.DEPENDABOT_MERGE_TOKEN }}" "$f" &&
    ! grep -qE 'secrets: *inherit' "$f" || echo "it does not pass DEPENDABOT_MERGE_TOKEN alone, by name (never secrets: inherit)"
  ! grep -qE "^name: Auto update$" "$f" || echo "it carries the name of auto_update.yml"
}
if [[ ! -f "$MERGE_WF" ]]; then
  fail "10. ${MERGE_WF} does not exist: no Dependabot pull request is judged"
else
  findings="$(judge_workflow "$MERGE_WF")"
  if [[ -z "$findings" ]]; then echo "  ok: 10. ${MERGE_WF} holds every rule"; else fail "10. ${MERGE_WF}: ${findings}"; fi
fi

# 11 the merge token check workflow
# judge_token_check <file>: one line per rule the token check breaks.
judge_token_check() {
  local f
  f="${TMP}/judged.$(basename "$1").code"
  grep -vE '^[[:space:]]*#' "$1" > "$f" || true
  [[ "$(on_events "$f")" == "workflow_dispatch " ]] || echo "its triggers are '$(on_events "$f")', not workflow_dispatch alone"
  [[ "$(sed -n '/^permissions:/,/^$/p' "$f" | sed '1d;/^$/d' | tr -d ' ' | tr '\n' ' ')" == "contents:read " ]] || echo "its permissions are not contents: read alone"
  ! grep -qE ': write|write-all|permissions: *[a-z]' "$f" || echo "it asks for more than contents: read"
  grep -qF "MERGE_TOKEN: ${D}{{ secrets.DEPENDABOT_MERGE_TOKEN }}" "$f" || echo "it does not read DEPENDABOT_MERGE_TOKEN through env:"
  [[ "$(grep -c 'secrets\.' "$f")" -eq 1 ]] || echo "it names another secret, or this one twice"
  ! grep -qE "(echo|printf|tee)[^|]*\\${D}\\{?MERGE_TOKEN" "$f" || echo "it prints the token"
  ! grep -qE "set -[a-z]*x|set -o xtrace" "$f" || echo "it traces commands, which would print the token"
  grep -qF "GH_TOKEN=\"${D}MERGE_TOKEN\" gh api \"repos/${D}GITHUB_REPOSITORY\" --jq '.permissions.push'" "$f" || echo "it does not ask GitHub whether the token can write here"
  grep -qF 'github_pat_*)' "$f" || echo "it does not report the github_pat_ prefix"
  grep -qF "length=\"${D}{#MERGE_TOKEN}\"" "$f" || echo "it does not report the length"
  ! grep -qE 'gh api .*-X|--method|-f |-F ' "$f" || echo "it writes through the API"
  ! grep -E '^[[:space:]]+runs-on:' "$f" | has -qvE 'runs-on: ubuntu-latest$' || echo "a job runs elsewhere than on GitHub's hosted ubuntu-latest"
}
TOKEN_WF=".github/workflows/dependabot_merge_token_check.yml"
if [[ ! -f "$TOKEN_WF" ]]; then
  fail "11. ${TOKEN_WF} does not exist: the merge token of step 2 cannot be checked"
else
  findings="$(judge_token_check "$TOKEN_WF")"
  if [[ -z "$findings" ]]; then echo "  ok: 11. ${TOKEN_WF} holds every rule"; else fail "11. ${TOKEN_WF}: ${findings}"; fi
fi
# token_mutant <name> <sed> <what>: a broken copy must be judged red.
token_mutant() {
  local m="${TMP}/tokmut/$1.yml"
  mkdir -p "${TMP}/tokmut"
  sed "$2" "$TOKEN_WF" > "$m"
  if cmp -s "$TOKEN_WF" "$m"; then
    fail "mutation proof: the token check mutation $2 changed nothing: the proof would be vacuous"
  elif [[ -n "$(judge_token_check "$m")" ]]; then
    echo "  ok: mutation proof: $3 is caught"
  else
    fail "mutation proof: $3 is not caught"
  fi
}
token_mutant print "s/echo \"length: ${D}length characters\"/echo \"token: ${D}MERGE_TOKEN\"/" "the token printed"
token_mutant push 's/^  workflow_dispatch:$/  push:\
  workflow_dispatch:/' "a push trigger"
token_mutant write 's/^  contents: read$/  contents: write/' "a write permission"
token_mutant xtrace "s/length=\"${D}{#MERGE_TOKEN}\"/set -x; &/" "a command trace"

# Mutation proofs: the policy. Each mutant runs on a case the real policy
# judges red; the mutant must call it eligible, so that case catches it.
# policy_mutant <name> <sed> <case dir> <what>
policy_mutant() {
  if selftest_mutant "$POLICY" "${TMP}/mut/$1/Scripts/dependabot_merge_policy.sh" "$2"; then
    SCRIPT="${TMP}/mut/$1/Scripts/dependabot_merge_policy.sh"
    rm -f "$3"/count.*
    run_policy "$3"
    unset SCRIPT
    if [[ "$RC" -eq 0 ]]; then echo "  ok: mutation proof: $4 is caught"; else fail "mutation proof: $4 is not caught (the mutant exits ${RC}). Output: ${OUT}"; fi
  fi
}
policy_mutant status "s/\\[ \"\\${D}status\" = completed \\] \\&\\& \\[ \"\\${D}conclusion\" = success \\] ||/true ||/" "$FAILED_CASE" "a check not completed with success taken as green"
policy_mutant allowed 's/^  return 1$/  return 0/' "${TMP}/case7" "every update allowed"
policy_mutant behind "s/elif \\[ \"\\${D}behind\" -ne 0 \\]/elif false/" "$BEHIND_CASE" "a head behind main taken as fresh"
policy_mutant author "s/\\[ \"\\${D}login\" = \"\\${D}AUTHOR\" \\] ||/true ||/" "$AUTHOR_CASE" "any author accepted"
policy_mutant repository "s/elif \\[ \"\\${D}head_repo\" != \"\\${D}REPO\" \\]; then/elif false; then/" "$REPO_CASE" "any head repository accepted"
policy_mutant branch "s#=~ ^dependabot/(\\[a-z_\\]+)/ \\]\\]#=~ ^[a-z]+/([a-z_]+)/ ]]#" "$BRANCH_CASE" "any branch prefix accepted"
EXPECT_HEAD="$OLD"
policy_mutant head "s/if \\[ -n \"\\${D}EXPECTED_HEAD\" \\] \\&\\& \\[ \"\\${D}HEAD_SHA\" != \"\\${D}EXPECTED_HEAD\" \\]; then/if false; then/" "$MOVED_CASE" "a head that moved since the run accepted"
unset EXPECT_HEAD
policy_mutant clean "s/\\[ \"\\${D}mstate\" = clean \\] ||/true ||/" "$UNCLEAN_CASE" "a mergeable state other than clean accepted"
policy_mutant apiblock 's/block "GitHub API read failed: .*/return 1/' "$COMMIT_FAIL_CASE" "a failed read that does not block"
policy_mutant oldest 's/sort_by(.id) | last/sort_by(.id) | first/' "$LATEST_CASE" "the oldest run deciding"

# Mutation proofs: the caller. Each broken copy must be judged red.
# workflow_mutant <name> <sed> <what>
workflow_mutant() {
  local m="${TMP}/wfmut/$1.yml"
  mkdir -p "${TMP}/wfmut"
  sed "$2" "$MERGE_WF" > "$m"
  if cmp -s "$MERGE_WF" "$m"; then
    fail "mutation proof: the workflow mutation $2 changed nothing: the proof would be vacuous"
  elif [[ -n "$(judge_workflow "$m")" ]]; then
    echo "  ok: mutation proof: $3 is caught"
  else
    fail "mutation proof: $3 is not caught"
  fi
}
workflow_mutant perms 's/^  contents: read$/  contents: write/' "a write permission on contents"
workflow_mutant trigger 's/^  workflow_run:/  pull_request_target:\
  workflow_run:/' "a pull_request_target trigger"
workflow_mutant onlyone 's/^    workflows: \[Quality, DCO\]$/    workflows: [Quality]/' "an expected workflow dropped from the trigger"
workflow_mutant types 's/^    types: \[completed\]$/    types: [requested, completed]/' "a start on requested runs"
workflow_mutant ignoreabove 's/^  workflow_run:  # zizmor: ignore\[dangerous-triggers\]$/  # zizmor: ignore[dangerous-triggers]\
  workflow_run:/' "the zizmor ignore moved to its own line"
workflow_mutant ignoretwice 's/^    types: \[completed\]$/    types: [completed]  # zizmor: ignore[dangerous-triggers]/' "a second zizmor ignore"
workflow_mutant ignoreother 's/ignore\[dangerous-triggers\]/ignore[template-injection]/' "an ignore of another rule"
workflow_mutant remote 's#^    uses: \./\.github/workflows/dependabot_merge_policy\.yml$#    uses: owner/forsgren/.github/workflows/dependabot_merge_policy.yml@main#' "a call of a branch instead of this commit's file"
workflow_mutant steps 's/^    uses: .*/    runs-on: ubuntu-latest\
    steps:\
      - run: echo/' "steps of its own"
workflow_mutant settings 's/^      settings-file: .*/      settings-file: other.conf/' "another settings file"
workflow_mutant modeon 's/^      mode: .*/      mode: on/' "the switch forced on"
workflow_mutant inherit 's/^    secrets:$/    secrets: inherit/;/DEPENDABOT_MERGE_TOKEN:/d' "secrets: inherit"
workflow_mutant extrasecret "s/^      DEPENDABOT_MERGE_TOKEN: .*/&\\
      OTHER: ${D}{{ secrets.OTHER }}/" "a second secret passed"

selftest_end "the Dependabot merge policy does not hold" \
  "dependabot merge policy: only an allowed Dependabot update with both expected workflows green on its head, mergeable, clean and fresh is eligible; every error is not eligible; read only; the workflow and config pinned; mutation proven"
