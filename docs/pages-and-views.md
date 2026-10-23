# Pages and views

**The DORA window** (forsgren#178). All five DORA numbers count back over one
window, `dora_days` in `forsgren.config.yml` (see
[Configuration](configuration.md#configuration)): 30 days unless it is set
to 90 or 180. The sections below say "the last 30 days", the default; with
`dora_days: 90` or `180` read 90 or 180 days there. Durations that are band
edges (a month of 30 days, six months of 180 days) and the 180-day count of
the two slowest frequency bands do not change with the window. The legend
states the window in use, and whether `dora_days` sets it.

## Deployment frequency

The first DORA number on the page (forsgren#12, step 7, package
`internal/metrics`), the first column of the page's table (see [The page](#the-page)):
its DORA band, always shown with the count it comes from, "Between once per
day and once per week · 12", the successful deployments of the last 30
days, or of the last 180 days for a band decided on them ("Between once per
month and once every six months · 3"). When some of those deployments were
made at a weekend, the next column, Weekend deployments, says how many
(forsgren#115, #124; decision #121's rule of no sixth column is overruled).
The cell itself ends with the count, "Between once per day and once per week
· 12". The legend page says which.

**What counts.** A deployment is a history line with the state `success`;
`failure` and `other` lines do not count. A line belongs to the project
whose config lists its repository (names compared ignoring case, as the
config does); a repository no project lists any more is left out. A
repository that deploys several services counts every deploy on its own;
a split per service is forsgren#11.

**The windows** are counted back from the render time, in UTC, in days of
24 hours: a deployment counts when it was created at or after the render
time minus 7 days (the DORA window, 180 days), and not after the render time. A deployment
exactly 7 days old is in the 7-day count.

**The bands** are the six deployment-frequency answers of the current DORA
Quick Check (forsgren#16, step 6), word for word, as mutually exclusive
ranges. The Quick Check asks people how often they deploy; forsgren counts,
and maps a count by its average time between deployments, on the same
edges as lead time's bands: an hour, a day, 7 days, a month of 30 days and
six months of 180 days. A band "between once per X and once per Y" holds Y
and not X, so exactly once a month (1 in 30 days) is between once per week
and once per month. The 30-day count decides whenever it holds a
deployment; only with none in 30 days does the 180-day count tell the two
slowest bands apart:

| Count | DORA band |
| --- | --- |
| 241 and more in 30 days (more than once an hour over an 8-hour day) | On demand (multiple deploys per day) |
| 30 to 240 in 30 days | Between once per hour and once per day |
| 5 to 29 in 30 days (once a week is 30/7, about 4.3) | Between once per day and once per week |
| 1 to 4 in 30 days | Between once per week and once per month |
| none in 30 days, 1 and more in 180 days | Between once per month and once every six months |
| none in 180 days | Less than once per six months |

Over a longer window the edges scale with it, never the count, so each band
stands for the same rate (forsgren#178): an edge per 30 days is multiplied by
`dora_days`/30. At 8 hours, on demand starts at 721 in 90 days and 1441 in
180 days, between once per hour and once per day at 90 and 180, between once
per day and once per week at 15 and 30, and between once per week and once
per month at 3 and 6; with fewer, the 180-day count tells the two slowest
bands apart as above (over 180 days it is the window's own count, so 1 to 5
is between once per month and once every six months).

Once an hour over a working day is `working_hours` × 30 deployments in 30
days (8 × 30 = 240 with the default 8), so on demand is more than that
(forsgren#69, #71); the legend page states the configured day and the numbers
that follow from it. A row whose first
successful deployment is younger than the window (the project total: its
earliest) has not had a whole window to deploy in, so its band uses its
window count scaled to the window: the count × the window's days over its age
in whole days, at least 1 (19 in 9 days count as 63 over 30 days). The count
shown, and the numbers view, stay the plain count.

The band describes throughput over the period, not regularity; the count
makes a burst visible (Yves's ruling on forsgren#12), so the band is never
shown without it, and neither the 30-day nor the 180-day count has a row of
its own.

**Weekend deployments** (forsgren#115, #124). The column of that name,
next to Deployment frequency on the standard and numbers views, is how many
of the successful deployments the frequency cell counts were created on a Saturday or a
Sunday, UTC (the day of `created_at`, the same UTC the windows use; which days
are the weekend is not configurable yet, forsgren#72). It takes its window
from the count it follows: the last 30 days, or the last 180 days when the
30 days hold none, so it is never more than that count. It is `0`, never
blank, when there are none (decision #129). The numbers view shows the
weekend deployments of the last 30 days beside its 30-day count; the scoring
view does not show the column, as the count is no DORA metric and has no
score. It never changes the band (the table is at the default window; at
180 days the window and the 180-day count are one):

| Situation | Frequency cell | Weekend deployments |
| --- | --- | --- |
| 12 in 30 days, 3 on weekends | `· 12` | `3` |
| 0 in 30 days, 3 in 180 days, 1 on a weekend | `· 3` | `1` |
| 0 in 30 days, 3 in 180 days, none on weekends | `· 3` | `0` |
| 0 in 180 days | `· 0` | `0` |

A row with no deployment in its history, successful or failed, says "No
deployments recorded yet" across its six columns. A row whose deployments
all failed is shown in full, so the worst case never looks like no data
(Yves's ruling on decision #35): its frequency is "Less than once per six
months · 0", since it counts successes.

## Lead time for changes

The second DORA number on the page (forsgren#16, steps 4 and 5, package
`internal/metrics`): how long a change takes from its commit to running in
production. The table's second column shows it as a DORA band with the
median and, in brackets, the commits of the last 30 days: "Less than one
hour · 17 min (37)". A row that has deployments but no commit deployed in
the last 30 days says "No lead time yet".

**What counts.** `render` reads `data/commits.csv` next to its `--data`
file, the commits `collect` stored for each successful deployment (see
[History](data-files.md#history)). A missing file is no commit; a file with an unknown version or a
malformed line fails the render with its own message. Yves's rulings:

- **Per commit**, DORA's definition: each commit's lead time runs from its
  author date to the creation time of the successful deployment that
  shipped it.
- **The commits of a deployment** are those since the previous successful
  deployment of its stream: the same repository, rule, environment or
  workflow, and task, while a repository's releases are one stream (see
  [Collecting deployments](data-files.md#collecting-deployments-collect), The commits of each deployment). The first
  success of a stream has none. Failed deployments, and other final
  states, store none: their commits move on to the next successful one. A
  success `collect` skips, with a warning, stores none either.
- **The window:** a commit counts when its deployment was created in the
  last 30 days, counted back from the render time in UTC, both ends
  included, as for deployment frequency. A commit belongs to the project
  whose config lists its repository, compared ignoring case. A commit
  shipped by two deployments (two tasks of one repository) counts once for
  each.
- **The median**, as DORA reports it, because lead times are not normally
  distributed: a few old commits would drag a mean far from the typical
  change. For an even count it is the mean of the two middle lead times.
- **A negative lead time** (a commit authored after its deployment: a
  skewed clock, or an author date set by hand) counts as 0. The commit did
  ship, so dropping it would lose a real change from the count, and 0 is
  the nearest possible value.

**The duration** is written in whole minutes below an hour ("17 minutes",
"less than a minute" below one), hours and minutes below a day ("5 hours
12 minutes"), days and hours above ("3 days 4 hours"). Each part is cut
down, never rounded up, so a median never reads as the next band's edge;
a zero second part is left out.

**The bands** are the six of the current DORA Quick Check, as mutually
exclusive ranges of the median. A month is 30 days and six months 180
days, so every edge is a fixed duration (the page says so too):

| Median lead time | DORA band |
| --- | --- |
| below 1 hour | Less than one hour |
| 1 hour to below 24 hours | Less than one day |
| 24 hours to below 7 days | One day to one week |
| 7 days to below 30 days | One week to one month |
| 30 days to below 180 days | One to six months |
| 180 days and more | More than six months |

The page calls them DORA bands, never Elite, High, Medium or Low.

## Failed deployment recovery time

The third DORA number on the page (forsgren#17, package `internal/metrics`):
DORA's "time it takes to recover from a deployment that fails and requires
immediate intervention". The table's third column shows it as a DORA band
with the median and, in brackets, the recoveries of the last 30 days: "Less
than one day · 3 h (2)", followed by " · 1 recovery not completed yet" when a
stream's latest deployments failed; with none recovered in the window but
one not completed yet, "— · 1 recovery not completed yet", the dash for the
band and the median it does not have yet; with neither, "No failed
deployments". The unit is the recovery, one per run of failures however
many deployments failed in it (Yves's ruling on decision #35), never a
failed deployment. It reads the deployments only, so a withdrawn failure
issue (forsgren#155) does not change it.

**What counts.** Rulings on forsgren#17, taken while Yves was away (each
can be reverted there):

- **Deployments only.** A failure is a line of `data/deployments.csv`
  whose state is `failure`. The web-hosting and TestFlight recorders record
  a failure only once live was touched, which is DORA's "requires
  immediate intervention". A `workflow=` rule stores every run that
  concluded `failure` (see [Collecting deployments](data-files.md#collecting-deployments-collect)), so for such a
  repository a run that failed before touching live counts too. Failure issues (the `failure` label with its
  record block, see [How it gets its data](data-files.md#how-it-gets-its-data)) are the source of change fail
  rate (forsgren#18), not of this number.
- **Recovered by the next success of its stream.** The stream is
  collect's (see [Collecting deployments](data-files.md#collecting-deployments-collect), The commits of each deployment):
  the same repository, compared ignoring case, the same kind, environment
  or workflow, and task; a repository's releases are one stream. A
  success of another stream (deploy-admin after a failed deploy-api)
  recovers nothing. Deployments are taken oldest first, by `created_at`,
  then ID.
- **The time** runs from the failed deployment's `created_at` to the
  success's `created_at`.
- **A run of failures** (failures one after the other in a stream, before
  a success) is one recovery, timed from the first failure of the run,
  since the service was degraded from then on. A deployment in the state
  `other` neither starts nor ends a run.
- **Not recovered yet:** a run with no success after it yet. It is counted
  ("1 recovery not completed yet", at most one per stream) whatever its
  age, but it is not in the median: it has no recovery time yet.
- **The window:** a recovery counts when its success was created in the
  last 30 days, counted back from the render time in UTC, both ends
  included, as for lead time. A deployment created after the render time
  is not there yet. A recovery belongs to the project whose config lists
  its repository, compared ignoring case.
- **The median**, as for lead time, with the count; for an even count the
  mean of the two middle recovery times. The duration is written as lead
  time's is.

**The bands** are DORA's current Quick Check answers for failure recovery,
which are word for word lead time's six (the script the Quick Check loads,
<https://dora.dev/quickcheck/quickcheck.js>, maps both questions to the same
answers: "Less than one hour", "Less than one day", "One day to one week",
"One week to one month", "One to six months", "More than six months"). So
the median recovery time is banded on lead time's edges, a month being 30
days:

| Median recovery time | DORA band |
| --- | --- |
| below 1 hour | Less than one hour |
| 1 hour to below 24 hours | Less than one day |
| 24 hours to below 7 days | One day to one week |
| 7 days to below 30 days | One week to one month |
| 30 days to below 180 days | One to six months |
| 180 days and more | More than six months |

A row whose deployments all failed shows "— · 1 recovery not completed
yet": the worst case, failed and never recovered, is never shown as no data
(decision #35).

## Change fail rate

The fourth DORA number on the page (forsgren#18, package `internal/metrics`):
DORA's share of deployments that cause a failure in production requiring
remediation. The table's fourth column shows it as a DORA band with the
rate and, in brackets, the failed changes of the final deployments of the
last 30 days: "20% · 15% (2 of 13)". With no deployment in the window it
says "No deployments", followed by " · 1 failure issue" when an issue was
opened in it.

**What counts.** Rulings on forsgren#18, taken while Yves was away (each
can be reverted there):

- **The deployments** are the final ones in `data/deployments.csv`,
  successes and failures, created in the last 30 days, counted back from
  the render time in UTC, both ends included, as for lead time and
  recovery time. A deployment in the state `other` (a cancelled run) is
  neither, and one created after the render time is not there yet.
- **A failed change** is a deployment whose state is `failure`, as recovery
  time counts them, or an issue labelled `failure` (forsgren#6) opened in
  the window, from `data/failures.csv` (see [History](data-files.md#history), [Collecting
  deployments](data-files.md#collecting-deployments-collect)). An issue counts once, open or closed, as its newest line
  says, however it was closed, unless it is withdrawn: the label is the
  ruling (forsgren#6), so a stored issue that loses its `failure` label, is
  closed as not planned, or is gone is taken back by a line in
  `data/failures_withdrawn.csv` and no longer counts, as if it were not in
  `failures.csv`; one that gets its label back counts again (forsgren#155,
  see [History](data-files.md#history), The withdrawn failures).
- **Never twice.** What is stored cannot tell which deployment an issue is
  about, so an issue filed about a failed deployment would count twice.
  Per repository, the failed changes are therefore the larger of its failed
  deployments and its failure issues: issues are taken to be about the
  repository's failed deployments as long as there are as many of those. A
  repository whose deployments all succeeded (a crash users hit after a
  good upload) fails by its issues alone; a repository that files no
  issues, by its failed deployments alone. The cost: a failed deployment
  and an unrelated issue of the same repository count as one. The page
  shows both counts as found, so the reader sees what was taken.
- **A project** adds up its repositories, compared ignoring case; a
  repository no project lists is left out. It has at most as many failed
  changes as deployments, so the rate is at most 100%; its counts still
  show what was found.
- **The rate** is the failed changes out of the deployments, shown in
  whole percent, rounded down, so the percent shown never reaches a band
  edge the rate has not.

**The bands.** DORA's current Quick Check does not offer answers for change
fail rate as it does for the other three: it asks for a percentage on a
slider, and shows it on a scale labelled with six values. The script the
Quick Check loads, <https://dora.dev/quickcheck/quickcheck.js>, asks
"Approximately what percentage of changes to production or releases to
users result in degraded service (for example, leads to service impairment
or service outage) and subsequently requires remediation (for example,
requires a hotfix, rollback, fix forward or patch), if at all?", shows the
answer as "`<n>`% of changes fail", and labels its scale "100%", "80%",
"60%", "40%", "20%" and "0%". A rate is banded by the nearest label; a rate
halfway between two is the higher one, as an edge of lead time's bands is
the slower band. Compared exactly, failed changes times 100 against the
edge times the deployments:

| Change fail rate | DORA band |
| --- | --- |
| below 10% | 0% |
| 10% to below 30% | 20% |
| 30% to below 50% | 40% |
| 50% to below 70% | 60% |
| 70% to below 90% | 80% |
| 90% and more | 100% |

A row whose deployments all failed shows its rate as found, "100% · 100%
(1 of 1)" (decision #35).

## Deployment rework rate

The fifth DORA number on the page (forsgren#39, package `internal/metrics`):
DORA's share of deployments that were not planned but made to address a
user-facing bug. The table's fifth column shows it as a DORA band with the
rate and, in brackets, the rework deployments of the successful deployments
of the last 30 days: "20% · 14% (1 of 7)". With no successful deployment in
the window it says "No successful deployments".

**What counts.** Lenka's proposal on forsgren#39 (Yves can revert it
there):

- **The deployments** are the successful ones in `data/deployments.csv`
  created in the last 30 days, counted back from the render time in UTC,
  both ends included, as for the other metrics. A deployment created after
  the render time is not there yet.
- **A rework deployment** is a successful deployment that either (a) is the
  first success of its stream after a failed deployment, the recovery that
  failed deployment recovery time already finds (the stream is collect's:
  repository ignoring case, kind, name and task, a repository's releases
  one stream), however old the failure; or (b) was created while an issue
  labelled `failure` of the same repository was open, from
  `data/failures.csv`: opened at or before the deployment, and closed after
  it or not yet. A withdrawn issue (`data/failures_withdrawn.csv`, as for
  change fail rate, forsgren#155) makes no rework; (a) does not read issues,
  so a withdrawal never changes it.
- **Counted once.** A deployment that is both is one rework deployment.
- **A project** adds up its repositories, compared ignoring case; a
  repository no project lists is left out. A failure issue names no task,
  so a service's row has no issues and only (a) applies there, as for
  change fail rate.
- **The rate** is the rework deployments out of the successful ones, in
  whole percent, rounded down, so the percent shown never reaches a band
  edge the rate has not.

**The bands.** DORA's Quick Check does ask for it. The script it loads,
<https://dora.dev/quickcheck/quickcheck.js>, asks "Approximately what
percentage of deployments in the last 6 months were not planned but were
performed to address a user-facing bug in the application?", shows the
answer as "`<n>`% of deployments were unplanned" and scales it on the same
six labels as change fail rate, "100%", "80%", "60%", "40%", "20%" and
"0%". A rate is banded by the nearest label, a rate halfway between two the
higher one, on change fail rate's edges (below 10% is 0%, 10% to below 30%
is 20%, and so on up to 90% and more as 100%). DORA's question says "in the
last 6 months"; forsgren measures the DORA window, the last 30 days unless
`dora_days: 180` asks for six months, like its other four metrics.

## The page

Every page's footer opens with one paragraph (forsgren#41, #45): Forsgren,
linked to https://forsgren.be/, the project page, which links its GitHub
repository (forsgren#162), its version, "Metrics from GitHub data."
"Calculated at
2026-10-03 12:00 UTC", the moment of the run (UTC, to the minute), on every
run, with rows or without; and, when a newer forsgren release exists than the
version that built the page, the version line adds it, "Forsgren <version> ·
0.3.9 is available" (forsgren#40; nothing is added when the page is up to
date, and no repository appears), "0.3.9 is waiting in pull request #7
(merge it to update)" when Dependabot's pull request for it is open, or
"0.3.9 is available; unknown (pull request list truncated)" when the list
of open pull requests was too long to read in full and none of those read
was it (forsgren#203; see
[Running forsgren](configuration.md#running-forsgren)). A development build, such as the
[preview](ci.md)'s, adds `+dev` and the short commit it is built from to its
version, "Forsgren <version>+dev (c41db9e)", where the version is the last release tag (no release bumps the version in the code, so it is read from the module version the go tool records for a checkout build), as text: the page links into no
repository (forsgren#224); a release build shows its version alone. The numbers are compared as numbers, so 0.0.10
is newer than 0.0.9. On every page the footer's paragraph is followed by
two links on one line, "Settings" and "Legend", to the settings page and the legend (forsgren#83, #84, #128). The footer is the same on every page, so the settings page and the legend link to themselves too (Yves's ruling on decision #133).

`render` writes one table (forsgren#38) first on the table page, with no text
above it but the page's heading, "DORA metrics" (forsgren#135; the version is
in the footer); where each metric comes from is explained on the
legend page, counting back from the time in the footer. A config that lists
no projects has no table: the page shows, in its place, a short how-to, that
`forsgren.config.yml` lists the projects, with a small example (a project, two
repositories, one with a `label`) and a link to Configuration
(forsgren#41), on the project page, https://forsgren.be/#configuration, never
a path on github.com (forsgren#172):

- **The columns** are the five metrics: deployment frequency, lead time for
  changes, failed deployment recovery time, change fail rate and deployment
  rework rate, with Weekend deployments after deployment frequency on the
  standard and numbers views (forsgren#124). The first column heads each row.
- **The rows** are, per project in the config's order, its total, then a
  row per label its repositories give (see [Configuration](configuration.md#configuration), `label` and
  `services`), sorted by label ignoring case and indented under it. A
  project with label rows is headed "Acme Shop (total)"; one without is
  one row with its name. A label row's header also carries its project's
  name for a screen reader ("Acme Shop: API"), hidden on screen, and the
  dash drawn before a label has empty alternative text, so it is not read.
- **Each row is counted** by the same five metric functions as a project of
  its own, over its own data: a project's total over all its repositories,
  the numbers the page showed per project before the table; a repository's
  label row over all that repository's deployments, commits and failure
  issues; a service's row over the deployments of its task (written
  exactly, the repository ignoring case) and the commits they shipped
  (joined by repository, kind and deployment ID). A failure issue names no
  task, so it counts on the total and on a repository's label row, never on
  a service's row, whose change fail rate is its failed deployments of its
  final deployments, and whose rework rate counts only the first success
  after a failed deployment.
- **Each cell is short**: the DORA band, then the number that decided it
  and the count it is over, "Less than one day · 2 h 7 min (48)"; the
  weekend deployments have their own column. Durations are in min, h and d,
  each part cut down, never rounded up.
- **Pages:** up to eleven pages are written: `index.html`, `legend.html`, `settings.html`, `issues.html`, `days.html`, `history.html`, `tbd.html`, the three views and the Numbers and scoring page. Every page opens with one menu, "View: Standard · Numbers · Scoring · Numbers and scoring · Issues · Daily · History · TBD" (forsgren#128, decision #133, forsgren#55, forsgren#68, forsgren#253): the three views, then the Numbers and scoring page, `numbers-scoring/`, then the issues page, `issues.html`, the days page, `days.html`, labelled Daily, the History page, `history.html`, and the TBD page, `tbd.html`, labelled TBD; one folder down its links go through `../`. The current page is plain text marked `aria-current="page"`; the root marks the view it shows `aria-current="true"` (see Views), and the settings and legend pages mark none. No page has a link back to the table, since the menu reaches it, and every page ends with the same footer, the version line and then Settings and Legend. Five pages have a key that takes `true`, `unlisted` or `false` (forsgren#159, #55, #68, #200, #253; see [Configuration](configuration.md#configuration)): `issues_page` for `issues.html`, `days_page` for `days.html`, `numbers_scoring_page` for `numbers-scoring/`, `history_page` for `history.html` and `tbd_page` for `tbd.html`. `true` generates the page and lists it in the menu. `false` does not generate it, removes it from the site if an earlier run wrote it (the Numbers and scoring page's folder too, once empty), and leaves it out of the menu. The defaults are `issues_page: true`, `days_page: false`, `numbers_scoring_page: unlisted`, `history_page: unlisted` (from 1.8.2) and `tbd_page: unlisted`; the starter that `init-config` writes sets `issues_page: false` and `days_page: false`, so a new installation starts with both off (forsgren#285). A render without a config, as forsgren's own build, writes and lists all eleven. The legend explains the five keys and their three values on every page set.
- **Unlisted pages** (forsgren#200, from 1.8.2): a page whose key is `unlisted` is generated, but no menu names it, not even its own, and its `<head>` carries `<meta name="robots" content="noindex">`. It is reachable by its address, `history.html`, `tbd.html` or `numbers-scoring/`, so you can look at it before you list it. Unlisted is discoverable, not private: noindex asks compliant search engines not to index the page; it does not enforce access control. Anyone who knows or guesses the address can open it. Only an unlisted page carries the tag; set the key to `true` and the next run lists the page and drops the tag. Up to 0.8.3 the days page was `issues.html` and the issues page `months.html`; 0.8.4 renamed them with no redirect (decision #133), and `months.html` is gone.
- **Meta description** (forsgren#208, from 1.9.2): every page's `<head>` carries `<meta name="description">`, the text a search result shows under the page's title. It is one fixed sentence per page, chosen by the page's name alone: it names no project, repository, number, date or title, so the head shows nothing the page does not, and two installations get the same sentences. Every sentence ends with the same words, " generated by Forsgren", with no comma before them and no closing period. The root, `index.html`, takes the sentence of the view it shows, so a root set to the numbers view has the numbers sentence, and a root without a view the standard one; the placeholder and no-projects pages read as their page does:

  | Page | Description |
  |---|---|
  | `index.html` (standard view) and `standard/` | DORA metrics per project: deployment frequency, lead time, recovery time, change fail rate and rework rate generated by Forsgren |
  | `numbers/` | The DORA numbers per project, without scores generated by Forsgren |
  | `scoring/` | The DORA Quick Check scores per project, with the Overall Performance generated by Forsgren |
  | `numbers-scoring/` | The DORA numbers per project, each with its DORA Quick Check score generated by Forsgren |
  | `issues.html` | Issues opened, closed and reopened, by week, month and year generated by Forsgren |
  | `days.html` | Issues opened, closed and reopened on each of the last 30 days generated by Forsgren |
  | `history.html` | The history of the DORA metrics per project: each half-year and the last 6 months generated by Forsgren |
  | `tbd.html` | Trunk-based development: the Mainline Interval and the developers per project generated by Forsgren |
  | `legend.html` | How the DORA numbers are counted and scored: the window, the bands and the scores generated by Forsgren |
  | `settings.html` | The settings of forsgren.config.yml and the value in use for each generated by Forsgren |

  The longest, the standard sentence, is 128 characters, under the 160 a search result usually shows; the others are 66 to 103. The sentences are in `internal/page/description.go`, and the HTMLHint gate's `meta-description-require` rule fails a page without one (see [Quality gates](quality-gates.md)).
- **Views** (forsgren#46): the table is built in more than one view, each its
  own page: `/standard/` (`standard/index.html`) is the table above, band,
  number and count, and `/numbers/` (`numbers/index.html`) shows only
  numbers, no band text: the successful deployments of the last 30 days
  (0 where there are none), the weekend ones among them in the next column
  (0 where there are none), the median lead time and the median recovery time
  as durations ("2 h 7 min", the same text the standard cell shows after its
  band), and the change fail rate and the rework rate in whole percent
  ("14%"); a `-` where there is no number (no commits, no completed
  recovery, no deployments or successful deployments). A row with no
  deployments recorded is six cells there, two `0` and four `-`, never a
  sentence. The table has no caption: the page's heading, "DORA metrics",
  names it and its scroll region (forsgren#135); the menu at the top of the page marks the view, plain
  text with `aria-current="page"`, and links the others (`../standard/`,
  `../numbers/`, `../scoring/`). Up to 0.8.3 the view switch sat in the caption
  (forsgren#51); 0.8.4 moved it to the menu (forsgren#128). A page one folder
  down reaches `styles.css`, the settings and the legend through `../`. The
  legend page serves all views. The root `index.html` follows the `view:`
  config key (see [Configuration](configuration.md#configuration)): that view, which its menu marks
  `aria-current="true"`, as the root is not that view's page; without the
  key it is the standard page and its menu marks no view. `/scoring/`
  (`scoring/index.html`, forsgren#47) shows each metric's DORA Quick Check
  score alone, 0 to 10 (`9.3`, `10`, `0`), `-` where the metric has no data
  (deployment frequency: never a successful deployment in the recorded
  history, where the numbers view shows `0`; a last success older than six
  months scores `0`, the lowest band), and a sixth column, Overall
  Performance: the mean of the scored metrics to one decimal, `-` when none
  is scored. A `0` score is performance in the lowest band, never missing
  data. The menu names it, as it names the other two.
- **The Numbers and scoring page** (`/numbers-scoring/`,
  `numbers-scoring/index.html`, forsgren#55, decision #187) puts the numbers
  view and the scoring view together: each metric cell is its number, as the
  numbers view shows it, then " · ", then its score, as the scoring view
  shows it: `12 · 6`, `7% · 9.3`, `0% · 10`, `2 h 7 min · 8`. A metric with
  no data is a single `-`, never `- · -`; deployment frequency of a project
  that never had a successful deployment is `0 · -`, its real zero count and
  no score, and a row with no deployments recorded is six cells, never a
  sentence. The last column is Overall Performance, as on `/scoring/`: the
  mean of the scored metrics to one decimal, `-` when none is scored. There
  is no Weekend deployments column. The cells follow the DORA window
  (`dora_days`), since both halves come from the same row. The menu names it
  "Numbers and scoring", after Scoring and before Issues; on its own page
  the entry is plain text with `aria-current="page"`. It is unlisted by
  default: generated with no menu entry; `numbers_scoring_page: true` (see
  [Configuration](configuration.md#configuration)) lists it and `false`
  leaves it out. It is not a view: `view:` cannot name it, so the root never
  shows it.
- **The legend** (`legend.html`, titled "Legend", forsgren#128) gives each metric's bands in one compact
  list, with what each cell counts and its window. Each level ends with the
  score the scoring view gives it (forsgren#79), from the same functions
  the scoring view scores with: "Less than one day: 1 hour to below 24 hours,
  score 8". Recovery time lists lead time's six levels, worded as a
  recovery, as it is banded and scored on them. Change fail rate and
  deployment rework rate are scored per whole percent, so each of their
  levels shows the range of scores its percentages give (decision #197):
  "20%: 10% to below 30%, score 9 to 7.1", and rework rate lists the same
  six levels worded as a rework, "Rework of 20%: 10% to below 30% of the
  deployments, score 9 to 7.1". Its Scores section says what the scoring
  view shows, that "The
  Numbers and scoring page, when it is shown, has the number and the score of
  each metric in one cell." (forsgren#55), credits the
  DORA Quick Check, linked: "Scores follow the DORA Quick Check (dora.dev),
  © Google LLC, CC BY 4.0" (forsgren#47), and points at the level scores
  above, with their ranges for the two percent metrics. A last section, Issues pages,
  explains the periods of the issues and days pages: "Days are in UTC, weeks
  run Monday to Sunday, months and years follow the calendar, and a week that
  spans two months is in both." (forsgren#128, decision #133). That
  section also says what the issue columns count (forsgren#112): New the
  issues created in the period, Completed, Not planned and Duplicate the
  issues closed with that reason, and Other those closed with no reason or
  one forsgren does not know, so every close is in exactly one column, while
  a reopen is in none; it explains Lead time and Bugs lead time
  (forsgren#202): "Lead time is the median time from an issue's creation to
  its Completed close, over the issues completed in the row's period; Not
  planned, Duplicate and Other closes are not counted. A reopened issue is
  measured from its creation to the close in that period. Bugs lead time is
  the same over the issues that carry the GitHub label bug, and shows —
  (incomplete) on the same rule as Open bugs. A dash means no issue was
  completed in the period."; and it names two limits: a reopen is dated when
  the collection sees it, and a repository with more issues than the one
  full read takes (100 pages of 100) has its older issues missing, so its
  historical Total stays incomplete, and it says the — (incomplete) note
  covers Open bugs and Bugs lead time only. It no longer
  lists the settings (forsgren#84). After the paragraph on where the numbers
  come from it states the window: "The window is 30 days (the default;
  dora_days is not set in forsgren.config.yml)." or "The window is 90 days
  (dora_days in forsgren.config.yml).", and every "last 30 days" of the
  metric sections and the frequency bands' counts follow it, at 90 days "3 to
  14 in 90 days", "Between once per month and once every six months: fewer
  than 3 in 90 days, 1 and more in 180 days" (forsgren#178). Its Settings page section explains the
  values of `auto_update_level` (forsgren#156): `patch` merges patch updates
  only, `minor` merges minor and patch updates, and `major` merges major, minor
  and patch updates, which does not mean a major release is safe, as nothing
  checks a release against the installation's own data. Its History page
  section explains the History page (forsgren#68): the periods, the 180-day
  banding at the configured working day with its edges, the `number · score`
  cells, the Trend chart, what a dash means and the limits of old periods.
- **The days page** (`days.html`, titled "Daily"; `issues.html` up to 0.8.3; forsgren#76, #128) is a table, Date | New |
  Completed | Lead time | Bugs lead time | Not planned | Duplicate | Other | Open | Open bugs | Total | Open / Total, one row per UTC calendar day,
  the last 30 complete days (`issueDays`), yesterday on top and going down;
  today is left out, so a row never changes once it is shown (apart from the
  [known limits](data-files.md#issue-events-forsgren76)). It has no week or month row: those are on the issues
  page (forsgren#123, #128). All tracked repositories are counted together. **Inactive days are hidden** (forsgren#108, decisions
  #116 and #117): a day is active when it has a new issue, a close of any kind
  or a reopen, and a day with none of these has no row. A reopen keeps a day
  visible because it changes the Open. The window stays 30 calendar days, so
  hiding days gives fewer rows; the page does not reach further back to fill
  30. The calculation keeps every day (`metrics.IssueDays` marks each with
  `Active`): Open and Total are computed over all of them, so a hidden day's
  Open and Total equal those of the shown day before it. When no day of the window is
  active, and when there are no issue events yet, the page shows one line,
  "No issues were opened, closed or reopened in the last 30 days.", instead
  of the table. **New** counts the `created` events of
  the day; a reopened issue is not new. Every `closed` event of the day is
  counted in exactly one of the other four columns, by its reason
  (decision #107): **Completed** is the reason `completed`, **Not planned**
  `not_planned` and **Duplicate** `duplicate`; **Other** is a close with no
  reason (an old issue, closed before GitHub gave reasons) or a reason
  forsgren does not know. **Lead time** (forsgren#202), right after
  Completed, is the median time from an issue's `created` event to its
  `completed` close, over the issues completed in the row's period, the
  mean of the two middle ones for an even count, in the short form of the
  numbers view ("3 d", "5 h", "12 min"); a dash when nothing was completed
  in the period. Not planned, Duplicate and Other closes are not counted, a
  close of an issue with no stored `created` event is left out, and a
  reopened issue is measured from its creation to the close in that period.
  **Bugs lead time** is the same over the issues that carry the `bug` label,
  the flag Open bugs reads, and shows `— (incomplete)` on the same rule as
  Open bugs (below). **Open** (headed Total up to 0.8.4, forsgren#134) is the issues open at the end of that
  day, across all repositories: the issues created, minus those closed, plus
  those reopened, counted from the oldest stored event. Every close counts
  -1 and every reopen +1, also for an issue with no created event
  (forsgren#122), and the order of the lines in `issues.csv` does not
  matter. A file `collect` wrote always holds the created event with the
  first close, so only a hand-edited `issues.csv` can show such an Open. The
  Open is shown as calculated: a negative Open means the collected data
  is inconsistent (missing events, a partial read, or a bug), and it is
  shown rather than hidden. Reopen times are the
  times `collect` saw them (see [Issue events](data-files.md#issue-events-forsgren76)), so an Open from before a
  reopen was seen is an estimate. **Total** is the issues created up to the
  end of that day, across all repositories, open or closed: the `created`
  events from the oldest stored one on, each counted once, so a close never
  lowers it and a reopen adds nothing, the issue already counts. An issue
  whose created event is not stored is not counted (Yves's ruling,
  forsgren#134), while a close or a reopen of it still moves Open (forsgren#122).
  **Open / Total** is Open out of Total, in whole percent, rounded down, as the
  change fail rate is ("55%"), and a dash when Total is 0. It is shown as
  calculated: where the stored history is incomplete, Open can exceed
  Total and the percent then exceeds 100%. **Open bugs** (forsgren#126), right
  after Open, is Open counted over the issues that carry the GitHub label
  `bug` (not configurable): +1 for a `created` or `reopened` event of such an
  issue and -1 for a `closed` one, at the end of the day. The label is the one
  at the latest collection, applied to the issue's whole history (Yves's
  ruling): adding or removing the label moves the issue in every past row,
  not only from the day it was changed. The flags come from
  `data/issue_bugs.csv` (see [History](data-files.md#history), Bug flags); a missing file marks no
  issue, and an unknown version or a malformed line fails the render with its
  own message. **An incomplete Open bugs cell** (forsgren#140, decision #171):
  when the bug read of any tracked repository stopped at the 10,000 issues
  cap, `data/issue_bugs_cut.csv` notes it (see
  [History](data-files.md#history), The bugs cut note), and the Open bugs cell
  of every row, on the days page and on the issues page, shows
  `— (incomplete)` with no arrow instead of the number, because a partial
  count would look complete. The cell is a `<span>` with `role="img"`, the
  `aria-label` "Open bugs incomplete: a repository's bug list was too long to
  read in full" and the `title` "A repository's bug list was too long to read
  in full, so the number of open bugs is not shown"; the legend explains it
  after its note on Open bugs. The Bugs lead time cell shows the same note
  in the same rows (forsgren#202), its `aria-label` starting "Bugs lead time
  incomplete" and its `title` ending "so the bugs lead time is not shown". The number comes back by itself once a run
  reads the bug list in full. A missing file marks no cell, and an unknown
  version or a malformed line fails the render with its own message.
  **The arrows** (forsgren#126, forsgren#114) follow the Open and
  Open bugs counts: a red up arrow and the change (`▲ +3`) when the count
  rose, a green down arrow and the change (`▼ −2`) when it fell, a grey dash
  when it did not change, also a day that nets to zero. Red and green mean a
  count that rose and one that fell, not worse and better. Each row is
  compared with the end of the period before it of the same kind: a day with
  the day before, a week with the week before, a month with the month before
  and a year with the year before, never with the row below it in the list;
  the oldest row of each kind is compared with the count just before its
  period, even when that period is outside the rows shown. Each arrow is a
  `<span>` with `role="img"` and an `aria-label` in words ("open issues
  increased by 3", "open bugs decreased by 2", "open issues unchanged"), so
  colour is never the only signal, and a class (`trend-up`, `trend-down`,
  `trend-flat`) that `styles.css` colours. The table has no caption: the page's
  heading, Daily, names it and its scroll region, and the legend says the days
  are UTC (forsgren#128). `render` reads `data/issues.csv` next to its
  `--data` file like `failures.csv`: a missing file is no events (the
  one-line message, a new installation), an unknown version or a malformed
  line fails the render with its own message.
- **The issues page** (`issues.html`, titled "Issues"; `months.html` up to
  0.8.3; forsgren#123, #128, from #89, decisions #118 and #119) is the days
  page's table over longer periods: Period | New |
  Completed | Lead time | Bugs lead time | Not planned | Duplicate | Other | Open | Open bugs | Total | Open / Total, the columns counted as
  on the days page, with four kinds of row, newest first within each.
  First the **days of the current week**, Monday up to yesterday (none on a
  Monday), labelled by their UTC date; then the **complete weeks** that touch
  the current month, Monday to Sunday, labelled "Week 41" (the ISO week
  number); then **the complete calendar months of the current year**, January
  up to last month, labelled "September 2026"; then **one row per earlier
  calendar year**, back to the year of the oldest stored event, labelled with
  the year alone, "2025" (forsgren#125). The current week appears only as its
  days, the current month only as its weeks and days, and the current year
  only as its months. A week that spans two months is in both: on Wednesday
  14 October 2026 the page lists Tuesday 13 and Monday 12, then weeks 41 and
  40 (week 40 begins on 28 September), then September back to January 2026,
  then 2025, 2024 and the years before it. In January the current year has no
  complete month, so the years follow the weeks directly. A year row counts
  the events of its UTC calendar year, and its **Open** is the issues open at
  the end of 31 December, its **Total** the issues created up to then; the oldest year may be partial, as the oldest month
  is. Today is left out, so
  a row never changes once it is shown. **Inactive rows are hidden** as on
  the days page (forsgren#108, decisions #116 and #117, for weeks and
  months too). The calculation keeps every row (`metrics.IssueRows`, built
  from `metrics.IssueWeekDays`, `IssueWeeks`, `IssueYearMonths` and
  `IssueYearRows`, each marking its rows with `Active`): Open and Total are computed over all of them, so
  a hidden row's Open and Total equal those of the shown row before it. In a week, month
  or year row, **Open** is the issues open at the end of the row's last day, **Open bugs**
  the open ones that carry the `bug` label, **Total**
  the issues created up to the end of it, and **Open / Total** their share; the arrows
  compare a week with the week before, a month with the month before and a year
  with the year before.
  When no row is active, and when there are no issue events yet, the page
  shows one line, "No issues were opened, closed or reopened before today."
  (decision #119: the rows reach back months, so the line names no period),
  instead of the table. The table has no caption: the page's heading,
  Issues, names it and its scroll region, and the note on the periods (days
  are UTC, weeks run Monday to Sunday, months and years follow the calendar,
  and a week that spans two months is in both) is on the legend page
  (forsgren#128). The page reads the
  same `data/issues.csv` as the days page, with the same failures for a
  missing, unknown or malformed file. The two pages share one table template
  (`templates/layout/issuestable.html`).
- **The settings page** (`settings.html`, forsgren#84, a table since forsgren#141)
  tabulates each optional config key under Parameter, Current value, Possible
  values and Default, see [Configuration](configuration.md#configuration).
  A value that is not accepted (forsgren#183) shows in its row's Current
  value as written, then why and the default in use: "60 is not accepted:
  use 30, 90 or 180. Using the default 30." (an empty value as "(empty)"),
  and its Default shows that default.
- **Layout:** no table has a caption: each is named by its page's heading
  ("DORA metrics" on the three views and the root, Issues, Daily, History), and one `h1`
  rule in `styles.css` sets the look of every page's heading (forsgren#135), and every table has `<th scope>` headers; it scrolls
  sideways inside its own box on a narrow screen, so the page keeps its
  1rem (16px) gutter and never scrolls sideways itself. A page grows with
  the screen up to 120rem (1920px) and is centred on a wider one; every page
  has the same width, since `styles.css` reserves the scrollbar's space
  whether or not the page scrolls, and every table fills that width, while
  running text (paragraphs and list items) stops at 72rem (forsgren#153,
  decision #160). The tables of the issues and days pages, of the numbers
  and scoring views, of the Numbers and scoring page and of the History page keep each cell on one line (class `no-wrap`); the
  standard view's band text and the settings table wrap. The starter page,
  forsgren.be, is 72rem wide, its text in a framed card (decision #161).
  `styles.css` sets
  no colour but `color-scheme: light dark`, so light and dark mode follow
  the browser's own colours, the lines drawn in the text colour, with one
  narrow exception (Yves's ruling on forsgren#114 and forsgren#126): the
  trend arrows of the issues tables, `.trend-up` red, `.trend-down` green and
  `.trend-flat` grey, each `light-dark(light, dark)` and at 4.5:1 contrast or
  more against the page background in its mode, which a test measures. It is
  not a general permission for colours elsewhere. The History page's charts
  are drawn in `currentcolor` too, so they need no colour of their own.

The page shows project names, labels and numbers only: never a repository's
or a task's own name, a SHA or a commit message.

### The History page

The History page (`history.html`, titled "History (BETA)", forsgren#68, from 1.8.0)
shows how the five metrics and Overall Performance moved over time. It is
unlisted by default (forsgren#200, from 1.8.2): generated and reachable at
`history.html`, with no menu entry and a noindex tag (see Unlisted pages
under [The page](#the-page), and
[Configuration](configuration.md#configuration)). `history_page: true` lists
it in the menu after Daily, "History"; `false` leaves it out.

- **Beta.** The page is marked beta (forsgren#198, from 1.8.2): its title,
  its heading and the legend's History section heading read "History
  (BETA)", in capitals as the TBD page's title does (one marker, `betaMarker`,
  forsgren#271); the menu entry stays "History". When the page leaves beta, all
  three go back together.
- **How to read it.** Under the heading one line says how to read the page:
  "Each column is a period: the calendar half-years, then the last 6 months.
  A cell is the number and its score (0 to 10), number · score. The chart
  above each project draws the score of each measure over the periods." The
  last sentence is left out while there is no chart.
- **One period.** While the last 6 months are the only column, a line under
  it says why, with dates (forsgren#198): "Only the last 6 months have data
  so far: the first deployment is 2026-10-02. The first half-year, 2026 H2,
  appears on 2027-01-01." When `history_days` is too short to reach back
  over that half-year, the line says the value it needs and to raise it in
  forsgren.config.yml. A half-year that is already over but has no column
  is named with its reason: `history_days` is too short, with the value it
  needs, or the history is still being read back to its start. The line
  needs a known first deployment, and is not there with no column or
  several.

- **Periods.** The columns are periods, the oldest on the left: the calendar
  half-years, January to June ("2026 H1") and July to December ("2025 H2"),
  in UTC, that are complete and start within `history_days`, and last the
  rolling column, "Last 6 months to 2026-10-15": the 180 days up to the
  render time, which overlaps the current half-year; the current half-year
  has no column of its own. A half-year counts from its first day up to, not
  including, the next half-year's; the rolling column counts both ends, as
  the table does. Nothing after a period's end is seen in it, so a project
  that deployed only later has no data in an earlier period, not a zero.
  `history_days` goes up to 1825, five years, so the page has at most ten
  half-years and the rolling column. With `history_days` under 180 there
  are no periods, and the page says, in one line, to set it to at least 180.
- **Rows.** One table with a block per project (forsgren#211), in the table
  page's order, each headed by the project's name. A block has a row per
  measure for the project's total, Overall Performance first, then deployment
  frequency, lead time for changes, failed deployment recovery time, change
  fail rate and deployment rework rate, and the same six rows for each of
  the project's labels, headed "API: Deployment frequency" (a screen reader
  also hears the project). A project's rows sit together, and the first
  column reads Measure.
- **Cells.** Each metric cell is `number · score`, as on the Numbers and
  scoring page (`40 · 6`, `7% · 9.3`); the Overall Performance cell is the
  score alone (`7.7`).
- **180-day banding.** Every period is banded as 180 days, DORA's standard,
  with the edges of 180 days at the configured working day (at 8 hours: 6,
  30, 180 and 1441 in 180 days); the count is the period's own, not
  rescaled to 180 days, so a half-year of 181 to 184 days can read higher
  than the same pace over exactly 180 days, by at most 3%. `dora_days` does
  not change this page; `working_hours` does.
- **The charts.** One chart per project (forsgren#212), above that project's
  rows: in the project's block, a row after its name holds a cell as wide as
  the table with the chart and its legend. With fewer than two periods there
  is no chart (forsgren#198, from 1.8.2): a trend of one period shows
  nothing. The chart has a line per measure of the project's total (not its
  labels), in the table's order: Overall Performance (black in light mode,
  white in dark mode), Deployment frequency (red), Lead time for changes
  (green), Failed deployment recovery time (blue), Change fail rate (orange)
  and Deployment rework rate (purple). A measure with no score in any period
  has no line. The scale is the score, 0 to 10, 10 at the top, the same in
  every chart, the oldest period on the left. A period without a score is a
  gap that breaks the line, never a zero, and a period alone between gaps
  is a dot. A legend under the chart names each line with a swatch in its
  colour and its dash pattern (Overall Performance solid, each metric its
  own), so the chart reads without colour (a screen reader hears the project's name before each legend entry). Every colour reaches a contrast
  of 4.5:1 on the page background in light and in dark mode. Each chart is
  an inline SVG with a title ("Scores of Acme Shop: 2025 H2 to Last 6
  months") and no script; the table below it carries every number the
  chart draws. The per-row Trend column of 1.8.0 to 1.9.x is gone: the
  project chart replaces it.
- **Dashes.** A dash is no data: nothing was deployed yet up to that
  period, or the collection has not read the history back that far yet: a
  period shows a row only when every repository of the row was read back to
  the period's start (`data/reach.csv`, see
  [Collecting deployments](data-files.md#collecting-deployments-collect)).
  A period no row has data for is left out, and with no period left the page
  says, in one line, that the periods fill as the history is collected over
  the next runs. To read further back, raise `history_days`, up to 1825;
  the older half-years fill in over the next daily runs, one
  `history_chunk_days` chunk per run.
- **Limits of old periods.** The lead time of an older period can be a dash,
  because the commits of older deployments may not be stored. The change
  fail rate of an old period can count a failure issue that lost its label
  long ago, because the one-time catch-up of withdrawn failure issues
  re-reads only the `dora_days` window.

### The TBD page

The TBD page (`tbd.html`, titled "Trunk-based development [TBD] (BETA)", forsgren#253, forsgren#271)
shows the Mainline Interval and the Mainline Lead Time of each project: how long it is, on average, between
two commits that deployments shipped landing on the main branch, and how much
that varies. It is unlisted
by default: generated and reachable at `tbd.html`, with no menu entry and a
noindex tag (see Unlisted pages under [The page](#the-page), and
[Configuration](configuration.md#configuration)). `tbd_page: true` lists it
last in the menu, "TBD"; `false` leaves it out.

- **The table.** A row per project and three columns, Mainline Interval,
  Mainline Lead Time and Developers (see below); the Mainline Interval cell reads `mean ± deviation (gaps) · median M · p90 P`, for example
  `24 min ± 2 h 24 min (12) · median 5 min · p90 1 h`, with the durations
  written as on the other pages, then, when some commits are timed by their
  author date (see The old approximation below), the note after ` · `:
  `2 d 22 h ± 4 d 3 h (2) · median 2 d 22 h · p90 - · 3 commits timed by author date`.
  The cell stays one line (the table scrolls
  sideways in its region on a narrow screen, as the other tables do). It is per project: the label rows of
  the table page have no row here.
- **What is counted.** The commits `forsgren collect` stores in
  `data/commits.csv`, the commits that deployments shipped, so it is an
  interval between deployed commits, not between every commit of the mainline.
  A commit counts when its deployment was created in the DORA window
  (`dora_days`, both ends included), as for lead time; its author date does not
  decide that. A commit counts once, by repository (ignoring case) and SHA, even
  when two deployments shipped it. A project's repositories are one sequence.
- **The first-parent chain** (forsgren#254). Of each deployment's commits only
  those of its first-parent chain count: the chain starts at the deployment's
  tip, the one stored commit of the deployment that none of its other commits
  names as a parent (the deployed commit), and goes through each commit's
  first parent (`parents` in [data-files.md](data-files.md#history)) while that
  parent is one of the deployment's commits. Those are the commits that landed
  on the main branch one after another. A merge's other parents, and the
  commits a merge brought in from a branch, are left out; the merge commit
  counts. The chain is judged before a commit is counted once, so a commit two
  deployments shipped counts when it is on the chain of one of them.
- **The committer date.** A commit of the chain is placed at its committer date
  (`committed_at`), when it landed where it is now: a rebase or a merge button
  moves it, the author date stays when the change was first written. A commit of
  the chain GitHub gave no committer date for is placed at its author date,
  never at an empty time.
- **The old approximation.** A deployment without exactly one tip keeps the
  Mainline Interval's first rule (forsgren#253): every one of its commits
  counts, at its author date. That is every deployment of two commits or more
  stored before the commits format v3, whose commits have no parents; a
  deployment of one such commit is its own chain, without a committer date, so
  at its author date as well. Those commits are never looked up again
  (decision 293 of forsgren#254), so this lasts until their deployments leave the
  window. The cell names how many commits are placed at their author date, by
  either rule: ` · 3 commits timed by author date`, `1 commit timed by author date`
  for one, nothing when there are none.
- **The gaps.** The commits are put in the order of the times they are placed
  at (the committer date, or the author date as above), whatever the order they
  are stored in, and a gap is the time between two neighbours; two commits
  placed at the same time have a gap of 0. The mean is
  the mean of the gaps, the deviation their sample standard deviation (the sum
  of the squared differences from the mean over the number of gaps less one),
  and the count in brackets is the number of gaps. The median is the middle
  gap, or the mean of the two middle gaps when their number is even. The 90th
  percentile (p90) is the nearest-rank one: the gap at position 0.9 times the
  number of gaps, rounded up (in integers, (9n + 9) / 10), of the gaps sorted
  from the shortest, so an actual gap and nine tenths of the gaps are no longer
  than it. They tell the typical spacing from occasional long gaps: a mean far
  above the median, and a deviation far above the mean, point at a few long
  gaps among short ones.
- **A dash.** Fewer than two commits have no gap, so the whole cell is `-`. One
  gap has a mean but no sample deviation, which needs two gaps, so the cell reads
  `2 h ± - (1) · median - · p90 -`. The median needs two gaps, and p90 needs ten
  (under ten, the nearest rank is the longest gap, which the maximum already
  says); each is a dash until then. A zero deviation reads `less than 1 min`.
- **Without data.** With no projects the page says so in one line, and so it
  does when no data was given to the render ("No commits have been collected
  yet, so there is no Mainline Interval to show."); with data and a project
  that has no commit in the window, the project's row is `-`.
- **Developers.** The column next to the Mainline Interval (forsgren#273),
  because a team of ten makes more commits than one person with the same
  habits; the interval itself is not divided by it. It counts the distinct GitHub logins of the authors of the commits
  deployed in the window (the Mainline Interval's window, each commit once),
  ignoring case, so
  one person is one developer across the email addresses they commit with. The
  first-parent chain does not apply here: the authors of the commits a merge
  brought in count too, since on the chain alone it would count whoever merged
  (decision 294 of forsgren#254). A
  bot account (a login ending in `[bot]`, such as `dependabot[bot]`) is no
  developer and its commits are left out. A commit without a login (GitHub
  links its email to no account, or it was stored by the commits format v1) is
  not guessed to be anyone's: the count leaves it out and its note says how
  many. GitHub's placeholder login `invalid-email-address`, its answer for an
  author email it links to no account, is such a commit too, ignoring case,
  and never legacy data, which is a commit without a login stored before the
  commits format v3 (forsgren#355). The cell is the count, then the note after ` · ` as the recovery cell
  names its recoveries not completed yet: `3`, or
  `3 · 2 commits without a known author are not counted` (singular for one);
  a project with no counted commit reads `0`, a count, not a dash. The
  Developers are paired with the Mainline Intervals by project: Developers that
  are missing or name another project in a row fail the render rather than
  show a count in the wrong row. The number and the note are counts only; no
  login reaches a page (`TestRenderShowsNoCommitAuthor` renders every page
  from commits that all carry one login and finds it on none, the TBD page's
  Developers cell counted from it). The legend's TBD section explains the
  column: what a developer is, bots left out, commits without a known author
  named, never who the developers are.
- **Mainline Lead Time** (forsgren#256), the column between the Mainline
  Interval and Developers: how old a change is when it reaches the main
  branch. It covers merged human pull requests only, not every change that
  reaches the trunk (forsgren#342): work pushed straight to the main branch is
  not in it, so a pull request stands in for the life of a branch, and in a
  workflow that mixes both the figure covers only the pull-request changes.
  - *What is counted.* One lead time per pull request merged in the DORA
    window, counted by its merge time: from its first commit, the earliest
    author date of its commits, to the merge. A first commit dated after the
    merge counts as 0. The pull requests come from `data/pulls.csv`.
  - *The cell* reads `mean ± deviation (pull requests)`, for example
    `3 h ± 1 h (4)`, the deviation the sample standard deviation (n-1), then
    `50% (2 of 4) pull requests merged within 24 hours of their first commit`.
    The share is rounded down; 24 hours or less counts as within, the same
    boundary everywhere. A dash is the deviation of a single pull request.
    There is no pass or fail verdict: the figure is supporting evidence.
  - *Two dates.* The Mainline Interval uses the committer date (how often
    changes reach the trunk); Mainline Lead Time uses the author date of the
    first commit up to the merge time (how old changes are when they reach it).
    Read together: short interval and short lead time is frequent, fresh
    integration; short interval and long lead time points at long-lived
    branches; long interval and short lead time is few changes, each integrated
    quickly; long and long is rare, old changes.
  - *Cut and stood in.* When GitHub lists only part of a pull request's
    commits, its first commit time may be too late: the count reads
    `(4, 1 cut)` and the cell adds `the mean is a lower bound`. A cut pull
    request can make the mean too low and the share within 24 hours too high.
    When the commit list gave no usable date, the created time stands in, and
    the cell says how many: `1 pull request timed by its created time`.
  - *People.* Only a GitHub account of the type `User` is a person. Pull
    requests opened by a bot are not counted (`3 bot pull requests not
    counted`), and neither are those whose author is not known to be a user,
    such as a pull request in the legacy format (pulls format v1), which has no
    known author type (`2 pull requests of unknown author not counted`). A
    project with no human pull request reads `No human pull requests in this
    period; changes may go directly to the trunk`, which is not proof of
    direct commits.
  - *Not readable and not collected.* `Pull requests not readable` means the
    token was refused the pull request read for a repository of the project
    (a 403, kept in `data/pulls_denied.csv`, see
    [Data files](data-files.md#history)); it replaces the whole cell and is
    cleared by the next read that succeeds. `No pull requests have been
    collected yet` means `data/pulls.csv` does not exist yet.
  - *Legacy format.* Records in the legacy format have no known author: the
    data establishes that format, not when or why the record was stored. In
    Developers, commits in the legacy format have no known author and are not
    counted, and when most of the deployed commits are of that kind the cell
    says `(legacy data)`. GitHub's placeholder author `invalid-email-address`
    is an unknown author too, not a developer. In the Mainline Interval, when
    more than half of the commits are timed by author date the note reads
    `Mostly estimated: 7 of 13 commits timed by author date.`

The page itself has the heading and the table, or its one line. The
explanation above, with the window in force, is the legend's section for the
page, headed with the same title; the menu entry stays "TBD". The BETA marker
is the History page's too, written in capitals.

## Privacy

The public page shows numbers and dates only. It carries no issue titles and
no links into private repositories, makes no third-party requests (no web
fonts, analytics or CDNs: everything it loads is served with it), sets no
cookies, uses no browser storage and tracks no one. Two POST gates check the
generated page on every run, privacy posture for the requests, cookies and
tracking, and repository links for the links (see [Quality gates](quality-gates.md)). No gate
checks for issue titles yet: that rests on the renderer, which is given
the project names of the owner's own config, numbers, durations and dates
only: no repository name, commit SHA, message or author, tag, environment,
workflow or task reaches the page, which `cmd/forsgren/render_data_test.go`
and, for the commits of lead time and their authors' GitHub logins
(forsgren#273), `cmd/forsgren/render_leadtime_test.go` pin. A finding is fixed in the template, never by
loosening the gate.
