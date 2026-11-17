#!/usr/bin/env bash
# canon: test_lib_parallel_mutants v5
# v5 adds (forsgren#657): case (n), the default wave is the smaller of the CPU rule and one job per GB of available memory (free plus inactive plus speculative pages of vm_stat, MemAvailable of /proc/meminfo), never below 1; MUTANT_JOBS still wins; memory that cannot be read falls back to the CPU rule with one ⚠️ line; both parsers from fixture text, with mutation proofs; case (i) runs with plenty of memory (MUTANT_MEM_AVAILABLE_KB), so the CPU rule decides there
# v4 adds (forsgren#632): case (m), the browser gate self-test runs its plain cases through the library too, each in a case function started with mutant_run, and only the cases of its named serial list (SERIAL_CASES) one after the other
# v3 adds (forsgren#629, CI red): case (l), a failing mutant in a second batch under set -e fails the harness with its own status, in a folder of its own
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
#       (with plenty of memory, MUTANT_MEM_AVAILABLE_KB, so the CPU rule decides)
#   (n) the memory rule (forsgren#657): the default is the smaller of the CPU rule
#       and one job per GB of available memory, never below 1: plenty of memory
#       leaves the CPU rule, little memory decides, very little gives 1, MUTANT_JOBS
#       still wins; memory that cannot be read (a value that is no number, no
#       vm_stat and no /proc/meminfo) gives the CPU rule with one ⚠️ line; vm_stat
#       (free + inactive + speculative pages, times its page size) and
#       /proc/meminfo (MemAvailable) are parsed from fixture text, an unparsable
#       text is a failed read; mutation proofs: the memory rule dropped, max
#       instead of min, no floor of 1, a silent fallback, inactive pages left out,
#       a fixed page size
#   (j) twenty quick mutants all come back with status 0 and no wait error (jobs -r
#       could reap a child); the library never calls jobs, with a mutation proof for
#       that pin
#   (h) Scripts/test_gate_browser.sh sources the library and runs its mutation proofs
#       through it (mutants_init, mutant_run, mutants_wait), and keeps no
#       selftest_mutant proof outside a mutant function
#   (l) a failing mutant in a later batch (after a mutants_wait), under set -e, fails
#       the harness with its own status and runs in a folder of its own
#   (m) Scripts/test_gate_browser.sh runs its plain cases through the library too
#       (forsgren#632): no gate run outside a function, cases started with
#       mutant_run "case_, and every case it still reports one after the other is
#       named in its SERIAL_CASES list; a mutation proof shows a plain case moved
#       back to the top level is seen
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
# MUTANT_JOBS overrides it; MUTANT_CPUS is the seam for the CPU count. With 64 GB of
# available memory (MUTANT_MEM_AVAILABLE_KB, the seam for the memory read) the memory
# rule of case (n) allows more than 4, so the CPU rule decides every case here.
PLENTY_KB=67108864
JOBS_PROG="${TMP}/jobs_prog.sh"
cat > "$JOBS_PROG" <<'PROG'
. "$1"
MUTANT_CPUS="$2" mutants_init "$3"
echo "$MUTANT_JOBS"
PROG
default_jobs() { # <cpus> [lib] [MUTANT_JOBS] [available KB]: the MUTANT_JOBS mutants_init settles on
  local lib="${2:-$LIB}" mem="${4:-$PLENTY_KB}"
  if [[ -n "${3:-}" ]]; then
    MUTANT_JOBS="$3" MUTANT_MEM_AVAILABLE_KB="$mem" bash "$JOBS_PROG" "$lib" "$1" "${TMP}/i"
  else
    env -u MUTANT_JOBS MUTANT_MEM_AVAILABLE_KB="$mem" bash "$JOBS_PROG" "$lib" "$1" "${TMP}/i"
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

# (n) the memory rule (forsgren#657): on 8 Nov a 16 GB Mac with swap nearly full started
# four browser cases (a Chrome and its node server each) at once and the first wave
# stalled for 9 minutes. The default is now the smaller of the CPU rule and one job per
# GB of available memory, never below 1; MUTANT_JOBS still wins.
# mem_jobs <cpus> <available KB> [lib]: the jobs mutants_init settles on; its stderr
# goes to ${TMP}/mem_err.
mem_jobs() {
  env -u MUTANT_JOBS MUTANT_MEM_AVAILABLE_KB="$2" bash "$JOBS_PROG" "${3:-$LIB}" "$1" "${TMP}/n" 2> "${TMP}/mem_err"
}
warn_lines() { grep -c '^⚠️' "${TMP}/mem_err" || true; }
check "(n) plenty of memory (64 GB), 12 CPUs: the CPU rule decides, 4" "4" "$(mem_jobs 12 "$PLENTY_KB")"
check "(n) and nothing is said on stderr" "" "$(cat "${TMP}/mem_err")"
check "(n) little memory (3 GB), 12 CPUs: memory decides, 3" "3" "$(mem_jobs 12 3145728)"
check_has "(n) and says so on stderr, with the CPU rule it lowered" "$(cat "${TMP}/mem_err")" "3 at once, not 4"
check "(n) and it is no warning" "0" "$(warn_lines)"
check "(n) 2.5 GB: whole jobs only, 2" "2" "$(mem_jobs 12 2621440)"
check "(n) little memory below the CPU floor: 1.5 GB on 2 CPUs gives 1" "1" "$(mem_jobs 2 1572864)"
check "(n) very little memory (512 MB): 1, never 0" "1" "$(mem_jobs 12 524288)"
check "(n) no memory at all (0 KB): still 1" "1" "$(mem_jobs 12 0)"
check "(n) MUTANT_JOBS still wins over the memory rule (512 MB, MUTANT_JOBS=7)" "7" "$(default_jobs 12 "" 7 524288)"
check "(n) memory unreadable (a seam that is no number): the CPU rule, 4" "4" "$(mem_jobs 12 lots)"
check "(n) with one ⚠️ line" "1" "$(warn_lines)"
check_has "(n) that names what was read" "$(cat "${TMP}/mem_err")" "lots"
check_has "(n) and the CPU rule's number" "$(cat "${TMP}/mem_err")" "the CPU rule alone: 4 at once"
check "(n) memory unreadable on 6 CPUs: the CPU rule, 3" "3" "$(mem_jobs 6 lots)"
# No vm_stat and no /proc/meminfo (or no awk to read it): the real read fails, never a
# silent guess. An empty PATH leaves only the shell's builtins.
NOREAD_PROG="${TMP}/noread_prog.sh"
cat > "$NOREAD_PROG" <<'PROG'
. "$1"
MUTANT_CPUS="$2" _mutant_default_jobs
PROG
mkdir -p "${TMP}/emptybin"
noread_jobs() { env -u MUTANT_JOBS -u MUTANT_MEM_AVAILABLE_KB PATH="${TMP}/emptybin" "$BASH" "$NOREAD_PROG" "${2:-$LIB}" "$1" 2> "${TMP}/mem_err"; }
check "(n) no command to read memory with: the CPU rule, 4" "4" "$(noread_jobs 12)"
check "(n) with one ⚠️ line" "1" "$(warn_lines)"
# The real read on this machine gives a whole number of KB.
LIVE_KB="$(
  unset MUTANT_MEM_AVAILABLE_KB
  _mutant_mem_available_kb || echo "failed"
)"
if [[ "$LIVE_KB" =~ ^[0-9]+$ ]]; then echo "  ok: (n) the real memory read gives a whole number of KB (${LIVE_KB})"; else fail "(n) the real memory read gave [${LIVE_KB}]"; fi

# The parsers, from fixture text: vm_stat on Apple silicon (16 KB pages) and on Intel
# (4 KB pages), /proc/meminfo on Linux.
VM_STAT_16K="Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                     5814.
Pages active:                                 213732.
Pages inactive:                               212305.
Pages speculative:                               532.
Pages throttled:                                   0.
Pages wired down:                             392817.
Pages purgeable:                                1730.
File-backed pages:                            136398.
Anonymous pages:                              290171.
Pages stored in compressor:                  2182255.
Pages occupied by compressor:                 183425."
VM_STAT_4K="Mach Virtual Memory Statistics: (page size of 4096 bytes)
Pages free:                                   100000.
Pages active:                                 900000.
Pages inactive:                               300000.
Pages speculative:                             20000.
Pages wired down:                             400000."
MEMINFO="MemTotal:       16303428 kB
MemFree:          512000 kB
MemAvailable:    6291456 kB
Buffers:          102400 kB
Cached:          5120000 kB"
# parse <lib> <parser> <text>: the parser's output, or failed when it refuses the text.
parse() { bash -c '. "$1"; "$2"' _ "$1" "$2" <<< "$3" || echo "failed"; }
# (5814 + 212305 + 532) pages of 16 KB
check "(n) vm_stat, 16 KB pages: free + inactive + speculative, in KB" "3498416" "$(parse "$LIB" _mutant_vm_stat_kb "$VM_STAT_16K")"
# (100000 + 300000 + 20000) pages of 4 KB
check "(n) vm_stat, 4 KB pages" "1680000" "$(parse "$LIB" _mutant_vm_stat_kb "$VM_STAT_4K")"
check "(n) vm_stat without its inactive line: a failed read" "failed" "$(parse "$LIB" _mutant_vm_stat_kb "$(grep -v inactive <<< "$VM_STAT_16K")")"
check "(n) vm_stat without its page size: a failed read" "failed" "$(parse "$LIB" _mutant_vm_stat_kb "$(sed 1d <<< "$VM_STAT_16K")")"
check "(n) vm_stat text that is no vm_stat: a failed read" "failed" "$(parse "$LIB" _mutant_vm_stat_kb "command not found")"
check "(n) /proc/meminfo: MemAvailable, in KB" "6291456" "$(parse "$LIB" _mutant_meminfo_kb "$MEMINFO")"
check "(n) /proc/meminfo without MemAvailable (a kernel before 3.14): a failed read" "failed" "$(parse "$LIB" _mutant_meminfo_kb "$(grep -v MemAvailable <<< "$MEMINFO")")"
check "(n) /proc/meminfo that is empty: a failed read" "failed" "$(parse "$LIB" _mutant_meminfo_kb "")"

# Mutation proofs: each mutant of the library is seen by a case above.
# mem_mutant <name> <sed> <ok text> <pin>: writes the mutant, runs the pin function
# with MUTANT_LIB naming it, and requires the pin to print "seen" (the mutant breaks
# what the case pins).
mem_mutant() {
  local name="$1" expr="$2" ok="$3" pin="$4"
  if selftest_mutant "$LIB" "${TMP}/lib_${name}.sh" "$expr"; then
    MUTANT_LIB="${TMP}/lib_${name}.sh"
    if [[ "$("$pin")" == "seen" ]]; then echo "  ok: (n) mutation proof: ${ok}"; else fail "(n) mutation proof: ${ok}: the cases did not see it"; fi
  fi
}
seen_if_not() { if [[ "$1" != "$2" ]]; then echo "seen"; fi; }
pin_little() { seen_if_not 3 "$(mem_jobs 12 3145728 "$MUTANT_LIB")"; }
pin_plenty() { seen_if_not 4 "$(mem_jobs 12 "$PLENTY_KB" "$MUTANT_LIB")"; }
pin_very_little() { seen_if_not 1 "$(mem_jobs 12 524288 "$MUTANT_LIB")"; }
pin_warning() {
  mem_jobs 12 lots "$MUTANT_LIB" > /dev/null
  seen_if_not 1 "$(warn_lines)"
}
pin_vm_stat() { seen_if_not 3498416 "$(parse "$MUTANT_LIB" _mutant_vm_stat_kb "$VM_STAT_16K")"; }
pin_meminfo() { seen_if_not 6291456 "$(parse "$MUTANT_LIB" _mutant_meminfo_kb "$MEMINFO")"; }
mem_mutant no_memory_rule 's/^      n="[$]m"$/      :/' "without the memory rule, 3 GB on 12 CPUs gives 4" pin_little
mem_mutant max_not_min 's/\(m" \)-lt/\1-gt/' "max instead of min gives more than 4 with plenty of memory" pin_plenty
mem_mutant no_floor 's/ || m=1$//' "without the floor of 1, 512 MB gives 0" pin_very_little
mem_mutant silent_fallback '/available memory not read/s/^\( *\)echo /\1: /' "a fallback without its ⚠️ line" pin_warning
mem_mutant no_inactive 's/free + inactive + spec/free + spec/' "inactive pages left out of the vm_stat sum" pin_vm_stat
mem_mutant fixed_page_size 's/size = [$](i + 1)/size = 4096/' "a page size of 4096 whatever vm_stat says" pin_vm_stat
mem_mutant memfree 's/\^MemAvailable:/^MemFree:/' "MemFree read in place of MemAvailable" pin_meminfo

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

# (l) a second batch after a mutants_wait, under set -e as the browser gate self-test
# runs (its proofs R, S, X and Z are four batches of one). v2 wrote no status file for a
# mutant that set failed=1 (set -e ended the subshell before the write), and the batch
# restarted at m1, so the status read was the passing one of the first batch: a FAIL line
# above an OK line. The failing mutant must fail the harness with its own status, and
# the second batch must start in folders of its own, not in the first batch's.
BATCH_PROG="${TMP}/batch_prog.sh"
cat > "$BATCH_PROG" <<'PROG'
set -euo pipefail
. "$1"
failed=0
MUTANT_JOBS=2
mutants_init "$2"
pass_l() { echo "pass ${MUTANT_DIR##*/}"; : > "${MUTANT_DIR}/left_by_the_first_batch"; }
fail_l() {
  if [ -e "${MUTANT_DIR}/left_by_the_first_batch" ]; then echo "folder shared with the first batch"; fi
  echo "mutant of the second batch says no"
  failed=1
}
mutant_run pass_l
mutant_run pass_l
mutants_wait
mutant_run fail_l
mutants_wait
echo "failed=${failed}"
PROG
batch_run() { bash "$BATCH_PROG" "$1" "${TMP}/l" 2>&1 || true; }
OUT_L="$(batch_run "$LIB")"
check_has "(l) the failing mutant of a second batch speaks" "$OUT_L" "mutant of the second batch says no"
check_has "(l) it fails the harness" "$OUT_L" "failed=1"
check_has "(l) with its own status, 1, numbered on after the first batch (mutant 3)" "$OUT_L" "mutant 3 ended with status 1"
if [[ "$OUT_L" == *"folder shared with the first batch"* ]]; then fail "(l) the second batch ran in a folder of the first batch"; else echo "  ok: (l) the second batch has folders of its own"; fi
# The same harness without set -e: the status is written either way.
OUT_L2="$(sed '1d' "$BATCH_PROG" > "${TMP}/batch_prog_plain.sh" && bash "${TMP}/batch_prog_plain.sh" "$LIB" "${TMP}/l2" 2>&1 || true)"
check_has "(l) without set -e too: status 1, failed=1" "$OUT_L2" "mutant 3 ended with status 1"

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

# (m) the browser gate self-test runs its plain cases side by side too (forsgren#632).
# plain_cases_verdict <file>: "" when every gate run of <file> sits inside a function, the
# cases are started with mutant_run "case_, and every case reported at the top level (one
# after the other) is in the file's SERIAL_CASES list; else one line per reason.
plain_cases_verdict() {
  local file="$1" top runs serial ids id
  if ! grep -q '^SERIAL_CASES=(' "$file"; then
    echo "no SERIAL_CASES=( list naming the cases that run one after the other"
  fi
  if ! grep -qF 'mutant_run "case_' "$file"; then
    echo "no plain case started with mutant_run \"case_"
  fi
  top="$(awk '/^[a-z_0-9]+\(\) \{.*\}[[:space:]]*$/ {next} /^[a-z_0-9]+\(\) \{/ {inside=1; next} inside && /^\}/ {inside=0; next} !inside {print}' "$file")"
  runs="$(grep -E '^[[:space:]]*([A-Z_]+=[^ ]+ )*(run_gate|run_gate_real|run_gate_hit|capture) ' <<< "$top" || true)"
  if [[ -n "$runs" ]]; then
    echo "$(wc -l <<< "$runs" | tr -d ' ') gate runs outside a case function, the first: $(head -1 <<< "$runs")"
  fi
  serial=" $(sed -n 's/^SERIAL_CASES=(\(.*\))$/\1/p' "$file") "
  ids="$({ grep -oE '(want_[a-z_]+|fail|echo) "(  ok: )?[0-9]+[a-z]?:' <<< "$top" || true; } | sed -E 's/^[^"]*"(  ok: )?//; s/:$//' | sort -u)"
  while IFS= read -r id; do
    if [[ -n "$id" && "$serial" != *" ${id} "* ]]; then
      echo "case ${id} runs one after the other and is not in SERIAL_CASES"
    fi
  done <<< "$ids"
}
check "(m) ${BROWSER_TEST} runs its plain cases through the library, only SERIAL_CASES one after the other" "" "$(plain_cases_verdict "$BROWSER_TEST")"
# Mutation proof: a plain case moved back to the top level is seen, its gate run and its id.
cp "$BROWSER_TEST" "${TMP}/browser_top.sh"
printf 'run_gate clean\nwant_green "98: a clean page at the top level" "OK:"\n' >> "${TMP}/browser_top.sh"
VERDICT_M="$(plain_cases_verdict "${TMP}/browser_top.sh")"
check_has "(m) mutation proof: a gate run at the top level is seen" "$VERDICT_M" "gate runs outside a case function"
check_has "(m) mutation proof: and its case, not in SERIAL_CASES, is named" "$VERDICT_M" "case 98 runs one after the other and is not in SERIAL_CASES"

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

selftest_end "the parallel mutants library self-test failed" "parallel mutants library: concurrency, order, failures, cap, memory rule and the browser gate use hold"
