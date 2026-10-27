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
#   4. a config file and a data/ file NOT          -> red, named (forsgren#204: a
#      git-added; an ignored config file -> green     new file is untracked while
#                                                    the gates run)
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
#  12. a tracked data/é.csv (non-ASCII name, git  -> red, named
#      quotepath on: git prints it quoted)
#  13. an issues.csv elsewhere (forsgren#76)      -> red, named
#  14. an issues_full.csv, a failures_read.csv,   -> red, each named
#      a failures_withdrawn.csv, an issue_bugs.csv
#      and an issue_bugs_cut.csv
#      elsewhere (forsgren#143, forsgren#140)
#  15. drift check: every data file the Go code   -> red, each named
#      names (const <Name>File = "<name>.csv" in
#      internal/collect, alone or in a const
#      block) elsewhere
#  16. a pulls.csv, a pulls_read.csv, a          -> red, each named
#      pull_commits.csv and a
#      pull_commits_filled.csv elsewhere
#      (forsgren#255, forsgren#463, forsgren#470)
#  17. a pulls_denied.csv elsewhere               -> red, named
#      (forsgren#337)
#  18. a pushes.csv, a pushes_read.csv, a        -> red, each named
#      pushes_denied.csv, a push_commits.csv and
#      a push_commits_filled.csv elsewhere
#      (forsgren#397, forsgren#470)
#  19. a pulls_bot_filled.csv elsewhere         -> red, named (forsgren#500)
#  20. a commit_files.csv and a                  -> red, each named
#      commit_files_filled.csv elsewhere
#      (forsgren#496)
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
#   - case 13: with the issues.csv arm deleted, a repository holding only
#     ops/issues.csv must turn green.
#   - case 14: with the issues_full.csv, failures_read.csv, issue_bugs.csv or
#     issue_bugs_cut.csv
#     arm deleted, a repository holding only ops/ of that file must turn
#     green.
#   - case 15: with the reach.csv, cut_runs.csv or starts_checked.csv arm deleted, a repository
#     holding only ops/ of that file must turn green; reach.csv has no case of its own, so the
#     drift check is the case that holds its arm. The drift check needs no
#     other proof: it reads the Go constants, and a deleted arm turns it red,
#     as case 14 shows.
#   - case 16: with the pulls.csv, pulls_read.csv, pull_commits.csv or pull_commits_filled.csv arm deleted, a repository
#     holding only ops/ of that file must turn green.
#   - case 17: with the pulls_denied.csv arm deleted, a repository holding
#     only ops/pulls_denied.csv must turn green.
#   - case 18: with the pushes.csv, pushes_read.csv, pushes_denied.csv or
#     push_commits.csv or push_commits_filled.csv arm deleted, a repository holding only ops/ of that file must turn green.
#   - case 19: with the pulls_bot_filled.csv arm deleted, a repository holding
#     only ops/pulls_bot_filled.csv must turn green.
#   - case 20: with the commit_files.csv or commit_files_filled.csv arm
#     deleted, a repository holding only ops/ of that file must turn green.
#   - case 6: with every arm whose pattern holds a `*` quoted (so it matches
#     only the literal text), case 6's repository must turn green with none
#     of its three files named, while case 2's repository stays red. Every
#     other red case is matched by a literal pattern, so a gate that stopped
#     glob-matching would pass them all; case 6 is the one that notices
#     (forsgren#1, step 12.2a, automated in 12.2c).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

GATE="$(pwd)/Scripts/check_data_guard.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "data-guard gate self-test"

# The mutants of the gate sit in $TMP and source their helper from beside them.
cp Scripts/lib_repo_files.sh "$TMP/lib_repo_files.sh"

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

# run_from_scripts <repo> — runs the gate by a relative path from inside its
# own directory (forsgren#204).
run_from_scripts() {
  (cd Scripts && ./check_data_guard.sh "$1")
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

# forsgren#204: the gate finds its helper whatever the current directory, from
# inside Scripts/ with a relative $0 included.
new_repo "run-from-scripts"
write_file "history.csv" $'date,metric,value\n' track
capture run_from_scripts "$REPO"
want_red "run from inside Scripts/ it still finds its helper and judges the repository" "❌ FAIL: history.csv"

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
write_file "data/deployments.csv" $'repo,id\n'
run_gate
want_red "an untracked config.yml is judged: a new file is untracked while the gates run (forsgren#204)" "❌ FAIL: config.yml"
want_said "  ... and an untracked data/deployments.csv" "❌ FAIL: data/deployments.csv"

new_repo "ignored-config"
write_file ".gitignore" $'scratch/\n' track
write_file "scratch/config.yml" $'repos:\n  - acme/app\n'
run_gate
want_green "an ignored config.yml will never be committed, green"

REPO="${TMP}/no-files"
mkdir -p "$REPO"
git -C "$REPO" init -q
run_gate
want_red "a repository with no tracked files is red" "no files found"

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

new_repo "issues-elsewhere"
write_file "ops/issues.csv" $'# forsgren issues v1\n' track
run_gate
want_red "an issues.csv outside data/ is red and named" "❌ FAIL: ops/issues.csv"

new_repo "other-data-elsewhere"
write_file "ops/issues_full.csv" $'# forsgren issues full v1\n' track
write_file "ops/failures_read.csv" $'# forsgren failures read v1\n' track
write_file "ops/failures_withdrawn.csv" $'# forsgren failures withdrawn v1\n' track
write_file "ops/issue_bugs.csv" $'# forsgren issue bugs v1\n' track
write_file "ops/issue_bugs_cut.csv" $'# forsgren bugs cut v1\n' track
run_gate
want_red "an issues_full.csv outside data/ is red and named (forsgren#143)" "❌ FAIL: ops/issues_full.csv"
want_said "a failures_read.csv outside data/ is red and named (forsgren#143)" "❌ FAIL: ops/failures_read.csv"
want_said "a failures_withdrawn.csv outside data/ is red and named (forsgren#155)" "❌ FAIL: ops/failures_withdrawn.csv"
want_said "an issue_bugs.csv outside data/ is red and named (forsgren#143)" "❌ FAIL: ops/issue_bugs.csv"
want_said "an issue_bugs_cut.csv outside data/ is red and named (forsgren#140)" "❌ FAIL: ops/issue_bugs_cut.csv"

# Drift check (forsgren#143): every data file the Go code names, a constant
# `const <Name>File = "<name>.csv"` in internal/collect, is guarded, so a data
# file added later cannot be forgotten. The names are read from the source, one
# source of truth; a read that finds fewer than the eight there are is itself
# red, so a changed constant shape cannot make this case pass over nothing.
# A constant inside a `const (` block counts too, `<Name>File = "<name>.csv"`
# on its own indented line (forsgren#255: PullsFile and PullsReadFile are
# declared that way, and the single-line form alone missed them).
GO_DATA_FILES="$(grep -rhoE --exclude='*_test.go' '^(const +|[[:space:]]+)[A-Za-z]+File += "[a-z_]+\.csv"' internal/collect \
  | sed -E 's/.*"([a-z_]+\.csv)"/\1/' | sort -u)"
go_data_count="$(grep -c . <<< "$GO_DATA_FILES" || true)"
if [[ "$go_data_count" -lt 8 ]]; then
  fail "drift check (forsgren#143): found ${go_data_count} data file constant(s) in internal/collect, want at least 8 — the constant shape changed, so this check proves nothing"
else
  new_repo "go-data-files"
  while IFS= read -r name; do
    write_file "ops/${name}" $'x\n' track
  done <<< "$GO_DATA_FILES"
  run_gate
  while IFS= read -r name; do
    want_said "drift check: ${name}, a data file the Go code names, is guarded" "❌ FAIL: ops/${name}"
  done <<< "$GO_DATA_FILES"
fi

new_repo "other-data-elsewhere-full"
write_file "ops/issues_full.csv" $'# forsgren issues full v1\n' track
new_repo "other-data-elsewhere-read"
write_file "ops/failures_read.csv" $'# forsgren failures read v1\n' track
new_repo "other-data-elsewhere-withdrawn"
write_file "ops/failures_withdrawn.csv" $'# forsgren failures withdrawn v1\n' track
new_repo "other-data-elsewhere-bugs"
write_file "ops/issue_bugs.csv" $'# forsgren issue bugs v1\n' track
new_repo "other-data-elsewhere-bugscut"
write_file "ops/issue_bugs_cut.csv" $'# forsgren bugs cut v1\n' track
new_repo "other-data-elsewhere-reach"
write_file "ops/reach.csv" $'# forsgren reach v1\n' track
new_repo "other-data-elsewhere-cutruns"
write_file "ops/cut_runs.csv" $'# forsgren cut runs v1\n' track
new_repo "other-data-elsewhere-startschecked"
write_file "ops/starts_checked.csv" $'# forsgren starts checked v1\n' track

new_repo "pulls-elsewhere"
write_file "ops/pulls.csv" $'# forsgren pulls v1\n' track
write_file "ops/pull_commits.csv" $'# forsgren pull commits v1\n' track
write_file "ops/pulls_read.csv" $'# forsgren pulls read v1\n' track
write_file "ops/pull_commits_filled.csv" $'# forsgren pull commits filled v1\n' track
run_gate
want_red "a pulls.csv outside data/ is red and named (forsgren#255)" "❌ FAIL: ops/pulls.csv"
want_said "a pulls_read.csv outside data/ is red and named (forsgren#255)" "❌ FAIL: ops/pulls_read.csv"
want_said "a pull_commits.csv outside data/ is red and named (forsgren#463)" "❌ FAIL: ops/pull_commits.csv"
want_said "a pull_commits_filled.csv outside data/ is red and named (forsgren#470)" "❌ FAIL: ops/pull_commits_filled.csv"
new_repo "pulls-elsewhere-pulls"
write_file "ops/pulls.csv" $'# forsgren pulls v1\n' track
new_repo "pulls-elsewhere-read"
write_file "ops/pulls_read.csv" $'# forsgren pulls read v1\n' track
new_repo "pulls-elsewhere-commits"
write_file "ops/pull_commits.csv" $'# forsgren pull commits v1\n' track
new_repo "pulls-elsewhere-filled"
write_file "ops/pull_commits_filled.csv" $'# forsgren pull commits filled v1\n' track

new_repo "pulls-denied-elsewhere"
write_file "ops/pulls_denied.csv" $'# forsgren pulls denied v1\n' track
run_gate
want_red "a pulls_denied.csv outside data/ is red and named (forsgren#337)" "❌ FAIL: ops/pulls_denied.csv"

new_repo "pushes-elsewhere"
write_file "ops/pushes.csv" $'# forsgren pushes v1\n' track
write_file "ops/pushes_read.csv" $'# forsgren pushes read v1\n' track
write_file "ops/pushes_denied.csv" $'# forsgren pushes denied v1\n' track
write_file "ops/push_commits.csv" $'# forsgren push commits v1\n' track
write_file "ops/push_commits_filled.csv" $'# forsgren push commits filled v1\n' track
run_gate
want_red "a pushes.csv outside data/ is red and named (forsgren#397)" "❌ FAIL: ops/pushes.csv"
want_said "a pushes_read.csv outside data/ is red and named (forsgren#397)" "❌ FAIL: ops/pushes_read.csv"
want_said "a pushes_denied.csv outside data/ is red and named (forsgren#397)" "❌ FAIL: ops/pushes_denied.csv"
want_said "a push_commits.csv outside data/ is red and named (forsgren#397)" "❌ FAIL: ops/push_commits.csv"
want_said "a push_commits_filled.csv outside data/ is red and named (forsgren#470)" "❌ FAIL: ops/push_commits_filled.csv"
new_repo "pushes-elsewhere-pushes"
write_file "ops/pushes.csv" $'# forsgren pushes v1\n' track
new_repo "pushes-elsewhere-read"
write_file "ops/pushes_read.csv" $'# forsgren pushes read v1\n' track
new_repo "pushes-elsewhere-denied"
write_file "ops/pushes_denied.csv" $'# forsgren pushes denied v1\n' track
new_repo "pushes-elsewhere-commits"
write_file "ops/push_commits.csv" $'# forsgren push commits v1\n' track
new_repo "pushes-elsewhere-filled"
write_file "ops/push_commits_filled.csv" $'# forsgren push commits filled v1\n' track

new_repo "pulls-bot-filled-elsewhere"
write_file "ops/pulls_bot_filled.csv" $'# forsgren pulls bot filled v1\n' track
run_gate
want_red "a pulls_bot_filled.csv outside data/ is red and named (forsgren#500)" "❌ FAIL: ops/pulls_bot_filled.csv"
new_repo "files-elsewhere"
write_file "ops/commit_files.csv" $'# forsgren commit files v1\n' track
write_file "ops/commit_files_filled.csv" $'# forsgren commit files filled v1\n' track
run_gate
want_red "a commit_files.csv outside data/ is red and named (forsgren#496)" "❌ FAIL: ops/commit_files.csv"
want_said "a commit_files_filled.csv outside data/ is red and named (forsgren#496)" "❌ FAIL: ops/commit_files_filled.csv"
new_repo "files-elsewhere-files"
write_file "ops/commit_files.csv" $'# forsgren commit files v1\n' track
new_repo "files-elsewhere-filled"
write_file "ops/commit_files_filled.csv" $'# forsgren commit files filled v1\n' track

new_repo "history-fixtures"
write_file "internal/history/testdata/deployments.csv" $'# forsgren history v1\n' track
write_file "internal/history/testdata/commits.csv" $'# forsgren commits v1\n' track
write_file "internal/history/testdata/failures.csv" $'# forsgren failures v1\n' track
write_file "internal/history/testdata/issues.csv" $'# forsgren issues v1\n' track
write_file "internal/history/testdata/data/deployments.csv" $'# forsgren history v1\n' track
write_file "internal/history/history_test.go" $'package history\n// acme/app is the made-up fixture repository.\n' track
write_file "internal/data/data.go" $'package data\n' track
run_gate
want_green "history fixtures under testdata/, a Go test file and internal/data/ are not installation data"

new_repo "data-dir-nonascii"
git -C "$REPO" config core.quotepath true
write_file "data/é.csv" $'x\n' track
run_gate
want_red "a tracked data/é.csv (non-ASCII name, quotepath on) is red and named" "❌ FAIL: data/é.csv"

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
# Case 13: the issues.csv arm (forsgren#76).
# ---------------------------------------------------------------------------
arm_deleted_proof 7 "data/*" '^[[:space:]]*data/\*\) why=' \
  "${TMP}/check_data_guard_nodir.sh" "data-dir-notes" "data/notes.txt"
arm_deleted_proof 8 "deployments.csv" '^[[:space:]]*deployments\.csv\) why=' \
  "${TMP}/check_data_guard_nodeploy.sh" "deployments-elsewhere" "ops/deployments.csv"
arm_deleted_proof 10 "commits.csv" '^[[:space:]]*commits\.csv\) why=' \
  "${TMP}/check_data_guard_nocommits.sh" "commits-elsewhere" "ops/commits.csv"
arm_deleted_proof 11 "failures.csv" '^[[:space:]]*failures\.csv\) why=' \
  "${TMP}/check_data_guard_nofailures.sh" "failures-elsewhere" "ops/failures.csv"
arm_deleted_proof 13 "issues.csv" '^[[:space:]]*issues\.csv\) why=' \
  "${TMP}/check_data_guard_noissues.sh" "issues-elsewhere" "ops/issues.csv"

arm_deleted_proof 14 "issues_full.csv" '^[[:space:]]*issues_full\.csv\) why=' \
  "${TMP}/check_data_guard_noissuesfull.sh" "other-data-elsewhere-full" "ops/issues_full.csv"
arm_deleted_proof 14 "failures_read.csv" '^[[:space:]]*failures_read\.csv\) why=' \
  "${TMP}/check_data_guard_nofailuresread.sh" "other-data-elsewhere-read" "ops/failures_read.csv"
arm_deleted_proof 14 "failures_withdrawn.csv" '^[[:space:]]*failures_withdrawn\.csv\) why=' \
  "${TMP}/check_data_guard_nowithdrawn.sh" "other-data-elsewhere-withdrawn" "ops/failures_withdrawn.csv"
arm_deleted_proof 14 "issue_bugs.csv" '^[[:space:]]*issue_bugs\.csv\) why=' \
  "${TMP}/check_data_guard_noissuebugs.sh" "other-data-elsewhere-bugs" "ops/issue_bugs.csv"
arm_deleted_proof 14 "issue_bugs_cut.csv" '^[[:space:]]*issue_bugs_cut\.csv\) why=' \
  "${TMP}/check_data_guard_noissuebugscut.sh" "other-data-elsewhere-bugscut" "ops/issue_bugs_cut.csv"
arm_deleted_proof 15 "reach.csv" '^[[:space:]]*reach\.csv\) why=' \
  "${TMP}/check_data_guard_noreach.sh" "other-data-elsewhere-reach" "ops/reach.csv"
arm_deleted_proof 15 "cut_runs.csv" '^[[:space:]]*cut_runs\.csv\) why=' \
  "${TMP}/check_data_guard_nocutruns.sh" "other-data-elsewhere-cutruns" "ops/cut_runs.csv"
arm_deleted_proof 15 "starts_checked.csv" '^[[:space:]]*starts_checked\.csv\) why=' \
  "${TMP}/check_data_guard_nostartschecked.sh" "other-data-elsewhere-startschecked" "ops/starts_checked.csv"
arm_deleted_proof 16 "pulls.csv" '^[[:space:]]*pulls\.csv\) why=' \
  "${TMP}/check_data_guard_nopulls.sh" "pulls-elsewhere-pulls" "ops/pulls.csv"
arm_deleted_proof 16 "pulls_read.csv" '^[[:space:]]*pulls_read\.csv\) why=' \
  "${TMP}/check_data_guard_nopullsread.sh" "pulls-elsewhere-read" "ops/pulls_read.csv"
arm_deleted_proof 16 "pull_commits.csv" '^[[:space:]]*pull_commits\.csv\) why=' \
  "${TMP}/check_data_guard_nopullcommits.sh" "pulls-elsewhere-commits" "ops/pull_commits.csv"
arm_deleted_proof 16 "pull_commits_filled.csv" '^[[:space:]]*pull_commits_filled\.csv\) why=' \
  "${TMP}/check_data_guard_nopullcommitsfilled.sh" "pulls-elsewhere-filled" "ops/pull_commits_filled.csv"
arm_deleted_proof 17 "pulls_denied.csv" '^[[:space:]]*pulls_denied\.csv\) why=' \
  "${TMP}/check_data_guard_nopullsdenied.sh" "pulls-denied-elsewhere" "ops/pulls_denied.csv"
arm_deleted_proof 18 "pushes.csv" '^[[:space:]]*pushes\.csv\) why=' \
  "${TMP}/check_data_guard_nopushes.sh" "pushes-elsewhere-pushes" "ops/pushes.csv"
arm_deleted_proof 18 "pushes_read.csv" '^[[:space:]]*pushes_read\.csv\) why=' \
  "${TMP}/check_data_guard_nopushesread.sh" "pushes-elsewhere-read" "ops/pushes_read.csv"
arm_deleted_proof 18 "pushes_denied.csv" '^[[:space:]]*pushes_denied\.csv\) why=' \
  "${TMP}/check_data_guard_nopushesdenied.sh" "pushes-elsewhere-denied" "ops/pushes_denied.csv"
arm_deleted_proof 18 "push_commits.csv" '^[[:space:]]*push_commits\.csv\) why=' \
  "${TMP}/check_data_guard_nopushcommits.sh" "pushes-elsewhere-commits" "ops/push_commits.csv"
arm_deleted_proof 18 "push_commits_filled.csv" '^[[:space:]]*push_commits_filled\.csv\) why=' \
  "${TMP}/check_data_guard_nopushcommitsfilled.sh" "pushes-elsewhere-filled" "ops/push_commits_filled.csv"
arm_deleted_proof 19 "pulls_bot_filled.csv" '^[[:space:]]*pulls_bot_filled\.csv\) why=' \
  "${TMP}/check_data_guard_nopullsbotfilled.sh" "pulls-bot-filled-elsewhere" "ops/pulls_bot_filled.csv"
arm_deleted_proof 20 "commit_files.csv" '^[[:space:]]*commit_files\.csv\) why=' \
  "${TMP}/check_data_guard_nocommitfiles.sh" "files-elsewhere-files" "ops/commit_files.csv"
arm_deleted_proof 20 "commit_files_filled.csv" '^[[:space:]]*commit_files_filled\.csv\) why=' \
  "${TMP}/check_data_guard_nocommitfilesfilled.sh" "files-elsewhere-filled" "ops/commit_files_filled.csv"

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
