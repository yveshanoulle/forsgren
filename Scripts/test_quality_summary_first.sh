#!/usr/bin/env bash
# Scripts/test_quality_summary_first.sh
#
# Pins that the run's key numbers stay the FIRST thing on the Quality run page
# (forsgren#233). GitHub shows each step's summary in step order, so the
# headline is first only while no step BEFORE the step "Render summary and
# report" writes to $GITHUB_STEP_SUMMARY. That step writes the headline, then
# the gate table. The steps after it (the
# baselines) may write the page themselves. forsgren's own. The pins, on the
# real .github/workflows/quality.yml, each proved by a mutant that breaks it
# and must be named:
#   1. no step before the summary step writes to $GITHUB_STEP_SUMMARY, neither
#      itself nor through a script of Scripts/ that appends to it
#      (report_baselines.sh ...); a step that runs such
#      a script points GITHUB_STEP_SUMMARY at its own file on that command
#   2. in the summary step the headline (render_quality_summary.sh) is the
#      first write, ahead of the gate table (render_quality_report.sh)
#
# The self-tests that run those scripts must not write the real page either;
# Scripts/test_step_summary_isolation.sh pins that.
#
# A workflow is read with the awk readers of Scripts/lib_workflow_steps.sh,
# not a YAML parser.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
selftest_begin "quality summary first pin"

WORKFLOW=".github/workflows/quality.yml"
SUMMARY_STEP="Render summary and report"
[[ -f "$WORKFLOW" ]] || selftest_abort "${WORKFLOW} does not exist"

# The scripts that append to the step summary themselves: every non-test
# script of Scripts/ that mentions it, minus the two renderers, which only
# print and are redirected by the summary step.
writers() {
  grep -l 'GITHUB_STEP_SUMMARY' Scripts/*.sh \
    | grep -v '/test_' | grep -v '/lib_' | grep -v 'render_quality_' | sed 's#^Scripts/##'
}

# step_names <file>: the names of the report job's steps, in order. That job
# holds the summary step: Quality's jobs hand their rows to it (forsgren#259),
# and it renders the one page.
step_names() {
  awk '/^jobs:/ { injobs = 1 } injobs && /^  [A-Za-z_-]+:[[:space:]]*$/ { on = ($0 == "  report:") } on && /^      - name: / { sub(/^      - name: /, ""); print }' "$1"
}

# code_of <file> <step>: the step's lines without comment lines, a command
# continued with a trailing backslash joined into one line.
code_of() {
  step_text "$1" "$2" | grep -vE '^[[:space:]]*#' | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta' || true
}

writer_findings() {
  local name text writer
  while IFS= read -r name; do
    [[ "$name" == "$SUMMARY_STEP" ]] && break
    text="$(code_of "$1" "$name")"
    if grep -v 'GITHUB_STEP_SUMMARY=' <<< "$text" | grep -q 'GITHUB_STEP_SUMMARY'; then
      echo "writer: step '${name}' writes to GITHUB_STEP_SUMMARY itself, so its output comes before the headline"
    fi
    while IFS= read -r writer; do
      if grep -F "$writer" <<< "$text" | grep -v 'GITHUB_STEP_SUMMARY=' | grep -q .; then
        echo "writer: step '${name}' runs ${writer}, which appends to GITHUB_STEP_SUMMARY, without pointing it at its own file"
      fi
    done < <(writers)
  done < <(step_names "$1")
}

order_findings() {
  local run head table
  run="$(step_block "$1" "$SUMMARY_STEP" run)"
  [[ -n "$run" ]] || { echo "summary: there is no step named '${SUMMARY_STEP}' with a run: block"; return 0; }
  head="$(grep -nF 'render_quality_summary.sh' <<< "$run" | head -1 | cut -d: -f1)"
  table="$(grep -nF 'render_quality_report.sh' <<< "$run" | head -1 | cut -d: -f1)"
  [[ -n "$head" ]] || echo "summary: the step '${SUMMARY_STEP}' does not write the headline (render_quality_summary.sh)"
  [[ -n "$table" ]] || echo "summary: the step '${SUMMARY_STEP}' does not write the gate table (render_quality_report.sh)"
  if later "$head" "$table"; then
    echo "summary: the gate table is written before the headline in '${SUMMARY_STEP}'"
  fi
  if grep -nE 'GITHUB_STEP_SUMMARY' <<< "$run" | head -1 | grep -qvF 'render_quality_summary.sh'; then
    echo "summary: the first write to GITHUB_STEP_SUMMARY in '${SUMMARY_STEP}' is not the headline"
  fi
}

findings() {
  writer_findings "$1"
  order_findings "$1"
}

if [[ -z "$(writers)" ]]; then
  fail "no script of Scripts/ appends to GITHUB_STEP_SUMMARY: the writer list is empty, so pin 1 would be vacuous"
fi

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

mutant "a step before the summary step that writes the summary itself" \
  's#^      - name: Download the gate reports#      - name: Early\
        run: echo early >> GITHUB_STEP_SUMMARY\
\
      - name: Download the gate reports#' \
  "writer: step 'Early' writes to GITHUB_STEP_SUMMARY itself"
mutant "the gate table before the headline" \
  's#render_quality_summary.sh#TMPNAME#;s#render_quality_report.sh#render_quality_summary.sh#;s#TMPNAME#render_quality_report.sh#' \
  "summary: the gate table is written before the headline"
mutant "a baselines step before the summary step" \
  's#^      - name: Download the gate reports#      - name: Language baselines\
        run: ./Scripts/report_baselines.sh language\
\
      - name: Download the gate reports#' \
  "writer: step 'Language baselines' runs report_baselines.sh"

selftest_end "the quality summary first pin found failures" "quality summary first pin (the real file holds every pin; each mutant is named)"
