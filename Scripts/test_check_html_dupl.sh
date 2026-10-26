#!/usr/bin/env bash
# canon: test_check_html_dupl v3
# Scripts/test_check_html_dupl.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh

# Fixture for check_html_dupl.sh — unit 397, the canon version.
#
# A ratchet's essential contract is that duplication above its ceiling fails.
# That contract is tested with a synthetic duplicated fixture, so it stays
# testable whatever the real site measures.
#
# Uses the REAL pinned jscpd (node_modules/.bin, installed by `npm ci`) rather
# than a fake: the thing under test is largely how this script reads jscpd's
# output, and a fake can silently diverge from the actual tool.
#
# What the canon pins:
#   - the target and the ceiling come from Scripts/site_settings.txt when no
#     argument is given, and the arguments override them. A lowered ceiling in
#     the settings turns the real site red; the settings' target is the one
#     measured;
#   - zero files scanned is exit 2 NAMING that nothing was scanned (mutation
#     proof B: without the zero-sources check the reason is no longer named);
#   - a missing node_modules/.bin/jscpd is exit 2, and a stub `npx` first on
#     PATH is never called: there is no fallback;
#   - an over-ceiling red shows the gate's own ceiling and verdict, never
#     jscpd's "over threshold (0%)" line (the -t 0 it runs with is only there
#     to print the number), and keeps the measured percentage (mutation proof D);
#   - a jscpd failure for any other reason (a crash, exit not 0 or 1) shows
#     jscpd's own error and is exit 2 (mutation proof E);
#   - mutation proof A: the duplicated fixture turns green against a copy whose
#     ceiling comparison always says "under";
#   - mutation proof C: the lowered-settings-ceiling case turns green against a
#     copy with the ceiling hard-coded.
# A repository with a second target keeps its own wrapper and its own cases for
# it, outside this canon file.

CHECK="./Scripts/check_html_dupl.sh"
REPO_ROOT="$(pwd)"
ZERO_REASON="scanned 0 .html files under"

TMP="$(mktemp -d)"
COMPLETED=0
finish() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: html-dupl fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap finish EXIT

failures=0

# check <name> <expected-rc> <actual-rc>
check() {
  if [[ "$2" == "$3" ]]; then
    echo "  ✅ $1"
  else
    echo "  ❌ $1 — expected exit $2, got $3"
    failures=$((failures + 1))
  fi
}

# check_says <name> <needle> — the last run's output carries needle.
check_says() {
  if grep -Fq -- "$2" <<< "$OUT"; then
    echo "  ✅ $1"
  else
    echo "  ❌ $1 — output does not carry '$2'"
    echo "     got: $(head -c 600 <<< "$OUT")"
    failures=$((failures + 1))
  fi
}

# check_not_says <name> <needle> — the last run's output does not carry needle.
check_not_says() {
  if grep -Fq -- "$2" <<< "$OUT"; then
    echo "  ❌ $1 — output carries '$2'"
    failures=$((failures + 1))
  else
    echo "  ✅ $1"
  fi
}

run() {
  set +e
  OUT="$("$CHECK" "$@" 2>&1)"
  RC=$?
  set -e
}

# new_root <name> <gate> <target-dir-name> <ceiling> [no-jscpd] — a throwaway
# repository root holding a copy of the gate, the settings lib, a
# site_settings.txt naming <target-dir-name> and <ceiling>, and (unless
# no-jscpd) a link to this repository's node_modules. Sets ROOT.
new_root() {
  ROOT="${TMP}/root-$1"
  mkdir -p "${ROOT}/Scripts"
  cp "$2" "${ROOT}/Scripts/check_html_dupl.sh"
  chmod +x "${ROOT}/Scripts/check_html_dupl.sh"
  cp Scripts/lib_site_settings.sh "${ROOT}/Scripts/"
  printf 'site_dir=%s\nhtml_dupl_target=%s\nhtml_dupl_ceiling=%s\nrequired_pages_manifest=m.json\n' "$3" "$3" "$4" > "${ROOT}/Scripts/site_settings.txt"
  [[ "${5:-}" == "no-jscpd" ]] || ln -s "${REPO_ROOT}/node_modules" "${ROOT}/node_modules"
}

# run_root <args...> — runs the gate of $ROOT with a stub npx first on PATH
# that records any call in $ROOT/npx.log.
run_root() {
  mkdir -p "${ROOT}/fakebin"
  cat > "${ROOT}/fakebin/npx" <<'NPX'
#!/usr/bin/env bash
echo "npx $*" >> "$NPX_LOG"
exit 0
NPX
  chmod +x "${ROOT}/fakebin/npx"
  : > "${ROOT}/npx.log"
  set +e
  OUT="$(PATH="${ROOT}/fakebin:${PATH}" NPX_LOG="${ROOT}/npx.log" "${ROOT}/Scripts/check_html_dupl.sh" "$@" 2>&1)"
  RC=$?
  set -e
}

make_duplicate_fixture() {
  local fixture_dir="$1"

  mkdir -p "$fixture_dir"

  cat > "${fixture_dir}/first.html" <<'HTML'
<!doctype html>
<html lang="en">
  <body>
    <main>
      <section>
        <h1>Duplicated fixture</h1>
        <p>This deliberately repeated block exists to prove the duplication gate can fail.</p>
        <p>The fixture needs enough repeated tokens and lines for jscpd to identify the clone.</p>
        <p>It is synthetic and does not establish the production duplication ceiling.</p>
        <p>The same complete block appears in a second HTML file below.</p>
        <p>This line adds enough material for the minimum token threshold used by the gate.</p>
        <p>This line also belongs to the deliberate duplicated test content.</p>
        <p>The ratchet must reject this fixture when its ceiling is zero percent.</p>
        <p>A passing result here would mean the duplication checker cannot detect duplication.</p>
        <p>That would make the production ratchet untrustworthy even if the pages are clean.</p>
        <p>The test therefore exercises the real pinned jscpd rather than a fake implementation.</p>
        <p>Both files intentionally contain this same sequence of markup and textual content.</p>
      </section>
    </main>
  </body>
</html>
HTML

  cp "${fixture_dir}/first.html" "${fixture_dir}/second.html"
}

echo "test_check_html_dupl"

if [[ ! -x node_modules/.bin/jscpd ]]; then
  echo "  ❌ node_modules/.bin/jscpd is missing — run npm ci; this gate cannot be exercised without the pinned jscpd"
  COMPLETED=1
  exit 1
fi

FIXTURE_DIR="${TMP}/duplicated"
make_duplicate_fixture "$FIXTURE_DIR"

# --- the arguments ----------------------------------------------------------
run "$FIXTURE_DIR" 99
check "passes under a deliberately loose ceiling" 0 "$RC"
if grep -qE 'html duplication [0-9]+(\.[0-9]+)?%' <<< "$OUT"; then
  echo "  ✅ reports the measured percentage on a passing run"
else
  echo "  ❌ a passing run does not print the number — a ratchet nobody can read is just a threshold"
  failures=$((failures + 1))
fi

run "$FIXTURE_DIR" 0.00
check "FAILS when deliberate duplication exceeds the ceiling" 1 "$RC"
check_says "the red names the ceiling it exceeded" "EXCEEDS the 0.00% ceiling"

# jscpd's own line reads as if the gate demanded 0%; the gate's ceiling is
# the real bar, so that line is not shown and the number is kept.
run "$FIXTURE_DIR" 7.5
check "FAILS over a non-zero ceiling" 1 "$RC"
check_not_says "the red does not show jscpd's over threshold (0%) line" "over threshold (0%)"
check_says "the red names the real ceiling" "EXCEEDS the 7.5% ceiling"
if grep -qE 'measured [0-9]+(\.[0-9]+)?%' <<< "$OUT"; then
  echo "  ✅ the red keeps the measured percentage on a line of its own"
else
  echo "  ❌ the red lost the measured percentage"
  failures=$((failures + 1))
fi

run does-not-exist 99
check "exits 2 on a missing target dir, never 0" 2 "$RC"

# --- zero files is red, and says so -----------------------------------------
EMPTY_DIR="${TMP}/no-html"
mkdir -p "$EMPTY_DIR"
printf 'body {\n  margin: 0;\n}\n' > "${EMPTY_DIR}/styles.css"
run "$EMPTY_DIR" 99
check "exits 2 on a directory with no .html in it, never 0" 2 "$RC"
check_says "the zero red names that nothing was scanned" "$ZERO_REASON"

# --- the settings: the real site, at the recorded ceiling -------------------
run
check "the default run (target and ceiling from site_settings.txt) passes" 0 "$RC"
WANT_TARGET="$(sed -n 's/^html_dupl_target=//p' Scripts/site_settings.txt)"
check_says "the default target is the settings' html_dupl_target" "in ${WANT_TARGET} (ceiling"

# A lowered ceiling in the settings turns the real site red. The real target is
# copied into a throwaway root so the real settings file stays untouched.
new_root lowered "$CHECK" "$WANT_TARGET" 0.1
mkdir -p "$(dirname "${ROOT}/${WANT_TARGET}")"  # a nested target such as internal/page/templates
cp -R "$WANT_TARGET" "${ROOT}/${WANT_TARGET}"
# A site whose real target measures 0.00% has no ceiling to lower under it, so
# the throwaway copy gets one page twice, a clone, and measures above 0.1.
_first="$(find "${ROOT}/${WANT_TARGET}" -name '*.html' | LC_ALL=C sort | head -1)"
cp "$_first" "${_first%.html}-copy.html"
run_root
check "a lowered ceiling in the settings turns the real site red" 1 "$RC"
check_says "the red quotes the settings' ceiling" "EXCEEDS the 0.1% ceiling"
LOWERED_ROOT="$ROOT"

# The target comes from the settings too: a settings target without .html files
# is the zero red, however clean the real site is.
new_root target "$CHECK" empty 99
mkdir -p "${ROOT}/empty"
cp "${EMPTY_DIR}/styles.css" "${ROOT}/empty/"
run_root
check "the target is read from the settings (an empty one is exit 2)" 2 "$RC"
check_says "the settings' target is the one named" "under empty"

# A missing settings file is exit 2, never a guessed default.
new_root nosettings "$CHECK" "$WANT_TARGET" 99
rm "${ROOT}/Scripts/site_settings.txt"
mkdir -p "$(dirname "${ROOT}/${WANT_TARGET}")"  # a nested target such as internal/page/templates
cp -R "$WANT_TARGET" "${ROOT}/${WANT_TARGET}"
run_root
check "a missing site_settings.txt is exit 2, no guessed default" 2 "$RC"

# --- no jscpd in node_modules: exit 2, and no npx --------------------------
new_root nojscpd "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
run_root dup 99
check "a missing node_modules/.bin/jscpd is exit 2" 2 "$RC"
check_says "the red says to run npm ci" "run npm ci"
if [[ -s "${ROOT}/npx.log" ]]; then
  echo "  ❌ the gate called npx: $(cat "${ROOT}/npx.log")"
  failures=$((failures + 1))
else
  echo "  ✅ the gate never calls npx"
fi
if grep -vE '^[[:space:]]*#' "$CHECK" | has -qE 'npx'; then
  echo "  ❌ the gate's text names npx outside comments"
  failures=$((failures + 1))
else
  echo "  ✅ the gate's text names no npx"
fi

# --- a jscpd failure for another reason still shows its error --------------
new_root crash "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
mkdir -p "${ROOT}/node_modules/.bin"
printf '#!/usr/bin/env bash\necho "jscpd: boom, cannot read config"\nexit 3\n' > "${ROOT}/node_modules/.bin/jscpd"
chmod +x "${ROOT}/node_modules/.bin/jscpd"
run_root dup 99
check "a jscpd crash (exit 3) is exit 2, never 0 or 1" 2 "$RC"
check_says "the crash shows jscpd's own error" "boom, cannot read config"

# --- Mutation proof A: the ceiling comparison is what reds the fixture ------
MUTANT_A="${TMP}/mutant_a.sh"
sed 's/print (a > b) ? 1 : 0/print 0/' "$CHECK" > "$MUTANT_A"
if cmp -s "$CHECK" "$MUTANT_A"; then
  echo "  ❌ mutation proof A: the sed no longer matches the ceiling comparison, so this proof proves nothing"
  failures=$((failures + 1))
else
  new_root mut-a "$MUTANT_A" dup 99
  cp -R "$FIXTURE_DIR" "${ROOT}/dup"
  run_root dup 0.00
  check "mutation proof A: the duplicated fixture turns green when the ceiling comparison always says under" 0 "$RC"
fi

# --- Mutation proof B: a copy WITHOUT the zero-files check ------------------
MUTANT_B="${TMP}/mutant_b.sh"
sed 's/\[ "[$]sources" = "0" \]/false/; s/\[ -z "[$]sources" \] ||/false ||/' "$CHECK" > "$MUTANT_B"
if cmp -s "$CHECK" "$MUTANT_B"; then
  echo "  ❌ mutation proof B: the sed no longer matches the zero-sources check, so this proof proves nothing"
  failures=$((failures + 1))
else
  new_root mut-b "$MUTANT_B" empty 99
  mkdir -p "${ROOT}/empty"
  cp "${EMPTY_DIR}/styles.css" "${ROOT}/empty/"
  run_root
  check_not_says "mutation proof B: without the zero-files check the empty target is no longer named as nothing scanned" "$ZERO_REASON"
fi

# --- Mutation proof C: a copy with the ceiling hard-coded -------------------
MUTANT_C="${TMP}/mutant_c.sh"
sed 's/^  \[ -n "[$]MAX_PCT" \] || MAX_PCT=.*$/  MAX_PCT=99/' "$CHECK" > "$MUTANT_C"
if cmp -s "$CHECK" "$MUTANT_C"; then
  echo "  ❌ mutation proof C: the sed no longer matches the ceiling read, so this proof proves nothing"
  failures=$((failures + 1))
else
  ROOT="$LOWERED_ROOT"
  cp "$MUTANT_C" "${ROOT}/Scripts/check_html_dupl.sh"
  run_root
  check "mutation proof C: the lowered-ceiling case turns green when the ceiling is hard-coded" 0 "$RC"
fi

# --- Mutation proof D: a copy that shows jscpd's output unfiltered ----------
MUTANT_D="${TMP}/mutant_d.sh"
sed "s/^ *shown=.*/  shown=\"\${plain}\"/" "$CHECK" > "$MUTANT_D"
if cmp -s "$CHECK" "$MUTANT_D"; then
  echo "  ❌ mutation proof D: the sed no longer matches the output filter, so this proof proves nothing"
  failures=$((failures + 1))
else
  new_root mut-d "$MUTANT_D" dup 99
  cp -R "$FIXTURE_DIR" "${ROOT}/dup"
  run_root dup 7.5
  check_says "mutation proof D: without the filter jscpd's over threshold (0%) line is shown again" "over threshold (0%)"
fi

# --- Mutation proof E: a copy without the jscpd-failure check ---------------
MUTANT_E="${TMP}/mutant_e.sh"
sed 's/\[ "[$]status" -ne 0 \] &&/false \&\&/' "$CHECK" > "$MUTANT_E"
if cmp -s "$CHECK" "$MUTANT_E"; then
  echo "  ❌ mutation proof E: the sed no longer matches the failure check, so this proof proves nothing"
  failures=$((failures + 1))
else
  new_root mut-e "$MUTANT_E" dup 99 no-jscpd
  cp -R "$FIXTURE_DIR" "${ROOT}/dup"
  mkdir -p "${ROOT}/node_modules/.bin"
  cp "${TMP}/root-crash/node_modules/.bin/jscpd" "${ROOT}/node_modules/.bin/jscpd"
  run_root dup 99
  check_not_says "mutation proof E: without the failure check the crash's error is swallowed" "boom, cannot read config"
fi

COMPLETED=1

if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_html_dupl contract"
  exit 1
fi

echo ""
echo "✅ test_check_html_dupl"
