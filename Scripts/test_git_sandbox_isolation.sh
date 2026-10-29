#!/usr/bin/env bash
# canon: test_git_sandbox_isolation v4
# v4 (forsgren#569): locally, with no --shard, the gate starts M shards side by side (Scripts/lib_isolation_local.sh) instead of one serial run; every self-test still runs in both shapes.
# v3 (forsgren#446): --shard deals the self-tests out by their seconds (Scripts/git_sandbox_isolation_weights.txt), greedy, not by index.
# v2 (forsgren#426): an optional --shard N/M runs every M-th self-test of the sorted list.
# Scripts/test_git_sandbox_isolation.sh
#
# Self-test: a self-test run with GIT_DIR, GIT_WORK_TREE and
# GIT_INDEX_FILE exported in the calling shell must not touch that
# repository. `git -C <sandbox>` does not override an exported GIT_DIR, so a
# fixture's `git push origin main` once went into the caller's repository.
#
# The caller's repository here is a DECOY the test builds under its own
# temporary directory, with a bare decoy origin. The variables are set only
# for the child processes, via env, never in this shell. The git-using
# self-tests run with them pointing at the decoy; afterwards the decoy's
# config, HEAD, refs, packed-refs and branch list, and the decoy origin's
# refs and HEAD, must be byte-for-byte what they were.
#
# SCOPE (forsgren#251, decision 249). Quality in CI runs every git-using
# self-test. FBP, and any local run (GITHUB_ACTIONS unset), runs only the
# AFFECTED ones: a self-test is affected when its own file changed, or any file it
# names (the Scripts/ scripts, libraries and data files it calls, followed
# transitively) changed, against the merge base with origin/main, counting
# committed, staged, unstaged and untracked changes. A change to this script or
# to a library it sources (Scripts/lib_gate_select.sh, which also holds changed_files,
# named_files and closure since forsgren#262), or no origin/main to compare against, means every
# self-test. When none is affected the gate says so and passes; it never skips
# without saying. FORSGREN_ISOLATION_FULL=1 forces the full run.
#
# GO CHANGES (forsgren#258). A change to Go code (cmd/*, internal/*, go.mod,
# go.sum) selects the self-tests that build or run the tool ONLY while some
# non-test Go file can start a program: it imports "os/exec", or calls
# os.StartProcess or syscall.Exec, ForkExec or StartProcess (go_starter; test
# files and testdata do not count). The gate exists to catch git commands that
# leave a self-test's sandbox, and Go code that starts no program cannot start
# git. The check reads the working tree at gate time, so a change that adds such
# a file turns the rule back on at once. The scope line says which case applied.
#
# RUNS (forsgren#251, step 2). Locally each selected self-test runs twice under
# the decoy (the two leak shapes below). In Quality (GITHUB_ACTIONS=true) it runs
# once, under the decoy with GIT_DIR and GIT_INDEX_FILE, and the leak check is
# done after that run.
#
# SHARDS (forsgren#426, #446). `--shard N/M` (1 <= N <= M) runs only the self-tests
# that Scripts/lib_isolation_shard.sh deals to shard N of the sorted list of
# git-using self-tests: greedy by the seconds in Scripts/git_sandbox_isolation_weights.txt
# (heaviest first, each to the shard that weighs least so far, a default weight for a
# self-test with no row), so M runs with N = 1..M together run every self-test
# exactly once, the shards weigh about the same, and a new self-test lands in one
# shard by itself, with no list to edit. (#426 dealt by index modulo M, which put
# the slow ones together: 2 minutes against 7.)
# Quality runs the two shards as two jobs (Scripts/ci_job_groups.txt); without
# the argument every self-test runs, as FBP does. The sharding applies to the
# whole list before the scope above picks the affected ones, so the split does
# not move when a commit changes. A bad shard is a usage error (exit 64).
#
# LOCAL SHARDS (forsgren#569). Locally (GITHUB_ACTIONS unset) without --shard the
# script runs itself as M shards side by side (Scripts/lib_isolation_local.sh), M
# half the CPUs, 2 to 4, or FORSGREN_ISOLATION_LOCAL_SHARDS (1 = one serial process
# as before): each shard has its own decoy, its output is printed in shard order,
# and the run fails when a shard failed or left no result. Every self-test still
# runs in both shapes.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

usage() {
  echo "usage: test_git_sandbox_isolation.sh [--shard N/M]  (1 <= N <= M)" >&2
  exit 64
}

SHARD_N=""
SHARD_M=""
if [[ "$#" -gt 0 ]]; then
  [[ "$#" -eq 2 && "$1" == "--shard" ]] || usage
  [[ "$2" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]] || usage
  SHARD_N="${BASH_REMATCH[1]}"
  SHARD_M="${BASH_REMATCH[2]}"
  [[ "$SHARD_N" -le "$SHARD_M" ]] || usage
fi

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_gate_select.sh
source Scripts/lib_gate_select.sh
# shellcheck source=Scripts/lib_isolation_shard.sh
source Scripts/lib_isolation_shard.sh
# shellcheck source=Scripts/lib_isolation_local.sh
source Scripts/lib_isolation_local.sh

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -z "$SHARD_N" && "${GITHUB_ACTIONS:-}" != "true" ]]; then
  LOCAL_M="${FORSGREN_ISOLATION_LOCAL_SHARDS:-$(isolation_default_shards)}"
  [[ "$LOCAL_M" =~ ^[1-9][0-9]*$ ]] || {
    echo "FORSGREN_ISOLATION_LOCAL_SHARDS must be a whole number of at least 1, got: ${LOCAL_M}" >&2
    exit 64
  }
  if [[ "$LOCAL_M" -gt 1 ]]; then
    echo "isolation: local run, ${LOCAL_M} shards side by side"
    if isolation_shards_run "$LOCAL_M" "${TMP}/shards" bash "${PWD}/Scripts/test_git_sandbox_isolation.sh"; then
      echo "OK: all ${LOCAL_M} shards ran and passed"
      exit 0
    fi
    echo ""
    echo "❌ FAIL: a shard failed or left no result (see the FAIL lines above)"
    exit 1
  fi
fi
failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}
ok() {
  echo "  ok: $*"
}

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

DECOY="${TMP}/decoy"
ORIGIN="${TMP}/decoy-origin.git"
git init -q --bare "$ORIGIN"
git init -q -b main "$DECOY"
echo decoy > "${DECOY}/decoy.txt"
git -C "$DECOY" add -A
git -C "$DECOY" -c user.name=decoy -c user.email=decoy@example.test commit -q -m decoy
git -C "$DECOY" remote add origin "$ORIGIN"
git -C "$DECOY" push -q origin main

# snapshot <repo-git-dir> <out-file>: everything a leak would change.
snapshot() {
  {
    echo "--- config"
    cat "$1/config"
    echo "--- HEAD"
    cat "$1/HEAD"
    echo "--- refs"
    git --git-dir="$1" for-each-ref
    echo "--- packed-refs"
    cat "$1/packed-refs" 2> /dev/null
    echo "--- branches"
    git --git-dir="$1" branch -a
  } > "$2" 2>&1
}

# compare <label> <before> <after>: names WHAT changed.
compare() {
  local label="$1" before="$2" after="$3" section
  if cmp -s "$before" "$after"; then
    ok "${label} unchanged"
    return
  fi
  for section in config HEAD refs packed-refs branches; do
    if ! diff <(sed -n "/^--- ${section}\$/,/^--- /p" "$before") \
      <(sed -n "/^--- ${section}\$/,/^--- /p" "$after") > /dev/null; then
      fail "${label}: the ${section} changed: $(diff <(sed -n "/^--- ${section}\$/,/^--- /p" "$before") <(sed -n "/^--- ${section}\$/,/^--- /p" "$after") | grep '^[<>]' | tr '\n' ' ')"
    fi
  done
}

snapshot "${DECOY}/.git" "${TMP}/decoy.before"
snapshot "$ORIGIN" "${TMP}/origin.before"

# One run per git-using self-test, so a reported leak names the self-test that
# caused it. The list is derived with the guard's own detector, never written
# down: a new git-using self-test is run against the decoy from the day it
# exists. This test and the guard are left out (this one would recurse; the
# guard only reads files).
TESTS=()
for t in Scripts/test_*.sh; do
  case "$t" in
    Scripts/test_git_sandbox_isolation.sh | Scripts/test_git_sandbox_guard.sh) continue ;;
  esac
  if git_sandbox_uses_git "$t"; then
    TESTS+=("$t")
  fi
done
if [[ "${#TESTS[@]}" -lt 3 ]]; then
  fail "only ${#TESTS[@]} git-using self-tests found: the detector is broken, not the repository"
fi

# shard_tests: keeps the self-tests dealt to shard N of M, from the list sorted in
# the C locale, so the split does not depend on the locale.
shard_tests() {
  local sorted kept t
  sorted="$(printf '%s\n' "${TESTS[@]}" | LC_ALL=C sort)"
  SHARD_TOTAL="${#TESTS[@]}"
  if ! kept="$(shard_assign "$SHARD_N" "$SHARD_M" Scripts/git_sandbox_isolation_weights.txt <<< "$sorted")"; then
    fail "the shards cannot be dealt: see the line above"
    TESTS=()
    return
  fi
  TESTS=()
  while IFS= read -r t; do
    [[ -n "$t" ]] && TESTS+=("$t")
  done <<< "$kept"
}
SHARD_NOTE=""
if [[ -n "$SHARD_N" ]]; then
  shard_tests
  [[ "$failed" -eq 0 ]] || exit 1
  SHARD_NOTE="shard ${SHARD_N}/${SHARD_M}: ${#TESTS[@]} of ${SHARD_TOTAL} self-tests"
  echo "isolation: ${SHARD_NOTE}"
  if [[ "${#TESTS[@]}" -eq 0 && "$failed" -eq 0 ]]; then
    echo "OK: ${SHARD_NOTE%%:*} holds no git-using self-test; the other shards run all ${SHARD_TOTAL}"
    exit 0
  fi
fi

# go_starter: the first non-test Go file under cmd/ or internal/ (not *_test.go,
# not under testdata) that can start a program, else nothing. Starting a program
# means one of: importing "os/exec", calling os.StartProcess, or calling
# syscall.Exec, syscall.ForkExec or syscall.StartProcess. It reads the working
# tree at gate time, so adding such a file in the same change counts at once. A
# match in a comment still counts: the error is only ever more self-tests.
go_starter() {
  local f
  while IFS= read -r f; do
    if grep -qE '"os/exec"|os[.]StartProcess|syscall[.](Exec|ForkExec|StartProcess)' "$f"; then
      echo "$f"
      return
    fi
  done < <(find cmd internal -name '*.go' ! -name '*_test.go' ! -path '*/testdata/*' 2> /dev/null | sort)
}

# select_tests: sets SELECTED (the affected self-tests) and SCOPE_NOTE (why).
select_tests() {
  local changed t c own go_changed=""
  SELECTED=()
  GO_NOTE=""
  if [[ "${GITHUB_ACTIONS:-}" == "true" || "${FORSGREN_ISOLATION_FULL:-}" == "1" ]]; then
    SELECTED=("${TESTS[@]}")
    SCOPE_NOTE="full run (Quality, or forced)"
    return
  fi
  if ! changed="$(changed_files)"; then
    SELECTED=("${TESTS[@]}")
    SCOPE_NOTE="full run (no origin/main to compare against)"
    return
  fi
  own="$(closure Scripts/test_git_sandbox_isolation.sh)"
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    if grep -qxF -- "$c" <<< "$own"; then
      SELECTED=("${TESTS[@]}")
      SCOPE_NOTE="full run (${c} is part of this gate)"
      return
    fi
  done <<< "$changed"
  GO_STARTER="$(go_starter)"
  while IFS= read -r c; do
    case "$c" in cmd/* | internal/* | go.mod | go.sum) go_changed=1 ;; esac
  done <<< "$changed"
  if [[ -n "$go_changed" && -z "$GO_STARTER" ]]; then
    GO_NOTE="isolation: Go changes select nothing, no non-test Go file starts a program"
  elif [[ -n "$go_changed" ]]; then
    GO_NOTE="isolation: Go changes count, ${GO_STARTER} starts a program"
  fi
  for t in "${TESTS[@]}"; do
    local files code
    files="$(closure "$t")"
    code="$(while IFS= read -r c; do cat "$c"; done <<< "$files")"
    while IFS= read -r c; do
      [[ -z "$c" ]] && continue
      if grep -qxF -- "$c" <<< "$files"; then
        SELECTED+=("$t")
        break
      fi
      # Go code and go.mod change what a self-test that builds or runs the tool
      # does, but only while some non-test Go file can start a program (forsgren#258).
      case "$c" in cmd/* | internal/* | go.mod | go.sum)
        if [[ -n "$GO_STARTER" ]] && grep -qE 'go (build|run|test|install)|cmd/forsgren' <<< "$code"; then
          SELECTED+=("$t")
          break
        fi ;;
      esac
    done <<< "$changed"
  done
  SCOPE_NOTE="changed or affected only; Quality runs all"
}

select_tests
[[ -n "${GO_NOTE:-}" ]] && echo "$GO_NOTE"
if [[ "${#SELECTED[@]}" -eq 0 ]]; then
  echo "isolation: 0 of ${#TESTS[@]} self-tests affected, full run in Quality"
  echo "OK: no git-using self-test is affected by the changes; Quality runs all ${#TESTS[@]}"
  exit 0
fi
echo "isolation: ${#SELECTED[@]} of ${#TESTS[@]} self-tests affected (${SCOPE_NOTE})"
TESTS=("${SELECTED[@]}")

# Two shapes of the leak (locally both run; Quality runs the second only, once): all three variables (the 2026-10-18 shell), and
# GIT_DIR with GIT_INDEX_FILE only, which lets fixtures that init a bare
# repository get past the work-tree check and reach their push.
run_variant() {
  local name="$1"
  shift
  local t before_fail
  for t in "${TESTS[@]}"; do
    if [[ ! -f "$t" ]]; then
      fail "${t} does not exist, so its isolation cannot be shown"
      continue
    fi
    env "$@" bash "$t" > "${TMP}/run.out" 2>&1 < /dev/null
    snapshot "${DECOY}/.git" "${TMP}/decoy.after"
    snapshot "$ORIGIN" "${TMP}/origin.after"
    before_fail=$failed
    compare "${t} (${name}): the decoy repository" "${TMP}/decoy.before" "${TMP}/decoy.after"
    compare "${t} (${name}): the decoy origin" "${TMP}/origin.before" "${TMP}/origin.after"
    if [[ "$failed" -ne "$before_fail" ]]; then
      # Later runs compare against what is on disk now, not the first leak again.
      cp "${TMP}/decoy.after" "${TMP}/decoy.before"
      cp "${TMP}/origin.after" "${TMP}/origin.before"
    fi
  done
}

if [[ "${GITHUB_ACTIONS:-}" = "true" ]]; then
  # Quality (forsgren#251, step 2): each self-test runs ONCE, under the decoy,
  # and the leak check is inside that run. The shape without GIT_WORK_TREE is
  # the one that lets a fixture that inits a bare repository get past the
  # work-tree check, so it reaches every push the all-three shape reaches.
  echo "isolation: Quality, each self-test runs once under the decoy"
  run_variant "single run under the decoy: GIT_DIR, GIT_INDEX_FILE" GIT_DIR="${DECOY}/.git" GIT_INDEX_FILE="${DECOY}/.git/index"
else
  run_variant "GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE" \
    GIT_DIR="${DECOY}/.git" GIT_WORK_TREE="$DECOY" GIT_INDEX_FILE="${DECOY}/.git/index"
  run_variant "GIT_DIR, GIT_INDEX_FILE" \
    GIT_DIR="${DECOY}/.git" GIT_INDEX_FILE="${DECOY}/.git/index"
fi

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "❌ FAIL: a self-test escaped its sandbox into the repository named by GIT_DIR (see the FAIL lines above)"
  exit 1
fi
echo "OK: ${#TESTS[@]} git-using self-tests leave a repository named by GIT_DIR untouched"
