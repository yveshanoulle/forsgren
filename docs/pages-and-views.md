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
failed deployment. It also reads the failure issues (forsgren#53, below), less
the withdrawn ones (forsgren#155).

**What counts.** Rulings on forsgren#17, taken while Yves was away (each
can be reverted there):

- **Deployments.** A failure is a line of `data/deployments.csv`
  whose state is `failure`. The web-hosting and TestFlight recorders record
  a failure only once live was touched, which is DORA's "requires
  immediate intervention". A `workflow=` rule stores every run that
  concluded `failure` (see [Collecting deployments](data-files.md#collecting-deployments-collect)), so for such a
  repository a run that failed before touching live counts too.
- **Failure issues** (forsgren#53, Yves's ruling): an issue with the
  `failure` label (with its record block, see [How it gets its data](data-files.md#how-it-gets-its-data))
  is a recovery of its own, timed from its `failure-start:` line, or from its
  opening when the line is missing, to its closing. An open issue is a
  recovery not completed yet, counted whatever its age, as a run of failed
  deployments with no success after it. A closed one counts when it was
  closed in the window. A withdrawn issue (forsgren#155) is not there.
- **Counted once.** Nothing stored links an issue to the deployment it is
  about, and change fail rate takes, per repository, the larger of its
  failed deployments and its failure issues so that an incident is not
  counted twice. Here an issue whose time, from its start to its closing or
  to now while it is open, overlaps the time of a run of failed
  deployments of the same repository (from its first failure to the
  success that recovered it, or to now while it is open; a shared moment
  or edge counts, any stream, any age) is taken to be that incident and
  is left out: the run's recovery counts alone. An issue that overlaps no
  run is a recovery of its own. A service or deployment rule row counts
  the issues whose `service:` line or `service:<name>` label names its label
  (forsgren#515, forsgren#53), as
  change fail rate does. Deployment rework rate reads the issues as it
  did and does not change.
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
- **A failure issue counts in the project's total row**, and in the row of a
  service or deployment rule when its record block has a `service:` line,
  or the issue a GitHub label `service:<name>` (forsgren#53), with that row's label as the page shows it, in any case (forsgren#515;
  see [How it gets its data](data-files.md#how-it-gets-its-data)). Without
  the line, or with a label the repository does not have or two rows share,
  it counts in the total only, and the run's output names it. That is why a
  total can be higher than every row under it (forsgren#514).
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
  repository no project lists is left out. A service's or a rule's row reads
  the issues whose `service:` line names its label, so (b) applies there for
  them, as for change fail rate.
- **A failure issue of the repository** makes the deployments made while it
  was open rework in the project's total row, and in the row its `service:`
  line names; without the line, or with a label no single row has, only in
  the total, so the total rate can be higher than the rate of every row
  under it (forsgren#514, forsgren#515).
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
run, with rows or without, then the report period of the DORA window,
"Report Start 2026-09-03 12:00 Report End 2026-10-03 12:00" (forsgren#542,
decision #543 A: the window's real rolling bounds in UTC to the minute, the
render time and `dora_days` days before it, the very bounds the metrics count
over, not whole calendar days); and, when a newer forsgren release exists than the
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
repository (forsgren#224); a release build shows its version alone. A build whose
version information names no release (no `-ldflags` value and no release tag the
go tool recorded, as `Scripts/build_site.sh`'s `-buildvcs=false` build) says "Forsgren dev
(c41db9e)", or "Forsgren dev" when it records no commit: it never names a release number
it cannot know, builds on no release it names, and promises no update (forsgren#340). The numbers are compared as numbers, so 0.0.10
is newer than 0.0.9. On every page the footer's paragraph is followed by
three links on one line, "Settings", "Legend" and "Dictionary", to the settings page, the legend and the dictionary (forsgren#83, #84, #128, #370). The footer is the same on every page, so the settings page, the legend and the dictionary link to themselves too (Yves's ruling on decision #133).

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
  project with label rows is headed "Acme Shop (total)", the " (total)"
  in a span that may wrap so it does not widen the first column
  (forsgren#454); one without is one row with its name. With `sub_rows: false` (forsgren#482, decision #488,
  see [Configuration](configuration.md#configuration)) every table, the
  History page and the TBD page included, shows each project's total row
  alone, headed by its name without "(total)" (decision #490). A label row's header also carries its project's
  name for a screen reader ("Acme Shop: API"), hidden on screen, and the
  dash drawn before a label has empty alternative text, so it is not read.
  In the DORA tables and the History table, whose cells stay on one line, the
  header of a label row may wrap at its spaces (`.no-wrap tr.label th`,
  forsgren#454); the dash stays glued to the label (forsgren#526).
- **Each row is counted** by the same five metric functions as a project of
  its own, over its own data: a project's total over all its repositories,
  the numbers the page showed per project before the table; a repository's
  label row over all that repository's deployments, commits and failure
  issues; a service's row over the deployments of its task (written
  exactly, the repository ignoring case) and the commits they shipped
  (joined by repository, kind and deployment ID); a deployment rule's row
  likewise over its kind and name. A failure issue counts on the total and
  on a repository's label row, and on the row of the service or rule whose
  label its `service:` line or `service:<name>` label names (forsgren#515,
  forsgren#53); one without either, or
  with a label no single row has, counts on the total only. Failed
  deployment recovery time reads failed deployments alone, so every row has
  its own.
- **Each cell is short**: the DORA band, then the number that decided it
  and the count it is over, "Less than one day · 2 h 7 min (48)"; the
  weekend deployments have their own column. Durations are in min, h and d,
  each part cut down, never rounded up.
- **Pages:** up to thirteen pages are written: `index.html`, `legend.html`, `settings.html`, `dictionary.html`, `issues.html`, `days.html`, `history.html`, `tbd.html`, `week.html`, the three views and the Numbers and scoring page. Every page opens with one menu, "View: Standard · Numbers · Scoring · Numbers and scoring · Issues · Daily · History · TBD" (forsgren#128, decision #133, forsgren#55, forsgren#68, forsgren#253): the three views, then the Numbers and scoring page, `numbers-scoring/`, then the issues page, `issues.html`, the days page, `days.html`, labelled Daily, the History page, `history.html`, and the TBD page, `tbd.html`, labelled TBD; one folder down its links go through `../`. The current page is plain text marked `aria-current="page"`; the root marks the view it shows `aria-current="true"` (see Views), and the settings, legend and dictionary pages mark none. No page has a link back to the table, since the menu reaches it, and every page ends with the same footer, the version line and then Settings, Legend and Dictionary. Five pages have a key that takes `true`, `unlisted` or `false` (forsgren#159, #55, #68, #200, #253; see [Configuration](configuration.md#configuration)): `issues_page` for `issues.html`, `days_page` for `days.html`, `numbers_scoring_page` for `numbers-scoring/`, `history_page` for `history.html` and `tbd_page` for `tbd.html`. `true` generates the page and lists it in the menu. `false` does not generate it, removes it from the site if an earlier run wrote it (the Numbers and scoring page's folder too, once empty), and leaves it out of the menu. The defaults are `issues_page: true`, `days_page: false`, `numbers_scoring_page: unlisted`, `history_page: unlisted` (from 1.8.2) and `tbd_page: true` (it was `unlisted` before forsgren#409); the starter that `init-config` writes sets `issues_page: false` and `days_page: false`, so a new installation starts with both off (forsgren#285). A render without a config, as forsgren's own build, writes and lists all eleven. The legend explains the five keys and their three values on every page set.
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
  | `tbd.html` | Trunk-based development per project: the Mainline Interval, the lead times, commits per push and per deployment and the developers generated by Forsgren |
  | `week.html` | Deployments, failed deployments and fail rate per weekday, with commits when week_commits is true generated by Forsgren |
  | `legend.html` | How the DORA numbers are counted and scored: the window, the bands and the scores generated by Forsgren |
  | `settings.html` | The settings of forsgren.config.yml and the value in use for each generated by Forsgren |
  | `dictionary.html` | What every number and term on the pages means, and where it comes from generated by Forsgren |

  Counted with the suffix, the longest, the TBD sentence, is 152 characters, under the 160 a search result usually shows, and the standard sentence is 128; the others are 66 to 119. A test fails any page whose description is longer than 160 characters (forsgren#556). The sentences are in `internal/page/description.go`, and the HTMLHint gate's `meta-description-require` rule fails a page without one (see [Quality gates](quality-gates.md)).
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
- **The dictionary page** (`dictionary.html`, titled "Dictionary", forsgren#370) defines every number
  and every term the pages show, in two sections, Numbers and Terms, each in
  alphabetical order. An entry has an anchor id (its name in lower case, other
  characters as hyphens), a heading, one definition and a line "From:" that says
  the data file or the window it is counted over. The page is generated from the one
  embedded file `internal/dictionary/dictionary.yml`, so it reads the same on every
  installation, and a test holds that each figure and term the pages show has an
  entry and each entry names something the pages show. The language gate takes
  the entry names as allowed terms.
- **The settings page** (`settings.html`, forsgren#84, a table since forsgren#141)
  tabulates each optional config key under Parameter, Current value, Possible
  values and Default, see [Configuration](configuration.md#configuration).
  A value that is not accepted (forsgren#183) shows in its row's Current
  value as written, then why and the default in use: "60 is not accepted:
  use 30, 90 or 180. Using the default 30." (an empty value as "(empty)"),
  and its Default shows that default. The rows `deployments` and `paths`
  (forsgren#512) say only how many repositories, services and rules use those
  per-repository settings, as counts or `(not set)`, never a name or path.
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

### Figures: alignment and thousands (forsgren#528)

- **Alignment by content type** (decision #530 A). A cell that holds only a
  figure (a count, a duration such as `1 h 19`, a rate, a share, a dash) has
  class `num` and is aligned on the right with tabular figures, so the digits
  line up: on the TBD page, the Issues and Daily tables and the numbers view
  of the DORA table. The header of such a column is aligned on the right too,
  with its cells; in the two rows of headers of `tbd_figures: all` the mean,
  median and p90 headers are, while a header that spans several columns (the
  group name) and the first column (Project, Date, Period) keep their
  alignment. Cells with words keep theirs too: `Per repository`, the push
  states, the no-data sentence, the band text of the standard and scoring
  views, the scores and the History page.
- **Thousands separator** (decision #529 B). Every count of 1000 or more is
  written through one formatter with the separator the config key
  `thousands_separator` names ([configuration](configuration.md)): a narrow
  no-break space by default (`1 282`, so it never breaks a line), `comma`
  (`1,282`), `period` (`1.282`, forsgren#536) or `none` (`1282`). It covers the DORA cells and their `(N)`
  counts, the TBD volumes, developers and notes, the Issues and Daily tables
  with their trend changes, and the example figures of the legend (the band
  edges, such as `1 441` deployments in 180 days at an 8 hour working day).
  Decimals go through one formatter too (forsgren#536): the config key
  `decimal_separator` writes their mark as a point (`6.0`, the default) or a
  comma (`6,0`) on every page: the TBD figures and shares, the scores, Overall
  Performance, the legend's figures and examples and the Week page's
  percentages; durations such as `1 h 19` have none. The same mark for both
  keys is refused and both revert to their defaults. The docs write figures
  plain. The pages do not sort in the
  browser, so no order depends on the text.

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
  (BETA)", in capitals (one marker, `betaMarker`, forsgren#271); the menu entry
  stays "History". When the page leaves beta, all three go back together. The
  TBD page left beta in forsgren#409 and has no marker.
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

The TBD page (`tbd.html`, titled "Trunk-based development [TBD]", forsgren#253, forsgren#271, forsgren#409)
shows, for each project and for each label or service of it (forsgren#422),
how often and how fast work reaches the main branch and how it is deployed: the Mainline Interval, the Mainline Lead Time, the time to main,
the PR Lead Time and the Bot PR Lead Time, the time to deploy, then the
commits the pushes brought, the commits per push and per deployment, their
shares and the Developers (forsgren#397, Yves's ruling on #401; the order of
forsgren#418 and forsgren#485). It is listed
by default (forsgren#409; before, it was unlisted): generated, in the menu and
without a noindex tag; `tbd_page: unlisted` gives it no menu entry and a
noindex tag (see Unlisted pages under [The page](#the-page), and
[Configuration](configuration.md#configuration)). It is last in the menu,
"TBD"; `false` leaves it out.

- **The table.** A total row per project, then a row under it for each of
  its labels and services (see *The rows* below), with the columns Project, then eleven
  groups in this order (forsgren#397, reordered by forsgren#418; *Mainline Lead
  Time* is the second, right after the Mainline Interval, forsgren#463; PR Lead
  Time before Time to deploy, so the three lead times stand together,
  forsgren#485; Bot PR Lead Time right after PR Lead Time, forsgren#479): *Mainline
  Interval*; *Mainline Lead Time*; *Time to main per commit*; *PR Lead
  Time* (pull requests a person opened); *Bot PR Lead Time* (pull requests a
  bot opened); *Time to deploy per commit*; *Volume* (Commits, Pushes,
  Deployments, Deployed commits); *Commits per push*; *Commits per deployment*; *Shares of
  commits* (Direct, PR, Unknown, Bots; forsgren#403 shortened the two headers,
  each keeps the full meaning in an `aria-label`); and *Developers* (the
  count). The key `tbd_figures` (forsgren#423, see
  [Configuration](configuration.md#configuration)) chooses the figures:
  - `median`, the default: one column for each measure and one row of headers.
    The table has 17 columns, the project and 16 more. The headers are the
    plain names, such as *Time to main per commit*, with no (median) and no
    (duration) in them (forsgren#444); the median is in an `aria-label`, such
    as "median time to main per commit". In this mode PR Lead Time and Mainline Lead Time show their
    median only, and Mainline Interval its median.
  - `all`: the mean, the median and the p90 of each measure, under two rows of
    headers (every group header `scope="colgroup"`, mean, median and p90
    beneath each measure). The table has 33 columns, wider than a phone, and
    scrolls sideways inside its region (Yves accepted that on #401; the
    project screen, forsgren#91, may give the phone its own view). The stat
    headers of every group carry the measure in an `aria-label`, such as "the mean of time to main",
    "the median of mainline interval" or "the p90 of PR lead time" (forsgren#518).

  *The column switches* (forsgren#482, decisions #480 and #481). The keys
  `tbd_time_to_main`, `tbd_pr_lead_time` and `tbd_bot_pr_lead_time` (see
  [Configuration](configuration.md#configuration)), `true` by default, each
  show or hide one group: Time to main per commit, PR Lead Time, Bot PR Lead
  Time. A group turned off is gone in both modes: its headers, cells and state
  sentence, its share of a service row's `Per repository` cell, and the notes
  of its cells (a note that only its cells carried leaves the Notes list and
  the count of columns a no-data row spans shrinks by its columns). The
  measures are still computed; only the table changes. Mainline Interval,
  Mainline Lead Time and the other groups have no switch. The legend says
  that a column the settings turn off is not shown.

  The units are in the names: durations say so, and the others are counts of
  commits. Cells are numbers only: every duration of the page is written in
  the TBD form (forsgren#403, `tbdDuration`; the other pages keep their own):
  hours and minutes `3 h 22`, whole hours `2 h` (never `2 h 0`), minutes alone
  `7 m`, under a minute `< 1 m`, a day or more as on the other pages (`1 d
  6 h`), each part cut down, never rounded up. A count (the mean, median
  and p90 of Commits per push and Commits per deployment) has two significant
  digits, rounded to the nearest with a half rounded up (forsgren#492,
  decision #493: unlike the shares, which round down): under 10 one decimal,
  always shown (`1.0`, `2.5`, `9.9`), from 10 a whole number (`10`, `11`,
  `55`), so 9.95 reads `10` and 10.5 reads `11`; a share has two significant
  digits (see *Shares of commits* below). A value that
  is not shown is a dash in its own cell: a median below two values, a p90
  below ten, a mean without a value, a share without a commit. A project with
  fewer than two commits has a dash in its Mainline Interval cells. The mean
  and the median of the Mainline Interval, of the Mainline Lead Time and of PR Lead Time have no
  deviation, count or share beside them any more (forsgren#423): what the
  count said is in the notes below the table.
- **The rows** (forsgren#422, decisions #449, #450 and #451). `metrics.TbdRows`
  builds every row with all the measures it needs, so no measure is paired
  with a row by position. For each project, in the config's order:
  - *The total row* has every measure over all of the project's data; a commit
    counts once, at its first deployment of any service.
  - *A label row* (`label: Website` on a repository) is that one repository as
    a project of its own, with every measure: its Mainline Interval, pushes and
    pull requests too.
  - *A service row* (`services:` on a repository, one row for each listed
    task) has the measures per deployment, over the deployments of its task
    and the commits they shipped: Time to deploy per commit, Deployments,
    Commits per deployment and Developers. The Mainline Interval (decision
    #449) and the pushes and pull requests (decision #450) name no service,
    so they are not the row's: one cell, `Per repository` (forsgren#475),
    stands across each run of those columns, not a dash in each. With the
    median alone the runs are 5 columns (Mainline Interval, Mainline Lead
    Time, Time to main, PR Lead Time and Bot PR Lead Time), 2 (Commits and
    Pushes: the pushed Commits and the Pushes are the repository's, so one
    cell across the two; Deployments and Deployed commits follow, the
    service's own, and a service without paths has `Per repository` in the
    Deployed commits cell), 1 (Commits per push) and 4 (the shares); with
    `all` the runs of the groups are 15, 2, 3 and 4. A group the column
    switches turn off leaves the first run shorter by its columns.

    The service's own figures are over the commits it owns (forsgren#496,
    decision #497). A service with `paths` counts only the commits that touch them
    in Time to deploy per commit and Commits per deployment,
    each commit once at its earliest deployment: a folder (a path ending in
    `/`) matches everything below it, a file matches exactly, a rename counts
    by its previous name too, `shared/` counts only for the services that list
    it, files in the root of the repository count for no service, a commit that
    touches several services' paths counts once for each, and a deployment none
    of whose commits touch the paths is a deployment of 0 commits. A service
    without `paths` says `Per repository` in those two groups (one cell across
    the group, 3 columns with `all`), as in the runs above; its Deployments
    stay its own. The total row and the label rows count every commit of the
    repository, the commits that no service counts included. The files are read from
    `data/commit_files.csv` ([Data files](data-files.md#commit-files-forsgren496));
    until a commit's files are read it is left out of the service's figures,
    and a deployment with such a commit is left out of Commits per deployment,
    which the note `(8) Files still being read` says.
  - *A rule row* (forsgren#498). A repository with `deployments:` has a service
    row for each rule, headed by the rule's label and counted as a service row
    is, over the deployments of its kind and name (a release having no name),
    on this table and on the DORA tables; its `paths` are the rule's, and a
    rule without `paths` says `Per repository` as a service does. The total
    row counts all of the repository's deployments. `sub_rows: false` hides
    them as it hides the other label and service rows.
  - *The order and the header.* The rows under a project are sorted by label,
    ignoring case, as on the other tables. A label or service row is
    `class="label"`, its header is the label alone and the project is in a
    visually hidden `Acme Shop: ` before it for a screen reader. A project
    without labels or services has its total row alone, as before 1.23.0, and
    so does every project with `sub_rows: false` (forsgren#482): the label
    and service rows are left out with their notes, and the total row is
    headed by the project's name alone (decision #490).
- **The notes** (forsgren#394, decisions #430 and #431). A cell that needs a
  caveat carries a marker, `(N)`, with `aria-describedby` pointing to the
  matching line of the list headed *Notes* below the table. The list is open
  by default and holds one line for each kind of note that occurs, in the
  order of its number, with the projects it applies to and their counts:
  `(1) Mostly estimated: commits timed by author date: Acme Web 7 of 13`. A
  label or service row is named `Project: label` there (`NotesName`, decision
  D4), such as `Acme Shop: Website 2`, though its header shows the label
  alone. A service row has no PR Lead Time or Bot PR Lead Time, so no note of
  those groups. A project whose PR Lead Time and Bot PR Lead Time both carry a
  note of one kind (3 or 4) is named once on its line, the counts added up
  (forsgren#479). The
  numbers are fixed, so (1) means the same on every page and in the legend:
  1. Mostly estimated: more than half of the commits of the Mainline Interval
     are timed by author date.
  2. Commits timed by author date: some, at most half, of them are.
  3. A lower bound: a first commit time of a pull request was cut (decision
     #438), so the PR Lead Time or the Bot PR Lead Time is a lower bound.
  4. Pull requests timed by their created time: the created time stands in for
     a first commit time.
  5. Retired (forsgren#479): it said `Bot pull requests not counted`; the Bot
     PR Lead Time column counts them now. Its number stays reserved, no cell
     shows it and the Notes list never lists it.
  6. Pushes left out: their commits are not known (incomplete data), not
     counted as 0. It sits on the Mainline Lead Time, with the number of
     pushes of the window whose commits are unknown (a cut or failed compare, a
     force push; forsgren#463, decision #468).
  7. History still filling: merge and squash branch commits from before this
     version are missing (decision #469; wording decision #472), so the
     Mainline Lead Time may read short. It sits on the Mainline Lead Time, with
     no count, and is listed with the project. Two things set it, each in the
     DORA window: a merge push (`pr_merge`) with a commit of unknown parents
     (the push commits written before format v2; a direct push with such a
     commit lost nothing and does not set the note, a tip several pushes share
     counts as a merge push when any of them is one, forsgren#476), and a
     merged pull request, not timed by its created time, without lines in
     `data/pull_commits.csv`. The history fill of forsgren#470 (see
     [Data files](data-files.md#collecting-deployments-collect)) reads both
     once per repository; a repository whose fill is done
     (`data/push_commits_filled.csv` for the merge pushes,
     `data/pull_commits_filled.csv` for the pull requests) no longer sets the
     note, also for what GitHub could not give (decision #484). Without the
     fill, the note goes away once the whole window lies after the first
     collection in the new formats.
  8. Files still being read (forsgren#496): commits whose changed files
     forsgren has not read yet are left out. It sits on the first cell of the
     Time to deploy per commit and Commits per deployment of a service row with
     `paths` while some commit of the window's deployments has no line in
     `data/commit_files.csv`, with the number of commits left out, and goes
     once every such commit is read. A service without `paths` has none.

  The notes are the same in both modes: the marker sits on the mean cell when
  the table shows all three figures, and on the median cell when it shows the
  median alone. A new kind is appended at the next number; no number is
  reused. A project that shows only a sentence in its PR Lead Time cell has no
  notes of that group, and a project without data has none.
- **The push groups** (forsgren#397). They read `data/pushes.csv` and
  `data/push_commits.csv` ([Data files](data-files.md#history)), the pushes to
  the default branch of each repository, never the deployments. A push counts
  when it was pushed in the DORA window. Push data starts with the release that
  collects it: pushes made before are not looked up afterwards, so a project
  shows the pushes since the first collection.
  - *Time to main per commit.* The push time minus the author date of the
    commit, a negative time counted as 0, for each distinct commit, at its
    first push. The clock starts at the author date, when the commit was
    written, and stops at the push to the default branch that brought it, at
    the time GitHub records for that push in the branch's activity list. The
    Mainline Interval is a different measure: the gaps between consecutive
    commits of the main line at the time they landed (the committer date),
    how often changes land, where this one is how old a change is when it
    lands (forsgren#448).
  - *The names* (forsgren#448). Mainline Interval and Mainline Lead Time are
    the two metrics of the Mainline Throughput Indicator (forsgren#56). The page
    shows PR Lead Time for the work that goes through pull requests, and Time
    to main for every change, direct pushes included; with the median by
    default the figure is the median time to main.
  - *Three lead times* (forsgren#460, forsgren#463). The Mainline Throughput
    Indicator has one lead time, the Mainline Lead Time. Measured on pull
    requests alone, it leaves out teams that push straight to main, so the page
    shows it in full and as two views: PR Lead Time, from the first commit of a
    pull request to its merge (people only), and Time to main, from the author
    date of a commit on the main line to the push that brought it, direct
    pushes included. A merge counts as its merge commit in Time to main, not
    as the commits it brought in from a branch. Time to main is the stretch of
    a change's lead time from its commit to the main branch, and forsgren's
    own term (#457), for teams that push straight to main. Every lead time of
    the page starts at a commit, so it measures commit to main, not start of
    work to main (forsgren#478): work done before the first commit is not
    visible to any measure from git, and a commit that waits before reaching
    main shows that wait (a RED commit of a fail-fast build stays local until
    the green on top of it is pushed, so its time to main is the time to the
    fix).
  - *Mainline Lead Time* (forsgren#463), the full measure, the second group
    after the Mainline Interval. It reads `data/pushes.csv`,
    `data/push_commits.csv` and `data/pull_commits.csv`
    ([Data files](data-files.md#history)). Every commit that reached main in
    the DORA window counts once, whether it was pushed directly, brought by a
    merge commit, rebased or squashed: its time in main minus its author date,
    a negative time counted as 0, with the median alone or the mean, median
    and p90 under `tbd_figures: all` (the median needs two commits, the p90
    ten, as every spread). The rules, by the decisions that made them:
    - *Merge commits are left out* (#464): a commit with two parents or more.
      Its branch commits stay. So it counts other commits than Time to main,
      which keeps the merge commit and leaves the branch commits out. A merge
      commit's own conflict resolution is not measured. A line whose parents
      are unknown (a push commit stored before format v2) counts.
    - *A squash commit is replaced by its pull request's commits* (#465): the
      commit has one parent, is the pull request's `merge_commit` in
      `data/pulls.csv` (not just any `pr_merge` push) and is the only
      first-parent commit its push brought. The pull request's commits from
      `data/pull_commits.csv` then stand in for it, never both, each from its
      own author date, never the squash commit's. A squash inside a push of
      several first-parent commits stays unrecognised and counts as an ordinary
      commit; so does a squash whose pull request has no stored pull commits.
    - *In-main time* (#466): the earliest push that brought the commit. The
      originals of a squash arrive at the push of the squash commit; with no
      stored push of it they are left out, and `merged_at` never stands in.
    - *Bots count* (#467), as in Time to main. PR Lead Time counts people
      only, so the two cover another population; the Bots share gives context.
    - *Unknown pushes* (#468): a push of the window whose commit count is
      unknown (a cut or failed compare, a force push) brings no commits; note
      (6) gives their number and says they are left out because the data is
      incomplete, not counted as 0.
    - *History* (#469, #470): data stored before the change lacks merge and
      squash branch commits; the history fill reads them once per repository,
      and note (7) says so while the window still holds such data of a
      repository whose fill is not done.
    A project whose push read was refused or not collected shows the push
    states (`Push activity not readable`, `Pushes not collected yet`) in its
    cells, the same words as the push groups. A service row has none of it
    (`Per repository`).
  - *Time to deploy per commit.* For every commit of the first-parent chain of
    the deployments created in the window (merge commits of pull requests
    included, no longer only the direct ones), each at its earliest
    deployment: the deployment time minus the author date, a negative time 0.
    The deployment time is the record's `created_at`: for an environment the
    deployment's creation, for a workflow the run's start, for a release its
    publication. The commits of a deployment without a known lineage count at
    their author date.
  - *Volume.* Commits are the distinct first-parent commits the pushes
    brought, by repository (ignoring case) and SHA, each counted once at its
    first push; Deployed commits (forsgren#513, decision #495) are the
    distinct commits the deployments of the window delivered, a plain number
    like Commits, each counted once at its first deployment in the window as
    Time to deploy counts it, never a sum over deployments: a service or rule
    row with `paths` counts only the commits that touch them (note 8 when
    their files are still being read), a service without paths says
    `Per repository`, and the project's total and a repository's label row
    count the distinct commits of all their deployments, a commit that several
    services or rules shipped once; Pushes the pushes of the window; Deployments the successful
    deployments of the window, as the table page counts them, the number
    only, `85`, whatever the kind of deployment (forsgren#403; it read
    `85 releases` for a project measured by releases alone before).
  - *Commits per push.* The `commits` column of each push with a known count;
    a force push, or a push whose compare failed or was cut, has none and is
    left out here (it still counts in Pushes).
  - *Commits per deployment.* The first-parent commits each deployment brought,
    merge commits included; a deployment without a known lineage is left out.
  - *Shares of commits.* Each is a share of the Commits number, computed from
    the counts with two significant digits, rounded down (forsgren#477,
    decision #487): a whole percent from 10% (`19%`, `100%`), one decimal from
    1% (`1.3%`, `5.0%`), two decimals under 1% (`0.65%`), `< 0.01%` for a
    share above 0 and under 0.01%, and `0%` for none. A share never shows more
    than it is and a non-zero one never reads 0. PR (the pull request share): the commit is the merge commit
    (`merge_commit` of `data/pulls.csv`) of a pull request, or a pull request
    merge (kind `pr_merge`) brought it. Direct: every other commit. Unknown
    (the unknown author share): the commit has no login, or GitHub's placeholder login
    `invalid-email-address` (ignoring case). Bots: the author login ends in
    `[bot]`, as the developer count tells a bot (Yves's ruling on #397). The
    last two are counted whatever else the commit is, so Direct and Pull
    requests add up to 100% (give or take the rounding) and the others
    overlap them. The counts are kept in the metrics.
  - *Mean, median, p90.* The same rules as the Mainline Interval's: the median
    is the middle value, or the mean of the two middle ones, and needs two
    values; p90 is the nearest rank, the value at position `(9n + 9) / 10` of
    the sorted values, and needs ten.
  - *Not readable and not collected.* A project with a repository whose push
    read GitHub refused (a 403, kept in `data/pushes_denied.csv`) shows `Push
    activity not readable`, a project with no `data/pushes.csv` yet `Pushes not
    collected yet`: one cell under each of the time to main, commits per push
    and shares groups (with `tbd_figures: all` three, three and four columns,
    with the median alone one, one and four, the same text in each), a dash
    for Commits and Pushes, and never deployment numbers in its place. If the
    project also has no data at all (see Without data below), the sentence of
    the no-data row wins and the row shows that alone. The Deployments column and the deployment
    groups keep their numbers. A repository is matched to its project ignoring
    case. The legend names both states.
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
  window. The Mainline Interval cell carries a note for them, by either rule: note
  (2), `Commits timed by author date`, with the project's count, such as
  `Acme Shop 3`, and nothing when there are none. When more than half of the
  commits are timed this way, the note is (1), `Mostly estimated`, with
  the count and the commits it is of, such as `Acme Web 7 of 13`.
- **The gaps.** The commits are put in the order of the times they are placed
  at (the committer date, or the author date as above), whatever the order they
  are stored in, and a gap is the time between two neighbours; two commits
  placed at the same time have a gap of 0. The mean is the mean of the gaps.
  The median is the middle gap, or the mean of the two middle gaps when their
  number is even. The 90th percentile (p90) is the nearest-rank one: the gap at
  position 0.9 times the number of gaps, rounded up (in integers, (9n + 9) /
  10), of the gaps sorted from the shortest, so an actual gap and nine tenths
  of the gaps are no longer than it. They tell the typical spacing from
  occasional long gaps: a mean far above the median points at a few long gaps
  among short ones. The page has no column for the deviation or for the number
  of gaps since forsgren#423 (the column `gaps` and the deviation were the
  first version's, forsgren#387); the sample standard deviation and the count
  are not shown.
- **A dash.** Fewer than two commits have no gap, so every Mainline Interval
  cell is `-`. One gap has a mean but no median, which needs two gaps: with
  `tbd_figures: all` the cells read `2 h` for the mean and `-` for the median
  and the p90, and with the median alone the cell is `-`. The p90
  needs ten gaps (under ten, the nearest rank is the longest gap, which the
  maximum already says); each is a dash until then.
- **Without data.** With no projects the page says so in one line, and so it
  does when no data was given to the render ("No commits have been collected
  yet, so there is no Mainline Interval to show.").
- **A project with no data** (forsgren#394, decisions #433 and #442). A
  project that has no deployed commit, no final deployment in the window (a
  failed one counts as one), no push and no merged pull request in the window
  (a bot's pull request included) shows its name and one cell across the whole
  row: `currently no data for this project in the last 30 days`, where 30 is
  the `dora_days` in force. The cell spans all the columns after the project,
  16 with `tbd_figures: median` and 32 with `all`, fewer by the columns the
  column switches turn off, and has no note marker. A
  project with data in any one of the four keeps its row of figures, and a
  single measure without a value keeps its dash: a project with a deployment
  but no commit shows a dash in the Mainline Interval and in Developers. When
  the push read was refused or no push was collected, the project is judged
  without pushes, so the sentence wins over the push states above only when
  the other three are absent too.
- **A service with no data** (forsgren#422, decision #451, A). A service row
  has no data when it has no final deployment in the window (a failed one
  counts) and no deployed commit (`metrics.ServiceNoData`); its pushes and pull
  requests do not count, since they name no service. It shows one cell across
  the row, as a project does, with the word *service*: `currently no data for
  this service in the last 30 days`. A label row follows the rule for a
  project, over its own repository, and says *project*.
- **Developers.** One column next to the Mainline Interval (forsgren#273),
  because a team of ten makes more commits than one person with the same
  habits; the interval itself is not divided by it. It counts the distinct GitHub logins of the authors of the commits
  deployed in the window (the Mainline Interval's window, each commit once),
  ignoring case, so
  one person is one developer across the email addresses they commit with. Logins that the config's `same_developer` lists together count as one
  developer too, also ignoring case, and the stored commits keep each login
  (see [Configuration](configuration.md)). The
  first-parent chain does not apply here: the authors of the commits a merge
  brought in count too, since on the chain alone it would count whoever merged
  (decision 294 of forsgren#254). A
  bot account (a login ending in `[bot]`, such as `dependabot[bot]`) is no
  developer and its commits are left out. A commit without a login (GitHub
  links its email to no account, or it was stored by the commits format v1) is
  not guessed to be anyone's, and GitHub's placeholder login
  `invalid-email-address`, ignoring case, is no developer either
  (forsgren#355). The unknown authors are a share of the pushed commits now
  (see The push groups). The cell is the count, `3`; a project with no
  deployed commit shows a dash, and a project whose commits are all by bots
  has 0 developers. Each
  row has the Developers of its own data (`metrics.TbdRows`), so a count is
  never taken from another row. The number is a count only; no
  login reaches a page (`TestRenderShowsNoCommitAuthor` renders every page
  from commits that all carry one login and finds it on none, the TBD page's
  Developers cell counted from it). The legend's TBD section explains the
  column: what a developer is, how listed logins count as one, bots left out,
  never who the developers are.
- **PR Lead Time** (forsgren#256, forsgren#403), the group after Time to main per commit
  and before Bot PR Lead Time (forsgren#485): how old a change is when it reaches
  the main branch, in one column since forsgren#397: pull requests. The first
  version had direct and batch size columns beside it (forsgren#390); the push
  and deployment groups replaced them. The pull requests column covers merged
  human pull requests only, not every change that reaches the trunk
  (forsgren#342): work pushed straight to the main branch is in the push
  groups and the Direct share, so a pull request stands in for the life of a
  branch, and in a workflow that mixes both this column covers only the
  pull-request changes.
  - *pull requests.* What the rest of this entry describes.
  - *What is counted.* One lead time per pull request merged in the DORA
    window, counted by its merge time: from its first commit, the earliest
    author date of its commits, to the merge. A first commit dated after the
    merge counts as 0. The pull requests come from `data/pulls.csv`.
  - *The cell* is a duration, such as `3 h 22`: the median of the lead times
    with `tbd_figures: median`, the default, or the mean, the median and the
    p90 in three cells with `all` (forsgren#423, Yves on #432). The median
    needs two pull requests and the p90 ten, and each is a dash until then;
    with no human pull request all are dashes. The deviation, the count in
    brackets and the share of pull requests merged within 24 hours were in the
    cell before forsgren#423 (`3 h ± 1 h (4)` and `50% (2 of 4) pull requests
    merged within 24 hours of their first commit`) and are not shown any more.
    There is no pass or fail verdict: the figure is supporting evidence.
  - *Two dates.* The Mainline Interval uses the committer date (how often
    changes reach the trunk); PR Lead Time uses the author date of the
    first commit up to the merge time (how old changes are when they reach it).
    Read together: short interval and short lead time is frequent, fresh
    integration; short interval and long lead time points at long-lived
    branches; long interval and short lead time is few changes, each integrated
    quickly; long and long is rare, old changes.
  - *Cut and stood in.* When GitHub lists only part of a pull request's
    commits, its first commit time may be too late. The cell then carries note
    (3), `A lower bound: a first commit time of a pull request was cut`, with
    the number of pull requests (decision #438): the figures of the cell can
    be too low. When the commit list gave no usable date, the created time
    stands in, and note (4) says how many: `Pull requests timed by their
    created time`, such as `Acme Web 1`.
  - *People.* Only a GitHub account of the type `User` is a person. Pull
    requests opened by a bot are counted in Bot PR Lead Time instead (below;
    note (5) said `Bot pull requests not counted` until forsgren#479), and
    those whose author is not known to be a user, such as a pull request in
    the legacy format (pulls format v1), which has no known author type, are
    counted in neither; the cell does not say how many of them (forsgren#403). A
    project with no human pull request shows a dash in pull requests (it read
    `No human pull requests in this period; changes may go directly to the
    trunk` until forsgren#390; the sentence is now the legend's), which is not
    proof of direct commits; the Direct share shows them.
  - *Not readable and not collected.* `Pull requests not readable` means the
    token was refused the pull request read for a repository of the project
    (a 403, kept in `data/pulls_denied.csv`, see
    [Data files](data-files.md#history)); it replaces the whole cell and is
    cleared by the next read that succeeds. `No pull requests have been
    collected yet` means `data/pulls.csv` does not exist yet.
  - *Legacy format.* Records in the legacy format have no known author: the
    data establishes that format, not when or why the record was stored. A
    pull request in the legacy format (pulls format v1) has no known author
    type and is not counted in the lead time. In the Mainline Interval, when
    more than half of the commits are timed by author date the note reads
    (1), `Mostly estimated: commits timed by author date`, `Acme Web 7 of 13`.
- **Bot PR Lead Time** (forsgren#479), the group right after PR Lead Time:
  the same measure over the merged pull requests a bot opened (an account of
  the type `Bot`, such as Dependabot's), in place of note 5. One lead time per
  such pull request merged in the window, from its first commit to its merge;
  the median alone, or the mean, the median and the p90 with
  `tbd_figures: all`, by the same rules; notes (3) and (4) as for PR Lead
  Time; the same two sentences for a refused read and for pull requests not
  collected yet; a service row has none of it (`Per repository`). PR Lead Time
  keeps counting people only, and a pull request of unknown author is in
  neither. A project whose only merged pull requests are a bot's shows a dash
  in PR Lead Time and its figures here.

The page itself has the heading and the table, or its one line. The legend's
section for the page, headed with the same title, is the reader's page
(forsgren#448): question headings, what the numbers mean, the window in force,
the names, the numbered notes and a link to this section. The
calculation detail above stays here; the menu entry stays "TBD". The page has no
BETA marker since forsgren#409; the History page keeps its marker.

### The Week page

The Week page (`week.html`, forsgren#531, from 1.29.0) shows when the work
happens (decisions #532, #533, #534 and #539). One table, a row per project and
under it a row for each label, service or rule (`sub_rows: false` leaves those
out, as on the other tables), with two header rows: Project, then Total and Monday to
Sunday in full, each with Deployments, Failed and Fail rate under it
(Failed and Fail rate from forsgren#545, decision #546), and Commits before
them with `week_commits: true` (forsgren#548, decision #549). The figures cover every weekday of the `dora_days` window, not one
calendar week, so a Monday appears as often as the window holds Mondays. The
page says nothing else above the table (forsgren#544): how to read Total and
the shares, and that the window is the last `dora_days` days, the period the
footer names as Report Start and Report End, are in the legend's Week page
section.

- Total holds Deployments, the row's successful deployments of the window as a count,
  written as every count (a thousands space from 1000); `0` for a row with
  none (forsgren#540, decision #541), then Failed and Fail rate (below).
  **A weekday** has a Deploys cell, the share of the row's deployments on that weekday,
  written like the shares on the TBD page (`13%`, `9.3%`,
  `0.22%`, `0%` for a weekday without any); the seven shares of a column add up to 100%, rounding aside.
  The weekday groups head that column Deploys, which saves width (forsgren#552);
  Total keeps Deployments, and every header's `aria-label` keeps the full
  word (`Monday deployments`), so a screen reader hears deployments.
  With `week_commits: true` Total and every weekday also have a Commits cell first:
  in Total the count of the row's commits, under a weekday the share of them on that weekday.
  A row with no commits reads `-` in its seven Commits cells, and one with no
  deployments in its seven Deployments cells, as there is nothing to divide.
  A commit counts at its author date and a deployment at its time, both in UTC
  (decision #532): a commit authored on Sunday at 23:30 UTC is a Sunday
  commit, one authored at 00:30 on Monday a Monday commit, whenever it was
  pushed or deployed.
- **Failed and Fail rate** (forsgren#545, decision #546, forsgren#547). A failed deployment
  is a deployment of state `failure` created in the window (state `other` is
  not failed, and is left out of Fail rate), over the row's own deployments for a service or
  rule. In Total, Failed is the count of the row's failed deployments and
  Fail rate the failed deployments out of the successful plus failed ones
  of the window. Under a weekday, Failed is the share of the
  row's failed deployments on that weekday, written like the other shares
  (`-` for a row with no failed deployment), and Fail rate is the failed
  deployments of that weekday out of its successful plus failed ones
  (`0%` where it deployed and nothing failed, `-` for a weekday without
  any, also one with only `other`; the change fail rate counts the same). The Deployments column keeps counting
  the successful deployments only, so it is not the denominator. In each
  row the weekday with the highest Failed and the one with the highest Fail
  rate are red (class `highest`, one `light-dark()` rule in `styles.css`,
  held at 4.5:1 or more in both modes by `trendcolours_test.go`), every tied
  weekday, none for a row without failed deployments; the cell also holds the
  visually hidden word "highest" for a screen reader, so colour is never the
  only signal. The legend's Week page section says all of this in one
  paragraph.
- **The Total row** (forsgren#552, decision #553, built as a header line on
  Yves's reply), the first row of the table body, right under the column
  headers and before the first project row (`<tr class="week-total">`, a row
  header `Total` and data cells, so it stays a data row and not a header
  row): every project row added up, per weekday, the
  commits (shown with `week_commits: true`), the successful deployments and
  the failed ones. A label, service or rule row is not added again, its
  project's row already counting it, so `sub_rows: false` leaves the Total
  row as it is. Its cells take the form of a project row's: counts in Total,
  the shares of the sums under each weekday, and Fail rate the failed
  deployments of the sums out of their successful plus failed ones, not a
  mean of the projects' rates; its highest Failed and Fail rate weekdays are
  red as in every row. The row is shaded (Yves's ruling on #552): its
  background is a little of the text colour, `color-mix(in srgb, currentcolor
  8%, transparent)` on `tr.week-total` in `styles.css`, so it follows the light and
  the dark scheme with no colour of its own, and its text and red marks keep
  4.5:1 or more (`weektotalshade_test.go`). The Total row appears only with two project rows or
  more (label, service and rule rows not counted; Yves's ruling on #552): with
  one project it would only repeat that project's row, so the table has no
  Total row. A page without a table (no projects, or nothing collected) has no
  Total row.
- **The commits** of a project's total row and of a repository's label row are
  the set of the Commits column of the TBD page: the first-parent commits
  that the pushes to the main branch brought in the window, each once. The
  **deployments** are the successful ones created in the window, over the
  row's own data for a service or rule.
- **A service or rule with `paths`** counts its own commits: the distinct
  commits of its deployments that change one of its paths, each once at its
  first deployment in the window, the commits that Deployed commits counts on
  the TBD page; a commit whose files are not read yet is left out.
- **A service or rule without paths** cannot tell which commits are its own,
  so its Total Commits and its seven Commits cells read `–`: the en dash stands for commits not
  attributed to this service or rule, counted at repository level on the
  project's row (decision #534; the dash is Yves's ruling on decision #539,
  because `Per repository` in every cell made the table 516 px wider than its
  box on a phone, 76 px now). It is not zero commits and not missing
  deployment data; its Deployments cells are the percentages of the deployments of
  the service or rule itself, and `0` / `0%` means zero.
- **`week_page`** (forsgren#531, decision #533): the page is in the menu unless
  `week_page: false`, which takes it out of the menu and asks search engines
  to skip it; the page is still written and reachable at `week.html`. See
  [Configuration](configuration.md#configuration).
- **`week_commits`** (forsgren#548, decision #549): the Commits columns, under
  Total and under each weekday, are shown only with `week_commits: true`; by
  default each header group is Deployments, Failed and Fail rate. The commits
  are still computed. See [Configuration](configuration.md#configuration).

The page has the heading and the table, or one line when there are no projects or nothing is collected
yet. The legend has a Week page section for the reader.

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
