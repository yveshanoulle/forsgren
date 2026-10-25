#!/usr/bin/env bash
# canon: test_run_ci_phase v2
# Scripts/test_run_ci_phase.sh
#
# Self-test for Scripts/run_ci_phase.sh, the loop CI runs over the rows of
# Scripts/gate_report_order.txt. Extracted from the
# runtime part of forsgren's test_gate_wiring.sh and widened with the
# conditions the reviewer set for a loop that replaces named CI steps:
#
#   - an invalid gate (a malformed row), a missing script and a script that is
#     not executable FAIL CI. None of them is ever skipped silently;
#   - a gate that leaves the tree dirty is red, even when it exits 0;
#   - an empty phase is red;
#   - an n/a row is skipped and does not report;
#   - the phases filter, a secret-class failure exits 2, and the rest of the
#     phase still runs.
#
# Every case runs a COPY of the runner inside a throwaway git repository with
# stub gates, never the real gates. Each case is a function taking the runner
# to try and printing one line per problem (nothing means the runner behaved).
# The proofs at the end run the same cases against runners weakened HERE, by
# sed, and require each to be caught: a runner without the dirty-tree check, a
# runner that skips a missing script, a runner that ignores a malformed phase.
# A case that cannot fail on a broken runner proves nothing.
#
# Local: ./Scripts/test_run_ci_phase.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

RUNNER="Scripts/run_ci_phase.sh"
ORDER="Scripts/gate_report_order.txt"

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: run_ci_phase self-test aborted before completing all cases" >&2
    exit 1
  fi
}
trap finish EXIT

failed=0
fail() { echo "❌ FAIL: $*"; failed=1; }

[[ -f "$RUNNER" ]] || { echo "FAIL: ${RUNNER} not found" >&2; exit 1; }
[[ -x "$RUNNER" ]] || { echo "FAIL: ${RUNNER} is not executable" >&2; exit 1; }
[[ -f "$ORDER" ]] || { echo "FAIL: ${ORDER} not found" >&2; exit 1; }

# The runner's canon line must be in its first 40 lines.
head -40 "$RUNNER" | grep -qxF '# canon: run_ci_phase v1' \
  || fail "${RUNNER} has no '# canon: run_ci_phase v1' line in its first 40 lines"

REAL_RUNNER="$(pwd)/${RUNNER}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; finish' EXIT

# new_sandbox <runner>: a fresh git repository holding a copy of the runner and
# one committed, tracked file, so a gate that writes to it dirties the tree.
# Sets SB and TRACE.
new_sandbox() {
  # mktemp, not a counter: the cases run in command substitutions, whose
  # variable changes are lost, and a reused sandbox would carry the last case in.
  SB="$(mktemp -d "${TMP}/sandbox.XXXXXX")"
  mkdir -p "${SB}/Scripts"
  cp "$1" "${SB}/Scripts/run_ci_phase.sh"
  chmod +x "${SB}/Scripts/run_ci_phase.sh"
  git -C "$SB" init -q
  echo "tracked" > "${SB}/tracked.txt"
  git -C "$SB" add tracked.txt Scripts/run_ci_phase.sh
  git -C "$SB" -c user.name=t -c user.email=t@example.invalid \
    -c commit.gpgsign=false commit -q -m sandbox
  TRACE="${SB}.trace"
  : > "$TRACE"
}

# stub <path> <exit> [writes]: an executable stub gate. With `writes` it
# changes the tracked file before exiting.
stub() {
  local path="$1" code="$2" writes="${3:-}"
  mkdir -p "$(dirname "${SB}/${path}")"
  {
    cat <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${0#./}" >> "$STUB_TRACE"
STUB
    printf 'echo "stub output of %s"\n' "$path"
    [[ -z "$writes" ]] || printf 'echo changed >> tracked.txt\n'
    printf 'exit %s\n' "$code"
  } > "${SB}/${path}"
  chmod +x "${SB}/${path}"
}

# order <lines...>: the sandbox's order file, one argument per line, the last
# one without a trailing newline.
order() {
  local n=$# i=0 line
  : > "${SB}/Scripts/gate_report_order.txt"
  for line in "$@"; do
    i=$((i + 1))
    if [[ "$i" -eq "$n" ]]; then
      printf '%s' "$line" >> "${SB}/Scripts/gate_report_order.txt"
    else
      printf '%s\n' "$line" >> "${SB}/Scripts/gate_report_order.txt"
    fi
  done
}

# run_phase <phase> [shell...]: sets RUN_OUT, RUN_RC, RUN_ROWS, RUN_DETAILS.
# RUN_JOB, when set, is the runner's optional fourth argument, the job.
run_phase() {
  local phase="$1"
  shift
  RUN_ROWS="${SB}.${phase}.rows"
  RUN_DETAILS="${SB}.${phase}.details"
  rm -rf "$RUN_ROWS" "$RUN_DETAILS"
  RUN_RC=0
  RUN_OUT="$(STUB_TRACE="$TRACE" RUN_CI_PHASE_ROOT="$SB" \
    "$@" "${SB}/Scripts/run_ci_phase.sh" "$phase" "$RUN_ROWS" "$RUN_DETAILS" ${RUN_JOB:+"$RUN_JOB"} 2>&1)" || RUN_RC=$?
}

rows_text() { tr '\n' ' ' < "$RUN_ROWS" 2>/dev/null || true; }

# --- the cases: each prints one line per problem -----------------------------

# n/a rows are skipped, never run, never reported; comments and blanks too; a
# last line with no newline is still read; the loop survives `bash -e`.
case_na_skip() {
  new_sandbox "$1"
  order "# a comment" "" "first|Scripts/pass_a.sh|pre|" \
    "declared n/a|n/a|this repo has no such gate" "last, no newline|Scripts/pass_b.sh|pre|"
  stub Scripts/pass_a.sh 0
  stub Scripts/pass_b.sh 0
  run_phase pre bash --noprofile --norc -eo pipefail
  [[ "$RUN_RC" -eq 0 ]] || echo "exit ${RUN_RC}, want 0 when only n/a and passing rows exist: ${RUN_OUT}"
  [[ "$(cat "$TRACE")" == "$(printf 'Scripts/pass_a.sh\nScripts/pass_b.sh')" ]] \
    || echo "ran the wrong scripts: $(tr '\n' ' ' < "$TRACE")"
  grep -q 'declared n/a' "$RUN_ROWS" 2>/dev/null && echo "the n/a row was reported as a gate"
  grep -qxF 'last, no newline|✅' "$RUN_ROWS" 2>/dev/null || echo "the last line with no newline was not read: $(rows_text)"
  return 0
}

# A row runs only in its own phase; a failure does not stop the phase.
case_phase_filter() {
  new_sandbox "$1"
  order "first|Scripts/pass_a.sh|pre|" "fails|Scripts/fail.sh|pre|" \
    "later|Scripts/pass_b.sh|pre|" "post only|Scripts/pass_c.sh|post|"
  stub Scripts/pass_a.sh 0
  stub Scripts/fail.sh 3
  stub Scripts/pass_b.sh 0
  stub Scripts/pass_c.sh 0
  run_phase pre
  [[ "$RUN_RC" -eq 1 ]] || echo "pre exit ${RUN_RC}, want 1 with a failing row: ${RUN_OUT}"
  [[ "$(cat "$TRACE")" == "$(printf 'Scripts/pass_a.sh\nScripts/fail.sh\nScripts/pass_b.sh')" ]] \
    || echo "pre ran the wrong rows or stopped at the failure: $(tr '\n' ' ' < "$TRACE")"
  grep -qxF 'fails|❌' "$RUN_ROWS" 2>/dev/null || echo "the failing row is not reported red: $(rows_text)"
  grep -qF 'stub output of Scripts/fail.sh' "${RUN_DETAILS}/fails.md" 2>/dev/null \
    || echo "the failing gate's details do not carry its output"
  : > "$TRACE"
  run_phase post
  [[ "$RUN_RC" -eq 0 ]] || echo "post exit ${RUN_RC}, want 0: ${RUN_OUT}"
  [[ "$(cat "$TRACE")" == "Scripts/pass_c.sh" ]] || echo "post ran the wrong rows: $(tr '\n' ' ' < "$TRACE")"
  return 0
}

# A secret-class failure exits 2 and the rest of the phase still runs.
case_secret_class() {
  new_sandbox "$1"
  order "secret scan|Scripts/fail.sh|pre|secret-class" "after|Scripts/pass_a.sh|pre|"
  stub Scripts/fail.sh 1
  stub Scripts/pass_a.sh 0
  run_phase pre
  [[ "$RUN_RC" -eq 2 ]] || echo "exit ${RUN_RC}, want 2 for a secret-class failure: ${RUN_OUT}"
  grep -qF Scripts/pass_a.sh "$TRACE" || echo "the phase stopped after the secret-class row"
  return 0
}

# A gate that exits 0 but changes the tree is red, naming the file.
case_dirty_tree() {
  new_sandbox "$1"
  order "clean|Scripts/pass_a.sh|pre|" "writes the tree|Scripts/writes.sh|pre|" "after|Scripts/pass_b.sh|pre|"
  stub Scripts/pass_a.sh 0
  stub Scripts/writes.sh 0 writes
  stub Scripts/pass_b.sh 0
  run_phase pre
  [[ "$RUN_RC" -eq 1 ]] || echo "exit ${RUN_RC}, want 1 when a gate dirties the tree: ${RUN_OUT}"
  grep -qxF 'writes the tree|❌' "$RUN_ROWS" 2>/dev/null || echo "the dirtying gate is not red: $(rows_text)"
  grep -qF 'changed the checked-out tree' "${RUN_DETAILS}/writes_the_tree.md" 2>/dev/null \
    || echo "the details do not say the tree changed"
  grep -qF 'M tracked.txt' "${RUN_DETAILS}/writes_the_tree.md" 2>/dev/null \
    || echo "the details do not name the changed file"
  grep -qxF 'after|✅' "$RUN_ROWS" 2>/dev/null || echo "the row after the dirtying gate was blamed too: $(rows_text)"
  return 0
}

# A phase with no row is red, with the reason.
case_empty_phase() {
  new_sandbox "$1"
  order "post only|Scripts/pass_c.sh|post|"
  stub Scripts/pass_c.sh 0
  run_phase pre
  [[ "$RUN_RC" -eq 1 ]] || echo "exit ${RUN_RC}, want 1 for a phase with no row: ${RUN_OUT}"
  grep -qF 'declares no pre row' <<< "$RUN_OUT" || echo "no reason given for the empty phase: ${RUN_OUT}"
  return 0
}

# A declared script that does not exist is a red row, never skipped.
case_missing_script() {
  new_sandbox "$1"
  order "present|Scripts/pass_a.sh|pre|" "ghost|Scripts/ghost.sh|pre|"
  stub Scripts/pass_a.sh 0
  run_phase pre
  [[ "$RUN_RC" -eq 1 ]] || echo "exit ${RUN_RC}, want 1 for a missing script: ${RUN_OUT}"
  grep -qxF 'ghost|❌' "$RUN_ROWS" 2>/dev/null || echo "the missing script has no red row: $(rows_text)"
  grep -qF 'does not exist' "${RUN_DETAILS}/ghost.md" 2>/dev/null || echo "the details do not say the script does not exist"
  return 0
}

# A declared script that is not executable is a red row, never skipped.
case_non_executable() {
  new_sandbox "$1"
  order "present|Scripts/pass_a.sh|pre|" "noexec|Scripts/noexec.sh|pre|"
  stub Scripts/pass_a.sh 0
  printf '#!/usr/bin/env bash\nexit 0\n' > "${SB}/Scripts/noexec.sh"
  run_phase pre
  [[ "$RUN_RC" -eq 1 ]] || echo "exit ${RUN_RC}, want 1 for a non-executable script: ${RUN_OUT}"
  grep -qxF 'noexec|❌' "$RUN_ROWS" 2>/dev/null || echo "the non-executable script has no red row: $(rows_text)"
  grep -qF 'not an executable script' "${RUN_DETAILS}/noexec.md" 2>/dev/null || echo "the details do not say it is not executable"
  return 0
}

# bad_row <order-line> <label> <what>: a malformed row beside a good one must
# be red in either phase, named, and must not stop the good row.
bad_row() {
  local line="$1" label="$2" what="$3" phase slug
  slug="$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')"
  for phase in pre post; do
    new_sandbox "$RUNNER_UNDER_TEST"
    order "good|Scripts/pass_a.sh|${phase}|" "$line"
    stub Scripts/pass_a.sh 0
    stub Scripts/pass_b.sh 0
    run_phase "$phase"
    [[ "$RUN_RC" -eq 1 ]] || echo "${what}: ${phase} exit ${RUN_RC}, want 1: ${RUN_OUT}"
    grep -qxF "${label}|❌" "$RUN_ROWS" 2>/dev/null || echo "${what}: no red row '${label}' in ${phase}: $(rows_text)"
    grep -qF 'malformed row' "${RUN_DETAILS}/${slug}.md" 2>/dev/null || echo "${what}: the details do not say malformed"
    grep -qxF 'good|✅' "$RUN_ROWS" 2>/dev/null || echo "${what}: the good row did not run in ${phase}"
  done
  return 0
}

case_bad_row() {
  RUNNER_UNDER_TEST="$1"
  bad_row "typo|Scripts/pass_b.sh|prez|" "typo" "a phase typo"
  bad_row "no script||pre|" "no script" "an empty script field"
  bad_row "outside|tools/pass_b.sh|pre|" "outside" "a script outside Scripts/"
  bad_row "dotdot|Scripts/../pass_b.sh|pre|" "dotdot" "a path with .."
  bad_row "bad class|Scripts/pass_b.sh|pre|loud" "bad class" "an unknown class"
  bad_row "|Scripts/pass_b.sh|pre|" "(row with no label)" "a row with no label"
  return 0
}

# usage and a missing order file.
case_usage() {
  new_sandbox "$1"
  run_phase pre
  [[ "$RUN_RC" -eq 1 ]] && grep -qF 'is missing' <<< "$RUN_OUT" || echo "a missing order file exited ${RUN_RC}: ${RUN_OUT}"
  run_phase build
  [[ "$RUN_RC" -eq 64 ]] || echo "an unknown phase exited ${RUN_RC}, want 64"
  return 0
}

# groups <lines...>: the sandbox's job group file, one `<job>|<label>` per line.
groups() {
  printf '%s\n' "$@" > "${SB}/Scripts/ci_job_groups.txt"
}

# JOBS (forsgren#259, step 2): Quality runs the gates in parallel jobs. The
# optional fourth argument names the job; Scripts/ci_job_groups.txt says which
# job each listed gate belongs to, and every gate it does not list is the main
# job's. A gate runs in exactly one job.
case_job_groups() {
  RUN_JOB=""
  new_sandbox "$1"
  order "main one|Scripts/pass_a.sh|pre|" "iso one|Scripts/pass_b.sh|pre|" \
    "iso two|Scripts/pass_c.sh|pre|" "main two|Scripts/pass_d.sh|pre|" "iso post|Scripts/pass_e.sh|post|"
  stub Scripts/pass_a.sh 0
  stub Scripts/pass_b.sh 0
  stub Scripts/pass_c.sh 0
  stub Scripts/pass_d.sh 0
  stub Scripts/pass_e.sh 0
  groups "isolation|iso one" "isolation|iso two"
  run_phase pre
  [[ "$RUN_RC" -eq 0 ]] || echo "no job argument: exit ${RUN_RC}, want 0: ${RUN_OUT}"
  [[ "$(cat "$TRACE")" == "$(printf 'Scripts/pass_a.sh\nScripts/pass_d.sh')" ]] \
    || echo "no job argument must mean the main job, which skips the listed gates; it ran: $(tr '\n' ' ' < "$TRACE")"
  : > "$TRACE"
  RUN_JOB=main run_phase pre
  [[ "$(cat "$TRACE")" == "$(printf 'Scripts/pass_a.sh\nScripts/pass_d.sh')" ]] \
    || echo "job main ran the wrong gates: $(tr '\n' ' ' < "$TRACE")"
  : > "$TRACE"
  RUN_JOB=isolation run_phase pre
  [[ "$RUN_RC" -eq 0 ]] || echo "job isolation: exit ${RUN_RC}, want 0: ${RUN_OUT}"
  [[ "$(cat "$TRACE")" == "$(printf 'Scripts/pass_b.sh\nScripts/pass_c.sh')" ]] \
    || echo "job isolation must run only its listed gates; it ran: $(tr '\n' ' ' < "$TRACE")"
  [[ "$(cat "$RUN_ROWS" 2>/dev/null)" == "$(printf 'iso one|✅\niso two|✅')" ]] || echo "job isolation reported the wrong rows: $(rows_text)"
  groups "isolation|iso post"
  RUN_JOB=isolation run_phase pre
  [[ "$RUN_RC" -eq 1 ]] && grep -qF 'declares no pre row' <<< "$RUN_OUT" \
    || echo "a job with no gate in the phase must be red, exit ${RUN_RC}: ${RUN_OUT}"
  RUN_JOB=isolation run_phase post
  [[ "$RUN_RC" -eq 0 ]] || echo "job isolation, phase post: exit ${RUN_RC}, want 0 for the listed post row: ${RUN_OUT}"
  RUN_JOB=nope run_phase pre
  [[ "$RUN_RC" -eq 64 ]] || echo "a job the group file does not name exited ${RUN_RC}, want 64: ${RUN_OUT}"
  groups "isolation|ghost label"
  RUN_JOB=main run_phase pre
  [[ "$RUN_RC" -eq 1 ]] && grep -qF 'ghost label' <<< "$RUN_OUT" \
    || echo "a group file naming a gate the order file does not have must be red and name it, exit ${RUN_RC}: ${RUN_OUT}"
  rm -f "${SB}/Scripts/ci_job_groups.txt"
  RUN_JOB=isolation run_phase pre
  [[ "$RUN_RC" -ne 0 ]] || echo "job isolation with no group file exited 0: it ran nothing"
  RUN_JOB=""
  return 0
}

# The REAL order file, with a stub for every runnable row: both phases pass and
# between them run each row exactly once, in its own phase. A real row the
# runner would call malformed fails here.
case_real_order_file() {
  local script want got
  new_sandbox "$1"
  cp "$ORDER" "${SB}/Scripts/gate_report_order.txt"
  cp Scripts/ci_job_groups.txt "${SB}/Scripts/ci_job_groups.txt" 2>/dev/null || echo "Scripts/ci_job_groups.txt is missing: no gate is assigned to a job"
  while IFS='|' read -r _l script _p _c; do
    [[ -n "${script:-}" && "$script" != "n/a" ]] || continue
    stub "$script" 0
  done < <(grep -v '^#' "$ORDER" | grep .)
  run_phase pre
  [[ "$RUN_RC" -eq 0 ]] || echo "pre over the real order file exited ${RUN_RC}: ${RUN_OUT}"
  RUN_JOB=lint run_phase pre
  [[ "$RUN_RC" -eq 0 ]] || echo "pre of the lint job over the real order file exited ${RUN_RC}: ${RUN_OUT}"
  RUN_JOB=isolation run_phase pre
  [[ "$RUN_RC" -eq 0 ]] || echo "pre of the isolation job over the real order file exited ${RUN_RC}: ${RUN_OUT}"
  RUN_JOB=browser run_phase pre
  [[ "$RUN_RC" -eq 0 ]] || echo "pre of the browser job over the real order file exited ${RUN_RC}: ${RUN_OUT}"
  RUN_JOB=browser run_phase post
  [[ "$RUN_RC" -eq 0 ]] || echo "post of the browser job over the real order file exited ${RUN_RC}: ${RUN_OUT}"
  RUN_JOB=workflows run_phase pre
  [[ "$RUN_RC" -eq 0 ]] || echo "pre of the workflows job over the real order file exited ${RUN_RC}: ${RUN_OUT}"
  RUN_JOB=""
  run_phase post
  [[ "$RUN_RC" -eq 0 ]] || echo "post over the real order file exited ${RUN_RC}: ${RUN_OUT}"
  want="$(grep -v '^#' "$ORDER" | grep . | awk -F'|' '$2 != "n/a" { print $2 }' | LC_ALL=C sort)"
  got="$(LC_ALL=C sort "$TRACE")"
  [[ "$got" == "$want" ]] || echo "the jobs and phases did not run every runnable row exactly once"
  return 0
}

CASES=(na_skip phase_filter secret_class dirty_tree empty_phase missing_script non_executable bad_row usage job_groups real_order_file)

# --- 1. the real runner passes every case ------------------------------------
for c in "${CASES[@]}"; do
  problems="$("case_${c}" "$REAL_RUNNER")"
  if [[ -n "$problems" ]]; then
    fail "case ${c} on ${RUNNER}:"
    while IFS= read -r line; do printf '      %s\n' "$line"; done <<< "$problems"
  else
    echo "  ok: ${c}"
  fi
done

# --- 2. mutations: a weakened runner must fail the matching case -------------
MUTANT_N=0
mutation_proof() {
  local label="$1" sed_expr="$2" case_name="$3" mutated problems
  MUTANT_N=$((MUTANT_N + 1))
  mutated="${TMP}/mutant_${MUTANT_N}.sh"
  sed -E "$sed_expr" "$REAL_RUNNER" > "$mutated"
  chmod +x "$mutated"
  if cmp -s "$REAL_RUNNER" "$mutated"; then
    fail "mutation ${label}: the sed changed nothing, so it proves nothing"
    return 0
  fi
  problems="$("case_${case_name}" "$mutated")"
  if [[ -z "$problems" ]]; then
    fail "mutation ${label}: PASSED case ${case_name}, so that case cannot catch it"
  else
    echo "  ok: mutation ${label} is caught by ${case_name}"
  fi
}

# No dirty-tree check: the comparison can never be true.
mutation_proof "a runner without the dirty-tree check" \
  $'s/^    elif \[ "\$tree_after" != "\$tree_before" \]; then$/    elif false; then/' dirty_tree

# A missing script is skipped instead of reported.
mutation_proof "a runner that skips a missing script" \
  $'s/^  elif \[ ! -e "\$script" \]; then$/  elif [ ! -e "$script" ]; then continue/' missing_script

# A phase typo is no longer malformed, so the row drops out of both phases.
mutation_proof "a runner that ignores a malformed phase" \
  $'s/^      pre\|post\) ;;$/      pre|post|*) ;;/' bad_row

# A non-executable script is run anyway (the -x test is gone).
mutation_proof "a runner that does not test executability" \
  $'s/^  elif \[ ! -x "\$script" \]; then$/  elif false; then/' non_executable

# An empty phase passes.
mutation_proof "a runner that accepts an empty phase" \
  $'s/^if \[ "\$ran" -eq 0 \]; then$/if false; then/' empty_phase

# The main job runs a gate the group file gives to another job: it runs twice.
mutation_proof "a runner whose main job runs the gates of other jobs" \
  $'s/^    \\[ "\\$\\(gate_job "\\$label"\\)" = "\\$JOB" \\] \\|\\| continue$/    true/' job_groups

# A job runs the gates of main, not its own.
mutation_proof "a runner whose jobs ignore their group" \
  $'s/^JOB="\\$\\{4:-main\\}"$/JOB="main"/' job_groups

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: run_ci_phase self-test"
  exit 1
fi

echo "OK: run_ci_phase.sh skips n/a rows, filters phases, exits 2 on a secret-class failure, and is red on a dirty tree, an empty phase, a missing or non-executable script and a malformed row, and runs each gate in exactly one job (each proved against a weakened runner)"
