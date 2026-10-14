# Pages and views

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
time minus 7 (30, 180) days, and not after the render time. A deployment
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

Once an hour over a working day is `working_hours` × 30 deployments in 30
days (8 × 30 = 240 with the default 8), so on demand is more than that
(forsgren#69, #71); the legend page states the configured day and the numbers
that follow from it. A row whose first
successful deployment is less than 30 days old (the project total: its
earliest) has not had a whole window to deploy in, so its band uses its
30-day count scaled to 30 days: the count × 30 over its age in whole days, at
least 1 (19 in 9 days count as 63). The count shown, and the numbers view,
stay the plain count.

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
score. It never changes the band:

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
failed deployment.

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
  says, however it was closed: the label is the ruling (forsgren#6), so an
  issue that turned out not to be a failure needs its label removed before
  it is stored, since a stored issue is never taken out.
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
  it or not yet.
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
last 6 months"; forsgren measures the last 30 days, like its other four
metrics.

## The page

Every page's footer opens with one paragraph (forsgren#41, #45): Forsgren,
linked to its GitHub repository, its version, "Metrics from GitHub data."
"Calculated at
2026-10-03 12:00 UTC", the moment of the run (UTC, to the minute), on every
run, with rows or without; and, when a newer forsgren release exists than the
version that built the page, the version line adds it, "Forsgren 1.1.0 ·
0.3.9 is available" (forsgren#40; nothing is added when the page is up to
date, and no repository appears). The numbers are compared as numbers, so 0.0.10
is newer than 0.0.9. On every page the footer's paragraph is followed by
two links on one line, "Settings" and "Legend", to the settings page and the legend (forsgren#83, #84, #128). The footer is the same on all eight pages, so the settings page and the legend link to themselves too (Yves's ruling on decision #133).

`render` writes one table (forsgren#38) first on the table page, with no text
above it but the page's heading, "DORA metrics" (forsgren#135; the version is
in the footer); where each metric comes from is explained on the
legend page, counting back from the time in the footer. A config that lists
no projects has no table: the page shows, in its place, a short how-to, that
`forsgren.config.yml` lists the projects, with a small example (a project, two
repositories, one with a `label`) and a link to Configuration (forsgren#41):

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
- **Pages:** eight pages are written: `index.html`, `legend.html`, `settings.html`, `issues.html`, `days.html` and the three views. Every page opens with one menu, "View: Standard · Numbers · Scoring · Issues · Daily" (forsgren#128, decision #133): the three views, then the issues page, `issues.html`, and the days page, `days.html`, labelled Daily; one folder down its links go through `../`. The current page is plain text marked `aria-current="page"`; the root marks the view it shows `aria-current="true"` (see Views), and the settings and legend pages mark none. No page has a link back to the table, since the menu reaches it, and every page ends with the same footer, the version line and then Settings and Legend. Up to 0.8.3 the days page was `issues.html` and the issues page `months.html`; 0.8.4 renamed them with no redirect (decision #133), and `months.html` is gone.
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
- **The legend** (`legend.html`, titled "Legend", forsgren#128) gives each metric's bands in one compact
  list (recovery time's are lead time's, and rework rate's are change fail
  rate's, so it refers to them), with what each cell counts and its window;
  its last section, Scores, says what the scoring view shows and credits the
  DORA Quick Check, linked: "Scores follow the DORA Quick Check (dora.dev),
  © Google LLC, CC BY 4.0" (forsgren#47). A last section, Issues pages,
  explains the periods of the issues and days pages: "Days are in UTC, weeks
  run Monday to Sunday, months and years follow the calendar, and a week that
  spans two months is in both." (forsgren#128, decision #133). It no longer
  lists the settings (forsgren#84).
- **The days page** (`days.html`, titled "Daily"; `issues.html` up to 0.8.3; forsgren#76, #128) is a table, Date | New |
  Completed | Not planned | Duplicate | Other | Open | Open bugs | Total | Open / Total, one row per UTC calendar day,
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
  forsgren does not know. **Open** (headed Total up to 0.8.4, forsgren#134) is the issues open at the end of that
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
  own message. **The arrows** (forsgren#126, forsgren#114) follow the Open and
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
  Completed | Not planned | Duplicate | Other | Open | Open bugs | Total | Open / Total, the columns counted as
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
- **Layout:** no table has a caption: each is named by its page's heading
  ("DORA metrics" on the three views and the root, Issues, Daily), and one `h1`
  rule in `styles.css` sets the look of every page's heading (forsgren#135), and every table has `<th scope>` headers; it scrolls
  sideways inside its own box on a narrow screen, so the page keeps its
  1rem (16px) gutter and never scrolls sideways itself. A page grows with
  the screen up to 120rem (1920px) and is centred on a wider one; every page
  has the same width, since `styles.css` reserves the scrollbar's space
  whether or not the page scrolls, and every table fills that width, while
  running text (paragraphs and list items) stops at 72rem (forsgren#153,
  decision #160). The tables of the issues and days pages and of the numbers
  and scoring views keep each cell on one line (class `no-wrap`); the
  standard view's band text and the settings table wrap. The starter page,
  forsgren.be, is 72rem wide, its text in a framed card (decision #161).
  `styles.css` sets
  no colour but `color-scheme: light dark`, so light and dark mode follow
  the browser's own colours, the lines drawn in the text colour, with one
  narrow exception (Yves's ruling on forsgren#114 and forsgren#126): the
  trend arrows of the issues tables, `.trend-up` red, `.trend-down` green and
  `.trend-flat` grey, each `light-dark(light, dark)` and at 4.5:1 contrast or
  more against the page background in its mode, which a test measures. It is
  not a general permission for colours elsewhere.

The page shows project names, labels and numbers only: never a repository's
or a task's own name, a SHA or a commit message.

## Privacy

The public page shows numbers and dates only. It carries no issue titles and
no links into private repositories, makes no third-party requests (no web
fonts, analytics or CDNs: everything it loads is served with it), sets no
cookies, uses no browser storage and tracks no one. Two POST gates check the
generated page on every run, privacy posture for the requests, cookies and
tracking, and repository links for the links (see [Quality gates](quality-gates.md)). No gate
checks for issue titles yet: that rests on the renderer, which is given
the project names of the owner's own config, numbers, durations and dates
only: no repository name, commit SHA or message, tag, environment,
workflow or task reaches the page, which `cmd/forsgren/render_data_test.go`
and, for the commits of lead time, `cmd/forsgren/render_leadtime_test.go`
pin. A finding is fixed in the template, never by
loosening the gate.
