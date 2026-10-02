#!/usr/bin/env bash
# Scripts/test_check_data_guard.sh
#
# Self-test for Scripts/check_data_guard.sh, run before the gate it validates.
# Each case is a throwaway git repository under one temp root. Every name
# in it is made up (acme, globex); none is a real repository, organisation or
# domain.
#   1. a clean repository                         -> green
#   2. history.csv at the root                    -> red, naming the file
#   3. a config file under testdata/              -> green (a fixture)
#   4. a config file NOT git-added                -> green (untracked scratch
#                                                    is not judged)
#   5. a fixture that mentions a private name     -> red, naming the file
#      from FORSGREN_PRIVATE_NAMES_FILE
#   6. FORSGREN_PRIVATE_NAMES_FILE unset          -> green, with the ⚠️
#                                                    skipped line
#   7. a names file with no names in it           -> red: a scan for nothing
#   8. a repository with no tracked files         -> red: the walk found nothing
#   9. names set, but no fixture or test file     -> red: the scan read nothing
#  10. a wildcard arm really matches: a tracked  -> red, each named
#      root events.jsonl (*.jsonl), x.history.csv
#      (*.history.csv) and forsgren.config.yaml
#      (forsgren.config.*)
# Mutation proofs, each against a copy of the gate (the patterns are `case`
# arms of guarded_reason, one per line):
#   - case 2: with the history.csv arm deleted, case 2's repository must turn
#     green, so case 2 is red BECAUSE of that arm, not because of something
#     else in its repository.
#   - case 10: with every arm whose pattern holds a `*` quoted (so it matches
#     only the literal text), case 10's repository must turn green with none
#     of its three files named, while case 2's repository stays red. Every
#     other red case is matched by a literal pattern, so a gate that stopped
#     glob-matching would pass them all; case 10 is the one that notices
#     (forsgren#1, step 12.2a, automated in 12.2c).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="$(pwd)/Scripts/check_data_guard.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "data-guard gate self-test"

# The made-up private names of the fixture owner, in a file outside every
# fixture repository, as a real installation keeps them outside forsgren.
NAMES="${TMP}/private-names.txt"
cat > "$NAMES" <<'NAMES'
# made-up private names for the data-guard fixture
globex-internal

acme-secret.example
NAMES

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

# run_gate [names-file] — runs GATE against $REPO; sets RC and OUT. With no
# argument FORSGREN_PRIVATE_NAMES_FILE is UNSET, not empty.
run_gate() {
  if [[ $# -gt 0 ]]; then
    capture env FORSGREN_PRIVATE_NAMES_FILE="$1" "$GATE" "$REPO"
  else
    capture env -u FORSGREN_PRIVATE_NAMES_FILE "$GATE" "$REPO"
  fi
}

# want_not_said <case> <text> — the last run's output does not contain <text>.
want_not_said() {
  if grep -qF -- "$2" <<< "$OUT"; then
    fail "$1: the output says '$2'. Output: ${OUT}"
  fi
}

new_repo "clean"
write_file "internal/m/m_test.go" $'package m\n// acme/app is the made-up fixture repository.\n' track
write_file "internal/m/testdata/history.csv" $'date,metric,value\n' track
run_gate "$NAMES"
want_green "a clean repository is green"
want_not_said "a clean repository" "skipped"

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

new_repo "private-name"
write_file "testdata/history.csv" $'repo,value\nGlobex-Internal/app,3\n' track
run_gate "$NAMES"
want_red "a fixture mentioning a private name is red and named" "❌ FAIL: testdata/history.csv"
want_not_said "the private-name FAIL line" "globex"
want_not_said "the private-name FAIL line" "Globex"

new_repo "private-name-in-test"
write_file "internal/m/m_test.go" $'package m\n// see https://acme-secret.example/x\n' track
run_gate "$NAMES"
want_red "a test file mentioning a private name is red and named" "❌ FAIL: internal/m/m_test.go"

new_repo "unset"
write_file "testdata/history.csv" $'repo,value\nglobex-internal/app,3\n' track
run_gate
want_green "an unset FORSGREN_PRIVATE_NAMES_FILE passes the name scan"
want_said "and says, with ⚠️, that the name scan was skipped" "⚠️ private-name scan skipped"

new_repo "missing-names-file"
write_file "testdata/history.csv" $'repo,value\nglobex-internal/app,3\n' track
run_gate "${TMP}/no-such-names.txt"
want_green "a missing names file passes the name scan"
want_said "and says, with ⚠️, that the name scan was skipped" "⚠️ private-name scan skipped"

new_repo "empty-names"
write_file "testdata/history.csv" $'repo,value\n' track
printf '# only a comment\n\n' > "${TMP}/empty-names.txt"
run_gate "${TMP}/empty-names.txt"
want_red "a names file with no names is red" "no names in"

REPO="${TMP}/no-files"
mkdir -p "$REPO"
git -C "$REPO" init -q
run_gate
want_red "a repository with no tracked files is red" "no tracked files"

new_repo "nothing-to-scan"
run_gate "$NAMES"
want_red "names set but no fixture or test file is red" "no fixture or test files"

new_repo "wildcard-rows"
write_file "events.jsonl" $'{"run":1}\n' track
write_file "x.history.csv" $'date,metric,value\n' track
write_file "forsgren.config.yaml" $'repos:\n  - acme/app\n' track
run_gate
want_red "a root events.jsonl is red and named (the *.jsonl arm)" "❌ FAIL: events.jsonl"
want_said "an x.history.csv is red and named (the *.history.csv arm)" "❌ FAIL: x.history.csv"
want_said "a forsgren.config.yaml is red and named (the forsgren.config.* arm)" "❌ FAIL: forsgren.config.yaml"

# run_mutant <mutant> <repo-name> — runs a mutated gate against a case's
# repository, names file unset; sets RC and OUT.
run_mutant() {
  capture env -u FORSGREN_PRIVATE_NAMES_FILE "$1" "${TMP}/$2"
}

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
# Mutation proof for case 10: a copy of the gate with every arm whose pattern
# holds a `*` quoted, so it matches only its literal text. The anchor is the
# arm shape `<pattern>) why=`, which only guarded_reason's arms have. The
# mutant must quote at least the three wildcard arms case 10 exercises (else
# the anchor stopped matching), must go green on case 10's repository with
# none of its files named (case 10 is red BECAUSE the arms glob-match), and
# must stay red on case 2's repository (the mutation stopped glob matching
# only; the literal arms still work, so a green above is not a broken gate).
# ---------------------------------------------------------------------------
LITERAL="${TMP}/check_data_guard_literal.sh"
sed -E 's/^([[:space:]]*)([^[:space:]"]*\*[^[:space:]"]*)\) why=/\1"\2") why=/' \
  "$GATE" > "$LITERAL"
chmod +x "$LITERAL"
quoted="$(grep -cE '^[[:space:]]*"[^"]*\*[^"]*"\) why=' "$LITERAL" || true)"

if [[ "$quoted" -lt 3 ]]; then
  fail "mutation proof (case 10): quoting the wildcard arms changed ${quoted} arm(s) in ${GATE} (want at least the 3 case 10 exercises) — the anchor no longer matches, so this proof proves nothing"
else
  run_mutant "$LITERAL" "wildcard-rows"
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof (case 10): a gate whose wildcard arms match only literally is still red on case 10's repository — case 10 is red for another reason than glob matching. Output: ${OUT}"
  elif grep -qE "FAIL: (events\.jsonl|x\.history\.csv|forsgren\.config\.yaml)" <<< "$OUT"; then
    fail "mutation proof (case 10): a gate whose wildcard arms match only literally still names a case-10 file. Output: ${OUT}"
  else
    echo "  ok: with its ${quoted} wildcard arms matching only literally, case 10's repository is green (case 10 is red because the arms glob-match)"
  fi

  run_mutant "$LITERAL" "history-root"
  if [[ "$RC" -eq 0 ]] || ! grep -qF "❌ FAIL: history.csv" <<< "$OUT"; then
    fail "mutation proof (case 10): the literal-only gate is no longer red on case 2's repository — the mutation broke more than glob matching, so case 10 going green above proves nothing. Output: ${OUT}"
  else
    echo "  ok: the literal-only gate is still red on case 2's repository (the mutation stopped glob matching, nothing else)"
  fi
fi

selftest_end "the data-guard gate does not tell fixtures from installation data" \
  "data-guard gate is red on installation config/data outside testdata/ and on private names in fixtures and tests, skips the name scan with a warning when no names file is given, and is red on a scan over nothing"
