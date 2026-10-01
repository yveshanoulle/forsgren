#!/usr/bin/env bash
# Scripts/test_go_toolchain.sh
#
# Self-test for Scripts/go_toolchain.sh, run before the gates that use the
# GOTOOLCHAIN it prints. Cases, each a throwaway go.mod:
#   1. a toolchain line            -> prints exactly that version, rc 0
#   2. no toolchain line           -> red, naming the missing line
#   3. no go.mod at all            -> red
#   4. a `go` line only (a comment mentioning toolchain does not count)
#                                  -> red
#   5. the repo's real go.mod has a toolchain line

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

SCRIPT="./Scripts/go_toolchain.sh"

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: go-toolchain self-test aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

# run_case <name> <go.mod content> -> sets OUT (stdout), ERR (stderr), RC
run_case() {
  local name="$1" content="$2"
  printf '%s' "$content" > "${TMP}/${name}.mod"
  RC=0
  OUT="$("$SCRIPT" "${TMP}/${name}.mod" 2>"${TMP}/${name}.err")" || RC=$?
  ERR="$(cat "${TMP}/${name}.err")"
}

run_case with $'module m\n\ngo 1.26.1\n\ntoolchain go1.27.1\n'
if [ "$RC" -ne 0 ] || [ "$OUT" != "go1.27.1" ]; then
  fail "a toolchain line must print exactly its version — rc=${RC}, stdout=${OUT}, stderr=${ERR}"
else
  echo "OK:   the toolchain line is read as-is"
fi

run_case without $'module m\n\ngo 1.26.1\n'
if [ "$RC" -eq 0 ]; then
  fail "a go.mod without a toolchain line was accepted — GOTOOLCHAIN would be unset and the version would float"
elif ! grep -q "no toolchain line" <<<"$ERR"; then
  fail "the failure does not say the toolchain line is missing: ${ERR}"
elif [ -n "$OUT" ]; then
  fail "a failed read must print nothing on stdout, or sfl would export it: ${OUT}"
else
  echo "OK:   a missing toolchain line is refused, by name"
fi

run_case commented $'module m\n\n// toolchain go1.99.9\ngo 1.26.1\n'
if [ "$RC" -eq 0 ]; then
  fail "a comment mentioning toolchain was read as the toolchain line: ${OUT}"
else
  echo "OK:   a comment is not a toolchain line"
fi

RC=0
"$SCRIPT" "${TMP}/no-such.mod" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 0 ]; then
  fail "a missing go.mod reported success"
else
  echo "OK:   a missing go.mod is refused"
fi

RC=0
OUT="$("$SCRIPT" 2>&1)" || RC=$?
if [ "$RC" -ne 0 ] || ! grep -qE '^go[0-9]+\.[0-9]+(\.[0-9]+)?$' <<<"$OUT"; then
  fail "the repo's own go.mod must carry a toolchain line — rc=${RC}: ${OUT}"
else
  echo "OK:   the repo's go.mod pins ${OUT}"
fi

COMPLETED=1

if [ "$failed" -ne 0 ]; then
  echo
  echo "FAIL: go-toolchain self-test"
  exit 1
fi

echo "go-toolchain self-test: all cases passed"
