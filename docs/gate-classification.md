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
list sfl and CI both run. It has 162 rows: 158 with a script and 4 `n/a`
rows. All scripts are in `Scripts/`. The phase is `pre` (repository inputs and
checker behaviour) or `post` (the generated site). `secret-class` means a
finding blocks the commit as well as the push. A row for a self-test is
named after the gate it proves; sourced helpers are not rows, only their
self-tests are. The rows between the `#! static-block-start` and
`#! static-block-end` marker lines (gofmt, Go lint, actionlint, shellcheck,
yamllint, zizmor, each after its self-test) are the static block: when one is red, sfl and FBP skip every
later gate, named; CI runs them all (see [development.md](development.md)).

| # | Label | Script | Phase | Class |
|---|-------|--------|-------|-------|
| 1 | secret-scan self-test | `test_check_secrets.sh` | pre, secret-class | required, `test_check_secrets v1` |
| 2 | secret scan | `check_secrets.sh` | pre, secret-class | required, `check_secrets v1` |
| 3 | data guard self-test | `test_check_data_guard.sh` | pre | required |
| 4 | data guard | `check_data_guard.sh` | pre, secret-class | required |
| 5 | private-names self-test | `test_check_private_names.sh` | pre | required |
| 6 | private names | `check_private_names.sh` | pre, secret-class | required |
| 7 | gofmt self-test | `test_check_gofmt.sh` | pre | required |
| 8 | gofmt | `check_gofmt.sh` | pre | required |
| 9 | Go lint self-test | `test_check_go_lint.sh` | pre | required |
| 10 | Go lint | `check_go_lint.sh` | pre | required |
| 11 | actionlint self-test | `test_check_actionlint.sh` | pre | required, `test_check_actionlint v1` |
| 12 | actionlint forsgren cases self-test | `test_check_actionlint_forsgren.sh` | pre | required |
| 13 | actionlint | `check_actionlint.sh` | pre | required, `check_actionlint v1` |
| 14 | shellcheck self-test | `test_check_shellcheck.sh` | pre | required |
| 15 | shellcheck | `check_shellcheck.sh` | pre | required |
| 16 | yamllint self-test | `test_check_yamllint.sh` | pre | required |
| 17 | yamllint | `check_yamllint.sh` | pre | required |
| 18 | zizmor self-test | `test_check_zizmor.sh` | pre | required |
| 19 | zizmor | `check_zizmor.sh` | pre | required |
| 20 | private-names secret sync self-test | `test_sync_private_names_secrets.sh` | pre | required |
| 21 | private-names local file self-test | `test_ensure_private_names_file.sh` | pre | required |
| 22 | sfl pull contract | `test_sfl_pull.sh` | pre | required, `test_sfl_pull v3` (the mutants sit beside a copy of `fbp_push_or_rebase.sh`, which `sfl_pull v2` sources) |
| 160 | sfl pull rebase self-test | `test_sfl_pull_rebase.sh` | pre | required; ported from the estate canon (`test_sfl_pull_rebase v1`) on `lib_selftest.sh`: `sfl_pull.sh` (`sfl_pull v2`) in a temp bare remote and two clones: an unrelated incoming commit rebased with the staged change still staged, the unstaged one kept and no stash left; an incoming commit on the staged file or on the local commit's file stopped with exit 3, the file named, the local side untouched; 2 mutation proofs, each asserting the reason (forsgren#283, step 2 of 2) |
| 23 | npm manifest policy self-test | `test_check_guardrail_packages.sh` | pre | required, `test_check_guardrail_packages v1` |
| 24 | npm manifest policy | `check_guardrail_packages.sh` | pre | required, `check_guardrail_packages v1` |
| 25 | tool install self-test | `test_install_tools.sh` | pre | required, `test_install_tools v1` |
| 161 | Linux tool install self-test | `test_install_tools_linux.sh` | pre | required; forsgren's own (forsgren#427, not canon): `install_tools_linux.sh`, the Linux installer the Lint gates job calls on ubuntu-latest, with the download and Python stubbed: four pinned tools installed and run at their pinned version, a wrong sha256 refused with nothing installed, another version, a tool with no pin, an empty list, another CPU and an unhashed requirements file red, the real pin list checked, 2 mutations |
| 26 | npm install sync self-test | `test_npm_sync_install.sh` | pre | required, `test_npm_sync_install v1` |
| 27 | site-settings self-test | `test_lib_site_settings.sh` | pre | required, `test_lib_site_settings v2` |
| 28 | HTMLHint self-test | `test_gate_htmlhint.sh` | pre | required, `test_gate_htmlhint v1` |
| 29 | HTMLHint | `gate_htmlhint.sh` | post | required, `gate_htmlhint v1` |
| 30 | Stylelint self-test | `test_gate_stylelint.sh` | pre | required, `test_gate_stylelint v1` |
| 31 | Stylelint | `gate_stylelint.sh` | post | required, `gate_stylelint v1` |
| 32 | Stylelint source-fix self-test | `test_fix_source_css.sh` | pre | required |
| 33 | starter page build | `build_starter_page.sh` | post | required |
| 34 | starter page HTMLHint | `gate_htmlhint_starter.sh` | post | required |
| 35 | starter page privacy posture | `check_privacy_posture_starter.sh` | post | required |
| 36 | starter page links | `check_starter_links.sh` | post | required |
| 37 | language gate self-test | `test_gate_language.sh` | pre | required, `test_gate_language v3`; LanguageTool stubbed, 11 mutations |
| 38 | language pages wrapper self-test | `test_gate_language_pages.sh` | pre | required; the wrapper's own, the canon gate stubbed, 4 mutations |
| 39 | language gate | `gate_language_pages.sh` | post | required; runs `gate_language.sh` (`gate_language v3`) over the metrics site and the starter page; LanguageTool 6.8 run locally and offline; mode `enforce` in `language_settings.txt`; the dictionary is passed as the terms file (`--terms`, forsgren#369); the allowlist and the baseline are data files (see below) |
| 40 | baseline report self-test | `test_report_baselines.sh` | pre | required, `test_report_baselines v4`; the report itself, `report_baselines.sh` (`report_baselines v4`, sideways rows since forsgren#350), is presentation, not a gate: Quality calls it in three steps (see below) |
| 41 | deployed-pages self-test | n/a | n/a | n/a: forsgren does not deploy its generated pages from this repository, so there is no deployed-pages verification to self-test |
| 42 | required-pages self-test | `test_validate_required_pages.sh` | pre | required, `test_validate_required_pages v1` |
| 43 | required-pages manifest | `validate_required_pages.sh` | post | required, `validate_required_pages v1` |
| 44 | publish-release shape | n/a | n/a | n/a: forsgren has no publish-release script: a release is a git tag made by the maintainer |
| 45 | mutation: checkout pins | `test_workflow_checkout_pins_mutations.sh` | pre | required, `test_workflow_checkout_pins_mutations v1` |
| 46 | checkout pins | `test_workflow_checkout_pins.sh` | pre | required, `test_workflow_checkout_pins v1` |
| 47 | html-duplication self-test | `test_check_html_dupl.sh` | pre | required, `test_check_html_dupl v1` |
| 48 | html duplication | `check_html_dupl.sh` | pre | required, `check_html_dupl v1` |
| 49 | html duplication, generated page self-test | `test_check_html_dupl_site.sh` | pre | required |
| 50 | html duplication, generated page | `check_html_dupl_site.sh` | post | required |
| 51 | golden-pages self-test | `test_check_golden_pages.sh` | pre | required |
| 52 | golden pages | `check_golden_pages.sh` | pre | required |
| 53 | FBP --no-push self-test | `test_fbp_no_push.sh` | pre | required, `test_fbp_no_push v2` |
| 159 | FBP push-or-rebase self-test | `test_fbp_push_or_rebase.sh` | pre | required; ported from the estate canon (`test_fbp_push_or_rebase v2`), forsgren's form: a copy of the real `FBP.sh` with `fbp_push_or_rebase.sh` (`fbp_push_or_rebase v3`) in a throwaway repository whose bare origin moves during the run: unrelated incoming file rebased, signed off and pushed with the ⚠️ row, same file stopped with the local commit untouched, nothing incoming, another refusal, moved again, moved every time (3 pushes); 1 mutation proof (forsgren#283, step 1 of 2) |
| 54 | gate wiring | `test_gate_wiring.sh` | pre | required |
| 55 | CI phase runner self-test | `test_run_ci_phase.sh` | pre | required, `test_run_ci_phase v4` (forsgren#574: the `report-dir`, cancel and workflow-path cases; it checks `run_ci_phase v3`) |
| 56 | go mod tidy self-test | `test_check_go_mod_tidy.sh` | pre | required |
| 57 | go mod tidy | `check_go_mod_tidy.sh` | pre | required |
| 58 | Go tests self-test | `test_check_go_tests.sh` | pre | required |
| 59 | Go tests | `check_go_tests.sh` | pre | required |
| 60 | Go coverage self-test | `test_check_coverage.sh` | pre | required |
| 61 | Go coverage | `check_coverage.sh` | pre | required |
| 62 | Go tool helper self-test | `test_lib_go_tool.sh` | pre | required |
| 63 | Go test duplication self-test | `test_check_test_dupl.sh` | pre | required |
| 64 | Go test duplication | `check_test_dupl.sh` | pre | required |
| 65 | Go file length self-test | `test_check_file_length.sh` | pre | required |
| 66 | Go file length | `check_file_length.sh` | pre | required |
| 67 | Go vulnerabilities self-test | `test_check_govulncheck.sh` | pre | required; documented exception: offline skip (see below) |
| 68 | Go vulnerabilities | `check_govulncheck.sh` | pre | required; documented exception: offline skip (see below) |
| 69 | Go dead code self-test | `test_check_deadcode.sh` | pre | required |
| 70 | Go dead code | `check_deadcode.sh` | pre | required |
| 71 | lint-coverage self-test | `test_check_lint_coverage.sh` | pre | required, `test_check_lint_coverage v1` |
| 72 | lint coverage | `check_lint_coverage.sh` | post | required, `check_lint_coverage v1` |
| 73 | npm-audit self-test | `test_npm_audit_check.sh` | pre | required, `test_npm_audit_check v2`; documented exception: one dated advisory (see below) |
| 74 | npm audit | `npm_audit_check.sh` | pre | required, `npm_audit_check v3`; documented exception: one dated advisory (see below) |
| 75 | manifest-covers-site self-test | `test_required_pages_covers_site_selftest.sh` | pre | required, `test_required_pages_covers_site_selftest v1` |
| 76 | manifest covers site | `test_required_pages_covers_site.sh` | post | required, `test_required_pages_covers_site v1` |
| 77 | quality trigger scope | `test_quality_trigger_scope.sh` | pre | required, `test_quality_trigger_scope v3` |
| 78 | quality runner pins | `test_quality_runner_pins.sh` | pre | required; forsgren's own (not canon): `test_quality_trigger_scope.sh` is the sites' shared `test_quality_trigger_scope v3`, byte-identical; this one pins push and `pull_request` on `main` with no `paths` or `paths-ignore` filter, no `pull_request_target`, `workflow_dispatch`, and each job on its image (`ubuntu-latest` for the Linux jobs, `macos-latest` for the others) with at most 5 macOS jobs starting together, mutation proofs on synthetic workflows (forsgren#240, forsgren#447) |
| 79 | stray tracked files | `test_no_stray_tracked_files.sh` | pre | required, `test_no_stray_tracked_files v1` |
| 80 | quality-report render | `test_render_quality_report.sh` | pre | required, `test_render_quality_report v3`; the renderer is `render_quality_report v3` |
| 81 | quality-run summary | `test_render_quality_summary.sh` | pre | required |
| 82 | gate-failure summary | `test_summarize_gate_failure.sh` | pre | required |
| 83 | sfl drives from the order file | `test_sfl_drives_from_order_file.sh` | pre | required |
| 84 | step table | `test_render_step_table.sh` | pre | required, `test_render_step_table v1` |
| 85 | FullBuildAndPush commit-message block | `test_fbp_commit_message.sh` | pre | required |
| 86 | FullBuildAndPush build-site page count | `test_fbp_build_pagecount.sh` | pre | required |
| 87 | FullBuildAndPush aborted run | `test_fbp_aborted.sh` | pre | required |
| 88 | FullBuildAndPush abort exit | `test_fbp_abort_exit.sh` | pre | required |
| 89 | privacy-posture self-test | `test_check_privacy_posture.sh` | pre | required, `test_check_privacy_posture v1` |
| 90 | privacy posture | `check_privacy_posture.sh` | post | required, `check_privacy_posture v1` |
| 91 | repository-links self-test | `test_check_repo_links.sh` | pre | required |
| 92 | repository links | `check_repo_links.sh` | post | required |
| 93 | community-files self-test | `test_check_community_files.sh` | pre | required |
| 94 | community files | `check_community_files.sh` | pre | required |
| 95 | exit-trap completion self-test | `test_check_exit_trap_completion.sh` | pre | required, `test_check_exit_trap_completion v1` |
| 96 | exit-trap completion | `check_exit_trap_completion.sh` | pre | required, `check_exit_trap_completion v1` |
| 97 | exit-trap completion behaviour | `test_exit_trap_completion_behaviour.sh` | pre | required, `test_exit_trap_completion_behaviour v1` |
| 97a | pipe into grep -q self-test | `test_check_pipe_grep_q.sh` | pre | required; forsgren's own (forsgren#428, not canon): 16 fixture trees (every shape of a producer piped into a quiet grep red, `has`, a file operand, a here-string, `\|\|`, a comment, no quiet flag green), 4 mutation proofs, and `has` of `lib_has.sh` finding a pattern after 300 KB of output where the plain pipe loses it |
| 97b | pipe into grep -q | `check_pipe_grep_q.sh` | pre | required; forsgren's own (forsgren#428, found by #425): red when a script at the root or in `Scripts/` pipes a producer into `grep -q` (any flag cluster with q, `--quiet`); under pipefail grep leaving at its first match can kill the producer with SIGPIPE and a present pattern reads as missing. The cure is `has` from `Scripts/lib_has.sh` |
| 98 | markdown-links self-test | `test_check_markdown_links.sh` | pre | required, `test_check_markdown_links v1` |
| 99 | markdown links | `check_markdown_links.sh` | pre | required, `check_markdown_links v1` |
| 100 | script references self-test | `test_check_script_references.sh` | pre | required, `test_check_script_references v1` |
| 101 | script references | `check_script_references.sh` | pre | required, `check_script_references v1` |
| 102 | Node pin self-test | `test_node_pin.sh` | pre | required, `test_node_pin v1` |
| 103 | Node pin gate self-test | `test_check_node_pin.sh` | pre | required, `test_check_node_pin v1` |
| 104 | Node pin | `check_node_pin.sh` | pre | required, `check_node_pin v1` |
| 105 | Go toolchain pin self-test | `test_go_toolchain.sh` | pre | required |
| 106 | build-site self-test | `test_build_site.sh` | pre | required |
| 107 | starter page build self-test | `test_build_starter_page.sh` | pre | required |
| 108 | starter page links self-test | `test_check_starter_links.sh` | pre | required |
| 109 | starter page gates self-test | `test_starter_page_gates.sh` | pre | required |
| 110 | workflow node pin | `test_workflow_node_pin.sh` | pre | required, `test_workflow_node_pin v1` |
| 152 | dependabot config | `test_dependabot_config.sh` | pre | required; forsgren's own (forsgren#86): `.github/dependabot.yml` has `gomod` and `github-actions` at `/`, a cron schedule, a commit-message prefix, groups, a cooldown and a comment per choice; 3 mutations (comments, cooldown, groups) |
| 111 | npm lockfile sync self-test | `test_check_npm_lock_sync.sh` | pre | required, `test_check_npm_lock_sync v1` |
| 112 | npm lockfile sync | `check_npm_lock_sync.sh` | pre | required, `check_npm_lock_sync v1` |
| 113 | workflow-triggers self-test | `test_check_workflow_triggers.sh` | pre | required, `test_check_workflow_triggers v1` |
| 114 | workflow triggers | `check_workflow_triggers.sh` | pre | required, `check_workflow_triggers v1` |
| 115 | DCO sign-off self-test | `test_check_dco.sh` | pre | required |
| 116 | metrics workflow | `test_metrics_workflow.sh` | pre | required |
| 117 | auto-update workflow | `test_auto_update_workflow.sh` | pre | required |
| 118 | starter page workflow | `test_starter_page_workflow.sh` | pre | required |
| 119 | vulncheck workflow | `test_vulncheck_workflow.sh` | pre | required |
| 120 | dispatch preview self-test | `test_dispatch_preview.sh` | pre | required; stub curl, no network, 3 mutation proofs. `dispatch_preview.sh` itself is run by the `preview` job of `quality.yml` (forsgren#222) |
| 121 | preview workflow | `test_preview_workflow.sh` | pre | required; pins the `preview` job of `quality.yml`, each pin proved by a mutant of the real file |
| 121a | parallel mutants library self-test | `test_lib_parallel_mutants.sh` | pre | required, `test_lib_parallel_mutants v2`; mutants run side by side in folders of their own, output in start order, a failing or aborting mutant fails the run, the default cap (half the CPUs, 2 to 4), no `jobs` call, and the browser gate self-test runs its mutants through `lib_parallel_mutants.sh` (`lib_parallel_mutants v2`) (forsgren#382) |
| 122 | browser gate self-test | `test_gate_browser.sh` | pre | required, `test_gate_browser v10`; real Chrome and axe-core, fixture sites on 127.0.0.1, 17 mutations run side by side, up to 4 at once (forsgren#382); the layout-shift fixtures answer once they moved, the log shows seconds per case (forsgren#386). The exit cases moved to row 122a (forsgren#386, decision #411 A); the shared helpers are `lib_gate_browser_selftest.sh` (`lib_gate_browser_selftest v1`) |
| 122a | browser gate process self-test | `test_gate_browser_process.sh` | pre | required, `test_gate_browser_process v1`; the exits of the browser gate, split from row 122 (forsgren#386, decision #411 A) and run after it in the same `browser` job: SIGTERM, SIGINT, SIGHUP to the wrapper, SIGTERM to node, SIGKILL to node (52a-52f), Chrome killed mid-run (53) and during the launch (53c), each with no Chrome and no profile folder left, and 2 mutation proofs (R, S); the run is mid-run before any signal (forsgren#381, #383, #386, #443) |
| 123 | browser gate | `gate_browser.sh` | post | required, `gate_browser v3` on the engine `browser_gate v6` (sideways scrolling, forsgren#350; CLS interval from the load, forsgren#377; Chrome closed on every exit, forsgren#381; Chrome watched from the launch, forsgren#386); the exceptions are empty, the baseline holds one sideways row (decision #364), one variant (see below) |
| 124 | browser gate (fixture site) self-test | `test_gate_browser_fixture.sh` | pre | required; real Chrome and axe-core, fixture sites on 127.0.0.1, 2 mutation proofs (forsgren#226, forsgren only, not canon) |
| 125 | browser gate (fixture site) | `gate_browser_fixture.sh` | post | required; the browser gate's engine on the site rendered from the made-up fixture of `Scripts/testdata/fixture_site/` by `build_fixture_site.sh`, with its own empty baseline (forsgren#226, forsgren only, not canon) |
| 156 | browser gate inputs self-test | `test_gate_inputs.sh` | pre | required; forsgren's own (forsgren#262, step 1 of 3, not canon): `Scripts/gate_inputs.txt` lists what each of the four browser rows reads (the non-script inputs written out, `*_test.go` and `testdata/` of the Go trees excluded, the script inputs by closure); every label has a row, every listed path exists, every gate's script closure is listed, and the guard holds that no `go:embed` line, nothing `go list` says go build embeds, and no build script reads `testdata/` or a test file; 7 mutation proofs |
| 157 | browser gate selection self-test | `test_gate_select.sh` | pre | required; forsgren's own (forsgren#262, step 2 of 3, not canon): `gate_select` of `Scripts/lib_gate_select.sh` in throwaway repositories (nothing changed, an input, a test file, a file no list names, markdown, untracked, staged, committed, Quality, forced, no origin/main, an unlisted label; on the real list, only `sfl.sh` or only `FBP.sh` skips the four browser rows, forsgren#284); 11 mutation proofs. sfl.sh calls it before each browser row (row 158) |
| 158 | browser gate skip self-test | `test_sfl_gate_skip.sh` | pre | required; forsgren's own (forsgren#262, step 3 of 3, not canon): the real `sfl.sh` in throwaway repositories with fake browser rows: a docs-only change skips all four (not run, counted, `⏭ skip`, named with the reason, logged in `.build/sfl-skips.log`), a change to the gates' inputs runs the two gates, `FORSGREN_GATE_SELECT_FULL=1` runs all four and pre empties a stale log, and `run_ci_phase.sh` runs all four; 3 mutation proofs |
| 126 | live check self-test | `test_live_check.sh` | pre | required, `test_live_check_selftest v1`; stub curl, no network. The live check itself, `live_check.sh` (`live_check v1`), is not a gate: it needs the deployed site and runs only in the live-check job of `starter_page.yml` |
| 127 | release plan self-test | `test_release_plan.sh` | pre | required; fixture data, no gh, 4 mutations. The plan itself, `release_plan.sh`, is not a gate: the Release workflow of forsgren#221 step 2 runs it |
| 129 | release quality self-test | `test_release_quality.sh` | pre | required; stub gh, 3 mutations. `release_quality.sh` is a step of the Release workflow, not a gate |
| 131 | release publish self-test | `test_release_publish.sh` | pre | required; stub gh, 3 mutations. `release_publish.sh` is a step of the Release workflow |
| 132 | release pins self-test | `test_release_pins.sh` | pre | required; a stub of the git-data API over the real template files of an earlier release, 13 mutations. `release_pins.sh` is a step of the Release workflow |
| 133 | release report self-test | `test_release_report.sh` | pre | required, 4 mutations (the failed step inferred from the log, a template failure without the resume instruction). `release_report.sh` is the last step of the Release workflow |
| 134 | release precheck self-test | `test_release_precheck.sh` | pre | required; `release_precheck.sh` runs the real `release_plan.sh --all` and `release_report.sh --table` on seam data: every kind of block named at once, ready issues listed, exit 0 or 1 as the plan, read-only, and the table equal line for line to the Release run page's for each kind of block; 4 mutations (no `--all`, open issues with commits ignored, exit 0 whatever the plan said, a hand-written table) (forsgren#231) |
| 134a | release check self-test | `test_release_check.sh` | pre | required; `release_check.sh` runs the real `release_plan.sh auto --all` on seam data and adds the stray `*** RED ****` commit; one line per finding, exit 1, `release check: OK, bump=<kind>`; 6 mutations (no RED look, a subject that merely holds the marker, no issue named, plan findings dropped, exit 0 with findings, a fixed bump) (forsgren#445) |
| 135 | release resume self-test | `test_release_resume.sh` | pre | required; stub gh and a throwaway repository, 3 mutations. `release_resume.sh` finds what a `resume: pins` run continues with (no `resume: publish` since forsgren#237 step 5b); it is a step of the Release workflow |
| 136 | release token expiry self-test | `test_release_token_expiry.sh` | pre | required; stub gh, injected clock, 5 mutations (each tier edge, a header taken as fine). `release_token_expiry.sh` is a step of the Release workflow |
| 136b | token expiry probe self-test | `test_probe_token_expiry.sh` | pre | required; stub curl, no network, 3 mutation proofs, and the pin of `token_expiry_probe.yml` (forsgren#269). `probe_token_expiry.sh` is the step of that workflow |
| 137 | release verify pin self-test | `test_release_verify_pin.sh` | pre | required; 3 mutations. `release_verify_pin.sh` reads a pin pull request (only the pins of both callers, to this release) and is a step of the Release workflow |
| 137a | release verify install self-test | `test_release_verify_install.sh` | pre | required; stub go and stub rm, 3 mutations (any module version accepted, no retry, the module cache removed without making it writable). `release_verify_install.sh` checks that `go install` at the released sha reports the release; the Release workflow runs it from forsgren#237 step 5b |
| 137b | release agent proofs self-test | `test_release_agent_proofs.sh` | pre | required; 2 mutations (the arrow form not read, a missing proof line taken for proved), and the real agent files held to one common major. `release_agent_proofs.sh` is called by `release_plan.sh` when the planned bump is a major |
| 138 | release metrics self-test | `test_release_metrics.sh` | pre | required; stub gh, 4 mutations (merging more than the pins, no wait, a red run taken for done, a second run next to a green one). `release_metrics.sh` merges the pin pull request and runs forsgren in forsgren-metrics until green |
| 139 | release workflow | `test_release_workflow.sh` | pre | required; pins `.github/workflows/release.yml`: trigger, permissions, actions, order, commands, ids and outcomes, resume, the secret, no tag made by hand; 39 mutations |
| 139a | release removed names | `test_release_removed_names.sh` | pre | required; forsgren's own (forsgren#263): no tracked file but SHIPPED.md names the removed bump scripts and words, and quality.yml has no scope input; split out of the release workflow pin because it reads every tracked file, so it always runs; 5 mutations |
| 143 | quality summary first | `test_quality_summary_first.sh` | pre | required; pins that no step before `Render summary and report` writes the run summary of `.github/workflows/quality.yml` and that the step writes the headline before the gate table, 4 mutations (a gate step writing the page, the short Quality note writing it directly, the table before the headline, a baselines step moved before the summary step) (forsgren#233) |
| 144 | step summary isolation | `test_step_summary_isolation.sh` | pre | required; every self-test that names a script appending to `$GITHUB_STEP_SUMMARY` is run with that variable pointing at a decoy file in the calling shell, and the decoy must stay empty, so fixture output never reaches the real run page of the Quality run; 2 mutations (a self-test on the harness, a self-test off it) (forsgren#233); locally sfl skips it when a commit touches none of the files `Scripts/gate_inputs.txt` lists for it (forsgren#264), Quality runs it always |
| 145 | git sandbox isolation self-test | `test_git_sandbox_isolation.sh` | pre | required; runs the git-using self-tests with `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` pointing at a decoy repository with a decoy origin, and requires both unchanged (forsgren#228); locally (`GITHUB_ACTIONS` unset) only the self-tests whose own file or any file they name changed against `origin/main`, saying `isolation: N of M self-tests affected`; Quality runs all, each once under the decoy with `GIT_DIR` and `GIT_INDEX_FILE` and the leak check after that single run, where local runs twice (forsgren#251) |
| 153 | git sandbox isolation scope self-test | `test_git_sandbox_isolation_scope.sh` | pre | required; the isolation gate in a throwaway repository: nothing changed, a self-test, a script it calls, a script that calls, a staged, an untracked and a committed change, a harness change (all), an unrelated file, Quality (all), no `origin/main` (all) and a forced full run, Quality running each self-test once (local twice) and a leaking self-test (config, origin refs, own refs, no work tree) turning that single run red with its reason, a Go-only change selecting nothing while no non-test Go file starts a program, the same change plus a non-test file importing `os/exec` selecting the Go-running self-test, a `_test.go` importing it not counting, 10 mutations (called scripts not followed, queue not extended, Quality filtered too, untracked ignored, no message when none is affected, harness change not widening, single-run mode removed, single run not under the decoy, exec check never true, exec check always true) (forsgren#251, forsgren#258) |
| 154 | quality jobs pin | `test_quality_jobs.sh` | pre | required; forsgren's own (forsgren#259): pins the job layout of `quality.yml` (the lint, isolation and browser jobs with the main job's setup, `run_ci_phase.sh` called with the job name, the gates of `ci_job_groups.txt`, each job's hand-over, the report job's `needs:`, each gate job's result in its status and the merge, one Quality workflow and no `continue-on-error`, the Release reading the run's conclusion; forsgren#282: the lint job), 38 mutations |
| 155 | merge quality report self-test | `test_merge_quality_report.sh` | pre | required; forsgren's own (forsgren#259): `merge_quality_report.sh` hands over, merges the jobs' rows and details into the one report, refuses a gate reported by two jobs and judges the run's status from the jobs' results, 2 mutations |
| 146 | git sandbox guard self-test | `test_git_sandbox_guard.sh` | pre | required; every git-using `test_*.sh` sources `lib_git_sandbox.sh`, 1 mutation (forsgren#228) |
| 148 | static block self-test | `test_sfl_static_block.sh` | pre | required; a fake gate set in a throwaway root, the real `sfl.sh`, `run_ci_phase.sh` and a sandboxed `FBP.sh`: a red gate in the static block (`#! static-block-start` / `#! static-block-end` in the order file) is followed by the rest of the block, then every later gate is skipped and named, the summary says `stopped after the static block`, FBP skips the build and the POST gates, named, and CI still runs every row; 2 mutations (the boundary ignored, skipped gates not named) (forsgren#231) |
| 149 | commit messages self-test | `test_check_commit_messages.sh` | pre | required; forsgren's own (forsgren#213): `check_commit_messages.sh` runs the private-names matcher (`check_private_names.sh --message -`) on the message of every commit a pull request or a push brings, in the second job of `dco.yml`; a throwaway repository with made-up names; 2 mutations (only the last commit judged, a before the checkout lacks skipped) |
| 150 | privacy-pages self-test | n/a | n/a | n/a: there is no privacy-pages gate here to self-test |
| 151 | privacy pages | n/a | n/a | n/a: static generated page - numbers and dates only; no forms, no analytics or tracking, no cookies or storage, no third-party assets or embeds; nothing personal is collected or processed - and the privacy-posture gate above re-proves that every run rather than leaving it asserted |

## Documented exceptions

Each one excuses one thing. The gate still runs and still fires everywhere
else, and a row without a reason is red.

| Gate | What is excused | Where it is recorded |
|------|-----------------|----------------------|
| Go vulnerabilities | when the vulnerability database does not answer, the gate prints a SKIP line and exits 0, never the OK line of a pass. The scheduled run sets `FORSGREN_VULN_DB_REQUIRED=1`, which turns the skip into a red | the header of [Scripts/check_govulncheck.sh](../Scripts/check_govulncheck.sh) and [.github/workflows/vulncheck.yml](../.github/workflows/vulncheck.yml), against forsgren#87 |

The other exception files are empty, with the rule for a row in their header:
[Scripts/htmlhint_exceptions.txt](../Scripts/htmlhint_exceptions.txt),
[Scripts/privacy_posture_exceptions.txt](../Scripts/privacy_posture_exceptions.txt),
[Scripts/workflow_trigger_exceptions.txt](../Scripts/workflow_trigger_exceptions.txt)
and
[Scripts/required_pages_exclusions.txt](../Scripts/required_pages_exclusions.txt).
zizmor has no suppression either ([.github/zizmor.yml](../.github/zizmor.yml)).

The browser gate has three data files: [Scripts/browser_gate_variants.txt](../Scripts/browser_gate_variants.txt)
(`name|how`, one row here, `light|scheme:light`), and two with no rows because
forsgren has no finding and no external embed:
[Scripts/browser_gate_baseline.txt](../Scripts/browser_gate_baseline.txt)
(a shrink-only baseline: `axe|variant|page|rule|selector|reason`,
`cls|variant|page|value|reason`, a reason on every row) and
[Scripts/browser_gate_exceptions.txt](../Scripts/browser_gate_exceptions.txt)
(`resource|reason`, `external|url prefix|reason`). A row is added only by a
ruling; a missing file is exit 2.

## Checks outside the order file

- **gofmt fix**: `FBP.sh` runs `gofmt -w` before sfl; sfl and CI only check.
- **Tool install, npm install sync, the opening pull** (`git pull --ff-only`,
  or a rebase when nothing overlaps, forsgren#283): sfl only, local
  steps with their own self-tests in the order file (`install_tools`,
  `npm_sync_install`, `sfl_pull`).
- **DCO sign-off**: `.github/workflows/dco.yml` on pull requests and pushes
  to main, with its self-test in the order file.
- **Private names in commit messages** (forsgren#213): the second job of
  `.github/workflows/dco.yml`, `Scripts/check_commit_messages.sh`, with its
  self-test in the order file.
- **Scheduled vulnerability scan**: `.github/workflows/vulncheck.yml` runs the
  Go vulnerabilities gate daily, shown in the order file by
  `test_vulncheck_workflow.sh`.
- **Preview deploy start**: the `preview` job of `.github/workflows/quality.yml`
  starts the preview repository's deploy after a push to main, only when every
  other job succeeded, through `Scripts/dispatch_preview.sh`; the order file
  shows it by `test_dispatch_preview.sh` and `test_preview_workflow.sh`. A
  start that does not answer 204 fails the run.
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

## The language gate (forsgren#220)

The gate (row 123, `Scripts/gate_language_pages.sh` running the canon
`Scripts/gate_language.sh`) checks the text a visitor reads on every generated
page, the metrics site and the starter page, with LanguageTool 6.8 in `en-GB`
(`Scripts/language_settings.txt`), plus the values of `alt`, `title` and
`aria-label`. The canon gate checks one directory and a row names a script, so the
wrapper puts both in one temporary directory, the starter page as
`starter/index.html`. It does not check `<head>`, `script`, `style`, `pre` or `svg`.

- **Local only.** LanguageTool runs on this machine under `sandbox-exec` with the
  network denied, so no page text can leave it. A missing LanguageTool, Java or
  sandbox-exec is red in both modes. The version is pinned by
  `language_tool_version`; another version is red.
- **Mode `enforce`.** A finding that is not allowlisted or baselined is red, and so
  is a baseline row whose finding is gone.
- **Data.** [Scripts/language_allowlist.txt](../Scripts/language_allowlist.txt)
  (6 words: the product name in two spellings, the standard's name, one surname,
  the template repository name, a robots keyword) and
  [Scripts/language_baseline.txt](../Scripts/language_baseline.txt) (13 rows, 13
  findings, each with its reason). The measurement found no real error; the one
  style hint (`By default` without a comma) is accepted as written.
- **Tool in CI.** CI runs on GitHub's `macos-latest`, which has no LanguageTool.
  `Scripts/required_tools.txt` lists `languagetool`, so the Install tools step
  installs it from Homebrew with its own keg-only `openjdk@17` (no other job sees
  a changed Java), the same as a local sfl run. The ruling's plan was the official
  zip checked against a recorded SHA-256, but languagetool.org publishes no 6.8
  zip: its download directory ends at 6.6 (`LanguageTool-stable.zip` is 6.6), and
  the pin would then differ from the version a local run uses. If the zip is
  wanted later, the pin has to move to a published version on both.

## The baselines on the Quality run page (forsgren#220)

`Scripts/report_baselines.sh <section>` (`report_baselines v4`) renders one
gate's baseline data as markdown tables, to stdout and to `$GITHUB_STEP_SUMMARY`.
Quality has one step per section after the report, each `if: always()` so it shows
when a gate is red, pinned by name in `Scripts/test_gate_wiring.sh` (pin 2b):
`Language baselines` (rows with the sentence where the text is used, and the allowlist words), `Browser baselines` (axe rows,
CLS rows, sideways rows, counts by rule and by page) and `Image baselines`. forsgren has no image
size gate, so that step prints that this site has no such file; that is correct
and stays. The sentence is not stored in the baseline: the report finds each row's recorded
context in the visible text of the row's own page, extracted by the gate itself
(`gate_language.sh --text`), and shows the enclosing sentence, bounded by `.`,
`!`, `?` or the paragraph and cut near 200 characters with `…`. The pages are
`language_page_roots` of `Scripts/language_settings.txt`: here `.build/site` and
`starter=.build/starter`, the same layout the pages wrapper gives the gate, so a
starter page row is keyed `starter/index.html`. Quality's baseline steps run after
the POST gates, so the built pages exist. A missing page or context says so
without failing the step. It reads data files and runs no gate; an unreadable file or a
malformed row fails the step. Its self-test is the PRE row 124.

## The ratchet today

`MIN_GATES` is 162, which equals the 162 rows of the order file (158 with a
script and 4 `n/a` rows; the pipe into grep -q gate and its self-test, forsgren#428,
made 160, the Linux tool install self-test, forsgren#427, made 161, and the browser
gate process self-test, forsgren#386, made 162). forsgren#215 brought it to 115 and the Go tool
helper self-test of forsgren#216 is the 116th; the browser gate and its
self-test (forsgren#205) made 118, and the live check self-test
(forsgren#205, step 2 of 2) made 119; the language gate, the pages wrapper's
self-test and the baseline report self-test (forsgren#220) made 123; the
self-tests of the release plan and the release bump (forsgren#221, step 1 of
2) made 125; the five self-tests of the release scripts and the pin of the
Release workflow (forsgren#221, step 2 of 2) made 131, and the resume
self-test made 132, the token expiry self-test made 133, and the self-tests of the pin check and of the
metrics merge (forsgren#221, step 5) made 135, and the two self-tests of the git
sandbox (forsgren#228) made 137, and the bump diff self-test (forsgren#230,
step 1) made 138, and the short Quality (forsgren#230, step 2: its runner and the pin
of the scope) made 140, and the preview deploy
script's self-test and the preview workflow pin (forsgren#222) made 142, and the
pre-check's self-test (forsgren#231, step 1) made 143, and the static block's self-test (forsgren#231, step 2) made 144, and the release pre-check's self-test (forsgren#231, step 3) made 145, and the pin that the run summary comes first (forsgren#233) made 146, and the isolation of the self-tests from the run summary (forsgren#233) made 147, and the Quality runner pins gate (forsgren#240, step 1) made 148, and the self-test and the gate of the browser gate on the fixture site (forsgren#226) made 150, and the commit messages self-test (forsgren#213) made 151, and the browser gate inputs self-test (forsgren#262, step 1 of 3) made 153, and the gate selection self-test (step 2 of 3) made 154, and the sfl gate skip self-test (step 3 of 3) made 155, and the FBP push-or-rebase self-test (forsgren#283, step 1 of 2) made 156, and the sfl pull rebase self-test (forsgren#283, step 2 of 2) made 157. The self-tests of the install check and the agent proofs (forsgren#237, steps 5a and 5b) made 153. The five self-tests of the bump, the commit, the bump diff, the short Quality and its scope pin (rows 128, 130, 140, 141, 142) went with the scripts they proved (forsgren#237, step 6), which brought it down to 148. The Dependabot configuration self-test (forsgren#86) made 149. The isolation scope self-test (forsgren#251, step 1) made 150.
