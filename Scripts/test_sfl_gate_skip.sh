#!/usr/bin/env bash
# Scripts/test_sfl_gate_skip.sh (forsgren#262, step 3 of 3). Not canon: forsgren only.
#
# Self-test of sfl.sh skipping an unselected browser row. A row whose label has
# `in` rows in Scripts/gate_inputs.txt (the four browser rows) is asked
# gate_select (Scripts/lib_gate_select.sh) before it runs. On `skip: <reason>`
# sfl.sh does not run its script; the step is still counted, it is printed as
# `⏭ skipped: <label> (<reason>)`, it is a `⏭ skip` row of the step table, and
# `<label><TAB><reason>` is appended to .build/sfl-skips.log, which `sfl.sh pre`
# empties first (forsgren#266 reads it). A selected row runs as before. CI
# (Scripts/run_ci_phase.sh) does not select: it runs every row.
#
# The gates are fakes in a throwaway repository with a copy of the real sfl.sh,
# the real library and the real step table renderer, a made-up list and an
# origin/main at the fixture's first commit; each gate records that it ran in a
# marks directory outside the tree. Cases:
#   1. only a docs file changed          -> all four skip, named, logged; the rest runs
#   2. a file under the gate inputs      -> the two gates run, the two self-tests skip
#   3. FORSGREN_GATE_SELECT_FULL=1       -> all four run, nothing logged; a stale log is emptied
#   4. CI (run_ci_phase.sh), docs change -> all four run
# The optional first argument is the sfl.sh under test (default: the real one).
#   5. FBP.sh's summary (forsgren#266): the gates the selection skipped, counted and
#      each named with its reason; nothing when none were skipped.
# Mutation proofs (each asserts the reason the real sfl.sh gives is gone):
#   A. the skip ignored:       case 1 runs the self-test and no longer names the reason;
#   B. no line in the log:     case 1 leaves no reason in .build/sfl-skips.log;
#   C. the log never emptied:  case 3 keeps a stale reason in .build/sfl-skips.log;
#   D. FBP.sh never reads the log: case 5 names no skipped gate.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_fbp_sandbox.sh
source Scripts/lib_fbp_sandbox.sh
selftest_begin "sfl gate skip self-test"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
SFL_UNDER_TEST="${1:-${REPO}/sfl.sh}"
MARKS="${TMP}/marks"
BST="browser gate self-test"
FST="browser gate (fixture site) self-test"
BG="browser gate"
FG="browser gate (fixture site)"

# mark_gate <path> <mark>: a gate that records that it ran.
mark_gate() {
  {
    echo '#!/usr/bin/env bash'
    echo "touch \"\${MARKS}/$1\""
  } > "$2"
}

# make_root <name>: a throwaway repository with origin/main at its first commit.
make_root() {
  local root="${TMP}/$1" s
  mkdir -p "${root}/Scripts" "${root}/.build" "${root}/docs" "${root}/site"
  cp "$SFL_UNDER_TEST" "${root}/sfl.sh"
  cp "${REPO}/Scripts/render_step_table.sh" "${REPO}/Scripts/summarize_gate_failure.sh" \
    "${REPO}/Scripts/lib_gate_select.sh" "${REPO}/Scripts/run_ci_phase.sh" "${root}/Scripts/"
  printf '#!/usr/bin/env bash\nsfl_pull_or_stop() { return 0; }\n' > "${root}/Scripts/sfl_pull.sh"
  printf '#!/usr/bin/env bash\necho go1.0\n' > "${root}/Scripts/go_toolchain.sh"
  for s in install_tools check_node_pin npm_sync_install; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/Scripts/${s}.sh"
  done
  mark_gate other-pre "${root}/Scripts/gate_other_pre.sh"
  mark_gate other-post "${root}/Scripts/gate_other_post.sh"
  mark_gate bst "${root}/Scripts/fake_browser_selftest.sh"
  mark_gate fst "${root}/Scripts/fake_fixture_selftest.sh"
  mark_gate bg "${root}/Scripts/fake_browser_gate.sh"
  mark_gate fg "${root}/Scripts/fake_fixture_gate.sh"
  cat > "${root}/Scripts/gate_report_order.txt" <<ORDER
other pre|Scripts/gate_other_pre.sh|pre|
${BST}|Scripts/fake_browser_selftest.sh|pre|
${FST}|Scripts/fake_fixture_selftest.sh|pre|
${BG}|Scripts/fake_browser_gate.sh|post|
${FG}|Scripts/fake_fixture_gate.sh|post|
other post|Scripts/gate_other_post.sh|post|
ORDER
  cat > "${root}/Scripts/gate_inputs.txt" <<INPUTS
none|out|docs/**
${BST}|in|Scripts/fake_browser_selftest.sh
${FST}|in|Scripts/fake_fixture_selftest.sh
${BG}|in|Scripts/fake_browser_gate.sh
${BG}|in|site/
${FG}|in|Scripts/fake_fixture_gate.sh
${FG}|in|site/
INPUTS
  echo 'page' > "${root}/site/page.txt"
  echo 'doc' > "${root}/docs/note.txt"
  printf '.build/\n' > "${root}/.gitignore"
  chmod +x "${root}"/sfl.sh "${root}"/Scripts/*.sh
  git -C "$root" init -q -b main
  git -C "$root" add -A
  git -C "$root" -c user.name=t -c user.email=t@example.invalid commit -q -m base
  git -C "$root" update-ref refs/remotes/origin/main HEAD
  printf '%s\n' "$root"
}

# run_sfl <root> <phase> [VAR=value...]: sfl.sh as FBP runs it, outside Quality.
run_sfl() {
  local root="$1" phase="$2"
  shift 2
  OUT="$(cd "$root" && env -u GITHUB_ACTIONS -u FORSGREN_GATE_SELECT_FULL MARKS="$MARKS" "$@" ./sfl.sh "$phase" 2>&1)" && RC=0 || RC=$?
}

# run_both <root> [VAR=value...]: pre then post, the marks cleared first.
run_both() {
  rm -rf "$MARKS"
  mkdir -p "$MARKS"
  run_sfl "$1" pre "${@:2}"
  PRE_OUT="$OUT" PRE_RC="$RC"
  run_sfl "$1" post "${@:2}"
  POST_OUT="$OUT" POST_RC="$RC"
  OUT="${PRE_OUT}"$'\n'"${POST_OUT}"
}

marked() { [[ -f "${MARKS}/$1" ]]; }
skips_log() { cat "$1/.build/sfl-skips.log" 2> /dev/null || true; }

# check_ran <case> <mark> <label>
check_ran() {
  if marked "$2"; then echo "  ok: $1 ${3} ran"; else fail "$1 ${3} did not run. Output: ${OUT}"; fi
}

# check_skipped <case> <root> <mark> <label>: not run, named with its reason, logged.
check_skipped() {
  local reason="none of the 1 changed files is an input of $4"
  if marked "$3"; then fail "$1 ${4} ran although no input of it changed. Output: ${OUT}"; else echo "  ok: $1 ${4} did not run"; fi
  want_said "$1 ${4} is named as skipped, with the reason" "⏭ skipped: ${4} (${reason})"
  if grep -qxF -- "${4}"$'\t'"${reason}" <<< "$(skips_log "$2")"; then
    echo "  ok: $1 ${4} and its reason are in .build/sfl-skips.log"
  else
    fail "$1 .build/sfl-skips.log has no line '${4}<TAB>${reason}'. Log: $(skips_log "$2")"
  fi
}

# Case 1: only a docs file changed: all four browser rows skip.
root="$(make_root docs)"
echo 'changed' >> "${root}/docs/note.txt"
run_both "$root"
for pair in "bst|${BST}" "fst|${FST}" "bg|${BG}" "fg|${FG}"; do
  check_skipped "1." "$root" "${pair%%|*}" "${pair#*|}"
done
check_ran "1." other-pre "other pre"
check_ran "1." other-post "other post"
if [[ "$PRE_RC" == 0 && "$POST_RC" == 0 ]]; then echo "  ok: 1. both phases are green (the skipped steps are counted)"; else fail "1. sfl exited pre ${PRE_RC}, post ${POST_RC}. Output: ${OUT}"; fi
want_said "1. the step table counts the skipped rows" "2 skipped"
want_said "1. a skipped row of the step table says why" "⏭ skip: no changed file is an input"
if [[ "$(skips_log "$root" | grep -c .)" == 4 ]]; then echo "  ok: 1. the log holds the four skips of pre and post"; else fail "1. .build/sfl-skips.log does not hold four lines: $(skips_log "$root")"; fi

# Case 2: a file under the gates' inputs: the gates run, the self-tests skip.
root="$(make_root site)"
echo 'changed' >> "${root}/site/page.txt"
run_both "$root"
check_ran "2." bg "$BG"
check_ran "2." fg "$FG"
check_skipped "2." "$root" bst "$BST"
check_skipped "2." "$root" fst "$FST"
if skips_log "$root" | has -q "^${BG}"$'\t'; then fail "2. a selected gate is in .build/sfl-skips.log"; else echo "  ok: 2. no selected gate is logged as skipped"; fi

# Case 3: forced full run: all four run, and pre empties a stale log.
root="$(make_root full)"
echo 'changed' >> "${root}/docs/note.txt"
printf 'stale gate\tstale reason\n' > "${root}/.build/sfl-skips.log"
run_both "$root" FORSGREN_GATE_SELECT_FULL=1
for pair in "bst|${BST}" "fst|${FST}" "bg|${BG}" "fg|${FG}"; do
  check_ran "3." "${pair%%|*}" "${pair#*|}"
done
if [[ -z "$(skips_log "$root")" ]]; then echo "  ok: 3. sfl pre emptied the stale .build/sfl-skips.log"; else fail "3. .build/sfl-skips.log is not empty: $(skips_log "$root")"; fi

# Case 4: CI does not select: run_ci_phase.sh runs all four on a docs-only change.
root="$(make_root ci)"
echo 'changed' >> "${root}/docs/note.txt"
rm -rf "$MARKS"
mkdir -p "$MARKS"
for phase in pre post; do
  capture env -u GITHUB_ACTIONS -u FORSGREN_GATE_SELECT_FULL MARKS="$MARKS" RUN_CI_PHASE_ROOT="$root" \
    "${root}/Scripts/run_ci_phase.sh" "$phase" "${TMP}/ci-rows-${phase}" "${TMP}/ci-details-${phase}"
done
for pair in "bst|${BST}" "fst|${FST}" "bg|${BG}" "fg|${FG}"; do
  check_ran "4. CI:" "${pair%%|*}" "${pair#*|}"
done
if grep -qE 'gate_select|lib_gate_select' Scripts/run_ci_phase.sh; then
  fail "4. Scripts/run_ci_phase.sh names the gate selection: Quality must run every row"
else
  echo "  ok: 4. Scripts/run_ci_phase.sh names no gate selection"
fi

# Case 5 (forsgren#266): FBP.sh's summary lists the gates sfl skipped by selection, each
# with its reason, so a skipped gate is never read as a passed one. The stub sfl.sh
# writes .build/sfl-skips.log; the real FBP.sh prints the summary.
SKIP_LINES="${BST}"$'\t'"none of the 3 changed files is an input of ${BST}"$'\n'"${BG}"$'\t'"none of the 3 changed files is an input of ${BG}"
fbp_summary() {
  FBP_SANDBOX_SFL_SKIPS="$1" fbp_sandbox_run 3 --no-commit
  OUT="$FBP_SANDBOX_OUT"
}
fbp_summary "$SKIP_LINES"
want_said "5. the FBP summary counts the gates skipped by selection" "gates skipped by selection: 2 (no changed file is an input of them; counted in the skipped totals above)"
want_said "5. the FBP summary names the first skipped gate with its reason" "  ⏭ skipped: ${BST} (none of the 3 changed files is an input of ${BST})"
want_said "5. the FBP summary names the second skipped gate with its reason" "  ⏭ skipped: ${BG} (none of the 3 changed files is an input of ${BG})"
fbp_summary ""
if grep -qF "skipped by selection" <<< "$OUT"; then fail "5. the FBP summary names skipped gates although sfl skipped none"; else echo "  ok: 5. a run that skipped nothing names nothing"; fi

# Mutation proofs. mutant_case1 <sed> / mutant_case3 <sed>: the case run against a mutant.
mutant_root() {
  local real="$SFL_UNDER_TEST"
  SFL_UNDER_TEST="$2"
  root="$(make_root "$1")"
  SFL_UNDER_TEST="$real"
}
REASON_BST="none of the 1 changed files is an input of ${BST}"
if selftest_mutant "$SFL_UNDER_TEST" "${TMP}/mA/sfl.sh" 's/== skip:\* \]\]/== never-a-skip \]\]/'; then
  mutant_root mA "${TMP}/mA/sfl.sh"
  echo 'changed' >> "${root}/docs/note.txt"
  run_both "$root"
  if marked bst && ! grep -qF "⏭ skipped: ${BST} (${REASON_BST})" <<< "$OUT"; then
    echo "  ok: mutation proof A: with the skip ignored the self-test runs and its reason is gone, which case 1 catches"
  else
    fail "mutation proof A: with the skip ignored the self-test still did not run or still said '${REASON_BST}'"
  fi
fi
if selftest_mutant "$SFL_UNDER_TEST" "${TMP}/mB/sfl.sh" '/>> ".SKIPS_SINK"/d'; then
  mutant_root mB "${TMP}/mB/sfl.sh"
  echo 'changed' >> "${root}/docs/note.txt"
  run_both "$root"
  if skips_log "$root" | has -qF "$REASON_BST"; then
    fail "mutation proof B: the reason reached .build/sfl-skips.log without the line that writes it"
  else
    echo "  ok: mutation proof B: without the log line no reason reaches .build/sfl-skips.log, which case 1 catches"
  fi
fi
if selftest_mutant "$SFL_UNDER_TEST" "${TMP}/mC/sfl.sh" '/^  : > ".SKIPS_SINK"$/d'; then
  mutant_root mC "${TMP}/mC/sfl.sh"
  echo 'changed' >> "${root}/docs/note.txt"
  printf 'stale gate\tstale reason\n' > "${root}/.build/sfl-skips.log"
  run_both "$root" FORSGREN_GATE_SELECT_FULL=1
  if skips_log "$root" | has -qF "stale reason"; then
    echo "  ok: mutation proof C: a log pre never empties keeps a stale reason, which case 3 catches"
  else
    fail "mutation proof C: the stale reason is gone although nothing empties the log"
  fi
fi

if selftest_mutant "${REPO}/FBP.sh" "${TMP}/mD/FBP.sh" '/sfl-skips[.]log/d'; then
  FBP_SANDBOX_FBP_OVERRIDE="${TMP}/mD/FBP.sh" fbp_summary "$SKIP_LINES"
  if grep -qF "⏭ skipped: ${BST} (" <<< "$OUT"; then
    fail "mutation proof D: a FBP.sh that never reads .build/sfl-skips.log still named the skipped gate"
  else
    echo "  ok: mutation proof D: a FBP.sh that never reads .build/sfl-skips.log names no skipped gate, which case 5 catches"
  fi
fi

selftest_end "sfl.sh does not skip an unselected browser row as it should" "sfl gate skip: an unselected browser row is not run, counted, named with its reason and logged; a selected one runs; CI runs all four"
