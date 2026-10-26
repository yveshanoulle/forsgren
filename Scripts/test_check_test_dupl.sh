#!/usr/bin/env bash
# Scripts/test_check_test_dupl.sh
#
# Self-test for Scripts/check_test_dupl.sh, run before the gate it validates.
#
# PORTED (forsgren#1, ladder step 20) from
# source-repo/Scripts/common/test_check_test_dupl.sh, whose reason for existing holds
# here: that gate once reported "0 findings / clean" for every module while
# running nothing (a mktemp bug dropped the config's .yml extension, so
# golangci-lint could not load it and linted nothing). A gate that cannot
# tell broken from clean is worse than no gate.
#
# Adapted: another estate repository finds its root with `git rev-parse --show-toplevel`
# from Scripts/common/; forsgren's Scripts/ is flat (the climb ruling on
# forsgren#1), so this one uses the repo's `cd "$(dirname "$0")/.."`.
# Another estate repository's two cases (1 and 2) asserted the exit code only; here every
# case asserts the exit code AND the reason, and forsgren adds 3 to 6.
#
# dupl's finding list is not deterministic (which clone is "the" duplicate),
# so no case asserts which lines are named; the reason and the count line are.
#
#   1. two test functions with identical bodies    -> exit 1, naming dupl
#   2. clean test code                             -> exit 0
#   3. the same duplication in NON-test files      -> exit 0: production
#      duplication is .golangci.yml's dupl (Scripts/check_go_lint.sh), not
#      this gate's
#   4. a module with no _test.go file              -> exit 1: a scan over no
#      test code is no pass
#   5. a module directory that does not exist      -> exit 2
#   6. MUTATION PROOF: the gate with its `path-except` filter turned into
#      `path` keeps only NON-test findings, and case 1 turns green: the
#      filter is what points the gate at test code; and case 3 turns red,
#      naming dupl: case 3's duplication is real, so its green is not vacuous

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_test_dupl.sh"
THRESHOLD=20

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "test-dupl gate self-test"

[[ -x "$GATE" ]] || selftest_abort "the test-dupl gate ${GATE} is missing (or not executable): nothing checks test code for duplication"

# run_gate <gate> <module> — sets RC and OUT (stdout and stderr together).
run_gate() {
  capture "$1" "$2" "$THRESHOLD"
}
# new_module <name> — a module with one package and no test yet.
new_module() {
  MOD="${TMP}/$1"
  mkdir -p "$MOD"
  printf 'module example.com/%s\n\ngo 1.26.1\n' "$1" > "${MOD}/go.mod"
  printf '// Package m is a dupl fixture.\npackage m\n' > "${MOD}/lib.go"
}

# write_twins <suffix> — two files, Alpha<suffix>.go and Beta<suffix>.go,
# each with one function of identical body: unmistakable duplication.
# <suffix> `_test` makes them test functions, empty makes them production.
write_twins() {
  local name
  for name in Alpha Beta; do
    if [[ "$1" == "_test" ]]; then
      cat > "${MOD}/${name}_test.go" <<GO
package m

import "testing"

func Test${name}(t *testing.T) {
	xs := []int{1, 2, 3, 4, 5}
	total := 0
	for _, x := range xs {
		total += x
	}
	if total != 15 {
		t.Errorf("expected 15, got %d", total)
	}
	if len(xs) != 5 {
		t.Errorf("expected 5 elements, got %d", len(xs))
	}
}
GO
    else
      cat > "${MOD}/${name}.go" <<GO
package m

import "fmt"

// Sum${name} sums one to five.
func Sum${name}() {
	xs := []int{1, 2, 3, 4, 5}
	total := 0
	for _, x := range xs {
		total += x
	}
	if total != 15 {
		fmt.Printf("expected 15, got %d", total)
	}
	if len(xs) != 5 {
		fmt.Printf("expected 5 elements, got %d", len(xs))
	}
}
GO
    fi
  done
}

# add_one_test — one short, unique test.
add_one_test() {
  cat > "${MOD}/only_test.go" <<'GO'
package m

import "testing"

func TestOnlyOne(t *testing.T) {
	if 1+1 != 2 {
		t.Fatal("math is broken")
	}
}
GO
}

# --- Case 1: duplicated test code.
new_module "dup"
write_twins "_test"
run_gate "$GATE" "$MOD"
want_exit "duplicated test code is red, naming dupl" 1 "(dupl)"
want_exit "  ... and counting the findings" 1 "test-code duplication findings:"
DUP="$MOD"

# --- Case 2: clean test code.
new_module "clean"
add_one_test
run_gate "$GATE" "$MOD"
want_exit "clean test code is green" 0 "OK:"

# --- Case 3: the same duplication in production code.
new_module "prod-dup"
write_twins ""
add_one_test
run_gate "$GATE" "$MOD"
want_exit "duplication in non-test code is not this gate's red" 0 "OK:"
PROD_DUP="$MOD"

# --- Case 4: no test file.
new_module "no-tests"
run_gate "$GATE" "$MOD"
want_exit "a module with no _test.go file is red" 1 "no _test.go file to check"

# --- Case 5: a module directory that does not exist.
run_gate "$GATE" "${TMP}/nope"
want_exit "a missing module directory is a tooling error" 2 "module directory not found"

# --- Case 5b: a cold runner (forsgren#210). `go tool -n` writes its
# "go: downloading ..." lines on stderr before it prints the path; a go shim
# does the same here. The gate must keep them out of the tool path.
SHIM="${TMP}/shim"
mkdir -p "$SHIM"
REAL_GO="$(command -v go)"
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n golangci-lint" ]]; then
  echo "go: downloading golang.org/x/tools v0.0.0" >&2
  echo "go: downloading golang.org/x/mod v0.0.0" >&2
fi
exec "$REAL_GO" "\$@"
EOF
chmod +x "${SHIM}/go"
new_module "cold"
add_one_test
capture env PATH="${SHIM}:${PATH}" "$GATE" "$MOD" "$THRESHOLD"
COLD="$MOD"
want_exit "cold runner: download lines on stderr of go tool -n do not reach the tool path" 0 "OK:"
if grep -qF -- "could not run" <<< "$OUT"; then
  fail "cold runner: the gate reported it could not run. Output: ${OUT}"
fi

# --- Case 5bb: MUTATION PROOF. The old 2>&1 capture put back (the -x check
# disabled too: it would catch the polluted path with its own message) is red
# on the cold runner as an exit 127.
if selftest_lib_mutant "$GATE" Scripts/lib_go_tool.sh "${TMP}/stderr-captured" '/go tool -n/s/1")"/1" 2>\&1)"/; s/^  if \[ ! -f .*$/  if false; then/'; then
  MUTANT_GATE="$MUTANT"
  capture env PATH="${SHIM}:${PATH}" "$MUTANT_GATE" "$COLD" "$THRESHOLD"
  want_red "mutation: with stderr captured into the tool path, a cold runner is red as the exit 127" "No such file or directory"
fi

# --- Case 5bc: the path go prints is not a built binary: red with its reason.
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n golangci-lint" ]]; then
  echo "${TMP}/not-built/golangci-lint"
  exit 0
fi
exec "$REAL_GO" "\$@"
EOF
capture env PATH="${SHIM}:${PATH}" "$GATE" "$COLD" "$THRESHOLD"
want_exit "a tool path that is not built is a tooling error, naming the reason" 2 "was not built"

# --- Tool failure (forsgren#216): the tool itself fails. A go shim whose
# `go tool -n golangci-lint` names a stub tool that exits $STUB_TOOL_RC: the gate is red as
# a tool that did not run, and never prints the OK line of a pass. The stub says
# nothing: its exit code is the only sign it failed.
cat > "${TMP}/failing-tool" <<'EOF'
#!/bin/sh
if [ -n "${STUB_TOOL_OUT:-}" ]; then printf '%s\n' "$STUB_TOOL_OUT"; fi
exit "${STUB_TOOL_RC:-2}"
EOF
chmod +x "${TMP}/failing-tool"
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n golangci-lint" ]]; then
  echo "${TMP}/failing-tool"
  exit 0
fi
exec "$REAL_GO" "\$@"
EOF
capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=2 "$GATE" "$COLD" "$THRESHOLD"
want_exit "a tool that exits 2 is a tooling error, never a pass" 2 "golangci-lint error (exit 2)"
if grep -qF -- "OK:" <<< "$OUT"; then
  fail "a tool that exits 2 printed the OK line of a pass. Output: ${OUT}"
fi

# MUTATION PROOF: a helper that swallows the tool's exit code turns the case
# above green, so Scripts/lib_go_tool.sh returning the tool's own code is what
# keeps check_test_dupl.sh red here.
if selftest_lib_mutant "$GATE" Scripts/lib_go_tool.sh "${TMP}/swallowed" '/BIN" "/s/$/ || true/'; then
  capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=2 "$MUTANT" "$COLD" "$THRESHOLD"
  want_exit "mutation: a helper that swallows the exit code lets the failing tool pass" 0 "OK:"
fi

# --- forsgren#217: an exit of 1 without a (dupl) line is not a pass. The config
# enables only dupl, so another issue line (here a typecheck error, which
# golangci-lint reports as an issue with exit 1) means the tool did not judge
# the code: a tooling error, exit 2, with the tool's output shown.
capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=1 \
  STUB_TOOL_OUT="x_test.go:3:1: undefined: foo (typecheck)" "$GATE" "$COLD" "$THRESHOLD"
want_exit "an exit of 1 without a (dupl) line is a tooling error, naming the reason" 2 "reported no (dupl) finding"
if grep -qF -- "OK:" <<< "$OUT"; then
  fail "an exit of 1 without a (dupl) line printed the OK line of a pass. Output: ${OUT}"
fi
if ! grep -qF -- "undefined: foo (typecheck)" <<< "$OUT"; then
  fail "an exit of 1 without a (dupl) line did not show the tool's output. Output: ${OUT}"
fi

# MUTATION PROOF: "exit 1 without dupl lines is OK" put back (the guard made
# inert) turns the case above green.
if selftest_lib_mutant Scripts/lib_go_tool.sh "$GATE" "${TMP}/exit1-ok" 's/ -eq 1 \] && / -eq 9 ] \&\& /'; then
  capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=1 \
    STUB_TOOL_OUT="x_test.go:3:1: undefined: foo (typecheck)" "${TMP}/exit1-ok/Scripts/check_test_dupl.sh" "$COLD" "$THRESHOLD"
  want_exit "mutation: exit 1 without a (dupl) line read as OK lets the typecheck error pass" 0 "OK:"
fi

# --- Lock (forsgren#437): golangci-lint takes a machine-wide file lock on
# start, so two gates in two checkouts at once refused each other ("parallel
# golangci-lint is running", exit 3) and read as a lint verdict. A stub
# stands in for the tool (the real one is never run here): it refuses with
# the lock message unless it is given --allow-parallel-runners, or always
# when $STUB_LOCK_ALWAYS is set. The gate must pass the flag, and a refusal
# that still comes must read as a tooling error naming the lock.
cat > "${TMP}/lock-tool" <<'EOF'
#!/bin/sh
if [ -z "${STUB_LOCK_ALWAYS:-}" ]; then
  for a in "$@"; do
    if [ "$a" = "--allow-parallel-runners" ]; then exit 0; fi
  done
fi
echo "Error: parallel golangci-lint is running"
exit 3
EOF
chmod +x "${TMP}/lock-tool"
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n golangci-lint" ]]; then
  echo "${TMP}/lock-tool"
  exit 0
fi
exec "$REAL_GO" "\$@"
EOF
capture env PATH="${SHIM}:${PATH}" "$GATE" "$COLD" "$THRESHOLD"
want_exit "two runs at once: the gate passes --allow-parallel-runners, so the lock never refuses it" 0 "OK:"
capture env PATH="${SHIM}:${PATH}" STUB_LOCK_ALWAYS=1 "$GATE" "$COLD" "$THRESHOLD"
want_exit "a lock refusal is a tooling error (exit 2) naming the lock" 2 "holds golangci-lint's machine-wide lock"
want_said "  ... and says it is no verdict on the code" "not a verdict on the code"
want_said "  ... with the red cross FAIL line" "❌ FAIL"
if grep -qF -- "findings:" <<< "$OUT"; then
  fail "a lock refusal was counted as duplication findings. Output: ${OUT}"
fi

# MUTATION PROOF: the gate without --allow-parallel-runners is refused by the
# lock, so the flag is what keeps two runs from failing each other.
if selftest_lib_mutant Scripts/lib_go_tool.sh "$GATE" "${TMP}/no-flag" 's/ --allow-parallel-runners//'; then
  capture env PATH="${SHIM}:${PATH}" "${TMP}/no-flag/Scripts/check_test_dupl.sh" "$COLD" "$THRESHOLD"
  want_exit "mutation: without the flag the lock refuses the gate" 2 "holds golangci-lint's machine-wide lock"
fi

# --- Case 6: MUTATION PROOF. path-except turned into path.
# The mutant finds its root as the gate does, one level above its Scripts/,
# and the pinned golangci-lint through the go.mod and go.sum it finds there.
MUTANT="${TMP}/mutant/Scripts/check_test_dupl.sh"
if selftest_mutant "$GATE" "$MUTANT" 's/path-except:/path:/'; then
  cp go.mod "${TMP}/mutant/"
  cp Scripts/lib_go_tool.sh "${TMP}/mutant/Scripts/"
  if [[ -f go.sum ]]; then cp go.sum "${TMP}/mutant/"; fi
  run_gate "$MUTANT" "$DUP"
  want_exit "mutation: with path instead of path-except, case 1 is green" 0 "OK:"
  run_gate "$MUTANT" "$PROD_DUP"
  want_exit "  ... and case 3 red, naming dupl: case 3's duplication is real" 1 "(dupl)"
fi

selftest_end "the test-dupl gate does not tell green from red" \
  "test-dupl gate is red on duplicated test code and on no test file, green on clean test code and on production-only duplication, a tooling error on a missing module, and its path-except filter is what points it at test code"
