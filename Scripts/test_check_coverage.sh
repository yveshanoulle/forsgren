#!/usr/bin/env bash
# Scripts/test_check_coverage.sh
#
# Self-test for Scripts/check_coverage.sh, run before the gate it validates.
#
# forsgren's own, in bash (forsgren#1, ladder step 22): the gate ports
# MenoPower's Scripts/go/check_coverage.py, whose test
# (Scripts/go/test_check_coverage.py) pins only its total recomputation and
# its FLOORWARN line. The rules pinned here, MenoPower's unless marked:
#   - a function measured below its floor is red, naming it and both numbers.
#   - a function at or above its floor is green; a floor of 0.0 is tracked,
#     not enforced.
#   - a measured function missing from the thresholds file is red: it must
#     be registered, at 0.0 (the estate rule: never guess a floor).
#   - the total measured below the total floor is red.
#   - a floor below the ratchet rule (100.0 at 100%, else measured - 0.1)
#     stays green and is counted into ONE line,
#     `FLOORWARN: N coverage floor(s) should be raised in <thresholds>`
#     (MenoPower #504); a floor exactly at measured - 0.1 is not counted.
#   - forsgren: no coverage data is red. The data is the profile the Go-tests
#     gate writes (no second test run), and that gate removes it when go test
#     is red, so a red test run never leaves coverage behind to be judged.
#   - forsgren: a thresholds file is read line by line in one fixed JSON
#     shape, and a line outside it is red: the gate never guesses.
#
# The module under test: Two (1 statement) and Pick (3 statements), one test
# calling Two() and Pick(true). Measured: Two 100.0%, Pick 66.7%, total 75.0%.
#
#   1. floors at the measured values                  -> exit 0, no FLOORWARN
#   2. Pick's floor 70.0                              -> exit 1, Pick 66.7% < 70.0%
#   3. Pick not registered                            -> exit 1, register at 0.0
#   4. Pick registered at 0.0                         -> exit 0, FLOORWARN: 1
#   5. Two at 99.9, Pick at 60.0                      -> exit 0, FLOORWARN: 2
#   6. Pick at 66.6, exactly measured - 0.1           -> exit 0, no FLOORWARN
#   7. the total floor 80.0                           -> exit 1, total 75.0% < 80.0%
#   8. no profile (go test never ran)                 -> exit 1, no coverage data
#   9. a profile holding no function                  -> exit 1, no coverage data
#  10. go test red                                    -> the Go-tests gate leaves no
#                                                        profile, coverage is red
#  11. a thresholds line outside the shape            -> exit 1, naming the line
#  12. no thresholds file                             -> exit 1
#  13. MUTATION PROOF: the gate with `actual < floor` turned into
#      `actual <= floor` is red on case 1, naming Pick at its floor: the
#      comparison is what keeps a function AT its floor green
#  14. MUTATION PROOF: the gate with the ratchet buffer `actual - 0.1` turned
#      into `actual - 0.0` counts case 6's floor: the buffer is what keeps a
#      floor at measured - 0.1 out of FLOORWARN
#  15. MUTATION PROOF: the Go-tests gate with its `rm -f "$PROFILE"` lines
#      removed leaves case 10's profile behind, and the coverage gate judges
#      it (no `no coverage data`): the removal is what makes case 10 red

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_coverage.sh"
GO_TESTS="./Scripts/check_go_tests.sh"
PROFILE_REL=".build/go-coverage.out"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "coverage gate self-test"

[[ -x "$GATE" ]] || selftest_abort "the coverage gate ${GATE} is missing (or not executable): nothing holds a Go function to its coverage floor"

# run_gate <gate> <module> — sets RC and OUT (stdout and stderr together).
run_gate() {
  capture "$1" "$2"
}
check_absent() { # <name> <fixed-string that must not appear>
  if grep -qF -- "$2" <<< "$OUT"; then
    fail "$1 — the output says: $2. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# new_module <name> <test-body> — a module with Two and Pick, and one test.
new_module() {
  MOD="${TMP}/$1"
  mkdir -p "$MOD"
  printf 'module example.com/m\n\ngo 1.26.1\n' > "${MOD}/go.mod"
  cat > "${MOD}/m.go" <<'GO'
package m

// Two returns 2.
func Two() int { return 2 }

// Pick returns 1 when b is true, else 0.
func Pick(b bool) int {
	if b {
		return 1
	}
	return 0
}
GO
  printf 'package m\n\nimport "testing"\n\nfunc TestTwo(t *testing.T) {\n\t%s\n}\n' "$2" > "${MOD}/m_test.go"
}

# go_tests <go-tests-gate> — runs the Go-tests gate on $MOD, which writes the
# profile; its own verdict is checked by the cases that need it.
go_tests() {
  capture "$1" "$MOD"
  GO_OUT="$OUT"
  GO_RC="$RC"
}

# thresholds <total> <two> <pick> — writes $MOD/coverage_thresholds.json; a
# floor of `-` leaves that function unregistered.
thresholds() {
  {
    printf '{\n  "_comment": "fixture floors",\n  "total": %s,\n  "functions": {\n' "$1"
    local entries=''
    [[ "$2" == "-" ]] || entries="${entries}    \"example.com/m/m.go:Two\": $2,"$'\n'
    [[ "$3" == "-" ]] || entries="${entries}    \"example.com/m/m.go:Pick\": $3,"$'\n'
    printf '%s' "${entries%,$'\n'}"
    [[ -z "$entries" ]] || printf '\n'
    printf '  }\n}\n'
  } > "${MOD}/coverage_thresholds.json"
}

PASSING='if Two() != 2 || Pick(true) != 1 { t.Fatal("want 2 and 1") }'

new_module "measured" "$PASSING"
go_tests "$GO_TESTS"
if [[ "$GO_RC" -ne 0 || ! -s "${MOD}/${PROFILE_REL}" ]]; then
  fail "the Go-tests gate did not write ${PROFILE_REL} on a green run (exit ${GO_RC}). Output: ${GO_OUT}"
fi
MEASURED="$MOD"

# --- Case 1: floors at the measured values.
thresholds 75.0 100.0 66.7
run_gate "$GATE" "$MEASURED"
want_exit "floors at the measured values are green" 0 "OK:"
check_absent "and nothing is counted to raise" "FLOORWARN"

# --- Case 2: one function below its floor.
thresholds 75.0 100.0 70.0
run_gate "$GATE" "$MEASURED"
want_exit "a function below its floor is red, naming it and both numbers" 1 \
  "example.com/m/m.go:Pick: 66.7% is below its floor 70.0%"

# --- Case 3: a measured function that is not registered.
thresholds 75.0 100.0 -
run_gate "$GATE" "$MEASURED"
want_exit "an unregistered function is red, to be registered at 0.0" 1 \
  "example.com/m/m.go:Pick: 66.7% is not registered in coverage_thresholds.json — register it at 0.0"

# --- Case 4: registered at 0.0, tracked, not enforced.
thresholds 75.0 100.0 0.0
run_gate "$GATE" "$MEASURED"
want_exit "a floor of 0.0 is green, and counted to raise" 0 \
  "FLOORWARN: 1 coverage floor(s) should be raised in coverage_thresholds.json"

# --- Case 5: two floors below the ratchet rule.
thresholds 75.0 99.9 60.0
run_gate "$GATE" "$MEASURED"
want_exit "floors below the ratchet rule are green, counted in one FLOORWARN line" 0 \
  "FLOORWARN: 2 coverage floor(s) should be raised in coverage_thresholds.json"

# --- Case 6: a floor exactly at measured - 0.1 is already ratcheted.
thresholds 75.0 100.0 66.6
run_gate "$GATE" "$MEASURED"
want_exit "a floor at measured - 0.1 is green" 0 "OK:"
check_absent "and is not counted to raise" "FLOORWARN"

# --- Case 7: the total below its floor.
thresholds 80.0 100.0 66.7
run_gate "$GATE" "$MEASURED"
want_exit "a total below its floor is red, with both numbers" 1 \
  "total: 75.0% is below its floor 80.0%"

# --- Case 8: no profile at all.
new_module "never-tested" "$PASSING"
thresholds 75.0 100.0 66.7
run_gate "$GATE" "$MOD"
want_exit "no profile is red" 1 "no coverage data"

# --- Case 9: a profile that holds no function.
mkdir -p "${MOD}/.build"
printf 'mode: set\n' > "${MOD}/${PROFILE_REL}"
run_gate "$GATE" "$MOD"
want_exit "a profile holding no function is red" 1 "no coverage data"

# --- Case 10: a red go test leaves no profile behind.
new_module "red-tests" 't.Fatal("deliberately red")'
thresholds 75.0 100.0 66.7
go_tests "$GO_TESTS"
run_gate "$GATE" "$MOD"
want_exit "after a red Go-tests run, coverage is red with no data" 1 "no coverage data"

# --- Case 11: a thresholds line outside the fixed shape.
MOD="$MEASURED"
printf '{"total": 75.0}\n' > "${MOD}/coverage_thresholds.json"
run_gate "$GATE" "$MOD"
want_exit "a thresholds line outside the shape is red, naming the line" 1 \
  "coverage_thresholds.json:1: cannot read"

# --- Case 12: no thresholds file.
rm -f "${MOD}/coverage_thresholds.json"
run_gate "$GATE" "$MOD"
want_exit "no thresholds file is red" 1 "no thresholds file"

# mutant <dir> <source> <sed-expression> — a mutated copy of <source> at
# $TMP/<dir>/<source>; sets MUTANT, or fails the case when the edit changed
# nothing (a vacuous proof), and the proof is not run.
mutant() {
  MUTANT="${TMP}/$1/$2"
  selftest_mutant "$2" "$MUTANT" "$3"
}

# --- Case 13: MUTATION PROOF. `<` turned into `<=`.
thresholds 75.0 100.0 66.7
if mutant "mutant-le" "$GATE" 's/actual < floor/actual <= floor/'; then
  run_gate "$MUTANT" "$MEASURED"
  want_exit "mutation: with <= instead of <, case 1 is red, Pick at its floor" 1 \
    "example.com/m/m.go:Pick: 66.7% is below its floor 66.7%"
fi

# --- Case 14: MUTATION PROOF. No ratchet buffer.
thresholds 75.0 100.0 66.6
if mutant "mutant-buffer" "$GATE" 's/actual - 0\.1/actual - 0.0/'; then
  run_gate "$MUTANT" "$MEASURED"
  want_exit "mutation: without the 0.1 buffer, case 6's floor is counted" 0 \
    "FLOORWARN: 1 coverage floor(s) should be raised in coverage_thresholds.json"
fi

# --- Case 15: MUTATION PROOF. The Go-tests gate keeps a red run's profile.
new_module "red-tests-kept" 't.Fatal("deliberately red")'
thresholds 75.0 100.0 66.7
if mutant "mutant-keep" "$GO_TESTS" "/rm -f \"\\\$PROFILE\"/d"; then
  go_tests "$MUTANT"
  run_gate "$GATE" "$MOD"
  if grep -qF "no coverage data" <<< "$OUT"; then
    RC=99
    OUT="the coverage gate still found no data: ${OUT}"
  fi
  want_exit "mutation: a Go-tests gate that keeps a red run's profile gets it judged" 1 \
    "example.com/m/m.go:Pick: 0.0% is below its floor 66.7%"
fi

selftest_end "the coverage gate does not hold functions and the total to their floors" \
  "the coverage gate is red below a floor, on an unregistered function, on a total below its floor, on no coverage data and on an unreadable thresholds file, green at a floor, and counts floors to raise into one FLOORWARN line"
