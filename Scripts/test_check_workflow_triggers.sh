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

if [[ ! -x "$GATE" ]]; then
  echo "❌ FAIL: ${GATE} not found or not executable — the workflow-trigger gate this self-test validates does not exist, so nothing keeps a pull-request trigger off the self-hosted runner"
  exit 1
fi

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: workflow-trigger self-test aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

failures=0
check() { # <name> <expected-rc> <actual-rc>
  if [[ "$2" == "$3" ]]; then echo "  ✅ $1"; else echo "  ❌ $1 — expected exit $2, got $3. Output: $OUT"; failures=$((failures+1)); fi
}
says() { # <name> <fixed-string> — the last output must contain it
  if grep -qF -- "$2" <<<"$OUT"; then echo "  ✅ $1"; else echo "  ❌ $1 — output lacks: $2. Output: $OUT"; failures=$((failures+1)); fi
}
run() { set +e; OUT="$("$@" 2>&1)"; RC=$?; set -e; }

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

echo "test_check_workflow_triggers"

workflow scalar ci.yml 'on: pull_request' "$SELF_HOSTED"
run "$GATE" "$TMP/scalar"
check "1. rejects a self-hosted job on \`on: pull_request\`" 1 "$RC"
says  "1. the finding names the file" "ci.yml"
says  "1. the finding names the trigger" "pull_request"
says  "1. the finding names the job" "build"

workflow target ci.yml 'on:
  pull_request_target:
    types: [opened]' "$SELF_HOSTED"
run "$GATE" "$TMP/target"
check "2. rejects a self-hosted job on pull_request_target" 1 "$RC"
says  "2. the finding names pull_request_target" "pull_request_target"

workflow flowlist ci.yml 'on: [push, pull_request]' "$SELF_HOSTED"
run "$GATE" "$TMP/flowlist"
check "3. rejects the list form \`on: [push, pull_request]\`" 1 "$RC"

workflow flowmap ci.yml 'on: {pull_request: {branches: [main]}}' "$SELF_HOSTED"
run "$GATE" "$TMP/flowmap"
check "4. rejects the map form \`on: {pull_request: ...}\`" 1 "$RC"

workflow blocklist ci.yml 'on:
  - push
  - pull_request' "$SELF_HOSTED"
run "$GATE" "$TMP/blocklist"
check "5. rejects the block-list form \`- pull_request\`" 1 "$RC"

workflow review ci.yml 'on:
  pull_request_review:
    types: [submitted]' "$SELF_HOSTED"
run "$GATE" "$TMP/review"
check "6. rejects pull_request_review (it checks out the pull request's code too)" 1 "$RC"

workflow hosted ci.yml 'on: [push, pull_request]' "$HOSTED"
run "$GATE" "$TMP/hosted"
check "7. a GitHub-hosted job on pull_request is allowed" 0 "$RC"

workflow pushonly ci.yml 'on:
  push:
    branches: ["main"]
  workflow_dispatch:' "$SELF_HOSTED"
run "$GATE" "$TMP/pushonly"
check "8. a self-hosted job on push and workflow_dispatch only is allowed" 0 "$RC"

workflow comment ci.yml 'on:
  # NO pull_request and NO pull_request_target, ever.
  push:
    branches: ["main"]  # not on pull_request
  workflow_dispatch:' "$SELF_HOSTED"
run "$GATE" "$TMP/comment"
check "9. a comment naming pull_request is not a trigger" 0 "$RC"

workflow runsblock ci.yml 'on: pull_request' '    runs-on:
      - self-hosted
      - macOS'
run "$GATE" "$TMP/runsblock"
check "10. rejects runs-on as a block list holding self-hosted" 1 "$RC"

workflow customlabel ci.yml 'on: pull_request' '    runs-on: runner-acme'
run "$GATE" "$TMP/customlabel"
check "11. rejects runs-on a custom label without self-hosted" 1 "$RC"

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
run "$GATE" "$TMP/matrix"
check "12. rejects runs-on a matrix expression" 1 "$RC"

mkdir -p "$TMP/reusable"
cat > "$TMP/reusable/ci.yml" <<'YAML'
name: Sample
on: pull_request
jobs:
  call:
    uses: ./.github/workflows/build.yml
YAML
run "$GATE" "$TMP/reusable"
check "13. rejects a reusable-workflow job on pull_request" 1 "$RC"

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
run "$GATE" "$TMP/twojobs"
check "14. rejects a workflow whose second job is self-hosted" 1 "$RC"
says  "14. the finding names the self-hosted job" "job 'deploy'"
if grep -qF "job 'lint'" <<<"$OUT"; then
  echo "  ❌ 14. the GitHub-hosted job is named as a finding. Output: $OUT"; failures=$((failures+1))
else
  echo "  ✅ 14. the GitHub-hosted job is not a finding"
fi

workflow yamlext ci.yaml 'on: pull_request' "$SELF_HOSTED"
run "$GATE" "$TMP/yamlext"
check "15. scans a .yaml file like a .yml" 1 "$RC"
says  "15. the finding names ci.yaml" "ci.yaml"

mkdir -p "$TMP/noon"
cat > "$TMP/noon/ci.yml" <<'YAML'
name: Sample
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
YAML
run "$GATE" "$TMP/noon"
check "16. rejects a workflow with no on: key" 1 "$RC"

mkdir -p "$TMP/empty"
echo "not a workflow" > "$TMP/empty/README.md"
run "$GATE" "$TMP/empty"
check "17. rejects a dir with no workflow file" 1 "$RC"
says  "17. the finding says it scanned nothing" "scan over nothing"

run "$GATE" "$TMP/does-not-exist"
check "18. exits 2 on a missing dir, never 0" 2 "$RC"

run "$GATE"
check "19. this repository's workflows keep pull-request triggers off the self-hosted runner" 0 "$RC"
[[ "$RC" -eq 0 ]] || printf '%s\n' "$OUT" | sed 's/^/    /'

# Mutation proof for case 1: the same workflow against a copy of the gate
# whose PR_EVENTS pattern can never match must be green, and must say why.
MUTANT="$TMP/check_workflow_triggers.mutant.sh"
sed "s/^PR_EVENTS=.*/PR_EVENTS='NEVER-MATCHES-ANY-EVENT'/" "$GATE" > "$MUTANT"
chmod +x "$MUTANT"
if cmp -s "$GATE" "$MUTANT"; then
  echo "  ❌ mutation proof: replacing the '^PR_EVENTS=' row changed nothing in ${GATE} — the anchor no longer matches, so this proof proves nothing"
  failures=$((failures+1))
else
  # The mutant cds to its own dir's parent; give it the same layout.
  mkdir -p "$TMP/mutant/Scripts"
  mv "$MUTANT" "$TMP/mutant/Scripts/check_workflow_triggers.sh"
  run "$TMP/mutant/Scripts/check_workflow_triggers.sh" "$TMP/scalar"
  if [[ "$RC" -eq 0 ]] && ! grep -qF "pull_request" <<<"$OUT"; then
    echo "  ✅ mutation proof: without the PR_EVENTS pattern case 1 is green, so it is red because it triggers on pull_request"
  else
    echo "  ❌ mutation proof: a gate whose PR_EVENTS never matches is still red on case 1, or still names pull_request (exit $RC) — case 1 is red for another reason. Output: $OUT"
    failures=$((failures+1))
  fi
fi

COMPLETED=1
if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "❌ FAIL: check_workflow_triggers contract (${failures} failed)"
  exit 1
fi
echo ""
echo "✅ test_check_workflow_triggers"
