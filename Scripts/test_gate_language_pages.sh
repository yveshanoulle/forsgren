#!/usr/bin/env bash
# Scripts/test_gate_language_pages.sh (forsgren#220)
#
# Self-test for Scripts/gate_language_pages.sh, the wrapper that runs the
# canon language gate over the metrics site and the starter page together. The
# canon gate is a STUB here (it lists the files of the directory it is given and
# exits as told), so the test needs no LanguageTool.
#   1. the directory the gate gets holds the site pages and starter/index.html
#   2. the gate's exit status and output pass through (0, 1 and 2)
#   3. the temporary directory is gone afterwards
#   4. a missing site directory, a missing starter page   -> exit 2, the gate not run
# Mutation proofs (each fixture is red BECAUSE of the line mutated):
#   A. the starter page not copied: case 1 loses starter/index.html;
#   B. the gate's status swallowed: case 2 turns green on a red gate;
#   C. the temporary directory kept: case 3 finds it.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
WRAPPER="${REPO_ROOT}/Scripts/gate_language_pages.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "language pages wrapper self-test"

[[ -f "$WRAPPER" ]] || selftest_abort "language pages wrapper self-test: ${WRAPPER} is missing"

# The stub gate: lists the files of its directory argument into STUB_LIST,
# records the directory, prints a line and exits STUB_RC.
cat > "${TMP}/stub_gate.sh" <<'STUB'
#!/usr/bin/env bash
( cd "$1" && find . -type f | sort ) > "$STUB_LIST"
printf '%s\n' "$1" > "$STUB_DIR"
echo "stub gate ran on a directory"
exit "${STUB_RC:-0}"
STUB
chmod +x "${TMP}/stub_gate.sh"

mkdir -p "${TMP}/site/numbers" "${TMP}/starter"
echo '<html lang="en"></html>' > "${TMP}/site/index.html"
echo '<html lang="en"></html>' > "${TMP}/site/numbers/index.html"
echo '<html lang="en"></html>' > "${TMP}/starter/index.html"
echo 'body{}' > "${TMP}/starter/styles.css"

TARGET="$WRAPPER"
# run [VAR=value ...]
run() {
  rm -f "${TMP}/list" "${TMP}/dir"
  capture env GATE_LANGUAGE_PAGES_GATE="${TMP}/stub_gate.sh" STUB_LIST="${TMP}/list" STUB_DIR="${TMP}/dir" "$@" \
    "$TARGET" "${TMP}/site" "${TMP}/starter"
}

run
want_green "2a: a green gate passes through" "stub gate ran on a directory"
if [[ "$(cat "${TMP}/list")" == "$(printf './index.html\n./numbers/index.html\n./starter/index.html')" ]]; then
  echo "  ok: 1: the gate gets the site pages and starter/index.html, and no other starter file"
else
  fail "1: the gate's directory holds: $(tr '\n' ' ' < "${TMP}/list" 2>/dev/null)"
fi
if [[ -n "$(cat "${TMP}/dir")" && ! -e "$(cat "${TMP}/dir")" ]]; then
  echo "  ok: 3: the temporary directory is gone afterwards"
else
  fail "3: the temporary directory $(cat "${TMP}/dir" 2>/dev/null) still exists"
fi

run STUB_RC=1
want_exit "2b: a red gate (1) passes through" 1 "stub gate ran on a directory"
run STUB_RC=2
want_exit "2c: a gate that could not run (2) passes through" 2 "stub gate ran on a directory"

capture env GATE_LANGUAGE_PAGES_GATE="${TMP}/stub_gate.sh" "$TARGET" "${TMP}/absent" "${TMP}/starter"
want_exit "4a: a missing site directory" 2 "site dir not found"
capture env GATE_LANGUAGE_PAGES_GATE="${TMP}/stub_gate.sh" "$TARGET" "${TMP}/site" "${TMP}/absent"
want_exit "4b: a missing starter page" 2 "starter page not found"

MUT="${REPO_ROOT}/Scripts/.language_pages_mutant.$$.sh"
trap 'rm -f "$MUT"; selftest_cleanup' EXIT

if selftest_mutant "$WRAPPER" "$MUT" '/^cp "/s/.*/:/'; then
  TARGET="$MUT"; run
  if grep -qF './starter/index.html' "${TMP}/list"; then
    fail "mutation proof A: without the copy the gate still gets starter/index.html"
  else
    echo "  ok: mutation proof A: without the copy the gate loses starter/index.html (case 1 would be red)"
  fi
fi
if selftest_mutant "$WRAPPER" "$MUT" '/^  exit ".rc"/s/.*/  COMPLETED=1; exit 0/'; then
  TARGET="$MUT"; run STUB_RC=1
  want_green "mutation proof B: a swallowed status turns case 2b green" "stub gate ran"
fi
if selftest_mutant "$WRAPPER" "$MUT" '/^  rm -rf ".PAGES"/s/.*/  :/'; then
  TARGET="$MUT"; run
  if [[ -e "$(cat "${TMP}/dir")" ]]; then
    echo "  ok: mutation proof C: the kept temporary directory is found (case 3 would be red)"
    rm -rf "$(cat "${TMP}/dir")"
  else
    fail "mutation proof C: the temporary directory is gone even without the rm"
  fi
fi

rm -f "$MUT"
selftest_end "the language pages wrapper self-test failed" "language pages wrapper: every case holds, three mutations seen"
