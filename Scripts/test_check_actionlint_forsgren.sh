#!/usr/bin/env bash
# Scripts/test_check_actionlint_forsgren.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# forsgren's own cases for Scripts/check_actionlint.sh. The gate and its
# self-test (Scripts/test_check_actionlint.sh) are the estate canon; these
# cases are what forsgren adds, and each asserts the REASON, not only the exit
# code:
#   1. a custom runner label .actionlint.yaml does not declare
#      (runner-forsgren, the label of the self-hosted runner
#      Quality ran on before forsgren#1's runner swap)          -> exit 1, the
#      label named as unknown
#   2. forsgren's own runs-on, as quality.yml writes it
#      (macos-latest, GitHub-hosted, known to actionlint)       -> exit 0
#   3. a workflow that is not valid YAML                       -> exit 1, as a
#      parse error
#   4. a shellcheck finding in a run: block                    -> exit 1, as
#      a shellcheck finding. actionlint runs shellcheck over run: blocks only
#      when shellcheck is on PATH, and SILENTLY skips it otherwise; this
#      case turns that silence into a red.
#   5. a directory with no workflow file                       -> exit 3, with
#      the reason
#   6. MUTATION PROOF: run from a copy of the repository root whose
#      .actionlint.yaml declares runner-forsgren, the gate accepts case 1:
#      it reads the repository's .actionlint.yaml, so the empty label list
#      there is what keeps every custom label red, and a label becomes
#      known only by a declaration in that file, never by a lenient rule.

CHECK="./Scripts/check_actionlint.sh"
TMP="$(mktemp -d)"

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: actionlint forsgren-cases fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap 'rm -rf "$TMP"; finish' EXIT

failures=0

echo "test_check_actionlint_forsgren"

# --- forsgren's cases : exit code AND reason. --------------------
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

# --- Case 1: a custom label nobody declares: the retired self-hosted
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

# --- Case 2: forsgren's own runs-on, as quality.yml writes it.
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

# --- Case 3: not YAML at all (an unclosed flow sequence).
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

# --- Case 4: a shellcheck finding inside a run: block (SC2086, unquoted).
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

# --- Case 5: no workflow file, with the reason.
none="$TMP/none"; mkdir -p "$none"
run_out "$CHECK" "$none"
check_reason "a dir with no workflow file is red, with the reason" 3 "actionlint: no workflows found under"

# --- Case 6: MUTATION PROOF. The same gate, run from a copy of the
# repository root whose .actionlint.yaml declares runner-forsgren, must
# accept case 1's workflow: the gate reads the repository's .actionlint.yaml,
# so case 1 is red BECAUSE that file declares no custom label.
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
check_reason "mutation: a .actionlint.yaml declaring runner-forsgren makes case 1 green" 0 "OK: actionlint (1 workflow(s) validated)"

COMPLETED=1

if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_actionlint forsgren cases"
  exit 1
fi
echo ""
echo "✅ test_check_actionlint_forsgren"
