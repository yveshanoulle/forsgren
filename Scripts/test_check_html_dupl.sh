#!/usr/bin/env bash
# canon: test_check_html_dupl v10
# Scripts/test_check_html_dupl.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# Fixture for check_html_dupl.sh — unit 397, the canon version.
#
# A ratchet's essential contract is that duplication above its ceiling fails.
# That contract is tested with a synthetic duplicated fixture, so it stays
# testable whatever the real site measures.
#
# Uses the REAL pinned jscpd (node_modules/.bin, installed by `npm ci`) rather
# than a fake: the thing under test is largely how this script reads jscpd's
# output, and a fake can silently diverge from the actual tool. Only three
# cases use a fake: a crash (fake_jscpd), and a replay of jscpd 5.4.2's run and
# a console that contradicts its report (stub_jscpd), which no real jscpd prints
# on demand.
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
#   - an over-ceiling red shows the gate's own ceiling and verdict, the
#     measured percentage and the clones, never jscpd's "over threshold" line;
#   - the percentage, the file count and the clones come from jscpd's JSON
#     report, never its console text: a stub replaying jscpd 5.4.2's run gates
#     as the installed jscpd does, and a stub whose console text says 0% while
#     its report says 50% is red (mutation proof D: a copy that reads the
#     percentage from the console text turns it green);
#   - a jscpd failure (a crash, any exit but 0) shows jscpd's own error and is
#     exit 2 (mutation proof E);
#   - the OK and red lines name the jscpd that RAN, from its `--version`
#     answer (4.2.4 answers `4.2.4`, 5.4.2 answers `jscpd 5.4.2`); a failing
#     or garbled answer is the label `jscpd@unknown`, never the pin, and the
#     gate still measures (v7);
#   - a jscpd that differs from the pin (4.2.4 installed, 5.4.2 pinned) is
#     labelled 4.2.4 and never fails the gate by itself: that is the npm
#     dependency policy's call (mutation proof G: a copy that labels by the
#     pin names 5.4.2; mutation proof H: a copy that fails on the mismatch is
#     exit 2);
#   - the ceiling form: a repository whose settings lib declares the key
#     family html_dupl_ceiling_jscpd (SITE_SETTINGS_FAMILIES) takes the
#     running major's html_dupl_ceiling_jscpd<major> line, one whose lib does
#     not takes html_dupl_ceiling; both forms are run here with a minimal
#     fixture lib, whatever this repository's own lib says. In the family form
#     an unreadable version or a running major with no line is exit 2;
#   - no jscpd pin readable (devDependencies without jscpd, a package.json
#     that is no JSON, or no package.json at all) is exit 2 naming that, never
#     0 (mutation proof F: with that exit turned into exit 0 the case turns
#     green);
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

# The ceiling form of this repository's settings lib: "family" when it declares
# the key family html_dupl_ceiling_jscpd, "single" otherwise. new_root writes
# its ceiling in that form.
REPO_FORM="$(
  # shellcheck source=Scripts/lib_site_settings.sh
  source Scripts/lib_site_settings.sh
  if [[ " ${SITE_SETTINGS_FAMILIES:-} " == *" html_dupl_ceiling_jscpd "* ]]; then
    echo family
  else
    echo single
  fi
)"

# ceiling_lines <form> <ceiling> — the settings lines of <ceiling> in <form>:
# html_dupl_ceiling=<ceiling>, or one html_dupl_ceiling_jscpd<major>=<ceiling>
# line for every major a fixture's jscpd may report (1 to 9).
ceiling_lines() {
  local m
  if [[ "$1" == "family" ]]; then
    for m in 1 2 3 4 5 6 7 8 9; do printf 'html_dupl_ceiling_jscpd%s=%s\n' "$m" "$2"; done
  else
    printf 'html_dupl_ceiling=%s\n' "$2"
  fi
}

# new_root <name> <gate> <target-dir-name> <ceiling> [no-jscpd] — a throwaway
# repository root holding a copy of the gate, the settings lib, package.json
# (the jscpd pin the gate checks), a site_settings.txt naming <target-dir-name>
# and <ceiling> (in this repository's ceiling form), and (unless
# no-jscpd) a link to this repository's node_modules. Sets ROOT.
new_root() {
  ROOT="${TMP}/root-$1"
  mkdir -p "${ROOT}/Scripts"
  cp "$2" "${ROOT}/Scripts/check_html_dupl.sh"
  chmod +x "${ROOT}/Scripts/check_html_dupl.sh"
  cp Scripts/lib_site_settings.sh "${ROOT}/Scripts/"
  cp package.json "${ROOT}/"
  {
    printf 'site_dir=%s\nhtml_dupl_target=%s\nrequired_pages_manifest=m.json\n' "$3" "$3"
    ceiling_lines "$REPO_FORM" "$4"
  } > "${ROOT}/Scripts/site_settings.txt"
  [[ "${5:-}" == "no-jscpd" ]] || ln -s "${REPO_ROOT}/node_modules" "${ROOT}/node_modules"
}

# form_lib <form> — replaces $ROOT's settings lib with a minimal one of
# <form> ("family" declares SITE_SETTINGS_FAMILIES=html_dupl_ceiling_jscpd,
# "single" declares none), so both ceiling forms run in every repository.
# Its site_settings_get prints the key's value, nothing for an absent key.
form_lib() {
  {
    echo '# fixture settings lib of test_check_html_dupl.sh'
    [[ "$1" == "family" ]] && echo 'SITE_SETTINGS_FAMILIES="html_dupl_ceiling_jscpd"'
    # shellcheck disable=SC2016  # the lib's text, expanded when it runs
    echo 'site_settings_get() { [ -f "$1" ] || return 1; sed -n "s/^$2=//p" "$1"; }'
  } > "${ROOT}/Scripts/lib_site_settings.sh"
}

# pin_root <version> — $ROOT's package.json pins jscpd at <version>.
pin_root() {
  printf '{"devDependencies":{"jscpd":"%s"}}\n' "$1" > "${ROOT}/package.json"
}

# fake_jscpd — writes stdin as $ROOT's node_modules/.bin/jscpd, for a root
# made with no-jscpd.
fake_jscpd() {
  mkdir -p "${ROOT}/node_modules/.bin"
  cat > "${ROOT}/node_modules/.bin/jscpd"
  chmod +x "${ROOT}/node_modules/.bin/jscpd"
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

# The OK line names the jscpd that ran, as it answers --version (4.2.4 says
# `4.2.4`, 5.4.2 says `jscpd 5.4.2`), never a copy and never the pin.
WANT_RAN="jscpd@$(node_modules/.bin/jscpd --version 2>/dev/null | sed -E 's/^jscpd[[:space:]]+//; s/^v//')"
check_says "the OK line names the jscpd that ran (${WANT_RAN}, from its --version)" "${WANT_RAN})"

run "$FIXTURE_DIR" 0.00
check "FAILS when deliberate duplication exceeds the ceiling" 1 "$RC"
check_says "the red names the ceiling it exceeded" "EXCEEDS the 0.00% ceiling"

# jscpd's own line reads as if the gate demanded 0%; the gate's ceiling is
# the real bar, so that line is not shown and the number is kept.
run "$FIXTURE_DIR" 7.5
check "FAILS over a non-zero ceiling" 1 "$RC"
check_not_says "the red does not show jscpd's over threshold line" "over threshold"
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
_gate_code="$(grep -vE '^[[:space:]]*#' "$CHECK")"
if grep -qE 'npx' <<< "$_gate_code"; then
  echo "  ❌ the gate's text names npx outside comments"
  failures=$((failures + 1))
else
  echo "  ✅ the gate's text names no npx"
fi

# --- a jscpd failure for another reason still shows its error --------------
new_root crash "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
printf '#!/usr/bin/env bash\necho "jscpd: boom, cannot read config"\nexit 3\n' | fake_jscpd
run_root dup 99
check "a jscpd crash (exit 3) is exit 2, never 0 or 1" 2 "$RC"
check_says "the crash shows jscpd's own error" "boom, cannot read config"

# --- a jscpd 5.4.2-shaped run -----------------------------------------------
# The gate reads jscpd's JSON report, so a jscpd whose console wording differs
# from the installed one (5.4.2 prints "(50.0%) over threshold (0.0%)") gates
# the same. The stub replays what jscpd 5.4.2 printed and wrote for the
# duplicated fixture (its report trimmed to the fields the gate reads), and
# exits as jscpd does: 1 only when given a threshold (-t) that clones exceed.
JSCPD5_CONSOLE="${TMP}/jscpd5-console.txt"
cat > "$JSCPD5_CONSOLE" <<'CONSOLE'
Clone found (markup)
 - first.html [1:1 - 21:8]
   second.html [1:1 - 21:8]
Found 1 clones.
ERROR: jscpd found too many duplicates (50.0%) over threshold (0.0%)
time: 5.400ms
CONSOLE
JSCPD5_REPORT="${TMP}/jscpd5-report.json"
cat > "$JSCPD5_REPORT" <<'REPORT'
{"duplicates":[{"format":"markup","lines":21,"tokens":267,
 "firstFile":{"name":"first.html","start":1,"end":21},
 "secondFile":{"name":"second.html","start":1,"end":21}}],
 "statistics":{"total":{"clones":1,"duplicatedLines":21,"duplicatedTokens":267,"lines":42,
 "percentage":50,"percentageTokens":50,"sources":2,"tokens":534}}}
REPORT

# stub_jscpd <console-file> <report-file> [version-answer [version-exit]] —
# writes $ROOT's node_modules/.bin/jscpd, for a root made with no-jscpd: it
# answers --version with <version-answer> (default `jscpd 5.4.2`, what jscpd
# 5.4.2 prints) and exits <version-exit> (default 0), otherwise prints
# <console-file>, writes <report-file> as jscpd-report.json into its -o
# directory, and exits 1 if given -t, else 0.
stub_jscpd() {
  fake_jscpd <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then echo "${3:-jscpd 5.4.2}"; exit ${4:-0}; fi
out=""; threshold=0
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift ;;
    -t) threshold=1; shift ;;
  esac
  shift
done
mkdir -p "\$out"
cp "$2" "\$out/jscpd-report.json"
cat "$1"
exit "\$threshold"
STUB
}

new_root jscpd5 "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT"
run_root dup 7.5
check "a jscpd 5.4.2-shaped run over the ceiling is exit 1" 1 "$RC"
check_says "the jscpd 5.4.2-shaped red keeps the measured percentage" "measured 50.00%"
check_says "the jscpd 5.4.2-shaped red names the real ceiling" "EXCEEDS the 7.5% ceiling"
check_says "the jscpd 5.4.2-shaped red names the clone from the report" "first.html lines 1-21 = second.html lines 1-21"
check_not_says "the jscpd 5.4.2-shaped red does not show jscpd's over threshold line" "over threshold"
run_root dup 99
check "a jscpd 5.4.2-shaped run under the ceiling is exit 0" 0 "$RC"
check_says "the jscpd 5.4.2-shaped pass reports the number, the file count and the jscpd that ran" "html duplication 50.00% over 2 file(s) in dup (ceiling 99%, jscpd@5.4.2)"

# --- the verdict is the report's, never the console's -----------------------
# A stub whose console text says 0% while its report says 50%: the gate reads
# the report and is red. Mutation proof D below runs it against a copy that
# reads the percentage from the console text.
LYING_CONSOLE="${TMP}/lying-console.txt"
printf 'Found 0 clones.\nERROR: jscpd found too many duplicates (0%%) over threshold (0%%)\n' > "$LYING_CONSOLE"
new_root lying "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
stub_jscpd "$LYING_CONSOLE" "$JSCPD5_REPORT"
run_root dup 7.5
check "a console that says 0% does not clear a report that says 50%" 1 "$RC"
check_says "the red quotes the report's percentage" "measured 50.00%"
LYING_ROOT="$ROOT"

# --- the label names the jscpd that ran, never the pin ----------------------
# The reported case: jscpd 4.2.4 installed while package.json pins 5.4.2. The
# label says 4.2.4, and the mismatch alone does not fail the gate: the npm
# dependency policy owns that. Mutation proofs G and H run this root.
new_root mismatch "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
pin_root 5.4.2
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT" "4.2.4"
run_root dup 99
check "4.2.4 installed, 5.4.2 pinned: the mismatch alone does not fail the gate" 0 "$RC"
check_says "the OK line names the jscpd that ran (4.2.4)" "(ceiling 99%, jscpd@4.2.4)"
check_not_says "the OK line does not name the pin (5.4.2)" "jscpd@5.4.2"
run_root dup 7.5
check "4.2.4 installed, 5.4.2 pinned, over the ceiling: exit 1 as any red" 1 "$RC"
check_says "the red names the jscpd that ran (4.2.4)" "jscpd@4.2.4 measured 50.00%"
check_not_says "the red does not name the pin (5.4.2)" "jscpd@5.4.2"
run_root
check "4.2.4 installed, 5.4.2 pinned, the ceiling from the settings: the mismatch alone does not fail the gate" 0 "$RC"
MISMATCH_ROOT="$ROOT"

# A --version that fails, or answers something that is no version, is the
# label jscpd@unknown, never the pin, and the gate still measures.
new_root versionfails "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
pin_root 5.4.2
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT" "Error: Cannot find module 'commander'" 1
run_root dup 99
check "a failing jscpd --version: the gate still measures" 0 "$RC"
check_says "a failing jscpd --version is the label jscpd@unknown" "html duplication 50.00% over 2 file(s) in dup (ceiling 99%, jscpd@unknown)"
check_not_says "a failing jscpd --version is never labelled by the pin" "jscpd@5.4.2"
VERSIONFAILS_ROOT="$ROOT"

new_root garbled "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
pin_root 5.4.2
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT" "jscpd version: see package.json"
run_root dup 7.5
check "a garbled jscpd --version: the gate still measures (red over the ceiling)" 1 "$RC"
check_says "a garbled jscpd --version is the label jscpd@unknown" "jscpd@unknown measured 50.00%"
check_not_says "a garbled jscpd --version is never labelled by the pin" "jscpd@5.4.2"

# jscpd 4.2.4 answers --version with the bare version, 5.x prefixes the name.
new_root bare "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT" "4.2.4"
run_root dup 99
check_says "a bare --version answer (4.2.4's shape) is the label" "(ceiling 99%, jscpd@4.2.4)"

# --- the ceiling form -------------------------------------------------------
# Family form: the settings lib declares html_dupl_ceiling_jscpd, and the
# ceiling is the running major's line.
new_root family "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
form_lib family
printf 'html_dupl_target=dup\nhtml_dupl_ceiling_jscpd4=99\nhtml_dupl_ceiling_jscpd5=0.00\n' > "${ROOT}/Scripts/site_settings.txt"
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT" "4.2.4"
run_root
check "family form: jscpd 4 runs and takes html_dupl_ceiling_jscpd4" 0 "$RC"
check_says "family form: the OK line names jscpd 4's ceiling" "(ceiling 99%, jscpd@4.2.4)"
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT" "jscpd 5.4.2"
run_root
check "family form: jscpd 5 runs and takes html_dupl_ceiling_jscpd5" 1 "$RC"
check_says "family form: the red names jscpd 5's ceiling" "EXCEEDS the 0.00% ceiling"
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT" "6.0.0"
run_root
check "family form: a running major with no line is exit 2" 2 "$RC"
check_says "family form: the red names the missing line" "no html_dupl_ceiling_jscpd6 line"
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT" "jscpd version: see package.json"
run_root
check "family form: an unreadable version cannot pick a ceiling, exit 2" 2 "$RC"
check_says "family form: the red says the version is unreadable" "could not read the running jscpd's version"
run_root dup 99
check "family form with a ceiling argument: an unreadable version still measures" 0 "$RC"
check_says "family form with a ceiling argument: the label is jscpd@unknown" "(ceiling 99%, jscpd@unknown)"

# Single form: the settings lib declares no family, and the ceiling is
# html_dupl_ceiling whatever jscpd runs.
new_root single "$CHECK" dup 99 no-jscpd
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
form_lib single
printf 'html_dupl_target=dup\nhtml_dupl_ceiling=7.5\nhtml_dupl_ceiling_jscpd5=99\n' > "${ROOT}/Scripts/site_settings.txt"
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT" "jscpd 5.4.2"
run_root
check "single form: the ceiling is html_dupl_ceiling, never a per-major line" 1 "$RC"
check_says "single form: the red names html_dupl_ceiling" "EXCEEDS the 7.5% ceiling"
stub_jscpd "$JSCPD5_CONSOLE" "$JSCPD5_REPORT" "jscpd version: see package.json"
run_root
check "single form: an unreadable version still measures against html_dupl_ceiling" 1 "$RC"
check_says "single form: the label is jscpd@unknown" "jscpd@unknown measured 50.00%"

# --- no jscpd pin readable: exit 2 naming it, never 0 -----------------------
# NOPIN_GATE is the gate under test for these two cases; mutation proof F
# below runs the same cases against a copy whose exit 2 became exit 0.
NOPIN_GATE="$CHECK"
NOPIN_SAYS="no jscpd pin readable from package.json devDependencies"

new_root nopin "$NOPIN_GATE" dup 99
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
printf '{"devDependencies":{"other":"1.0.0"}}\n' > "${ROOT}/package.json"
run_root dup 99
check "a package.json whose devDependencies lack jscpd is exit 2, never 0" 2 "$RC"
check_says "the no-pin red names that no jscpd pin is readable" "$NOPIN_SAYS"

new_root unreadablepin "$NOPIN_GATE" dup 99
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
printf '{"devDependencies": {"jscpd": "5.4.2",\n' > "${ROOT}/package.json"
run_root dup 99
check "a package.json that is no JSON (an unreadable pin) is exit 2, never 0" 2 "$RC"
check_says "the unreadable-pin red names that no jscpd pin is readable" "$NOPIN_SAYS"

new_root nopackage "$NOPIN_GATE" dup 99
cp -R "$FIXTURE_DIR" "${ROOT}/dup"
rm "${ROOT}/package.json"
run_root dup 99
check "no package.json at all is exit 2, never 0" 2 "$RC"
check_says "the no-package.json red names that no jscpd pin is readable" "$NOPIN_SAYS"

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
sed 's/^\( *\)MAX_PCT="[$](site_settings_get .*$/\1MAX_PCT=99/' "$CHECK" > "$MUTANT_C"
if cmp -s "$CHECK" "$MUTANT_C"; then
  echo "  ❌ mutation proof C: the sed no longer matches the ceiling read, so this proof proves nothing"
  failures=$((failures + 1))
else
  ROOT="$LOWERED_ROOT"
  cp "$MUTANT_C" "${ROOT}/Scripts/check_html_dupl.sh"
  run_root
  check "mutation proof C: the lowered-ceiling case turns green when the ceiling is hard-coded" 0 "$RC"
fi

# --- Mutation proof D: the verdict is the report's, never the console's -----
# A copy that reads the percentage from jscpd's console text, as the gate did
# up to v4, turns the lying-console case green.
MUTANT_D="${TMP}/mutant_d.sh"
cat > "${TMP}/console_pct.line" <<'LINE'
pct="$(sed -nE 's/.*duplicates \(([0-9.]+)%\).*/\1/p' <<<"$out" | tail -1)"
LINE
awk -v f="${TMP}/console_pct.line" 'BEGIN { getline r < f } /^pct=/ { print r; next } { print }' "$CHECK" > "$MUTANT_D"
if cmp -s "$CHECK" "$MUTANT_D"; then
  echo "  ❌ mutation proof D: the awk no longer matches the percentage read, so this proof proves nothing"
  failures=$((failures + 1))
else
  ROOT="$LYING_ROOT"
  cp "$MUTANT_D" "${ROOT}/Scripts/check_html_dupl.sh"
  run_root dup 7.5
  check "mutation proof D: reading the percentage from jscpd's console text turns the lying-console case green" 0 "$RC"
fi

# --- Mutation proof E: a copy without the jscpd-failure check ---------------
MUTANT_E="${TMP}/mutant_e.sh"
sed 's/^if \[ "[$]status" -ne 0 \]; then/if false; then/' "$CHECK" > "$MUTANT_E"
if cmp -s "$CHECK" "$MUTANT_E"; then
  echo "  ❌ mutation proof E: the sed no longer matches the failure check, so this proof proves nothing"
  failures=$((failures + 1))
else
  new_root mut-e "$MUTANT_E" dup 99 no-jscpd
  cp -R "$FIXTURE_DIR" "${ROOT}/dup"
  fake_jscpd < "${TMP}/root-crash/node_modules/.bin/jscpd"
  run_root dup 99
  check_not_says "mutation proof E: without the failure check the crash's error is swallowed" "boom, cannot read config"
fi

# --- Mutation proof F: a copy whose no-pin exit 2 is exit 0 ----------------
MUTANT_F="${TMP}/mutant_f.sh"
sed '/no jscpd pin readable/{n;s/exit 2/exit 0/;}' "$CHECK" > "$MUTANT_F"
if cmp -s "$CHECK" "$MUTANT_F"; then
  echo "  ❌ mutation proof F: the sed no longer matches the no-pin exit, so this proof proves nothing"
  failures=$((failures + 1))
else
  new_root mut-f "$MUTANT_F" dup 99
  cp -R "$FIXTURE_DIR" "${ROOT}/dup"
  printf '{"devDependencies":{"other":"1.0.0"}}\n' > "${ROOT}/package.json"
  run_root dup 99
  check "mutation proof F: the no-pin case turns green when its exit 2 becomes exit 0" 0 "$RC"
fi

# --- Mutation proof G: a copy that labels by the pin ------------------------
# The mismatch case (4.2.4 ran, 5.4.2 pinned) and the failing --version case
# then name the pin, which their checks above would catch.
MUTANT_G="${TMP}/mutant_g.sh"
# shellcheck disable=SC2016  # the gate's text, not this script's variables
sed 's/^\( *\)JSCPD_LABEL=.*$/\1JSCPD_LABEL="${JSCPD_PIN}"/' "$CHECK" > "$MUTANT_G"
if cmp -s "$CHECK" "$MUTANT_G"; then
  echo "  ❌ mutation proof G: the sed no longer matches the label, so this proof proves nothing"
  failures=$((failures + 1))
else
  ROOT="$MISMATCH_ROOT"
  cp "$MUTANT_G" "${ROOT}/Scripts/check_html_dupl.sh"
  run_root dup 99
  check_says "mutation proof G: a gate that labels by the pin names 5.4.2 where 4.2.4 ran" "(ceiling 99%, jscpd@5.4.2)"
  ROOT="$VERSIONFAILS_ROOT"
  cp "$MUTANT_G" "${ROOT}/Scripts/check_html_dupl.sh"
  run_root dup 99
  check_says "mutation proof G: a gate that labels by the pin names 5.4.2 where the version is unknown" "(ceiling 99%, jscpd@5.4.2)"
fi

# --- Mutation proof H: a copy that fails on a version mismatch --------------
# A copy that refuses a jscpd other than the pin turns the mismatch case red
# (exit 2), which its check above (exit 0) would catch.
MUTANT_H="${TMP}/mutant_h.sh"
cat > "${TMP}/mismatch_fails.line" <<'LINE'
[ "$JSCPD_LABEL" = "$JSCPD_PIN" ] || { echo "html-dupl: ${JSCPD_LABEL} ran, not the pinned ${JSCPD_PIN}" >&2; exit 2; }
LINE
awk -v f="${TMP}/mismatch_fails.line" 'BEGIN { getline r < f } /^if \[ ! -d "[$]TARGET_DIR" \]; then$/ { print r } { print }' "$CHECK" > "$MUTANT_H"
if cmp -s "$CHECK" "$MUTANT_H"; then
  echo "  ❌ mutation proof H: the awk no longer finds the target-dir check, so this proof proves nothing"
  failures=$((failures + 1))
else
  ROOT="$MISMATCH_ROOT"
  cp "$MUTANT_H" "${ROOT}/Scripts/check_html_dupl.sh"
  run_root dup 99
  check "mutation proof H: a gate that fails on the mismatch turns the mismatch case into exit 2" 2 "$RC"
  check_says "mutation proof H: and its red is the mismatch" "jscpd@4.2.4 ran, not the pinned jscpd@5.4.2"
fi

COMPLETED=1

if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_html_dupl contract"
  exit 1
fi

echo ""
echo "✅ test_check_html_dupl"
