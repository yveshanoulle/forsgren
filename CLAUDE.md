# CLAUDE.md — forsgren

Guidance for Claude Code in this repository.

## What this repo is

forsgren measures the four DORA metrics for a set of GitHub repositories from
data GitHub already has, and publishes them as a small static page (see
[README.md](README.md)).
It is written in Go: one module, `github.com/yveshanoulle/forsgren`.

## Layout

- `cmd/forsgren/` — the composition root; thin. `forsgren render --out <dir>` writes the site.
- `internal/page/` — the page renderer: `html/template` files embedded with `//go:embed`, shared chrome in `templates/layout/*.html` (one `{{define}}` each), one file per page in `templates/pages/*.html`, `styles.css`, the hand-authored `required-pages.json`, golden files in `testdata/`.
- `Scripts/` — the gates, their self-tests and the build script; `Scripts/gate_report_order.txt` declares every gate.
- `.build/` — build output, never committed: `.build/bin/forsgren`, the generated site in `.build/site/`, the counts sinks.

## Build and quality gates

- **`./FBP.sh "<message>"`** (FBP = FullBuildAndPush) — the local run: `gofmt -w` → `./sfl.sh pre` → `./Scripts/build_site.sh` → `./sfl.sh post` → commit, and push only when everything is green. An ordinary red still commits locally with the subject `*** RED ****`; a secret-class red commits nothing. `./FBP.sh --no-commit` runs the gates and the build only.
- **`./sfl.sh pre|post`** — the gates of one phase, dispatched from `Scripts/gate_report_order.txt` (`label|script|phase|class`). Every gate is check-only here, as in CI, except npm audit's one-shot `npm audit fix` heal, whose lockfile change rides into the commit (CI turns that heal red).
- **`./Scripts/build_site.sh [out-dir]`** — builds `./cmd/forsgren` into `.build/bin/` and renders the site (default `.build/site`); writes the page count to `.build/site-page-count.log` only on full success.
- **`Scripts/fbp_agent_friend.sh "<message>"`** — FBP.sh under the agent-Friend commit identity, for the subagent loop.
- **CI** — `.github/workflows/quality.yml`, on every push to `main`, every pull request into `main` and by hand, on GitHub's hosted `macos-latest`: `Scripts/install_tools.sh` and `npm ci`, then `Scripts/run_ci_phase.sh pre` → `Scripts/build_site.sh` → `Scripts/run_ci_phase.sh post`, the same order-file rows as sfl, check-only. A `pull_request` trigger is allowed only on a workflow whose every job runs on a GitHub-hosted image label (`ubuntu-*`, `windows-*`, `macos-*`), never with a self-hosted runner; `Scripts/check_workflow_triggers.sh` is red otherwise. Never `pull_request_target`. `Scripts/test_quality_trigger_scope.sh` pins Quality's triggers and its `macos-latest`. See README, CI.

Adding a gate: write the script and its self-test, give each a row in the order file at its canon position, add any Homebrew tool it needs to `Scripts/required_tools.txt`, describe it in README's Quality gates, and keep `Scripts/test_sfl_drives_from_order_file.sh` green (every `Scripts/test_*.sh` must be declared). README's "Working on forsgren" explains FBP.sh, sfl.sh and the order file.

## Working rules

- Conventions for TODO/SHIPPED and issues: [CONVENTIONS.md](CONVENTIONS.md).
- The plan and Yves's rulings for the bootstrap are on [#1](https://github.com/yveshanoulle/forsgren/issues/1).
- Tests first: a new behaviour starts with a test seen failing; a ported gate comes with its fixtures, seen green, plus one mutation seen red.
- Test fixtures use made-up repositories (`acme/app`), never real private ones; the page shows numbers and dates only.
