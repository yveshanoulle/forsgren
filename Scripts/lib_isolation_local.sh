#!/usr/bin/env bash
# Scripts/lib_isolation_local.sh (forsgren#569). Not canon: forsgren only.
#
# SOURCED, never run. It sets no shell options.
#
# The git sandbox isolation gate runs every selected self-test twice locally (two leak
# shapes), one after the other: 1100 to 1200 seconds when all are selected. The script
# already deals the self-tests to shards (--shard N/M, Scripts/lib_isolation_shard.sh);
# this starts all M shards at once, locally, each in a process of its own with its own
# decoy repository, and joins them.
#
#   isolation_default_shards
#     Prints M: half the CPUs, at least 2, at most 4 (the cap of
#     Scripts/lib_parallel_mutants.sh, so one gate never saturates the machine).
#   isolation_shards_run <m> <dir> <command...>
#     Starts <command...> --shard N/<m> for N = 1..m in the background, all at once
#     (m is at most 4, so there is nothing to throttle), each writing its status to a
#     file of its own when it ends. Waits for every shard, prints each shard's output
#     in shard order, and returns 1 when any shard failed OR left no status file (a
#     shard that was killed has no result, and a missing result is a failure, never a
#     pass). It never calls `jobs`: that can reap a finished child and make a later
#     `wait` fail; `wait` here only reaps.

# shellcheck source=Scripts/lib_parallel_mutants.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib_parallel_mutants.sh"

isolation_default_shards() {
  _mutant_default_jobs
}

isolation_shards_run() {
  local m="$1" dir="$2" n pid rc status=0
  local pids=()
  shift 2
  rm -rf "$dir"
  mkdir -p "$dir"
  for ((n = 1; n <= m; n++)); do
    (
      "$@" --shard "${n}/${m}"
      echo "$?" > "${dir}/s${n}.rc.tmp"
      mv "${dir}/s${n}.rc.tmp" "${dir}/s${n}.rc"
    ) > "${dir}/s${n}.out" 2>&1 < /dev/null &
    pids+=("$!")
  done
  for ((n = 1; n <= m; n++)); do
    pid="${pids[$((n - 1))]}"
    wait "$pid" 2> /dev/null || true
    rc="$(cat "${dir}/s${n}.rc" 2> /dev/null || echo missing)"
    cat "${dir}/s${n}.out"
    if [[ "$rc" == "missing" ]]; then
      echo "❌ FAIL: shard ${n}/${m} left no result (it ended before writing its status)"
      status=1
    elif [[ "$rc" != "0" ]]; then
      echo "❌ FAIL: shard ${n}/${m} failed with status ${rc}"
      status=1
    fi
  done
  return "$status"
}
