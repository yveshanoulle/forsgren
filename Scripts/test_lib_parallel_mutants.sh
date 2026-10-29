#!/usr/bin/env bash
# canon: test_lib_parallel_mutants v2
# Scripts/test_lib_parallel_mutants.sh
#
# Self-test for Scripts/lib_parallel_mutants.sh: mutants run side by side in folders
# of their own, their output comes back in start order, and a failing or aborting
# mutant fails the harness.
#
#   (a) two mutants that each wait for the other's marker finish only when they really
#       run at the same time (a serial run times them out): MUTANT_JOBS=2
#   (b) MUTANT_JOBS=1 runs them one after the other: the same rendezvous times out,
#       which is how this test proves (a) measures concurrency and not luck
#   (c) at most MUTANT_JOBS mutants run at once (six mutants, three at a time)
#   (d) every mutant has a folder of its own (distinct MUTANT_DIR)
#   (e) the output is printed in the order the mutants were started, whatever the
#       order they finish in
#   (f) a mutant that sets failed=1 fails the harness; one that aborts (unbound
#       variable under set -u) fails it too, and says so
#   (g) a harness whose mutants all pass keeps failed=0
#   (i) the default cap: half the CPUs, floor 2, ceiling 4 (12 CPUs give 4),
#       MUTANT_JOBS overrides; a library that restores a ceiling of 8 is caught
#   (j) twenty quick mutants all come back with status 0 and no wait error (jobs -r
#       could reap a child); the library never calls jobs, with a mutation proof for
#       that pin
#   (h) Scripts/test_gate_browser.sh sources the library and runs its mutation proofs
#       through it (mutants_init, mutant_run, mutants_wait), and keeps no
#       selftest_mutant proof outside a mutant function
#   (k) Scripts/test_quality_jobs.sh runs its mutation proofs through the library, and
#       Scripts/test_step_summary_isolation.sh its self-test runs (forsgren#569), each
#       started with mutant_run and collected with mutants_wait, none run in a loop of
#       its own
#
# Local invocation: ./Scripts/test_lib_parallel_mutants.sh
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

LIB="${PWD}/Scripts/lib_parallel_mutants.sh"
BROWSER_TEST="Scripts/test_gate_browser.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "parallel mutants library self-test"
[[ -f "$LIB" ]] || selftest_abort "${LIB} is missing"
# shellcheck source=Scripts/lib_parallel_mutants.sh
source "$LIB"

# check <case> <want> <got>
check() {
  if [[ "$3" == "$2" ]]; then echo "  ok: $1"; else fail "$1: want [$2] got [$3]"; fi
}
# check_has <case> <text> <want>
check_has() {
  if [[ "$2" == *"$3"* ]]; then echo "  ok: $1"; else fail "$1: want [...$3...] got [$2]"; fi
}

# rendezvous <name> <other>: touch my marker, wait up to 3 s for the other's.
rendezvous() {
  local me="$1" other="$2" i
  : > "${TMP}/marker_${me}"
  for ((i = 0; i < 30; i++)); do
    if [[ -f "${TMP}/marker_${other}" ]]; then echo "rendezvous ${me}: met ${other}"; return 0; fi
    sleep 0.1
  done
  echo "rendezvous ${me}: ${other} never came"
  failed=1
}

# run_pair <jobs> <dir>: the two-way rendezvous through the library, the harness output.
run_pair() {
  rm -f "${TMP}"/marker_*
  (
    failed=0
    MUTANT_JOBS="$1"
    mutants_init "${TMP}/$2"
    mutant_run rendezvous one two
    mutant_run rendezvous two one
    mutants_wait
    echo "failed=${failed}"
  ) 2>&1 || true
}

# (a) concurrent
OUT_A="$(run_pair 2 a)"
check_has "(a) two mutants meet: they ran at the same time" "$OUT_A" "rendezvous one: met two"
check_has "(a) and the harness stays green" "$OUT_A" "failed=0"

# (b) MUTANT_JOBS=1 is serial: the same rendezvous cannot succeed
OUT_B="$(run_pair 1 b)"
check_has "(b) with one job at a time the first mutant waits in vain" "$OUT_B" "rendezvous one: two never came"
check_has "(b) and the harness goes red" "$OUT_B" "failed=1"

# (c) the limit, (d) folders, (e) order
count_running() { # mutant n: record how many mutants are running now
  local me="$1"
  : > "${TMP}/live_${me}"
  find "${TMP}" -maxdepth 1 -name 'live_*' | wc -l | tr -d ' ' > "${TMP}/seen_${me}"
  sleep "0.$((7 - me))" # earlier mutants take longer, so they finish last
  rm -f "${TMP}/live_${me}"
  echo "mutant ${me} in ${MUTANT_DIR##*/}"
}
rm -f "${TMP}"/live_* "${TMP}"/seen_*
OUT_C="$(
  failed=0
  MUTANT_JOBS=3
  mutants_init "${TMP}/c"
  for n in 1 2 3 4 5 6; do mutant_run count_running "$n"; done
  mutants_wait 2>&1
)"
MAX=0
for f in "${TMP}"/seen_*; do
  v="$(cat "$f")"
  if [[ "$v" -gt "$MAX" ]]; then MAX="$v"; fi
done
check "(c) never more than MUTANT_JOBS=3 at once" "3" "$MAX"
check "(d) six mutants, six folders" "6" "$(grep -c '^mutant [0-9] in m[0-9]$' <<< "$OUT_C")"
check "(d) the folders are distinct" "6" "$(grep -o 'in m[0-9]$' <<< "$OUT_C" | sort -u | wc -l | tr -d ' ')"
check "(e) the output is in start order although the first finishes last" "1 2 3 4 5 6" \
  "$(sed -n 's/^mutant \([0-9]\) in .*/\1/p' <<< "$OUT_C" | tr '\n' ' ' | sed 's/ $//')"

# (f) failures
fail_one() {
  echo "mutant says no"
  failed=1
}
abort_one() {
  echo "about to abort"
  : "${DEFINITELY_UNSET_VARIABLE}"
  echo "not reached"
}
OUT_F="$(
  (
    failed=0
    MUTANT_JOBS=2
    mutants_init "${TMP}/f"
    mutant_run fail_one
    mutant_run abort_one
    mutants_wait
    echo "failed=${failed}"
  ) 2>&1 || true
)"
check_has "(f) a failing mutant's own words come back" "$OUT_F" "mutant says no"
check_has "(f) it fails the harness" "$OUT_F" "failed=1"
check_has "(f) an aborting mutant is reported" "$OUT_F" "mutant 2 ended with status"
if [[ "$OUT_F" == *"not reached"* ]]; then fail "(f) an aborting mutant went on after the abort"; else echo "  ok: (f) an aborting mutant stops"; fi

# (g) all pass
pass_one() { echo "fine"; }
OUT_G="$(
  failed=0
  MUTANT_JOBS=2
  mutants_init "${TMP}/g"
  mutant_run pass_one
  mutant_run pass_one
  mutants_wait 2>&1
  echo "failed=${failed}"
)"
check_has "(g) passing mutants keep failed=0" "$OUT_G" "failed=0"

# (i) the default number of mutants at once: half the CPUs, at least 2 and at most 4.
# MUTANT_JOBS overrides it; MUTANT_CPUS is the seam for the CPU count.
JOBS_PROG="${TMP}/jobs_prog.sh"
cat > "$JOBS_PROG" <<'PROG'
. "$1"
MUTANT_CPUS="$2" mutants_init "$3"
echo "$MUTANT_JOBS"
PROG
default_jobs() { # <cpus> [lib] [MUTANT_JOBS]: the MUTANT_JOBS mutants_init settles on for that many CPUs
  local lib="${2:-$LIB}"
  if [[ -n "${3:-}" ]]; then
    MUTANT_JOBS="$3" bash "$JOBS_PROG" "$lib" "$1" "${TMP}/i"
  else
    env -u MUTANT_JOBS bash "$JOBS_PROG" "$lib" "$1" "${TMP}/i"
  fi
}
check "(i) 12 CPUs: 4" "4" "$(default_jobs 12)"
check "(i) 16 CPUs: still 4" "4" "$(default_jobs 16)"
check "(i) 8 CPUs: 4" "4" "$(default_jobs 8)"
check "(i) 6 CPUs: half is 3" "3" "$(default_jobs 6)"
check "(i) 4 CPUs: 2" "2" "$(default_jobs 4)"
check "(i) 2 CPUs: the floor of 2" "2" "$(default_jobs 2)"
check "(i) 1 CPU: the floor of 2" "2" "$(default_jobs 1)"
check "(i) MUTANT_JOBS still overrides" "7" "$(default_jobs 12 "" 7)"
# A mutant of the library that restores a ceiling of 8 must be caught by the 12-CPU case.
if selftest_mutant "$LIB" "${TMP}/lib_cap8.sh" 's/-le 4 \]/-le 8 ]/;s/|| n=4$/|| n=8/'; then
  mutant_default="$(default_jobs 12 "${TMP}/lib_cap8.sh")"
  if [[ "$mutant_default" != "4" ]]; then
    echo "  ok: (i) a library with a ceiling of 8 gives ${mutant_default} on 12 CPUs, which the 12-CPU case above rejects"
  else
    fail "(i) the cap mutant still gives 4 on 12 CPUs: the pin would not catch it"
  fi
fi

# (j) the throttle once counted running mutants with jobs -r, which can reap a
# finished child, so a later wait on its pid failed (status 127, not a child of this
# shell). Twenty mutants that exit at once, two at a time, must all come back clean.
QUICK_PROG="${TMP}/quick_prog.sh"
cat > "$QUICK_PROG" <<'PROG'
. "$1"
failed=0
MUTANT_JOBS=2
mutants_init "$2"
quick_one() { echo "quick ${MUTANT_DIR##*/}"; }
for n in $(seq 1 20); do mutant_run quick_one; done
mutants_wait
echo "failed=${failed}"
PROG
quick_run() { bash "$QUICK_PROG" "$1" "${TMP}/j" 2>&1 || true; }
jbad=0
for round in 1 2 3 4 5 6 7 8; do
  jout="$(quick_run "$LIB")"
  if [[ "$(grep -c '^quick m[0-9]*$' <<< "$jout")" != "20" || "$jout" != *"failed=0"* || "$jout" == *"not a child"* || "$jout" == *"ended with status"* ]]; then
    jbad=1
    echo "round ${round}: $(head -n 8 <<< "$jout")"
  fi
done
check "(j) twenty quick mutants, eight rounds: all clean, failed=0" "0" "$jbad"
# The shape pin: no jobs call in the library (a comment may name it).
jobs_calls() { grep -v '^[[:space:]]*#' "$1" | grep -c 'jobs -' || true; }
check "(j) the library does not call jobs" "0" "$(jobs_calls "$LIB")"
# Mutation proof: a library that counts with jobs -r again is seen by the pin.
cp "$LIB" "${TMP}/lib_jobs.sh"
echo '_mutants_running() { jobs -r | wc -l; }' >> "${TMP}/lib_jobs.sh"
check "(j) mutation proof: a library with jobs -r is seen" "1" "$(jobs_calls "${TMP}/lib_jobs.sh")"

# (h) the browser gate self-test runs its mutation proofs through the library.
# file_has <case> <file> <text>: the file holds <text> (a fixed string); a miss names the
# file, never prints it.
file_has() {
  if grep -qF -- "$3" "$2"; then echo "  ok: $1"; else fail "$1: ${2} has no [${3}]"; fi
}
file_has "(h) ${BROWSER_TEST} sources lib_parallel_mutants.sh" "$BROWSER_TEST" "lib_parallel_mutants.sh"
file_has "(h) it calls mutants_init" "$BROWSER_TEST" "mutants_init"
file_has "(h) it starts its mutants with mutant_run" "$BROWSER_TEST" 'mutant_run "mutant_'
file_has "(h) it calls mutants_wait" "$BROWSER_TEST" "mutants_wait"
# Every selftest_mutant call sits inside a mutant_* function, so none runs on its own,
# one after the other, outside the library.
outside="$(awk '/^mutant_[a-z0-9_]*\(\) \{/ {inside=1} /^\}/ {inside=0} /selftest_mutant / && !inside {print}' "$BROWSER_TEST")"
check "(h) no selftest_mutant call outside a mutant function" "" "$outside"

# (k) the quality jobs pin and the step summary isolation gate run through the library.
for QJ in Scripts/test_quality_jobs.sh Scripts/test_step_summary_isolation.sh; do
  file_has "(k) ${QJ} sources lib_parallel_mutants.sh" "$QJ" "source Scripts/lib_parallel_mutants.sh"
  file_has "(k) ${QJ} calls mutants_init" "$QJ" "mutants_init"
  file_has "(k) ${QJ} starts its cases with mutant_run" "$QJ" "mutant_run "
  file_has "(k) ${QJ} calls mutants_wait" "$QJ" "mutants_wait"
done
# The quality jobs pin's inline judge has a name of its own: the bare name `mutant`
# starts it through the library.
file_has "(k) the inline judge is mutant_case" "Scripts/test_quality_jobs.sh" 'mutant_case() {'

selftest_end "the parallel mutants library self-test failed" "parallel mutants library: concurrency, order, failures, cap and the browser gate use hold"
