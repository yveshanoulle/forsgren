# Shipped — forsgren

History of completed work on forsgren. Append-only.

Conventions:
[CONVENTIONS.md](CONVENTIONS.md).
Active work lives in
[TODO.md](TODO.md).

---

## 2026-10-18 — a writer's pre-check runs the fast gates and the tests that read the changed files ([#231](https://github.com/yveshanoulle/forsgren/issues/231), step 1)

`Scripts/precheck.sh` is what a writer runs before handing a change back: the checks FBP would find red after minutes, on the changed files, in seconds.

- The changed files are the tracked changes against HEAD plus the untracked files git does not ignore. It runs the gates' own scripts: shellcheck, actionlint, zizmor, yamllint, gofmt and Go lint, the gate wiring test when `Scripts/` or the order file changed, the markdown link gate for a changed `.md`, the git sandbox guard for a changed `Scripts/test_*.sh`, and every `Scripts/test_*.sh` whose source names the basename of a changed file (`SHIPPED.md`, `CLAUDE.md`, `README.md` and `TODO.md` are left out as too broad).
- One line per check, `precheck: N checks, M failed`, the elapsed seconds, exit 1 on any failure. A missing tool is a red line, never a skip.
- `check_shellcheck.sh`, `check_yamllint.sh` and `check_actionlint.sh` take an optional file list; without it they behave as before.
- Red first for the six cases (an SC2034 finding, an actionlint finding, a mentioning test run, nothing changed, a missing tool, git detection) and the parity of its gate scripts with the order file; mutation proofs for a pre-check that skips the test-mention step and one that counts a missing tool as a pass. `MIN_GATES` 142 to 143.

## 2026-10-18 — the Release run page names the issues that block the release ([#232](https://github.com/yveshanoulle/forsgren/issues/232))

When the release plan stops, the run summary lists every blocking issue in a table (issue, why it blocks, what to do), and the error annotation names the issue numbers.

- `Scripts/release_plan.sh` prints a `blocking=` machine line per blocking issue next to its red line, from the same data; `Scripts/release_report.sh` renders the table from the plan's output. The generic cause is said only when the plan names no issue.
- The job summary of a failed run starts with a red ❌ instead of the literal `::error::` (the annotation stays in the log), and every table row starts with a red ❌ in an icon column.
- The table has a blank line before its header and after its last row, so GitHub renders it (pinned in `Scripts/test_release_report.sh`, with a mutation proof for a table glued to the sentence above).
- Red first for the machine lines and the table; mutation proofs for a plan without the machine line of an open issue and a report that renders only the first issue.

## 2026-10-18 — the Release runs a short Quality on its bump commit ([#230](https://github.com/yveshanoulle/forsgren/issues/230), step 2)

The bump commit was given the full Quality for a change of version strings only.

- `quality.yml` takes a `scope` (`full` by default; a push and a pull request are always full) and, for `bump`, the green parent and the two versions. The short Quality runs `Scripts/release_bump_diff.sh` first, then only the gates of `Scripts/quality_bump_gates.txt` (secret scan, Go tests, golden pages, Go lint) through `Scripts/run_short_quality.sh`, then the site build; the run page says `short Quality for a release bump: N gates` and names every gate not run.
- The Release workflow dispatches `scope=bump` with the commit Quality was green on, so a bump on any other commit is red; `resume = publish` keeps the full Quality. The run report says `short Quality (bump)` with the run's link.
- Red first for the runner, the dispatch, the pin of the scope (`Scripts/test_quality_scope.sh`), the release pins and the report; mutation proofs for a short Quality that skips the diff check, a release that dispatches `scope=full`, a list that ignores itself and a summary that claims POST ran. `MIN_GATES` 138 to 140.

## 2026-10-18 — a release bump commit is checked to hold only the version bump ([#230](https://github.com/yveshanoulle/forsgren/issues/230), step 1)

A bump commit that changed more than the version, or sat on a commit Quality was not green on, would have been released as it was.

- `Scripts/release_bump_diff.sh <bump-sha> <green-parent-sha> <old> <new>` is green only when the commit's one parent is the green commit, every changed file is only modified and one the bump may change, and every changed line is its old line with the version replaced (the newer-release example too); each violation is a `FAIL: bump diff:` line naming file and line.
- The files the bump may change are one list, `Scripts/release_bump_scope.txt`, read by `Scripts/release_bump.sh` and the check alike, so they cannot drift.
- Red first in `Scripts/test_release_bump_diff.sh` (the real bump on a fixture repository; an extra line, an extra file, a mode change, a wrong parent, a merge commit, a version replaced in a line that also changes); mutation proofs for no parent comparison and for accepting any line of an allowed file. `MIN_GATES` 137 to 138. Not yet wired into the Release workflow (step 2).

## 2026-10-18 — the release plan stops on open issues that already landed ([#229](https://github.com/yveshanoulle/forsgren/issues/229))

An open issue with a commit on main since the latest release ships with the release anyway, because the release tags main as it is, while its notes and its bump miss it.

- `Scripts/release_plan.sh` stops on every open issue with a `#N` or `forsgren#N` in a commit subject since the latest tag, names each one, and advises closing it or splitting it; release-bump commits, other repositories' references and issues an earlier release named do not count.
- Red first in `Scripts/test_release_plan.sh` with a seam for the open issues and the commit subjects; mutation proofs for naming only the first issue and for dropping the earlier-release exclusion.
- The Release run report's plan-failure cause names these issues too; the Release workflow fetches the tags the plan needs.

## 2026-10-18 — self-tests no longer escape their sandbox ([#228](https://github.com/yveshanoulle/forsgren/issues/228))

A self-test run from a shell that exported `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` wrote into that repository: `git -C <sandbox>` does not override an exported `GIT_DIR`, so a fixture's push, config and branch changes landed in the caller's repository.

- `Scripts/lib_git_sandbox.sh` unsets every variable by which git locates a repository; every `Scripts/test_*.sh` that calls git sources it before its first git call.
- Red first: `Scripts/test_git_sandbox_isolation.sh` runs ten git-using self-tests with the variables pointing at a decoy repository with a decoy origin, and requires both unchanged; it named the changed config, refs and branches before the fix.
- `Scripts/test_git_sandbox_guard.sh` fails, naming the file, when a git-using self-test does not source the helper.

## 2026-10-18 — one chart per project on the History page ([#212](https://github.com/yveshanoulle/forsgren/issues/212), 1/1)

Yves: one trend chart per project, above that project's block; a colour for each line (Overall Performance black in light mode and white in dark mode, Deployment frequency red, Lead time for changes green, three more chosen by Lenka); every colour at 4.5:1 in both modes, tested like the trend arrows; a legend under the chart naming each line.

- The project's block opens with its name row, then one row with a full-width cell holding the chart and its legend, then the measure rows. A cell spanning the table in the tbody keeps the HTML valid and the project's name is the chart's heading.
- A line per measure of the project's total, 0 to 10 on one scale. Colours (light / dark): `#000000 / #ffffff`, red `#b3261e / #ff8a80`, green `#1b6e2f / #7fd98f`, blue `#0b57d0 / #8ab4f8`, orange `#a34100 / #ffb74d`, purple `#7b1fa2 / #ce93d8`, as `.measure-N` rules with `light-dark()`. The legend gives each line a swatch with its dash pattern, a second cue besides colour.
- The per-row Trend cells and the Trend column are removed: the project chart replaces them and nothing depends on them. With one period there is still no chart.
- Red first: `TestHistoryChartIsOnePerProjectAboveItsBlock`, `TestHistoryChartDrawsOneLinePerMeasureAndALegendNamesThem` and `TestHistoryChartColoursReachContrastInLightAndDark`. Goldens `history*` and `legend` regenerated. The colour tests read hex by value (`#000` is `#000000`), since FBP runs `stylelint --fix` on `styles.css` and it writes the short form; `styles.css` holds that form.

---

## 2026-10-18 — the History page groups per project ([#211](https://github.com/yveshanoulle/forsgren/issues/211), 1/1)

Yves: the goal was to group things. The History page was one table with a block per measure, each listing every project; it is now one table with a block per project.

- One `<tbody>` per project, headed by the project's name, in the table page's order. In it the project's total and each of its labels have a row per measure, Overall Performance first, then the five metrics. A label's row header reads `API: Deployment frequency`, with the project's name visually hidden before it; the first column header reads Measure.
- One table kept (not one per project): the periods share the same column headers, a screen reader announces each project as a row group, and the Trend charts of #212 will sit above each block later. Periods, the Trend cell per row, the beta marker, the notices and the unlisted behaviour are unchanged.
- Red first: `TestHistoryPageGroupsRowsPerProject`. Goldens `history` and `history.one-period` regenerated. `Data.HistorySections` is now `Data.HistoryGroups`.

---

## 2026-10-17 — release tags are protected by a ruleset ([#225](https://github.com/yveshanoulle/forsgren/issues/225), 1/1)

- The repository ruleset "Protect release tags" blocks moving and deleting every `v*` tag, with no bypass; creating one stays allowed for the Release workflow. Checked with a test tag that could be created but not moved or deleted, then removed. Recorded in docs/updating-and-releases.md.

---

## 2026-10-17 — a push to main starts the preview deploy ([#222](https://github.com/yveshanoulle/forsgren/issues/222), 1/1)

Tooling only: no release.

- New `preview` job at the end of `quality.yml`: after a push to `main`, and only when every other job succeeded (`needs:`, no status function in its `if:`), it runs `Scripts/dispatch_preview.sh <sha>`, which starts the deploy of the preview site (<https://feta.forsgren.forsgren.be>) in the preview repository `yveshanoulle/forsgren-metrics-feta`. A commit that fails a gate, or a pull request, never reaches it. The preview shows the newest code on `main` on the public metrics installation's collected data; it never collects.
- The script POSTs a `workflow_dispatch` with the Actions secret `PREVIEW_DISPATCH_TOKEN` (Actions read and write on the preview repository only) and requires HTTP 204. Any other status, a failing curl, an empty token or a bad sha fails the run with an `::error::` line; no other token or login is a fallback. The token reaches curl on stdin, never in its arguments.
- `macos-latest` like every job of the file, `contents: read`, one group that never cancels a run in flight (push order). Not a `workflow_run` workflow (a dangerous trigger).
- Pins: `Scripts/test_dispatch_preview.sh` (stub curl, 3 mutation proofs) and `Scripts/test_preview_workflow.sh` (the job: needs, push-only condition, no status function, runner, permissions, secret; a dispatch-triggered run, scope bump or full, never starts it; mutants include a missing `needs:`, a missing condition, `always()` and `workflow_dispatch` allowed). `MIN_GATES` 140 to 142. docs/ci.md and docs/gate-classification.md describe the preview.
- forsgren may now name its own preview environment: the word was taken out of this repository's extra private-names list in the same step.

---

## 2026-10-17 — the live check also requires charset=utf-8, shared canon `live_check v1` ([#223](https://github.com/yveshanoulle/forsgren/issues/223), 1/1)

Tooling only: no release.

- `Scripts/live_check.sh` and `Scripts/test_live_check.sh` are now shared canon (`live_check v1`, `live_check_selftest v1`), byte-identical with the two site repositories that run the same check against their deployed hosts.
- New check: the page's Content-Type must carry `charset=utf-8` (any spelling of the name, a quoted value allowed). A missing or other charset is a `❌ FAIL: live check: https page` line naming the observed Content-Type and charset. The OK line now says `https page 200 text/html charset=utf-8`.
- forsgren.be already sends `text/html; charset=utf-8`, so the live-check job stays green. The self-test gained the 5b cases and a no-charset mutation proof.

---

## 2026-10-17 — the sentence of each language baseline row on the run page ([#220](https://github.com/yveshanoulle/forsgren/issues/220))

The Language baselines table on the run page gains a `sentence` column: the
report (`report_baselines v2`) finds each row's recorded context in the visible
text of the row's own page, extracted by the gate itself (`gate_language v2`, new
`--text` mode), and shows the enclosing sentence, cut near 200 characters. It is
never stored in the baseline. New optional key `language_page_roots` in
`Scripts/language_settings.txt`: `.build/site,starter=.build/starter` here. The
four canon files are byte-identical with the other sites.

---

## 2026-10-17 — language gate and the baselines on the run page ([#220](https://github.com/yveshanoulle/forsgren/issues/220))

A language gate for the generated pages: LanguageTool 6.8 in `en-GB`, run locally
and offline (`sandbox-exec`, no network), over the metrics site and the starter
page. Mode `enforce`; names and terms in an allowlist (6 words), 13 false
positives and accepted style hints in a shrink-only baseline with a reason each;
the measurement found no real error.

- **Canon, byte-identical with the other sites:** `Scripts/gate_language.sh`
  (`gate_language v1`), `Scripts/test_gate_language.sh`, `Scripts/report_baselines.sh`
  (`report_baselines v1`) and `Scripts/test_report_baselines.sh`.
- **forsgren's own:** `Scripts/gate_language_pages.sh` (both page directories in
  one, the starter page as `starter/index.html`) with its self-test, the settings,
  allowlist and baseline files, and `languagetool` in `Scripts/required_tools.txt`
  so CI installs it with the other Homebrew tools.
- **Run page:** three `if: always()` steps, Language baselines, Browser baselines
  and Image baselines (no image size gate here, so the last says so), pinned by
  name. `MIN_GATES` 119 to 123.

---

## 2026-10-02 — bootstrap: the estate's build, gates, CI and conventions for forsgren ([#1](https://github.com/yveshanoulle/forsgren/issues/1))

Twenty-five steps, `da7bf40` … this review (step 25), each landed through
`FBP.sh`. forsgren now builds like the sites and checks like
another estate repository's PRE → BUILD → POST sfl and FBP, driven from one
order file that CI runs phase by phase on forsgren's own runner, plus
another estate repository's Go gates, around a Go module that renders one placeholder page
through `html/template`.

**What landed, by step:** 1–2 sfl/FBP with the guarded commit block and
page-count fixtures, the Go module, the placeholder page, the site build,
Go tests and gofmt; 3 the secret scan; 4 the tool installer and the exact Go
pin (`toolchain` line exported as `GOTOOLCHAIN`); 5 the commit-message
fixture must reach PRE; 6 the data guard; 7 npm (exact pins, lockfile,
`npm ci`, manifest policy, audit); 8 HTMLHint, Stylelint, lint coverage on
the generated page; 9 required pages; 10 privacy posture and repository
links; 11 HTML duplication on templates and generated page; 12 shellcheck,
yamllint, stray tracked files (12.1 no inherited suppression; 12.2 the data
guard made secret-class, its patterns as case arms); 13 script references;
14 CI (`quality.yml`, `run_ci_phase.sh`, gate wiring, trigger scope, report);
15 the flat-folder guard (15.1 go.mod ignores node_modules); 16 the
workflow-trigger gate; 17 action pins; 18 actionlint; 19 zizmor; 20 Go lint
and Go test duplication; 21 Go file length; 22 Go coverage ratchet; 23 go
mod tidy, govulncheck, deadcode; 24 refactor (one self-test harness); 25
review (docs checked against the code, comment truth, open points listed on
the issue).

**Yves's rulings on the way (all on #1):** Go, not Python; konenki's phases
and template layout too; the script is `FBP.sh`; steps 1–2 in one FBP; Go
tools through go.mod `tool` lines; gofmt auto-fix in FBP, check-only in CI;
no gosec G101 exclusion; HTML duplication ported, not n/a; the
script-reference guard and the no-pull-request-trigger gate in the
bootstrap; code only in this repository, an installation's config and data
in a data repository made from a template forsgren will provide; install
and update designed in; docs from the start; an exclusion needs Yves's yes
on an issue, inherited suppressions are removed; the data guard is
secret-class with no suppression; the climb ban is n/a while the script
folder stays flat; the gate workflow keeps the name Quality.

Open points the steps left are in the step comments on #1; the template repository, its
workflow and the getting-started doc are in TODO.md.

---

## 2026-10-05 — the /scoring/ view, released as 0.1.3 ([#47](https://github.com/yveshanoulle/forsgren/issues/47))

`0e4d7e1` … the 0.1.3 version step, each step a red and its green through
`FBP.sh`. /scoring/ is a fourth page beside /standard/ and /numbers/, named
in every view's switch and selectable as `view: scoring`: each metric's DORA
Quick Check score alone (categorical bands (6 - band) x 2, percents
(100 - whole percent) / 10), `-` where a metric has no data, and an Overall
Performance column, the exact mean of the scored metrics in whole tenths,
half up, `-` when none is scored. Deployment frequency has data once a
successful deployment is recorded; an old last success scores 0, the
lowest band. The legend credits the Quick Check (dora.dev, © Google LLC,
CC BY 4.0). The page has its golden.

**Yves's rulings (all on #47):** whole percents rounded down; `-` for a
metric without data, Overall over the scored ones; the legend credit; the
scoring page shows scores only (numbers and scores side by side is #55);
`-` means not enough evidence, 0 means observed performance in the lowest
band, and "ever deployed" is the evidence for deployment frequency. A
longer first collect run is #57.

---

## 2026-10-05 — auto-update for Dependabot's forsgren bumps, released as 0.2.0 ([#58](https://github.com/yveshanoulle/forsgren/issues/58))

`f4c761a` … the 0.2.0 version step, each step a red and its green through
`FBP.sh`. Two config keys, `auto_update` (off when absent) and
`auto_update_level`, say whether and how far an installation lets a
Dependabot pull request that bumps forsgren's pin merge itself. The command
`forsgren check-update --config <path> --repo <owner/name> --pull <n>` decides:
exit 0 merges (printing `merge <old> to <new>`), exit 1 leaves the pull
request for a human with one reason line, exit 2 is a usage, configuration or
network error. The reusable `auto_update.yml` (workflow_call only, no
permissions of its own: the caller grants contents, pull-requests and actions
write) installs forsgren from its own commit, checks out the caller at the
pull request's base commit, runs the guard, merges (squash, branch deleted)
and then starts the installation's `forsgren.yml` on the default branch; a
failed merge fails the run and starts nothing. The docs, the refactor and the
review continue in [#60](https://github.com/yveshanoulle/forsgren/issues/60)
and [#59](https://github.com/yveshanoulle/forsgren/issues/59).

## 2026-10-05 — Dependabot's forsgren pull request comes as one, released as 0.2.1 ([#61](https://github.com/yveshanoulle/forsgren/issues/61))

An installation has two caller workflows that pin forsgren, `forsgren.yml`
and `forsgren-update.yml`. The guard now takes the caller files that exist in
the repository at the pull request's base commit (`Pull.Present`, filled by
`forsgren check-update` from the directory of `--config` and the guard's own
list of callers, `update.Callers`), and leaves a pull request for a human with
the reason `moves <file> but not <file>` when it moves one of two existing
callers and not the other. A repository with one caller, or none, behaves as
before. The starter config names the possible values of `auto_update_level`
in a comment.

## 2026-10-05 — auto-update fails closed on a caller lookup error, released as 0.2.2 ([#59](https://github.com/yveshanoulle/forsgren/issues/59))

`forsgren check-update` now exits 2 when looking up a caller file fails with
anything other than does-not-exist, instead of treating the file as absent and
letting the guard decide on a partial picture; the update stays unmerged until
the lookup works. A caller file that exists but has no pin change now gets a
readable reason in the guard's output. The level tests cover `auto_update_level`
with v0.2.1 to v0.2.2, the review pins were seen failing before they went
green, and the tests share their helpers instead of each building its own.

## 2026-10-05 — the newest release within the level installs by itself, released as 0.2.3 ([#62](https://github.com/yveshanoulle/forsgren/issues/62))

Dependabot proposes only the newest release, so a pull request beyond
`auto_update_level` used to leave a safe release within the level uninstalled.
`forsgren check-update` now exits 3 with `install <old> to <new> at <sha>` when
only the level leaves a pull request and forsgren has a published release
within it; `auto_update.yml` then runs the new `forsgren install-update`, which
moves both pins on the default branch in one commit through the API, based on
the branch head it read the files at and without force, and starts
`forsgren.yml`. The bigger pull request stays open for a human. The release
list (`PublishedReleases`), the newest-within-level pick, the pin rewrite and
the commit through the git data API are each tested, and the workflow's new
steps are pinned by `Scripts/test_auto_update_workflow.sh`.

## 2026-10-06 — history_days: how far back the first run reads, released as 0.3.0 ([#57](https://github.com/yveshanoulle/forsgren/issues/57))

A new key in `forsgren.config.yml`, `history_days`, sets how far back a
repository with nothing stored is read, and the most any later run reads back.
It is a whole number of days from 1 to 1825, 365 when left out, and
`check-config` refuses anything else naming the key and the limit. The first
run used to be 90 days; collect's repository window and the failure issues'
window both follow the key now, and the starter writes `history_days: 365`.
The README documents the key, including how to read a repository again further
back.

## 2026-10-06 — history in chunks: history_chunk_days and data/reach.csv, released as 0.3.1 ([#57](https://github.com/yveshanoulle/forsgren/issues/57))

A first run of a repository now reads one chunk of history, `history_chunk_days`
(1 to 365, 100 by default), and every later run reads what is new plus one
older chunk, until the history reaches `history_days` (renamed from
`first_run_days` before it was released). `data/reach.csv` records, per
repository, the date down to which it was read; an installation without it
starts each repository at its oldest stored deployment. A read cut at the page
limit moves the reach to the oldest date it reached and warns. Raising
`history_days` later fills in the extra range chunk by chunk. The failure
issues are still read from `history_days` back on every run, and deployments
found by an older chunk add no lead time yet. The README documents it all.

## 2026-10-06 — deployment frequency: on demand above 240 in 30 days, young projects by their age, released as 0.3.2 ([#69](https://github.com/yveshanoulle/forsgren/issues/69))

On demand is now more than 240 deployments in 30 days (once an hour over an 8-hour day, 8 × 30), and a row whose first successful deployment is less than 30 days old is banded by its count scaled to 30 days of its age. The README and the legend say so.

## 2026-10-06 — failure issues read only what changed since the last run, released as 0.3.3 ([#67](https://github.com/yveshanoulle/forsgren/issues/67))

`data/failures_read.csv` (header `repository,read_at`) records per repository when its failure issues were last read. A run asks for the issues updated since then minus 1 day, a first read goes from `history_days` back, and the time moves only after a successful read and store. The README says so.

## 2026-10-06 — backfilled deployments get their commits, released as 0.3.4 ([#66](https://github.com/yveshanoulle/forsgren/issues/66))

A success stored by an older chunk is compared with the success before it in its stream, and the oldest stored success of a stream, which waits for a previous, is compared on the run that reads one. A success between two stored ones is still skipped with a warning. The README says so.

## 2026-10-06 — working_hours sets the on-demand threshold, released as 0.3.5 ([#71](https://github.com/yveshanoulle/forsgren/issues/71))

The optional top-level `working_hours` key (a whole number from 1 to 24, default 8) is read and checked by `check-config`, and on demand is now more than `working_hours` × 30 deployments in 30 days; the legend page states the configured working day and the thresholds that follow from it. The README says so.

## 2026-10-06 — the legend lists every setting, marking the ones not set, released as 0.3.6 ([#74](https://github.com/yveshanoulle/forsgren/issues/74))

The legend page has a Settings section that lists every optional key of `forsgren.config.yml` with the value forsgren uses, and marks each key the file does not set as a default. The README says so.

## 2026-10-06 — the footer says "Metrics from GitHub data.", released as 0.3.7 ([#75](https://github.com/yveshanoulle/forsgren/issues/75))

The page footer's "The five DORA metrics, from GitHub data." now reads "Metrics from GitHub data.".

## 2026-10-07 — one setup issue says what a release needs, for 0.4.0 ([#73](https://github.com/yveshanoulle/forsgren/issues/73))

Each release declares what an installation needs in `internal/needs/needs.yml` (a permission, a secret, a file or a config key; an entry applies from its release on, and a kind with no check is an error), and every metrics run checks the needs of the running version with the new `forsgren check-needs --config <path> --repository <owner/name> [--status <path>]`. When something is missing, forsgren opens one setup issue (label `forsgren-setup`, found by a hidden marker in its body, never by the label), updates it, reopens it when a need goes missing again, and closes it with a comment when everything is in place; nothing missing is `ok` even if the close failed. A refused or failed write never fails the run: `run-summary --needs-check` lists what is needed in the job summary and `render --needs-check` adds a line to the page footer. The first need is `issues: write`, declared explicitly on the forsgren job in `.github/workflows/forsgren.yml` (`write-all`, `read-all` and workflow-level permissions are not supported by the check, by ruling). The README documents it and its known limits; the template's `forsgren.yml` gets `issues: write` in its own step.

## 2026-10-07 — forsgren 0.4.0 re-releases what was 0.3.8, as a minor ([#78](https://github.com/yveshanoulle/forsgren/issues/78))

forsgren 0.4.0 re-releases what was 0.3.8, the setup issue ([#73](https://github.com/yveshanoulle/forsgren/issues/73)), as a minor because it asks every installation for `issues: write`. 0.3.8 is withdrawn: it is marked as a pre-release, so `install-update` never offers it, and 0.3.7 stayed Latest until 0.4.0. CONVENTIONS "Versions" now says when a release is a patch, a minor or a major.

## 2026-10-10 — the footer opens with the Forsgren line, the legend link follows it, released as 0.4.1 ([#83](https://github.com/yveshanoulle/forsgren/issues/83))

The footer now opens with "Forsgren <version> … Metrics from GitHub data. Calculated at … UTC", and on the table pages the "What the bands mean" link follows it, inside the footer, instead of standing above it at the end of the page. The legend page and the placeholder pages have no such link, as before. Pages fill a `footerlinks` block in the shared footer with their own links; the Settings link of [#84](https://github.com/yveshanoulle/forsgren/issues/84) goes there next.

## 2026-10-10 — the README quotes the footer's own words, released as 0.4.2 ([#90](https://github.com/yveshanoulle/forsgren/issues/90))

The README's description of the footer quoted "The five DORA metrics, from GitHub data."; the footer says "Metrics from GitHub data." The README and CLAUDE.md now quote what the template says. The release moves the running version to 0.4.2 in the code, the README, and the tests and goldens that pin it.

## 2026-10-10 — a settings page, released as 0.5.0 ([#84](https://github.com/yveshanoulle/forsgren/issues/84))

The settings left the legend for their own page, `settings.html`: it lists each config key with the value in use, and marks the keys the file does not set as defaults. The legend no longer lists them. The footer links follow: the table pages show "Settings" and "What the bands mean", the legend page links to Settings, the settings page links to What the bands mean, and no page links to itself. The release moves the running version to 0.5.0 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.5.1.

## 2026-10-10 — daily new and completed issues, released as 0.6.0 ([#76](https://github.com/yveshanoulle/forsgren/issues/76))

A new page, `issues.html`: a table Date | New | Completed with one row per UTC day, the last 30 complete days, yesterday on top, all tracked repositories together. It is linked from the view switch, after scoring, and its own switch marks only `issues` as the current entry. `collect` reads every issue of each repository, whatever its labels, and stores their events (created, closed with GitHub's reason, reopened) in `data/issues.csv`, which `render` reads next to the history; a reopen is dated when collect sees it. Only the reason `completed` counts as Completed for now; the other reasons are stored. The data guard also refuses a tracked `issues.csv` outside `testdata/`. The release moves the running version to 0.6.0 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.6.1.

## 2026-10-11 — not planned, duplicate and other closes on the issues page, released as 0.6.1 ([#76](https://github.com/yveshanoulle/forsgren/issues/76))

The issues page grew three columns after Completed: Not planned, Duplicate and Other. Every close of the day is counted in exactly one of Completed, Not planned, Duplicate and Other, by the reason GitHub gives. Other holds a close with no reason, such as an issue closed before GitHub had reasons, and a reason forsgren does not know. The release moves the running version to 0.6.1 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.6.2.

## 2026-10-11 — the Total column and the whole history on the issues page, released as 0.6.2 ([#76](https://github.com/yveshanoulle/forsgren/issues/76))

The issues page has a last column, Total: the issues open at the end of each day, across all repositories, from the created, closed and reopened events. A close of an issue with no created event lowers nothing, the order of the lines of `issues.csv` does not matter, and a negative Total, which means inconsistent data, is shown as calculated. `collect` now does one full read of every issue of a repository (no time cut, up to 10,000 issues), so the page has its history back to the first issue and the Total counts issues nothing has touched for a long time; `data/issues_full.csv` notes the repositories done, a read cut at the cap warns and leaves no mark so the next run tries again, and the daily collection continues past it. The daily read warns when its list was cut at the page limit (forsgren#104). Events are worked out from the newest stored event of an issue by time, with created before closed before reopened at the same second (decisions #100 and #109). Reopen times are the times collect saw them, so historical Totals from before a reopen was seen are estimates. The release moves the running version to 0.6.2 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.6.3.

## 2026-10-13 — empty days are hidden on the issues page, released as 0.6.3 ([#108](https://github.com/yveshanoulle/forsgren/issues/108))

The issues page no longer shows days on which nothing happened. A day is active when it has a new issue, a close of any kind or a reopen (a reopen changes the Total, so it stays visible); every other day has no row. The window stays 30 calendar days, so the page has fewer rows rather than reaching further back, and the calculation keeps every day (`IssueDay.Active`), so the Total is computed over all of them and a hidden day's Total equals the shown day before it. When no day is active, and while there are no issue events yet, the page shows one line, "No issues were opened, closed or reopened in the last 30 days.", and the view switch, instead of the table (decisions #116 and #117). The release moves the running version to 0.6.3 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.6.4.

## 2026-10-13 — the issues page lists weeks and months, released as 0.6.4 ([#89](https://github.com/yveshanoulle/forsgren/issues/89))

The issues page now shows, as well as days, the weeks and the months (decisions #118 and #119). From the top: the days of the current week, Monday to yesterday (none on a Monday); then the complete Monday-to-Sunday weeks that touch the current month, labelled by their ISO number ("Week 41"), a week that spans two months being in both (on Wednesday 14 October 2026: Tuesday 13, Monday 12, week 41, week 40, which begins in September); then every complete calendar month back to the oldest stored event ("September 2026"). The current week appears only as its days and the current month only as its weeks and days. Rows with nothing in them are hidden as for days (#108), the calculation keeps them (`IssueDay.Active`), and a week's or month's Total is the issues open at the end of its last day. The first column is now headed "Period", a note under the table explains the periods, and with no active row the page says "No issues were opened, closed or reopened before today." instead of naming 30 days. The rows come from `metrics.IssueRows` (`IssueWeekDays`, `IssueWeeks`, `IssueMonthRows`, which share the open-issues count of `IssueDays`) and the page labels them by kind (`IssueRow`, `Data.IssueRows`); the fixed 30-day window and `Data.IssueDays` are gone. This covers the week view asked for in #88, which is therefore not built separately. The release moves the running version to 0.6.4 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.6.5.

## 2026-10-13 — the Total ignores a reopen of an issue with no created event, released as 0.6.5 ([#113](https://github.com/yveshanoulle/forsgren/issues/113))

The Total on the issues page now treats a reopen like a close: a reopened event of an issue that has no created event anywhere in `issues.csv` counts 0, where it counted +1 before, so closed, reopened, closed of such an issue no longer leaves the Total one too high on every later row (decision #120). `collect` never stores a closed or reopened event without the created event of the same issue, on any of its paths (the daily read, the full read cut at its cap, the reopen dated when collect sees it), so only a hand-edited `issues.csv` was affected. The README and CLAUDE.md say that a close or a reopen of an issue with no created event is ignored. The release moves the running version to 0.6.5 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.6.6.

## 2026-10-13 — the deployment frequency cell counts weekend deployments, released as 0.7.0 ([#115](https://github.com/yveshanoulle/forsgren/issues/115))

The deployment frequency cell now ends with how many of its deployments were made at a weekend: "Between once per day and once per week · 12 · 3 at weekends" (decision #121). A weekend is a Saturday or a Sunday in UTC, taken from the deployment's `created_at`; which days count is not configurable yet (#72). The count comes from the same window as the count the cell shows, as Yves ruled while revising the first version of the decision: the last 30 days, or the last 180 days when the 30 days hold none, so a row with no deployment in 30 days and 3 in 180, one of them on a Saturday, shows "· 3 · 1 at weekends". It is shown only when it is above 0, so "· 3" and "· 0" read as before, and the numbers and scoring views do not show it. `Frequency` gets `Weekend30` and `Weekend180`, counted in `Frequency.add` with the same window test as `Last30` and `Last180`, and `Frequency.Cell` picks the pair of the window it shows; an invariant test pins that the weekend count is never above the count over a table of real histories. The legend explains "N at weekends" in one paragraph under deployment frequency, and the README and CLAUDE.md describe the rule. This is a minor release, as CONVENTIONS asks for new visible behaviour; it needs nothing from an installation and declares no need in `internal/needs/needs.yml`, so an installation on `auto_update_level: patch` receives it only when its owner moves the level or the pin. The release moves the running version to 0.7.0 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.7.1.

## 2026-10-13 — the issues page is back to days, and weeks and months have their own page, released as 0.8.0 ([#123](https://github.com/yveshanoulle/forsgren/issues/123))

Yves ruled on decision #118 that the issues page and the weeks and months are two pages, not one (the ruling overruled point 6 of #118 and #89's shared page). The issues page, `issues.html`, shows again what 0.6.3 showed: one row per UTC day of the last 30 days, yesterday first, empty days hidden (#108), the header "Date", and the message "No issues were opened, closed or reopened in the last 30 days." when nothing happened; it has no week or month row. A new page, `months.html` ("Months"), has the table 0.6.4 put on the issues page: the days of the current week up to yesterday, the complete weeks that touch the current month, and every complete month back to the oldest event, under "Period", with the note and the message "No issues were opened, closed or reopened before today." (decisions #118 and #119); empty rows are hidden as on the issues page. The view switch ends with `issues · months` on every table page (decisions on #123: the file name `months.html`, the title "Months", the link in the switch after issues, no footer links as for the issues page by decision #103, the 0.6.4 note and message texts, and the 30-day window of 0.6.3). `Data` carries `IssueDays` for the issues page and `IssueRows` for the months page, the switch loops over the issue pages (`pageData.Page`, `IssuePages`), and `required-pages.json`, `test_build_site.sh` and the golden pages (`months.golden.html`, `months.no-rows.golden.html`) know the eighth page. Found on the way: the html duplication ceiling is 0%, and two pages with the same table counted as duplication, so the table is now one shared template, `templates/layout/issuestable.html`, which each page fills with its caption, its first column header and its rows, with byte-identical output. Restoring the 0.6.3 template in step 1 brought back its message, its empty-day rule and the render wiring at once, the page counts moved with the new page in step 4, and months.html already had its skip and message behaviour, so those steps were folded or landed as one commit with mutation evidence; the commit subjects counted to 10 and then to 13 after a recount on the issue. This is a minor release, as CONVENTIONS asks for new visible behaviour (a new page); it needs nothing from an installation and declares no need in `internal/needs/needs.yml`, so an installation on `auto_update_level: patch` receives it only when its owner moves the level or the pin. The Total rule still follows #122, which comes after this. The release moves the running version to 0.8.0 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.8.1.

## 2026-10-13 — the months page groups the older months per calendar year, released as 0.8.1 ([#125](https://github.com/yveshanoulle/forsgren/issues/125))

Yves ruled on #125 that the months page keeps its name, that the months of the current year stay month rows and that the older months become one row per calendar year, released as a patch. The months page, `months.html`, now lists the days of the current week, the complete weeks touching the current month, the complete months of the current year (January up to last month; none in January) and then one row per earlier calendar year back to the year of the oldest event, labelled with the year alone ("2025"). A year row counts the events of its UTC year and its Total is the issues open at the end of 31 December; a year with no events is a zero row that still carries the Total, and the oldest year may be partial. Inactive years are hidden like the other rows while the calculation keeps them. The caption is now "Issues per day, week, month and year, all projects" and the note says months and years follow the calendar (decision #127, closed by Yves; #128 later drops the caption and moves the note to the legend page). `metrics.IssueYears`, `IssueYearRows` and `IssueYearMonths` are new, `IssueRows` ends with `KindYear` rows, and `issueRowLabel` formats them. Steps 6 and 7, and 8 and 9, landed together so main never showed a year row labelled by its first day or a golden without its note; steps 2, 4 and 9 passed on arrival and landed with mutation evidence. The Opus refactor (step 10) gave the four period functions one `rowBack` for the bounds and the two row builders one `oldestAt`, with unchanged results. This is a patch release, as CONVENTIONS asks for small visible changes; it needs nothing from an installation and declares no need in `internal/needs/needs.yml`, so an installation on `auto_update_level: patch` receives it by Dependabot. The release moves the running version to 0.8.1 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.8.2.

## 2026-10-13 — the weekend deployments have their own column, released as 0.8.2 ([#124](https://github.com/yveshanoulle/forsgren/issues/124))

Yves ruled on #124 that the weekend count moves out of the deployment frequency cell into its own column, Weekend deployments, next to Deployment frequency, overruling point 1 of decision #121 (no sixth column), and added in a comment that the numbers view gets the column too; released as a patch. The frequency cell now ends with the count alone ("Between once per day and once per week · 12"). The new column is the weekend count of the window the cell shows, 30 days, or 180 when the 30 hold none, `0` when there are none (decision #129, with the scoring view left as it was: the count is no DORA metric and has no score). The numbers view shows the weekend deployments of the last 30 days beside its 30-day count. The legend explains the column; a row with no deployments recorded is now six cells (`colspan="6"` on the standard view). `Frequency.WeekendCell` and `WeekendNumberCell` are new and the invariant test of #115 reads the count from the cell and the weekend number from the column. Steps 1 to 7 landed together so main never showed the suffix twice or a legend for a suffix that was gone; step 4 passed on arrival and landed with two mutations; step 8 changed the labels fixture, whose total and API rows had become a clone for the duplication gate once they gained the identical weekend cell. The Opus refactor (step 9) gave the two cells one `windowCounts` pair, `shown()` and `last30Counts()`. Patch release 0.8.2.

## 2026-10-13 — the Total counts every reopen and every close, released as 0.8.3 ([#122](https://github.com/yveshanoulle/forsgren/issues/122))

Yves ruled on #122, overruling decision #120 and the behaviour #113 shipped in 0.6.5, that every reopen counts +1 and every close -1 on the issues page's Total, also for an issue with no created event in `issues.csv`; released as a patch. `openDelta` no longer looks at whether the issue has a created event, so `createdIssues` and its map are gone, and day, week, month and year rows all follow the rule from the same code. The two pins that said a close or a reopen of such an issue is ignored are now pins of the new rule (`TestIssueDaysTotalCountsACloseOfAnIssueItNeverSawCreated`, `...AReopen...`). `collect` always stores the created event with the first close, so a file forsgren wrote shows the same numbers; only a hand-edited `issues.csv` can now show a lower Total, a negative one included, which the page shows as calculated. README and CLAUDE.md say so.

## 2026-10-13 — one menu on every page, the issues pages renamed, one footer, released as 0.8.4 ([#128](https://github.com/yveshanoulle/forsgren/issues/128))

Yves asked for the page rework of #128, decided in #133 (Yves's ruling: no redirects, every menu label capitalised, the menu out of the DORA caption, the footer links Settings and Legend, the titles Daily and Issues, and the legend's Issues pages section) and released as a patch. The days of the last 30 days moved from `issues.html` to `days.html`, titled "Daily", and the weeks, months and years from `months.html` to `issues.html`, titled "Issues"; `months.html` is gone, with no redirect. Every one of the eight pages now opens with one menu, "View: Standard · Numbers · Scoring · Issues · Daily" (`templates/layout/menu.html`, built in Go by `pageData.Menu()`), the page's own entry plain text with `aria-current="page"`, the root's view `aria-current="true"`, and none on the settings and legend pages; the view switch left the DORA table's caption, which reads "DORA metrics" again, and the issue tables lost their caption, the page's heading naming each table. No page has a "Back to the table" link any more. Every page ends with the same footer: the version line with Calculated at, then Settings and Legend, so the settings and legend pages link to themselves too (Yves's ruling: an identical footer with self-links). The legend page is titled "Legend", its title and heading as its link (Yves's ruling, overruling #133's point 4, which kept "What the bands mean"), and its last section, Issues pages, holds the note on the periods that sat under the issues table. Found on the way (step 7): `Scripts/build_site.sh` copied a fresh render over `.build/site` and never removed a page an earlier build left, so the renamed `months.html` stayed locally and `test_required_pages_covers_site.sh` saw it as undeclared (CI starts from a fresh checkout, so only local runs saw it); the build now removes every `*.html` and `styles.css` it does not produce and the folders they leave empty, and keeps other files, which `test_build_site.sh` pins. The ladder counted 16 steps: 1 to 7 (the rename, the menu entries and the build fix, 556dc31), 8 to 12 (the menu, the captions, the Back links, the footer and the periods note, landed together so the note was never missing from both places, 4496e59), and 13 to 16 in this build: the legend title, the Opus refactor (the menu built in Go, one template loop), the docs (README, CLAUDE.md, the starter config's comment on `view:`, which now names the menu, and code comments), and this entry with the release. The unused `.views` rule left `styles.css`. This is a patch release; it needs nothing from an installation and declares no need in `internal/needs/needs.yml`, so an installation on `auto_update_level: patch` receives it by Dependabot. The release moves the running version to 0.8.4 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.8.5.

## 2026-10-13 — the issues tables count the issues created, the views get a DORA metrics heading, FBP.sh and four more scripts report an abort, released as 0.8.5 ([#134](https://github.com/yveshanoulle/forsgren/issues/134), [#135](https://github.com/yveshanoulle/forsgren/issues/135), [#136](https://github.com/yveshanoulle/forsgren/issues/136), [#137](https://github.com/yveshanoulle/forsgren/issues/137))

Yves asked on #134 for the real total next to the open count, and for Open / Total as a percentage; he ruled option A (Total counts created events only; Open / Total is shown as calculated) and that #135, #136 and #137 ship in the same release, 0.8.5 (of #137: "as it is a bug and that should be released ASAP"), a patch like the other column and row additions. #134: the issues tables' `Total` column, the issues open at the end of each day, week, month or year, is renamed `Open` (`IssueDay.Total` is now `IssueDay.Open`); a new `Total` column next to it is every issue created up to the end of the period, open or closed (`createdDelta`: one per created event, so a reopen adds none, and an issue whose created event is not stored is not counted, while a close or a reopen of it still moves Open, forsgren#122); a third column, `Open / Total` (`IssueDay.OpenShare`), is Open out of Total in whole percent, rounded down like the change fail rate, and a dash when Total is 0. On incomplete history Open can exceed Total and the percent then exceeds 100%, shown as calculated, as a negative Open always was. The three columns are on the days and the issues page alike (one shared template), the legend's Issues pages section explains them, and `openChanges` and `addUpOpen` became `periodChanges` and `addUp`, which sum any count per period, and the final refactor made `periodRows` loop over a small table, `runningCounts` (one `runningCount` of delta and column for Open and Total), instead of two copies of the same two calls. The build went in four parts: cea02a1 (the rename and the Total count in metrics, with the coverage entries for the renamed functions added in a fix), dae59c8 (the Total column, `OpenShare`, the dash), 8350529 (the Open / Total column and the legend text). #135: the standard, numbers and scoring pages and the root, a view too, open with a visible `<h1 id="metrics-heading">DORA metrics</h1>` after the menu, where the issues page shows Issues (Yves's ruling: "DORA metrics" for the views, the version stays in the footer); the metrics table lost its caption and is named by that heading, as the issue tables since #128; `styles.css` has one `h1` rule (bold, 1.25rem, the caption's look, whose rule is gone) that styles every page's heading, so a change there changes all (2b0df35, after a lint fix that split the styles test into helpers). The two cmd tests that found the version in the hidden h1 now find it in the footer. #136: on bash 3.2 an unbound variable under `set -eu` after the EXIT trap ended `FBP.sh` with status 0 and "All checks passed", so a caller read an aborted run as green; `FBP.sh` now sets a `COMPLETED` flag as its last statement and `print_summary` reports an exit 0 without it as `Aborted ❌` with exit 1 (`FBP_VERSION` 5, `Scripts/test_fbp_abort_exit.sh` in the gate order, 88e8e0d); `sfl.sh` sets neither -e nor -u and did not reproduce. #137 then took the class: `Scripts/check_exit_trap_completion.sh` (with its self-test) is red for a script under `set -e` with a top-level EXIT trap and no completion flag; it found `build_site.sh`, `test_sfl_pull.sh` and `test_validate_required_pages.sh`, and a fourth, `gate_htmlhint.sh`, found and reproduced by hand, and all four now carry the COMPLETED idiom (0f4739c, landed with 6961710; the first version of those traps removed `$$STAGE` instead of `$STAGE` and so never cleaned their temporary directories, which the behaviour test caught before the push). Yves then asked for the behaviour test too: `Scripts/test_exit_trap_completion_behaviour.sh` copies each real script into a sandbox, injects an unbound variable right after its trap, and requires a non-zero exit, the probe named on stderr, the aborted-before-completing line and no temporary directory left behind (6961710; the refactor split it into `probe_sandbox`, `probe_verdict` and `probe_case`). The commits are cea02a1, dae59c8, 8350529 and 2b0df35 for #134 and #135, 88e8e0d for #136, 0f4739c and 6961710 for #137, and this build for the refactor, the docs and 0.8.5. This is a patch release; it needs nothing from an installation and declares no need in `internal/needs/needs.yml`, so an installation on `auto_update_level: patch` receives it by Dependabot. The release moves the running version to 0.8.5 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.8.6.

## 2026-10-14 — an Open bugs column, trend arrows on Open and Open bugs, the settings page as a table, the data guard knows every data file, released as 0.8.6 ([#126](https://github.com/yveshanoulle/forsgren/issues/126), [#141](https://github.com/yveshanoulle/forsgren/issues/141), [#143](https://github.com/yveshanoulle/forsgren/issues/143))

Yves asked on #126 for a column of open bugs in the issues tables and an arrow, up or down, in the colours of the total; his ruling: a bug is an issue that carries the GitHub `bug` label, not configurable, the label as it is at the latest collection applied to the whole history (a true label history would take one API call per issue), and the arrow on both Open and Open bugs, with #114 (the Open arrow) closing as covered. Collection: each run reads the repository's issues under the label (`issues?labels=bug&state=all`, no `since`, up to 100 pages) after its issue events and stores `data/issue_bugs.csv` (issue bugs format v1, `repository,issue,bug`, the newest line per issue wins and a line is written only when a flag changes), so an installation that upgrades gets the whole history of its bugs on its first run with no full re-read; a stored bug that is no longer listed is stored again as not a bug; a read that stops at its 100-page cap says so on stderr and removes no flag; a refused list or an unwritable file fails the repository and a file that is not in the format refuses the repository before GitHub is asked, and `render` refuses it by name. `IssueEvent.Bug` is an in-memory flag that `render` sets from that file, `IssueDay.OpenBugs` counts the open issues that carry it (`bugDelta`, summed like Open), and the days and issues tables show Open | Open bugs | Total | Open / Total. Each of the two counts has a change over the row's period (`OpenChange`, `OpenBugsChange`, read as `TrendUp`, `TrendDown` or `TrendFlat`); a row is compared with the end of the period before it of the same kind (a week with the week before, never with a day below it in the list) and the oldest row of a kind with the count just before its period, even outside the rows shown. The cell shows `5 ▲ +3`, `2 ▼ −2` or `4 –` in a span with `role="img"` and an `aria-label` in words ("open issues increased by 3", "open bugs decreased by 2", "open issues unchanged"), through one `trend` template and the template function `trend` (`trend.go`); red means a rising count and green a falling one, not worse and better, with grey for no change. `styles.css` sets colours for the first time, Yves's narrow exception (the trend arrows only): `.trend-up` `#b3261e` / `#ff8a80`, `.trend-down` `#1b6e2f` / `#7fd98f`, `.trend-flat` `#595959` / `#b0b0b0` as `light-dark(light, dark)`, measured by a test at 4.5:1 or more (6.3:1 to 10.9:1) on white and on the three usual dark canvases. The legend explains the arrows, what the oldest row compares against and the Open bugs column. The known limit is forsgren #140: a capped bug read warns but its Open bugs cell is not marked as incomplete. #141 (Yves): the settings page is a table, Parameter | Current value | Possible values | Default, where Default is True when `forsgren.config.yml` does not set the key and False when it does, even to the default's value (the legend says so); the possible values are built from the config package's own constants and limits (`settings.go`) and a test holds each list to what `config.Load`, that is check-config, accepts and refuses, and an unset `auto_update_level` keeps `none` as its current value with the possible values `patch, minor, major (required when auto_update is true)`. #143 (found on the way, with reach.csv): the data guard named `issues.csv` but not `issues_full.csv`, `failures_read.csv`, `issue_bugs.csv` or `reach.csv`; it now refuses all four outside `data/` and `testdata/`, and its self-test reads every `const <Name>File = "<name>.csv"` in `internal/collect` and fails when one is not guarded, so a future data file cannot be forgotten. The ladder counted 29 steps: 1 to 6 (the label read and the flag store, the malformed-file, refused-list and unwritable-file cases, 124a669), 7 to 9 (removals, the cap guard, the unreadable file, d4646ef, 43c42e6, a201fed), 10 to 13 (`OpenBugs`, render marks the bugs, the column, render refuses a bad file, 7189cf8, 8735110, 30f92ce, a9d8cbe), 14 to 19 (the trend: up, down, flat, the oldest row, Open bugs, week and month rows, 0e37739 to 700d314), 20 to 22 (the arrows in the tables and the colours, d3bef9a, 8d61182, f5a3226), 23 to 25 (#141 and the legend, e7e2aa7, cf4eae0, ead02f8), 26 (docs, e7eaf2e), 27 (#143, 3b32cb4), 28 (the refactor, d55b422) and 29 in this build, SHIPPED and 0.8.6. CodeScene scored every changed Go file, and two test files that steps 1 to 13 had left below 10 got their duplication removed. This is a patch release; it needs nothing from an installation and declares no need in `internal/needs/needs.yml`, so an installation on `auto_update_level: patch` receives it by Dependabot, and its first run after the update reads the bug labels. The release moves the running version to 0.8.6 in the code, the README, and the tests and goldens that pin it, and the newer-release examples to 0.8.7.

## 2026-10-14 — the README is short and the reference lives in docs/, released as 0.8.7 ([#130](https://github.com/yveshanoulle/forsgren/issues/130))

Yves asked on #130 (2026-10-13), while planning the forsgren.be page, for a README that tells a visitor what forsgren is and how to install it, with the reference moved out; the plan, its eight choices (decision #146) and the 11 steps are on the issue. Every section moved verbatim, step by step: 1 `docs/development.md` (797828e), 2 `docs/quality-gates.md` (b86aa8c), 3 `docs/ci.md` (ca614c7), 4 `docs/data-files.md` (3042228), 5 `docs/pages-and-views.md` (b7617fb), 6 `docs/configuration.md` (2713976), 7 `docs/updating-and-releases.md` (f6e207f), 8 the short README (e68f9be), 9 the docs refer to each other with relative links instead of section names (6b0014d), 10 the page and `agent-installer.md` link `docs/configuration.md` directly, red and green (8f96e94), and 11 this build, SHIPPED and 0.8.7.

The file map: `README.md` (about 100 lines: intro, the five metrics with a paragraph each, what it produces, a live example, installing, a Documentation list, Status, Licence and Security), `docs/configuration.md` (Configuration, Running forsgren), `docs/data-files.md` (How it gets its data, the paragraph of Where configuration and data live, History, Collecting deployments with Issue events), `docs/pages-and-views.md` (the five metric sections, The page, Privacy), `docs/updating-and-releases.md` (The setup issue, Auto-update, the agent install and newer-release paragraphs), `docs/development.md` (the data guard, Working on forsgren, the tools and their pins, the tooling's own fixtures), `docs/quality-gates.md` and `docs/ci.md`. Nothing was lost or duplicated: after each step the non-blank lines of the old README equalled the new README plus the new file, except for headings, pointer lines and the changed links.

The anchors kept: `#readme` is the top of the README, and `## Configuration` stays in the README as a stub, so the `#configuration` link of already published pages, the `# Reference:` comment in installed `forsgren.config.yml` files and the template's links keep working. The no-projects page and the `# Reference:` comment `agent-installer.md` writes into a new install now link `docs/configuration.md` directly. The other README headings are gone as anchors; no link to them was found in the repositories, the releases or the issues.

Two follow-ups are filed: #147 (a gate for relative links and anchors in the Markdown files, since no gate reads them today) and #148 (a test that pins the "Forsgren x.y.z" strings in the docs to `version`). Until then the release bump covers `README.md` and `docs/`, five strings: one in `docs/pages-and-views.md`, three in `docs/configuration.md` and the one in `docs/updating-and-releases.md` that wraps over two lines ("forsgren" then "0.8.7 needs more configuration"). This is a patch release; it needs nothing from an installation and declares no need in `internal/needs/needs.yml`. The release moves the running version to 0.8.7 in the code, the docs, and the tests and goldens that pin it, and the newer-release examples to 0.8.8. `agent-installer.md`'s "Tested with" line is left as it is (decision #144).

---

## 2026-10-14 — agent-installer.md: one file a coding agent follows to install forsgren, proven by a real install ([#142](https://github.com/yveshanoulle/forsgren/issues/142), [#131](https://github.com/yveshanoulle/forsgren/issues/131))

Yves's idea (2026-10-14): someone who wants their own forsgren points their coding agent at one file, and the agent does the install from that file alone, asking the person only what they must decide and handing them the few things only they can do (a token, DNS, a domain verification). Nine steps: 1 the file and its README link (4b9d312), 2 `forsgren.<your domain>` as the recommended custom domain with an already verified parent checked (4cf5077), 3 `forsgren-metrics` as the default data repository name (ee14e70), 4 the model it is tested with, claude-sonnet-5-5 (6f2c592), 5 how the person starts the agent (a1239f8), 6 how to answer the questions, filled-in defaults and an explicit go that names the commits (bee5ef8), 7 the work folder inside the start folder and the folder-trust prompt (bf934dd), 8 the update wait, changing a setting later, the CNAME trailing dot and the 0.8.6 settings-table check (a65d658), 9 the certificate nudge and the work-folder removal (3934da6).

The proof (Yves's rule): #131, forsgren.forsgren.be, installed by a fresh Sonnet session that read only this file. Attempt 1 failed on an unrequested commit (the file then asks for an explicit go); attempt 2 passed with the defaults; attempt 3 (public, major, 1825 days of history, a custom domain) passed all 17 steps. Two things in attempt 3 were done by hand and are recorded on #131: the update wait set to 0 (on purpose: forsgren-metrics is the main example and takes each release at once), and the custom domain removed and set again to get the certificate.

What attempt 3 taught, now in the file (step 9): GitHub starts no new certificate request when the same custom domain is saved again, so step 16 removes it first (`-F cname=null`, not yet run in a real install) and sets it again, at most once, and otherwise gives the person the Settings > Pages click path that worked; every `rm -r WORK` first leaves the folder, so the agent never deletes its own working directory. The new package `internal/installerdoc` holds the first tests that read the file (three: the removal call, the click-path tip, and the cd before each rm).

Not covered here: a scheduled update arriving with nobody starting it (#154), the domain-verification click path (Yves installs 1.x on a new domain once #150 is done), and a gate on the "Tested with" version (#148).

---

## 2026-10-14 — new installations update at major level, released as 1.0.0 ([#150](https://github.com/yveshanoulle/forsgren/issues/150))

Yves asked (2026-10-14) that a new installation takes every forsgren release by default, now that the update path is robust and there is an agent installer, and ruled that this ships as forsgren 1.0.0. CONVENTIONS.md keeps its definition of a major release (an installation that does nothing would stop working), which this change does not meet; 1.0.0 is a major anyway because forsgren stayed on 0.x too long, and with the update guard, the quality gates and the agent installer in place, now is the time: 1.0.0 marks the defaults as stable.

What changed: 1 the starter writes `auto_update_level: major` (2186387); 2 the starter's comment says what that means (c9bbe00); 3 agent-installer.md step 7 and its step 9 example (6f2265a); 4 docs/configuration.md and docs/updating-and-releases.md (80e50f3); 5 the documentation tests share one helper (this commit). The wording, approved on #150 with Yves's four adjustments: `major` permits major, minor and patch updates and does not mean a major release is safe; eligible releases merge automatically unless the update fails or is blocked; what the safeguards check (a release is cut only when Quality is green, Dependabot proposes it only after the update wait, the merge goes through only for a clean pin change to a published release); and, said out loud, nothing checks a release against the installation's own data.

What does not change: an existing installation keeps the level its own forsgren.config.yml says (`init-config` never rewrites it), the update wait default stays 3 days, and `auto_update_level` stays required while `auto_update` is true (#157 is about that). For an installation at `patch` or `minor`, v0.8.7 to v1.0.0 is a major update, so its Dependabot pull request waits for a person.

Tests: the starter's level and its limitation sentence (internal/config), and internal/installerdoc reads agent-installer.md and the docs and requires every stated default to equal the starter's level, so a future default change cannot leave a document behind.

---

## 2026-10-14 — forsgren.be: the README is the project page ([#132](https://github.com/yveshanoulle/forsgren/issues/132))

Yves wanted forsgren.be to tell a visitor what forsgren is, without a second copy of the text to keep up to date: the README itself is rendered to one page and published there. Decisions in #149 (approved): a small Go renderer for the README's own Markdown subset instead of a dependency, relative links turned into links into `main`, its own link check, the metrics site's stylesheet reused.

Steps: 1-2 the renderer with its link test and its refusal of anything outside the subset (a24e756), 3 escaping and unclosed markers (ac52cc9), 4-5 `cmd/readmepage` renders the real README and fails loud on bad input (67a96e1), 6 `Scripts/build_starter_page.sh` builds `.build/starter` with its CNAME (2ab5ceb), 7 the starter link check allows only its three destinations (664f8b5), 8 HTMLHint and the privacy posture on the page (df602c1), 9 the stylesheet (c3e87b2), 10 `starter_page.yml` deploys on a push to `main`, on a release and by hand, and a release run skips with a notice while Pages is not enabled (18fd633), 11 the docs (docs/ci.md, the README, CLAUDE.md, docs/development.md), 12 a refactor of the inline renderer (two shared helpers, the built page byte-identical), both in this commit. Steps 1 and 2 rode one FBP so the coverage total never dropped below its 99.6 floor (decision #149).

Live since 2026-10-14: https://forsgren.be/ (HTTPS enforced, `www` redirects), deployed by the push run 38545347984 and redeployed by the v1.0.0 release run 38549004390. What it took on the GitHub side, done by Yves: Pages switched on with GitHub Actions as its source; DNS for the apex (four A, four AAAA) and `www` (CNAME); the custom domain; a `v*` tag rule on the `github-pages` environment so a release run may deploy. Twice today the certificate stayed at `new` because the domain had been set before DNS was complete; removing and re-adding the domain fixed it at once (written into docs/ci.md and agent-installer.md).

Not done here: the renderer names the file of unsupported Markdown and quotes the line, but not its line number, and no test pins a quote inside a link target (#158).

---

## 2026-10-14 — the pages use the screen: up to 120rem wide, tables on one line, released as 1.1.0 ([#153](https://github.com/yveshanoulle/forsgren/issues/153))

Yves (#153): at 1800px the tables used a narrow strip of the screen and the dates and the trend ("5 ▲ +6") wrapped to a second line; he wanted one line, a table that scales with the screen, and the same width on every page so nothing jumps. The cause was a 48rem (768px) cap on every page, cells free to wrap at hyphens and spaces, and pages with a scrollbar narrower than pages without.

Steps, each its own FBP: 1 pages grow to 120rem, centred beyond (5b612bd); 2 forsgren.be stays at 72rem (135e303); 2b forsgren.be's text in a framed card (ead8669); 3 every table fills the page width (6c7ee3c); 4 the scrollbar's space is always reserved (d796063); 5 a no-wrap rule scoped by class (f84869d); 6 the issues, days, numbers and scoring tables never wrap, the standard view's band text and the settings table still do (c1c61ca); 7 running text stops at 72rem (2f17282); 8 the stylesheet tests share one CSS parser and the layout is in docs/pages-and-views.md (this commit). Decisions: #160 (Yves's answers: 120rem, forsgren.be 72rem, text 72rem, which cells never wrap) and #161 (the framed card).

A lesson recorded on #161: step 1 widened every page including forsgren.be, and its push redeployed forsgren.be at 120rem before step 2 narrowed it again; a shared-stylesheet change that widens everything should land with the rule that narrows the exception.

Not tested by a gate: how it looks in a browser at a given width (the repository has no headless browser); the rules that cause it are pinned by tests, and Yves checks it by eye at 1800px.

---

## 2026-10-14 — auto_update_level is optional and defaults to major, released as 1.2.0 ([#157](https://github.com/yveshanoulle/forsgren/issues/157))

Yves (#157): "just use the default when auto_update is set, and remove the warning in the settings page". Until now a forsgren.config.yml with `auto_update: true` and no `auto_update_level` was refused at load, which stopped check-config, collect, render and check-update alike, and the settings page carried a "required when auto_update is true" note.

Steps, each its own FBP: 1 a missing or empty level reads as `config.DefaultLevel`, which is `major`, the #150 default, for every config; the settings page shows `major` for an unset level instead of "none" (99243fd); 2 the settings page drops the note, so Possible values reads "patch, minor, major" (e0d27fd); 3 the starter comment and docs say the level is optional and defaults to `major`, and a test fails any document that calls it required (aae097a); 4 a refactor: the possible-values function gets its plain name back, the doc tests share one whitespace helper, CLAUDE.md's stale sentence is fixed (this commit). Decisions: #164 (one default everywhere; the guard keeps its defensive branch for an empty level).

What an installation sees: one that wrote a level keeps it; one with `auto_update: true` and no level used to fail and now updates at `major`. The starter still writes `auto_update_level: major` explicitly, so a new installation sees the setting. The auto-update workflow never read the level itself (forsgren check-update decides), so it needed no change.

---

## 2026-10-14 — the Issues and Daily pages can be shown or hidden; Daily is hidden by default, released as 1.3.0 ([#159](https://github.com/yveshanoulle/forsgren/issues/159))

Yves (#159): "Issues: True / False, default True. Daily: True / False, default False. When false the page is not generated or removed if it exists, also removed from the menu. The readme, legend and the agent installer need to be updated."

Steps, each its own FBP: 1 the config reads `issues_page` and `days_page`, only the literals `true` and `false` (30911d6); 2 the settings page lists both keys (ffcdfeb); 3 a hidden page is not written and a stale copy in a reused output directory is removed (ce2cc1b); 4 the menu leaves out hidden pages (0b7bfb1); 5 a render with a config applies the keys, a render without one hides nothing, so forsgren's own site and the goldens keep all eight pages (f8e9c4d); 6 the starter writes `issues_page: true` and `days_page: false` (cd3ed3e); 7 the legend always explains both keys and how to bring the Daily page back, whether the pages are shown or not (5309819, Yves overruled dropping the section); 8 the docs, the README and agent-installer.md (question 10, the step 9 example, the step 12 settings check now expects eight rows), tests that every document states the starter's defaults, and a refactor: the page names have one source, a `booleanKey` type mirrors `numberKey` (validate.go back to its CodeScene score), the render tests share one config helper (this commit). Decisions: #165.

What an installation sees at 1.3.0: one that does not set `days_page` loses its Daily page (the next run's deploy no longer has `days.html`); `days_page: true` in forsgren.config.yml brings it back at the next run. The 1.3.0 notes and docs/updating-and-releases.md say so.

---

## 2026-10-14 — agent-upgrade.md: one file a coding agent follows to upgrade an existing installation, proven by a real upgrade ([#166](https://github.com/yveshanoulle/forsgren/issues/166))

Yves's idea (2026-10-14): agent-installer.md makes a new installation; people who started on an older forsgren, or who have automatic updates switched off, need the same for an upgrade. The agent asks one thing to start, the address of the current report (Yves), and finds the rest itself: the running version from the footer, the settings from settings.html (it exists from 0.5.0; older, it reads forsgren.config.yml), the repository from the address, then the pins, dependabot.yml and the token route.

The file, step by step (each step its own FBP, the commits tagged 166-N): the checks and the one question; find the installation and compare the two pins (a half-moved or hand-edited pin stops it); the latest release and a waiting Dependabot pull request (used only when its diff moves exactly both pins); read the notes of every release in between and write down what each asks of the installation; one message of questions with the current values as defaults, the plan, and a go sentence that names every commit; the pin move in one commit through the Git Data API, or merging the waiting pull request; only the template changes the notes name; only the settings the person chose, checked with check-config; a run it starts itself and checks of the published page (footer, settings, hidden or shown pages, HTTPS); the report to the person, clean-up, "Later", and "Going back" (a new commit, never a forced branch). It supports installations from forsgren 0.2.0 on. Rules shared with agent-installer.md are repeated word for word, and a test keeps them equal. Decisions: #167.

Lessons folded in from a real older installation (unnamed): a 404 on settings.html means "older than 0.5.0", not an error; an installation repository may itself be named `forsgren`, so forsgren is only ever `yveshanoulle/forsgren` exactly; a Dependabot pull request that waits because the level is too low is named, explained and offered three ways out.

The proof (Yves's rule from #142): a fresh Claude Code session (claude-sonnet-5-5), given only the file and the report address, upgraded a throwaway installation from v0.8.5 to v1.3.0 with nothing done by hand: both pins moved in one commit, the chosen settings (auto-update on at minor, no update wait, the Daily page kept) in a second, a run started and the page checked. Three small fixes it showed are in this commit, with the Tested-with line. The installerdoc tests grew a shared helper set along the way (a refactor step), and every placeholder a command uses must be listed.

agent-upgrade.md is documentation only: no forsgren release; an agent reads it from main.

---

## 2026-10-14 — forsgren.be's renderer names the file and the line of what it refuses, released as 1.3.1 ([#158](https://github.com/yveshanoulle/forsgren/issues/158))

Yves's ruling on decision #149 asked that unsupported Markdown fail with the source file and line. The renderer named the file and quoted the line, but not its number. Steps, each its own FBP: 1 the block split carries each block's start line, the renderer returns a `LineError{Line, Msg}`, and cmd/readmepage prints `readmepage: README.md:3: unsupported Markdown, a line starting with ">": > quoted` (b7d7501); 2 a test that a `"`, `<` or `>` in a link target cannot leave the escaped href, proven by a mutation that drops the escaping (72e4cea); 3 a refactor that brought two test files back to their CodeScene score of 10 (9469ab8); 4 a pin on the error text itself (a mutation dropping the line number had failed no test), docs/ci.md and CLAUDE.md (this commit). Decisions: #168 (an error found inside a block's inline text, such as a bad link or an image, names the block's first line).

---

## 2026-10-14 — the legend explains patch, minor and major, released as 1.3.2 ([#156](https://github.com/yveshanoulle/forsgren/issues/156))

Yves (#156): the settings page lists `auto_update_level` with the values patch, minor and major, but nothing on the site said what they mean. The legend's Settings page section now explains them in forsgren's approved wording: what a patch, a minor and a major release are (CONVENTIONS.md), what each level merges by itself, and that `major` does not mean a major release is safe, because nothing checks a release against the installation's own data. Steps: 1 the legend text and its test, tied to the config's level constants (9fa6c92); 2 the test's text as a constant like its neighbour, docs/pages-and-views.md and docs/configuration.md (this commit). page_test.go keeps its CodeScene score of 10.

---

## 2026-10-14 — the footer links forsgren.be, released as 1.3.3 ([#162](https://github.com/yveshanoulle/forsgren/issues/162))

Yves (#162): now forsgren.be is live, the footer of every page should link to it instead of the GitHub repository. Steps: 1 the footer's "Forsgren" links https://forsgren.be/, the project page, which links GitHub itself; the footer text "Forsgren X.Y.Z" is unchanged, so the agent files and the docs version test still read the version (1df38d2); 2 the link gate's exception for forsgren's own GitHub link, now dead, is removed (a link to forsgren's repository is judged like any other, and a self-test pins it), cmd/forsgren's goldens regenerate with -update like the page package's, and the docs (pages-and-views.md, quality-gates.md, CLAUDE.md) follow (this commit). Decisions on #162. Found on the way: the no-projects page links a github.com blob path the link gate refuses (#172).

---

## 2026-10-14 — an incomplete Open bugs column says so, released as 1.4.0 ([#140](https://github.com/yveshanoulle/forsgren/issues/140))

Yves's ruling on #126: a successful collection does not imply complete data, and an incomplete metric must not look complete. When a repository's bug read stops at its cap (10,000 issues), its bug flags may be incomplete, and the Open bugs number, summed over every repository, would look complete while it is not. Steps, each its own FBP: 1 collect notes the repository in a new mark file, `data/issue_bugs_cut.csv`, and the data guard knows it (405c26c); 2 a complete bug read removes the note, a failed one keeps it (d7a5195); 3 render reads the file and marks every row when any repository is noted (9a67805); 4 the Open bugs cell then shows "— (incomplete)", with a title and an aria-label, no number, no arrow and no colour (1386d37); 5 the legend explains it (e0ed778); 6 a refactor (the four mark files are one table in collect, one format helper in history; two test files back to their CodeScene score of 10) and the docs (data-files.md, pages-and-views.md, development.md, CLAUDE.md) (this commit). Decisions: #171 (any capped repository marks the whole column, every row, because the page has one summed number per row).

What an installation sees: nothing changes until a bug read actually hits the cap; then the Open bugs column shows "— (incomplete)" until a later run reads the list in full. No new permission, secret or config key.

---

## 2026-10-14 — agent-delete.md: one file a coding agent follows to remove an installation, proven by a real removal ([#174](https://github.com/yveshanoulle/forsgren/issues/174))

Yves's idea (2026-10-14), next to agent-installer.md and agent-upgrade.md. The agent asks for the report's address only (or takes it from the first message), finds the repository from it (never yveshanoulle/forsgren or forsgren-template; a repository named `forsgren` under another owner is an installation), shows in one message what will go, with a go sentence that names the repository and its custom domain, downloads the repository first unless told not to, removes the custom domain (`-F cname=null`) and switches off Pages before it deletes (or archives) the repository, hands the person their steps (the CNAME, the TXT record only when no other site uses the domain, the route-B token), checks the page until it answers 404, and says plainly what rests on the person's word. Rules shared with the other two files are repeated word for word, kept equal by a test.

The proof: a fresh Claude Code session (claude-sonnet-5-5) removed a real route-B installation with a custom domain from the file alone (8cbe14c), including the first real use of the cname=null removal and a wait through GitHub's 10-minute page cache. Its Tested-with line and the first-message rule are in this commit. Docs only, no release.

---

## 2026-10-14 — a release bump cannot forget a version in the docs, and the agent files must be proven on the running major ([#148](https://github.com/yveshanoulle/forsgren/issues/148))

Each release bump edits the version strings in README.md and docs/ by hand, and the agent files name the forsgren version they were proven with; nothing caught a string left behind. Steps: 1 a test pins every "Forsgren X.Y.Z" and "forsgren X.Y.Z needs more configuration" in README.md and docs/*.md to `version`, with a minimum count per file so rewording cannot empty it; history and examples use other phrases on purpose and are not caught (84e764a); 2 after Yves's 1.x install proof on forsgren.agilelean.eu (route B, custom domain, forsgren v1.3.3), agent-installer.md's Tested-with line names v1.3.3, and a test requires every agent file's tested major to equal the running major, so a new major needs a new proof run of each (60c6db9); 3 the tests share an agent-file list and a running-major helper, and quality-gates.md, updating-and-releases.md and CLAUDE.md describe both (this commit). Decisions: #170. Tests only, no release.

---

## 2026-10-15 — a failure that is no longer a failure stops counting, released as 1.4.1 ([#155](https://github.com/yveshanoulle/forsgren/issues/155))

`data/failures.csv` only grows, so a failure issue that lost its `failure` label, or was closed as not planned, kept counting in change fail rate (and rework rate) forever. Now forsgren takes it back with a line in a new append-only file, `data/failures_withdrawn.csv` (reasons `label_removed`, `not_planned`, `issue_gone`; the newest line per issue wins, so a later line reinstates an issue that gets its label back). failures.csv keeps its format, so no installation migrates anything. Steps, each its own FBP: 1 a lost label withdraws (42cc9cf); 2 a not-planned close withdraws (a96ca01); 3 the label back reinstates, an unchanged state writes nothing (ee72b81, which went red on test-code duplication, fixed by 4f90a65); 4 a one-time catch-up re-reads the stored failures that can still count, and a deleted or transferred issue is withdrawn as `issue_gone` instead of failing its repository forever (5359b61); 5 render drops withdrawn issues before the metrics, recovery time unchanged (e8f483a); 6 a refactor (one path decides catch-up or daily, shared helpers, renames) and the docs (data-files.md, pages-and-views.md, development.md, CLAUDE.md) (this commit). Detection needs no new request: the daily read of all issues already sees a label change or a not-planned close. Decisions: #176.

---

## 2026-10-15 — forsgren tells you before FORSGREN_TOKEN expires, released as 1.5.0 ([#177](https://github.com/yveshanoulle/forsgren/issues/177))

A fine-grained token expires on a date the person chose a year earlier, and the first sign was a red daily run. GitHub names that date in its answers (the `GitHub-Authentication-Token-Expiration` header), so forsgren now reads it and speaks up from 14 days before. Steps, each its own FBP: 1 the client records the latest valid expiry header (e8250ee); 2 `collect --token-expiry <path>` writes the date as one RFC 3339 line (5ba7346); 3 collect warns on stderr within 14 days, naming the date and `gh secret set FORSGREN_TOKEN -R <repo>` in a separate terminal; the exit code is unchanged (d40a938); 4 `check-needs --token-expiry` adds that item to the setup issue (2be6627); 5 metrics.yml hands `${RUNNER_TEMP}/token-expiry` from collect to check-needs, pinned in test_metrics_workflow.sh (461828d); 6 a settings-page Token expires row (ef214ea); 7 a refactor and the docs (db7c172). Then Yves's ruling on decision #179 changed four things: 8 the settings row is gone again, since a static page cannot show a date that lives on the runner only (16b3526); 9 only answers to FORSGREN_TOKEN count, not the job's GITHUB_TOKEN, and an unreadable header is noted once per run (4c451bd); 10 three states in check-needs: a near date adds or keeps the item, a far date drops it, an unknown date keeps an item the open setup issue already carries (a hidden `<!-- forsgren:token_expiry <date> -->` mark) and never creates one (95159e4); 11 collect removes the file before anything else and writes it whole, so a failed collect never hands check-needs an old date (a1c2fab); 12 a refactor (collect's side and check-needs' side of the feature in two files, one builder for the item, the file read once) and the docs, with the limitation stated plainly (this commit). Decisions: #179.

What an installation sees: with an expiring FORSGREN_TOKEN, from 14 days before the date a log warning and a setup-issue item that stays until a new token is set. The warning works only while GitHub still accepts the token and sends the date; a token revoked or deleted early gives no warning. A token without an expiry date sees nothing new. No new permission, secret or config key.

---

## 2026-10-15 — check-needs looks the setup issue up once, and a failed lookup is pinned, released in 1.5.0 ([#181](https://github.com/yveshanoulle/forsgren/issues/181))

Found by #177's last refactor: with an unknown token expiry, check-needs looked the setup issue up twice (once to see whether it carries the renewal mark, once to write it), and the first lookup's error path had no test. Yves's ruling: both go into 1.5.0 before the release is cut. Steps, each its own FBP: 1 a test where the lookup fails while the expiry is unknown: no renewal item is kept, nothing is written or closed, today's note and status stay, proven by a mutation that kept the item (e2ca595); 2 one lookup per run, passed to both the keep and the write; a request-counting fake proves one lookup for unknown, near and far expiry with an open, closed or missing issue (two before, for unknown), with the writes unchanged; "not found" and "lookup failed" stay distinct, and neither counts as a renewal (this commit).

What an installation sees: nothing, except one GitHub request fewer per run while the token's expiry is unknown.

---

## 2026-10-15 — a setting forsgren does not accept falls back to its default and says so, released in 1.6.0 ([#183](https://github.com/yveshanoulle/forsgren/issues/183))

Yves's general rule (2026-10-15): an unaccepted value in the config no longer stops the run; forsgren uses that key's default, and the settings page makes clear the value is bad and the default is used. Until 1.5.x a value such as `view: weekly` made `config.Load` fail and the daily run red. Steps, each its own FBP: 1 `view`, the mechanism: `Config.Rejected` (key, written value, reason, default; the error text unchanged), a rejected key counts as not written, file and project errors still win (36a3b92); 2 `auto_update` and `auto_update_level`; check-update reads a rejected auto_update as off (7c148c1); 3 `history_days`, `history_chunk_days`, `working_hours` (a75d0db); 4 `issues_page`, `days_page` (bf2d483); 5 `dora_days`, checked against the history in force, every rejection listed in settings order (0cb017a); 6 a list or mapping value falls back instead of failing the whole file, shown in one-line flow form (ab2bc36); 7 `Settings()` carries the written value and reason (32d4e3f); 8 the settings page row: "0 is not accepted: … Using the default 365." (56b5ae9); 9–11 one `config: warning:` line per rejected setting in render, collect and check-update (d3d9960, 723793b, 90d4a2d); 12 check-config reports `settings not accepted: N` and exits 0 (9bf658e). No refactor of its own: Yves asked for one pass with #178 (its step 17). Decisions: #184.

What an installation sees: a setting with a bad value now warns in the log and on the settings page and uses its default; the run stays green. A file that cannot be read or parsed, a missing or unsupported `version`, an unknown key and every mistake in the projects part still stop the run.

---

## 2026-10-15 — the DORA window: 30, 90 or 180 days, released as 1.6.0 ([#178](https://github.com/yveshanoulle/forsgren/issues/178))

Yves (2026-10-15): DORA metrics are usually reported over the past 180 days; forsgren measured the last 30. A new optional key, `dora_days` (30, 90 or 180, default 30), sets the window of all five DORA metrics. Steps, each its own FBP: 1 config reads `dora_days` (0803e0a); 2 a window longer than `history_days` is not accepted (52bee9c); then #183 ran (one release for both, Yves); 3 `history_days` accepts 30 to 1825, Yves's minimum (c6c4c0f); 4 the settings page lists `dora_days` (5cdc147); 5 the starter writes it (2f42ec4); 6 the deployment-frequency band thresholds scale with the window, never the counts: 1/5/30/241 at 30 days, 3/15/90/721 at 90, 6/30/180/1441 at 180 (67e7b9c); 7 a row younger than the window scales to it (21c6311); 8–12 deployment frequency, lead time, recovery time, change fail rate and rework rate count the window (8c6dc50, 6e81a89, e154c63, 4710c48, b865a81); 13 render passes the configured window (43674df); 14 the withdrawn-failure catch-up re-reads the window (0470a8d); 15 the legend states the window and its scaled numbers (43901b6); 16 agent-installer.md asks for it and proves the row (8dc3c03); 17 one refactor and docs pass for #178 and #183: one entry point per metric taking the data, window-named fields, one "0 means 30 days" rule, settings order from one list, rejections built one way, CodeScene back to 10.0 on every changed metrics and config file; docs (configuration.md, pages-and-views.md, data-files.md, updating-and-releases.md, README.md, CLAUDE.md) (3fd3b79); 18 service rows follow `dora_days` and `working_hours`: they kept only records and commits, so a service always counted 30 days and an 8-hour day (the working-hours half dates from #71); a test now guards every setting field (this commit). Decisions: #182, #184.

What an installation sees: nothing until `dora_days` is set; then every DORA number counts that many days back and the legend says so. `history_days` under 30 now falls back to 365. Known gap: an installation that already ran the withdrawn-failure catch-up and later widens the window gets no second catch-up (rare, see data-files.md).

---

## 2026-10-15 — the run summary says how long FORSGREN_TOKEN is still valid, released as 1.6.1 ([#185](https://github.com/yveshanoulle/forsgren/issues/185))

Yves (2026-10-15), on the run summary each workflow run writes: add the days the token is still valid, and say so when that is unknown. The summary gets one line between "Update" and "Setup", read from the same `${RUNNER_TEMP}/token-expiry` file collect writes (#177): `valid for N more days (until …)`, under a day `valid for N more hours (until … UTC)`, under an hour `valid for less than an hour (until … UTC)`, singular for 1, and without a readable date `days left unknown: …` with a pointer to a failed collect step. No "expired on" line: an expired token fails collect with a 401, which names no date, so that run reads "unknown". Steps, each its own FBP: 1 run-summary `--token-expiry` and the line (21121ff); 2 metrics.yml passes the file, pinned in test_metrics_workflow.sh, and the docs (this commit). Only the run summary shows it; the published pages do not (decision #179). Decisions: #186.

---

## 2026-10-15 — the no-change dash after Open bugs is blue, released as 1.6.2 ([#152](https://github.com/yveshanoulle/forsgren/issues/152))

Yves: the – shown when the open bug count did not change should be blue. The Open and Open bugs columns shared one grey class for it, so Open bugs gets its own, `trend-flat-bugs`, in the stylesheet's light/dark pattern (`#0b57d0` light, 6.39:1 on white; `#8ab4f8` dark, at least 7.91:1), and Open stays grey. The dash keeps its "open bugs unchanged" label, so colour is not the only signal; the legend says "grey when it did not change (blue after Open bugs)". One step: the cell, the legend, the contrast test and the Days, Issues and legend goldens (this commit).

---

## 2026-10-15 — a Numbers and scoring page, shown with numbers_scoring_page, released as 1.7.0 ([#55](https://github.com/yveshanoulle/forsgren/issues/55))

Yves (2026-10-05, while building #47): the scores and the numbers have two pages; a further view shows both. His ruling (2026-10-14): a configuration key switches it on, false by default, its own minor release. A new optional key, `numbers_scoring_page`, adds `/numbers-scoring/`: each metric's number, " · ", its DORA Quick Check score (`12 · 6`, `7% · 9.3`, `2 h 7 min · 8`), a single `-` without data and `0 · -` for a project that never deployed successfully, and the Overall Performance column; the cells follow `dora_days`. `view:` does not name it, so the root never shows it. Steps, each its own FBP: 1 config reads the key, the settings page lists it as its tenth row (334b4e5); 2 an unaccepted value falls back to false (f7e8403); 3 the page and its cells (05e1fdd); 4 no-data cells (8b6516d); 5 the cells follow the DORA window (5f128ae); 6 the menu entry "Numbers and scoring" after Scoring (a9faa18); 7 a hidden page is not written and a stale one is removed with its emptied folder (b6df3c6); 8 render shows it only when the key is true, and a render without a config keeps it (d39b444); 9 the starter writes `numbers_scoring_page: false` (1e0b4db); 10 the legend explains it (d4680cf); 11 agent-installer.md asks question 12 and proves ten rows (d0ce0a4); 12 a refactor (one folder-page list for pages and menu, one scored table branch) with one rule fix: removing the emptied folder now fails on any error but "not empty"; the docs, an agent-upgrade.md pin, CodeScene back to 10.0 (this commit). Decisions: #187.

What an installation sees: nothing until `numbers_scoring_page: true`; then the page and its menu entry. No new permission or secret.

---

## 2026-10-15 — a 0 in the Open bugs cell is green, released as 1.7.1 ([#151](https://github.com/yveshanoulle/forsgren/issues/151))

Yves: when the open bugs are at 0, that zero can be green too (`0 ▼ −1`). The count in the Open bugs cell now carries `bugs-zero`, the green of the falling arrow (`#1b6e2f` light, `#7fd98f` dark, no new colour), whenever it is 0, whatever the arrow; unchanged, the 0 is green and the dash stays blue (#152). The Open column and the "— (incomplete)" cell (#140) are unchanged. The legend adds "where a count of 0 open bugs is green too". One step: the cell, the legend, the contrast test and the Days, Issues and legend goldens (this commit). Decisions: #188.

---

## 2026-10-15 — the settings page's Default column shows the default value, released as 1.7.2 ([#169](https://github.com/yveshanoulle/forsgren/issues/169))

Yves: the Default column (True/False) is confusing; better show the actual default setting. The column now shows each key's default (`standard`, `false`, `major`, `365`, `100`, `8`, `30`, `true`, `false`, `false`). The signal it carried (#141: does the file set this key, or does the default apply?) moves into the Current value cell: a key the file leaves out reads `<value> (not set)`; a key the file sets shows its bare value, even when equal to the default. A rejected row (#183) keeps its sentence. Steps, each its own FBP: 1 a setting carries its default (e5861e8); 2 the Default column shows it (1002c7a); 3 `(not set)` for a key the file does not set (b3b3d65); 4 the legend, configuration.md, pages-and-views.md, CLAUDE.md, agent-installer.md step 12 and agent-upgrade.md steps 2 and 9 read the new columns; step 2 explains both readings, since it reads an installation's page from before the update (this commit). Decisions: #189.

What an installation sees: on the settings page, real defaults in the last column and `(not set)` beside each key the file leaves out. Nothing to do.

---

## 2026-10-15 — the render tests pin SOURCE_DATE_EPOCH themselves ([#163](https://github.com/yveshanoulle/forsgren/issues/163))

Found during #153: with `SOURCE_DATE_EPOCH` exported in the shell, 20 render tests in cmd/forsgren failed, because `renderTime()` (render.go) rightly prefers that variable over the injectable clock (the reproducible-builds contract) and the test helper only replaced the clock. A new test helper, `pinClock`, pins both the clock and the variable (`t.Setenv` to empty); `pinNow` and the three tests that set the clock by hand use it. Red: `TestPinnedClockIgnoresSourceDateEpochInTheEnvironment` sets the variable and expects the pinned footer. `SOURCE_DATE_EPOCH=1 go test ./...` now passes. The production behaviour is unchanged. Tests only, no release (this commit).

---

## 2026-10-15 — a gate for relative links and anchors in the Markdown files ([#147](https://github.com/yveshanoulle/forsgren/issues/147))

Found planning #130: `check_repo_links.sh` walks only the generated site, so a relative link in README.md, docs/*.md, CLAUDE.md or the agent files that points at a moved file broke silently. A new PRE gate, `Scripts/check_markdown_links.sh`, reads every tracked `*.md` (SHIPPED.md included) and requires each relative link (inline, reference, angle target) to resolve to a tracked file or directory, case-sensitive, inside the repository; web and mail links, fenced code, code spans and HTML comments are skipped. Every `#anchor`, to another file or the same one, must name an ATX heading by GitHub's slug rules (repeats get `-1`, `-2`); setext headings and HTML ids are not seen and say so. Steps: 1 the gate and its fixtures (bf895e1), which went RED because a gate no order-file row names is refused; 2 the order-file rows (PRE, so CI runs it too), the docs, and the one real finding, an example `[#7](link)` in configuration.md put in a code span (a74c54a); 3 anchors (this commit). Today: 138 relative links, 78 with an anchor, all resolve. No suppressions. Tooling only, no release.

---

## 2026-10-15 — npm: lockfile sync, reinstall on a lockfile change, and a Node pin ([#2](https://github.com/yveshanoulle/forsgren/issues/2))

Found while porting npm in forsgren#1: nothing checked that package-lock.json matches package.json, sfl ran `npm ci` only when two tools were missing (so a lockfile bump kept the old node_modules), and Node followed whatever Homebrew had. Steps, each its own FBP: 1 an offline PRE gate, `check_npm_lock_sync.sh`, compares package.json's dependencies with the lockfile's root entry and names the fix `npm install --package-lock-only` (f528a2b); 2 sfl runs `npm_sync_install.sh`, which runs `npm ci` when node_modules or its stamp is missing or the stamp no longer matches (ddee666); 3 `.nvmrc` pins the Node major (26, all Homebrew can pin), `check_node_pin.sh` fails with the exact `brew` fix when the running major differs, sfl runs it after the tool install, and the stamp holds the lockfile hash plus the Node major (2e7b13b); 4 CI sets Node up from `.nvmrc` (`actions/setup-node`, SHA-pinned, its cache off) before the tool install, a workflow test requires it, `jq` is listed as a required tool, and the docs (quality-gates.md, development.md, ci.md, CLAUDE.md) (this commit). No suppressions. Tooling only, no release. Decisions: #190. The port to the three websites that share these scripts is filed per repository.

---

## 2026-10-15 — DCO checked on every push, private-names fixes, the full usage text, the no-projects link, released as 1.7.3 ([#81](https://github.com/yveshanoulle/forsgren/issues/81), [#54](https://github.com/yveshanoulle/forsgren/issues/54), [#180](https://github.com/yveshanoulle/forsgren/issues/180), [#172](https://github.com/yveshanoulle/forsgren/issues/172))

Yves grouped the small work into one patch release (#111 and #77 turned out to be done already and were closed), with one refactor at the end. Decisions: #191.

- **#81, every check runs in CI.** dco.yml also runs on every push to main and checks only the pushed range (`Scripts/dco_push_commits.sh before after`): a new branch is checked on its head commit, an empty range is red, and no commit of a push is exempt. A missing `FORSGREN_PRIVATE_NAMES` secret in Actions stays exit 2 and now names the secret and says a fork's pull request gets none; it never prints a value. Steps: e84168b, 5e294b5, 9e187d2 (the first real run: "✅ DCO: 1 commit(s), every one signed off by its author"), 8149508.
- **#54, private-names follow-ups.** FBP hands the commit message to the gate on stdin, never in a file an interrupt could leave behind (6628471); an empty `FORSGREN_PRIVATE_NAMES_FILE` counts as unset in the helper as in the gate (f1dbde4); the refused-message and tier-stripping tests assert their own reason (36f0cd4); FBP never prints an unrecognised option back (a4b09e9).
- **#180, the printed usage** names every command and every flag; a test compares each command's flag set with its usage block (9fc1ab8). `check-update` and `install-update` were missing entirely.
- **#172, the no-projects page** links https://forsgren.be/#configuration instead of a github.com docs path the repository-links gate refuses; a test runs that gate on a site rendered with no projects (7da2f8d).
- **One refactor and the docs** (this commit): the FBP test's sandbox proof counts its own `run_fbp` calls instead of a hand-written number; the three tier-stripping proofs share one helper; docs/ci.md, CONTRIBUTING.md, docs/quality-gates.md, docs/configuration.md (the full usage), docs/pages-and-views.md, docs/development.md, agent-installer.md and CLAUDE.md.

- **#193, the docs' usage copy is held to the code**: a test requires docs/configuration.md's usage block to equal what main.go prints, byte for byte, and names the first differing line (the next commit).

What an installation sees: the complete usage text and the forsgren.be link on a page without projects. Everything else is forsgren's own checks.

---

## 2026-10-15 — the History page and a clearer run summary, released as 1.8.0 ([#68](https://github.com/yveshanoulle/forsgren/issues/68), [#194](https://github.com/yveshanoulle/forsgren/issues/194), [#196](https://github.com/yveshanoulle/forsgren/issues/196))

Yves grouped both into one minor release, with one refactor and the docs at the end. Decisions: #192 (the History page, Yves's rulings: calendar half-years plus the last 6 months, banded as 180 days, one table with a row group per measure), #195 (the Update line when dependabot.yml has no cooldown key: open).

- **#68, the History page** (`history.html`, last in the menu): the five metrics and Overall Performance per calendar half-year (January to June, July to December, UTC) and for the last 6 months, each cell `number · score`, plus a small inline-SVG Trend chart per row on the 0–10 score, in `currentcolor`, a gap where a period has no data. A period before what collect has read (`data/reach.csv`, now read by render; a bad reach.csv fails render) is a dash, never a zero; a column no row has data for is dropped; without history the page says why in one line. Every period is banded as 180 days at the configured working day; counts are not rescaled. New key `history_page`, default `true` (a page that appears on update), `false` hides the page and its menu entry; the settings page has eleven rows; the starter writes the key; agent-installer.md asks question 13; the legend explains the page and its limits (old change fail rate). Steps 1–19: a2dfe1c … 510215b.
- **#194, the run summary**: a first line `- Run: YYYY-MM-DD HH:MM UTC` (81f2a07); the Token line tells the run's own token (`ghs_`, renewed every run), a token without an expiry date, a date GitHub sent that forsgren cannot read, and a collect that could not ask apart, through a one-line value collect writes to the token-expiry file (4f84a57, 81e44d7); the Update line names the Dependabot cooldown, `waiting for the 3-day cooldown until <date>`, from the installation's `.github/dependabot.yml` (`default-days`) and the release's publish time, which `latest-release --published` writes and `run-summary --latest-published` reads (5cf6f15). Steps 20–23.
- **One refactor and the docs** (step 24, this commit): the token-expiry file has one shape, its writer and readers in `expiryfile.go`; the run summary is built as a list of lines, one `token()` reading the file once; `Row.overall()` and `metrics.Row.HasData` are shared by the scored table and the History page; the chart geometry lives in one place; `issuePages` became `rootPages`; `coverage_thresholds.json` parses again (a missing comma). Docs: configuration.md (`history_page`, eleven rows, every run summary line, `latest-release --published`), pages-and-views.md (the History page section, ten pages), data-files.md (reach.csv read by render, the token-expiry words), ci.md, updating-and-releases.md ("Upgrading to 1.8.0"), README.md and CLAUDE.md.
- **#196, a reach row for every read repository** (24701c6): a repository with stored history but no row in `data/reach.csv`, whose history already reaches `history_days`, never got a row, so the History page would have shown it unread forever; collect now notes its oldest stored deployment as its reach, and render matches reach rows ignoring case. Found by the refactor step; the installation checked was not in that state (a row for each of its 8 repositories).
- **The bump to 1.8.0** (this commit): main.go, the docs, the tests and the 29 goldens that name the version.

What an installation sees: a History page after the update (switch it off with `history_page: false`), filling in over the next daily runs, and a run summary that says when it ran, what kind of token it has and why an available update waits. No new permission or secret.

---

## 2026-10-15 — the legend shows the score of each level, and the History page is off by default, released as 1.8.1 ([#79](https://github.com/yveshanoulle/forsgren/issues/79), [#199](https://github.com/yveshanoulle/forsgren/issues/199))

Decisions: #197 (a percent level shows its score range).

- **#79, the score of each level.** The legend shows next to each level the score the scoring view gives it. These scores come from `metrics.BandScore` through `scoreCell`, the scoring view's own helper: lead time (1ad051b) and deployment frequency (f8ea659). Change fail rate is scored per whole percent, so each of its levels shows its range from `ChangeFailBand.Percents` and `PercentScore`, for example `20%: 10% to below 30%, score 9 to 7.1` (dcef25d). Recovery time gets its own list on lead time's levels (db34094). Rework rate gets its own list on change fail's ranges (9378ae3). The two lists are worded for their metric, because a shared define put two identical lists on the page and the golden duplication gate refused them. The Scores section points at the level scores (71481be). The other half of #79, every possible value next to the chosen one, was already done by the settings page (#84, #141, #169).
- **#199, the History page off by default.** Yves, after seeing an installation's History page with one period and a one-dot trend: "lets turn of history on fosgren metrics and turn it of by default, tilll we get this better" (#198). `history_page` now defaults to `false`, so a hidden page is not written and a stale one is removed (40a8bf0). The starter and agent-installer.md question 13 follow (acffff6).
- **One refactor and the docs** (this commit):
  - `legendscores.go` is one generic `levelScores` with `bandScore` and `percentRange`.
  - `Percents` reads its band starts without branches.
  - `init_test.go` (9.16) and `pages_test.go` (8.95) are back at CodeScene 10.0.
  - Docs: configuration.md, pages-and-views.md, updating-and-releases.md ("Upgrading to 1.8.1"), README.md and CLAUDE.md.

What an installation sees: the History page is gone after the update unless the config sets `history_page: true`, and the legend's levels carry their scores. No new permission, secret or key.

---

## 2026-10-16 — a page can be generated without a menu entry, and the History page explains itself, released as 1.8.2 ([#200](https://github.com/yveshanoulle/forsgren/issues/200), [#198](https://github.com/yveshanoulle/forsgren/issues/198))

Yves, on the History page of 1.8.0: "only 1 period / the trend shows nothing / all in all, I don't understand the screen" (#198). Then: "for pages there should be two settings: generate, menu so we can generate a page and not add it to the menu, so I (and others) can easily test it, without that customers can see it" (#200), option A (one key, three values), "also create history, numbers_scoring_page as unlisted by default". The release was first planned with #112 and #42 too; Yves split it so #198 closes the next day ("ok do that new plan"); those two follow as 1.8.3.

- **#200, three values per page key.** `issues_page`, `days_page`, `numbers_scoring_page` and `history_page` take `true` (generated and in the menu), `unlisted` (generated, no menu entry, `<meta name="robots" content="noindex">`) or `false` (not generated, a stale file removed). The steps:
  - the `PageMode` type and `pageKey` (97d3ec9);
  - the message "use true, unlisted or false" for a value not accepted (daa9141);
  - History and Numbers and scoring default to `unlisted` (0c04ec2);
  - the settings page lists the three values (18c720f);
  - `config.Accepted`, so no accepted value can be missing from the settings page, which closes a gap left by #79 (793c6ff);
  - an unlisted root page leaves every menu, including its own (459b5bd), and carries `noindex` (cc931b3); the folder page gets the same (1089dd9);
  - render wires the three modes (0508b9a);
  - the legend (0bf0478);
  - the starter and agent-installer.md questions 10, 12 and 13 (7a1693f);
  - Yves's acceptance checks pinned, each proven by a mutation: every switch of a key in a reused site, and no link to an unlisted page outside the menu (ebc60d0).
- **#198, the History page explains itself.**
  - "History (beta)" in the title and heading; one constant removes it later (2da314a).
  - A line under the heading says how to read the page (0cc31d5).
  - With only the last 6 months, the page says why, with the first deployment and the day the first half-year appears, or how far to raise `history_days` (75fed4e).
  - No Trend column below two periods (2b2afdb).
- **One refactor and the docs** (this commit): the page keys live in `pagemode.go`, the menu and unlisted helpers in `menu.go` (page.go 584 → 512 lines), the History notice in `historynotice.go`, `pageModes` is the one map from page to mode, each page default is written once; `internal/metrics/history_test.go` 9.09 → 10.0. Docs: configuration.md (one page-keys entry, "discoverable, not private"), pages-and-views.md (Unlisted pages, the History page), updating-and-releases.md ("Upgrading to 1.8.2"), README.md and CLAUDE.md.

What an installation sees after the update: without page keys, the History page and the Numbers and scoring page are generated but not in the menu, at `history.html` and `numbers-scoring/`. Anyone with the address can open them, so they are discoverable, not private. No new permission or secret.

---

## 2026-10-16 — the waiting update found by what it changes, and the legend explains the issue columns, released as 1.8.3 ([#42](https://github.com/yveshanoulle/forsgren/issues/42), [#112](https://github.com/yveshanoulle/forsgren/issues/112))

These two were planned with #200 and #198 as one patch. Yves split them off so #198 could close a day earlier ("ok do that new plan"), and on #112 he said "keep doing 112".

- **#112, the issue columns in the legend** (4663458). The legend now says what New, Completed, Not planned, Duplicate and Other count, and that a reopen counts in none of them. It names two limits: a reopen is dated when the collection sees it, and a repository past the full-read cap (100 pages) has an incomplete back history. The footer links #112 asked for had already come with #128.
- **#42, the waiting pull request by its contents.**
  - `update.MovesPinTo` tells whether a patch moves the `metrics.yml` pin to a version (6d63bd3).
  - `waiting-pull-request` reads the files of the open `dependabot[bot]` pull requests and takes the highest one that moves the pin, so a grouped branch such as `dependabot/github_actions/group-abc123` is found (fd8af72).
  - The matching rules are pinned, each proven by a mutation: another author, another version, another file, a person's pull request on a Dependabot-like branch, and the highest of several (34d755c).
  - A failed files read gives `no-access`, `rate-limited` or `failed`, and a file list too long to read is no match (3346bf0).
  - The branch-name heuristic, `ForsgrenBump`, is gone (369df6b).
  - check-update's 403 on reading the pull request itself names `pull-requests: read` too, found by the refactor step: the author read came before the files read and gave the plain 403 (this release's step 8).
- **One refactor and the docs** (this commit): `pullFiles` is the one way check-update and the waiting lookup read a pull request's files (a cut list is `errFilesCut`), `pullLookup.movesPin` checks one candidate, `MovesPinTo` reads as one predicate, `explainDenied` names the missing permission, and two test fakes share `serveAPI`. Docs: configuration.md (the pull request found by its files), ci.md, updating-and-releases.md ("Upgrading to 1.8.3"), pages-and-views.md and CLAUDE.md.

What an installation sees: "is waiting in pull request #N" where it used to say "is available" when Dependabot grouped or renamed its branch, and the legend's issue columns explained. No new permission, secret or key.

---

## 2026-10-16 — issue lead time, the installation README follows the installed version, and five smaller changes, released as 1.9.0 ([#202](https://github.com/yveshanoulle/forsgren/issues/202), [#203](https://github.com/yveshanoulle/forsgren/issues/203), [#201](https://github.com/yveshanoulle/forsgren/issues/201), [#195](https://github.com/yveshanoulle/forsgren/issues/195), [#87](https://github.com/yveshanoulle/forsgren/issues/87), [#204](https://github.com/yveshanoulle/forsgren/issues/204), [#110](https://github.com/yveshanoulle/forsgren/issues/110))

Yves: "202, 201, 203, 195, 110,87 can go togther as 1.9.0". #204 was found during the release and went in too. One refactor and the docs come at the end.

- **#202, lead time of issues** (Yves: "yes bugs lead times next to it", "good to all of it").
  - The median time from creation to the Completed close, per row's period. Only Completed closes count, and a close without a created event is skipped (cfd87b5, a533d48, accc30d).
  - Every row kind carries it, and so does the bugs version (4f87381, 42a3336).
  - The cell is a short duration or a dash (3d44a8c). The Lead time column comes after Completed (20666ce).
  - Bugs lead time has its own "— (incomplete)" wording, so a screen reader names the right column (87542b1).
  - The legend explains both (62461e4).
- **#203, a cut pull-request list** (Yves's four behaviours on the issue). A cut list with no match is `truncated`, never "available" (c2f0781). The run summary (e17955a) and the footer (51fa6b1) say "unknown (pull request list truncated)", and the workflow passes the check to render (fa1475b).
  - A GNU-only `sed` made an older mutation proof vacuous on macOS. It now bites on both (d58bcdc).
- **#201, forsgren.be's description.**
  - It comes from the README's first paragraph (0641e21).
  - A paragraph over 160 characters is cut at a word with "…" (47c50ab).
  - A README with no paragraph fails the starter page (619bc64).
- **#195, no cooldown key means 3 days.** Yves: "no key = 3 days, the documented default". `default-days: 0` stays 0 (c73eb5c).
- **#87, govulncheck daily.** `FORSGREN_VULN_DB_REQUIRED=1` makes an unreachable vulnerability database red (e030738). `vulncheck.yml` runs the push gate's script every day (be0d02d).
  - That step's new pin script broke shellcheck on CI. The local FBP missed it because the gate scanned tracked files only. The fix rode in b156515, and the class became #204.
- **#204, the file gates scan new files too.** Shellcheck, yamllint, markdown links, guardrail packages and the data guard list their files through `Scripts/lib_repo_files.sh`: tracked plus untracked files that are not ignored (006e3a1).
- **#110, the installation README.**
  - `forsgren install-readme` writes the README of this version from `install/README.md`, embedded in the binary. It creates, replaces or leaves the file untouched (b156515, 2b51ddb). The text is pinned (4c53603).
  - The daily run writes it and commits it alone, as the bot, only when it changed (405e3b1). A tag ref or a moved branch is named, never forced or rebased (d056329).
  - The run summary says what happened, and the run passes that on (d9a4d96, 6abf6f5). A whole-job pin covers it (9cbc113).
- **One refactor and the docs** (this commit):
  - A shared `rowIndex`, and issue keys through `history.IssueKey`.
  - The incomplete cell's subject comes through a template function, not a string branch. `PRListCut` is a bool, so "truncated" lives in Go only.
  - The README words are keyed by the install package's outcomes.
  - Docs: configuration.md, pages-and-views.md, ci.md, quality-gates.md, development.md, data-files.md, updating-and-releases.md ("Upgrading to 1.9.0"), README.md, install/README.md and CLAUDE.md.
- **Found by the refactor step, fixed before the release:**
  - **#203 never reached a real run** (f8e3284). The waiting step in metrics.yml turned `truncated` into `failed`. It now passes `truncated` on, and a pin follows it from the waiting step through render to the summary.
  - **A failed README step stopped the whole day's run** (25110ed). It now records `readme=failed` and the run goes on. A last step fails the job, and the summary says "README: not pushed: see the README step". A failed push undoes the README commit, so the data push carries `data/` alone.
  - **The data guard could not find its helper when run from inside `Scripts/`** (07c38cf).
  - **The package gate missed a `node_modules` symlink, and `.gitignore` did not ignore one** (this commit).

What an installation sees after the update: a README written and committed by the daily run (a hand-edited one is replaced), the 3-day cooldown when dependabot.yml sets none, Lead time and Bugs lead time on the Issues and Daily pages, and "unknown (pull request list truncated)" where a cut list cannot rule out a waiting pull request. No new permission or secret.

---

## 2026-10-16 — every page carries a meta description, and HTMLHint checks 30 rules, released as 1.9.1 ([#208](https://github.com/yveshanoulle/forsgren/issues/208), [#206](https://github.com/yveshanoulle/forsgren/issues/206), [#207](https://github.com/yveshanoulle/forsgren/issues/207))

These came out of the accessibility-gate research (#138, now #205). Yves asked whether htmlhint's charset rule was on: "is that turned on already ? if not can we turn it on already now for all websites ?" Then: "can we investigate htmlhint rules that we can still turn on for all the sites we hav enow ?" On the description texts: "all these sentences have to end with generated by Forsgren". forsgren has no title key, so T was always "forsgren", and on the title in the texts he said: "drop it".

- **#206, meta-charset-require** (20d697c). A page with no `<meta charset>` is red.
- **#207, the shared rule set** (15a554b).
  - `.htmlhintrc` grows from 5 rules to 29: the 28 rules the estate's public sites share, all at 0 violations when measured, plus inline-style-disabled.
  - `Scripts/test_gate_htmlhint.sh` gives each rule a page that breaks only that rule, and a mutation that turns the rule off. tagname-specialchars always trips tag-pair as well, and the test says why.
- **#208, a meta description on every page.**
  - One fixed sentence per page, ending " generated by Forsgren", with meta-description-require as rule 30 (a8177e0).
  - The test pages of two self-tests, the coverage entry and the test's line length, after the first FBP was red (a5c4d3c).
  - The sentences no longer name the title (4d500f3).
- **One refactor and the docs** (this commit):
  - page-name constants as the map keys;
  - one placeholder value in the test;
  - `RC_RULES` in the htmlhint self-test.
  - Docs: pages-and-views.md (the table of sentences), quality-gates.md (the 30 rules), updating-and-releases.md ("Upgrading to 1.9.1") and CLAUDE.md.

What an installation sees after the update: each page has a `<meta name="description">`, for example "The DORA numbers per project, without scores generated by Forsgren". It names no project, repository, number, date or title. No new permission, secret or config key.

---

## 2026-10-17 — the quality gates move to the shared canon, FBP gets `--no-push` and fix mode, and the Go-tool gates share one helper, released as 1.9.2 ([#209](https://github.com/yveshanoulle/forsgren/issues/209), [#210](https://github.com/yveshanoulle/forsgren/issues/210), [#214](https://github.com/yveshanoulle/forsgren/issues/214), [#215](https://github.com/yveshanoulle/forsgren/issues/215), [#216](https://github.com/yveshanoulle/forsgren/issues/216))

Nothing a user of forsgren sees changes: these are local build and quality-gate changes only, shipped as the patch release 1.9.2 (also #209, the braces exception re-check, and #210, govulncheck and the other Go-tool gates on a cold runner).

- **#214, local build.**
  - `FBP.sh --no-push` builds, checks and commits but does not push, for changes that only touch FBP.sh, sfl.sh, local-only scripts or their self-tests. Its self-test builds generic stubs for every helper script FBP.sh calls.
  - Fix mode only locally: sfl.sh exports `GATE_FIX=1`, and a gate that can repair what it finds (the npm audit heal, the Stylelint source fix) does so only when it is set. CI never sets it, so CI only checks.
- **#215, quality gates at the shared canon versions.**
  - The site settings file accepts a leading-dot directory such as `.build/site`; lint coverage and HTML duplication read their target from it.
  - Stylelint: CI only checks; FBP fixes the source CSS before the build, never the generated copy, proven by a test.
  - HTMLHint from 30 to 32 rules; CI runs the gates in a loop over the order file per phase, with the shared step-table renderer.
  - Data-file gates with empty exception files (stray tracked files, privacy posture, workflow triggers, the required-pages trio), markdown links, script references, the exit-trap gate and its behaviour engine, actionlint, zizmor with `--color never`, and canon version lines on the shared scripts.
  - The `MIN_GATES` ratchet: the number of gates only goes up. Its last fix (this issue) made the private-names self-tests own the extra-list variables, so the extra secret that CI passes no longer leaks into their cases.
- **#216, one helper for the four Go-tool gates** (this commit).
  - `Scripts/lib_go_tool.sh` (sourced, never run) resolves the tool from `go tool -n` on stdout only, requires an executable file, and returns the tool's own exit code. `check_govulncheck.sh`, `check_deadcode.sh`, `check_go_lint.sh` and `check_test_dupl.sh` use it and keep their messages, exit codes and skip rules; before and after output of each gate on the repository is identical. The tool versions stay in the `go.mod` tool directives, unchanged.
  - Red first: `Scripts/test_lib_go_tool.sh` (a stub `go` writing download lines on stderr; a failing `go tool -n`; a path that is not an executable file; the tool's exit code), with a mutation each for a helper that captures stderr into the path, one that swallows the exit code and one that skips the executable check.
  - Each of the four gate self-tests has a case where the tool itself exits non-zero and the gate must be red, never an OK, and a mutation proof that the case turns green when the exit code is swallowed.
  - `MIN_GATES` 115 to 116 (the helper self-test is one order-file row), and the gate-wiring test requires the four gates to source the helper.
  - New: [docs/gate-classification.md](docs/gate-classification.md), each gate required, n/a or a documented exception.
  - No Go code is touched, so there is no CodeScene review.

---

## 2026-10-17 — every page shows a small forsgren icon in the browser tab and bookmarks, released as 1.9.3 ([#218](https://github.com/yveshanoulle/forsgren/issues/218))

What an installation sees after the update: every page, the root, the three views and the Numbers and scoring page included, links a small SVG icon, so the browser tab and bookmarks show a forsgren icon instead of the browser's default. The icon is written as `favicon.svg` next to `styles.css`, and each page links it by its relative path, so it works from the site root and from a folder one level down. The starter page the README links to carries it too. Released as the patch release 1.9.3.

- **#218, favicon.**
  - `internal/page/favicon.svg` is embedded and written beside the stylesheet with the embedded bytes; the layout header links `<link rel="icon" href="favicon.svg" type="image/svg+xml">`, with `../` in front one folder down.
  - Red first: `internal/page/favicon_test.go` (the file is written with the embedded bytes; every page links it by its relative path), and the golden pages of every view.
  - The site build and the starter-link check follow the extra file.
  - Release 1.9.3: `version` in `cmd/forsgren/main.go`, the pinned version in the tests, goldens and docs, the newer-release examples at 1.9.4. No new permission, secret or config key.

---

## 2026-10-17 — the browser gate, the estate's shared canon version ([#205](https://github.com/yveshanoulle/forsgren/issues/205), 1/2)

Tooling only: no release.

- **#205 (1/2), the browser gate.**
  - `Scripts/gate_browser.sh`, `Scripts/browser_gate.mjs` and `Scripts/test_gate_browser.sh` are the estate's canon v2, byte-identical (`# canon:` lines). After the build, every page of the required-pages manifest is opened from `.build/site` on 127.0.0.1 in Chrome with puppeteer-core 25.14.0 and axe-core 4.14.0 (exact devDependencies, lockfile), once per variant: axe serious and critical, doctype, charset, console and page errors, failed requests, CLS exactly 0 (the largest of five cold loads).
  - Chrome has a fresh temporary profile, the sandbox on, a scrubbed environment and a loopback-only resolver.
  - `Scripts/browser_gate_variants.txt` has one row, `light|scheme:light`. `Scripts/browser_gate_baseline.txt` and `Scripts/browser_gate_exceptions.txt` have no rows: forsgren has no findings and no external embed.
  - Red first: the self-test run before the engine existed.
  - `MIN_GATES` 116 to 118 (self-test in pre, gate in post). No new workflow, trigger, secret or permission.

---

## 2026-10-17 — the live check after every forsgren.be deploy ([#205](https://github.com/yveshanoulle/forsgren/issues/205), 2/2)

Tooling only: no release.

- **#205 (2/2), the live check.**
  - `Scripts/live_check.sh <https-base-url>` checks the deployed site with curl and no browser: `http://` answers 301 or 308 with exactly `https://<host>/` as Location; `https://` answers 200 as `text/html` with the certificate validated (never `-k` or `--insecure`, `--disable` first so a curlrc cannot add it) and links a stylesheet; the stylesheet the page actually links, resolved against the base, answers 200 as `text/css`.
  - Every failed check is a `❌ FAIL: live check: <check>: <observed value>` line and exit 1. Success is one `OK:` line with the status codes, content types and the number of tries. The set is tried up to 5 times, 10 s apart (`LIVE_CHECK_TRIES`, `LIVE_CHECK_DELAY`), so a deploy that is still propagating is not a false red.
  - `.github/workflows/starter_page.yml` has a third job, `live-check`: `needs: deploy`, only when the deploy step really published (a release run that skipped the deploy skips it), `contents: read`, `Scripts/live_check.sh https://forsgren.be`. A red check cannot undo the deploy; it makes the job red.
  - Red first: `Scripts/test_live_check.sh` run before the script existed. It uses a stub curl, no network, and covers each check passing and failing by name, the href forms, the bounded retry, the usage errors, and four mutants (no redirect check, no Location assertion, `--insecure`, no stylesheet check). `Scripts/test_starter_page_workflow.sh` pins the new job, with eight mutants.
  - `MIN_GATES` 118 to 119 (the self-test in pre). The live check itself is not a local gate: it needs the deployed site. No new secret; the job adds no permission.

---

## 2026-10-17 — a Release workflow releases patch, minor or major in one run ([#221](https://github.com/yveshanoulle/forsgren/issues/221), 1/2 and 2/2)

Tooling only: no release.

- **#221 (1/2), the building blocks.**
  - `Scripts/release_plan.sh` computes the bump the labels of the closed issues require and the release notes; `Scripts/release_bump.sh` makes the version bump of the manual bump commits, goldens included, and run on the tree before the 1.9.3 bump it reproduces that commit byte for byte.
  - Red first: both self-tests before the scripts existed; mutation proofs for a lower bump accepted, nothing closed accepted and a missed golden page.
- **#221 (2/2), the workflow.**
  - `.github/workflows/release.yml`: `workflow_dispatch` with `bump` (patch, minor, major; default patch), permissions `contents: write`, `actions: write`, `issues: read`. The steps: Quality green on main, the plan, the new version, the bump and `go test`, the DCO-signed bump commit as github-actions[bot] pushed to main, Quality dispatched on it and awaited (bounded), one `gh release create --target <bump commit> --latest`, forsgren-template's pins and README in one git-data commit, a pin pull request in forsgren-metrics, and a last step that says what was done.
  - Decisions on the issue: an issue without a patch, minor or major label stops the plan and is named; an issue an earlier release's notes already name is never listed again.
  - Scripts, each with a self-test and mutation proofs: `release_quality.sh`, `release_commit.sh` (a throwaway repository with a bare origin), `release_publish.sh`, `release_pins.sh` (a stub of the git-data API over the real template files), `release_report.sh`; `Scripts/test_release_workflow.sh` pins the workflow with 39 mutants.
  - The new secret `FORSGREN_RELEASE_TOKEN` (fine-grained: contents write on forsgren-template, contents and pull-requests write on forsgren-metrics, expiry under one year) is checked first thing and again by the two steps that use it.
  - `MIN_GATES` 123 to 131.
- **#221 (3/3), the report names the step that failed.**
  - The first real Release run stopped correctly at the token check, but the report said it ended at the quality step: it named the first step with no line in the log, and the token check recorded nothing. The token check and the test of the bumped tree now record themselves, and the report step gets `steps.<id>.outcome` of every step and names the one that failed, never inferring it from the log; with no outcomes it says the step is unknown.
  - Red first: `Scripts/test_release_report.sh` reproduced the report naming `quality`; a mutation proof (the old log inference) shows a failed token check reported as quality, and `Scripts/test_release_workflow.sh` pins the ids, the outcomes and the two log lines. No new gate, permission or secret.
- **#221 (3/3), a failed token first run: resume and the Workflows permission.**
  - The second real run released the new version, then the template step failed with HTTP 403: a fine-grained token needs Workflows: Read and write to change files under `.github/workflows`, and the token spec lacked it (both repositories need it, the metrics pin pull request changes workflow files too). The docs and the secret's error line now list Contents, Pull requests and Workflows, and `release_pins.sh` names the permission on a 403 (red first, with a stubbed 403).
  - New input `resume: pins` (default `none`): `Scripts/release_resume.sh` finds the latest published release and checks its tag is at the commit it was made for; the run then skips the plan, bump, commit, Quality and publish and does only the template and metrics steps. Both are idempotent (a repository already on the pin, or a pull request already open or merged, is "already done"; a pull request closed without merging is named in a note and a new one is opened, the release branch reused or moved; of several pull requests for the branch any open or merged one is done). The report of a resumed run expects only its own steps.
  - Red first for all of it; mutation proofs: a resume that republishes (the publish step loses its skip), a template step that fails on an already-moved pin, a resume that accepts a tag at another commit or a draft. `MIN_GATES` 131 to 132.
  - A closed pull request no longer blocks the pin step: of all the pull requests for the release branch, any open or merged one is "already done"; one closed without merging is named in a note and a new one is opened, the release branch reused when it already holds the pins or moved when it does not.
  - A failed run says what to do next, per stage, in the job summary and one `::notice::`: before anything was pushed, start Release again with the same bump (with the cause where it is known); the bump commit on main with no release, `resume: publish` (a plain rerun cannot work: the version in `main.go` is already the new one and the bump step refuses it; the new mode takes the version from `main.go`, runs Quality on main's head, publishes and does the pins); released with a pin step failed, `resume: pins`. Never a step by hand.
- **#221 (4/4), the token's expiry on every run page, and a strict `resume: publish`.**
  - `Scripts/release_token_expiry.sh` reads the expiry of `FORSGREN_RELEASE_TOKEN` from GitHub's `github-authentication-token-expiration` header on one authenticated call on forsgren-template, and puts one line first in the job summary of every run: more than 30 days left, a green line with the date and the days; 30 to 8 days, a yellow line and a `::warning::`; 7 days or fewer, a red line and an `::error::` with the run going on; expired, no header (a token without an expiry is said so and not accepted), an unreadable date, a refused call or no token, a failed line that stops the run before anything is pushed. The clock is injected in the self-test (`RELEASE_NOW`); mutation proofs move each tier edge (30/31, 7/8) and take a missing header for fine.
  - `resume: publish` now publishes only when main's head is the bump commit: if main has moved past it, the run refuses, naming both commits, with the advice to fix main and run a new release instead (a release is made only at its bump commit). A mutation proof shows a moved head being published without the check. `MIN_GATES` 132 to 133.
- **#221 (5/5), the release is done only when the metrics site runs it.**
  - The 1.9.4 resume run moved the template and opened forsgren-metrics#19 by itself, but #19 waited for a hand (the metrics repository's auto-merge takes only Dependabot pull requests) and its merge started nothing (`forsgren.yml` runs on a schedule or by hand). The Release workflow now finishes it: `Scripts/release_verify_pin.sh` reads the pull request's files (only the two callers' pins, to this release's commit and version, the `check-update` rule for the changed files; anything else is a red and not merged), `Scripts/release_metrics.sh` squash-merges it with its branch deleted, starts `forsgren.yml` in forsgren-metrics on its default branch and waits for the run, at most about 20 minutes. The run page says `metrics: PR #N merged, forsgren run <url> green`; a red or cancelled run fails the step with the URL, and the advice is `resume: pins`, which is safe to repeat (a merged pull request skips to the run, a green run after the merge is already done, no second run next to a green or running one).
  - The metrics pull request now changes the `uses:` lines only, as Dependabot does (the comment lines are left), which is what the check requires. `FORSGREN_RELEASE_TOKEN` also needs Actions: Read and write.
  - Red first for both scripts; mutation proofs: merging a pull request that changes more than the pins, no wait for the run, a red run taken for done, a second run started next to a green one, and for the check another file, another commit and a second changed line. `MIN_GATES` 133 to 135.

