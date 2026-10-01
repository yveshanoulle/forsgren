#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Fixture for Scripts/install_tools.sh — unit 414.
#
# Yves, 2026-09-01, reading the sfl.sh comment that said this repo installs
# nothing: *"other sfls do install using brew … we should have an install.sh
# that does the installers and reuse the same everywhere."* The reason this repo
# installed nothing only ever covered the npm linters, which are pinned
# devDependencies on purpose. It never covered gitleaks, shellcheck, yamllint or
# actionlint, which were simply assumed to be on the machine.
#
# THE SEAM IS `BREW`. The installer never runs Homebrew here: the fixture puts a
# stub on the path that records what it was asked to do and, for `install`,
# creates the tool it claims to have installed. That makes the interesting
# property testable — what happens when Homebrew says it worked and the tool
# still is not there.
#
# Runs from sfl.sh; CI parity via quality.yml. Local:
#   ./Scripts/test_install_tools.sh

SCRIPT_UNDER_TEST="./Scripts/install_tools.sh"
TMP="$(mktemp -d)"

COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [ "$COMPLETED" -ne 1 ]; then
    echo "❌ FAIL: install-tools fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

failed=0
fail() { echo "❌ FAIL: $*"; failed=1; }

if [ ! -x "$SCRIPT_UNDER_TEST" ]; then
  fail "${SCRIPT_UNDER_TEST} is missing or not executable — the estate's installer does not exist yet"
  COMPLETED=1
  exit 1
fi

# A stub Homebrew. It logs every call, and `install <tool>` writes a working
# executable of that name into the fake bin dir — Homebrew's success case.
# `install FAILING_TOOL` logs the call and creates nothing, which is the case
# that matters.
make_brew_stub() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "${bin}/brew" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${BREW_LOG}"
if [ "${1:-}" = "install" ] && [ "${2:-}" != "unobtainable" ]; then
  printf '#!/usr/bin/env bash\necho stub %s\n' "${2}" > "$(dirname "$0")/${2}"
  chmod +x "$(dirname "$0")/${2}"
fi
exit 0
STUB
  chmod +x "${bin}/brew"
}

# run_case <tools-file-content> -> sets OUT, RC, LOG
run_case() {
  local content="$1" name="$2"
  local dir="${TMP}/${name}"
  mkdir -p "${dir}/bin"
  printf '%s' "$content" > "${dir}/tools.txt"
  make_brew_stub "${dir}/bin"
  BREW_LOG="${dir}/brew.log"
  : > "$BREW_LOG"
  RC=0
  OUT="$(PATH="${dir}/bin:/usr/bin:/bin" BREW_LOG="$BREW_LOG" BREW="${dir}/bin/brew" \
        "$SCRIPT_UNDER_TEST" "${dir}/tools.txt" 2>&1)" || RC=$?
  LOG="$(cat "$BREW_LOG")"
}

# --- a tool that is not installed -----------------------------------------
run_case 'shellcheck
' missing
if [ "$RC" -ne 0 ]; then
  fail "a missing tool Homebrew can supply must end green — got rc=${RC}: ${OUT}"
elif ! grep -q "install shellcheck" <<<"$LOG"; then
  fail "a missing tool was not installed — brew was asked: ${LOG:-<nothing>}"
else
  echo "OK:   a missing tool is installed"
fi

# --- a tool that is already there -----------------------------------------
run_case 'shellcheck
' present
# Put it there first, then run again: the second run must upgrade, not reinstall.
printf '#!/usr/bin/env bash\necho already\n' > "${TMP}/present/bin/shellcheck"
chmod +x "${TMP}/present/bin/shellcheck"
: > "${TMP}/present/brew.log"
RC=0
OUT="$(PATH="${TMP}/present/bin:/usr/bin:/bin" BREW_LOG="${TMP}/present/brew.log" \
      BREW="${TMP}/present/bin/brew" "$SCRIPT_UNDER_TEST" "${TMP}/present/tools.txt" 2>&1)" || RC=$?
LOG="$(cat "${TMP}/present/brew.log")"
if [ "$RC" -ne 0 ]; then
  fail "an already-installed tool must not fail the run — rc=${RC}: ${OUT}"
elif grep -q "install shellcheck" <<<"$LOG"; then
  fail "an already-installed tool was reinstalled rather than upgraded: ${LOG}"
elif ! grep -q "upgrade shellcheck" <<<"$LOG"; then
  fail "an already-installed tool was not upgraded — dev-tool currency is the whole point of running this every time: ${LOG:-<nothing>}"
else
  echo "OK:   an installed tool is upgraded, not reinstalled"
fi

# --- Homebrew says it worked and the tool is still absent ------------------
#
# THE CASE THIS EXISTS FOR. `brew install` exiting 0 is not evidence that the
# command is now runnable, and a gate whose tool is missing does not fail — it
# reports whatever `command not found` exits with, inside a step that then
# summarises its own exit code.
run_case 'unobtainable
' unobtainable
if [ "$RC" -eq 0 ]; then
  fail "brew exited 0 without providing the tool and the installer called that success — every gate needing it would then run against nothing"
elif ! grep -qi "unobtainable" <<<"$OUT"; then
  fail "the installer failed without naming the tool it could not provide: ${OUT}"
else
  echo "OK:   a tool Homebrew did not actually provide is a hard failure, by name"
fi

# --- comments and blank lines ---------------------------------------------
run_case '# a comment

shellcheck
' comments
if [ "$RC" -ne 0 ]; then
  fail "comments and blank lines must be skipped, not installed — rc=${RC}: ${OUT}"
elif grep -qE "install (#|a|comment)" <<<"$LOG"; then
  fail "a comment line was treated as a tool name: ${LOG}"
else
  echo "OK:   comments and blank lines are skipped"
fi

# --- an empty list ---------------------------------------------------------
#
# NON-VACUITY. A list that has quietly become empty must not read as "all tools
# present". It is the same failure the estate's grant audit had: an enumeration
# that returned nothing, reported as nothing wrong.
run_case '# nothing but a comment
' empty
if [ "$RC" -eq 0 ]; then
  fail "an empty tool list reported success — a run that installed nothing and checked nothing must not look like a green one"
else
  echo "OK:   an empty tool list is refused"
fi

# --- a list that is not there ----------------------------------------------
RC=0
OUT="$("$SCRIPT_UNDER_TEST" "${TMP}/no-such-file.txt" 2>&1)" || RC=$?
if [ "$RC" -eq 0 ]; then
  fail "a missing tool list reported success"
else
  echo "OK:   a missing tool list is refused"
fi

# --- the repo's real list is readable and non-empty -------------------------
#
# The cases above drive synthetic lists. This one asserts the file the runner
# actually reads exists and declares something, so a fixture full of temp files
# cannot pass while the real list is gone.
real_count=$(grep -vE '^#|^$' Scripts/required_tools.txt 2>/dev/null | grep -c . || true)
if [ "${real_count:-0}" -lt 1 ]; then
  fail "Scripts/required_tools.txt declares no tools — sfl would install nothing and say so cheerfully"
else
  echo "OK:   the repo declares ${real_count} required tools"
fi

COMPLETED=1

if [ "$failed" -ne 0 ]; then
  echo ""
  echo "FAIL: install-tools fixture"
  exit 1
fi

echo "install-tools fixture: all cases passed"
