#!/usr/bin/env bash
# canon: lib_parallel_mutants v2
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
# at most 4); MUTANT_JOBS=1 runs them one after the other.
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
MUTANT_PIDS=()

# The default number of mutants at once: half the CPUs, at least 2, at most 4, so a
# machine that also runs other jobs is not saturated by one harness. MUTANT_CPUS
# overrides the CPU count (the self-test's seam).
_mutant_default_jobs() {
  local n
  n="${MUTANT_CPUS:-$(sysctl -n hw.ncpu 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null || echo 4)}"
  n=$((n / 2))
  [ "$n" -ge 2 ] || n=2
  [ "$n" -le 4 ] || n=4
  echo "$n"
}

# mutants_init <dir>: the folder under which every mutant gets its own.
mutants_init() {
  MUTANT_ROOT="$1/mutants"
  rm -rf "$MUTANT_ROOT"
  mkdir -p "$MUTANT_ROOT"
  MUTANT_N=0
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
  local n dir
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
  (
    (
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
  local i=0 pid rc
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
  MUTANT_N=0
  MUTANT_PIDS=()
}
