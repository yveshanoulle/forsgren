#!/usr/bin/env bash
# Scripts/test_sfl_static_block.sh
#
# Self-test of the static block (forsgren#231, step 2). Scripts/gate_report_order.txt
# marks the fast static checks between `#! static-block-start` and
# `#! static-block-end`. When a row of the block is red:
#   - sfl.sh runs the rest of the block (every static finding is reported),
#     then no later row of the phase: each is printed as skipped, by name, is a
#     row of the step table, and the summary says "stopped after the static
#     block";
#   - FBP.sh skips the build and the POST gates, names the POST gates it
#     skipped, still commits the RED commit and exits 1;
#   - CI (Scripts/run_ci_phase.sh) does NOT stop: every row of the phase runs.
# With a green block everything runs as before.
#
# forsgren#441 (decision #440): the same stop for ANY red gate. sfl.sh stops a
# phase at its first red gate (pre and post): each later gate is printed
# skipped and named, "stopped after <label>", never counted as passed, the
# stop sink is written, a secret-class red still exits 2 and writes no sink;
# `--all` runs every gate (also past the static block); CI still runs all;
# FBP.sh reads the sink, skips the build and POST gates, commits the RED
# commit, and passes --all on to both sfl phases. Usage texts list --all.
#
# The gates are fakes in a synthetic root with a copy of the real sfl.sh and
# the real step table renderer; each later gate records that it ran in a marks
# directory outside the tree. The optional first argument is the sfl.sh under
# test (default: the real one), which is how the red state before the change
# was shown: git show HEAD~:sfl.sh > file; test_sfl_static_block.sh file.
# Mutation proofs: a block boundary the runner ignores runs the later gates
# (caught); skipped gates that are not named are caught.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_fbp_sandbox.sh
source Scripts/lib_fbp_sandbox.sh
selftest_begin "static block self-test"

SFL_UNDER_TEST="${1:-${REPO}/sfl.sh}"
# The FBP.sh under test (the optional second argument), for the red state
# before forsgren#441: git show HEAD:FBP.sh > file; test_sfl_static_block.sh sfl-file file.
FBP_UNDER_TEST="${2:-${REPO}/FBP.sh}"
MARKS="${TMP}/marks"

# mark_gate <path> <mark>: a gate that records that it ran, in the marks
# directory named by MARKS in its environment (outside the tree).
mark_gate() {
  {
    echo '#!/usr/bin/env bash'
    echo "touch \"\${MARKS}/$2\""
  } > "$1"
}

# make_root <name> <static gate script> [variant]: a synthetic root, the order
# file below, fake gates. The static gate "static bad" runs <static gate
# script>. Variants (forsgren#441): midred = the red gate is a plain row after
# a green block; secret = a red secret-class row before the block; postred =
# a red POST row followed by a marking one.
make_root() {
  local root="${TMP}/$1"
  mkdir -p "${root}/Scripts" "${root}/.build"
  cp "$SFL_UNDER_TEST" "${root}/sfl.sh"
  cp "${REPO}/Scripts/render_step_table.sh" "${REPO}/Scripts/summarize_gate_failure.sh" "${root}/Scripts/"
  printf '#!/usr/bin/env bash\nsfl_pull_or_stop() { return 0; }\n' > "${root}/Scripts/sfl_pull.sh"
  printf '#!/usr/bin/env bash\necho go1.0\n' > "${root}/Scripts/go_toolchain.sh"
  local s
  for s in install_tools check_node_pin npm_sync_install; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/Scripts/${s}.sh"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/Scripts/gate_ok.sh"
  printf '#!/usr/bin/env bash\necho "static finding"; exit 1\n' > "${root}/Scripts/gate_bad.sh"
  mark_gate "${root}/Scripts/gate_static_later.sh" static-later
  mark_gate "${root}/Scripts/gate_later_one.sh" later-one
  mark_gate "${root}/Scripts/gate_later_two.sh" later-two
  mark_gate "${root}/Scripts/gate_post_one.sh" post-one
  case "${3:-}" in
    midred) cat > "${root}/Scripts/gate_report_order.txt" <<ORDER
first gate|Scripts/gate_ok.sh|pre|
#! static-block-start
static ok|Scripts/gate_ok.sh|pre|
static later|Scripts/gate_static_later.sh|pre|
#! static-block-end
mid bad|Scripts/${2}|pre|
later one|Scripts/gate_later_one.sh|pre|
later two|Scripts/gate_later_two.sh|pre|
post one|Scripts/gate_post_one.sh|post|
ORDER
    ;;
    secret) cat > "${root}/Scripts/gate_report_order.txt" <<ORDER
secret bad|Scripts/${2}|pre|secret-class
#! static-block-start
static ok|Scripts/gate_ok.sh|pre|
static later|Scripts/gate_static_later.sh|pre|
#! static-block-end
later one|Scripts/gate_later_one.sh|pre|
later two|Scripts/gate_later_two.sh|pre|
ORDER
    ;;
    postred) cat > "${root}/Scripts/gate_report_order.txt" <<ORDER
later one|Scripts/gate_later_one.sh|pre|
post bad|Scripts/${2}|post|
post one|Scripts/gate_post_one.sh|post|
post two|Scripts/gate_later_two.sh|post|
ORDER
    ;;
    *) cat > "${root}/Scripts/gate_report_order.txt" <<ORDER
first gate|Scripts/gate_ok.sh|pre|
#! static-block-start
static ok|Scripts/gate_ok.sh|pre|
static bad|Scripts/${2}|pre|
static later|Scripts/gate_static_later.sh|pre|
#! static-block-end
later one|Scripts/gate_later_one.sh|pre|
later two|Scripts/gate_later_two.sh|pre|
post one|Scripts/gate_post_one.sh|post|
ORDER
    ;;
  esac
  chmod +x "${root}"/sfl.sh "${root}"/Scripts/*.sh
  printf '%s\n' "$root"
}

# run_sfl <root> <phase> [--all]
run_sfl() {
  rm -rf "$MARKS"
  mkdir -p "$MARKS"
  OUT="$(cd "$1" && MARKS="$MARKS" ./sfl.sh ${3:+"$3"} "$2" 2>&1)" && RC=0 || RC=$?
}

marked() { [[ -f "${MARKS}/$1" ]]; }

# Case 1: a red static gate stops the later rows, named.
root="$(make_root red gate_bad.sh)"
run_sfl "$root" pre
want_exit "1. a red static gate makes sfl exit 1" 1 "stopped after the static block"
if marked static-later; then echo "  ok: 1. the rest of the block still ran (every static finding is reported)"; else fail "1. the rest of the block did not run: a second static finding would stay hidden"; fi
if marked later-one || marked later-two; then
  fail "1. a gate after the static block ran although the block is red. Output: ${OUT}"
else
  echo "  ok: 1. no gate after the static block ran"
fi
want_said "1. the first skipped gate is named" "⏭ skipped: later one (stopped after the static block)"
want_said "1. the second skipped gate is named" "⏭ skipped: later two (stopped after the static block)"
want_said "1. the step table names a skipped row" "later two"
want_said "1. the table counts the skipped rows" "2 skipped"
want_said "1. the failed static gate is listed" "static bad ❌"
if [[ -s "${root}/.build/sfl-static-stop.log" ]]; then echo "  ok: 1. the stop sink FBP.sh reads is written"; else fail "1. no .build/sfl-static-stop.log: FBP.sh could not tell the block stopped the run"; fi

# Case 2: a green block changes nothing.
root="$(make_root green gate_ok.sh)"
run_sfl "$root" pre
want_green "2. a green static block lets the run go green" "sfl pre green"
if marked later-one && marked later-two; then echo "  ok: 2. the later gates ran"; else fail "2. a green static block skipped later gates"; fi
if [[ -e "${root}/.build/sfl-static-stop.log" ]]; then fail "2. a stop sink was written for a green block"; else echo "  ok: 2. no stop sink for a green block"; fi

# Case 3: the POST phase has no block and keeps running its rows.
root="$(make_root post gate_bad.sh)"
run_sfl "$root" post
if marked post-one; then echo "  ok: 3. the post phase runs its rows"; else fail "3. the post phase skipped its row. Output: ${OUT}"; fi

# Case 4: CI does not stop: run_ci_phase.sh runs every row after a red static gate.
root="$(make_root ci gate_bad.sh)"
git -C "$root" init -q
cp "${REPO}/Scripts/run_ci_phase.sh" "${root}/Scripts/"
git -C "$root" add -A
git -C "$root" -c user.name=t -c user.email=t@example.invalid commit -q -m base
rm -rf "$MARKS"; mkdir -p "$MARKS"
capture env MARKS="$MARKS" RUN_CI_PHASE_ROOT="$root" "${root}/Scripts/run_ci_phase.sh" pre "${TMP}/ci-rows" "${TMP}/ci-details"
want_red "4. CI reports the red static gate" "static bad"
if marked later-one && marked later-two; then echo "  ok: 4. CI runs the gates after a red static block (a pull request shows all its reds)"; else fail "4. CI stopped after the static block; it must run every row. Output: ${OUT}"; fi

# Case 5: the real order file: the block holds exactly these pairs, each
# self-test directly before its gate (the canon rule holds inside the block).
block="$(awk -F'|' '/^#! static-block-start/ {on=1; next} /^#! static-block-end/ {on=0} on && $0 !~ /^#/ {print $2}' Scripts/gate_report_order.txt | tr '\n' ',')"
want_block="Scripts/test_check_gofmt.sh,Scripts/check_gofmt.sh,Scripts/test_check_go_lint.sh,Scripts/check_go_lint.sh,Scripts/test_check_actionlint.sh,Scripts/test_check_actionlint_forsgren.sh,Scripts/check_actionlint.sh,Scripts/test_check_shellcheck.sh,Scripts/check_shellcheck.sh,Scripts/test_check_yamllint.sh,Scripts/check_yamllint.sh,Scripts/test_check_zizmor.sh,Scripts/check_zizmor.sh,"
if [[ "$block" == "$want_block" ]]; then
  echo "  ok: 5. the real static block is the six gates, each directly after its self-test (actionlint after two)"
else
  fail "5. the static block of Scripts/gate_report_order.txt is '${block}', want '${want_block}'"
fi
if [[ "$(grep -c '^#! static-block-' Scripts/gate_report_order.txt)" == 2 ]]; then echo "  ok: 5. exactly two markers"; else fail "5. the order file must hold exactly one start and one end marker"; fi

# Case 6: FBP.sh with a PRE that stopped after the static block.
ORDER_FOR_FBP="${TMP}/fbp-order.txt"
cat > "$ORDER_FOR_FBP" <<'ORDER'
static bad|Scripts/check_gofmt.sh|pre|
later one|Scripts/x.sh|pre|
post one|Scripts/y.sh|post|
post two|Scripts/z.sh|post|
ORDER
FBP_SANDBOX_ORDER_FILE="$ORDER_FOR_FBP" FBP_SANDBOX_SFL_STATIC_STOP="stopped after the static block: 1 gate(s) skipped" \
  FBP_SANDBOX_SFL_PRE_RC=1 FBP_SANDBOX_SFL_PRE_OUTPUT=$'Errors:\n  gofmt ❌\n' \
  fbp_sandbox_run 3 "static stop"
FBP_OUT="$FBP_SANDBOX_OUT"
if [[ "$FBP_SANDBOX_RC" == 1 ]]; then echo "  ok: 6. FBP.sh exits 1"; else fail "6. FBP.sh exited ${FBP_SANDBOX_RC}. Output: ${FBP_OUT}"; fi
OUT="$FBP_OUT"
want_said "6. FBP.sh says the build is skipped for the static block" "Skipping build: stopped after the static block"
want_said "6. FBP.sh names the first skipped POST gate" "⏭ skipped: post one"
want_said "6. FBP.sh names the second skipped POST gate" "⏭ skipped: post two"
if grep -qF "pages generated" <<< "$FBP_OUT"; then fail "6. the build ran after a red static block"; else echo "  ok: 6. the build did not run"; fi
if [[ "$FBP_SANDBOX_COMMIT_MSG" == *"*** RED ****"* ]]; then echo "  ok: 6. the RED commit is made as for any red"; else fail "6. no RED commit. Message: ${FBP_SANDBOX_COMMIT_MSG}"; fi

# --- forsgren#441: the stop at the first red gate, any gate ---------------

# Case 7: a red gate outside the static block stops the phase, named.
root="$(make_root mid gate_bad.sh midred)"
run_sfl "$root" pre
want_exit "7. a red plain gate makes sfl exit 1" 1 "sfl pre failed, stopped after mid bad"
if marked later-one || marked later-two; then
  fail "7. a gate after the red gate ran. Output: ${OUT}"
else
  echo "  ok: 7. no gate after the red gate ran"
fi
want_said "7. the first skipped gate is named with the stop" "⏭ skipped: later one (stopped after mid bad)"
want_said "7. the second skipped gate is named with the stop" "⏭ skipped: later two (stopped after mid bad)"
want_said "7. the table counts the skipped rows" "2 skipped"
want_said "7. the summary names the gate it stopped after" "stopped after mid bad (2 later gate(s) skipped, named above)"
if grep -E '^later (one|two)[[:space:]].*pass' <<< "$OUT" > /dev/null; then fail "7. a skipped gate is shown as passed. Output: ${OUT}"; else echo "  ok: 7. a skipped gate is never shown as passed"; fi
sink_text="$(cat "${root}/.build/sfl-static-stop.log" 2>/dev/null || true)"
if [[ "$sink_text" == "stopped after mid bad: 2 gate(s) skipped" ]]; then echo "  ok: 7. the stop sink FBP.sh reads names the gate"; else fail "7. the stop sink says '${sink_text}'"; fi

# Case 8: --all runs every gate past the red one (and past the static block).
root="$(make_root all gate_bad.sh midred)"
run_sfl "$root" pre --all
want_exit "8. --all with a red gate still exits 1" 1 "sfl pre failed"
if marked later-one && marked later-two; then echo "  ok: 8. --all ran the gates after the red gate"; else fail "8. --all stopped at the red gate. Output: ${OUT}"; fi
if grep -qF "⏭ skipped" <<< "$OUT"; then fail "8. --all skipped a gate. Output: ${OUT}"; else echo "  ok: 8. --all skipped nothing"; fi
if [[ -e "${root}/.build/sfl-static-stop.log" ]]; then fail "8. --all wrote a stop sink"; else echo "  ok: 8. --all wrote no stop sink"; fi
root="$(make_root allblock gate_bad.sh)"
run_sfl "$root" pre --all
if marked later-one && marked later-two; then echo "  ok: 8. --all runs past a red static block too"; else fail "8. --all stopped at a red static block. Output: ${OUT}"; fi
run_sfl "$root" --all pre
if marked later-one; then echo "  ok: 8. --all is read before the phase too"; else fail "8. --all before the phase was not read. Output: ${OUT}"; fi

# Case 9: a secret-class red stops too, exits 2, and writes no sink (FBP.sh commits nothing).
root="$(make_root secret gate_bad.sh secret)"
run_sfl "$root" pre
want_exit "9. a red secret-class gate exits 2" 2 "SECRET-CLASS"
if marked static-later || marked later-one; then fail "9. a gate ran after the secret-class red. Output: ${OUT}"; else echo "  ok: 9. the gates after a secret-class red are skipped"; fi
want_said "9. they are named" "⏭ skipped: later one (stopped after secret bad)"
if [[ -e "${root}/.build/sfl-static-stop.log" ]]; then fail "9. a secret-class red wrote the stop sink: FBP.sh would commit"; else echo "  ok: 9. no stop sink for a secret-class red"; fi

# Case 10: the POST phase stops at its first red gate too.
root="$(make_root postred gate_bad.sh postred)"
run_sfl "$root" post
want_exit "10. a red POST gate makes sfl post exit 1" 1 "stopped after post bad"
if marked post-one || marked later-two; then fail "10. a POST gate ran after the red POST gate. Output: ${OUT}"; else echo "  ok: 10. the POST gates after the red one did not run"; fi
want_said "10. the skipped POST gate is named" "⏭ skipped: post one (stopped after post bad)"

# Case 11: CI still runs every row after a red plain gate.
root="$(make_root ci2 gate_bad.sh midred)"
git -C "$root" init -q
cp "${REPO}/Scripts/run_ci_phase.sh" "${root}/Scripts/"
git -C "$root" add -A
git -C "$root" -c user.name=t -c user.email=t@example.invalid commit -q -m base
rm -rf "$MARKS"; mkdir -p "$MARKS"
capture env MARKS="$MARKS" RUN_CI_PHASE_ROOT="$root" "${root}/Scripts/run_ci_phase.sh" pre "${TMP}/ci2-rows" "${TMP}/ci2-details"
want_red "11. CI reports the red plain gate" "mid bad"
if marked later-one && marked later-two; then echo "  ok: 11. CI runs the gates after a red plain gate"; else fail "11. CI stopped at a red gate; it must run every row. Output: ${OUT}"; fi

# Case 12: FBP.sh with a PRE that stopped after a plain gate.
cat > "$ORDER_FOR_FBP" <<'ORDER'
mid bad|Scripts/check_gofmt.sh|pre|
later one|Scripts/x.sh|pre|
post one|Scripts/y.sh|post|
post two|Scripts/z.sh|post|
ORDER
FBP_SANDBOX_FBP_OVERRIDE="$FBP_UNDER_TEST" FBP_SANDBOX_ORDER_FILE="$ORDER_FOR_FBP" FBP_SANDBOX_SFL_STATIC_STOP="stopped after mid bad: 1 gate(s) skipped" \
  FBP_SANDBOX_SFL_PRE_RC=1 FBP_SANDBOX_SFL_PRE_OUTPUT=$'Errors:\n  mid bad ❌\n' \
  fbp_sandbox_run 3 "plain stop"
OUT="$FBP_SANDBOX_OUT"
if [[ "$FBP_SANDBOX_RC" == 1 ]]; then echo "  ok: 12. FBP.sh exits 1"; else fail "12. FBP.sh exited ${FBP_SANDBOX_RC}. Output: ${OUT}"; fi
want_said "12. FBP.sh skips the build, naming the stop" "Skipping build: stopped after mid bad"
want_said "12. FBP.sh skips the POST gates, naming the stop" "Skipping POST gates: stopped after mid bad"
want_said "12. FBP.sh names the skipped POST gates" "⏭ skipped: post two"
if grep -qF "pages generated" <<< "$OUT"; then fail "12. the build ran after a red gate"; else echo "  ok: 12. the build did not run"; fi
if [[ "$FBP_SANDBOX_COMMIT_MSG" == *"*** RED ****"* ]]; then echo "  ok: 12. the RED commit is made locally"; else fail "12. no RED commit. Message: ${FBP_SANDBOX_COMMIT_MSG}"; fi

# Case 13: a secret-class red in FBP.sh still commits nothing.
FBP_SANDBOX_FBP_OVERRIDE="$FBP_UNDER_TEST" FBP_SANDBOX_ORDER_FILE="$ORDER_FOR_FBP" FBP_SANDBOX_SFL_PRE_RC=2 FBP_SANDBOX_SFL_PRE_OUTPUT=$'Errors:\n  secret scan ❌\n' \
  fbp_sandbox_run 3 "secret stop"
if [[ "$FBP_SANDBOX_RC" == 1 && -z "$FBP_SANDBOX_COMMIT_SHA" ]]; then echo "  ok: 13. a secret-class red commits nothing"; else fail "13. rc ${FBP_SANDBOX_RC}, commit '${FBP_SANDBOX_COMMIT_MSG}'"; fi

# Case 14: --all reaches both sfl phases of FBP.sh (the stub prints its arguments).
FBP_SANDBOX_FBP_OVERRIDE="$FBP_UNDER_TEST" FBP_SANDBOX_SFL_LOG_ARGS=1 fbp_sandbox_run 3 "all flag" --all --no-commit
OUT="$FBP_SANDBOX_OUT"
want_said "14. sfl pre got --all" "stub sfl args: pre --all"
want_said "14. sfl post got --all" "stub sfl args: post --all"
FBP_SANDBOX_FBP_OVERRIDE="$FBP_UNDER_TEST" FBP_SANDBOX_SFL_LOG_ARGS=1 fbp_sandbox_run 3 "default" --no-commit
OUT="$FBP_SANDBOX_OUT"
if grep -qxF "stub sfl args: pre" <<< "$OUT" && ! grep -qF -- "--all" <<< "$OUT"; then echo "  ok: 14. without --all sfl gets no flag"; else fail "14. a run without --all passed a flag on. Output: ${OUT}"; fi

# Case 15: the usage texts list --all.
capture "$SFL_UNDER_TEST"
want_said "15. the sfl usage lists --all" "--all"
capture "$FBP_UNDER_TEST"
want_said "15. the FBP usage lists --all" "--all"

# Mutation proofs.
if selftest_mutant "$SFL_UNDER_TEST" "${TMP}/m1/sfl.sh" 's/^        STOPPED=1$/        STOPPED=0/;s/^    STOPPED=1$/    STOPPED=0/'; then
  SFL_UNDER_TEST_REAL="$SFL_UNDER_TEST"
  SFL_UNDER_TEST="${TMP}/m1/sfl.sh"
  root="$(make_root mr1 gate_bad.sh)"
  run_sfl "$root" pre
  SFL_UNDER_TEST="$SFL_UNDER_TEST_REAL"
  if marked later-one; then
    echo "  ok: mutation proof: a block boundary the runner ignores runs the later gates, which case 1 catches"
  else
    fail "mutation proof: with the boundary ignored the later gates still did not run: case 1 does not depend on it"
  fi
fi
if selftest_mutant "$SFL_UNDER_TEST" "${TMP}/m2/sfl.sh" '/echo "⏭ skipped: /d'; then
  SFL_UNDER_TEST_REAL="$SFL_UNDER_TEST"
  SFL_UNDER_TEST="${TMP}/m2/sfl.sh"
  root="$(make_root mr2 gate_bad.sh)"
  run_sfl "$root" pre
  SFL_UNDER_TEST="$SFL_UNDER_TEST_REAL"
  if grep -qF "⏭ skipped: later one" <<< "$OUT"; then
    fail "mutation proof: skipped gates were still named without the line that names them"
  else
    echo "  ok: mutation proof: skipped gates that are not named leave no 'skipped: later one' line, which case 1 catches"
  fi
fi

# forsgren#441 mutation proofs: without the generic stop a red plain gate lets
# the later gates run (case 7 catches it); with --all ignored they stop (case 8);
# FBP.sh that does not pass --all on loses it (case 14).
if selftest_mutant "$SFL_UNDER_TEST" "${TMP}/m3/sfl.sh" 's/^    STOPPED=1$/    STOPPED=0/'; then
  SFL_UNDER_TEST_REAL="$SFL_UNDER_TEST"; SFL_UNDER_TEST="${TMP}/m3/sfl.sh"
  root="$(make_root mr3 gate_bad.sh midred)"
  run_sfl "$root" pre
  SFL_UNDER_TEST="$SFL_UNDER_TEST_REAL"
  if marked later-one; then echo "  ok: mutation proof: without the generic stop the later gates run, which case 7 catches"; else fail "mutation proof: case 7 does not depend on the generic stop"; fi
fi
if selftest_mutant "$SFL_UNDER_TEST" "${TMP}/m4/sfl.sh" 's/--all) RUN_ALL=1 ;;/--all) RUN_ALL=0 ;;/'; then
  SFL_UNDER_TEST_REAL="$SFL_UNDER_TEST"; SFL_UNDER_TEST="${TMP}/m4/sfl.sh"
  root="$(make_root mr4 gate_bad.sh midred)"
  run_sfl "$root" pre --all
  SFL_UNDER_TEST="$SFL_UNDER_TEST_REAL"
  if marked later-one; then fail "mutation proof: --all ignored still ran the later gates: case 8 does not depend on it"; else echo "  ok: mutation proof: an ignored --all stops at the red gate, which case 8 catches"; fi
fi
if selftest_mutant "$FBP_UNDER_TEST" "${TMP}/m5/FBP.sh" 's/SFL_ALL_ARG=(--all)/SFL_ALL_ARG=()/'; then
  FBP_SANDBOX_FBP_OVERRIDE="${TMP}/m5/FBP.sh" FBP_SANDBOX_SFL_LOG_ARGS=1 fbp_sandbox_run 3 "mutant all" --all --no-commit
  if grep -qF "stub sfl args: pre --all" <<< "$FBP_SANDBOX_OUT"; then fail "mutation proof: FBP.sh that drops --all still passed it on"; else echo "  ok: mutation proof: FBP.sh that drops --all is caught by case 14"; fi
fi

selftest_end "the static block does not stop the run as the order file says" "static block: a red static gate stops sfl and FBP after the block, names every skipped gate, and CI still runs everything"
