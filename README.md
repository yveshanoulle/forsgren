# forsgren

Measure the five DORA metrics for a set of GitHub repositories, from GitHub
data, and publish them as a small static status page.

Named after Dr. Nicole Forsgren, whose research with DORA (and the book
*Accelerate*, with Jez Humble and Gene Kim) defined the first four of these metrics.

## The five metrics

| Metric | Question it answers |
|---|---|
| Deployment frequency | How often do we ship to users? |
| Change lead time | How long from a commit to that commit reaching users? |
| Change failure rate | What share of deployments causes a failure users hit? |
| Failed deployment recovery time | When a deployment fails and needs immediate intervention, how long until a successful one recovers it? |
| Deployment rework rate | What share of deployments is unplanned, made to fix a problem users hit? |

## How it gets its data

forsgren reads only what is already in GitHub:

- **Deployments:** workflow runs (for example a TestFlight upload) and GitHub
  Deployments, with their commit and end time. Failed deployment recovery
  time comes from these alone, the failed ones and the successes after them
  (see Failed deployment recovery time).
- **Failures**, for change fail rate (forsgren#18): issues labelled
  `failure`, and the failed deployments. Each issue carries a short record
  block in its body:

  ```
  failure-start: 2030-04-01T09:30+02:00
  failed-build: 12.345
  fixed-build: 12.346
  ```

  `failure-start` is when users were first hit; the two builds name the
  deployment that caused the failure and the one that fixed it. forsgren
  stores the issue's opening and closing times and its `failure-start`; an
  issue without a `failure-start` it can read is stored all the same and
  named on stderr by `collect`, never silently skipped (see Collecting
  deployments, The failure issues). The builds are not used yet.

## What it produces

- the current value of each metric, per service
- a history file, so each metric can be shown as a trend
- a static page with the current numbers and a trend chart per metric, safe to
  publish: numbers and dates only, no issue titles, no links into private
  repositories

## Where configuration and data live

Not in this repository. It holds code only. An installation keeps its
configuration (which repositories and services, workflow names, labels, the
health URL) and its data (`data/deployments.csv`, the deployments fetched
from GitHub, `data/commits.csv`, their commits, `data/failures.csv`,
the failure issues, `data/issues.csv`, what happened to every issue, and
`data/issue_bugs.csv`, which issues carry the `bug` label) in a separate private
data repository, made from a template, and
passes them to forsgren as paths. Test fixtures are made up (`acme/app`) and live only
under `testdata/`.

The data guard that keeps it that way is described in [docs/development.md](docs/development.md).

## History

The deployments `forsgren collect` finds are kept in the installation's data
repository, in `data/deployments.csv` (the history format v1, package
`internal/history`). It is plain CSV, one deployment per line, so the daily
commit of `data/` is a diff of added lines:

```
# forsgren history v1
project,repository,kind,name,deployment_id,commit,created_at,state,task
shop,acme/app,environment,production,1001,<40 hex>,2026-09-01T10:00:00Z,success,
```

- The first line states the format version, the second names the columns.
- `kind` is `environment`, `workflow` or `release`; `name` is the environment
  or workflow file (empty for a release); `deployment_id` is the ID at GitHub;
  `created_at` is UTC; `state` is the final state, `success`, `failure` or
  `other` (a deployment still running is stored once it has finished); `task`
  may be empty.

**History is never overwritten.** forsgren creates `data/` and the file when it
first stores history, with the version line. After that it only appends: a
deployment already in the file (same repository, compared ignoring case as
GitHub compares names, same kind and same ID) is skipped, so
the first line stays even if GitHub says something else later, and no line is
rewritten or removed. The new lines are written in one write and synced, after
a newline if the last line lacked one. A file whose first line states another
version, or with a line that is not in the format, is refused before anything
is written: its bytes and modification time stay as they were, and the error
names the line.

**The commits of each deployment**, for lead time (forsgren#16), are kept
next to it in `data/commits.csv`, with its own format version (the commits
format v1); `data/deployments.csv` does not change. `collect` writes it,
always next to the `--data` file (see Collecting deployments, The commits
of each deployment):

```
# forsgren commits v1
repository,kind,deployment_id,commit,authored_at,deployed_at
acme/app,environment,1001,<40 hex>,2026-09-01T09:00:00Z,2026-09-01T10:00:00Z
```

- One line per commit per deployment. `repository`, `kind` and
  `deployment_id` are the deployment's key in `deployments.csv`;
  `authored_at` is the commit's author date and `deployed_at` the
  deployment's `created_at`, copied so lead time needs no join. Both are UTC.
- The project and the task are not repeated: the project comes from the
  config, as for deployment frequency, and the task is the deployment's own.
- The same rules as `deployments.csv`: created with its version line,
  appended only, refused untouched when its version is unknown or a line is
  malformed. A commit already there for the same deployment (repository
  ignoring case, kind, ID and the same SHA) is skipped; a call with nothing
  new leaves the file alone.

**The failure issues**, for change fail rate (forsgren#18), are kept next to
it in `data/failures.csv`, with its own format version (the failures format
v1):

```
# forsgren failures v1
repository,issue,opened_at,closed_at,failure_start
acme/app,42,2026-09-01T10:00:00Z,,2026-09-01T09:30:00Z
acme/app,42,2026-09-01T10:00:00Z,2026-09-01T15:00:00Z,2026-09-01T09:30:00Z
```

- One line per state of an issue labelled `failure`: `issue` is its number,
  `opened_at` and `closed_at` its `created_at` and `closed_at` at GitHub
  (`closed_at` empty while it is open), `failure_start` its `failure-start:`
  line (empty when it has none forsgren can read). All are UTC.
- An issue changes after it is stored: it is closed, or reopened. The file
  still only grows, so an issue gets a new line whenever it differs from its
  newest line (key: repository, ignoring case, and issue number), and the
  newest line of an issue is the issue: above, issue 42 was stored open, then
  closed. An unchanged issue is not written again, and a call with nothing
  new leaves the file alone.
- Otherwise the same rules as `deployments.csv`: created with its version
  line, refused untouched when its version is unknown or a line is
  malformed.

**The issue events**, for the days and issues pages (forsgren#76, #123, #128), are kept in
`data/issues.csv`, with its own format version (the issues format v1). It
holds every issue of a configured repository, whatever its labels, as one
line per event:

```
# forsgren issues v1
repository,issue,event,reason,at
acme/app,7,created,,2026-09-01T10:00:00Z
acme/app,7,closed,not_planned,2026-09-01T13:00:00Z
acme/app,7,reopened,,2026-09-02T12:00:00Z
```

- `event` is `created`, `closed` or `reopened`. `reason` is GitHub's
  `state_reason` on a `closed` event, `completed`, `not_planned` or
  `duplicate`, and empty when GitHub gives none (an old issue) and on the
  other two events. `at` is UTC, to the second.
- Events, not states: a line is never revised, so a past day's counts never
  change after the fact. The file only grows; an event already there
  (repository ignoring case, issue number, event and time) is not written
  again, and a call with nothing new leaves the file alone. Lines are
  appended in time order within a call.
- Otherwise the same rules as `deployments.csv`: created with its version
  line, refused untouched when its version is unknown or a line is
  malformed, naming the line.

**The bug flags**, for the Open bugs column (forsgren#126), are kept in
`data/issue_bugs.csv`, with its own format version (the issue bugs format v1):
one line per state of an issue that carries, or carried, the GitHub label
`bug`.

```
# forsgren issue bugs v1
repository,issue,bug
acme/app,7,true
acme/app,8,true
acme/app,7,false
```

- `bug` is `true` or `false`. The file only grows, yet a label can be removed,
  so an issue gets a new line when its flag changes, like a failure issue
  (key: repository ignoring case and issue number); the newest line of an
  issue is the issue. Above, issue 7 had the label and lost it, and issue 8
  still has it. An unchanged flag is not written again.
- It is not part of `issues.csv`: those events stay as they are, and the
  flag is joined to them when the page is rendered.
- Otherwise the same rules as `deployments.csv`: created with its version
  line, refused untouched when its version is unknown or a line is
  malformed, naming the line.

## Deployment frequency

The first DORA number on the page (forsgren#12, step 7, package
`internal/metrics`), the first column of the page's table (see The page):
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
History). A missing file is no commit; a file with an unknown version or a
malformed line fails the render with its own message. Yves's rulings:

- **Per commit**, DORA's definition: each commit's lead time runs from its
  author date to the creation time of the successful deployment that
  shipped it.
- **The commits of a deployment** are those since the previous successful
  deployment of its stream: the same repository, rule, environment or
  workflow, and task, while a repository's releases are one stream (see
  Collecting deployments, The commits of each deployment). The first
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
  concluded `failure` (see Collecting deployments), so for such a
  repository a run that failed before touching live counts too. Failure issues (the `failure` label with its
  record block, see How it gets its data) are the source of change fail
  rate (forsgren#18), not of this number.
- **Recovered by the next success of its stream.** The stream is
  collect's (see Collecting deployments, The commits of each deployment):
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
  the window, from `data/failures.csv` (see History, Collecting
  deployments). An issue counts once, open or closed, as its newest line
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
version that built the page, the version line adds it, "Forsgren 0.8.6 ·
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
  row per label its repositories give (see Configuration, `label` and
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
  config key (see Configuration): that view, which its menu marks
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
  known limits below). It has no week or month row: those are on the issues
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
  times `collect` saw them (see Issue events), so an Open from before a
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
  `data/issue_bugs.csv` (see History, Bug flags); a missing file marks no
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
  values and Default, see Configuration.
- **Layout:** no table has a caption: each is named by its page's heading
  ("DORA metrics" on the three views and the root, Issues, Daily), and one `h1`
  rule in `styles.css` sets the look of every page's heading (forsgren#135), and every table has `<th scope>` headers; it scrolls
  sideways inside its own box on a narrow screen, so the page keeps its
  1rem (16px) gutter and never scrolls sideways itself. `styles.css` sets
  no colour but `color-scheme: light dark`, so light and dark mode follow
  the browser's own colours, the lines drawn in the text colour, with one
  narrow exception (Yves's ruling on forsgren#114 and forsgren#126): the
  trend arrows of the issues tables, `.trend-up` red, `.trend-down` green and
  `.trend-flat` grey, each `light-dark(light, dark)` and at 4.5:1 contrast or
  more against the page background in its mode, which a test measures. It is
  not a general permission for colours elsewhere.

The page shows project names, labels and numbers only: never a repository's
or a task's own name, a SHA or a commit message.

## Configuration

An installation describes what forsgren measures in one file,
`forsgren.config.yml`, in its data repository. Together with `data/` it is
all an installation's owner owns, so the template contains neither: it holds
only forsgren's own files. Installing a new version is one click: the
template's `.github/dependabot.yml` makes Dependabot open a pull request that
moves the pinned `uses:` line to each new release, and merging it is the
update (#14). A release that changes more than that line (a permission, a
secret) says so in its notes; then the owner copies the new template's files
over the data repository once, which replaces every forsgren file and never
touches `forsgren.config.yml` or `data/`, and the repository keeps its secrets
and Pages address (ruled 2026-10-02, #9). forsgren creates
`data/` when it first stores history and never overwrites history that is
there. One installation measures every project it lists on one page, each
project in its own rows of one table (#6, #38).

```yaml
version: 1
projects:
  - name: Acme Shop
    repositories:
      - name: acme/api                          # owner/name on GitHub
      - name: acme/ios-app
        deployment: workflow=testflight.yml
  - name: Acme Tools
    repositories:
      - name: acme/cli
        deployment: release
```

- **`version: 1`** is required: it is the format's version. A file without
  it, or with any other version, is refused, so a forsgren never misreads a
  file written for another format.
- **`view`** is optional (forsgren#46): the view the site's root page shows,
  `standard`, `numbers` or `scoring` (forsgren#47), written
  at the top level, for example `view: numbers`. Left out, or without a value,
  the root is the standard page and the menu marks no view, so an
  existing installation sees the standard table until it opts in; with a
  `view:`, even `standard`, the root page is that view and the menu marks it. Any
  other value is refused by `check-config` and `render`, naming the key and
  the valid values: `invalid view "Numbers": use standard, numbers or scoring`. Each
  view is also its own page at `/standard/`, `/numbers/` and `/scoring/`, whatever this
  key says. The starter that `init-config` writes for a new installation
  includes `view: standard` (forsgren#51), so a new installation's menu
  marks its view from its first run; an existing config without `view:` keeps
  the plain root, as `init-config` never rewrites an existing file. The starter
  also writes `auto_update: true` and `auto_update_level: patch` (forsgren#58),
  so a new installation merges forsgren's patch releases by itself; an
  existing config without `auto_update:` keeps it off (see Auto-update).
- **`history_days`** is optional (forsgren#57): how deep a repository's
  history goes, in days, a whole number from 1 to 1825 (5 years), written at
  the top level, for example `history_days: 730`. Left out, or without a
  value, it is 365. Anything else (zero, a negative number, more than 1825, a
  quoted value, a decimal or text) is refused by `check-config` and `render`,
  naming the key and the limit: `invalid history_days "1826": use a whole
  number of days from 1 to 1825`. forsgren does not read that far at once:
  a repository's first run reads one chunk (`history_chunk_days`), and each
  later run reads what is new plus one older chunk, until the history reaches
  `history_days` back (see Collecting deployments). It is also the most any
  run reads back, however old the newest stored deployment is, and how far
  back the first read of a repository's failure issues goes. Raising it later fills in
  the extra range, chunk by chunk, from where each repository's history ends
  now; lowering it stops the older chunks sooner and removes nothing. To read
  a range again that was already read, remove that repository's rows from
  `data/deployments.csv`, `data/commits.csv` and `data/reach.csv`, or remove
  `data/`, and the next run is its first run again. What GitHub no longer
  returns (a deleted deployment, a run past its retention) cannot come back.
  The starter that `init-config` writes includes `history_days: 365`.
- **`history_chunk_days`** is optional (forsgren#57): how many days back each
  run adds until `history_days` is reached, a whole number from 1 to 365,
  written at the top level, for example `history_chunk_days: 30`. Left out,
  or without a value, it is 100; it is not tied to `history_days`. Anything
  else (zero, a negative number, more than 365, a quoted value, a decimal or
  text) is refused by `check-config` and `render`, naming the key and the
  limit: `invalid history_chunk_days "366": use a whole number of days from 1
  to 365`. A repository's first run reads this many days back, and each
  later run adds one older chunk of this size until `history_days` is
  reached; a chunk larger than `history_days` is allowed and covers all of it
  in one read. The starter that `init-config` writes includes
  `history_chunk_days: 100`.
- **`working_hours`** is optional (forsgren#71): how many hours a working day
  is, a whole number from 1 to 24, written at the top level, for example
  `working_hours: 8`. Left out, or without a value, it is 8. Anything else
  (zero, a negative number, more than 24, a quoted value, a decimal such as
  `8.5` or `8.0`, or text) is refused by `check-config` and `render`, naming
  the key and the limit: `invalid working_hours "25": use a whole number of
  hours from 1 to 24`. It is read and checked now; the on-demand threshold
  uses it in the next step. The starter that `init-config` writes includes
  `working_hours: 8`.
- **The settings page** (`settings.html`, forsgren#74, moved out of the legend
  in forsgren#84, a table since forsgren#141) tabulates every optional key,
  `view`, `auto_update`, `auto_update_level`, `history_days`,
  `history_chunk_days` and `working_hours`, in four columns: **Parameter**;
  **Current value**, the value in use (`none` for an unset
  `auto_update_level`); **Possible values**, built from the config package's
  own constants and limits so the page cannot drift from what `check-config`
  accepts (`standard, numbers, scoring`; `true, false`; `patch, minor, major
  (required when auto_update is true)`; `1 to 1825`; `1 to 365`; `1 to 24`),
  a test holds the lists to the config loader; and **Default**: True when
  `forsgren.config.yml` does not set the key, so the current value is the
  default, False when the file sets it, even to the default's value. The legend
  explains the Default column.
- **`projects`** is required: a list of projects, or `projects: []` for an
  installation that measures nothing yet (it is valid, and `check-config`
  reports `projects: 0, repositories: 0`). A file whose `projects` key is
  missing, or has no value (`projects:`, `projects: null`), is refused with
  `no projects`, so a forgotten list is never taken for an empty one. A
  project is a name and the repositories that ship it (a product can be
  several repositories). Project names are unique, ignoring case.
- **`repositories`**: at least one per project, each `owner/name`, and each
  listed once in the whole file (ignoring case, as GitHub does).
- **`deployment`** says what counts as a deployment of that repository (#6):
  - left out, or `environment=production`: a GitHub Deployment to the
    environment `production` whose status is success. This is the default
    and the recommended way: it works in any repository, and carries the
    commit lead time is measured from. `environment=<name>` names another
    environment.
  - `workflow=<file>.yml` (or `.yaml`): a successful run on `main` of that
    workflow, by its file name in `.github/workflows/` (no directory).
  - `release`: a published GitHub Release, for App Store apps and tools.

- **`label`** and **`services`** are optional, per repository
  (forsgren#38): they name the rows the page shows under the project's
  total. The page never shows a repository's or a task's own name, only a
  label written here, so a public page names nothing its owner did not
  choose.
  - `label: Website`: one row for all of the repository's deployments,
    its commits and its failure issues.
  - `services:`, a map of deployment task to label: a row per listed
    task, with that task's deployments and the commits they shipped. A
    task left out counts in the project's total only.
  - neither: no row of its own; the repository counts in the total only,
    as every repository did before.

  ```yaml
  version: 1
  projects:
    - name: Acme Shop
      repositories:
        - name: acme/app
          services:
            deploy-api: API
            deploy-admin: ADMIN
            deploy-ios: IOS
        - name: acme/web
          label: Website
  ```

  The rows under a project are sorted by label, ignoring case (ADMIN, API,
  IOS, Website); a project without labels shows its total row alone.
  Refused: an empty label, a label used twice in one project (ignoring
  case), a label or task that is not text (`label: 5`, `deploy-api: true`),
  `services: {}` or a task that is empty, `label` and `services` on one
  repository (a row for the repository and rows for its services would
  count the same deployments twice beside each other), and `services` on a
  `release` repository (its task is the tag, new with every release). A
  `label:` or `services:` without a value is the key left out.

A **failure** is an issue labelled `failure` whose body carries the failure
record block (see How it gets its data); lead time runs from a change's first
commit. Neither is configured per repository in version 1.

Any other key is refused, as is a value of the wrong kind or a second YAML
document in the file, so a typo never silently does nothing. Every refusal
names the file, the project and repository it is in (or the line, for a
YAML error) and what to write instead, on one line: a line break in a key
or value it quotes is written as `\n`.

Check a config without rendering anything:

```
forsgren check-config --config forsgren.config.yml
```

It prints one line, `OK: forsgren.config.yml is a valid forsgren config
(version 1): projects: 2, repositories: 3`, with `, labels: 4` added when
the file labels rows, and exits 0; it exits 1 with
the refusal on stderr when the file is invalid or cannot be read, and 2 on
a usage error.

Start an installation's config with `init-config`:

```
forsgren init-config --config forsgren.config.yml
```

When the file is missing it writes a starter and prints `created
forsgren.config.yml`. The starter is a comment that explains the file, names
`forsgren check-config`, the three deployment forms and the two label
forms, and shows a commented
example with made-up `acme` names (the default deployment, `workflow=` and
`release`), followed by `version: 1`, `view: standard`, `auto_update: true`,
`auto_update_level: patch`, `history_days: 365`,
`history_chunk_days: 100` and `projects: []`, so
`check-config` accepts it as it is: `projects: 0, repositories: 0`. When the file exists,
whatever it holds (even an invalid or an empty file), it is left byte for
byte and the command prints `kept forsgren.config.yml`; both exit 0. The file
is written whole or not at all, and a file that appears while the command
runs is never replaced. The directory must exist: `init-config` does not
create one, so a mistyped directory is an error. It exits 1 with
`init-config: <path>: <reason>` on a real error (the directory is missing or
not writable, or the path is a directory), and 2 on a usage error. The
metrics workflow runs it on every new install (see Running forsgren).

## Collecting deployments (`collect`)

```
FORSGREN_TOKEN=<token> forsgren collect --config forsgren.config.yml --data data/deployments.csv
```

`collect` reads, for every repository in the config, that repository's
deployments from GitHub's REST API by its `deployment` rule, and appends the
final ones to the history (see History), the commits of each new
successful one to `data/commits.csv` next to it, the repository's
failure issues to `data/failures.csv` next to it, and the events of all its
issues to `data/issues.csv` next to it and which of them carry the `bug` label to
`data/issue_bugs.csv` (see Issue events below). It prints one line per
repository, `acme/app: 3 new, 1 skipped (not final), 12 commits`: `new` is
what was appended, `skipped (not final)` is what is still running and is
stored by a later run, `commits` is the commits stored for the new
deployments. A deployment already in the history is skipped without a
count. When it stored failure issues the line goes on with
`, 2 failure issues`, the issues new or changed since the last run.

- **`environment=<name>`** (the default, `production`): the GitHub
  Deployments to that environment, and each one's statuses. A deployment is
  a `success` when any of its statuses was `success`: GitHub marks a
  successful deployment `inactive` once a newer one replaces it, so its
  latest status says nothing. It is a `failure` when no status was
  `success` and its newest status other than `inactive` (by time, then ID)
  is `failure` or `error`. Anything else (no status yet, `pending`,
  `queued`, `in_progress`, only `inactive`, or a retry: `pending`,
  `queued` or `in_progress` after a `failure`) is not final, so a retry
  that succeeds is stored as a `success`. The deployment's ID, `sha`,
  `task` and `created_at` are stored.
- **`workflow=<file>.yml`**: the runs of that workflow on the repository's
  default branch, from the repository itself (a fork's run on a branch of
  the same name does not count). The conclusion `success` is stored as
  `success`, `failure` as `failure`, and every other conclusion
  (`cancelled`, `skipped`, `timed_out`, `action_required`, `neutral`,
  `stale`, `startup_failure`) as `other`: it is final, it is not a
  deployment that reached users, and the history keeps that it happened
  (lines are never rewritten, so what is not stored when it is seen cannot
  be added later). A run that is not `completed` is not final. The run ID,
  `head_sha` and `run_started_at` (the start of the attempt whose
  conclusion is stored) are stored. A re-run keeps its run ID, so a run
  stored after a failed attempt keeps that `failure` when a later attempt
  succeeds.
- **`release`**: the published releases, as `success` at their
  `published_at`. Drafts are not published; prereleases are not shipped to
  everyone (a release candidate or a beta), so neither is a deployment. The
  commit is the tag's commit (an annotated tag resolved to its commit), one
  small request per release not stored yet; the tag is stored as the task.

**How far back.** A repository's history is read in chunks of
`history_chunk_days` (100 unless the config says otherwise), down to
`history_days` (365), see Configuration (forsgren#57).

- A repository with nothing in the history for its rule and no row in
  `data/reach.csv` is on its first run: it reads one chunk back from now, and
  its reach (the date down to which its history was read) is set to the start
  of that chunk.
- Every later run reads what is new, from 7 days before the newest
  deployment stored for it (so a deployment that was not final at the last
  run is still found, and never more than `history_days` back), plus one
  older chunk: from its reach back by one chunk, but not past `history_days`.
  Its reach then moves to the start of that chunk. Once the reach is at or
  past `history_days` back, no older chunk is read and the reach stays.
- **`data/reach.csv`** holds the reach, one row per repository, sorted by
  name (`# forsgren reach v1`, then `repository,reach`, the date as RFC 3339
  UTC). It is written next to `deployments.csv` whole, through a temporary
  file that is renamed over it, and only when a reach moved. It is needed
  because the oldest stored deployment cannot tell a quiet stretch from one
  that was not read yet. An installation that has none starts each repository
  with stored deployments at its oldest stored deployment: everything since
  was read by the runs so far.
- A deployment still not final 7 days before the newest stored one is not
  read again, so it is never stored.
- Every list is read newest first, 100 per page, and stops at the first page
  that reaches the start of its range; at most 10 pages per list (the newest
  1000). GitHub's list of deployments and releases has no date filter, so an
  older chunk pages again past everything newer; a workflow's runs are asked
  for the range of the chunk and skip it. When a read is cut at the page
  limit, stderr says so: `collect: acme/app: read the newest 10 page(s) only;
  older deployments were not read`, and the reach moves to the oldest date
  the read actually reached, so the next run continues from there. A chunk
  that lies behind more than 1000 newer deployments can never be reached: the
  run warns, and the reach stays.
- The failure issues are not chunked: a repository's first read goes from
  `history_days` back, and each later run reads from where the last one ended
  (see The failure issues below).
- Re-reading is safe: the history skips what it already holds, and a stored
  deployment's statuses or tag are not asked again.

**The commits of each deployment** (for lead time, forsgren#16). Each
successful deployment `collect` stores is compared with the previous
successful one of its stream, `compare/{previous commit}...{its commit}`,
and the commits after the previous one's commit up to its own are stored
in `data/commits.csv`, each with its author date and the deployment's
`created_at`.

- **A stream** is a repository's deployments by one rule with the same
  environment or workflow and the same `task`: a repository deploying
  `deploy-api` and `deploy-admin` to production measures each against its
  own previous deployment. A release's task is its tag, a new one with
  each release, so a repository's releases are one stream. Repository
  names are compared ignoring case.
- **The previous** is the newest success of the stream before the
  deployment (by `created_at`, then ID), stored by an earlier run or found
  in the same run: a run takes its new deployments oldest first.
- **The first success** of a stream has no known start and gets no
  commits. **A failure**, or another final state, is never a previous and
  gets no commits: its commits are in the next success's comparison.
- **Once.** Only the deployments a run stores are compared, so the daily
  run never asks about a stored one again, and a deployment skipped below
  is not tried again either: what makes it skip does not change by asking
  again.
- **Skipped, with a warning on stderr, the run going on:** a comparison
  GitHub cut (more commits than forsgren reads, or fewer than GitHub's
  `total_commits`): `collect: acme/app: deployment 1002: 1000 commits
  compared, list cut; lead time skips this deployment`, since a cut list
  keeps the oldest commits and would skew lead time; a previous commit that
  is not an ancestor of the new one (a force-push, or a rollback to an older
  commit) and a commit GitHub does not have, both naming the two SHAs
  (`...; lead time skips deployment 1002`). These are the history's shape,
  not the token's access. Any other error of a comparison (no access, a
  rate limit) fails the repository like any other call.
- **Skipped, not compared, with a warning:** a success that finished
  between two successes of its stream stored by earlier runs, say one still
  running at the last run while a newer one succeeded: `collect:
  acme/app: deployment 1002 finished after the newer deployment 1003 was
  stored; lead time skips it, so no commit counts twice`. The newer one was
  compared with the success before both, so its commits already hold this
  one's.
- **Backfilled deployments:** a success older than the oldest stored one of
  its stream (an older chunk) is compared with the success before it. The
  oldest stored success has no previous yet and waits; the run that reads
  an older success of the stream compares it. No commit is stored twice.
- **Not verified against live GitHub.** What `collect` assumes of a
  comparison comes from GitHub's REST reference and is pinned against
  made-up answers only: that `total_commits` counts every commit of the
  comparison (fewer read is taken as a cut list); that a SHA GitHub does
  not have answers 404 or 422 (both read as a missing commit, so that
  deployment is skipped, not the repository failed); and that the pages
  list the commits oldest first, so a cut list keeps the oldest. The first
  live runs are where to check them.

**The failure issues** (for change fail rate, forsgren#18). Every
repository's issues labelled `failure`, open or closed, that GitHub says
were updated since a time: `issues?labels=failure&state=all&since=`,
every page up to the page limit, pull requests left out (GitHub lists them
as issues, with a `pull_request` field).

- **Where a run starts reading.** `data/failures_read.csv`, next to the
  history, records per repository when its failure issues were last read:
  a version line `# forsgren failures read v1`, the column line
  `repository,read_at`, then one line per repository. A run asks for the
  issues updated since that time minus 1 day. A repository with no time yet
  is read for the first time, from `history_days` back. The time moves to
  the run's start only after the repository's issues were read and stored; a
  failed read leaves it, so the next run asks again from the old time. A
  `failures_read.csv` that is not in the format refuses the run, like
  `reach.csv`.

- Each issue's number, `created_at`, `closed_at` and the `failure-start:`
  line of its body are stored (see History). An issue already stored is
  stored again only when one of them changed: closed, or reopened.
- **The record block is read from the issue's body**, the lines
  `failure-start:`, `failed-build:` and `fixed-build:` alone on their
  line, as forsgren#6 rules. `failure-start` is read as ISO 8601 with an
  offset, to the minute (`2026-09-20T09:12+02:00`) or the second; a body
  without one, or with a time in another form, stores the issue with an
  empty `failure_start` and a warning: `collect: acme/app: failure issue
  #43 has no failure-start line forsgren can read in its body`, once, when
  the issue is first stored (not again when it is closed or reopened). A block written in a comment instead of the body is
  not read. The issue counts all the same: change fail rate needs only
  when it was opened.
- A list cut at the page limit is stored and named on stderr: `collect:
  acme/app: read the newest 10 page(s) of failure issues only; older ones
  were not read`.
- **Not verified against live GitHub.** That `since` filters by the update
  time, and that a pull request is any item with a `pull_request` field,
  come from GitHub's REST reference and are pinned against made-up answers
  only.

**Errors.** Each repository is tried, also after another failed; a failing
one is named on stderr (`collect: acme/app: ...`) and nothing of it is
stored, neither its deployments, nor their commits, nor its failure issues,
because a repository's records are appended in one go, after all of them
are read and compared: its commits first, then its failure issues, then its
deployments. A deployment is never stored
without its commits: when one of the two writes fails, the next run reads
and compares those deployments again, and the commits already stored are
skipped. The others are stored, and `collect` then exits 1
with `collect: 1 of 3 repositories failed`. A 401, 403 or 404 says `check
FORSGREN_TOKEN's access to acme/app`, except for a release's tag: a 404 or
422 there says `tag v1.2.0 not found` and asks whether it was deleted after
the release was published, since the release itself was just read with the
same token; and except for a comparison, where a 404 or 422 is a commit
GitHub does not have (see above); a rate limit says when it resets (UTC)
or how many seconds GitHub asks to wait; an answer that is not what GitHub
documents is refused by the repository's name. A history, a commits file
or a failures file that cannot be read (another version, a malformed line) is refused
before GitHub is asked anything. With no project configured `collect` does nothing, needs no
token and exits 0; with at least one repository and no `FORSGREN_TOKEN` it
exits 1 before anything is read or written. It exits 2 on a usage error.

**The token.** `collect` reads the token from the environment variable
`FORSGREN_TOKEN` only (never a flag) and sends it only as an
`Authorization: Bearer` header to `api.github.com`: never in a URL, never in
a message, and never to another host (a next-page link elsewhere is
refused). A fine-grained personal access token, read-only, for the measured
repositories, needs per rule:

| Rule | Repository permissions (read) | Calls |
|---|---|---|
| `environment=<name>` | Deployments, Contents, Metadata | list deployments, list deployment statuses, compare two commits |
| `workflow=<file>.yml` | Actions, Contents, Metadata | get the repository (its default branch), list a workflow's runs, compare two commits |
| `release` | Contents, Metadata | list releases, get the tag's commit, compare two commits |

Every rule also lists the repository's issues labelled `failure`, for
change fail rate, which needs Issues (read) as well. A token without it
fails every repository, deployments included, with `check FORSGREN_TOKEN's
access`: add Issues (read) to the token before updating to a forsgren that
reads failure issues.

Comparing two commits, for the commits of each deployment, needs Contents
with every rule. A token without it fails the repository from its second
successful deployment on, with `check FORSGREN_TOKEN's access`, when
GitHub answers 401 or 403; a 404 would read as a commit GitHub does not
have and skip each deployment with a warning instead (not verified against
live GitHub, see above). Metadata is
in every fine-grained token. A classic token needs `repo` for
private repositories (no scope for public ones).

### Issue events (forsgren#76)

Besides the failure issues, each run reads the issues of the repository,
whatever their labels (`Client.Issues`: `issues?state=all&since=`, 100 per
page, pull requests left out, up to the page limit), and appends their
events to `data/issues.csv` (see History). It asks since the same time as
the failure issues, the repository's entry in `failures_read.csv` minus one
day, and the read time moves only after the deployments, failure issues and
issue events of the repository were all stored (decision #101). A
`issues.csv` that is not in the format refuses the run before GitHub is
asked anything, like the other data files; if it cannot be written, the
repository fails and its deployments are not stored, so the next run reads
them again. The events are worked out from what GitHub says now, and
from the newest event stored for the issue, by time (at the same second,
created comes before closed, and closed before reopened; decision #100):

- **created**, at the issue's `created_at`, for every issue read;
- **closed**, at its `closed_at`, with its `state_reason`, when it is closed.
  A close after a reopen has a new `closed_at`, so it is a second `closed`
  event;
- **reopened**, when the issue is open and the last event stored for it is a
  close. GitHub gives no reopen time, so it is dated when collect sees it:
  the run's time, to the second. Once stored, it is not written again,
  because the last event is then the reopen, not a close.

An event already stored is skipped (see History), so reading the same issues
again writes nothing.

**The full read** (decision #109) gives the days and issues pages their history back to
the first issue, including the open issues nothing has touched for a long
time, which Open counts.
The first run for a repository with no line in `data/issues_full.csv`
(`repository,full_at`, the time the full read was done) reads every issue of
it, open or closed, without a time cut: `issues?state=all`, 100 per page, up
to 100 pages (10,000 issues), pull requests left out. Its events are
appended like any others, so an installation that already has events from
the daily reads gets only the missing ones. The repository is noted in
`issues_full.csv` only after its events were stored, and later runs skip the
full read. If the full read stopped at the 10,000 issues cap, stderr says so
(`the full read stopped at 100 page(s) of issues; the daily collection
continues, but older issues and so the historical total stay incomplete`),
what was read is kept, the repository is not noted, and the next run tries
again. Daily collection is not capped this way: it continues past the cap,
but for a repository with more than 10,000 issues the back history, and so
the historical Open and Total, stays incomplete. An `issues_full.csv` that is not in
the format refuses the run before GitHub is asked anything.

**The bug flags** (forsgren#126) are read in the same run, after the issue
events of the repository: `issues?labels=bug&state=all`, 100 per page, up to
100 pages (10,000 issues), pull requests left out, no `since`, so an
installation that upgrades gets the whole history of its bugs on the first
run, with no full re-read. Every issue listed is stored as `bug=true`, and
every issue stored as a bug that is no longer listed is stored again as
`bug=false`, so a removed label is seen on the next run. What is already
stored is skipped (see History, Bug flags). If the list stopped at the
10,000 issues cap, stderr says so (`the bug read stopped at 100 page(s) of
issues; the stored bug flags are kept`), what was read is stored and no flag is
removed, because an issue it did not reach may still carry the label; the run
goes on. A refused list (GitHub errors) fails the repository, like a refused
issue list, and so does an `issue_bugs.csv` that cannot be written; an
`issue_bugs.csv` that is not in the format refuses the repository before
GitHub is asked for the bug issues. The label is the one at the latest
collection, not the label at the time of each event (Yves's ruling): there is
no label history, which would take one call per issue.

**Known limits of the issue events** (forsgren#76):

- Deleted or transferred issues drift: GitHub no longer lists them, so their
  events stay in the file but nothing marks them as gone.
- A close and a reopen that both happen between two collect runs are never
  seen: the issue looks as if nothing happened (or, when it was closed
  before, closed again at a new time).
- A reopen is dated when collect sees it, up to a day late (the
  runs are daily), not when it happened on GitHub; its day on the issues
  page can be the next one, and an Open from before a reopen was seen is an
  estimate.
- The full read stops at 10,000 issues: for a repository above that, the
  daily collection continues, but the back history and the historical Open and Total
  are incomplete (the warning above).
- The Open bugs of a repository above 10,000 bug-labelled issues is incomplete
  too: a warning, but its cell is not marked as incomplete (a known limit,
  forsgren#140).

## Running forsgren

forsgren renders a static page whose footer says "Forsgren 0.8.6", the version of
the forsgren that rendered it, and shows each project's deployment frequency,
lead time for changes, failed deployment recovery time and change fail
rate (and the deployment rework rate); every run writes the page in each view too, at
`/standard/`, `/numbers/` and `/scoring/` (see The page). That version has one source,
the `version` variable in `cmd/forsgren/main.go`; a release build can set
it with `-ldflags "-X main.version=<version>"`. `forsgren collect` reads
GitHub into the history file (see Collecting deployments); the daily run
calls it, commits the history to the data repository and renders the page
with each project's deployment frequency, lead time for changes, failed
deployment recovery time and change fail rate from it (see Deployment
frequency, Lead time for changes, Failed deployment recovery time and Change
fail rate).

The first release is `v0.0.1`. Install a release with
`go install github.com/yveshanoulle/forsgren/cmd/forsgren@v0.0.1`; an
installation pins that version. From a checkout of this repository:

```
./Scripts/build_site.sh            # builds .build/bin/forsgren, renders .build/site
.build/bin/forsgren render --out <dir>
```

`forsgren render --out <dir> [--config <path>] [--data <path>] [--latest <version>] [--waiting-pr <number>] [--needs-check <status>]` writes the site (every page
plus `styles.css`) into `<dir>`, creating it when needed, and exits 0; 1 when
the render failed (or the `--config` file is missing or invalid, with
check-config's refusal), 2 on a usage error. `--latest` is the newest forsgren
release, as `forsgren latest-release` prints it: render itself never calls
GitHub, so it stays testable offline, and a value that is missing, equal, older
or not a version adds nothing to the footer. `forsgren latest-release` reads
forsgren's own public repository's latest release (with `GITHUB_TOKEN` when the
environment has one, without otherwise) and prints its version without the
`v`; when the lookup fails it prints nothing, says why on stderr and exits 0,
since a page without news of a release is not an error. `--waiting-pr <number>`
(1 or more, anything below is a usage error; leaving it out means none)
is Dependabot's open pull request for it, as `forsgren waiting-pull-request
--version <x.y.z> [--status <path>]` prints it (the open pull requests of
`GITHUB_REPOSITORY`, read with `GITHUB_TOKEN`; with `--status` it also writes
how the lookup went, `ok`, `no-access` for the 403 of a token without
`pull-requests: read`, `rate-limited` when GitHub's rate limit refused it (a
403 or 429 with no request left, never taken for a missing permission), or
`failed`, and its exit status is 0 either way); the
footer then names the pull request instead of "is available".
`--needs-check <ok|no-access|rate-limited|failed>` is how `forsgren
check-needs` went (see The setup issue): anything but `ok` adds "needs more
configuration: see the job summary of this run" to the footer, and leaving it
out or `ok` adds nothing. `forsgren
run-summary --latest <version> --waiting-pr <number> --pr-check
<ok|no-access|rate-limited|failed|skipped> [--needs-check
<ok|no-access|rate-limited|failed>] --repository <owner/name>` prints the run's job
summary as markdown (the version that built the page, the latest release or
"unknown", and one of "up to date", "0.0.10 is available; no Dependabot pull
request yet", "0.0.10 is waiting in pull request [#7](link)", "pull-request
check skipped: grant pull-requests: read in your caller to enable it", "the
pull-request check hit GitHub's rate limit, the next run tries again" and "the
pull-request check failed", and a Setup line, see The setup issue); the link is fine there, because a run page is
private to the repository, unlike the public page. A flag it cannot use is a
usage error that prints nothing. With `--config`, a config that
lists no projects makes the page show, in place of the table and besides
"Forsgren 0.8.6" in its footer, a how-to for filling `forsgren.config.yml`;
without `--config` (the build above has no installation config) or with
projects, the page is the placeholder. With `--data` as well (it needs `--config`), the
page shows each project's deployment frequency from that history, counted
back from the moment of the render, which the page names in its footer, "Calculated at 2026-10-03 12:00 UTC" (UTC, to the minute; forsgren#28: the
render time, not the time `collect` finished; forsgren#41: shown on every
run, so two renders differ by their time, and `SOURCE_DATE_EPOCH`, Unix
seconds as in reproducible builds, 0 or more (a negative or non-numeric value
fails the render), pins it, which `Scripts/build_site.sh`'s
fixture uses to compare a build with the golden files); a missing history file (a new install
before its first collect) is an empty history, and a history with another
format version or a malformed line fails the render with the history's
message (exit 1).

**Daily, from an installation's data repository.** An installation does not
build forsgren: its data repository calls forsgren's reusable workflow,
`.github/workflows/metrics.yml`, once a day. That workflow installs
forsgren from the very commit it is called at with `go install`, checks the
data repository's `forsgren.config.yml` with `forsgren check-config` (writing
a starter first when the file is missing), collects the configured
repositories' deployments into `data/deployments.csv` with `forsgren
collect` and commits that history, renders the page and publishes it to the
data repository's GitHub Pages, on a GitHub-hosted runner, with no server
and no local Go. The calling workflow, in the data repository:

```yaml
name: Metrics
on:
  schedule:
    - cron: "17 5 * * *"   # once a day, 05:17 UTC
  workflow_dispatch:
jobs:
  metrics:
    permissions:
      contents: write
      pages: write
      id-token: write
      pull-requests: read   # optional, see below
      issues: write         # lets forsgren open its setup issue, see below
    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@<commit> # vX.Y.Z
    secrets:
      FORSGREN_TOKEN: ${{ secrets.FORSGREN_TOKEN }}
```

- **The `uses:` line is the only version.** Pin it by the full commit of
  a release, its tag in the comment. The workflow takes no input naming a
  version: it installs forsgren from its own commit and repository, which
  GitHub gives a called workflow as `job.workflow_sha` and
  `job.workflow_repository` (the `github` context would name the
  caller's). It refuses anything but a 40-digit commit and one
  `owner/name` before it installs anything. Dependabot, configured by the
  template, proposes the new `uses:` line of each release as a pull request
  (see Configuration, #14). A fork calling its own copy installs the fork,
  never upstream.
- **`v0.0.1` predates this.** Its `metrics.yml` still requires
  `with: forsgren-version: v0.0.1` under the `uses:` line; the one-line
  form starts with the next release, which has no such input: drop the
  `with:` block when moving to it.
- **A new install gets a starter configuration.** After the checkout the
  workflow runs `forsgren init-config --config forsgren.config.yml`. When
  the file is missing it is written (`version: 1`, `view: standard`,
  `auto_update: true`, `auto_update_level: patch`, `projects: []`, a commented example) and that one file, nothing else, is committed to the
  branch the run is on (`GITHUB_REF`; a scheduled run is always on the
  default branch) as `github-actions[bot]` with the message
  "forsgren: add a starter forsgren.config.yml"; the run goes on, the check
  passes on the starter, and the page shows the how-to for filling
  it. An existing file is never rewritten and
  nothing is committed, and a run that finds the file never looks at
  branches. **Branch protection:** the commit is a direct push, so the
  branch it lands on must accept a push from `github-actions[bot]`; if the
  default branch is protected against that (required pull requests or
  reviews, or required status checks with no bypass for the bot), the
  starter push is refused and the run fails once, on the first run of a new
  install. Then commit a `forsgren.config.yml` yourself (`forsgren
  init-config --config forsgren.config.yml` writes the starter) or allow the
  bot to bypass the rule. A run started by hand on another branch with no
  config puts the starter on that branch; a run on a tag fails by name,
  there is no branch to commit to. The push sends the job's token as an HTTP header through git's
  environment for that one command: not in any argument, not in a file, not
  in the log, and the checkout still keeps no credential.
- **The daily run checks the configuration first.** The workflow checks out
  the data repository (the commit that triggered the run, without leaving
  its token in the checkout) and runs `forsgren check-config --config
  forsgren.config.yml` on the file at the repository root, before it renders
  anything. An invalid file (a missing one was just written) fails the job with check-config's
  message in the log and in the run's summary, after a cross mark, and
  nothing is published from it. The message can quote the file, so the log
  shows it with workflow commands stopped: a line of it that starts with
  `::` is printed, never run.
- **The token: a `FORSGREN_TOKEN` secret.** `forsgren collect` reads the
  measured repositories with a read-only token of the installation's own
  (the job's token reaches only the data repository). Make one with the
  permissions its rules need (see Collecting deployments, The token: per
  rule `environment=` Deployments, `workflow=` Actions, and for every rule
  Contents and Metadata), store it as the data repository's Actions secret
  `FORSGREN_TOKEN`, and pass it by name as above. By name, not
  `secrets: inherit`: the called workflow then receives this one secret and
  none of the repository's others. The workflow declares it
  `required: false`: a new install's first run, with the starter's zero
  projects, needs no token and runs before one is made; once
  `forsgren.config.yml` lists a repository, a missing token fails the run
  with collect's message naming `FORSGREN_TOKEN`. Inside the workflow only
  the collect step gets it, in its environment.
- **The daily run collects and commits the history.** After the check,
  `forsgren collect --config forsgren.config.yml --data
  data/deployments.csv` appends the new final deployments, and their
  commits to `data/commits.csv` (see Collecting deployments). When `data/`
  changed, it and nothing else is committed to
  the branch the run is on as `github-actions[bot]`, "forsgren: record
  deployments", and pushed the way the starter is; a run with nothing new
  commits nothing, and a run on a tag that has something new fails by
  name. **A failing repository** does not stop the run: what the others
  stored is committed and the page is published, and then the job's last
  step fails it, so the run shows red with collect's message in the step
  "Collect deployments". That message, and the rest of collect's output,
  is shown with workflow commands stopped, as check-config's is.
  **One run at a time:** the job's concurrency
  group is the data repository's, so the daily run and one started by hand
  queue rather than race on the push. If the branch still moved under a run
  (someone pushed meanwhile), its push is refused and the run fails with
  "… moved since this run checked it out"; nothing is rebased or forced,
  and the next run collects the same deployments again. The branch
  protection note on the starter holds for this commit too.
- **The three permissions are the caller's to grant.** A called workflow
  can only keep or narrow what its caller's job grants: `pages: write` and
  `id-token: write` let `actions/deploy-pages` publish, `contents: write`
  lets the starter step and the data step each push their one commit.
  Without them the deploy step or a push fails. **Moving to the release
  that adds the starter and collect, change `contents: read` to
  `contents: write` and add the `secrets:` block** in the calling workflow
  (and in the template's copy of it).
- **`pull-requests: read` is optional, and the caller's to grant too**
  (forsgren#40). With it, when a newer forsgren release exists and
  Dependabot has an open pull request in your repository that bumps the
  `uses:` pin to exactly that release, the page footer says "Forsgren 0.8.6
  · 0.3.9 is waiting in pull request #7 (merge it to update)", with the
  number only. Without it the footer still says "0.3.9 is available": the
  lookup treats the refusal (a 403) as unknown, never as an error, and the
  run goes on. The workflow itself declares no permissions block, so it
  takes what your caller grants; it does not ask for this one, because a
  called workflow that asks for more than its caller grants stops the run
  before any step, which would break every install that has not added the
  line. Add it to the calling workflow (and to the template's copy) with the
  new release. Every run's job summary (its run page, private to the
  repository) says where the update stands, and when the token lacks the
  permission it says "pull-request check skipped: grant pull-requests: read
  in your caller to enable it".
  **The pull request is found by its head branch, a temporary heuristic**
  ([#42](https://github.com/yveshanoulle/forsgren/issues/42)): its author
  is `dependabot[bot]` and its branch starts with
  `dependabot/github_actions/yveshanoulle/forsgren/` and ends with
  `/metrics.yml-` plus the version, which is Dependabot's naming for a
  dependabot.yml with `directory: /`, no `groups:` and the default branch
  separator, as the template has it. A grouped update, another separator or
  another directory names the branch differently, and the footer then keeps
  saying "is available".
- **`issues: write` lets forsgren open its setup issue** (forsgren#73). When
  the running version needs more configuration, `forsgren check-needs` writes
  one issue in the data repository with the job's token. Without the
  permission the run does not fail: the job summary and the page footer say
  what is needed instead (see The setup issue). The workflow declares no
  permissions block, so it takes what your caller grants.
- **GitHub Pages must build from GitHub Actions** (the data repository's
  Settings → Pages → Source). The run deploys to the repository's
  `github-pages` environment.
- The Go the workflow builds with is the one of forsgren's `go.mod`
  toolchain line for that release; the caller sets up nothing.

## The setup issue (`check-needs`)

Each forsgren release declares what an installation needs: a permission, a
secret, a file or a config key. The declarations are `internal/needs/needs.yml`,
built into the binary, each from the release that introduced it on, so an
entry applies to that release and every later one. Every metrics run checks the
needs of the running version, so this is configuration compliance, not only a
step of moving to a release: a need that is fixed stays fixed, and one that is
removed again later is found again. Its command line, which `metrics.yml` runs
in the step "Check what this forsgren version needs":

```
forsgren check-needs --config <path> --repository <owner/name> [--status <path>]
```

`--config` is the installation's `forsgren.config.yml` (the config keys a need
asks for are its top-level keys), `--repository` is the installation's own
repository, where the issue lives, and `--status` writes how the issue's write
went (`ok`, `no-access`, `rate-limited` or `failed`). The job's token is
`GITHUB_TOKEN`. It prints the steps of each missing need and exits 0 once its
flags are valid, whatever the check or the write did; 2 is a usage error. The
workflow passes the status on as `render --needs-check` and
`run-summary --needs-check`.

- **One setup issue per installation, not per version.** It carries the label
  `forsgren-setup`, but its identity is a hidden marker, an HTML comment on the
  first line of its body; the label only narrows the lookup. An issue with
  the label and no marker is never touched, and if you remove the label from
  the managed issue, the next run opens a new one. Its title is "forsgren
  0.8.6 needs more configuration" (the running version) and its body lists the
  steps of each missing need; title and body are presentation, and a run
  rewrites them.
- **What a run does with it.** Something missing and no issue: it opens one.
  Missing and the issue open: it updates it. Missing and the issue closed:
  it reopens and updates it, since the same issue is the installation's. Nothing
  missing and the issue open: it closes it with the comment "All items are in
  place as of forsgren <version>.". Nothing missing and no issue, or a closed
  one: nothing.
- **Without `issues: write`** the write is refused, and the run does not fail:
  the job summary of the run says "the setup issue could not be written" and
  lists what this version needs, and the page footer says "needs more
  configuration: see the job summary of this run". A rate limit or any other
  failure does the same, with its own words. The summary and the footer speak
  only when something is really missing.
- **Nothing missing is `ok`**, even if closing the old issue failed: the failed
  close goes to the job log only.

**Known limits.** A check that cannot see something reports it as missing, so
a false alarm is possible but never a silent pass.

- **Permissions** are read from the installation's
  `.github/workflows/forsgren.yml` (a renamed caller file reads as missing).
  forsgren requires permissions to be declared explicitly on the forsgren job in
  that file. `write-all` and `read-all` are intentionally unsupported, because
  forsgren follows least-privilege security practice. Workflow-level
  (top-of-file) `permissions:` are not supported by the check, even though the
  job inherits them, and with no `permissions:` at all the repository's default
  token permissions cannot be seen, so an explicit declaration is required. A
  successful issue write does not count as proof: it shows the capability, not
  the supported configuration.
- **A secret** is only seen when the workflow passes it in, so only secrets
  that `metrics.yml` passes to forsgren can be declared.
- **A file** is checked in the run's checkout, so `check-needs` runs at the
  checkout root; the `metrics.yml` step pins it.

## Auto-update (`check-update`)

An installation can let forsgren's own updates merge themselves
([#58](https://github.com/yveshanoulle/forsgren/issues/58)). It is off until
the config switches it on, and a new install's starter does (see
Configuration). The chain, for each forsgren release:

1. Dependabot opens one grouped pull request that moves the pins of both
   caller files, `.github/workflows/forsgren.yml` (which calls `metrics.yml`)
   and `.github/workflows/forsgren-update.yml` (which calls `auto_update.yml`),
   to the new release.
2. On that pull request the caller `forsgren-update.yml` runs forsgren's
   reusable `auto_update.yml`, from the new pin the pull request carries. The
   workflow installs forsgren from its own commit, as `metrics.yml` does, and
   checks out the caller's repository at the pull request's base commit, so a
   pull request never switches auto-update on for itself.
3. `forsgren check-update` decides (below).
4. When it says merge, the workflow squash-merges the pull request, deletes
   its branch and starts `forsgren.yml` on the default branch, so the new
   release publishes the page now and not at the next daily run.
5. When it says install (exit 3, below), the workflow installs the newest
   release within the level itself and starts `forsgren.yml`; the pull request
   stays open ([#62](https://github.com/yveshanoulle/forsgren/issues/62)).

**The two keys** of `forsgren.config.yml` (see Configuration):

- **`auto_update`** is `true` or `false`, and only those literals (a quoted
  value, `yes` or a number is refused by `check-config`). Absent, or without
  a value, it is off, so an existing config keeps its behaviour until it opts
  in.
- **`auto_update_level`** is `patch`, `minor` or `major`: the largest step
  an update may take and still merge itself. It has no default: with
  `auto_update: true` and no level, the config is refused (`check-config`
  names the three values), and any other value is refused too. At `patch`,
  v0.2.0 to v0.2.1 merges and v0.3.0 does not; at `minor`, v0.3.0 merges (and
  every patch) and v1.0.0 does not; at `major`, v1.0.0 merges as well. A
  level only limits what merges: a pull request beyond it is left for you,
  and a release within the level is installed meanwhile (see below).

**What the guard checks.** The pull request merges only when every one of
these holds, and otherwise it is left for a human with one reason line:

- the pull request's author is `dependabot[bot]`;
- the config at the pull request's base commit has `auto_update: true`;
- the diff changes nothing but pin lines: every changed file is one of the
  two callers, each changes one `uses: yveshanoulle/forsgren/.github/workflows/...@<sha> # vX.Y.Z`
  line to another, and a caller pins the workflow it calls (`metrics.yml` in
  `forsgren.yml`, `auto_update.yml` in `forsgren-update.yml`);
- the pins move from the same version to the same version and commit in every
  file, and when the repository has both caller files at the base commit, the
  pull request moves both (a pull request that moves only one is left for you,
  [#61](https://github.com/yveshanoulle/forsgren/issues/61));
- the new version is a release version (`vX.Y.Z`), an upgrade of the old one,
  and within `auto_update_level`;
- forsgren has a published release for the new version, not a draft and not a
  prerelease, and its tag points at exactly the pinned commit.

**`check-update`** is the command the workflow runs:

```
forsgren check-update --config forsgren.config.yml --repo <owner/name> --pull <number>
```

`--config` is the installation's config file (the caller files are looked
up next to it, which in the workflow is the checkout of the base commit),
`--repo` the data repository and `--pull` Dependabot's pull request in it
(1 or more). It reads the pull request, its files and forsgren's release
with `GITHUB_TOKEN`, which needs `pull-requests: read`, and prints one line,
or two for exit 3:

- exit 0: `merge <old> to <new>`, for example `merge v0.2.0 to v0.2.1`;
- exit 1: `left for a human: <reason>`, for example `left for a human:
  v0.2.1 to v0.3.0 is a minor update; auto_update_level is patch`. With
  `auto_update` off it prints `left for a human: auto_update is off` and asks
  GitHub for nothing;
- exit 3: `install <old> to <new> at <sha>`, then the exit 1 line, for
  example `install v0.2.1 to v0.2.2 at 0123456789abcdef0123456789abcdef01234567`
  and `left for a human: v0.2.1 to v0.3.0 is a minor update;
  auto_update_level is patch`. It is given only when every check passed but
  the level (the pull request goes further than `auto_update_level` allows)
  and forsgren has a release that is newer than the installed version, within
  the level, published (not a draft, not a prerelease) and a release version;
  `<new>` is the newest such release and `<sha>` the commit its tag points at.
  With no such release it is exit 1, as before; any other reason to leave the
  pull request never looks at the releases;
- exit 2: a usage, config or network error, with the message on stderr and
  nothing on stdout (a flag missing or invalid, a config that is invalid, an
  answer of GitHub that is an error, or a pull request with more files than
  forsgren reads).

**A release within the level (`install-update`).** Dependabot proposes only
the newest release, so with `auto_update_level: patch` and v0.2.1 installed,
v0.3.0 is left for you while the patch release v0.2.2 would have been safe.
On exit 3 the workflow installs v0.2.2 itself, with `forsgren install-update`:

```
forsgren install-update --repo <owner/name> --branch <branch> --version <vX.Y.Z> --sha <40-hex>
```

`--repo` is the data repository, `--branch` its default branch, `--version`
the release to install and `--sha` the commit its tag points at (both taken
from check-update's first line, which the workflow checks against a release
version and 40 lower-case hex digits first). It reads each caller file as it
is at the head of the branch, through the API, because the branch moves daily
with data commits and the pull request's base commit may be stale; moves the
pin of each caller file that exists there to the release; and writes all of
them in one commit, `forsgren: install <version> within auto_update_level
(forsgren#62)`, that follows the head it read the files at. The branch is
moved without force, so a branch that moved meanwhile, or is protected
against the job's token, fails the command with the branch unchanged. It
reads `GITHUB_TOKEN`, which needs `contents: write`, and prints `installed
<version> on <branch> as <commit>`:

- exit 0: installed;
- exit 2: a usage error (a flag missing or invalid, named on stderr), an
  answer of GitHub that is an error, a caller file without exactly one pin
  line of its workflow, or no caller file at the head of the branch. A caller
  file that is not there is skipped.

Then the workflow starts `forsgren.yml`, as it does after a merge (a commit
made with the job's token triggers no other workflow), and the bigger pull
request stays open: Dependabot refreshes it, and merging it is yours. The
job summary holds both lines of check-update's output. A failing
`install-update` fails the run and starts nothing.

**What you see.** When the pull request is left for you, the workflow puts
the reason in the run's job summary, the run stays green and nothing is
merged: review the pull request and merge it yourself if it is fine. When
check-update fails (exit 2) or the merge fails, the run fails, and a failed
merge starts nothing. When a release within the level is installed instead,
the summary says so and why the pull request stays open, and the run is green.

**The caller grants three permissions**, all `write`, because a called
workflow can only keep or narrow what its caller's job grants:
`contents: write` to merge or to write the install commit,
`pull-requests: write` to merge the pull request and `actions: write` to start
`forsgren.yml`. The last is needed because a
merge made with the job's token triggers no other workflow, so without the
explicit start the merged update would wait for the next daily run. The
workflow declares no permissions block of its own.

**The template's Dependabot setup.** The template's `.github/dependabot.yml`
groups the pins of both caller files into one pull request, checks every day
at 04:00 UTC, weekends included (`interval: cron`, `cronjob: "0 4 * * *"`;
`interval: daily` runs Monday to Friday only), and waits 3 days after a
release before it proposes it (a cooldown).

**To switch auto-update off**, set `auto_update: false` in
`forsgren.config.yml` (or remove the key). Dependabot still opens its pull
request, `forsgren-update.yml` runs and leaves it for you with `auto_update is
off`, and merging it is the update, as before (see Configuration).

## Working on forsgren

Moved to [docs/development.md](docs/development.md).

## Quality gates

Moved to [docs/quality-gates.md](docs/quality-gates.md).

## CI

Moved to [docs/ci.md](docs/ci.md).

## Privacy

The public page shows numbers and dates only. It carries no issue titles and
no links into private repositories, makes no third-party requests (no web
fonts, analytics or CDNs: everything it loads is served with it), sets no
cookies, uses no browser storage and tracks no one. Two POST gates check the
generated page on every run, privacy posture for the requests, cookies and
tracking, and repository links for the links (see [Quality gates](docs/quality-gates.md)). No gate
checks for issue titles yet: that rests on the renderer, which is given
the project names of the owner's own config, numbers, durations and dates
only: no repository name, commit SHA or message, tag, environment,
workflow or task reaches the page, which `cmd/forsgren/render_data_test.go`
and, for the commits of lead time, `cmd/forsgren/render_leadtime_test.go`
pin. A finding is fixed in the template, never by
loosening the gate.

## Installing and updating

**To install forsgren with an AI coding agent,** point the agent at
[agent-installer.md](agent-installer.md): it asks what only you can decide
and creates your data repository from the template step by step
(forsgren#142).

**An installation's page names a newer release** (forsgren#40). The page
footer says "0.0.10 is available" when forsgren has a newer release than the
one that built the page, and, when your caller grants `pull-requests: read`
(see Running forsgren), "0.0.10 is waiting in pull request #N (merge it to
update)" when Dependabot's pull request for it is open in your repository.
Updating is merging that pull request; the template's calling workflow
carries the permission line.

Run `./sfl.sh pre` (or `./FBP.sh`) and the tools install themselves.
`Scripts/required_tools.txt` lists them, and `Scripts/install_tools.sh` installs
each missing one with Homebrew and upgrades the ones already there. Homebrew
must already be installed. Only the tools the quality gates use are listed.

The tools, the Go and npm pins and the tooling's own fixtures are described in [docs/development.md](docs/development.md).

## Status

The bootstrap is done (forsgren#1, 2026-10-02): the build, the gates, CI
and these docs. Since then `collect` reads GitHub into the history file:
the deployments of the configured projects and the commits they shipped.
The page shows each project's deployment frequency, lead time for
changes, failed deployment recovery time, change fail rate and deployment
rework rate. Installations start from the forsgren-template
repository and take each new release as a Dependabot pull request. forsgren
is open source, under EUPL-1.2 (see Licence).

## Licence

forsgren is licensed under the European Union Public Licence v. 1.2
(EUPL-1.2): see [LICENSE](LICENSE). Contributions are accepted under the
same licence, with a Developer Certificate of Origin sign-off on every
commit and no CLA: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Report a vulnerability privately, never in a public issue: see
[SECURITY.md](SECURITY.md).

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
