#!/usr/bin/env bash
# Scripts/test_step_summary_isolation.sh
#
# sfl skips this gate when a commit touches none of the files Scripts/gate_inputs.txt
# lists for it (forsgren#264); Quality runs it always.
#
# forsgren's own (forsgren#233). In CI the runner exports GITHUB_STEP_SUMMARY,
# and the Quality run runs the self-tests inside a gate step. A self-test that
# runs a script which appends to $GITHUB_STEP_SUMMARY (the release report, the
# token expiry check, the baselines report) then wrote its
# fixture output to the REAL run page, ahead of the run's headline. Every
# self-test must run those scripts under a summary file it owns:
# Scripts/lib_selftest.sh points GITHUB_STEP_SUMMARY at a file in the
# self-test's temp root, the way Scripts/lib_git_sandbox.sh isolates GIT_DIR.
#
# This test mirrors Scripts/test_git_sandbox_isolation.sh: it runs each
# self-test that names a script appending to the step summary with
# GITHUB_STEP_SUMMARY exported, in the child only, pointing at a DECOY file,
# and the decoy must stay empty. Cases:
#   1. a script of Scripts/ appends to GITHUB_STEP_SUMMARY, so the list of
#      self-tests below is not empty
#   2. every self-test that names such a script (or one of the two renderers)
#      leaves the decoy empty; the finding names the self-test
#   3. mutation proofs: a self-test that sources the harness and writes to
#      GITHUB_STEP_SUMMARY leaves the decoy empty; one that does not source
#      it leaves bytes in the decoy and is named

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_summary_writers.sh
source Scripts/lib_summary_writers.sh
selftest_begin "step summary isolation"

SELF="test_step_summary_isolation.sh"

# The scripts that write the step summary and the self-tests that name them are
# found by Scripts/lib_summary_writers.sh (forsgren#264), which
# Scripts/test_gate_inputs.sh uses too, to hold Scripts/gate_inputs.txt to list
# everything this gate runs.
writer_names() { summary_writer_names; }
self_tests() { summary_selftests "$SELF" "$@"; }

# leak <script>: run it with GITHUB_STEP_SUMMARY on a decoy, in the child
# only; print the number of bytes that reached the decoy.
leak() {
  local decoy="${TMP}/decoy.$$.$RANDOM"
  : > "$decoy"
  GITHUB_STEP_SUMMARY="$decoy" bash "$1" > /dev/null 2>&1
  wc -c < "$decoy" | tr -d ' '
}

mapfile_names() {
  local line
  NAMES=()
  while IFS= read -r line; do NAMES+=("$line"); done < <(writer_names)
}
mapfile_names
if [[ "${#NAMES[@]}" -eq 0 ]]; then
  selftest_abort "no script of Scripts/ appends to GITHUB_STEP_SUMMARY: the isolation would be proven against nothing"
fi

TESTS=()
while IFS= read -r line; do TESTS+=("$line"); done < <(self_tests "${NAMES[@]}" render_quality_summary.sh render_quality_report.sh)
if [[ "${#TESTS[@]}" -eq 0 ]]; then
  selftest_abort "no self-test names a script that writes the step summary: the list is empty"
fi

for t in "${TESTS[@]}"; do
  bytes="$(leak "$t")"
  if [[ "$bytes" == "0" ]]; then
    echo "  ok: ${t} leaves the ambient step summary alone"
  else
    fail "${t} wrote ${bytes} bytes to the ambient GITHUB_STEP_SUMMARY: on the Quality run that is the real run page, ahead of the headline"
  fi
done

# Mutation proofs, with throwaway self-tests that write to the summary.
mkdir -p "${TMP}/proof"
cat > "${TMP}/proof/isolated.sh" <<'PROOF'
#!/usr/bin/env bash
set -uo pipefail
cd "$ROOT" || exit 1
source Scripts/lib_selftest.sh
selftest_begin "proof"
echo "fixture output" >> "$GITHUB_STEP_SUMMARY"
COMPLETED=1
PROOF
cat > "${TMP}/proof/ambient.sh" <<'PROOF'
#!/usr/bin/env bash
set -uo pipefail
echo "fixture output" >> "$GITHUB_STEP_SUMMARY"
PROOF
ROOT="$(pwd)"
export ROOT
if [[ "$(leak "${TMP}/proof/isolated.sh")" == "0" ]]; then
  echo "  ok: mutation proof: a self-test on the harness leaves the ambient summary alone"
else
  fail "mutation proof: a self-test that sources Scripts/lib_selftest.sh still wrote the ambient summary"
fi
if [[ "$(leak "${TMP}/proof/ambient.sh")" != "0" ]]; then
  echo "  ok: mutation proof: a self-test that writes the ambient summary is named by its bytes"
else
  fail "mutation proof: a self-test writing the ambient summary left the decoy empty: the leak check sees nothing"
fi

selftest_end "a self-test wrote the ambient GITHUB_STEP_SUMMARY" "step summary isolation (no self-test that runs a summary writer touches the ambient page)"
