#!/usr/bin/env bash
# Scripts/test_lib_go_tool.sh
#
# Self-test for Scripts/lib_go_tool.sh (forsgren#216), the helper the four
# Go-tool gates (check_govulncheck.sh, check_deadcode.sh, check_go_lint.sh,
# check_test_dupl.sh) source to resolve and run a tool pinned in go.mod. Each
# gate's own self-test proves that gate's verdicts; this one proves the helper
# on its own, with a stub `go` that writes what a cold runner writes.
#
# go_tool_path <tool>:
#   1. download lines on stderr, the path on stdout -> GO_TOOL_BIN is the
#      stdout path and nothing else (forsgren#210), exit 0
#   2. `go tool -n` fails (even with a path on stdout)  -> exit 1
#   3. a path that does not exist, a directory, a file that is not
#      executable, an empty stdout                      -> exit 2
# go_tool_run <args>:
#   4. the tool's own exit code comes back unchanged (0, 1, 2, 3, 127), and
#      its stdout and stderr are its output
# MUTATION PROOFS, each red for its reason:
#   5. a helper that captures stderr into the path (the #210 bug) fails case 1
#   6. a helper that swallows the tool's exit code fails case 4
#   7. a helper that skips the executable check fails case 3

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

LIB="Scripts/lib_go_tool.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "Go tool helper self-test"

[[ -f "$LIB" ]] || selftest_abort "the helper ${LIB} is missing: the four Go-tool gates have nothing to resolve their tool with"

# The stub go: `go tool -n <tool>` writes STUB_STDERR to stderr, STUB_STDOUT
# to stdout and exits STUB_RC.
SHIM="${TMP}/shim"
mkdir -p "$SHIM"
cat > "${SHIM}/go" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" != "tool -n" ]]; then
  exit 99
fi
if [[ -n "${STUB_STDERR:-}" ]]; then
  printf '%s\n' "$STUB_STDERR" >&2
fi
if [[ -n "${STUB_STDOUT:-}" ]]; then
  printf '%s\n' "$STUB_STDOUT"
fi
exit "${STUB_RC:-0}"
STUB
chmod +x "${SHIM}/go"

# Tools the stub can name.
TOOLS="${TMP}/tools"
mkdir -p "$TOOLS/a-directory"
cat > "${TOOLS}/tool" <<'TOOL'
#!/bin/sh
echo "tool says hi"
echo "tool warns" >&2
exit "${TOOL_RC:-0}"
TOOL
chmod +x "${TOOLS}/tool"
printf 'not a program\n' > "${TOOLS}/not-executable"
chmod -x "${TOOLS}/not-executable"

# The probe: sources the helper under test and prints what it did.
#   probe.sh <lib> path -> "rc=<go_tool_path status>; bin=<GO_TOOL_BIN>"
#   probe.sh <lib> run  -> "rc=<go_tool_run status>;" then its output
cat > "${TMP}/probe.sh" <<'PROBE'
#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=/dev/null
source "$1"
if [[ "$2" == "path" ]]; then
  go_tool_path sometool
  echo "rc=$?; bin=${GO_TOOL_BIN:-}"
else
  go_tool_path sometool || { echo "rc=path-failed;"; exit 0; }
  out="$(go_tool_run --flag value)"
  echo "rc=$?;"
  printf '%s\n' "$out"
fi
PROBE
chmod +x "${TMP}/probe.sh"

# probe <lib> <path|run> <stub stdout> <stub stderr> <stub rc> [tool rc]
probe() {
  capture env PATH="${SHIM}:${PATH}" STUB_STDOUT="$3" STUB_STDERR="$4" STUB_RC="$5" TOOL_RC="${6:-0}" \
    "${TMP}/probe.sh" "$1" "$2"
}

NOISE=$'go: downloading golang.org/x/vuln v0.0.0\ngo: downloading golang.org/x/mod v0.0.0'

# Case 1: the cold runner (forsgren#210).
case_cold_runner() {
  probe "$1" path "${TOOLS}/tool" "$NOISE" 0
  want_said "${2}download lines on stderr: the path is the stdout one alone" "rc=0; bin=${TOOLS}/tool"
}

# Case 4: the tool's own exit code, for the codes the gates tell apart.
case_exit_codes() {
  local code
  for code in 0 1 2 3 127; do
    probe "$1" run "${TOOLS}/tool" "" 0 "$code"
    want_said "${2}the tool exiting ${code} comes back as ${code}" "rc=${code};"
  done
  want_said "${2}the tool's stdout and stderr are its output" "tool says hi"
  want_said "${2}  ... stderr too" "tool warns"
}

# Case 3: a path that is not an executable file.
case_not_executable() {
  probe "$1" path "${TOOLS}/not-built/tool" "" 0
  want_said "${2}a path that does not exist is exit 2" "rc=2;"
  probe "$1" path "${TOOLS}/a-directory" "" 0
  want_said "${2}a directory is exit 2" "rc=2;"
  probe "$1" path "${TOOLS}/not-executable" "" 0
  want_said "${2}a file that is not executable is exit 2" "rc=2;"
  probe "$1" path "" "" 0
  want_said "${2}an empty stdout is exit 2" "rc=2;"
}

case_cold_runner "$LIB" ""
probe "$LIB" path "${TOOLS}/tool" "go: no such tool" 1
want_said "go tool -n failing is exit 1, even with a path on stdout" "rc=1;"
case_not_executable "$LIB" ""
case_exit_codes "$LIB" ""

# make_lib_mutant <name> <sed-expression>: a mutated copy of the helper.
make_lib_mutant() {
  MUTANT_LIB="${TMP}/$1/lib_go_tool.sh"
  selftest_mutant "$LIB" "$MUTANT_LIB" "$2"
}

# --- Case 5: MUTATION PROOF. The #210 capture (2>&1) put back: the path is
# the download lines plus the path, so the cold-runner case is red.
if make_lib_mutant "stderr-captured" '/go tool -n/s/1")"/1" 2>\&1)"/'; then
  probe "$MUTANT_LIB" path "${TOOLS}/tool" "$NOISE" 0
  if grep -qF -- "rc=0; bin=${TOOLS}/tool" <<< "$OUT"; then
    fail "mutation: with stderr captured into the path the cold-runner case still held. Output: ${OUT}"
  elif grep -qF -- "go: downloading" <<< "$OUT"; then
    echo "  ok: mutation: with stderr captured into the path, the cold-runner case is red, the path holding the download lines"
  else
    fail "mutation: the cold-runner case is red but not for the download lines in the path. Output: ${OUT}"
  fi
fi

# --- Case 6: MUTATION PROOF. A helper that swallows the tool's exit code:
# every code in case 4 comes back 0.
if make_lib_mutant "swallowed" '/BIN" "/s/$/ || true/'; then
  probe "$MUTANT_LIB" run "${TOOLS}/tool" "" 0 2
  if grep -qF -- "rc=0;" <<< "$OUT"; then
    echo "  ok: mutation: a helper that swallows the exit code returns 0 for a tool that exited 2"
  else
    fail "mutation: the swallowing helper did not return 0 for a tool that exited 2. Output: ${OUT}"
  fi
  if grep -qF -- "rc=2;" <<< "$OUT"; then
    fail "mutation: the swallowing helper still returned the tool's code, so case 4 would not catch it. Output: ${OUT}"
  fi
fi

# --- Case 7: MUTATION PROOF. A helper that skips the executable check
# accepts a path that was not built (case 3 red).
if make_lib_mutant "no-x-check" 's/^  if \[ ! -f .*$/  if false; then/'; then
  probe "$MUTANT_LIB" path "${TOOLS}/not-built/tool" "" 0
  if grep -qF -- "rc=0;" <<< "$OUT"; then
    echo "  ok: mutation: without the executable check a path that was not built is accepted"
  else
    fail "mutation: without the executable check the path that was not built was still refused. Output: ${OUT}"
  fi
fi

selftest_end "the Go tool helper does not resolve the tool from stdout alone, check it, or return the tool's own exit code" \
  "Go tool helper takes the path from stdout alone (download lines on stderr stay out), refuses a failing go tool -n and a path that is not an executable file, returns the tool's own exit code, and each of the three mutations is red for its reason"
