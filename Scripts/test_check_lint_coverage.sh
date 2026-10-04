#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Fixture for check_lint_coverage.sh — unit 394.
#
# Fake linters drive every mode, the way another estate repository's npm-audit fixture does.
# The real binaries are not used: this asserts what the CHECK does with a
# linter's answer, and an unexercised mode is broken until a fixture drives it.
#
# The case that matters is "linter scanned fewer files than ship" — a real
# htmlhint being green about a file it never opened looks exactly like a
# htmlhint that found nothing wrong.

CHECK="./Scripts/check_lint_coverage.sh"
TMP="$(mktemp -d)"

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: lint-coverage fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap 'rm -rf "$TMP"; finish' EXIT

failures=0
check() { # <name> <expected-rc> <actual-rc>
  if [[ "$2" == "$3" ]]; then echo "  ✅ $1"; else echo "  ❌ $1 — expected exit $2, got $3"; failures=$((failures+1)); fi
}

site="$TMP/site"
mkdir -p "$site"
printf '<html></html>\n' > "$site/index.html"
printf '<html></html>\n' > "$site/two.html"
printf 'body{}\n'        > "$site/a.css"

bin="$TMP/bin"; mkdir -p "$bin"
# HTML_N / CSS_N decide what the fakes claim to have seen.
cat > "$bin/htmlhint" <<'FAKE'
#!/usr/bin/env bash
echo "Scanned ${HTML_N} files, no errors found (1 ms)."
FAKE
cat > "$bin/stylelint" <<'FAKE'
#!/usr/bin/env bash
python3 -c "import json,sys; print(json.dumps([{'source':'f%d' % i} for i in range(int(sys.argv[1]))]))" "$CSS_N"
FAKE
# The REAL stylelint writes its JSON to stderr (measured 2026-08-22). The
# original fake wrote to stdout, so the fixture proved the check's LOGIC and
# said nothing about its INTEGRATION — every case passed while the check was
# blind against the actual tool. This fake reproduces the real behaviour.
cat > "$bin/stylelint_stderr" <<'FAKE'
#!/usr/bin/env bash
python3 -c "import json,sys; print(json.dumps([{'source':'f%d' % i} for i in range(int(sys.argv[1]))]))" "$CSS_N" >&2
FAKE
cat > "$bin/htmlhint_silent" <<'FAKE'
#!/usr/bin/env bash
echo "no count line here"
FAKE
chmod +x "$bin"/*

run() { # <html_n> <css_n> [htmlhint-binary] [stylelint-binary]
  set +e
  HTML_N="$1" CSS_N="$2" HTMLHINT_ARGS="" \
    HTMLHINT_CMD="${3:-$bin/htmlhint}" STYLELINT_CMD="${4:-$bin/stylelint}" \
    "$CHECK" "$site" >/dev/null 2>&1
  RC=$?
  set -e
}

echo "test_check_lint_coverage"

run 2 1;  check "accepts linters that opened every shipped file" 0 "$RC"
run 1 1;  check "rejects htmlhint scanning fewer files than ship" 1 "$RC"
run 3 1;  check "rejects htmlhint scanning MORE than ship (wrong glob reach)" 1 "$RC"
run 2 0;  check "rejects stylelint opening no css at all" 1 "$RC"
run 2 2;  check "rejects stylelint opening more css than ship" 1 "$RC"
run 2 1 "$bin/htmlhint" "$bin/stylelint_stderr"
          check "accepts stylelint JSON arriving on stderr (what the real tool does)" 0 "$RC"

run 2 1 "$bin/htmlhint_silent"
          check "rejects a linter whose output carries no count — blind, not clean" 1 "$RC"

set +e
HTML_N=2 CSS_N=1 HTMLHINT_ARGS="" HTMLHINT_CMD="$bin/htmlhint" STYLELINT_CMD="$bin/stylelint" \
  "$CHECK" "$TMP/does-not-exist" >/dev/null 2>&1
RC=$?
set -e
check "exits 2 (tooling) on a missing site dir, never 0" 2 "$RC"

empty="$TMP/empty"; mkdir -p "$empty"
set +e
HTML_N=0 CSS_N=0 HTMLHINT_ARGS="" HTMLHINT_CMD="$bin/htmlhint" STYLELINT_CMD="$bin/stylelint" \
  "$CHECK" "$empty" >/dev/null 2>&1
RC=$?
set -e
check "exits 2 on a site with nothing to lint, never a clean 0" 2 "$RC"

COMPLETED=1

if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_lint_coverage contract"
  exit 1
fi
echo ""
echo "✅ test_check_lint_coverage"
