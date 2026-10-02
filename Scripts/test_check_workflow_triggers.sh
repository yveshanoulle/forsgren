#!/usr/bin/env bash
# Scripts/test_check_workflow_triggers.sh
#
# Self-test for Scripts/check_workflow_triggers.sh (forsgren#1, ladder step
# 16), run in pre before the gate it validates. forsgren's own: no repo of the
# estate has this gate, so none has a fixture for it. Every workflow here is
# made up, written into a temp dir; the gate takes that dir as its argument.
#
#   1. self-hosted job, `on: pull_request` (scalar)        -> red, naming the
#                                                             file, the
#                                                             trigger, the job
#   2. self-hosted job, `pull_request_target:` (block map) -> red
#   3. `on: [push, pull_request]` (flow list)              -> red
#   4. `on: {pull_request: ...}` (flow map)                -> red
#   5. `on:` block list `- pull_request`                   -> red
#   6. pull_request_review (the same fork-code event)      -> red
#   7. GitHub-hosted job (ubuntu-latest), pull_request     -> green
#   8. self-hosted job, push and workflow_dispatch only    -> green
#   9. a comment naming pull_request inside `on:`          -> green (comments
#                                                             are not triggers;
#                                                             quality.yml has
#                                                             such a comment)
#  10. runs-on as a block list holding self-hosted         -> red
#  11. runs-on a custom label without `self-hosted`        -> red (a label only
#                                                             a self-hosted
#                                                             runner carries)
#  12. runs-on a matrix expression                         -> red (cannot be
#                                                             proven hosted)
#  13. a reusable-workflow job (job-level `uses:`)         -> red (its runner
#                                                             is decided
#                                                             elsewhere)
#  14. two jobs, one hosted, one self-hosted               -> red, naming the
#                                                             self-hosted job
#                                                             and not the other
#  15. a .yaml file is scanned like a .yml                 -> red
#  16. a workflow with no `on:` key                        -> red (unjudged is
#                                                             not clean)
#  17. a dir with no workflow file                         -> red: a scan over
#                                                             nothing
#  18. a missing dir                                       -> exit 2, never 0
#  19. this repository's .github/workflows                 -> green
# Mutation proof: case 1 against a copy of the gate whose PR_EVENTS pattern
# never matches must turn green, so case 1 is red BECAUSE it triggers on a
# pull-request event, not for something else in its file.
#
# The gate itself absent or not executable: this self-test is red, with the
# FAIL line below, before any case runs.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_workflow_triggers.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "workflow-trigger self-test"

[[ -x "$GATE" ]] || selftest_abort "${GATE} not found or not executable — the workflow-trigger gate this self-test validates does not exist, so nothing keeps a pull-request trigger off the self-hosted runner"

SELF_HOSTED='    runs-on: [self-hosted, macOS, ARM64]'
HOSTED='    runs-on: ubuntu-latest'

# workflow <case-dir> <file-name> <on-block> <runs-on-line>: one workflow
# file, with one job `build` on that runner, alone in its own dir.
workflow() {
  mkdir -p "$TMP/$1"
  {
    echo "name: Sample"
    printf '%s\n' "$3"
    echo "permissions:"
    echo "  contents: read"
    echo "jobs:"
    echo "  build:"
    printf '%s\n' "$4"
    echo "    steps:"
    echo "      - uses: actions/checkout@v4"
    echo "      - run: echo hi"
  } > "$TMP/$1/$2"
}

workflow scalar ci.yml 'on: pull_request' "$SELF_HOSTED"
capture "$GATE" "$TMP/scalar"
want_rc "1. rejects a self-hosted job on \`on: pull_request\`" 1
want_said "1. the finding names the file" "ci.yml"
want_said "1. the finding names the trigger" "pull_request"
want_said "1. the finding names the job" "build"

workflow target ci.yml 'on:
  pull_request_target:
    types: [opened]' "$SELF_HOSTED"
capture "$GATE" "$TMP/target"
want_rc "2. rejects a self-hosted job on pull_request_target" 1
want_said "2. the finding names pull_request_target" "pull_request_target"

workflow flowlist ci.yml 'on: [push, pull_request]' "$SELF_HOSTED"
capture "$GATE" "$TMP/flowlist"
want_rc "3. rejects the list form \`on: [push, pull_request]\`" 1

workflow flowmap ci.yml 'on: {pull_request: {branches: [main]}}' "$SELF_HOSTED"
capture "$GATE" "$TMP/flowmap"
want_rc "4. rejects the map form \`on: {pull_request: ...}\`" 1

workflow blocklist ci.yml 'on:
  - push
  - pull_request' "$SELF_HOSTED"
capture "$GATE" "$TMP/blocklist"
want_rc "5. rejects the block-list form \`- pull_request\`" 1

workflow review ci.yml 'on:
  pull_request_review:
    types: [submitted]' "$SELF_HOSTED"
capture "$GATE" "$TMP/review"
want_rc "6. rejects pull_request_review (it checks out the pull request's code too)" 1

workflow hosted ci.yml 'on: [push, pull_request]' "$HOSTED"
capture "$GATE" "$TMP/hosted"
want_rc "7. a GitHub-hosted job on pull_request is allowed" 0

workflow pushonly ci.yml 'on:
  push:
    branches: ["main"]
  workflow_dispatch:' "$SELF_HOSTED"
capture "$GATE" "$TMP/pushonly"
want_rc "8. a self-hosted job on push and workflow_dispatch only is allowed" 0

workflow comment ci.yml 'on:
  # NO pull_request and NO pull_request_target, ever.
  push:
    branches: ["main"]  # not on pull_request
  workflow_dispatch:' "$SELF_HOSTED"
capture "$GATE" "$TMP/comment"
want_rc "9. a comment naming pull_request is not a trigger" 0

workflow runsblock ci.yml 'on: pull_request' '    runs-on:
      - self-hosted
      - macOS'
capture "$GATE" "$TMP/runsblock"
want_rc "10. rejects runs-on as a block list holding self-hosted" 1

workflow customlabel ci.yml 'on: pull_request' '    runs-on: runner-acme'
capture "$GATE" "$TMP/customlabel"
want_rc "11. rejects runs-on a custom label without self-hosted" 1

mkdir -p "$TMP/matrix"
cat > "$TMP/matrix/ci.yml" <<'YAML'
name: Sample
on: pull_request
jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest]
    steps:
      - run: echo hi
YAML
capture "$GATE" "$TMP/matrix"
want_rc "12. rejects runs-on a matrix expression" 1

mkdir -p "$TMP/reusable"
cat > "$TMP/reusable/ci.yml" <<'YAML'
name: Sample
on: pull_request
jobs:
  call:
    uses: ./.github/workflows/build.yml
YAML
capture "$GATE" "$TMP/reusable"
want_rc "13. rejects a reusable-workflow job on pull_request" 1

mkdir -p "$TMP/twojobs"
cat > "$TMP/twojobs/ci.yml" <<'YAML'
name: Sample
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo lint
  deploy:
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo deploy
YAML
capture "$GATE" "$TMP/twojobs"
want_rc "14. rejects a workflow whose second job is self-hosted" 1
want_said "14. the finding names the self-hosted job" "job 'deploy'"
if grep -qF "job 'lint'" <<<"$OUT"; then
  fail "14. the GitHub-hosted job is named as a finding. Output: $OUT"
else
  echo "  ok: 14. the GitHub-hosted job is not a finding"
fi

workflow yamlext ci.yaml 'on: pull_request' "$SELF_HOSTED"
capture "$GATE" "$TMP/yamlext"
want_rc "15. scans a .yaml file like a .yml" 1
want_said "15. the finding names ci.yaml" "ci.yaml"

mkdir -p "$TMP/noon"
cat > "$TMP/noon/ci.yml" <<'YAML'
name: Sample
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
YAML
capture "$GATE" "$TMP/noon"
want_rc "16. rejects a workflow with no on: key" 1

mkdir -p "$TMP/empty"
echo "not a workflow" > "$TMP/empty/README.md"
capture "$GATE" "$TMP/empty"
want_rc "17. rejects a dir with no workflow file" 1
want_said "17. the finding says it scanned nothing" "scan over nothing"

capture "$GATE" "$TMP/does-not-exist"
want_rc "18. exits 2 on a missing dir, never 0" 2

capture "$GATE"
want_rc "19. this repository's workflows keep pull-request triggers off the self-hosted runner" 0
[[ "$RC" -eq 0 ]] || printf '%s\n' "$OUT" | sed 's/^/    /'

# Mutation proof for case 1: the same workflow against a copy of the gate
# whose PR_EVENTS pattern can never match must be green, and must say why.
# The mutant cds to its own dir's parent; give it the same layout.
MUTANT="$TMP/mutant/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUTANT" "s/^PR_EVENTS=.*/PR_EVENTS='NEVER-MATCHES-ANY-EVENT'/"; then
  capture "$MUTANT" "$TMP/scalar"
  if [[ "$RC" -eq 0 ]] && ! grep -qF "pull_request" <<<"$OUT"; then
    echo "  ok: mutation proof: without the PR_EVENTS pattern case 1 is green, so it is red because it triggers on pull_request"
  else
    fail "mutation proof: a gate whose PR_EVENTS never matches is still red on case 1, or still names pull_request (exit $RC) — case 1 is red for another reason. Output: $OUT"
  fi
fi

selftest_end "the workflow-trigger gate does not keep pull-request triggers off the self-hosted runner" \
  "workflow-trigger gate is red on a pull-request trigger (every on: form, pull_request_review included) in a workflow with a job not on a GitHub-hosted runner (self-hosted, a custom label, a matrix, a reusable workflow; .yml and .yaml), on no on: key, on no workflow file and on a missing dir, green on a hosted job, on push-only triggers and on a comment, this repository's workflows pass, and its PR_EVENTS pattern is what reddens case 1"
