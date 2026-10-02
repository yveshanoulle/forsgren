#!/usr/bin/env bash
# Scripts/test_check_test_dupl.sh
#
# Self-test for Scripts/check_test_dupl.sh, run before the gate it validates.
#
# PORTED (forsgren#1, ladder step 20) from
# MenoPower/Scripts/common/test_check_test_dupl.sh, whose reason for existing holds
# here: that gate once reported "0 findings / clean" for every module while
# running nothing (a mktemp bug dropped the config's .yml extension, so
# golangci-lint could not load it and linted nothing). A gate that cannot
# tell broken from clean is worse than no gate.
#
# Adapted: MenoPower finds its root with `git rev-parse --show-toplevel`
# from Scripts/common/; forsgren's Scripts/ is flat (the climb ruling on
# forsgren#1), so this one uses the repo's `cd "$(dirname "$0")/.."`.
# MenoPower's two cases (1 and 2) asserted the exit code only; here every
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

# --- Case 6: MUTATION PROOF. path-except turned into path.
# The mutant finds its root as the gate does, one level above its Scripts/,
# and the pinned golangci-lint through the go.mod and go.sum it finds there.
MUTANT="${TMP}/mutant/Scripts/check_test_dupl.sh"
if selftest_mutant "$GATE" "$MUTANT" 's/path-except:/path:/'; then
  cp go.mod "${TMP}/mutant/"
  if [[ -f go.sum ]]; then cp go.sum "${TMP}/mutant/"; fi
  run_gate "$MUTANT" "$DUP"
  want_exit "mutation: with path instead of path-except, case 1 is green" 0 "OK:"
  run_gate "$MUTANT" "$PROD_DUP"
  want_exit "  ... and case 3 red, naming dupl: case 3's duplication is real" 1 "(dupl)"
fi

selftest_end "the test-dupl gate does not tell green from red" \
  "test-dupl gate is red on duplicated test code and on no test file, green on clean test code and on production-only duplication, a tooling error on a missing module, and its path-except filter is what points it at test code"
