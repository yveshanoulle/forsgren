#!/usr/bin/env bash
# canon: test_git_sandbox_isolation_scope v3
# v3 (forsgren#446): cases 25 to 28 over the real list, case 29 over a fixture where only the weights balance (weights balance the shards within 10 seconds, each self-test once, a new one in one shard, no stale weight row), mutations K (retargeted), M and N.
# v2 (forsgren#426): cases 20 to 24 and mutations K and L for the --shard argument.
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
# Shards (forsgren#426): cases 20 to 24 run --shard N/M over the fixture (two
# shards together run each self-test once, a new one lands in one shard, a bad
# shard is exit 64); K. the modulo ignored: shard 2/2 runs everything;
# L. the N <= M check removed: shard 3/2 is accepted.

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
# The serial cases below run the isolation script as one process (forsgren#569: 30 to 33 use shards).
export FORSGREN_ISOLATION_LOCAL_SHARDS=1

FX="${TMP}/fx"
ORIGIN="${TMP}/origin.git"
git init -q --bare "$ORIGIN"
git init -q -b main "$FX"
mkdir -p "${FX}/Scripts"
cp "$ISO" Scripts/lib_git_sandbox.sh Scripts/lib_gate_select.sh Scripts/lib_isolation_shard.sh Scripts/lib_isolation_local.sh Scripts/lib_parallel_mutants.sh "${FX}/Scripts/"
printf 'default 5\n' > "${FX}/Scripts/git_sandbox_isolation_weights.txt"
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

# 20-24 (forsgren#426): a shard argument runs every n-th self-test of the sorted
# list (index modulo n, from 1), so two shards together run each self-test
# exactly once, a new self-test lands in one shard on its own, and a bad shard
# is a usage error (64). The three fixture self-tests a, b and c count their
# runs; sorted they are a, b, c, so shard 1/2 is a and c, shard 2/2 is b.
shard() {
  capture env GITHUB_ACTIONS=true bash "${FX}/Scripts/test_git_sandbox_isolation.sh" --shard "$1"
}
want_usage() {
  if [[ "$RC" -ne 64 ]]; then
    fail "$1: the exit code is ${RC}, wanted 64. Output: ${OUT}"
  else
    want_said "$1" "usage"
  fi
}
reset
counting
shard 1/2
want_green "20: shard 1/2 of three self-tests" "isolation: shard 1/2: 2 of 3 self-tests"
want_said "20b: the shard's run is over its own self-tests" "OK: 2 git-using self-tests"
if [[ "$(count_runs a)$(count_runs b)$(count_runs c)" == "101" ]]; then
  echo "  ok: 20c: shard 1/2 ran a and c once, b not"
else
  fail "20c: shard 1/2 ran a $(count_runs a), b $(count_runs b), c $(count_runs c) time(s), wanted 1, 0, 1"
fi
shard 2/2
want_green "21: shard 2/2 of three self-tests" "isolation: shard 2/2: 1 of 3 self-tests"
want_runs "21b: the two shards together ran each self-test exactly once" 1

reset
counting
shard 1/1
want_green "22: shard 1/1 is the whole list" "isolation: shard 1/1: 3 of 3 self-tests"
want_runs "22b: shard 1/1 ran each once" 1

# 23: a new self-test (sorted last) lands in exactly one shard, with no list edited.
reset
counting
printf '#!/usr/bin/env bash\ngit --version > /dev/null\necho run >> "%s/e"\n' "$RUNS" > "${FX}/Scripts/test_e.sh"
shard 1/2
shard 2/2
if [[ "$(count_runs e)" == 1 ]]; then
  echo "  ok: 23: a new self-test ran in exactly one of the two shards"
else
  fail "23: the new self-test ran $(count_runs e) time(s) over the two shards, wanted 1"
fi
rm -f "${FX}/Scripts/test_e.sh"

# 24: a bad shard is a usage error, not a run.
reset
for bad in 0/2 3/2 x 1/0 1/2/3 -1/2 ""; do
  shard "$bad"
  want_usage "24: shard '${bad}' is a usage error"
done
capture env GITHUB_ACTIONS=true bash "${FX}/Scripts/test_git_sandbox_isolation.sh" --shard
want_usage "24b: --shard without a value is a usage error"
capture env GITHUB_ACTIONS=true bash "${FX}/Scripts/test_git_sandbox_isolation.sh" --nope
want_usage "24c: an unknown argument is a usage error"
reset

# 25-28 (forsgren#446): the split is balanced by the seconds in the weights file
# (a default for the rest), not by position. Over the REAL list of git-using
# self-tests, derived with the guard's own detector: the two shards weigh within
# 10 of each other (25), together hold every self-test exactly once (26), a new
# self-test that is not in the file lands in exactly one shard (27), and no row
# of the file names a self-test that is gone (28).
# shellcheck source=Scripts/lib_isolation_shard.sh
source Scripts/lib_isolation_shard.sh
WEIGHTS="${REPO_ROOT}/Scripts/git_sandbox_isolation_weights.txt"
REAL=()
for t in Scripts/test_*.sh; do
  case "$t" in
    Scripts/test_git_sandbox_isolation.sh | Scripts/test_git_sandbox_guard.sh) continue ;;
  esac
  if git_sandbox_uses_git "$t"; then
    REAL+=("$t")
  fi
done
REAL_SORTED="$(printf '%s\n' "${REAL[@]}" | LC_ALL=C sort)"
# weight_of <self-test>: its row in the file, else the default row.
weight_of() {
  local w
  w="$(awk -v t="$1" '$1 == t { print $2 }' "$WEIGHTS")"
  [[ -n "$w" ]] || w="$(awk '$1 == "default" { print $2 }' "$WEIGHTS")"
  echo "$w"
}
# shard_weight <n> <m> <sorted list>: the summed weight of shard n of m.
shard_weight() {
  local sum=0 t
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    sum=$((sum + $(weight_of "$t")))
  done < <(shard_assign "$1" "$2" "$WEIGHTS" <<< "$3")
  echo "$sum"
}
w1="$(shard_weight 1 2 "$REAL_SORTED")"
w2="$(shard_weight 2 2 "$REAL_SORTED")"
gap=$((w1 > w2 ? w1 - w2 : w2 - w1))
if [[ "$gap" -le 10 ]]; then
  echo "  ok: 25: the two shards weigh ${w1} and ${w2}, within 10 of each other"
else
  fail "25: the two shards weigh ${w1} and ${w2} seconds, ${gap} apart, wanted at most 10"
fi

# 29 (forsgren#446): the same on a small fixture where the weights alone decide. Four
# made-up self-tests, a and c heavy (10 s), b and d light (1 s). Dealt by name with
# equal weights, a and c share a shard (20 against 2); dealt by weight they part
# (11 against 11). So ignoring the weights, which case 25 cannot tell on the real
# list, makes this case red.
FIXTURE_LIST="$(printf '%s\n' Scripts/test_fx_a.sh Scripts/test_fx_b.sh Scripts/test_fx_c.sh Scripts/test_fx_d.sh)"
FIXTURE_WEIGHTS="${TMP}/fixture_weights.txt"
printf '%s\n' "default 1" "Scripts/test_fx_a.sh 10" "Scripts/test_fx_c.sh 10" > "$FIXTURE_WEIGHTS"
# fixture_gap: the seconds between the two shards of the fixture, by its own weights.
fixture_gap() {
  local n sum out=()
  for n in 1 2; do
    sum="$(shard_assign "$n" 2 "$FIXTURE_WEIGHTS" <<< "$FIXTURE_LIST" |
      awk -v f="$FIXTURE_WEIGHTS" 'BEGIN { while ((getline l < f) > 0) { split(l, p, " "); w[p[1]] = p[2] } }
        { s += ($1 in w) ? w[$1] : w["default"] } END { print s + 0 }')"
    out+=("$sum")
  done
  echo $((out[0] > out[1] ? out[0] - out[1] : out[1] - out[0]))
}
fgap="$(fixture_gap)"
if [[ "$fgap" -le 2 ]]; then
  echo "  ok: 29: on the fixture the weights part the two heavy self-tests, the shards are ${fgap} apart (at most 2)"
else
  fail "29: on the fixture the shards are ${fgap} seconds apart, wanted at most 2"
fi

dealt="$( { shard_assign 1 2 "$WEIGHTS" <<< "$REAL_SORTED"; shard_assign 2 2 "$WEIGHTS" <<< "$REAL_SORTED"; } | LC_ALL=C sort)"
if [[ "$dealt" == "$REAL_SORTED" ]]; then
  echo "  ok: 26: the two shards together hold each of the ${#REAL[@]} self-tests exactly once"
else
  fail "26: the two shards do not hold each of the ${#REAL[@]} self-tests exactly once"
fi

NEWT="Scripts/test_zz_new_self_test.sh"
WITH_NEW="$(printf '%s\n%s\n' "$REAL_SORTED" "$NEWT" | LC_ALL=C sort)"
hits=0
for n in 1 2; do
  shard_assign "$n" 2 "$WEIGHTS" <<< "$WITH_NEW" > "${TMP}/shard.out"
  if grep -qxF -- "$NEWT" "${TMP}/shard.out"; then
    hits=$((hits + 1))
  fi
done
if [[ "$hits" -eq 1 ]]; then
  echo "  ok: 27: a new self-test, not in the weights file, lands in exactly one shard"
else
  fail "27: a new self-test landed in ${hits} shards, wanted 1"
fi

stale=""
while read -r name secs; do
  [[ -z "$name" || "$name" == "#"* || "$name" == default ]] && continue
  if ! grep -qxF -- "$name" <<< "$REAL_SORTED"; then
    stale="${stale} ${name}"
  fi
  [[ "$secs" =~ ^[1-9][0-9]*$ ]] || fail "28: the weight of ${name} is not a whole number of seconds: ${secs}"
done < "$WEIGHTS"
if [[ -z "$stale" ]]; then
  echo "  ok: 28: every row of the weights file names a git-using self-test that exists"
else
  fail "28: the weights file names self-tests that are gone or not git-using:${stale}"
fi
reset

# 30-33 (forsgren#569): locally (GITHUB_ACTIONS unset, no --shard) the gate deals the
# self-tests out to FORSGREN_ISOLATION_LOCAL_SHARDS shards (default: Scripts/lib_isolation_local.sh)
# and starts them side by side, so the serial wall time drops. Every self-test still runs
# in BOTH shapes. 30: through the real script over the fixture, each shard named, every
# self-test twice, a leak in any shard red. 31-33 over the library with a fake shard that
# starts, then waits until every shard has started (so a serial run cannot pass): 31 the
# shards run side by side and print in shard order, 32 a failed shard fails the run and
# the others are still printed, 33 a shard that leaves no result (killed) is a failure.
LOCAL_LIB="${REPO_ROOT}/Scripts/lib_isolation_local.sh"
local_run() {
  capture env -u GITHUB_ACTIONS FORSGREN_ISOLATION_FULL=1 FORSGREN_ISOLATION_LOCAL_SHARDS=2 \
    bash "${FX}/Scripts/test_git_sandbox_isolation.sh"
}
reset
counting
local_run
want_green "30: local run with 2 shards, clean self-tests" "OK: all 2 shards ran and passed"
want_said "30b: names shard 1" "isolation: shard 1/2:"
want_said "30c: names shard 2" "isolation: shard 2/2:"
want_runs "30d: every self-test still runs in both shapes" 2
reset
leaker leak_config 'git config leak.key 1'
local_run
want_red "30e: local, sharded, a leaking self-test" "test_leak_config.sh (GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE): the decoy repository: the config changed"
reset

FAKE="${TMP}/fake_shard.sh"
cat > "$FAKE" <<'FAKE_EOF'
#!/usr/bin/env bash
# fake shard: --shard N/M. Starts, then waits for every shard to have started.
n="${2%%/*}"
m="${2##*/}"
touch "${RV}/started.${n}"
[[ "${FAKE_MODE:-}" == "kill:${n}" ]] && kill -9 "$PPID"
for _ in $(seq 1 100); do
  [[ "$(find "$RV" -name 'started.*' | wc -l | tr -d ' ')" -ge "$m" ]] && break
  sleep 0.1
done
[[ "$n" == 1 ]] && sleep 0.5
if [[ "${FAKE_MODE:-}" == "fail:${n}" ]]; then
  echo "fake shard ${n} failing"
  exit 1
fi
if [[ "$(find "$RV" -name 'started.*' | wc -l | tr -d ' ')" -lt "$m" ]]; then
  echo "fake shard ${n} ran alone"
  exit 1
fi
echo "fake shard ${n} saw all ${m} started"
FAKE_EOF
fake_shards() {
  rm -rf "${TMP}/rv" "${TMP}/shards"
  mkdir -p "${TMP}/rv"
  RV="${TMP}/rv" FAKE_MODE="$1" capture isolation_shards_run 3 "${TMP}/shards" bash "$FAKE"
}
if [[ ! -f "$LOCAL_LIB" ]]; then
  fail "31-33: ${LOCAL_LIB} does not exist, so no shard is ever started side by side"
else
  # shellcheck source=Scripts/lib_isolation_local.sh
  source Scripts/lib_isolation_local.sh
  export RV FAKE_MODE
  fake_shards ""
  want_green "31: three shards side by side" "fake shard 3 saw all 3 started"
  want_said "31b: shard 1 waited for the others and saw them" "fake shard 1 saw all 3 started"
  if [[ "$(grep -n 'fake shard' <<< "$OUT" | sed 's/.*fake shard \([0-9]\).*/\1/' | tr -d '\n')" == "123" ]]; then
    echo "  ok: 31c: the output is in shard order although shard 1 ended last"
  else
    fail "31c: the shards' output is not in shard order 1, 2, 3. Output: ${OUT}"
  fi
  fake_shards "fail:2"
  want_red "32: a failed shard fails the run" "shard 2/3 failed"
  want_said "32b: the other shards are still printed" "fake shard 3 saw all 3 started"
  fake_shards "kill:2"
  want_red "33: a shard that leaves no result fails the run" "shard 2/3 left no result"
fi

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

if mutate_lib 's/done <<< "[$]names"/done <<< ""/'; then
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

# K and L (forsgren#426): the fixture has four self-tests by now (a, b, c, gorun).
SHARDLIB="${FX}/Scripts/lib_isolation_shard.sh"
cp "$SHARDLIB" "${TMP}/shardlib.orig"
if selftest_mutant "${TMP}/shardlib.orig" "$SHARDLIB" 's/if (shard\[i\] == n) print name\[i\]/print name[i]/'; then
  publish mutant
  reset
  shard 2/2
  proof K "shard 2/2: 2 of 4" "with the shard test removed, shard 2/2 runs more than its own half, case 21 is red"
  cp "${TMP}/shardlib.orig" "$SHARDLIB"
  publish restore
  reset
fi

if mutate 's/\[\[ "[$]SHARD_N" -le "[$]SHARD_M" \]\] || usage/:/'; then
  shard 3/2
  if [[ "$RC" -eq 64 ]]; then
    fail "mutation proof L: with the N <= M check removed, shard 3/2 was still a usage error"
  else
    echo "  ok: mutation proof L: without the N <= M check, shard 3/2 is accepted, case 24 is red"
  fi
  restore
fi

# M and N (forsgren#446): the real shard library, mutated in the temp root and
# sourced in a subshell, must make a case red (M: the weights ignored, so the split is
# by name again; case 29, as case 25 stays green on the real list by luck; N: every
# self-test to the first shard, case 25).
for spec in "M|s/wt\\[c\\] = (\\\$1 in w) ? w\\[\\\$1\\] : def/wt[c] = def/|the weights ignored, the split is by name again and the fixture gap is|29|2" \
  "N|s/low = 1\$/low = 1; load[1] = -1000000/|the first shard always the lightest, the gap is|25|10"; do
  IFS='|' read -r tag expr what case_no limit <<< "$spec"
  if selftest_mutant Scripts/lib_isolation_shard.sh "${TMP}/mutant_shard_${tag}.sh" "$expr"; then
    mgap="$( (
      # shellcheck disable=SC1090
      source "${TMP}/mutant_shard_${tag}.sh"
      if [[ "$case_no" == 29 ]]; then
        fixture_gap
      else
        a="$(shard_weight 1 2 "$REAL_SORTED")"
        b="$(shard_weight 2 2 "$REAL_SORTED")"
        echo $((a > b ? a - b : b - a))
      fi
    ))"
    if [[ "$mgap" -gt "$limit" ]]; then
      echo "  ok: mutation proof ${tag}: with ${what} ${mgap}, case ${case_no} is red"
    else
      fail "mutation proof ${tag}: with ${what} still ${mgap} (at most ${limit}), case ${case_no} would stay green"
    fi
  fi
done

selftest_end "the git sandbox isolation scope self-test failed" "git sandbox isolation scope: every case holds, fourteen mutations seen"
