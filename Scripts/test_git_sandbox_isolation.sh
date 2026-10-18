#!/usr/bin/env bash
# Scripts/test_git_sandbox_isolation.sh
#
# Self-test for forsgren#228: a self-test run with GIT_DIR, GIT_WORK_TREE and
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

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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

# One run per self-test, so a reported leak names the self-test that caused it.
TESTS=(
  Scripts/test_release_commit.sh
  Scripts/test_metrics_workflow.sh
  Scripts/test_release_workflow.sh
  Scripts/test_fbp_no_push.sh
  Scripts/test_fbp_commit_message.sh
  Scripts/test_fbp_build_pagecount.sh
  Scripts/test_fbp_aborted.sh
  Scripts/test_fbp_abort_exit.sh
  Scripts/test_release_resume.sh
  Scripts/test_sfl_pull.sh
)

# Two shapes of the leak: all three variables (the 2026-10-18 shell), and
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

run_variant "GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE" \
  GIT_DIR="${DECOY}/.git" GIT_WORK_TREE="$DECOY" GIT_INDEX_FILE="${DECOY}/.git/index"
run_variant "GIT_DIR, GIT_INDEX_FILE" \
  GIT_DIR="${DECOY}/.git" GIT_INDEX_FILE="${DECOY}/.git/index"

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "❌ FAIL: a self-test escaped its sandbox into the repository named by GIT_DIR (see the FAIL lines above)"
  exit 1
fi
echo "OK: ${#TESTS[@]} git-using self-tests leave a repository named by GIT_DIR untouched"
