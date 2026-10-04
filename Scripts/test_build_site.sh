#!/usr/bin/env bash
# Scripts/test_build_site.sh
#
# Fixture for Scripts/build_site.sh. Shape ported from konenki-website's
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
  PATH="$CASE_PATH" STUB_GO_MODE="$CASE_GO_MODE" \
    SITE_PAGE_COUNT_FILE="$CASE_SINK" FORSGREN_BIN_DIR="$CASE_BIN" \
    "$BUILD" "$CASE_OUTPUT" > "$CASE_LOG" 2>&1
  RC=$?
  set -e
}

# A stub `go`, put first on PATH by stub_go. build_site.sh calls
# `go build -o <bin> ./cmd/forsgren`, so <bin> is $3. STUB_GO_MODE picks
# what it does: build-fails exits 1; render-fails and no-pages "build" a
# fake forsgren that exits 1, or exits 0 having written nothing.
STUB_GO_DIR="${TEMP_ROOT}/stub-go"
mkdir -p "$STUB_GO_DIR"
cat > "${STUB_GO_DIR}/go" <<'STUB'
#!/usr/bin/env bash
case "${STUB_GO_MODE:?}" in
  build-fails) echo "stub go: build failed" >&2; exit 1 ;;
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
check_file 3 "styles.css is copied as authored" "$STYLES" "${HAPPY_OUTPUT}/styles.css"

if [[ -f "$HAPPY_SINK" ]] && [[ "$(cat "$HAPPY_SINK")" == "2" ]]; then
  pass 4 "writes the page count (2) to SITE_PAGE_COUNT_FILE"
else
  fail_check 4 "writes the page count (2) to SITE_PAGE_COUNT_FILE — found: $(cat "$HAPPY_SINK" 2>/dev/null || echo MISSING)"
fi

new_case "again"
run_build
if [[ "$RC" -eq 0 ]] && diff -r "$HAPPY_OUTPUT" "$CASE_OUTPUT" > /dev/null; then
  pass 5 "two builds are byte-identical (no timestamp in the page)"
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
