#!/usr/bin/env bash
# canon: test_check_actionlint v2
set -euo pipefail

cd "$(dirname "$0")/.."

# Fixture for check_actionlint.sh.
#
# The case that matters is the FIRST one: the exact bug that motivated this
# gate. On 2026-08-22 a site repository put `${{ runner.temp }}` in a job-level
# `env:` block — the `runner` context does not exist when job env is
# evaluated, GitHub rejected the whole file, and NOT ONE GATE RAN. sfl was
# green, the file was valid YAML, and nothing local said a word.
#
# A gate written to catch that must be shown catching it, or it is a hope.
#
# MUTATION PROOF, at the end: the same cases run against weakened copies of the
# gate (the lint never runs, a missing tool or directory or an empty directory
# exits 0), and each copy must be red. A fixture that passes a gate which cannot
# fail is decoration. The gate under test is the optional first argument;
# without one it is the real gate and the mutation proof runs.

CHECK="${1:-./Scripts/check_actionlint.sh}"
SELF="${PWD}/Scripts/test_check_actionlint.sh"
TMP="$(mktemp -d)"

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: actionlint fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap 'rm -rf "$TMP"; finish' EXIT

failures=0
check() { # <name> <expected-rc> <actual-rc>
  if [[ "$2" == "$3" ]]; then echo "  ✅ $1"; else echo "  ❌ $1 — expected exit $2, got $3"; failures=$((failures+1)); fi
}
run() { set +e; "$CHECK" "$1" >/dev/null 2>&1; RC=$?; set -e; }

echo "test_check_actionlint"

# --- Case 1: a job-level env referencing the runner context (a site repo shipped it on 2026-08-22).
bad="$TMP/bad"; mkdir -p "$bad"
cat > "$bad/wf.yml" <<'YML'
name: Runner context in job env
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      ROWS: ${{ runner.temp }}/rows.md
    steps:
      - run: echo hi
YML
run "$bad"
check "rejects runner.temp in a job-level env block (the 2026-08-22 bug)" 1 "$RC"

# --- Case 2: the same value obtained the correct way must be accepted.
good="$TMP/good"; mkdir -p "$good"
cat > "$good/wf.yml" <<'YML'
name: Runner temp via the environment variable
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - shell: bash
        run: |
          rows="${RUNNER_TEMP}/rows.md"
          : > "$rows"
YML
run "$good"
check "accepts RUNNER_TEMP used inside a step" 0 "$RC"

# --- Case 3: an unknown key is a workflow error even though the YAML is fine.
typo="$TMP/typo"; mkdir -p "$typo"
cat > "$typo/wf.yml" <<'YML'
name: Typo
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - runs: echo hi
YML
run "$typo"
check "rejects an unknown step key (valid YAML, invalid workflow)" 1 "$RC"

# --- Case 4: this repo's own workflows must pass.
run "${PWD}/.github/workflows"
check "accepts this repo's workflows" 0 "$RC"

# --- Case 5: an empty dir is a broken invocation, never a clean pass.
empty="$TMP/empty"; mkdir -p "$empty"
run "$empty"
check "exits 3 on a dir with no workflows, never 0" 3 "$RC"

run "$TMP/nope"
check "exits 3 on a missing dir, never 0" 3 "$RC"

# --- Case 6: a missing actionlint is a machine fault, never a skip. PATH holds
# only the tools the gate itself needs, so actionlint cannot be found.
nopath="$TMP/nopath-bin"; mkdir -p "$nopath"
for tool in env bash dirname find wc tr; do ln -s "$(command -v "$tool")" "$nopath/$tool"; done
set +e; PATH="$nopath" "$CHECK" "$good" >/dev/null 2>&1; RC=$?; set -e
check "exits 3 when actionlint is not on PATH, never 0" 3 "$RC"

# --- Case 7: a file list after the directory: only the listed workflows are judged.
mixed="$TMP/mixed"; mkdir -p "$mixed"
cp "$good/wf.yml" "$mixed/ok.yml"
cp "$bad/wf.yml" "$mixed/broken.yml"
set +e; "$CHECK" "$mixed" "$mixed/ok.yml" >/dev/null 2>&1; RC=$?; set -e
check "a file list judges only the listed workflow, not the broken one beside it" 0 "$RC"
set +e; LISTOUT="$("$CHECK" "$mixed" "$mixed/broken.yml" 2>&1)"; RC=$?; set -e
check "a file list with the broken workflow is red" 1 "$RC"
if [[ "$LISTOUT" == *"broken.yml"* ]]; then echo "  ✅ ... and names it"; else echo "  ❌ the finding does not name broken.yml"; failures=$((failures+1)); fi

# --- Case 8: a listed path that is no file is red, named, exit 3.
set +e; LISTOUT="$("$CHECK" "$mixed" "$mixed/ok.yml" "$mixed/missing.yml" 2>&1)"; RC=$?; set -e
check "a file list naming a missing file exits 3" 3 "$RC"
if [[ "$LISTOUT" == *"missing.yml"* ]]; then echo "  ✅ ... and names it"; else echo "  ❌ the error does not name missing.yml"; failures=$((failures+1)); fi

# --- Mutation proof: weakened copies of the gate must be red here.
# Only for the real gate; the copies are judged by this same file, run on them.
if [[ $# -eq 0 ]]; then
  mutant_must_fail() { # <label> <sed-expression>
    local dir="$TMP/mutant-$RANDOM" m
    mkdir -p "$dir/Scripts"
    cp .actionlint.yaml "$dir/.actionlint.yaml"
    m="$dir/Scripts/check_actionlint.sh"
    sed "$2" "$CHECK" > "$m"
    chmod +x "$m"
    if cmp -s "$CHECK" "$m"; then
      echo "  ❌ mutation '$1' changed nothing — it proves nothing"; failures=$((failures+1)); return
    fi
    if "$SELF" "$m" >/dev/null 2>&1; then
      echo "  ❌ mutation '$1' PASSED this fixture — the cases do not guard it"; failures=$((failures+1))
    else
      echo "  ✅ mutation '$1' is red"
    fi
  }
  mutant_must_fail "the lint never runs" 's/^actionlint -config-file /true -config-file /'
  mutant_must_fail "a missing actionlint exits 0" '/command -v actionlint/,/^fi$/ s/exit 3/exit 0/'
  mutant_must_fail "a missing workflow dir exits 0" '/! -d "[$]WF_DIR"/,/^fi$/ s/exit 3/exit 0/'
  mutant_must_fail "a dir with no workflows exits 0" '/"[$]count" -eq 0/,/^fi$/ s/exit 3/exit 0/'
  mutant_must_fail "the file list is ignored" 's/^if \[ "[$]#" -gt 0 \]; then$/if false; then/'
fi

COMPLETED=1

if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_actionlint contract"
  exit 1
fi
echo ""
echo "✅ test_check_actionlint"
