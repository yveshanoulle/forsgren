#!/usr/bin/env bash
# Scripts/test_preview_workflow.sh
#
# Pins the `preview` job of .github/workflows/quality.yml, the job that starts
# the preview deploy after a push to main (forsgren#222). forsgren's own. In
# the shape of Scripts/test_vulncheck_workflow.sh: the real file must hold
# every pin, and each pin is proved by a mutant of the real file that breaks
# it and must be named. Yves's ruling: the preview starts only after Quality
# is green for that commit, so a pushed commit that fails a gate never
# reaches the preview site. The pins:
#   1. the job exists, and its needs: names EVERY other job of the file, so it
#      runs only when all of them succeeded (a gate job added later must be
#      added to needs:)
#   2. its if: is exactly the push-to-main condition (never a pull request,
#      where no secret exists), and no status function (always(), failure(),
#      cancelled(), success()) is in it: a failed gate skips the job
#   3. runs-on: macos-latest, like every job of the file
#      (Scripts/test_quality_runner_pins.sh)
#   4. the job grants contents: read only, and no write appears in it
#   5. its own concurrency group, cancel-in-progress false (push order)
#   6. only checkout, at the commit metrics.yml pins, no persisted credentials
#   7. the start step runs exactly ./Scripts/dispatch_preview.sh "$SHA", with
#      PREVIEW_DISPATCH_TOKEN from secrets.PREVIEW_DISPATCH_TOKEN and SHA from
#      github.sha in its env:
#   8. the secret is referenced once in the whole file, in that env:
#   9. no run: block of the job expands a ${{ }} expression
#  10. a failed start is never softened: no continue-on-error, no || true
#  11. the file has no workflow_run and no pull_request_target trigger
#  12. the order: checkout, then the start
#  13. a dispatch-triggered run (workflow_dispatch: a by-hand
#      Quality run) never starts the preview: the if: names
#      no workflow_dispatch, no inputs and no ||, so only a push passes it

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

WORKFLOW=".github/workflows/quality.yml"
METRICS=".github/workflows/metrics.yml"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
selftest_begin "preview workflow pin"

[[ -f "$WORKFLOW" ]] || selftest_abort "${WORKFLOW} does not exist: nothing starts the preview deploy"
[[ -f "$METRICS" ]] || selftest_abort "${METRICS} does not exist: the action pins have nothing to be compared with"

DOLLAR='$'

# code <file>: the file without its comment lines.
code() {
  grep -vE '^[[:space:]]*#' "$1"
}

# pin_of <file> <action>: the commit the file pins an action at.
pin_of() {
  code "$1" | grep -E "uses: actions/$2@" | head -1 | sed -E 's/.*@([0-9a-f]{40}).*/\1/'
}

# job_ids <file>: the job ids under jobs:, in order.
job_ids() {
  code "$1" | awk '/^jobs:/ { injobs=1; next } injobs && /^[^[:space:]]/ { injobs=0 } injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { id=$0; sub(/^  /, "", id); sub(/:.*$/, "", id); print id }'
}

# job_of <file> <id>: the lines of that job (comment lines left out).
job_of() {
  code "$1" | awk -v id="$2" '
    /^jobs:/ { injobs=1; next }
    injobs && /^[^[:space:]]/ { injobs=0 }
    injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { on = ($0 == "  " id ":"); }
    injobs && on { print }
  '
}

# job_findings <job-file> <whole file> — pins 1 to 5 and 13.
job_findings() {
  local job="$1" whole="$2" others id needs
  if [[ ! -s "$job" ]]; then
    echo "job: the file has no preview job"
    return 0
  fi
  others="$(job_ids "$whole" | grep -vx preview || true)"
  needs="$(grep -E '^    needs:' "$job" | head -1 | sed -E 's/^    needs:[[:space:]]*//' || true)"
  if [[ -z "$needs" ]]; then
    echo "needs: the preview job has no needs:, so it runs whether or not the gates passed"
  else
    for id in $others; do
      grep -qE "(\[|, *)${id}(\]|,)" <<< "$needs" || echo "needs: the gate job ${id} is not in the preview job's needs:"
    done
    local listed
    listed="$(tr -d '[] ' <<< "$needs" | tr ',' '\n')"
    for id in $listed; do
      grep -qx "$id" <<< "$others" || echo "needs: ${id} is not a job of the file"
    done
  fi
  grep -qxF "    if: github.event_name == 'push' && github.ref == 'refs/heads/main'" "$job" \
    || echo "if: the condition is not exactly the push-to-main one"
  if grep -E '^    if:' "$job" | has -E 'workflow_dispatch|inputs\.|[|][|]'; then
    echo "dispatch: the if: lets a workflow_dispatch run (scope bump or full) start the preview, or an || widens it"
  fi
  if grep -E '^    if:' "$job" | has -E 'always\(\)|failure\(\)|cancelled\(\)|success\(\)'; then
    echo "status: the if: holds a status function, so a failed gate may not skip the job"
  fi
  grep -qxF '    runs-on: macos-latest' "$job" || echo "runs-on: the preview job is not on macos-latest"
  grep -qxF '      contents: read   # the checkout of Scripts/dispatch_preview.sh' "$job" || echo "permissions: the job does not hold contents: read"
  if grep -qE ': write|write-all|read-all' "$job" || [[ "$(grep -cE '^      [a-z-]+: ' "$job")" != 1 ]] && grep -E '^      [a-z-]+: ' "$job" | has -vE '^      (contents: read|group:|cancel-in-progress)'; then
    echo "permissions: the job grants more than contents: read"
  fi
  grep -qxF '      group: preview-deploy' "$job" || echo "concurrency: the group is not the fixed preview-deploy"
  grep -qxF '      cancel-in-progress: false' "$job" || echo "concurrency: a run in flight may be cancelled"
}

# step_findings <job-file> — pins 6, 7, 9, 10, 12.
step_findings() {
  local step="Start the preview deploy" used want got
  [[ -s "$1" ]] || return 0
  used="$(grep -E '^[[:space:]]+(- )?uses:' "$1" | sed -E 's/.*uses:[[:space:]]*([^@ ]+)@.*/\1/' | LC_ALL=C sort -u | tr '\n' ' ')"
  [[ "$used" == "actions/checkout " ]] || echo "actions: want checkout only in the job, got: ${used}"
  if grep -E 'uses:' "$1" | has -vE '@[0-9a-f]{40}  # v[0-9]'; then
    echo "pins: an action is not pinned by a full commit with its version comment"
  fi
  want="$(pin_of "$METRICS" checkout)"
  got="$(pin_of "$1" checkout)"
  [[ -n "$want" && "$got" == "$want" ]] || echo "pin of checkout: ${got:-none} is not metrics.yml's ${want:-none}"
  grep -qF 'persist-credentials: false' "$1" || echo "checkout: credentials are persisted"
  step_text "$1" "$step" | has -xF "        run: ./Scripts/dispatch_preview.sh \"${DOLLAR}SHA\"" \
    || echo "start: the step does not run exactly ./Scripts/dispatch_preview.sh \"\$SHA\""
  step_text "$1" "$step" | has -xF "          PREVIEW_DISPATCH_TOKEN: ${DOLLAR}{{ secrets.PREVIEW_DISPATCH_TOKEN }}" \
    || echo "token: the step's env does not take PREVIEW_DISPATCH_TOKEN from secrets.PREVIEW_DISPATCH_TOKEN"
  step_text "$1" "$step" | has -xF "          SHA: ${DOLLAR}{{ github.sha }}" \
    || echo "sha: the step's env does not take SHA from github.sha"
  if run_blocks "$1" | has -F -- "\${{"; then
    echo "injection: a run: block expands a \${{ }} expression"
  fi
  if grep -qE 'continue-on-error|\|\| *(true|:)|set \+e' "$1"; then
    echo "softened: a failed start may pass (continue-on-error, || true or set +e)"
  fi
  local checkout start
  checkout="$(line_of "$1" "uses: actions/checkout")"
  start="$(line_of "$1" "- name: ${step}")"
  later "$start" "$checkout" || echo "order: want checkout, then the start"
}

# file_findings <whole file> — pins 8 and 11.
file_findings() {
  [[ "$(code "$1" | grep -c 'secrets\.PREVIEW_DISPATCH_TOKEN')" == 1 ]] || echo "secrets: want exactly one reference to the token, in the start step's env"
  if code "$1" | has -E 'workflow_run|pull_request_target'; then
    echo "triggers: workflow_run or pull_request_target appears"
  fi
}

# findings <file>: every pin the file breaks, one line each.
findings() {
  local job="${TMP}/job.yml"
  job_of "$1" preview > "$job"
  job_findings "$job" "$1"
  step_findings "$job"
  file_findings "$1"
}

OUT="$(findings "$WORKFLOW")"
if [[ -z "$OUT" ]]; then
  echo "  ok: the real workflow holds every pin"
else
  fail "the real workflow breaks a pin:"$'\n'"$OUT"
fi

# mutant <name> <sed-expression> <finding>: a copy of the workflow with the
# expression applied must break the pin that <finding> names. The expressions
# are basic sed, the same on BSD and GNU; most are ranged to the preview job.
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

P='/^  preview:/,$'
mutant "no needs" "${P}"'{/^    needs: /d;}' "needs: the preview job has no needs:"
mutant "a gate job missing from needs" 's/^  preview:/  extra_gate:\
    runs-on: macos-latest\
    steps:\
      - run: true\
\
  preview:/' "needs: the gate job extra_gate"
mutant "the report job missing from needs" "${P}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows, report\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows]/' "needs: the gate job report is not in the preview job's needs:"
mutant "the isolation_1 job missing from needs" "${P}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows, report\]/needs: [quality, quality_2, lint, isolation_2, summary, browser_1, browser, workflows, report]/' "needs: the gate job isolation_1 is not in the preview job's needs:"
mutant "the isolation_2 job missing from needs" "${P}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows, report\]/needs: [quality, quality_2, lint, isolation_1, summary, browser_1, browser, workflows, report]/' "needs: the gate job isolation_2 is not in the preview job's needs:"
mutant "the summary job missing from needs" "${P}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows, report\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, browser_1, browser, workflows, report]/' "needs: the gate job summary is not in the preview job's needs:"
mutant "the browser job missing from needs" "${P}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows, report\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, workflows, report]/' "needs: the gate job browser is not in the preview job's needs:"
mutant "the browser_1 job missing from needs" "${P}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows, report\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, summary, browser, workflows, report]/' "needs: the gate job browser_1 is not in the preview job's needs:"
mutant "the lint job missing from needs" "${P}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows, report\]/needs: [quality, quality_2, isolation_1, isolation_2, summary, browser_1, browser, workflows, report]/' "needs: the gate job lint is not in the preview job's needs:"
mutant "the workflows job missing from needs" "${P}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows, report\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, report]/' "needs: the gate job workflows is not in the preview job's needs:"
mutant "a needs for a job that is not there" "${P}"'s/needs: \[quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows, report\]/needs: [quality, quality_2, lint, isolation_1, isolation_2, summary, browser_1, browser, workflows, report, ghost]/' "needs: ghost is not a job"
mutant "no push-only condition" "${P}"'{/^    if: /d;}' "if: the condition is not exactly"
mutant "a pull request condition" "${P}"'s/github.event_name == .push./github.event_name != '"'"'push'"'"'/' "if: the condition is not exactly"
mutant "another branch" "${P}"'s#refs/heads/main#refs/heads/dev#' "if: the condition is not exactly"
mutant "workflow_dispatch allowed" "${P}"'s/^    if: \(.*\)/    if: (\1) || github.event_name == '"'"'workflow_dispatch'"'"'/' "dispatch: the if: lets a workflow_dispatch run"
mutant "only a full or bump scope excluded" "${P}"'s/^    if: \(.*\)/    if: \1 || inputs.scope == '"'"'full'"'"'/' "dispatch: the if: lets a workflow_dispatch run"
mutant "if always" "${P}"'s/^    if: .*/    if: always() \&\& github.event_name == '"'"'push'"'"' \&\& github.ref == '"'"'refs\/heads\/main'"'"'/' "status: the if: holds a status function"
mutant "if failure or success" "${P}"'s/^    if: \(.*\)/    if: \1 \&\& !failure()/' "status: the if: holds a status function"
mutant "an ubuntu runner" "${P}"'s/runs-on: macos-latest/runs-on: ubuntu-latest/' "runs-on: the preview job"
mutant "a self-hosted runner" "${P}"'s/runs-on: macos-latest/runs-on: self-hosted/' "runs-on: the preview job"
mutant "a write permission" "${P}"'s/^      contents: read.*/      contents: write/' "permissions: the job does not hold"
mutant "an extra permission" "${P}"'s/^\(      contents: read.*\)$/\1\
      actions: read/' "permissions: the job grants more"
mutant "a cancelling group" "${P}"'s/cancel-in-progress: false/cancel-in-progress: true/' "concurrency: a run in flight"
mutant "another group" "${P}"'s/group: preview-deploy/group: ci/' "concurrency: the group"
mutant "an unpinned checkout" "${P}"'s/checkout@[0-9a-f]\{40\}/checkout@v7/' "pins: an action is not pinned"
mutant "another commit of checkout" "${P}"'s/checkout@3d3c/checkout@3d3d/' "pin of checkout:"
mutant "a third action" "${P}"'s/^\(      - name: Start the preview deploy\)$/      - uses: actions\/cache@0000000000000000000000000000000000000000  # v1.0.0\
\1/' "actions: want checkout only"
mutant "persisted credentials" "${P}"'s/persist-credentials: false/persist-credentials: true/' "checkout: credentials are persisted"
mutant "another command" "${P}"'s#run: ./Scripts/dispatch_preview.sh#run: echo#' "start: the step does not run exactly"
mutant "a token from elsewhere" "${P}"'s/secrets.PREVIEW_DISPATCH_TOKEN/secrets.GITHUB_TOKEN/' "token: the step's env"
mutant "a sha from elsewhere" "${P}"'s/SHA: .*github.sha.*/SHA: main/' "sha: the step's env"
mutant "the token in another job too" 's/^\(      QS_PR_NUMBER: .*\)$/\1/;s/^\(          QS_QUALITY_RESULT: .*\)$/\1\
          LEAK: '"${DOLLAR}"'{{ secrets.PREVIEW_DISPATCH_TOKEN }}/' "secrets: want exactly one"
mutant "a template expression in run" "${P}s#\"\\${DOLLAR}SHA\"#\"${DOLLAR}{{ github.sha }}\"#" "injection:"
mutant "a start that may fail" "${P}"'s#^\(        run: .*\)$#\1 || true#' "softened:"
mutant "continue-on-error" "${P}"'s/^        shell: bash/        shell: bash\
        continue-on-error: true/' "softened:"
mutant "a workflow_run trigger" 's/^  workflow_dispatch:/  workflow_run:\
    workflows: [x]\
  workflow_dispatch:/' "triggers: workflow_run"
mutant "no start step to run after the checkout" "${P}"'s/- name: Start the preview deploy/- name: Start it/' "order:"
mutant "no preview job" 's/^  preview:/  previewed:/' "job: the file has no preview job"

selftest_end "the preview workflow pin found failures" "preview workflow pin (the real quality.yml holds every pin; each mutant is named)"
