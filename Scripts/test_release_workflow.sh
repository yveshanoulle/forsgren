#!/usr/bin/env bash
# Scripts/test_release_workflow.sh
#
# Pins .github/workflows/release.yml, the Release workflow (forsgren#221,
# step 2 of 2). forsgren's own. Nothing in sfl or Quality runs the workflow, so
# this pin is what proves it, on every run, in the shape of
# Scripts/test_vulncheck_workflow.sh: the real file must hold every pin, and
# each pin is proved by a mutant of the real file that breaks it and must be
# named. The pins:
#   1. workflow_dispatch and nothing else; one input `bump`, a choice of
#      patch, minor, major, default patch; one release at a time, never cancelled
#   2. top-level permissions contents: read; the one job has exactly contents,
#      actions and issues, the first two write, the last read; one job on ubuntu-latest
#   3. only checkout and setup-go, pinned by the commits metrics.yml pins; the
#      checkout keeps no credentials
#   4. no run: block expands a ${{ }} expression (template injection)
#   5. the steps, in this order, each with its name: the run is on main,
#      checkout, Go, the log, the token check, Quality on main, the plan, the
#      version is free, the bump, go test, the commit, Quality on the bump
#      commit, the release, the template, the metrics pull request, the report
#   6. each step runs exactly its script with its arguments
#   7. the secret FORSGREN_RELEASE_TOKEN is in the env of the token check, the
#      template step and the metrics step, and nowhere else
#   8. the tag is made by Scripts/release_publish.sh alone: the workflow has no
#      git tag, no git push, no gh release
#   9. the last step runs `if: ${{ always() }}`, reports the job's status and
#      gets the outcome of every step (steps.<id>.outcome), every step has its
#      id, and the token check and the test record themselves in the log

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

WORKFLOW=".github/workflows/release.yml"
METRICS=".github/workflows/metrics.yml"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
selftest_begin "release workflow pin"

[[ -f "$WORKFLOW" ]] || selftest_abort "${WORKFLOW} does not exist: nothing releases forsgren in one run"
[[ -f "$METRICS" ]] || selftest_abort "${METRICS} does not exist: the action pins have nothing to be compared with"

DOLLAR='$'

code() { grep -vE '^[[:space:]]*#' "$1"; }

pin_of() { code "$1" | grep -E "uses: actions/$2@" | head -1 | sed -E 's/.*@([0-9a-f]{40}).*/\1/'; }

# want_line <file> <step> <exact line>: that step holds that line.
step_has() {
  step_text "$1" "$2" | grep -qxF -- "$3" || echo "step '$2': want the line: $3"
}

NAMES=(
  "Require a run on main"
  "Check out main"
  "Set up Go"
  "Start the log of what is done"
  "Check the release token is set"
  "Find the release to resume"
  "Quality is green on main"
  "Plan the release"
  "Check the version is new"
  "Bump the version in the working tree"
  "Test the bumped tree"
  "Commit the bump and push it to main"
  "Quality is green on the bump commit"
  "Create the tag and the release"
  "Move the pins and README of forsgren-template"
  "Open the pin pull request in forsgren-metrics"
  "Say what was done"
)

# IDS: the step ids in the order of NAMES; the report step passes the outcome
# of each (steps.<id>.outcome), so it names the step that failed (forsgren#221).
IDS=(main checkout setup-go log token resume quality plan free bump test commit quality-bump publish template metrics)

id_findings() {
  local i name id
  for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"
    id="${IDS[$i]:-}"
    [[ -n "$id" ]] || continue
    step_text "$1" "$name" | grep -qxF "        id: ${id}" || echo "ids: the step '${name}' has no id '${id}'"
    step_text "$1" "Say what was done" | grep -qxF "            ${id}=${DOLLAR}{{ steps.${id}.outcome }}" \
      || echo "outcomes: the report step does not get steps.${id}.outcome"
  done
  step_text "$1" "Say what was done" | grep -qxF '          RELEASE_STEP_OUTCOMES: |' || echo "outcomes: the report step has no RELEASE_STEP_OUTCOMES"
}

# resume_findings: with `resume: pins` only the template and metrics steps run
# for the release that exists; every step that makes a release is skipped.
resume_findings() {
  local name
  # A new release only: the steps that make the release.
  for name in "Quality is green on main" "Plan the release" "Check the version is new" "Bump the version in the working tree" "Test the bumped tree" "Commit the bump and push it to main"; do
    step_text "$1" "$name" | grep -qxF "        if: ${DOLLAR}{{ inputs.resume == 'none' }}" || echo "resume: the step '${name}' is not skipped by resume: pins and publish"
  done
  # Quality on the bump commit and the publish also run for resume: publish.
  for name in "Quality is green on the bump commit" "Create the tag and the release"; do
    step_text "$1" "$name" | grep -qxF "        if: ${DOLLAR}{{ inputs.resume != 'pins' }}" || echo "resume: the step '${name}' is not skipped by resume: pins only"
  done
  for name in "Move the pins and README of forsgren-template" "Open the pin pull request in forsgren-metrics" "Check the release token is set"; do
    if step_text "$1" "$name" | grep -qE '^        if:'; then echo "resume: the step '${name}' must run also when resuming"; fi
  done
  code "$1" | grep -qxF '        options: [none, pins, publish]' || echo "input: resume is not a choice of none, pins, publish"
  awk '/^      resume:/ { r=1 } r && /default:/ { print; exit }' "$1" | grep -qxF '        default: none' || echo "input: the default resume is not none"
}

trigger_findings() {
  local events
  events="$(on_events "$1" | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$events" == "workflow_dispatch " ]] || echo "triggers: want workflow_dispatch only, got: ${events:-none}"
  code "$1" | grep -qxF '        options: [patch, minor, major]' || echo "input: bump is not a choice of patch, minor, major"
  code "$1" | grep -qxF '        default: patch' || echo "input: the default bump is not patch"
  code "$1" | grep -qxF '        type: choice' || echo "input: bump is not a choice"
  code "$1" | grep -qxF '  group: release' || echo "concurrency: the group is not release"
  code "$1" | grep -qxF '  cancel-in-progress: false' || echo "concurrency: a release in flight can be cancelled"
}

permission_findings() {
  awk '/^permissions:/ { getline; if ($0 == "  contents: read") ok=1 } END { exit !ok }' "$1" \
    || echo "permissions: the top level is not contents: read"
  local perms
  perms="$(awk '/^    permissions:/ { p=1; next } p && /^      [a-z-]+:/ { s=$0; sub(/#.*/, "", s); gsub(/ +/, " ", s); print s; next } p { exit }' "$1" | tr -d ' ' | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$perms" == "actions:write contents:write issues:read " ]] || echo "permissions: the job must hold exactly actions write, contents write, issues read, got: ${perms:-none}"
  local hosts
  hosts="$(code "$1" | grep -E '^[[:space:]]+runs-on:' | sed -E 's/.*runs-on:[[:space:]]*//' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
  [[ "$hosts" == " 1 ubuntu-latest;" ]] || echo "runs-on: want one job on ubuntu-latest, got: ${hosts}"
}

action_findings() {
  local used action want got
  used="$(code "$1" | grep -E '^[[:space:]]+(- )?uses:' | sed -E 's/.*uses:[[:space:]]*([^@ ]+)@.*/\1/' | LC_ALL=C sort -u | tr '\n' ' ')"
  [[ "$used" == "actions/checkout actions/setup-go " ]] || echo "actions: want checkout and setup-go only, got: ${used}"
  if code "$1" | grep -E 'uses:' | grep -vqE '@[0-9a-f]{40}  # v[0-9]'; then
    echo "pins: an action is not pinned by a full commit with its version comment"
  fi
  for action in checkout setup-go; do
    want="$(pin_of "$METRICS" "$action")"
    got="$(pin_of "$1" "$action")"
    [[ -n "$want" && "$got" == "$want" ]] || echo "pin of ${action}: ${got:-none} is not metrics.yml's ${want:-none}"
  done
  step_has "$1" "Check out main" '          persist-credentials: false' | sed 's/^step/checkout: step/' | grep . || true
}

step_findings() {
  local previous=0 name line
  for name in "${NAMES[@]}"; do
    line="$(line_of "$1" "- name: ${name}")"
    if [[ -z "$line" ]]; then
      echo "steps: there is no step named '${name}'"
    elif [[ "$line" -le "$previous" ]]; then
      echo "order: the step '${name}' is out of order"
    else
      previous="$line"
    fi
  done
  if run_blocks "$1" | grep -qF -- "\${{"; then
    echo "injection: a run: block expands a \${{ }} expression"
  fi
}

# PINNED_LINES: <step name>@@<the exact line that step holds>, one per row.
PINNED_LINES="$(cat <<'ROWS'
Check the release token is set@@          ./Scripts/release_pins.sh token
Check the release token is set@@          echo "token: FORSGREN_RELEASE_TOKEN is set" >> "$RELEASE_LOG"
Find the release to resume@@        if: ${{ inputs.resume != 'none' }}
Find the release to resume@@          RESUME_MODE: ${{ inputs.resume }}
Find the release to resume@@          ./Scripts/release_resume.sh "$RESUME_MODE" | tee "${RUNNER_TEMP}/resume.txt"
Find the release to resume@@          echo "resume: $(grep '^tag=' "${RUNNER_TEMP}/resume.txt") at $(grep '^sha=' "${RUNNER_TEMP}/resume.txt" | cut -d= -f2)" >> "$RELEASE_LOG"
Quality is green on the bump commit@@          BUMP_SHA: ${{ steps.commit.outputs.sha || steps.resume.outputs.sha }}
Create the tag and the release@@          VERSION: ${{ steps.plan.outputs.version || steps.resume.outputs.version }}
Create the tag and the release@@          BUMP_SHA: ${{ steps.commit.outputs.sha || steps.resume.outputs.sha }}
Say what was done@@          RELEASE_BUMP: ${{ inputs.bump }}
Check out main@@          fetch-depth: 200  # resume: publish looks for the bump commit in the history
Move the pins and README of forsgren-template@@          VERSION: ${{ steps.plan.outputs.version || steps.resume.outputs.version }}
Move the pins and README of forsgren-template@@          BUMP_SHA: ${{ steps.commit.outputs.sha || steps.resume.outputs.sha }}
Open the pin pull request in forsgren-metrics@@          VERSION: ${{ steps.plan.outputs.version || steps.resume.outputs.version }}
Open the pin pull request in forsgren-metrics@@          BUMP_SHA: ${{ steps.commit.outputs.sha || steps.resume.outputs.sha }}
Say what was done@@          RELEASE_RESUME: ${{ inputs.resume }}
Quality is green on main@@          ./Scripts/release_quality.sh check "$GITHUB_SHA"
Plan the release@@          ./Scripts/release_plan.sh "$BUMP" --notes "${RUNNER_TEMP}/notes.md" | tee "${RUNNER_TEMP}/plan.txt"
Plan the release@@          BUMP: ${{ inputs.bump }}
Check the version is new@@          ./Scripts/release_publish.sh free "$VERSION"
Bump the version in the working tree@@          ./Scripts/release_bump.sh "$VERSION"
Test the bumped tree@@          go test ./...
Test the bumped tree@@          echo "test: go test ./... passes on the bumped tree" >> "$RELEASE_LOG"
Commit the bump and push it to main@@          ./Scripts/release_commit.sh "$VERSION" "$ISSUES" "$remote" | tee "${RUNNER_TEMP}/commit.txt"
Commit the bump and push it to main@@          FORSGREN_PRIVATE_NAMES: ${{ secrets.FORSGREN_PRIVATE_NAMES }}
Quality is green on the bump commit@@          ./Scripts/release_quality.sh dispatch "$BUMP_SHA" main
Create the tag and the release@@          ./Scripts/release_publish.sh create "$VERSION" "$BUMP_SHA" "${RUNNER_TEMP}/notes.md"
Move the pins and README of forsgren-template@@          ./Scripts/release_pins.sh template "$VERSION" "$BUMP_SHA"
Open the pin pull request in forsgren-metrics@@          ./Scripts/release_pins.sh metrics "$VERSION" "$BUMP_SHA"
Say what was done@@        if: ${{ always() }}
Say what was done@@        run: ./Scripts/release_report.sh "${RELEASE_LOG:-${RUNNER_TEMP}/release.log}" "$JOB_STATUS"
Say what was done@@          JOB_STATUS: ${{ job.status }}
Require a run on main@@          REF: ${{ github.ref }}
ROWS
)"

command_findings() {
  local row
  while IFS= read -r row; do
    step_has "$1" "${row%%@@*}" "${row#*@@}"
  done <<< "$PINNED_LINES"
}

secret_findings() {
  local count where
  count="$(code "$1" | grep -c 'secrets.FORSGREN_RELEASE_TOKEN' || true)"
  [[ "$count" -eq 3 ]] || echo "secret: FORSGREN_RELEASE_TOKEN appears ${count} times, want 3 (token check, template, metrics)"
  for where in "Check the release token is set" "Move the pins and README of forsgren-template" "Open the pin pull request in forsgren-metrics"; do
    step_text "$1" "$where" | grep -qF "FORSGREN_RELEASE_TOKEN: ${DOLLAR}{{ secrets.FORSGREN_RELEASE_TOKEN }}" \
      || echo "secret: the step '${where}' does not get FORSGREN_RELEASE_TOKEN"
  done
}

tag_findings() {
  if code "$1" | grep -qE 'git tag|git push|git remote|gh release|--tags|gh api .*git/(refs|tags)'; then
    echo "tag: the workflow makes a tag, a push or a release itself, not only through the scripts"
  fi
  if code "$1" | grep -qE 'echo .*.remote|echo .*GH_TOKEN'; then
    echo "token: the workflow echoes a token"
  fi
}

findings() {
  trigger_findings "$1"
  permission_findings "$1"
  action_findings "$1"
  step_findings "$1"
  command_findings "$1"
  id_findings "$1"
  resume_findings "$1"
  secret_findings "$1"
  tag_findings "$1"
}

OUT="$(findings "$WORKFLOW")"
if [[ -z "$OUT" ]]; then
  echo "  ok: the real workflow holds every pin"
else
  fail "the real workflow breaks a pin:"$'\n'"$OUT"
fi

mutant() {
  local file="${TMP}/$1.yml"
  sed "$2" "$WORKFLOW" > "$file"
  if cmp -s "$WORKFLOW" "$file"; then
    fail "the mutation $2 changed nothing: the proof of '$1' would be vacuous"
    return 0
  fi
  OUT="$(findings "$file")"
  if grep -qF -- "$3" <<< "$OUT"; then
    echo "  ok: mutation proof: $1"
  else
    fail "mutation proof: '$1' was not named '$3'. Findings: ${OUT:-none}"
  fi
}

mutant "a push trigger" 's/^  workflow_dispatch:/  push:/' "triggers: want workflow_dispatch only"
mutant "a schedule" 's/^  workflow_dispatch:/  workflow_dispatch:\
  schedule:/' "triggers: want workflow_dispatch only"
mutant "a default of minor" 's/^        default: patch/        default: minor/' "input: the default bump"
mutant "a free text bump" 's/^        type: choice/        type: string/' "input: bump is not a choice"
mutant "a cancellable release" 's/cancel-in-progress: false/cancel-in-progress: true/' "concurrency: a release in flight"
mutant "a write token at the top" 's/^  contents: read/  contents: write/' "permissions: the top level"
mutant "pull requests write" 's/^      issues: read /      pull-requests: write\
      issues: read /' "permissions: the job must hold exactly"
mutant "no actions write" 's/^      actions: write /      actions: read /' "permissions: the job must hold exactly"
mutant "a macOS runner" 's/runs-on: ubuntu-latest/runs-on: macos-latest/' "runs-on: want one job"
mutant "a self-hosted runner" 's/runs-on: ubuntu-latest/runs-on: self-hosted/' "runs-on: want one job"
mutant "an unpinned checkout" 's/checkout@[0-9a-f]\{40\}/checkout@v7/' "pins: an action is not pinned"
mutant "another commit of setup-go" 's/setup-go@b7ad/setup-go@b7ae/' "pin of setup-go:"
mutant "persisted credentials" 's/persist-credentials: false/persist-credentials: true/' "step 'Check out main'"
mutant "a template expression in run" "s#^          go test ./...#          go test ${DOLLAR}{{ inputs.bump }}#" "injection:"
mutant "no quality wait on main" 's/name: Quality is green on main/name: Quality on main/' "no step named 'Quality is green on main'"
mutant "the release before the commit" 's/name: Commit the bump and push it to main/name: Moved/;s/name: Create the tag and the release/name: Commit the bump and push it to main/;s/name: Moved/name: Create the tag and the release/' "order:"
mutant "no go test" 's/^          go test \.\/\.\.\.$/          true/' "step 'Test the bumped tree'"
mutant "a resume that republishes" "/name: Create the tag and the release/,/shell:/s/inputs.resume != 'pins'/inputs.resume == 'none'/" "resume: the step 'Create the tag and the release' is not skipped by resume: pins only"
mutant "a resume: pins that republishes" "/name: Create the tag and the release/,/shell:/{/if: .{{ inputs.resume != 'pins' }}/d;}" "resume: the step 'Create the tag and the release' is not skipped by resume: pins only"
mutant "a resume that bumps again" "/name: Bump the version in the working tree/,/shell:/{/if: .{{ inputs.resume == 'none' }}/d;}" "resume: the step 'Bump the version in the working tree' is not skipped"
mutant "a template step skipped by resume" "/name: Move the pins and README of forsgren-template/,/shell:/s/^        id: template\$/        id: template\\
        if: ${DOLLAR}{{ inputs.resume != 'pins' }}/" "resume: the step 'Move the pins and README of forsgren-template' must run"
mutant "a resume by default" 's/^        default: none/        default: pins/' "input: the default resume is not none"
mutant "a template that ignores the resumed release" 's/^          VERSION: \(.*\) || steps.resume.outputs.version }}/          VERSION: \1 }}/' "Move the pins and README of forsgren-template"
mutant "a token check that records nothing" '/echo "token: FORSGREN_RELEASE_TOKEN is set"/d' "step 'Check the release token is set'"
mutant "a step without an id" '/^        id: token$/d' "ids: the step 'Check the release token is set'"
mutant "an outcome the report does not get" '/^            token=/d' "outcomes: the report step does not get steps.token.outcome"
mutant "the wrong step's outcome" 's/^            token=.*$/            token=success/' "outcomes: the report step does not get steps.token.outcome"
mutant "no outcomes at all" 's/RELEASE_STEP_OUTCOMES: |/RELEASE_STEP_OUTCOMES_X: |/' "outcomes: the report step has no RELEASE_STEP_OUTCOMES"
mutant "a bump that is not the plan's" "s/release_bump.sh \".VERSION\"/release_bump.sh 9.9.9/" "step 'Bump the version in the working tree'"
mutant "the release before quality on the bump" "s/release_quality.sh dispatch \".BUMP_SHA\" main/release_quality.sh check \"${DOLLAR}BUMP_SHA\"/" "step 'Quality is green on the bump commit'"
mutant "a tag made by hand" 's/^          set -euo pipefail$/          set -euo pipefail\
          git tag v0/' "tag: the workflow makes a tag"
mutant "a release made by hand" "s/release_publish.sh create \".VERSION\"/gh release create \"${DOLLAR}VERSION\"/" "tag: the workflow makes a tag"
mutant "the token in a job env" "s/^      GH_REPO: \(.*\)\$/      GH_REPO: \1\\
      FORSGREN_RELEASE_TOKEN: ${DOLLAR}{{ secrets.FORSGREN_RELEASE_TOKEN }}/" "secret: FORSGREN_RELEASE_TOKEN appears"
mutant "the template step without the secret" '/name: Move the pins and README/,/run:/s/FORSGREN_RELEASE_TOKEN: .*$/FORSGREN_RELEASE_TOKEN: x/' "secret: the step 'Move the pins"
mutant "a report that only runs on success" "s/if: .{{ always() }}/if: ${DOLLAR}{{ success() }}/" "step 'Say what was done'"
mutant "a leaked token" "s/^          remote=\(.*\)\$/          remote=\1\\
          echo \"${DOLLAR}remote\"/" "token: the workflow echoes a token"

selftest_end "the release workflow pin found failures" "release workflow pin (the real file holds every pin; each mutant is named)"
