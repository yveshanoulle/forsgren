#!/usr/bin/env bash
# canon: test_check_zizmor v1
set -euo pipefail

cd "$(dirname "$0")/.."

# Self-test for check_zizmor.sh.
#
# A gate that has never been seen red is a hope, so this fixture shows the gate
# catching what it exists to catch.
#
# zizmor is the GitHub Actions security linter. actionlint asks "is this a
# valid workflow?"; zizmor asks "is this workflow safe?". The class that
# matters is template injection: an attacker-controlled `${{ ... }}` value
# (an issue title, a branch name) expanded straight into a run: block, where
# it is shell code, run with the job's token on the runner.
#
# The gate runs at its setting, `--min-severity high`, the default
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
#  11. a workflow_run trigger without an ignore                -> exit 14,
#      naming dangerous-triggers
#  12. the same with `# zizmor: ignore[dangerous-triggers]` on the workflow_run
#      line                                                    -> exit 0
#  13. the ignore covers ONE RULE: the same file with a template injection is
#      still red for template-injection, and an ignore naming another rule
#      leaves the trigger red
#  14. the ignore covers ONE LINE: placed on another line of the file, the
#      trigger is red; and it covers ONE FILE: beside a second workflow_run
#      workflow with no ignore, that file is red and this one is not
#  15. every `zizmor: ignore` this repository carries names ONE rule on ONE
#      line (it may carry none), and its config disables and ignores nothing
#  16. MUTATION PROOF: this repository's .github scanned with --no-ignores has
#      exactly the findings its ignores name (counted from the JSON format), so
#      the ignores are what make case 6 green and they hide only those
#
# Colour: the gate passes --color never, and the self-test is run under the CI
# environment too (GITHUB_ACTIONS, CI, FORCE_COLOR, CLICOLOR_FORCE); the
# mutation proof for that is the last case.

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

# write_chain <file> <on-line-suffix> <after-key-suffix> [inject]: a workflow_run
# workflow; the suffixes are appended to the `workflow_run:` line and to the
# `permissions:` line, and a third argument adds a template injection.
write_chain() {
  local file="$1" onsuffix="$2" permsuffix="$3" step='echo hi' dollar='$'
  if [[ -n "${4:-}" ]]; then step="echo \"${dollar}{{ github.event.workflow_run.head_commit.message }}\""; fi
  cat > "$file" <<YML
name: Chain
on:
  workflow_run:${onsuffix}
    workflows: ["Quality"]
    types: [completed]
permissions: {}${permsuffix}
jobs:
  go:
    runs-on: ubuntu-latest
    steps:
      - run: ${step}
YML
}
IGN='  # zizmor: ignore[dangerous-triggers]'

# --- Case 11: a workflow_run trigger, no ignore.
wr="$TMP/wr/.github"; mkdir -p "$wr/workflows"
write_chain "$wr/workflows/wf.yml" "" ""
capture "$CHECK" "$wr"
want_exit "a workflow_run trigger without an ignore is red, naming the audit" 14 "error[dangerous-triggers]"

# --- Case 12: the ignore on the workflow_run line.
wri="$TMP/wri/.github"; mkdir -p "$wri/workflows"
write_chain "$wri/workflows/wf.yml" "$IGN" ""
capture "$CHECK" "$wri"
want_exit "an ignore[dangerous-triggers] on the workflow_run line makes it green" 0 "No findings to report"

# --- Case 13: the ignore covers one rule.
wrj="$TMP/wrj/.github"; mkdir -p "$wrj/workflows"
write_chain "$wrj/workflows/wf.yml" "$IGN" "" inject
capture "$CHECK" "$wrj"
want_exit "the ignore does not hide a template injection in the same file" 14 "error[template-injection]"
wro="$TMP/wro/.github"; mkdir -p "$wro/workflows"
write_chain "$wro/workflows/wf.yml" "  # zizmor: ignore[template-injection]" ""
capture "$CHECK" "$wro"
want_exit "an ignore naming another rule leaves the trigger red" 14 "error[dangerous-triggers]"

# --- Case 14: the ignore covers one line and one file.
wrl="$TMP/wrl/.github"; mkdir -p "$wrl/workflows"
write_chain "$wrl/workflows/wf.yml" "" "$IGN"
capture "$CHECK" "$wrl"
want_exit "the ignore on another line of the file leaves the trigger red" 14 "error[dangerous-triggers]"
wrf="$TMP/wrf/.github"; mkdir -p "$wrf/workflows"
write_chain "$wrf/workflows/covered.yml" "$IGN" ""
write_chain "$wrf/workflows/bare.yml" "" ""
capture "$CHECK" "$wrf"
want_exit "an ignore in one workflow leaves another workflow's trigger red" 14 "workflows/bare.yml"
if grep -qF "workflows/covered.yml:" <<< "$OUT"; then
  fail "the ignored workflow is reported although its line carries the ignore. Output: ${OUT}"
else
  echo "  ok:   ... and the ignored workflow is not reported"
fi

# --- Case 15: this repository's accepted findings, as data (in the workflows;
# the config file only mentions the syntax in a comment). Every inline ignore
# is scoped to ONE rule on ONE line: `<trigger line>  # zizmor: ignore[<rule>]`.
# A repository may carry none.
ign_lines="$(grep -rnE 'zizmor:[[:space:]]*ignore' .github/workflows || true)"
bad_ign="$(grep -vE '^\.github/workflows/[^:]+:[0-9]+:.*[^[:space:]].*[[:space:]]+# zizmor: ignore\[[a-z-]+\]$' <<< "$ign_lines" | grep -v '^$' || true)"
if [[ -z "$bad_ign" ]]; then
  echo "  ok: every zizmor ignore in this repository names one rule on one line (ignores: $(grep -c . <<< "$ign_lines" || true))"
else
  fail "a zizmor ignore in this repository is not a one-rule, one-line ignore: ${bad_ign}"
fi
if grep -qE '^[[:space:]]*[^#[:space:]].*(ignore|disable)' "$CONFIG"; then
  fail "${CONFIG} disables or ignores a rule: the only accepted findings are the inline ignores"
else
  echo "  ok: ${CONFIG} disables and ignores nothing"
fi

# --- Case 16: MUTATION PROOF. This repository's .github without honouring ignores.
# The findings with ignores off must be EXACTLY the ignored ones: every ignore
# hides a finding that is there, and no finding is hidden by anything else.
# Counted from zizmor's JSON, not from its text: the text carries colour codes
# when the runner forces colour, the JSON never does.
found="$(zizmor --offline --color never --min-severity high --no-ignores --format=json .github 2>/dev/null || true)"
have="$(jq -r '.[] | .ident as $i | .locations[].symbolic.key.Local.verbatim_path | . + " " + $i' <<< "$found" 2>/dev/null | LC_ALL=C sort -u || true)"
want="$(sed -nE 's/^([^:]+):[0-9]+:.*zizmor: ignore\[([a-z-]+)\]$/\1 \2/p' <<< "$ign_lines" | LC_ALL=C sort -u || true)"
if [[ "$have" == "$want" ]]; then
  echo "  ok: mutation: with ignores off, the findings are exactly the ignored ones (${want:-none})"
else
  fail "mutation: with ignores off, the findings differ from the ignored ones. Findings: ${have:-none}. Ignored: ${want:-none}"
fi

# --- Case 17: MUTATION PROOF. The gate without --color never, run with colour forced.
# The text of the report then carries escape codes, which is what broke a text
# count on CI; the gate with the flag stays plain under the same environment.
esc="$(printf '\033')"
capture env CLICOLOR_FORCE=1 FORCE_COLOR=1 GITHUB_ACTIONS=true "$CHECK" "$inj"
if grep -qF -- "$esc" <<< "$OUT"; then
  fail "the gate prints escape codes when colour is forced: its report is not plain text on CI"
else
  echo "  ok: the gate's output is plain under the CI colour environment"
fi
colour="$TMP/colour/Scripts/check_zizmor.sh"
if selftest_mutant "$CHECK" "$colour" 's/ --color never//'; then
  capture env CLICOLOR_FORCE=1 FORCE_COLOR=1 GITHUB_ACTIONS=true "$colour" "$inj"
  if grep -qF -- "$esc" <<< "$OUT"; then
    echo "  ok: mutation: without --color never, forced colour puts escape codes in the report"
  else
    fail "mutation: without --color never the report is still plain under forced colour, so case 17 proves nothing"
  fi
fi

selftest_end "the zizmor gate does not tell a safe workflow from an unsafe one" \
  "zizmor gate is red on template injection (.yml and .yaml), on no workflow and on a missing directory, green on a clean workflow, on a Medium finding and on this repository's .github, its severity threshold is what keeps the Medium out, this repository's zizmor.yml suppresses no template injection, and its inline ignores, if any, hide exactly the findings they name, one rule on one line each"
