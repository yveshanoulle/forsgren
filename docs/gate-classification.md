# Gate classification

Every check this repository runs, and the class each one has. It was written
with forsgren#216, the step after the quality gates moved to the shared canon
versions (forsgren#215) and the local build got `--no-push` and fix mode
(forsgren#214).

A gate is not "present" or "absent". It is one of three classes:

- **required**: it runs here, in sfl and in CI. Its canon id and version are
  on its `# canon:` line, when the script has one.
- **n/a**: it does not apply to this repository, and the reason is written
  down in the order file.
- **documented exception**: the gate runs, but one finding or one rule is
  excused. The excuse is a row in a data file with a required reason, or a
  rule written in the gate and its documentation.

A gap is closed when a test shows the behaviour. A matching version line does
not close it.

## The order file, row by row

[Scripts/gate_report_order.txt](../Scripts/gate_report_order.txt) is the one
list sfl and CI both run. It has 116 rows: 112 with a script and 4 `n/a`
rows. All scripts are in `Scripts/`. The phase is `pre` (repository inputs and
checker behaviour) or `post` (the generated site). `secret-class` means a
finding blocks the commit as well as the push. A row for a self-test is
named after the gate it proves; sourced helpers are not rows, only their
self-tests are.

| # | Label | Script | Phase | Class |
|---|-------|--------|-------|-------|
| 1 | secret-scan self-test | `test_check_secrets.sh` | pre | required, `test_check_secrets v1` |
| 2 | secret scan | `check_secrets.sh` | pre, secret-class | required, `check_secrets v1` |
| 3 | data guard self-test | `test_check_data_guard.sh` | pre | required |
| 4 | data guard | `check_data_guard.sh` | pre, secret-class | required |
| 5 | private-names self-test | `test_check_private_names.sh` | pre | required |
| 6 | private names | `check_private_names.sh` | pre, secret-class | required |
| 7 | private-names secret sync self-test | `test_sync_private_names_secrets.sh` | pre | required |
| 8 | private-names local file self-test | `test_ensure_private_names_file.sh` | pre | required |
| 9 | sfl pull contract | `test_sfl_pull.sh` | pre | required, `test_sfl_pull v1` |
| 10 | npm manifest policy self-test | `test_check_guardrail_packages.sh` | pre | required, `test_check_guardrail_packages v1` |
| 11 | npm manifest policy | `check_guardrail_packages.sh` | pre | required, `check_guardrail_packages v1` |
| 12 | tool install self-test | `test_install_tools.sh` | pre | required, `test_install_tools v1` |
| 13 | npm install sync self-test | `test_npm_sync_install.sh` | pre | required, `test_npm_sync_install v1` |
| 14 | site-settings self-test | `test_lib_site_settings.sh` | pre | required, `test_lib_site_settings v2` |
| 15 | HTMLHint self-test | `test_gate_htmlhint.sh` | pre | required, `test_gate_htmlhint v1` |
| 16 | HTMLHint | `gate_htmlhint.sh` | post | required, `gate_htmlhint v1` |
| 17 | Stylelint self-test | `test_gate_stylelint.sh` | pre | required, `test_gate_stylelint v1` |
| 18 | Stylelint | `gate_stylelint.sh` | post | required, `gate_stylelint v1` |
| 19 | Stylelint source-fix self-test | `test_fix_source_css.sh` | pre | required |
| 20 | starter page build | `build_starter_page.sh` | post | required |
| 21 | starter page HTMLHint | `gate_htmlhint_starter.sh` | post | required |
| 22 | starter page privacy posture | `check_privacy_posture_starter.sh` | post | required |
| 23 | starter page links | `check_starter_links.sh` | post | required |
| 24 | deployed-pages self-test | n/a | n/a | n/a: forsgren does not deploy its generated pages from this repository, so there is no deployed-pages verification to self-test |
| 25 | required-pages self-test | `test_validate_required_pages.sh` | pre | required, `test_validate_required_pages v1` |
| 26 | required-pages manifest | `validate_required_pages.sh` | post | required, `validate_required_pages v1` |
| 27 | publish-release shape | n/a | n/a | n/a: forsgren has no publish-release script: a release is a git tag made by the maintainer |
| 28 | mutation: checkout pins | `test_workflow_checkout_pins_mutations.sh` | pre | required, `test_workflow_checkout_pins_mutations v1` |
| 29 | checkout pins | `test_workflow_checkout_pins.sh` | pre | required, `test_workflow_checkout_pins v1` |
| 30 | html-duplication self-test | `test_check_html_dupl.sh` | pre | required, `test_check_html_dupl v1` |
| 31 | html duplication | `check_html_dupl.sh` | pre | required, `check_html_dupl v1` |
| 32 | html duplication, generated page self-test | `test_check_html_dupl_site.sh` | pre | required |
| 33 | html duplication, generated page | `check_html_dupl_site.sh` | post | required |
| 34 | golden-pages self-test | `test_check_golden_pages.sh` | pre | required |
| 35 | golden pages | `check_golden_pages.sh` | pre | required |
| 36 | FBP --no-push self-test | `test_fbp_no_push.sh` | pre | required, `test_fbp_no_push v2` |
| 37 | gate wiring | `test_gate_wiring.sh` | pre | required |
| 38 | CI phase runner self-test | `test_run_ci_phase.sh` | pre | required, `test_run_ci_phase v1` |
| 39 | go mod tidy self-test | `test_check_go_mod_tidy.sh` | pre | required |
| 40 | go mod tidy | `check_go_mod_tidy.sh` | pre | required |
| 41 | Go tests self-test | `test_check_go_tests.sh` | pre | required |
| 42 | Go tests | `check_go_tests.sh` | pre | required |
| 43 | Go coverage self-test | `test_check_coverage.sh` | pre | required |
| 44 | Go coverage | `check_coverage.sh` | pre | required |
| 45 | gofmt self-test | `test_check_gofmt.sh` | pre | required |
| 46 | gofmt | `check_gofmt.sh` | pre | required |
| 47 | Go tool helper self-test | `test_lib_go_tool.sh` | pre | required |
| 48 | Go lint self-test | `test_check_go_lint.sh` | pre | required |
| 49 | Go lint | `check_go_lint.sh` | pre | required |
| 50 | Go test duplication self-test | `test_check_test_dupl.sh` | pre | required |
| 51 | Go test duplication | `check_test_dupl.sh` | pre | required |
| 52 | Go file length self-test | `test_check_file_length.sh` | pre | required |
| 53 | Go file length | `check_file_length.sh` | pre | required |
| 54 | Go vulnerabilities self-test | `test_check_govulncheck.sh` | pre | required; documented exception: offline skip (see below) |
| 55 | Go vulnerabilities | `check_govulncheck.sh` | pre | required; documented exception: offline skip (see below) |
| 56 | Go dead code self-test | `test_check_deadcode.sh` | pre | required |
| 57 | Go dead code | `check_deadcode.sh` | pre | required |
| 58 | actionlint self-test | `test_check_actionlint.sh` | pre | required, `test_check_actionlint v1` |
| 59 | actionlint | `check_actionlint.sh` | pre | required, `check_actionlint v1` |
| 60 | actionlint forsgren cases self-test | `test_check_actionlint_forsgren.sh` | pre | required |
| 61 | shellcheck self-test | `test_check_shellcheck.sh` | pre | required |
| 62 | shellcheck | `check_shellcheck.sh` | pre | required |
| 63 | yamllint self-test | `test_check_yamllint.sh` | pre | required |
| 64 | yamllint | `check_yamllint.sh` | pre | required |
| 65 | lint-coverage self-test | `test_check_lint_coverage.sh` | pre | required, `test_check_lint_coverage v1` |
| 66 | lint coverage | `check_lint_coverage.sh` | post | required, `check_lint_coverage v1` |
| 67 | npm-audit self-test | `test_npm_audit_check.sh` | pre | required, `test_npm_audit_check v1`; documented exception: one dated advisory (see below) |
| 68 | npm audit | `npm_audit_check.sh` | pre | required, `npm_audit_check v1`; documented exception: one dated advisory (see below) |
| 69 | manifest-covers-site self-test | `test_required_pages_covers_site_selftest.sh` | pre | required, `test_required_pages_covers_site_selftest v1` |
| 70 | manifest covers site | `test_required_pages_covers_site.sh` | post | required, `test_required_pages_covers_site v1` |
| 71 | quality trigger scope | `test_quality_trigger_scope.sh` | pre | required |
| 72 | stray tracked files | `test_no_stray_tracked_files.sh` | pre | required, `test_no_stray_tracked_files v1` |
| 73 | quality-report render | `test_render_quality_report.sh` | pre | required, `test_render_quality_report v1` |
| 74 | quality-run summary | `test_render_quality_summary.sh` | pre | required |
| 75 | gate-failure summary | `test_summarize_gate_failure.sh` | pre | required |
| 76 | sfl drives from the order file | `test_sfl_drives_from_order_file.sh` | pre | required |
| 77 | step table | `test_render_step_table.sh` | pre | required, `test_render_step_table v1` |
| 78 | FullBuildAndPush commit-message block | `test_fbp_commit_message.sh` | pre | required |
| 79 | FullBuildAndPush build-site page count | `test_fbp_build_pagecount.sh` | pre | required |
| 80 | FullBuildAndPush aborted run | `test_fbp_aborted.sh` | pre | required |
| 81 | FullBuildAndPush abort exit | `test_fbp_abort_exit.sh` | pre | required |
| 82 | privacy-posture self-test | `test_check_privacy_posture.sh` | pre | required, `test_check_privacy_posture v1` |
| 83 | privacy posture | `check_privacy_posture.sh` | post | required, `check_privacy_posture v1` |
| 84 | repository-links self-test | `test_check_repo_links.sh` | pre | required |
| 85 | repository links | `check_repo_links.sh` | post | required |
| 86 | community-files self-test | `test_check_community_files.sh` | pre | required |
| 87 | community files | `check_community_files.sh` | pre | required |
| 88 | exit-trap completion self-test | `test_check_exit_trap_completion.sh` | pre | required, `test_check_exit_trap_completion v1` |
| 89 | exit-trap completion | `check_exit_trap_completion.sh` | pre | required, `check_exit_trap_completion v1` |
| 90 | exit-trap completion behaviour | `test_exit_trap_completion_behaviour.sh` | pre | required, `test_exit_trap_completion_behaviour v1` |
| 91 | markdown-links self-test | `test_check_markdown_links.sh` | pre | required, `test_check_markdown_links v1` |
| 92 | markdown links | `check_markdown_links.sh` | pre | required, `check_markdown_links v1` |
| 93 | script references self-test | `test_check_script_references.sh` | pre | required, `test_check_script_references v1` |
| 94 | script references | `check_script_references.sh` | pre | required, `check_script_references v1` |
| 95 | Node pin self-test | `test_node_pin.sh` | pre | required, `test_node_pin v1` |
| 96 | Node pin gate self-test | `test_check_node_pin.sh` | pre | required, `test_check_node_pin v1` |
| 97 | Node pin | `check_node_pin.sh` | pre | required, `check_node_pin v1` |
| 98 | Go toolchain pin self-test | `test_go_toolchain.sh` | pre | required |
| 99 | build-site self-test | `test_build_site.sh` | pre | required |
| 100 | starter page build self-test | `test_build_starter_page.sh` | pre | required |
| 101 | starter page links self-test | `test_check_starter_links.sh` | pre | required |
| 102 | starter page gates self-test | `test_starter_page_gates.sh` | pre | required |
| 103 | workflow node pin | `test_workflow_node_pin.sh` | pre | required, `test_workflow_node_pin v1` |
| 104 | npm lockfile sync self-test | `test_check_npm_lock_sync.sh` | pre | required, `test_check_npm_lock_sync v1` |
| 105 | npm lockfile sync | `check_npm_lock_sync.sh` | pre | required, `check_npm_lock_sync v1` |
| 106 | workflow-triggers self-test | `test_check_workflow_triggers.sh` | pre | required, `test_check_workflow_triggers v1` |
| 107 | workflow triggers | `check_workflow_triggers.sh` | pre | required, `check_workflow_triggers v1` |
| 108 | DCO sign-off self-test | `test_check_dco.sh` | pre | required |
| 109 | metrics workflow | `test_metrics_workflow.sh` | pre | required |
| 110 | auto-update workflow | `test_auto_update_workflow.sh` | pre | required |
| 111 | starter page workflow | `test_starter_page_workflow.sh` | pre | required |
| 112 | vulncheck workflow | `test_vulncheck_workflow.sh` | pre | required |
| 113 | zizmor self-test | `test_check_zizmor.sh` | pre | required |
| 114 | zizmor | `check_zizmor.sh` | pre | required |
| 115 | privacy-pages self-test | n/a | n/a | n/a: there is no privacy-pages gate here to self-test |
| 116 | privacy pages | n/a | n/a | n/a: static generated page - numbers and dates only; no forms, no analytics or tracking, no cookies or storage, no third-party assets or embeds; nothing personal is collected or processed - and the privacy-posture gate above re-proves that every run rather than leaving it asserted |

## Documented exceptions

Each one excuses one thing. The gate still runs and still fires everywhere
else, and a row without a reason is red.

| Gate | What is excused | Where it is recorded |
|------|-----------------|----------------------|
| npm audit | GHSA-vfj7-8cjw-p6xm on braces, dev tooling only, with no patched release. The exception holds up to and including 2026-10-23, then the gate is red again | [Scripts/npm_audit_exceptions.txt](../Scripts/npm_audit_exceptions.txt), against forsgren#13 |
| Go vulnerabilities | when the vulnerability database does not answer, the gate prints a SKIP line and exits 0, never the OK line of a pass. The scheduled run sets `FORSGREN_VULN_DB_REQUIRED=1`, which turns the skip into a red | the header of [Scripts/check_govulncheck.sh](../Scripts/check_govulncheck.sh) and [.github/workflows/vulncheck.yml](../.github/workflows/vulncheck.yml), against forsgren#87 |

The other exception files are empty, with the rule for a row in their header:
[Scripts/htmlhint_exceptions.txt](../Scripts/htmlhint_exceptions.txt),
[Scripts/privacy_posture_exceptions.txt](../Scripts/privacy_posture_exceptions.txt),
[Scripts/workflow_trigger_exceptions.txt](../Scripts/workflow_trigger_exceptions.txt)
and
[Scripts/required_pages_exclusions.txt](../Scripts/required_pages_exclusions.txt).
zizmor has no suppression either ([.github/zizmor.yml](../.github/zizmor.yml)).

## Checks outside the order file

- **gofmt fix**: `FBP.sh` runs `gofmt -w` before sfl; sfl and CI only check.
- **Tool install, npm install sync, git pull --ff-only**: sfl only, local
  steps with their own self-tests in the order file (`install_tools`,
  `npm_sync_install`, `sfl_pull`).
- **DCO sign-off**: `.github/workflows/dco.yml` on pull requests and pushes
  to main, with its self-test in the order file.
- **Scheduled vulnerability scan**: `.github/workflows/vulncheck.yml` runs the
  Go vulnerabilities gate daily, shown in the order file by
  `test_vulncheck_workflow.sh`.
- **Fix mode**: sfl exports `GATE_FIX=1`. Gates that can repair what they find
  (the npm audit heal, the Stylelint source-CSS fix) do so only when it is
  set. CI never sets it, so CI only checks.

## The Go-tool gates (forsgren#216)

Go lint, Go test duplication, Go vulnerabilities and Go dead code each run a
tool pinned by a `tool` directive in `go.mod` plus `go.sum`; the versions are
explicit there and never move with this change. They resolve and run it
through one sourced helper, [Scripts/lib_go_tool.sh](../Scripts/lib_go_tool.sh):
the tool path is what `go tool -n <tool>` prints on stdout and nothing else
(its download lines on stderr stay in the log, forsgren#210), it must be an
executable file, and the tool's own exit code comes back unchanged. Each gate
keeps its own messages, exit codes and skip rules.

[Scripts/test_lib_go_tool.sh](../Scripts/test_lib_go_tool.sh) proves the helper
with a stub `go`, and a mutation each for a helper that captures stderr into
the path, one that swallows the tool's exit code and one that skips the
executable check. Each of the four gate self-tests has a case where the tool
itself exits non-zero and the gate must be red, and a mutation proof that the
same case turns green with the exit code swallowed.

## The rules

- **Fix locally, check in CI.** A tool that can fix things runs with its fix
  in the local build only. CI only checks, and a gate that changes the tree in
  CI is red.
- **Identical scripts, with canon lines.** A shared script carries
  `# canon: <id> v<n>`. A repository-specific value lives in data or in an
  argument, not in an edited copy. Where a script must differ, the reason is
  written in it.
- **A version line declares, a test shows.** Each gate's self-test, with
  mutation proofs in weakened copies, is what shows the behaviour.
- **The gate count is a ratchet.** `MIN_GATES` in
  `Scripts/test_gate_wiring.sh` equals the number of rows in the order file. It
  goes up when a row lands and never goes down to clear a red.

## The ratchet today

`MIN_GATES` is 116, which equals the 116 rows of the order file (112 with a
script and 4 `n/a` rows). forsgren#215 brought it to 115 and the Go tool
helper self-test of forsgren#216 is the 116th.
