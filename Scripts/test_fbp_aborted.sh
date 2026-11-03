#!/usr/bin/env bash
# Scripts/test_fbp_aborted.sh
#
# forsgren#85: a killed FBP run must not print "All checks passed".
#
# On 2026-10-10 the session that started FBP ended; the run was terminated
# partway through ./sfl.sh pre, every summary row stayed skipped, nothing was
# committed, and the summary still ended in "All checks passed ✅". The EXIT
# trap (print_summary) reads $? and prints the pass line when it is 0, and
# when a signal the script does not trap ends it, bash 3.2 (macOS /bin/bash)
# runs the EXIT trap with $? at 0.
#
# Drives the REAL FBP.sh in the sandbox of Scripts/lib_fbp_sandbox.sh. The
# stub sfl.sh signals its parent, the FBP.sh run, with
# FBP_SANDBOX_SFL_PRE_SIGNAL: deterministic, no pid looked up.
#
# Table over TERM, INT and HUP (143, 130, 129): a signal to the run ->
# "Aborted ❌ (<SIG>, exit <n>)" in the summary, never "All checks passed",
# and exactly that exit status.
#
# forsgren#234: the same table again with the signal IGNORED in the fixture's
# own process. An ignored disposition is inherited through exec, and a
# non-interactive bash does not trap a signal that was ignored on entry, so a
# run launched under nohup, or by a harness that ignores HUP, never saw its
# HUP trap and finished green: the HUP case that failed once and passed on
# rerun depends on how the fixture was launched, not on timing. The run must
# not inherit the ignore.

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
selftest_begin "FBP aborted-run fixture"
trap 'fbp_sandbox_cleanup; selftest_cleanup' EXIT

# aborted_case <signal> <want> — a run whose PRE is ended by <signal> sent to
# FBP.sh must print Aborted ❌ (<signal>, exit <want>) and exit <want>.
aborted_case() {
  local sig="$1" want="$2" how="${3:-}" out rc held=true
  if ! FBP_SANDBOX_SFL_PRE_SIGNAL="$sig" fbp_sandbox_run 3 --no-commit "85: a run ended by ${sig}"; then
    fail "${sig}${how}: ${FBP_SANDBOX_REASON}"
    return
  fi
  out="$(fbp_sandbox_output)"
  rc="$(fbp_sandbox_rc)"

  # The run must be real: the signal was sent from inside PRE.
  if ! grep -Fq "Step 1/4: PRE gates" <<< "$out"; then
    fail "${sig}${how}: the run never reached PRE, so nothing was tested. Output: ${out}"
    return
  fi

  if grep -Fq "All checks passed" <<< "$out"; then
    fail "${sig}${how}: a run ended by ${sig} printed 'All checks passed' — a reader or an agent takes it as green. Output: ${out}"
    held=false
  fi
  if ! grep -Fq "Aborted ❌ (${sig}, exit ${want})" <<< "$out"; then
    fail "${sig}${how}: a run ended by ${sig} printed no 'Aborted ❌ (${sig}, exit ${want})' line. Output: ${out}"
    held=false
  fi
  if [ "$rc" != "$want" ]; then
    fail "${sig}${how}: a run ended by ${sig} exited ${rc}, not ${want}"
    held=false
  fi
  if $held; then
    echo "  ok: a run ended by ${sig}${how} prints Aborted ❌ (${sig}, exit ${want}) and exits ${want}"
  fi
}

aborted_case TERM 143
aborted_case INT 130
aborted_case HUP 129

# ignored_case <signal> <want> — the same case, with <signal> ignored in this
# process when the run starts (trap '' <signal> is inherited through exec).
ignored_case() {
  local sig="$1"
  trap '' "$sig"
  aborted_case "$sig" "$2" " (ignored on entry)"
  trap - "$sig"
}

ignored_case HUP 129
ignored_case TERM 143
ignored_case INT 130

# forsgren#234, the ready condition: the signal is sent by the stub sfl.sh, so
# the run is ready for it exactly when every signal trap is installed before
# FBP.sh starts ./sfl.sh pre. The handshake is the source order, proven here
# for the real FBP.sh and for a mutant (no sleep, no clock).
# traps_before_pre <file> — prints nothing and returns 0 when the EXIT, TERM,
# INT and HUP traps all come before the first ./sfl.sh pre line; otherwise
# prints which one is late, with both line numbers, and returns 1.
traps_before_pre() {
  local pre_line sig trap_line late=""
  pre_line="$(grep -n '^\./sfl\.sh pre' "$1" | head -1 | cut -d: -f1)"
  [ -n "$pre_line" ] || { echo "no './sfl.sh pre' line in $1"; return 1; }
  for sig in EXIT TERM INT HUP; do
    trap_line="$(grep -n "^trap .* ${sig}\$" "$1" | head -1 | cut -d: -f1)"
    if [ -z "$trap_line" ]; then
      late="${late}the ${sig} trap is missing; "
    elif [ "$trap_line" -gt "$pre_line" ]; then
      late="${late}the ${sig} trap (line ${trap_line}) comes after ./sfl.sh pre (line ${pre_line}); "
    fi
  done
  [ -z "$late" ] || { echo "$late"; return 1; }
}

late_reason="$(traps_before_pre "$FBP_SANDBOX_FBP")" && late_rc=0 || late_rc=$?
if [ "$late_rc" -eq 0 ]; then
  echo "  ok: FBP.sh installs its EXIT, TERM, INT and HUP traps before ./sfl.sh pre"
else
  fail "FBP.sh is not ready when PRE signals it: ${late_reason}"
fi

# Mutation: the HUP trap moved to just after ./sfl.sh pre must be caught, and
# for that reason.
mutant="${TMP}/FBP_late_hup.sh"
awk '/^trap .on_signal HUP. HUP$/ { next } { print } /^\.\/sfl\.sh pre/ { print "trap '"'"'on_signal HUP'"'"' HUP" }' \
  "$FBP_SANDBOX_FBP" > "$mutant"
mutant_reason="$(traps_before_pre "$mutant")" && mutant_rc=0 || mutant_rc=$?
if [ "$mutant_rc" -ne 0 ] && grep -Fq "the HUP trap (line " <<< "$mutant_reason" \
   && grep -Fq ") comes after ./sfl.sh pre (line " <<< "$mutant_reason"; then
  echo "  ok: a HUP trap installed after ./sfl.sh pre is caught: ${mutant_reason}"
else
  fail "mutation: a HUP trap after ./sfl.sh pre went unseen or for another reason (rc ${mutant_rc}): ${mutant_reason}"
fi

# forsgren#614: the sfl logs (forsgren_sfl_pre.*, forsgren_sfl_post.*) are gone
# after the run on EVERY way out: a green run, a red PRE, a signal, and a
# summary that itself ends the script early. Each run gets its own TMPDIR, so
# the find sees this run's files alone. leftovers_case <label> <fbp override>
# <env assignment>... runs the sandbox and requires no such file.
leak_n=0
# leftovers_driver: the sandbox run in its own bash, so the lib's own resets
# (FBP_SANDBOX_FBP_OVERRIDE and the stub's seams are set empty when it is
# sourced) come first and this run's values after. $1 the FBP.sh to run (empty
# is the real one), then NAME=value seams.
leftovers_driver() {
  local override="$1"
  shift
  [ -z "$override" ] || FBP_SANDBOX_FBP_OVERRIDE="$override"
  local assignment
  for assignment in "$@"; do
    eval "$assignment"
  done
  fbp_sandbox_run 3 --no-commit "614: logs removed"
  exit 0
}
export -f leftovers_driver

# leftovers_case <label> <FBP.sh override or empty> [NAME=value seam...]: runs
# the sandbox with its own TMPDIR and requires no forsgren_sfl_* file in it.
leftovers_case() {
  local label="$1" override="$2" dir left
  shift 2
  leak_n=$((leak_n + 1))
  dir="${TMP}/leak${leak_n}"
  mkdir -p "$dir"
  if ! TMPDIR="$dir"  bash -c 'source "$1"; source "$2"; shift 2; leftovers_driver "$@"' \
      x "${ROOT}/Scripts/lib_git_sandbox.sh" "${ROOT}/Scripts/lib_fbp_sandbox.sh" \
      "$override" "$@" >"${dir}.out" 2>&1; then
    fail "${label}: the sandbox run itself failed. Output: $(cat "${dir}.out")"
    return 1
  fi
  left="$(find "$dir" -maxdepth 1 -name 'forsgren_sfl_*' -print)"
  if [ -n "$left" ]; then
    fail "${label}: the run left its log behind: ${left}"
    return 1
  fi
  echo "  ok: ${label}: no forsgren_sfl_* file is left"
}

exit7="${TMP}/mutants/FBP_summary_exit.sh"
selftest_mutant "$FBP_SANDBOX_FBP" "$exit7" 's|^  local pre_tail post_tail$|  local pre_tail post_tail; exit 7|'
leftovers_case "a green run" ""
leftovers_case "a red PRE" "" FBP_SANDBOX_SFL_PRE_RC=1
leftovers_case "a run ended by TERM" "" FBP_SANDBOX_SFL_PRE_SIGNAL=TERM
leftovers_case "a summary that ends the script early" "$exit7"

# Mutation: a FBP.sh that never removes its logs is caught, naming the file.
nolog="${TMP}/mutants/FBP_keeps_logs.sh"
# shellcheck disable=SC2016 # sed text, not shell
if selftest_mutant "$FBP_SANDBOX_FBP" "$nolog" 's|rm -f "\$PRE_LOG"|:|;s|rm -f "\$POST_LOG"|:|'; then
  (leftovers_case "mutation" "$nolog") >"${TMP}/mut.out" 2>&1 || true
  if grep -Fq 'the run left its log behind: '"${TMP}/leak"  "${TMP}/mut.out" \
     && grep -Fq 'forsgren_sfl_pre.' "${TMP}/mut.out"; then
    echo "  ok: mutation proof: a FBP.sh that never removes its logs is caught, naming the file"
  else
    fail "mutation proof: a FBP.sh that never removes its logs went unseen. Output: $(cat "${TMP}/mut.out")"
  fi
fi

selftest_end "FBP.sh prints All checks passed, or exits 0, on a run a signal ended" \
  "a run ended by TERM, INT or HUP prints Aborted ❌ with the signal, never All checks passed, and exits 143, 130 or 129"
