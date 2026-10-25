#!/usr/bin/env bash
# Scripts/build_fixture_site.sh (forsgren#226)
#
# Builds the site as forsgren renders it WITH data, from the made-up fixture
# in Scripts/testdata/fixture_site/, for the gates that open pages in a
# browser. Scripts/build_site.sh renders the site without a config or history,
# so its History page shows only "No history to show yet" and its Daily and
# Issues pages no rows: their tables and charts were never opened by the
# browser gate. This site has them.
#
# The fixture is a config (two made-up projects, acme/api, acme/ios-app and
# acme/cli) and the files `forsgren collect` keeps beside the history
# (deployments, commits, failures, issues, issue bugs, reach and merged pull
# requests, forsgren#350, decision #336), all in the
# formats of internal/history. Nothing is read from GitHub or from an
# installation's data. The render time is pinned (SOURCE_DATE_EPOCH, the
# moment of the golden files, 2026-10-03 12:00 UTC), so two builds are
# byte-identical.
#
# After the render the script checks that the pages it exists for carry data,
# and is red when they do not: the History page has a chart, the Daily and
# Issues pages have rows, and the TBD page has a Mainline Interval row and a
# PR Lead Time with pull requests. A fixture that stopped showing data would otherwise
# let the browser gate go back to checking the placeholder.
#
# Usage: Scripts/build_fixture_site.sh [out-dir]   (default .build/site-fixture)
#
# FORSGREN_BIN_DIR moves the compiled binary (default .build/bin);
# FORSGREN_FIXTURE_DIR names another fixture (default
# Scripts/testdata/fixture_site), for Scripts/test_build_site.sh.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

OUTPUT_DIR="${1:-.build/site-fixture}"
BIN_DIR="${FORSGREN_BIN_DIR:-.build/bin}"
BIN="${BIN_DIR}/forsgren"
FIXTURE="${FORSGREN_FIXTURE_DIR:-Scripts/testdata/fixture_site}"
PINNED_EPOCH=1791028800

# fail <reason> — prints why the build failed and stops it.
fail() {
  echo "❌ build-fixture-site: $1" >&2
  exit 1
}

# On bash 3.2 an abort (an unbound variable under set -eu) ends a script with
# an EXIT trap with status 0. COMPLETED, set as the very last statement, is the
# only way out with 0 (forsgren#137, Scripts/check_exit_trap_completion.sh).
COMPLETED=0
STAGE=""
finish() {
  local rc=$?
  if [[ -n "$STAGE" ]]; then rm -rf "$STAGE"; fi
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: build_fixture_site.sh aborted before completing (COMPLETED was never set)" >&2
    exit 1
  fi
}
trap finish EXIT

case "$OUTPUT_DIR" in
  "" | "/" | "." | "..") fail "refusing to replace the output directory '${OUTPUT_DIR}'" ;;
esac
[[ -f "${FIXTURE}/forsgren.config.yml" ]] || fail "the fixture config ${FIXTURE}/forsgren.config.yml is missing"
[[ -f "${FIXTURE}/data/deployments.csv" ]] || fail "the fixture history ${FIXTURE}/data/deployments.csv is missing"

mkdir -p "$BIN_DIR"
# -buildvcs=false: a release build's footer, as Scripts/build_site.sh.
go build -o "$BIN" -buildvcs=false ./cmd/forsgren || fail "go build ./cmd/forsgren failed"

STAGE="$(mktemp -d)"
SOURCE_DATE_EPOCH="$PINNED_EPOCH" "$BIN" render --out "$STAGE" \
  --config "${FIXTURE}/forsgren.config.yml" --data "${FIXTURE}/data/deployments.csv" > /dev/null \
  || fail "forsgren render failed"

# The pages the fixture exists for must show data.
history_shows_chart() {
  [[ -f "${STAGE}/history.html" ]] && ! grep -qF 'No history to show yet' "${STAGE}/history.html" \
    && grep -qF '<svg' "${STAGE}/history.html"
}
if ! history_shows_chart; then
  fail "history.html shows no chart: the fixture has no history the page can show"
fi
# The TBD page has a Mainline Interval row with a mean, not only dashes
# (forsgren#253; the fixture config sets tbd_figures: all, so three cells since
# forsgren#423), found at the start of its row, right after the project, since
# the Mainline Interval group comes first (forsgren#418).
tbd_shows_interval() {
  [[ -f "${STAGE}/tbd.html" ]] && tr -d '\n' <"${STAGE}/tbd.html" \
    | grep -qE '<th scope="row">[^<]*</th> *<td[^>]*>[^<-][^<]*(<span[^>]*>[^<]*</span>[^<]*)*</td> *(<td>[^<]*</td> *){2}<td>[^<]*</td>'
}
if ! tbd_shows_interval; then
  fail "tbd.html shows no Mainline Interval: the fixture has no commits the page can show"
fi
# The TBD page has a PR Lead Time mean with a duration and the note on the bot
# pull requests the fixture has, not 'not collected yet' (forsgren#350, decision
# #336; the cell has no sentence since forsgren#423).
tbd_shows_lead_time() {
  grep -qE '<td aria-describedby="[^"]*tbd-note-5[^"]*">[0-9][^<]*(<span[^>]*>[^<]*</span>[^<]*)*</td>' "${STAGE}/tbd.html" \
    && ! grep -qF 'No pull requests have been collected yet' "${STAGE}/tbd.html"
}
if ! tbd_shows_lead_time; then
  fail "tbd.html shows no Mainline Lead Time: the fixture has no pull requests the page can show"
fi
for page in days issues; do
  if [[ ! -f "${STAGE}/${page}.html" ]] || grep -qF 'No issues were opened' "${STAGE}/${page}.html" \
    || ! grep -qF '<td' "${STAGE}/${page}.html"; then
    fail "${page}.html shows no rows: the fixture has no issues the page can show"
  fi
done

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR" || fail "cannot create the output directory ${OUTPUT_DIR}"
cp -R "$STAGE"/. "$OUTPUT_DIR"/ || fail "cannot copy the site into ${OUTPUT_DIR}"

echo "✅ build_fixture_site: $(find "$OUTPUT_DIR" -type f -name '*.html' | wc -l | tr -d '[:space:]') pages rendered from ${FIXTURE}"
COMPLETED=1
