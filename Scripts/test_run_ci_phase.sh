#!/usr/bin/env bash
# canon: test_run_ci_phase v9
# v9 (forsgren#646, decision #647 A; canon home forsgren): the test of run_ci_phase v8, one for every site. It keeps every case of forsgren's v5 and of the sites' v8 and adds: group row arguments split by read -r -a within a safe character set (unsafe ones red, never expanded, no eval), the default job, post rows in a named job, the group file checks, the build-volume TMPDIR only where Scripts/builds_tmpdir.sh exists (the real script, with the fake Companion, only there), the checked temp file, gate selection only where its library exists, and workflow_paths per gate job read from the workflow (any site's layout).
# v3 (forsgren#426): the shards case (group rows with arguments) and two mutations; the jobs of the real-order case come from the group file.
# v4 (forsgren#574): the report_dir, cancel and workflow_paths cases and two mutations.
# v5 (forsgren#641): workflow_paths reads the number of gate jobs from quality.yml (every job but report and preview) instead of a fixed 9, and two workflow mutations prove it.
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
#     phase still runs;
#   - forsgren#574: the rows and details folder is unique per run, attempt and
#     job (`report-dir`), and the cancel signal stops the gate loop with its
#     gates and writes nothing more.
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
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh

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
head -40 "$RUNNER" | has -xF '# canon: run_ci_phase v8' \
  || fail "${RUNNER} has no '# canon: run_ci_phase v8' line in its first 40 lines"

REAL_RUNNER="$(pwd)/${RUNNER}"
# shellcheck source=Scripts/lib_tmp.sh
source Scripts/lib_tmp.sh
TMP="$(tmp_dir test_run_ci_phase)" || exit 1
trap 'rm -rf "$TMP"; finish' EXIT
# The runner appends to the step summary; on a Quality run the ambient one is
# the real run page, so every case writes to this one unless it names its own.
GITHUB_STEP_SUMMARY="${TMP}/ambient_step_summary.md"
: > "$GITHUB_STEP_SUMMARY"
export GITHUB_STEP_SUMMARY
# Where the repository has a build volume script (a self-hosted site), the
# real one is tried too, and it pushes the volume's status to the Stream
# Deck: then, and only then, the fake Companion of Scripts/lib_fake_companion.sh
# stands in for the real one. A repository without the script has no such
# library either.
BUILDS_TMPDIR_SCRIPT=""
if [[ -f Scripts/builds_tmpdir.sh ]]; then
  BUILDS_TMPDIR_SCRIPT="$(pwd)/Scripts/builds_tmpdir.sh"
  # The sandboxes are not all git repositories, so builds_tmpdir.sh gets its
  # folder through its seam.
  export BUILDS_REPO_FOLDER="fixture-repo"
  # shellcheck source=/dev/null # present only in a repository that has Scripts/builds_tmpdir.sh
  source Scripts/lib_fake_companion.sh
  fake_companion "${TMP}/fake-companion"
fi

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
  cp Scripts/lib_tmp.sh "${SB}/Scripts/lib_tmp.sh"
  git -C "$SB" init -q
  echo "tracked" > "${SB}/tracked.txt"
  git -C "$SB" add tracked.txt Scripts/run_ci_phase.sh Scripts/lib_tmp.sh
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
printf '%s|%s\n' "${0#./}" "$*" >> "${STUB_TRACE}.args"
{ printf '%s|' "${0#./}"; [ "$#" -eq 0 ] || printf '[%s]' "$@"; printf '\n'; } >> "${STUB_TRACE}.argv"
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

rows_text() { tr '\n' ' ' 2>/dev/null < "$RUN_ROWS" || true; }

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

# groups <lines...>: the sandbox's job group file, one `<job>|<label>[|<args>]` per line.
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

# SHARDS (forsgren#426). A group row may carry a third field, the arguments the
# job runs the gate with: `<job>|<label>|<args>`. Two jobs may then name the
# same label, each with its own arguments (--shard 1/2, --shard 2/2): the main
# job skips the gate, each job runs it with its arguments, and the row it
# records names the shard, `<label> (shard 1/2)`, so a red names its shard.
case_shards() {
  RUN_JOB=""
  new_sandbox "$1"
  order "main one|Scripts/pass_a.sh|pre|" "split one|Scripts/pass_b.sh|pre|" "split post|Scripts/pass_c.sh|post|"
  stub Scripts/pass_a.sh 0
  stub Scripts/pass_b.sh 0
  stub Scripts/pass_c.sh 0
  groups "part_1|split one|--shard 1/2" "part_2|split one|--shard 2/2" "other|split post"
  run_phase pre
  [[ "$RUN_RC" -eq 0 ]] || echo "the main job over a split gate: exit ${RUN_RC}, want 0: ${RUN_OUT}"
  [[ "$(cat "$TRACE")" == "Scripts/pass_a.sh" ]] || echo "the main job must skip a gate the group file splits; it ran: $(tr '\n' ' ' < "$TRACE")"
  : > "$TRACE"
  rm -f "${TRACE}.args"
  RUN_JOB=part_1 run_phase pre
  [[ "$RUN_RC" -eq 0 ]] || echo "job part_1: exit ${RUN_RC}, want 0: ${RUN_OUT}"
  [[ "$(cat "$TRACE")" == "Scripts/pass_b.sh" ]] || echo "job part_1 must run the split gate once; it ran: $(tr '\n' ' ' < "$TRACE")"
  [[ "$(cat "${TRACE}.args" 2>/dev/null)" == "Scripts/pass_b.sh|--shard 1/2" ]] \
    || echo "job part_1 must run the gate with its arguments as two words; the stub was called: $(tr '\n' ' ' < "${TRACE}.args" 2>/dev/null)"
  [[ "$(cat "$RUN_ROWS" 2>/dev/null)" == "split one (shard 1/2)|✅" ]] || echo "job part_1 must record a row that names its shard; it recorded: $(rows_text)"
  [[ -f "${RUN_DETAILS}/split_one__shard_1_2_.md" ]] || echo "job part_1 must write the details under the shard row's slug; it wrote: $(find "$RUN_DETAILS" -type f | tr "\n" " ")"
  rm -f "${TRACE}.args"
  RUN_JOB=part_2 run_phase pre
  [[ "$(cat "${TRACE}.args" 2>/dev/null)" == "Scripts/pass_b.sh|--shard 2/2" ]] \
    || echo "job part_2 must run the gate with its own arguments; the stub was called: $(tr '\n' ' ' < "${TRACE}.args" 2>/dev/null)"
  [[ "$(cat "$RUN_ROWS" 2>/dev/null)" == "split one (shard 2/2)|✅" ]] || echo "job part_2 must record its shard row; it recorded: $(rows_text)"
  RUN_JOB=other run_phase post
  [[ "$(cat "$RUN_ROWS" 2>/dev/null)" == "split post|✅" ]] || echo "a group row without arguments keeps the plain label; it recorded: $(rows_text)"
  stub Scripts/pass_b.sh 1
  RUN_JOB=part_2 run_phase pre
  [[ "$RUN_RC" -eq 1 ]] && grep -qF 'split one (shard 2/2) failed' <<< "$RUN_OUT" \
    || echo "a red shard must name its shard in the error line, exit ${RUN_RC}: ${RUN_OUT}"
  [[ "$(cat "$RUN_ROWS" 2>/dev/null)" == "split one (shard 2/2)|❌" ]] || echo "a red shard must record a red row naming its shard; it recorded: $(rows_text)"
  RUN_JOB=""
  return 0
}

# forsgren#646 (decision #644 A, gap (a) of #647): group row arguments in the
# canon. The third field is split into words by `read -r -a`, never by eval or
# an unquoted expansion, and may hold only letters, digits, _ . / = - and
# spaces. A row without a third field, or with an empty one, is the plain
# `<job>|<label>` row. Arguments with any other character are a red row named
# by the label, the gate not run, and the job's other gates still run.
case_group_args() {
  local bad label
  RUN_JOB=""
  new_sandbox "$1"
  order "plain|Scripts/pass_a.sh|pre|" "trailing bar|Scripts/pass_b.sh|pre|" \
    "split|Scripts/pass_c.sh|pre|" "spaced|Scripts/pass_d.sh|pre|" "words|Scripts/pass_e.sh|pre|"
  stub Scripts/pass_a.sh 0
  stub Scripts/pass_b.sh 0
  stub Scripts/pass_c.sh 0
  stub Scripts/pass_d.sh 0
  stub Scripts/pass_e.sh 0
  groups "j|plain" "j|trailing bar|" "j|split|--shard 1/2" "j|spaced|  --shard   2/2  " "j|words|--mode=fast ./x_y.txt"
  rm -f "${TRACE}.argv"
  RUN_JOB=j run_phase pre
  [[ "$RUN_RC" -eq 0 ]] || echo "job j with safe arguments: exit ${RUN_RC}, want 0: ${RUN_OUT}"
  # .argv brackets each word, so one word "--shard 1/2" and two words differ.
  [[ "$(cat "${TRACE}.argv" 2>/dev/null)" == "$(printf '%s\n' 'Scripts/pass_a.sh|' 'Scripts/pass_b.sh|' \
    'Scripts/pass_c.sh|[--shard][1/2]' 'Scripts/pass_d.sh|[--shard][2/2]' 'Scripts/pass_e.sh|[--mode=fast][./x_y.txt]')" ]] \
    || echo "the gates were not called with the row's words (none for a row without or with an empty third field): $(tr '\n' ' ' < "${TRACE}.argv" 2>/dev/null)"
  [[ "$(cat "$RUN_ROWS" 2>/dev/null)" == "$(printf '%s\n' 'plain|✅' 'trailing bar|✅' 'split (shard 1/2)|✅' \
    'spaced (shard 2/2)|✅' 'words (mode=fast ./x_y.txt)|✅')" ]] \
    || echo "the rows do not name the arguments (or a row without them is no longer plain): $(rows_text)"
  # Unsafe arguments: each is a red row named by its label, never run, and
  # nothing in it is expanded or executed.
  new_sandbox "$1"
  order "good|Scripts/pass_a.sh|pre|" "subst|Scripts/pass_b.sh|pre|" "semicolon|Scripts/pass_b.sh|pre|" \
    "glob|Scripts/pass_b.sh|pre|" "quotes|Scripts/pass_b.sh|pre|" "pipe|Scripts/pass_b.sh|pre|" \
    "backtick|Scripts/pass_b.sh|pre|" "dollar|Scripts/pass_b.sh|pre|" "after|Scripts/pass_c.sh|pre|"
  stub Scripts/pass_a.sh 0
  stub Scripts/pass_b.sh 0
  stub Scripts/pass_c.sh 0
  # shellcheck disable=SC2016 # the arguments are data the runner must refuse, never expanded here
  groups "bad|good" 'bad|subst|$(touch PWNED)' "bad|semicolon|--a;touch PWNED" "bad|glob|*" \
    'bad|quotes|--name "a b"' "bad|pipe|--x|--y" 'bad|backtick|`touch PWNED`' 'bad|dollar|--home=$HOME' "bad|after"
  RUN_JOB=bad run_phase pre
  [[ "$RUN_RC" -eq 1 ]] || echo "unsafe arguments: exit ${RUN_RC}, want 1: ${RUN_OUT}"
  [[ ! -e "${SB}/PWNED" ]] || echo "an argument was executed: ${SB}/PWNED exists"
  has -F Scripts/pass_b.sh < "$TRACE" && echo "a gate with unsafe arguments was run: $(tr '\n' ' ' < "${TRACE}.args" 2>/dev/null)"
  for bad in subst semicolon glob quotes pipe backtick dollar; do
    grep -qxF "${bad}|❌" "$RUN_ROWS" 2>/dev/null || echo "unsafe arguments of '${bad}' have no red row under the plain label: $(rows_text)"
    label="$(printf '%s' "$bad" | tr -c 'A-Za-z0-9' '_')"
    grep -qF 'arguments' "${RUN_DETAILS}/${label}.md" 2>/dev/null || echo "the details of '${bad}' do not say its arguments are refused"
  done
  grep -qxF 'good|✅' "$RUN_ROWS" 2>/dev/null && grep -qxF 'after|✅' "$RUN_ROWS" 2>/dev/null \
    || echo "a refused row stopped the job's other gates: $(rows_text)"
  # No eval anywhere in the runner's code (comments aside).
  grep -nE '^[^#]*(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)' "${SB}/Scripts/run_ci_phase.sh" \
    | sed 's/^/the runner uses eval: /' || true
  RUN_JOB=""
  return 0
}

# Gap (b) of #647: with no job argument the runner runs, in either phase, the
# rows the group file gives to no job, so a gate is in exactly one job; with no
# group file it runs every row. A site that lists every pre row (the v7
# layout) and calls post with no job runs every post row, as before. A job the
# group file does not name, or a job name with a character other than letters,
# digits, _ and -, is a usage error (64).
case_default_job() {
  RUN_JOB=""
  new_sandbox "$1"
  order "listed pre|Scripts/pass_a.sh|pre|" "unlisted pre|Scripts/pass_b.sh|pre|" \
    "unlisted post|Scripts/pass_c.sh|post|" "listed post|Scripts/pass_d.sh|post|"
  stub Scripts/pass_a.sh 0
  stub Scripts/pass_b.sh 0
  stub Scripts/pass_c.sh 0
  stub Scripts/pass_d.sh 0
  run_phase pre
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "$(printf 'Scripts/pass_a.sh\nScripts/pass_b.sh')" ]] \
    || echo "no group file, no job: pre must run every pre row, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE")"
  groups "x|listed pre" "y|listed post"
  : > "$TRACE"
  run_phase pre
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "Scripts/pass_b.sh" ]] \
    || echo "no job: pre must run only the rows no job lists, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE")"
  : > "$TRACE"
  run_phase post
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "Scripts/pass_c.sh" ]] \
    || echo "no job: post must run only the rows no job lists, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE")"
  groups "x|listed pre" "x|unlisted pre"
  : > "$TRACE"
  run_phase post
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "$(printf 'Scripts/pass_c.sh\nScripts/pass_d.sh')" ]] \
    || echo "every pre row listed (the v7 layout): post with no job must run every post row, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE")"
  RUN_JOB=nope run_phase pre
  [[ "$RUN_RC" -eq 64 ]] || echo "a job the group file does not name exited ${RUN_RC}, want 64: ${RUN_OUT}"
  groups "x|listed pre" "a/b|unlisted pre"
  RUN_JOB=a/b run_phase pre
  [[ "$RUN_RC" -eq 64 ]] || echo "a job name with a / exited ${RUN_RC}, want 64: ${RUN_OUT}"
  RUN_JOB=""
  return 0
}

# Gap (c) of #647: a named job may hold post rows (a job that builds its own
# site and runs its post gates). It runs its listed rows of the phase it is
# called with; with no job the post phase skips them; a job with no row of the
# phase is the empty phase, red.
case_post_job() {
  RUN_JOB=""
  new_sandbox "$1"
  order "own pre|Scripts/pass_a.sh|pre|" "main pre|Scripts/pass_b.sh|pre|" \
    "own post|Scripts/pass_c.sh|post|" "main post|Scripts/pass_d.sh|post|" "only post|Scripts/pass_e.sh|post|"
  stub Scripts/pass_a.sh 0
  stub Scripts/pass_b.sh 0
  stub Scripts/pass_c.sh 0
  stub Scripts/pass_d.sh 0
  stub Scripts/pass_e.sh 0
  groups "site|own pre" "site|own post" "postonly|only post"
  RUN_JOB=site run_phase pre
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "Scripts/pass_a.sh" ]] \
    || echo "job site, pre: must run its pre row, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE"): ${RUN_OUT}"
  : > "$TRACE"
  RUN_JOB=site run_phase post
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "Scripts/pass_c.sh" ]] \
    || echo "job site, post: must run its post row, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE"): ${RUN_OUT}"
  [[ "$(cat "$RUN_ROWS" 2>/dev/null)" == "own post|✅" ]] || echo "job site, post: wrong rows: $(rows_text)"
  : > "$TRACE"
  RUN_JOB="" run_phase post
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "Scripts/pass_d.sh" ]] \
    || echo "no job, post: must skip the post rows of named jobs, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE")"
  RUN_JOB=postonly run_phase pre
  [[ "$RUN_RC" -eq 1 ]] && grep -qF 'declares no pre row' <<< "$RUN_OUT" \
    || echo "a job with post rows only, called for pre, must be the red empty phase, exit ${RUN_RC}: ${RUN_OUT}"
  RUN_JOB=""
  return 0
}

# Gap (d) of #647: the build-volume temp folder only where the repository has
# Scripts/builds_tmpdir.sh. Without it the gates keep the TMPDIR they were
# given and nothing is said about a build volume. With it the runner exports
# the folder it prints, repeats its ⚠️ line, names the folder in the step
# summary, and a failing or silent script stops the phase before any gate. A
# builds_tmpdir.sh that is there but not executable is red, never skipped.
case_builds_tmpdir() {
  local given seen summary
  RUN_JOB=""
  new_sandbox "$1"
  order "tmp probe|Scripts/tmp_probe.sh|pre|"
  cat > "${SB}/Scripts/tmp_probe.sh" <<'PROBE'
#!/usr/bin/env bash
printf '%s\n' "${TMPDIR:-unset}" > "${STUB_TRACE}.tmpdir"
exit 0
PROBE
  chmod +x "${SB}/Scripts/tmp_probe.sh"
  given="${SB}.given_tmp"
  mkdir -p "$given"
  run_phase pre env TMPDIR="$given"
  seen="$(cat "${TRACE}.tmpdir" 2>/dev/null || true)"
  [[ "$RUN_RC" -eq 0 ]] || echo "no builds_tmpdir.sh: exit ${RUN_RC}, want 0: ${RUN_OUT}"
  [[ "$seen" == "$given" ]] || echo "no builds_tmpdir.sh: the gate must keep the given TMPDIR ${given}, it saw ${seen:-nothing}"
  grep -qF 'builds_tmpdir' <<< "$RUN_OUT" && echo "no builds_tmpdir.sh: the runner still talks about it: ${RUN_OUT}"
  # With the script: its folder is exported, its ⚠️ line repeated, the folder
  # named in the step summary.
  mkdir -p "${SB}.volume_tmp"
  printf '#!/usr/bin/env bash\necho "⚠️ fake volume note" >&2\nprintf "%%s\\n" "%s"\n' "${SB}.volume_tmp" > "${SB}/Scripts/builds_tmpdir.sh"
  chmod +x "${SB}/Scripts/builds_tmpdir.sh"
  summary="${SB}.summary.md"
  : > "$summary"
  rm -f "${TRACE}.tmpdir"
  run_phase pre env TMPDIR="$given" GITHUB_STEP_SUMMARY="$summary"
  seen="$(cat "${TRACE}.tmpdir" 2>/dev/null || true)"
  [[ "$RUN_RC" -eq 0 ]] || echo "builds_tmpdir.sh present: exit ${RUN_RC}, want 0: ${RUN_OUT}"
  [[ "$seen" == "${SB}.volume_tmp" ]] || echo "builds_tmpdir.sh present: the gate must see its folder ${SB}.volume_tmp, it saw ${seen:-nothing}"
  grep -qF '⚠️ fake volume note' <<< "$RUN_OUT" || echo "builds_tmpdir.sh present: its ⚠️ line is not repeated: ${RUN_OUT}"
  grep -qF "${SB}.volume_tmp" "$summary" || echo "builds_tmpdir.sh present: the step summary does not name the temp folder: $(cat "$summary")"
  # A failing script, and one that names no folder, stop the phase.
  for body in 'exit 1' 'exit 0'; do
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "${SB}/Scripts/builds_tmpdir.sh"
    rm -f "${TRACE}.tmpdir"
    run_phase pre
    [[ "$RUN_RC" -eq 1 ]] || echo "builds_tmpdir.sh '${body}' with no folder: exit ${RUN_RC}, want 1: ${RUN_OUT}"
    [[ ! -e "${TRACE}.tmpdir" ]] || echo "builds_tmpdir.sh '${body}' with no folder: a gate ran anyway"
    grep -qF 'no gate ran' <<< "$RUN_OUT" || echo "builds_tmpdir.sh '${body}' with no folder: the runner does not say no gate ran: ${RUN_OUT}"
  done
  # There but not executable: red, never taken for absent.
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "${SB}.volume_tmp" > "${SB}/Scripts/builds_tmpdir.sh"
  chmod -x "${SB}/Scripts/builds_tmpdir.sh"
  rm -f "${TRACE}.tmpdir"
  run_phase pre
  [[ "$RUN_RC" -eq 1 && ! -e "${TRACE}.tmpdir" ]] \
    || echo "a builds_tmpdir.sh that is not executable must stop the phase, exit ${RUN_RC}: ${RUN_OUT}"
  return 0
}

# Gap (e) of #647: the capture file is a checked tmp_file. When no temp file
# can be made (TMPDIR names a folder that does not exist) the runner stops
# with a ❌ line naming the temp folder, runs no gate and records no green row.
case_tmp_failure() {
  RUN_JOB=""
  new_sandbox "$1"
  order "first|Scripts/pass_a.sh|pre|"
  stub Scripts/pass_a.sh 0
  run_phase pre env TMPDIR="${SB}.no_such_folder"
  [[ "$RUN_RC" -ne 0 ]] || echo "no temp file possible: exit 0, want a failure: ${RUN_OUT}"
  grep -qF '❌' <<< "$RUN_OUT" && grep -qF "${SB}.no_such_folder" <<< "$RUN_OUT" \
    || echo "no temp file possible: no ❌ line naming the temp folder: ${RUN_OUT}"
  grep -qF 'cannot make a temp file' <<< "$RUN_OUT" || echo "no temp file possible: the failure is not named as the temp file: ${RUN_OUT}"
  [[ ! -s "$TRACE" ]] || echo "no temp file possible: a gate ran: $(tr '\n' ' ' < "$TRACE")"
  [[ ! -s "$RUN_ROWS" ]] || echo "no temp file possible: a row was recorded: $(rows_text)"
  return 0
}

# The group file is checked before any gate, in every job: the same
# `<job>|<label>` twice, a row for the job main (the default job is not
# listed) and a job name with a character other than letters, digits, _ and -
# are each red and named. A malformed order row is red in a named job too.
case_group_file() {
  RUN_JOB=""
  new_sandbox "$1"
  order "alpha|Scripts/pass_a.sh|pre|" "beta|Scripts/pass_b.sh|pre|"
  stub Scripts/pass_a.sh 0
  stub Scripts/pass_b.sh 0
  groups "x|alpha" "x|alpha"
  RUN_JOB=x run_phase pre
  [[ "$RUN_RC" -eq 1 ]] && grep -qF 'x|alpha' <<< "$RUN_OUT" \
    || echo "the same job and gate twice must be red and named, exit ${RUN_RC}: ${RUN_OUT}"
  [[ ! -s "$TRACE" ]] || echo "a gate ran over a group file with a row twice: $(tr '\n' ' ' < "$TRACE")"
  groups "x|alpha" "main|beta"
  RUN_JOB="" run_phase pre
  [[ "$RUN_RC" -eq 1 ]] && grep -qF 'job main' <<< "$RUN_OUT" \
    || echo "a group row for the job main must be red and named, exit ${RUN_RC}: ${RUN_OUT}"
  groups "x|alpha" "y.z|beta"
  RUN_JOB=x run_phase pre
  [[ "$RUN_RC" -eq 1 ]] && grep -qF "'y.z'" <<< "$RUN_OUT" \
    || echo "a group row whose job name holds a . must be red and named, exit ${RUN_RC}: ${RUN_OUT}"
  groups "x|alpha"
  order "alpha|Scripts/pass_a.sh|pre|" "typo|Scripts/pass_b.sh|prez|"
  RUN_JOB=x run_phase pre
  grep -qxF 'typo|❌' "$RUN_ROWS" 2>/dev/null || echo "a malformed row is not red in the named job x: $(rows_text)"
  RUN_JOB=""
  return 0
}

# Gate selection, where Scripts/lib_ci_gate_select.sh exists. Without it every
# gate runs, never a skipped one, and the runner says nothing unless the
# workflow asks for selection (CI_GATE_EVENT set) or the library is there but
# cannot be read. With it a gate the selector skips is a ⏭ row, counted as not
# run, never as passed.
case_gate_selection() {
  local summary="${TMP}/selection_summary_$$.md" lib
  RUN_JOB=""
  new_sandbox "$1"
  order "alpha|Scripts/pass_a.sh|pre|" "beta|Scripts/pass_b.sh|pre|"
  stub Scripts/pass_a.sh 0
  stub Scripts/pass_b.sh 0
  : > "$summary"
  run_phase pre env -u CI_GATE_EVENT -u CI_GATE_BASE GITHUB_STEP_SUMMARY="$summary"
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "$(printf 'Scripts/pass_a.sh\nScripts/pass_b.sh')" ]] \
    || echo "no selector: every gate must run, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE")"
  grep -qF 'Gate selection' <<< "$RUN_OUT" && echo "no selector and none asked for: the runner still names gate selection: ${RUN_OUT}"
  [[ ! -s "$summary" ]] || echo "no selector and none asked for: the step summary got: $(cat "$summary")"
  : > "$TRACE"
  run_phase pre env CI_GATE_EVENT=push CI_GATE_BASE=0 GITHUB_STEP_SUMMARY="$summary"
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "$(printf 'Scripts/pass_a.sh\nScripts/pass_b.sh')" ]] \
    || echo "a workflow that asks for selection without the library: every gate must run, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE")"
  grep -qF 'cannot be read, so every gate runs' <<< "$RUN_OUT" \
    || echo "a workflow that asks for selection without the library: the full run is not named: ${RUN_OUT}"
  # A stub library: beta is skipped.
  lib="${SB}/Scripts/lib_ci_gate_select.sh"
  cat > "$lib" <<'LIB'
ci_gate_select_init() { CI_SELECT_NOTE="stub selection for $1"; }
ci_gate_select() { if [ "$1" = beta ]; then echo "skip: stub reason"; else echo "run: stub"; fi; }
LIB
  : > "$TRACE"
  : > "$summary"
  run_phase pre env CI_GATE_EVENT=push GITHUB_STEP_SUMMARY="$summary"
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "Scripts/pass_a.sh" ]] \
    || echo "a selector that skips beta: only alpha must run, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE")"
  grep -qxF 'beta|⏭ not run (selector: stub reason)' "$RUN_ROWS" 2>/dev/null \
    || echo "the skipped gate has no not-run row: $(rows_text)"
  grep -qF '1 of 2 gates passed, none red; ⏭ 1 not run (selector), not passed' <<< "$RUN_OUT" \
    || echo "the phase does not count the skipped gate as not run: ${RUN_OUT}"
  grep -qF 'Gate selection: stub selection for push' <<< "$RUN_OUT" || echo "the selector's note is not in the log: ${RUN_OUT}"
  grep -qF 'stub selection for push' "$summary" || echo "the selector's note is not in the step summary: $(cat "$summary")"
  # There but unreadable: every gate runs, named.
  chmod 000 "$lib"
  : > "$TRACE"
  run_phase pre env -u CI_GATE_EVENT
  chmod 644 "$lib"
  [[ "$RUN_RC" -eq 0 && "$(cat "$TRACE")" == "$(printf 'Scripts/pass_a.sh\nScripts/pass_b.sh')" ]] \
    || echo "an unreadable selector: every gate must run, exit ${RUN_RC}, ran: $(tr '\n' ' ' < "$TRACE")"
  grep -qF 'cannot be read, so every gate runs' <<< "$RUN_OUT" || echo "an unreadable selector is not named: ${RUN_OUT}"
  return 0
}

# The REAL Scripts/builds_tmpdir.sh, only where the repository has it (a
# self-hosted site; its Stream Deck push goes to the fake Companion set up at
# the top). A writable fake volume: the probe gate sees
# <volume>/tmp/fixture-repo, and the log and the step summary carry a `temp
# folder` row naming it. A missing volume: the probe sees the default TMPDIR,
# the phase still passes, and the log and the step summary carry the ⚠️ line.
case_builds_tmpdir_real() {
  local vol default seen summary
  [[ -n "$BUILDS_TMPDIR_SCRIPT" ]] || return 0
  new_sandbox "$1"
  cp "$BUILDS_TMPDIR_SCRIPT" "${SB}/Scripts/builds_tmpdir.sh"
  chmod +x "${SB}/Scripts/builds_tmpdir.sh"
  order "probe|Scripts/probe.sh|pre|"
  cat > "${SB}/Scripts/probe.sh" <<'PROBE'
#!/usr/bin/env bash
printf '%s\n' "${TMPDIR:-}" > "$PROBE_SEEN"
PROBE
  chmod +x "${SB}/Scripts/probe.sh"
  vol="${SB}.volume"
  default="${SB}.default-tmp"
  mkdir -p "$vol" "$default"
  seen="${SB}.seen"
  summary="${SB}.summary.md"
  : > "$seen"; : > "$summary"
  run_phase pre env BUILDS_VOLUME="$vol" TMPDIR="$default" PROBE_SEEN="$seen" GITHUB_STEP_SUMMARY="$summary"
  [[ "$RUN_RC" -eq 0 ]] || echo "writable volume: exit ${RUN_RC}, want 0: ${RUN_OUT}"
  [[ "$(cat "$seen")" == "${vol}/tmp/fixture-repo" ]] \
    || echo "writable volume: the probe gate saw TMPDIR=$(cat "$seen"), not ${vol}/tmp/fixture-repo"
  grep -qF "${vol}/tmp/fixture-repo" <<< "$(grep -E 'temp folder' <<< "$RUN_OUT")" \
    || echo "writable volume: the log has no 'temp folder' row naming ${vol}/tmp/fixture-repo"
  grep -qF "${vol}/tmp/fixture-repo" <<< "$(grep -E 'temp folder' "$summary")" \
    || echo "writable volume: the step summary has no 'temp folder' row naming ${vol}/tmp/fixture-repo"
  : > "$seen"; : > "$summary"
  run_phase pre env BUILDS_VOLUME="${SB}.missing" TMPDIR="$default" PROBE_SEEN="$seen" GITHUB_STEP_SUMMARY="$summary"
  [[ "$RUN_RC" -eq 0 ]] || echo "missing volume: exit ${RUN_RC}, want 0 (estate decision 388, the run continues): ${RUN_OUT}"
  [[ "$(cat "$seen")" == "$default" ]] \
    || echo "missing volume: the probe gate saw TMPDIR=$(cat "$seen"), not the default ${default}"
  grep -qF "${SB}.missing" <<< "$(grep -F '⚠️' <<< "$RUN_OUT")" \
    || echo "missing volume: the log has no ⚠️ line naming ${SB}.missing"
  grep -qF "${SB}.missing" <<< "$(grep -F '⚠️' "$summary")" \
    || echo "missing volume: the step summary has no ⚠️ line naming ${SB}.missing"
  return 0
}

# The REAL order file, with a stub for every runnable row: both phases pass and
# between them run each row exactly once, in its own phase. A real row the
# runner would call malformed fails here.
case_real_order_file() {
  local script want got
  new_sandbox "$1"
  cp "$ORDER" "${SB}/Scripts/gate_report_order.txt"
  # No group file is a repository whose gates all run in the default job.
  local groups_file="${TMP}/no_job_groups.txt"
  : > "$groups_file"
  if [[ -f Scripts/ci_job_groups.txt ]]; then
    cp Scripts/ci_job_groups.txt "${SB}/Scripts/ci_job_groups.txt"
    groups_file=Scripts/ci_job_groups.txt
  fi
  while IFS='|' read -r _l script _p _c; do
    [[ -n "${script:-}" && "$script" != "n/a" ]] || continue
    stub "$script" 0
  done < <(grep -v '^#' "$ORDER" | grep .)
  # default_has <phase>: the default job has a row in the phase (a site that
  # gives every pre row to a job has none in pre, and does not call it).
  default_has() {
    awk -F'|' -v ph="$1" 'NR == FNR { if ($0 !~ /^#/ && $2 != "") g[$2] = 1; next } $0 !~ /^#/ && $2 != "" && $2 != "n/a" && $3 == ph && !($1 in g) { f = 1 } END { exit !f }' \
      "$groups_file" "$ORDER"
  }
  if default_has pre; then
    run_phase pre
    [[ "$RUN_RC" -eq 0 ]] || echo "pre over the real order file exited ${RUN_RC}: ${RUN_OUT}"
  fi
  # Every job the group file names, in every phase it has a row in (the jobs
  # are read from the data file, not spelled here).
  while IFS='|' read -r job; do
    [[ -n "$job" ]] || continue
    for phase in pre post; do
      awk -F'|' -v j="$job" -v ph="$phase" 'NR == FNR { if ($0 !~ /^#/ && $1 == j) want[$2] = 1; next } $0 !~ /^#/ && ($1 in want) && $3 == ph { f = 1 } END { exit !f }' \
        "$groups_file" "$ORDER" || continue
      RUN_JOB="$job" run_phase "$phase"
      [[ "$RUN_RC" -eq 0 ]] || echo "${phase} of the job ${job} over the real order file exited ${RUN_RC}: ${RUN_OUT}"
    done
  done < <(awk -F'|' '$0 !~ /^#/ && $1 != "" && !seen[$1]++ { print $1 }' "$groups_file")
  RUN_JOB=""
  if default_has post; then
    run_phase post
    [[ "$RUN_RC" -eq 0 ]] || echo "post over the real order file exited ${RUN_RC}: ${RUN_OUT}"
  fi
  # Each runnable row runs once, or once per group row that names it (a split
  # gate runs once in each of its shard jobs).
  want="$(awk -F'|' 'NR == FNR { if ($0 !~ /^#/ && $2 != "") n[$2]++; next } $0 !~ /^#/ && $2 != "" && $2 != "n/a" { for (i = 0; i < (n[$1] ? n[$1] : 1); i++) print $2 }' "$groups_file" "$ORDER" | LC_ALL=C sort)"
  got="$(LC_ALL=C sort "$TRACE")"
  [[ "$got" == "$want" ]] || echo "the jobs and phases did not run every runnable row exactly once"
  return 0
}

# forsgren#574, part 1: the rows and details paths are unique per run,
# attempt and job. A self-hosted runner reuses _work/_temp, so a fixed
# quality_rows.md let a cancelled job's loop append into the NEXT run's file.
# `run_ci_phase.sh report-dir` prints the folder a job writes its rows
# (quality_rows.md), details (quality_details/) and hand-over in; quality.yml
# uses it.
case_report_dir() {
  local a b c d e v
  new_sandbox "$1"
  report_dir() { # <run> <attempt> <job>
    (cd "$SB" && RUNNER_TEMP="${SB}.temp" GITHUB_RUN_ID="$1" GITHUB_RUN_ATTEMPT="$2" GITHUB_JOB="$3" \
      RUN_CI_PHASE_ROOT="$SB" bash "${SB}/Scripts/run_ci_phase.sh" report-dir 2>&1)
  }
  a="$(report_dir 100 1 lint)" || echo "report-dir failed with every variable set: ${a}"
  b="$(report_dir 101 1 lint)" || true
  c="$(report_dir 100 2 lint)" || true
  d="$(report_dir 100 1 browser)" || true
  e="$(report_dir 100 1 lint)" || true
  [[ "$a" == "${SB}.temp/"* ]] || echo "the report folder is not under RUNNER_TEMP: ${a}"
  [[ "$a" == "$e" ]] || echo "the report folder is not stable for one run, attempt and job: ${a} vs ${e}"
  [[ -n "$a" && "$a" != "$b" ]] || echo "two runs share a report folder: ${a} and ${b}"
  [[ -n "$a" && "$a" != "$c" ]] || echo "two attempts of one run share a report folder: ${a} and ${c}"
  [[ -n "$a" && "$a" != "$d" ]] || echo "two jobs of one run share a report folder: ${a} and ${d}"
  for v in RUNNER_TEMP GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_JOB; do
    if (cd "$SB" && env RUNNER_TEMP="${SB}.temp" GITHUB_RUN_ID=1 GITHUB_RUN_ATTEMPT=1 GITHUB_JOB=lint \
        RUN_CI_PHASE_ROOT="$SB" "${v}=" bash "${SB}/Scripts/run_ci_phase.sh" report-dir > /dev/null 2>&1); then
      echo "report-dir succeeded with an empty ${v}"
    fi
  done
  return 0
}

# forsgren#574, part 2: the cancel signal. The runner sends SIGTERM to the
# step's shell; the loop must stop its gate (and the gate's own children),
# exit, and write nothing more: no row for the gate it cut off, no later gate.
case_cancel() {
  local pid rc=0 i gatepid childpid rows
  new_sandbox "$1"
  order "slow|Scripts/slow.sh|pre|" "after|Scripts/pass_a.sh|pre|"
  stub Scripts/pass_a.sh 0
  cat > "${SB}/Scripts/slow.sh" <<'SLOW'
#!/usr/bin/env bash
echo $$ > "${STUB_TRACE}.gatepid"
sleep 60 &
echo $! > "${STUB_TRACE}.childpid"
wait
SLOW
  chmod +x "${SB}/Scripts/slow.sh"
  rows="${SB}.cancel.rows"
  rm -f "$rows" "${TRACE}.gatepid" "${TRACE}.childpid"
  STUB_TRACE="$TRACE" RUN_CI_PHASE_ROOT="$SB" \
    bash "${SB}/Scripts/run_ci_phase.sh" pre "$rows" "${SB}.cancel.details" > "${SB}.cancel.out" 2>&1 < /dev/null &
  pid=$!
  for i in $(seq 1 100); do
    [[ -s "${TRACE}.childpid" ]] && break
    sleep 0.1
  done
  gatepid="$(cat "${TRACE}.gatepid" 2>/dev/null || true)"
  childpid="$(cat "${TRACE}.childpid" 2>/dev/null || true)"
  if [[ -z "$childpid" ]]; then
    echo "the slow gate never started: $(cat "${SB}.cancel.out")"
    kill -KILL "$pid" 2>/dev/null || true
    return 0
  fi
  kill -TERM "$pid"
  for i in $(seq 1 100); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "the loop kept running 10 s after SIGTERM"
    kill -KILL "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || rc=$?
  [[ "$rc" -eq 143 ]] || echo "the cancelled loop exited ${rc}, want 143 (128 + SIGTERM)"
  sleep 0.3
  if kill -0 "$gatepid" 2>/dev/null; then echo "the gate (${gatepid}) survived the cancel"; fi
  if kill -0 "$childpid" 2>/dev/null; then echo "the gate's child (${childpid}) survived the cancel"; fi
  kill -KILL "$gatepid" "$childpid" 2>/dev/null || true
  sleep 0.3
  if [[ -s "$rows" ]]; then echo "the cancelled loop wrote rows: $(tr '\n' ' ' < "$rows")"; fi
  if has -F Scripts/pass_a.sh < "$TRACE"; then echo "the loop ran the next gate after the cancel"; fi
  return 0
}

# forsgren#614: the gate's capture file (run_ci_phase_capture.*, made with
# tmp_file in TMPDIR) is gone after the run on every way out: the gate ends,
# the cancel (TERM, INT) and a kill (KILL, which no trap can answer). Each run
# gets its own TMPDIR, so the find sees this run's files alone.
# capture_left <how>: how is ended, TERM, INT or KILL; prints the files left.
capture_left() {
  local how="$1" pid i childpid gatepid tmpd
  tmpd="${SB}.tmp.${how}"
  mkdir -p "$tmpd"
  rm -f "${TRACE}.gatepid" "${TRACE}.childpid"
  if [[ "$how" == ended ]]; then
    TMPDIR="$tmpd" STUB_TRACE="$TRACE" RUN_CI_PHASE_ROOT="$SB" \
      bash "${SB}/Scripts/run_ci_phase.sh" pre "${SB}.${how}.rows" "${SB}.${how}.details" > "${SB}.${how}.out" 2>&1 < /dev/null || true
  else
    TMPDIR="$tmpd" STUB_TRACE="$TRACE" RUN_CI_PHASE_ROOT="$SB" \
      bash "${SB}/Scripts/run_ci_phase.sh" pre "${SB}.${how}.rows" "${SB}.${how}.details" > "${SB}.${how}.out" 2>&1 < /dev/null &
    pid=$!
    for i in $(seq 1 100); do
      [[ -s "${TRACE}.childpid" ]] && break
      sleep 0.1
    done
    gatepid="$(cat "${TRACE}.gatepid" 2>/dev/null || true)"
    childpid="$(cat "${TRACE}.childpid" 2>/dev/null || true)"
    kill -"$how" "$pid" 2>/dev/null || true
    for i in $(seq 1 100); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    sleep 0.3
    kill -KILL "${gatepid:-0}" "${childpid:-0}" 2>/dev/null || true
  fi
  find "$tmpd" -maxdepth 1 -name 'run_ci_phase_capture.*' -print
}

case_capture_gone() {
  local how left
  new_sandbox "$1"
  order "slow|Scripts/slow.sh|pre|"
  cat > "${SB}/Scripts/slow.sh" <<'SLOW'
#!/usr/bin/env bash
echo $$ > "${STUB_TRACE}.gatepid"
sleep 60 &
echo $! > "${STUB_TRACE}.childpid"
wait
SLOW
  chmod +x "${SB}/Scripts/slow.sh"
  for how in TERM INT KILL; do
    left="$(capture_left "$how")"
    [[ -z "$left" ]] || echo "after ${how} the runner left its capture file: ${left}"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > "${SB}/Scripts/slow.sh"
  left="$(capture_left ended)"
  [[ -z "$left" ]] || echo "after a finished gate the runner left its capture file: ${left}"
  return 0
}

# The workflow names the folder through the runner, never a fixed path. The
# gate jobs are read from the workflow, not counted here (forsgren#641; gap (f)
# of #647 makes it hold for every site's layout): a gate job is a job that
# calls `run_ci_phase.sh pre` or `post`. Each gate job asks `report-dir`, and
# hands its rows on through the per-run folder: a per-run hand-over folder
# (forsgren's merge_quality_report.sh) or a per-run quality_rows.md upload (the
# sites'). A job that names a hand-over folder names the per-run one.
# workflow_jobs <workflow>: one line per job, `<id> <gate> <report-dir> <per-run
# hand-over> <per-run rows> <other hand-over>` (gate 1 or 0, then counts).
workflow_jobs() {
  awk -v per='runner\\.temp }}/quality_\\$\\{\\{ github\\.run_id }}_\\$\\{\\{ github\\.run_attempt }}_\\$\\{\\{ github\\.job }}/' '
    function flush() { if (id != "") print id, g + 0, r + 0, h + 0, q + 0, o + 0 }
    /^jobs:/ { on = 1; next }
    on && /^[^[:space:]#]/ { flush(); id = ""; on = 0 }
    on && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); id = $1; sub(/:$/, "", id); g = r = h = q = o = 0; next }
    !on || id == "" { next }
    /run_ci_phase\.sh (pre|post) / { g = 1 }
    /run_ci_phase\.sh report-dir/ { r++ }
    $0 ~ per "handover[[:space:]]*$" { h++; next }
    $0 ~ per "quality_rows\\.md" { q++ }
    /\/handover[[:space:]]*$/ { o++ }
    END { flush() }' "$1"
}
# gate_job_count <workflow>: the jobs that call the runner's pre or post phase.
gate_job_count() {
  workflow_jobs "$1" | awk '$2 == 1 { n++ } END { print n + 0 }'
}
case_workflow_paths() {
  local wf="${QUALITY_WF:-.github/workflows/quality.yml}" id gate r h q o
  grep -nE '(RUNNER_TEMP\}|runner\.temp \}\})/quality_(rows|details)' "$wf" \
    | sed 's/^/a fixed rows or details path in quality.yml: /' || true
  [[ "$(gate_job_count "$wf")" -ge 1 ]] || echo "quality.yml has no gate job this case can read"
  while read -r id gate r h q o; do
    [[ "$gate" -eq 1 ]] || continue
    [[ "$r" -ge 1 ]] || echo "the gate job ${id} never asks the runner for its report folder (report-dir)"
    [[ "$h" -ge 1 || "$q" -ge 1 ]] || echo "the gate job ${id} hands its rows on through no per-run folder (no per-run hand-over, no per-run quality_rows.md)"
    [[ "$o" -eq 0 ]] || echo "the gate job ${id} names a hand-over folder that is not the per-run one"
  done < <(workflow_jobs "$wf")
  return 0
}

CASES=(report_dir cancel capture_gone workflow_paths na_skip phase_filter secret_class dirty_tree empty_phase missing_script non_executable bad_row usage job_groups shards group_args default_job post_job group_file builds_tmpdir builds_tmpdir_real tmp_failure gate_selection real_order_file)

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
  $'s/^    in_job "\$label" \|\| continue$/    true/' job_groups

# A job runs the gates of main, not its own.
mutation_proof "a runner whose jobs ignore their group" \
  $'s/^JOB="\\$\\{4:-\\}"$/JOB=""/' job_groups

# A shard job runs its gate without the group row's arguments.
mutation_proof "a runner that drops the arguments of a group row" \
  $'s/ \\$\\{gate_args\\[@\\]\\+"\\$\\{gate_args\\[@\\]\\}"\\} </ </' shards

# A shard row keeps the plain label, so a red cannot name its shard.
mutation_proof "a runner that does not name the shard in the row" \
  $'s/^      shown="\\$\\{label\\} \\(.*$/      :/' shards

# Without the trap the cancel kills the loop and leaves the gate running.
mutation_proof "a runner without the cancel trap" \
  $'s/^trap .cancelled 143. TERM$/:/' cancel \
  "survived the cancel"

# A capture file that is never unlinked stays in TMPDIR on a kill (and, the
# trap having nothing to remove, on a cancel too).
mutation_proof "a runner that keeps its capture file" \
  $'s/^    rm -f "\\$capture_path"$/    :/' capture_gone

# A report folder without the job is shared by the jobs of one run.
mutation_proof "a runner whose report folder ignores the job" \
  $'s/"\\$GITHUB_RUN_ATTEMPT" "\\$GITHUB_JOB"$/"$GITHUB_RUN_ATTEMPT" job/' report_dir \
  "two jobs of one run share a report folder"

# v8 (forsgren#646). Arguments outside the safe set are taken as none.
mutation_proof "a runner without the safe character set for arguments" \
  $'s/bad_args="its arguments/bad_args=""; : "its arguments/' group_args

# Arguments split by eval.
mutation_proof "a runner that splits arguments with eval" \
  $'s/read -r -a gate_args <<< "\\$args"/eval "gate_args=($args)"/' group_args

# Any job name is taken.
mutation_proof "a runner that takes any job name" \
  $'s/^    \'\'\\|\\*\\[!A-Za-z0-9_-\\]\\*\\) echo "❌ FAIL: the job name.*$/    \'\') usage ;;/' default_job

# A named job may not run post rows (the sites' v7 rule).
mutation_proof "a runner that refuses post rows in a named job" \
  $'s/^\\[ "\\$JOB" != "main" \\] \\|\\| JOB=""$/&; [ -z "$JOB" ] || [ "$PHASE" = "pre" ] || usage/' post_job

# A malformed row is skipped in a named job.
mutation_proof "a runner that reports a malformed row only in the default job" \
  $'s/^  if \\[ -z "\\$bad" \\]; then$/  if [ -n "$bad" ] \\&\\& [ -n "$JOB" ]; then continue; fi; if [ -z "$bad" ]; then/' group_file

# The same job and gate twice is taken.
mutation_proof "a runner that takes a group row twice" \
  $'s/^  if \\[ -n "\\$twice" \\]; then$/  if false; then/' group_file

# builds_tmpdir.sh is run where the repository has none.
mutation_proof "a runner that runs builds_tmpdir.sh where there is none" \
  $'s/^if \\[ -e \\.\\/Scripts\\/builds_tmpdir\\.sh \\]; then$/if true; then/' builds_tmpdir

# A failing or silent builds_tmpdir.sh does not stop the phase.
mutation_proof "a runner that ignores a failing builds_tmpdir.sh" \
  $'s/^  if \\[ -z "\\$BUILDS_TMPDIR" \\]; then$/  if false; then/' builds_tmpdir

# The capture file's tmp_file is not checked.
mutation_proof "a runner that does not check its temp file" \
  $'s/capture_path="\\$\\(tmp_file run_ci_phase_capture\\)" \\|\\| \\{.*$/capture_path="$(tmp_file run_ci_phase_capture)"/' tmp_failure

# The absent selector is named on every run.
mutation_proof "a runner that names a missing selector nobody asked for" \
  $'s/^  if \\[ -e "\\$SELECT_LIB" \\] \\|\\| \\[ -n "\\$\\{CI_GATE_EVENT:-\\}" \\]; then$/  if true; then/' gate_selection

# Without the selector a gate is skipped instead of run.
mutation_proof "a runner that skips gates without a selector" \
  $'s/echo "run: \\[selector_unreadable\\]/echo "skip: [selector_unreadable]/' gate_selection

# workflow_paths reads the gate jobs from the workflow (forsgren#641, #646), so
# its proofs do too: a copy of quality.yml with one more gate job that asks for
# no report folder, and copies whose last gate job with a per-run hand-over or
# rows path loses it (another folder, or a fixed one), must each be named. The
# job is read from the workflow, never spelled here, so every site's layout
# gets the same proofs.
# wf_proof <label> <awk-program> <finding>: case_workflow_paths on the mutated copy.
wf_proof() {
  local mutated="${TMP}/quality_$((MUTANT_N += 1)).yml" problems
  awk -v job="$WF_JOB" "$2" .github/workflows/quality.yml > "$mutated"
  if cmp -s .github/workflows/quality.yml "$mutated"; then
    fail "mutation ${1}: the awk changed nothing, so it proves nothing"
    return 0
  fi
  problems="$(QUALITY_WF="$mutated" case_workflow_paths)"
  if grep -qF -- "$3" <<< "$problems"; then
    echo "  ok: mutation ${1} is caught by workflow_paths"
  else
    fail "mutation ${1}: workflow_paths did not say '${3}'. It said: ${problems:-nothing}"
  fi
}
WF_JOB="$(workflow_jobs .github/workflows/quality.yml | awk '$2 == 1 && ($4 > 0 || $5 > 0) { j = $1 } END { print j }')"
[[ -n "$WF_JOB" ]] || fail "quality.yml has no gate job with a per-run hand-over or rows path for the workflow proofs"
# In the job: the lines of its per-run folder (the awk sees the job's id line
# as `  <job>:` and leaves at the next one).
WF_IN_JOB="/^  [A-Za-z0-9_-]+:[[:space:]]*\$/ { id = \$1; sub(/:\$/, \"\", id); on = (id == job) }"
WF_PER_RUN='/quality_\$\{\{ github\.run_id \}\}_/'
wf_proof "a gate job that asks for no report folder" \
  '{ print } /^jobs:/ { print "  extra_gate:"; print "    runs-on: ubuntu-latest"; print "    steps:"; print "      - run: ./Scripts/run_ci_phase.sh pre rows details extra_gate"; print "" }' \
  "the gate job extra_gate never asks the runner for its report folder"
wf_proof "a gate job whose hand-over names another folder" \
  "${WF_IN_JOB} on && ${WF_PER_RUN} { sub(/\\/handover[[:space:]]*\$/, \"/elsewhere\"); sub(/\\/quality_rows\\.md/, \"/elsewhere.md\") } { print }" \
  "the gate job ${WF_JOB} hands its rows on through no per-run folder"
wf_proof "a gate job whose hand-over is a fixed folder" \
  "${WF_IN_JOB} on && !done && ${WF_PER_RUN} && /(\\/handover|\\/quality_rows\\.md)[[:space:]]*\$/ { sub(/(path: )?\\\$\\{\\{ runner\\.temp \\}\\}.*\$/, (\$0 ~ /path: / ? \"path: \" : \"\") \"/tmp/handover\"); done = 1 } { print }" \
  "the gate job ${WF_JOB} names a hand-over folder that is not the per-run one"

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: run_ci_phase self-test"
  exit 1
fi

echo "OK: run_ci_phase.sh skips n/a rows, filters phases, exits 2 on a secret-class failure, and is red on a dirty tree, an empty phase, a missing or non-executable script, a malformed row, unsafe group arguments, a wrong group file and a failed temp file; it runs each gate in exactly one job (the default job the unlisted ones, a named job its own pre or post rows, shards with their words split by read -r -a), and takes the build-volume TMPDIR and gate selection only where their scripts exist (each proved against a weakened runner)"
