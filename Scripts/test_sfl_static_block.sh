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
MARKS="${TMP}/marks"

# mark_gate <path> <mark>: a gate that records that it ran, in the marks
# directory named by MARKS in its environment (outside the tree).
mark_gate() {
  {
    echo '#!/usr/bin/env bash'
    echo "touch \"\${MARKS}/$2\""
  } > "$1"
}

# make_root <name> <static gate script>: a synthetic root, the order file
# below, fake gates. The static gate "static bad" runs <static gate script>.
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
  cat > "${root}/Scripts/gate_report_order.txt" <<ORDER
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
  chmod +x "${root}"/sfl.sh "${root}"/Scripts/*.sh
  printf '%s\n' "$root"
}

# run_sfl <root> <phase>
run_sfl() {
  rm -rf "$MARKS"
  mkdir -p "$MARKS"
  OUT="$(cd "$1" && MARKS="$MARKS" ./sfl.sh "$2" 2>&1)" && RC=0 || RC=$?
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

# Mutation proofs.
if selftest_mutant "$SFL_UNDER_TEST" "${TMP}/m1/sfl.sh" 's/^        STOPPED=1$/        STOPPED=0/'; then
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

selftest_end "the static block does not stop the run as the order file says" "static block: a red static gate stops sfl and FBP after the block, names every skipped gate, and CI still runs everything"
