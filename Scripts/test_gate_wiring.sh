#!/usr/bin/env bash
# Scripts/test_gate_wiring.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# Every gate must be wired into BOTH runners, sfl.sh and CI — the sfl/CI
# parity guard.
#
# Ported from another estate repository 2026-10-01 (forsgren#1, ladder step 14), its
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
#   4. THE CI LOOP, AT RUNTIME. Pinned by Scripts/test_run_ci_phase.sh, its
#      own order-file row: run_ci_phase.sh over the REAL order file with a
#      stub at every declared path runs every runnable row exactly once across
#      its two phases, each in its own phase, in file order; and over
#      synthetic order files it skips what sfl skips, keeps going after a
#      failure, exits 2 on a secret-class failure, is red on a malformed row,
#      a phase with no row, a missing or non-executable script and a gate that
#      changes the checked-out tree, and survives GitHub's
#      `bash -e -o pipefail`.
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
# quality.yml, dco.yml, starter_page.yml or the order file. Nothing else sets them; sfl and CI
# always run against the real files.
SFL="${GATE_WIRING_SFL_OVERRIDE:-sfl.sh}"
FBP="${GATE_WIRING_FBP_OVERRIDE:-FBP.sh}"
CI="${GATE_WIRING_CI_OVERRIDE:-.github/workflows/quality.yml}"
ORDER="${GATE_WIRING_ORDER_OVERRIDE:-Scripts/gate_report_order.txt}"
DCO_WF="${GATE_WIRING_DCO_OVERRIDE:-.github/workflows/dco.yml}"
STARTER_WF="${GATE_WIRING_STARTER_OVERRIDE:-.github/workflows/starter_page.yml}"
RELEASE_WF=".github/workflows/release.yml"
CI_RUNNER="Scripts/run_ci_phase.sh"

# is_mutation_rerun: this run is a proof re-running the check with one of
# the files above replaced, so it must not start proofs of its own, nor
# repeat the runtime cases of part 4, which do not read those files.
is_mutation_rerun() {
  [[ -n "${GATE_WIRING_CI_OVERRIDE:-}${GATE_WIRING_FBP_OVERRIDE:-}${GATE_WIRING_SFL_OVERRIDE:-}${GATE_WIRING_ORDER_OVERRIDE:-}${GATE_WIRING_DCO_OVERRIDE:-}${GATE_WIRING_STARTER_OVERRIDE:-}" ]]
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

# --- 1b. THE GATE COUNT IS A RATCHET: gates go up, never down -----------------
#
# Yves, 2026-08-31: "so that gates can not go down, only up". Same rule as the
# coverage ratchet and the duplication ceiling: raise MIN_GATES whenever a row
# lands, never lower it to make a red go away. It counts the runnable rows of
# the order file (n/a rows included: a declared absence is a row). It counts
# rather than pinning the list, deliberately: swapping one gate for another
# keeps the count and passes; the estate's gate-parity axis catches that from
# outside, because the removed one reappears as missing against the canon.
#
# New in forsgren with forsgren#215; set to the row count of that change
# (115), plus the Go tool helper self-test of forsgren#216 (116).
# Raised to 118 for the browser gate and its self-test (forsgren#205), and to
# 119 for the live check's self-test (forsgren#205, step 2 of 2), and to 123
# for the language gate (its self-test, the pages wrapper's self-test and the gate)
# and the baseline report self-test (forsgren#220), and to 125 for the two
# self-tests of the release building blocks (forsgren#221, step 1 of 2), and to
# 131 for the five self-tests of the release scripts and the pin of the Release
# workflow (forsgren#221, step 2 of 2), and to 132 for the self-test of
# release_resume.sh (forsgren#221, the resume), and to 133 for the self-test of
# release_token_expiry.sh (forsgren#221, step 4), and to 135 for the self-tests of
# release_verify_pin.sh and release_metrics.sh (forsgren#221, step 5), and
# to 138 for the self-test of release_bump_diff.sh (forsgren#230, step 1), and to
# 140 for the self-tests of run_short_quality.sh and the pin of quality.yml's scope
# (forsgren#230, step 2), and to 142 for the preview deploy's script self-test and
# workflow pin (forsgren#222), and to 143 for the pre-check's self-test
# (forsgren#231, step 1).
# The self-proof below removes one row and requires the count to fall under the
# floor, so the floor has to track the current count exactly: a row cannot
# land here without someone raising the ratchet on purpose.
MIN_GATES=143

gate_count_of() {
  grep -v '^#' "$1" | grep -c . || true
}

if [[ -f "$ORDER" ]]; then
  declared="$(gate_count_of "$ORDER")"
  if [[ "$declared" -lt "$MIN_GATES" ]]; then
    fail "gate count fell to ${declared}, ratchet is ${MIN_GATES} — a gate was removed. Restore it, or raise MIN_GATES only if a gate was legitimately merged into another"
  fi
  SHRUNK="$(mktemp)"
  grep -v '^#' "$ORDER" | grep . | tail -n +2 > "$SHRUNK"
  if [[ "$(gate_count_of "$SHRUNK")" -ge "$MIN_GATES" ]]; then
    fail "the ratchet cannot detect a removed gate — it is measuring nothing"
  fi
  rm -f "$SHRUNK"
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
#   - the read that keeps a last line with no trailing newline (a row with
#     only a label counts as a last line too)
#   - the n/a skip
#   - the phase filter, after the row is validated
#   - the validation: a malformed row (no label, no script, a script that is
#     not a Scripts/<name>.sh path, a phase other than pre or post, an
#     unknown class) is a red row in whichever phase runs, never skipped
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
while IFS='|' read -r label script phase gate_class || [ -n "${label:-}${script:-}" ]; do
[ "${script:-}" = "n/a" ] && continue
[ "$phase" = "$PHASE" ] || continue
bad="the row has no label"
bad="the row names no script"
*) bad="its script ${script} is not a Scripts/<name>.sh path" ;;
*) bad="its phase '${phase:-}' is neither pre nor post, so no phase would ever run it" ;;
*) bad="its class '${gate_class:-}' is neither empty nor secret-class" ;;
RULES
grep -qF 'done < Scripts/gate_report_order.txt' "$SFL" \
  || fail "${SFL} no longer reads Scripts/gate_report_order.txt — sfl and CI must run the same rows"
grep -qF 'ORDER="Scripts/gate_report_order.txt"' "$CI_RUNNER" \
  || fail "${CI_RUNNER} no longer reads Scripts/gate_report_order.txt — sfl and CI must run the same rows"

# --- 2b. THE BASELINES ON THE RUN PAGE (forsgren#220) -----------------------
#
# The baselines are shown on the Quality run page, one step per gate, each by
# name, each `if: always()` (so it shows when a gate is red), each calling
# Scripts/report_baselines.sh with its own section.
baseline_step_problems() {
  local wf="$1" pair name arg block
  for pair in "Language baselines:language" "Browser baselines:browser" "Image baselines:image"; do
    name="${pair%%:*}"
    arg="${pair##*:}"
    block="$(awk -v n="      - name: ${name}" '
      $0 == n { on = 1; print; next }
      on && /^      - / { exit }
      on { print }
    ' "$wf")"
    if [[ -z "$block" ]]; then
      echo "the workflow has no step named '${name}'"
      continue
    fi
    grep -qE '^[[:space:]]+if: always\(\)[[:space:]]*$' <<< "$block" \
      || echo "the step '${name}' is not 'if: always()', so it would vanish when a gate is red"
    grep -vE '^[[:space:]]*#' <<< "$block" | grep -qE "^[[:space:]]*\./Scripts/report_baselines\.sh ${arg}[[:space:]]*$" \
      || echo "the step '${name}' does not run ./Scripts/report_baselines.sh ${arg}"
  done
}
problems="$(baseline_step_problems "$CI")"
[[ -z "$problems" ]] || fail "quality.yml must show the baselines, one step per gate: ${problems}"

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

    # PRESENTATION, not a gate (forsgren#220): it renders the baseline data
    # files as markdown tables on CI's run page, one Quality step per gate
    # (pin 2b below). Same terms as the report renderer: CI must call it and it
    # must have a fixture.
    report_baselines.sh)
      runs_script "$CI" "$base" \
        || fail "${base} renders the baselines on CI's run page and ${CI} never invokes it — a renderer nobody calls is a file, not a report"
      require_fixture "$base"
      ;;

    # THE CANON LANGUAGE GATE (forsgren#220): the order file runs it through
    # Scripts/gate_language_pages.sh, which puts the metrics site and the
    # starter page in one directory (a row names a script, not a command
    # line). The wrapper must still call it, and it must keep its fixture.
    gate_language.sh)
      runs_script "Scripts/gate_language_pages.sh" "$base" \
        || fail "${base} is the language gate and Scripts/gate_language_pages.sh, the row that runs it, never invokes it"
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

    # READER, not a gate (forsgren#2): it prints the Node major pinned in
    # .nvmrc for check_node_pin.sh, the gate (a row of its own), which must
    # still call it, and for CI's setup-node step later. Fixture required.
    node_pin.sh)
      runs_script "Scripts/check_node_pin.sh" "$base" \
        || fail "${base} reads the Node pin and Scripts/check_node_pin.sh never invokes it — the gate would not read .nvmrc"
      require_fixture "$base" "a pin reader with no fixture can print the wrong major and nothing would notice"
      ;;

    # PRE-FLIGHT, not a gate (forsgren#2): sfl's npm install step. It runs
    # `npm ci` when node_modules is missing or older than the lockfile. CI
    # checks out a fresh tree and runs `npm ci` itself, so only sfl calls it.
    npm_sync_install.sh)
      runs_script "$SFL" "$base" \
        || fail "${base} reinstalls node_modules on a lockfile change and ${SFL} never invokes it — sfl would run the old node_modules after a lockfile bump"
      require_fixture "$base" "an install step with no fixture can skip the install and nothing would notice"
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
      for consumer in test_fbp_commit_message.sh test_fbp_build_pagecount.sh test_fbp_aborted.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} holds the shared FBP sandbox and Scripts/${consumer} never sources it"
      done
      ;;

    # SOURCED HELPER, not a gate (forsgren#228): unsets the variables by which
    # git locates a repository. Scripts/test_git_sandbox_guard.sh is its test
    # and holds that every git-using self-test sources it; this guards the
    # other way, that the guard itself does.
    lib_git_sandbox.sh)
      runs_script "Scripts/test_git_sandbox_guard.sh" "$base" \
        || fail "${base} isolates the self-tests from an exported GIT_DIR and Scripts/test_git_sandbox_guard.sh never sources it"
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

    # SOURCED HELPER, not a gate (forsgren#52, refactor): the private-names
    # list parsing the gate and the secret sync share. Their self-tests are
    # its test, and both must still source it.
    lib_private_names.sh)
      for consumer in check_private_names.sh sync_private_names_secrets.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} holds the private-names list parsing and Scripts/${consumer} never sources it"
      done
      ;;

    # SOURCED HELPER, not a gate (forsgren#204): the one listing of the
    # files a gate judges, tracked plus untracked and not ignored. The
    # self-tests of the five gates that source it are its test, and all five
    # must still source it (a plain grep: the data guard's mutants source it
    # from beside them, so the path is not always Scripts/<name>).
    lib_repo_files.sh)
      for consumer in check_shellcheck.sh check_yamllint.sh check_markdown_links.sh check_guardrail_packages.sh check_data_guard.sh; do
        grep -qE '^source .*lib_repo_files\.sh"?$' "Scripts/${consumer}" \
          || fail "${base} holds the file listing and Scripts/${consumer} never sources it"
      done
      ;;

    # SOURCED HELPER, not a gate (forsgren#59, refactor): the awk readers of
    # a workflow file the pins of the two reusable workflows share. Those
    # pins are its test, and both must still source it.
    lib_workflow_steps.sh)
      for consumer in test_metrics_workflow.sh test_auto_update_workflow.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} holds the workflow readers and Scripts/${consumer} never sources it"
      done
      ;;

    # DCO WORKFLOW CHECK, not a gate of sfl or Quality (road to public,
    # step 4): every commit of a pull request, and of a push to main
    # (forsgren#81), carries a DCO sign-off from its author. It judges the
    # commits a pull request or a push brings, which neither runner has;
    # .github/workflows/dco.yml runs it, on a GitHub-hosted runner, and its
    # self-test is an order-file row, so sfl and Quality still prove it.
    check_dco.sh)
      runs_script "$DCO_WF" "$base" \
        || fail "${base} checks a pull request's sign-offs and ${DCO_WF} never invokes it — no pull request would be checked"
      require_fixture "$base" "the sign-off check would wave commits through unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the check dco.yml relies on"
      ;;

    # THE LIVE CHECK, not a local gate (forsgren#205, step 2 of 2): it checks
    # the DEPLOYED forsgren.be with curl, so only the live-check job of
    # .github/workflows/starter_page.yml can run it, after a deploy. Its
    # self-test (stub curl, no network) is an order-file row, so sfl and
    # Quality still prove it.
    live_check.sh)
      runs_script "$STARTER_WF" "$base" \
        || fail "${base} checks the live site after a deploy and ${STARTER_WF} never invokes it — nothing would check forsgren.be"
      require_fixture "$base" "the live check would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the check starter_page.yml runs"
      ;;

    # THE PREVIEW DISPATCH, not a local gate (forsgren#222): it starts the
    # preview repository's deploy through the GitHub API with a token only
    # CI holds, so only the preview job of .github/workflows/quality.yml can run it,
    # after a push to main and Quality green. Its self-test (stub curl, no network) is an order-file
    # row, so sfl and Quality still prove it.
    dispatch_preview.sh)
      runs_script "$CI" "$base" \
        || fail "${base} starts the preview deploy and ${CI} never invokes it — no push would start a preview"
      require_fixture "$base" "the preview start would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the script the preview job runs"
      ;;

    # THE RELEASE SCRIPTS, not gates (forsgren#221): the Release workflow
    # (.github/workflows/release.yml) runs each of them, and its own pin
    # (Scripts/test_release_workflow.sh) holds the order and the arguments.
    # Their self-tests are order-file rows, so sfl and Quality prove them.
    # A script the workflow never calls would be a release step nobody runs.
    release_plan.sh|release_bump.sh|release_quality.sh|release_commit.sh|release_publish.sh|release_pins.sh|release_report.sh|release_resume.sh|release_token_expiry.sh|release_metrics.sh)
      runs_script "$RELEASE_WF" "$base" \
        || fail "${base} is a step of the release and ${RELEASE_WF} never invokes it — that step would be done by hand"
      require_fixture "$base" "the release step would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove ${base}"
      ;;

    # THE BUMP DIFF CHECK (forsgren#230): checks the bump commit. The Release
    # workflow reaches it through quality.yml: the short Quality (scope=bump)
    # runs it first, and the release dispatches that scope. So quality.yml
    # must invoke it, its self-test must be an order-file row, and it must read
    # the one list of the files a bump may change.
    release_bump_diff.sh)
      runs_script "$CI" "$base" \
        || fail "${base} checks the bump commit and ${CI} (the short Quality, scope=bump) never invokes it — a bump commit would be released unread"
      require_fixture "$base" "the bump commit check would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove ${base}"
      grep -qF 'lib_release_bump_scope.sh' "Scripts/${base}" \
        || fail "${base} does not source Scripts/lib_release_bump_scope.sh — its list of allowed files could drift from the bump's"
      ;;

    # THE SHORT QUALITY (forsgren#230, step 2): quality.yml runs it, for
    # scope=bump, instead of the PRE phase. Its self-test and the pin of the
    # workflow's scope are order-file rows.
    run_short_quality.sh)
      runs_script "$CI" "$base" \
        || fail "${base} runs the short Quality and ${CI} never invokes it — scope=bump would run no gate"
      require_fixture "$base" "the short Quality would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove ${base}"
      order_names "test_quality_scope.sh" \
        || fail "Scripts/test_quality_scope.sh is not an order-file row — nothing would hold quality.yml's scope to the short Quality"
      ;;

    # SOURCED HELPER, not a gate (forsgren#230): the files a release bump may
    # change, read by release_bump.sh and release_bump_diff.sh alike. The
    # self-test of the latter proves it.
    lib_release_bump_scope.sh)
      order_names "test_release_bump_diff.sh" \
        || fail "${base} is read by the bump check and Scripts/test_release_bump_diff.sh is not an order-file row"
      grep -qF 'lib_release_bump_scope.sh' Scripts/release_bump.sh \
        || fail "${base} lists the files of a bump and Scripts/release_bump.sh never reads it — the list could drift"
      ;;

    # THE PIN CHECK of the Release workflow's metrics step (forsgren#221, step 5):
    # release_metrics.sh runs it on the pull request's files before it merges
    # anything, so that script, not the workflow, must invoke it.
    release_verify_pin.sh)
      runs_script "Scripts/release_metrics.sh" "$base" \
        || fail "${base} reads a pin pull request and Scripts/release_metrics.sh never invokes it — a pull request would be merged unread"
      require_fixture "$base" "the pin check would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove ${base}"
      ;;

    # HELPER OF THE DCO CHECK, not a gate (forsgren#81): lists the commits of
    # a push in check_dco.sh's input shape. Scripts/test_check_dco.sh, an
    # order-file row, is its test and must still run it; dco.yml runs it on
    # a push to main, and must trigger on one.
    dco_push_commits.sh)
      runs_script "Scripts/test_check_dco.sh" "$base" \
        || fail "${base} lists a push's commits for the DCO check and Scripts/test_check_dco.sh never runs it — the listing would be unproven"
      runs_script "$DCO_WF" "$base" \
        || fail "${base} lists a push's commits for the DCO check and ${DCO_WF} never invokes it — a push to main would not be checked"
      awk '/^  push:/ { p = 1; next } /^  [A-Za-z_]+:/ { p = 0 } p && /branches:.*"main"/ { f = 1 } END { exit !f }' "$DCO_WF" \
        || fail "${DCO_WF} has no push trigger on main — ${base} would list commits nobody checks"
      ;;

    # HAND-RUN BY THE LOOP, never by sfl or a workflow: a thin exec wrapper
    # around FBP.sh under the agent-Friend identity. Requiring a runner to
    # invoke it would mean FBP invoking itself. CLAUDE.md declares it.
    fbp_agent_friend.sh)
      grep -qF 'Scripts/fbp_agent_friend.sh' CLAUDE.md \
        || fail "${base} is run by hand and CLAUDE.md no longer declares it — an undeclared script nobody runs is a file, not a tool"
      ;;

    # HAND-RUN, not a gate (forsgren#52): run by hand to sync the private-names
    # list into the FORSGREN_PRIVATE_NAMES Actions and Dependabot secrets. No
    # runner invokes it (it needs the maintainer's gh login), so it must carry
    # a fixture, and that fixture must be an order-file row.
    sync_private_names_secrets.sh)
      require_fixture "$base" "the secret sync would be untested"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the secret sync"
      ;;

    # LOCAL PRE-FLIGHT, not a gate (forsgren#52): FBP.sh calls it before the
    # PRE gates to create an empty private-names list when none is given. CI
    # never runs FBP.sh, so CI stays strict. It must carry a fixture, and that
    # fixture must be an order-file row.
    ensure_private_names_file.sh)
      runs_script "$FBP" "$base" \
        || fail "${base} exists and FBP.sh never runs it — a contributor without the list could not run FBP"
      require_fixture "$base" "the local list creation would be untested"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the local list creation"
      ;;

    # SOURCE CSS FIX, not a gate (forsgren#215): FBP.sh runs it, with
    # GATE_FIX=1, on the source internal/page/styles.css before the build.
    # CI never runs it (it only checks), so no workflow may name it. Its
    # self-test is an order-file row, so sfl and Quality prove it.
    fix_source_css.sh)
      runs_script "$FBP" "$base" \
        || fail "${base} fixes the source CSS and ${FBP} never invokes it — the generated stylesheet would be fixed too late or not at all"
      if grep -rqF "$base" .github/workflows; then
        fail "a workflow names ${base} — CI only checks and must never fix the source CSS"
      fi
      require_fixture "$base" "the source CSS fix would be untested"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the source CSS fix"
      ;;

    # SOURCED HELPER, not a gate (estate canon): the one reader of
    # Scripts/site_settings.txt. The gates that need a per-repository value
    # source it; its self-test is an order-file row, and the gates below must
    # still source it.
    lib_site_settings.sh)
      for consumer in gate_htmlhint.sh gate_stylelint.sh check_lint_coverage.sh check_html_dupl.sh validate_required_pages.sh check_privacy_posture.sh; do
        grep -qE '^[[:space:]]*source .*lib_site_settings\.sh"?$' "Scripts/${consumer}" \
          || fail "${base} holds the settings reader and Scripts/${consumer} never sources it"
      done
      order_names "test_lib_site_settings.sh" \
        || fail "Scripts/test_lib_site_settings.sh is not an order-file row — the settings reader would be unproven"
      ;;

    # SOURCED HELPER, not a gate (forsgren#216): how the four Go-tool gates
    # resolve and run their go.mod-pinned tool. Each must still source it, and
    # its self-test is an order-file row.
    lib_go_tool.sh)
      for consumer in check_govulncheck.sh check_deadcode.sh check_go_lint.sh check_test_dupl.sh; do
        grep -qE '^source .*lib_go_tool\.sh"?$' "Scripts/${consumer}" \
          || fail "${base} holds the Go tool resolver and Scripts/${consumer} never sources it"
      done
      order_names "test_lib_go_tool.sh" \
        || fail "Scripts/test_lib_go_tool.sh is not an order-file row — the Go tool resolver would be unproven"
      ;;

    # WRITER TOOL, not a gate (forsgren#231): the pre-check a writer runs
    # before handing a change back. It runs gates' own scripts on the changed
    # files and judges nothing FBP and CI do not; FBP.sh and quality.yml never
    # call it. Required to have a fixture, and its self-test is an order-file
    # row (which also pins that every gate it runs is an order-file row).
    precheck.sh)
      require_fixture "$base" "the pre-check would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the pre-check"
      ;;

    # SOURCED HELPER, not a gate (estate canon): the engine of the exit-trap
    # behaviour test, which sources it. The test is its own order-file row.
    lib_exit_trap_probe.sh)
      runs_script "Scripts/test_exit_trap_completion_behaviour.sh" "$base" \
        || fail "${base} holds the exit-trap probe engine and Scripts/test_exit_trap_completion_behaviour.sh never sources it"
      ;;

    *)
      fail "${base} is a script no order-file row names and no declared exemption covers — a validator nobody runs is a file, not a gate"
      ;;
  esac
done


# --- 4. THE CI LOOP, AT RUNTIME ----------------------------------------------
#
# Pinned by Scripts/test_run_ci_phase.sh (an order-file row, the estate canon):
# the runner over throwaway order files with stub gates, over the REAL order
# file with a stub at every declared path (each runnable row exactly once, in
# its own phase, in file order), and against weakened copies of the runner.
# The cases that used to sit here moved there unchanged in what they require.

# --- 5. PROOFS ----------------------------------------------------------------
#
# Each proof re-runs this whole check against a copy of one runner file (or of
# the order file) whose real invocation is turned into a comment, or one rule
# broken, while other lines keep MENTIONING it. The check must reject that
# copy, by name.
#
# mutation_proof <override-var> <mention> <sed-expr> <expected> <label>
#   <override-var>  GATE_WIRING_CI_OVERRIDE, GATE_WIRING_FBP_OVERRIDE,
#                   GATE_WIRING_SFL_OVERRIDE, GATE_WIRING_ORDER_OVERRIDE,
#                   GATE_WIRING_DCO_OVERRIDE or GATE_WIRING_STARTER_OVERRIDE
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
    GATE_WIRING_STARTER_OVERRIDE) original="$STARTER_WF" ;;
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
# another estate repository's Scripts/test_gate_wiring.sh; issue numbers in it are
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
  MUTATION_TMP="$(mktemp -d)"
  trap 'rm -rf "$MUTATION_TMP"; finish' EXIT
  MUTANT_N=0

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

  # quality.yml: the baseline steps (forsgren#220), each broken once.
  mutation_proof GATE_WIRING_CI_OVERRIDE "Browser baselines" \
    's|^      - name: Browser baselines$|      - name: Browser baselines (renamed)|' \
    "no step named 'Browser baselines'" \
    "a quality.yml without the Browser baselines step"
  mutation_proof GATE_WIRING_CI_OVERRIDE "Image baselines" \
    '/name: Image baselines/,$ s|^        if: always\(\)$|        if: success()|' \
    "'Image baselines' is not 'if: always()'" \
    "a quality.yml whose Image baselines step is not always()"
  mutation_proof GATE_WIRING_CI_OVERRIDE "report_baselines.sh language" \
    's|^( *)\./Scripts/report_baselines\.sh language$|\1: report_baselines.sh language|' \
    "does not run ./Scripts/report_baselines.sh language" \
    "a quality.yml whose Language baselines step does not call the report"

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
  mutation_proof GATE_WIRING_SFL_OVERRIDE "PHASE" \
    's#^([[:space:]]*)(\[ "[$]phase" = )#\1\# \2#' \
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

  # dco.yml: the push-listing call becomes a comment, then the push trigger
  # becomes another one.
  mutation_proof GATE_WIRING_DCO_OVERRIDE "Scripts/dco_push_commits.sh" \
    's|^([[:space:]]*)(\./Scripts/dco_push_commits\.sh )|\1# \2|' \
    "dco_push_commits.sh lists a push's commits for the DCO check and" \
    "a dco.yml whose dco_push_commits.sh call is a comment"
  mutation_proof GATE_WIRING_DCO_OVERRIDE "Scripts/dco_push_commits.sh" \
    's|^  push:|  workflow_dispatch:|' \
    "has no push trigger on main" \
    "a dco.yml with no push trigger"

  # starter_page.yml: the live check call becomes a comment.
  mutation_proof GATE_WIRING_STARTER_OVERRIDE "Scripts/live_check.sh" \
    's|^([[:space:]]*)(run: \./Scripts/live_check\.sh )|\1run: # \2|' \
    "live_check.sh checks the live site after a deploy and" \
    "a starter_page.yml whose live_check.sh call is a comment"

  # The order file: the live check self-test row becomes a comment.
  mutation_proof GATE_WIRING_ORDER_OVERRIDE "Scripts/test_live_check.sh" \
    's#^(live check self-test\|)#\# \1#' \
    "Scripts/test_live_check.sh is not an order-file row" \
    "an order file whose live check self-test row is a comment"

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

# Pin 6 (forsgren#214, canon from the sister site repositories): FBP FIXES, CI
# ONLY CHECKS. sfl.sh exports GATE_FIX=1 (the npm audit heal runs only under
# it); no workflow may set it, or CI would change files instead of reporting
# what the commit contains. Mutations built here: an sfl.sh without the
# export, and a workflow copy that mentions GATE_FIX, must each be rejected.
# Adapted from the canon only in its file names: forsgren's workflows live in
# .github/workflows and quality.yml is the one the mutation appends to.
if ! is_mutation_rerun; then
  fix_wiring_problems() {
    local sfl="$1" wf="$2"
    grep -qE '^export GATE_FIX=1$' "$sfl" || echo "sfl.sh does not export GATE_FIX=1"
    if grep -rqF 'GATE_FIX' "$wf"; then echo "a workflow mentions GATE_FIX"; fi
  }
  WF_DIR=".github/workflows"
  problems="$(fix_wiring_problems "$SFL" "$WF_DIR")"
  [[ -z "$problems" ]] || fail "FBP must fix and CI only check: ${problems}"
  _t="$(mktemp -d)"
  grep -v '^export GATE_FIX=1$' "$SFL" > "${_t}/sfl.sh"
  mkdir -p "${_t}/wf"
  cp "$WF_DIR"/*.yml "${_t}/wf/"
  printf '# GATE_FIX=1\n' >> "${_t}/wf/quality.yml"
  if cmp -s "$SFL" "${_t}/sfl.sh"; then
    fail "the no-export mutation changed nothing — pin 6 matches something other than the export line"
  elif ! grep -qF 'does not export' <<< "$(fix_wiring_problems "${_t}/sfl.sh" "$WF_DIR")"; then
    fail "an sfl.sh without the GATE_FIX export was accepted — pin 6 does not guard it"
  fi
  if ! grep -qF 'a workflow mentions' <<< "$(fix_wiring_problems "$SFL" "${_t}/wf")"; then
    fail "a workflow that mentions GATE_FIX was accepted — pin 6 does not guard CI staying check-only"
  fi
  rm -rf "$_t"
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: gate wiring"
  exit 1
fi

echo "OK: gate wiring (${n_rows} rows run by sfl and by CI in their declared phase, ${n_gate} gate scripts among them, ${n_exempt} declared exemptions run by their required runners)"
