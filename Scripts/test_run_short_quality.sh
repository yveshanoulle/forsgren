#!/usr/bin/env bash
# Scripts/test_run_short_quality.sh
#
# Self-test for Scripts/run_short_quality.sh (forsgren#230, step 2): the PRE
# gates of the short Quality a release runs on its bump commit. Every case
# runs a copy of the runner in a throwaway git repository with stub gates, a
# synthetic order file and a synthetic list of the short gates.
#   1. only the listed gates run, in the order file's order, and their rows
#      and details are written as run_ci_phase.sh writes them          -> exit 0
#   2. the header names the gate count and every gate that is not run, in the
#      output and in the step summary file ($GITHUB_STEP_SUMMARY)
#   3. a listed gate that fails: the others still run                  -> exit 1
#   4. a listed secret-class gate that fails                           -> exit 2
#   5. a gate that changes the tree is red even with exit 0            -> exit 1
#   6. a listed script that is no PRE row of the order file, a POST row, a
#      missing list, an empty list, a missing script                    -> exit 1
#   7. usage                                                            -> exit 64
# Mutation proofs: a copy that runs every row (the list ignored), one that
# does not name the gates it skipped, and one without the tree check must each
# let their case pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "run short quality self-test"

RUNNER="Scripts/run_short_quality.sh"
[[ -f "$RUNNER" ]] || selftest_abort "${RUNNER} does not exist — the short Quality of a release bump would run no gate"
[[ -x "$RUNNER" ]] || selftest_abort "${RUNNER} is not executable"

# sandbox <runner>: a fresh git repository with the runner, a tracked file and
# stub gates; sets SB.
sandbox() {
  SB="$(mktemp -d "${TMP}/sb.XXXXXX")"
  mkdir -p "${SB}/Scripts"
  cp "$1" "${SB}/Scripts/run_short_quality.sh"
  chmod +x "${SB}/Scripts/run_short_quality.sh"
  echo tracked > "${SB}/tracked.txt"
  local name
  for name in secret tests golden lint other post; do stub "$name" 0; done
  printf '%s\n' \
    'secret scan|Scripts/gate_secret.sh|pre|secret-class' \
    'Go tests|Scripts/gate_tests.sh|pre|' \
    'golden pages|Scripts/gate_golden.sh|pre|' \
    'Go lint|Scripts/gate_lint.sh|pre|' \
    'other gate|Scripts/gate_other.sh|pre|' \
    'declared n/a|n/a|none here' \
    'post gate|Scripts/gate_post.sh|post|' > "${SB}/Scripts/gate_report_order.txt"
  printf '# the short list\nScripts/gate_secret.sh\nScripts/gate_tests.sh\nScripts/gate_golden.sh\nScripts/gate_lint.sh\n' > "${SB}/Scripts/quality_bump_gates.txt"
  git -C "$SB" init -q
  git -C "$SB" add -A
  git -C "$SB" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m sandbox
}

# stub <name> <exit> [writes]: Scripts/gate_<name>.sh, tracing its own name.
stub() {
  local path="${SB}/Scripts/gate_$1.sh"
  {
    echo '#!/usr/bin/env bash'
    echo "echo \"$1\" >> \"\${STUB_TRACE:?}\""
    echo "echo \"stub output of $1\""
    if [[ -n "${3:-}" ]]; then echo 'echo changed >> tracked.txt'; fi
    echo "exit $2"
  } > "$path"
  chmod +x "$path"
}

# run_it: the runner of the sandbox; sets OUT, RC, and the summary, rows and details paths.
run_it() {
  SUMMARY="${SB}.summary"
  ROWS="${SB}.rows"
  DETAILS="${SB}.details"
  rm -rf "$SUMMARY" "$ROWS" "$DETAILS"
  : > "$SUMMARY"
  : > "${SB}.trace"
  OUT="$(STUB_TRACE="${SB}.trace" RUN_SHORT_QUALITY_ROOT="$SB" GITHUB_STEP_SUMMARY="$SUMMARY" \
    "${SB}/Scripts/run_short_quality.sh" "$ROWS" "$DETAILS" 2>&1)" && RC=0 || RC=$?
}
traced() { tr '\n' ' ' < "${SB}.trace"; }

# 1 and 2
sandbox "$RUNNER"
run_it
want_green "the listed gates pass" "all 4 gates passed"
if [[ "$(traced)" == "secret tests golden lint " ]]; then echo "  ok: only the listed gates ran, in the order file's order"; else fail "ran: $(traced), want secret tests golden lint"; fi
if [[ "$(cat "$ROWS")" == "$(printf 'secret scan|✅\nGo tests|✅\ngolden pages|✅\nGo lint|✅')" ]]; then echo "  ok: the rows are label|mark"; else fail "rows: $(cat "$ROWS")"; fi
if [[ -f "${DETAILS}/Go_tests.md" ]] && grep -qF "stub output of tests" "${DETAILS}/Go_tests.md"; then echo "  ok: the details file holds the gate's output"; else fail "no details file for Go tests"; fi
want_said "the header names the count" "short Quality for a release bump: 6 gates"
want_said "the header names the bump diff check" "bump diff check"
want_said "the header names a skipped PRE gate" "other gate"
want_said "the header names a skipped POST gate" "post gate"
if grep -qF "short Quality for a release bump: 6 gates" "$SUMMARY" && grep -qF "other gate" "$SUMMARY"; then echo "  ok: the step summary holds the same note"; else fail "the step summary lacks the note: $(cat "$SUMMARY")"; fi
if grep -qF "declared n/a" <<< "$OUT"; then fail "an n/a row is named as skipped"; else echo "  ok: an n/a row is no gate"; fi

# 3
sandbox "$RUNNER"
stub tests 1
run_it
want_exit "a listed gate fails" 1 "1 of 4 gates failed"
if [[ "$(traced)" == "secret tests golden lint " ]]; then echo "  ok: the gates after a red one still run"; else fail "ran: $(traced)"; fi
if grep -qxF 'Go tests|❌' "$ROWS"; then echo "  ok: the red row is recorded"; else fail "rows: $(cat "$ROWS")"; fi

# 4
sandbox "$RUNNER"
stub secret 1
run_it
want_exit "a secret-class gate fails" 2 "SECRET-CLASS"

# 5
sandbox "$RUNNER"
stub golden 0 writes
git -C "$SB" add -A
git -C "$SB" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m stub
run_it
want_exit "a gate that changes the tree" 1 "golden pages changed the checked-out tree"

# 6
sandbox "$RUNNER"
echo 'Scripts/gate_nowhere.sh' >> "${SB}/Scripts/quality_bump_gates.txt"
run_it
want_exit "a listed script that is no order row" 1 "Scripts/gate_nowhere.sh is no PRE row"
if [[ -z "$(traced)" ]]; then echo "  ok: nothing ran after the bad list"; else fail "gates ran after the bad list: $(traced)"; fi
sandbox "$RUNNER"
echo 'Scripts/gate_post.sh' >> "${SB}/Scripts/quality_bump_gates.txt"
run_it
want_exit "a listed POST row" 1 "Scripts/gate_post.sh is no PRE row"
sandbox "$RUNNER"
rm "${SB}/Scripts/quality_bump_gates.txt"
run_it
want_exit "a missing list" 1 "quality_bump_gates.txt"
sandbox "$RUNNER"
printf '# nothing\n' > "${SB}/Scripts/quality_bump_gates.txt"
run_it
want_exit "an empty list" 1 "lists no gate"
sandbox "$RUNNER"
rm "${SB}/Scripts/gate_lint.sh"
run_it
want_exit "a missing script" 1 "declares Scripts/gate_lint.sh, which does not exist"

# 7
sandbox "$RUNNER"
OUT="$("${SB}/Scripts/run_short_quality.sh" 2>&1)" && RC=0 || RC=$?
want_exit "no argument" 64 "usage"

# Mutation proofs.
mutant() {
  rm -rf "${TMP:?}/mut/$1"
  mkdir -p "${TMP}/mut/$1"
  selftest_mutant "$RUNNER" "${TMP}/mut/$1/run_short_quality.sh" "$2"
}
if mutant all 's/grep -qxF -- "[$]script" <<< "[$]listed" || continue/true || continue/'; then
  sandbox "${TMP}/mut/all/run_short_quality.sh"
  run_it
  if [[ "$(traced)" == *other* ]]; then echo "  ok: mutation proof: without the list every PRE row runs, and the case above catches it"; else fail "mutation proof: the mutant that ignores the list still ran only the listed gates: $(traced)"; fi
fi
if mutant silent 's/^  echo "Not run (.*$/  true/'; then
  sandbox "${TMP}/mut/silent/run_short_quality.sh"
  run_it
  if grep -qF "other gate" <<< "$OUT"; then fail "mutation proof: the mutant still names the skipped gates"; else echo "  ok: mutation proof: without the note the skipped gates are not named, and the case above catches it"; fi
fi
if mutant notree 's/elif \[ "[$]tree_after" != "[$]tree_before" \]; then/elif false; then/'; then
  sandbox "${TMP}/mut/notree/run_short_quality.sh"
  stub golden 0 writes
  git -C "$SB" add -A
  git -C "$SB" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m stub
  run_it
  want_green "mutation proof: without the tree check a gate that writes passes" "all 4 gates passed"
fi

selftest_end "the run short quality does not hold" "run short quality: only the listed gates run, the others are named, red, secret-class, tree-changing and unknown gates are judged right"
