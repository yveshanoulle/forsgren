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

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "zizmor self-test"

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

# --- Case 1: template injection, .yml.
inj="$TMP/inj/.github"; mkdir -p "$inj/workflows"
write_injection "$inj/workflows/wf.yml"
capture "$CHECK" "$inj"
want_exit "rejects template injection in a run: block (.yml), naming the audit" 14 "error[template-injection]"

# --- Case 2: the same in a .yaml file.
injy="$TMP/injy/.github"; mkdir -p "$injy/workflows"
write_injection "$injy/workflows/wf.yaml"
capture "$CHECK" "$injy"
want_exit "rejects template injection in a .yaml workflow, naming the audit" 14 "error[template-injection]"
want_exit "  ... and names the .yaml file" 14 "workflows/wf.yaml"

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
capture "$CHECK" "$clean"
want_exit "accepts the value passed through env:" 0 "No findings to report"

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
capture "$CHECK" "$medium"
want_exit "a Medium finding (artipacked) is not red at --min-severity high" 0 "No findings to report"

# --- Case 5: MUTATION PROOF. The gate without its severity threshold.
mutant="$TMP/mutant/Scripts/check_zizmor.sh"
if [[ ! -f "$CHECK" ]]; then
  fail "mutation: no gate to mutate: ${CHECK}"
elif selftest_mutant "$CHECK" "$mutant" 's/ --min-severity high//'; then
  capture "$mutant" "$medium"
  want_exit "mutation: without --min-severity high, case 4 is red, naming artipacked" 13 "warning[artipacked]"
fi

# --- Case 6: this repository's own workflows.
capture "$CHECK" ".github"
want_exit "accepts this repo's .github" 0 "No findings to report"

# --- Case 7: no workflow file.
empty="$TMP/empty/.github"; mkdir -p "$empty"
capture "$CHECK" "$empty"
want_exit "a .github with no workflow file is red, with the reason" 3 "no inputs collected"

# --- Case 8: a directory that does not exist.
capture "$CHECK" "$TMP/nope"
want_exit "a missing directory is red, as an invalid input" 1 "invalid input"

# --- Case 9: this repository's config suppresses no template injection.
cfg="$TMP/cfg/.github"; mkdir -p "$cfg/workflows"
write_injection "$cfg/workflows/wf.yml"
if [[ -f "$CONFIG" ]]; then
  cp "$CONFIG" "$cfg/zizmor.yml"
  capture "$CHECK" "$cfg"
  want_exit "this repo's zizmor.yml lets template injection through as red" 14 "error[template-injection]"
else
  fail "this repo's zizmor.yml lets template injection through as red: no config ${CONFIG}"
fi

# --- Case 10: MUTATION PROOF. A config that disables the audit, same place.
printf 'rules:\n  template-injection:\n    disable: true\n' > "$cfg/zizmor.yml"
capture "$CHECK" "$cfg"
want_exit "mutation: a zizmor.yml disabling template-injection turns case 9 green" 0 "No findings to report"

selftest_end "the zizmor gate does not tell a safe workflow from an unsafe one" \
  "zizmor gate is red on template injection (.yml and .yaml), on no workflow and on a missing directory, green on a clean workflow, on a Medium finding and on this repository's .github, its severity threshold is what keeps the Medium out, and this repository's zizmor.yml suppresses no template injection"
