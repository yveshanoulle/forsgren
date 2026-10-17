#!/usr/bin/env bash
# Scripts/test_check_deadcode.sh
#
# Self-test for Scripts/check_deadcode.sh, run before the gate it validates.
#
# NEW (forsgren#1, ladder step 23). Another estate repository runs `deadcode -test ./...` in
# sfl (run_go_deadcode_check) and in CI with no fixture: nothing there shows
# the check red on a dead function, nor that `-test` is what keeps a
# test-only helper green. A gate that has never been seen red is a hope.
#
# Each case is a throwaway Go module under one temp root, a `package main`
# that calls lib.Used and used(), judged by the deadcode pinned in go.mod.
# Each case asserts the exit code AND the reason:
#   1. every function reachable from main             -> green
#   2. an unreachable unexported function `dead`      -> red, naming it
#   3. an unreachable exported function lib.Exported  -> red, naming it
#   4. FIXTURE MUTATION: case 2's `dead` called from main -> green: its
#      reachability, nothing else in the module, is what reddened case 2
#   5. a function called only from a _test.go file    -> green: another estate repository's
#      `-test` semantics, the tests are roots too
#   6. MUTATION PROOF: the gate without `-test` is red on case 5, naming the
#      test-only function: the flag is what keeps it green
#   7. a module with no main package                  -> red: deadcode has
#      no root to reach from, and a check over nothing is no pass
#   8. a module that does not compile                 -> red, as a tool
#      error: a deadcode that did not run is never a clean result
#   9. a module directory that does not exist         -> red

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_deadcode.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "dead-code gate self-test"

[[ -x "$GATE" ]] || selftest_abort "the dead-code gate ${GATE} is missing (or not executable): nothing runs deadcode"

# new_module <name> — a main package calling lib.Used and used(), with
# nothing unreachable.
new_module() {
  MOD="${TMP}/$1"
  mkdir -p "${MOD}/lib"
  printf 'module example.com/m\n\ngo 1.26.1\n' > "${MOD}/go.mod"
  printf 'package main\n\nimport "example.com/m/lib"\n\nfunc main() {\n\tlib.Used()\n\tused()\n}\n\nfunc used() {}\n' \
    > "${MOD}/main.go"
  printf '// Package lib is a dead-code fixture.\npackage lib\n\n// Used is called from main.\nfunc Used() {}\n' \
    > "${MOD}/lib/lib.go"
}

# run_gate [gate] — runs the gate against $MOD; sets RC and OUT.
run_gate() {
  capture "${1:-$GATE}" "$MOD"
}

# mutant <name> <sed-expression> — a mutated copy of the gate at
# $TMP/<name>/Scripts/, with this repository's go.mod and go.sum beside it so
# `go tool -n deadcode` resolves the same pinned deadcode there; sets
# MUTANT, or fails the case when the edit changed nothing (a vacuous proof).
mutant() {
  MUTANT="${TMP}/$1/Scripts/check_deadcode.sh"
  selftest_mutant "$GATE" "$MUTANT" "$2" || return 1
  cp go.mod go.sum "${TMP}/$1/"
  cp Scripts/lib_go_tool.sh "${TMP}/$1/Scripts/"
}

# --- Case 1: everything reachable.
new_module "clean"
run_gate
want_green_ok "every function reachable from main is green"

# --- Case 2: an unreachable unexported function.
new_module "dead-unexported"
printf 'package main\n\nfunc dead() {}\n' > "${MOD}/dead.go"
run_gate
want_red "an unreachable unexported function is red, naming it" "unreachable func: dead"
want_red "  ... and its file" "dead.go:3:6"
DEAD="$MOD"

# --- Case 3: an unreachable exported function.
new_module "dead-exported"
printf '\n// Exported is called by nobody.\nfunc Exported() {}\n' >> "${MOD}/lib/lib.go"
run_gate
want_red "an unreachable exported function is red, naming it" "unreachable func: Exported"

# --- Case 4: FIXTURE MUTATION. Case 2's function, now called.
MOD="$DEAD"
printf 'package main\n\nfunc dead() {}\n\nfunc init() { dead() }\n' > "${MOD}/dead.go"
run_gate
want_green_ok "mutation: case 2's function called from the program is green"

# --- Case 5: a function only a test calls.
new_module "test-only"
printf '\nfunc testOnly() int { return 1 }\n' >> "${MOD}/lib/lib.go"
printf 'package lib\n\nimport "testing"\n\nfunc TestTestOnly(t *testing.T) {\n\tif testOnly() != 1 {\n\t\tt.Fatal("testOnly")\n\t}\n}\n' \
  > "${MOD}/lib/lib_test.go"
run_gate
want_green_ok "a function called only from a test is green (-test: tests are roots)"

# --- Case 6: MUTATION PROOF. The gate without -test.
if mutant "no-test-flag" 's/ -test / /'; then
  run_gate "$MUTANT"
  want_red "mutation: without -test, case 5's test-only function is red" "unreachable func: testOnly"
fi

# --- Case 6b: a cold runner (forsgren#210). `go tool -n` writes its
# "go: downloading ..." lines on stderr before it prints the path; a go shim
# does the same here. The gate must keep them out of the tool path.
SHIM="${TMP}/shim"
mkdir -p "$SHIM"
REAL_GO="$(command -v go)"
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n deadcode" ]]; then
  echo "go: downloading golang.org/x/tools v0.0.0" >&2
  echo "go: downloading golang.org/x/mod v0.0.0" >&2
fi
exec "$REAL_GO" "\$@"
EOF
chmod +x "${SHIM}/go"
new_module "cold"
capture env PATH="${SHIM}:${PATH}" "$GATE" "$MOD"
want_green_ok "cold runner: download lines on stderr of go tool -n do not reach the tool path"
if grep -qF -- "could not run" <<< "$OUT"; then
  fail "cold runner: the gate reported it could not run. Output: ${OUT}"
fi

# --- Case 6bb: MUTATION PROOF. The old 2>&1 capture put back (the -x check
# disabled too: it would catch the polluted path with its own message) is red
# on the cold runner as an exit 127.
if selftest_lib_mutant "$GATE" Scripts/lib_go_tool.sh "${TMP}/stderr-captured" '/go tool -n/s/1")"/1" 2>\&1)"/; s/^  if \[ ! -f .*$/  if false; then/'; then
  capture env PATH="${SHIM}:${PATH}" "$MUTANT" "$MOD"
  want_red "mutation: with stderr captured into the tool path, a cold runner is red as the exit 127" "could not run"
fi

# --- Case 6bc: the path go prints is not a built binary: red with its reason.
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n deadcode" ]]; then
  echo "${TMP}/not-built/deadcode"
  exit 0
fi
exec "$REAL_GO" "\$@"
EOF
capture env PATH="${SHIM}:${PATH}" "$GATE" "$MOD"
want_red "a tool path that is not built is red, naming the reason" "was not built"

# --- Tool failure (forsgren#216): the tool itself fails. A go shim whose
# `go tool -n deadcode` names a stub tool that exits $STUB_TOOL_RC: the gate is red as
# a tool that did not run, and never prints the OK line of a pass. The stub says
# nothing: its exit code is the only sign it failed.
cat > "${TMP}/failing-tool" <<'EOF'
#!/bin/sh
exit "${STUB_TOOL_RC:-2}"
EOF
chmod +x "${TMP}/failing-tool"
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n deadcode" ]]; then
  echo "${TMP}/failing-tool"
  exit 0
fi
exec "$REAL_GO" "\$@"
EOF
capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=2 "$GATE" "$MOD"
want_red "a tool that exits 2 is red, never a pass" "could not run (exit 2)"
if grep -qF -- "OK:" <<< "$OUT"; then
  fail "a tool that exits 2 printed the OK line of a pass. Output: ${OUT}"
fi
capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=1 "$GATE" "$MOD"
want_red "a tool that exits 1 is red, never a pass" "could not run (exit 1)"
if grep -qF -- "OK:" <<< "$OUT"; then
  fail "a tool that exits 1 printed the OK line of a pass. Output: ${OUT}"
fi

# MUTATION PROOF: a helper that swallows the tool's exit code turns the case
# above green, so Scripts/lib_go_tool.sh returning the tool's own code is what
# keeps check_deadcode.sh red here.
if selftest_lib_mutant "$GATE" Scripts/lib_go_tool.sh "${TMP}/swallowed" '/BIN" "/s/$/ || true/'; then
  capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=2 "$MUTANT" "$MOD"
  want_green_ok "mutation: a helper that swallows the exit code lets the failing tool pass"
fi

# --- Case 7: no main package.
new_module "no-main"
rm "${MOD}/main.go"
run_gate
want_red "a module with no main package is red" "no main package"

# --- Case 8: a module that does not compile.
new_module "broken"
printf 'package main\n\nfunc broken() int { return "x" }\n' > "${MOD}/broken.go"
run_gate
want_red "a module that does not compile is red, as a tool error" "deadcode could not run"

# --- Case 9: a module directory that does not exist.
MOD="${TMP}/nope"
run_gate
want_red "a missing module directory is red" "module directory not found"

selftest_end "the dead-code gate does not tell reachable from unreachable" \
  "dead-code gate is red on an unreachable function (exported or not), on no main package, on a module that does not compile and on a missing module, green when everything is reachable from main or a test, and -test is shown to be what keeps a test-only function green"
