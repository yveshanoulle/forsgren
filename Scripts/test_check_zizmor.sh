#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Fixture for check_zizmor.sh.
#
# NEW (forsgren#1, ladder step 19). No repo of the estate has a self-test for
# its zizmor gate: web-infra, MenoPower and agileRetroflection run zizmor in
# sfl and CI with no fixture, so nothing there shows the gate catching what it
# exists to catch. A gate that has never been seen red is a hope.
#
# zizmor is the GitHub Actions security linter. actionlint asks "is this a
# valid workflow?"; zizmor asks "is this workflow safe?". The class that
# matters is template injection: an attacker-controlled `${{ ... }}` value
# (an issue title, a branch name) expanded straight into a run: block, where
# it is shell code, run with the job's token on forsgren's self-hosted
# runner.
#
# The gate runs at the estate's setting, `--min-severity high`, the default
# persona: High findings are red, Medium and below are not reported. So a
# checkout WITHOUT persist-credentials: false (zizmor's artipacked audit,
# Medium) is NOT this gate's red: Scripts/test_workflow_checkout_pins.sh owns
# that rule. Case 4 pins that boundary and case 5 proves the threshold is
# what draws it.
#
# zizmor reads .yml AND .yaml workflow files (the gate hands it a directory,
# not a glob), so case 2 puts the injection in a .yaml file.
#
# Each case asserts the exit code AND the reason:
#   1. template injection in a run: block, .yml           -> exit 14 (zizmor's
#      code for a High finding), naming template-injection
#   2. the same in a .yaml file                           -> exit 14, naming
#      template-injection and the .yaml file
#   3. a clean workflow: the same value passed through env:, checkout pinned
#      with persist-credentials: false                    -> exit 0
#   4. a Medium finding only (checkout without persist-credentials: false)
#                                                         -> exit 0 at high
#   5. MUTATION PROOF: the gate without `--min-severity high` rejects case 4,
#      naming artipacked: the threshold is what keeps a Medium out
#   6. this repository's own .github                      -> exit 0
#   7. a .github with no workflow file                    -> exit 3, "no
#      inputs collected": a scan over nothing is never a pass
#   8. a directory that does not exist                    -> exit 1, as an
#      invalid input
#   9. this repository's .github/zizmor.yml placed beside case 1's workflow
#      still lets the injection through as red: the config suppresses no
#      template-injection (a suppression needs Yves's approved issue)
#  10. MUTATION PROOF: a zizmor.yml that disables template-injection, in the
#      same place, turns case 9 green: zizmor reads the config from the
#      scanned directory, so case 9 is not vacuous

CHECK="./Scripts/check_zizmor.sh"
CONFIG=".github/zizmor.yml"
TMP="$(mktemp -d)"

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: zizmor fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap 'rm -rf "$TMP"; finish' EXIT

failures=0
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

# write_injection <file> — an issue title expanded into a run: block.
write_injection() {
  cat > "$1" <<'YML'
name: Template injection
on:
  issues:
    types: [opened]
permissions: {}
jobs:
  greet:
    runs-on: ubuntu-latest
    steps:
      - run: echo "${{ github.event.issue.title }}"
YML
}

echo "test_check_zizmor"

# --- Case 1: template injection, .yml.
inj="$TMP/inj/.github"; mkdir -p "$inj/workflows"
write_injection "$inj/workflows/wf.yml"
run_out "$CHECK" "$inj"
check_reason "rejects template injection in a run: block (.yml), naming the audit" 14 "error[template-injection]"

# --- Case 2: the same in a .yaml file.
injy="$TMP/injy/.github"; mkdir -p "$injy/workflows"
write_injection "$injy/workflows/wf.yaml"
run_out "$CHECK" "$injy"
check_reason "rejects template injection in a .yaml workflow, naming the audit" 14 "error[template-injection]"
check_reason "  ... and names the .yaml file" 14 "workflows/wf.yaml"

# --- Case 3: clean. The same title, read from the environment.
clean="$TMP/clean/.github"; mkdir -p "$clean/workflows"
cat > "$clean/workflows/wf.yml" <<'YML'
name: Clean
on:
  issues:
    types: [opened]
permissions: {}
jobs:
  greet:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          persist-credentials: false
      - env:
          TITLE: ${{ github.event.issue.title }}
        run: echo "$TITLE"
YML
run_out "$CHECK" "$clean"
check_reason "accepts the value passed through env:" 0 "No findings to report"

# --- Case 4: a Medium finding only.
medium="$TMP/medium/.github"; mkdir -p "$medium/workflows"
cat > "$medium/workflows/wf.yml" <<'YML'
name: Checkout keeps its credentials
on:
  push:
    branches: ["main"]
permissions: {}
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      - run: echo hi
YML
run_out "$CHECK" "$medium"
check_reason "a Medium finding (artipacked) is not red at --min-severity high" 0 "No findings to report"

# --- Case 5: MUTATION PROOF. The gate without its severity threshold.
mutant="$TMP/mutant/Scripts"; mkdir -p "$mutant"
if [[ -f "$CHECK" ]]; then
  sed 's/ --min-severity high//' "$CHECK" > "$mutant/check_zizmor.sh"
  chmod +x "$mutant/check_zizmor.sh"
  if cmp -s "$CHECK" "$mutant/check_zizmor.sh"; then
    OUT="the mutation changed nothing: no ' --min-severity high' in ${CHECK}"; RC=0
  else
    run_out "$mutant/check_zizmor.sh" "$medium"
  fi
else
  OUT="no gate to mutate: ${CHECK}"; RC=127
fi
check_reason "mutation: without --min-severity high, case 4 is red, naming artipacked" 13 "warning[artipacked]"

# --- Case 6: this repository's own workflows.
run_out "$CHECK" ".github"
check_reason "accepts this repo's .github" 0 "No findings to report"

# --- Case 7: no workflow file.
empty="$TMP/empty/.github"; mkdir -p "$empty"
run_out "$CHECK" "$empty"
check_reason "a .github with no workflow file is red, with the reason" 3 "no inputs collected"

# --- Case 8: a directory that does not exist.
run_out "$CHECK" "$TMP/nope"
check_reason "a missing directory is red, as an invalid input" 1 "invalid input"

# --- Case 9: this repository's config suppresses no template injection.
cfg="$TMP/cfg/.github"; mkdir -p "$cfg/workflows"
write_injection "$cfg/workflows/wf.yml"
if [[ -f "$CONFIG" ]]; then
  cp "$CONFIG" "$cfg/zizmor.yml"
  run_out "$CHECK" "$cfg"
else
  OUT="no config: ${CONFIG}"; RC=127
fi
check_reason "this repo's zizmor.yml lets template injection through as red" 14 "error[template-injection]"

# --- Case 10: MUTATION PROOF. A config that disables the audit, same place.
printf 'rules:\n  template-injection:\n    disable: true\n' > "$cfg/zizmor.yml"
run_out "$CHECK" "$cfg"
check_reason "mutation: a zizmor.yml disabling template-injection turns case 9 green" 0 "No findings to report"

COMPLETED=1

if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_zizmor contract"
  exit 1
fi
echo ""
echo "✅ test_check_zizmor"
