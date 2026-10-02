#!/usr/bin/env bash
# Scripts/test_check_deadcode.sh
#
# Self-test for Scripts/check_deadcode.sh, run before the gate it validates.
#
# NEW (forsgren#1, ladder step 23). MenoPower runs `deadcode -test ./...` in
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
#   5. a function called only from a _test.go file    -> green: MenoPower's
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

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: dead-code gate self-test aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

if [[ ! -x "$GATE" ]]; then
  echo "❌ FAIL: the dead-code gate ${GATE} is missing (or not executable): nothing runs deadcode"
  COMPLETED=1
  exit 1
fi

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

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
  set +e
  OUT="$("${1:-$GATE}" "$MOD" 2>&1)"
  RC=$?
  set -e
}

want_green() {
  if [[ "$RC" -ne 0 ]]; then
    fail "$1: the gate exited ${RC}. Output: ${OUT}"
  elif ! grep -qF -- "OK:" <<< "$OUT"; then
    fail "$1: the gate exited 0 without its OK line. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# want_red <case> <reason> — the last run failed and said <reason>.
want_red() {
  if [[ "$RC" -eq 0 ]]; then
    fail "$1: the gate exited 0. Output: ${OUT}"
  elif ! grep -qF -- "$2" <<< "$OUT"; then
    fail "$1: the gate failed without saying '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# mutant <name> <sed-expression> — a mutated copy of the gate at
# $TMP/<name>/Scripts/, with this repository's go.mod and go.sum beside it so
# `go tool -n deadcode` resolves the same pinned deadcode there; sets
# MUTANT, or fails the case when the edit changed nothing (a vacuous proof).
mutant() {
  mkdir -p "${TMP}/$1/Scripts"
  cp go.mod go.sum "${TMP}/$1/"
  MUTANT="${TMP}/$1/Scripts/check_deadcode.sh"
  sed "$2" "$GATE" > "$MUTANT"
  chmod +x "$MUTANT"
  if cmp -s "$GATE" "$MUTANT"; then
    fail "mutation $1 changed nothing in ${GATE}: the proof would be vacuous"
    return 1
  fi
}

# --- Case 1: everything reachable.
new_module "clean"
run_gate
want_green "every function reachable from main is green"

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
want_green "mutation: case 2's function called from the program is green"

# --- Case 5: a function only a test calls.
new_module "test-only"
printf '\nfunc testOnly() int { return 1 }\n' >> "${MOD}/lib/lib.go"
printf 'package lib\n\nimport "testing"\n\nfunc TestTestOnly(t *testing.T) {\n\tif testOnly() != 1 {\n\t\tt.Fatal("testOnly")\n\t}\n}\n' \
  > "${MOD}/lib/lib_test.go"
run_gate
want_green "a function called only from a test is green (-test: tests are roots)"

# --- Case 6: MUTATION PROOF. The gate without -test.
if mutant "no-test-flag" 's/ -test / /'; then
  run_gate "$MUTANT"
  want_red "mutation: without -test, case 5's test-only function is red" "unreachable func: testOnly"
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

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: the dead-code gate does not tell reachable from unreachable (see the FAIL lines above)"
  exit 1
fi

echo "OK: dead-code gate is red on an unreachable function (exported or not), on no main package, on a module that does not compile and on a missing module, green when everything is reachable from main or a test, and -test is shown to be what keeps a test-only function green"
