#!/usr/bin/env bash
# Scripts/test_fbp_local_hook.sh (forsgren#290). Not canon: forsgren only.
#
# Self-test of the optional local hook of FBP.sh and sfl.sh: a file named
# .fbp-local.sh in the repository root, git-ignored, which both scripts SOURCE
# (in their own shell, never as a child process) before the first gate. What a
# machine needs to set for its own runs, such as an exported TMPDIR, lives in
# it; the repository holds none and names no machine.
#
#   1. no hook: the run is as before, a gate runs, nothing mentions a hook
#   2. a hook that exports TMPDIR: the gate sees that TMPDIR
#   3. a failing hook: exit 1, a ❌ line naming .fbp-local.sh, no gate runs and
#      (FBP.sh) no commit is made
#   4. the hook cannot be staged: `git add -A` with the file present, under
#      this repository's .gitignore, leaves it untracked
# Cases 1 to 3 run the real FBP.sh (in the FBP sandbox of
# Scripts/lib_fbp_sandbox.sh, stub gates) and the real sfl.sh (in a folder with
# two stub helpers). Mutation proofs: a hook run as a child process fails case
# 2; a hook failure ignored fails case 3; a .gitignore without the line fails
# case 4. Nothing here touches the network or this repository's files.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_fbp_sandbox.sh
source Scripts/lib_fbp_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh

selftest_begin "FBP and sfl local hook self-test"
trap 'fbp_sandbox_cleanup; selftest_cleanup' EXIT

# shellcheck disable=SC2016 # the hook expands it when it is sourced
HOOK_TMPDIR='mkdir -p "$PWD/hooktmp"; export TMPDIR="$PWD/hooktmp"'
HOOK_FAIL='echo "hook ran"; false'
WHY=""
COMMIT=""

# run_fbp <hook> <fbp-script|""> [FBP arguments]: one sandbox run; OUT and RC
# hold its output and exit status, COMMIT the sandbox's commit sha.
run_fbp() {
  local hook="$1" override="$2"
  shift 2
  FBP_SANDBOX_LOCAL_HOOK="$hook" FBP_SANDBOX_SFL_LOG_TMPDIR=1 FBP_SANDBOX_FBP_OVERRIDE="$override" \
    fbp_sandbox_run 3 "$@" || selftest_abort "$FBP_SANDBOX_REASON"
  OUT="$(fbp_sandbox_output)"
  RC="$(fbp_sandbox_rc)"
  COMMIT="$(fbp_sandbox_commit_sha)"
}

# run_sfl <hook> <sfl-script>: a copy of sfl.sh in a folder whose first two
# helpers are stubs: install_tools.sh says which TMPDIR it got, and
# check_node_pin.sh stops the run, so nothing later is needed.
sfl_n=0
run_sfl() {
  local hook="$1" script="$2" dir
  sfl_n=$((sfl_n + 1))
  dir="${TMP}/sfl${sfl_n}"
  mkdir -p "${dir}/Scripts"
  cp "$script" "${dir}/sfl.sh"
  # shellcheck disable=SC2016 # the stub expands it, not this printf
  printf '#!/usr/bin/env bash\necho "stub install_tools TMPDIR=${TMPDIR:-unset}"\n' > "${dir}/Scripts/install_tools.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${dir}/Scripts/check_node_pin.sh"
  chmod +x "${dir}/Scripts/"*.sh "${dir}/sfl.sh"
  if [ -n "$hook" ]; then printf '%s\n' "$hook" > "${dir}/.fbp-local.sh"; fi
  capture bash "${dir}/sfl.sh" post
}

# The checks return 0 when the case holds; WHY says what did not.
check_no_hook() { # <gate marker>
  if ! grep -qF "$1" <<< "$OUT"; then WHY="no gate ran: ${OUT}"; return 1; fi
  if grep -qF ".fbp-local" <<< "$OUT"; then WHY="the output mentions the hook: ${OUT}"; return 1; fi
}
check_tmpdir() { # <gate marker>
  if ! grep -qE "$1=.*/hooktmp\$" <<< "$OUT"; then WHY="the gate did not see the hook's TMPDIR: ${OUT}"; return 1; fi
}
check_failing() { # <gate marker>
  if [ "$RC" != 1 ]; then WHY="exit ${RC}, not 1: ${OUT}"; return 1; fi
  if ! grep -E '^❌.*\.fbp-local\.sh' <<< "$OUT" > /dev/null; then WHY="no ❌ line naming .fbp-local.sh: ${OUT}"; return 1; fi
  if grep -qF "$1" <<< "$OUT"; then WHY="a gate ran after the failing hook: ${OUT}"; return 1; fi
}

case_fbp() { # <case> <FBP script, "" for the real one>
  case "$1" in
    nohook)
      run_fbp "" "$2" --no-commit "290: no hook"
      check_no_hook "stub sfl TMPDIR=" ;;
    tmpdir)
      run_fbp "$HOOK_TMPDIR" "$2" --no-commit "290: tmpdir"
      check_tmpdir "stub sfl TMPDIR" ;;
    failing)
      run_fbp "$HOOK_FAIL" "$2" "290: failing"
      check_failing "stub sfl TMPDIR=" || return 1
      if grep -qF "Step 1/4" <<< "$OUT"; then WHY="the run started PRE: ${OUT}"; return 1; fi
      if [ -n "$COMMIT" ]; then WHY="a commit was made: ${COMMIT}"; return 1; fi ;;
  esac
}

case_sfl() { # <case> <sfl script>
  case "$1" in
    nohook)
      run_sfl "" "$2"
      check_no_hook "stub install_tools TMPDIR=" ;;
    tmpdir)
      run_sfl "$HOOK_TMPDIR" "$2"
      check_tmpdir "stub install_tools TMPDIR" ;;
    failing)
      run_sfl "$HOOK_FAIL" "$2"
      check_failing "stub install_tools" ;;
  esac
}

# case_ignored <unused> <.gitignore file>: a sandbox with that .gitignore, the
# hook present, and the add step FBP.sh runs.
ignored_n=0
case_ignored() {
  local dir
  ignored_n=$((ignored_n + 1))
  dir="${TMP}/ignored${ignored_n}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  cp "$2" "${dir}/.gitignore"
  echo 'export TMPDIR=/nonexistent' > "${dir}/.fbp-local.sh"
  echo x > "${dir}/other.txt"
  git -C "$dir" add -A
  if ! git -C "$dir" ls-files --error-unmatch other.txt > /dev/null 2>&1; then
    WHY="git add -A staged nothing: the check is vacuous"; return 1
  fi
  if git -C "$dir" ls-files --error-unmatch .fbp-local.sh > /dev/null 2>&1; then
    WHY=".fbp-local.sh was staged by git add -A"; return 1
  fi
}

holds() { # <label> <function> <case> <script>
  if "$2" "$3" "$4"; then echo "  ok: $1"; else fail "$1 — ${WHY}"; fi
}

fbp_real="$ROOT/FBP.sh"
sfl_real="$ROOT/sfl.sh"
holds "FBP.sh: no hook changes nothing and says nothing" case_fbp nohook ""
holds "FBP.sh: the gate sees the TMPDIR the hook exports" case_fbp tmpdir ""
holds "FBP.sh: a failing hook stops with a ❌ naming it, no gate, no commit" case_fbp failing ""
holds "sfl.sh: no hook changes nothing and says nothing" case_sfl nohook "$sfl_real"
holds "sfl.sh: the gate sees the TMPDIR the hook exports" case_sfl tmpdir "$sfl_real"
holds "sfl.sh: a failing hook stops with a ❌ naming it, no gate" case_sfl failing "$sfl_real"
grep -qF 'git add -A' FBP.sh || fail "FBP.sh no longer stages with git add -A: case 4 does not test its add step"
holds "git add -A leaves .fbp-local.sh unstaged (git-ignored)" case_ignored hook .gitignore

# Mutation proofs: each mutant must fail the case it targets.
mutant_must_fail() { # <label> <function> <case> <script>
  if "$2" "$3" "$4"; then
    fail "mutation proof: $1 was NOT caught"
  else
    echo "  ok: mutation proof: $1 is caught"
  fi
}
child_sed='s#source \./\.fbp-local\.sh#bash ./.fbp-local.sh#'
ignore_sed='s#hook_rc=\$?#hook_rc=0#'
if selftest_mutant "$fbp_real" "${TMP}/mut/fbp_child.sh" "$child_sed"; then
  mutant_must_fail "FBP.sh running the hook as a child process" case_fbp tmpdir "${TMP}/mut/fbp_child.sh"
fi
if selftest_mutant "$fbp_real" "${TMP}/mut/fbp_ignore.sh" "$ignore_sed"; then
  mutant_must_fail "FBP.sh ignoring a failing hook" case_fbp failing "${TMP}/mut/fbp_ignore.sh"
fi
if selftest_mutant "$sfl_real" "${TMP}/mut/sfl_child.sh" "$child_sed"; then
  mutant_must_fail "sfl.sh running the hook as a child process" case_sfl tmpdir "${TMP}/mut/sfl_child.sh"
fi
if selftest_mutant "$sfl_real" "${TMP}/mut/sfl_ignore.sh" "$ignore_sed"; then
  mutant_must_fail "sfl.sh ignoring a failing hook" case_sfl failing "${TMP}/mut/sfl_ignore.sh"
fi
grep -vF '.fbp-local.sh' .gitignore > "${TMP}/gitignore_without"
mutant_must_fail "a .gitignore without the hook line" case_ignored hook "${TMP}/gitignore_without"

selftest_end "the local hook is not sourced before the first gate, or can be committed" \
  "FBP.sh and sfl.sh source an optional git-ignored .fbp-local.sh before the first gate; a failing hook stops them"
