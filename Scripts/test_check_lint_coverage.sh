#!/usr/bin/env bash
# canon: test_check_lint_coverage v1
set -euo pipefail

cd "$(dirname "$0")/.."

# Fixture for check_lint_coverage.sh — unit 394.
#
# Fake linters drive every mode, the way the estate's npm-audit fixture does.
# The real binaries are not used: this asserts what the CHECK does with a
# linter's answer, and an unexercised mode is broken until a fixture drives it.
#
# The case that matters is "linter scanned fewer files than ship" — a real
# htmlhint being green about a file it never opened looks exactly like a
# htmlhint that found nothing wrong.

CHECK="./Scripts/check_lint_coverage.sh"
REAL_CHECK="$(pwd)/Scripts/check_lint_coverage.sh"
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
  HTML_N="$1" CSS_N="$2" \
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
HTML_N=2 CSS_N=1 HTMLHINT_CMD="$bin/htmlhint" STYLELINT_CMD="$bin/stylelint" \
  "$CHECK" "$TMP/does-not-exist" >/dev/null 2>&1
RC=$?
set -e
check "exits 2 (tooling) on a missing site dir, never 0" 2 "$RC"

empty="$TMP/empty"; mkdir -p "$empty"
set +e
HTML_N=0 CSS_N=0 HTMLHINT_CMD="$bin/htmlhint" STYLELINT_CMD="$bin/stylelint" \
  "$CHECK" "$empty" >/dev/null 2>&1
RC=$?
set -e
check "exits 2 on a site with nothing to lint, never a clean 0" 2 "$RC"

# --- No npx, no fallback. A sandbox repository holds a
# copy of the check, the settings and fake linters in node_modules/.bin, and a
# stub `npx` first on PATH that records any call and answers like htmlhint.
# *_CMD is NOT set: this is the default path the sfl and CI gates take.
new_sandbox() { # <check-script>; sets SB
  SB="$(mktemp -d "${TMP}/sb.XXXXXX")"
  mkdir -p "$SB/Scripts" "$SB/node_modules/.bin" "$SB/Site" "$SB/fakebin"
  cp "$1" "$SB/Scripts/check_lint_coverage.sh"
  cp Scripts/lint_json_count.py Scripts/lib_site_settings.sh "$SB/Scripts/"
  printf 'site_dir=Site\nhtml_dupl_target=Site\nhtml_dupl_ceiling=1.0\nrequired_pages_manifest=m.json\n' > "$SB/Scripts/site_settings.txt"
  printf '{}\n' > "$SB/.htmlhintrc"
  cp "$site"/* "$SB/Site/"
  cp "$bin/htmlhint" "$SB/node_modules/.bin/htmlhint"
  cp "$bin/stylelint" "$SB/node_modules/.bin/stylelint"
  chmod +x "$SB/Scripts/check_lint_coverage.sh" "$SB/node_modules/.bin/"*
  cat > "$SB/fakebin/npx" <<'NPX'
#!/usr/bin/env bash
echo "npx $*" >> "$NPX_LOG"
echo "Scanned 2 files, no errors found (1 ms)."
NPX
  chmod +x "$SB/fakebin/npx"
  NPX_LOG="$SB/npx.log"; : > "$NPX_LOG"
}
sandbox_run() { # [site-arg]; sets RC and OUT
  set +e
  OUT="$(cd "$SB" && env -u HTMLHINT_CMD -u STYLELINT_CMD -u HTMLHINT_ARGS \
    PATH="$SB/fakebin:$PATH" NPX_LOG="$NPX_LOG" HTML_N=2 CSS_N=1 \
    ./Scripts/check_lint_coverage.sh "$@" 2>&1)"
  RC=$?
  set -e
}
npx_calls() { grep -c . "$NPX_LOG" || true; }

# case_default: the default path uses node_modules/.bin, takes the site dir from
# the settings, and never calls npx. Prints one line per problem.
case_default() {
  new_sandbox "$1"
  sandbox_run
  [[ "$RC" -eq 0 ]] || echo "default run exited ${RC}, want 0: ${OUT}"
  [[ "$(npx_calls)" -eq 0 ]] || echo "the gate called npx: $(cat "$NPX_LOG")"
  grep -qF 'html  2/2 scanned' <<< "$OUT" || echo "the site_dir from site_settings.txt was not used: ${OUT}"
  return 0
}

# case_missing_binary: a missing node_modules binary is red (exit 2) and npx
# is not called to make up for it.
case_missing_binary() {
  local tool
  for tool in htmlhint stylelint; do
    new_sandbox "$1"
    rm -f "$SB/node_modules/.bin/${tool}"
    sandbox_run
    [[ "$RC" -eq 2 ]] || echo "missing ${tool}: exit ${RC}, want 2: ${OUT}"
    [[ "$(npx_calls)" -eq 0 ]] || echo "missing ${tool}: the gate fell back to npx: $(cat "$NPX_LOG")"
    grep -qF "no fallback" <<< "$OUT" || echo "missing ${tool}: the message does not say there is no fallback"
  done
  return 0
}

# The script text carries no npx and no pinned linter version.
case_no_npx_text() {
  grep -vE '^[[:space:]]*#' "$1" | grep -nE 'npx|@[0-9]+\.[0-9]+\.[0-9]+' || true
}

problems="$(case_default "$REAL_CHECK")"
if [[ -n "$problems" ]]; then echo "  ❌ default path: ${problems}"; failures=$((failures+1)); else echo "  ✅ the default path uses node_modules/.bin, reads site_dir from settings and never calls npx"; fi
problems="$(case_missing_binary "$REAL_CHECK")"
if [[ -n "$problems" ]]; then echo "  ❌ missing binary: ${problems}"; failures=$((failures+1)); else echo "  ✅ a missing node_modules binary is exit 2 with no npx fallback"; fi
problems="$(case_no_npx_text "$REAL_CHECK")"
if [[ -n "$problems" ]]; then echo "  ❌ the script names npx or a pinned version: ${problems}"; failures=$((failures+1)); else echo "  ✅ the script names no npx and no pinned version"; fi

# Mutation: a copy with the npx fallback put back must fail the cases.
mutant="$TMP/check_with_npx.sh"
sed -E $'s|^(HTMLHINT_CMD="\$\{HTMLHINT_CMD:-node_modules/.bin/htmlhint\}")$|\\1\\n[ -x "$HTMLHINT_CMD" ] \|\| HTMLHINT_CMD="$(command -v npx)"|' "$REAL_CHECK" > "$mutant"
if cmp -s "$REAL_CHECK" "$mutant"; then
  echo "  ❌ the npx-fallback mutation changed nothing"; failures=$((failures+1))
else
  problems="$(case_missing_binary "$mutant")"
  if [[ -n "$problems" ]]; then echo "  ✅ mutation: a check with the npx fallback put back is caught"; else echo "  ❌ mutation: the npx fallback was NOT caught"; failures=$((failures+1)); fi
fi

COMPLETED=1

if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_lint_coverage contract"
  exit 1
fi
echo ""
echo "✅ test_check_lint_coverage"
