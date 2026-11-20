#!/usr/bin/env bash
# Scripts/test_sfl_selftest_skip.sh (forsgren#686, step 2)
#
# Self-test of a local run leaving the self-test rows to the Self-tests
# workflow. Since forsgren#686 step 1 the self-test rows run in
# .github/workflows/selftests.yml after the push and quality.yml runs the real
# gates; sfl.sh runs what quality.yml runs. Scripts/selftest_rows.sh names the
# rows to leave out from the same files CI runs from (Scripts/ci_job_groups.txt
# and selftests.yml); sfl.sh does not run them, does not count them, prints one
# line saying how many it left out, and appends that line to
# .build/sfl-selftests-skipped.log (emptied by pre), which FBP.sh's summary
# repeats. `sfl.sh --with-selftests`, SFL_WITH_SELFTESTS=1 and
# `FBP.sh --with-selftests` run every row.
#
# The gates are fakes in a throwaway root with a copy of the real sfl.sh, the
# real Scripts/selftest_rows.sh and the real step table renderer, a made-up
# order file, groups file and self-tests' workflow; each gate records that it
# ran in a marks directory outside the tree. Cases:
#   1. selftest_rows.sh: exactly the rows whose jobs are all self-tests' jobs, in
#      order (not a real gate, not a row of Quality's main job, not an n/a row,
#      not a row split over both workflows); red, named, for a missing file or
#      a workflow that runs no job; 64 for a wrong call
#   2. default pre run  -> the real gates run, the three self-test rows do not;
#                          green; the step count holds; the line is printed and
#                          written to the sink, and no skipped row is a row of
#                          the step table
#   3. --with-selftests -> every row runs, no line, a stale sink is emptied
#   4. SFL_WITH_SELFTESTS=1 -> every row runs
#   5. a list that cannot be read stops sfl before any gate (exit 1, named)
#   6. a post run after a pre run keeps pre's line in the sink
#   7. the real files: selftest_rows.sh names exactly the rows of the rule (a
#      label ending in " self-test" or starting with "mutation: ", and the step
#      summary isolation gate; not the secret-class secret-scan self-test), none
#      other, so the local skip set is the CI self-test set
#   8. FBP.sh: the summary repeats the sink's line, prints nothing without it,
#      and --with-selftests reaches sfl.sh as SFL_WITH_SELFTESTS=1 (a plain run
#      leaves it unset)
# Mutation proofs:
#   A. the skip ignored:           the self-tests run and the step count is red
#   B. a real gate wrongly skipped (selftest_rows.sh prints every grouped row):
#                                  case 1, the sfl run and case 7 catch it
#   C. the summary line dropped:   case 2 prints no line
#   D. --with-selftests ignored:   case 3 runs no self-test
#   E. TOTAL_STEPS not lowered:    the step-count self-check is red
#   F. a skip not counted:         the step-count self-check is red
#   G. FBP's summary never prints the line; H. FBP never passes the switch on

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

# The FBP.sh runs of case 8 call git: never against an ambient GIT_DIR.
# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_fbp_sandbox.sh
source Scripts/lib_fbp_sandbox.sh
selftest_begin "sfl self-test skip self-test"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
SFL_REAL="${REPO}/sfl.sh"
ROWS_REAL="${REPO}/Scripts/selftest_rows.sh"
FBP_REAL="${REPO}/FBP.sh"
MARKS="${TMP}/marks"
LINE3="self-tests skipped locally (3 rows): they run in the Self-tests workflow on GitHub after the push — use --with-selftests to run them here"

# mark_gate <mark> <path>: a gate that records that it ran.
mark_gate() {
  {
    echo '#!/usr/bin/env bash'
    echo "touch \"\${MARKS}/$1\""
  } > "$2"
}

# write_fixture_files <dir>: the made-up order file, groups file and workflow.
# `real pre` runs in Quality's main job (no group row), `real lint` in a
# Quality job, `site self-test` and `mutation: site pins` in self-test jobs,
# `split self-test` in a shard of each workflow (so not left out), `sandbox
# isolation` in two self-test shards.
write_fixture_files() {
  mkdir -p "$1/Scripts" "$1/.github/workflows"
  cat > "$1/Scripts/gate_report_order.txt" << 'ORDER'
# a made-up order file
real pre|Scripts/gate_real_pre.sh|pre|
real lint|Scripts/gate_real_lint.sh|pre|
site self-test|Scripts/fake_site_selftest.sh|pre|
mutation: site pins|Scripts/fake_mutation.sh|pre|
split self-test|Scripts/fake_split.sh|pre|
sandbox isolation|Scripts/fake_sandbox.sh|pre|
not a gate|n/a|declared for the report|
real post|Scripts/gate_real_post.sh|post|
ORDER
  cat > "$1/Scripts/ci_job_groups.txt" << 'GROUPS'
# a made-up groups file
lint|real lint
selftest_1|site self-test
selftest_2|mutation: site pins
lint|split self-test|--shard 1/2
selftest_1|split self-test|--shard 2/2
sandbox_1|sandbox isolation|--shard 1/2
sandbox_2|sandbox isolation|--shard 2/2
GROUPS
  cat > "$1/.github/workflows/selftests.yml" << 'WORKFLOW'
name: Self-tests
jobs:
  selftest_1:
    steps:
      - run: |
          # ./Scripts/run_ci_phase.sh pre "$ROWS" "$DETAILS" lint
          ./Scripts/run_ci_phase.sh pre "$ROWS" "$DETAILS" selftest_1
  selftest_2:
    steps:
      - run: |
          ./Scripts/run_ci_phase.sh pre "$ROWS" "$DETAILS" selftest_2
  sandbox_1:
    steps:
      - run: |
          ./Scripts/run_ci_phase.sh pre "$ROWS" "$DETAILS" sandbox_1
  sandbox_2:
    steps:
      - run: |
          ./Scripts/run_ci_phase.sh pre "$ROWS" "$DETAILS" sandbox_2
WORKFLOW
}

# make_root <name> [sfl] [selftest_rows]: a throwaway root running copies of the
# real (or the given) scripts, its environment helpers stubbed.
make_root() {
  local root="${TMP}/$1" s
  write_fixture_files "$root"
  mkdir -p "${root}/.build"
  cp "${2:-$SFL_REAL}" "${root}/sfl.sh"
  cp "${3:-$ROWS_REAL}" "${root}/Scripts/selftest_rows.sh"
  cp "${REPO}/Scripts/render_step_table.sh" "${REPO}/Scripts/summarize_gate_failure.sh" \
    "${REPO}/Scripts/lib_gate_select.sh" "${REPO}/Scripts/lib_tmp.sh" "${root}/Scripts/"
  printf '#!/usr/bin/env bash\nsfl_pull_or_stop() { return 0; }\n' > "${root}/Scripts/sfl_pull.sh"
  printf '#!/usr/bin/env bash\necho go1.0\n' > "${root}/Scripts/go_toolchain.sh"
  for s in install_tools check_node_pin npm_sync_install; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/Scripts/${s}.sh"
  done
  echo '# no gate is selected by its inputs here' > "${root}/Scripts/gate_inputs.txt"
  mark_gate real-pre "${root}/Scripts/gate_real_pre.sh"
  mark_gate real-lint "${root}/Scripts/gate_real_lint.sh"
  mark_gate real-post "${root}/Scripts/gate_real_post.sh"
  mark_gate fst "${root}/Scripts/fake_site_selftest.sh"
  mark_gate mut "${root}/Scripts/fake_mutation.sh"
  mark_gate split "${root}/Scripts/fake_split.sh"
  mark_gate sandbox "${root}/Scripts/fake_sandbox.sh"
  chmod +x "${root}"/sfl.sh "${root}"/Scripts/*.sh
  printf '%s\n' "$root"
}

# run_sfl <root> <phase> [VAR=value...] [-- sfl arguments...]: sfl.sh as FBP
# runs it, outside Quality, the marks cleared first.
run_sfl() {
  local root="$1" phase="$2" envs=()
  shift 2
  while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift
  rm -rf "$MARKS"
  mkdir -p "$MARKS"
  OUT="$(cd "$root" && env -u GITHUB_ACTIONS -u SFL_WITH_SELFTESTS -u SFL_GATE_SELECT_FULL MARKS="$MARKS" ${envs[@]+"${envs[@]}"} ./sfl.sh "$@" "$phase" 2>&1)" && RC=0 || RC=$?
}

marked() { [[ -f "${MARKS}/$1" ]]; }
sink() { cat "$1/.build/sfl-selftests-skipped.log" 2> /dev/null || true; }

# check_ran / check_not_ran <case> <mark> <label>
check_ran() {
  if marked "$2"; then echo "  ok: $1 ${3} ran"; else fail "$1 ${3} did not run. Output: ${OUT}"; fi
}
check_not_ran() {
  if marked "$2"; then fail "$1 ${3} ran although it is a self-test row. Output: ${OUT}"; else echo "  ok: $1 ${3} did not run"; fi
}

# check_all_ran <case>: every pre row of the fixture ran.
check_all_ran() {
  local pair
  for pair in "real-pre|real pre" "real-lint|real lint" "fst|site self-test" "mut|mutation: site pins" "split|split self-test" "sandbox|sandbox isolation"; do
    check_ran "$1" "${pair%%|*}" "${pair#*|}"
  done
}

# Case 1: selftest_rows.sh on the fixture files.
FX="${TMP}/fx"
write_fixture_files "$FX"
want_rows=$'site self-test\nmutation: site pins\nsandbox isolation'
capture "$ROWS_REAL" "$FX/Scripts/gate_report_order.txt" "$FX/Scripts/ci_job_groups.txt" "$FX/.github/workflows/selftests.yml"
if [[ "$RC" == 0 && "$OUT" == "$want_rows" ]]; then
  echo "  ok: 1. the self-test rows, in order, and no real gate, main-job row, split row or n/a row"
else
  fail "1. selftest_rows.sh printed (exit ${RC}): ${OUT}; want: ${want_rows}"
fi
capture "$ROWS_REAL" "$FX/Scripts/gate_report_order.txt" "$FX/Scripts/ci_job_groups.txt" "${TMP}/absent.yml"
want_exit "1. a missing workflow is red and named" 1 "${TMP}/absent.yml is missing"
echo 'name: nothing' > "${TMP}/nojobs.yml"
capture "$ROWS_REAL" "$FX/Scripts/gate_report_order.txt" "$FX/Scripts/ci_job_groups.txt" "${TMP}/nojobs.yml"
want_exit "1. a workflow that runs no job is red and named" 1 "runs no job through the CI phase runner"
capture "$ROWS_REAL" one two
want_exit "1. a wrong number of arguments is a usage error" 64 "usage: selftest_rows.sh"

# Case 2: the default pre run leaves the self-test rows out.
root="$(make_root default)"
run_sfl "$root" pre
check_ran "2." real-pre "real pre (Quality's main job)"
check_ran "2." real-lint "real lint (a Quality job)"
check_ran "2." split "split self-test (one shard in Quality)"
check_not_ran "2." fst "site self-test"
check_not_ran "2." mut "mutation: site pins"
check_not_ran "2." sandbox "sandbox isolation"
if [[ "$RC" == 0 ]]; then echo "  ok: 2. sfl is green"; else fail "2. sfl exited ${RC}. Output: ${OUT}"; fi
want_said "2. the step-count self-check holds with the self-test rows left out" "OK: TOTAL_STEPS=4 matches the 4 steps executed (3 self-test rows skipped locally)"
want_said "2. the summary line names the rows left out and the switch" "$LINE3"
if [[ "$(sink "$root")" == "$LINE3" ]]; then echo "  ok: 2. the line is in .build/sfl-selftests-skipped.log"; else fail "2. the sink holds: $(sink "$root")"; fi
if grep -qE '\] ==> (site self-test|mutation: site pins|sandbox isolation)$' <<< "$OUT"; then
  fail "2. a self-test row left out was a step of the run. Output: ${OUT}"
else
  echo "  ok: 2. no row left out is a step of the run"
fi

# Case 3: --with-selftests runs every row and empties a stale sink.
root="$(make_root with)"
echo "stale line" > "${root}/.build/sfl-selftests-skipped.log"
run_sfl "$root" pre -- --with-selftests
check_all_ran "3."
want_said "3. the step-count self-check holds with every row" "OK: TOTAL_STEPS=7 matches the 7 steps executed (0 self-test rows skipped locally)"
if grep -qF "self-tests skipped locally" <<< "$OUT"; then fail "3. the line is printed although every row ran"; else echo "  ok: 3. no line when every row ran"; fi
if [[ -z "$(sink "$root")" ]]; then echo "  ok: 3. the stale sink is emptied"; else fail "3. the sink holds: $(sink "$root")"; fi

# Case 4: the environment switch.
root="$(make_root env)"
run_sfl "$root" pre SFL_WITH_SELFTESTS=1
check_all_ran "4."

# Case 5: a list that cannot be read stops the run before any gate.
root="$(make_root unreadable)"
rm -f "${root}/.github/workflows/selftests.yml"
run_sfl "$root" pre
want_exit "5. an unreadable self-test list stops sfl, named" 1 "Scripts/selftest_rows.sh failed, so the self-test rows are unknown; no gate ran"
if marked real-pre; then fail "5. a gate ran although the list could not be read"; else echo "  ok: 5. no gate ran"; fi

# Case 6: post after pre: the post phase has no self-test row here, runs its
# gate, prints no line and leaves pre's line in the sink for FBP.sh.
root="$(make_root post)"
run_sfl "$root" pre
run_sfl "$root" post
check_ran "6." real-post "real post"
want_said "6. the post step count holds" "OK: TOTAL_STEPS=2 matches the 2 steps executed (0 self-test rows skipped locally)"
if [[ "$(sink "$root")" == "$LINE3" ]]; then echo "  ok: 6. pre's line is still in the sink after post"; else fail "6. after post the sink holds: $(sink "$root")"; fi

# Case 7: the real files name exactly the self-test rows of the rule.
ORDER="${REPO}/Scripts/gate_report_order.txt"
rule_rows="$(grep -v '^#' "$ORDER" | awk -F'|' '
  $2 == "" || $2 == "n/a" { next }
  $1 == "secret-scan self-test" { next }
  $1 == "step summary isolation" || $1 ~ / self-test$/ || $1 ~ /^mutation: / { print $1 }')"
# real_rows_problems <selftest_rows script>: one line per row on the wrong side.
real_rows_problems() {
  local got
  got="$("$1" "$ORDER" "${REPO}/Scripts/ci_job_groups.txt" "${REPO}/.github/workflows/selftests.yml")" || { echo "selftest_rows.sh failed on the real files"; return 0; }
  comm -23 <(sort <<< "$rule_rows") <(sort <<< "$got") | sed 's/^/a self-test row the local run would still run: /'
  comm -13 <(sort <<< "$rule_rows") <(sort <<< "$got") | sed 's/^/a real gate the local run would skip: /'
}
problems="$(real_rows_problems "$ROWS_REAL")"
n_rule="$(grep -c . <<< "$rule_rows")"
if [[ -z "$problems" && "$n_rule" -gt 0 ]]; then
  echo "  ok: 7. the real files leave out exactly the ${n_rule} self-test rows Self-tests runs"
else
  fail "7. the real files: ${problems:-no self-test row found}"
fi

# Case 8: FBP.sh repeats the line and passes the switch on (lib_fbp_sandbox.sh:
# a stub sfl.sh that writes the line when asked and prints what it saw).
# run_fbp <fbp> <line or empty> [FBP flags...]: sets OUT and RC.
run_fbp() {
  local fbp="$1" line="$2"
  shift 2
  FBP_SANDBOX_FBP_OVERRIDE="$fbp" FBP_SANDBOX_SFL_SELFTESTS="$line" FBP_SANDBOX_SFL_LOG_SELFTESTS=1 \
    fbp_sandbox_run 3 --no-commit "$@"
  OUT="$FBP_SANDBOX_OUT"
  RC="$FBP_SANDBOX_RC"
}
# summary_has_line: the line stands after the summary's git row.
summary_has_line() {
  grep -qxF -- "$LINE3" <<< "$(awk '/^  git  / { on = 1 } on' <<< "$OUT")"
}
run_fbp "$FBP_REAL" "$LINE3"
if summary_has_line; then echo "  ok: 8. the FBP summary repeats sfl's line"; else fail "8. the FBP summary does not repeat '${LINE3}' (exit ${RC}). Output: ${OUT}"; fi
want_said "8. a plain FBP run leaves the self-tests out" "stub sfl SFL_WITH_SELFTESTS=unset"
run_fbp "$FBP_REAL" "" --with-selftests
want_said "8. FBP --with-selftests reaches sfl as SFL_WITH_SELFTESTS=1" "stub sfl SFL_WITH_SELFTESTS=1"
if grep -qF "self-tests skipped locally" <<< "$OUT"; then fail "8. the FBP summary prints the line although sfl wrote none"; else echo "  ok: 8. no line in the FBP summary when sfl wrote none"; fi

# Mutation proofs.
M="${TMP}/mut"
if selftest_mutant "$SFL_REAL" "$M/A/sfl.sh" 's/grep -qxF -- "[$]label" <<< "[$]SELFTEST_ROWS"/false/'; then
  root="$(make_root mA "$M/A/sfl.sh")"
  run_sfl "$root" pre
  if marked fst && [[ "$RC" != 0 ]]; then
    echo "  ok: mutation proof A: with the skip ignored the self-tests run and the step count is red, which case 2 catches"
  else
    fail "mutation proof A: with the skip ignored the self-test did not run or sfl stayed green (exit ${RC})"
  fi
fi
if selftest_mutant "$ROWS_REAL" "$M/B/selftest_rows.sh" 's/ in inst) \&\& !(/ in inst) || (/'; then
  capture "$M/B/selftest_rows.sh" "$FX/Scripts/gate_report_order.txt" "$FX/Scripts/ci_job_groups.txt" "$FX/.github/workflows/selftests.yml"
  b_case1=0
  [[ "$OUT" != "$want_rows" ]] && b_case1=1
  root="$(make_root mB "$SFL_REAL" "$M/B/selftest_rows.sh")"
  run_sfl "$root" pre
  if [[ "$b_case1" == 1 ]] && ! marked real-lint && [[ -n "$(real_rows_problems "$M/B/selftest_rows.sh")" ]]; then
    echo "  ok: mutation proof B: a real gate wrongly skipped is caught by case 1, by the sfl run (real lint did not run) and by case 7"
  else
    fail "mutation proof B: a selftest_rows.sh that names real gates was not caught"
  fi
fi
if selftest_mutant "$SFL_REAL" "$M/C/sfl.sh" '/self-tests skipped locally (%s rows)/d'; then
  root="$(make_root mC "$M/C/sfl.sh")"
  run_sfl "$root" pre
  if grep -qF "$LINE3" <<< "$OUT"; then fail "mutation proof C: the line is still printed"; else echo "  ok: mutation proof C: without the printf there is no line, which case 2 catches"; fi
fi
if selftest_mutant "$SFL_REAL" "$M/D/sfl.sh" 's/--with-selftests) SFL_WITH_SELFTESTS=1 ;;/--with-selftests) : ;;/'; then
  root="$(make_root mD "$M/D/sfl.sh")"
  run_sfl "$root" pre -- --with-selftests
  if marked fst; then fail "mutation proof D: the self-tests still ran with the switch ignored"; else echo "  ok: mutation proof D: with the switch ignored no self-test runs, which case 3 catches"; fi
fi
if selftest_mutant "$SFL_REAL" "$M/E/sfl.sh" 's/ - SELFTEST_SKIP_N + 1))/ + 1))/'; then
  root="$(make_root mE "$M/E/sfl.sh")"
  run_sfl "$root" pre
  if [[ "$RC" != 0 ]] && grep -qF "but this run executed 4 steps" <<< "$OUT"; then
    echo "  ok: mutation proof E: a TOTAL_STEPS that counts the rows left out makes the step-count self-check red"
  else
    fail "mutation proof E: the step-count self-check accepted a total that counts the rows left out (exit ${RC})"
  fi
fi
if selftest_mutant "$SFL_REAL" "$M/F/sfl.sh" '/^    SELFTEST_SKIPPED=[$]((SELFTEST_SKIPPED + 1))$/d'; then
  root="$(make_root mF "$M/F/sfl.sh")"
  run_sfl "$root" pre
  if [[ "$RC" != 0 ]] && grep -qF "and skipped 0 self-test rows" <<< "$OUT"; then
    echo "  ok: mutation proof F: a skip that is not counted makes the step-count self-check red"
  else
    fail "mutation proof F: the step-count self-check accepted uncounted skips (exit ${RC})"
  fi
fi
if selftest_mutant "$FBP_REAL" "$M/G/FBP.sh" '/^  print_selftest_skip$/d'; then
  run_fbp "$M/G/FBP.sh" "$LINE3"
  if summary_has_line; then fail "mutation proof G: the FBP summary still repeats the line"; else echo "  ok: mutation proof G: a summary that never prints the line is caught by case 8"; fi
fi
if selftest_mutant "$FBP_REAL" "$M/H/FBP.sh" 's/^      export SFL_WITH_SELFTESTS=1$/      :/'; then
  run_fbp "$M/H/FBP.sh" "" --with-selftests
  if grep -qF "stub sfl SFL_WITH_SELFTESTS=1" <<< "$OUT"; then fail "mutation proof H: sfl still saw the switch"; else echo "  ok: mutation proof H: an FBP.sh that never passes the switch on is caught by case 8"; fi
fi

selftest_end "a local run does not leave exactly the self-test rows to the Self-tests workflow" "sfl self-test skip: the default run leaves out exactly the self-test rows selftests.yml runs, counts the steps it runs and says so in one line FBP repeats; --with-selftests, SFL_WITH_SELFTESTS=1 and FBP --with-selftests run every row"
