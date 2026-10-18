#!/usr/bin/env bash
# Scripts/test_fbp_abort_exit.sh
#
# forsgren#136: an FBP.sh run that aborts on an unbound variable must not exit
# 0 or print "All checks passed".
#
# On bash 3.2 (macOS /bin/bash) a script under `set -euo pipefail` that has an
# EXIT trap ends with status 0 after an unbound variable in the main shell,
# and $? inside the trap is 0 too. FBP.sh is such a script: print_summary read
# that 0 and printed "All checks passed ✅". Measured 2026-10-13 on the real
# FBP.sh: the abort exits 0 and says All checks passed. (The same abort in
# sfl.sh does not reproduce: sfl.sh sets neither -e nor -u.)
#
# Drives the REAL FBP.sh, in the sandbox of Scripts/lib_fbp_sandbox.sh, as a
# copy with one line injected right after its `trap print_summary EXIT`: an
# unbound variable read. The run must exit non-zero, name the variable (a run
# that died earlier proves nothing), print Aborted ❌ and not All checks passed.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=Scripts/lib_git_sandbox.sh
source "${ROOT}/Scripts/lib_git_sandbox.sh"
# shellcheck source=Scripts/lib_fbp_sandbox.sh
source "${ROOT}/Scripts/lib_fbp_sandbox.sh"
# shellcheck source=Scripts/lib_selftest.sh
source "${ROOT}/Scripts/lib_selftest.sh"

# selftest_begin sets the EXIT trap, replacing the lib's, so the trap that
# replaces both runs the lib's cleanup too (see Scripts/lib_fbp_sandbox.sh).
selftest_begin "FBP abort-exit fixture"
trap 'fbp_sandbox_cleanup; selftest_cleanup' EXIT

PROBE_VAR="FBP_ABORT_PROBE"

if ! fbp_sandbox_new_dir; then
  selftest_abort "could not make a directory for the probed FBP.sh"
fi
mutant="${FBP_SANDBOX_NEW_DIR}/FBP.sh"
awk -v v="$PROBE_VAR" '{ print } /^trap print_summary EXIT$/ && !done { print ": \"${" v "}\""; done = 1 }' "$FBP_SANDBOX_FBP" > "$mutant"
chmod +x "$mutant"
if cmp -s "$FBP_SANDBOX_FBP" "$mutant"; then
  selftest_abort "FBP.sh has no top-level 'trap print_summary EXIT' line to probe, so nothing was tested"
fi

if ! FBP_SANDBOX_FBP_OVERRIDE="$mutant" fbp_sandbox_run 3 --no-commit "136: an abort after the EXIT trap"; then
  selftest_abort "${FBP_SANDBOX_REASON}"
fi
out="$(fbp_sandbox_output)"
rc="$(fbp_sandbox_rc)"

if ! grep -Fq "${PROBE_VAR}: unbound variable" <<< "$out"; then
  fail "the probe never reached the trap (exit ${rc}), so nothing was tested. Output: ${out}"
else
  if [ "$rc" = "0" ]; then
    fail "an abort after FBP.sh's EXIT trap exits 0 — a caller takes that as green. Output: ${out}"
  else
    echo "  ok: an abort after FBP.sh's EXIT trap exits ${rc}, not 0"
  fi
  if grep -Fq "All checks passed" <<< "$out"; then
    fail "an aborted run's summary says 'All checks passed' — a reader or an agent takes it as green. Output: ${out}"
  else
    echo "  ok: the summary of an aborted run does not say All checks passed"
  fi
  if grep -Fq "Aborted ❌" <<< "$out"; then
    echo "  ok: the summary of an aborted run says Aborted ❌"
  else
    fail "the summary of an aborted run must say Aborted ❌. Output: ${out}"
  fi
fi

selftest_end "FBP.sh exits 0, or prints All checks passed, on a run that aborted on an unbound variable" \
  "a run that aborts on an unbound variable after the EXIT trap exits non-zero and prints Aborted ❌, never All checks passed"
