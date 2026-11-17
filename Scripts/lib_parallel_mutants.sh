#!/usr/bin/env bash
# canon: lib_parallel_mutants v4
# v4 adds (forsgren#657): the default wave is the smaller of the CPU rule and one job per GB of available memory (free plus inactive plus speculative pages of vm_stat on macOS, MemAvailable of /proc/meminfo on Linux), never below 1, said on stderr when memory lowers it; memory that cannot be read falls back to the CPU rule with one ⚠️ line; MUTANT_MEM_AVAILABLE_KB is the seam for the read; a set MUTANT_JOBS still wins
# v3 fixes (forsgren#629, CI red): a mutant that set failed=1 under the caller's set -e left no status file, so a later batch, restarting at m1, read the passing status of the first batch and a failed proof printed its FAIL line above an OK line; the status is now written whatever the end, and a later batch numbers on from the last mutant instead of restarting at m1
# lib_parallel_mutants.sh — sourced, never run on its own.
#
# The mutation harnesses (self-tests that rerun a heavy fixture once per mutant) run
# their mutants one after the other. This lets a harness run its mutants side by side,
# each in a folder of its own, and print the results in the order the mutants were
# started, so the log reads the same as a serial run.
#
#   . "$(dirname "$0")/lib_parallel_mutants.sh"
#   failed=0                            # the harness's own flag, read by mutants_wait
#   mutants_init "$TMP"                 # a folder for the mutants, inside the harness TMP
#   mutant_run mutate_one LABEL ...     # starts: mutate_one LABEL ... in a subshell
#   ...
#   mutants_wait                        # waits, prints each mutant's output in order,
#                                       # sets failed=1 when any mutant failed
#
# A mutant function:
#   * works in "$MUTANT_DIR", a folder of its own (never a path shared with another
#     mutant: that is the one thing that makes mutants unsafe to run together);
#   * reports a failure by setting the `failed` variable (the usual `fail` helper
#     does that) and returning: the subshell exits with `failed` as its status, which
#     is how the parent learns of it. Setting `failed` in a subshell changes nothing
#     in the parent, so mutants_wait does it from the exit statuses;
#   * writes everything it wants to say to stdout/stderr: it is captured and printed
#     in order by mutants_wait.
# MUTANT_JOBS is the number of mutants at once (default: half the CPUs, at least 2,
# at most 4, and no more than one per GB of available memory, at least 1);
# MUTANT_JOBS=1 runs them one after the other.
#
# An abort inside a mutant (an unbound variable under set -u, a failing command under
# set -e) ends that subshell with a non-zero status, which mutants_wait reports. The
# caller's EXIT trap does not run in the subshell: a harness keeps one cleanup, in the
# parent.
#
# The library never calls `jobs`: `jobs` can reap a finished child, and a later
# `wait <pid>` then fails with `not a child of this shell` (status 127). Each mutant
# writes its own status to a file when it ends, the throttle counts those files, and
# mutants_wait reads the status from the file: `wait` only reaps.
#
# MUTANT_DIR is exported, not merely assigned: the mutant function (written by the
# caller) is the one that reads it, which a static check of this file cannot see, and
# an exported variable is a deliberate interface, not an unused one.

MUTANT_ROOT=""
MUTANT_N=0
MUTANT_BASE=0
MUTANT_PIDS=()

# One job per this much available memory (KB). The heaviest mutants are the browser
# gate self-test's cases: one case (Chrome with its helpers, its node server and the
# gate's shell) peaked at 700 to 725 MB of summed RSS, measured on macOS (forsgren#657);
# 1 GB per job leaves about 30% for a case with more pages or variants.
MUTANT_KB_PER_JOB=1048576

# _mutant_vm_stat_kb: reads vm_stat's output on stdin and prints the available memory
# in KB: free plus inactive plus speculative pages, times the page size its first line
# names. vm_stat's "Pages free" leaves the speculative pages out, so the sum is the
# kernel's free count plus its inactive count, the pages it hands out before it takes
# any from a running process (psutil's "available" on macOS is the same sum). Status 1,
# nothing printed, when a line is missing or no number.
_mutant_vm_stat_kb() {
  awk '
    function count(v) { sub(/\.$/, "", v); if (v !~ /^[0-9]+$/) bad = 1; return v + 0 }
    /page size of/ { for (i = 1; i < NF; i++) if ($i == "of") size = $(i + 1) }
    /^Pages free:/ { free = count($3); seen++ }
    /^Pages inactive:/ { inactive = count($3); seen++ }
    /^Pages speculative:/ { spec = count($3); seen++ }
    END {
      if (seen != 3 || bad || size !~ /^[0-9]+$/ || size == 0) exit 1
      printf "%.0f\n", (free + inactive + spec) * size / 1024
    }'
}

# _mutant_meminfo_kb: reads /proc/meminfo on stdin and prints its MemAvailable in KB
# (the kernel's own estimate of what can be handed out without swapping). Status 1,
# nothing printed, without that line in kB (a kernel before 3.14 has none).
_mutant_meminfo_kb() {
  awk '
    /^MemAvailable:/ { if ($2 ~ /^[0-9]+$/ && $3 == "kB") kb = $2 }
    END { if (kb == "") exit 1; print kb }'
}

# _mutant_mem_available_kb: prints the available memory in KB; when it cannot be read,
# prints why and returns 1 (never a guess). MUTANT_MEM_AVAILABLE_KB overrides the read
# (the self-test's seam); a value that is no whole number is a failed read.
_mutant_mem_available_kb() {
  local kb
  if [ -n "${MUTANT_MEM_AVAILABLE_KB:-}" ]; then
    case "$MUTANT_MEM_AVAILABLE_KB" in
      *[!0-9]*) echo "MUTANT_MEM_AVAILABLE_KB=${MUTANT_MEM_AVAILABLE_KB} is no whole number of KB"; return 1 ;;
    esac
    echo "$MUTANT_MEM_AVAILABLE_KB"
    return 0
  fi
  if command -v vm_stat > /dev/null 2>&1; then
    if kb="$(vm_stat 2> /dev/null | _mutant_vm_stat_kb 2> /dev/null)" && [ -n "$kb" ]; then echo "$kb"; return 0; fi
    echo "vm_stat gave no free, inactive and speculative page counts with a page size"
    return 1
  fi
  if [ -r /proc/meminfo ]; then
    if kb="$(_mutant_meminfo_kb < /proc/meminfo 2> /dev/null)" && [ -n "$kb" ]; then echo "$kb"; return 0; fi
    echo "/proc/meminfo gave no MemAvailable in kB"
    return 1
  fi
  echo "neither vm_stat nor /proc/meminfo is there"
  return 1
}

# The default number of mutants at once: half the CPUs, at least 2, at most 4, so a
# machine that also runs other jobs is not saturated by one harness, and no more than
# one per GB of available memory, at least 1 (v4, forsgren#657: four browser cases
# started together on a Mac with swap nearly full stalled for 9 minutes). A lowered
# wave is said on stderr; memory that cannot be read leaves the CPU rule, with one ⚠️
# line on stderr. MUTANT_CPUS overrides the CPU count (the self-test's seam).
_mutant_default_jobs() {
  local n mem m
  n="${MUTANT_CPUS:-$(sysctl -n hw.ncpu 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null || echo 4)}"
  n=$((n / 2))
  [ "$n" -ge 2 ] || n=2
  [ "$n" -le 4 ] || n=4
  if mem="$(_mutant_mem_available_kb)"; then
    m=$((mem / MUTANT_KB_PER_JOB))
    [ "$m" -ge 1 ] || m=1
    if [ "$m" -lt "$n" ]; then
      echo "lib_parallel_mutants: ${m} at once, not ${n}: $((mem / 1024)) MB of memory available, one job per $((MUTANT_KB_PER_JOB / 1024)) MB" >&2
      n="$m"
    fi
  else
    echo "⚠️ lib_parallel_mutants: available memory not read (${mem}); the default wave follows the CPU rule alone: ${n} at once" >&2
  fi
  echo "$n"
}

# mutants_init <dir>: the folder under which every mutant gets its own.
mutants_init() {
  MUTANT_ROOT="$1/mutants"
  rm -rf "$MUTANT_ROOT"
  mkdir -p "$MUTANT_ROOT"
  MUTANT_N=0
  MUTANT_BASE=0
  MUTANT_PIDS=()
  MUTANT_JOBS="${MUTANT_JOBS:-$(_mutant_default_jobs)}"
}

# _mutants_running: how many started mutants have not written their status yet.
_mutants_running() {
  local done_n
  done_n="$(find "$MUTANT_ROOT" -maxdepth 1 -name 'm*.rc' | wc -l | tr -d ' ')"
  echo $((MUTANT_N - done_n))
}

# mutant_run <function> [args...]: starts the function in a subshell, in its own
# folder ($MUTANT_DIR), waiting first when MUTANT_JOBS mutants are already running.
mutant_run() {
  local n dir errexit=0
  case "$-" in *e*) errexit=1 ;; esac
  while [ "$(_mutants_running)" -ge "$MUTANT_JOBS" ]; do
    sleep 0.1
  done
  MUTANT_N=$((MUTANT_N + 1))
  n="$MUTANT_N"
  dir="${MUTANT_ROOT}/m${n}"
  mkdir -p "$dir"
  # Set in the parent, just before the fork, so the subshell inherits it (and the
  # parent never sees a variable assigned in a subshell).
  export MUTANT_DIR="$dir"
  # The status is written whatever the mutant's end: under the caller's set -e a
  # failing inner subshell would end this one before the write (v2), and the
  # status read was then "missing" or a stale one. The mutant itself keeps the
  # caller's set -e, so an abort inside it still ends it.
  (
    set +e
    (
      if [ "$errexit" -eq 1 ]; then set -e; fi
      failed=0
      "$@"
      exit "$failed"
    )
    echo "$?" > "${MUTANT_ROOT}/m${n}.rc.tmp"
    mv "${MUTANT_ROOT}/m${n}.rc.tmp" "${MUTANT_ROOT}/m${n}.rc"
  ) > "${MUTANT_ROOT}/m${n}.out" 2>&1 &
  MUTANT_PIDS+=("$!")
}

# mutants_wait: waits for every mutant started, prints their output in start order and
# sets failed=1 when any of them failed.
mutants_wait() {
  local i="$MUTANT_BASE" pid rc
  if [ "${#MUTANT_PIDS[@]}" -gt 0 ]; then
    for pid in "${MUTANT_PIDS[@]}"; do
      i=$((i + 1))
      wait "$pid" 2> /dev/null || true
      rc="$(cat "${MUTANT_ROOT}/m${i}.rc" 2> /dev/null || echo missing)"
      cat "${MUTANT_ROOT}/m${i}.out"
      if [ "$rc" != "0" ]; then
        echo "❌ FAIL: mutant ${i} ended with status ${rc}"
        failed=1
      fi
    done
  fi
  # The next batch numbers on (v3): v2 restarted at m1, where the status file of the
  # first batch's m1 was still there to be read, and its folder to be shared.
  MUTANT_BASE="$MUTANT_N"
  MUTANT_PIDS=()
}
