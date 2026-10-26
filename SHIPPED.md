# Shipped — forsgren

History of completed work on forsgren. Append-only.

Conventions:
[CONVENTIONS.md](CONVENTIONS.md).
Active work lives in
[TODO.md](TODO.md).

---

## 2026-10-26 — A corrupt pulls_denied.csv or pushes_denied.csv no longer closes the setup issue's refused-read items ([#395](https://github.com/yveshanoulle/forsgren/issues/395), 1 step)

forsgren issue 395, bug, patch release. `check-needs` used to print a note on stderr and build no refused-read items when `--pulls-denied` or `--pushes-denied` named a file in no known format, so an open setup issue that carried the items closed although the refusal might still stand. A failed operation fails: `refusedNeeds` and `refusedItems` (`cmd/forsgren/deniedneeds.go`) now return the error, naming the read and the file, and `reportNeeds` (via the new `gatherNeeds`) notes it on stderr, writes and closes nothing and returns the status `failed`. A missing file still notes no refusal. `CLAUDE.md` and `docs/updating-and-releases.md` say so.

---

## 2026-10-25 — One function builds every TBD table row, with all its measures ([#422](https://github.com/yveshanoulle/forsgren/issues/422), step 2 of 5)

forsgren issue 422, step 2: decisions #449 (A), #450 (A). The page is not switched to it yet (step 4), so no golden changes.

- `metrics.TbdRows(projects, data, now, groups)` (`internal/metrics/tbdrows.go`): the rows and the order of `Rows` (each project's total, then its label rows by name ignoring case), as `TbdRow{Level, Name, Project, Interval, Lead, Developers, Push, Deploy, Volume, IntervalAbsent, PushAbsent}`, instead of the parallel slices the page pairs by position.
- The total row has every measure over all of its project's data, each commit once at its first deployment of any service. A repository's label row is a project of that one repository with every measure. A service's label row has its own Time to deploy, Deployments, Commits per deployment and Developers, over the deployments of its task and the commits they shipped (`Data.ofTask`); the Mainline Interval and the push and pull request measures (Time to main, PR Lead Time, Commits, Pushes, Commits per push, the four shares) are empty and marked `IntervalAbsent` and `PushAbsent`, for the page to show a dash in step 4.
- Red first, seen failing at runtime against a stub returning no rows: `TestTbdRowsAreTotalsThenLabelsLikeTheDoraTable`, `TestAServiceTbdRowCountsItsOwnDeployments`, `TestTheTotalTbdRowCountsACommitOnceAtItsFirstDeploymentOfAnyService` and `TestARepositoryLabelTbdRowIsAOneRepositoryProject`.
- Coverage: five rows in `coverage_thresholds.json`, 100.0 each. CodeScene: `tbdrows.go` and `tbdrows_test.go` 10.0.

Steps left: 3 no-data and names; 4 page and goldens; 5 fixture with services; 6 docs with the release's docs issue.

Signed: Lenka B

- Lenka B

---

# 2026-10-25 — Scripts/release_check.sh runs the release plan's rules locally before the last FBP of a release ([#445](https://github.com/yveshanoulle/forsgren/issues/445), 1 step)

forsgren issue 445, tools, no release of its own. `Scripts/release_check.sh` runs the Release workflow's own `release_plan.sh` with `auto --all` on the maintainer's machine (no second copy of its rules): a closed issue since the last release tag without `patch`, `minor`, `major` or `tools`, an open non-tools issue named by `#N` in a commit subject, nothing closed and the bump the labels require are findings, and it adds one the plan does not make, a commit on main since the tag whose subject is `*** RED ****` alone, naming the issue its body names. One line per finding and exit 1, else `release check: OK, bump=<kind>`; read-only. `Scripts/test_release_check.sh` (order-file row) uses the plan's seams and six mutation proofs; `docs/updating-and-releases.md` and `CLAUDE.md` say to run it before the last FBP of a release.

---

## 2026-10-25 — The two isolation shards are dealt by the seconds each self-test takes ([#446](https://github.com/yveshanoulle/forsgren/issues/446), step 1 of 1)

forsgren issue 446, tools issue, follow-up of #426, no release of its own. In Quality run 40220840433 the shards took 2 and 7 minutes: index modulo over the sorted list put the slow self-tests together. `Scripts/test_git_sandbox_isolation.sh` (canon v3) now deals them with `shard_assign` (`Scripts/lib_isolation_shard.sh`): greedy by weight, heaviest first, each to the shard that weighs least so far, from `Scripts/git_sandbox_isolation_weights.txt` (seconds of the 13 slowest, measured one run each; a default of 5 for every other, so a new self-test needs no row). Every self-test is still in exactly one shard and the split depends on the list and the file alone, not on the commit. Over the real 33 self-tests the shards weigh 219 and 218 seconds (before: 155 and 282 measured locally); a local Quality-style run took 237 and 228 seconds.

The CI log holds no per-test time (the self-test prints its ok lines at the end), so the weights are local timings of each self-test run alone; the ratio matches the 2 to 7 of the run.

- Red first: `Scripts/test_git_sandbox_isolation_scope.sh` (canon v3) cases 25 to 28 over the real list (the shards within 10 seconds of each other, each self-test once, a new one in exactly one shard, no weight row for a self-test that is gone), case 25 seen failing against the index rule (155 and 282); mutations K (shard test removed), M (weights ignored) and N (all to one shard) seen red.

- Lenka B

---

## 2026-10-25 — The legend's TBD section is a reader's page, and the calculation detail stays in the manual ([#448](https://github.com/yveshanoulle/forsgren/issues/448), 1 step)

forsgren issue 448, feature, patch release, in 1.23.0. The legend's TBD section is rewritten after a reviewer's proposal and Yves's three reader questions: question headings (how to read the numbers, how often changes reach main, how long a change takes to reach main, when the Time to main clock starts and stops, how the Mainline Interval differs from Time to main, how long to be deployed, how long a pull request takes to merge, how much work is integrated at once, how work reaches main, how many developers contribute, what to look for, what if data is missing, where the names come from, the Notes, where the calculation is explained). The window is named from the config. The five numbered note texts stay, each with the measure it applies to. The section links to the documentation on forsgren.be, since the repository-links gate refuses a github.com repository path on a page.

The seven corrections of the review are applied: the window is the DORA window; the Mainline Interval measures the commits on the main line at their committer date; Commits per deployment counts the commits on the main line; Commits is what the pushes of the window brought; PR is a pull request merge commit or a commit a pull request merge brought, and a branch merged locally and pushed is Direct; the notes cover estimates, a lower bound, a stand-in time and bots, missing data is a dash, a no-data row or a not-readable cell; the key `tbd_figures` is no longer named on the legend (the settings page and `docs/configuration.md` have it). `docs/pages-and-views.md`, The TBD page, gains the clock of Time to main per commit, the difference from the Mainline Interval and the names; the rest of the calculation detail was there.

- Red first: the legend pins of `legend_tbd_test.go` (`legendTbdText`, `legendLeadText`, `legendTbdRetired`, `legendTbdGroups`, `legendLeadVersusDeployText`, the once test) seen failing against the old template (94 findings in six tests), then the template; the legend golden regenerated.

- Lenka B

---

## 2026-10-25 — The manual, the legend and the agent documents follow the 1.22.0 changes, and say where to find the logins for same_developer ([#417](https://github.com/yveshanoulle/forsgren/issues/417), 1 step)

forsgren issue 417, feature, patch release, shipped with #398, #399, #421, #422 and #423 in the release after 1.21.0. `docs/configuration.md`, the `same_developer` entry, says the page shows counts only and the logins are in the `author` column of `data/commits.csv` or in the repository's commit list on GitHub, with the typical cases (an assistant or agent account, one person with a work and a private account); the outdated sentence that Mainline Lead Time counts pull requests now says PR Lead Time (since #403). `agent-installer.md` asks one question (14) about commits from more than one account or an assistant account and writes `same_developer` only with the person's yes; `agent-upgrade.md` step 5 asks the same. `agent-delete.md` was checked: it describes no config key, so it is unchanged.

By Yves's ruling the documentation of the other 1.22.0 issues rides here:

- **#423 and #444 (median by default, no (median) or (duration) in the headers):** the legend says the table shows the median of each measure by default, `tbd_figures: all` shows the mean, the median and p90, and in the median table PR Lead Time shows its median only; the deviation, gaps, count and share-within-24-hours sentences are retired (`legendTbdText`, `legendTbdRetired`, golden). `docs/configuration.md` has the key `tbd_figures` and the settings page as fourteen rows; `docs/pages-and-views.md` describes the table in both modes (15 and 27 columns); `docs/updating-and-releases.md` has the upgrade note for 1.22.0 (without the key the TBD table shows the median only). `CLAUDE.md` follows (the Mainline Interval and PR Lead Time cells, `MedianNotedCell`, `tbd_figures`, the headers, the fixture site).
- **#394 steps 2 and 3 (numbered notes, no-data row):** the legend and the manual describe the five numbered notes with their fixed texts (note 3 is `A lower bound: a first commit time of a pull request was cut`, decision #438), the Notes list below the table, open by default, the markers, and the no-data row with `colspan` 14 or 26. Where the list and the code disagreed, the code was followed: a refused or uncollected push read gives way to the no-data sentence only when the other three signs of data are absent too.
- **#414 (push read token naming):** `docs/data-files.md` has the pushes denied format v2 with the token column, the v1 read, and that the TBD page and `check-needs --pushes-denied` read the file; `docs/updating-and-releases.md` has `A refused push read` with the two item texts.
- **Agent documents:** `agent-installer.md` step 12 now proves fourteen settings rows (`tbd_figures` shows `median (not set)`, `same_developer` follows question 14) and names `tbd_figures` and `same_developer` among the keys it can change later; `agent-upgrade.md` and `agent-delete.md` were checked against the changed manual and describe nothing that changed.

- Red first: `TestConfigurationSaysWhereToFindTheLoginsToGroup` and `TestInstallerAndUpgraderAskAboutSeveralAccounts`, seen failing before the text; the legend pins of `legend_tbd_test.go` (51 findings against the old template) and the installer pins of step 12 (seen failing against the old file). `TestManualDescribesTheTbdFiguresAndTheRefusedPushRead` was written after the text and not seen red.

- Lenka B

---

## 2026-10-25 — The setup issue names a token that was refused the push read ([#414](https://github.com/yveshanoulle/forsgren/issues/414), 1 step)

forsgren issue 414, feature, patch release, in the release after 1.21.0 (1.22.0), the same as #321 did for pull requests. `data/pushes_denied.csv` is the denied format v2, `repository,denied_at,token`: the token column is the name of the token that was refused (`FORSGREN_TOKEN`, `GITHUB_TOKEN`), never a value (a name that is not an upper-case variable name refuses the file on read and on save); a v1 file is still read, every name empty, and written again as v2. `collect` writes the refused token's name with the refusal. `check-needs` adds one setup issue item per repository whose push read was refused, naming the token and its fix (`FORSGREN_TOKEN`: the repository permission Contents: Read; `GITHUB_TOKEN`: `contents: read` on the forsgren job), `--pushes-denied` names the file (`data/pushes_denied.csv` by default), and the item goes away when a later read clears the line. The code is shared with #321: `history.Denied` (was `PullsDenied`), `deniedFormat`, `loadDenied`/`saveDenied`, `collect.deniedFile`, `needs.deniedRead` and `refusedItems` serve both files. Code and tests only; the docs, `CLAUDE.md`, the legend and the agent documents ride with #417.

- Red first, seen failing at runtime against stubs, the push cases of: `TestDeniedV2RoundTripsWithTheTokenName`, `TestDeniedV1IsReadWithNoTokenAndWrittenAsV2`, `TestDeniedHoldsATokenNameNeverAValue`, `TestRefusedNamesTheTokenAndItsFix`, `TestRefusedHasOneItemPerRepositorySorted`, `TestAMissingContentsPermissionNeverFailsThePushRead`, `TestAPushRefusalNotesTheNameOfTheTokenThatWasRefused`, `TestCheckNeedsMakesAnItemOfARefusedRead`, `TestCheckNeedsReadsTheDeniedFileItIsGiven`, `TestCheckNeedsNotesADeniedFileItCannotRead`, `TestRenderRefusesABadPushFile`, `TestConfigurationDocHoldsTheUsageText`.
- Green: the generic denied code above, `needs.RefusedPushes`, `h.pushesDeniedBy` in collect, the data guard reason of `pushes_denied.csv`.

- Lenka B

---

## 2026-10-25 — A project with no data in the window has one sentence for its TBD row ([#394](https://github.com/yveshanoulle/forsgren/issues/394), step 3 of 3)

forsgren issue 394, step 3: Yves's decision #433 (A) with his wording of 2026-10-24. The documentation and the legend ride with #417.

- `metrics.NoData(volume, deploy, push, lead)` (`internal/metrics/nodata.go`): a project has no data when it has no deployed commit, no final deployment in the window, a failed one included (decision #442, A; `DeploymentVolume.Final` from `ChangeFailRates`), no push and no merged pull request (a bot's included). Each of the four alone keeps the data row.
- The TBD row of such a project is its name and one cell across every column after it, `currently no data for this project in the last 30 days`, 30 being the config's dora_days (`TbdRow.NoData`, `NoDataSentence`; `colspan` 14 with the median only, 26 with `tbd_figures: all`, pinned against the header). No note marker and no line of the Notes list comes from such a row. A single column without data keeps its dash.
- Red first, seen failing at runtime: `TestNoDataNeedsAllFourAbsent` against a stub and the page tests against the old template (`internal/page/tbdnodata_test.go`). Acme Tools in the `cmd/forsgren` tests, whose only deployment failed, stays a data row, so those tests are unchanged.
- Goldens: new `tbd.project-no-data` and `tbd.all-project-no-data`; the others unchanged.
- Fixture site: a made-up project Acme Old (`acme/archive`, no records) so the browser gate sees the row; `reach.csv` follows.
- CodeScene: the changed or new Go files 10.0 except `cmd/forsgren/render_pushes_test.go` 9.68 (floor 9.58); rows added for the three new files.

Signed: Lenka B

- Lenka B

---

## 2026-10-25 — The browser gate self-test loses mutation proof U, which raced on a hosted runner ([#386](https://github.com/yveshanoulle/forsgren/issues/386), step 2b)

forsgren issue 386, tools issue, no release. Proof U put `waitForInitialPage: true` back and expected case 53c to still run 15 s after the kill. On a hosted runner the kill marker (the profile folder) can come before Chrome connects, so even the old engine ended at once and the proof raced (forsgren#443). Proof U is removed; case 53c stays as a pin, and it was seen failing against the v5 engine when it was written. `test_gate_browser` goes from v7 to v8 and the self-test ends with nineteen mutations seen instead of twenty; `docs/gate-classification.md` row 122 follows.

- Red first: not applicable, a removal (commit 687ade3).

- Lenka B

---

## 2026-10-25 — FBP and sfl stop at the first red gate ([#441](https://github.com/yveshanoulle/forsgren/issues/441), 1 step)

forsgren issue 441, tools issue, no release. Decision #440 (A): `sfl.sh pre` and `post` stop at the first red gate by default, each later gate printed skipped and named, and the summary says where the phase stopped. `FBP.sh` skips the build or the post phase after a red pre phase, as it already did after the static block, commits the RED commit locally and does not push. `./FBP.sh --all` and `./sfl.sh --all` run every gate. CI (`Scripts/run_ci_phase.sh`) still runs every gate. The static block still runs to its own end first. `sfl.sh` goes from v9 to v10. `docs/development.md` and `CLAUDE.md` describe the run order (commit deed363).

- Red first: `Scripts/test_sfl_static_block.sh`, a red gate stops its phase, the skipped gates are listed as skipped and never as passed, `--all` runs everything, and a secret-class red still commits nothing.

- Lenka B

---

## 2026-10-25 — The writer pre-check is retired, FBP fails fast and is the check ([#439](https://github.com/yveshanoulle/forsgren/issues/439), 1 step)

forsgren issue 439, tools, no release. With FBP stopping a phase at its first red gate (forsgren#441), `precheck.sh` and its self-test `test_precheck.sh` are removed, with the order-file row, the wiring case, the CONTRIBUTING.md gate list line, the `gate-classification.md` row and the passages in `CLAUDE.md` and `docs/development.md`; one sentence replaces them: writers run their tests red first, and FBP (fail fast) is the check. `MIN_GATES` goes from 158 to 157 with the retired row. `Scripts/gate_inputs.txt` had no row for either script.

- Red first: not applicable, a removal; `Scripts/test_gate_wiring.sh`, `test_gate_inputs.sh`, `test_gate_select.sh` and `test_sfl_drives_from_order_file.sh` stay green without exemptions.

- Lenka B

---

## 2026-10-25 — The TBD table headers lose (median), (median duration) and (duration) ([#444](https://github.com/yveshanoulle/forsgren/issues/444), 1 step)

forsgren issue 444, feature, patch release (in 1.22.0, with #423; #435 folded in). Yves's ruling on the live median table. In median mode the headers are Mainline Interval, Time to main per commit, Time to deploy per commit, PR Lead Time, Commits per push and Commits per deployment, each with an `aria-label` that keeps the meaning (`median time to main per commit`); in `all` mode Time to main per commit and Time to deploy per commit lose `(duration)`. Red first: `TestTbdPageHasOneHeaderRowWithTheMedianOnly`, `TestTbdPageHasTwoLevelHeadersWithAllTheFigures` and the two `cmd/forsgren` header tests failed on the old template; the six TBD goldens follow. The legend and the docs (`docs/pages-and-views.md` line 818, `CLAUDE.md` line 22) ride with #417.

- Lenka B

---

## 2026-10-25 — The installer and the upgrader help a repository that has no deployments to count ([#399](https://github.com/yveshanoulle/forsgren/issues/399), 1 step)

forsgren issue 399, feature, patch release, shipped with #398, #417, #421, #422 and #423 in the release after 1.21.0. `agent-installer.md` step 3 (item 4) helps when nothing is found or a deploy job has no environment: propose `environment: production` on the deploy job, or a record step after a deploy outside Actions (the two API calls and the permission), each only with the person's yes, never pushing to a product repository, then check that the next deploy shows. `agent-upgrade.md` step 9 gives the same help where "No deployments" shows. `agent-delete.md` was checked: it says nothing about deployments, so it is unchanged.

- Red first: `TestInstallerHelpsWhenNoDeploymentIsFound`, `TestUpgraderHelpsWhenNoDeploymentShows`, seen failing before the text; `TestDeleterSaysNothingAboutDeploymentSetup` pins the check.

- Lenka B

---

## 2026-10-25 — The TBD table shows the median only by default, and the key tbd_figures shows mean, median and p90 ([#423](https://github.com/yveshanoulle/forsgren/issues/423), 1 step)

forsgren issue 423, feature, minor release 1.22.0 (a new config key; the documentation of 1.22.0 rides with #417). Yves's decisions #424 (C: the Mainline Interval's gaps leave the table in both modes) and #432 (the PR Lead Time follows the other groups). The new key `tbd_figures` is `median` (the default) or `all` (`internal/config/tbdfigures.go`, `checkTbdFigures`, `Config.TbdFigures`; `Accepted`, `settingKeys` before `same_developer`, the settings page row with its possible values, a commented line in `starter.yml`); any other value is rejected, the default is in force and the settings page says why.

- `median`: one column per measure and one header row; each header says it is the median, the shares are `Direct share`, `PR share`, `Unknown share` and `Bots share` (their groups' header row is gone). `all`: mean, median and p90 per measure under two header rows, as before.
- The Mainline Interval and the PR Lead Time lose their deviation; the interval loses its gaps column; the PR Lead Time loses the count, the cut count and the share merged within 24 hours (`MainlineLeadTime.WithinReference` and `Deviation` are gone, with `sampleDeviation`). `MainlineLeadTime` gets a median (from 2 pull requests) and a p90 (nearest rank, from 10), by `medianAndP90`'s rules. A project whose pull requests are not readable or not collected yet has its sentence in one cell, three wide in `all`.
- The notes are the same in both modes: on the mean cell in `all`, on the median cell in `median` (`MedianNotedCell`, for the interval and the PR Lead Time), where the mean is hidden. Decision #424's estimate note therefore stays on a cell the table shows.
- Red first, seen failing at runtime: `internal/metrics/mainleadspread_test.go` against stubs, `internal/config/tbd_figures_test.go` against a config without the key, the page tests against the old template, the settings drift tests (`TestPossibleValuesAreExactlyWhatCheckConfigAccepts`), and `cmd/forsgren/render_tbd_figures_test.go` before `render.go` set `Data.TbdFigures`.
- Decision #438 (A): note (3) reads `A lower bound: a first commit time of a pull request was cut` (number unchanged), as it now sits on a median cell too; `TestNoteKindsKeepTheirNumbersAndTexts` and `TestTbdPageListsTheNotesThatOccurBelowTheTable` changed on purpose, seen red first.
- Goldens: `tbd`, `tbd.lead-no-data`, `tbd.lead-not-collected`, `tbd.lead-not-readable`, `settings`, `settings.rejected` regenerated; new `tbd.all` and `tbd.all-lead-not-readable`.
- Browser gate (fixture site, which sets `tbd_figures: all`): the TBD sideways numbers shrank, 1280x800 table 359 to 312 px and 390x844 table 1249 to 1202 px; `Scripts/browser_gate_fixture_baseline.txt` follows. With the median only the table has no sideways scroll at 1280x800 and 787 px at 390x844 (measured, not gated). `Scripts/build_fixture_site.sh` and `Scripts/test_build_site.sh` read the new cells.
- CodeScene: the changed or new Go files 10.0, except `internal/config/config_test.go` 9.68 and `internal/config/settings_test.go` 9.38, unchanged and above their floors.

Signed: Lenka B

---

## 2026-10-25 — npm: fast-uri 3.1.9 and the stale braces audit exception removed ([#419](https://github.com/yveshanoulle/forsgren/issues/419), 1 step)

- Lenka B

---

## 2026-10-25 — The git sandbox isolation self-test runs in two shards, as two jobs ([#426](https://github.com/yveshanoulle/forsgren/issues/426), step 1 of 1)

forsgren issue 426, tools issue, in the release after 1.21.0. Step 2 of #425: with the step summary gate gone, the Isolation job was still the longest (the self-test 9 min 27 s plus 1.5 minutes of setup). `Scripts/test_git_sandbox_isolation.sh` (canon v2) takes `--shard N/M` and runs the self-tests at positions N, N+M, N+2M of its sorted list (index modulo M), so each runs in exactly one shard and a new one lands in one by itself; no argument runs all, as FBP does; a bad shard (`0/2`, `3/2`, `x`, a missing value, an unknown argument) is exit 64. `Scripts/ci_job_groups.txt` rows may now carry a third field, the arguments of the job (`isolation_1|git sandbox isolation self-test|--shard 1/2`, `isolation_2|...|--shard 2/2`); `Scripts/run_ci_phase.sh` (canon v2) runs the gate in each job named, in no other, with those arguments, and records `<label> (shard N/M)`, so a red names its shard. `Scripts/merge_quality_report.sh` joins the shard rows into the gate's one row under its order-file label: green only when every shard is green, red naming a failed shard or one that reported no row, the details holding every shard. `quality.yml` has the jobs `isolation_1` and `isolation_2` (hand-overs `quality-report-isolation_1` and `_2`, `QS_ISOLATION_1_RESULT` and `QS_ISOLATION_2_RESULT`); the report and preview jobs `needs:` both. Expected: about 6 to 7 minutes per shard job (1.5 setup plus half of 9.5), so every Quality job is under 10 minutes. Every gate still runs in CI exactly once (the real-order-file case counts a split gate once per shard). `Scripts/gate_inputs.txt` is unchanged. Red first: `Scripts/test_git_sandbox_isolation_scope.sh` (cases 20 to 24, canon v2, mutations K and L), `Scripts/test_run_ci_phase.sh` (case shards, canon v3, two mutations), `Scripts/test_merge_quality_report.sh` (cases 3b to 3e, two mutations), `Scripts/test_quality_jobs.sh` and `Scripts/test_preview_workflow.sh` (both jobs, group rows, report wiring, mutants). Docs: `docs/ci.md` (Jobs, Shards) and `docs/quality-gates.md`.

- Lenka B

---

## 2026-10-25 — The configuration page says what a repository must hold for each deployment kind ([#398](https://github.com/yveshanoulle/forsgren/issues/398), 1 step)

forsgren issue 398, feature, patch release, shipped with #399, #417, #421, #422 and #423 in the release after 1.21.0. `docs/configuration.md` has a section, Giving a repository the deployments forsgren counts: per kind, `environment=<name>` (a workflow job with `environment: <name>`, or two REST calls after a deploy elsewhere, a deployment for the commit that went live and a success status, with the token permission Deployments: Read and write), `workflow=<file>` (successful runs on the default branch, nothing to add) and `release` (publish a GitHub Release); how to check a repository has them; and that the deployment must name the commit that went live. `docs/data-files.md` links to it where collecting deployments is described. Made-up names only (`acme/app`).

- Red first: `TestConfigurationExplainsWhatEachDeploymentKindNeeds`, seen failing before the text.

- Lenka B

---

## 2026-10-25 — The TBD cells carry numbered notes instead of sentences ([#394](https://github.com/yveshanoulle/forsgren/issues/394), step 2 of 3)

forsgren issue 394, feature, minor release with step 3 (the legend and the no-data row sentence of #433 are step 3). `metrics.NoteKind` (`internal/metrics/notes.go`) has five kinds with fixed numbers and one table of generic texts: (1) Mostly estimated: commits timed by author date, (2) Commits timed by author date, (3) The mean is a lower bound, (4) Pull requests timed by their created time, (5) Bot pull requests not counted; a new kind appends from (6). `MainlineInterval.MeanCell` and `MainlineLeadTime.Cell` return a `NotedCell` (value and `Note`s with counts); the interval note sits on the mean cell, so #423 can drop the gaps and the deviation, and the gaps cell is the number alone. The PR cell is written per #432 (`3 h ± 1 h · 4 (1 cut)`, then the share sentence). The TBD page writes the marker `(N)` with a visually hidden `note` before it and `aria-describedby="tbd-note-N"` on the cell (`templates/layout/notedcell.html`), and below the table a `details` element, summary Notes, open by default (#430, #431), with one list item `tbd-note-N` per kind that occurs and its projects with counts (`internal/page/tbdnotes.go`, `Data.TbdNotes`).

- `styles.css`: `.table-scroll` is `position: relative`, so the absolutely positioned hidden word stays in the scroll box; it also removed the History page's whole-page sideways overflow of 105 px on the fixture site.
- Red first, seen failing at runtime: the note and cell tests of `internal/metrics` against stubs that returned no notes, the page tests against the old template, `TestTheScrollBoxHoldsTheVisuallyHiddenNotes` before the rule. `TestNoteKindsKeepTheirNumbersAndTexts` pins the numbers and texts; seen red with one text changed and with two kinds swapped.
- Browser gate (fixture site): the TBD sideways numbers shrank, 1280x800 table 397 to 359 px and 390x844 table 1287 to 1249 px; the history page row (105) is gone. `Scripts/browser_gate_fixture_baseline.txt` follows. The fixture site shows four kinds of note (1, 3, 4, 5). `Scripts/build_fixture_site.sh` and `Scripts/test_build_site.sh` read the noted cells. Goldens regenerated: `tbd`, `tbd.lead-no-data`, `tbd.lead-not-collected`, `tbd.lead-not-readable`.
- CodeScene: all 16 changed or new Go files 10.0.

Signed: Lenka B

- Lenka B

---

## 2026-10-25 — npm: fast-uri 3.1.9 and the stale braces audit exception removed ([#419](https://github.com/yveshanoulle/forsgren/issues/419), 1 step)

forsgren issue 419, tools issue, ships in 1.21.0. Dependabot reported 4 alerts (2 moderate, 2 low) for `fast-uri` 3.1.8, a dev dependency of the check tooling (stylelint, table, ajv). The npm audit gate passed because it is red on high and critical advisories only (`npm audit` itself lists all four as one moderate finding). `package-lock.json` now holds `fast-uri` 3.1.9 (`npm update fast-uri`: a transitive package, no override, no pin in `package.json` changed); `npm ci` and `npm audit` report 0 vulnerabilities. The exception for GHSA-vfj7-8cjw-p6xm (braces, forsgren#13) is removed from `Scripts/npm_audit_exceptions.txt`, which npm audit no longer reports; the two docs that named it are updated. The gate still ignores moderate and low advisories; that gap is not changed here.

- Lenka B

---

## 2026-10-25 — Quality runs the two isolation gates in two jobs ([#425](https://github.com/yveshanoulle/forsgren/issues/425), step 1 of 1)

forsgren issue 425, tools issue, no release. The Isolation gates job took 15 minutes in Quality run 40183200190 (setup 1.5 minutes, step summary isolation 4 min 15 s, git sandbox isolation self-test 9 min 27 s, one after another). `Scripts/ci_job_groups.txt` now gives the step summary isolation gate to a new `summary` job (name `Summary isolation gates`, hand-over `quality-report-summary`, `QS_SUMMARY_RESULT` in the report status) and leaves the git sandbox isolation self-test in the `isolation` job; the setup is the same step for step, and the report and preview jobs `needs:` it. Expected: the `isolation` job about 11 minutes, the `summary` job about 6, in line with the Quality gates job. Every gate still runs in one job. Red first: `Scripts/test_run_ci_phase.sh` (the summary job over the real order file), `Scripts/test_quality_jobs.sh` (the job, its setup, hand-over, group rows and report wiring, with mutants; the gate names a step may not spell now come from the group file) and `Scripts/test_preview_workflow.sh` (the needs list). The preview pin's trigger check read a found `workflow_run` as not found once the workflow file outgrew the pipe (`producer | grep -q` under pipefail: grep leaves at its first match and the writer gets SIGPIPE); the three tests above now pipe into a helper `has` that reads all of its input first. Step 2 (two shards of the git sandbox self-test) is only needed if this leaves Isolation the longest job.

- Lenka B

---

## 2026-10-25 — The legend says how Lead time for changes and Time to deploy per commit differ ([#421](https://github.com/yveshanoulle/forsgren/issues/421), 1 step)

forsgren issue 421, feature, patch release; it ships with #398, #399, #417, #422, #423 and #426. The two measures looked alike and gave different numbers, and the legend did not say why. Checked against the code first (`internal/metrics`: `LeadTimes` in `leadtime.go`, `firstDeployments` in `maindirect.go`, `DeployMeasuresOf` in `deploymeasures.go`), and the code agrees on every point: both time a commit from its author date to a deployment in the same window, a negative time as 0; Lead time for changes takes every stored commit of a deployment (also those a merge brought in), once for each deployment that shipped it, and shows the median and its band; Time to deploy takes the first-parent chain only, each commit once at its first deployment, and shows mean, median and p90. So a commit shipped by several deployments is counted at each by Lead time for changes and at the first only by Time to deploy.

- The legend: a paragraph under the Time to deploy per commit heading of the TBD section, and a sentence in the Lead time for changes part that links to the heading id `tbd-time-to-deploy-per-commit`. Kinds only, no project names. The agent documents do not describe these metrics and are unchanged.
- Red first: `TestLegendSaysHowLeadTimeAndTimeToDeployDiffer`, seen failing for the four sentences and the link before the text. Golden regenerated: `legend`.

Signed: Lenka B

---

## 2026-10-25 — The TBD table has a new order of column groups ([#418](https://github.com/yveshanoulle/forsgren/issues/418), 1 step)

forsgren issue 418, feature, patch release, as Yves worded it; it ships in 1.21.0 with #409. The TBD table lists its groups in this order after Project: Mainline Interval, Time to main per commit (duration), Time to deploy per commit (duration), PR Lead Time, Volume, Commits per push, Commits per deployment, Shares of commits, Developers. The columns inside each group keep their order. The two header rows, the column groups, the scopes and the aria-labels follow, and so do the cells of a row.

- The push state (`Push activity not readable`, `Pushes not collected yet`): the three push groups (Time to main, Commits per push, Shares of commits) are no longer next to each other, so each has its own state cell with the same text, `colspan` 3, 3 and 4, in place of the one cell of ten columns. Volume keeps its Commits and Pushes dashes, and the deployment groups keep their numbers.
- The legend: the TBD sub-headings and their sections (h3 ids of #404) follow the table order, every sentence kept; the general paragraph names the groups in the new order, the Developers sentence no longer says it is next to the Mainline Interval, and the push states sentence says one cell under each push group. `docs/pages-and-views.md` and `CLAUDE.md` list the groups in the new order.
- Red first: the header order test, the row cell order tests (shop, lead time states) and the legend h3 order test, seen failing before the change. Goldens regenerated: `tbd*`, `legend`.

Signed: Lenka B

---

## 2026-10-25 — The coverage gate parses its floors file as JSON ([#415](https://github.com/yveshanoulle/forsgren/issues/415), 1 step)

forsgren issue 415, tools issue, no release. `coverage_thresholds.json` had not been valid JSON since forsgren#397 step 5 (a missing comma after the `tbd.go:pairedWithMainline` row, a comma after the last row), and `Scripts/check_coverage.sh` passed every run because it reads the file line by line in a fixed shape and never parsed it. Red first: case 11b of `Scripts/test_check_coverage.sh` (every line in the fixed shape, but a missing comma and a trailing comma) was seen passing the gate, exit 0. The gate now runs `jq empty` on the file before anything else (jq is in `Scripts/required_tools.txt`, so sfl installs it and the hosted image has it): red naming the file and jq's line and column, exit 1; no jq is exit 2. The file is fixed, no floor changed. No other script reads `coverage_thresholds.json`; `codescene-scores.json` is read by no script (a ledger, valid JSON today), so it gets no parse.

- Lenka B

---

- Lenka B

---

## 2026-10-25 — The TBD page leaves beta and is on by default ([#409](https://github.com/yveshanoulle/forsgren/issues/409), 1 step)

forsgren issue 409, feature, minor release, as Yves worded it. Two things an installation sees change. (1) The TBD page has no BETA marker: its title and h1 read "Trunk-based development [TBD]" (`tbdTitle` in `tbd.go` no longer adds `betaMarker`), and so does the legend's TBD section heading. The History page keeps its marker. (2) `tbd_page` defaults to `true` instead of `unlisted` (`tbdPage` in `pagemode.go`): an installation whose config has no `tbd_page` key gets the TBD page in its menu, after History, and the page no longer carries the noindex tag. `unlisted` and `false` work as before, and the accepted values are unchanged.
- Follows the default: the settings page Default column (`true`, from the config), the starter config (`tbd_page: true`), the legend's sentences on the default (the TBD section and the page-keys paragraph), `docs/configuration.md`, `docs/pages-and-views.md`, `install/README.md`, `agent-installer.md` (the settings proof reads `true (not set)` for `tbd_page`), and `CLAUDE.md`.
- `docs/updating-and-releases.md` has an upgrade note: an installation without `tbd_page` in its config gets the TBD page in its menu with this release.
- Red first: the TBD title and h1 without BETA, the legend heading, the config default and its rejection default, the settings defaults, the render of an absent `tbd_page` (menu entry, no noindex) and the installer proof, each seen failing before the change. Goldens regenerated: `tbd*`, `legend`, `settings*`.

Signed: Lenka B

- Lenka B

---

## 2026-10-25 — The setup issue names a FORSGREN_TOKEN that was refused the pull request read ([#321](https://github.com/yveshanoulle/forsgren/issues/321), 2 steps)

forsgren issue 321, bug, patch release. On route B (a fine-grained `FORSGREN_TOKEN`) the setup issue could not see that the token lacked Pull requests (read); a refusal only showed on stderr during collect. Step 1: `data/pulls_denied.csv` is the pulls denied format v2, `repository,denied_at,token`: the token column is the name of the token that was refused (`FORSGREN_TOKEN`, `GITHUB_TOKEN`), never its value (a column that is not an upper-case variable name refuses the file on read and on write, without quoting it). A v1 file is still read, every token name empty, and written again as v2 by the next save; render reads both. Step 2: `forsgren check-needs` reads the file (`--pulls-denied`, `data/pulls_denied.csv` by default) and adds one setup issue item per refused repository: for `GITHUB_TOKEN` the `pull-requests: read` line for the forsgren job, for any other token its own repository permission Pull requests: Read, for a v1 line both fixes, each with its token. The item goes away on the run after a read of the repository worked, because collect then clears its line. A file in no known format is a note on stderr and no item (#395 makes a corrupt file fail; not done here). The push read (`data/pushes_denied.csv`) gets no token column and no item in this issue: it stays on its own follow-up.

- Red first: `TestPullsDeniedV2RoundTripsWithTheTokenName`, `TestPullsDeniedV1IsReadWithNoTokenAndWrittenAsV2`, `TestPullsDeniedHoldsATokenNameNeverAValue`, `TestPullsDeniedSplitsIntoTimesAndTokens`, `TestARefusedPullRequestReadIsNotedWithItsTime`, `TestARefusalNotesTheNameOfTheTokenThatWasRefused`, `TestAPullRequestReadThatWorksClearsTheRefusal`, `TestRenderRefusesABadPullsDeniedFile` (step 1); `TestRefusedNamesTheTokenAndItsFix`, `TestRefusedHasOneItemPerRepositorySorted`, `TestCheckNeedsMakesAnItemOfARefusedPullRequestRead`, `TestCheckNeedsReadsThePullsDeniedFileItIsGiven`, `TestCheckNeedsNotesAPullsDeniedFileItCannotRead` (step 2), each seen failing for its reason.
- Green: `history.Denial`, `PullsDenied`, `DeniedOf` and the v2 format (`internal/history/pullsdenied.go`), `Client.TokenName`, `deniedmark.go` and `h.deniedBy` in collect, `needs.Refused` (`internal/needs/denied.go`), `refusedNeeds` and `--pulls-denied` in `cmd/forsgren`. `docs/data-files.md` and `docs/updating-and-releases.md` describe the file and the items.

- Lenka B

---

## 2026-10-25 — A refused pull request read names the token that was refused, and its fix ([#318](https://github.com/yveshanoulle/forsgren/issues/318), step 1 of 1)

forsgren issue 318, bug, patch release. `explainDenied` always said the job's token needs `pull-requests: read`, also when the refused token was `FORSGREN_TOKEN`, a fine-grained token on route B, so the fix it named was the wrong one. It is now a method of the client and names the client's token. For `GITHUB_TOKEN`: `GITHUB_TOKEN was refused: the job's token needs pull-requests: read in the permissions of the workflow job`. For any other token, `FORSGREN_TOKEN` by default: `FORSGREN_TOKEN was refused: it needs the repository permission Pull requests: Read`. The sentence is the same for the open pull request list, the closed list, a pull request's commits, files and author. The push read of collect (`explainPushesDenied`, which said only `the token needs contents: read`) gets the same two sentences with `contents: read` and `Contents: Read`: it is the same defect, and collect reads it with `FORSGREN_TOKEN`.

- Red first: `TestARefusedPullRequestReadNamesTheTokenAndItsFix` and `TestARefusedPushReadNamesTheTokenAndItsFix` (a refused call with each token name; the message names its own fix and never the other's), seen failing against the old messages.
- Green: `Client.explainRefusal`, `deniedFix` and `permission` in `internal/github/pulls.go`, `jobVariable` in `client.go`; the tests of the other callers, collect's stderr tests and check-update's message test name the new sentences. `docs/configuration.md` describes them.

- Lenka B

---

## 2026-10-25 — The legacy commit backfill runs before the push read, so the first push read cannot starve it ([#416](https://github.com/yveshanoulle/forsgren/issues/416), 1 step)

forsgren issue 416, bug, patch. On an installation whose stored commits predate commits format v3, the push read (#397) ran before the legacy backfill (#385) and spent one comparison per push, so the request budget ran out there and the backfill never ran: `commits_backfilled.csv` was never written and the TBD page showed estimated lead figures and no developers. `collectRepository` now calls `backfillThenPushes`: the backfill goes first, and a backfill that is cut short or fails stops the repository's run, so the push read sends no request after it. A pushes cut after a finished backfill is no cut of the backfill, so the repository is noted done. Tests: a budget that covers the backfill but not both pushes fills the legacy commits, stores the newer push, reports the pushes cut and marks the backfill; a cut backfill sends no push request.

- Lenka B

---

## 2026-10-25 — The coverage gate parses its floors file as JSON ([#415](https://github.com/yveshanoulle/forsgren/issues/415), 1 step)

forsgren issue 415, tools issue, no release. `coverage_thresholds.json` had not been valid JSON since forsgren#397 step 5 (a missing comma after the `tbd.go:pairedWithMainline` row, a comma after the last row), and `Scripts/check_coverage.sh` passed every run because it reads the file line by line in a fixed shape and never parsed it. Red first: case 11b of `Scripts/test_check_coverage.sh` (every line in the fixed shape, but a missing comma and a trailing comma) was seen passing the gate, exit 0. The gate now runs `jq empty` on the file before anything else (jq is in `Scripts/required_tools.txt`, so sfl installs it and the hosted image has it): red naming the file and jq's line and column, exit 1; no jq is exit 2. The file is fixed, no floor changed. No other script reads `coverage_thresholds.json`; `codescene-scores.json` is read by no script (a ledger, valid JSON today), so it gets no parse.

- Lenka B

---

## 2026-10-25 — Quality gets a workflows job, so the main job is no longer the critical path ([#408](https://github.com/yveshanoulle/forsgren/issues/408), 2 steps)

forsgren issue 408, tools issue, no release. The Quality gates job took 15 to 20 minutes on main, 5 to 9 minutes longer than the next job. Step 1 measured the per-gate seconds from the logs of three green Quality runs (the main job's PRE step took 11 to 14 minutes, POST 10 to 14 seconds, the setup 71 seconds). The slowest gates were gate wiring (75 s), the metrics workflow pin (68 s), Go lint self-test (60 s), mutation: checkout pins (45 s) and the release workflow pin (40 s). Step 2: `Scripts/ci_job_groups.txt` gives nine workflow and wiring gates (about 262 s) to a new `workflows` job in `quality.yml`, with the setup of the other group jobs, its hand-over `quality-report-workflows`, and the report and preview jobs `needs:` it (`QS_WORKFLOWS_RESULT` in the report status). Expected: the main job about 10 minutes, the new job about 6, Isolation unchanged. Every gate still runs in one job. Red first: `Scripts/test_run_ci_phase.sh` (the workflows job over the real order file), `Scripts/test_quality_jobs.sh` (the job, its setup, hand-over, group rows and report wiring, with mutants) and `Scripts/test_preview_workflow.sh` (the needs list).

- Lenka B

---

## 2026-10-25 — The browser gate self-test knows when the run is mid-run, and a Chrome that dies during the launch ends it at once ([#386](https://github.com/yveshanoulle/forsgren/issues/386), step 2a)

forsgren issue 386, tools issue, no release. Step 1 found why case 53 raced: its "up" wait (a renderer of Chrome's first about:blank page) is true while `puppeteer.launch` is still pending, so the test could kill Chrome before the engine had attached its process watch, and puppeteer then waited its own 30 s for an initial page that never came. Decision #410 (answer C): the engine and the test are both fixed. Step 2a; the split into a second self-test (#411) is a later step.
- **Engine, `browser_gate` v5 to v6.** The launch passes `waitForInitialPage: false`, so it resolves as soon as Chrome answers on its pipe and the process and connection watch (`chromeGone`) is attached then; `chromeGone` also sees a Chrome that had already ended before it was attached. The pages are opened with `newPage`, which never needed the initial page. A Chrome killed while the run starts now ends it within seconds with the usual error (exit 2, Chrome and profile gone); before, it took puppeteer's 30 s.
- **Test, "up".** The signal comes once the profile folder exists and Chrome holds a connection to the engine's own server (`lsof` on the engine's pid), i.e. it is loading a fixture page, which is only possible after the launch resolved. The listener of the test that step 1 proposed cannot work: the engine blocks every request that leaves its server (even one with an exception row is aborted in Chrome, and never sent), so the connection to the engine's own server is the observable hit. 60 s bound; no engine seam.
- **Test, Chrome gone.** The fixed 10 s window after the end of a signal case (proof R, case 52f) is one 60 s poll of the condition itself.
- **Test, CLS.** The shift fixtures set a flag (`window.__moved`) after the page moved and two frames more; `window.__shifts` answers the gate's read as a promise that resolves then (30 s bound), which the gate's `evaluate` waits for. Cases 8, 8a/8b, 19-23, 38, 38b, 40 and the proof K control no longer depend on 1000 or 2500 ms; the override cases read after 50 ms. Case 15's default-interval text and proof K's read-order trick are unchanged. No change to the engine's read was needed.
- **Test, durations.** Every ok and FAIL line ends with the seconds the case took, and the run ends with the total.
- **New case 53c and proof U.** A Chrome that opens no initial page (`FORSGREN_CHROME` names a wrapper that adds `--no-startup-window`) is killed once its helpers run: exit 2 within 15 s, the usual error, no Chrome, no profile. Seen failing against the v5 engine (30 s timeout); proof U puts `waitForInitialPage: true` back and sees case 53c still running after 15 s. Twenty mutations. `test_gate_browser` v6 to v7.

Signed: Lenka B

- Lenka B

---

## 2026-10-25 — The gate selector skips the gate wiring check on a Go-only change ([#406](https://github.com/yveshanoulle/forsgren/issues/406), 1/1)

forsgren issue 406, tools issue, no release. Follow-up of #402: the gate wiring check (42 s) had no `in` rows, so FBP ran it on every commit. It now has rows from the closure of `Scripts/test_gate_wiring.sh`: the `Scripts/` directory (the test globs it, so a new script selects it), the six workflows, `sfl.sh`, `FBP.sh`, the manifests, the lint configs and the starter config. Red first: the Go-only case skipped it and each kind of input (a closure script, a workflow, the order file, `sfl.sh`, `FBP.sh`, a new script) selected it; `Scripts/test_gate_inputs.sh` checks the label. No exemption: `Scripts/test_gate_select.sh` takes its ledger and Go fixture paths from the list rows instead of spelling them. Quality still runs the gate in full.

- Lenka B

---

## 2026-10-25 — The legend's TBD section has a sub-heading for each group of the table ([#404](https://github.com/yveshanoulle/forsgren/issues/404), 1/1)

forsgren issue 404, feature, patch. The TBD section of the legend was one long run of paragraphs. It now has h3 sub-headings under its h2, each with an id so it can be linked: General (`tbd-general`: the window, the push groups, the mean, median and p90 rules, the duration format and the unlisted default), then in table order Volume, Shares of commits, Time to main per commit, Commits per push, Time to deploy per commit, Commits per deployment, PR Lead Time, Mainline Interval and Developers (`tbd-volume`, `tbd-shares-of-commits`, `tbd-time-to-main-per-commit`, `tbd-commits-per-push`, `tbd-time-to-deploy-per-commit`, `tbd-commits-per-deployment`, `tbd-pr-lead-time`, `tbd-mainline-interval`, `tbd-developers`), and Push states (`tbd-push-states`). Each existing sentence sits under the heading it belongs to; the sentences of the PR Lead Time paragraphs now follow the table order, and the one paragraph about the two intervals is split between PR Lead Time and Mainline Interval, words kept.

- Red first: `TestLegendTbdSectionHasASubHeadingForEachGroup` (the eleven h3 headings, their ids and order, and one sentence of each group after its heading), seen failing before the template change. `legend.golden.html` regenerated.

- Lenka B

---

## 2026-10-25 — check-needs reads the workflow inside the checkout only ([#407](https://github.com/yveshanoulle/forsgren/issues/407), step 1 of 1)

forsgren issue 407, bug, patch release. A code scanner flagged `internal/needs/check.go` for path traversal. Not exploitable today (the workflow of every need in the built-in `needs.yml` is `.github/workflows/forsgren.yml`), but nothing enforced it: an entry with `../` or an absolute path would have read outside the checkout silently.

- The permission check reads the workflow through `os.OpenRoot` on the checkout (`readInRoot`), so `..`, an absolute path and a symlink leaving the checkout are refused by Go; a workflow that cannot be read stays not in place.
- Red first: a need with workflow `../outside.yml`, with a granting file outside the checkout, was read and counted as in place; a symlink in `.github/workflows` to a granting file outside was followed. A third test holds every `workflow:` of `needs.yml` to a clean relative path under `.github/workflows/`.

- Lenka B

---

## 2026-10-25 — The TBD table: shorter headers and durations, PR Lead Time, deployments as a number ([#403](https://github.com/yveshanoulle/forsgren/issues/403), 1/1)

forsgren issue 403, feature. Yves's rulings on the live TBD table: the Deployments cell is the number only (`87`, never `87 releases`); the headers Pull requests and Unknown authors of Shares of commits are PR and Unknown, each keeping its full meaning in an `aria-label` for screen readers; the group Mainline Lead Time is PR Lead Time; Time to main per commit (duration) stays. Every duration in the table is written in one TBD-only form (`tbdDuration`, one table test of every boundary): `3 h 22`, whole hours `2 h` (never `2 h 0`), minutes `7 m`, under a minute `< 1 m`, a day or more as before (`1 d 6 h`), each part cut down as before; the other pages keep their format. The PR Lead Time cell no longer says how many pull requests of unknown author were not counted. The legend follows (retired sentences are in `legendTbdRetired`), and so do the goldens, docs and CLAUDE.md.

- Lenka B

---

## 2026-10-25 — The gate selector stops running slow checks whose inputs did not change ([#402](https://github.com/yveshanoulle/forsgren/issues/402), steps 1 to 3 of 3)

forsgren issue 402, tools issue, no release. A typical Go-only FBP ran about 640 s of checks whose inputs had not changed. Findings and Yves's ruling (steps 1 to 3 in one commit, gate wiring left out) are on the issue.

- Step 1: `codescene-scores.json` was named by no list, so every Go step that moved the score ledger fired the fail-safe and ran every gate. It is a `none|out` row now, as is `coverage_thresholds.json`. The audit of the files changed by the last 30 commits found two files that fire the fail-safe: the ledger, fixed, and `install/install.go`, which is Go source built into the binary the browser gates render with and is now an `in` tree (`install/`) of the three rows that build the site, like `internal/`; the audit list is empty.
- Step 2: the `step summary isolation|in|coverage_thresholds.json` row (added in #264) is gone. No script of the gate's closure opens the file; `Scripts/test_render_quality_summary.sh` prints its name in a message. The closure takes every name for a read, so the message in `Scripts/test_render_quality_summary.sh` now says the coverage floors file instead of naming it; no exemption in `Scripts/test_gate_inputs.sh`.
- Step 3: `in` rows from the closure of the script for `metrics workflow` (30 files), `CI phase runner self-test` (5), `mutation: checkout pins` (2 and the workflow directory) and `git sandbox isolation self-test` (7). `sfl.sh` and `FBP.sh` stay `in` for the metrics workflow, which names them. The git sandbox isolation row is its own closure only: the self-tests it runs under the decoy are scoped by the script itself, and Quality runs it in full.
- Red first: `Scripts/test_gate_select.sh` cases 41 to 54 (a ledger-only change skips the six rows, a Go-only step skips the step summary isolation gate and the four gates, a change to each gate's own script selects it) and the four labels in `Scripts/test_gate_inputs.sh`, each seen failing before the rows. Mutation proof K now removes the ledger row.

- Lenka B

---

## 2026-10-24 — The TBD table shows pushes, shares and deployments side by side ([#397](https://github.com/yveshanoulle/forsgren/issues/397), steps 1 to 6 of 6)

forsgren issue 397, feature, minor release. The TBD page measured everything at deployments: for a project measured by releases, a batch size of 11 was commits per release and a direct time of 1 h 35 min was a commit's age at its release, not at main. The page now reads the pushes to the main branch. Per project it shows, in one table under two-level headers (decisions #400 and #401, Yves 2026-10-24): Volume (Commits, Pushes, Deployments, `85 releases` for a project measured by releases alone), Shares of commits (Direct, Pull requests, Unknown authors, Bots, each of the same commit base, whole percent rounded down), Time to main per commit, Commits per push, Time to deploy per commit and Commits per deployment (mean, median, p90 each), then the Mainline Lead Time of pull requests, the Mainline Interval and the Developers count. A project whose push read was refused says `Push activity not readable`, one with no push collected yet `Pushes not collected yet`, in one cell across the push groups, never deployment numbers in their place.

- Step 1: the decisions, the push signal (GitHub's repository activity list, #400) and the layout (#401).
- Step 2: `collect` reads each repository's pushes to its default branch into `data/pushes.csv` (push, pull request merge, force push; the actor's account type, never a login), with `data/pushes_read.csv` and `data/pushes_denied.csv`; the token need is Contents: read, which every rule already has, so `needs.yml` is unchanged. A 403 stores nothing and never fails the repository; a budget stop shows as a `pushes-cut` line of the cut report and in the run summary.
- Step 3: `data/push_commits.csv`, the first-parent commits each push brought (author login, author date), from the compare collect already makes, written before the pushes; pushes stored before are not read again for them.
- Step 4: the metrics: `PushMeasuresOf`, `DeployMeasuresOf` and their spreads (mean, median from two values, p90 by nearest rank from ten), no page change.
- Step 5: the page: the two-level header, the cells, the two push states, a made-up fixture with pushes, the goldens; the direct and batch size columns and the unknown authors column of Developers are gone; the browser gate's baseline grew for the wider TBD table (about 26 columns, accepted without mobile work on #401).
- Step 6: the Bots share, the legend's TBD section rewritten for the new table, `docs/pages-and-views.md` and `docs/configuration.md`.
- Red first at every step; the HTML duplication ratchet of the golden pages turned out to forbid repeated headers and long runs of identical cells, so the stat headers carry their measure in an `aria-label` and the test data differ per row.
- Push data starts with the release that collects it: older pushes are not looked up afterwards.

- Lenka B

---

## 2026-10-24 — The TBD table as columns: Mainline Interval in five, Developers in two ([#387](https://github.com/yveshanoulle/forsgren/issues/387), steps 1 to 3 of 3)

forsgren issue 387, feature, minor release with #264 and #390. The Mainline Interval and Developers cells of the TBD page had grown into long lines of several numbers. Each number is now a column of its own under a grouped header: Mainline Interval is mean, deviation (the sample standard deviation of the gaps), median, p90 and gaps (how many gaps the other four rest on); Developers is developers (the count) and unknown authors, written `170 (14%)`: the commits without a known author and their share of the window's distinct deployed commits, bots included, in whole percent rounded down. Decisions #388 (mean first, no plus-minus) and #389 (the gap count stays its own figure). A figure not shown yet, and a project without data, is a dash in its own cell. The notes moved: the author-date note ends the gaps cell, and the legacy-data note ends the unknown authors cell. A project with no deployed commit now shows a dash in developers, not 0. The TBD table no longer fits a phone: its sideways overflow at 390x844 is a row of the fixture browser baseline, until the project screen (#91) gives the phone its own view; at 1280x800 it fits.

- Step 1: `MainlineInterval.MeanCell`, `DeviationCell`, `MedianCell`, `P90Cell` and `GapsCell` replace `Cell`; the template has the five columns under a `colgroup`.
- Step 2: `Developers.CountCell` and `UnknownCell` replace `Cell`, `Note` and `legacyCell`; the Developers `colgroup`.
- Step 3: the legend says what mean, deviation, median, p90, a gap and an unknown author are; `docs/pages-and-views.md`, `docs/configuration.md` and `CLAUDE.md`.
- Red first: the cell tests (`TestMainlineIntervalCells`, `TestDevelopersCells`, `TestDevelopersUnknownCellNamesTheLegacyDataAboveHalf`) failed to compile against the old API, the page, render and legend tests failed on the old table; goldens of the TBD page and the legend changed, nothing else.

- Lenka B

---

## 2026-10-24 — Mainline Lead Time in three columns: direct, pull requests, batch size ([#390](https://github.com/yveshanoulle/forsgren/issues/390), steps 1 to 3 of 3)

forsgren issue 390, feature, minor release with #264 and #387. A project that commits straight to the trunk showed nothing in Mainline Lead Time, which measured pull requests only. The TBD page's Mainline Lead Time is now a group of three columns: direct (the time from a commit's author date to the first deployment that contains it, for commits on the first-parent chain that are no pull request's merge commit; the time to main measured at the deployment, as forsgren sees no push time), pull requests (as before, a dash when there is no human pull request) and batch size (the median number of first-parent commits per deployment). Decisions #391 to #393: legacy commits count as direct at their author date with a note, pull-request commits are recognised by the `merge_commit` of `data/pulls.csv`, batch size counts every first-parent commit and leaves legacy deployments out with a note.

- Red first: `maindirect_test.go` (direct median, pull-request commits left out, a negative time as 0, the first deployment of a commit, batch size with a legacy deployment) against stubs; the uncollected note was a red page test before its code.
- Green: `MainlineDirects`, `BatchSizes`, `lineage.known`, the cells in `maindirectcell.go`, `TbdRow.DirectCell`, the grouped header of `tbd.html`, `render.go` passing `Data.MainlineDirect` and `Data.BatchSize`; goldens of the TBD page and the legend.
- Docs: the legend's TBD section says what each column measures and the push-time limit, and now carries the sentence that changes may go directly to the trunk; `docs/pages-and-views.md` and `CLAUDE.md`.

- Lenka B

---

## 2026-10-24 — FBP names each gate it skipped, and why ([#266](https://github.com/yveshanoulle/forsgren/issues/266), step 1 of 1)

forsgren issue 266, tools issue, no release. A gate skipped by the selector of #262 and #263 (the browser gates and the release workflow gate) was only a count in the summary, which reads like a pass. The step table row of a selector skip now says why (`⏭ skip: no changed file is an input`), and the FBP summary lists them under the git row: `gates skipped by selection: N (no changed file is an input of them; counted in the skipped totals above)`, then one `  ⏭ skipped: <label> (<reason>)` line each, from `.build/sfl-skips.log` (FBP removes it before PRE; nothing is printed when no gate was skipped). `sfl.sh` v9, `FBP.sh` v11.

- Red first: cases 1 and 5 of `Scripts/test_sfl_gate_skip.sh` wanted the reason in the table row and the named lines in the FBP summary (the real `FBP.sh` in the sandbox, a stub `sfl.sh` writing the log through the new `FBP_SANDBOX_SFL_SKIPS` seam of `Scripts/lib_fbp_sandbox.sh`).
- Green: `skip_step` takes the short reason; `print_selection_skips` in `FBP.sh`. Mutation proof D: an `FBP.sh` that never reads the log names no skipped gate.
- The stale comment in `sfl.sh` that said the four browser rows now names the browser rows and the release workflow gate.

- Lenka B

---

## 2026-10-24 — sfl skips the step summary isolation gate when a commit touches none of the files it reads ([#264](https://github.com/yveshanoulle/forsgren/issues/264), steps 1 and 2 of 2)

forsgren issue 264, tools issue, no release. The step summary isolation gate took 136 s of an FBP and only needs to run when a commit touches a script that writes the step summary, a self-test that runs one, or what those read. It finds those by searching `Scripts/`, so its inputs are not the closure of its own script. `Scripts/lib_summary_writers.sh` is that discovery, shared by the gate and `Scripts/test_gate_inputs.sh`; `Scripts/gate_inputs.txt` lists the closure of the writers and of the self-tests the discovery finds (66 files; `Scripts/test_gate_wiring.sh` counts with the files it sources only, since it greps the other scripts and runs none). A script added later is the blind spot, and it is closed in the selector: a new kind of row, `grep`, selects the gate for a changed script of `Scripts/` whose text says `GITHUB_STEP_SUMMARY`, before any list names it; a new self-test that names a writer makes `Scripts/test_gate_inputs.sh` red. sfl asks the selector as it does for the other listed rows, and the FBP summary of #266 names the skip.

- Red: mutations I, J and K of `Scripts/test_gate_inputs.sh` and L of `Scripts/test_gate_select.sh` were seen red, each for its named reason; the list and the `grep` row came after them.
- Green: the list, the `grep` row and `gate_input_grepped` in `Scripts/lib_gate_select.sh`; check 6b and mutations I, J and K in `Scripts/test_gate_inputs.sh` (a writer dropped from the rows, a new writer, a new self-test that runs one); cases 33 to 40 and mutation L in `Scripts/test_gate_select.sh` (a listed file runs, a script nobody reads and a docs file skip, a new summary writer runs, a quiet new script skips, an unknown file runs, CI runs it; without the `grep` row a new writer skips).
- Docs: docs/quality-gates.md, docs/gate-classification.md, the comments of `Scripts/gate_inputs.txt` and `Scripts/test_step_summary_isolation.sh`.

- Lenka B

---

## 2026-10-24 — sfl skips the release workflow gate when a commit touches none of the files it reads ([#263](https://github.com/yveshanoulle/forsgren/issues/263), steps 1 and 2 of 2)

forsgren issue 263, tools issue, no release. The release workflow gate took 165 s of an FBP and read nothing a documentation or browser change touches. `Scripts/gate_inputs.txt` now lists the files it reads (its script's closure: the four workflows, the release scripts it names, the libraries it sources), and `sfl.sh` asks the selector of #262 before the row, so the row is skipped when none of them changed; a file no list names still runs it, and Quality runs it always. Deriving the list found that the gate also searched every tracked file for the removed bump machinery, which no list can state. That scan is now its own always-run row, `release removed names`, one search per name (about 3 s), so the gate itself reads only listed files (a copy holding only the listed files passes it, 29 s against 106 s).

- Red first: `Scripts/test_gate_inputs.sh` was red for a missing input list and for the gate listing the tracked files; cases 25 to 31 of `Scripts/test_gate_select.sh` said `has no input list` instead of run or skip.
- Green: the list, the new row and script, `named_files` dropping a leading `./`, `MIN_GATES` 158; `Scripts/test_gate_inputs.sh` has a check that the gate does not enumerate the repository (mutation H); cases 25 to 32 hold the selection (workflow, its pin and a release script run it; another release self-test, another workflow, sfl.sh skip it; an unknown file runs it; CI runs it).
- Docs: docs/quality-gates.md, docs/gate-classification.md, CONTRIBUTING.md, the comments of `Scripts/gate_inputs.txt`, `Scripts/gate_report_order.txt` and `Scripts/test_release_workflow.sh`.

- Lenka B

---

## 2026-10-24 — Collect backfills the author, parents and committer date of legacy commits once ([#385](https://github.com/yveshanoulle/forsgren/issues/385), steps 1 to 4 of 4)

forsgren issue 385, minor release. An installation that ran forsgren before the commits format v3 had lines in `data/commits.csv` with no author, no parents and no committer date, so the TBD page said `1123 commits without a known author excluded (1099 of them legacy data)` and timed those commits by author date. Step 1 was the red tests. Step 2 is the backfill, inside the daily collect and once per repository: `Commit.Legacy` (no parents and no committer date, the old `storedBeforeLineage` moved to `history`), `history.BackfillCommits` (fills only the empty columns of legacy lines from the known commit of the same deployment and SHA, whole-file rewrite in file order through `replaceWhole`, nothing written when no line changed), one Compare per stored deployment that has legacy lines against the previous success of its stream, newest first, `Client.Reserve(repo, 1)` before each, and the ninth mark file `data/commits_backfilled.csv` (also known to the data guard), moved only when no repository failed or was cut short. A previous that is not an ancestor, a missing commit or a cut list leaves the lines legacy with a `collect: backfill:` warning and the backfill still marked; a commit GitHub links to no account keeps an empty login. Step 3 is the report: a backfill the budget cut short is a `backfill-cut` line of the collect report and `<repo> legacy commits cut short (deployments, issues and pull requests read)` on the job summary's Collected line, incomplete and never failed, and the next run continues. Step 4 is `CLAUDE.md`, `docs/data-files.md`, `docs/configuration.md`, `docs/ci.md`, the installation README and an upgrade note in `docs/updating-and-releases.md`.
- Lenka B

---

## 2026-10-24 — The browser gate self-test's CLS cases are ordered by the test, not the clock ([#384](https://github.com/yveshanoulle/forsgren/issues/384), step 1 of 1)

- **Why:** Quality on main went red on a hosted runner: case 38 (the 300 ms setting must catch the shift fixture) saw no shift, because the fixture shifted two animation frames after the load and a loaded machine delivered those frames after the 300 ms read. Proof K had the same race before (#377, #280).
- **Hit cases** 38, 38b (new, a fixture that delays its own shift by 800 ms without blocking) and 40 read with a 2500 ms interval (`run_gate_hit`), seconds of margin.
- **Proof K** and its delayed-load variant: the late-shift page moves one tick after the engine's first read of `window.__shifts`, so the read comes first on any machine; its control is a separate `earlyshift` site that moves two frames after the load.
- **Engine unchanged:** the CLS contract of #379 (interval from the load, default 1000 ms) stands. `test_gate_browser` canon v5 to v6.
- **Proof:** 38b failed before the fix; the full self-test passed normally and under 36 CPU burners. Closes the cause of #280 as well.

Signed: Lenka B

- **Follow-up (.1), case 53 of the next run:** a Chrome killed mid-run was noticed only through the closing pipe. A helper of its group that keeps the pipe open (hosted Linux) kept puppeteer waiting for its timeouts: 299 s measured with a test double, against 0 to 1 s with a clean exit. The engine now watches Chrome's own process exit and the browser disconnect, ends the run at once with exit 2, and release() does not wait 5 s to close a browser that is already gone. `browser_gate` stays v5 (findings and statuses unchanged; its changelog line says so); `test_gate_browser` stays v6 (case 53 only waits longer).
- **Test:** the gate gets up to 60 s to end (its exit is the condition), not a fixed 20 s; new case 53b (double: Chrome plus a helper holding the pipe) and mutation proof T (25 s bound). 53b failed against the old engine, passes now; twenty mutations seen.
- **Removed per [#386](https://github.com/yveshanoulle/forsgren/issues/386):** case 53b and mutation proof T. A helper that holds the pipe after Chrome died was never seen in real life, and the case kept racing. The engine keeps its process watch as safety code; nineteen mutations again; `test_gate_browser` stays v6.

Signed: Lenka B

---

## 2026-10-24 — The browser gate self-test sends its signals once Chrome is up ([#383](https://github.com/yveshanoulle/forsgren/issues/383), step 1 of 1)

Quality went red on the first push of browser_gate v5: on the hosted runner mutation proof S (no signal forwarding) found no Chrome left and no reason. The signal cases 52a to 52f and 53 sent their signal on a timing guess, and the gate had run its pages by then. A run with one look reproduces it: every case ends with exit 0 and the mutations R and S get the reason `expected exit 143, got 0`.
- **Cause.** The wait for a page used a pattern that never matched: a renderer's command line has `--type=renderer` before `--user-data-dir`, not after. So every case waited its full 30 s and signalled then, a fixed delay that a fast machine outran. The cases also did not check that the gate was still running when the signal came, and ten looks were too few.
- **Fix.** `signal_case` waits (30 s) for the profile folder of its own case and a Chrome renderer with that profile, then checks that the gate is still running, then sends the signal. If Chrome is not up, or the gate ended first, the case is red with that reason. The fixture has forty looks. The first real signal at the first page then showed a race in the engine: Chrome's helpers still wrote into the profile while it was removed, so 52b and 52e left the folder. `release()` now removes the profile with retries (`maxRetries` 10, 200 ms). The engine stays `browser_gate` v5 (no copy took v5 yet; findings and exit statuses unchanged, no marker line), the wrapper is unchanged. The self-test is canon `test_gate_browser` v5: other copies take the new waiting.
- **Second fix (step 1.1).** Under a full FBP's load cases 52a and 52d still left the profile folder. Cause: closing the browser does not end Chrome's helper processes (GPU, network, renderers); one still running wrote into the profile after `rmSync` removed it, so the folder came back, and a failed removal was swallowed by the signal handler. Retries cannot fix that, whatever their number. `release()` now kills Chrome's whole process group (puppeteer starts it as a group leader) and waits, at most 10 s, until the group is empty before it removes the profile; a group that still runs is an error, and a cleanup that fails in a signal handler prints a line and exits 2. A signal during the launch waits for the launch (at most 30 s), so that browser is closed too. The engine stays `browser_gate` v5 (no copy took v5 yet; findings and exit statuses unchanged), the wrapper and the self-test are unchanged.

-- Lenka B

---

## 2026-10-24 — The browser gate closes its Chrome and removes its profile on every exit ([#381](https://github.com/yveshanoulle/forsgren/issues/381), step 1 of 1)

Another estate repository found a headless Chrome of the browser gate still running 25 hours after its run, with its profile folder. The engine closed the browser only in a `finally` after the pages, a signal skipped that, the launch sat outside the `try`, and the wrapper ran node in a pipe to `tee` with no trap. The same engine and wrapper pattern were here. The engine is now canon `browser_gate` v5, the wrapper `gate_browser` v3, its self-test `test_gate_browser` v4.
- **Engine.** One `release()` closes the browser (five seconds, then a kill), the server and the profile folder, once. It runs in `finally` and on SIGINT, SIGTERM and SIGHUP, which exit 130, 143 and 129. The profile folder and the launch are inside the `try`, puppeteer's own signal handlers are off, and Chrome runs on a pipe, so it also ends when node is killed with SIGKILL. The findings and the exit statuses 0, 1 and 2 are unchanged.
- **Wrappers.** `Scripts/gate_browser.sh` and `Scripts/gate_browser_fixture.sh` run node in the background, its output through a fifo to `tee`, forward SIGINT, SIGTERM and SIGHUP to it, wait, and exit 128 plus the signal number.
- Red first: `Scripts/test_gate_browser.sh` cases 52a to 52f and 53 start the gate on a ten-look fixture, signal it once a page is open, and look for Chrome processes of that profile and for the profile folder. On v4: 52a, 52d and 52f left 7 Chrome processes, 52b and 52e exited 2, 52c ran to the end with 0. Mutations R (no handler: the profile folder stays) and S (no forwarding: Chrome stays alive) are red for those reasons. Nineteen mutations in all.
- The two sites move to v5 in their own port issues.

-- Lenka B

---

## 2026-10-24 — Logins of one person count as one developer ([#361](https://github.com/yveshanoulle/forsgren/issues/361), steps 1 to 3 of 3)

forsgren issue 361, decisions #360 and #378, minor release. A new optional config key, `same_developer`, lists groups of GitHub logins that count as one developer in the TBD page's Developers column: a list of lists, two or more logins each, compared without case, the first login naming the developer, a login in one group only. A value that is not accepted is not used at all: the default `[]` stays in force with a warning and the settings page says why, so no group is half applied. Step 1 is the key, its validation and the settings row (thirteen rows). Step 2 is the count: `MainlineDevelopers` merges each group into one developer, a `[bot]` login stays left out even when grouped, a login in no group counts as before, a group none of whose logins appears counts nothing, and `data/commits.csv` keeps the real login; the legend's TBD section says in one sentence how aliases count. Mainline Lead Time counts pull requests, not people, so it does not change. Step 3 is `docs/configuration.md` (the key, its refusals, the bot quoting rule, the thirteen rows), `docs/pages-and-views.md` and an upgrade note in `docs/updating-and-releases.md`.
- Lenka B

---

## 2026-10-24 — The browser gate engine is canon v4 ([#377](https://github.com/yveshanoulle/forsgren/issues/377), step 1 of 1)

forsgren issue 377, decisions #379 and #380 (A). The engine `Scripts/browser_gate.mjs` changed what it observes, so it is now canon `browser_gate` v4: the layout shift (CLS) interval, default 1000 ms, starts right after the page load, with no second read after axe, and the sideways measurement ignores scrollbar room. The baseline format is unchanged, no migration. The engine header carries the changelog; `docs/quality-gates.md`, `docs/gate-classification.md` and CLAUDE.md name v4. No self-test pins the version line, so there was no red.
- Lenka B

---

## 2026-10-23 — The legend and the docs say what Mainline Lead Time counts ([#256](https://github.com/yveshanoulle/forsgren/issues/256), step 3 of 3)

forsgren issue 256, step 3 of 3, minor release (with steps 1 and 2, #337, #345 and #355). The legend's TBD section no longer says Mainline Lead Time is not on the page yet. It says: the scope (merged human pull requests only, work pushed straight to the main branch not in it, a pull request standing in for a branch, mixed workflows covered only for pull-request changes; #342); what is counted (one lead time per pull request merged in the window, first commit author date to merge, a negative one as 0) and the cell (mean ± deviation (pull requests), the share within 24 hours rounded down, no verdict); the two dates of the Mainline Interval and Mainline Lead Time and how the four combinations read (#297); the lower bound for cut pull requests, which can also push the 24-hour share too high, and the created-time stand-ins; that only a GitHub User is a person, bot and unknown-author notes, the placeholder author `invalid-email-address` not a developer; the legacy format worded as Yves ruled on #356 (commits in the legacy format have no known author and are not counted; never claimed to be stored before v3); the Mostly estimated note; and what the no-human-pull-request, not readable and not collected cells mean. `docs/pages-and-views.md` (The TBD page) and `docs/configuration.md` carry the same, and CLAUDE.md names the legend as the page's explanation.

- Red first: `TestLegendSaysWhatEachLeadTimeNumberCounts` (32 sentences read from the rendered legend, two claims it must not make) and the retired sentences in `TestLegendRetiresTheAuthorDateWording` failed at runtime against the old template; `TestLegendSaysEachTbdSentenceOnce` moved to the scope sentence. Only `legend.golden.html` changed, by the legend text.
- Lenka B

---

## 2026-10-23 — The TBD table fits a laptop and a phone without sideways scrolling ([#350](https://github.com/yveshanoulle/forsgren/issues/350), steps 1 and 2 of 2)

forsgren issue 350, steps 1 and 2 of 2 in one build (red and green together), patch; decisions #364 (option B) and #365 (option A). The TBD table's cells had grown long notes, and as a `no-wrap` table with the tables' minimum width of 44rem it was 2058 px wider than its box at 1280x800 and 2948 px at 390x844.

- Step 1, the check: the shared browser gate engine (`Scripts/browser_gate.mjs`, canon `browser_gate` v3, decision #365) measures every page at 1280x800 and 390x844 (`SIDEWAYS_VIEWPORTS`) after the layout shift is read, which stays at 1280x800 alone, and is red when the page is wider than the window or a table wider than the box it sits in, naming the page, the width and the overflow in pixels (`measureSideways`, `checkSideways`). One rule for every page with a table, in both browser gates. The fixture site gets a made-up `data/pulls.csv` (decision #336), so its TBD page shows a Mainline Lead Time with its long notes, and `Scripts/build_fixture_site.sh` is red when it does not (`tbd_shows_lead_time`).
- The baseline (decision #364): a `sideways|<variant>|<page>|<viewport>|<what>|<px>|reason` row kind, judged as a CLS row (above red, below red until the row shrinks, gone red, none red; `readSidewaysRow`, `judgeSideways`). The other tables keep scrolling inside their box by design (forsgren#38); their overflow today is 13 rows in `Scripts/browser_gate_fixture_baseline.txt` and 1 in `Scripts/browser_gate_baseline.txt`, temporary debt with a follow-up issue per page family and forsgren#366 for the History page's own 105 px. `Scripts/report_baselines.sh` (canon v4) shows the sideways rows on the Quality page.
- Step 2, the fix: the TBD table is class `wraps` instead of `no-wrap` (`templates/pages/tbd.html`; the four table goldens change in that attribute only), and `table.wraps` in `styles.css` has no minimum width and half the side padding, so its cells break and its four columns share the width: at 390x844 the table is exactly its box's 343 px wide. No text changes; the legend is unchanged.
- Red first, seen failing: cases 41 to 49 and the OK line of case 15 in `Scripts/test_gate_browser.sh`; cases 34 to 36 in `Scripts/test_build_site.sh`; cases 4i, 4j and the new counts in `Scripts/test_report_baselines.sh`; `TestTbdTableWrapsItsCells` and `TestWrappingTablesHaveNoMinimumWidth`; the fixture gate on the TBD page (2058 px at 1280x800, 2948 px at 390x844, then 5 px at 390x844 before the padding).
- Mutations seen red: the check removed (L) and loosened to 1000 px (M); the growth comparison dropped (N); the sideways stale check removed (O); the sideways rows not printed by the report (P); the lead-time check of the fixture build removed (case 36).

---

## 2026-10-23 — A build with no version information says dev, never a stale release ([#340](https://github.com/yveshanoulle/forsgren/issues/340), step 2 of 2)

forsgren issue 340, step 2 of 2, patch release (Yves chose option C on #367). `var version = "1.11.1"` in `main.go` was a fallback nothing moved, since releases make no commit (#237), so the preview footer named 1.11.1 while the latest release was 1.15.0. The fallback is gone: `var version` is empty and only an ldflags value sets it. `runningVersion` gives the ldflags value, else a clean release tag of the build information, else the last tag of a checkout build (`lastTagOfCheckout`, still `1.15.0+dev (commit)`), else `buildversion.Dev`, `dev`. The footer reads `dev (<commit>)`, or `dev` with no commit, and promises no update; the run summary says `Update: unknown (a development build)` and `Setup: not checked, a development build does not know what it needs`; `check-needs` records `skipped`, makes no request and so opens, updates, reopens or closes no setup issue; the installation README says `for forsgren dev (a development build)`. `Scripts/release_verify_install.sh` says installations show `dev` meanwhile. `TestNoTestPinsTheReleasedVersion` went with the value it pinned, and the docs test looks only for running-version strings. #237 stays: a release makes no commit.

- Red first, seen failing at runtime: the resolver cases that returned an empty version, the dev footer (three builds), the run summary, `check-needs` (stderr, status, no request), the README, and `var version` empty.
- No new script: the step 1 idea of `check_version_fallback.sh` was dropped with the fallback it pinned; Go tests replace it (tagged, untagged, checkout, no VCS, version-dependent behaviour).

---

## 2026-10-23 — GitHub's placeholder author is never a developer ([#355](https://github.com/yveshanoulle/forsgren/issues/355), step 1 of 1)

forsgren issue 355, step 1 of 1, patch release (with #256, #337, #345). GitHub answers a commit whose author email links to no account with the placeholder login `invalid-email-address`, which collect stored as the author like any login, so the Developers count took it for a person. `MainlineDevelopers` now counts a commit by that login (`placeholderLogin`, compared ignoring case in `noteAuthor`) with the other commits without a known author, never as a developer. Such a commit is never legacy data: `Developers.add` counts as legacy only a commit without a login stored before the commits format v3, so the legacy cell says `(3 of them legacy data)` when placeholder commits are among the unknown ones. The stored lines keep the login as GitHub gave it (no rewrite, #293): the counting side decides, so the lines stored before stop counting as a developer too. GitHub documents no list of placeholder logins; `invalid-email-address` is the one seen. The legend's sentence on commits whose author GitHub links to no account already covers it, so no golden changes. `docs/data-files.md` and `docs/pages-and-views.md` name the placeholder.

- Red first, seen failing at runtime: `TestDevelopersTakeGitHubsPlaceholderForAnUnknownAuthor` (two placeholder commits, one with another case, one stored before v3, and a person: 2 developers and 0 unknown before the fix, want 1 and 3; and a mostly legacy project with one placeholder commit called all legacy data).
- Mutations seen red: the placeholder counted as a developer again; the placeholder called legacy data; the placeholder compared with case.
- Coverage: no new function, `noteAuthor` and `Developers.add` stay at 100.0, total 99.8. CodeScene: `developers.go` and `developers_test.go` 10.0, unchanged.

---

## 2026-10-23 — The TBD page names legacy data plainly when it is most of a figure ([#345](https://github.com/yveshanoulle/forsgren/issues/345), step 3 of 3)

forsgren issue 345, step 3 of 3, minor release (before #256 step 3 and its release; Yves's answer on #344, Option C; #355 noted). The Mainline Interval cell's note becomes `Mostly estimated: 1121 of 1134 commits timed by author date.` when more than half of the commits counted are timed by author date (`MainlineInterval.Note`, `mostOf`); at half or below it stays `1121 commits timed by author date`. `Developers` now holds `Commits`, the window's distinct deployed commits, bots' included, and `Legacy`, the commits without a known author stored before the commits format v3 (`storedBeforeLineage`: no parents and no committer date). When `Legacy` is more than half of `Commits`, the Developers cell is `3 developers · 1099 commits without a known author excluded (legacy data).` (`legacyCell`); when some of the unknown ones were stored with their lineage, GitHub linking them to no account, it says how many are legacy data, `(3 of them legacy data)`, so none is called legacy data that is not. At half or below the plain note stays. Mainline Interval speaks of an estimate, measurement accuracy; Developers never does, incomplete attribution (#344). No backfill (#293). The legend is #256 step 3.

- Red first, seen failing at runtime against a stub (the `Legacy` and `Commits` fields alone, not filled, not shown): `TestMainlineIntervalSaysMostlyEstimatedAboveHalf`, `TestMainlineIntervalCellSaysMostlyEstimated`, `TestDevelopersCountTheCommitsAndTheLegacyUnknownOnes`, `TestDevelopersCellNamesTheLegacyDataAboveHalf`, the updated Developers counts, the lineage cell, the TBD page rows and goldens and the render tests.
- Mutations seen red: the threshold at half inclusive; the plain Mainline note gone below the threshold; the Developers sentence below the threshold; the word estimated in the Developers cell; every unknown author counted as legacy data; the threshold on the unknown ones instead of the legacy ones; the mixed case claiming all of them legacy data.
- Coverage: `mostOf`, `legacyCell`, `Developers.add` and `storedBeforeLineage` registered at 100.0, total 99.8. CodeScene: `legacyshare_test.go` 10.0, new row; `developers.go`, `mainline.go`, `developers_test.go`, `mainline_lineage_test.go`, `page/tbd_test.go`, `render_tbd_test.go` 10.0, unchanged.

---

## 2026-10-23 — Mainline Lead Time counts human pull requests only and shows its counts ([#345](https://github.com/yveshanoulle/forsgren/issues/345), step 2 of 3)

forsgren issue 345, step 2 of 3, minor release (before #256 step 3 and its release; Yves's answers on #341, #342, #343, #348 and #349). `MainlineLeadTimes` counts a pull request merged in the window only when a person opened it (`history.ByHuman`, `add`): one a bot opened goes to `MainlineLeadTime.Bots` and one of unknown author, every line of the pulls format v1 among them, to `UnknownAuthors` (`leaveOut`), never into the mean, the deviation, the count or the 24-hour share. The TBD page's cell (`Cell`, `counted`, `notCountedNotes`, `pullRequests`) writes the share with its counts, `66% (2 of 3) pull requests merged within 24 hours of their first commit` (#343, rounded down as before, no `of` after the brackets); without a human pull request it reads `No human pull requests in this period; changes may go directly to the trunk` (#342's wording, the dash gone); last, either way, `3 bot pull requests not counted` and `1 pull request of unknown author not counted`, each only when there are any, singular and plural. `Pull requests not readable` and `No pull requests have been collected yet` keep their wording and precedence. The column's description is the legend's, which still says Mainline Lead Time is not on the page: it is written in #256 step 3, with the scope of merged human pull requests (#342). `docs/data-files.md` says which `bot` lines Mainline Lead Time counts. Collect now follows Yves's answer on #349 (Option B): `botOf` takes the account type `User` alone as a person, `Bot` as a bot, and any other type (`Organization`, `Mannequin`) or none as unknown, the pull request stored all the same with its `bot` column empty; step 1 had taken every type but `Bot` and none as a person.

- Red first, seen failing at runtime against a stub (the `Bots` and `UnknownAuthors` fields alone, not counted, not shown): `TestMainlineLeadTimeCountsHumanPullRequestsOnly`, `TestMainlineLeadTimeWithoutAHumanPullRequestHasNoLeadTime`, `TestMainlineLeadTimeCellNamesThePullRequestsNotCounted`, the share and no-human cases of `TestMainlineLeadTimeCellShowsMeanCountAndShare` and `TestMainlineLeadTimeCellSaysWhatIsNotExact`, `TestTbdPageShowsTheDevelopersNextToTheInterval`, `TestTbdPageSaysThePullRequestsAreNotCollectedYet`, `TestTbdPageSaysThePullRequestsAreNotReadable`, the `tbd`, `tbd.lead-no-data` and `tbd.lead-not-readable` goldens (Acme Docs with 2 bot pull requests and no human one, Acme Web with 3 of bots and 1 of unknown author), and the render tests over a `pulls.csv` with a bot's and an unknown author's pull request (`TestRenderShowsTheMainlineLeadTimeOfEachProject`, `TestRenderTbdPageBeforeThePullRequestsAreCollected`, `TestRenderShowsTheDevelopersOfEachProject`, `TestRenderTbdPageSaysThePullRequestsAreNotReadable`); `TestCollectStoresAnAuthorOfAnotherTypeAsUnknown` (an `Organization` and a `Mannequin` author stored as `false` before the fix, want empty; a user with no type stays empty) against step 1's `botOf`.
- Mutations seen red: bots counted; unknown counted as human; the share without its counts; the old `of pull requests` wording; the no-human sentence shown while human pull requests exist; the no-human cell back to the dash; the bot and unknown notes dropped; the plural for one; the notes winning over `not readable`; any non-`Bot` type read as a person (step 1's rule); `User` read as unknown.
- Coverage: `add`, `leaveOut`, `counted`, `notCountedNotes` and `pullRequests` registered at 100.0, total 99.8. CodeScene: `mainlineleadhuman_test.go` 10.0, new row; `collect/pulls.go`, `collect/pulls_bot_test.go`, `history/pullbot.go` 10.0, unchanged; `mainlinelead.go`, `mainlineleadcell.go`, `mainlinelead_test.go`, `mainlineleadcell_test.go`, `tbd_test.go`, `render_tbd_test.go`, `render_tbd_lead_test.go`, `render_tbd_denied_test.go` 10.0, unchanged.

---

## 2026-10-23 — pulls.csv v2 says whether a bot opened each pull request ([#345](https://github.com/yveshanoulle/forsgren/issues/345), step 1 of 3)

forsgren issue 345, step 1 of 3, minor release (before #256 step 3 and its release; Yves's answer on #341, Option A). `data/pulls.csv` is the pulls format v2: the column line gains `bot` after `created_stands_in`, `true` when GitHub's account type of the pull request's author (`user.type`) is `Bot`, `false` for any other type, and empty when the type is not known. `history.PullRequest.Bot` is a `BotStatus` (`pullbot.go`) with three states, `BotUnknown` (the zero value, so a pull request nobody judged is never a person's), `ByHuman` and `ByBot`. `ClosedPullRequests` reads `user.type` into `ClosedPullRequest.UserType` and never the login (#255's no-authors rule); `collect` turns it into the bot status (`botOf`), a null user or a missing type being unknown. A v1 file is still read, every line's bot status unknown, and the first append rewrites it once as v2, whole, through a temporary file, unknown kept as an empty column (as #273 and #254 upgraded the commits). No metric or page changes: the Mainline Lead Time leaving out bot and unknown pull requests is step 2. Documented in docs/data-files.md.

- Red first, seen failing at runtime against stubs (the `BotStatus` type, the `Bot` and `UserType` fields alone, the format still v1): `TestThePullsFileKeepsWhoOpenedEachPullRequest`, `TestAppendPullRequestsUpgradesAV1FileToV2`, `TestAppendPullRequestsWithNothingNewStillUpgradesAV1File`, `TestAV1PullsLineInAV2FileIsRefused`, `TestABotStatusThatIsNoneOfTheThreeIsRefused`, the existing pulls tests on the v2 header, `TestClosedPullRequestsReadTheAuthorsAccountType`, the closed pulls fixture with a Dependabot item, `TestCollectStoresWhetherABotOpenedEachPullRequest`, `TestCollectUpgradesAV1PullsFileKeepingUnknownAsUnknown` and the collect pulls tests on v2 lines. `TestLoadPullRequestsReadsAV1FileWithBotStatusUnknown` and `TestAClosedPullRequestHoldsNoLogin` were green against the stubs (they pin what the stubs already did) and are proven by mutation.
- Mutations seen red: a bot read as a person (`botOf`); a missing author type read as a person; a v1 line read as a person (the lift); the login read into the pull request (`TestAClosedPullRequestHoldsNoLogin`: want no login held); unknown written as `false` (a bool column, lost on the rewrite); a bot status outside the three accepted.
- Coverage: `botOf`, `String`, `isBotStatus` and `parseBot` registered at 100.0, total 99.8. CodeScene: `pullbot.go`, `pulls_bot_test.go` (history and collect) and `closedpulls_user_test.go` 10.0, new rows; `history/pulls.go`, `pulls_test.go`, `closedpulls.go`, `closedpulls_test.go`, `collect/pulls.go`, `collect/pulls_test.go`, `render_tbd_lead_test.go` 10.0, unchanged.

---

## 2026-10-23 — the TBD page says the pull requests are not readable ([#337](https://github.com/yveshanoulle/forsgren/issues/337), step 2 of 2)

forsgren issue 337, step 2 of 2, minor release (before #256 is released, decision #332). render reads `data/pulls_denied.csv` beside `--data` into `metrics.Data.PullsDenied` (`withPulls` in `render.go`, with `data/pulls.csv`): a missing file refuses nothing, an unknown version or a malformed line fails the render naming the file, as the other data files do. `MainlineLeadTimes` marks a project `NotReadable` when one of its repositories is in the file (`markNotReadable`, compared ignoring case through the project index, decision #339; a repository no project lists is left out), and `MainlineLeadTime.Cell` then says `Pull requests not readable`, never a lead time of the repositories that were read nor `-`. One refused repository makes the project's whole cell not readable (the decision of this step). `TbdRow.LeadCell` shows it also while `data/pulls.csv` is absent, so the three states stay apart: `No pull requests have been collected yet` (no pulls.csv, no refusal), `Pull requests not readable` (a refusal line), `-` (pulls.csv, no merged pull request in the window). docs/data-files.md describes `data/pulls_denied.csv` (columns, when it is written and cleared, kept apart from `pulls-cut`, what the TBD page does with it); docs/development.md lists it among the data guard's names. The legend is #256 step 3's.

- Red first, seen failing at runtime against stubs (the `NotReadable` and `PullsDenied` fields alone): `TestMainlineLeadTimeIsNotReadableWhenARepositoryWasRefused`, `TestMainlineLeadTimeComparesRefusedRepositoriesWithoutCase`, `TestMainlineLeadTimeCellSaysNotReadable`, `TestTbdPageSaysThePullRequestsAreNotReadable`, the `tbd.lead-not-readable` golden, `TestRenderTbdPageSaysThePullRequestsAreNotReadable` (the line written as `ACME/Api`, with and without pulls.csv) and `TestRenderRefusesABadPullsDeniedFile`.
- Mutations seen red: `Cell` ignoring `NotReadable` (the refused project shown with its lead time or `-`); a case-sensitive compare (`file in capitals` and the render test); the denied file's load error ignored (malformed and unknown version rendered); `not collected yet` winning over `not readable`; render not passing the refusals on.
- Coverage: `markNotReadable` and `withPulls` registered at 100.0, total 99.8. CodeScene: `render.go` 10.0 (9.68 before `withPulls` was split out of `metricsDataOf`), `mainlinelead.go`, `mainlineleadcell.go`, `rows.go`, `tbd.go`, `tbd_test.go` 10.0, unchanged; `mainlineleadnotreadable_test.go` and `render_tbd_denied_test.go` 10.0, new rows.

---

## 2026-10-23 — collect notes the refused pull request reads in `data/pulls_denied.csv` ([#337](https://github.com/yveshanoulle/forsgren/issues/337), step 1 of 2)

forsgren issue 337, step 1 of 2, minor release (before #256 is released, decision #332). The TBD page reading the file and the docs are step 2. When GitHub refuses a repository's pull request read with a 403 (`ErrPullRequestsDenied`, the token without `pull-requests: read`), on the list or on a pull request's commits, collect writes the repository's line in the new `data/pulls_denied.csv`: the pulls denied format v1 (`# forsgren pulls denied v1`, `repository,denied_at`, `internal/history/pullsdenied.go`, `LoadPullsDenied`/`SavePullsDenied`), a mark file like `pulls_read.csv`, the eighth of `markFiles`. A line holds the repository name and the run's time, whole seconds UTC, nothing else; a later refusal moves the time. A read that ends without an error removes the line: one that stored merged pull requests, one that found none, and one cut at the page limit (the list was answered). A budget stop (`pulls-cut`) or any other error leaves the file as it was, since neither says whether the pull requests can be read; a refusal is never in the report's `pulls-cut` lines. The collection still never stops or fails on a refusal (Yves's ruling on #255). A `pulls_denied.csv` that cannot be read refuses the run before GitHub is asked. The data guard has a `pulls_denied.csv` arm, so the file outside `testdata/` blocks the commit.

- Red first, seen failing at runtime against stubs (`LoadPullsDenied` and `SavePullsDenied` reading and writing nothing, `endPulls` not touching the mark): the `pulls_denied.csv` row of the mark file round trip; `TestARefusedPullRequestReadIsNotedWithItsTime` (the list with no file and with an older refusal, a commit list), `TestAPullRequestReadThatWorksClearsTheRefusal` (merged pull requests, none, a list cut at the page limit), the `pulls_denied.csv` case of `TestAPullsFileThatCannotBeReadRefusesTheRun`; the data guard self-test (the drift check naming `pulls_denied.csv` unguarded, a new case 17 and its arm-deleted mutation proof). `TestABudgetStopOrAFailedReadLeavesTheRefusalsAsTheyWere` passed against the stubs, as a test of what must not change; its mutations below are its red.
- Mutations seen red: the refusal not written; the line not cleared after a read that works; the line cleared after a budget stop; a budget stop noted as a refusal; a token-like value written into the line (the test names it: `want no token value in pulls_denied.csv`); the data guard's `pulls_denied.csv` arm deleted (the self-test's own proof).
- Coverage: `LoadPullsDenied`, `SavePullsDenied` and `pullsDeniedFile` registered at 100.0, total 99.8. CodeScene: `internal/history/pullsdenied.go` and `internal/collect/pullsdenied_test.go` 10.0, new rows; `pulls.go`, `pulls_test.go`, `failuresread.go` and `readat_test.go` 10.0, `collect.go` 9.68, unchanged.

---

## 2026-10-23 — Mainline Lead Time on the TBD page ([#256](https://github.com/yveshanoulle/forsgren/issues/256), step 2 of 3)

forsgren issue 256, step 2 of 3, minor release. The TBD page has a Mainline Lead Time column next to the Mainline Interval: Project | Mainline Interval | Mainline Lead Time | Developers. render loads `data/pulls.csv` into `metrics.Data.Pulls` (missing is none, unknown or malformed fails the render, as for the other data files) and sets `page.Data.MainlineLead` from `metrics.MainlineLeadTimes`; `page.Data.TbdRows` pairs it with the Mainline Intervals by project, as it pairs the Developers, and fails the render when they disagree. The cell (`MainlineLeadTime.Cell`, `internal/metrics/mainlineleadcell.go`) is the mean, the deviation and the count, the cut pull requests next to the count (decision #299), then the share in the wording of decision #302, `3 h ± 1 h (4, 1 cut) · 50% of pull requests merged within 24 hours of their first commit`; with a cut one it adds `the mean is a lower bound`, and it names the pull requests the created time stood in for (decision #300), `1 pull request timed by its created time`; `-` without a pull request in the window. Without `data/pulls.csv` every cell says `No pull requests have been collected yet` (`page.Data.PullsUncollected`). A refused pull-requests read is not told apart yet: collect leaves no trace of it that render reads (decision to come). The legend still says Mainline Lead Time is not on the page; the legend and the docs are step 3.

- Red first: the tests failed at runtime against stubs (an empty `Cell` and `LeadCell`, no pairing, no column, no load): `TestMainlineLeadTimeCellShowsMeanCountAndShare`, `TestMainlineLeadTimeCellSaysWhatIsNotExact`, `TestTbdPageShowsTheDevelopersNextToTheInterval`, `TestTbdPageSaysThePullRequestsAreNotCollectedYet`, `TestTbdPageRefusesDevelopersOfOtherProjects`, `TestTbdPageGolden` (goldens `tbd`, `tbd.lead-no-data`, `tbd.lead-not-collected`), `TestTbdPageHasItsHeadingAndTable`, `TestRenderShowsTheMainlineLeadTimeOfEachProject`, `TestRenderTbdPageBeforeThePullRequestsAreCollected`, `TestRenderRefusesABadPullsFile`, `TestRenderShowsTheDevelopersOfEachProject`, `TestRenderShowsNoCommitAuthor`.
- Mutations seen red (14): the share worded as commits, the lower-bound note left out or always there, the cut count left out, the stand-in note always singular or left out, a deviation shown for one pull request, the not-collected cell never shown, the pairing by project or by count not checked, the pull requests not loaded, the file never absent, a bad pulls file ignored, the column after Developers.
- Coverage: `absent`, `Cell`, `deviation`, `counts`, `standInNote`, `LeadCell` and `pairedWithMainline` registered at 100.0, total 99.8. CodeScene: `mainlineleadcell.go`, `mainlineleadcell_test.go` and `render_tbd_lead_test.go` 10.0, new rows; `render.go`, `tbd.go`, `tbd_test.go`, `page.go`, `mainlinelead.go`, `render_tbd_test.go` and `render_leadtime_test.go` 10.0, rechecked.

---

## 2026-10-23 — Mainline Lead Time per project from the merged pull requests ([#256](https://github.com/yveshanoulle/forsgren/issues/256), step 1 of 3)

forsgren issue 256, step 1 of 3, minor release. Nothing on a page changes yet: the TBD page column and its goldens are step 2, the docs and the legend step 3. `metrics.MainlineLeadTimes(projects, data, now)` (`internal/metrics/mainlinelead.go`) gives each project's `MainlineLeadTime` from the merged pull requests of `data/pulls.csv`, which `metrics.Data` now carries as `Pulls` (render loads it in step 2): one lead time per pull request, never per commit (decision #302), its merged time minus its first commit time, the earliest author date of its commits (decision #297), for the pull requests merged in the DORA window (`dora_days`, both ends included) in the project whose config lists the repository, ignoring case. The mean, the sample standard deviation (n-1) and the count; `WithinReference`, the pull requests merged 24 hours or less after their first commit, exactly 24 hours included, and `WithinReferenceShare`, their share in whole percent rounded down (Yves's ruling: the 24-hour reference, no pass or fail verdict); `Cut`, the counted pull requests whose commit list was cut, each lead time a lower bound kept in the mean (decision #299); `CreatedStandsIn`, those whose created time stood in for the first commit time, counted (decision #300). A first commit authored after the merge counts as 0, as lead time for changes counts one.

- Red first: the tests failed at runtime against a stub that returned every project with zero counts (`TestMainlineLeadTimeMeanDeviationAndCount`, `TestMainlineLeadTimeReferenceIsTwentyFourHoursOrLess`, `TestMainlineLeadTimeCountsCutValues`, `TestMainlineLeadTimeStandInUsesTheCreatedTime`, `TestMainlineLeadTimeCountsANegativeOneAsZero`, `TestMainlineLeadTimeCountsThePullRequestsMergedInTheWindow`); `TestMainlineLeadTimesGiveEveryProject` is a pin, green on the stub.
- Mutations seen red (12): exactly 24 hours left out of the reference, cut values left out, the stand-in timed from the empty first commit time, the window ignored, a merge after the render time counted, the population deviation (n) for the sample one, the share rounded to the nearest percent, a negative lead time kept, the cut and the stand-in counts not counted, a repository no project lists counted, a deviation from one pull request.
- Coverage: the eight functions of `mainlinelead.go` registered at 100.0, total 99.8. CodeScene: `mainlinelead.go` and `mainlinelead_test.go` 10.0, new rows; `rows.go` 10.0, its row rechecked.

---

## 2026-10-23 — The release brings the template's pull-requests: read comment to the agreed wording ([#320](https://github.com/yveshanoulle/forsgren/issues/320), step 4 of 4)

forsgren issue 320, step 4 of 4, minor release (one release with #254 and #255, #319); #320 is done. Decision #315: the comment of the `pull-requests: read` line in forsgren-template's `.github/workflows/forsgren.yml` names both reads the permission serves, the merged pull requests for Mainline Lead Time (from 1.15.0) and the page footer's waiting Dependabot pull request; the permission is unchanged. Nobody commits to the template by hand, so the release's own template step writes it: `Scripts/release_pins.sh rewrite workflow` replaces the comment of any `pull-requests: read` line with `PR_READ_COMMENT`, in the same commit as the pins and the README, whatever the comment said before. The template's `forsgren.yml` is the kind `caller`, a workflow file that must have that line: without it the step stops red before anything is written, naming the file and the missing line, as for a missing pin (a failed operation fails, never skips). Every other line stays byte for byte the same, a second run changes nothing, the update workflow's `pull-requests: write` line and the metrics installation's pin pull request (the `pins` kind) keep their comments. `Scripts/test_release_pins.sh` pins it, with three new mutation proofs (no comment rewrite; a rewrite right once but not stable; no check of the line). forsgren-metrics' `forsgren.yml` holds the line with the old comment today; its pin pull request (the `pins` kind) neither needs the line nor changes it. `docs/updating-and-releases.md` says so under the template step.

## 2026-10-23 — The pull requests ship in 1.15.0, a cut repository's summary names its pull requests, and the docs carry the rulings ([#320](https://github.com/yveshanoulle/forsgren/issues/320), step 3 of 4)

forsgren issue 320, step 3 of 4, minor release (one release with #254 and #255, #319, over #316). `internal/needs/needs.yml` declares `pull-requests: read` from 1.15.0 (it said 1.16.0), and `docs/updating-and-releases.md` has the note as Upgrading to 1.15.0, with a paragraph for #254 (commits format v3, decision 293; the first-parent chain at the committer date, the old approximation named in the cell, decision 294). Decision #327 (A): the run summary's words for a repository cut short as a whole are `issues and pull requests not read` (`cutWords`); the report's `issues=unread` field is unchanged.

- The docs: `updated_at` is a snapshot of the first read, never the latest update, and the pulls read mark alone decides where the read resumes, moving only after the store (#304, #308); `first_commit_cut` and `created_stands_in` are permanent quality marks of that record (#306); cut versus a budget interruption in Yves's words from #255 (#308); the count of merged pull requests is those newly stored by the run (#311); the setup issue cannot see a fine-grained token's permission and never claims the pull request read works, as a known limit of the setup issue and in the configuration, the token, the upgrade note and the installation README (#314); a budget stop in the pull requests reported as incomplete on a `pulls-cut` line, never failed, with the summary's words in `docs/configuration.md` and `docs/ci.md` (#307); the page-limit read incomplete, older pull requests possibly skipped for good (#309); the two stand-in cases, an unreadable commit page's warning naming the repository and the pull request, and a server error, a rate limit or a 403 never a stand-in (#313); the cut report's example and bullets with the `pulls-cut` line and the incomplete status; the branch name not read by collect (#322).
- Red first, seen failing at runtime: `TestFromTheMergedPullRequestsReleaseTheCallerGrantsPullRequestsRead` (no pull-requests need in 1.14.0, the need from 1.15.0; the old file gave none in 1.15.0), `TestRunSummaryNamesWhatTheBudgetCutShort` and the after-a-cut-repository case of `TestRunSummaryNamesARepositoryWhosePullRequestsWereCutShort` (the old words `issues not read`).
- Mutations seen red: the need at 1.14.0 (asked for in 1.14.0, and not the 1.15.0 need), the need at 1.16.0 and the old summary words (both the red itself).
- CodeScene: `cmd/forsgren/collected.go`, `cmd/forsgren/summary_collected_test.go` and `internal/needs/needs_test.go` at 10.0, their rows unchanged. Coverage: total 99.8, no floor changed.

---

## 2026-10-23 — A budget stop in the pull requests is incomplete in the collect report, and collect's pull request warnings say what was lost ([#320](https://github.com/yveshanoulle/forsgren/issues/320), step 2 of 4)

forsgren issue 320, step 2 of 4, minor release (one release with #254 and #255, #319). The rulings on the decision issues of #255, built into collect and the client; the docs follow in step 3.

- Decision #307 (Yves chose B): a repository whose deployments and issues were stored whole but whose pull requests the request budget stopped is incomplete, never failed. The collect report has a new line kind, `pulls-cut <repository>`, after the `cut` lines and before the `failed` ones (`Report.PullsCut`); the status line is `incomplete resets=<UTC>` when any repository or its pull requests were cut short (`Report.incomplete`, which `closeReport` also asks before it sets the reset time). `endPulls` adds the repository (`reportPullsCut`); it is not counted as cut short in the run's tally, so the one-time catch-ups still finish for it, as its issues were read whole. The run summary's Collected line names it in the budget part, after the repositories cut short: `acme/app pull requests cut short (deployments and issues read)` (`budgetWords` in `cmd/forsgren/collected.go`). `parseLine` reads the three line kinds from one table (`lineKinds`) and `Cut.line` writes a cut line.
- Decisions #304 and #308: verified, no code change. The pulls read mark moves only after `pulls.csv` was appended to, and a budget stop moves no mark, so the pull request it interrupted is read by the next run; pinned by `TestAPullRequestTheBudgetInterruptedIsReadByTheNextRun`.
- Decision #310: verified, no code change. A pull request merged before `history_days` back is skipped and the read goes on by updated time; pinned by `TestAnOldMergeIsSkippedAndTheReadGoesOn`.
- Decision #309: the page-limit warning now says `the pull request read is incomplete: only the newest N page(s) were read, and older pull requests may be skipped for good, since the read mark moves on`.
- Decision #313: the client's `FirstCommitTime` wraps the new `github.ErrNoCommitDate` (with `ErrAnswer`) for no commit or a commit without an author date; a page it cannot read is `ErrAnswer` alone. Collect has the created time stand in for both, with the warning it had for a missing date and, for an unreadable page, `collect: <repo>: pull request <n>: the answer for its commits is malformed or unreadable: ...`. A rate limit, a 403, a server error and the other errors keep their handling: a server error on the commits fails the repository, never a stand-in.
- Decision #322 (B): `ClosedPullRequest.HeadBranch`, its JSON field and its completeness check are gone; a closed pull request without `head.ref`, empty or absent, is read.
- Red first, seen failing at runtime (stubs: `Report.PullsCut` and `github.ErrNoCommitDate` declared, unused): the report's file and read-back with a `pulls-cut` line and a report incomplete for the pull requests alone, the budget test expecting `acme/app` in the report with the reset time, the run summary's two cases, the page-limit warning's words, the unreadable commit page's warning, `ErrNoCommitDate` on a missing date, and a pull request without a head branch read.
- Pins, green from the start, each with a mutation seen red: the interrupted pull request read next run, an old merge followed by one in the window, a server error on the commits failing the repository, a missing date never called unreadable, an unreadable page never `ErrNoCommitDate`.
- Mutations seen red (14): the budget stop not reported, no reset time for a pulls-only cut, a pulls-only report written complete, the run summary leaving it out, the budget stop moving the mark, the mark moving before the store, an old merge ending the read, the old page-limit warning, a missing date given the unreadable warning, an unreadable page given the missing-date warning, a server error standing in, `ErrNoCommitDate` dropped from a commit without an author date, an unreadable page wrapped as `ErrNoCommitDate`, and `head.ref` required again.
- Coverage: `budgetWords`, `Report.incomplete`, `Cut.line` and `reportPullsCut` registered at 100.0, total 99.8. CodeScene: every changed Go file at 10.0, `cmd/forsgren/collected.go` lifted from 9.92, and a row for the new `internal/collect/pulls_interrupt_test.go`.

---

## 2026-10-23 — `data/pulls.csv` stores no head branch, and its stand-in rule holds on read and on write ([#320](https://github.com/yveshanoulle/forsgren/issues/320), step 1 of 4)

forsgren issue 320, step 1 of 4, minor release (one release with #254 and #255, #319). The pulls format v1 is not released yet, so it changes in place: its column line is now `repository,number,created_at,merged_at,merge_commit,updated_at,first_commit_at,first_commit_cut,created_stands_in`. No head branch is stored (Yves's ruling on decision #305: a branch name can identify people, and no metric uses it): `history.PullRequest` has no `HeadBranch` and no check of it, and collect copies none. The client, `github.ClosedPullRequests`, still reads `head.ref`. The stand-in rule (Yves's ruling on decision #303): `created_stands_in` `true` has an empty `first_commit_at`, `false` a valid author date, and any other line is refused, as `ErrMalformed` naming the line when the file is read and as `ErrInvalidRecord` when a record is written. Step 3 of #255 already enforced it both ways, in the one record check that reading and writing share; the read of a line with neither a stand-in nor a time had no test, and now has one. `docs/data-files.md` and CLAUDE.md say both.

- Red first, seen failing at runtime: the pulls tests of `internal/history` and `internal/collect` expecting the column line and lines without `head_branch` (the old code refused every record for its empty head branch or wrote the old line), and the new `TestAStandInThatDisagreesWithTheFirstCommitTimeIsNotRead`, both directions on read; the stand-in rule needed no new code, so its directions are proved by mutations, not by a red of their own.
- Mutations seen red: the rule weakened to only a stand-in without a time (the write and the read of a line with neither fail naming the rule), to only a time without a stand-in (the write and the read of a line with both fail naming it), a head branch field written back, and `head_branch` back in the column line.
- Coverage: the floors of `pulls.go` stay at 100.0, total 99.8. CodeScene: `internal/history/pulls.go`, `internal/history/pulls_test.go`, `internal/collect/pulls.go` and `internal/collect/pulls_test.go` at 10.0, their rows unchanged; `coverage_thresholds.json` and `codescene-scores.json` need no change.

---

## 2026-10-23 — the data guard, the setup issue and the docs know the merged pull requests ([#255](https://github.com/yveshanoulle/forsgren/issues/255), step 5 of 5)

forsgren issue 255, step 5 of 5, minor release; #255 is done. The data guard (`Scripts/check_data_guard.sh`) has arms for `pulls.csv` and `pulls_read.csv`, so either file outside `testdata/` blocks the commit. Its self-test's drift check, which reads the data file constants of `internal/collect`, now reads a constant inside a `const (` block too: `PullsFile` and `PullsReadFile` are declared that way, and the single-line form alone missed them. `internal/needs/needs.yml` declares, from 1.16.0 (1.15.0 since #320 step 3, one release with #254, #319), `pull-requests: read` on the forsgren job of `.github/workflows/forsgren.yml`, so the setup issue names a caller without it; a missing grant still never stops or fails the collection (Yves's ruling on #255). The template's calling workflow already grants it. The docs: `docs/data-files.md` describes both files, every column, the first commit time definition of decision #298, what cut and stand-in mean, the collect behaviour and the token's Pull requests (read); `docs/configuration.md`, `install/README.md` and `agent-installer.md` name the permission; `docs/updating-and-releases.md` has the 1.16.0 upgrade note (1.15.0 since #320 step 3); `docs/development.md` lists the two files under the data guard.

- Red first, seen failing at runtime: the data guard self-test (the drift check naming `pulls.csv` and `pulls_read.csv` unguarded, a new case 16 with both files outside `data/`, and its two arm-deleted mutation proofs), and `TestFromTheMergedPullRequestsReleaseTheCallerGrantsPullRequestsRead` in `internal/needs/needs_test.go` (no such need in 1.16.0; 1.15.0 since #320 step 3).
- Mutations seen red: the need introduced in 1.15.0, at `write`, under a misspelled permission; each of the two arms deleted (the self-test's own proofs); the drift check back to its single-line form, which no longer sees the two constants.
- No Go code outside tests changed: coverage and CodeScene rows stay as they were.

---

## 2026-10-23 — collect stores the merged pull requests ([#255](https://github.com/yveshanoulle/forsgren/issues/255), step 4 of 5)

forsgren issue 255, step 4 of 5, minor release. The docs, the data guard, the caller workflow and the template are step 5. After a repository's deployments and issues are stored, collect reads its merged pull requests into `data/pulls.csv` (`internal/collect/pulls.go`). The read is incremental by updated time: it asks for the closed pull requests updated since the repository's mark in the new `data/pulls_read.csv` (the pulls read format v1, `# forsgren pulls read v1`, `repository,read_at`, a mark file like `failures_read.csv`, decision #304) less a day, never before `history_days` back, and `history_days` back on the first run. A pull request closed without a merge, merged before `history_days` back or already stored is not asked for its commits and not stored (the first line stays, decision #306). Each other one gets its first commit time from its commits; a commit list cut at the page limit or at GitHub's 250 commits keeps its earliest author date with `first_commit_cut` (#299), and one that gives no usable date (no commit, or a commit without an author date) has the created time stand in, `created_stands_in`, named on stderr (#300, #301). A pull request's commits are read only while the request budget has room for all their pages (3 at most). A missing `pull-requests: read` never stops or fails the collection (Yves's ruling on #255): the pull requests read so far are stored, the mark stays and stderr names the permission. The same goes for a stop at the request budget, so the next run reads the rest. Neither marks the repository cut short, since its deployments and issues were stored whole. A list cut at the page limit is named on stderr and the mark moves. Any other error fails the repository, after its deployments and issues are stored. The stdout line ends with `, <p> merged pull requests` when it stored any. A `pulls.csv` or `pulls_read.csv` that cannot be read refuses the run before GitHub is asked.

- Red first, seen failing at runtime against stubs (`LoadPullsRead` and `SavePullsRead` reading and writing nothing, collect not calling the pull requests): eleven new tests in `internal/collect/pulls_test.go` (merged, unmerged, no commits and an undated commit; the read position with no mark, a mark, a mark older than `history_days` and a pull request merged before it, each stopping on page 1; a stored pull request not read again; a cut commit list; a cut list; a 403 on the list and on a commit list; the request budget; a wrong answer; an unreadable and an unwritable file) and the `pulls_read.csv` row of the mark file round trip. The fakes list no pull requests by default.
- Mutations seen red, 17: an unmerged or an old pull request stored, a stored one read again, the mark not capped at `history_days`, no overlap, no stand-in, the cut flag dropped, a 403 or a budget stop failing the repository, no budget reserve, a cut list keeping the mark, no report count, the mark not moved, the pulls file not loaded, the pulls error or the write error swallowed, and the mark file's version line.
- Coverage: the ten functions of `pulls.go`, the two of `pullsread.go` and `loadFiles` registered at 100.0. CodeScene: `pulls.go`, `pulls_test.go` and `pullsread.go` at 10.0, rows added; `collect.go` stays at 9.68, `failuresread.go` at 10.0.

---

## 2026-10-23 — `data/pulls.csv`, the merged pull requests format v1 ([#255](https://github.com/yveshanoulle/forsgren/issues/255), step 3 of 5)

forsgren issue 255, step 3 of 5, minor release. Nothing writes the file yet: collect is step 4, the docs step 5. The new `internal/history.PullRequest` (`pulls.go`) is one line of `data/pulls.csv`, the pulls format v1: `# forsgren pulls v1`, then the column line `repository,number,created_at,merged_at,merge_commit,updated_at,first_commit_at,first_commit_cut,created_stands_in` (as forsgren#320 step 1 left it: this step also had `head_branch` after `number`, dropped before any release, decision #305), on the shared append-only CSV layer like the other history files. Only merged pull requests are stored (#256): a merged time and a merge commit SHA are required, so one closed without a merge is refused. No title and no author is stored. `first_commit_at` is the earliest git author date of the pull request's commits (#298); `first_commit_cut` says the commit list was cut (#299: 250 commits or more, the page limit or the request budget), the time kept as a lower bound; `created_stands_in` says the commit list gave no usable date (#300), and then `first_commit_at` is empty and the created time stands in, never because the list was cut, so a line is never cut and standing in at once. `LoadPullRequests` reads the file in order; `AppendPullRequests` creates it or appends only the pull requests it does not hold (key: `IssueKey`, repository ignoring case and number, as GitHub numbers issues and pull requests from one sequence), the first line staying whatever a later read says, the new lines in merge order (merged time, repository, number). Every time is UTC to the second; an unknown version, a malformed line (named by its number) and a record that cannot be stored (`ErrInvalidRecord`) are refused before anything is written, by Append's rules.

- Red first, seen failing at runtime against a stub that stored and read nothing: six new tests in `internal/history/pulls_test.go` (the file created with its exact lines and a held pull request, in another case, not written again; a complete, a cut and a standing-in first commit time written and read back; merge order; fifteen records refused, each by its reason; nine malformed lines, each named by line and reason; another version refused, the file untouched).
- Mutations seen red: the key keeping the repository's case, a held pull request revised, the order by number instead of merged time, the two flags swapped, an empty first commit time written as a zero time, an empty one read as malformed, the parse errors ignored, any flag text read as false, each of the eleven record checks dropped, and the version line changed.
- Coverage: the eight functions of `pulls.go` registered at 100.0. CodeScene: `pulls.go` and `pulls_test.go` at 10.0, rows added.

---

## 2026-10-23 — the client reads a pull request's first commit time ([#255](https://github.com/yveshanoulle/forsgren/issues/255), step 2 of 5)

forsgren issue 255, step 2 of 5, minor release. Nothing is stored and collect does not call it yet: `data/pulls.csv` is step 3, collect step 4. The new `internal/github.FirstCommitTime` (`pullcommits.go`) reads a pull request's commits, `GET /repos/{owner}/{repo}/pulls/{number}/commits`, 100 per page, every page up to the limit, and gives its first commit time for Mainline Lead Time (merged time minus first commit time, #256): the earliest git author date (`commit.author.date`) of the commits read, in UTC. The author date is when the commit was made, #256's "commit creation"; the committer date is not read, since a rebase or a merge button moves it. The earliest one, not the first of the list, since a rebase can put an older commit later. GitHub lists at most 250 commits of a pull request, so 250 commits read is a cut answer, the first commit possibly left out, as is a next page left unread at the page limit; the caller decides what a cut answer counts as. A 403 is `ErrAccess` and `ErrPullRequestsDenied` by `explainDenied`; GitHub's rate limit stays `ErrRateLimit`. A pull request with no commit, or a commit with no author date, is `ErrAnswer` naming the path and the pull request, never a zero time; the created time standing in for a commit list that could not be read (#256) is the caller's. Every request goes through the client's request budget like every other call.

- Red first, seen failing at runtime against a stub that returned a zero time: five new tests in `internal/github/pullcommits_test.go` (two pages, the earliest author date on the second, in another offset, with committer dates earlier still, from the new fixture `testdata/pull-commits.json`; 249 commits complete and 250 cut; the page limit; the missing permission and the rate limit told from it; no commits and no author date refused), and the new `first commit time` row of `calls`, which runs it through the margin, malformed JSON, refusal and repository name tests.
- Mutations seen red: `explainDenied` dropped, the committer date read instead of the author date, the first commit of the list instead of the earliest, the time not in UTC, the cap check dropped, the cap at more than 250 instead of 250 or more, the page limit's cut ignored, the no-commits refusal dropped, and the author date check dropped.
- Coverage: `FirstCommitTime`, `page` and `result` of `pullcommits.go` registered at 100.0. CodeScene: `pullcommits.go` and `pullcommits_test.go` at 10.0, rows added; `fake_test.go` and `client_test.go` unchanged at 9.68.

---

## 2026-10-23 — the client reads a repository's closed pull requests ([#255](https://github.com/yveshanoulle/forsgren/issues/255), step 1 of 5)

forsgren issue 255, step 1 of 5, minor release (Yves's ruling of 2026-10-22 on the issue). Nothing is stored and collect does not call it yet: the first commit time is step 2, `data/pulls.csv` step 3, collect step 4. The new `internal/github.ClosedPullRequests` (`closedpulls.go`) lists a repository's closed pull requests updated at or after a time, newest updated first: `GET /repos/{owner}/{repo}/pulls?state=closed&sort=updated&direction=desc`, 100 per page, up to the page limit, and says whether it stopped there. GitHub's pull request list has no `since` filter, so the read ends at the first pull request updated before the time, which is left out, as the deployments and releases end at their window (`keep`). Each `ClosedPullRequest` has its number, its head branch (`head.ref`), its created, merged and updated time in UTC and, when it was merged, its merge commit SHA. One closed without a merge is read too, with no merge time and no merge commit: GitHub still names a `merge_commit_sha` for it, a test merge that never landed, which is not read. No title, body or author is read. A 403 is the token missing `pull-requests: read`, `ErrAccess` and `ErrPullRequestsDenied` by `explainDenied`, as for the open pull requests; GitHub's rate limit stays `ErrRateLimit`. A pull request with no number, head branch, created or updated time, or merged without a merge commit SHA, is `ErrAnswer` naming the path. Every request goes through the client's request budget like every other call.

- Red first, seen failing at runtime against a stub that returned nothing: six new tests in `internal/github/closedpulls_test.go` (two pages read with the query, a merged and an unmerged pull request from the new fixture `testdata/closed-pulls.json`, a merge time in another offset; the read ending at the first one updated before since with no next page asked for; the page limit; the missing permission; the rate limit told from it; six answers it cannot store), and the new `closed pull requests` row of `calls`, which runs it through the margin, malformed JSON, refusal and repository name tests.
- Mutations seen red: `explainDenied` dropped, the since stop dropped, an unmerged pull request keeping GitHub's test merge SHA, the merge commit SHA check dropped, `sort=updated` dropped, the merge time not in UTC, and each of the four completeness checks dropped.
- Coverage: `ClosedPullRequests`, `readClosedPulls`, `toClosedPullRequest` and `complete` registered at 100.0. CodeScene: `closedpulls.go` and `closedpulls_test.go` at 10.0, rows added; `fake_test.go` unchanged at 9.68.

---

## 2026-10-23 — the legend and the docs say the Mainline Interval follows the first-parent chain at the committer date ([#254](https://github.com/yveshanoulle/forsgren/issues/254), step 5 of 5)

forsgren issue 254, step 5 of 5, minor release; #254 is done. The wording an installation reads now says what step 4 counts. The legend's TBD section: the interval is the time between commits landing on the main branch, by their committer date, and a gap is between two neighbours by committer date; a new paragraph says only each deployment's first-parent chain counts, the commits a merge brought in are left out and the merge commit counts, and what the committer date is next to the author date; a second new paragraph explains the old approximation (commits stored before forsgren kept their parents and committer date, and chain commits without a committer date, at their author date), how the cell names them (`· 3 commits timed by author date`, `1 commit timed by author date`) and that the note stays until those deployments leave the window. The read-together line says how often the deployed commits landed on the main branch, by committer date. Developers now says it counts the people who made the commits deployed in the window, those a merge brought in included (decision 294, point 3), no longer "the commits it counts", which step 4 made untrue.

- `docs/pages-and-views.md`, The TBD page: the cell with its note, and new bullets The first-parent chain (the tip, each first parent while it is one of the deployment's commits, merges' other parents left out, the chain judged before a commit is counted once), The committer date and The old approximation (a deployment without exactly one tip, a one-commit deployment stored before v3, never looked up again, decision 293, the note); The gaps by the time a commit is placed at; Developers no longer limited to the chain; the Later line by committer date.
- `docs/configuration.md` (`tbd_page`) names the first-parent chain at the committer date; `docs/data-files.md` (`parents`) says the Mainline Interval follows the first parents and links the TBD page. The README and the installation README do not describe the Mainline Interval, so they are unchanged.
- Red first, seen failing at runtime against the step 4 legend: `TestLegendExplainsTheTbdPage` (eleven new or changed sentences in `legendTbdText`) and the new `TestLegendRetiresTheAuthorDateWording` (`legendTbdRetired`: by their author date, next to each other by author date, were made by author date, who made the commits it counts), both through the new helper `legendTbdSection`. Golden: `internal/page/testdata/legend.golden.html`, regenerated with `go test ./internal/page/ -update`.
- Mutations seen red: the interval back to author date, the gaps by author date, the first-parent paragraph dropped, the old approximation paragraph dropped, the singular note lost, Developers back to the commits it counts, the read-together line back to author date.
- Coverage: no new production function. CodeScene: `legend_tbd_test.go` at 10.0.

---

## 2026-10-23 — the Mainline Interval counts first-parent commits at their committer date ([#254](https://github.com/yveshanoulle/forsgren/issues/254), step 4 of 5)

forsgren issue 254, step 4 of 5, minor release. The Mainline Interval on the TBD page now reads the lineage collect stores: of each deployment's commits, only those of its first-parent chain count, each placed at its committer date, when it landed, instead of its author date. The commits a merge brought in through its other parents are left out. The deployments stored before the commits format v3 keep the old approximation, every commit counted at its author date, and the cell names them: `2 d 22 h ± 4 d 3 h (2) · median 2 d 22 h · p90 - · 3 commits timed by author date`. The legend and the docs follow in step 5.

- `internal/metrics/lineage.go` (new): per deployment (`keyOf`), the tip is the one commit no other commit of the deployment names as a parent (`tipOf`, `namedParents`): a comparison with the deployment before it gives every commit reachable from the deployed commit and not from the one before, so the deployed commit is the only one. `firstParentChain` follows each first parent from the tip while it is one of the deployment's commits. `lineage.place` says whether a commit counts and when: a chain commit at its committer date, or at its author date when GitHub gave none (never the zero time); a commit off the chain not at all; a commit of a deployment without exactly one tip at its author date. A deployment stored before v3 has no parents, so with two commits or more it has as many tips; its only commit, when it has one, is its own chain without a committer date, at its author date all the same.
- `MainlineIntervals` judges the chain before `distinctInWindow` counts a commit once, so a branch copy of a commit does not use up the copy another deployment has on its chain. `MainlineInterval.ByAuthorDate` counts the commits placed at their author date, `MainlineInterval.Note` names them (`1 commit timed by author date`, `2 commits timed by author date`), and `Cell` adds it after the cells' separator.
- Developers is unchanged: it still counts the authors of every distinct deployed commit of the window, those a merge brought in included; only its comments say so now.
- Red first, seen failing at runtime against stubs (`lineageOf` empty, `place` counting every commit at its author date, `Note` empty): seven tests in the new `internal/metrics/mainline_lineage_test.go` (a merged deployment with a two-commit branch, the old approximation, both kinds of deployment mixed, a chain commit without a committer date, two tips, the chain judged before the commit is counted once, the note), `TestRenderMainlineIntervalFollowsTheStoredLineage` through a v3 commits file, and the four TBD cells of the render tests over `acmeCommits`, which have no lineage and now end with the note. The metrics fixture `authored` gives each commit its own deployment and a parent, so the earlier Mainline Interval tests run on a known lineage with the committer date equal to the author date.
- Mutations seen red: a branch commit counted, the last parent followed instead of the first, the author date taken for a chain commit, the old rows not named, the zero committer date used as the time, the first of several tips taken, the commit counted once before the chain is judged, no note in the cell, the singular note lost.
- Coverage: six new functions at 100%, total 99.8%. CodeScene: `lineage.go` and `mainline_lineage_test.go` at 10.0, rows added; `mainline.go`, `mainline_test.go`, `developers.go`, `render_tbd_test.go` and `render_leadtime_test.go` at 10.0.

---

## 2026-10-23 — collect stores each commit's parents and committer date ([#254](https://github.com/yveshanoulle/forsgren/issues/254), step 3 of 5)

forsgren issue 254, step 3 of 5, minor release. `collect` now fills the two v3 columns of `data/commits.csv`: `deployed` (`internal/collect/commits.go`) copies each compared commit's parents as `Compare` read them, in GitHub's order, the first parent first, and its committer date in UTC cut to the whole second (`wholeSecond`, which the failure issues already used; the author date now goes through it too). A commit GitHub gives no committer date for is stored with an empty `committed_at`, never the author date. No page changes yet (step 4).

- Commits stored before v3 keep their empty parents and committer date on a later collect: a deployment already stored is never compared again (its statuses are not read, and `fresh` leaves it out), so nothing is looked up again, and the held rule of `AppendCommits` keeps a stored line as it is. The file is still rewritten once as v3. Stored history stays stable; step 4 names the commits without parents as the old approximation.
- Red first, seen failing at runtime against the step 2 code: `TestCollectStoresEachCommitsParentsInOrderAndItsCommitterDate` (a merge whose first parent sorts after its second, a committer date given in CEST with half a second, a commit without a committer) and `TestACommitStoredBeforeV3KeepsItsEmptyParentsOnALaterCollect` (a v2 file whose held commit stays empty while the new deployment's commit is filled, the stored deployment not compared again, the file rewritten as v3), both in the new `internal/collect/commits_lineage_test.go`. The fake comparison answer (`comparisonOf`, `lineage`) now gives parents and a committer only when a test names them, so the other tests' commits have none.
- Mutations seen red: the parents sorted, the parents reversed, the parents dropped, the committer date dropped, the author date taken for a missing committer date, the committer date not cut to the second (the append refuses it), and the held deployments read and compared again (both guards removed together; either one alone still keeps them out).
- Docs: `docs/data-files.md` describes the `parents` and `committed_at` columns, their order, separator and empty meanings, and the one-time upgrade of v1 and v2 files; CLAUDE.md.
- Coverage: no new function; total 99.8%. CodeScene: `internal/collect/commits.go`, `commits_test.go` and the new `commits_lineage_test.go` at 10.0, a row added for the new file.

---

## 2026-10-23 — the commits format v3 with each commit's parents and committer date ([#254](https://github.com/yveshanoulle/forsgren/issues/254), step 2 of 5)

forsgren issue 254, step 2 of 5, minor release. The format only: `collect` does not fill the new columns yet (step 3), and no page changes (step 4). `data/commits.csv` is now the commits format v3, v3 and not the v2 the issue named, since #273 made v2: two columns after `author`. `parents` holds the SHAs of the commit's parents in the order they were given, the first parent first, parted by one space, as git lists them; empty means none known (a commit stored before v3, or a root commit, which a comparison of two deployments does not reach). `committed_at` is the git committer date in UTC, empty when unknown; never the author date in its place. `history.Commit` has `Parents` and `CommittedAt`. Only SHAs are accepted as parents (so no parent can hold the separator) and only whole seconds as the committer date; the key and the held rule are unchanged, neither column is part of the key.

- v1 and v2 files: `LoadCommits` reads both as they are (`commitsV1`, `commitsV2`, the format's `legacy` versions from #273), a v2 file keeping its authors, the parents and committer date empty. `AppendCommits` to either rewrites it once as v3, also with nothing new to store, every line kept with the columns it lacks empty, through `upgrade` and `replaceWhole` as #273 built them. A v4 file and a malformed line are still refused untouched. `history.Commit` holds a list now, so tests compare commits with `reflect.DeepEqual` (`sameCommit` in `internal/collect`'s tests).
- Red first, seen failing at runtime with only the two fields stubbed: the existing commits tests on the v3 header and lines (v3 files refused as an unknown version, a created file still v2), the new `commits_lineage_test.go` (`TestCommitsKeepTheParentsInOrderAndTheCommitterDate`: a merge whose first parent sorts after its second, a committer date given in CEST; the v2 upgrade with and without a new commit; malformed parents and committer dates refused with their line; parents and a committer date that cannot be stored refused; the first parents of a held commit kept), and `TestCollectStoresDeploymentsAndSaysHowMany` on the v3 header. The compatibility pins (`TestLoadCommitsReadsAV2FileWithNoParents`, `TestAV2FileThatIsMalformedIsRefusedUntouchedOnAppend`) passed before the change, as they must.
- Mutations seen red: the parents sorted, the parents reversed, the author date taken for a missing committer date, the committer date required, no v2 legacy entry, the v2 lift losing the author, an empty parents column read as one empty parent, the parent check dropped, the committer date's whole-second check dropped, a zero committer date written as a time, the committer date made part of the key, the read error ignored before the upgrade.
- Docs: the `Commit` comment, the package comment and CLAUDE.md; `docs/data-files.md` describes what collect stores and changes in step 3, when the columns are first filled.
- Coverage: `parentsOf` and `isNotSHA` registered at 100.0. CodeScene: `commits.go`, `commits_test.go`, the new `commits_lineage_test.go`, `history.go` and `internal/collect/commits_test.go` at 10.0, a row added for the new file; `internal/collect/cutshort_test.go` (9.38) and `cmd/forsgren/collect_test.go` (9.68) unchanged by their one-line edits.

---

## 2026-10-23 — the FBP push-or-rebase self-test names main on its bare origin and reads no built-in git config ([#292](https://github.com/yveshanoulle/forsgren/issues/292), step 1 of 1)

forsgren issue 292, step 1 of 1, tools. Quality was red on GitHub's hosted Mac since #283 step 1: `Scripts/test_fbp_push_or_rebase.sh` failed there (the git row ✅ instead of the ⚠️ rebase row, origin without the incoming commit, then an abort on `ambiguous argument 'HEAD'`), while it passed on a Mac with Apple's git. The cause: the fixture made its bare origin with `git init --bare` and git's default branch. Apple's git reads a built-in gitconfig of its own (Xcode's `share/git-core/gitconfig`, `init.defaultbranch=main`) that `GIT_CONFIG_SYSTEM=/dev/null` does not turn off, so there the origin's HEAD was main; the hosted runner's Homebrew git (2.56.0) has no such file, so its origin's HEAD was an unborn master. The "other" clone then checked out nothing, its incoming commit was a root commit on master, its `git push origin main` was refused (its stderr was silenced), and the remote never moved: the local push was an ordinary fast-forward. In the same-file case the incoming commit failed altogether, so the clone had no HEAD.

- Red first: the fixture now also sets `GIT_CONFIG_NOSYSTEM=1`, which turns off Apple's built-in file, so the hosted condition is the local one; the self-test then failed locally with the four hosted lines.
- Green: the bare origin is made with `git init --bare -b main`, so no case depends on git's default branch.
- Not changed: the other self-tests that make a bare origin without `-b` (`test_fbp_no_push.sh`, `test_gate_select.sh`, the two git sandbox isolation tests) never clone their origin, so its HEAD is never read, and they are green on the hosted Mac.

---

## 2026-10-23 — Compare reads each commit's parents and committer date ([#254](https://github.com/yveshanoulle/forsgren/issues/254), step 1 of 5)

forsgren issue 254, step 1 of 5, minor release. Nothing is stored and no page changes yet: storing is steps 2 and 3, the Mainline Interval over first-parent commits by committer date is step 4. `internal/github.Compare` now reads two more fields from the comparison answer it already fetches, onto `github.Commit`: `Parents`, the SHAs of the commit's parents in GitHub's order, the first parent first (the line a merge was made on, then the line it brought in), none for a root commit, and `CommittedAt`, the git committer date (`commit.committer.date`) in UTC, which a rebase or the merge button sets. GitHub's schema lets the committer be null, so a commit without a committer date is still read, with a zero `CommittedAt` (unknown), never the author date in its place; a parent with no SHA, or one that is not a SHA, refuses the answer as a commit without a SHA does. The commits format version for steps 2 and 3 is v3, not the v2 the issue named: #273 already made commits.csv v2 (the author login), so v1 and v2 files keep loading.

- Red first, seen failing at runtime against the two fields stubbed: `TestCompareReadsTheCommitsOldestFirst` (the made-up compare answer's parents and its committer dates, a day after the author dates), `TestCompareReadsTheParentsInOrder` (a merge commit with two parents, its second parent below its first in SHA order; a root commit with none; a single parent), `TestCompareReadsTheCommitterDate` (a later committer date in another offset, a null committer, no committer, a committer with a null date) and two new rows of `TestCompareRefusesAnAnswerItCannotStore` (a parent not a SHA, a parent with no SHA).
- Mutations seen red: the parents reversed, the two parents sorted, the author date taken for the committer date, the author date taken when the committer date is missing, the committer date not in UTC, and the parent SHA check dropped.
- Docs: the `Commit` comment and CLAUDE.md; `docs/data-files.md` describes what is stored and is unchanged until step 3.
- Coverage: `answerCommit.login` and `answerCommit.parents` registered at 100.0. CodeScene: `compare.go`, `compare_test.go` and the new `compare_lineage_test.go` at 10.0, a row added for the new file.

## 2026-10-23 — the Developers column on the TBD page, next to the Mainline Interval ([#273](https://github.com/yveshanoulle/forsgren/issues/273), step 3 of 3)

forsgren issue 273, step 3 of 3, minor release; #273 is done. The TBD page has a second column, Developers, next to the Mainline Interval: each project's `Developers.Cell` (`internal/metrics/developers.go`), the count of distinct human GitHub logins of the commits the Mainline Interval counts, then the note after ` · ` when commits without a known author were left out, as the recovery cell names its recoveries not completed yet: `3`, `1 · 1 commit without a known author is not counted`, `12 · 2 commits without a known author are not counted`; a project with no counted commit reads `0`, a count, not a dash. Render sets `Data.Developers` from `metrics.MainlineDevelopers`; the template ranges over `Data.TbdRows()` (`internal/page/tbd.go`), which pairs each Mainline Interval with the Developers of its project and fails the render when they are missing, one too many, or name another project in a row, never a count in the wrong row. The legend's TBD section explains the column: the distinct GitHub accounts of the authors, a person counted once across email addresses, a bot account (login ending in [bot]) left out with its commits, a commit whose author GitHub links to no account not guessed and named in the cell, 0 for no counted commit, the page never shows who the developers are, and the interval is not divided by it. The page's meta description reads "Trunk-based development: the Mainline Interval and the developers per project". No page shows a login (decision 274).

- Red first, seen failing at runtime against stubs (`Developers.Cell` returning "", `Data.TbdRows` returning no rows and no error) with the goldens already updated: `TestDevelopersCell`, `TestTbdPageShowsTheDevelopersNextToTheInterval`, `TestTbdPageRefusesDevelopersOfOtherProjects`, `TestLegendExplainsTheTbdPage` (six new sentences), `TestEveryPageCarriesAMetaDescription` (tbd), `TestTbdPageGolden`, `TestLegendPageMatchesGolden`, `TestRenderShowsTheDevelopersOfEachProject` and `TestRenderShowsNoCommitAuthor`, which now also holds that Acme Shop's Developers cell is counted from the one login every commit carries, so the cell a login would reach is on the page.
- Mutations seen red: the length check of `TbdRows` dropped, its project check dropped, the note dropped from the cell, the unknown commits added to the count, the render wiring dropped, the cell dropped from the template, and a login appended to the cell (`TestRenderShowsNoCommitAuthor` finds it in tbd.html).
- Docs: `docs/pages-and-views.md` (The TBD page: the table's two columns, the Developers bullet now on the page, the cell, the pairing; the meta description row), `docs/configuration.md` (`tbd_page`), CLAUDE.md.
- Coverage: `Developers.Cell` and `Data.TbdRows` at 100.0, the total floor raised to 99.7 (measured 99.8). CodeScene: every changed Go file 10.0, rows added for `description.go` and `description_test.go`.

---

## 2026-10-23 — the Developers count per project, bots left out, unknown authors named ([#273](https://github.com/yveshanoulle/forsgren/issues/273), step 2 of 3)

forsgren issue 273, step 2 of 3, minor release. Nothing on a page changes yet: the column, the legend and the page docs are step 3. `metrics.MainlineDevelopers(projects, data, now)` (`internal/metrics/developers.go`) gives each project's `Developers`: over the commits the Mainline Interval counts (the same `distinctInWindow`: deployed in the DORA window, each commit once by repository ignoring case and SHA, in the project whose config lists the repository), `Count` is the number of distinct GitHub logins, compared ignoring case as GitHub does, so one person is one developer across their email addresses. A login ending in `[bot]` (`dependabot[bot]` among them) is no developer and its commits are left out, not unknown. A commit without a login (GitHub links it to no account, or a v1 file stored it) is not guessed: it is counted in `Unknown`, and `Developers.Note` names it, `1 commit without a known author is not counted` or `2 commits without a known author are not counted`, empty when there is none. The result holds counts only, never a login (decision 274).

- Red first: the tests failed at runtime against a stub that returned every project with a zero count and no note (`TestDevelopersCountEachLoginOnce`, `TestDevelopersLeaveBotsOut`, `TestDevelopersNameTheUnknownAuthors`, `TestDevelopersCountTheMainlineCommits`, `TestDevelopersHoldNoLogin`). Mutations seen red: bots counted, an empty author counted as a person, every commit's login counted (the same login twice counted twice), logins compared with case, a login kept on the result, the window ignored, the distinct rule dropped (window kept), the singular note dropped. `TestRenderShowsNoCommitAuthor` is unchanged and still green; it covers the number once step 3 puts it on the page.
- Docs: `docs/pages-and-views.md` (The TBD page: what the number counts, marked not on the page yet), the package comment and CLAUDE.md.
- Coverage: `Note`, `MainlineDevelopers` and `noteAuthor` at 100.0. CodeScene: `developers.go` and `developers_test.go` 10.0.

---

## 2026-10-23 — the commits format v2 with the author's GitHub login ([#273](https://github.com/yveshanoulle/forsgren/issues/273), step 1 of 3)

forsgren issue 273, step 1 of 3, minor release (decision 274, option 1). Nothing on a page changes yet: the Developers count is step 2. `data/commits.csv` is now the commits format v2 and has an `author` column: the GitHub login of the commit's author, empty when GitHub links the commit to no account (its email belongs to no user), a bot as GitHub names it (`dependabot[bot]`; leaving bots out is step 2's job). `internal/github.Compare` reads it from the top-level `author.login` of GitHub's comparison answer, null meaning empty, and never from `commit.author`, which holds the git name and email; `collect` stores it. Only the shape of a GitHub login is accepted when a commit is stored (letters, digits, hyphens, underscores, the `[bot]` suffix), so an email or a name cannot reach the file, and no page shows a login. The key and the held rule are unchanged: the author is not part of the key, a held commit keeps the author it was stored with.

- v1 files: `LoadCommits` reads a v1 file (six columns) as it is, every author empty, and so does `render`. `AppendCommits` to a v1 file rewrites it once as v2, also when it has nothing new to store (collect appends for every repository it stores, so the first such run upgrades it): every line kept with an empty author, then the new lines, written whole through `replaceWhole` (`reach.go`, taken out of `saveReach`, which the mark files already wrote with: a synced temporary file next to it, renamed over the old one), so an interrupted run leaves the old file and a failed write names it and leaves it untouched. Appending v1 lines would lose the author of every new commit, and a file that mixes two column counts could not be read; the authors of the commits stored before are not known and stay empty. The generic CSV layer got `legacy` versions for this (`format.legacy`, `legacyFormat`, `parseAs`, `legacyOf`), so any other file can use it later. An unknown version (v3) and a malformed line are still refused untouched.
- Red first: the new tests failed at runtime against the unchanged format, with only the `Author` fields stubbed (v2 files refused as an unknown version, the header of a created file still v1, no author read or stored, a login not compared or refused), in `internal/history`, `internal/github`, `internal/collect` and `cmd/forsgren` (`TestRenderShowsNoCommitAuthor`: the commits file holds the login, no page of the site shows it). The compatibility pins (a v1 file read by `LoadCommits` and by `render`, a malformed v1 file refused untouched) passed before the change, as they must, and were seen failing by mutation: without the v1 legacy entry, with no upgrade, with the read error ignored; `isLogin` always true fails the refusal test, the author taken from the git name fails `TestCompareReadsTheAuthorsLogin`, collect dropping it fails `TestACommitsAuthorIsStoredAsItsGitHubLogin`. The fixture site (`Scripts/testdata/fixture_site`) keeps its v1 commits file, so the browser and fixture builds read v1 end to end. Docs: `docs/data-files.md` (the v2 format, what the author is and is not, v1 files, collect), `docs/pages-and-views.md` (Privacy), the package comment and CLAUDE.md.
- Coverage: `isLogin`, `parseAs`, `legacyOf`, `upgrade` and `replaceWhole` at 100.0.

---

## 2026-10-23 — a commit that changes only sfl.sh or FBP.sh skips the four browser rows ([#284](https://github.com/yveshanoulle/forsgren/issues/284), step 1 of 1)

forsgren issue 284. `sfl.sh` and `FBP.sh` were in no list of `Scripts/gate_inputs.txt`, so the fail-safe of the browser gate selection ran all four browser rows (about 285 s) on every commit that changed them. Both are now `none|out` rows: they run the browser rows, but no browser gate reads them (neither is in the closure of a browser gate's script), and their effect stays covered by the gate wiring, sfl and FBP self-tests. The scripts #283 added (`Scripts/sfl_pull.sh`, `Scripts/fbp_push_or_rebase.sh`) need no row: they are under `Scripts/` and in no browser gate's closure, so they already select nothing. The fail-safe for a file no list names is unchanged.

- Red first: cases 22 to 24 of `Scripts/test_gate_select.sh` run `gate_select` on the real list in its throwaway repository; on the red, only `sfl.sh` and only `FBP.sh` said `run: ... is named by no gate's list` instead of skipping, for each of the four labels (expectation mismatches only), and a file no list names ran all four (the fail-safe pin, green on both). Then green, with mutation proof K: the real list without the `sfl.sh` row makes the sfl-only commit run the browser gate again, asserting the fail-safe reason.
- Docs: docs/quality-gates.md, docs/development.md, docs/gate-classification.md, the comments of `Scripts/gate_inputs.txt` and `Scripts/lib_gate_select.sh`.

---

## 2026-10-22 — sfl's opening pull rebases when it cannot fast-forward and nothing overlaps ([#283](https://github.com/yveshanoulle/forsgren/issues/283), step 2 of 2)

forsgren issue 283, step 2 of 2, ported from the estate canon. When sfl's opening `git pull --ff-only` cannot fast-forward (local commits not on the remote, typically a local RED commit), `Scripts/sfl_pull.sh` now fetches and asks step 1's `fbp_overlap_files` (sourced from `Scripts/fbp_push_or_rebase.sh`, no second copy) which files the incoming commits changed that the local commits or the staged, unstaged or untracked changes changed too. None: the changes are stashed, the local commits rebased onto the upstream and the stash popped with `--index`, so staged stays staged, and only the stash this run created is popped (the stash ref compared before and after); the line names the incoming short shas, and the gates run on the rebased tree, so what is pushed is what was tested. An overlap, no upstream, a failed fetch or a failed rebase: `❌` lines naming the files, `git pull --rebase --autostash` to run, exit 3 as before, HEAD, the staged and unstaged changes and the stash list untouched. sfl.sh v8.

- Red first: `Scripts/test_sfl_pull_rebase.sh` (a temp bare remote and two clones) failed on its expectations only: the unrelated case exit 3 instead of a rebase, the overlap cases without the file named on a `❌` line, the overlap-check line missing for the mutation proof. Then green, with two mutation proofs, each asserting its reason: without the overlap check the local commit's file is rebased, without the working-tree part of the overlap list the staged file is rebased.
- Registered: an order-file row after the sfl pull contract, `MIN_GATES` 157, CONTRIBUTING.md, docs/gate-classification.md, docs/quality-gates.md, docs/development.md, CLAUDE.md. `Scripts/test_sfl_pull.sh` (v3) puts its mutants beside a copy of the shared helper.

---

## 2026-10-22 — FBP rebases and pushes when the push is refused and the incoming commits touch other files ([#283](https://github.com/yveshanoulle/forsgren/issues/283), step 1 of 2)

forsgren issue 283, step 1 of 2, ported from the estate canon. When the final `git push` of `FBP.sh` is refused because the remote moved during the run, `Scripts/fbp_push_or_rebase.sh` fetches and compares the files changed by the incoming commits with those of the local commits. No file in both: the local commits are rebased onto the remote (author and message kept, so the Signed-off-by trailer stays), pushed, and the git row reads `⚠️ (pushed after rebasing onto <shas>; this combination is tested by CI, not by this run)`; a remote that moves again is rebased over again, at most 3 pushes. A file in both, a rebase conflict, a third refused push or a refusal with nothing incoming: any rebase aborted, the local commits unchanged, `❌` lines naming the files and `git pull --rebase --autostash`, and the run is red. The helper is sourceable, so step 2 (sfl's opening pull) can reuse `fbp_overlap_files`. The opening pull is unchanged. FBP_VERSION 10.

- Red first: `Scripts/test_fbp_push_or_rebase.sh` drives a copy of the real FBP.sh in throwaway repositories whose bare origin moves during the run; on the red it failed on its expectations: the helper missing, the unrelated case exit 1 with the git row `⏭️`, nothing pushed, the same-file case without the file named, no 3-push stop. Then green, with a mutation proof: without the overlap check the same-file case is pushed and the scenario fails on the missing file name.
- Registered: an order-file row after the FBP --no-push self-test, `MIN_GATES` 156, the gate wiring case for the helper, CONTRIBUTING.md, docs/gate-classification.md, docs/quality-gates.md, docs/development.md.

---

## 2026-10-22 — the quality-run summary's older mutation proofs check their own case ([#288](https://github.com/yveshanoulle/forsgren/issues/288), step 1 of 1)

forsgren issue 288, step 1 of 1. In `Scripts/test_render_quality_summary.sh` the four mutation proofs that predate #282 (0 for a missing input, a Total summed over the parts it has, verdict lines counted, the unknown-format guard dropped) asserted the bare case name, which the `ok:` line of a run red for any other reason carries too. Each now asserts its case's own failure line, `FAIL: <case>: no row`, the shape of the #282 proofs. A new helper, `want_own_case`, pins it: the run of a mutant that breaks another case (the unguarded mutant for the first three, the partial-sum mutant for the fourth) is red, passes the proof's case on an `ok:` line and never says the proof's needle. Test-only: the renderer and the workflows are unchanged.

- Red first: the four `want_own_case` pins, with the needles still the bare names, failed on four expectations: each other-case mutant run said the proof's case name. Then green with the needles on the cases' own FAIL lines; each proof is still met by its own mutant.

---

## 2026-10-22 — tools issues need no release ([#289](https://github.com/yveshanoulle/forsgren/issues/289), step 1 of 1)

forsgren issue 289, step 1 of 1. Yves's ruling: a tooling update (CI, release scripts, build gates, self-tests) needs no release; a release comes with a feature change labelled patch, minor or major. `Scripts/release_plan.sh` now treats an issue labelled `tools` and none of patch, minor or major as needing no bump, never as unlabelled; an issue with `tools` and a bump label counts by its bump label. When only tools issues were closed since the latest release the plan says `OK: nothing to release`, names them, prints `release=none` and `tools=#N ...` and exits 0 with no version, no tag and no notes file. A release with feature issues lists the tools issues closed since the last one under `### Tooling`, after the bump headings, and in a `tools=` line. An open tools issue with commits since the latest release no longer stops the plan (the open-issue seam and the gh read carry the labels now); an open feature issue still does. `release.yml` passes `release` and `tools` on to the plan step's outputs, logs `plan: nothing to release`, and skips the version check, the head check, the publish, the install check, the template, the metrics pull request and merge and the preview on `steps.plan.outputs.release != 'none'` (a resumed run, whose plan is skipped, still runs them), so a tools-only run ends green with nothing tagged; no permission or secret change. `Scripts/release_report.sh` says nothing was released and no pin moved, and `Scripts/release_precheck.sh` says nothing to release instead of "would pass the plan". `docs/updating-and-releases.md` says tools issues need no release.

- Red first: `Scripts/test_release_plan.sh` case 14 (tools only, patch plus tools, tools plus minor, an open tools issue with commits, open feature issues with commits, --all), `Scripts/test_release_workflow.sh` pin 11, `Scripts/test_release_precheck.sh` case 7 and `Scripts/test_release_report.sh` case 6 failed on their expectations: the tools issues called unlabelled, no `release=none`, no Tooling heading, the open tools issue red, the workflow steps ungated. Cases 8 and 11 now use a `docs` label for the unlabelled issue. Then green with new mutation proofs, each asserting its reason: without the tools rule a tools issue is unlabelled, without nothing to release a tools-only set is released as a patch, without the Tooling notes the issue is missing, without the open tools rule the open issue blocks, a tools label that wins over a bump label loses the minor, each workflow gate removed is named, and the report and the pre-check that ignore it read as a release.

---

## 2026-10-22 — the DCO check asks a failed GitHub API call once more ([#287](https://github.com/yveshanoulle/forsgren/issues/287), step 1 of 1)

forsgren issue 287, step 1 of 1. A DCO run on a signed-off push turned red because GitHub answered the pull request lookup of the commit with an empty body (`unexpected end of JSON input`); the re-run was green. The API calls of `Scripts/dco_push_check.sh` and the pull request listing `Scripts/dco_pr_commits.sh` now share one helper, `Scripts/lib_dco_api.sh` (`dco_api`): a failed call is asked once more after `DCO_RETRY_PAUSE` seconds (default 5; the self-tests set 0). A retry that answers goes on with one `⚠️` line on stderr naming the first failure, never in the commit list; a second failure is red naming both reasons, so an outage or a missing permission still turns the check red and shows its cause. `dco.yml` checks the helper out in both jobs' sparse checkouts; no new secret or permission. **gate wiring** holds that both scripts source it and both jobs check it out. `docs/ci.md` describes the retry.

- Red first: `Scripts/test_check_dco.sh` cases 39e to 39g (a stub gh that fails once and then answers, fails twice with two reasons, answers at once) and `Scripts/test_check_commit_messages.sh` cases 10b and 10c failed on eight expectations: the push check and the listing red on one failure, naming only the first reason, gh asked once. Then green with a new mutation proof: without the retry, case 39e is red naming the empty answer.

---

## 2026-10-22 — the template README comes from the released source ([#286](https://github.com/yveshanoulle/forsgren/issues/286), step 1 of 1)

forsgren issue 286, step 1 of 1. The release's template commit used to fetch forsgren-template's README and rewrite only its "written by the daily run for forsgren X.Y.Z" line, so the body stayed the previous release's until the next daily run. `Scripts/release_pins.sh template` now first runs `go install` of `cmd/forsgren` at the released sha (GOBIN a temporary directory) and that binary's `forsgren install-readme --out <file>`, the two commands the daily run (`metrics.yml`) runs, and commits that file byte for byte as `README.md` with the pins, in the one commit as before. A failed install, or a README whose version line does not name the release exactly (a pseudo-version build), is a red before anything is read or written. The version check of the README no longer takes `1.9.4-0.…` or `1.9.40` for `1.9.4`. The metrics step, the `rewrite` and `token` modes and the resume path are unchanged; a resumed run finds the README already equal and says already done. The Release job already has Go set up for the install check, so `release.yml` is unchanged: no new secret or permission. `docs/updating-and-releases.md` (step 7) says so.

- Red first: `Scripts/test_release_pins.sh` case 8 (a stub go whose installed forsgren writes `install/README.md` with the version filled in, as `install.Text` does) failed on seven expectations: the README blob without the released body line, not byte for byte the released text, no go install at the sha, and a failed install and a pseudo-version README each exiting 0 and each writing the commit. Then green with three new mutation proofs, each asserting its reason: the old version-line rewrite commits the old body, an install of another ref shows in the go log, and without the early version check blobs are written before the refusal.

---

## 2026-10-22 — the run summary names the red gate job ([#282](https://github.com/yveshanoulle/forsgren/issues/282), step 2 of 2)

forsgren issue 282, step 2 of 2. Since step 1 a lint-only red left every phase step of the main job green, and the run summary's status read `❌ Failed — every phase ran; red in: no phase step.`; the same gap was already there for an isolation or browser red. `Scripts/render_quality_summary.sh` now reads the gate jobs from `Scripts/ci_job_groups.txt` (isolation, browser, lint, in its order; `QS_JOB_GROUPS` moves it for the fixture) and each one's `QS_<JOB>_RESULT`: a red job joins the red list after the red phase steps (`red in: lint job`, `red in: PRE, lint job`, `red in: isolation job, browser job`), a cancelled or skipped job is named as such (`stopped in POST; browser job cancelled`, `every phase ran; isolation job skipped`), never as red, and a run whose every job and phase is green keeps its line. A gate job added to the groups file is named without a change here. The report job already passes the three results to the render step, so `quality.yml` is unchanged: no new secret or permission. `docs/ci.md` describes the line.

- Red first: `Scripts/test_render_quality_summary.sh` case 10 (a lint-only red, a browser and isolation red, a PRE and lint red, an all-green run, a cancelled job, a skipped job) failed on six expectations, the renderer saying `red in: no phase step`, `red in: PRE` and `stopped in POST.`. Then green with three new mutation proofs, each asserting its own case's failure line: a red gate job left unnamed, a cancelled job named as red, and the jobs read in another order (sorted by name).

---

## 2026-10-22 — the lint block runs as its own Quality job ([#282](https://github.com/yveshanoulle/forsgren/issues/282), step 1 of 2)

forsgren issue 282, step 1 of 2. `Scripts/ci_job_groups.txt` gives the nine lint rows (actionlint, its two self-tests, shellcheck, yamllint and zizmor with their self-tests) to a new `lint` job, the mechanism of the isolation and browser jobs, so the main `quality` job no longer runs them. `.github/workflows/quality.yml` has the `lint` job (Lint gates) in parallel with `quality`, `isolation` and `browser`, with the same setup, `Scripts/run_ci_phase.sh pre ... lint` and its hand-over `quality-report-lint`; the report job needs it and passes `QS_LINT_RESULT` to the status, and the preview job needs it. The order file is unchanged: the rows keep their pre phase and their place in the static block, so `sfl.sh` and `FBP.sh` run them, and stop after the block, as before. No new secret or permission.

- Red first: `Scripts/test_quality_jobs.sh` failed on the real workflow (`job: the file has no lint job`, and the group file without the lint rows); `Scripts/test_run_ci_phase.sh` failed its real order file case (the lint job had no gate); `Scripts/test_preview_workflow.sh`'s needs mutants, aimed at the new needs line, changed nothing. Then green with 38 mutation proofs in the jobs pin (12 new: the lint job gone, off macos-latest, without npm ci, running the main job's gates, a step naming a lint gate, its hand-over not always or under another name, the report without lint in needs, without `QS_LINT_RESULT` or without it in the status call, a group file without the lint rows, a lint row moved to post), each asserting its finding, and one new preview mutant (lint missing from the preview's needs).

---

## 2026-10-22 — new installations start with the Issues page off ([#285](https://github.com/yveshanoulle/forsgren/issues/285), step 1 of 1)

forsgren issue 285, step 1 of 1. The starter that `init-config` writes (`internal/config/starter.yml`) and the agent installer (question 10 of step 2, the example config and the instruction of step 9) set `issues_page: false` instead of `issues_page: true`, so a new installation starts with the Issues page off. The built-in default for a config that leaves the key out stays `true`: an installation that never set `issues_page` keeps its Issues page after an automatic update. `docs/configuration.md` (the page keys and `init-config`), `docs/pages-and-views.md`, the 1.3.0 note of `docs/updating-and-releases.md` and the installation README's example config say so; the legend and the settings page, which state the built-in default, are unchanged.

- Red first: the starter test (`TestStarterIsACommentedGuideThenAnEmptyConfig`, `TestStarterPassesLoad`) expected `issues_page: false` and failed on the starter's `true`; the new `TestNewInstallationsStartWithTheIssuesPageOff` (`internal/installerdoc`) failed on the starter's value and on the installer's step 2 default and step 9 line. The new pin `TestIssuesPageDefaultStaysOnWithoutTheKey` passed on arrival; its mutation, the built-in default flipped to `false`, was seen red with `got "false"`.

---

## 2026-10-22 — sfl skips a browser row whose inputs a commit did not touch ([#262](https://github.com/yveshanoulle/forsgren/issues/262), step 3 of 3)

forsgren issue 262, step 3 of 3. Before a row whose label has `in` rows in `Scripts/gate_inputs.txt` (the four browser rows: the browser gate self-test, the browser gate, the fixture self-test and the fixture gate) runs, `sfl.sh` (v7) asks `gate_select`. On a skip the script does not run; as with the static-block skip the step is still counted, it is printed `⏭ skipped: <label> (<reason>)` and is a `⏭ skip` row of the step table (`skip_step`, now shared by both), and `<label><TAB><reason>` is appended to `.build/sfl-skips.log`, which `sfl.sh pre` empties and post appends to, for the FBP summary of #266. A selected row prints `▶ selected: <label> (<reason>)` and runs. `Scripts/run_ci_phase.sh` is untouched: Quality runs every row. A commit that touches only workflows, docs, release scripts or other gates' scripts skips the four rows, about 285 s of an FBP.

- Red first: the new self-test `Scripts/test_sfl_gate_skip.sh` (its own order row; `MIN_GATES` 155) against the previous `sfl.sh` failed on every skip: the four rows ran on a docs-only change, no row was named as skipped, `.build/sfl-skips.log` was never written and a stale one was not emptied; the CI case (all four run by `run_ci_phase.sh`) already held and pins it. Then green with four cases and three mutation proofs, each asserting the reason: the skip ignored (the self-test runs and its reason is gone), the log line dropped, the log never emptied.

---

## 2026-10-22 — a selector says which browser gates a commit needs ([#262](https://github.com/yveshanoulle/forsgren/issues/262), step 2 of 3)

forsgren issue 262, step 2 of 3. `Scripts/lib_gate_select.sh` (sourced, never run) holds `changed_files`, `named_files` and `closure`, moved out of the git sandbox isolation gate and out of `Scripts/test_gate_inputs.sh`, which both source it now (no copy is left), and `gate_select <label>`: one line, `run: <reason>` or `skip: <reason>`, from the files changed against the merge base with origin/main and `Scripts/gate_inputs.txt`. A changed file under one of the gate's inputs, and matching none of its exclusions, selects it. Fail-safe: a changed file that no gate's list names, neither as an input nor as an excluded pattern, selects every listed gate and says which file. `GITHUB_ACTIONS=true`, `FORSGREN_GATE_SELECT_FULL=1`, a missing origin/main and a label with no list select all. `*_test.go` and `testdata/` of the Go trees are known and excluded, so they select nothing and are not unknown either (decision 281). Nothing in sfl.sh calls it yet: that is step 3.

- The guard of step 1 is now exact where it is cheap: `go list` says what go build embeds (0.3 s), so a directory pattern such as `//go:embed templates` that comes to hold a testdata file is red, besides the written patterns.
- Red first: throwaway-repository tests (`Scripts/test_gate_select.sh`, its own order row) against a stub library whose `gate_select` always said `run: stub` failed on every skip and every reason; then green with fourteen cases and eight mutation proofs, each asserting that the mutant no longer says the reason (the Quality path, the forced path, a missing origin/main, the fail-safe, the exclusions for a gate, excluded files counted as unknown, a listed directory not covering its files, untracked files ignored). The isolation scope self-test's three proofs that mutated the moved functions now mutate the library.
- Files known to be unrelated select nothing, so a commit that touches only a workflow, docs, a release script or another gate's script skips all four: `none|out|...` rows in `Scripts/gate_inputs.txt` (`.github/**`, `docs/**`, `*.md`, the release scripts), and a file under Scripts/ that is in the closure of no gate's script (`gate_unrelated_script`; a closure file the list forgot still takes the fail-safe). A new top-level file or directory still runs all four. Red first: the workflow-only and the other-script cases ran all four against the previous library; two more proofs (no `none` rows, the closure check removed) make ten.

---

## 2026-10-22 — the browser gates' inputs are listed and proved ([#262](https://github.com/yveshanoulle/forsgren/issues/262), step 1 of 3)

forsgren issue 262, step 1 of 3, from the prepared ladder and decision 281. `Scripts/gate_inputs.txt` lists what each of the four browser rows reads: the non-script inputs written out (`cmd/`, `internal/`, `go.mod`, `go.sum`, `package.json`, `package-lock.json`, the fixture directory, the required-pages manifest, the `browser_gate_*` data files) and the script inputs, the closure of each gate's script. For the Go trees it excludes `*_test.go` and `testdata/`, as decision 281 ruled: a test file is never compiled into the binary `go build` makes, and a golden reaches the site only through a `go:embed` line or a build script. The new self-test `Scripts/test_gate_inputs.sh` (its own row, after the fixture rows) asserts that each label has a row in the order file and in the list, every listed path exists, every gate's script closure is inside its list and a gate that lists the Go trees excludes tests, and the guard: no `go:embed` line of a non-test Go file and neither build script reads `testdata/` or a test file (the fixture directory is the one allowed path). `install/README.md` is embedded but not part of the rendered site, so it is not listed; the fail-safe of step 2 covers it. No behaviour change: nothing in sfl.sh or FBP.sh reads the list yet.

- Red first: the self-test run with no list stopped with `Scripts/gate_inputs.txt is missing`; its first run against a draft list was red for four closure files the draft did not name (the browser engine names its own self-test, so the closure is wide; a wider list only selects a gate more often). Six mutation proofs seen red with their reason: a script dropped from a list, a nonexistent path, the `*_test.go` exclusion dropped, a `go:embed` of a testdata file, a `go:embed` of a `_test.go` file, a build script reading a testdata file.
- The self-test copies `named_files` and `closure` from the isolation self-test; step 2 moved both into `Scripts/lib_gate_select.sh`.

---

## 2026-10-22 — the Mainline Interval shows the median and the 90th percentile of the gaps ([#272](https://github.com/yveshanoulle/forsgren/issues/272), step 1 of 1)

forsgren issue 272, step 1 of 1, as Yves asked: a deviation several times the mean needs the median and the 90th percentile to tell typical commit spacing from occasional long gaps. `MainlineInterval` (`internal/metrics/mainline.go`) has `Median` and `P90` over the same gaps as the mean and the deviation. Median: the middle gap, or the mean of the two middle ones (`middleOf`, now shared with lead time's `median`), from two gaps. 90th percentile: nearest rank, the gap at position ceil(0.9 n) of the sorted gaps, worked in integers as (9n + 9) / 10, so it is always an observed gap and no float rounds the rank; from ten gaps (`minP90Gaps`), because under ten the nearest rank is the longest gap, which tells nothing the maximum does not. Linear interpolation was not chosen: it invents a gap that never happened. The cell on the TBD page is `mean ± deviation (gaps) · median M · p90 P`, for example `24 min ± 2 h 24 min (12) · median 5 min · p90 1 h`, a dash for a part not shown (`2 h ± 1 h (3) · median 2 h · p90 -`). It stays one line in the existing two-column table: that table is already `no-wrap` inside its scrolling region, so a long cell scrolls sideways on a narrow screen like the other tables, and no column was added. The legend's TBD section explains the median, the nearest rank, the two minimums and how to read a mean far above the median; `docs/pages-and-views.md` and CLAUDE.md say the same.

- Red first: the tests with hand-computed values failed at runtime against `HasMedian` and `HasP90` returning false and the cell unchanged. By hand: gaps 1 to 10 h give a median of 5.5 h and p90 9 h (rank 9); 1 to 11 h give 6 h and 10 h (rank ceil(9.9) = 10); nine gaps of 1 h and one of 91 h give a median of 1 h and a p90 of 1 h while the mean is 10 h; 1 h and 3 h give a median of 2 h and no p90. Green: `go test ./...`; the `tbd` and legend goldens changed by the cell format, the new "Acme Web" row (12 gaps, with a p90) and the new legend paragraph only. `Scripts/test_build_site.sh` (fixture cases 31 to 33, whose cell pattern now allows the new suffix) is green.
- Coverage floors at 100.0 for `HasMedian`, `HasP90`, `shown`, `medianAndP90` and `middleOf`. The language gate found 0 new findings on the legend and TBD pages.

---

## 2026-10-22 — the browser gate self-test's shift fixtures are anchored to the page load ([#275](https://github.com/yveshanoulle/forsgren/issues/275), step 1 of 1)

forsgren issue 275, step 1 of 1, patch. Nothing an installation sees changes. `Scripts/test_gate_browser.sh` cases 8, 19 to 23, 38 and mutation proof K race the gate's measurement window, and Quality failed on it twice: run 39700100601, case 38 "the short setting still catches the shift fixture" got exit 0 (`CLS worst 0`), and run 39676284969, proof K got `CLS 0.0269` with exit 1. The cause, in both: the shift fixtures moved the page with `setTimeout` from the script's parse (200 ms for the shift, 500 ms for the late shift), while the gate starts its interval at the load event and reads after it. A load that the machine delays breaks both premises. (1) The move can come before the first paint, and a move before the first paint is no layout shift: the short setting sees CLS 0 (case 38). (2) The move can come before the 1 ms read of proof K, which should have missed it (K). #252 had moved K's shift to 500 ms, which only widened the margin on the fast side. The premise of those cases, a wall-clock delay from the parse, was timing-based itself.

The fix keeps every case's assertion and changes the fixtures, not the gate (the canon engine is untouched): `shift` moves the page two animation frames after the load event (a double `requestAnimationFrame`, so after the first paint and at once, with no delay left to lose), and `lateshift` moves it 500 ms after the load event, the middle of the 1 ms and the 1000 ms reads. Two cases were added with an injected delay seam, the same pages after a script that blocks the parse for 800 ms (the starved machine): case 40, the short setting still catches the shift fixture after a delayed load, and "mutation proof K, delayed load", a 1 ms read still misses the shift. No case was removed or weakened.

- Red first, by running the cases in a loop (30 runs each, the same fixtures and engine as the self-test; a loop that runs one gate call per case): the race did not show on this machine on its own, 30 of 30 for both cases unloaded and 30 of 30 with 16 CPU burners on 12 cores, so it was shown with the delay seam. Old fixtures after a load delayed 800 ms: case 38 held 17 of 30 (13 times exit 0, `CLS worst 0`), proof K held 10 of 30 (20 times `CLS 0.0269`, exit 1), the two signatures of the two failed runs. New fixtures: delayed load 30 of 30 for both, no delay 30 of 30, 16 CPU burners 30 of 30.
- Green: the whole self-test, four times in a row (once, then three more): `OK: browser gate: every case holds, eleven mutations seen`.

---

## 2026-10-22 — the TBD page keeps its table, the explanation moves to the legend, and the title reads BETA ([#271](https://github.com/yveshanoulle/forsgren/issues/271), step 1 of 1)

forsgren issue 271, step 1 of 1, as Yves worded it. Two things an installation that lists or opens the TBD page sees change. (1) The page keeps its h1, its table and its two no-data lines; the paragraph that explained the Mainline Interval and the line "Mainline Lead Time is coming later." are gone from it. They are in the legend's TBD section, merged with the text step 7 of 253 had put there so that no sentence stands twice: the mean and sample standard deviation of the time between commits by author date, the number of gaps in brackets (`mean ± deviation (gaps)`, `2 h ± 1 h (3)`), a gap, the commits that deployments of the last N days shipped (N from `Data.Window`) counted by deployment date and each once, the interval being between deployed commits, a dash for fewer than two commits, one gap with a mean and no deviation, and how the two metrics are read together (Yves's review): the Mainline Interval shows how often the commits that were deployed were made, by author date, in the window; Mainline Lead Time, not on the page yet, will show how long a commit takes from its creation to reaching the main branch; a short interval with a long lead time points at long-lived branches. The metric keeps its name, Mainline Interval, and the Go names are untouched. (2) The page's title and h1 are now exactly "Trunk-based development [TBD] (BETA)", and the legend's section heading is the same text (`Data.TbdTitle()`, `internal/page/tbd.go`, one constant). The menu label stays "TBD". The History page's marker (`betaMarker`, "(beta)", lower case) is not reused and not changed: History reads "History (beta)", the TBD page "(BETA)"; Yves decides whether they should match. The docs (`docs/pages-and-views.md`, `docs/configuration.md`) and CLAUDE.md say the same.

- Red first: the TBD page tests failed at runtime against the old template (title and h1 still "(TBD)", the explanation and the Lead Time line still on the page, `TbdTitle()` empty, no legend section under the new heading). Green: `go test ./...`; the legend and the three `tbd*` goldens regenerated, the diff read (only the heading, the merged paragraphs and the removed explanation changed). The legend test also holds that each of five sentences stands once in the legend. The render test for `dora_days: 90` now reads the 90 days in the legend, not on the page.
- Yves: "use both BETA". The History page's marker is capitals too: `betaMarker` is `" (BETA)"` (`history.go`), so the History title, h1 and the legend's History heading read "History (BETA)", the menu label stays "History", and the TBD title is `"Trunk-based development [TBD]" + betaMarker`, one place for the word. Red first: the tests pinning "(BETA)" failed on History's lower-case marker; the five `history*` goldens and the legend golden changed by that word only.
- `TbdTitle` registered at 100.0 in `coverage_thresholds.json`. The language gate on the legend and TBD pages: 0 new findings.

---

## 2026-10-22 — the TBD page in the docs, the legend and the installer texts ([#253](https://github.com/yveshanoulle/forsgren/issues/253), step 7 of 7)

forsgren issue 253, step 7 of 7, minor release (decision 257). The last step of the TBD page: its texts say what the page does today. `docs/pages-and-views.md`: the menu line ends with TBD, five pages have a key (`tbd_page`, default `unlisted`), `tbd.html` is in the unlisted example and the meta description table, and a new section "The TBD page" says what the Mainline Interval is and how it is counted (decision 270: the commits of the DORA window by their deployment's date, each once by repository and SHA, sorted by author date, the gaps between neighbours, their mean and sample standard deviation over n-1, the count of gaps in brackets, a dash under two commits, one gap with a mean and no deviation, per project only, and that Mainline Lead Time comes later). `docs/configuration.md` lists `tbd_page` with the other page keys, the starter and the twelve rows of the settings page (the page had grown to twelve rows in step 1). The legend has a TBD page section after the History page's, with the cell format `mean ± deviation (gaps)`, the window in force, what a dash is and the default of `tbd_page`, and its page-keys paragraph names the fifth key. `install/README.md` shows `tbd_page: unlisted` in its example and lists the TBD page among the unlisted ones. `agent-installer.md` step 12 expected eleven settings rows, which stopped being true when step 1 added the `tbd_page` row: it now says twelve, reads `tbd_page` as left to its default (`unlisted (not set)`, the installer does not ask about it), and "Changing a setting later" lists the key. CLAUDE.md's `cmd/forsgren`, `internal/config`, `internal/metrics` and `internal/page` paragraphs name `Data.Mainline`, `tbd_page`, `MainlineIntervals` and the page. The settings page and its goldens already carried the key (step 1).

- Refactor, structure only: in `internal/metrics/mainline.go` the sorting and the subtraction of the gaps are `gapsOf`, so `mainlineOver` reads count, mean, deviation; results unchanged (the metrics tests are the same). `tbd.go`, the template and the render wiring were reviewed and left as they are. CodeScene 10.0 on `mainline.go`; `gapsOf` registered at 100.0 in `coverage_thresholds.json`.
- Red first: the new legend test (no "TBD page" section, and the page-keys paragraph without `tbd_page`) and the changed installer test (`TestInstallerProvesTwelveSettingsRows`: no "Twelve rows in all", no `tbd_page` row, key not listed) failed against the old texts. Green: `go test ./...`, the legend golden regenerated (only the new section and the key paragraph changed). The language gate (LanguageTool) found one comma suggestion in the new legend sentence, fixed before this entry; no new finding is left on the legend page.

---

## 2026-10-22 — the fixture site shows the TBD page ([#253](https://github.com/yveshanoulle/forsgren/issues/253), step 6 of 7)

forsgren issue 253, step 6 of 7, minor release (decision 257). Nothing an installation sees changes. The required-pages manifest (`/tbd.html`) and the site's page count (11) moved in step 2. What this step adds: the fixture site (`Scripts/build_fixture_site.sh`, the made-up data of `Scripts/testdata/fixture_site/`, which the fixture browser gate opens through the manifest) already renders `tbd.html`, listed by default as unlisted, and its fixture has commits deployed in the last 30 days (the last on 2026-09-28, render time 2026-10-03), so Acme Shop's row has a real Mainline Interval and no fixture data was added. The build script is now red, naming the page, when `tbd.html` shows no Mainline Interval cell with a number (a fixture with no commits would otherwise pass with dashes), as it is for the History chart and the Daily and Issues rows. The docs that count the site's pages say eleven and name `tbd.html` (`docs/pages-and-views.md`, `docs/development.md`, `CLAUDE.md`); `docs/configuration.md` and `docs/data-files.md` count pull request list pages, not the site, and are unchanged.

- Red first: `Scripts/test_build_site.sh` case 32, a fixture without `commits.csv` is red with "tbd.html shows no Mainline Interval", failed (exit 0: the build was green with dash-only rows). Case 31 (the fixture's `tbd.html` has an `Acme Shop` row and a number, not the no-data line) held at once, as the fixture already had commits. Green: `test_build_site.sh`, run to the end here (the fixture build needs no `node_modules`). Mutation proof 33: with the TBD check removed from a copy of the script, the fixture of case 32 turns green.
- Left for step 7: the docs, legend, settings, install and agent-installer texts that name the menu and the keys (the menu line and "Four pages have a key" in `docs/pages-and-views.md`, the CLAUDE.md page paragraph), then the refactor.
- Not run here: the fixture browser gate itself (puppeteer-core and axe-core need `npm ci`); FBP is the first to open `/tbd.html` of the fixture site in the browser. The manifest and the fixture's pages are the same as the data site's, which passed it in the build of steps 4 and 5.

---

## 2026-10-22 — the TBD page's table and goldens ([#253](https://github.com/yveshanoulle/forsgren/issues/253), steps 4 and 5 of 7)

forsgren issue 253, steps 4 and 5 of 7, minor release (decision 257). The two ship together in one build: the template alone (step 4) would make every rendered site, the preview site included, say "No commits have been collected yet" where commits exist, because `Data.Mainline` is only filled by the render wiring (step 5), and a page may only say what is true. `tbd.html` now has its template: under the h1 one line says what the Mainline Interval is (mean and sample standard deviation of the time between commits by author date, then the number of gaps, `2 h ± 1 h (3)`; the commits that deployments of the last `dora_days` days shipped, each once, so an interval between deployed commits; a dash is fewer than two commits, or fewer than two gaps for the deviation) and one says `Mainline Lead Time is coming later.`, with no empty column. Then the table, in the region of the h1 as the other pages (`aria-labelledby="tbd-heading"`, no caption, class `no-wrap`): Project | Mainline Interval, a row per project from the new `Data.Mainline` (`[]metrics.MainlineInterval`), each cell `MainlineInterval.Cell()`. With no `Data.Mainline` the page shows one line in place of the table, `Data.TbdMessage()` (`internal/page/tbd.go`): "No projects are listed yet, so there is no Mainline Interval to show." with no projects, else "No commits have been collected yet, so there is no Mainline Interval to show." (a one-line message like the History, Daily and Issues pages, not the how-to of the table page). The meta description names the metric now: "Trunk-based development: the Mainline Interval per project" (step 2 had recorded it). Step 5, the render wiring: `withHistory` in `cmd/forsgren/render.go` sets `Data.Mainline = metrics.MainlineIntervals(cfg.Projects, metricsData, at)`, from the same `metrics.Data` (the commits beside `--data`, `dora_days` as the window) and the same render time as lead time; without `--data` the page keeps the "No commits have been collected yet" line, which is then true, and with no projects the no-projects line.
- Render tests (`cmd/forsgren/render_tbd_test.go`): a project with commits shows its cell (`2 d 22 h ± 4 d 3 h (2)`, two gaps of 141 h 13 min and 22 min), one without shows `-`, `dora_days: 90` brings in the older commit (`14 d 7 h ± 19 d 22 h (3)`, the window named), no projects keep the no-projects line with data or not, projects with no `--data` say no commits were collected, and `tbd_page: false` writes no `tbd.html`, removes a stale one and leaves it out of the menu. Red first: with the wiring missing, the cell and window tests failed (the page had no row for Acme Shop or Acme Tools); the no-projects, no-data and `false` tests already held. Green: `go test ./...`. No new function, so no new coverage floor; CodeScene: `render.go` and `render_tbd_test.go` 10.0.

- Red first: with `Data.Mainline` declared and the step 2 template, the new tests failed at runtime (no `aria-labelledby`, no columns, no rows, no `Mainline Lead Time is coming later`, no window sentence, no message; the golden files `tbd.no-data` and `tbd.no-projects` missing). Green: `go test ./...`. Goldens: `tbd` (three projects: four commits, two commits, none), `tbd.no-data`, `tbd.no-projects`.
- Coverage: `TbdMessage` registered at 100.0 in `coverage_thresholds.json`.

---

## 2026-10-21 — Mainline Interval, the metric ([#253](https://github.com/yveshanoulle/forsgren/issues/253), step 3 of 7)

forsgren issue 253, step 3 of 7, minor release (decision 257). Nothing an installation sees changes yet: `metrics.MainlineIntervals(projects, data, now)` (`internal/metrics/mainline.go`) is a pure function like the other metrics, not wired to a page until steps 4 and 5. Per project it gives `MainlineInterval{Commits, Gaps, Mean, Deviation}` and a `Cell()`, `2 h ± 1 h (3)`: the mean of the gaps, their sample standard deviation and the count of gaps, `-` below two commits. The reading, from how lead time reads the stored commits:

- Which commits: those of `data/commits.csv` whose deployment was created in the DORA window (`Data.window()`, `dora_days`, both ends included, 0 is 30), whatever their author date, as `LeadTimes` does. They are commits a deployment shipped, so this is an interval between deployed commits, not every mainline commit.
- Which date: the author date. The commits of a project, over all its repositories (compared ignoring case), are one sequence sorted by author date, whatever the stored order; a gap is the time between two consecutive ones.
- Distinct: by repository (ignoring case) and SHA. A commit shipped by two deployments counts once (lead time counts each line); the same SHA in two repositories is two commits; two commits with one author date have a gap of 0.
- Deviation: the sample standard deviation, over n-1 with n the count of gaps. Two commits have one gap, so a mean but no deviation: the cell is `2 h ± - (1)`. Below two commits there is no gap and the cell is `-`.
- Per project only; the label rows get theirs when the page is wired.

- Red first: with the type and function stubbed (all zero), `go test ./internal/metrics/...` failed in all seven new tests (every case showed `Commits:0 Gaps:0`, the cells empty). Green: `go test ./internal/metrics/...`. Mutation proof: dividing the squares by n instead of n-1 turns the gaps 1, 2, 3 and the gaps 1 and 3 hours red (`Deviation:48m59s`, `1h0m0s`) and `TestMainlineIntervalDeviationDividesByNMinusOne` fails.

---

## 2026-10-21 — the TBD page, tbd.html ([#253](https://github.com/yveshanoulle/forsgren/issues/253), step 2 of 7)

forsgren issue 253, step 2 of 7, minor release (decision 257). One thing an installation sees changes: a new root page `tbd.html`, "Trunk-based development (TBD)", handled by the `tbd_page` key of step 1 like the History page. Unlisted by default: written, no menu entry, `<meta name="robots" content="noindex">` in its head. With `tbd_page: true` it is the last entry of the menu, labelled "TBD", after History; with `tbd_page: false` it is not written and a `tbd.html` left in a reused out dir is removed. The page has its `<h1 id="tbd-heading">` and, for now, one line that says the metrics are coming and none are shown yet; the metrics come in steps 3 to 5. Its meta description is the fixed sentence "Trunk-based development metrics per project, coming to this page" and the suffix every page has. `tbd` is in `rootPages` (`page.TbdPage`) and `pageModes` (`render.go`), `tbd.html` in `internal/page/required-pages.json`, and every golden page gained the menu entry, plus the new `tbd.golden.html`. The site now has eleven pages (the placeholder build and the fixture build write `tbd.html`, as its key defaults to unlisted), so `Scripts/test_build_site.sh` expects 11.

- Red first: with the page name only (`TbdPage`) declared, the new tests failed at runtime: the TBD page golden, heading and root-page tests (`page "tbd.html" not found`, the last root page was History), the meta description of `tbd.html` (real and placeholder), the page count 11, the hidden and stale-file test, the menu order, the unlisted and noindex cases for `tbd`, and the render mode tests of `tbd_page` (file, menu, noindex, reused out dir). Green: `go test ./...`.
- The description names the Mainline Interval once the page shows it: the step that adds the metric (step 4 or 5) changes the sentence and its pin then.
- Left for step 6: the page count in `docs/pages-and-views.md` and `docs/development.md` ("ten pages"), and the browser gate fixture checks. Left for step 7: the docs, legend and CLAUDE.md texts that name the menu and the page list.

---

## 2026-10-21 — DCO on a push to main leaves a merged pull request's commits to its own DCO run ([#267](https://github.com/yveshanoulle/forsgren/issues/267), steps 1 and 2 of 2)

forsgren issue 267, steps 1 and 2 of 2, patch (decision 268, option 1). Nothing an installation sees changes. Merging Dependabot's pull request 248 with GitHub's merge button turned DCO red on the push to main although the pull request's own DCO run was green: the push path judged Dependabot's commit (a sign-off by the bot, "not by its author", the exemption needs the pull request's opener) and the merge commit GitHub made (no sign-off). The new `Scripts/dco_push_check.sh` is what `dco.yml` now runs on a push: for each pushed commit it asks the API which pull requests it belongs to (`GET /repos/{repo}/commits/{sha}/pulls`, through `gh api` with its own `--jq`, the token and the repository through `env:`). A commit of a merged pull request of this repository whose DCO sign-off check run (made by GitHub Actions) succeeded on the pull request's head, and that is one of the pull request's commits, is not judged again; the merge commit GitHub made for it (committer GitHub's `web-flow`, email noreply, verified, second parent that head) is exempt; each is named in the output. Every other commit goes to `Scripts/check_dco.sh` unchanged (a direct push, a failed or missing DCO run, an unmerged or other repository's pull request, a squash or rebase commit, a merge commit not made, not verified or with another second parent), and any failed API call is red with gh's reason. `dco.yml` passes `GH_TOKEN` and `REPO` to the push step, adds `checks: read` to its read-only permissions (reading check runs) and the script to its sparse checkout; the private-names job is untouched. `Scripts/test_gate_wiring.sh` knows the new script and pins its call in `dco.yml`. docs/ci.md, CONTRIBUTING.md and CLAUDE.md say how a merged Dependabot pull request is judged.

- Red first: with a stand-in that sent every commit to the strict check (today's push path), `Scripts/test_check_dco.sh` failed on the Dependabot commit, the merge commit and both together (cases 29 to 31), on the four failed API calls (39 to 39d, a signed commit passed, the others red for the wrong reason) and on the mixed push (40); its ten new mutation proofs were vacuous. Green: `test_check_dco.sh` (14 new cases, a stub `gh` answering from fixtures, no network), `test_gate_wiring.sh`. Mutation proofs, each asserting its reason: without the DCO-success check a commit of a pull request whose DCO run failed turns green (32), without the merged check (33), the repository check (34), the membership check (38), the committer, verification, second parent and committer email checks (35, 36, 37, 37b), and a failed API call that is not an exit (39).

## 2026-10-21 — Quality runs the browser gates in their own job ([#259](https://github.com/yveshanoulle/forsgren/issues/259), step 3 of 5)

forsgren issue 259, step 3 of 5, patch (decision 260). Nothing an installation sees changes. `.github/workflows/quality.yml` has a new job `browser` with the main job's setup (the hosted image's Chrome, puppeteer-core and axe-core from `npm ci`) that runs the browser gate self-test, the browser gate, and the browser gate (fixture site) with its self-test, about 295 s of gates, in parallel with the main and isolation jobs. The browser gate reads the built site, so the job runs its PRE rows (the two self-tests), builds its own site (`Scripts/build_site.sh`, 0.3 s), then runs its POST rows (the two gates), each call of `Scripts/run_ci_phase.sh` with the job name `browser`; the fixture-site gate renders its own site. `Scripts/ci_job_groups.txt` lists the four rows, so the main job skips them. The `report` job and `preview` now need all three gate jobs, the report job takes the browser job's result into the run status, and its hand-over `quality-report-browser` is merged like the others. One verdict as before: the run's conclusion comes from every job.

- Red first: `Scripts/test_quality_jobs.sh` failed against the unchanged workflow and group file ("the file has no browser job", the group rows wrong) and its 8 new mutants plus the preview pin's new needs were vacuous until the job existed. Green: `test_quality_jobs.sh` (26 mutation proofs, the group pin now accepts pre and post rows), `test_preview_workflow.sh` (needs the browser job, 1 new mutant).

## 2026-10-21 — Quality runs the git sandbox isolation and the step summary isolation in their own job ([#259](https://github.com/yveshanoulle/forsgren/issues/259), step 2 of 5)

forsgren issue 259, step 2 of 5, patch (decision 260: parallel jobs inside `quality.yml`, not separate workflows). Nothing an installation sees changes. `.github/workflows/quality.yml` has a new job `isolation` with the main job's setup (checkout, gate environment, Node, tools, `npm ci`) that runs the git sandbox isolation self-test and the step summary isolation gate, about 294 s of gates, in parallel with the main job. `Scripts/ci_job_groups.txt` lists them (`<job>|<label>`); `Scripts/run_ci_phase.sh` takes the job as an optional fourth argument (default `main`), skips the listed gates in the main job, runs only them in their job, is red when the file names a gate the order file does not have, and exits 64 for a job the file does not name. `sfl.sh` and FBP run every row, unchanged. One Quality report: each gate job hands over its rows, details and page count (`Scripts/merge_quality_report.sh handover`, artifact `quality-report-<job>`), a new `report` job (`if: always()`, `needs:` both) merges them (`merge`; a gate reported by two jobs is red, a job that handed over nothing is named) and renders the summary and the gate table, with the run status from `merge_quality_report.sh status` of the jobs' results; the three baselines steps stay in the main job, they read the built site. `preview` needs all three jobs. One verdict: the run's conclusion is success only when every job is, which is what `Scripts/release_quality.sh` reads (a run's status and conclusion, never a job); `Scripts/test_quality_jobs.sh` pins that, with one workflow named Quality and no `continue-on-error`. Two existing pins changed with the layout: `Scripts/test_workflow_node_pin.sh` judges each job on its own (a second job that runs `npm ci` with no `setup-node` is red), and `Scripts/test_quality_summary_first.sh` reads the report job's steps. `MIN_GATES` 150 to 152.

- Red first: the extended `test_run_ci_phase.sh` failed against the unchanged runner (the job argument was a usage error: 8 failure lines in the new case and 2 in the real order file case, and both new mutation proofs vacuous), `test_quality_jobs.sh` failed against the unchanged workflow (no isolation job, no hand-over, no report job, no group file) and `test_merge_quality_report.sh` aborted because the script did not exist. Green: the three, plus `test_preview_workflow.sh` (needs the three jobs; two new mutants), `test_quality_summary_first.sh`, `test_workflow_node_pin.sh`, `test_gate_wiring.sh`. Mutation proofs: `test_run_ci_phase.sh` 2 (the main job runs other jobs' gates, a job ignores its group), `test_quality_jobs.sh` 18, `test_merge_quality_report.sh` 2.
- Not measured yet: the time saved. The last step of the issue measures it on the first runs; the expectation is about 294 s less in the main job, minus about 65 s of setup in the new job.

## 2026-10-21 — A Go change selects no isolation self-test while forsgren starts no program ([#258](https://github.com/yveshanoulle/forsgren/issues/258), step 1 of 1)

forsgren issue 258, step 1 of 1, patch. Nothing an installation sees changes. `Scripts/test_git_sandbox_isolation.sh` run locally (FBP) now counts a change to Go code (`cmd/`, `internal/`, `go.mod`, `go.sum`) for the self-tests that build or run the tool only while some non-test Go file can start a program: it imports `os/exec`, or calls `os.StartProcess` or `syscall.Exec`, `ForkExec` or `StartProcess` (`*_test.go` and `testdata` do not count). Today none does, so a Go change selects nothing; the check reads the working tree at gate time, so a change that adds such a file turns the old rule back on by itself. The scope line says which case applied: `isolation: Go changes select nothing, no non-test Go file starts a program`, or `isolation: Go changes count, <file> starts a program`. Quality (`GITHUB_ACTIONS=true`) keeps the full run, unchanged.

- Red first: the extended scope self-test failed against the unchanged gate with 4 case failures (17 and 17b a Go-only change still selected 1 of 4 and named no reason, 18b no file named, 19 a `_test.go` importing `os/exec` still selected). Green: the scope self-test. Mutation proofs, each asserting its reason: I the exec check never true (case 18 loses the Go-running self-test), J the exec check always true (case 17 selects it). The scope self-test now proves 10 mutations.

## 2026-10-21 — config key tbd_page ([#253](https://github.com/yveshanoulle/forsgren/issues/253), step 1 of 7)

forsgren issue 253, step 1 of 7, minor release (decision 257). One thing an installation sees changes: a new optional config key `tbd_page` (true, unlisted or false; default unlisted, like `history_page`). It is read and validated like `history_page`: a value that is not the plain literal true, unlisted or false (yes, a quoted value, a number) is rejected with `use true, unlisted or false`, the default unlisted in force; the settings page lists `tbd_page` after `history_page` with its current value, the three possible values and the default unlisted; `forsgren init` writes `tbd_page: unlisted` after `history_page` in the starter, with the same comment sentence. No page, no template and no metric yet: the key changes nothing else, and the TBD page itself comes in the next steps.

- Red first: the config package failed to build (`Config.TbdPage` and `ErrTbdPage` undefined) and the settings page tests failed (`TestSettingsPageMatchesGolden`, `TestSettingsPageWithRejectedSettingsMatchesGolden`, `TestEveryValueTheConfigAcceptsIsListedOnTheSettingsPage`). Green: `go test ./internal/config ./internal/page ./cmd/...`. The two settings goldens gained the `tbd_page` row.

## 2026-10-21 — Quality runs each git-using self-test once under the decoy ([#251](https://github.com/yveshanoulle/forsgren/issues/251), step 2 of 2)

forsgren issue 251, step 2 of 2, patch (decision 249, as the owner changed it: the single-run change goes to Quality only). Nothing an installation sees changes. In Quality (`GITHUB_ACTIONS=true`) `Scripts/test_git_sandbox_isolation.sh` runs each git-using self-test ONCE, under the decoy with `GIT_DIR` and `GIT_INDEX_FILE` (the shape without `GIT_WORK_TREE`, which gets a fixture that inits a bare repository past the work-tree check and so reaches every push the all-three shape reaches), and checks the decoy and its origin after that run; it prints `isolation: Quality, each self-test runs once under the decoy`. Locally (FBP, `GITHUB_ACTIONS` unset, or a forced full run) it is unchanged from step 1: the affected self-tests, each twice, once per leak shape. Known limit: a self-test that leaks only when `GIT_WORK_TREE` is set, which no real fixture does, is no longer seen in Quality; locally it still is.

- Red first: the extended scope self-test failed against the unchanged gate with 8 failure lines (13b no single-run message, 13c self-tests a, b and c ran 2 times, 15a-15c and 16 the FAIL line did not name the single run). Green: the scope self-test, 17 s. Mutation proofs, each asserting its reason: G the single-run mode removed (Quality runs each self-test twice), H the single run not under the decoy (the config leak of 15a goes unseen). Fixture leaks that turn the single run red: a changed decoy config, a push to the decoy origin, a commit into the decoy, and a leak without `GIT_WORK_TREE`. The scope self-test now proves 8 mutations.

## 2026-10-21 — FBP runs the git sandbox isolation only for affected self-tests ([#251](https://github.com/yveshanoulle/forsgren/issues/251), step 1 of 2)

forsgren issue 251 (split from 247), step 1 of 2, patch (decision 249). Nothing an installation sees changes. `Scripts/test_git_sandbox_isolation.sh` run locally (`GITHUB_ACTIONS` unset, so FBP and sfl) runs only the affected git-using self-tests: one whose own file, or any file it names (the `Scripts/` scripts, libraries and data files and workflow files, followed transitively), changed against the merge base with `origin/main`, counting committed, staged, unstaged and untracked changes (Go code or go.mod count for a self-test that builds or runs the tool; markdown does not). A change to the gate or to a library it sources, no `origin/main`, or `FORSGREN_ISOLATION_FULL=1` runs all. When none is affected the gate prints `isolation: 0 of 26 self-tests affected, full run in Quality` and passes; it never skips silently. Quality in CI (`GITHUB_ACTIONS=true`) runs all 26, unchanged. `Scripts/test_git_sandbox_isolation_scope.sh` is a new PRE row (`MIN_GATES` 149 to 150, with its docs rows). Measured locally on a change that touches no git self-test: 11 s, against 1473 s for the full run on the same tree (under load; 682-1245 s in the four FBP logs of #247).

- Red first: the new scope self-test failed against the unchanged gate with 20 failure lines (every scope case, plus the six vacuous mutants). Mutation proofs, each asserting its reason: A the called scripts not followed, B the queue not extended (transitive), C the Quality path filtered too, D untracked files ignored, E the none-affected message removed, F a harness change not widening to all.

## 2026-10-21 — mutation proof K of the browser gate self-test no longer depends on the machine's speed ([#252](https://github.com/yveshanoulle/forsgren/issues/252), step 1 of 1)

forsgren issue 252, step 1 of 1, patch. Nothing an installation sees changes. Mutation proof K (a shift case on a too short setting turns green) ran the 200 ms shift fixture with 1 load at 1 ms and expected the gate to miss the shift; on a fast runner (Quality run 39542802573) the 1 ms read still came after the shift and the proof went red with `CLS 0.0269 ... interval 1 ms, largest of 1 cold loads`. `Scripts/test_gate_browser.sh` now gives K its own fixture that shifts at 500 ms, the middle: about 500 ms of margin on both sides, so a browser timer slipping under heavy load still cannot cross either read. It is far under the default 1000 ms read, so the real setting sees it, and far over the 1 ms read. K asserts the reason and not a race: the OK line says `interval 1 ms` (the short setting was the one used) and a control run of the same page on the real setting is red with a CLS value, so only the setting hid the shift; a gate that ignored the short setting would say `interval 1000 ms` and fail K.

- Red first: with the shift fixture moved to 30 ms (a fast machine), the old proof K failed three runs in three with the CI line. Green: the new K passed three runs in three.

## 2026-10-21 — the browser gate self-test measures layout shift briefly where no case asserts on it ([#247](https://github.com/yveshanoulle/forsgren/issues/247), step 1 of 2)

forsgren issue 247, step 1 of 3, patch (decision 249). Nothing an installation sees changes. `Scripts/browser_gate.mjs` reads the layout-shift loads and interval from `FORSGREN_CLS_LOADS` and `FORSGREN_CLS_INTERVAL_MS`; unset, the defaults stay 5 loads at 1000 ms (the real gate and the site check are unchanged), and a value that is no positive integer stops the gate with exit 2. `Scripts/test_gate_browser.sh` runs its cases with 1 load at 300 ms (longer than the 200 ms of the shift fixture) except the clean page that records the interval, the layout-shift cases 8 and 19-23 and the mutation runs, which keep the real values; `Scripts/test_gate_browser_fixture.sh` does the same for its non-mutation cases. Measured locally: the browser gate self-test 321 s before, 132 s after; the fixture-site self-test about 70 s (CI log) before, 23 s after.

- Red first: the new cases failed against the unchanged engine with 8 failure lines (37 override not honoured, 38 short setting not read, 39a and 39b no exit 2, the three default mutants vacuous because the override did not exist, and the too-short-setting proof). Mutation proofs: H the override ignored (case 37 loses 50 ms), I the default interval changed (case 15 loses 1000 ms), J the default loads changed (case 8a loses 5 cold loads), K a shift case given a 1 ms setting turns green (why the shift cases keep the real values; 100 ms still caught the shift, so 1 ms is the proof value).

## 2026-10-21 — the Go toolchain moves to go1.27.3 ([#250](https://github.com/yveshanoulle/forsgren/issues/250), step 1 of 1)

forsgren issue 250, step 1 of 1, patch. Nothing an installation sees changes. govulncheck reported GO-2026-6809 (crypto/x509, distrust of compromised intermediate certificates), reached through `collect.Report.Render`, fixed in go1.27.3. `go.mod` now says `toolchain go1.27.3` (the one place `sfl.sh` and `FBP.sh` read through `Scripts/go_toolchain.sh`) and the `go-version` of `auto_update.yml`, `metrics.yml` and `starter_page.yml` is `1.27.3`. No other file names the running toolchain.

- Red first: `Scripts/check_govulncheck.sh` run with `GOTOOLCHAIN=go1.27.2` (what go.mod pins) exited non-zero with 1 vulnerability, GO-2026-6809; green after the bump.

## 2026-10-21 — Dependabot proposes Go module and action updates ([#86](https://github.com/yveshanoulle/forsgren/issues/86), step 1 of 1)

forsgren issue 86, step 1 of 1, patch. Nothing an installation sees changes. `.github/dependabot.yml` is new: `gomod` (go.mod / go.sum) and `github-actions` (the commit-pinned `uses:` lines of `.github/workflows`), each at `/`, on a cron schedule of 04:00 UTC every day (interval `daily` runs Monday to Friday only), with a commit-message prefix (`go`, `actions`), one group per ecosystem for minor and patch updates (a major stays its own pull request) and a 3-day cooldown, each choice with its comment. Dependabot's commits need no sign-off (the DCO check exempts the Bot that opened the pull request) and the file passes yamllint and zizmor. `Scripts/test_dependabot_config.sh` is a PRE row after the workflow node pin, so `MIN_GATES` goes from 148 to 149, and the docs rows (`docs/gate-classification.md`, `docs/quality-gates.md`, `CONTRIBUTING.md`) went with it.

- Red first: the test failed against c101f2c with 1 failure line (`.github/dependabot.yml: there is no dependabot.yml`); its nine synthetic cases (no file, no gomod, no github-actions, a subdirectory, no cooldown, no groups, no comments, interval daily) were already red or green as intended. Mutation proofs: no comment check, no cooldown check, no groups check, each accepting the file its case refuses.
- Not settled by the documentation, to check on the first Dependabot runs: that a `github-actions` pull request keeps the commit plus `# vX.Y.Z` pin format, and whether the `gomod` updates also move the `toolchain` line of go.mod or the literal `go-version: '1.27.2'` inputs of three workflows. The daily `vulncheck.yml` stays the detector for standard-library fixes.

## 2026-10-20 — an unreleased build shows the last release tag and +dev ([#237](https://github.com/yveshanoulle/forsgren/issues/237), step 7 of 8)

forsgren issue 237, step 7 of 8, minor. The preview, built from main, shows `<last release tag>+dev (<short commit>)` in its footer instead of the version written in the code, which no release bumps any more. A build made from a checkout records its commit and, since the go tool derives the module version from the tags, a pseudo-version of the next patch release (such as `vA.B.(C+1)-0.<time>-<commit>`, `+dirty` for a modified tree); `runningVersion` now returns the tag behind it, `A.B.C`, for such a build (`lastTagOfCheckout` in `cmd/forsgren/devbuild.go`, registered at 100.0 in `coverage_thresholds.json`). The order is: an ldflags value; a clean `vX.Y.Z`; the last tag of a checkout build; `var version`. An installation's `go install` of an untagged commit records no commit, so it keeps `var version`; a release build and `build_site.sh` (`-buildvcs=false`) are unchanged. `Built with`, the setup report and the install README of a checkout build name the same tag. The preview repository needs no change. No golden changes: the tests set a fixed version through the `TestMain` seam.

- Red first: `TestRunningVersionOfACheckoutBuildIsTheLastTag` and `TestFooterOfADevelopmentBuildNamesTheLastTag` failed with 5 failure lines (`runningVersion() = "9.9.9", want "4.5.6"` and the footer with the var); the five negative cases (no commit, no tag behind the pseudo-version, a patch of 0, a pre-release base, `(devel)`) already held. Mutation proofs, each named by its case: no commit check (the installation case returns the tag), the patch not minus one (3 cases), a patch of 0 accepted (`4.5.-1`), `+dirty` not accepted.

## 2026-10-20 — the unused bump scripts and the short Quality are removed ([#237](https://github.com/yveshanoulle/forsgren/issues/237), step 6 of 8)

forsgren issue 237, step 6 of 8, patch. Nothing an installation sees changes. What the Release workflow stopped calling in step 5b is deleted: `release_bump.sh`, `release_commit.sh`, `release_bump_diff.sh`, `lib_release_bump_scope.sh`, `release_bump_scope.txt`, `quality_bump_gates.txt`, `run_short_quality.sh` and the self-tests `test_release_bump.sh`, `test_release_commit.sh`, `test_release_bump_diff.sh`, `test_run_short_quality.sh` and `test_quality_scope.sh`. `quality.yml` loses its `scope` input, the green parent and the two version inputs, the bump diff check and the short PRE gates (a by-hand run is the full Quality, as before); `render_quality_summary.sh` no longer knows the short Quality (`QS_SHORT_QUALITY`, `QS_DIFF_OUTCOME`). `release_quality.sh` keeps `check` and `head`; its `dispatch` and `dispatch-bump` modes went with the `quality-bump` and `quality-resumed` steps they served. Five rows left the order file, so `MIN_GATES` goes from 153 to 148, and the docs rows (`docs/gate-classification.md`, `docs/ci.md`, `CONTRIBUTING.md`, `CLAUDE.md`) went with them.

- Red first: a new section 10 of `test_release_workflow.sh` asserts that the twelve files are gone, that no tracked file except this one names them or the words `dispatch-bump`, `scope=bump`, `QS_SHORT_QUALITY`, `QS_DIFF_OUTCOME`, `summary_short_note`, `quality-bump` and `quality-resumed`, and that `quality.yml` has no `scope` input. It failed against 05c89aa with 128 failure lines (12 files still existing).
- Before the deletion each file was proved unused by name across the repository (workflows, Scripts, docs, Go code): the only callers were each other, their self-tests, order-file rows and docs rows.

## 2026-10-20 — a release tags main's head and makes no bump commit ([#237](https://github.com/yveshanoulle/forsgren/issues/237), step 5b of 8)

forsgren issue 237, step 5b of 8, minor. How forsgren is released changes: the Release workflow no longer bumps, tests, commits or pushes anything. After Quality is green on main's head and the plan, it checks the version is free, checks main's head has not moved (`release_quality.sh head`, the step right before the publish), tags that sha (`RELEASE_SHA`, formerly `BUMP_SHA`) with the release, requires `go install` at that sha to report `vX.Y.Z` (`release_verify_install.sh`, before any pin moves), and then does the pins and the preview deploy as before. Installers notice only that there is no bump commit; it is minor because the release process, which the installations' pins rely on, is rewired. `resume: publish` is gone and `resume: pins` also reruns the install check; the job needs `actions: read` instead of `actions: write`, since nothing is dispatched. `release_report.sh` has advice for the head check and the install check (resume: pins reruns it; no pin by hand). A major is refused by the plan until every agent file has its proof run on the new major (`release_agent_proofs.sh`, with its self-test and the real agent files held to one common major); that replaces `TestEveryAgentFileWasTestedOnTheRunningMajor`, which read `var version`, retired because no release bumps it. `release_bump.sh`, `release_commit.sh` and `release_bump_diff.sh` are no longer called; step 6 removes them.

- Red first: `test_release_workflow.sh` failed on today's workflow for the new step list, `RELEASE_SHA`, the head check before the publish and the install check before the pins, and for any `git commit` or `git push`; the plan's major refusal, `resume` publish as a usage error and the report's advice failed at runtime. Mutation proofs: a `git push` added back, the install check moved after the pins, the head check removed, a head check of another sha, a release at another sha, an install check skipped when resuming, and the agent-proof mutants.

## 2026-10-20 — the release gets its install check and a head check ([#237](https://github.com/yveshanoulle/forsgren/issues/237), step 5a of 8)

forsgren issue 237, step 5a of 8, patch. Two building blocks for the release that tags main's Quality-green head without a bump commit; the Release workflow does not call them yet, so the current release keeps working (step 5b wires them). `Scripts/release_quality.sh head <sha>` is green when main's head (read through gh) still is the commit Quality was proved green on, and red naming both shas when main has moved or the head cannot be read. `Scripts/release_verify_install.sh <X.Y.Z> <sha>` runs `go install` of the module at the sha into a temporary GOBIN and requires `go version -m` to report `vX.Y.Z`, retrying while the module proxy catches up (default 5 tries, 30 s apart); on failure its `::error::` says what installations show meanwhile (the fallback version of `cmd/forsgren/main.go`), that `resume: pins` reruns the check and that no pin may move onto that sha. Its self-test is an order-file row (152) and `test_gate_wiring.sh` knows the script.

- Red first: the head cases (moved main, unreadable head) and all verify-install cases failed at runtime against exit-0 stubs. Mutation proofs: a head check that never compares passes a moved main; a version check that accepts any module version passes a pseudo-version; a verify without the retry misses a late tag.

## 2026-10-20 — the docs name no running version ([#237](https://github.com/yveshanoulle/forsgren/issues/237), step 4 of 7)

forsgren issue 237, step 4 of 7, patch. `README.md` and `docs/` no longer write the version of the day: the footer, `Built with` and setup-issue-title examples say `<version>`. `TestDocsNameNoRunningVersion` replaces the docs version pin: no doc holds "Forsgren X.Y.Z" or "forsgren X.Y.Z needs more configuration" with any version, and the released version (`var version`) appears nowhere except right after a history phrase (since, from, in, upgrading to, until); other past versions ("From 1.3.0", "v0.8.7 to v1.0.0") stay. `TestDocsKeepTheirVersionPlaceholders` keeps a reworded doc from emptying the pin. `Scripts/release_bump_scope.txt` lost its README and docs rows, `release_bump.sh` rewrites `main.go` alone, and the release bump self-tests expect exactly that. With `var version` set to `1.11.9`, no test fails. `runningVersion` is also split (structure only; restores devbuild.go to 10.0): `usableBuildInfo` decides whether there is build information to read the version from, so no conditional has more than one `||`.

- Red first: the new pin failed on 15 findings across `docs/ci.md`, `docs/configuration.md`, `docs/pages-and-views.md` and `docs/updating-and-releases.md`, each with its file and line.

## 2026-10-20 — the tests stop pinning the released version ([#237](https://github.com/yveshanoulle/forsgren/issues/237), step 3 of 7)

forsgren issue 237, step 3 of 7, patch. The tests of `cmd/forsgren` run as a fixed version through one seam, a `TestMain` that sets `var version` to `9.9.9`; the page package's tests render `Placeholder(testVersion)` with the same value, so the 29 page goldens say `9.9.9` and a release touches none of them (regenerated with the existing `-update` flag). The newer-release examples derive from it (`9.9.10`, by `nextPatch`), no longer literals. `TestNoTestPinsTheReleasedVersion` fails for any test file or golden that names the value of `var version` or the next patch. With `var version` set to `1.11.9`, 40 tests failed before and only the docs-version test fails after; step 4 handles the docs.

## 2026-10-20 — the install by commit reports the tag ([#237](https://github.com/yveshanoulle/forsgren/issues/237), step 2 of 7)

forsgren issue 237, step 2 of 7, patch. Measured with `go install github.com/yveshanoulle/forsgren/cmd/forsgren@<ref>` and `go version -m`: the commit the tag v1.11.1 points at (790b3f4) records `v1.11.1`, the tag `v1.11.1` records `v1.11.1`, and an untagged commit of main (fc3b9cd) records `v1.11.2-0.20261020113112-fc3b9cd8afaa`. So a pin on a commit that carries the tag reports the release, and an untagged build falls back to `var version`. No code change; `TestRunningVersionOfAnInstallationByCommit` pins the two strings.

- Red on a mutant: a resolver whose pattern accepts pseudo-versions fails the untagged case with `runningVersion() = "1.11.2", want "0.0.0-test"`.

## 2026-10-20 — the running version comes from one resolver ([#237](https://github.com/yveshanoulle/forsgren/issues/237), step 1 of 7)

forsgren issue 237, step 1 of 7, patch. `runningVersion()` in `cmd/forsgren/devbuild.go` is the one place the version is read for output: an ldflags `-X main.version` value as is; else the build information's module version when it is a clean `vX.Y.Z`, without its `v`; else `var version`, with the existing `+dev (sha)` footer logic. The render, summary, setup-check and install-README call sites use it. No visible change: goldens, footer and docs are unchanged.

- Red first: `TestRunningVersionComesFromOneResolver` failed for `v1.12.0` (got `1.11.1`, want `1.12.0`). Mutation proofs: `v` not stripped, the end anchor of the clean-version pattern removed (pseudo-version, pre-release and `+dirty` cases fail), and the ldflags check removed each fail with their reason.

## 2026-10-20 — the Release workflow starts the preview deploy of the release ([#236](https://github.com/yveshanoulle/forsgren/issues/236), step 1 of 1)

After a release the preview site could name the version before the metrics site: the bump commit is pushed with the job's token, which starts no Quality run with a preview job, so the preview deploy waited for the next push to main. `release.yml` has a new step after the metrics step, "Start the preview deploy of the release", that runs `Scripts/dispatch_preview.sh` with the bump sha and gets `PREVIEW_DISPATCH_TOKEN` (and only that step does). It also runs for `resume: pins` and `resume: publish`. A failed start prints an `::error::` line with a red cross and fails the step; there is no `continue-on-error` and no `|| true`. The release is already published by then and stays published. Patch.

- Red first: `Scripts/test_release_workflow.sh` failed with "there is no step named 'Start the preview deploy of the release'", the missing id and outcome, and the token appearing 0 times; five mutation proofs pin the step (removed, wrong sha, no token, a failure that only warns, a failure that is ignored).
- Not in this step: `Scripts/release_report.sh` does not yet name the `preview` step in its summary advice.

## 2026-10-20 — a one-time catch-up reads the comments of stored failure issues with an empty failure start ([#245](https://github.com/yveshanoulle/forsgren/issues/245))

Failure issues stored before `collect` read their comments (forsgren#37) kept an empty `failure_start` even when a comment holds the record block. Like the withdrawn-failures catch-up (forsgren#155), `collect` now does a one-time catch-up per repository (`internal/collect/startscatchup.go`): each stored failure issue with an empty `failure_start` that is open or was opened in the DORA window, and that no withdrawal takes back, has its comments read once with `CommentRecords`, and a block found there is stored as a new line. A refused read fails the repository. The new mark file `data/starts_checked.csv` (starts checked format v1, a row per repository, in the mark-file table and known to the data guard) is written only when every repository of the run finished, so a run that failed or was cut short does the catch-up again and an installation that has done it gets no second one.

- Red first: the catch-up cases of `internal/collect/startscatchup_test.go` (comments read once, block stored, marked done, not repeated; not marked after a refused read) and the mark file's round trip failed; the case that a closed old failure or one with a start is left alone is a pin that holds from the start. The data guard's self-test failed on the new `starts_checked.csv` arm.

## 2026-10-20 — collect reads the failure record block from an issue's comments when the body has none ([#37](https://github.com/yveshanoulle/forsgren/issues/37))

Another estate repository writes the record block (`failure-start`, `failed-build`, `fixed-build`) in a comment of its own, so forsgren stored an empty `failure_start` for each of its failure issues. `collect` now reads the issue's comments when its body gives no `failure-start`: one request per such issue (`github.Client.CommentRecords`, every page up to the limit), never for an issue whose body has the block, so the body wins and a newer block in a comment does not override it. Among the comments the first one with a `failure-start` counts, oldest first; the lines of different comments are never combined. A refused read of the comments fails the repository like the other reads, never a silent empty value; a list cut at the page limit is named on stderr; an issue with no block anywhere is stored with an empty `failure_start` and named on stderr as before ("in its body or its comments"). An issue is looked at again only when it is listed again, so when its update time moved. Recovery time is unchanged. Not in this step: a backfill of the failure issues already stored with an empty `failure_start` (they are repaired when their issue is next updated).

- Red first: with a stub, `go test -run` showed `TestCommentRecordsReadsTheBlockOfEachComment`, `TestCommentRecordsFollowsTheLinkNext`, `TestCommentRecordsRefusesWhatItCannotRead` and the collect cases (comment block, no block anywhere, refused comments read) failing; the body-wins case is a pin that holds from the start.
- `CommentRecords` and `commentStart` are registered at 100.0 in `coverage_thresholds.json`.

## 2026-10-20 — the Quality run page shows details only for gates that are not green ([#235](https://github.com/yveshanoulle/forsgren/issues/235))

Under the gate table the Quality run page printed the full output of every gate, green ones included: the whole Go test log, each coverage function and every self-test case, thousands of lines. `Scripts/render_quality_report.sh` is now canon `render_quality_report v3` (with `test_render_quality_report v3`): the page keeps the headline, the key numbers and the gate table, then the details of the gates whose mark is not the green check only, so a green run ends after the table and the baseline sections. The full output stays in the job log. The sites take the same v3 byte-identical through their own issues.

- Red first: case 13 (one green and one red gate) failed five times, for example `the green gate's details are left out — did NOT expect: green gate output line`; the two older cases that expected a green gate's heading now expect it left out.
- Mutation proof (case 14): a renderer that prints every gate's details is caught, naming the green gate.
- `Scripts/test_quality_summary_first.sh` and `Scripts/test_step_summary_isolation.sh` still hold.

## 2026-10-20 — the baseline report self-test carries canon v3 ([#244](https://github.com/yveshanoulle/forsgren/issues/244))

`Scripts/test_report_baselines.sh` changed content in forsgren#226 (the cases for every further browser baseline) but kept its `# canon: test_report_baselines v2` line. It now says `v3`, as does its row in `docs/gate-classification.md`, so the copies in the estate's repositories end byte-identical. A version line only: no behaviour changed, so no red.

## 2026-10-20 — html duplication takes canon v2: jscpd's threshold line is rewritten and a jscpd crash is shown ([#242](https://github.com/yveshanoulle/forsgren/issues/242))

`Scripts/check_html_dupl.sh` is now canon `check_html_dupl` v2 and `Scripts/test_check_html_dupl.sh` v3, both byte-identical to another estate repository's. The gate runs jscpd with a threshold of 0 only to make it print the number, so an over-ceiling red used to show jscpd's own `over threshold (0%)` line as if the gate demanded 0%. The red now shows the gate's own ceiling and verdict and keeps the measured percentage on a line of its own; a jscpd failure for any other reason (exit not 0 or 1) shows jscpd's own error and is exit 2. The wrapper `Scripts/check_html_dupl_site.sh` does not read that line and needed no change.

- Red first: the v3 test on the v1 gate failed five times, for example `the red does not show jscpd's over threshold (0%) line — output carries 'over threshold (0%)'` and `the crash shows jscpd's own error — output does not carry 'boom, cannot read config'`.
- The test carries two new mutation proofs (D: jscpd's output shown unfiltered; E: no jscpd-failure check).

## 2026-10-20 — the gate-failure summary takes only lines that start with the cross ([#243](https://github.com/yveshanoulle/forsgren/issues/243))

`Scripts/summarize_gate_failure.sh`, which fills the Errors list of an sfl or FBP run, matched the cross mark anywhere in a line. A self-test's passing ok: lines that quote the marker as a needle matched too, and with the cap of six shown lines they pushed the real FAIL lines out. It now takes only lines that start with the marker after any indentation (`grep -E '^[[:space:]]*❌'`); the bare `FAIL` and tail fallbacks are unchanged. Ported from the same fix in another estate repository.

- Red first: the new case 6 of `Scripts/test_summarize_gate_failure.sh` (six quoting ok lines, then three real FAIL lines, one indented) failed four times, for example `the first real failure is shown past six quoting ok lines — expected to find: first real failure`.
- Mutation proof: a copy of the summarizer that matches the marker anywhere shows the quoting ok lines and pushes the real failures out.

## 2026-10-19 — CI checks the private names in every new commit message ([#213](https://github.com/yveshanoulle/forsgren/issues/213))

`FBP.sh` already refused a commit message that names a private name, but a pull request's commits and a hand-made push never passed through it. The second job of `.github/workflows/dco.yml`, **Private names in commit messages**, now sends the message of every commit a pull request or a push to `main` brings to `Scripts/check_private_names.sh --message -` (canon v2, unchanged), through the new `Scripts/check_commit_messages.sh`. A hit is red, naming the short sha and the commit's number, never a name, a message or a subject; history is not rewritten. A push is listed by `Scripts/dco_push_commits.sh --fresh`: a normal range as before, but a new branch (all-zero before) or a before the checkout does not have (a force-push) checks every commit of the pushed head that is on no other branch or tag, never the head commit alone and never nothing. In Actions the list must exist (exit 2 naming the secret when it is unset or emptied, a fork's pull request included), where `--message` alone would pass. The pull request listing moved from the workflow into `Scripts/dco_pr_commits.sh`, shared by both jobs. The job is in `dco.yml` and not `quality.yml` because that workflow already runs on every pull request and push without checking out the pull request's code and has the history and both listings. The canon gate needed no change.

- Red first: `Scripts/test_check_commit_messages.sh` (stub check and listing) failed 22 times, for example `a hit in the middle commit is red, naming that commit: the gate exited 0` and `a new branch (all-zero before) checks every commit on no other branch: the gate failed without saying ...` (the listing refused `--fresh`).
- Two mutation proofs: judging only the last commit turns the middle-commit case green; a listing that skips the range when before is unavailable stops naming the commit.
- `Scripts/test_gate_wiring.sh` requires `dco.yml` to run the check, the pull request listing and the push listing with `--fresh` (three mutations), and the self-test to be an order-file row (row 149, `MIN_GATES` 151).

## 2026-10-19 — the browser gate also opens the site rendered from fixture data ([#226](https://github.com/yveshanoulle/forsgren/issues/226))

`Scripts/build_site.sh` renders the site without a config or history, so the History page the browser gate opened showed only its "no history" message, and the charts and tables of the History, Daily and Issues pages were never checked by axe. `Scripts/build_fixture_site.sh` now renders the site from the made-up fixture of `Scripts/testdata/fixture_site/` (acme/api, acme/ios-app and acme/cli; render time pinned), red when the History page has no chart or the Daily or Issues page no rows. A new gate, `Scripts/gate_browser_fixture.sh` (forsgren only; the canon `gate_browser.sh` is unchanged), runs the browser gate's engine on it, with the same checks, manifest, exceptions and variants and its own empty shrink-only baseline, `Scripts/browser_gate_fixture_baseline.txt`, which `Scripts/report_baselines.sh browser` now shows. Seen red first: its self-test (`Scripts/test_gate_browser_fixture.sh`, two mutation proofs), the fixture build (cases 20 to 30 of `Scripts/test_build_site.sh`, one mutation proof) and the report case. The gate found nothing on the data pages.

## 2026-10-19 — the shared trigger scope test needs no globs file when there is none ([#240](https://github.com/yveshanoulle/forsgren/issues/240), step 3)

`Scripts/test_quality_trigger_scope.sh` is now `test_quality_trigger_scope v3`: its nested sandbox cases copy `Scripts/quality_trigger_globs.txt` when the repository has one and otherwise run on an empty one of their own. forsgren's comment-only copy of that file, added in step 1 for v2, is removed. The sites take v3 through their own issues, one per repository.

- Red first: with the file removed, v2 aborted with `cp: Scripts/quality_trigger_globs.txt: No such file or directory` and `FAIL: quality trigger scope check aborted before completing`; green with v3.

## 2026-10-19 — render_gate_list.sh carries its canon line ([#240](https://github.com/yveshanoulle/forsgren/issues/240), step 2)

`Scripts/render_gate_list.sh`, the generator of the "What we check" list of CONTRIBUTING.md, has the line `# canon: render_gate_list v1`, so the estate's parity check can tell it is the shared copy; the sites take it afterwards. The script itself is unchanged.

- Red first: `Scripts/test_gate_wiring.sh` now requires the canon line in the first 5 lines of the generator, and failed with `Scripts/render_gate_list.sh has no '# canon: render_gate_list v1' line`; green after.

## 2026-10-19 — the private-names gate leaves out a repository's own name ([#241](https://github.com/yveshanoulle/forsgren/issues/241))

A repository's own name is not private inside that repository. `Scripts/check_private_names.sh` (canon v2) drops the basename of the origin remote (https, scp or ssh, with or without .git, compared ignoring case) from the list, in the tree scan and in `--message`, so a commit can refer to its own repository's issues. Every other listed name stays blocked, a repository with no origin keeps every name, and the output still never prints a name.

- Red first: a file and a message naming the own name (four URL forms, mixed case) were refused; green after. Another listed name in the same repository and a repository with no origin stay red. A mutant that does not leave the own name out is caught for that reason.
- The sites take v2 through their own issues.

---

## 2026-10-19 — the HUP case of the aborted-run test no longer depends on how it is launched ([#234](https://github.com/yveshanoulle/forsgren/issues/234))

`Scripts/test_fbp_aborted.sh` failed once in its HUP case and passed on rerun. FBP.sh installs its EXIT, TERM, INT and HUP traps before it starts `./sfl.sh pre`, and the stub that sends the signal runs only from there, so the signal cannot arrive before the traps. The cause was the launch: a signal ignored when a non-interactive bash starts is never trapped, and the sandbox reset that disposition for INT only, so a fixture started under nohup (or by a harness that ignores HUP) saw FBP.sh finish with "All checks passed" and exit 0 on a HUP.

- The sandbox now resets INT, TERM and HUP to the default before FBP.sh starts.
- The test runs each signal again with that signal ignored in the fixture (red before the reset: HUP and TERM printed "All checks passed" and exited 0), and checks the ready condition by source order: all four traps come before the first `./sfl.sh pre`, with a mutant that moves the HUP trap after it, caught for that reason. No sleep, no change to FBP.sh.

---

## 2026-10-19 — forsgren's own Quality pins have their own gate ([#240](https://github.com/yveshanoulle/forsgren/issues/240), step 1)

`Scripts/test_quality_trigger_scope.sh` is now the sites' shared `test_quality_trigger_scope v2`, byte-identical: either `quality.yml` has no `paths` or `paths-ignore` filter (then it reads no settings), or its `paths` filter holds every glob the gates read, and it must have a `pull_request` trigger. forsgren's own pins moved, with their mutation proofs, into the new `Scripts/test_quality_runner_pins.sh` (row 78): push and `pull_request` on `main` with no `paths` or `paths-ignore` filter, no `pull_request_target`, `workflow_dispatch`, and every job on `macos-latest`.

- `Scripts/quality_trigger_globs.txt` is the data file the shared script requires to exist; forsgren keeps it without a glob.
- `MIN_GATES` is 148. Red first: a runner-pins stub that accepts everything fails each of its nine mutation proofs.

## 2026-10-19 — the job summary says whether the history was collected in full ([#64](https://github.com/yveshanoulle/forsgren/issues/64), step 3c)

A green run is not a complete history. The run summary now has a `Collected:` line: "complete" only when collect's report says so, otherwise "incomplete, budget reached;" with each repository cut short (how far it kept, that its issues were not read, the recent read when it was discarded), the time the budget resets, and the repositories that failed on GitHub's primary or secondary rate limit, named apart. A repository cut short with nothing kept on consecutive runs is named "not progressing". A missing report is "unknown", never complete.

- `forsgren run-summary --collect-report <path>` reads the file `collect --cut-report` wrote; `metrics.yml` passes `${RUNNER_TEMP}/collect-report` from the collect step to the summary step, and `Scripts/test_metrics_workflow.sh` pins both flags, with mutations for a missing flag and another file.
- Red first (the flag did not exist, the workflow passed neither file). This completes step 3 of #64.

## 2026-10-19 — collect reports what it left incomplete ([#64](https://github.com/yveshanoulle/forsgren/issues/64), step 3b)

`forsgren collect --cut-report <path>` writes a small report of the run: complete, or incomplete with the time the request budget resets, the repositories cut short (how far the read mark moved, what became of the recent read, that the issues were not read, and whether it progressed), and the repositories that failed on GitHub's primary or secondary rate limit. The job summary line that prints it is step 3c.

- A repository cut short that keeps nothing on two runs in a row is reported as stalled. `data/cut_runs.csv` (a new mark file, guarded by the data guard) notes the first run of such a streak, and is cleared when the repository progresses or is read to the end.
- The file is removed first thing, and a run that was refused writes none, so a missing file reads as unknown, never as complete.
- Red first (no flag, no report, no mark file, the data guard's drift check). Tests use fixture servers, never the network.

## 2026-10-19 — GitHub's two rate limits are named apart ([#64](https://github.com/yveshanoulle/forsgren/issues/64), step 3a)

A failed repository now says which of GitHub's limits it met: "GitHub's primary rate limit is reached; it resets at ..." when no request is left in the hour, and "GitHub's secondary rate limit is reached; GitHub asks to retry after 60 seconds" for a `Retry-After`, or a 429 that says nothing else. Both stay failures, neither is the budget's cut, and both are still a rate limit for the lookups that treat the two alike (the waiting pull request and the pull-request lookups). A 429 with no header used to be reported as a plain error status.

- Red first (the old error named neither limit, a bare 429 was a plain status error). Tests use fixture servers, never the network.
- Still to come in step 3: the report file collect writes, the repositories that make no progress, and the job summary line ("Collected: complete" or "incomplete").

## 2026-10-19 — a cut recent read keeps its whole days when the next window still reaches the rest ([#64](https://github.com/yveshanoulle/forsgren/issues/64), step 2b)

When the budget runs out in what is new since the last run, `collect` now keeps the newest days it read whole, with their commits, if the next run's window (7 days before the newest deployment stored) still starts at or before the newest deployment stored before this run, so nothing that was not read can fall out of it. Otherwise it stores nothing, as before, and reads it again.

- The boundary is tested to the second: exactly 7 days after the stored deployment keeps the day, one second more stores nothing, and a mutation test shows that keeping a day beyond the reach would lose a deployment for good.
- A deployment read by the next run between two stored successes gets no commits and a warning, as the existing rule has it, so no commit counts twice.
- The read marks do not move for a recent read.

## 2026-10-19 — a repository cut short keeps what it read whole ([#64](https://github.com/yveshanoulle/forsgren/issues/64), step 2a)

Throwing a whole repository away at the request budget's margin meant a very busy repository could meet the same wall every day. Now a cut repository keeps every UTC calendar day it read whole, and the next run goes on behind it.

- In the first chunk and the older chunk, `collect` stores each day after the day of the item the budget stopped at: its deployments and their commits. The read mark (`reach.csv`) moves only to the start of the oldest such day; the day the cut fell in, and everything older, is read again.
- A deployment is whole only with its statuses and its commits comparison, so the statuses are read only while the budget has room for the comparisons of the successes read so far, and the comparisons are sent newest first. A success compared again on a later run leaves the commits file as an uncut run leaves it.
- The issue reads are stored as a group or not at all: a cut in them keeps the deployments and moves no issue mark. A cut in the recent read of a repository with a read mark still stores none of it (step 2b). A cut that keeps no day moves no mark and is named on stderr every run.
- Red first (nothing of a half-read chunk was stored, a repository could not progress across runs), with a mutation-style test that a half-read day is not kept, a midnight boundary test, and a test that a chunk bigger than one run's budget ends where an uncut run ends. Tests use fixture servers, never the network. The job summary line is step 3.

## 2026-10-19 — collect stops before the token's request budget is gone ([#64](https://github.com/yveshanoulle/forsgren/issues/64), step 1)

A large first read can use thousands of requests, and forsgren noticed the limit only when GitHub refused a request at 0. Now `collect` reads GitHub's rate-limit headers on every answer and starts no further request once fewer than max(100, 5% of the limit) are left (250 for a token with 5,000 an hour), so the run's last steps and anything else using the token keep some of the hour.

- The repository it was reading is cut short: it stores nothing for it, moves none of its read marks, and stderr names it with the reset time. Every repository behind it is cut short the same way before its first request; the repositories already done keep what they stored.
- The run exits 0: meeting the limit is not a failure. A request GitHub refuses with none left stays a failed repository, as before. The next run reads the cut-short repositories again.
- The one-time withdrawn-failures catch-up waits until no repository was cut short.
- Not yet: the job summary naming the repositories cut short (step 2). The margin is kept by the client for collect only; the lookups of the render and the setup issue are unchanged.
- Red first (a client at its margin kept sending, a run past it stored the repository). Tests use fixture servers, never the network.

## 2026-10-19 — a preview build shows a development version in the footer ([#224](https://github.com/yveshanoulle/forsgren/issues/224), step 1)

A build made from a checkout, as the preview site's, shows its version with `+dev` and the short commit it is built from in the page footer, "Forsgren 1.11.1+dev (c41db9e)", so the preview can no longer be taken for the release. The commit is plain text: the repository-links gate allows no link into a repository. A release build, installed at a pinned commit, shows its version alone and its pages are unchanged. `Scripts/build_site.sh` builds with `-buildvcs=false`, so the gates still render a release page. Tests pin both footers and the commit read from the build information. Step 2 (no bump commit, the version from the release tag) stays open on the issue.

## 2026-10-19 — the gate table shows plain gate names again ([#219](https://github.com/yveshanoulle/forsgren/issues/219), step 4)

The gate table of the Quality run report shows plain gate names again: GitHub job summaries do not keep in-page links, so the links to each gate's section (and their anchors) did nothing when clicked and are gone. The Checks column, the details sections and the "What we check" list in CONTRIBUTING.md are unchanged. A test pins that no table row links and no anchor line is written, with a mutation proof for a renderer that still links a label. Tooling only.

## 2026-10-19 — the key numbers are the first thing on the Quality run page again ([#233](https://github.com/yveshanoulle/forsgren/issues/233))

The headline block of the Quality run (status, gates per phase, Go tests, total checks, coverage, pages, version, commit, trigger, duration) is again the first thing on the run summary page.

- The cause: the Quality run executes the self-tests inside a gate step, CI exports `GITHUB_STEP_SUMMARY`, and the self-tests of the release report, the token expiry check, the release pre-check and the baselines report ran their scripts under that ambient variable. Their fixture output (many blocks with temporary paths and example releases) was appended to the real run page long before the headline step. `Scripts/lib_selftest.sh` now gives every self-test a summary file of its own, as `lib_git_sandbox.sh` does for `GIT_DIR`.
- `Scripts/test_step_summary_isolation.sh` pins it: every self-test that names a script appending to the step summary runs with `GITHUB_STEP_SUMMARY` pointing at a decoy file, which must stay empty. It failed on four self-tests before the change.
- The note of the short Quality of a release bump was the one real step before the headline; it now goes to a file that the summary step appends after the gate table. `Scripts/test_quality_summary_first.sh` pins that no step before the summary step writes the page and that the headline comes before the gate table.
- Tooling only.

## 2026-10-18 — the shared gate scripts and self-tests are byte-identical with the shared versions ([#227](https://github.com/yveshanoulle/forsgren/issues/227))

Forsgren's copies of the shared gate scripts, their self-tests and the git sandbox (`lib_git_sandbox.sh`, its guard and its isolation test) are the shared versions again, with no adaptation of their own; the one repository-specific input, the shellcheck exclusions, is a data file. Tooling only.

## 2026-10-18 — the Quality report shows what each gate checked ([#219](https://github.com/yveshanoulle/forsgren/issues/219))

The gate table of the Quality run report is now the place to see what is checked.

- A Checks column: the number of `ok:` and check-mark lines in each gate's own output. A gate that prints none shows `not counted`, never 0; a gate whose details cannot be read shows `not readable`.
- Each gate label links to its section below the table, through an explicit anchor (`gate-` and the label with every character outside A-Za-z0-9 turned into `_`); the rule is pinned in a test. Whether GitHub keeps the anchors in a job summary is proved on a real run, not in this change.
- CONTRIBUTING.md gets a "What we check" list, generated from `Scripts/gate_report_order.txt` by `Scripts/render_gate_list.sh` and kept in sync by a test.
- Red first. Mutation proofs: 0 for an uncounted gate, no links, no anchors, an unreadable gate shown as not counted, the verdict line counted.

## 2026-10-18 — a read-only pre-check before a Release ([#231](https://github.com/yveshanoulle/forsgren/issues/231), step 3)

The 1.11.0 Release stopped at its plan on an issue closed two minutes after 1.10.0 with no label; nothing said so before the run.

- `Scripts/release_precheck.sh [patch|minor|major]` runs the same `Scripts/release_plan.sh` against the real data and prints its verdict, the table of blocking issues in the Release run page's shape, and a ✅ list of the ready issues. Exit 0 when the Release would pass its plan, 1 when it would stop. It writes nothing.
- `release_plan.sh --all` names every kind of block at once (open with commits, unlabelled, needs a higher bump) and prints a `ready=` line per labelled issue; the default behaviour is unchanged. `release_report.sh --table <plan output>` renders the table and the ready list with the code of the run page, so there is no second table.
- Red first; the parity test feeds the pre-check and the Release's report the same data for each kind of block and compares the tables (it found the one difference, the bump named in the "needs minor" row). Mutation proofs: no `--all`, open issues with commits ignored, exit 0 whatever the plan said, a hand-written table. `MIN_GATES` 144 to 145.
- Fix (Quality was red on main after step 3): the pre-check test read the ambient `GITHUB_REPOSITORY`/`GH_REPO`, which CI sets and a laptop does not, so the table linked its issues only in CI. `Scripts/test_release_precheck.sh` now runs every run through its own repository variables (the table cases in a plain pass and a linked pass), `Scripts/test_release_report.sh` unsets `GH_REPO`; a copy of the test that reads the ambient variable fails when `GITHUB_REPOSITORY` is exported (mutation proof).

## 2026-10-18 — a red static check stops the run early ([#231](https://github.com/yveshanoulle/forsgren/issues/231), step 2)

FBP ran all 117 steps for 22 minutes after a shellcheck red that appeared about minute 4.

- The fast static checks (gofmt check, Go lint, actionlint, shellcheck, yamllint, zizmor), each directly after its self-test, moved in `Scripts/gate_report_order.txt` into one block straight after the secret-class rows, between the marker lines `#! static-block-start` and `#! static-block-end` (comments to every other reader). `sfl.sh` runs the block to its end; when a row is red it runs no later gate: each is printed `⏭ skipped: <label> (stopped after the static block)`, is a `⏭ skip` row of the step table, and the summary says `stopped after the static block`.
- `FBP.sh` reads `.build/sfl-static-stop.log`, skips the build and the POST gates (the POST gates named) and makes the RED commit as for any red. After the block the gates keep running all and reporting all.
- CI keeps running everything: `run_ci_phase.sh` ignores the markers, so a pull request shows all its reds. Pinned, with the block's contents, in `Scripts/test_sfl_static_block.sh`.
- Red first (against the old `sfl.sh` the later gates ran); mutation proofs for a block boundary the runner ignores and for skipped gates that are not named. `MIN_GATES` 143 to 144; `sfl.sh` v6.

## 2026-10-18 — the test duplication gate fails when the tool reports something other than duplication ([#217](https://github.com/yveshanoulle/forsgren/issues/217))

- An exit of 1 from golangci-lint without a `(dupl)` line (a typecheck or build error, which the tool reports as an issue) used to read as OK. It is now a tooling error: exit 2, with the tool's output shown. Exit 1 with `(dupl)` lines and exit 0 are unchanged.
- Red first with a stub tool that exits 1 and prints a typecheck line; mutation proof: putting "exit 1 without dupl lines is OK" back is caught by that case.

## 2026-10-18 — a writer's pre-check runs the fast gates and the tests that read the changed files ([#231](https://github.com/yveshanoulle/forsgren/issues/231), step 1)

`precheck.sh` is what a writer runs before handing a change back: the checks FBP would find red after minutes, on the changed files, in seconds.

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

- `quality.yml` takes a `scope` (`full` by default; a push and a pull request are always full) and, for `bump`, the green parent and the two versions. The short Quality runs `release_bump_diff.sh` first, then only the gates of `Scripts/quality_bump_gates.txt` (secret scan, Go tests, golden pages, Go lint) through `run_short_quality.sh`, then the site build; the run page says `short Quality for a release bump: N gates` and names every gate not run.
- The Release workflow dispatches `scope=bump` with the commit Quality was green on, so a bump on any other commit is red; `resume = publish` keeps the full Quality. The run report says `short Quality (bump)` with the run's link.
- Red first for the runner, the dispatch, the pin of the scope (`test_quality_scope.sh`), the release pins and the report; mutation proofs for a short Quality that skips the diff check, a release that dispatches `scope=full`, a list that ignores itself and a summary that claims POST ran. `MIN_GATES` 138 to 140.

## 2026-10-18 — a release bump commit is checked to hold only the version bump ([#230](https://github.com/yveshanoulle/forsgren/issues/230), step 1)

A bump commit that changed more than the version, or sat on a commit Quality was not green on, would have been released as it was.

- `release_bump_diff.sh <bump-sha> <green-parent-sha> <old> <new>` is green only when the commit's one parent is the green commit, every changed file is only modified and one the bump may change, and every changed line is its old line with the version replaced (the newer-release example too); each violation is a `FAIL: bump diff:` line naming file and line.
- The files the bump may change are one list, `Scripts/release_bump_scope.txt`, read by `release_bump.sh` and the check alike, so they cannot drift.
- Red first in `test_release_bump_diff.sh` (the real bump on a fixture repository; an extra line, an extra file, a mode change, a wrong parent, a merge commit, a version replaced in a line that also changes); mutation proofs for no parent comparison and for accepting any line of an allowed file. `MIN_GATES` 137 to 138. Not yet wired into the Release workflow (step 2).

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
  - `Scripts/release_plan.sh` computes the bump the labels of the closed issues require and the release notes; `release_bump.sh` makes the version bump of the manual bump commits, goldens included, and run on the tree before the 1.9.3 bump it reproduces that commit byte for byte.
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

