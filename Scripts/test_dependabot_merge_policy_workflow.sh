#!/usr/bin/env bash
# Scripts/test_dependabot_merge_policy_workflow.sh
#
# Pins .github/workflows/dependabot_merge_policy.yml (forsgren#666, step 1),
# the REUSABLE Dependabot merge policy that installations call and that
# forsgren's own .github/workflows/dependabot_merge.yml calls too. The
# policy and the comment scripts have their own self-tests
# (Scripts/test_dependabot_merge_policy.sh, which also pins the caller, and
# Scripts/test_dependabot_pr_comment.sh); this one holds the called file to
# every safeguard the caller's one zizmor ignore rests on.
#   1. triggers: workflow_call alone; the inputs settings-file (default
#      .github/dependabot-merge.conf) and mode (default dry-run), strings;
#      one secret, DEPENDABOT_MERGE_TOKEN, not required; no zizmor ignore
#   2. permissions: contents: read, pull-requests: write, actions: read at
#      the workflow level, no job-level block, and exactly what the caller
#      grants
#   3. the job: only for a workflow_run event of a pull_request run of a
#      dependabot/ branch of the caller's own repository, on ubuntu-latest,
#      a concurrency group per repository and branch
#   4. forsgren's scripts: the commit and repository from job.workflow_sha
#      and job.workflow_repository through env:, checked, written to the
#      step's outputs only after the checks (executed: a tag, a short sha, a
#      bad repository refused, nothing written; a good pair written); one
#      checkout, of those outputs, sparse, exactly the three scripts, no
#      credentials; never the caller's repository, never github.workflow_sha,
#      no artifact, no cache
#   5. the settings file from the caller's default branch through the API
#      (executed: a leading /, a .. part, an empty part, an empty path and
#      no default branch refused before any gh call; a failed read fails; a
#      good path is one GET of contents at ref=<default branch>, written to
#      the conf output)
#   6. the policy step: the fetched policy script on the pull request, the
#      settings as DEPENDABOT_MERGE_CONF, the run's head as
#      DEPENDABOT_MERGE_EXPECTED_HEAD, the kill switch from inputs.mode
#      (off, on, dry-run, anything else), eligible= and head_sha= only after
#      the policy's exit 0
#   7. the merge step: the only secret, if: eligible and mode on,
#      HEAD_SHA from the policy, --match-head-commit, the only gh pr merge,
#      no job token (executed: an empty token fails with ❌ and calls no gh;
#      a token merges squash at the head; a refusal fails with gh's message)
#   8. the record step adds the result to the same comment with the job
#      token; no GitHub expression inside any run: block
# Mutation proofs: copies of the workflow with one rule broken must each be
# judged red.
#
# Read with awk, not a YAML parser, as the other workflow pins are.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
selftest_begin "dependabot merge policy workflow pin"

WF=".github/workflows/dependabot_merge_policy.yml"
CALLER=".github/workflows/dependabot_merge.yml"
[[ -f "$WF" ]] || selftest_abort "${WF} does not exist: no installation could call the Dependabot merge policy"
# D stands for a dollar sign inside double quotes, so the expected texts read
# as written without a shellcheck suppression.
D='$'
SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

COMMIT_STEP="Check this workflow's own commit"
SETTINGS_STEP="Read the caller's settings file from its default branch"
MERGE_STEP="Merge the pull request"

# The fake gh: logs its arguments to $FAKE_GH_LOG; fails with a message when
# FAKE_GH_FAIL is set; an api call prints a settings line.
mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/gh" << 'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"
[ -z "${FAKE_GH_FAIL:-}" ] || { echo "Pull request is not mergeable (fake)" >&2; exit 1; }
[ "$1" != api ] || echo "allow github_actions * semver-patch"
exit 0
FAKE
chmod +x "${TMP}/bin/gh"

# run_step <file> <step name> <case dir> [NAME=value...]: the step's run:
# block, executed the way GitHub runs shell: bash (-eo pipefail) with the
# fake gh, in a fresh case dir; RC and OUT as capture leaves them.
run_step() {
  local f="$1" step="$2" dir="$3"
  shift 3
  rm -rf "$dir"
  mkdir -p "$dir"
  step_block "$f" "$step" run > "$dir/step.sh"
  : > "$dir/gh.log"
  : > "$dir/output"
  capture env PATH="${TMP}/bin:${PATH}" FAKE_GH_LOG="$dir/gh.log" GITHUB_OUTPUT="$dir/output" \
    GITHUB_STEP_SUMMARY="$dir/summary.md" RUNNER_TEMP="$dir" GITHUB_REPOSITORY=owner/repo "$@" \
    bash --noprofile --norc -eo pipefail "$dir/step.sh"
}

# executed_findings <file>: one line per rule the executed steps break.
executed_findings() {
  local f="$1" c="${TMP}/exec" bad
  # 4. the commit check
  for bad in "v1.2.3|owner/forsgren" "${SHA:0:12}|owner/forsgren" "${SHA}|not a repository" "|owner/forsgren"; do
    run_step "$f" "$COMMIT_STEP" "$c" FORSGREN_SHA="${bad%%|*}" FORSGREN_REPOSITORY="${bad#*|}"
    [[ "$RC" -ne 0 && ! -s "$c/output" ]] || echo "the commit check accepts '${bad}' or writes an output before refusing it"
  done
  run_step "$f" "$COMMIT_STEP" "$c" FORSGREN_SHA="$SHA" FORSGREN_REPOSITORY=owner/forsgren
  [[ "$RC" -eq 0 ]] && grep -qxF "sha=${SHA}" "$c/output" && grep -qxF "repository=owner/forsgren" "$c/output" ||
    echo "the commit check does not pass a good commit and repository to its outputs"
  # 5. the settings file
  for bad in "/etc/passwd" "../other/x.conf" ".github/../x.conf" ".github//x.conf" "" ".github/x.conf " "-x" "./x.conf" ".github/./x.conf" "."; do
    run_step "$f" "$SETTINGS_STEP" "$c" GH_TOKEN=t SETTINGS_FILE="$bad" DEFAULT_BRANCH=main
    [[ "$RC" -ne 0 && ! -s "$c/gh.log" && ! -s "$c/output" ]] || echo "the settings step accepts the path '${bad}', or reads before refusing it"
  done
  run_step "$f" "$SETTINGS_STEP" "$c" GH_TOKEN=t SETTINGS_FILE=.github/dependabot-merge.conf DEFAULT_BRANCH=
  [[ "$RC" -ne 0 && ! -s "$c/gh.log" ]] || echo "the settings step reads without a default branch"
  run_step "$f" "$SETTINGS_STEP" "$c" GH_TOKEN=t SETTINGS_FILE=.github/dependabot-merge.conf DEFAULT_BRANCH=main FAKE_GH_FAIL=1
  [[ "$RC" -ne 0 && ! -s "$c/output" ]] || echo "the settings step goes on after a failed read"
  run_step "$f" "$SETTINGS_STEP" "$c" GH_TOKEN=t SETTINGS_FILE=.github/dependabot-merge.conf DEFAULT_BRANCH=main
  [[ "$RC" -eq 0 ]] && grep -qxF "conf=${c}/dependabot-merge.conf" "$c/output" && grep -qxF "allow github_actions * semver-patch" "$c/dependabot-merge.conf" &&
    [[ "$(wc -l < "$c/gh.log" | tr -d ' ')" -eq 1 ]] &&
    grep -qxF "api --method GET -H Accept: application/vnd.github.raw+json repos/owner/repo/contents/.github/dependabot-merge.conf -f ref=main" "$c/gh.log" ||
    echo "the settings step does not read the file once, with GET at the default branch, into the conf output ($(cat "$c/gh.log"))"
  # 7. the merge step
  run_step "$f" "$MERGE_STEP" "$c" GH_TOKEN= PR=7 HEAD_SHA="$SHA"
  [[ "$RC" -ne 0 && ! -s "$c/gh.log" ]] && grep -qF "❌ DEPENDABOT_MERGE_TOKEN is not set or empty" <<< "$OUT" ||
    echo "the merge step does not fail on an empty token before any gh call"
  run_step "$f" "$MERGE_STEP" "$c" GH_TOKEN=secret PR=7 HEAD_SHA="$SHA"
  [[ "$RC" -eq 0 ]] && grep -qxF "pr merge 7 -R owner/repo --squash --match-head-commit ${SHA}" "$c/gh.log" &&
    [[ "$(wc -l < "$c/gh.log" | tr -d ' ')" -eq 1 ]] ||
    echo "the merge step does not squash-merge once at the policy's head commit ($(cat "$c/gh.log"))"
  run_step "$f" "$MERGE_STEP" "$c" GH_TOKEN=secret PR=7 HEAD_SHA="$SHA" FAKE_GH_FAIL=1
  [[ "$RC" -ne 0 ]] && grep -qF "Pull request is not mergeable (fake)" "$c/dependabot-merge-result.md" ||
    echo "the merge step does not fail with gh's message on a refusal"
}

# judge <file> [caller]: one line per rule the workflow breaks; nothing when
# it holds them all. Static rules read a copy without comment lines.
judge() {
  local w="$1" caller="${2:-$CALLER}" f perms caller_perms policy merge record if_at yes_at else_at fetch
  f="${TMP}/judged.$(basename "$w").code"
  grep -vE '^[[:space:]]*#' "$w" > "$f" || true
  # 1
  [[ "$(on_events "$f" | paste -sd' ' -)" == "workflow_call" ]] || echo "its triggers are not workflow_call alone"
  grep -qxF "      settings-file:" "$f" && grep -qxF "        default: .github/dependabot-merge.conf" "$f" ||
    echo "it lacks the input settings-file with the default .github/dependabot-merge.conf"
  grep -qxF "      mode:" "$f" && grep -qxF "        default: dry-run" "$f" || echo "it lacks the input mode with the default dry-run"
  [[ "$(grep -cxF '        type: string' "$f")" -eq 2 ]] || echo "its inputs are not two strings"
  [[ "$(sed -n '/^    secrets:$/,/^[^ ]/p' "$f" | grep -cE '^      [A-Za-z_]+:$')" -eq 1 ]] && grep -qxF "      DEPENDABOT_MERGE_TOKEN:" "$f" &&
    [[ "$(sed -n '/^      DEPENDABOT_MERGE_TOKEN:$/,/^[^ ]/p' "$f" | grep -c 'required: false')" -eq 1 ]] ||
    echo "its secrets are not DEPENDABOT_MERGE_TOKEN alone, not required"
  [[ "$(grep -c 'zizmor: ignore' "$w")" -eq 0 ]] || echo "it carries a zizmor ignore"
  # 2
  perms="$(sed -n '/^permissions:/,/^$/p' "$f" | sed '1d;/^$/d' | tr -d ' ' | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$perms" == "actions:read contents:read pull-requests:write " ]] || echo "its permissions are '$perms', not the minimal three"
  [[ "$(grep -cE '^[[:space:]]*permissions:' "$f")" -eq 1 ]] || echo "it has a job-level permissions block"
  caller_perms="$(sed -n '/^permissions:/,/^$/p' "$caller" | grep -vE '^[[:space:]]*#' | sed '1d;/^$/d' | tr -d ' ' | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$perms" == "$caller_perms" ]] || echo "its permissions '$perms' differ from what ${caller} grants ('$caller_perms')"
  # 3
  grep -qxF "      github.event_name == 'workflow_run' &&" "$f" || echo "it does not require a workflow_run event"
  grep -qxF "      github.event.workflow_run.event == 'pull_request' &&" "$f" || echo "it does not require a run of event pull_request"
  grep -qxF "      startsWith(github.event.workflow_run.head_branch, 'dependabot/') &&" "$f" || echo "it does not require a dependabot/ branch"
  grep -qxF "      github.event.workflow_run.head_repository.full_name == github.repository" "$f" || echo "it does not require the head repository to be the caller's"
  [[ "$(grep -cE '^[[:space:]]+runs-on:' "$f")" -eq 1 ]] && grep -qxF "    runs-on: ubuntu-latest" "$f" || echo "the job does not run on GitHub's hosted ubuntu-latest alone"
  grep -qxF "      group: forsgren-dependabot-merge-${D}{{ github.repository }}-${D}{{ github.event.workflow_run.head_branch }}" "$f" &&
    grep -qxF "      cancel-in-progress: false" "$f" || echo "its concurrency group is not per repository and branch, waiting"
  # 4
  grep -qxF "          FORSGREN_SHA: ${D}{{ job.workflow_sha }}" "$f" && grep -qxF "          FORSGREN_REPOSITORY: ${D}{{ job.workflow_repository }}" "$f" ||
    echo "the commit check does not read job.workflow_sha and job.workflow_repository through env:"
  [[ "$(grep -c '{{ job\.workflow_' "$f")" -eq 2 ]] || echo "job.workflow_sha or job.workflow_repository is read outside the commit check"
  ! grep -qE 'github\.workflow_sha|github\.job_workflow_sha' "$f" || echo "it reads the caller's commit (github.workflow_sha)"
  fetch="$(step_text "$f" "Fetch forsgren's merge scripts at this workflow's own commit")"
  [[ "$(grep -c 'uses: actions/checkout@' "$f")" -eq 1 && "$(grep -c 'uses: actions/checkout@' <<< "$fetch")" -eq 1 ]] ||
    echo "it has a checkout other than the fetch of forsgren's scripts"
  grep -qxF "          repository: ${D}{{ steps.forsgren.outputs.repository }}" <<< "$fetch" &&
    grep -qxF "          ref: ${D}{{ steps.forsgren.outputs.sha }}" <<< "$fetch" && [[ "$(grep -cE '^[[:space:]]+(ref|repository):' "$f")" -eq 2 ]] ||
    echo "the fetch is not of the checked commit and repository (it could check out the caller's repository or the pull request)"
  grep -qxF "          persist-credentials: false" <<< "$fetch" || echo "the fetch keeps credentials"
  [[ "$(sed -n '/sparse-checkout: |/,/sparse-checkout-cone-mode/p' <<< "$fetch" | sed '1d;$d' | tr -d ' ' | paste -sd' ' -)" == \
    "Scripts/dependabot_merge_policy.sh Scripts/dependabot_pr_comment.sh Scripts/lib_tmp.sh" ]] &&
    grep -qxF "          sparse-checkout-cone-mode: false" <<< "$fetch" || echo "the fetch is not a sparse checkout of exactly the three scripts"
  ! grep -qE 'download-artifact|actions/cache|^[[:space:]]+cache:|cache-dependency-path' "$f" || echo "it downloads an artifact or uses a cache"
  # 5
  grep -qxF "          DEFAULT_BRANCH: ${D}{{ github.event.repository.default_branch }}" "$f" &&
    grep -qxF "          SETTINGS_FILE: ${D}{{ inputs.settings-file }}" "$f" || echo "the settings step does not read the input from the default branch"
  # 6
  policy="$(step_of "$f" "Apply the merge policy")"
  merge="$(step_of "$f" "$MERGE_STEP")"
  record="$(step_of "$f" "Record the merge result")"
  [[ -n "$policy" && -n "$merge" && -n "$record" ]] || echo "it lacks the policy, the merge or the record step"
  grep -qxF "          DEPENDABOT_MERGE_CONF: ${D}{{ steps.settings.outputs.conf }}" <<< "$policy" &&
    grep -qxF "        if: steps.settings.outputs.conf != ''" <<< "$policy" || echo "the policy does not judge by the settings read from the default branch"
  grep -qxF "          DEPENDABOT_MERGE_EXPECTED_HEAD: ${D}{{ github.event.workflow_run.head_sha }}" <<< "$policy" || echo "it does not give the policy the head commit the run was for"
  grep -qxF "          MODE: ${D}{{ inputs.mode }}" <<< "$policy" && grep -qF "case \"${D}{MODE:-dry-run}\" in" <<< "$policy" || echo "its kill switch is not the input mode, empty meaning dry-run"
  [[ "$(after_line "$policy" "              echo \"The mode is off: no decision, no comment for #${D}PR.\" | tee -a \"${D}GITHUB_STEP_SUMMARY\"")" == '              exit 0' ]] &&
    [[ "$(after_line "$policy" '            on)')" == '              yes="eligible: merging"' ]] &&
    grep -qxF '              no="not eligible: no merge"' <<< "$policy" &&
    [[ "$(after_line "$policy" '            dry-run)')" == '              yes="dry run: would merge"' ]] &&
    [[ "$(after_line "$policy" '            *)')" == '              yes="dry run: would merge"' ]] &&
    [[ "$(grep -cxF '              no="dry run: would not merge"' <<< "$policy")" -eq 2 ]] ||
    echo "its kill switch is not off = log only, on = eligible: merging / not eligible: no merge, anything else = would merge / would not merge"
  if_at="$(grep -nxF "          if ./forsgren-merge/Scripts/dependabot_merge_policy.sh \"${D}PR\" >\"${D}record\"; then" <<< "$policy" | cut -d: -f1)"
  yes_at="$(grep -nxF "              echo \"eligible=true\" >>\"${D}GITHUB_OUTPUT\"" <<< "$policy" | cut -d: -f1)"
  else_at="$(awk -v from="${if_at:-0}" 'NR > from && /^          else$/ { print NR; exit }' <<< "$policy")"
  [[ -n "$if_at" && -n "$yes_at" && -n "$else_at" && "$if_at" -lt "$yes_at" && "$yes_at" -lt "$else_at" ]] &&
    grep -qxF "              echo \"head_sha=${D}head_sha\" >>\"${D}GITHUB_OUTPUT\"" <<< "$policy" &&
    [[ "$(grep -c 'eligible=' "$f")" -eq 1 && "$(grep -c 'head_sha=.*GITHUB_OUTPUT' "$f")" -eq 1 ]] ||
    echo "it does not run the fetched policy, or writes eligible= or head_sha= elsewhere than once, after the policy's exit 0"
  grep -qxF "          ./forsgren-merge/Scripts/dependabot_pr_comment.sh \"${D}PR\" \"${D}RUNNER_TEMP/dependabot-merge-comment.md\"" <<< "$policy" ||
    echo "the policy step does not keep the one comment with the fetched script"
  # 7
  [[ "$(grep -c 'secrets\.' "$f")" -eq 1 ]] && grep -qxF "          GH_TOKEN: ${D}{{ secrets.DEPENDABOT_MERGE_TOKEN }}" <<< "$merge" ||
    echo "it reads a secret other than DEPENDABOT_MERGE_TOKEN as the merge step's GH_TOKEN, or reads one twice: it is not secret-free except the merge step"
  grep -qxF "        if: steps.policy.outputs.eligible == 'true' && inputs.mode == 'on'" <<< "$merge" &&
    [[ "$(grep -c '^        if:' <<< "$merge")" -eq 1 ]] || echo "the merge step's if: does not require both the policy's eligible output and the mode on"
  grep -qxF "          HEAD_SHA: ${D}{{ steps.policy.outputs.head_sha }}" <<< "$merge" &&
    grep -qF "gh pr merge \"${D}PR\" -R \"${D}GITHUB_REPOSITORY\" --squash --match-head-commit \"${D}HEAD_SHA\"" <<< "$merge" ||
    echo "the merge step does not squash-merge with --match-head-commit at the head commit the policy checked"
  [[ "$(grep -c 'gh pr merge' "$f")" -eq 1 && "$(grep -c 'gh pr merge' <<< "$merge")" -eq 1 ]] && ! grep -qE 'gh api .*merge' "$f" ||
    echo "it merges outside the merge step, or more than once"
  ! grep -qE 'github\.token|GITHUB_TOKEN' <<< "$merge" || echo "the merge step can use the job token"
  # 8
  grep -qF "steps.merge.outcome" <<< "$record" && grep -qxF "          GH_TOKEN: ${D}{{ github.token }}" <<< "$record" &&
    grep -qxF "          ./forsgren-merge/Scripts/dependabot_pr_comment.sh \"${D}PR\" \"${D}comment\"" <<< "$record" ||
    echo "the record step does not add the merge result to the same comment with the job token"
  ! run_blocks "$f" | has -qF "${D}{{" || echo "a run: block holds a GitHub expression; values reach the shell through env: only"
  executed_findings "$w"
}
# step_of <code file> <step name>: the step's lines, up to the next step.
step_of() {
  awk -v n="      - name: $2" '/^      - / { inside = ($0 == n) } inside' "$1"
}
# after_line <text> <exact line>: the line that follows it.
after_line() { grep -A1 -xF "$2" <<< "$1" | sed -n 2p; }

findings="$(judge "$WF")"
if [[ -z "$findings" ]]; then echo "  ok: ${WF} holds every rule"; else fail "${WF}: ${findings}"; fi

# Mutation proofs: each broken copy must be judged red.
# mutant <name> <sed> <what>
mutant() {
  local m="${TMP}/mut/$1.yml"
  mkdir -p "${TMP}/mut"
  sed "$2" "$WF" > "$m"
  if cmp -s "$WF" "$m"; then
    fail "mutation proof: the mutation $2 changed nothing: the proof would be vacuous"
  elif [[ -n "$(judge "$m")" ]]; then
    echo "  ok: mutation proof: $3 is caught"
  else
    fail "mutation proof: $3 is not caught"
  fi
}
mutant trigger 's/^  workflow_call:$/  pull_request:\
  workflow_call:/' "a pull_request trigger"
mutant inputdefault 's/^        default: .github\/dependabot-merge.conf$/        default: settings.conf/' "another default settings file"
mutant modeon 's/^        default: dry-run$/        default: on/' "the mode on by default"
mutant secretreq '/^      DEPENDABOT_MERGE_TOKEN:$/,/required: false/s/required: false/required: true/' "the secret required"
mutant zizmor 's/^      - name: Find the pull request of the run.s head commit$/&  # zizmor: ignore[template-injection]/' "a zizmor ignore"
mutant perms 's/^  contents: read$/  contents: write/' "a write permission on contents"
mutant jobperms 's/^    timeout-minutes: 5$/&\
    permissions: write-all/' "a job-level permissions block"
mutant extraperm 's/^  actions: read$/&\
  checks: read/' "a permission the caller does not grant"
mutant event "/github.event_name == 'workflow_run' \\&\\&/d" "any event let through"
mutant prevent "s/github.event.workflow_run.event == 'pull_request' \\&\\&/true \\&\\&/" "a run of another event let through"
mutant fork '/head_repository.full_name == github.repository/d' "a fork's branch let through"
mutant branch "s/'dependabot\\/'/''/" "any branch let through"
mutant runner 's/runs-on: ubuntu-latest/runs-on: [self-hosted, linux]/' "a self-hosted runner"
mutant group 's/^      group: forsgren-dependabot-merge-.*/      group: forsgren-dependabot-merge/' "one concurrency group for every branch"
mutant tagref "s/^          ref: \\${D}{{ steps.forsgren.outputs.sha }}$/          ref: main/" "the scripts fetched from a branch"
mutant callerref "s/^          ref: \\${D}{{ steps.forsgren.outputs.sha }}$/          ref: ${D}{{ github.event.workflow_run.head_sha }}/" "a checkout of the pull request's head"
mutant callerrepo "/^          repository: \\${D}{{ steps.forsgren.outputs.repository }}$/d" "a checkout of the caller's repository"
mutant callersha "s/FORSGREN_SHA: \\${D}{{ job.workflow_sha }}/FORSGREN_SHA: ${D}{{ github.workflow_sha }}/" "the caller's commit taken for forsgren's"
mutant nocheck "s/if \\[\\[ ! \"\\${D}FORSGREN_SHA\" =~ \\${D}full_commit \\]\\]; then/if false; then/" "the commit check disabled"
mutant earlyout "s/^          full_commit='.*'$/&\\
          echo \"sha=${D}{FORSGREN_SHA}\" >>\"${D}GITHUB_OUTPUT\"/" "the commit written before it is checked"
mutant creds 's/persist-credentials: false/persist-credentials: true/' "a fetch that keeps credentials"
mutant fullfetch '/sparse-checkout-cone-mode: false/d' "a fetch that is not sparse"
mutant morefiles 's/^            Scripts\/lib_tmp.sh$/&\
            Scripts\//' "a fetch of more than the three scripts"
mutant secondcheckout 's/^      - name: Find the pull request of the run.s head commit$/      - uses: actions\/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1\
&/' "a second checkout"
mutant artifact 's/^      - name: Find the pull request of the run.s head commit$/      - uses: actions\/download-artifact@0000000000000000000000000000000000000000\
&/' "an artifact download"
mutant pathcheck "s/if \\[\\[ ! \"\\${D}SETTINGS_FILE\" =~ \\${D}plain_path \\]\\] || /if /" "the settings path check reduced to the .. test"
mutant dotdot 's#== \*/\.\./\*#== */never/*#' "a .. part let through"
mutant dot 's#== \*/\./\*#== */never/*#' "a . part let through"
mutant prbranch "s/DEFAULT_BRANCH: \\${D}{{ github.event.repository.default_branch }}/DEFAULT_BRANCH: ${D}{{ github.event.workflow_run.head_branch }}/" "the settings read from the pull request's branch"
mutant readfail '/cannot be read from the default branch/{n;s/^            exit 1$/            :/;}' "a failed settings read that goes on"
mutant noconf '/DEPENDABOT_MERGE_CONF:/d' "the policy judging by forsgren's own settings"
mutant expected '/DEPENDABOT_MERGE_EXPECTED_HEAD:/d' "the run's head commit not given to the policy"
mutant killswitch "s/^              yes=\"dry run: would merge\"$/              gh pr merge \"${D}PR\"; yes=\"dry run: would merge\"/" "a merge in dry-run"
mutant dryeligible 's/^              yes="dry run: would merge"$/              yes="eligible: merging"/' "dry-run commenting eligible: merging"
mutant offcomments '/no decision, no comment for/{n;s/^              exit 0$/              :/;}' "off going on to decide and comment"
mutant varsmode "s/MODE: \\${D}{{ inputs.mode }}/MODE: ${D}{{ vars.DEPENDABOT_AUTOMERGE }}/" "the switch read from a variable, not the input"
mutant dropon "s/ \\&\\& inputs.mode == 'on'$//" "the merge step without the on condition"
mutant dropeligible "s/if: steps.policy.outputs.eligible == 'true' \\&\\& /if: /" "the merge step without the eligible condition"
mutant dropmatch "s/ --match-head-commit \"\\${D}HEAD_SHA\"//" "the merge without --match-head-commit"
mutant runhead "s/HEAD_SHA: \\${D}{{ steps.policy.outputs.head_sha }}/HEAD_SHA: ${D}{{ github.event.workflow_run.head_sha }}/" "the merged head taken from the run, not from the policy"
mutant jobtoken "s/GH_TOKEN: \\${D}{{ secrets.DEPENDABOT_MERGE_TOKEN }}/GH_TOKEN: ${D}{{ github.token }}/" "the job token swapped in for the merge"
mutant fallback "s/GH_TOKEN: \\${D}{{ secrets.DEPENDABOT_MERGE_TOKEN }}/GH_TOKEN: ${D}{{ secrets.DEPENDABOT_MERGE_TOKEN || github.token }}/" "a job token fallback for the merge"
mutant emptytoken "s/if \\[ -z \"\\${D}GH_TOKEN\" \\]; then/if false; then/" "the empty-token check disabled"
mutant refusalgreen '/GitHub refused to merge/,/exit 1/s/^          exit 1$/          exit 0/' "a refused merge reported green"
mutant eligibleanyway "s/^          record=\"\\${D}RUNNER_TEMP\\/dependabot-merge-record.md\"$/&\\
          echo \"eligible=true\" >>\"${D}GITHUB_OUTPUT\"/" "eligible written before the policy ran"
mutant eligibleelse "s/^            verdict=\"\\${D}no\"$/            verdict=\"${D}no\"; echo \"eligible=true\" >>\"${D}GITHUB_OUTPUT\"/" "eligible written on the policy's refusal"
mutant norecord "/^          .\\/forsgren-merge\\/Scripts\\/dependabot_pr_comment.sh \"\\${D}PR\" \"\\${D}comment\"$/d" "the merge result not added to the comment"
mutant secret "s/^          GH_TOKEN: \\${D}{{ github.token }}$/          GH_TOKEN: ${D}{{ secrets.DEPENDABOT_MERGE_TOKEN }}/" "a secret read outside the merge step"
mutant injection "s/^          echo \"forsgren merge scripts: .*/          echo \"${D}{{ github.repository }}\"/" "a GitHub expression inside a run: block"

selftest_end "the reusable Dependabot merge policy workflow does not hold" \
  "dependabot merge policy workflow: workflow_call with the settings file and mode inputs and one optional secret; minimal permissions equal to the caller's; forsgren's three scripts fetched at its own checked commit, never the caller's code; settings from the default branch; the secret in the merge step alone, at the policy's head, never the job token; mutation proven"
