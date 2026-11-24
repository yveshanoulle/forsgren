#!/usr/bin/env bash
# Scripts/gate_wiring_local_cases.sh
#
# forsgren's own arms and pins of the gate wiring check (canon
# test_gate_wiring v15, estate issue 850). forsgren's quality.yml names no
# gate: it runs Scripts/gate_report_order.txt through Scripts/run_ci_phase.sh,
# phase by phase, as sfl.sh does, so what is forsgren's own here is:
#   1. ROWS. Every runnable row of the order file has phase `pre` or `post`
#      and class empty or `secret-class`. Both runners run only pre and post
#      rows, so a row with any other phase ("Pre", "build", a typo, nothing)
#      runs in NEITHER, and nothing else reports it missing.
#   2. RUNNERS. FBP.sh runs `./sfl.sh pre`, Scripts/build_site.sh and
#      `./sfl.sh post`, in that order; quality.yml runs
#      `Scripts/run_ci_phase.sh pre`, Scripts/build_site.sh and
#      `Scripts/run_ci_phase.sh post`, in that order. And sfl.sh and
#      run_ci_phase.sh carry the same row rules, line for line. Then the
#      canon's baseline steps pin (forsgren#220).
#   3. SCRIPTS OUTSIDE THE ORDER FILE. A script an order-file row names is a
#      gate (parts 1 and 2 run it in both); every other one is a declared
#      exemption below, each with its reason and the runner it must still be
#      invoked by.
#   4. THE CI LOOP, AT RUNTIME. Pinned by Scripts/test_run_ci_phase.sh, its
#      own order-file row (not repeated here).
#   8. TWO WORKFLOWS (forsgren#686). quality.yml runs the real gates and
#      selftests.yml the self-test rows; every runnable row runs in exactly
#      one of them, the one its kind names, with the secret-scan self-test the
#      one written exception (see "Pin 8" below).
#   5. PROOFS. Mutation proofs re-run the whole check against a copy of a
#      runner, of dco.yml, of starter_page.yml or of the order file with one
#      invocation commented out or one rule broken, and require the rejection
#      by name; two more guard samples for the matcher self-proof.
# The sites' pins with no counterpart here, not taken over: their pin 7 (sfl.sh
# runs the local private-names pre-flight; forsgren's FBP.sh runs it, the
# ensure_private_names_file.sh arm), their pin 5 (a feta deploy workflow keyed
# off Quality) and their build boundary, built site check and CI exemption
# list arms.
#
# SOURCED by the canon Scripts/test_gate_wiring.sh, never run alone (its
# LOCAL_CASES line names this file); it uses that file's helpers (fail,
# runs_script, order_names, require_fixture, tmp_dir, has, mutation_proof,
# matcher_accepts, is_mutation_rerun, baseline_step_pin) and the runner paths
# SFL, FULL_BUILD, CI and ORDER. The pins below are written at the left margin
# inside their functions, as they stood in forsgren's copy of the check before
# canon v15, so their multi-line sed expressions stay byte for byte.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "$0 is sourced by Scripts/test_gate_wiring.sh; run that" >&2
  exit 2
fi

# The canon's runner paths, set before it sources this file; a run without
# them is a run outside the canon, and stops here.
SFL="${SFL:?set by Scripts/test_gate_wiring.sh}"
FULL_BUILD="${FULL_BUILD:?set by Scripts/test_gate_wiring.sh}"
CI="${CI:?set by Scripts/test_gate_wiring.sh}"
ORDER="${ORDER:?set by Scripts/test_gate_wiring.sh}"

# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
# shellcheck source=Scripts/lib_tmp.sh
source Scripts/lib_tmp.sh

# The files only these cases' proofs replace are overridable ONLY for those
# proofs; nothing else sets them.
FBP="$FULL_BUILD"
DCO_WF="${GATE_WIRING_DCO_OVERRIDE:-.github/workflows/dco.yml}"
STARTER_WF="${GATE_WIRING_STARTER_OVERRIDE:-.github/workflows/starter_page.yml}"
RELEASE_WF=".github/workflows/release.yml"
CI_RUNNER="Scripts/run_ci_phase.sh"

# gate_wiring_local_is_rerun: a file only these cases override is replaced.
gate_wiring_local_is_rerun() {
  [[ -n "${GATE_WIRING_DCO_OVERRIDE:-}${GATE_WIRING_STARTER_OVERRIDE:-}" ]]
}

# gate_wiring_local_original <override-var>: the file that override replaces.
gate_wiring_local_original() {
  case "$1" in
    GATE_WIRING_DCO_OVERRIDE) echo "$DCO_WF" ;;
    GATE_WIRING_STARTER_OVERRIDE) echo "$STARTER_WF" ;;
    *) return 1 ;;
  esac
}

# gate_wiring_local_fixture <base>: forsgren has no CI-only fixture, so every
# fixture takes the canon's default (an order row; Scripts/
# test_sfl_drives_from_order_file.sh's pin 4 holds the same).
gate_wiring_local_fixture() {
  return 1
}

# gate_wiring_local_script <base>: status 0 when <base> is a declared
# exemption, judged here, 1 for the canon's default (an order row, else red).
gate_wiring_local_script() {
  local base="$1" consumer selftest_users
  # A script an order-file row names is a gate: parts 1 and 2 run it in both.
  order_names "$base" && return 1

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
      return 0
      ;;

    # CI's gate loop: quality.yml runs it once per phase. Its tests are
    # part 4 of this file.
    run_ci_phase.sh)
      runs_script "$CI" "$base" \
        || fail "${base} is CI's gate loop and ${CI} never invokes it — no gate would run in CI at all"
      return 0
      ;;

    # PRESENTATION, not a gate. It renders CI's step summary from the rows
    # and details run_ci_phase.sh writes. Required in the runner that uses
    # it, AND required to have a fixture: a presentation script that breaks
    # makes the report lie, and nothing else is watching it.
    render_quality_report.sh)
      runs_script "$CI" "$base" \
        || fail "${base} renders CI's step summary and CI never invokes it — a renderer nobody calls is a file, not a report"
      require_fixture "$base"
      return 0
      ;;

    # PRESENTATION, not a gate (forsgren#220): it renders the baseline data
    # files as markdown tables on CI's run page, one Quality step per gate
    # (pin 2b below). Same terms as the report renderer: CI must call it and it
    # must have a fixture.
    report_baselines.sh)
      runs_script "$CI" "$base" \
        || fail "${base} renders the baselines on CI's run page and ${CI} never invokes it — a renderer nobody calls is a file, not a report"
      require_fixture "$base"
      return 0
      ;;

    # THE CANON LANGUAGE GATE (forsgren#220): the order file runs it through
    # Scripts/gate_language_pages.sh, which puts the metrics site and the
    # starter page in one directory (a row names a script, not a command
    # line). The wrapper must still call it, and it must keep its fixture.
    gate_language.sh)
      runs_script "Scripts/gate_language_pages.sh" "$base" \
        || fail "${base} is the language gate and Scripts/gate_language_pages.sh, the row that runs it, never invokes it"
      require_fixture "$base"
      return 0
      ;;

    # BUILD HELPER, not a gate (forsgren#226): it renders the site from the
    # made-up fixture, which the browser gate opens as its data site. The gate
    # (a row of its own) must still build it. Its fixture is cases 20 to 30 of
    # test_build_site.sh, a row of its own, not a test_build_fixture_site.sh.
    build_fixture_site.sh)
      runs_script "Scripts/gate_browser_fixture.sh" "$base" \
        || fail "${base} renders the data site and Scripts/gate_browser_fixture.sh, the row that opens it, never invokes it — the History, Daily and Issues pages would not be opened"
      return 0
      ;;

    # PRESENTATION, not a gate (forsgren#259): it hands over each Quality
    # job's rows and details and merges them into the one report the renderers
    # read, and judges the run's status from the jobs' results. CI must call
    # it and it must have a fixture, as for the renderers.
    merge_quality_report.sh)
      runs_script "$CI" "$base" \
        || fail "${base} merges the Quality jobs' reports and ${CI} never invokes it — each job's gates would be missing from the report"
      require_fixture "$base"
      return 0
      ;;

    # PRE-FLIGHT, not a gate (forsgren#686): it lists the self-test rows, the
    # rows of selftests.yml's jobs, which sfl.sh skips locally by default. sfl
    # must call it (or every self-test would run locally again, or none), and
    # its self-test, Scripts/test_sfl_selftest_skip.sh, must be a row.
    selftest_rows.sh)
      runs_script "$SFL" "$base" \
        || fail "${base} lists the self-test rows sfl.sh skips and ${SFL} never invokes it — the local run would not run what Quality runs"
      order_names "test_sfl_selftest_skip.sh" \
        || fail "Scripts/test_sfl_selftest_skip.sh is not an order-file row — the self-test list sfl relies on would go unproven"
      return 0
      ;;

    # SELF-TESTS WORKFLOW STEP, not a gate (forsgren#686): it opens the one
    # issue of a red Self-tests run on main. The failure_issue job of
    # selftests.yml runs it, and its self-test,
    # Scripts/test_selftests_failure_issue.sh, must be a row.
    open_selftests_failure_issue.sh)
      runs_script ".github/workflows/selftests.yml" "$base" \
        || fail "${base} opens the issue of a red Self-tests run and selftests.yml never invokes it — a red self-test on main would be seen by nobody"
      order_names "test_selftests_failure_issue.sh" \
        || fail "Scripts/test_selftests_failure_issue.sh is not an order-file row — the failure issue would go unproven"
      return 0
      ;;

    # THE REPORT DISPATCH, not gates: selftests.yml sends its start (the
    # report_start job) and its outcome (the report job's last step) to the
    # maintainer's receiving repository with Scripts/dispatch_report.sh, the
    # counts from Scripts/selftests_counts.sh (quality.yml's report_start job
    # sends its start and its report job its result with it too). One self-test,
    # Scripts/test_report_dispatch.sh, proves both and must be a row.
    dispatch_report.sh|selftests_counts.sh)
      runs_script ".github/workflows/selftests.yml" "$base" \
        || fail "${base} reports a Self-tests run and selftests.yml never invokes it — the run would not be reported"
      order_names "test_report_dispatch.sh" \
        || fail "Scripts/test_report_dispatch.sh is not an order-file row — the report would go unproven"
      return 0
      ;;

    # PRESENTATION, not a gate (forsgren#8): the run's key numbers, rendered
    # above the gate report in CI's step summary from what the run wrote.
    # Same two requirements as the report renderer, for the same reason.
    render_quality_summary.sh)
      runs_script "$CI" "$base" \
        || fail "${base} renders the run summary at the top of CI's step summary and CI never invokes it — a renderer nobody calls is a file, not a summary"
      require_fixture "$base"
      return 0
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
      return 0
      ;;

    # PRE-FLIGHT, not a gate (a sibling site's unit 414): it installs the tools the
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
      return 0
      ;;

    # THE LINUX PATH OF THE INSTALLER (forsgren#427), not a gate: forsgren's
    # own. The Linux jobs of quality.yml run it, in their Install tools step
    # (the estate's install_tools.sh stays byte-identical). Its own fixture
    # runs as a row of the order file.
    install_tools_linux.sh)
      runs_script "$CI" "$base" \
        || fail "${base} installs the pinned Linux tools and ${CI} never invokes it — \
the Lint gates job would have no way to install a tool"
      require_fixture "$base" "an installer with no fixture fails by leaving a machine looking correctly configured"
      return 0
      ;;

    # READER, not a gate (forsgren#2): it prints the Node major pinned in
    # .nvmrc for check_node_pin.sh, the gate (a row of its own), which must
    # still call it, and for CI's setup-node step later. Fixture required.
    node_pin.sh)
      runs_script "Scripts/check_node_pin.sh" "$base" \
        || fail "${base} reads the Node pin and Scripts/check_node_pin.sh never invokes it — the gate would not read .nvmrc"
      require_fixture "$base" "a pin reader with no fixture can print the wrong major and nothing would notice"
      return 0
      ;;

    # PRE-FLIGHT, not a gate (forsgren#2): sfl's npm install step. It runs
    # `npm ci` when node_modules is missing or older than the lockfile. CI
    # checks out a fresh tree and runs `npm ci` itself, so only sfl calls it.
    npm_sync_install.sh)
      runs_script "$SFL" "$base" \
        || fail "${base} reinstalls node_modules on a lockfile change and ${SFL} never invokes it — sfl would run the old node_modules after a lockfile bump"
      require_fixture "$base" "an install step with no fixture can skip the install and nothing would notice"
      return 0
      ;;

    # PRE-FLIGHT SYNCHRONISATION, not a gate. sfl sources it before PRE so
    # the run starts from the latest upstream state: a fast-forward, or a
    # rebase over incoming commits on other files (forsgren#283, step 2). CI
    # checks out the exact commit it evaluates and must not pull another.
    sfl_pull.sh)
      runs_script "$SFL" "$base" \
        || fail "${base} provides sfl's opening pull and sfl never sources it"
      require_fixture "$base" "the pull contract would be untested"
      return 0
      ;;

    # PRESENTATION, not a gate: sfl's end-of-run block. CI builds its report
    # from the rows and details instead.
    summarize_gate_failure.sh|render_step_table.sh)
      runs_script "$SFL" "$base" \
        || fail "${base} renders part of sfl's end-of-run output and sfl never invokes it — a renderer nobody calls is a file, not a report"
      require_fixture "$base" "a presentation script with no fixture fails silently, because nothing else reads its output closely enough to notice"
      return 0
      ;;

    # SOURCED HELPER, not a gate (a sibling site's issue 14): the throwaway FBP
    # sandbox both FBP fixtures drive. They are its test, and both must
    # still source it.
    lib_fbp_sandbox.sh)
      for consumer in test_fbp_commit_message.sh test_fbp_build_pagecount.sh test_fbp_aborted.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} holds the shared FBP sandbox and Scripts/${consumer} never sources it"
      done
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#228): unsets the variables by which
    # git locates a repository. Scripts/test_git_sandbox_guard.sh is its test
    # and holds that every git-using self-test sources it; this guards the
    # other way, that the guard itself does.
    lib_git_sandbox.sh)
      runs_script "Scripts/test_git_sandbox_guard.sh" "$base" \
        || fail "${base} isolates the self-tests from an exported GIT_DIR and Scripts/test_git_sandbox_guard.sh never sources it"
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#446): deals the git sandbox isolation
    # self-tests to the shards by their weights. The isolation gate runs the
    # shards, and its scope self-test sources it to hold the balance.
    lib_isolation_shard.sh)
      for consumer in test_git_sandbox_isolation.sh test_git_sandbox_isolation_scope.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} deals the isolation shards and Scripts/${consumer} never sources it"
      done
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#569): starts the isolation shards side
    # by side locally. The isolation gate runs them, and its scope self-test
    # sources it to prove the concurrency and the failed and missing shard.
    lib_isolation_local.sh)
      for consumer in test_git_sandbox_isolation.sh test_git_sandbox_isolation_scope.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} starts the local isolation shards and Scripts/${consumer} never sources it"
      done
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#262): the changed files, the script
    # closure and gate_select. Scripts/test_gate_select.sh is its test, and the
    # inputs self-test and the git sandbox isolation gate are the other two
    # that must source it, as no copy of its functions is left in them.
    lib_gate_select.sh)
      for consumer in test_gate_select.sh test_gate_inputs.sh test_git_sandbox_isolation.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} holds the gate selection and Scripts/${consumer} never sources it"
      done
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#264): the scripts that write the step
    # summary and the self-tests that name them. The step summary isolation gate
    # and the inputs self-test must source it, so the two find the same files.
    lib_summary_writers.sh)
      for consumer in test_step_summary_isolation.sh test_gate_inputs.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} finds the step summary writers and Scripts/${consumer} never sources it"
      done
      return 0
      ;;

    # SOURCED HELPER, not a gate (a sibling site's issue 18): runs_script, the one
    # definition of what counts as running a script. Its test is the matcher
    # self-proof in part 5 of this file, which sources it.
    lib_runs_script.sh)
      runs_script "Scripts/test_gate_wiring.sh" "$base" \
        || fail "${base} holds runs_script and Scripts/test_gate_wiring.sh never sources it"
      return 0
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
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#52, refactor): the private-names
    # list parsing the gate and the secret sync share. Their self-tests are
    # its test, and both must still source it.
    lib_private_names.sh)
      for consumer in check_private_names.sh sync_private_names_secrets.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} holds the private-names list parsing and Scripts/${consumer} never sources it"
      done
      return 0
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
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#287): the GitHub API call of the
    # DCO workflow's two listings, asked once more when it fails. Their
    # self-tests are its test; both must still source it, and both jobs of
    # dco.yml must check it out beside them, or the sparse checkout would
    # leave the push check and the pull request listing without it.
    lib_dco_api.sh)
      for consumer in dco_push_check.sh dco_pr_commits.sh; do
        grep -qE '^source .*lib_dco_api\.sh"?$' "Scripts/${consumer}" \
          || fail "${base} holds the DCO scripts' API call and Scripts/${consumer} never sources it"
      done
      [[ "$(grep -cE '^[[:space:]]+Scripts/lib_dco_api\.sh$' "$DCO_WF")" -eq 2 ]] \
        || fail "${base} is sourced by the DCO listings and ${DCO_WF} does not check it out in both jobs — the job would stop on a missing file"
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#59, refactor): the awk readers of
    # a workflow file the pins of the reusable workflows share. Those pins
    # are its test, and each must still source it.
    lib_workflow_steps.sh)
      for consumer in test_metrics_workflow.sh test_auto_update_workflow.sh test_dependabot_merge_policy_workflow.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} holds the workflow readers and Scripts/${consumer} never sources it"
      done
      return 0
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
      return 0
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
      return 0
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
      return 0
      ;;

    # THE RELEASE SCRIPTS, not gates (forsgren#221): the Release workflow
    # (.github/workflows/release.yml) runs each of them, and its own pin
    # (Scripts/test_release_workflow.sh) holds the order and the arguments.
    # Their self-tests are order-file rows, so sfl and Quality prove them.
    # A script the workflow never calls would be a release step nobody runs.
    release_plan.sh|release_quality.sh|release_publish.sh|release_pins.sh|release_report.sh|release_resume.sh|release_token_expiry.sh|release_metrics.sh|release_verify_install.sh)
      runs_script "$RELEASE_WF" "$base" \
        || fail "${base} is a step of the release and ${RELEASE_WF} never invokes it — that step would be done by hand"
      require_fixture "$base" "the release step would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove ${base}"
      return 0
      ;;

    # THE TOKEN EXPIRY PROBE (forsgren#269), not a gate: the weekly workflow
    # runs it; its self-test, an order-file row, also pins that workflow.
    probe_token_expiry.sh)
      runs_script ".github/workflows/token_expiry_probe.yml" "$base" \
        || fail "${base} is the step of the token expiry probe and its workflow never invokes it — no token would be probed"
      require_fixture "$base" "the token expiry probe would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove ${base}"
      return 0
      ;;

    # THE DEPENDABOT MERGE POLICY (forsgren#664), not gates: the reusable merge
    # workflow (forsgren#666), which installations and this repository's own
    # dependabot_merge.yml call, runs both on Dependabot pull requests; their
    # self-tests, order-file rows, also pin the caller and its config, and
    # Scripts/test_dependabot_merge_policy_workflow.sh pins the called file.
    dependabot_merge_policy.sh|dependabot_pr_comment.sh)
      runs_script ".github/workflows/dependabot_merge_policy.yml" "$base" \
        || fail "${base} is a step of the reusable Dependabot merge workflow and it never invokes it — no Dependabot pull request would be judged"
      require_fixture "$base" "the Dependabot merge policy would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove ${base}"
      return 0
      ;;

    # THE AGENT PROOF CHECK (forsgren#237, step 5b): a major release needs a
    # proof run of every agent file on the new major. The plan decides the
    # bump, so release_plan.sh, not the workflow, must invoke it.
    release_agent_proofs.sh)
      runs_script "Scripts/release_plan.sh" "$base" \
        || fail "${base} holds a major release to the agent proofs and Scripts/release_plan.sh never invokes it — a major could be planned on unproved agent files"
      require_fixture "$base" "the agent proof check would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove ${base}"
      return 0
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
      return 0
      ;;

    # COMMIT MESSAGE CHECK, not a gate of sfl or Quality (forsgren#213): the
    # private-names matcher on the message of every commit a pull request or
    # a push brings. It judges commits neither runner has, so the second job
    # of .github/workflows/dco.yml runs it, and its self-test is an
    # order-file row, so sfl and Quality still prove it.
    check_commit_messages.sh)
      runs_script "$DCO_WF" "$base" \
        || fail "${base} checks the private names in commit messages and ${DCO_WF} never invokes it — no commit message would be checked"
      require_fixture "$base" "the commit message check would wave commits through unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the check dco.yml relies on"
      return 0
      ;;

    # HELPER OF THE DCO CHECK AND THE COMMIT MESSAGE CHECK, not a gate
    # (forsgren#213): lists a pull request's commits through gh, for both
    # jobs of dco.yml. Scripts/test_check_commit_messages.sh, an order-file
    # row, is its test and must still run it.
    dco_pr_commits.sh)
      runs_script "Scripts/test_check_commit_messages.sh" "$base" \
        || fail "${base} lists a pull request's commits and Scripts/test_check_commit_messages.sh never runs it — the listing would be unproven"
      runs_script "$DCO_WF" "$base" \
        || fail "${base} lists a pull request's commits and ${DCO_WF} never invokes it — a pull request would not be checked"
      return 0
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
      # forsgren#213: the commit message check lists a push with --fresh, so
      # a new branch or a before the checkout lacks is never listed as its
      # head commit alone, nor as nothing.
      grep -qE '^[[:space:]]*\./Scripts/dco_push_commits\.sh --fresh ' "$DCO_WF" \
        || fail "${DCO_WF} never lists a push with ${base} --fresh — a new branch or a force-push would be checked on its head commit alone"
      return 0
      ;;

    # HELPER OF THE DCO CHECK (forsgren#267): the push path's judge, which
    # leaves a merged pull request's commits to its own DCO run and hands every
    # other commit to check_dco.sh. Scripts/test_check_dco.sh, an order-file
    # row, is its test and must still run it; dco.yml runs it on a push.
    dco_push_check.sh)
      runs_script "Scripts/test_check_dco.sh" "$base" \
        || fail "${base} judges a push for the DCO check and Scripts/test_check_dco.sh never runs it — the push check would be unproven"
      runs_script "$DCO_WF" "$base" \
        || fail "${base} judges a push for the DCO check and ${DCO_WF} never invokes it — a push to main would not be checked"
      return 0
      ;;

    # HAND-RUN BY THE LOOP, never by sfl or a workflow: a thin exec wrapper
    # around FBP.sh under the agent-Friend identity. Requiring a runner to
    # invoke it would mean FBP invoking itself. CLAUDE.md declares it.
    fbp_agent_friend.sh)
      grep -qF 'Scripts/fbp_agent_friend.sh' CLAUDE.md \
        || fail "${base} is run by hand and CLAUDE.md no longer declares it — an undeclared script nobody runs is a file, not a tool"
      return 0
      ;;

    # HAND-RUN, not a gate (forsgren#52): run by hand to sync the private-names
    # list into the FORSGREN_PRIVATE_NAMES Actions and Dependabot secrets. No
    # runner invokes it (it needs the maintainer's gh login), so it must carry
    # a fixture, and that fixture must be an order-file row.
    sync_private_names_secrets.sh)
      require_fixture "$base" "the secret sync would be untested"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the secret sync"
      return 0
      ;;

    # FBP'S REFUSED PUSH, not a gate (forsgren#283, step 1 of 2): FBP.sh runs
    # it when its final push is refused (rebase over incoming commits on other
    # files, or stop). CI never pushes, so only FBP runs it. It must carry a
    # fixture, and that fixture must be an order-file row.
    fbp_push_or_rebase.sh)
      runs_script "$FBP" "$base" \
        || fail "${base} handles a refused push and ${FBP} never invokes it — a push refused because the remote moved would stop the run again"
      require_fixture "$base" "the rebase on a refused push would be untested"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the refused-push handling"
      return 0
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
      return 0
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
      return 0
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
      return 0
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
      return 0
      ;;

    # WRITER/MAINTAINER TOOL, not a gate (forsgren#231, step 3): the read-only
    # check before a Release starts. It runs release_plan.sh and
    # release_report.sh, which the Release workflow runs too. A fixture,
    # and its self-test is an order-file row.
    release_precheck.sh | release_check.sh)
      require_fixture "$base" "the release pre-check would be unproven"
      order_names "test_${base}" \
        || fail "Scripts/test_${base} is not an order-file row — sfl and Quality would never prove the release pre-check"
      return 0
      ;;

    # GENERATOR, not a gate (forsgren#219): prints the "What we check" list of
    # CONTRIBUTING.md from the order file. Scripts/test_render_quality_report.sh,
    # an order-file row, runs it and compares its output with CONTRIBUTING.md.
    render_gate_list.sh)
      runs_script "Scripts/test_render_quality_report.sh" "$base" \
        || fail "${base} generates the CONTRIBUTING.md gate list and Scripts/test_render_quality_report.sh, the row that keeps the two in sync, never runs it"
      # Shared with the sites (forsgren#240): a shared helper carries its canon
      # line, which the estate's parity check reads.
      head -5 "Scripts/${base}" | has -qxF '# canon: render_gate_list v1' \
        || fail "Scripts/${base} has no '# canon: render_gate_list v1' line in its first 5 lines — the sites' parity check could not tell it is the shared copy"
      return 0
      ;;

    # SOURCED HELPER, not a gate (estate canon): the engine of the exit-trap
    # behaviour test, which sources it. The test is its own order-file row.
    lib_exit_trap_probe.sh)
      runs_script "Scripts/test_exit_trap_completion_behaviour.sh" "$base" \
        || fail "${base} holds the exit-trap probe engine and Scripts/test_exit_trap_completion_behaviour.sh never sources it"
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#428): has, a quiet grep that reads
    # all of stdin first. The self-test of the pipe into grep -q gate is its
    # test, and every script that ends a pipe in has must still source it
    # (without it the call would be a command not found, read as "no match").
    lib_has.sh)
      runs_script "Scripts/test_check_pipe_grep_q.sh" "$base" \
        || fail "${base} holds has and Scripts/test_check_pipe_grep_q.sh, its test, never sources it"
      while IFS= read -r consumer; do
        grep -qE '^source .*lib_has\.sh"?$' "$consumer" \
          || fail "${consumer} ends a pipe in has and never sources ${base}"
      done < <(grep -lE '^[^#]*[|][[:space:]]*has ' Scripts/*.sh)
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#612, the estate sweep): the one way
    # a script makes a temp folder or file, so the path honours TMPDIR. Its
    # test is Scripts/test_lib_tmp.sh, an order-file row (it sources the
    # helper through a variable, which runs_script does not follow), and
    # Scripts/check_bare_mktemp.sh keeps every other call templated. sfl.sh
    # must still source it, and so must every script that calls tmp_dir or
    # tmp_file, directly or through Scripts/lib_selftest.sh or
    # Scripts/lib_fbp_sandbox.sh (without it the call is a command not found).
    lib_tmp.sh)
      runs_script "$SFL" "$base" \
        || fail "${base} makes every temp path of this repository and ${SFL} never sources it — the helper would then be a file nobody uses"
      order_names test_lib_tmp.sh \
        || fail "Scripts/test_lib_tmp.sh is not an order-file row — ${base} would be unproven"
      while IFS= read -r consumer; do
        grep -qE '^[[:space:]]*(source|[.]) .*lib_(tmp|selftest|fbp_sandbox)\.sh"?$' "$consumer" \
          || fail "${consumer} calls tmp_dir or tmp_file and never sources ${base}"
      done < <(grep -lE '^[^#]*[$][(]tmp_(dir|file) ' FBP.sh sfl.sh Scripts/*.sh | grep -v '^Scripts/lib_tmp\.sh$')
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#386, decision #411 A): what the two
    # browser gate self-tests share. Both are order-file rows and both must
    # still source it, else the page and site helpers they call would be missing.
    lib_gate_browser_selftest.sh)
      for consumer in test_gate_browser.sh test_gate_browser_process.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} holds the helpers of the browser gate self-tests and Scripts/${consumer} never sources it"
        order_names "$consumer" \
          || fail "Scripts/${consumer} is not an order-file row — the browser gate helpers would be unproven"
      done
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#382): runs a self-test's mutation
    # proofs side by side. Its self-test is an order-file row, and the browser
    # gate self-test must still source it, else its proofs would run one after
    # the other again.
    lib_parallel_mutants.sh)
      runs_script "Scripts/test_gate_browser.sh" "$base" \
        || fail "${base} holds the parallel mutants helper and Scripts/test_gate_browser.sh never sources it"
      order_names "test_lib_parallel_mutants.sh" \
        || fail "Scripts/test_lib_parallel_mutants.sh is not an order-file row — the parallel mutants helper would be unproven"
      return 0
      ;;

    # SOURCED HELPER, not a gate (forsgren#642): which baseline file the two
    # browser gates read on this platform (Darwin the macOS file, Linux the
    # _linux one). Both gates must still source it, and its self-test is an
    # order-file row.
    lib_browser_baseline.sh)
      for consumer in gate_browser.sh gate_browser_fixture.sh; do
        runs_script "Scripts/${consumer}" "$base" \
          || fail "${base} picks the baseline of the platform and Scripts/${consumer} never sources it"
      done
      order_names "test_gate_browser_baseline.sh" \
        || fail "Scripts/test_gate_browser_baseline.sh is not an order-file row — the baseline choice would be unproven"
      return 0
      ;;

    *)
      return 1
      ;;
  esac
}

# gate_wiring_local_pins: forsgren's own pins, run after the canon's two loops.
gate_wiring_local_pins() {
[[ -f "$CI_RUNNER" ]] || { fail "${CI_RUNNER} not found"; return 0; }

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
    sed 's/^[[:space:]]*//' "$runner" | has -qxF -- "$rule" \
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


# --- 2b. THE BASELINES ON THE RUN PAGE (forsgren#220): the canon's pin -------
baseline_step_pin

# Pin 8 (forsgren's own arm, forsgren#686; the sibling sites' pin 8 adapted):
# THE SELF-TESTS RUN IN THEIR OWN WORKFLOW, THE REAL GATES IN QUALITY, EACH ROW
# IN EXACTLY ONE. selftests.yml runs the self-test rows, quality.yml every other
# row; both run their jobs through Scripts/run_ci_phase.sh, and
# Scripts/ci_job_groups.txt gives each row to one job, or to shard jobs, while a
# row it lists for no job runs in Quality's main job (`main`, forsgren's default
# job). What this pins on top: the workflow a job belongs to is the one whose
# step runs `run_ci_phase.sh <phase> "$ROWS" "$DETAILS" <job>`, every job of
# the groups file runs in exactly one of the two workflows, and each runnable
# row runs in the workflow its kind wants and in no other:
#   a self-test row (is_selftest_row): its label ends in " self-test" or starts
#     with "mutation: ", or it is the step summary isolation gate, a self-test
#     in full (the git sandbox isolation self-test already ends in
#     " self-test") -> selftests.yml only;
#   every other runnable row, a real gate -> quality.yml only;
#   the one written exception: the secret-scan self-test is secret-class (its
#     first case scans the real tree, forsgren#570), so it stays in Quality and
#     in every local run, before a commit.
# So nothing is dropped (a row in neither workflow) and nothing is doubled (a
# row in both). Scripts/selftest_rows.sh reads the same files for the rows sfl
# skips locally, so the local skip set is this CI self-test set
# (Scripts/test_sfl_selftest_skip.sh, case 7). Mutation proofs below.
if ! is_mutation_rerun; then
  SELFTESTS_WF=".github/workflows/selftests.yml"
  JOB_GROUPS_FILE="Scripts/ci_job_groups.txt"
  # The step summary isolation gate is named by its script, its label read from
  # the order file.
  SUMMARY_ISOLATION_LABEL="$(awk -F'|' '$2 == "Scripts/test_step_summary_isolation.sh" { print $1; exit }' "$ORDER")"
  is_selftest_row() {
    [[ "$1" != "secret-scan self-test" ]] || return 1
    [[ "$1" != "$SUMMARY_ISOLATION_LABEL" ]] || return 0
    case "$1" in
      *" self-test" | "mutation: "*) return 0 ;;
    esac
    return 1
  }
  # phase_jobs <workflow>: the jobs whose run_ci_phase.sh calls the workflow
  # makes, once each (the reading of Scripts/selftest_rows.sh).
  phase_jobs() {
    grep -vE '^[[:space:]]*#' "$1" \
      | sed -nE 's#^[[:space:]]*\./Scripts/run_ci_phase\.sh (pre|post) "[$]ROWS" "[$]DETAILS" ([A-Za-z0-9_-]+)[[:space:]]*$#\2#p' \
      | sort -u
  }
  # split_problems <quality.yml> <selftests.yml> <groups> <order>: one line per
  # problem; nothing means it holds.
  split_problems() {
    local quality="$1" selftests="$2" groups="$3" order="$4" q_jobs s_jobs job label where want
    [[ -f "$selftests" ]] || { echo "no ${selftests}: the self-tests run in no workflow"; return 0; }
    q_jobs="$(phase_jobs "$quality")"
    s_jobs="$(phase_jobs "$selftests")"
    if has -qxF -- main <<< "$s_jobs"; then
      echo "selftests.yml runs the main job, whose rows are Quality's"
    fi
    while IFS= read -r job; do
      [[ -n "$job" ]] || continue
      if has -qxF -- "$job" <<< "$q_jobs" && has -qxF -- "$job" <<< "$s_jobs"; then
        echo "job ${job} runs in both quality.yml and selftests.yml: its gates would run twice"
      elif ! has -qxF -- "$job" <<< "$q_jobs" && ! has -qxF -- "$job" <<< "$s_jobs"; then
        echo "job ${job} of ${groups} runs in neither quality.yml nor selftests.yml: its gates would run nowhere"
      fi
    done < <(grep -v '^#' "$groups" | grep '|' | cut -d'|' -f1 | sort -u)
    while IFS= read -r label; do
      [[ -n "$label" ]] || continue
      where=""
      if ! grep -v '^#' "$groups" | awk -F'|' -v l="$label" '$2 == l { f = 1 } END { exit !f }'; then
        # No group row: the main job, Quality's when quality.yml runs it.
        if has -qxF -- main <<< "$q_jobs"; then where="quality.yml"; fi
      fi
      while IFS= read -r job; do
        [[ -n "$job" ]] || continue
        if has -qxF -- "$job" <<< "$q_jobs"; then where="${where}"$'\n'"quality.yml"; fi
        if has -qxF -- "$job" <<< "$s_jobs"; then where="${where}"$'\n'"selftests.yml"; fi
      done < <(grep -v '^#' "$groups" | awk -F'|' -v l="$label" '$2 == l { print $1 }')
      where="$(grep . <<< "$where" | sort -u | tr '\n' ' ' | sed 's/ $//' || true)"
      if is_selftest_row "$label"; then want="selftests.yml"; else want="quality.yml"; fi
      if [[ -z "$where" ]]; then
        echo "row ${label} runs in no workflow, want ${want}"
      elif [[ "$where" != "$want" ]]; then
        echo "row ${label} runs in ${where}, want ${want} only"
      fi
    done < <(grep -v '^#' "$order" | awk -F'|' '$2 != "" && $2 != "n/a" { print $1 }')
    # selftests.yml, like quality.yml in pin 2, names no gate itself.
    if grep -vE '^[[:space:]]*#' "$selftests" | grep -vE 'run_ci_phase\.sh|merge_quality_report\.sh|render_quality_report\.sh|render_quality_summary\.sh|open_selftests_failure_issue\.sh|dispatch_report\.sh|selftests_counts\.sh|selftest_rows\.sh|install_tools(_linux)?\.sh|go_toolchain\.sh' \
      | has -qE '(^|[^A-Za-z0-9_./-])(\./)?Scripts/[A-Za-z0-9_]+\.sh'; then
      echo "selftests.yml names a gate itself; the order file and ${groups} decide which rows a job runs"
    fi
  }
  problems="$(split_problems "$CI" "$SELFTESTS_WF" "$JOB_GROUPS_FILE" "$ORDER")"
  [[ -z "$problems" ]] || fail "every self-test row must run in selftests.yml and every other row in quality.yml, each in exactly one: ${problems}"
  _t="$(tmp_dir test_gate_wiring)" || exit 1
  # split_case <name> <reason> <groups|selftests|quality> <sed -E expression>:
  # the copy of that file, mutated, is rejected with <reason>.
  split_case() {
    local q="$CI" s="$SELFTESTS_WF" g="$JOB_GROUPS_FILE" src out got
    case "$3" in
      groups) src="$g"; g="${_t}/groups_$1.txt"; out="$g" ;;
      selftests) src="$s"; s="${_t}/selftests_$1.yml"; out="$s" ;;
      *) src="$q"; q="${_t}/quality_$1.yml"; out="$q" ;;
    esac
    sed -E "$4" "$src" > "$out"
    if cmp -s "$src" "$out"; then
      fail "pin 8 proof $1: the mutation $4 changed nothing, so the proof would be vacuous"
      return 0
    fi
    got="$(split_problems "$q" "$s" "$g" "$ORDER")"
    if has -qF -- "$2" <<< "$got"; then
      echo "  ok: pin 8 proof $1 is rejected"
    else
      fail "pin 8 proof $1 was accepted: expected '$2'. Got: ${got:-nothing}"
    fi
  }
  split_case selftest-in-quality "row data guard self-test runs in quality.yml, want selftests.yml only" groups 's/^selftest_mac_2\|data guard self-test$/quality_2|data guard self-test/'
  split_case selftest-left-in-main "row private-names self-test runs in quality.yml, want selftests.yml only" groups '/^selftest_mac_2\|private-names self-test$/d'
  split_case gate-in-selftests "row shellcheck runs in selftests.yml, want quality.yml only" groups 's/^lint\|shellcheck$/selftest_linux|shellcheck/'
  split_case mutation-in-quality "row mutation: checkout pins runs in quality.yml, want selftests.yml only" groups 's/^selftest_linux\|mutation: checkout pins$/workflows|mutation: checkout pins/'
  split_case sandbox-shard-in-quality "row git sandbox isolation self-test runs in quality.yml selftests.yml, want selftests.yml only" groups 's/^isolation_2\|git sandbox isolation self-test\|/quality_2|git sandbox isolation self-test|/'
  split_case summary-in-quality "row ${SUMMARY_ISOLATION_LABEL} runs in quality.yml, want selftests.yml only" groups "s/^summary\\|${SUMMARY_ISOLATION_LABEL}\$/workflows|${SUMMARY_ISOLATION_LABEL}/"
  split_case exception-moved "row secret-scan self-test runs in selftests.yml, want quality.yml only" groups 's/^(selftest_mac_2\|data guard self-test)$/\1\
selftest_mac_2|secret-scan self-test/'
  split_case job-in-no-workflow "job selftest_mac_2 of ${JOB_GROUPS_FILE} runs in neither quality.yml nor selftests.yml" selftests 's#(run_ci_phase\.sh pre "[$]ROWS" "[$]DETAILS") selftest_mac_2$#\1 selftest_mac_1#'
  split_case job-in-both "job isolation_1 runs in both quality.yml and selftests.yml" quality 's#^( *)(\./Scripts/run_ci_phase\.sh pre "[$]ROWS" "[$]DETAILS" )lint$#&\
\1\2isolation_1#'
  split_case main-job-gone "row secret scan runs in no workflow, want quality.yml" quality 's#("[$]DETAILS") main( |$)#\1 mainless\2#'
  split_case main-in-selftests "selftests.yml runs the main job, whose rows are Quality's" selftests 's#(run_ci_phase\.sh pre "[$]ROWS" "[$]DETAILS") summary$#\1 main#'
  split_case selftests-names-a-gate "selftests.yml names a gate itself" selftests 's#^( *)\./Scripts/run_ci_phase\.sh pre "[$]ROWS" "[$]DETAILS" isolation_2$#&\
\1./Scripts/check_secrets.sh#'
  if [[ "$(split_problems "$CI" "${_t}/absent.yml" "$JOB_GROUPS_FILE" "$ORDER")" != *"the self-tests run in no workflow"* ]]; then
    fail "pin 8: a missing selftests.yml was accepted"
  fi
  rm -rf "$_t"
fi
}

# gate_wiring_local_proofs: forsgren's mutation proofs, at the top level only
# (the canon has made MUTATION_TMP).
gate_wiring_local_proofs() {
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

  # quality.yml: the summary calls become comments (forsgren#8; the checks step's too,
  # whose call is the condition of an `if checks=...` or `if ! checks=...`).
  mutation_proof GATE_WIRING_CI_OVERRIDE "Scripts/render_quality_summary.sh" \
    's|^([[:space:]]*)(\./Scripts/render_quality_summary\.sh)|\1# \2|; s|^([[:space:]]*)(if (! )?checks="\$\(\./Scripts/render_quality_summary\.sh)|\1# \2|' \
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
    "sfl_pull.sh provides sfl's opening pull and sfl never sources it" \
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
  mutation_proof GATE_WIRING_DCO_OVERRIDE "Scripts/dco_push_check.sh" \
    's|^([[:space:]]*)(\./Scripts/dco_push_check\.sh )|\1# \2|' \
    "dco_push_check.sh judges a push for the DCO check and" \
    "a dco.yml whose dco_push_check.sh call is a comment"
  mutation_proof GATE_WIRING_DCO_OVERRIDE "Scripts/dco_push_commits.sh" \
    's|^  push:|  workflow_dispatch:|' \
    "has no push trigger on main" \
    "a dco.yml with no push trigger"

  # dco.yml: the commit message check call becomes a comment, the pull
  # request listing too, and the --fresh of the push listing goes.
  mutation_proof GATE_WIRING_DCO_OVERRIDE "Scripts/check_commit_messages.sh" \
    's|^([[:space:]]*)(\./Scripts/check_commit_messages\.sh )|\1# \2|' \
    "check_commit_messages.sh checks the private names in commit messages and" \
    "a dco.yml whose check_commit_messages.sh call is a comment"
  mutation_proof GATE_WIRING_DCO_OVERRIDE "Scripts/dco_pr_commits.sh" \
    's|^([[:space:]]*)(\./Scripts/dco_pr_commits\.sh )|\1# \2|' \
    "dco_pr_commits.sh lists a pull request's commits and" \
    "a dco.yml whose dco_pr_commits.sh call is a comment"
  mutation_proof GATE_WIRING_DCO_OVERRIDE "Scripts/dco_push_commits.sh" \
    's|(dco_push_commits\.sh) --fresh |\1 |' \
    "never lists a push with dco_push_commits.sh --fresh" \
    "a dco.yml whose push listing for the messages has no --fresh"

  # The order file: the commit messages self-test row becomes a comment.
  mutation_proof GATE_WIRING_ORDER_OVERRIDE "Scripts/test_check_commit_messages.sh" \
    's#^(commit messages self-test\|)#\# \1#' \
    "Scripts/test_check_commit_messages.sh is not an order-file row" \
    "an order file whose commit messages self-test row is a comment"

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

  # Two more guard samples of the matcher self-proof: the call shape of the
  # report_ci_step.sh wrapper, which Scripts/lib_runs_script.sh still models.
  # The samples spell the folder as @S@, which sed turns back into the real
  # name, so the script references gate does not read the two made-up scripts
  # as paths of this repository.
  matcher_accepts "guard" "a gate named after the -- of report_ci_step.sh" yml < <(sed 's#@S@#Scripts#g' <<'SAMPLE'
        run: |
          ./@S@/report_ci_step.sh "probe" "$ROWS" "$DETAILS" -- ./@S@/probe.sh
SAMPLE
  )
  matcher_accepts "guard" "a gate named after -- on a continuation line" yml < <(sed 's#@S@#Scripts#g' <<'SAMPLE'
        run: |
          ./@S@/report_ci_step.sh \
            --heading "Probe" \
            "probe" "$ROWS" "$DETAILS" -- ./@S@/probe.sh "$GENERATED_SITE"
SAMPLE
  )
}
