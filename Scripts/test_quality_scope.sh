#!/usr/bin/env bash
# Scripts/test_quality_scope.sh
#
# Pins the scope of .github/workflows/quality.yml (forsgren#230, step 2): the
# Release workflow dispatches Quality on its bump commit with scope=bump, and
# that run is the short Quality: the bump diff check FIRST, then only the gates
# of Scripts/quality_bump_gates.txt and the site build. forsgren's own. The
# pins, on the real file, each proved by a mutant that breaks it and must be named:
#   1. workflow_dispatch has the inputs scope (a choice of full and bump,
#      default full), green_parent, old_version and new_version, and the
#      triggers push and pull_request exist: a push and a pull request never
#      set a scope, so they run the full Quality
#   2. the step "Bump diff check" runs only for scope bump, runs
#      Scripts/release_bump_diff.sh on the run's sha with the three inputs
#      (through env, never a ${{ }} in run:), and comes before every gate step
#   3. the step "Short PRE gates" runs only for scope bump, runs
#      Scripts/run_short_quality.sh, and comes after the diff check
#   4. the step "PRE gates" is skipped for scope bump and runs
#      Scripts/run_ci_phase.sh pre otherwise
#   5. the build does not run after a red diff check, and POST is skipped for
#      scope bump
#   6. the summary step is told the short Quality (QS_SHORT_QUALITY) and the
#      diff outcome, and the short Quality is named on the run page
#   7. the list of the short gates, Scripts/quality_bump_gates.txt, holds exactly
#      the secret scan, the Go tests, the golden pages and the Go lint, and
#      each is a PRE row of the order file

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
selftest_begin "quality scope pin"

WORKFLOW=".github/workflows/quality.yml"
LIST="Scripts/quality_bump_gates.txt"
ORDER="Scripts/gate_report_order.txt"
[[ -f "$WORKFLOW" ]] || selftest_abort "${WORKFLOW} does not exist"
[[ -f "$LIST" ]] || selftest_abort "${LIST} does not exist: the short gates are not named"
DOLLAR='$'

code() { grep -vE '^[[:space:]]*#' "$1"; }

# step_has <file> <step> <exact line>
step_has() {
  step_text "$1" "$2" | grep -qxF -- "$3" || echo "step '$2': want the line: $3"
}

input_findings() {
  local opts
  opts="$(code "$1" | awk '/^  workflow_dispatch:/ { d=1 } d && /^    inputs:/ { i=1 } i { print }')"
  grep -qxF '      scope:' <<< "$opts" || echo "input: workflow_dispatch has no input scope"
  awk '/^      scope:/ { s=1 } s && /options:/ { print; exit }' <<< "$opts" | grep -qxF '        options: [full, bump]' \
    || echo "input: scope is not a choice of full and bump"
  awk '/^      scope:/ { s=1 } s && /default:/ { print; exit }' <<< "$opts" | grep -qxF '        default: full' \
    || echo "input: the default scope is not full"
  local name
  for name in green_parent old_version new_version; do
    grep -qxF "      ${name}:" <<< "$opts" || echo "input: workflow_dispatch has no input ${name}"
  done
  local events
  events="$(on_events "$1" | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$events" == "pull_request push workflow_dispatch " ]] || echo "triggers: want push, pull_request and workflow_dispatch, got: ${events:-none}"
  if code "$1" | grep -E 'scope' | grep -vE "inputs\.scope|scope:|scope bump" | grep -q .; then
    echo "scope: something other than the dispatch input sets a scope"
  fi
}

step_findings() {
  local diff short pre
  diff="$(line_of "$1" "- name: Bump diff check")"
  short="$(line_of "$1" "- name: Short PRE gates")"
  pre="$(line_of "$1" "- name: PRE gates")"
  [[ -n "$diff" ]] || echo "steps: there is no step named 'Bump diff check'"
  [[ -n "$short" ]] || echo "steps: there is no step named 'Short PRE gates'"
  [[ -n "$pre" ]] || echo "steps: there is no step named 'PRE gates'"
  if [[ -n "$diff" && -n "$short" && -n "$pre" ]]; then
    later "$short" "$diff" || echo "order: 'Short PRE gates' does not come after 'Bump diff check'"
    later "$pre" "$diff" || echo "order: the bump diff check does not run FIRST: 'PRE gates' comes before 'Bump diff check'"
  fi
  step_has "$1" "Bump diff check" "        if: ${DOLLAR}{{ inputs.scope == 'bump' }}"
  step_has "$1" "Bump diff check" "          ./Scripts/release_bump_diff.sh \"\$BUMP_SHA\" \"\$GREEN_PARENT\" \"\$OLD_VERSION\" \"\$NEW_VERSION\""
  step_has "$1" "Bump diff check" "          BUMP_SHA: ${DOLLAR}{{ github.sha }}"
  step_has "$1" "Bump diff check" "          GREEN_PARENT: ${DOLLAR}{{ inputs.green_parent }}"
  step_has "$1" "Bump diff check" "          OLD_VERSION: ${DOLLAR}{{ inputs.old_version }}"
  step_has "$1" "Bump diff check" "          NEW_VERSION: ${DOLLAR}{{ inputs.new_version }}"
  step_has "$1" "Short PRE gates" "        if: ${DOLLAR}{{ inputs.scope == 'bump' }}"
  step_has "$1" "Short PRE gates" "          ./Scripts/run_short_quality.sh \"\$ROWS\" \"\$DETAILS\" && rc=0 || rc=\$?"
  step_has "$1" "PRE gates" "        if: ${DOLLAR}{{ inputs.scope != 'bump' }}"
  step_has "$1" "PRE gates" "          ./Scripts/run_ci_phase.sh pre \"\$ROWS\" \"\$DETAILS\" && rc=0 || rc=\$?"
  step_has "$1" "POST gates" "        if: ${DOLLAR}{{ !cancelled() && steps.build.outcome == 'success' && inputs.scope != 'bump' }}"
  step_has "$1" "Build site" "        if: ${DOLLAR}{{ !cancelled() && steps.pre.outputs.secret_block != 'true' && steps.short.outputs.secret_block != 'true' && steps.diff.outcome != 'failure' }}"
  step_has "$1" "Render summary and report" "          QS_SHORT_QUALITY: ${DOLLAR}{{ inputs.scope == 'bump' && 'true' || '' }}"
  step_has "$1" "Render summary and report" "          QS_DIFF_OUTCOME: ${DOLLAR}{{ steps.diff.outcome }}"
  step_has "$1" "Render summary and report" "          QS_PRE_OUTCOME: ${DOLLAR}{{ inputs.scope == 'bump' && steps.short.outcome || steps.pre.outcome }}"
  if run_blocks "$1" | grep -qF -- "${DOLLAR}{{"; then
    echo "injection: a run: block expands a \${{ }} expression"
  fi
}

list_findings() {
  local got want
  got="$(grep -v '^#' "$LIST" | grep . | LC_ALL=C sort | tr '\n' ' ')"
  want="Scripts/check_go_lint.sh Scripts/check_go_tests.sh Scripts/check_golden_pages.sh Scripts/check_secrets.sh "
  [[ "$got" == "$want" ]] || echo "list: ${LIST} holds: ${got:-nothing}; want the secret scan, Go tests, golden pages and Go lint"
  local script
  while IFS= read -r script; do
    awk -F'|' -v s="$script" '$1 !~ /^#/ && $2 == s && $3 == "pre" { f = 1 } END { exit !f }' "$ORDER" \
      || echo "list: ${script} is no PRE row of the order file"
  done < <(grep -v '^#' "$LIST" | grep .)
}

findings() {
  input_findings "$1"
  step_findings "$1"
  list_findings
}

OUT="$(findings "$WORKFLOW")"
if [[ -z "$OUT" ]]; then
  echo "  ok: the real workflow holds every pin"
else
  fail "the real workflow breaks a pin:"$'\n'"$OUT"
fi

mutant() {
  local file="${TMP}/$1.yml"
  sed "$2" "$WORKFLOW" > "$file"
  if cmp -s "$WORKFLOW" "$file"; then
    fail "the mutation $2 changed nothing: the proof of '$1' would be vacuous"
    return 0
  fi
  OUT="$(findings "$file")"
  if grep -qF -- "$3" <<< "$OUT"; then
    echo "  ok: mutation proof: $1"
  else
    fail "mutation proof: '$1' was not named '$3'. Findings: ${OUT:-none}"
  fi
}

mutant "no scope input" 's/^      scope:/      scoped:/' "input: workflow_dispatch has no input scope"
mutant "a default scope of bump" 's/^        default: full/        default: bump/' "input: the default scope is not full"
mutant "a scope that is free text" 's/^        options: \[full, bump\]/        options: [full, bump, none]/' "input: scope is not a choice of full and bump"
mutant "no green parent input" 's/^      green_parent:/      parent:/' "input: workflow_dispatch has no input green_parent"
mutant "no push trigger" 's/^  push:/  merge_group:/' "triggers: want push, pull_request and workflow_dispatch"
mutant "the bump diff check skipped for the bump scope" "/name: Bump diff check/,/shell:/s/inputs.scope == 'bump'/inputs.scope == 'none'/" "step 'Bump diff check': want the line"
mutant "the bump diff check not run" 's/^          .\/Scripts\/release_bump_diff.sh .*$/          true/' "step 'Bump diff check': want the line: "
mutant "the bump diff check without the green parent" "s/\"\\\$GREEN_PARENT\" //" "step 'Bump diff check': want the line"
mutant "the bump diff check after the gates" 's/name: Bump diff check/name: Moved/;s/name: PRE gates/name: Bump diff check/;s/name: Moved/name: PRE gates/' "order:"
mutant "the short gates before the diff check" 's/name: Short PRE gates/name: Moved/;s/name: Bump diff check/name: Short PRE gates/;s/name: Moved/name: Bump diff check/' "order: 'Short PRE gates' does not come after 'Bump diff check'"
mutant "the short gates run for every scope" "/name: Short PRE gates/,/shell:/{/if: /d;}" "step 'Short PRE gates': want the line"
mutant "the full gates run for the bump scope" "/name: PRE gates/,/shell:/{/if: /d;}" "step 'PRE gates': want the line"
mutant "the build after a red diff check" "s/ \&\& steps.diff.outcome != 'failure'//" "step 'Build site': want the line"
mutant "POST for the bump scope" "s/ \&\& inputs.scope != 'bump' }}/ }}/" "step 'POST gates': want the line"
mutant "a summary that does not know the short Quality" '/QS_SHORT_QUALITY:/d' "step 'Render summary and report': want the line"
mutant "a template expression in run" "s#^          set -euo pipefail\$#          echo ${DOLLAR}{{ github.sha }}#" "injection:"
sed 's/^Scripts\/check_go_lint.sh$/Scripts\/check_go_lint.sh\nScripts\/check_coverage.sh/' "$LIST" > "${TMP}/list_more.txt"
cp "$LIST" "${TMP}/list.real"
cp "${TMP}/list_more.txt" "$LIST"
OUT="$(findings "$WORKFLOW")"
cp "${TMP}/list.real" "$LIST"
if grep -qF "list: ${LIST} holds" <<< "$OUT"; then echo "  ok: mutation proof: a gate added to the short list is named"; else fail "mutation proof: a longer short list was not named. Findings: ${OUT:-none}"; fi

selftest_end "the quality scope pin found failures" "quality scope pin (the real file holds every pin; each mutant is named)"
