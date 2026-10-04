#!/usr/bin/env bash
# Scripts/test_check_data_guard.sh
#
# Self-test for Scripts/check_data_guard.sh, run before the gate it validates.
# Each case is a throwaway git repository under one temp root. Every name
# in it is made up (acme); none is a real repository, organisation or
# domain.
#   1. a clean repository                         -> green
#   2. history.csv at the root                    -> red, naming the file
#   3. a config file under testdata/              -> green (a fixture)
#   4. a config file NOT git-added                -> green (untracked scratch
#                                                    is not judged)
#   5. a repository with no tracked files         -> red: the walk found nothing
#   6. a wildcard arm really matches: a tracked  -> red, each named
#      root events.jsonl (*.jsonl), x.history.csv
#      (*.history.csv) and forsgren.config.yaml
#      (forsgren.config.*)
#   7. a tracked data/deployments.csv, and any    -> red, each named
#      other tracked file under a top-level data/
#   8. a deployments.csv elsewhere                -> red, named
#   9. controls: testdata/ fixtures (also under   -> green
#      testdata/data/), a Go test file, and a
#      deeper internal/data/ code directory
#  10. a commits.csv elsewhere (forsgren#16)      -> red, named
#  11. a failures.csv elsewhere (forsgren#18)     -> red, named
# Mutation proofs, each against a copy of the gate (the patterns are `case`
# arms of guarded_reason, one per line):
#   - case 2: with the history.csv arm deleted, case 2's repository must turn
#     green, so case 2 is red BECAUSE of that arm, not because of something
#     else in its repository.
#   - case 7: with the data/* arm of guarded_path_reason deleted, a
#     repository holding only data/notes.txt must turn green.
#   - case 8: with the deployments.csv arm deleted, a repository holding
#     only ops/deployments.csv must turn green.
#   - case 10: with the commits.csv arm deleted, a repository holding only
#     ops/commits.csv must turn green.
#   - case 11: with the failures.csv arm deleted, a repository holding only
#     ops/failures.csv must turn green.
#   - case 6: with every arm whose pattern holds a `*` quoted (so it matches
#     only the literal text), case 6's repository must turn green with none
#     of its three files named, while case 2's repository stays red. Every
#     other red case is matched by a literal pattern, so a gate that stopped
#     glob-matching would pass them all; case 6 is the one that notices
#     (forsgren#1, step 12.2a, automated in 12.2c).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="$(pwd)/Scripts/check_data_guard.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "data-guard gate self-test"

# new_repo <name> — a git repository with one ordinary tracked Go file.
new_repo() {
  REPO="${TMP}/$1"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  write_file "main.go" $'package main\n\nfunc main() {}\n' track
}

# write_file <path> <content> [track] — writes a file; `track` git-adds it.
write_file() {
  mkdir -p "$(dirname "${REPO}/$1")"
  printf '%s' "$2" > "${REPO}/$1"
  if [[ "${3:-}" == "track" ]]; then
    git -C "$REPO" add "$1"
  fi
}

# run_gate — runs GATE against $REPO; sets RC and OUT.
run_gate() {
  capture "$GATE" "$REPO"
}

# run_mutant <mutant> <repo-name> — runs a mutated gate against a case's
# repository; sets RC and OUT.
run_mutant() {
  capture "$1" "${TMP}/$2"
}

# arm_deleted_proof <case> <arm> <anchor> <mutant> <repo-name> <holding>: the
# mutation proof of a case red for one arm. Writes <mutant>, a copy of the
# gate without the arm lines matching the ERE <anchor>; the copy must differ
# (else the anchor stopped matching and the proof proves nothing) and must go
# green on the case's repository <repo-name>, which holds only <holding>: if
# it stayed red, the case was red for another reason than <arm>.
arm_deleted_proof() {
  local case_no="$1" arm="$2" anchor="$3" mutant="$4" repo="$5" holding="$6"
  grep -vE "$anchor" "$GATE" > "$mutant"
  chmod +x "$mutant"
  if cmp -s "$GATE" "$mutant"; then
    fail "mutation proof (case ${case_no}): deleting the '${arm}) why=' arm changed nothing in ${GATE} — the anchor no longer matches, so this proof proves nothing"
    return 0
  fi
  run_mutant "$mutant" "$repo"
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof (case ${case_no}): a gate without the ${arm} arm is still red on a repository holding only ${holding}. Output: ${OUT}"
  else
    echo "  ok: without the ${arm} arm, a repository holding only ${holding} is green (case ${case_no} is red for that arm)"
  fi
}

new_repo "clean"
write_file "internal/m/m_test.go" $'package m\n// acme/app is the made-up fixture repository.\n' track
write_file "internal/m/testdata/history.csv" $'date,metric,value\n' track
run_gate
want_green "a clean repository is green"

new_repo "history-root"
write_file "history.csv" $'date,metric,value\n' track
run_gate
want_red "history.csv at the root is red and named" "❌ FAIL: history.csv"

new_repo "config-in-testdata"
write_file "testdata/forsgren.config.yml" $'repos:\n  - acme/app\n' track
write_file "testdata/events.jsonl" $'{"run":1}\n' track
run_gate
want_green "config and events under testdata/ are fixtures, green"

new_repo "untracked-config"
write_file "config.yml" $'repos:\n  - acme/app\n'
run_gate
want_green "an untracked config.yml is not judged"

REPO="${TMP}/no-files"
mkdir -p "$REPO"
git -C "$REPO" init -q
run_gate
want_red "a repository with no tracked files is red" "no tracked files"

new_repo "wildcard-rows"
write_file "events.jsonl" $'{"run":1}\n' track
write_file "x.history.csv" $'date,metric,value\n' track
write_file "forsgren.config.yaml" $'repos:\n  - acme/app\n' track
run_gate
want_red "a root events.jsonl is red and named (the *.jsonl arm)" "❌ FAIL: events.jsonl"
want_said "an x.history.csv is red and named (the *.history.csv arm)" "❌ FAIL: x.history.csv"
want_said "a forsgren.config.yaml is red and named (the forsgren.config.* arm)" "❌ FAIL: forsgren.config.yaml"

new_repo "data-dir"
write_file "data/deployments.csv" $'# forsgren history v1\n' track
write_file "data/notes.txt" $'x\n' track
write_file "data/commits.csv" $'# forsgren commits v1\n' track
write_file "data/failures.csv" $'# forsgren failures v1\n' track
run_gate
want_red "a tracked data/deployments.csv is red and named" "❌ FAIL: data/deployments.csv"
want_said "any other file under a top-level data/ is red and named" "❌ FAIL: data/notes.txt"
want_said "a tracked data/commits.csv is red and named" "❌ FAIL: data/commits.csv"
want_said "a tracked data/failures.csv is red and named" "❌ FAIL: data/failures.csv"

new_repo "deployments-elsewhere"
write_file "ops/deployments.csv" $'# forsgren history v1\n' track
run_gate
want_red "a deployments.csv outside data/ is red and named" "❌ FAIL: ops/deployments.csv"

new_repo "commits-elsewhere"
write_file "ops/commits.csv" $'# forsgren commits v1\n' track
run_gate
want_red "a commits.csv outside data/ is red and named" "❌ FAIL: ops/commits.csv"

new_repo "failures-elsewhere"
write_file "ops/failures.csv" $'# forsgren failures v1\n' track
run_gate
want_red "a failures.csv outside data/ is red and named" "❌ FAIL: ops/failures.csv"

new_repo "history-fixtures"
write_file "internal/history/testdata/deployments.csv" $'# forsgren history v1\n' track
write_file "internal/history/testdata/commits.csv" $'# forsgren commits v1\n' track
write_file "internal/history/testdata/failures.csv" $'# forsgren failures v1\n' track
write_file "internal/history/testdata/data/deployments.csv" $'# forsgren history v1\n' track
write_file "internal/history/history_test.go" $'package history\n// acme/app is the made-up fixture repository.\n' track
write_file "internal/data/data.go" $'package data\n' track
run_gate
want_green "history fixtures under testdata/, a Go test file and internal/data/ are not installation data"

new_repo "data-dir-notes"
write_file "data/notes.txt" $'x\n' track

# ---------------------------------------------------------------------------
# Mutation proof for case 2: the same repository against a copy of the gate
# with the history.csv arm deleted. The mutant must change the copy (else the
# anchor stopped matching and this proves nothing) and must go green: if it
# stayed red, case 2 was red for some other reason than the arm it claims to
# test.
# ---------------------------------------------------------------------------
MUTANT="${TMP}/check_data_guard_mutant.sh"
grep -vE '^[[:space:]]*history\.csv\) why=' "$GATE" > "$MUTANT"
chmod +x "$MUTANT"

if cmp -s "$GATE" "$MUTANT"; then
  fail "mutation proof (case 2): deleting the 'history.csv) why=' arm changed nothing in ${GATE} — the anchor no longer matches, so this proof proves nothing"
else
  run_mutant "$MUTANT" "history-root"
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof (case 2): a gate without the history.csv arm is still red on case 2's repository — case 2 is red for another reason than the arm it tests. Output: ${OUT}"
  else
    echo "  ok: without the history.csv arm, case 2's repository is green (case 2 is red for that arm)"
  fi
fi

# ---------------------------------------------------------------------------
# Mutation proofs for cases 7, 8, 10 and 11 (arm_deleted_proof): with one arm
# deleted, a repository holding only the file that arm names must turn
# green, so each case is red BECAUSE of its arm. Case 7: the data/* arm of
# guarded_path_reason, and not the deployments.csv name. Case 8: the
# deployments.csv arm (forsgren#12, step 8). Case 10: the commits.csv arm
# (forsgren#16, step 1). Case 11: the failures.csv arm (forsgren#18, step 1).
# ---------------------------------------------------------------------------
arm_deleted_proof 7 "data/*" '^[[:space:]]*data/\*\) why=' \
  "${TMP}/check_data_guard_nodir.sh" "data-dir-notes" "data/notes.txt"
arm_deleted_proof 8 "deployments.csv" '^[[:space:]]*deployments\.csv\) why=' \
  "${TMP}/check_data_guard_nodeploy.sh" "deployments-elsewhere" "ops/deployments.csv"
arm_deleted_proof 10 "commits.csv" '^[[:space:]]*commits\.csv\) why=' \
  "${TMP}/check_data_guard_nocommits.sh" "commits-elsewhere" "ops/commits.csv"
arm_deleted_proof 11 "failures.csv" '^[[:space:]]*failures\.csv\) why=' \
  "${TMP}/check_data_guard_nofailures.sh" "failures-elsewhere" "ops/failures.csv"

# ---------------------------------------------------------------------------
# Mutation proof for case 6: a copy of the gate with every arm whose pattern
# holds a `*` quoted, so it matches only its literal text. The anchor is the
# arm shape `<pattern>) why=`, which only guarded_reason's arms have. The
# mutant must quote at least the three wildcard arms case 6 exercises (else
# the anchor stopped matching), must go green on case 6's repository with
# none of its files named (case 6 is red BECAUSE the arms glob-match), and
# must stay red on case 2's repository (the mutation stopped glob matching
# only; the literal arms still work, so a green above is not a broken gate).
# ---------------------------------------------------------------------------
LITERAL="${TMP}/check_data_guard_literal.sh"
sed -E 's/^([[:space:]]*)([^[:space:]"]*\*[^[:space:]"]*)\) why=/\1"\2") why=/' \
  "$GATE" > "$LITERAL"
chmod +x "$LITERAL"
quoted="$(grep -cE '^[[:space:]]*"[^"]*\*[^"]*"\) why=' "$LITERAL" || true)"

if [[ "$quoted" -lt 3 ]]; then
  fail "mutation proof (case 6): quoting the wildcard arms changed ${quoted} arm(s) in ${GATE} (want at least the 3 case 6 exercises) — the anchor no longer matches, so this proof proves nothing"
else
  run_mutant "$LITERAL" "wildcard-rows"
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof (case 6): a gate whose wildcard arms match only literally is still red on case 6's repository — case 6 is red for another reason than glob matching. Output: ${OUT}"
  elif grep -qE "FAIL: (events\.jsonl|x\.history\.csv|forsgren\.config\.yaml)" <<< "$OUT"; then
    fail "mutation proof (case 6): a gate whose wildcard arms match only literally still names a case-6 file. Output: ${OUT}"
  else
    echo "  ok: with its ${quoted} wildcard arms matching only literally, case 6's repository is green (case 6 is red because the arms glob-match)"
  fi

  run_mutant "$LITERAL" "history-root"
  if [[ "$RC" -eq 0 ]] || ! grep -qF "❌ FAIL: history.csv" <<< "$OUT"; then
    fail "mutation proof (case 6): the literal-only gate is no longer red on case 2's repository — the mutation broke more than glob matching, so case 6 going green above proves nothing. Output: ${OUT}"
  else
    echo "  ok: the literal-only gate is still red on case 2's repository (the mutation stopped glob matching, nothing else)"
  fi
fi

selftest_end "the data-guard gate does not tell fixtures from installation data" \
  "data-guard gate is red on installation config/data outside testdata/ and on a walk over nothing"
