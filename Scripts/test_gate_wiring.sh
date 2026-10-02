#!/usr/bin/env bash
# Scripts/test_gate_wiring.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# Every gate must be wired into BOTH runners, sfl.sh and CI — the sfl/CI
# parity guard.
#
# Ported from konenki-website 2026-10-01 (forsgren#1, ladder step 14), its
# unit 396 and issues #13, #15 and #18 (issue numbers below are konenki's
# unless they say forsgren). ADAPTED, because the two repos wire CI the
# opposite way. konenki names each gate in its own quality.yml step, so its
# check asks, per script, "does sfl's order file name it, and does a
# quality.yml step run it?". forsgren's quality.yml names no gate: it runs
# Scripts/gate_report_order.txt through Scripts/run_ci_phase.sh, phase by
# phase, as sfl.sh does. So the question becomes whether both runners read
# every row the same way, and this check answers it in five parts:
#
#   1. ROWS. Every runnable row of the order file has phase `pre` or `post`
#      and class empty or `secret-class`. Both runners run only pre and post
#      rows, so a row with any other phase ("Pre", "build", a typo, nothing)
#      runs in NEITHER, and nothing else reports it missing.
#   2. RUNNERS. FBP.sh runs `./sfl.sh pre`, Scripts/build_site.sh and
#      `./sfl.sh post`, in that order; quality.yml runs
#      `Scripts/run_ci_phase.sh pre`, Scripts/build_site.sh and
#      `Scripts/run_ci_phase.sh post`, in that order, then the report. And
#      sfl.sh and run_ci_phase.sh carry the same row rules, line for line.
#   3. SCRIPTS OUTSIDE THE ORDER FILE. Every Scripts/*.sh that is not a
#      fixture is either named by an order-file row (then parts 1 and 2 run
#      it in both), or a declared exemption, each with its reason and the
#      runner it must still be invoked by. Anything else is a validator
#      nobody runs. (That every Scripts/test_*.sh is named by a row is
#      Scripts/test_sfl_drives_from_order_file.sh's pin 4, not repeated here.)
#   4. THE CI LOOP, AT RUNTIME. run_ci_phase.sh, over the REAL order file
#      with a stub at every declared path, runs every runnable row exactly
#      once across its two phases, each in its own phase, in file order; and
#      over synthetic order files it skips what sfl skips, keeps going after
#      a failure, exits 2 on a secret-class failure, is red on a phase with
#      no row, on a non-executable script and on a gate that changes the
#      checked-out tree, and survives GitHub's `bash -e -o pipefail`.
#   5. PROOFS. Mutation proofs re-run this whole check against a copy of a
#      runner (or of the order file) with one invocation commented out or one
#      rule broken, and require the rejection by name; konenki's matcher
#      self-proof feeds runs_script its sample files.
#
# The failure this prevents is silent in the direction that matters: a gate
# that runs only in sfl still passes locally, so it looks wired. It is CI
# that stops running it, and CI is the gatekeeper.
#
# Only a word that RUNS something counts as an invocation (runs_script,
# konenki issues #13, #15 and #18): the script must stand where a command
# stands, so a script that is only mentioned (in a comment, an echo, a YAML
# name: or as another command's argument) is not wired. runs_script lives in
# Scripts/lib_runs_script.sh, byte-identical with konenki's.

# The runner paths are overridable ONLY so the mutation proofs in part 5 can
# re-run this whole check against a mutated copy of sfl.sh, FBP.sh,
# quality.yml, dco.yml or the order file. Nothing else sets them; sfl and CI
# always run against the real files.
SFL="${GATE_WIRING_SFL_OVERRIDE:-sfl.sh}"
FBP="${GATE_WIRING_FBP_OVERRIDE:-FBP.sh}"
CI="${GATE_WIRING_CI_OVERRIDE:-.github/workflows/quality.yml}"
ORDER="${GATE_WIRING_ORDER_OVERRIDE:-Scripts/gate_report_order.txt}"
DCO_WF="${GATE_WIRING_DCO_OVERRIDE:-.github/workflows/dco.yml}"
CI_RUNNER="Scripts/run_ci_phase.sh"

# is_mutation_rerun: this run is a proof re-running the check with one of
# the files above replaced, so it must not start proofs of its own, nor
# repeat the runtime cases of part 4, which do not read those files.
is_mutation_rerun() {
  [[ -n "${GATE_WIRING_CI_OVERRIDE:-}${GATE_WIRING_FBP_OVERRIDE:-}${GATE_WIRING_SFL_OVERRIDE:-}${GATE_WIRING_ORDER_OVERRIDE:-}${GATE_WIRING_DCO_OVERRIDE:-}" ]]
}

COMPLETED=0

finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: gate wiring check aborted before completing" >&2
    exit 1
  fi
}

trap finish EXIT

failed=0

fail() {
  echo "❌ FAIL: $*"
  failed=1
}

for f in "$SFL" "$FBP" "$CI" "$ORDER" "$CI_RUNNER"; do
  [[ -f "$f" ]] || {
    echo "❌ FAIL: $f not found" >&2
    exit 1
  }
done

# runs_script <file> <script>: defined once, in the sourced helper.
# shellcheck source=Scripts/lib_runs_script.sh
source Scripts/lib_runs_script.sh

# order_names <script-basename>: an order-file row names Scripts/<basename>.
order_names() {
  grep -v '^#' "$ORDER" | cut -d'|' -f2 | grep -qxF "Scripts/$1"
}

# require_fixture <script> [consequence]: an exempted script that must still
# carry its own Scripts/test_<script>.
require_fixture() {
  [[ -f "Scripts/test_$1" ]] \
    || fail "${1} has no Scripts/test_${1}${2:+ — $2}"
}

# --- 1. ROWS ----------------------------------------------------------------
n_rows=0
while IFS='|' read -r label script phase gate_class || [[ -n "${label:-}" ]]; do
  case "$label" in \#*|'') continue ;; esac
  [[ "${script:-}" == "n/a" ]] && continue
  n_rows=$((n_rows + 1))
  case "${phase:-}" in
    pre|post) ;;
    *) fail "'${label}' declares phase '${phase:-}' in ${ORDER} — sfl.sh and ${CI_RUNNER} run only pre and post rows, so this gate runs in neither, and nothing else reports it missing" ;;
  esac
  case "${gate_class:-}" in
    ''|secret-class) ;;
    *) fail "'${label}' declares class '${gate_class}' in ${ORDER} — sfl.sh and ${CI_RUNNER} understand only secret-class, so this row is an ordinary red in both, which is not what was declared" ;;
  esac
done < "$ORDER"

if [[ "$n_rows" -eq 0 ]]; then
  fail "no runnable row found in ${ORDER} — the parse is broken, so this check verified nothing"
fi

# --- 2. RUNNERS -------------------------------------------------------------
#
# first_line <file> <regex>: the number of the first line of <file> matching
# <regex>, or nothing. Each regex below anchors the command at the start of
# its line, so a comment or an echo naming it never matches.
first_line() {
  grep -nE "$2" "$1" | head -n 1 | cut -d: -f1 || true
}

BUILD_RE='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*\./Scripts/build_site\.sh([[:space:]]|$)'

# phases_in_order <runner-file> <pre-regex> <post-regex> <pre-what> <post-what>
phases_in_order() {
  local file="$1" pre_re="$2" post_re="$3" pre_what="$4" post_what="$5"
  local pre build post
  pre="$(first_line "$file" "$pre_re")"
  build="$(first_line "$file" "$BUILD_RE")"
  post="$(first_line "$file" "$post_re")"
  [[ -n "$pre" ]] || fail "${file} never runs the PRE phase (${pre_what}) — every pre row of ${ORDER} goes unrun there"
  [[ -n "$build" ]] || fail "${file} never runs ./Scripts/build_site.sh — the POST gates would read a site nobody built"
  [[ -n "$post" ]] || fail "${file} never runs the POST phase (${post_what}) — every post row of ${ORDER} goes unrun there"
  if [[ -n "$pre" && -n "$build" && -n "$post" ]]; then
    if [[ "$pre" -lt "$build" && "$build" -lt "$post" ]]; then
      echo "  ok: ${file} runs PRE (line ${pre}), the build (line ${build}) and POST (line ${post}), in that order"
    else
      fail "${file} runs PRE (line ${pre}), the build (line ${build}) and POST (line ${post}) out of order — PRE validates the inputs before the build, POST the site after it"
    fi
  fi
}

phases_in_order "$FBP" \
  '^[[:space:]]*\./sfl\.sh pre([[:space:]]|$)' \
  '^[[:space:]]*\./sfl\.sh post([[:space:]]|$)' \
  "./sfl.sh pre" "./sfl.sh post"

phases_in_order "$CI" \
  '^[[:space:]]*\./Scripts/run_ci_phase\.sh pre[[:space:]]' \
  '^[[:space:]]*\./Scripts/run_ci_phase\.sh post[[:space:]]' \
  "./Scripts/run_ci_phase.sh pre" "./Scripts/run_ci_phase.sh post"

# The two loops must read a row the same way. These are sfl.sh's own lines;
# run_ci_phase.sh repeats them on purpose. If one changes, the other must,
# and this says which line.
#   - the read that keeps a last line with no trailing newline
#   - the n/a skip
#   - the phase filter
#   - the order file both read
#
# Each rule must be a whole line of each runner, indentation aside, so a
# commented-out copy does not count. The rules come from a quoted heredoc:
# they are shell text, compared as text, never expanded.
while IFS= read -r rule; do
  for runner in "$SFL" "$CI_RUNNER"; do
    sed 's/^[[:space:]]*//' "$runner" | grep -qxF -- "$rule" \
      || fail "${runner} no longer has the row rule: ${rule} — sfl.sh and ${CI_RUNNER} read ${ORDER} with the same rules, so they run the same rows; change both or neither"
  done
done <<'RULES'
while IFS='|' read -r label script phase gate_class || [ -n "${label:-}" ]; do
[ "${script:-}" = "n/a" ] && continue
[ "${phase:-}" = "$PHASE" ] || continue
RULES
grep -qF 'done < Scripts/gate_report_order.txt' "$SFL" \
  || fail "${SFL} no longer reads Scripts/gate_report_order.txt — sfl and CI must run the same rows"
grep -qF 'ORDER="Scripts/gate_report_order.txt"' "$CI_RUNNER" \
  || fail "${CI_RUNNER} no longer reads Scripts/gate_report_order.txt — sfl and CI must run the same rows"

# --- 3. SCRIPTS OUTSIDE THE ORDER FILE --------------------------------------
n_gate=0
n_exempt=0

for path in Scripts/*.sh; do
  base="$(basename "$path")"

  case "$base" in
    test_*) continue ;;
  esac

  if order_names "$base"; then
    n_gate=$((n_gate + 1))
    continue
  fi

  n_exempt=$((n_exempt + 1))

  # DECLARED EXEMPTIONS. Each names WHY, so the list reads as decisions
  # rather than as the check being worn down. Adding one without a reason is
  # how a wiring check stops meaning anything.
  case "$base" in
    # BUILD BOUNDARY, not a gate. Part 2 checks where both runners call it;
    # this checks that each call is a real one.
    build_site.sh)
      runs_script "$FBP" "$base" \
        || fail "${base} is the local build boundary and ${FBP} never invokes it"
      runs_script "$CI" "$base" \
        || fail "${base} is the CI build boundary and ${CI} never invokes it"
      ;;

    # CI's gate loop: quality.yml runs it once per phase. Its tests are
    # part 4 of this file.
    run_ci_phase.sh)
      runs_script "$CI" "$base" \
        || fail "${base} is CI's gate loop and ${CI} never invokes it — no gate would run in CI at all"
      ;;

    # PRESENTATION, not a gate. It renders CI's step summary from the rows
    # and details run_ci_phase.sh writes. Required in the runner that uses
    # it, AND required to have a fixture: a presentation script that breaks
    # makes the report lie, and nothing else is watching it.
    render_quality_report.sh)
      runs_script "$CI" "$base" \
        || fail "${base} renders CI's step summary and CI never invokes it — a renderer nobody calls is a file, not a report"
      require_fixture "$base"
      ;;

    # PRESENTATION, not a gate (forsgren#8): the run's key numbers, rendered
    # above the gate report in CI's step summary from what the run wrote.
    # Same two requirements as the report renderer, for the same reason.
    render_quality_summary.sh)
      runs_script "$CI" "$base" \
        || fail "${base} renders the run summary at the top of CI's step summary and CI never invokes it — a renderer nobody calls is a file, not a summary"
      require_fixture "$base"
      ;;

    # PRE-FLIGHT, not a gate: it prints go.mod's toolchain line, which sfl,
    # FBP and CI each export as GOTOOLCHAIN before any Go runs. A runner
    # that stops calling it runs whatever Go the machine has.
    go_toolchain.sh)
      runs_script "$SFL" "$base" \
        || fail "${base} pins Go and ${SFL} never invokes it — sfl's gates would run whatever Go this machine has"
      runs_script "$FBP" "$base" \
        || fail "${base} pins Go and ${FBP} never invokes it — FBP's gofmt and build would run whatever Go this machine has"
      runs_script "$CI" "$base" \
        || fail "${base} pins Go and ${CI} never invokes it — CI's gates would run whatever Go the runner has"
      require_fixture "$base" "the pin would be untested"
      ;;

    # PRE-FLIGHT, not a gate (konenki unit 414): it installs the tools the
    # gates need, in sfl AND in CI. CI runs on GitHub's macos-latest, a
    # fresh machine per run with none of forsgren's tools (forsgren#1, the
    # runner swap), so without the installer there every gate needing one
    # would be red with `command not found`. Required to carry a fixture: an
    # installer that silently stops installing leaves every gate reading
    # whatever is on the machine.
    install_tools.sh)
      runs_script "$SFL" "$base" \
        || fail "${base} installs the tools the gates need and sfl never invokes it — the gates then run against whatever this machine happens to have"
      runs_script "$CI" "$base" \
        || fail "${base} installs the tools the gates need and ${CI} never invokes it — on a fresh hosted runner every gate needing a Homebrew tool would fail with command not found"
      require_fixture "$base" "an installer with no fixture fails by leaving a machine looking correctly configured"
      ;;

    # PRE-FLIGHT SYNCHRONISATION, not a gate. sfl sources it before PRE so
    # the run starts from the latest fast-forwardable upstream state. CI
    # checks out the exact commit it evaluates and must not pull another.
    sfl_pull.sh)
      runs_script "$SFL" "$base" \
        || fail "${base} provides sfl's opening ff-only pull and sfl never sources it"
      require_fixture "$base" "the pull contract would be untested"
      ;;

    # PRESENTATION, not a gate: sfl's end-of-run block. CI builds its report
    # from the rows and details instead.
    summarize_gate_failure.sh|render_step_table.sh)
      runs_script "$SFL" "$base" \
        || fail "${base} renders part of sfl's end-of-run output and sfl never invokes it — a renderer nobody calls is a file, not a report"
      require_fixture "$base" "a presentation script with no fixture fails silently, because nothing else reads its output closely enough to notice"
      ;;

    # SOURCED HELPER, not a gate (konenki issue #14): the throwaway FBP
    # sandbox both FBP fixtures drive. They are its test, and both must
    # still source it.
    lib_fbp_sandbox.sh)
      for consumer in test_fbp_commit_message.sh test_fbp_build_pagecount.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} holds the shared FBP sandbox and Scripts/${consumer} never sources it"
      done
      ;;

    # SOURCED HELPER, not a gate (konenki issue #18): runs_script, the one
    # definition of what counts as running a script. Its test is the matcher
    # self-proof in part 5 of this file, which sources it.
    lib_runs_script.sh)
      runs_script "Scripts/test_gate_wiring.sh" "$base" \
        || fail "${base} holds runs_script and Scripts/test_gate_wiring.sh never sources it"
      ;;

    # SOURCED HELPER, not a gate (forsgren#1, ladder step 24): the harness of
    # forsgren's own self-tests. Every self-test that calls selftest_begin
    # is its test, and must source it; one that stopped would die at its
    # first case, so this guards the other way: a lib no self-test uses is a
    # file, not a harness.
    lib_selftest.sh)
      selftest_users="$(grep -l '^selftest_begin ' Scripts/test_*.sh || true)"
      [[ -n "$selftest_users" ]] \
        || fail "${base} holds the self-test harness and no Scripts/test_*.sh calls selftest_begin — a harness nobody uses is a file"
      for consumer in $selftest_users; do
        runs_script "$consumer" "$base" \
          || fail "${base} holds selftest_begin and ${consumer} calls it without sourcing ${base}"
      done
      ;;

    # PULL-REQUEST CHECK, not a gate of sfl or Quality (road to public,
    # step 4): every commit of a pull request carries a DCO sign-off from its
    # author. A commit on main has no pull request, so neither runner can
    # run it; .github/workflows/dco.yml does, on a GitHub-hosted runner, and
    # its self-test is an order-file row, so sfl and Quality still prove it.
    check_dco.sh)
      runs_script "$DCO_WF" "$base" \
        || fail "${base} checks a pull request's sign-offs and ${DCO_WF} never invokes it — no pull request would be checked"
      require_fixture "$base" "the sign-off check would wave commits through unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the check dco.yml relies on"
      ;;

    # HAND-RUN BY THE LOOP, never by sfl or a workflow: a thin exec wrapper
    # around FBP.sh under the agent-Friend identity. Requiring a runner to
    # invoke it would mean FBP invoking itself. CLAUDE.md declares it.
    fbp_agent_friend.sh)
      grep -qF 'Scripts/fbp_agent_friend.sh' CLAUDE.md \
        || fail "${base} is run by hand and CLAUDE.md no longer declares it — an undeclared script nobody runs is a file, not a tool"
      ;;

    *)
      fail "${base} is a script no order-file row names and no declared exemption covers — a validator nobody runs is a file, not a gate"
      ;;
  esac
done


# --- 4. THE CI LOOP, AT RUNTIME ----------------------------------------------
#
# run_ci_phase.sh runs against a sandbox root (its RUN_CI_PHASE_ROOT seam): a
# git repository holding an order file and stub gates. A stub appends its own
# path to $WIRING_TRACE, prints one line, and exits with the status its name
# asks for.

# new_sandbox: a fresh sandbox; sets SB and TRACE. One tracked file,
# committed, so a gate that writes to it changes the tree.
new_sandbox() {
  SANDBOX_N=$((SANDBOX_N + 1))
  SB="${RUNTIME_TMP}/sandbox_${SANDBOX_N}"
  mkdir -p "${SB}/Scripts"
  git -C "$SB" init -q
  echo "tracked" > "${SB}/tracked.txt"
  git -C "$SB" add tracked.txt
  git -C "$SB" -c user.name=wiring -c user.email=wiring@example.invalid \
    -c commit.gpgsign=false commit -q -m "sandbox"
  TRACE="${SB}.trace"
  : > "$TRACE"
}

# stub <path> <exit> [writes]: an executable stub gate at <path> in $SB.
# With `writes`, it changes the tracked file before exiting.
stub() {
  local path="$1" code="$2" writes="${3:-}"
  mkdir -p "$(dirname "${SB}/${path}")"
  {
    cat <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${0#./}" >> "$WIRING_TRACE"
STUB
    printf 'echo "stub output of %s"\n' "$path"
    if [[ -n "$writes" ]]; then
      printf '%s\n' 'echo changed >> tracked.txt'
    fi
    printf 'exit %s\n' "$code"
  } > "${SB}/${path}"
  chmod +x "${SB}/${path}"
}

# run_phase <phase> [shell...]: runs the loop over $SB; sets RUN_OUT, RUN_RC,
# RUN_ROWS and RUN_DETAILS. With a shell, runs it under that shell.
run_phase() {
  local phase="$1"
  shift
  RUN_ROWS="${SB}.${phase}.rows"
  RUN_DETAILS="${SB}.${phase}.details"
  rm -rf "$RUN_ROWS" "$RUN_DETAILS"
  RUN_RC=0
  RUN_OUT="$(WIRING_TRACE="$TRACE" RUN_CI_PHASE_ROOT="$SB" \
    "$@" "./${CI_RUNNER}" "$phase" "$RUN_ROWS" "$RUN_DETAILS" 2>&1)" || RUN_RC=$?
}

# runnable_rows <order-file>: the script of every runnable row, file order,
# phase ignored. What the two phases together must run, each exactly once.
runnable_rows() {
  awk -F'|' '$0 !~ /^#/ && $1 != "" && NF >= 2 && $2 != "n/a" { print $2 }' "$1"
}

# phase_of <order-file> <script>: the phase the row naming <script> declares.
phase_of() {
  awk -F'|' -v s="$2" '$0 !~ /^#/ && $2 == s { print $3; exit }' "$1"
}

# 4a. The REAL order file: every runnable row runs exactly once across the
# two phases, each in its own phase, in file order.
runtime_real_order_file() {
  local script trace_pre trace_post want got wrong=0
  new_sandbox
  cp "$ORDER" "${SB}/Scripts/gate_report_order.txt"
  while IFS= read -r script; do
    stub "$script" 0
  done < <(runnable_rows "$ORDER")

  run_phase pre
  trace_pre="$(cat "$TRACE")"
  [[ "$RUN_RC" -eq 0 ]] || fail "run_ci_phase.sh pre over the real order file, all stubs green, exited ${RUN_RC}. Output: ${RUN_OUT}"
  : > "$TRACE"
  run_phase post
  trace_post="$(cat "$TRACE")"
  [[ "$RUN_RC" -eq 0 ]] || fail "run_ci_phase.sh post over the real order file, all stubs green, exited ${RUN_RC}. Output: ${RUN_OUT}"

  want="$(runnable_rows "$ORDER" | LC_ALL=C sort)"
  got="$(printf '%s\n%s\n' "$trace_pre" "$trace_post" | grep -v '^$' | LC_ALL=C sort || true)"
  if [[ "$got" != "$want" ]]; then
    fail "run_ci_phase.sh pre + post did not run every runnable row of ${ORDER} exactly once. Missing or extra (< wanted, > ran):"
    diff <(echo "$want") <(echo "$got") | grep '^[<>]' | sed 's/^/      /' || true
    wrong=1
  fi

  while IFS= read -r script; do
    [[ -n "$script" ]] || continue
    [[ "$(phase_of "$ORDER" "$script")" == "pre" ]] \
      || { fail "${script} ran in CI's PRE phase but its row declares $(phase_of "$ORDER" "$script")"; wrong=1; }
  done <<< "$trace_pre"
  while IFS= read -r script; do
    [[ -n "$script" ]] || continue
    [[ "$(phase_of "$ORDER" "$script")" == "post" ]] \
      || { fail "${script} ran in CI's POST phase but its row declares $(phase_of "$ORDER" "$script")"; wrong=1; }
  done <<< "$trace_post"

  want="$(runnable_rows "$ORDER" | while IFS= read -r script; do
    [[ "$(phase_of "$ORDER" "$script")" == "pre" ]] && echo "$script"; done || true)"
  [[ "$trace_pre" == "$want" ]] \
    || { fail "CI's PRE phase did not run its rows in file order. Ran: ${trace_pre}"; wrong=1; }

  [[ "$wrong" -eq 0 ]] \
    && echo "  ok: run_ci_phase.sh runs each of the $(runnable_rows "$ORDER" | grep -c .) runnable rows of ${ORDER} exactly once, in its own phase, in file order"
  return 0
}

# 4b. Synthetic order files: the row rules, failures, the tree check.
runtime_synthetic() {
  new_sandbox
  {
    echo "# a comment line"
    echo ""
    echo "first|Scripts/pass_a.sh|pre|"
    echo "fails|Scripts/fail.sh|pre|"
    echo "later|Scripts/pass_b.sh|pre|"
    echo "post only|Scripts/pass_c.sh|post|"
    echo "declared n/a|n/a|this repo has no such gate"
    echo "not executable|Scripts/noexec.sh|pre|"
    echo "writes the tree|Scripts/writes.sh|pre|"
    printf '%s' "last, no newline|Scripts/pass_d.sh|pre|"
  } > "${SB}/Scripts/gate_report_order.txt"
  stub Scripts/pass_a.sh 0
  stub Scripts/fail.sh 3
  stub Scripts/pass_b.sh 0
  stub Scripts/pass_c.sh 0
  stub Scripts/writes.sh 0 writes
  stub Scripts/pass_d.sh 0
  printf '#!/usr/bin/env bash\nexit 0\n' > "${SB}/Scripts/noexec.sh"

  # GitHub's `shell: bash`: errexit and pipefail on. The loop must survive.
  run_phase pre bash --noprofile --norc -eo pipefail

  [[ "$RUN_RC" -eq 1 ]] \
    || fail "run_ci_phase.sh exited ${RUN_RC} on a phase with failing rows — want 1. Output: ${RUN_OUT}"

  local want_trace got_trace
  want_trace="$(printf '%s\n' Scripts/pass_a.sh Scripts/fail.sh Scripts/pass_b.sh Scripts/writes.sh Scripts/pass_d.sh)"
  got_trace="$(cat "$TRACE")"
  if [[ "$got_trace" == "$want_trace" ]]; then
    echo "  ok: the loop skips comments, blanks, n/a and the other phase, keeps going after a failure, and reads a last line with no newline"
  else
    fail "the loop ran the wrong rows (want: $(echo "$want_trace" | tr '\n' ' '); ran: $(echo "$got_trace" | tr '\n' ' ')) — sfl runs exactly the first list"
  fi

  local row
  for row in "first|✅" "fails|❌" "later|✅" "not executable|❌" "writes the tree|❌" "last, no newline|✅"; do
    grep -qxF -- "$row" "$RUN_ROWS" \
      || fail "no '${row}' row was written. Rows: $(tr '\n' ' ' < "$RUN_ROWS")"
  done
  if grep -qE '^(post only|declared n/a)\|' "$RUN_ROWS"; then
    fail "a row of another phase or an n/a row was reported. Rows: $(tr '\n' ' ' < "$RUN_ROWS")"
  fi
  [[ "$(grep -c . "$RUN_ROWS")" -eq 6 ]] \
    || fail "want exactly 6 rows, one per pre row run. Rows: $(tr '\n' ' ' < "$RUN_ROWS")"

  grep -qF "stub output of Scripts/fail.sh" "${RUN_DETAILS}/fails.md" 2>/dev/null \
    || fail "the failing gate's details file does not carry its output"
  grep -qF "#### ❌ fails" "${RUN_DETAILS}/fails.md" 2>/dev/null \
    || fail "the failing gate's details file has no ❌ heading"
  grep -qF "not an executable script" "${RUN_DETAILS}/not_executable.md" 2>/dev/null \
    || fail "a non-executable declared script is not named as such in its details"
  if grep -qF "changed the checked-out tree" "${RUN_DETAILS}/writes_the_tree.md" 2>/dev/null \
    && grep -qF "M tracked.txt" "${RUN_DETAILS}/writes_the_tree.md"; then
    echo "  ok: a gate that exits 0 but changes the checked-out tree is red, naming the file"
  else
    fail "a gate that changed a tracked file was not reported red with the file named — CI would pass a commit only after fixing it"
  fi
  grep -qF "stub output of Scripts/pass_d.sh" <<< "$RUN_OUT" \
    || fail "the gates' output does not reach the step log"

  # A secret-class failure: exit 2, and the rows after it still run.
  new_sandbox
  {
    echo "secret scan|Scripts/fail.sh|pre|secret-class"
    echo "after|Scripts/pass_a.sh|pre|"
  } > "${SB}/Scripts/gate_report_order.txt"
  stub Scripts/fail.sh 1
  stub Scripts/pass_a.sh 0
  run_phase pre
  if [[ "$RUN_RC" -eq 2 ]] && grep -qF Scripts/pass_a.sh "$TRACE"; then
    echo "  ok: a secret-class failure exits 2, and the rest of the phase still runs"
  else
    fail "a secret-class failure exited ${RUN_RC} (want 2, so the workflow skips the build as FBP does) or stopped the phase. Output: ${RUN_OUT}"
  fi

  # A phase with no row is red, with the reason.
  new_sandbox
  echo "post only|Scripts/pass_c.sh|post|" > "${SB}/Scripts/gate_report_order.txt"
  stub Scripts/pass_c.sh 0
  run_phase pre
  if [[ "$RUN_RC" -eq 1 ]] && grep -qF "declares no pre row" <<< "$RUN_OUT"; then
    echo "  ok: a phase with no row is red, and says so"
  else
    fail "a phase with no row exited ${RUN_RC} — a CI phase that ran nothing must not be green. Output: ${RUN_OUT}"
  fi

  # No order file: red, with the reason.
  new_sandbox
  run_phase pre
  if [[ "$RUN_RC" -eq 1 ]] && grep -qF "is missing" <<< "$RUN_OUT"; then
    echo "  ok: a missing order file is red, and says so"
  else
    fail "a missing order file exited ${RUN_RC}. Output: ${RUN_OUT}"
  fi

  # A phase name sfl does not have is a usage error, not an empty phase.
  run_phase build
  [[ "$RUN_RC" -eq 64 ]] \
    || fail "run_ci_phase.sh build exited ${RUN_RC} — want 64, usage: only pre and post exist"
  return 0
}

# --- 5. PROOFS ----------------------------------------------------------------
#
# Each proof re-runs this whole check against a copy of one runner file (or of
# the order file) whose real invocation is turned into a comment, or one rule
# broken, while other lines keep MENTIONING it. The check must reject that
# copy, by name.
#
# mutation_proof <override-var> <mention> <sed-expr> <expected> <label>
#   <override-var>  GATE_WIRING_CI_OVERRIDE, GATE_WIRING_FBP_OVERRIDE,
#                   GATE_WIRING_SFL_OVERRIDE, GATE_WIRING_ORDER_OVERRIDE or
#                   GATE_WIRING_DCO_OVERRIDE
#   <mention>       text the mutant must still contain (else the proof tests
#                   a deletion, not a mention)
#   <sed-expr>      the -E expression that makes the mutant
#   <expected>      the substring the rejecting fail line must contain
#   <label>         what the mutant is, for the messages
#
# Three guards, all needed (konenki's): the mutant must differ from the
# original (else the sed stopped matching and the proof proves nothing), the
# mutant must still contain <mention>, and the re-run must fail WITH the
# expected message (a non-zero exit for any other reason is not the check
# biting).
rerun_with() {
  env "${1}=${2}" "./Scripts/$(basename "$0")" 2>&1
}

mutation_proof() {
  local override_var="$1" mention="$2" sed_expr="$3" expected="$4" label="$5"
  local original mutated rc out

  case "$override_var" in
    GATE_WIRING_CI_OVERRIDE) original="$CI" ;;
    GATE_WIRING_FBP_OVERRIDE) original="$FBP" ;;
    GATE_WIRING_SFL_OVERRIDE) original="$SFL" ;;
    GATE_WIRING_ORDER_OVERRIDE) original="$ORDER" ;;
    GATE_WIRING_DCO_OVERRIDE) original="$DCO_WF" ;;
    *)
      fail "mutation proof: unknown override variable ${override_var}"
      return 0
      ;;
  esac

  MUTANT_N=$((MUTANT_N + 1))
  mutated="${MUTATION_TMP}/${MUTANT_N}.$(basename "$original")"
  sed -E "$sed_expr" "$original" > "$mutated"

  if cmp -s "$original" "$mutated"; then
    fail "mutation proof: ${label} — the sed changed nothing in ${original}, so this case proves nothing"
    return 0
  fi

  if ! grep -qF -- "$mention" "$mutated"; then
    fail "mutation proof: ${label} no longer mentions ${mention} at all — the case must keep a mention to prove a mention is not an invocation"
    return 0
  fi

  rc=0
  out="$(rerun_with "$override_var" "$mutated")" || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    fail "mutation proof: ${label} PASSED the gate wiring check"
  elif ! grep -qF -- "$expected" <<< "$out"; then
    fail "mutation proof: ${label} failed, but not with the expected message (${expected}). Output: ${out}"
  else
    echo "  ok: ${label} is rejected"
  fi
}

# Every line of konenki's matcher self-proof below is byte-identical with
# konenki-website's Scripts/test_gate_wiring.sh; issue numbers in it are
# konenki's. Its "guard" samples include konenki's report_ci_step.sh call
# shape, which lib_runs_script.sh still models.
# --- Matcher self-proof: runs_script on sample files — issue #18 ----------
#
# The mutation proofs only show that runs_script rejects what the real
# runners happen to contain today. These feed it sample files, one form per
# file, each naming Scripts/probe.sh: a form that only MENTIONS the script
# must be rejected, and a form that RUNS it must be accepted. The file
# extension says what the sample is (.yml a workflow, .sh a shell script),
# as it does for the real runners. Items are those of issue #18; "guard"
# samples are the real call shapes of quality.yml, sfl.sh,
# FullBuildAndPush.sh and the fixtures that source a helper, plus one call
# through bash (no runner has that shape today; it pins the wrapper rule),
# so that a stricter matcher cannot start rejecting them.
MATCHER_N=0

# matcher_sample <ext>: copies stdin into a fresh sample file with extension
# <ext> and sets MATCHER_FILE to its path.
matcher_sample() {
  MATCHER_N=$((MATCHER_N + 1))
  MATCHER_FILE="${MUTATION_TMP}/matcher_${MATCHER_N}.$1"
  cat > "$MATCHER_FILE"
}

# matcher_fail <item> <what went wrong>: fails naming the issue item and
# shows the sample the verdict was wrong on.
matcher_fail() {
  fail "runs_script (issue #18 ${1}): ${2} Sample (${MATCHER_FILE##*/}):"
  sed 's/^/      | /' "$MATCHER_FILE"
}

# matcher_rejects <item> <label> <ext> < sample: runs_script must NOT count
# the sample as running Scripts/probe.sh.
matcher_rejects() {
  matcher_sample "$3"
  if runs_script "$MATCHER_FILE" probe.sh; then
    matcher_fail "$1" "${2} counted as running Scripts/probe.sh, but it only mentions it."
  else
    echo "  ok: runs_script rejects ${2}"
  fi
}

# matcher_accepts <item> <label> <ext> < sample: runs_script MUST count the
# sample as running Scripts/probe.sh.
matcher_accepts() {
  matcher_sample "$3"
  if runs_script "$MATCHER_FILE" probe.sh; then
    echo "  ok: runs_script accepts ${2}"
  else
    matcher_fail "$1" "${2} was not counted as running Scripts/probe.sh, but it runs it."
  fi
}

matcher_self_proof() {
  # Item 2: another command takes the path as an argument.
  matcher_rejects "item 2" "a chmod +x line in a run block" yml <<'SAMPLE'
      - name: Render report
        run: |
          chmod +x ./Scripts/probe.sh
          ./Scripts/other.sh "$ROWS" "$DETAILS"
SAMPLE
  matcher_rejects "item 2" "a cp line copying the script" sh <<'SAMPLE'
cp "${ROOT}/Scripts/probe.sh" "${dir}/Scripts/probe.sh"
SAMPLE
  matcher_rejects "item 2" "a [ -x ] test of the script" sh <<'SAMPLE'
[ -x ./Scripts/probe.sh ] || exit 1
SAMPLE
  matcher_rejects "item 2, #14 note a" "the script passed as an argument to another script" sh <<'SAMPLE'
PATH="${dir}/bin:$PATH" "$BASH" "${dir}/driver.sh" "${ROOT}/Scripts/probe.sh" > "${dir}/run.out" 2>&1
SAMPLE

  # Item 3: YAML keys other than run: hold text, not commands.
  matcher_rejects "item 3" "a YAML - name: value" yml <<'SAMPLE'
      - name: Run ./Scripts/probe.sh
        run: |
          ./Scripts/other.sh
SAMPLE
  matcher_rejects "item 3" "a YAML name: value that is not the first key" yml <<'SAMPLE'
      - uses: actions/checkout@v4
        name: Scripts/probe.sh self-test
SAMPLE
  matcher_rejects "item 3" "a YAML if: expression" yml <<'SAMPLE'
      - if: hashFiles('Scripts/probe.sh') != ''
        run: ./Scripts/other.sh
SAMPLE

  # Item 4: heredoc bodies and multi-line strings are data.
  matcher_rejects "item 4" "a quoted heredoc body" sh <<'SAMPLE'
cat > "$f" <<'EOF'
./Scripts/probe.sh
EOF
SAMPLE
  matcher_rejects "item 4" "an unquoted <<- heredoc body in a run block" yml <<'SAMPLE'
        run: |
          cat <<-EOF >> "$GITHUB_STEP_SUMMARY"
          ./Scripts/probe.sh "$ROWS"
          EOF
SAMPLE
  matcher_rejects "item 4" "the continuation line of a multi-line double-quoted string" sh <<'SAMPLE'
echo "Regenerate with
  ./Scripts/probe.sh, then commit"
SAMPLE
  matcher_rejects "item 4" "a backslash continuation line of an echo" sh <<'SAMPLE'
echo "Regenerate with" \
  ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 4" "a > block scalar under env:" yml <<'SAMPLE'
      - name: Hint
        env:
          HINT: >
            ./Scripts/probe.sh
        run: ./Scripts/other.sh
SAMPLE
  matcher_rejects "item 4" "a | block scalar under with:" yml <<'SAMPLE'
      - uses: actions/github-script@v7
        with:
          script: |
            ./Scripts/probe.sh
SAMPLE

  # Item 5: an echo, printf, comment, : or test AFTER real code.
  matcher_rejects "item 5" "an echo inside a { } group" sh <<'SAMPLE'
{ echo; echo ./Scripts/probe.sh; }
SAMPLE
  matcher_rejects "item 5" "a comment after true" sh <<'SAMPLE'
true # ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 5" "a comment after a real call of another script" sh <<'SAMPLE'
./Scripts/other.sh # replaces ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 5" "a : no-op" sh <<'SAMPLE'
: ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 5" "a test -x" sh <<'SAMPLE'
test -x ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 5" "a printf after ;" sh <<'SAMPLE'
rc=0; printf '%s\n' ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 5" "an echo after && on a one-line run:" yml <<'SAMPLE'
      - run: true && echo ./Scripts/probe.sh
SAMPLE

  # Item 6: a real call fed by echo or printf through a pipe.
  matcher_accepts "item 6" "a call fed by printf through a pipe" yml <<'SAMPLE'
        run: |
          printf '%s\n' x | ./Scripts/probe.sh
SAMPLE
  matcher_accepts "item 6" "a call fed by echo through a pipe" sh <<'SAMPLE'
echo x | ./Scripts/probe.sh
SAMPLE

  # Item 9: the match is on the whole path, not on part of a longer one.
  matcher_rejects "item 9" "a call of Scripts/probe.sh.bak" yml <<'SAMPLE'
        run: |
          ./Scripts/probe.sh.bak "$ROWS"
SAMPLE
  matcher_rejects "item 9" "a call of LegacyScripts/probe.sh" sh <<'SAMPLE'
./LegacyScripts/probe.sh
SAMPLE

  # Guards: the real call shapes, which must stay accepted. These held when
  # they were written.
  matcher_accepts "guard" "a call in a run: | block" yml <<'SAMPLE'
        run: |
          set -uo pipefail
          ./Scripts/probe.sh "$ROWS" "$DETAILS"
SAMPLE
  matcher_accepts "guard" "a one-line - run: call" yml <<'SAMPLE'
      - run: ./Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a gate named after the -- of report_ci_step.sh" yml <<'SAMPLE'
        run: |
          ./Scripts/report_ci_step.sh "probe" "$ROWS" "$DETAILS" -- ./Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a gate named after -- on a continuation line" yml <<'SAMPLE'
        run: |
          ./Scripts/report_ci_step.sh \
            --heading "Probe" \
            "probe" "$ROWS" "$DETAILS" -- ./Scripts/probe.sh "$GENERATED_SITE"
SAMPLE
  matcher_accepts "guard" "a call captured in an if test" yml <<'SAMPLE'
        run: |
          if out="$(./Scripts/probe.sh "$GENERATED_SITE" Site 2>&1)"; then
            rc=0
          fi
SAMPLE
  matcher_accepts "guard" "a call captured before && rc=0 || rc=\$?" yml <<'SAMPLE'
        run: |
          out="$(./Scripts/probe.sh 2>&1)" && rc=0 || rc=$?
SAMPLE
  matcher_accepts "guard" "a call in a run block after an env: block scalar" yml <<'SAMPLE'
      - name: Hint
        env:
          HINT: >
            see the docs
        run: |
          ./Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a call after a heredoc has ended" sh <<'SAMPLE'
cat > "$f" <<'EOF'
text
EOF
./Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a call with an env-assignment prefix" sh <<'SAMPLE'
  SITE_PAGE_COUNT_FILE="$PAGE_COUNT_FILE" ./Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a call inside a command substitution" sh <<'SAMPLE'
    FAILED_GATES="${FAILED_GATES}$(./Scripts/probe.sh "$log")"$'\n'
SAMPLE
  matcher_accepts "guard" "a call whose arguments continue on the next line" sh <<'SAMPLE'
./Scripts/probe.sh \
  "$STEP_FILE"
SAMPLE
  matcher_accepts "guard" "a source of the ROOT-prefixed path" sh <<'SAMPLE'
source "${ROOT}/Scripts/probe.sh"
SAMPLE
  matcher_accepts "guard" "an indented source Scripts/probe.sh" sh <<'SAMPLE'
  source Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a call through bash" sh <<'SAMPLE'
bash ./Scripts/probe.sh
SAMPLE
}

if ! is_mutation_rerun; then
  RUNTIME_TMP="$(mktemp -d)"
  MUTATION_TMP="$(mktemp -d)"
  trap 'rm -rf "$RUNTIME_TMP" "$MUTATION_TMP"; finish' EXIT
  SANDBOX_N=0
  MUTANT_N=0

  runtime_real_order_file
  runtime_synthetic

  # quality.yml: the POST phase call becomes a comment; the comments that
  # name the runner stay.
  mutation_proof GATE_WIRING_CI_OVERRIDE "Scripts/run_ci_phase.sh" \
    's|^([[:space:]]*)(\./Scripts/run_ci_phase\.sh post )|\1# \2|' \
    "never runs the POST phase" \
    "a quality.yml whose POST phase call is a comment"

  # quality.yml: PRE and POST swapped, so PRE runs after the build.
  mutation_proof GATE_WIRING_CI_OVERRIDE "Scripts/run_ci_phase.sh" \
    's|run_ci_phase\.sh pre |run_ci_phase.sh SWAP |; s|run_ci_phase\.sh post |run_ci_phase.sh pre |; s|run_ci_phase\.sh SWAP |run_ci_phase.sh post |' \
    "out of order" \
    "a quality.yml that runs POST before the build and PRE after it"

  # quality.yml: the build call becomes a comment.
  mutation_proof GATE_WIRING_CI_OVERRIDE "Scripts/build_site.sh" \
    's|^([[:space:]]*)(\./Scripts/build_site\.sh)|\1# \2|' \
    "build_site.sh is the CI build boundary and" \
    "a quality.yml that mentions build_site.sh only in comments"

  # quality.yml: the report call becomes a comment.
  mutation_proof GATE_WIRING_CI_OVERRIDE "Scripts/render_quality_report.sh" \
    's|^([[:space:]]*)(\./Scripts/render_quality_report\.sh)|\1# \2|' \
    "render_quality_report.sh renders CI's step summary and" \
    "a quality.yml whose render_quality_report.sh call is a comment"

  # quality.yml: the summary call becomes a comment (forsgren#8).
  mutation_proof GATE_WIRING_CI_OVERRIDE "Scripts/render_quality_summary.sh" \
    's|^([[:space:]]*)(\./Scripts/render_quality_summary\.sh)|\1# \2|' \
    "render_quality_summary.sh renders the run summary" \
    "a quality.yml whose render_quality_summary.sh call is a comment"

  # quality.yml: the Go pin call becomes an echo of it.
  mutation_proof GATE_WIRING_CI_OVERRIDE "Scripts/go_toolchain.sh" \
    's|\((\./Scripts/go_toolchain\.sh)\)|(echo \1)|' \
    "go_toolchain.sh pins Go and" \
    "a quality.yml that echoes go_toolchain.sh instead of running it"

  # quality.yml: the tool install call becomes a comment; the comments that
  # name the installer stay.
  mutation_proof GATE_WIRING_CI_OVERRIDE "Scripts/install_tools.sh" \
    's|^([[:space:]]*)(\./Scripts/install_tools\.sh)|\1# \2|' \
    "install_tools.sh installs the tools the gates need and" \
    "a quality.yml whose install_tools.sh call is a comment"

  # FBP.sh: the POST call becomes a comment.
  mutation_proof GATE_WIRING_FBP_OVERRIDE "sfl.sh post" \
    's|^([[:space:]]*)(\./sfl\.sh post )|\1# \2|' \
    "never runs the POST phase" \
    "an FBP.sh whose sfl.sh post call is a comment"

  # FBP.sh: every non-comment line that runs build_site.sh becomes a
  # comment; the commentary naming it stays.
  mutation_proof GATE_WIRING_FBP_OVERRIDE "Scripts/build_site.sh" \
    's|^([[:space:]]*)([^#[:space:]][^#]*\./Scripts/build_site\.sh)|\1# \2|' \
    "build_site.sh is the local build boundary and" \
    "an FBP.sh that mentions build_site.sh only in comments"

  # sfl.sh: the pull source line becomes a comment.
  mutation_proof GATE_WIRING_SFL_OVERRIDE "Scripts/sfl_pull.sh" \
    's|^([[:space:]]*)(source Scripts/sfl_pull\.sh)|\1# \2|' \
    "sfl_pull.sh provides sfl's opening ff-only pull and sfl never sources it" \
    "an sfl.sh that mentions sfl_pull.sh only in comments"

  # sfl.sh: the phase filter becomes a comment, so sfl would run every row in
  # both phases while CI runs each in one.
  mutation_proof GATE_WIRING_SFL_OVERRIDE "phase:-" \
    's#^([[:space:]]*)(\[ "[$][{]phase:-[}]" = )#\1\# \2#' \
    "no longer has the row rule" \
    "an sfl.sh whose phase filter is a comment"

  # The order file: one row's phase misspelt, so neither runner runs it.
  mutation_proof GATE_WIRING_ORDER_OVERRIDE "Scripts/check_gofmt.sh" \
    's#^(gofmt\|Scripts/check_gofmt\.sh\|)pre\|#\1Pre|#' \
    "declares phase 'Pre'" \
    "an order file whose gofmt row declares phase Pre"

  # The order file: a row naming a script that is no gate and no exemption
  # becomes a comment; that script is then run by nobody.
  mutation_proof GATE_WIRING_ORDER_OVERRIDE "Scripts/check_repo_links.sh" \
    's#^(repository links\|Scripts/check_repo_links\.sh\|)#\# \1#' \
    "check_repo_links.sh is a script no order-file row names" \
    "an order file whose repository-links row is a comment"

  # dco.yml: the check call becomes a comment; the comments naming it stay.
  mutation_proof GATE_WIRING_DCO_OVERRIDE "Scripts/check_dco.sh" \
    's|^([[:space:]]*)(\./Scripts/check_dco\.sh )|\1# \2|' \
    "check_dco.sh checks a pull request's sign-offs and" \
    "a dco.yml whose check_dco.sh call is a comment"

  # The order file: the DCO self-test row becomes a comment, so neither sfl
  # nor Quality proves the check dco.yml runs.
  mutation_proof GATE_WIRING_ORDER_OVERRIDE "Scripts/test_check_dco.sh" \
    's#^(DCO sign-off self-test\|)#\# \1#' \
    "Scripts/test_check_dco.sh is not an order-file row" \
    "an order file whose DCO sign-off self-test row is a comment"

  matcher_self_proof
fi

if [[ "$n_gate" -eq 0 ]]; then
  fail "no Scripts/*.sh is named by an order-file row — the glob or the parse is broken, so this check verified nothing"
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: gate wiring"
  exit 1
fi

echo "OK: gate wiring (${n_rows} rows run by sfl and by CI in their declared phase, ${n_gate} gate scripts among them, ${n_exempt} declared exemptions run by their required runners)"
