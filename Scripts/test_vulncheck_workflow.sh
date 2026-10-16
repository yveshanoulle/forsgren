#!/usr/bin/env bash
# Scripts/test_vulncheck_workflow.sh
#
# Pins .github/workflows/vulncheck.yml, the scheduled govulncheck run
# (forsgren#87). forsgren's own. Nothing in sfl or Quality runs it, so this
# pin is what proves it, on every run, in the shape of
# Scripts/test_starter_page_workflow.sh: the real file must hold every pin,
# and each pin is proved by a mutant of the real file that breaks it and must
# be named. The pins:
#   1. it triggers on schedule and workflow_dispatch, and on nothing else;
#      no push or pull-request event appears anywhere in it
#   2. one cron entry, daily, at an off-peak minute (not :00 or :30)
#   3. permissions: contents: read, and no write anywhere
#   4. one job, on ubuntu-latest (GitHub-hosted)
#   5. only checkout and setup-go, each pinned by a full commit and the very
#      commit metrics.yml pins for it
#   6. the checkout does not persist credentials
#   7. setup-go reads go.mod, no cache
#   8. GOTOOLCHAIN comes from Scripts/go_toolchain.sh, written to GITHUB_ENV
#   9. the scan step runs exactly ./Scripts/check_govulncheck.sh with
#      FORSGREN_VULN_DB_REQUIRED set to 1 in its env: (an unreachable database
#      fails the run, it is never a skip)
#  10. no run: block expands a ${{ }} expression (template injection)
#  11. the order: checkout, Go, toolchain, scan

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

WORKFLOW=".github/workflows/vulncheck.yml"
METRICS=".github/workflows/metrics.yml"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
selftest_begin "vulncheck workflow pin"

[[ -f "$WORKFLOW" ]] || selftest_abort "${WORKFLOW} does not exist: nothing runs govulncheck on a schedule"
[[ -f "$METRICS" ]] || selftest_abort "${METRICS} does not exist: the action pins have nothing to be compared with"

# code <file>: the file without its comment lines.
code() {
  grep -vE '^[[:space:]]*#' "$1"
}

# pin_of <file> <action>: the commit the file pins an action at.
pin_of() {
  code "$1" | grep -E "uses: actions/$2@" | head -1 | sed -E 's/.*@([0-9a-f]{40}).*/\1/'
}

# trigger_findings <file> — pins 1 and 2.
trigger_findings() {
  local events crons
  events="$(on_events "$1" | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$events" == "schedule workflow_dispatch " ]] || echo "triggers: want schedule and workflow_dispatch, got: ${events:-none}"
  if code "$1" | grep -qE 'pull_request|push:'; then
    echo "push or pull_request: such an event appears in the workflow"
  fi
  crons="$(code "$1" | grep -E '^[[:space:]]+- cron:')"
  [[ "$(grep -c . <<< "$crons")" == 1 ]] || echo "cron: want exactly one entry, got: ${crons:-none}"
  grep -qE '^[[:space:]]+- cron: "([1-9]|[1-5][0-9]) [0-9]+ \* \* \*"$' <<< "$crons" \
    && ! grep -qE '"30 ' <<< "$crons" || echo "cron: want one daily entry at an off-peak minute (not :00 or :30), got: ${crons:-none}"
}

# permission_findings <file> — pins 3 and 4.
permission_findings() {
  if ! awk '/^permissions:/ { getline; if ($0 == "  contents: read") ok=1 } END { exit !ok }' "$1"; then
    echo "permissions: the top level is not contents: read"
  fi
  if code "$1" | grep -qE ': write|write-all'; then
    echo "write permissions: a write permission appears"
  fi
  local hosts
  hosts="$(code "$1" | grep -E '^[[:space:]]+runs-on:' | sed -E 's/.*runs-on:[[:space:]]*//' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
  [[ "$hosts" == " 1 ubuntu-latest;" ]] || echo "runs-on: want one job on ubuntu-latest, got: ${hosts}"
}

# action_findings <file> — pins 5 to 7.
action_findings() {
  local action want got used
  used="$(code "$1" | grep -E '^[[:space:]]+(- )?uses:' | sed -E 's/.*uses:[[:space:]]*([^@ ]+)@.*/\1/' | LC_ALL=C sort -u | tr '\n' ' ')"
  [[ "$used" == "actions/checkout actions/setup-go " ]] || echo "actions: want checkout and setup-go only, got: ${used}"
  if code "$1" | grep -E 'uses:' | grep -vqE '@[0-9a-f]{40}  # v[0-9]'; then
    echo "pins: an action is not pinned by a full commit with its version comment"
  fi
  for action in checkout setup-go; do
    want="$(pin_of "$METRICS" "$action")"
    got="$(pin_of "$1" "$action")"
    [[ -n "$want" && "$got" == "$want" ]] || echo "pin of ${action}: ${got:-none} is not metrics.yml's ${want:-none}"
  done
  step_text "$1" "Check out" | grep -qF 'persist-credentials: false' || echo "checkout: credentials are persisted"
  step_text "$1" "Set up Go" | grep -qxF '          go-version-file: go.mod' || echo "setup-go: it does not read go.mod"
  step_text "$1" "Set up Go" | grep -qxF '          cache: false' || echo "setup-go: a cache is restored"
}

# step_findings <file> — pins 8 to 11.
step_findings() {
  step_block "$1" "Pin the Go toolchain" run | grep -qF 'toolchain="$(./Scripts/go_toolchain.sh)"' \
    || echo "toolchain: it is not read from Scripts/go_toolchain.sh"
  step_block "$1" "Pin the Go toolchain" run | grep -qF 'echo "GOTOOLCHAIN=${toolchain}" >> "$GITHUB_ENV"' \
    || echo "toolchain: GOTOOLCHAIN is not written to GITHUB_ENV"
  step_text "$1" "Scan for vulnerabilities" | grep -qxF '        run: ./Scripts/check_govulncheck.sh' \
    || echo "scan: the step does not run exactly ./Scripts/check_govulncheck.sh"
  step_text "$1" "Scan for vulnerabilities" | grep -qxF "          FORSGREN_VULN_DB_REQUIRED: '1'" \
    || echo "required: the scan step does not set FORSGREN_VULN_DB_REQUIRED to 1"
  if run_blocks "$1" | grep -qF -- "\${{"; then
    echo "injection: a run: block expands a \${{ }} expression"
  fi
  local checkout gosetup toolchain scan
  checkout="$(line_of "$1" "name: Check out")"
  gosetup="$(line_of "$1" "name: Set up Go")"
  toolchain="$(line_of "$1" "name: Pin the Go toolchain")"
  scan="$(line_of "$1" "name: Scan for vulnerabilities")"
  if ! { later "$gosetup" "$checkout" && later "$toolchain" "$gosetup" && later "$scan" "$toolchain"; }; then
    echo "order: want checkout, Go, toolchain, scan"
  fi
}

# findings <file>: every pin the file breaks, one line each.
findings() {
  trigger_findings "$1"
  permission_findings "$1"
  action_findings "$1"
  step_findings "$1"
}

OUT="$(findings "$WORKFLOW")"
if [[ -z "$OUT" ]]; then
  echo "  ok: the real workflow holds every pin"
else
  fail "the real workflow breaks a pin:"$'\n'"$OUT"
fi

# mutant <name> <sed-expression> <finding>: a copy of the workflow with the
# expression applied must break the pin that <finding> names. The expressions
# are basic sed, the same on BSD and GNU.
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

mutant "a push trigger" 's/^  workflow_dispatch:/  push:/' "push or pull_request:"
mutant "a pull_request trigger" 's/^  workflow_dispatch:/  pull_request:/' "push or pull_request:"
mutant "no schedule" 's/^  schedule:/  release:/' "triggers: want schedule"
mutant "a second cron" 's/^    - cron: \(.*\)$/    - cron: \1\
    - cron: "5 6 * * *"/' "cron: want exactly one"
mutant "a cron on the hour" 's/- cron: "[0-9]* /- cron: "0 /' "cron: want one daily entry at an off-peak"
mutant "a weekly cron" 's/\* \* \*"$/* * 1"/' "cron: want one daily entry"
mutant "a write token at the top" 's/^  contents: read/  contents: write/' "permissions: the top level"
mutant "a write permission" 's/^    runs-on: ubuntu-latest/    permissions:\
      issues: write\
    runs-on: ubuntu-latest/' "write permissions:"
mutant "a macOS runner" 's/runs-on: ubuntu-latest/runs-on: macos-latest/' "runs-on: want one job"
mutant "a self-hosted runner" 's/runs-on: ubuntu-latest/runs-on: self-hosted/' "runs-on: want one job"
mutant "an unpinned checkout" 's/checkout@[0-9a-f]\{40\}/checkout@v7/' "pins: an action is not pinned"
mutant "another commit of setup-go" 's/setup-go@b7ad/setup-go@b7ae/' "pin of setup-go:"
mutant "a third action" 's/^\(      - name: Scan for vulnerabilities\)$/      - uses: actions\/cache@0000000000000000000000000000000000000000  # v1.0.0\
\1/' "actions: want checkout and setup-go only"
mutant "persisted credentials" 's/persist-credentials: false/persist-credentials: true/' "checkout: credentials are persisted"
mutant "a Go that ignores go.mod" 's/go-version-file: go.mod/go-version: stable/' "setup-go: it does not read go.mod"
mutant "a Go cache" 's/cache: false/cache: true/' "setup-go: a cache"
mutant "a toolchain from elsewhere" 's#\./Scripts/go_toolchain.sh#echo go1.0#' "toolchain: it is not read from"
mutant "a toolchain never exported" 's#>> "\$GITHUB_ENV"#>> /dev/null#' "toolchain: GOTOOLCHAIN is not written"
mutant "another scan command" 's#run: ./Scripts/check_govulncheck.sh#run: go vet ./...#' "scan: the step does not run exactly"
mutant "a scan that may skip" "s/FORSGREN_VULN_DB_REQUIRED: '1'/FORSGREN_VULN_DB_REQUIRED: '0'/" "required: the scan step"
mutant "a template expression in run" 's#run: ./Scripts/check_govulncheck.sh#run: ./Scripts/check_govulncheck.sh ${{ github.sha }}#' "injection:"
mutant "a scan before the toolchain" 's/name: Pin the Go toolchain/name: Pin the Go toolchain late/;s/name: Scan for vulnerabilities/name: Pin the Go toolchain/' "order:"

selftest_end "the vulncheck workflow pin found failures" "vulncheck workflow pin (the real file holds every pin; each mutant is named)"
