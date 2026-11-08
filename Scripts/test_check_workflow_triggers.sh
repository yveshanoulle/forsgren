#!/usr/bin/env bash
# canon: test_check_workflow_triggers v3
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
# v3 (forsgren#645): the job-level guard. On `pull_request` a job off
# GitHub-hosted runners is allowed when its own job-level `if:` is an accepted
# guard (the gate's header defines the grammar), so a fork's pull request never
# allocates the runner. Every red case asserts its reason, not only its exit.
#  27. a self-hosted job without a job-level if:           -> red, named
#  28. a guard only on the steps                           -> red
#  29. a guarded job and a self-hosted job that needs: it  -> red, naming the
#                                                             job that needs it
#  30. GitHub-hosted jobs without a guard beside a guarded
#      self-hosted job                                     -> green
#  31. the accepted guard forms (g1-g13: plain, ${{ }},
#      operands swapped, `N || S`, `S || N`, inside &&,
#      the precedence of && over ||, YAML quoting, a
#      comment, extra parentheses, the literal first)      -> green
#  32. the unsafe forms (r1-r23: inverted, a side of ||
#      true for a fork, && over ||, the event test alone,
#      a function, !=, a weaker or misspelled property,
#      the base repository, ${{ }} mixed with text, a block
#      scalar, two if: keys, index syntax, unbalanced
#      parentheses, another event's literal, always(), an
#      empty if:, a YAML tag, N || N, an inverted guard
#      inside &&)                                          -> red, each its
#                                                             reason
#  33. a reusable workflow (local, inspected): an unguarded
#      caller whose callee has an unguarded self-hosted
#      job (33a), a callee job behind needs: only (33b),
#      two levels deep (33c), a cycle (33d), a missing
#      callee (33e), a remote callee (33f)                 -> red, named;
#      a callee whose self-hosted jobs are guarded (33g),
#      a callee with hosted jobs only (33h), a guarded
#      caller (33i), a guarded remote caller (33j)         -> green
#  34. a matrix runs-on: unguarded red (case 12), guarded  -> green
#  35. a guard on pull_request_target or
#      pull_request_review counts for nothing              -> red
#  36. two self-hosted jobs, one guarded                   -> red, naming only
#                                                             the other
#  37. an exception row for a fully guarded workflow       -> red: it excuses
#                                                             no finding
# Mutation proofs for v3, each turning a red case green and its reason gone:
# the guard judgement always true (27, 28, 29 and the unsafe forms), the `!`
# token dropped (r1, r2), every side of a top-level || no longer required to
# be the guard or the event test (r3, r4, r16), at least one side no longer
# required to be the guard (r22), the callee no longer inspected (33a, 33b,
# 33c), a remote callee taken as clean (33f), the guard counted for every
# pull-request event (35), the base repository taken for the head (r17), and
# the event literal of another event (r16).
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

# --- v3 (forsgren#645): the job-level guard ---------------------------------

# The two atoms of the accepted guard, as the gate's header defines them.
S='github.event.pull_request.head.repo.full_name == github.repository'
N="github.event_name != 'pull_request'"

# one_job <case-dir> [job-line...]: a workflow on pull_request with one job
# `build` on the self-hosted runner; each further argument is one more line of
# the job, indented already.
one_job() {
  local dir="$TMP/$1" line
  shift
  mkdir -p "$dir"
  {
    echo "name: Sample"
    echo "on: pull_request"
    echo "jobs:"
    echo "  build:"
    echo "$SELF_HOSTED"
    for line in "$@"; do printf '%s\n' "$line"; done
    echo "    steps:"
    echo "      - run: echo hi"
  } > "$dir/ci.yml"
}

# guard_green <case> <if-value>: job `build` with that job-level if: is
# green, and the gate says it is guarded.
guard_green() {
  one_job "guard-$1" "    if: $2"
  capture "$GATE" "$TMP/guard-$1" "$NOEXC"
  want_green "31.$1 the guard \`$2\` is accepted" "guarded: ci.yml: pull_request with job 'build'"
}

# guard_red <case> <if-value> <reason>: job `build` with that job-level if:
# is red, the finding naming the job and the reason.
guard_red() {
  one_job "guard-$1" "    if: $2"
  capture "$GATE" "$TMP/guard-$1" "$NOEXC"
  want_red "32.$1 the guard \`$2\` is red, naming the job" "job 'build'"
  want_said "32.$1 and says why" "$3"
}

R_MISSING="has no job-level if: guard"
R_COMPARE="does not compare github.event.pull_request.head.repo.full_name with github.repository"
R_OR="one side of a top-level || is neither the guard nor"
R_INVERTED="the guard is inverted"
R_FORM="is not one of the accepted guard forms"
R_AND="no part joined by && is the guard"
R_READ="cannot be read as an expression"

one_job unguarded
capture "$GATE" "$TMP/unguarded" "$NOEXC"
want_red "27. a self-hosted job without a job-level if: is red, named" "job 'build'"
want_said "27. and says it has no guard" "$R_MISSING"

mkdir -p "$TMP/steponly"
cat > "$TMP/steponly/ci.yml" <<'YAML'
name: Sample
on: pull_request
jobs:
  build:
    runs-on: [self-hosted, macOS]
    steps:
      - if: github.event.pull_request.head.repo.full_name == github.repository
        run: echo hi
YAML
capture "$GATE" "$TMP/steponly" "$NOEXC"
want_red "28. a guard only on the steps is red" "job 'build'"
want_said "28. and says the job has no job-level guard" "$R_MISSING"

mkdir -p "$TMP/needs"
cat > "$TMP/needs/ci.yml" <<'YAML'
name: Sample
on: pull_request
jobs:
  check:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo check
  deploy:
    needs: check
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo deploy
YAML
capture "$GATE" "$TMP/needs" "$NOEXC"
want_red "29. a self-hosted job that needs: a guarded job is red" "job 'deploy'"
want_said "29. and says the needs: dependency is no guard" "$R_MISSING"
if grep -qF "FAIL: ci.yml: triggers on pull_request and job 'check'" <<<"$OUT"; then
  fail "29. the guarded job is named as a finding. Output: $OUT"
else
  echo "  ok: 29. the guarded job is not a finding"
fi

mkdir -p "$TMP/hostedmix"
cat > "$TMP/hostedmix/ci.yml" <<'YAML'
name: Sample
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo lint
  test:
    runs-on: macos-latest
    steps:
      - run: echo test
  deploy:
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo deploy
YAML
capture "$GATE" "$TMP/hostedmix" "$NOEXC"
want_green "30. GitHub-hosted jobs need no guard beside a guarded self-hosted job" "guarded: ci.yml: pull_request with job 'deploy'"

guard_green g1 "$S"
guard_green g2 "\${{ $S }}"
guard_green g3 "github.repository == github.event.pull_request.head.repo.full_name"
guard_green g4 "$N || $S"
guard_green g5 "$S || $N"
guard_green g6 "($N || $S) && !cancelled()"
guard_green g7 "github.ref == 'refs/heads/main' && ($N || $S)"
guard_green g8 "$N || $S && github.actor != 'someone'"
guard_green g9 "'github.event_name != ''pull_request'' || $S'"
guard_green g10 "\"$S\""
guard_green g11 "$S # same repository only"
guard_green g12 "(($S))"
guard_green g13 "\${{ 'pull_request' != github.event_name || $S }}"

guard_red r1 "\${{ !($S) }}" "$R_INVERTED"
guard_red r2 "\${{ !($N || $S) }}" "$R_INVERTED"
guard_red r3 "$S || github.actor == 'dependabot[bot]'" "$R_OR"
guard_red r4 "github.actor == 'dependabot[bot]' || $S" "$R_OR"
guard_red r5 "$S && github.ref == 'refs/heads/main' || github.event_name == 'push'" "$R_OR"
guard_red r6 "$N" "$R_COMPARE"
guard_red r7 "$N || github.actor == 'someone'" "$R_COMPARE"
guard_red r8 "contains(github.event.pull_request.head.repo.full_name, github.repository)" "$R_FORM"
guard_red r9 "github.event.pull_request.head.repo.full_name != github.repository" "$R_FORM"
guard_red r10 "github.event.pull_request.head.repo.fork == false" "$R_COMPARE"
guard_red r11 "github.event.pull_request.head.repo.fullname == github.repository" "$R_COMPARE"
guard_red r12 "\${{ $S }} && always()" "mixes \${{ }} with other text"
one_job "guard-r13" "    if: >-" "      $S"
capture "$GATE" "$TMP/guard-r13" "$NOEXC"
want_red "32.r13 a guard written as a block scalar is red, naming the job" "job 'build'"
want_said "32.r13 and says it spans several lines" "over several lines"
one_job "guard-r14" "    if: $S" "    if: always()"
capture "$GATE" "$TMP/guard-r14" "$NOEXC"
want_red "32.r14 two job-level if: keys are red, naming the job" "job 'build'"
want_said "32.r14 and says there are two" "two job-level if: keys"
guard_red r15 "github.event.pull_request.head.repo['full_name'] == github.repository" "$R_READ"
guard_red r16 "github.event_name != 'pull_request_target' || $S" "$R_OR"
guard_red r17 "github.event.pull_request.base.repo.full_name == github.repository" "$R_COMPARE"
guard_red r18 "($S" "$R_READ"
guard_red r19 "always()" "$R_COMPARE"
guard_red r20 "" "an empty job-level if:"
guard_red r21 "!($S)" "YAML reads"
guard_red r22 "$N || $N" "$R_COMPARE"
guard_red r23 "\${{ !cancelled() && !($S) }}" "$R_AND"

# reusable <case-dir>: the caller ci.yml (on pull_request), its job given by
# the remaining lines; the callees are written by the case.
reusable() {
  local dir="$TMP/$1" line
  shift
  mkdir -p "$dir"
  {
    echo "name: Sample"
    echo "on: pull_request"
    echo "jobs:"
    echo "  call:"
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$dir/ci.yml"
}
CALL_BUILD='    uses: ./.github/workflows/build.yml'
GUARD_LINE="    if: $S"

reusable reuse-open "$CALL_BUILD"
cat > "$TMP/reuse-open/build.yml" <<'YAML'
name: Build
on: workflow_call
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
capture "$GATE" "$TMP/reuse-open" "$NOEXC"
want_red "33a. an unguarded caller of a callee with an unguarded self-hosted job is red" "job 'call'"
want_said "33a. and names the callee's job" "calls ./.github/workflows/build.yml, where job 'deploy'"

reusable reuse-needs "$CALL_BUILD"
cat > "$TMP/reuse-needs/build.yml" <<'YAML'
name: Build
on: workflow_call
jobs:
  check:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo check
  deploy:
    needs: [check]
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo deploy
YAML
capture "$GATE" "$TMP/reuse-needs" "$NOEXC"
want_red "33b. a callee's self-hosted job behind needs: only is red" "calls ./.github/workflows/build.yml, where job 'deploy'"
want_said "33b. and says needs: is no guard" "$R_MISSING"

reusable reuse-deep "$CALL_BUILD"
cat > "$TMP/reuse-deep/build.yml" <<'YAML'
name: Build
on: workflow_call
jobs:
  inner:
    uses: ./.github/workflows/deploy.yml
YAML
cat > "$TMP/reuse-deep/deploy.yml" <<'YAML'
name: Deploy
on: workflow_call
jobs:
  ship:
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo ship
YAML
capture "$GATE" "$TMP/reuse-deep" "$NOEXC"
want_red "33c. an unguarded self-hosted job two reusable levels down is red" "job 'call'"
want_said "33c. and names the chain" "calls ./.github/workflows/deploy.yml, where job 'ship'"

reusable reuse-cycle "$CALL_BUILD"
cat > "$TMP/reuse-cycle/build.yml" <<'YAML'
name: Build
on: workflow_call
jobs:
  again:
    uses: ./.github/workflows/build.yml
YAML
capture "$GATE" "$TMP/reuse-cycle" "$NOEXC"
want_red "33d. a reusable workflow that calls itself is red" "job 'call'"
want_said "33d. and says it is a cycle" "in a cycle"

reusable reuse-missing "$CALL_BUILD"
capture "$GATE" "$TMP/reuse-missing" "$NOEXC"
want_red "33e. a callee that is not there is red" "job 'call'"
want_said "33e. and says it is not there" "which is not in"

reusable reuse-remote '    uses: someone/elsewhere/.github/workflows/build.yml@0123456789abcdef0123456789abcdef01234567'
capture "$GATE" "$TMP/reuse-remote" "$NOEXC"
want_red "33f. an unguarded caller of a remote reusable workflow is red" "job 'call'"
want_said "33f. and says it cannot be inspected" "outside this repository"

reusable reuse-guarded-callee "$CALL_BUILD"
cat > "$TMP/reuse-guarded-callee/build.yml" <<'YAML'
name: Build
on: workflow_call
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo lint
  deploy:
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo deploy
YAML
capture "$GATE" "$TMP/reuse-guarded-callee" "$NOEXC"
want_green "33g. a callee whose self-hosted jobs are all guarded is green" "guarded: ci.yml: pull_request with job 'call'"

reusable reuse-hosted-callee "$CALL_BUILD"
cat > "$TMP/reuse-hosted-callee/build.yml" <<'YAML'
name: Build
on: workflow_call
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo lint
YAML
capture "$GATE" "$TMP/reuse-hosted-callee" "$NOEXC"
want_green "33h. a callee with GitHub-hosted jobs only is green" "guarded: ci.yml: pull_request with job 'call'"

reusable reuse-guarded-caller "$GUARD_LINE" "$CALL_BUILD"
cp "$TMP/reuse-open/build.yml" "$TMP/reuse-guarded-caller/build.yml"
capture "$GATE" "$TMP/reuse-guarded-caller" "$NOEXC"
want_green "33i. a guarded caller is green whatever its callee runs on" "guarded: ci.yml: pull_request with job 'call'"

reusable reuse-remote-guarded "$GUARD_LINE" '    uses: someone/elsewhere/.github/workflows/build.yml@0123456789abcdef0123456789abcdef01234567'
capture "$GATE" "$TMP/reuse-remote-guarded" "$NOEXC"
want_green "33j. a guarded caller of a remote reusable workflow is green" "guarded: ci.yml: pull_request with job 'call'"

mkdir -p "$TMP/matrixguarded"
cat > "$TMP/matrixguarded/ci.yml" <<'YAML'
name: Sample
on: pull_request
jobs:
  build:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [self-hosted]
    steps:
      - run: echo hi
YAML
capture "$GATE" "$TMP/matrixguarded" "$NOEXC"
want_green "34. a guarded job whose runs-on is a matrix expression is green" "guarded: ci.yml: pull_request with job 'build'"

workflow guardtarget ci.yml 'on:
  pull_request_target:' "$SELF_HOSTED
$GUARD_LINE"
capture "$GATE" "$TMP/guardtarget" "$NOEXC"
want_red "35a. a guard on pull_request_target counts for nothing" "triggers on pull_request_target and job 'build'"
want_said "35a. and says a guard counts for pull_request only" "a job-level guard counts for pull_request only"
workflow guardreview ci.yml 'on:
  pull_request_review:' "$SELF_HOSTED
$GUARD_LINE"
capture "$GATE" "$TMP/guardreview" "$NOEXC"
want_red "35b. a guard on pull_request_review counts for nothing" "triggers on pull_request_review and job 'build'"

mkdir -p "$TMP/halfguarded"
cat > "$TMP/halfguarded/ci.yml" <<'YAML'
name: Sample
on: [push, pull_request]
jobs:
  test:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo test
  deploy:
    runs-on: [self-hosted, macOS]
    steps:
      - run: echo deploy
YAML
capture "$GATE" "$TMP/halfguarded" "$NOEXC"
want_red "36. two self-hosted jobs, one guarded, is red" "job 'deploy'"
if grep -qF "FAIL: ci.yml: triggers on pull_request and job 'test'" <<<"$OUT"; then
  fail "36. the guarded job is named as a finding. Output: $OUT"
else
  echo "  ok: 36. the guarded job is not a finding"
fi

capture "$GATE" "$TMP/guard-g1" "$EXC"
want_red "37. an exception row for a fully guarded workflow is red" "excuses no finding"

# --- v3 mutation proofs ------------------------------------------------------

# mutant_green <label> <mutant> <fixture> <reason>: the mutant is green on the
# fixture and no longer says the reason, so the real gate is red on it
# because of what the mutation removed.
mutant_green() {
  capture "$2" "$3" "$NOEXC"
  if [[ "$RC" -eq 0 ]] && ! grep -qF -- "$4" <<<"$OUT"; then
    echo "  ok: mutation proof: $1"
  else
    fail "mutation proof: $1 — the mutant is still red, or still says '$4' (exit $RC). Output: $OUT"
  fi
}

MUT="$TMP/mut-guard/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUT" 's/^      if (F(1, n)) { print "OK"; exit }/      print "OK"; exit/; s/^    none) echo "has no job-level if: guard.*/    none) return 0 ;;/'; then
  mutant_green "the guard judgement always true turns case 27 green" "$MUT" "$TMP/unguarded" "$R_MISSING"
  mutant_green "the guard judgement always true turns case 28 green" "$MUT" "$TMP/steponly" "$R_MISSING"
  mutant_green "the guard judgement always true turns case 29 green" "$MUT" "$TMP/needs" "$R_MISSING"
  for c in r1 r3 r5 r6 r8 r9 r10 r11 r17 r19 r22 r23; do
    mutant_green "the guard judgement always true turns case 32.$c green" "$MUT" "$TMP/guard-$c" "FAIL: ci.yml"
  done
fi

MUT="$TMP/mut-not/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUT" 's/^        if (c == "!") { t\[++n\] = "!"/        if (c == "!") { i = i/'; then
  mutant_green "the ! token dropped turns case 32.r1 green" "$MUT" "$TMP/guard-r1" "$R_INVERTED"
  mutant_green "the ! token dropped turns case 32.r2 green" "$MUT" "$TMP/guard-r2" "$R_INVERTED"
fi

MUT="$TMP/mut-or/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUT" 's/^          else if (!isN(s, i - 1)) return 0/          else if (0) return 0/'; then
  mutant_green "a side of || no longer required to be the guard turns case 32.r3 green" "$MUT" "$TMP/guard-r3" "$R_OR"
  mutant_green "a side of || no longer required to be the guard turns case 32.r4 green" "$MUT" "$TMP/guard-r4" "$R_OR"
  mutant_green "a side of || no longer required to be the guard turns case 32.r16 green" "$MUT" "$TMP/guard-r16" "$R_OR"
fi

MUT="$TMP/mut-anyf/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUT" 's/^      return anyF$/      return 1/'; then
  mutant_green "no side of || required to be the guard turns case 32.r22 green" "$MUT" "$TMP/guard-r22" "$R_COMPARE"
fi

MUT="$TMP/mut-callee/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUT" 's/^      callee_problems "[$]target"/      true "callee"/'; then
  mutant_green "the callee not inspected turns case 33a green" "$MUT" "$TMP/reuse-open" "where job 'deploy'"
  mutant_green "the callee not inspected turns case 33b green" "$MUT" "$TMP/reuse-needs" "where job 'deploy'"
  mutant_green "the callee not inspected turns case 33c green" "$MUT" "$TMP/reuse-deep" "where job 'ship'"
fi

MUT="$TMP/mut-remote/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUT" 's/^    \*) echo "calls [$]{u}, a reusable workflow outside/    *) true "/'; then
  mutant_green "a remote callee taken as clean turns case 33f green" "$MUT" "$TMP/reuse-remote" "outside this repository"
fi

MUT="$TMP/mut-event/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUT" 's/^      if \[ "[$]event" = "[$]GUARDED_EVENT" \]; then/      if true; then/'; then
  mutant_green "the guard counted for every pull-request event turns case 35a green" "$MUT" "$TMP/guardtarget" "counts for pull_request only"
  mutant_green "the guard counted for every pull-request event turns case 35b green" "$MUT" "$TMP/guardreview" "counts for pull_request only"
fi

MUT="$TMP/mut-head/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUT" "s/^GUARD_HEAD=.*/GUARD_HEAD='github.event.pull_request.base.repo.full_name'/"; then
  mutant_green "the base repository taken for the head turns case 32.r17 green" "$MUT" "$TMP/guard-r17" "$R_COMPARE"
fi

MUT="$TMP/mut-literal/Scripts/check_workflow_triggers.sh"
if selftest_mutant "$GATE" "$MUT" "s/^GUARD_LITERAL=.*/GUARD_LITERAL=\"'pull_request_target'\"/"; then
  mutant_green "another event's literal in the event test turns case 32.r16 green" "$MUT" "$TMP/guard-r16" "$R_OR"
fi

selftest_end "the workflow-trigger gate does not keep pull-request triggers off the self-hosted runner" \
  "workflow-trigger gate is red on a pull-request trigger (every on: form, pull_request_review included) in a workflow with a job not on a GitHub-hosted runner (self-hosted, a custom label, a matrix, a reusable workflow; .yml and .yaml), on no on: key, on no workflow file and on a missing dir, green on a hosted job, on push-only triggers and on a comment, this repository's workflows pass only with their exception row, an exception covers exactly one file and event and needs a reason, an unused row and a missing exceptions file are red, the PR_EVENTS pattern, the reason, the file name and the exit status are what decide its cases, and on pull_request a job off GitHub-hosted runners is green only behind an accepted job-level guard of its own: never a step-level one or a needs: dependency, never an inverted, weaker, misspelled, mixed or ambiguous expression, a side of || true for a fork among them, a reusable workflow inspected (local) or rejected (remote) unless the caller is guarded, and never on another pull-request event"
