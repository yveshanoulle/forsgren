#!/usr/bin/env bash
# canon: test_git_sandbox_isolation_scope v1
# Scripts/test_git_sandbox_isolation_scope.sh (forsgren#251, decision 249)
#
# Self-test for the scope of Scripts/test_git_sandbox_isolation.sh: run locally
# (GITHUB_ACTIONS unset) it checks only the git-using self-tests that are
# affected by the changes against origin/main; in Quality (GITHUB_ACTIONS=true)
# it checks all of them. The real isolation script runs in a throwaway
# repository with three git-using self-tests and one that is not, a helper one
# of them calls and a helper that helper calls:
#   1. nothing changed                      -> 0 of 3, says full run in Quality, rc 0
#   2. a self-test's own file, unstaged     -> that self-test only
#   3. a script a self-test calls           -> that self-test
#   4. a script that script calls           -> that self-test (transitive)
#   5. a staged change                      -> that self-test
#   6. an untracked new self-test           -> it is run, 1 of 4
#   7. a committed change not yet on origin -> that self-test
#   8. a library the isolation script sources, or the script itself -> all 3
#   9. a file no self-test names, or a markdown file -> 0 of 3
#  10. GITHUB_ACTIONS=true, nothing changed -> all 3 (Quality is full)
#  11. no origin/main                       -> all 3, naming why
#  12. FORSGREN_ISOLATION_FULL=1            -> all 3
#  13-16 (step 2) Quality runs each self-test once under the decoy (locally
#      twice); a leaking self-test turns that single run red, each leak class
#      (config, origin refs, own refs, a leak without GIT_WORK_TREE), naming
#      the self-test, the single run and the reason.
#  17-19 (forsgren#258) a Go change selects the self-tests that build or run the
#      tool only while a non-test Go file imports os/exec: none -> 0 of 4 and
#      the reason; one -> the Go-running self-test and the file; a _test.go
#      importing os/exec does not count.
# Mutation proofs (each case is wrong BECAUSE of the line mutated):
#   A. the scripts a self-test calls not followed: case 3 loses its self-test;
#   B. the queue not extended (one level only): case 4 loses its self-test;
#   C. the CI path filtered too: case 10 runs 0 of 3 in Quality;
#   D. untracked files ignored: case 6 loses the new self-test;
#   E. the 0-selected message removed: case 1 skips without saying so;
#   F. a change to the harness not widening to all: case 8 runs 1 of 3 or 0;
#   G. the single-run mode removed: Quality runs each self-test twice;
#   H. the single run not under the decoy: the leak of case 15a goes unseen;
#   I. the exec check never true: case 18 loses the Go-running self-test;
#   J. the exec check always true: case 17 selects the Go-running self-test.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
ISO="${REPO_ROOT}/Scripts/test_git_sandbox_isolation.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
selftest_begin "git sandbox isolation scope self-test"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
G=(git -c user.name=fixture -c user.email=fixture@example.test)

FX="${TMP}/fx"
ORIGIN="${TMP}/origin.git"
git init -q --bare "$ORIGIN"
git init -q -b main "$FX"
mkdir -p "${FX}/Scripts"
cp "$ISO" Scripts/lib_git_sandbox.sh Scripts/lib_gate_select.sh "${FX}/Scripts/"
for t in a b c; do
  printf '#!/usr/bin/env bash\ngit --version > /dev/null\nbash Scripts/helper_%s.sh\n' "$t" > "${FX}/Scripts/test_${t}.sh"
done
printf '#!/usr/bin/env bash\ngit --version > /dev/null\n' > "${FX}/Scripts/test_c.sh"
printf '#!/usr/bin/env bash\necho nogit\n' > "${FX}/Scripts/test_d.sh"
printf '#!/usr/bin/env bash\necho helper a\n' > "${FX}/Scripts/helper_a.sh"
printf '#!/usr/bin/env bash\nbash Scripts/deeper_b.sh\n' > "${FX}/Scripts/helper_b.sh"
printf '#!/usr/bin/env bash\necho deep\n' > "${FX}/Scripts/deeper_b.sh"
printf '#!/usr/bin/env bash\necho unrelated\n' > "${FX}/Scripts/unrelated.sh"
printf 'notes\n' > "${FX}/NOTES.md"
"${G[@]}" -C "$FX" add -A
"${G[@]}" -C "$FX" commit -q -m fixture
git -C "$FX" remote add origin "$ORIGIN"
git -C "$FX" push -q origin main
git -C "$FX" fetch -q origin

# reset: the fixture back to origin/main, nothing changed.
reset() {
  git -C "$FX" reset -q --hard origin/main
  git -C "$FX" clean -fdq
}

# iso [script]: the isolation script of the fixture, locally (GITHUB_ACTIONS unset).
iso() {
  capture env -u GITHUB_ACTIONS -u FORSGREN_ISOLATION_FULL bash "${FX}/Scripts/${1:-test_git_sandbox_isolation.sh}"
}

# 1
reset
iso
want_green "1: nothing changed" "isolation: 0 of 3 self-tests affected, full run in Quality"

# 2-5
reset
echo '# edit' >> "${FX}/Scripts/test_a.sh"
iso
want_green "2: a self-test's own file" "isolation: 1 of 3 self-tests affected"
want_said "2b: the run is over that one" "OK: 1 git-using self-tests"

reset
echo '# edit' >> "${FX}/Scripts/helper_b.sh"
iso
want_green "3: a script a self-test calls" "isolation: 1 of 3 self-tests affected"

reset
echo 'echo edit' >> "${FX}/Scripts/deeper_b.sh"
iso
want_green "4: a script that script calls" "isolation: 1 of 3 self-tests affected"

reset
echo 'echo edit' >> "${FX}/Scripts/helper_a.sh"
git -C "$FX" add -A
iso
want_green "5: a staged change" "isolation: 1 of 3 self-tests affected"

# 6
reset
printf '#!/usr/bin/env bash\ngit --version > /dev/null\n' > "${FX}/Scripts/test_e.sh"
iso
want_green "6: an untracked new self-test" "isolation: 1 of 4 self-tests affected"

# 7
reset
echo 'echo edit' >> "${FX}/Scripts/helper_a.sh"
"${G[@]}" -C "$FX" commit -q -a -m local
iso
want_green "7: a committed change not on origin" "isolation: 1 of 3 self-tests affected"

# 8
reset
echo '# edit' >> "${FX}/Scripts/lib_git_sandbox.sh"
iso
want_green "8a: a library the isolation script sources" "isolation: 3 of 3 self-tests affected"
reset
echo '# edit' >> "${FX}/Scripts/test_git_sandbox_isolation.sh"
iso
want_green "8b: the isolation script itself" "isolation: 3 of 3 self-tests affected"

# 9
reset
echo 'echo edit' >> "${FX}/Scripts/unrelated.sh"
echo more >> "${FX}/NOTES.md"
iso
want_green "9: a file no self-test names and a markdown file" "isolation: 0 of 3 self-tests affected, full run in Quality"

# 10-12
reset
capture env GITHUB_ACTIONS=true bash "${FX}/Scripts/test_git_sandbox_isolation.sh"
want_green "10: Quality (GITHUB_ACTIONS=true), nothing changed" "isolation: 3 of 3 self-tests affected"
capture env -u GITHUB_ACTIONS FORSGREN_ISOLATION_FULL=1 bash "${FX}/Scripts/test_git_sandbox_isolation.sh"
want_green "12: forced full" "isolation: 3 of 3 self-tests affected"
git -C "$FX" update-ref -d refs/remotes/origin/main
iso
want_green "11: no origin/main" "full run (no origin/main to compare against)"
git -C "$FX" fetch -q origin

# 13-16 (forsgren#251, step 2): in Quality each git-using self-test runs ONCE,
# under the decoy, with the leak check inside that one run; locally the two
# leak variants keep their two runs. The seam is GITHUB_ACTIONS, as for the
# scope. The three fixture self-tests count their runs.
RUNS="${TMP}/runs"
count_runs() {
  if [[ -f "${RUNS}/$1" ]]; then wc -l < "${RUNS}/$1" | tr -d ' '; else echo 0; fi
}
# counting: makes the fixture self-tests a, b and c record each run.
counting() {
  mkdir -p "$RUNS"
  rm -f "${RUNS}"/*
  for t in a b c; do
    printf 'echo run >> "%s/%s"\n' "$RUNS" "$t" >> "${FX}/Scripts/test_${t}.sh"
  done
}
# leaker <name> <body>: an untracked git-using self-test that leaks.
leaker() {
  printf '#!/usr/bin/env bash\ngit --version > /dev/null\n%s\n' "$2" > "${FX}/Scripts/test_${1}.sh"
}
ci() {
  capture env GITHUB_ACTIONS=true bash "${FX}/Scripts/test_git_sandbox_isolation.sh"
}
want_runs() {
  local t got
  for t in a b c; do
    got="$(count_runs "$t")"
    if [[ "$got" == "$2" ]]; then
      echo "  ok: $1: self-test ${t} ran ${got} time(s)"
    else
      fail "$1: self-test ${t} ran ${got} time(s), wanted $2. Output: ${OUT}"
    fi
  done
}

reset
counting
ci
want_green "13: Quality, clean self-tests" "OK: 3 git-using self-tests leave a repository named by GIT_DIR untouched"
want_said "13b: says each runs once" "isolation: Quality, each self-test runs once under the decoy"
want_runs "13c: Quality runs each once" 1

reset
counting
capture env -u GITHUB_ACTIONS FORSGREN_ISOLATION_FULL=1 bash "${FX}/Scripts/test_git_sandbox_isolation.sh"
want_green "14: local full run, clean self-tests" "OK: 3 git-using self-tests"
want_runs "14b: local keeps the two leak-variant runs" 2

# 15: each leak class turns the single run red, naming the self-test, the
# single run and the reason.
IDENT='-c user.name=leak -c user.email=leak@example.test'
reset
leaker leak_config 'git config leak.key 1'
ci
want_red "15a: Quality, a self-test that changes the decoy config" "test_leak_config.sh (single run under the decoy: GIT_DIR, GIT_INDEX_FILE): the decoy repository: the config changed"
reset
leaker leak_origin "git ${IDENT} commit -q --allow-empty -m leak; git push -q origin main"
ci
want_red "15b: Quality, a self-test that pushes to the decoy origin" "test_leak_origin.sh (single run under the decoy: GIT_DIR, GIT_INDEX_FILE): the decoy origin: the refs changed"
reset
leaker leak_ref "git ${IDENT} commit -q --allow-empty -m leak"
ci
want_red "15c: Quality, a self-test that commits into the decoy" "test_leak_ref.sh (single run under the decoy: GIT_DIR, GIT_INDEX_FILE): the decoy repository: the refs changed"
# 16: the leak that only shows with GIT_DIR and GIT_INDEX_FILE (no work tree).
reset
leaker leak_bare "if [[ -z \"\${GIT_WORK_TREE:-}\" ]]; then git config leak.bare 1; fi"
ci
want_red "16: Quality, a self-test that leaks only without GIT_WORK_TREE" "test_leak_bare.sh (single run under the decoy: GIT_DIR, GIT_INDEX_FILE): the decoy repository: the config changed"
reset

# Mutation proofs: the isolation script of the fixture is mutated and pushed to
# the fixture's origin (so the mutation is not itself a change), the change a
# case needs is made, and the case must no longer hold.
MUT="${FX}/Scripts/test_git_sandbox_isolation.sh"
cp "$MUT" "${TMP}/iso.orig"
# publish: the fixture's isolation script as it is now becomes origin/main.
publish() {
  "${G[@]}" -C "$FX" commit -q -a -m "$1"
  git -C "$FX" push -q origin main
  git -C "$FX" fetch -q origin
}
mutate() {
  if selftest_mutant "${TMP}/iso.orig" "$MUT" "$1"; then
    publish mutant
    reset
    return 0
  fi
  return 1
}
restore() {
  cp "${TMP}/iso.orig" "$MUT"
  publish restore
  reset
}
# The same for the shared library (forsgren#262: changed_files, named_files and
# closure live in Scripts/lib_gate_select.sh, which the isolation script sources).
LIBMUT="${FX}/Scripts/lib_gate_select.sh"
cp "$LIBMUT" "${TMP}/lib.orig"
mutate_lib() {
  if selftest_mutant "${TMP}/lib.orig" "$LIBMUT" "$1"; then
    publish mutant
    reset
    return 0
  fi
  return 1
}
restore_lib() {
  cp "${TMP}/lib.orig" "$LIBMUT"
  publish restore
  reset
}
proof() {
  if grep -qF -- "$2" <<< "$OUT"; then
    fail "mutation proof $1: the output still said '$2'. Output: ${OUT}"
  else
    echo "  ok: mutation proof $1: $3"
  fi
}

if mutate_lib 's/done < <(named_files "[$]f")/done < <(:)/'; then
  echo '# edit' >> "${FX}/Scripts/helper_b.sh"
  iso
  proof A "isolation: 1 of 3" "without following the scripts a self-test calls, case 3 loses its self-test"
  restore_lib
fi

if mutate_lib 's/^        queue+=("[$]n")$/        :/'; then
  echo 'echo edit' >> "${FX}/Scripts/deeper_b.sh"
  iso
  proof B "isolation: 1 of 3" "without extending the queue, case 4 loses the transitive self-test"
  restore_lib
fi

if mutate 's/"[$]{GITHUB_ACTIONS:-}" == "true"/"never" == "true"/'; then
  capture env GITHUB_ACTIONS=true bash "$MUT"
  proof C "isolation: 3 of 3" "with the CI path filtered too, case 10 runs fewer than all in Quality"
  restore
fi

if mutate_lib 's/; git ls-files --others --exclude-standard;/;/'; then
  printf '#!/usr/bin/env bash\ngit --version > /dev/null\n' > "${FX}/Scripts/test_e.sh"
  iso
  proof D "isolation: 1 of 4" "with untracked files ignored, case 6 loses the new self-test"
  restore_lib
fi

if mutate '/^  echo "isolation: 0 of /d'; then
  iso
  proof E "isolation: 0 of 3" "without the message, case 1 skips without saying so"
  restore
fi

if mutate 's/if grep -qxF -- "[$]c" <<< "[$]own"/if false/'; then
  echo '# edit' >> "${FX}/Scripts/lib_git_sandbox.sh"
  iso
  proof F "isolation: 3 of 3" "with a harness change not widening to all, case 8a runs fewer"
  restore
fi

if mutate 's/^if \[\[ "[$]{GITHUB_ACTIONS:-}" = "true" \]\]; then/if false; then/'; then
  counting
  capture env GITHUB_ACTIONS=true bash "$MUT"
  if [[ "$(count_runs a)" == 1 ]]; then
    fail "mutation proof G: with the single run removed, Quality still ran self-test a once. Output: ${OUT}"
  else
    echo "  ok: mutation proof G: without the single-run mode, Quality runs each self-test $(count_runs a) times, case 13c is red"
  fi
  restore
fi

if mutate '/^  run_variant "single run/s/GIT_DIR="/GIT_DIX="/'; then
  leaker leak_config 'git config leak.key 1'
  capture env GITHUB_ACTIONS=true bash "$MUT"
  proof H "the config changed" "with the single run not under the decoy, case 15a no longer sees the leak"
  restore
fi

# 17-19 (forsgren#258): a Go change selects the self-tests that build or run the
# tool ONLY while some non-test Go file can start a program (imports os/exec).
# The fixture gains a fourth, Go-running self-test and a Go file, committed to
# origin so they are not themselves a change.
printf '#!/usr/bin/env bash\ngit --version > /dev/null\ngo build ./...\n' > "${FX}/Scripts/test_gorun.sh"
mkdir -p "${FX}/cmd/app"
printf 'package main\n\nfunc main() {}\n' > "${FX}/cmd/app/main.go"
"${G[@]}" -C "$FX" add -A
publish "go fixture"
reset
EXEC_FILE='package main\n\nimport "os/exec"\n\nvar _ = exec.Command\n'
go_change() { printf '\n// edit\n' >> "${FX}/cmd/app/main.go"; }

go_change
iso
want_green "17: a Go-only change, no file starts a program" "isolation: 0 of 4 self-tests affected, full run in Quality"
want_said "17b: the reason is named" "isolation: Go changes select nothing, no non-test Go file starts a program"

reset
go_change
printf %b "$EXEC_FILE" > "${FX}/cmd/app/run.go"
iso
want_green "18: the same change plus a non-test file importing os/exec" "isolation: 1 of 4 self-tests affected"
want_said "18b: the file that starts a program is named" "cmd/app/run.go starts a program"

reset
go_change
printf %b "$EXEC_FILE" > "${FX}/cmd/app/run_test.go"
iso
want_green "19: a _test.go importing os/exec does not count" "isolation: 0 of 4 self-tests affected, full run in Quality"
reset

if mutate 's/^  GO_STARTER="[$](go_starter)"$/  GO_STARTER=""/'; then
  go_change
  printf %b "$EXEC_FILE" > "${FX}/cmd/app/run.go"
  iso
  proof I "isolation: 1 of 4" "without the exec check counting, case 18 loses the Go-running self-test"
  restore
fi

if mutate 's/^  GO_STARTER="[$](go_starter)"$/  GO_STARTER="cmd\/app\/main.go"/'; then
  go_change
  iso
  proof J "isolation: 0 of 4" "with the exec check always true, case 17 selects the Go-running self-test"
  restore
fi

selftest_end "the git sandbox isolation scope self-test failed" "git sandbox isolation scope: every case holds, ten mutations seen"
