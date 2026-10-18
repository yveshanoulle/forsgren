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
list sfl and CI both run. It has 143 rows: 139 with a script and 4 `n/a`
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
| 113 | dispatch preview self-test | `test_dispatch_preview.sh` | pre | required; stub curl, no network, 3 mutation proofs. `dispatch_preview.sh` itself is run by the `preview` job of `quality.yml` (forsgren#222) |
| 114 | preview workflow | `test_preview_workflow.sh` | pre | required; pins the `preview` job of `quality.yml`, each pin proved by a mutant of the real file |
| 115 | zizmor self-test | `test_check_zizmor.sh` | pre | required |
| 116 | zizmor | `check_zizmor.sh` | pre | required |
| 117 | browser gate self-test | `test_gate_browser.sh` | pre | required, `test_gate_browser v2`; real Chrome and axe-core, fixture sites on 127.0.0.1 |
| 118 | browser gate | `gate_browser.sh` | post | required, `gate_browser v2`; baseline and exceptions are empty, one variant (see below) |
| 119 | live check self-test | `test_live_check.sh` | pre | required, `test_live_check_selftest v1`; stub curl, no network. The live check itself, `live_check.sh` (`live_check v1`), is not a gate: it needs the deployed site and runs only in the live-check job of `starter_page.yml` |
| 120 | language gate self-test | `test_gate_language.sh` | pre | required, `test_gate_language v2`; LanguageTool stubbed, 9 mutations |
| 121 | language pages wrapper self-test | `test_gate_language_pages.sh` | pre | required; the wrapper's own, the canon gate stubbed, 3 mutations |
| 122 | language gate | `gate_language_pages.sh` | post | required; runs `gate_language.sh` (`gate_language v2`) over the metrics site and the starter page; LanguageTool 6.8 run locally and offline; mode `enforce` in `language_settings.txt`; the allowlist and the baseline are data files (see below) |
| 123 | baseline report self-test | `test_report_baselines.sh` | pre | required, `test_report_baselines v2`; the report itself, `report_baselines.sh` (`report_baselines v2`), is presentation, not a gate: Quality calls it in three steps (see below) |
| 124 | release plan self-test | `test_release_plan.sh` | pre | required; fixture data, no gh, 4 mutations. The plan itself, `release_plan.sh`, is not a gate: the Release workflow of forsgren#221 step 2 runs it |
| 125 | release bump self-test | `test_release_bump.sh` | pre | required; bumps a copy of the repository and runs `go test ./...` on it, 2 mutations. The bump itself, `release_bump.sh`, is not a gate: the Release workflow runs it |
| 126 | release quality self-test | `test_release_quality.sh` | pre | required; stub gh, 3 mutations. `release_quality.sh` is a step of the Release workflow, not a gate |
| 127 | release commit self-test | `test_release_commit.sh` | pre | required; a throwaway repository with a local bare origin, 3 mutations. `release_commit.sh` is a step of the Release workflow |
| 128 | release publish self-test | `test_release_publish.sh` | pre | required; stub gh, 3 mutations. `release_publish.sh` is a step of the Release workflow |
| 129 | release pins self-test | `test_release_pins.sh` | pre | required; a stub of the git-data API over the real template files of an earlier release, 6 mutations. `release_pins.sh` is a step of the Release workflow |
| 130 | release report self-test | `test_release_report.sh` | pre | required, 4 mutations (the failed step inferred from the log, a template failure without the resume instruction). `release_report.sh` is the last step of the Release workflow |
| 131 | release resume self-test | `test_release_resume.sh` | pre | required; stub gh and a throwaway repository, 3 mutations. `release_resume.sh` finds what a `resume: pins` or `resume: publish` run continues with; it is a step of the Release workflow |
| 132 | release token expiry self-test | `test_release_token_expiry.sh` | pre | required; stub gh, injected clock, 5 mutations (each tier edge, a header taken as fine). `release_token_expiry.sh` is a step of the Release workflow |
| 133 | release verify pin self-test | `test_release_verify_pin.sh` | pre | required; 3 mutations. `release_verify_pin.sh` reads a pin pull request (only the pins of both callers, to this release) and is a step of the Release workflow |
| 134 | release metrics self-test | `test_release_metrics.sh` | pre | required; stub gh, 4 mutations (merging more than the pins, no wait, a red run taken for done, a second run next to a green one). `release_metrics.sh` merges the pin pull request and runs forsgren in forsgren-metrics until green |
| 135 | release workflow | `test_release_workflow.sh` | pre | required; pins `.github/workflows/release.yml`: trigger, permissions, actions, order, commands, ids and outcomes, resume, the secret, no tag made by hand; 39 mutations |
| 136 | release bump diff self-test | `test_release_bump_diff.sh` | pre | required; a fixture repository bumped by the real `release_bump.sh`, 2 mutations (no parent comparison, any line of an allowed file accepted). `release_bump_diff.sh` holds a bump commit to the version bump on the green parent and is a step of the Release workflow from forsgren#230 step 2 |
| 137 | run short quality self-test | `test_run_short_quality.sh` | pre | required; stub gates in a throwaway repository, 3 mutations (the list ignored, the skipped gates not named, no tree check). `run_short_quality.sh` runs the PRE gates of `quality_bump_gates.txt` for the short Quality of a release bump and is a step of `quality.yml` (forsgren#230) |
| 138 | quality scope | `test_quality_scope.sh` | pre | required; pins the scope input of `.github/workflows/quality.yml` (default full, push and pull request always full, scope bump runs the bump diff check first and only the listed gates), 17 mutations (forsgren#230) |
| 139 | git sandbox isolation self-test | `test_git_sandbox_isolation.sh` | pre | required; runs ten git-using self-tests with `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` pointing at a decoy repository with a decoy origin, and requires both unchanged (forsgren#228) |
| 140 | git sandbox guard self-test | `test_git_sandbox_guard.sh` | pre | required; every git-using `test_*.sh` sources `lib_git_sandbox.sh`, 1 mutation (forsgren#228) |
| 141 | precheck self-test | `test_precheck.sh` | pre | required; `precheck.sh` runs the fast static gates on the changed files and the self-tests that name them, 7 cases and 2 mutations (the test-mention step skipped, a missing tool counted as a pass), and a parity check that every gate script it runs is a row of this file (forsgren#231) |
| 142 | privacy-pages self-test | n/a | n/a | n/a: there is no privacy-pages gate here to self-test |
| 143 | privacy pages | n/a | n/a | n/a: static generated page - numbers and dates only; no forms, no analytics or tracking, no cookies or storage, no third-party assets or embeds; nothing personal is collected or processed - and the privacy-posture gate above re-proves that every run rather than leaving it asserted |

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
- **Tool install, npm install sync, git pull --ff-only**: sfl only, local
  steps with their own self-tests in the order file (`install_tools`,
  `npm_sync_install`, `sfl_pull`).
- **DCO sign-off**: `.github/workflows/dco.yml` on pull requests and pushes
  to main, with its self-test in the order file.
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

The gate (row 122, `Scripts/gate_language_pages.sh` running the canon
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

`Scripts/report_baselines.sh <section>` (`report_baselines v2`) renders one
gate's baseline data as markdown tables, to stdout and to `$GITHUB_STEP_SUMMARY`.
Quality has one step per section after the report, each `if: always()` so it shows
when a gate is red, pinned by name in `Scripts/test_gate_wiring.sh` (pin 2b):
`Language baselines` (rows with the sentence where the text is used, and the allowlist words), `Browser baselines` (axe rows,
CLS rows, counts by rule and by page) and `Image baselines`. forsgren has no image
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
malformed row fails the step. Its self-test is the PRE row 123.

## The ratchet today

`MIN_GATES` is 143, which equals the 143 rows of the order file (139 with a
script and 4 `n/a` rows). forsgren#215 brought it to 115 and the Go tool
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
pre-check's self-test (forsgren#231, step 1) made 143.
