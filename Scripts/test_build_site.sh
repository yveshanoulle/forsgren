#!/usr/bin/env bash
# Scripts/test_build_site.sh
#
# Fixture for Scripts/build_site.sh. Shape ported from another estate repository's
# fixture of the same name (its checks 14 to 16, the page-count sink, are
# carried over as checks 4, 10 and 11); the build itself is new: the Go
# generator replaces konenki's include-marker assembly.
#
# Every case gets its own output directory, page-count sink and binary
# directory under one temp root, so no case can read what another left, and
# no run writes the repository's own .build/site-page-count.log or
# .build/bin/forsgren.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

VERSION=1
BUILD="./Scripts/build_site.sh"
GOLDEN="internal/page/testdata/index.golden.html"
STYLES="internal/page/styles.css"

# The page's footer shows the render time on every run (forsgren#41), so every
# build here is pinned to the moment of the golden files, 2026-10-03 12:00 UTC,
# through render's clock seam (SOURCE_DATE_EPOCH); the time is never stripped.
PINNED_EPOCH=1791028800

# The goldens are rendered as the fixed test version of the Go tests, never the
# released one (forsgren#237); the build says it is that version.
export FORSGREN_BUILD_VERSION=9.9.9

TEMP_ROOT="$(mktemp -d)"
COMPLETED=0
FAILURES=0

cleanup() {
  rm -rf "$TEMP_ROOT"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: build-site fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

pass() { echo "  ✅ $1. $2"; }
fail_check() {
  echo "  ❌ $1. $2"
  FAILURES=$((FAILURES + 1))
}

# check <number> <name> <expected-exit> <actual-exit>
check() {
  if [[ "$3" == "$4" ]]; then
    pass "$1" "$2"
  else
    fail_check "$1" "$2 — expected exit $3, got $4"
  fi
}

# check_file <number> <name> <expected-file> <actual-file>
check_file() {
  if cmp -s "$3" "$4"; then
    pass "$1" "$2"
  else
    fail_check "$1" "$2 — generated file differs from ${3}"
    diff -u "$3" "$4" || true
  fi
}

# new_case <name> — sets CASE_OUTPUT, CASE_SINK and CASE_BIN for a fresh case.
new_case() {
  local root="${TEMP_ROOT}/$1"
  mkdir -p "$root"
  CASE_OUTPUT="${root}/site"
  CASE_SINK="${root}/site-page-count.log"
  CASE_BIN="${root}/bin"
  CASE_PATH="$PATH"
  CASE_GO_MODE=""
}

# run_build — builds the current case. Sets RC and leaves the output in
# CASE_LOG.
run_build() {
  CASE_LOG="${CASE_OUTPUT}.log"
  set +e
  PATH="$CASE_PATH" STUB_GO_MODE="$CASE_GO_MODE" SOURCE_DATE_EPOCH="$PINNED_EPOCH" \
    SITE_PAGE_COUNT_FILE="$CASE_SINK" FORSGREN_BIN_DIR="$CASE_BIN" \
    "$BUILD" "$CASE_OUTPUT" > "$CASE_LOG" 2>&1
  RC=$?
  set -e
}

# A stub `go`, put first on PATH by stub_go. build_site.sh calls
# `go build -o <bin> ./cmd/forsgren`, so <bin> is $3. STUB_GO_MODE picks
# what it does: build-fails exits 1; render-fails and no-pages "build" a
# fake forsgren that exits 1, or exits 0 having written nothing; prebuilt
# copies the binary STUB_PREBUILT names (the mutation proof of the fixture site).
STUB_GO_DIR="${TEMP_ROOT}/stub-go"
mkdir -p "$STUB_GO_DIR"
cat > "${STUB_GO_DIR}/go" <<'STUB'
#!/usr/bin/env bash
case "${STUB_GO_MODE:?}" in
  build-fails) echo "stub go: build failed" >&2; exit 1 ;;
  prebuilt) cp "${STUB_PREBUILT:?}" "$3" ;;
  render-fails) printf '#!/usr/bin/env bash\nexit 1\n' > "$3" ;;
  no-pages) printf '#!/usr/bin/env bash\nexit 0\n' > "$3" ;;
esac
chmod +x "$3"
STUB
chmod +x "${STUB_GO_DIR}/go"

# stub_go <mode> — the current case runs the stub go in <mode>.
stub_go() {
  CASE_PATH="${STUB_GO_DIR}:$PATH"
  CASE_GO_MODE="$1"
}

# expect_build_failure <number> <name> <reason> — requires exit 1 with
# <reason> in the build's output (a failure for any other reason is not the
# case biting), and records the case's sink for check 10.
expect_build_failure() {
  run_build
  if [[ "$RC" -ne 1 ]]; then
    fail_check "$1" "$2 — expected exit 1, got ${RC}"
  elif ! grep -qF -- "$3" "$CASE_LOG"; then
    fail_check "$1" "$2 — failed without saying '$3': $(cat "$CASE_LOG")"
  else
    pass "$1" "$2"
  fi
  FAILED_SINKS="${FAILED_SINKS} ${CASE_SINK}"
}

echo "test_build_site v${VERSION}"
echo ""

# Check 11 needs to tell a write by this run from a count an earlier run
# left: stamped before the first build (APFS mtimes are sub-second).
REAL_PAGE_COUNT_FILE=".build/site-page-count.log"
BEFORE_FIRST_BUILD="${TEMP_ROOT}/before-first-build"
touch "$BEFORE_FIRST_BUILD"

# A plain string, not an array: an empty bash 3.2 array under set -u is fatal.
FAILED_SINKS=""

new_case "happy"
run_build
check 1 "builds the site" 0 "$RC"
HAPPY_OUTPUT="$CASE_OUTPUT"
HAPPY_SINK="$CASE_SINK"
if [[ "$RC" -ne 0 ]]; then
  cat "$CASE_LOG"
fi

check_file 2 "index.html is the golden placeholder page" "$GOLDEN" "${HAPPY_OUTPUT}/index.html"
check_file 12 "legend.html is the golden legend page" "internal/page/testdata/legend.golden.html" "${HAPPY_OUTPUT}/legend.html"
check_file 13 "standard/index.html is the golden placeholder standard view" "internal/page/testdata/standard.placeholder.golden.html" "${HAPPY_OUTPUT}/standard/index.html"
check_file 14 "numbers/index.html is the golden placeholder numbers view" "internal/page/testdata/numbers.placeholder.golden.html" "${HAPPY_OUTPUT}/numbers/index.html"
check_file 15 "settings.html is the golden settings page" "internal/page/testdata/settings.golden.html" "${HAPPY_OUTPUT}/settings.html"
check_file 16 "days.html is the golden placeholder days page" "internal/page/testdata/days.placeholder.golden.html" "${HAPPY_OUTPUT}/days.html"
check_file 17 "issues.html is the golden placeholder issues page" "internal/page/testdata/issues.no-rows.golden.html" "${HAPPY_OUTPUT}/issues.html"
check_file 3 "styles.css is copied as authored" "$STYLES" "${HAPPY_OUTPUT}/styles.css"
check_file 19 "favicon.svg is copied as authored" "internal/page/favicon.svg" "${HAPPY_OUTPUT}/favicon.svg"

if [[ -f "$HAPPY_SINK" ]] && [[ "$(cat "$HAPPY_SINK")" == "11" ]]; then
  pass 4 "writes the page count (11) to SITE_PAGE_COUNT_FILE"
else
  fail_check 4 "writes the page count (11) to SITE_PAGE_COUNT_FILE — found: $(cat "$HAPPY_SINK" 2>/dev/null || echo MISSING)"
fi

new_case "again"
run_build
if [[ "$RC" -eq 0 ]] && diff -r "$HAPPY_OUTPUT" "$CASE_OUTPUT" > /dev/null; then
  pass 5 "two builds at the same pinned time are byte-identical"
else
  fail_check 5 "two builds are byte-identical — the second build (exit ${RC}) differs from the first"
fi

new_case "go-build-fails"
stub_go build-fails
expect_build_failure 6 "fails when go build fails" "go build ./cmd/forsgren failed"

new_case "render-fails"
stub_go render-fails
expect_build_failure 7 "fails when forsgren render fails" "forsgren render failed"

new_case "no-pages"
stub_go no-pages
expect_build_failure 8 "fails when forsgren render writes no pages" "forsgren render wrote no pages"

new_case "output-is-a-file"
printf 'not a directory\n' > "$CASE_OUTPUT"
expect_build_failure 9 "fails when the output directory is a regular file" "cannot create the output directory"

# Check 18: a page an earlier build left, and no page now renders, is not in
# the new site: the build empties what it owns (the site's .html pages and
# styles.css, and the folders they leave empty) and nothing else.
new_case "stale-pages"
mkdir -p "${CASE_OUTPUT}/old-view"
printf 'left by an earlier build\n' > "${CASE_OUTPUT}/months.html"
printf 'left by an earlier build\n' > "${CASE_OUTPUT}/old-view/index.html"
printf 'not the build'"'"'s\n' > "${CASE_OUTPUT}/notes.txt"
run_build
if [[ "$RC" -eq 0 && ! -e "${CASE_OUTPUT}/months.html" && ! -e "${CASE_OUTPUT}/old-view" ]] \
  && [[ -f "${CASE_OUTPUT}/notes.txt" ]] && diff -r -x notes.txt "$HAPPY_OUTPUT" "$CASE_OUTPUT" > /dev/null; then
  pass 18 "a page left by an earlier build is not in the new site, a file the build does not own is kept"
else
  fail_check 18 "a page left by an earlier build is not in the new site (exit ${RC}) — found: $(cd "$CASE_OUTPUT" && find . -type f | LC_ALL=C sort | tr '\n' ' ')"
fi


# The site rendered from the made-up fixture (forsgren#226): the pages the
# browser gate opens for the tables and charts the placeholder build never has.
# Scripts/build_fixture_site.sh; each case its own output and binary directory.
FIXTURE_BUILD="./Scripts/build_fixture_site.sh"
FIXTURE_DIR="Scripts/testdata/fixture_site"

# run_fixture <name> [fixture-dir [script]]: builds the fixture site into
# ${TEMP_ROOT}/<name>/site; sets RC and leaves the output in FIXTURE_LOG.
run_fixture() {
  local root="${TEMP_ROOT}/$1"
  mkdir -p "$root"
  FIXTURE_OUT="${root}/site"
  FIXTURE_LOG="${root}/log"
  set +e
  FORSGREN_BIN_DIR="${root}/bin" FORSGREN_FIXTURE_DIR="${2:-$FIXTURE_DIR}" "${3:-$FIXTURE_BUILD}" "$FIXTURE_OUT" > "$FIXTURE_LOG" 2>&1
  RC=$?
  set -e
}

run_fixture "fixture"
check 20 "builds the site from the fixture" 0 "$RC"
if [[ "$RC" -ne 0 ]]; then cat "$FIXTURE_LOG"; fi
FIXTURE_HAPPY="$FIXTURE_OUT"
FIXTURE_PAGES="$( (find "$FIXTURE_HAPPY" -type f -name '*.html' 2>/dev/null || true) | wc -l | tr -d '[:space:]')"
if [[ "$FIXTURE_PAGES" == "11" ]]; then
  pass 21 "the fixture site has the eleven pages of the manifest"
else
  fail_check 21 "the fixture site has the eleven pages of the manifest — found ${FIXTURE_PAGES}"
fi

if [[ -f "${FIXTURE_HAPPY}/history.html" ]] && grep -qF '<svg' "${FIXTURE_HAPPY}/history.html" \
  && grep -qF 'role="img"' "${FIXTURE_HAPPY}/history.html" && ! grep -qF 'No history to show yet' "${FIXTURE_HAPPY}/history.html"; then
  pass 22 "history.html has its charts and not the no-history message"
else
  fail_check 22 "history.html has its charts and not the no-history message"
fi

if grep -qF '<td' "${FIXTURE_HAPPY}/days.html" 2>/dev/null && ! grep -qF 'No issues were opened' "${FIXTURE_HAPPY}/days.html" \
  && grep -qF '<td' "${FIXTURE_HAPPY}/issues.html" 2>/dev/null && ! grep -qF 'No issues were opened' "${FIXTURE_HAPPY}/issues.html"; then
  pass 23 "days.html and issues.html have rows"
else
  fail_check 23 "days.html and issues.html have rows"
fi

if grep -qF 'Acme Shop' "${FIXTURE_HAPPY}/index.html" 2>/dev/null && grep -qF 'Acme Tools' "${FIXTURE_HAPPY}/index.html"; then
  pass 24 "index.html has the table of both made-up projects"
else
  fail_check 24 "index.html has the table of both made-up projects"
fi

# 31: the TBD page (forsgren#253) has a Mainline Interval row for a project, not
# the no-data line: the fixture has commits deployed in the last 30 days.
if [[ -f "${FIXTURE_HAPPY}/tbd.html" ]] && grep -qF '<th scope="row">Acme Shop</th>' "${FIXTURE_HAPPY}/tbd.html" \
  && grep -qE '<td>[^<-][^<]* ± [^<]* \([0-9]+\) · median [^<]*</td>' "${FIXTURE_HAPPY}/tbd.html" \
  && ! grep -qF 'No commits have been collected yet' "${FIXTURE_HAPPY}/tbd.html"; then
  pass 31 "tbd.html has a Mainline Interval row and not the no-data line"
else
  fail_check 31 "tbd.html has a Mainline Interval row and not the no-data line"
fi

# 34: the TBD page has a Mainline Lead Time with pull requests (forsgren#350,
# decision #336): the fixture's made-up pulls.csv, its long notes included, so
# the browser gate opens the cell with data and not 'not collected yet'.
if grep -qE '<td>[^<]* pull requests merged within 24 hours of their first commit[^<]*bot pull requests not counted[^<]*</td>' "${FIXTURE_HAPPY}/tbd.html" 2>/dev/null \
  && ! grep -qF 'No pull requests have been collected yet' "${FIXTURE_HAPPY}/tbd.html"; then
  pass 34 "tbd.html has a Mainline Lead Time with pull requests and not the not-collected line"
else
  fail_check 34 "tbd.html has a Mainline Lead Time with pull requests and not the not-collected line"
fi

run_fixture "fixture-again"
if [[ "$RC" -eq 0 ]] && diff -r "$FIXTURE_HAPPY" "$FIXTURE_OUT" > /dev/null; then
  pass 25 "two fixture builds are byte-identical"
else
  fail_check 25 "two fixture builds are byte-identical — the second (exit ${RC}) differs from the first"
fi

# 26: every repository of the fixture is made up (acme/...), never a real one.
NOT_MADE_UP="$(cd "$FIXTURE_DIR" && {
  awk -F, '!/^#/ && !/^project,/ && !/^repository,/ { print $2 }' data/deployments.csv
  for f in commits failures issues issue_bugs reach pulls; do
    awk -F, '!/^#/ && !/^repository,/ { print $1 }' "data/${f}.csv"
  done
  grep -E '^ +- name: ' forsgren.config.yml | sed 's/^ *- name: //' | grep '/'
} | sort -u | grep -v '^acme/' || true)"
if [[ -z "$NOT_MADE_UP" ]]; then
  pass 26 "every repository of the fixture is a made-up acme/ one"
else
  fail_check 26 "every repository of the fixture is a made-up acme/ one — found: ${NOT_MADE_UP}"
fi

# 27, 28: a fixture that shows no data is red, naming the page. 27 has no
# reach.csv (every row unread, so no history column), 28 no issues.csv, 32 no
# commits.csv (no Mainline Interval, forsgren#253), 35 no pulls.csv (no
# Mainline Lead Time, forsgren#350).
for dropped in "27:reach:history.html shows no chart" "28:issues:days.html shows no rows" \
  "32:commits:tbd.html shows no Mainline Interval" "35:pulls:tbd.html shows no Mainline Lead Time"; do
  number="${dropped%%:*}"
  rest="${dropped#*:}"
  file="${rest%%:*}"
  reason="${rest#*:}"
  rm -rf "${TEMP_ROOT}/fx-${file}"
  mkdir -p "${TEMP_ROOT}/fx-${file}"
  cp -R "$FIXTURE_DIR"/. "${TEMP_ROOT}/fx-${file}/"
  rm -f "${TEMP_ROOT}/fx-${file}/data/${file}.csv"
  run_fixture "fixture-no-${file}" "${TEMP_ROOT}/fx-${file}"
  if [[ "$RC" -eq 1 ]] && grep -qF -- "$reason" "$FIXTURE_LOG"; then
    pass "$number" "a fixture without ${file}.csv is red: ${reason}"
  else
    fail_check "$number" "a fixture without ${file}.csv is red: ${reason} — exit ${RC}: $(cat "$FIXTURE_LOG")"
  fi
done

# 29: a fixture without its config is red, naming it.
run_fixture "fixture-no-config" "${TEMP_ROOT}/nowhere"
if [[ "$RC" -eq 1 ]] && grep -qF 'forsgren.config.yml is missing' "$FIXTURE_LOG"; then
  pass 29 "a fixture without a config is red"
else
  fail_check 29 "a fixture without a config is red — exit ${RC}: $(cat "$FIXTURE_LOG")"
fi

# 30: mutation proof. The data check removed from a copy of the script, run with
# the stub go that copies the binary case 20 built: the fixture of case 27
# (no history to show) turns green, so case 27 was red BECAUSE of the check.
MUTANT_ROOT="${TEMP_ROOT}/mutant"
mkdir -p "${MUTANT_ROOT}/Scripts"
sed 's/^if ! history_shows_chart; then/if false; then/' "$FIXTURE_BUILD" > "${MUTANT_ROOT}/Scripts/build_fixture_site.sh"
chmod +x "${MUTANT_ROOT}/Scripts/build_fixture_site.sh"
if cmp -s "$FIXTURE_BUILD" "${MUTANT_ROOT}/Scripts/build_fixture_site.sh"; then
  fail_check 30 "mutation proof: the mutation changed nothing, the proof would be vacuous"
else
  mkdir -p "${TEMP_ROOT}/mutant-out"
  set +e
  PATH="${STUB_GO_DIR}:$PATH" STUB_GO_MODE=prebuilt STUB_PREBUILT="${TEMP_ROOT}/fixture/bin/forsgren" \
    FORSGREN_BIN_DIR="${TEMP_ROOT}/mutant-out/bin" FORSGREN_FIXTURE_DIR="$(cd "${TEMP_ROOT}/fx-reach" && pwd)" \
    "${MUTANT_ROOT}/Scripts/build_fixture_site.sh" "${TEMP_ROOT}/mutant-out/site" > "${TEMP_ROOT}/mutant-out/log" 2>&1
  RC=$?
  set -e
  check 30 "mutation proof: without the data check the fixture with no history is green" 0 "$RC"
fi

# 33: mutation proof for the TBD check (forsgren#253), as case 30: the check
# removed from a copy of the script, the fixture of case 32 (no commits) turns
# green, so case 32 was red BECAUSE of the check.
MUTANT_TBD="${TEMP_ROOT}/mutant-tbd"
mkdir -p "${MUTANT_TBD}/Scripts"
sed 's/^if ! tbd_shows_interval; then/if false; then/' "$FIXTURE_BUILD" > "${MUTANT_TBD}/Scripts/build_fixture_site.sh"
chmod +x "${MUTANT_TBD}/Scripts/build_fixture_site.sh"
if cmp -s "$FIXTURE_BUILD" "${MUTANT_TBD}/Scripts/build_fixture_site.sh"; then
  fail_check 33 "mutation proof: the mutation changed nothing, the proof would be vacuous"
else
  set +e
  PATH="${STUB_GO_DIR}:$PATH" STUB_GO_MODE=prebuilt STUB_PREBUILT="${TEMP_ROOT}/fixture/bin/forsgren" \
    FORSGREN_BIN_DIR="${MUTANT_TBD}/bin" FORSGREN_FIXTURE_DIR="$(cd "${TEMP_ROOT}/fx-commits" && pwd)" \
    "${MUTANT_TBD}/Scripts/build_fixture_site.sh" "${MUTANT_TBD}/site" > "${MUTANT_TBD}/log" 2>&1
  RC=$?
  set -e
  check 33 "mutation proof: without the TBD check the fixture with no commits is green" 0 "$RC"
fi

# 36: mutation proof for the lead-time check (forsgren#350), as case 33: the
# fixture of case 35 (no pulls) turns green without it.
MUTANT_LEAD="${TEMP_ROOT}/mutant-lead"
mkdir -p "${MUTANT_LEAD}/Scripts"
sed 's/^if ! tbd_shows_lead_time; then/if false; then/' "$FIXTURE_BUILD" > "${MUTANT_LEAD}/Scripts/build_fixture_site.sh"
chmod +x "${MUTANT_LEAD}/Scripts/build_fixture_site.sh"
if cmp -s "$FIXTURE_BUILD" "${MUTANT_LEAD}/Scripts/build_fixture_site.sh"; then
  fail_check 36 "mutation proof: the mutation changed nothing, the proof would be vacuous"
else
  set +e
  PATH="${STUB_GO_DIR}:$PATH" STUB_GO_MODE=prebuilt STUB_PREBUILT="${TEMP_ROOT}/fixture/bin/forsgren" \
    FORSGREN_BIN_DIR="${MUTANT_LEAD}/bin" FORSGREN_FIXTURE_DIR="$(cd "${TEMP_ROOT}/fx-pulls" && pwd)" \
    "${MUTANT_LEAD}/Scripts/build_fixture_site.sh" "${MUTANT_LEAD}/site" > "${MUTANT_LEAD}/log" 2>&1
  RC=$?
  set -e
  check 36 "mutation proof: without the lead-time check the fixture with no pulls is green" 0 "$RC"
fi

FOUND_FAILED_SINKS=""
for failed_sink in $FAILED_SINKS; do
  if [[ -e "$failed_sink" ]]; then
    FOUND_FAILED_SINKS="${FOUND_FAILED_SINKS} ${failed_sink} ($(cat "$failed_sink" 2>/dev/null || true))"
  fi
done
if [[ -z "$FOUND_FAILED_SINKS" ]]; then
  pass 10 "writes no page-count sink when the build fails (cases 6 to 9)"
else
  fail_check 10 "writes no page-count sink when the build fails — found:${FOUND_FAILED_SINKS}"
fi

REAL_SINK_WRITTEN="$(find "$REAL_PAGE_COUNT_FILE" -newer "$BEFORE_FIRST_BUILD" 2>/dev/null || true)"
if [[ -z "$REAL_SINK_WRITTEN" ]]; then
  pass 11 "never writes the real repository sink ${REAL_PAGE_COUNT_FILE}"
else
  fail_check 11 "never writes the real repository sink ${REAL_PAGE_COUNT_FILE} — this fixture run wrote it"
fi

COMPLETED=1

if [[ "$FAILURES" -ne 0 ]]; then
  echo ""
  echo "❌ FAIL: test_build_site v${VERSION} — ${FAILURES} failure(s)"
  exit 1
fi

echo ""
echo "✅ test_build_site v${VERSION}"
