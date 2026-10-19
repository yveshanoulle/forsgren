# Contributing to forsgren

## Proposing a change

Open an issue first for anything larger than a typo, so the change can be
agreed before it is built. Then send a pull request against `main`. Every
change keeps the gates green: run `./FBP.sh --no-commit` (see [Working on forsgren](docs/development.md#working-on-forsgren)) before you push.

A pull request from outside the repository gets CI only after the
maintainer has approved its workflow run.

## What we check

Every run of the gates (`./FBP.sh`, and the Quality workflow in CI) checks the
following, in this order, each with the script that does it and the phase it
runs in (`pre` before the site is built, `post` on the built site). The list is
generated from [Scripts/gate_report_order.txt](Scripts/gate_report_order.txt) by
`./Scripts/render_gate_list.sh`, and a test fails when it differs. The Quality
run report shows how many checks each of them ran.

<!-- gate-list:start -->
- secret-scan self-test (`Scripts/test_check_secrets.sh`, pre)
- secret scan (`Scripts/check_secrets.sh`, pre)
- data guard self-test (`Scripts/test_check_data_guard.sh`, pre)
- data guard (`Scripts/check_data_guard.sh`, pre)
- private-names self-test (`Scripts/test_check_private_names.sh`, pre)
- private names (`Scripts/check_private_names.sh`, pre)
- gofmt self-test (`Scripts/test_check_gofmt.sh`, pre)
- gofmt (`Scripts/check_gofmt.sh`, pre)
- Go lint self-test (`Scripts/test_check_go_lint.sh`, pre)
- Go lint (`Scripts/check_go_lint.sh`, pre)
- actionlint self-test (`Scripts/test_check_actionlint.sh`, pre)
- actionlint forsgren cases self-test (`Scripts/test_check_actionlint_forsgren.sh`, pre)
- actionlint (`Scripts/check_actionlint.sh`, pre)
- shellcheck self-test (`Scripts/test_check_shellcheck.sh`, pre)
- shellcheck (`Scripts/check_shellcheck.sh`, pre)
- yamllint self-test (`Scripts/test_check_yamllint.sh`, pre)
- yamllint (`Scripts/check_yamllint.sh`, pre)
- zizmor self-test (`Scripts/test_check_zizmor.sh`, pre)
- zizmor (`Scripts/check_zizmor.sh`, pre)
- private-names secret sync self-test (`Scripts/test_sync_private_names_secrets.sh`, pre)
- private-names local file self-test (`Scripts/test_ensure_private_names_file.sh`, pre)
- sfl pull contract (`Scripts/test_sfl_pull.sh`, pre)
- npm manifest policy self-test (`Scripts/test_check_guardrail_packages.sh`, pre)
- npm manifest policy (`Scripts/check_guardrail_packages.sh`, pre)
- tool install self-test (`Scripts/test_install_tools.sh`, pre)
- npm install sync self-test (`Scripts/test_npm_sync_install.sh`, pre)
- site-settings self-test (`Scripts/test_lib_site_settings.sh`, pre)
- HTMLHint self-test (`Scripts/test_gate_htmlhint.sh`, pre)
- HTMLHint (`Scripts/gate_htmlhint.sh`, post)
- Stylelint self-test (`Scripts/test_gate_stylelint.sh`, pre)
- Stylelint (`Scripts/gate_stylelint.sh`, post)
- Stylelint source-fix self-test (`Scripts/test_fix_source_css.sh`, pre)
- starter page build (`Scripts/build_starter_page.sh`, post)
- starter page HTMLHint (`Scripts/gate_htmlhint_starter.sh`, post)
- starter page privacy posture (`Scripts/check_privacy_posture_starter.sh`, post)
- starter page links (`Scripts/check_starter_links.sh`, post)
- language gate self-test (`Scripts/test_gate_language.sh`, pre)
- language pages wrapper self-test (`Scripts/test_gate_language_pages.sh`, pre)
- language gate (`Scripts/gate_language_pages.sh`, post)
- baseline report self-test (`Scripts/test_report_baselines.sh`, pre)
- required-pages self-test (`Scripts/test_validate_required_pages.sh`, pre)
- required-pages manifest (`Scripts/validate_required_pages.sh`, post)
- mutation: checkout pins (`Scripts/test_workflow_checkout_pins_mutations.sh`, pre)
- checkout pins (`Scripts/test_workflow_checkout_pins.sh`, pre)
- html-duplication self-test (`Scripts/test_check_html_dupl.sh`, pre)
- html duplication (`Scripts/check_html_dupl.sh`, pre)
- html duplication, generated page self-test (`Scripts/test_check_html_dupl_site.sh`, pre)
- html duplication, generated page (`Scripts/check_html_dupl_site.sh`, post)
- golden-pages self-test (`Scripts/test_check_golden_pages.sh`, pre)
- golden pages (`Scripts/check_golden_pages.sh`, pre)
- FBP --no-push self-test (`Scripts/test_fbp_no_push.sh`, pre)
- gate wiring (`Scripts/test_gate_wiring.sh`, pre)
- CI phase runner self-test (`Scripts/test_run_ci_phase.sh`, pre)
- go mod tidy self-test (`Scripts/test_check_go_mod_tidy.sh`, pre)
- go mod tidy (`Scripts/check_go_mod_tidy.sh`, pre)
- Go tests self-test (`Scripts/test_check_go_tests.sh`, pre)
- Go tests (`Scripts/check_go_tests.sh`, pre)
- Go coverage self-test (`Scripts/test_check_coverage.sh`, pre)
- Go coverage (`Scripts/check_coverage.sh`, pre)
- Go tool helper self-test (`Scripts/test_lib_go_tool.sh`, pre)
- Go test duplication self-test (`Scripts/test_check_test_dupl.sh`, pre)
- Go test duplication (`Scripts/check_test_dupl.sh`, pre)
- Go file length self-test (`Scripts/test_check_file_length.sh`, pre)
- Go file length (`Scripts/check_file_length.sh`, pre)
- Go vulnerabilities self-test (`Scripts/test_check_govulncheck.sh`, pre)
- Go vulnerabilities (`Scripts/check_govulncheck.sh`, pre)
- Go dead code self-test (`Scripts/test_check_deadcode.sh`, pre)
- Go dead code (`Scripts/check_deadcode.sh`, pre)
- lint-coverage self-test (`Scripts/test_check_lint_coverage.sh`, pre)
- lint coverage (`Scripts/check_lint_coverage.sh`, post)
- npm-audit self-test (`Scripts/test_npm_audit_check.sh`, pre)
- npm audit (`Scripts/npm_audit_check.sh`, pre)
- manifest-covers-site self-test (`Scripts/test_required_pages_covers_site_selftest.sh`, pre)
- manifest covers site (`Scripts/test_required_pages_covers_site.sh`, post)
- quality trigger scope (`Scripts/test_quality_trigger_scope.sh`, pre)
- quality runner pins (`Scripts/test_quality_runner_pins.sh`, pre)
- stray tracked files (`Scripts/test_no_stray_tracked_files.sh`, pre)
- quality-report render (`Scripts/test_render_quality_report.sh`, pre)
- quality-run summary (`Scripts/test_render_quality_summary.sh`, pre)
- gate-failure summary (`Scripts/test_summarize_gate_failure.sh`, pre)
- sfl drives from the order file (`Scripts/test_sfl_drives_from_order_file.sh`, pre)
- step table (`Scripts/test_render_step_table.sh`, pre)
- FullBuildAndPush commit-message block (`Scripts/test_fbp_commit_message.sh`, pre)
- FullBuildAndPush build-site page count (`Scripts/test_fbp_build_pagecount.sh`, pre)
- FullBuildAndPush aborted run (`Scripts/test_fbp_aborted.sh`, pre)
- FullBuildAndPush abort exit (`Scripts/test_fbp_abort_exit.sh`, pre)
- privacy-posture self-test (`Scripts/test_check_privacy_posture.sh`, pre)
- privacy posture (`Scripts/check_privacy_posture.sh`, post)
- repository-links self-test (`Scripts/test_check_repo_links.sh`, pre)
- repository links (`Scripts/check_repo_links.sh`, post)
- community-files self-test (`Scripts/test_check_community_files.sh`, pre)
- community files (`Scripts/check_community_files.sh`, pre)
- exit-trap completion self-test (`Scripts/test_check_exit_trap_completion.sh`, pre)
- exit-trap completion (`Scripts/check_exit_trap_completion.sh`, pre)
- exit-trap completion behaviour (`Scripts/test_exit_trap_completion_behaviour.sh`, pre)
- markdown-links self-test (`Scripts/test_check_markdown_links.sh`, pre)
- markdown links (`Scripts/check_markdown_links.sh`, pre)
- script references self-test (`Scripts/test_check_script_references.sh`, pre)
- script references (`Scripts/check_script_references.sh`, pre)
- Node pin self-test (`Scripts/test_node_pin.sh`, pre)
- Node pin gate self-test (`Scripts/test_check_node_pin.sh`, pre)
- Node pin (`Scripts/check_node_pin.sh`, pre)
- Go toolchain pin self-test (`Scripts/test_go_toolchain.sh`, pre)
- build-site self-test (`Scripts/test_build_site.sh`, pre)
- starter page build self-test (`Scripts/test_build_starter_page.sh`, pre)
- starter page links self-test (`Scripts/test_check_starter_links.sh`, pre)
- starter page gates self-test (`Scripts/test_starter_page_gates.sh`, pre)
- workflow node pin (`Scripts/test_workflow_node_pin.sh`, pre)
- npm lockfile sync self-test (`Scripts/test_check_npm_lock_sync.sh`, pre)
- npm lockfile sync (`Scripts/check_npm_lock_sync.sh`, pre)
- workflow-triggers self-test (`Scripts/test_check_workflow_triggers.sh`, pre)
- workflow triggers (`Scripts/check_workflow_triggers.sh`, pre)
- DCO sign-off self-test (`Scripts/test_check_dco.sh`, pre)
- metrics workflow (`Scripts/test_metrics_workflow.sh`, pre)
- auto-update workflow (`Scripts/test_auto_update_workflow.sh`, pre)
- starter page workflow (`Scripts/test_starter_page_workflow.sh`, pre)
- vulncheck workflow (`Scripts/test_vulncheck_workflow.sh`, pre)
- dispatch preview self-test (`Scripts/test_dispatch_preview.sh`, pre)
- preview workflow (`Scripts/test_preview_workflow.sh`, pre)
- browser gate self-test (`Scripts/test_gate_browser.sh`, pre)
- browser gate (`Scripts/gate_browser.sh`, post)
- browser gate (fixture site) self-test (`Scripts/test_gate_browser_fixture.sh`, pre)
- browser gate (fixture site) (`Scripts/gate_browser_fixture.sh`, post)
- live check self-test (`Scripts/test_live_check.sh`, pre)
- release plan self-test (`Scripts/test_release_plan.sh`, pre)
- release bump self-test (`Scripts/test_release_bump.sh`, pre)
- release quality self-test (`Scripts/test_release_quality.sh`, pre)
- release commit self-test (`Scripts/test_release_commit.sh`, pre)
- release publish self-test (`Scripts/test_release_publish.sh`, pre)
- release pins self-test (`Scripts/test_release_pins.sh`, pre)
- release report self-test (`Scripts/test_release_report.sh`, pre)
- release precheck self-test (`Scripts/test_release_precheck.sh`, pre)
- release resume self-test (`Scripts/test_release_resume.sh`, pre)
- release token expiry self-test (`Scripts/test_release_token_expiry.sh`, pre)
- release verify pin self-test (`Scripts/test_release_verify_pin.sh`, pre)
- release metrics self-test (`Scripts/test_release_metrics.sh`, pre)
- release workflow (`Scripts/test_release_workflow.sh`, pre)
- release bump diff self-test (`Scripts/test_release_bump_diff.sh`, pre)
- run short quality self-test (`Scripts/test_run_short_quality.sh`, pre)
- quality scope (`Scripts/test_quality_scope.sh`, pre)
- quality summary first (`Scripts/test_quality_summary_first.sh`, pre)
- step summary isolation (`Scripts/test_step_summary_isolation.sh`, pre)
- git sandbox isolation self-test (`Scripts/test_git_sandbox_isolation.sh`, pre)
- git sandbox guard self-test (`Scripts/test_git_sandbox_guard.sh`, pre)
- precheck self-test (`Scripts/test_precheck.sh`, pre)
- static block self-test (`Scripts/test_sfl_static_block.sh`, pre)
- commit messages self-test (`Scripts/test_check_commit_messages.sh`, pre)
<!-- gate-list:end -->

## Reporting a vulnerability

Never in a public issue or pull request: report it privately, as
[SECURITY.md](SECURITY.md) describes.

## Licence of contributions

forsgren is licensed under the European Union Public Licence v. 1.2
(EUPL-1.2), see [LICENSE](LICENSE). Contributions are accepted under the
same licence: inbound = outbound. There is no Contributor Licence Agreement
(CLA).

## Developer Certificate of Origin

Instead of a CLA, every contribution is made under the Developer
Certificate of Origin (DCO) 1.1, from <https://developercertificate.org>:

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.


Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

You certify this by adding a `Signed-off-by` line to every commit, with
your real name and an email address you can be reached at:

```
Signed-off-by: Name <email>
```

`git commit -s` adds that line for you, from your `user.name` and
`user.email`. `./FBP.sh` signs off for you: every commit it makes, the
`*** RED ****` one included, is a `git commit --signoff`. A pull request with a commit that is not signed off is not
merged until it is.

### What the DCO check enforces

Every pull request, and every push to `main`, runs the **DCO** workflow
(`.github/workflows/dco.yml`). It is red, naming the commit, when any
commit it checks (every commit of the pull request, or every commit the
push brings to `main`; commits of an earlier push are not checked again):

- has no `Signed-off-by: Name <email>` line as a trailer: the line must
  stand whole, in the last paragraph of the commit message (where
  `git commit -s` puts it). A `Signed-off-by` in the body text, in the
  middle of a line, or as the subject line does not count;
- is signed off with an email that is not the commit's author email
  (compared without case). Each author signs off their own commits;
- has no author email at all.

Merge commits are held to the same rule (`git merge --signoff`).

Bots are exempt: a commit with no sign-off passes, and the check names it
as exempt, when GitHub links it to an account of type Bot (Dependabot and
other GitHub Apps) and that same bot opened the pull request. The check
decides on what GitHub reports, the account type and who opened the pull
request, never on a commit's author name or email: anyone can write a
bot's address into a commit. Your own commit in a bot's pull request is
held to the rule. A push to `main` has no one who opened it, so no commit
of a push is exempt. To fix a red check, sign the
commits off and force-push the branch: `git commit --amend -s` for the
last commit, `git rebase --signoff main` for all of them.
