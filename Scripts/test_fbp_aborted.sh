#!/usr/bin/env bash
# Scripts/test_fbp_aborted.sh
#
# forsgren#85: a killed FBP run must not print "All checks passed".
#
# On 2026-10-10 the session that started FBP ended; the run was terminated
# partway through ./sfl.sh pre, every summary row stayed skipped, nothing was
# committed, and the summary still ended in "All checks passed ✅". The EXIT
# trap (print_summary) reads $? and prints the pass line when it is 0, and
# bash 3.2 (macOS /bin/bash) leaves $? at 0 in the EXIT trap of a script that
# a signal ended.
#
# Drives the REAL FBP.sh in the sandbox of Scripts/lib_fbp_sandbox.sh. The
# stub sfl.sh signals its parent, the FBP.sh run, with
# FBP_SANDBOX_SFL_PRE_SIGNAL: deterministic, no pid looked up.
#
# Table over TERM, INT and HUP (143, 130, 129): a signal to the run ->
# "Aborted ❌ (<SIG>, exit <n>)" in the summary, never "All checks passed",
# and exactly that exit status.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=Scripts/lib_fbp_sandbox.sh
source "${ROOT}/Scripts/lib_fbp_sandbox.sh"
# shellcheck source=Scripts/lib_selftest.sh
source "${ROOT}/Scripts/lib_selftest.sh"

# selftest_begin sets the EXIT trap, replacing the lib's, so the trap that
# replaces both runs the lib's cleanup too (see Scripts/lib_fbp_sandbox.sh).
selftest_begin "FBP aborted-run fixture"
trap 'fbp_sandbox_cleanup; selftest_cleanup' EXIT

# aborted_case <signal> — a run whose PRE is ended by <signal> sent to FBP.sh.
aborted_case() {
  local sig="$1" want="$2" out rc held=true
  if ! FBP_SANDBOX_SFL_PRE_SIGNAL="$sig" fbp_sandbox_run 3 --no-commit "85: a run ended by ${sig}"; then
    fail "${sig}: ${FBP_SANDBOX_REASON}"
    return
  fi
  out="$(fbp_sandbox_output)"
  rc="$(fbp_sandbox_rc)"

  # The run must be real: the signal was sent from inside PRE.
  if ! grep -Fq "Step 1/4: PRE gates" <<< "$out"; then
    fail "${sig}: the run never reached PRE, so nothing was tested. Output: ${out}"
    return
  fi

  if grep -Fq "All checks passed" <<< "$out"; then
    fail "${sig}: a run ended by ${sig} printed 'All checks passed' — a reader or an agent takes it as green. Output: ${out}"
    held=false
  fi
  if ! grep -Fq "Aborted ❌ (${sig}, exit ${want})" <<< "$out"; then
    fail "${sig}: a run ended by ${sig} printed no 'Aborted ❌ (${sig}, exit ${want})' line. Output: ${out}"
    held=false
  fi
  if [ "$rc" != "$want" ]; then
    fail "${sig}: a run ended by ${sig} exited ${rc}, not ${want}"
    held=false
  fi
  if $held; then
    echo "  ok: a run ended by ${sig} prints Aborted ❌ (${sig}, exit ${want}) and exits ${want}"
  fi
}

aborted_case TERM 143
aborted_case INT 130
aborted_case HUP 129

selftest_end "FBP.sh prints All checks passed, or exits 0, on a run a signal ended" \
  "a run ended by TERM, INT or HUP prints Aborted ❌ with the signal, never All checks passed, and exits 143, 130 or 129"
