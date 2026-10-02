#!/usr/bin/env bash
# Scripts/test_render_quality_summary.sh
#
# Self-test for Scripts/render_quality_summary.sh (forsgren#8), the block of
# key numbers at the top of every Quality run page. It renders from what the
# run already wrote (the rows file and details directory of
# Scripts/run_ci_phase.sh, the Go tests and Go coverage gate outputs in
# them, Scripts/build_site.sh's page-count sink, the version in
# cmd/forsgren/main.go) and from the job's status and step outcomes, which
# quality.yml passes through env. Each case is a fixture run under one temp
# root:
#   1. a green run          -> every number, and "Succeeded"
#   2. a red PRE with a secret-class finding
#                           -> "stopped in PRE"; POST, Go-less build numbers
#                              show — with the reason, never 0
#   3. a cancelled run      -> "Cancelled", and where it stopped
#   4. no coverage output   -> coverage and floors show — with the reason
#   5. a pull-request trigger -> its number
#   6. a run that stopped in setup, with no rows file at all -> it still
#      renders, and exits 0
#   7. MUTATION PROOF: this self-test, re-run against a renderer whose
#      missing-input reason is replaced by a 0, is red, and says why.
#
# The renderer is presentation, so like Scripts/render_quality_report.sh it
# must exit 0 on whatever it is given: a summary step that fails turns a
# run's page red for a reason unrelated to what it reports.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# Overridable ONLY by the mutation proof (case 7), which re-runs this
# self-test against a mutated copy of the renderer.
RENDER="${QS_SELFTEST_RENDER_OVERRIDE:-./Scripts/render_quality_summary.sh}"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "quality-run summary self-test"

[[ -x "$RENDER" ]] || selftest_abort "${RENDER} is missing or not executable"

# --- fixtures ---------------------------------------------------------------

# The order file: three pre rows (two of them the Go rows the summary reads),
# two post rows and an n/a row, which counts in neither phase.
ORDER="${TMP}/order.txt"
{
  echo "# comment"
  echo "alpha|Scripts/alpha.sh|pre|"
  echo "Go tests|Scripts/go_tests.sh|pre|"
  echo "Go coverage|Scripts/go_coverage.sh|pre|"
  echo "omega|Scripts/omega.sh|post|"
  echo "psi|Scripts/psi.sh|post|"
  echo "privacy pages|n/a|nothing is collected here"
} > "$ORDER"

MAIN_GO="${TMP}/main.go"
printf 'package main\n\n// version is the release.\nvar version = "9.8.7"\n' > "$MAIN_GO"

# details_file <dir> <slug> <gate output...>: a details file as
# run_ci_phase.sh writes it, the gate's output inside a fence.
details_file() {
  local dir="$1" slug="$2"
  shift 2
  mkdir -p "$dir"
  {
    echo ""
    echo "#### ✅ ${slug}"
    echo ""
    echo '```'
    printf '%s\n' "$@"
    echo '```'
  } > "${dir}/${slug}.md"
}

# green_run <dir>: the rows, details and page-count sink of a run where
# every gate passed and the build wrote 3 pages.
green_run() {
  local dir="$1"
  mkdir -p "$dir"
  printf 'alpha|✅\nGo tests|✅\nGo coverage|✅\nomega|✅\npsi|✅\n' > "${dir}/rows.md"
  details_file "${dir}/details" "Go_tests" \
    "=== RUN   TestOne" "--- PASS: TestOne (0.00s)" "" "OK: go test ./... — 12 tests passed"
  details_file "${dir}/details" "Go_coverage" \
    "  ✅ example.com/m/a.go:One: 100.0% (floor 100.0%)" \
    "  ✅ total: 63.2% (floor 63.1%)" "" \
    "  ⬆️  example.com/m/a.go:Two: 80.0%, floor 0.0% — raise it to 79.9" \
    "FLOORWARN: 2 coverage floor(s) should be raised in coverage_thresholds.json" "" \
    "OK: coverage — total 63.2%, 2 function(s) measured, 1 enforced at or above their floors"
  echo 3 > "${dir}/pages.log"
}

# The env of one run. Each case sets what differs; reset_env restores a
# green push on main, started 252 seconds before "now".
reset_env() {
  JOB=success PRE=success BUILD=success POST=success SECRET=""
  EVENT=push SHA=0123456789abcdef0123456789abcdef01234567 REF=main PR=""
  STARTED=1000 NOW=1252
}

# render <dir>: runs the renderer on <dir>'s rows, details and sink, with
# every input passed explicitly, so a variable of the machine running this
# (GITHUB_SHA on CI, for one) never leaks into a case.
render() {
  local dir="$1"
  capture env \
    QS_JOB_STATUS="$JOB" QS_PRE_OUTCOME="$PRE" QS_BUILD_OUTCOME="$BUILD" \
    QS_POST_OUTCOME="$POST" QS_SECRET_BLOCK="$SECRET" QS_PR_NUMBER="$PR" \
    QS_STARTED_AT="$STARTED" QS_NOW="$NOW" \
    GITHUB_EVENT_NAME="$EVENT" GITHUB_SHA="$SHA" GITHUB_REF_NAME="$REF" \
    QS_MAIN_GO="$MAIN_GO" SITE_PAGE_COUNT_FILE="${dir}/pages.log" \
    "$RENDER" "${dir}/rows.md" "${dir}/details" "$ORDER"
}

# want_row <case> <row>: the output has exactly this table row, whole line.
want_row() {
  if grep -qxF -- "$2" <<< "$OUT"; then
    echo "  ok: $1"
  else
    fail "$1: no row '$2'. Output: ${OUT}"
  fi
}

# want_absent <case> <text>: the output does not contain <text>.
want_absent() {
  if grep -qF -- "$2" <<< "$OUT"; then
    fail "$1: the output says '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# --- 1. a green run -----------------------------------------------------------
reset_env
green_run "${TMP}/green"
render "${TMP}/green"
want_rc  "a green run renders and exits 0" 0
want_said "the status says it succeeded" "**✅ Succeeded** — PRE, build and POST all ran."
want_row "the PRE gates are counted by phase"   "| PRE gates | 3 passed · 0 failed · 0 skipped |"
want_row "the POST gates are counted by phase"  "| POST gates | 2 passed · 0 failed · 0 skipped |"
want_row "the Go tests passed are counted"      "| Go tests | 12 passed |"
want_row "the coverage total and its floor"     "| Go coverage | 63.2% (floor 63.1%) |"
want_row "the FLOORWARN count"                  "| Floors to raise | 2 |"
want_row "the pages generated"                  "| Pages generated | 3 |"
want_row "the forsgren version"                 "| forsgren version | 9.8.7 |"
want_row "the short commit"                     "| Commit | \`0123456\` |"
want_row "a push names its branch"              "| Trigger | push to main |"
want_row "the duration"                         "| Duration | 4m 12s |"

# --- 2. a red PRE with a secret-class finding -------------------------------
# The build and POST are skipped, so their numbers do not exist: each shows —
# with why, never a 0 that reads as measured.
reset_env
JOB=failure PRE=failure BUILD=skipped POST=skipped SECRET=true
mkdir -p "${TMP}/red_pre"
printf 'alpha|❌\nGo tests|✅\n' > "${TMP}/red_pre/rows.md"
details_file "${TMP}/red_pre/details" "Go_tests" "OK: go test ./... — 12 tests passed"
render "${TMP}/red_pre"
want_rc  "a red run renders and exits 0" 0
want_said "the status says it failed, and stopped in PRE" "**❌ Failed** — stopped in PRE; red in: PRE."
want_row "a PRE gate that never reported is skipped, not passed" "| PRE gates | 1 passed · 1 failed · 1 skipped |"
want_row "POST shows — with the secret-class reason" \
  "| POST gates | — (not run: a secret-class finding in PRE skips the build and POST) |"
want_row "pages show — because the build did not run" "| Pages generated | — (the build did not run) |"
want_row "a coverage gate that never ran shows — with why" "| Go coverage | — (the Go coverage gate did not report) |"
want_absent "no phase of a stopped run reads as 0 passed" "| POST gates | 0 passed"

# --- 3. a cancelled run -------------------------------------------------------
reset_env
JOB=cancelled PRE=cancelled BUILD="" POST=""
mkdir -p "${TMP}/cancelled"
printf 'alpha|✅\n' > "${TMP}/cancelled/rows.md"
render "${TMP}/cancelled"
want_rc  "a cancelled run renders and exits 0" 0
want_said "the status says cancelled, and in which phase" "**⏹️ Cancelled** — stopped in PRE."
want_row "the PRE gates it got through" "| PRE gates | 1 passed · 0 failed · 2 skipped |"
want_row "POST shows — because the run was cancelled" "| POST gates | — (not run: the run was cancelled) |"
want_row "pages show — because the build did not run" "| Pages generated | — (the build did not run) |"

# --- 4. no coverage output --------------------------------------------------
# A green-looking run whose details hold no Go coverage file: the total and
# the floors to raise are unknown, so — with the reason, never 0.
reset_env
green_run "${TMP}/no_cov"
rm "${TMP}/no_cov/details/Go_coverage.md"
render "${TMP}/no_cov"
want_row "missing coverage output shows — with its reason, never a number" \
  "| Go coverage | — (the Go coverage gate did not report) |"
want_row "floors to raise show — with the same reason" \
  "| Floors to raise | — (the Go coverage gate did not report) |"
want_absent "floors to raise is not 0 when nothing measured them" "| Floors to raise | 0 |"

# --- 5. a pull-request trigger ----------------------------------------------
reset_env
EVENT=pull_request PR=42 REF="42/merge"
green_run "${TMP}/pr"
render "${TMP}/pr"
want_row "a pull request names its number" "| Trigger | pull request #42 |"
EVENT=workflow_dispatch PR=""
render "${TMP}/pr"
want_row "a manual run says so" "| Trigger | by hand |"

# --- 6. a run that stopped in setup -----------------------------------------
# quality.yml's Start report step never ran, so there is no rows file and no
# details directory: the run that most needs a summary.
reset_env
JOB=failure PRE="" BUILD="" POST="" SHA="" EVENT="" STARTED=""
mkdir -p "${TMP}/setup"
render "${TMP}/setup"
want_rc  "a run with no rows file renders and exits 0" 0
want_said "the status says it stopped in setup" "**❌ Failed** — stopped in setup, before the PRE gates."
want_row "PRE shows — with the reason" "| PRE gates | — (not run: the job stopped in setup, before the gates) |"
want_row "a missing commit says so" "| Commit | — (GITHUB_SHA not set) |"
want_row "a missing start time says so" "| Duration | — (the start time was not recorded) |"

# --- 7. MUTATION PROOF --------------------------------------------------------
# The renderer with every missing-input reason replaced by a 0: the shape
# this self-test exists to refuse. Re-run against it, this self-test must be
# red, and red for THAT reason (case 4's), not for an unrelated one.
if [[ -z "${QS_SELFTEST_RENDER_OVERRIDE:-}" ]]; then
  mutant="${TMP}/mutant/render_quality_summary.sh"
  if selftest_mutant "$RENDER" "$mutant" "s|printf '— (%s)' \"\$1\"|printf '0'|"; then
    capture env QS_SELFTEST_RENDER_OVERRIDE="$mutant" "$0"
    want_red "a renderer that writes 0 for a missing input is caught" \
      "missing coverage output shows — with its reason, never a number"
  fi
fi

selftest_end "quality-run summary self-test" \
  "quality-run summary (green, red PRE, cancelled, setup-stopped and pull-request runs; a missing input shows — with its reason, never 0)"
