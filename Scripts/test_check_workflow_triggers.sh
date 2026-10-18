#!/usr/bin/env bash
# canon: test_check_workflow_triggers v2
# Scripts/test_check_workflow_triggers.sh
#
# Self-test for Scripts/check_workflow_triggers.sh, run in pre
# before the gate it validates. Every workflow here is made up, written into a
# temp dir; the gate takes that dir as its first argument and an exceptions file
# as its second (an empty one for cases 1-18, so the repository's own rows do
# not interfere).
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
#  19. this repository's .github/workflows                 -> green, with its
#                                                             exceptions file
#  20. the same workflows with an EMPTY exceptions file    -> red when a
#                                                             self-hosted job
#                                                             has a pull_request
#                                                             (this repository's
#                                                             Quality)
#  21. an exception row for that file and event            -> green, and the
#                                                             output names the
#                                                             row's reason
#  22. a NEW pull-request event in the excepted file       -> red (the row
#                                                             covers one event)
#  23. the same event in ANOTHER file                      -> red (one file)
#  24. a row without a reason, or with two fields          -> red
#  25. a row that excuses nothing (no such trigger)        -> red
#  26. a missing exceptions file                           -> exit 2
# Mutation proofs (weakened copies of the gate): the PR_EVENTS pattern never
# matches (case 1 turns green), the reason not required (case 24 turns green),
# the file name not compared (case 23 turns green), and the findings swallowed
# (case 1 exits 0).
#
# The gate itself absent or not executable: this self-test is red, with the
# FAIL line below, before any case runs.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_workflow_triggers.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "workflow-trigger self-test"
NOEXC="$TMP/no-exceptions.txt"
printf '# no exceptions\n' > "$NOEXC"

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
capture "$GATE" "$TMP/scalar" "$NOEXC"
want_rc "1. rejects a self-hosted job on \`on: pull_request\`" 1
want_said "1. the finding names the file" "ci.yml"
want_said "1. the finding names the trigger" "pull_request"
want_said "1. the finding names the job" "build"

workflow target ci.yml 'on:
  pull_request_target:
    types: [opened]' "$SELF_HOSTED"
capture "$GATE" "$TMP/target" "$NOEXC"
want_rc "2. rejects a self-hosted job on pull_request_target" 1
want_said "2. the finding names pull_request_target" "pull_request_target"

workflow flowlist ci.yml 'on: [push, pull_request]' "$SELF_HOSTED"
capture "$GATE" "$TMP/flowlist" "$NOEXC"
want_rc "3. rejects the list form \`on: [push, pull_request]\`" 1

workflow flowmap ci.yml 'on: {pull_request: {branches: [main]}}' "$SELF_HOSTED"
capture "$GATE" "$TMP/flowmap" "$NOEXC"
want_rc "4. rejects the map form \`on: {pull_request: ...}\`" 1

workflow blocklist ci.yml 'on:
  - push
  - pull_request' "$SELF_HOSTED"
capture "$GATE" "$TMP/blocklist" "$NOEXC"
want_rc "5. rejects the block-list form \`- pull_request\`" 1

workflow review ci.yml 'on:
  pull_request_review:
    types: [submitted]' "$SELF_HOSTED"
capture "$GATE" "$TMP/review" "$NOEXC"
want_rc "6. rejects pull_request_review (it checks out the pull request's code too)" 1

workflow hosted ci.yml 'on: [push, pull_request]' "$HOSTED"
capture "$GATE" "$TMP/hosted" "$NOEXC"
want_rc "7. a GitHub-hosted job on pull_request is allowed" 0

workflow pushonly ci.yml 'on:
  push:
    branches: ["main"]
  workflow_dispatch:' "$SELF_HOSTED"
capture "$GATE" "$TMP/pushonly" "$NOEXC"
want_rc "8. a self-hosted job on push and workflow_dispatch only is allowed" 0

workflow comment ci.yml 'on:
  # NO pull_request and NO pull_request_target, ever.
  push:
    branches: ["main"]  # not on pull_request
  workflow_dispatch:' "$SELF_HOSTED"
capture "$GATE" "$TMP/comment" "$NOEXC"
want_rc "9. a comment naming pull_request is not a trigger" 0

workflow runsblock ci.yml 'on: pull_request' '    runs-on:
      - self-hosted
      - macOS'
capture "$GATE" "$TMP/runsblock" "$NOEXC"
want_rc "10. rejects runs-on as a block list holding self-hosted" 1

workflow customlabel ci.yml 'on: pull_request' '    runs-on: runner-acme'
capture "$GATE" "$TMP/customlabel" "$NOEXC"
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
capture "$GATE" "$TMP/matrix" "$NOEXC"
want_rc "12. rejects runs-on a matrix expression" 1

mkdir -p "$TMP/reusable"
cat > "$TMP/reusable/ci.yml" <<'YAML'
name: Sample
on: pull_request
jobs:
  call:
    uses: ./.github/workflows/build.yml
YAML
capture "$GATE" "$TMP/reusable" "$NOEXC"
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
capture "$GATE" "$TMP/twojobs" "$NOEXC"
want_rc "14. rejects a workflow whose second job is self-hosted" 1
want_said "14. the finding names the self-hosted job" "job 'deploy'"
if grep -qF "job 'lint'" <<<"$OUT"; then
  fail "14. the GitHub-hosted job is named as a finding. Output: $OUT"
else
  echo "  ok: 14. the GitHub-hosted job is not a finding"
fi

workflow yamlext ci.yaml 'on: pull_request' "$SELF_HOSTED"
capture "$GATE" "$TMP/yamlext" "$NOEXC"
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
capture "$GATE" "$TMP/noon" "$NOEXC"
want_rc "16. rejects a workflow with no on: key" 1

mkdir -p "$TMP/empty"
echo "not a workflow" > "$TMP/empty/README.md"
capture "$GATE" "$TMP/empty" "$NOEXC"
want_rc "17. rejects a dir with no workflow file" 1
want_said "17. the finding says it scanned nothing" "scan over nothing"

capture "$GATE" "$TMP/does-not-exist" "$NOEXC"
want_rc "18. exits 2 on a missing dir, never 0" 2

capture "$GATE"
want_rc "19. this repository's workflows pass with their exceptions file" 0
[[ "$RC" -eq 0 ]] || printf '%s\n' "$OUT" | sed 's/^/    /'

capture "$GATE" .github/workflows "$NOEXC"
# A repository whose jobs all run on GitHub-hosted images has no row in its
# exceptions file, and the empty file changes nothing: the case is
# red-without-the-row only for a repository whose file carries a row.
if grep -qvE '^[[:space:]]*(#|$)' Scripts/workflow_trigger_exceptions.txt; then
  want_rc "20. this repository's workflows are red without the exception row" 1
  want_said "20. the finding names quality.yml and pull_request" "quality.yml: triggers on pull_request"
else
  want_rc "20. this repository needs no exception row: its workflows are green with an empty file" 0
fi

# Exceptions: workflow|event|reason.
EXC="$TMP/exceptions.txt"
printf '# kept by ruling\nci.yml|pull_request|kept; made safe in issue 10\n' > "$EXC"
workflow excepted ci.yml 'on: pull_request' "$SELF_HOSTED"
capture "$GATE" "$TMP/excepted" "$EXC"
want_rc "21. an exception row for that file and event is green" 0
want_said "21. and the output names the row's reason" "kept; made safe in issue 10"

workflow newevent ci.yml 'on:
  pull_request:
  pull_request_target:' "$SELF_HOSTED"
capture "$GATE" "$TMP/newevent" "$EXC"
want_rc "22. a new pull-request event in the excepted file is red" 1
want_said "22. the finding names the new event" "triggers on pull_request_target"
if grep -qF "FAIL: ci.yml: triggers on pull_request and" <<<"$OUT"; then
  fail "22. the excepted event is reported too. Output: $OUT"
else
  echo "  ok: 22. the excepted event is not a finding"
fi

workflow otherfile other.yml 'on: pull_request' "$SELF_HOSTED"
capture "$GATE" "$TMP/otherfile" "$EXC"
want_rc "23. the same event in another file is red" 1
want_said "23. the finding names the other file" "other.yml: triggers on pull_request"

printf 'ci.yml|pull_request|\n' > "$TMP/noreason.txt"
capture "$GATE" "$TMP/excepted" "$TMP/noreason.txt"
want_rc "24a. a row without a reason is red" 1
want_said "24a. and says what it wanted" "wanted workflow|event|reason"
printf 'ci.yml|pull_request\n' > "$TMP/twofields.txt"
capture "$GATE" "$TMP/excepted" "$TMP/twofields.txt"
want_rc "24b. a row with two fields is red" 1

workflow stale ci.yml 'on: push' "$SELF_HOSTED"
capture "$GATE" "$TMP/stale" "$EXC"
want_rc "25. a row that excuses nothing is red" 1
want_said "25. and says it excuses no finding" "excuses no finding"

capture "$GATE" "$TMP/excepted" "$TMP/no-such-exceptions.txt"
want_rc "26. exits 2 on a missing exceptions file, never 0" 2

# Mutation proof for case 1: the same workflow against a copy of the gate
# whose PR_EVENTS pattern can never match must be green, and must say why.
# The mutant cds to its own dir's parent; give it the same layout.
MUTANT="$TMP/mutant/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUTANT" "s/^PR_EVENTS=.*/PR_EVENTS='NEVER-MATCHES-ANY-EVENT'/"; then
  capture "$MUTANT" "$TMP/scalar" "$NOEXC"
  if [[ "$RC" -eq 0 ]] && ! grep -qF "pull_request" <<<"$OUT"; then
    echo "  ok: mutation proof: without the PR_EVENTS pattern case 1 is green, so it is red because it triggers on pull_request"
  else
    fail "mutation proof: a gate whose PR_EVENTS never matches is still red on case 1, or still names pull_request (exit $RC) — case 1 is red for another reason. Output: $OUT"
  fi
fi

# Reason not required: the row without a reason is accepted, so case 24a is red
# because the reason is required.
selftest_mutant "$GATE" "$TMP/mutant-reason/Scripts/check_workflow_triggers.sh" \
  's/ || \[ -z "[$]ex_has_reason" \]//' || true
MUT="$TMP/mutant-reason/Scripts/check_workflow_triggers.sh"
capture "$MUT" "$TMP/excepted" "$TMP/noreason.txt"
if [[ "$RC" -eq 0 ]]; then
  echo "  ok: mutation proof: without the reason check a row with no reason is accepted, so case 24a is red because the reason is required"
else
  fail "mutation proof: the reason-blind gate still failed the row without a reason (exit $RC). Output: $OUT"
fi

# File name not compared: an exception for ci.yml excuses other.yml too. The
# fixture holds both files, so the row is used either way and only the name
# comparison decides case 23's verdict.
workflow bothfiles ci.yml 'on: pull_request' "$SELF_HOSTED"
workflow bothfiles other.yml 'on: pull_request' "$SELF_HOSTED"
capture "$GATE" "$TMP/bothfiles" "$EXC"
want_rc "23b. with both files present only the excepted one is excused" 1
want_said "23b. the other file is the finding" "other.yml: triggers on pull_request"
if selftest_mutant "$GATE" "$TMP/mutant-name/Scripts/check_workflow_triggers.sh" 's/[$]1 == n \&\& //'; then
  capture "$TMP/mutant-name/Scripts/check_workflow_triggers.sh" "$TMP/bothfiles" "$EXC"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: without the file name compared an exception excuses any file, so case 23b is red because the name is compared"
  else
    fail "mutation proof: the name-blind gate still failed the second file (exit $RC). Output: $OUT"
  fi
fi

# Findings swallowed: the gate prints them and exits 0.
if selftest_mutant "$GATE" "$TMP/mutant-swallow/Scripts/check_workflow_triggers.sh" 's/^if \[ "[$]findings" -ne 0 \]; then/if false; then/'; then
  capture "$TMP/mutant-swallow/Scripts/check_workflow_triggers.sh" "$TMP/scalar" "$NOEXC"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: a gate that swallows its findings exits 0 on case 1, so the exit status is what makes it red"
  else
    fail "mutation proof: the findings-swallowing gate still exits $RC on case 1. Output: $OUT"
  fi
fi

selftest_end "the workflow-trigger gate does not keep pull-request triggers off the self-hosted runner" \
  "workflow-trigger gate is red on a pull-request trigger (every on: form, pull_request_review included) in a workflow with a job not on a GitHub-hosted runner (self-hosted, a custom label, a matrix, a reusable workflow; .yml and .yaml), on no on: key, on no workflow file and on a missing dir, green on a hosted job, on push-only triggers and on a comment, this repository's workflows pass only with their exception row, an exception covers exactly one file and event and needs a reason, an unused row and a missing exceptions file are red, and the PR_EVENTS pattern, the reason, the file name and the exit status are what decide its cases"
