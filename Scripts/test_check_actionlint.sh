#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Fixture for check_actionlint.sh.
#
# The case that matters is the FIRST one: the exact bug that motivated this
# gate. On 2026-08-22 konenki-website put `${{ runner.temp }}` in a job-level
# `env:` block — the `runner` context does not exist when job env is
# evaluated, GitHub rejected the whole file, and NOT ONE GATE RAN. sfl was
# green, the file was valid YAML, and nothing local said a word.
#
# A gate written to catch that must be shown catching it, or it is a hope.
#
# PORTED (forsgren#1, ladder step 18). Cases 1 to 5 are the estate's fixture,
# byte-identical in konenki-website, coachretreat-website and
# agilelean-website. Cases 6 to 11 are forsgren's own, and each asserts the
# REASON, not only the exit code:
#   6. a custom runner label .actionlint.yaml does not declare
#      (runner-forsgren, the label of the self-hosted runner
#      Quality ran on before forsgren#1's runner swap)          -> exit 1, the
#      label named as unknown
#   7. forsgren's own runs-on, as quality.yml writes it
#      (macos-latest, GitHub-hosted, known to actionlint)       -> exit 0
#   8. a workflow that is not valid YAML                       -> exit 1, as a
#      parse error
#   9. a shellcheck finding in a run: block                    -> exit 1, as
#      a shellcheck finding. actionlint runs shellcheck over run: blocks only
#      when shellcheck is on PATH, and SILENTLY skips it otherwise; this
#      case turns that silence into a red.
#  10. a directory with no workflow file                       -> exit 3, with
#      the reason
#  11. MUTATION PROOF: run from a copy of the repository root whose
#      .actionlint.yaml declares runner-forsgren, the gate accepts case 6:
#      it reads the repository's .actionlint.yaml, so the empty label list
#      there is what keeps every custom label red, and a label becomes
#      known only by a declaration in that file, never by a lenient rule.

CHECK="./Scripts/check_actionlint.sh"
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

# --- Case 1: the konenki bug. Job-level env referencing the runner context.
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
run ".github/workflows"
check "accepts this repo's workflows" 0 "$RC"

# --- Case 5: an empty dir is a broken invocation, never a clean pass.
empty="$TMP/empty"; mkdir -p "$empty"
run "$empty"
check "exits 3 on a dir with no workflows, never 0" 3 "$RC"

run "$TMP/nope"
check "exits 3 on a missing dir, never 0" 3 "$RC"

# --- forsgren's cases (6 to 11): exit code AND reason. --------------------
# run_out <gate> <dir> — sets RC and OUT (stdout and stderr together).
run_out() { set +e; OUT="$("$1" "$2" 2>&1)"; RC=$?; set -e; }
check_reason() { # <name> <expected-rc> <fixed-string reason>
  if [[ "$RC" == "$2" ]] && grep -qF -- "$3" <<<"$OUT"; then
    echo "  ✅ $1"
  else
    echo "  ❌ $1 — expected exit $2 with: $3; got exit $RC"
    echo "      ${OUT//$'\n'/$'\n'      }"
    failures=$((failures+1))
  fi
}

# --- Case 6: a custom label nobody declares: the retired self-hosted
# runner's own label. .actionlint.yaml declares no custom label since the
# runner swap (forsgren#1), so a job sent back to that runner is red.
undeclared="$TMP/undeclared"; mkdir -p "$undeclared"
cat > "$undeclared/wf.yml" <<'YML'
name: Undeclared label
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: [self-hosted, macOS, ARM64, runner-forsgren]
    steps:
      - run: echo hi
YML
run_out "$CHECK" "$undeclared"
check_reason "rejects a custom runner label .actionlint.yaml does not declare, naming it" 1 'label "runner-forsgren" is unknown'

# --- Case 7: forsgren's own runs-on, as quality.yml writes it.
declared="$TMP/declared"; mkdir -p "$declared"
cat > "$declared/wf.yml" <<'YML'
name: Hosted label
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: macos-latest
    steps:
      - run: echo hi
YML
run_out "$CHECK" "$declared"
check_reason "accepts macos-latest, the GitHub-hosted label quality.yml runs on" 0 "OK: actionlint (1 workflow(s) validated)"

# --- Case 8: not YAML at all (an unclosed flow sequence).
syntax="$TMP/syntax"; mkdir -p "$syntax"
cat > "$syntax/wf.yml" <<'YML'
name: Broken YAML
on:
  push:
    branches: ["main"
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
YML
run_out "$CHECK" "$syntax"
check_reason "rejects a workflow that is not valid YAML, as a parse error" 1 "could not parse as YAML"

# --- Case 9: a shellcheck finding inside a run: block (SC2086, unquoted).
shell="$TMP/shell"; mkdir -p "$shell"
cat > "$shell/wf.yml" <<'YML'
name: Unquoted expansion
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - shell: bash
        run: |
          target="a b"
          ls $target
YML
run_out "$CHECK" "$shell"
check_reason "rejects a shellcheck finding in a run: block (shellcheck is on PATH)" 1 "shellcheck reported issue in this script: SC2086"

# --- Case 10: no workflow file, with the reason.
none="$TMP/none"; mkdir -p "$none"
run_out "$CHECK" "$none"
check_reason "a dir with no workflow file is red, with the reason" 3 "actionlint: no workflows found under"

# --- Case 11: MUTATION PROOF. The same gate, run from a copy of the
# repository root whose .actionlint.yaml declares runner-forsgren, must
# accept case 6's workflow: the gate reads the repository's .actionlint.yaml,
# so case 6 is red BECAUSE that file declares no custom label.
mutant_root="$TMP/mutant"; mkdir -p "$mutant_root/Scripts"
if [[ -f "$CHECK" && -f .actionlint.yaml ]]; then
  cp "$CHECK" "$mutant_root/Scripts/check_actionlint.sh"
  chmod +x "$mutant_root/Scripts/check_actionlint.sh"
  printf 'self-hosted-runner:\n  labels:\n    - runner-forsgren\n' > "$mutant_root/.actionlint.yaml"
  if cmp -s .actionlint.yaml "$mutant_root/.actionlint.yaml"; then
    OUT="the mutation changed nothing: .actionlint.yaml already declares runner-forsgren"; RC=1
  else
    run_out "$mutant_root/Scripts/check_actionlint.sh" "$undeclared"
  fi
else
  OUT="no gate or no .actionlint.yaml to mutate"; RC=127
fi
check_reason "mutation: a .actionlint.yaml declaring runner-forsgren makes case 6 green" 0 "OK: actionlint (1 workflow(s) validated)"

COMPLETED=1

if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_actionlint contract"
  exit 1
fi
echo ""
echo "✅ test_check_actionlint"
