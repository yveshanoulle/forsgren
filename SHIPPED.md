# Shipped — forsgren

History of completed work on forsgren. Append-only.

Conventions:
[CONVENTIONS.md](CONVENTIONS.md).
Active work lives in
[TODO.md](TODO.md).

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
