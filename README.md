# forsgren

Measure the four DORA metrics for a set of GitHub repositories, from the data
GitHub already has, and publish them as a small static status page.

Named after Dr. Nicole Forsgren, whose research with DORA (and the book
*Accelerate*, with Jez Humble and Gene Kim) defined these four metrics.

## The four metrics

| Metric | Question it answers |
|---|---|
| Deployment frequency | How often do we ship to users? |
| Change lead time | How long from a commit to that commit reaching users? |
| Change failure rate | What share of deployments causes a failure users hit? |
| Failed deployment recovery time | When a deployment fails and needs immediate intervention, how long until a successful one recovers it? |

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
from GitHub, `data/commits.csv`, their commits, and `data/failures.csv`,
the failure issues) in a separate private
data repository, made from a template, and
passes them to forsgren as paths. Test fixtures are made up (`acme/app`) and live only
under `testdata/`.

The data guard (`Scripts/check_data_guard.sh`, a PRE gate) keeps it that way.
Like the secret scan it is secret-class: a finding blocks the commit itself,
not only the push, so the leak never enters history.
Over the files git tracks, it fails when:

- a file that looks like installation config or data sits outside
  `testdata/`: anything under a top-level `data/`, `deployments.csv`,
  `commits.csv`, `failures.csv`, `history.csv`, `*.history.csv`, `forsgren.config.*`,
  `forsgren-config.*`, `config.yml`/`.yaml`/`.json` at any depth, or a
  `*.jsonl` events file;
- a fixture under `testdata/` or a test file (`*_test.go`, `test_*.sh`)
  mentions one of the owner's real repository, organisation or domain names.

Those names are not written in this repository, since listing them here would
publish them. Put them in a file outside it, one per line (`#` starts a
comment), and point `FORSGREN_PRIVATE_NAMES_FILE` at that file. When the
variable is unset or the file is missing, the name scan is skipped with a ⚠️
line and the rest of the gate still runs. The failure line names the file and
line, never the name it matched.

Untracked files are not checked, so `git add` (or `git add -N`) a new file
before running the gates.

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

## Deployment frequency

The first DORA number on the page (forsgren#12, step 7, package
`internal/metrics`). Each configured project gets a section, in the config's
order, with:

- the successful deployments of the last 7 days;
- the date of its latest successful deployment;
- its DORA band, always shown with the count and the period it comes from:
  "Between once per day and once per week — 12 production deployments in
  the last 30 days" (one is "1 production deployment"); a band decided on
  the last 180 days shows that count: "Between once per month and once
  every six months — 3 production deployments in the last 180 days".

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
| 720 and more in 30 days (once an hour or more often) | On demand (multiple deploys per day) |
| 30 to 719 in 30 days | Between once per hour and once per day |
| 5 to 29 in 30 days (once a week is 30/7, about 4.3) | Between once per day and once per week |
| 1 to 4 in 30 days | Between once per week and once per month |
| none in 30 days, 1 and more in 180 days | Between once per month and once every six months |
| none in 180 days | Less than once per six months |

The band describes throughput over the period, not regularity; the count
makes a burst visible (Yves's ruling on forsgren#12), so the band is never
shown without it, and neither the 30-day nor the 180-day count has a row of
its own.

A project with no successful deployment in its history says "No deployments
recorded yet".

## Lead time for changes

The second DORA number on the page (forsgren#16, steps 4 and 5, package
`internal/metrics`): how long a change takes from its commit to running in
production. Each project's section shows it next to its deployment
frequency, as a DORA band with the median, the count and the period:
"Less than one hour — median 17 minutes over 37 commits in the last 30
days" (one is "1 commit"). A project that has deployments but no commit
deployed in the last 30 days says "No lead time yet".

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
immediate intervention". Each project's section shows it after its lead
time, as a DORA band with the median, the count and the period: "Less than
one day — median 3 hours over 2 recoveries in the last 30 days" (one is "1
recovery"), followed by "; 1 failure not recovered yet" when a stream's
latest deployments failed. With none recovered in the window but one not
recovered yet it says "No recovery in the last 30 days; 1 failure not
recovered yet"; with neither, "No failed deployments in the last 30 days".

**What counts.** Rulings on forsgren#17, taken while Yves was away (each
can be reverted there):

- **Deployments only.** A failure is a line of `data/deployments.csv`
  whose state is `failure`. The web-infra and TestFlight recorders record
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
  ("1 failure not recovered yet", at most one per stream) whatever its
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

A project with no successful deployment in its history says "No
deployments recorded yet", and shows no recovery time either.

## Change fail rate

The fourth DORA number on the page (forsgren#18, package `internal/metrics`):
DORA's share of deployments that cause a failure in production requiring
remediation. Each project's section shows it after its recovery time, as a
DORA band with the rate, the deployments and both kinds of failed change:
"20% — 15% of 13 deployments failed (1 failed deployment, 2 failure issues)
in the last 30 days". With no deployment in the window it says "No
deployments in the last 30 days", followed by "; 1 failure issue" when an
issue was opened in it.

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

A project with no successful deployment in its history says "No
deployments recorded yet", and shows no change fail rate either.

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
project in its own section (#6).

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
`release`), followed by `version: 1` and `projects: []`, so `check-config`
accepts it as it is: `projects: 0, repositories: 0`. When the file exists,
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
successful one to `data/commits.csv` next to it, and the repository's
failure issues to `data/failures.csv` next to it. It prints one line per
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

**How far back.** A repository with nothing in the history for its rule is
read 90 days back. After that, a run reads from 7 days before the newest
deployment stored for it, so a deployment that was not final at the last
run is still found, and never more than 90 days back: the daily run reads
little more than what is new. A deployment still not final 7 days before
the newest stored one is not read again, so it is never stored. Every list
is read newest first, 100 per page,
and stops at the first page that reaches the start; at most 10 pages per
list (the newest 1000), and when that cut a list stderr says so:
`collect: acme/app: read the newest 10 page(s) only; older deployments were
not read`. Re-reading is safe: the history skips what it already holds, and
a stored deployment's statuses or tag are not asked again.

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
- **Skipped, not compared, with a warning:** a success that finished after
  a newer success of its stream was stored, say one still running at the
  last run while a newer one succeeded: `collect: acme/app: deployment
  1002 finished after the newer deployment 1003 was stored; lead time skips
  it, so no commit counts twice`. The newer one was compared with the
  success before both, so its commits already hold this one's.
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
were updated in the last 90 days: `issues?labels=failure&state=all&since=`,
every page up to the page limit, pull requests left out (GitHub lists them
as issues, with a `pull_request` field).

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

## Running forsgren

forsgren renders a static page which says "Forsgren 0.0.6", the version of
the forsgren that rendered it, and shows each project's deployment frequency,
lead time for changes, failed deployment recovery time and change fail
rate. That version has one source,
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

`forsgren render --out <dir> [--config <path>] [--data <path>]` writes the site (every page
plus `styles.css`) into `<dir>`, creating it when needed, and exits 0; 1 when
the render failed (or the `--config` file is missing or invalid, with
check-config's refusal), 2 on a usage error. With `--config`, a config that
lists no projects makes the page say, besides "Forsgren 0.0.6", "No projects
configured yet: add them to forsgren.config.yml."; without `--config` (the
build above has no installation config) or with projects, the page is the
placeholder, unchanged. With `--data` as well (it needs `--config`), the
page shows each project's deployment frequency from that history, counted
back from the moment of the render, which the page names in its first line,
"Calculated 2026-10-03 12:00 UTC" (UTC, to the minute; forsgren#28: the
render time, not the time `collect` finished, and shown only with `--data`
and at least one project, so a page without numbers stays byte-identical
between renders); a missing history file (a new install
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
  the file is missing it is written (`version: 1`, `projects: []`, a
  commented example) and that one file, nothing else, is committed to the
  branch the run is on (`GITHUB_REF`; a scheduled run is always on the
  default branch) as `github-actions[bot]` with the message
  "forsgren: add a starter forsgren.config.yml"; the run goes on, the check
  passes on the starter, and the page says "No projects configured yet: add
  them to forsgren.config.yml." An existing file is never rewritten and
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
- **GitHub Pages must build from GitHub Actions** (the data repository's
  Settings → Pages → Source). The run deploys to the repository's
  `github-pages` environment.
- The Go the workflow builds with is the one of forsgren's `go.mod`
  toolchain line for that release; the caller sets up nothing.

## Working on forsgren

**`./FBP.sh "<message>"`** (FBP = FullBuildAndPush) is the one command for a
change: 

`gofmt -w` over the Go files, `./sfl.sh pre`, `Scripts/build_site.sh`,
`./sfl.sh post`, then `git add -A`, a commit, and a push only when every
phase is green. 
An ordinary red still commits locally, with the subject
`*** RED ****` and the message in the body, so work is never lost, and
skips the push. 
A secret-class red (the secret scan or the data guard)
commits nothing at all. `./FBP.sh --no-commit` runs the gates and the build
only. 
Every commit it makes, green or `*** RED ****`, is signed off
(`git commit --signoff`): git adds a `Signed-off-by:` trailer for the
committer identity, yours from `user.name` and `user.email`, or
agent-Friend's under `Scripts/fbp_agent_friend.sh`. That is the Developer
Certificate of Origin sign-off the DCO check on pull requests asks for (see
CI and [CONTRIBUTING.md](CONTRIBUTING.md)).

Its closing summary prints the message, one row per phase with the
gate counts and the page count, and every failure's reason.

**`./sfl.sh pre|post`** runs one phase of the gates. Before PRE it runs
`git pull --ff-only` and stops (exit 3) when that cannot fast-forward, then
installs the tools (see Installing and updating), runs `npm ci` when the
npm linters are missing, and exports the Go pin. It runs every gate of the
phase even after a failure, prints a step table and an `Errors:` block with
each failed gate's reason, and exits 0 green, 1 red, 2 on a secret-class
red.

**`Scripts/gate_report_order.txt`** declares every gate, one row
`<label>|<script>|<phase>|<class>`: the label sfl and CI print, the script
that runs, `pre` or `post`, and `secret-class` or nothing. A gate this repo
does not have is a row `<label>|n/a|<reason>`. sfl and CI both run the
rows in file order, so the file is the one list.

**Adding a gate:** write the script and its self-test (`Scripts/test_*.sh`,
red first, plus a mutation proof), give each a row at its position in the
order file (the self-test in PRE, before its gate), add any Homebrew tool
it needs to `Scripts/required_tools.txt`, and describe it below.
`Scripts/test_sfl_drives_from_order_file.sh` is red on a `Scripts/test_*.sh`
no row declares, and the gate-wiring gate on a script neither runner runs.

## Quality gates

`./FBP.sh` runs the gates in two phases around the build: `./sfl.sh pre`
checks the repository before the site is generated, `Scripts/build_site.sh`
renders the site into `.build/site`, and `./sfl.sh post` checks that
generated output. `Scripts/gate_report_order.txt` declares every gate, its
phase and its order; a gate's self-test always runs in PRE, before the gate
it validates.

Two PRE gates come first and are secret-class, so a finding blocks the
commit itself:

- **secret scan** (`Scripts/check_secrets.sh`, the estate's gitleaks gate):
  gitleaks over the working tree, before anything is staged, under `.gitleaks.toml`
  (the default rules, with `${{ secrets.NAME }}` references allowed, since
  they are names, not values). Red, never skipped, when gitleaks is
  missing. Its self-test (`Scripts/test_check_secrets.sh`) plants a key and
  shows it caught.
- **data guard** (`Scripts/check_data_guard.sh`): see Where configuration
  and data live.

Two PRE gates check the page templates and the pages they render:

- **html duplication** (`Scripts/check_html_dupl.sh`, the estate's ratchet
  from konenki-website): jscpd measures the share of duplicated markup in
  the `html/template` files under `internal/page/templates` and the gate
  compares it to a recorded ceiling, today 0.00%. The ceiling only moves
  down: a red is fixed by removing the duplication, never by raising the
  number. Red on a run that scanned zero `.html` files. jscpd is pinned like
  the linters below.
- **golden pages** (`Scripts/check_golden_pages.sh`, forsgren's own,
  forsgren#12 step 8): the build renders the page without an installation's
  config or history, so the POST gates below never see the page with data
  or the no-projects line. This gate runs three of them, HTMLHint, privacy
  posture and html duplication, generated page, on each golden page of
  `internal/page/testdata` (the pages the Go tests pin byte for byte to what
  forsgren renders, the page with data from a made-up history), each page
  alone as the site's one page is. A finding names the page and the gate.
  Red on a directory with no golden page.

Two PRE gates run the Go tests and the formatting:

- **Go tests** (`Scripts/check_go_tests.sh`): `go test ./...` over the
  module. Red on a failing test, on a run that found no test at all, and
  on a package under `node_modules` (go.mod's `ignore node_modules` is what
  keeps npm's vendored Go out of `./...`; this is its guard). A green run
  leaves the coverage profile the Go coverage gate reads.
- **gofmt** (`Scripts/check_gofmt.sh`): check-only, `gofmt -l` over every
  Go file git tracks or would add; red naming each unformatted file, and on
  no Go file found. `./FBP.sh` runs the same script with `--fix` before the
  gates, so locally it sees a formatted tree; CI never fixes.

Seven more PRE gates check the Go code:

- **go mod tidy** (`Scripts/check_go_mod_tidy.sh`, MenoPower's check made
  check-only): red when `go.mod` or `go.sum` is not what `go mod tidy`
  would write, a require missing or unneeded, a `go.sum` line missing or
  stale, with the diff tidy would apply. It runs `go mod tidy -diff`, so it
  never rewrites either file; the fix is `go mod tidy`, committed with the
  change that needed it. Red, as a tool error, when tidy could not run (a
  `go.mod` it cannot parse, a module it cannot fetch). Its self-test
  (`Scripts/test_check_go_mod_tidy.sh`) runs offline and shows, by
  mutation, that `-diff` is what makes the gate red instead of a silent
  rewrite.
- **Go lint** (`Scripts/check_go_lint.sh`, MenoPower's): golangci-lint
  over the module under `.golangci.yml`, ported from MenoPower `shared/`,
  its strictest module: govet, errcheck, staticcheck, gosec, dupl
  (80 tokens), funlen (60 lines, 40 statements), lll (120), gocognit (10)
  and gocyclo (above 6 is red), plus the gofmt and goimports formatters,
  test code included. revive is enabled too but runs no rule: the config's
  one entry, which disables `exported`, replaces revive's default rule set
  (as in MenoPower; an open point on forsgren#1). No issue cap, so every finding is listed. Unlike
  `shared/`, gosec's G101 (a hardcoded credential) is not excluded. A
  finding is fixed in the code: an exclusion or `//nolint` needs Yves's
  approved issue. Red on a module with no Go package, and when golangci-lint
  could not run. Its self-test (`Scripts/test_check_go_lint.sh`) shows
  complexity 7 red (in a test file too) and 6 green, a credential red under
  G101, and, by mutation, that the threshold and the missing G101 exclusion
  in `.golangci.yml` are what decide those cases.
- **Go test duplication** (`Scripts/check_test_dupl.sh`, MenoPower's): the
  same `dupl` rule pointed at `_test.go` files only, which `.golangci.yml`
  leaves to it, so test code is judged once. Red on a module with no test
  file.
- **Go file length** (`Scripts/check_file_length.sh`, MenoPower's
  `check_file_length.py` rewritten in bash and awk): red when a Go
  production file is longer than 600 lines, each such file named with its
  count, longest first. `_test.go` files are not judged; a generated file
  is; a last line without a newline counts. The files are the module's own
  as `go list ./...` sees them, so `node_modules` (ignored in `go.mod`) is
  never judged and a file only another GOOS builds is. Red on a module with
  no production `.go` file. Its self-test
  (`Scripts/test_check_file_length.sh`) shows 601 lines red and 600 green,
  and, by mutation, that the comparison, `go.mod`'s ignore line and the
  GOOS-bound file list are what decide those cases.
- **Go coverage** (`Scripts/check_coverage.sh`, MenoPower's
  `check_coverage.py` rewritten in bash and awk): the coverage ratchet.
  Every function `go tool cover -func` measures has a floor in
  `coverage_thresholds.json`, and the total has one too. Red when a function
  or the total is below its floor, naming it with both numbers, and when a
  measured function is not registered: register it at 0.0, never a guessed
  floor (0.0 is tracked, not enforced). A floor below the ratchet rule,
  measured − 0.1 or exactly 100.0 at 100 %, stays green and is counted into
  one `FLOORWARN: N coverage floor(s) should be raised` line, each such
  function listed with the floor to set. Floors only go up: a red is fixed by
  testing, never by lowering a number. It reads the profile the Go-tests gate
  writes (`.build/go-coverage.out`), so the tests run once; that gate removes
  the profile when it is red, and no profile is red here. The thresholds
  file is read in one fixed shape, one `"key": number` per line, and a line
  outside it is red. Its self-test (`Scripts/test_check_coverage.sh`) shows
  each of those cases and, by mutation, that the floor comparison, the 0.1
  buffer and the Go-tests gate's removal of a red run's profile are what
  decide them.
- **Go vulnerabilities** (`Scripts/check_govulncheck.sh`, MenoPower's):
  govulncheck over the module, red when the code reaches a symbol the Go
  vulnerability database lists, naming each entry. When the database does
  not answer (`curl -sf --max-time 5 https://vuln.go.dev/index/db.json`
  fails: offline, refused, a timeout, an HTTP error) the check is skipped,
  as in MenoPower: one `⚠️ SKIP: govulncheck did not run` line naming the
  database, a `::warning::` in GitHub Actions, exit 0, and never the `OK`
  line of a pass. `FORSGREN_VULN_DB` points it at another database. Its
  self-test (`Scripts/test_check_govulncheck.sh`) runs offline against a
  database it writes, with one made-up entry, and shows a call to the listed
  symbol red, an unreachable database a skip and, by mutation, that the
  probe is what makes offline a skip rather than a tool error.
- **Go dead code** (`Scripts/check_deadcode.sh`, MenoPower's): `deadcode
  -test ./...`, red on any function, exported or not, that neither a main
  package nor a test reaches, each named with its file and line. The fix is
  to delete it, never to call it from a test to keep it alive. Red on a
  module with no main package and when deadcode could not run (a module that
  does not compile). Its self-test (`Scripts/test_check_deadcode.sh`) shows
  both kinds of dead function red, a test-only helper green and, by
  mutation, that `-test` is what keeps it green.

Go lint, Go test duplication, Go vulnerabilities and Go dead code run the
golangci-lint, govulncheck and deadcode pinned in `go.mod` (see Installing
and updating).

Seven PRE gates read the repository's own scripts and files:

- **actionlint** (`Scripts/check_actionlint.sh`, the estate's gate in
  coachretreat-website's copy): every `.github/workflows/*.yml` file under
  `.actionlint.yaml`. Valid YAML is not a valid workflow: actionlint knows
  which contexts exist where (a `runner.temp` in a job-level `env:` block
  once made GitHub reject konenki-website's whole workflow, so not one gate
  ran), which keys a step takes, and which runner labels exist. Every job
  here runs on a GitHub-hosted image, so `.actionlint.yaml` declares no
  custom label: a custom label (a self-hosted runner's) is red until it is
  declared there, and declaring one is configuration, not a waiver.
  actionlint also runs shellcheck over every
  `run:` block, and its self-test (`Scripts/test_check_actionlint.sh`) is red
  when that does not happen, since actionlint skips it silently when
  shellcheck is missing. No `-ignore` flag: a suppression needs a finding
  someone has looked at and Yves's explicit yes. One exists:
  `.actionlint.yaml` ignores, for `.github/workflows/metrics.yml` only,
  actionlint's "not defined" on the documented `job.workflow_sha` and
  `job.workflow_repository`, which actionlint 1.7.12 does not know yet
  (rhysd/actionlint#705); approved on
  [forsgren#4](https://github.com/yveshanoulle/forsgren/issues/4#issuecomment-5952631931),
  to be removed once an actionlint release knows them. Red on a directory with no
  workflow file, and when actionlint itself is missing.
- **zizmor** (`Scripts/check_zizmor.sh`, web-infra's gate): the GitHub
  Actions security linter, over `.github` under `.github/zizmor.yml`, every
  `.yml` and `.yaml` workflow. actionlint asks whether a workflow is valid,
  zizmor whether it is safe; the class it exists for is template injection,
  an attacker-controlled `${{ ... }}` (an issue title, a branch name)
  expanded into a `run:` block, where it runs as shell with the job's token
  on the runner. It runs at web-infra's setting: offline, High
  findings only, the default persona. A Medium finding such as a checkout
  that keeps its credentials is not its red; checkout pins owns that rule.
  The config suppresses nothing: a suppression needs a finding someone has
  looked at and Yves's explicit yes recorded on a GitHub issue. Red on a
  directory with no workflow file. Its self-test
  (`Scripts/test_check_zizmor.sh`) shows each of these, with two mutation
  proofs: the severity threshold is what keeps a Medium out, and the
  config is read from the scanned directory.
- **shellcheck** (`Scripts/check_shellcheck.sh`, the estate's gate from
  web-infra): every tracked `*.sh` file, and every tracked file without an
  extension whose first line is a bash or sh shebang, at any depth. The
  targets come from `git ls-files`, so a new script is checked the moment it
  is tracked, with no list to keep up to date. Red on any finding, and on a
  run that found no script. No script is excluded, and an empty
  `EXCLUDE_ALLOWED` is the normal state. An exclusion needs three things:
  the entry in the gate's `EXCLUDE_ALLOWED`, a sentence here naming the
  script and the reason, and Yves's explicit yes recorded on a GitHub issue,
  which that sentence links.
  A finding is fixed in the script. The same rule holds for a single line:
  it may carry a `# shellcheck disable=SCxxxx` only with a comment giving the
  reason, and with Yves's explicit yes recorded on a GitHub issue, which
  that comment links.
- **yamllint** (`Scripts/check_yamllint.sh`, from konenki-website): every
  tracked `.yml` and `.yaml` file under the rules in `.yamllint.yml`
  (konenki-website's). konenki lints its workflow directory by name;
  here the targets come from `git ls-files`, as for shellcheck, so the
  workflow and any other YAML are covered the moment they are tracked.
  `.yamllint.yml` is itself tracked YAML and is linted too, so the list is
  never empty, and a run that found none is red.
- **stray tracked files** (`Scripts/test_no_stray_tracked_files.sh`,
  konenki-website's): red on a tracked `.DS_Store` at any depth, and on a
  tracked `.yml`/`.yaml` with a top-level `jobs:` key anywhere GitHub would
  not run it (outside `.github/workflows/`, or in a subdirectory of it): a
  workflow copy nobody lints and nothing runs. It first proves its matcher
  on a scratch repository holding one offender of each kind.
- **script references** (`Scripts/check_script_references.sh`, MenoPower's
  guard): red when a script, workflow, order or tool file, or doc names a
  `Scripts/` path that does not exist, checked case-sensitively, so a path
  that macOS forgives but GitHub does not is caught too. Red as well on a
  script that nothing calls: no script, workflow or order-file row mentions
  it, and CLAUDE.md does not list it as run by hand. Red on a run that
  scanned no file or found no `Scripts/` path at all. Another repository's
  script is written with that repository as the first part of its path
  (`web-infra/Scripts/...`) and is not checked; a bare `Scripts/` path is
  read as forsgren's own. Unlike the gates above, it reads the working tree,
  untracked files included. It also keeps `Scripts/` flat: a script (`.sh`
  or `.py`) in any subfolder of `Scripts/` is red. MenoPower bans scripts
  that climb to the root with `..`; Yves ruled that ban N/A for forsgren
  while `Scripts/` is flat, because every script then reaches the root with
  the same single step (forsgren#1, 2026-10-01). This gate enforces the
  condition the ruling rests on, so a script subfolder means revisiting
  the ruling first. Data files in a subfolder are not scripts and stay
  allowed.
- **checkout pins** (`Scripts/test_workflow_checkout_pins.sh`, the estate's
  gate in coachretreat-website's copy): every `uses:` in a
  `.github/workflows/*.yml` file ends in a full 40-hex commit SHA, never a
  tag (`@v4`), a branch (`@main`) or a short SHA, because a tag or a branch
  is resolved when the runner fetches it and its owner can re-point it. The
  version goes in a comment after the SHA (`# v7.0.1`), by convention: the
  gate does not check it. A local action
  (`./...`) is this repository's own code and is skipped; a `docker://`
  reference has no exception and is red. Every `actions/checkout` must also
  set `persist-credentials: false`, so the job token is not left in
  `.git/config` for later steps. Red on a directory with no checkout or no
  `uses:` at all. Its proof (`Scripts/test_workflow_checkout_pins_mutations.sh`,
  row `mutation: checkout pins`) runs first and shows each kind of bad ref
  rejected for its own reason.

actionlint, zizmor, shellcheck and yamllint come from Homebrew, through
`Scripts/required_tools.txt` (see Installing and updating). As with the data
guard, untracked files are not checked: `git add -N` a new script first.

The POST gates, on the generated site:

- **HTMLHint** (`Scripts/gate_htmlhint.sh`): every `.html` file under the
  rules in `.htmlhintrc`. Red on a finding, and on a run that scanned zero
  files, since nothing linted is not clean.
- **Stylelint** (`Scripts/gate_stylelint.sh`): every `.css` file under
  `.stylelintrc.json` (stylelint-config-standard plus konenki-website's
  overrides). Red on a finding, and on a glob that matches no file.
- **html duplication, generated page** (`Scripts/check_html_dupl_site.sh`):
  the same ratchet over `.build/site`, with its own ceiling, today 0.00%. It
  catches what the template scan cannot see, such as a page template that
  pastes the header instead of calling it. The rendered header alone is
  long enough to count as a clone, so a second page will red this ceiling
  even with clean templates; what it does then is still to be decided.
- **lint coverage** (`Scripts/check_lint_coverage.sh`): each linter opened
  every `.html` and `.css` file the site ships, no fewer and no more. A glob
  that stops matching is a smaller job that still reports success; this is
  the gate that notices.
- **required pages** (`Scripts/validate_required_pages.sh` and
  `Scripts/test_required_pages_covers_site.sh`): the pages the site must
  ship are listed, hand-authored, in `internal/page/required-pages.json`
  (today only `/`). The first checks that list's shape: valid JSON, a
  non-empty `requiredPages` array of root-relative paths, no scheme or host,
  no `..`, no duplicates. The second checks it against `.build/site`: every
  `.html` file there is listed, and every listed page was generated. Both
  are red on a missing file or an empty list, and the second on a site with
  no `.html` page at all. A new page means a new line in the list, in the
  same commit as its template.
- **privacy posture** (`Scripts/check_privacy_posture.sh`, the estate's gate
  from konenki-website): the page collects nothing. Red on a form, an
  iframe, a script or stylesheet loaded from another host, a CSS `url()`
  pointing off-site, `document.cookie`, `localStorage` or `sessionStorage`,
  and a known analytics snippet. A green run lists what the page does load
  (self-hosted fonts) and the hosts it links to, so the verdict can be read
  rather than trusted. An outbound link is not a finding: it sends nothing
  until someone clicks it.
- **repository links** (`Scripts/check_repo_links.sh`, forsgren's own): no
  `github.com/<owner>/<repo>` path anywhere in the generated `.html` or
  `.css`, linked or as text. The gate cannot tell a private repository from
  a public one, and the page has no reason to point into either. Red on a
  site with no `.html` page. The failure line names the file and line, never
  the path it matched, so a private repository's name cannot reach a commit
  message.

forsgren has no privacy-pages gate: that one is konenki-website's, pinning
the content of a privacy policy forsgren does not serve. The order file
declares it `n/a` with its reason, and the privacy posture gate keeps that
reason true.

A finding in the generated page is fixed in the template under
`internal/page/`, never by loosening a rule in the config.

## CI

`.github/workflows/quality.yml` runs the same gates as `./sfl.sh`, on every
push to `main`, on every pull request into `main`, and by hand (Actions →
Quality → Run workflow).

**What runs where.** Locally, `./FBP.sh` runs `gofmt -w`, `./sfl.sh pre`,
`Scripts/build_site.sh` and `./sfl.sh post`. CI runs the same three phases
with nothing fixed: `Scripts/run_ci_phase.sh pre`, then
`Scripts/build_site.sh` into `.build/site`, then `Scripts/run_ci_phase.sh
post`. Both read `Scripts/gate_report_order.txt` with the same row rules, so
every gate runs in both, in the same order, under the same label. Before the
gates, CI checks out the commit, puts Homebrew's directories first on `PATH`
and exports `GOTOOLCHAIN` from `go.mod` (as `sfl.sh` does), runs
`Scripts/install_tools.sh` (as `sfl.sh` does) and `npm ci`. The runner is a
fresh machine on every run with none of the Homebrew tools the gates need,
so the installer puts them there; installing and upgrading costs nothing
lasting on a machine that is thrown away after the job. A tool still missing
after it fails the Install tools step by name.

**Check-only.** CI reports what the commit contains. gofmt runs as
`gofmt -l` (the `gofmt` row), never with `--fix`, and a gate that changes
the checked-out tree is a red row, even when it exits 0. That is how CI
treats `npm audit`: locally `Scripts/npm_audit_check.sh` may heal an
advisory with one `npm audit fix` and the new `package-lock.json` rides into
the commit; in CI the same heal is red, naming `package-lock.json`. Run
`./FBP.sh` and commit the result.

**Failures.** A failing gate does not stop its phase: every row runs, so one
run reports every failure, as `sfl.sh` does. The build runs after an
ordinary PRE red too; it is skipped after a secret-class finding (the secret
scan or the data guard), as `FBP.sh` skips it, and the POST gates are
skipped when the build did not succeed. The job's summary page lists every gate in the order
file's order, ✅, ❌ or `n/a`, with each gate's output below the table.
Gates that did not run are counted as unmeasured, never as passing.

**The run summary.** Above that table, every run page opens with the run's
key numbers (forsgren#8), written by the job's last step, which runs after a
failure or a cancel too: the status (succeeded, failed or cancelled, and the
phase it stopped in), the gates passed, failed and skipped in PRE and in
POST, the Go tests passed, the total checks (every individual check that
ran, counted once: each case of every self-test and gate, each Go test, and
a gate with no case lines as one; passed and failed), the coverage total
with its floor, the floors to raise (the coverage gate's FLOORWARN count), the pages generated, the
forsgren version, the commit and trigger (push, pull request with its
number, or by hand) and the duration. `Scripts/render_quality_summary.sh`
reads them from what the run already wrote (the gate rows and outputs, the
page-count sink, `cmd/forsgren/main.go`) and from the job's status and step
outcomes, passed through `env:`. A number that does not exist, from a phase
that never ran or an output that is missing, shows as `—` with the reason,
never as 0. The total checks read each gate's output with one case-line
grammar, written out in the renderer: a closing verdict (`OK: …`,
`✅ test_x`, `FAIL: … contract`) is never a case; a phase that never ran
makes the total `—` naming it, never a partial sum; a gate that never
reported is named as skipped, and a gate whose case lines are in a format
the grammar does not know is named rather than counted silently. Adding a
self-test or a case raises the number.

**From a red CI row to a local run.** A CI row carries the label sfl prints,
and the order file names the script and phase behind it:

```
grep '^gofmt|' Scripts/gate_report_order.txt   # gofmt|Scripts/check_gofmt.sh|pre|
./Scripts/check_gofmt.sh                       # that one gate
./sfl.sh pre                                   # or the whole phase
```

A POST gate reads `.build/site`, so run `./Scripts/build_site.sh` first.

**The runner.** The job runs on GitHub's hosted `macos-latest` image
(`runs-on: macos-latest`), a fresh virtual machine per run, thrown away
after it (Yves's ruling on forsgren#1, road to public: the runner swap). It
has Homebrew and a Go to start from; everything else comes from
`Scripts/install_tools.sh`, `npm ci` and the `go.mod` pins, as locally.

**On pull requests, safely.** Quality triggers on `pull_request` into
`main`, so a contributor's pull request shows the same gate results as a
local `./FBP.sh` run, and never on `pull_request_target`. A pull request
from a fork runs its own code here, which is safe only because of the two
things the ruling pairs with the trigger: the machine is GitHub's and is
thrown away after the job, and a fork's `pull_request` run gets a read-only
token (`contents: read`) and no secrets. The **quality trigger scope** gate
pins this job to `macos-latest`, and the rule holds for every workflow: the
**workflow triggers** gate below is red on any of them that triggers on a
pull-request event while one of its jobs runs anywhere but on a
GitHub-hosted runner. A new push to a pull request cancels its run in
flight; runs on `main` are never cancelled, each commit gets its own.

**Repository settings behind the gates.** On top of that, GitHub holds
every workflow run of a pull request from an outside contributor until the
maintainer approves it, and the repository requires every action to be
pinned to a full commit SHA, the rule **checkout pins** checks in the
files. Secret scanning with push protection and Dependabot alerts are on
too, behind the secret scan and npm audit gates. These are settings, not
files: no gate can see them.

**The DCO check, on pull requests.** `.github/workflows/dco.yml` triggers
on `pull_request` (never `pull_request_target`), as Quality does, and may
because its one job runs on a GitHub-hosted runner (`ubuntu-latest`), with
a read-only token (`contents: read`, `pull-requests: read`). It holds every commit of the pull request to the
Developer Certificate of Origin (see [CONTRIBUTING.md](CONTRIBUTING.md)):
`Scripts/check_dco.sh` is red on a commit with no `Signed-off-by:`
trailer, or with one whose email is not the commit author's, naming the
commit and its subject. A trailer counts only as a whole line of the
message's last paragraph, never in the body, mid-line or as the subject;
the emails are compared without case and never printed. Merge commits get no
exception. Bots are (ruled 2026-10-02, for Dependabot's security updates): a
commit is exempt, named as such, when GitHub links it to an account of type
`Bot` and that bot opened the pull request (`pull_request.user`, passed
through `env:`). Never on the commit's author email, which anyone can write,
nor on the linked account alone, which GitHub derives from that email. The job never checks out the pull request's code: it reads the
commit list through the API (`gh api`, the pull request number passed
through `env:`, never as `${{ }}` inside `run:`), and checks out only
`Scripts/check_dco.sh`, at the pull request's base commit, so a pull
request cannot change the check that judges it. A pull request can still
change `dco.yml` itself, which GitHub reads from the pull request: the
review of such a change is the guard there. The check does not run in
`sfl` or Quality, since a commit on `main` has no pull request; its
self-test does (**DCO sign-off self-test**, `Scripts/test_check_dco.sh`,
offline, with mutation proofs for the last-paragraph rule, the email
comparison, the account-type rule and the opener comparison), and **gate wiring** is red when `dco.yml` stops running
the check or the self-test loses its row.

**The metrics workflow, for installations.** `.github/workflows/metrics.yml`
is the reusable workflow a data repository calls daily (see Running
forsgren). It triggers on `workflow_call` only, so it never runs in this
repository and no pull request can start it. Its one job runs on
`ubuntu-latest`, in the caller's repository and with the caller's token,
checks out the caller's repository only (never forsgren's), and asks for
`pages: write`, `id-token: write` and `contents: write` (the starter step
and the data step each push one commit; a top-level `permissions: {}` gives
the workflow nothing else). Its concurrency group is the caller's
repository, `cancel-in-progress: false`. It takes no inputs: the
caller's `uses: …/metrics.yml@<commit>` line is the only version. Its one
secret, `FORSGREN_TOKEN`, is optional and reaches the collect step's `env:`
only. Its
steps: set up Go (`actions/setup-go` on exactly `go.mod`'s toolchain,
`cache: false`), check its own `job.workflow_sha` is a full 40-digit commit
and its own `job.workflow_repository` one `owner/name`, then
`go install github.com/<that repository>/cmd/forsgren@<that commit>`,
check out the caller's repository (`actions/checkout`, pinned at Quality's
commit, `persist-credentials: false`), `forsgren init-config --config
forsgren.config.yml` and, when it created the file, one commit of that file
alone as `github-actions[bot]`, pushed to the branch the run is on with the token
in git's environment only (so it is in no argument, file or log and the
checkout still stores nothing), `forsgren check-config --config
forsgren.config.yml` (its message printed between
`::stop-commands::<token>` and `::<token>::`, a fresh random token per
run, so a line of it that starts with `::` never runs as a workflow
command), `forsgren collect --config forsgren.config.yml --data
data/deployments.csv` (its output shown with workflow commands stopped, its
exit status kept as a step output), a commit of
`data/` alone when it changed, pushed like the starter (an `::error` naming a
branch that moved, never a rebase or a force), `forsgren render --config
forsgren.config.yml --data data/deployments.csv`, then `actions/upload-pages-artifact` and
`actions/deploy-pages` into the `github-pages` environment, and last a step
that fails the job when collect failed. The job
context, not the `github` context: in a called workflow the `github`
context is the caller's. `setup-go` exports `GOTOOLCHAIN=local`, so
`go install` builds with that Go and never switches to another. The commit
and repository reach the shell through `env:`, never as `${{ }}` inside
`run:`. The two checks are regexes inside the workflow, not a script under
`Scripts/`: the job has no checkout of forsgren, and the only commit it
could fetch one at is the one still unchecked, and the starter and data
steps' logic is the commit and the push, which only git can do. The
**metrics workflow** pin below executes those very blocks, the starter and
data steps with a real git against a local remote.
Nothing in this repository runs the workflow, so no gate does; the pin and
actionlint, zizmor, yamllint, checkout pins and workflow triggers, which read
every workflow, are what check it.

**No paths filter, on purpose.** The secret scan, the data guard, stray
tracked files and script references read every tracked file, so a filter
on paths would leave some change that runs no gate.

Six PRE gates keep the CI honest:

- **gate wiring** (`Scripts/test_gate_wiring.sh`, konenki-website's,
  adapted): every runnable row of the order file has phase `pre` or `post`
  (any other phase runs in neither); `FBP.sh` and `quality.yml` each run
  PRE, the build and POST in that order; `sfl.sh` and
  `Scripts/run_ci_phase.sh` read a row with the same rules; every script
  that no row names is a declared exemption with the runner it must still
  be run by. It also runs `run_ci_phase.sh` itself, over the real order
  file with a stub at every declared path (each row must run exactly once,
  in its own phase, in file order) and over made-up order files (failures,
  the secret-class exit, the tree check, a phase with no row).
- **quality trigger scope** (`Scripts/test_quality_trigger_scope.sh`): the
  workflow runs on every push to `main` and every `pull_request` into it,
  neither with a `paths` or `paths-ignore` filter, never on
  `pull_request_target`, and on `workflow_dispatch`; and its job runs on
  `macos-latest`, the GitHub-hosted image that makes the pull-request
  trigger safe.
- **workflow triggers** (`Scripts/check_workflow_triggers.sh`, forsgren's
  own): no workflow in `.github/workflows` triggers on `pull_request`,
  `pull_request_target`, `pull_request_review` or
  `pull_request_review_comment` (the two review events also run a fork's
  code) while one of its jobs may run on a self-hosted runner. A job counts
  as GitHub-hosted only when its `runs-on` is a single GitHub image label
  (`ubuntu-*`, `windows-*`, `macos-*`); the `self-hosted` label, a custom
  label, a list, a runner group, an expression such as `${{ matrix.os }}`
  and a reusable-workflow job are all judged as self-hosted, because the
  gate cannot prove otherwise. Red as well on a workflow whose `on:` it
  cannot read, and on a run that found no workflow file. It reads the YAML
  with awk, not a YAML library: PyYAML is a Python module, not a command,
  so nothing here installs it, and a parser that depends on it would stop
  gating on the first machine without it.
- **metrics workflow** (`Scripts/test_metrics_workflow.sh`, forsgren's
  own): `metrics.yml` triggers on `workflow_call` and nothing else, and
  declares no inputs; no `run:` block expands a `${{ }}` expression; the
  step "Install forsgren from this workflow's own commit" takes
  `FORSGREN_SHA` from `${{ job.workflow_sha }}` and `FORSGREN_REPOSITORY`
  from `${{ job.workflow_repository }}`, and its `run:` block, executed
  here with a stub `go`, runs exactly
  `go install github.com/yveshanoulle/forsgren/cmd/forsgren@<commit>` for
  `yveshanoulle/forsgren`, installs `github.com/acme/forsgren` for the fork
  `acme/forsgren`, and refuses before `go` runs any commit that is not 40
  lower-case hex digits (a tag, a branch, `latest`, a short or long hash,
  capitals, surrounding spaces, a trailing `;id` or newline, empty) and any
  repository that is not one `owner/name`; `actions/setup-go` comes before
  that step and installs exactly `go.mod`'s toolchain, so a toolchain bump
  in `go.mod` without one here is red; the step "Check out the caller's
  repository" uses `actions/checkout` at the commit Quality's checkout
  uses, with `persist-credentials: false`; the step "Check the caller's
  forsgren configuration", executed with a stub `forsgren`, runs exactly
  `forsgren check-config --config forsgren.config.yml`, fails the job on a
  refusal with the message in the log and after a cross mark in the step
  summary, and leaves no line of the message that starts with `::` live as a
  workflow command, under a token that differs per run; the same step,
  executed with the real `forsgren` built from the checkout, is refused for
  a missing and an invalid `forsgren.config.yml` and passes a valid one;
  the starter step, executed with a real git against a local remote and
  with a stub and the real `forsgren`, commits a created
  `forsgren.config.yml` alone as `github-actions[bot]`, unsigned even under
  a hostile inherited git environment, pushes it to the run's branch with
  the token in git's environment only (pin 13), exits 0 for a kept file
  before any branch logic and refuses on a tag, and the job grants
  `contents: write`;
  `workflow_call` declares the one secret `FORSGREN_TOKEN`, `required:
  false`, and the only `${{ secrets… }}` in the file is the collect step's
  `env:`; the collect step, executed with a stub and with the real
  `forsgren`, runs exactly `forsgren collect --config forsgren.config.yml
  --data data/deployments.csv`, records its exit status as the output
  `status` and succeeds, keeps the token out of arguments, files, the log
  and outputs, with no token passes the starter and records a failure
  naming `FORSGREN_TOKEN` for a configured repository, and, as the config
  step does, leaves no line of collect's output (both streams) that starts
  with `::` live as a workflow command, under a token that differs per run,
  with the stub and with the real `forsgren`; the data step,
  executed with a real git against a local remote, commits nothing when
  `data/` is unchanged (on a tag too), else one commit of `data/` alone as
  `github-actions[bot]`, unsigned even under a hostile inherited git
  environment, pushed to the run's branch with the token as pin 13 has it,
  refused on a tag, and failing with an `::error` naming a branch that
  moved, with no rebase and no force; the last step fails the job for any
  collect status but 0, and collect failing after storing still commits and
  pushes; the job's concurrency group is keyed on `github.repository` with
  `cancel-in-progress: false`; the render step, executed with a stub, runs
  exactly `forsgren render --out <dir> --config forsgren.config.yml --data
  data/deployments.csv`; and install, checkout, starter, config
  check, collect, data commit and render come in that order, the fail step
  after publishing. Each pin is shown failing, with its own reason, on a
  mutant of the real file, judged by the pin it is aimed at.
- **quality-report render** (`Scripts/test_render_quality_report.sh`): the
  summary renderer (`Scripts/render_quality_report.sh`) keeps the declared
  order, exits 0 on a report it rendered, tells an empty or partial run from
  a clean one, and does not count an `n/a` row as a gate that should have
  reported.
- **quality-run summary** (`Scripts/test_render_quality_summary.sh`,
  forsgren's own): the run summary (`Scripts/render_quality_summary.sh`)
  renders every number of a green run, says where a red, cancelled or
  setup-stopped run stopped, names a pull request's number, exits 0 on
  whatever it is given, and shows `—` with the reason for a phase that
  never ran or an output that is missing, never 0; its total checks count
  every case-line format of the real gates once, each Go test once, no
  verdict line, a red gate's failures, and name a phase they are missing, a
  gate that never reported and a case-line format they do not know; shown
  failing, each with its own reason, on mutants that write 0 instead, that
  sum only the phases they have, that count verdict lines, and that drop
  the unknown-format guard.

## Privacy

The public page shows numbers and dates only. It carries no issue titles and
no links into private repositories, makes no third-party requests (no web
fonts, analytics or CDNs: everything it loads is served with it), sets no
cookies, uses no browser storage and tracks no one. Two POST gates check the
generated page on every run, privacy posture for the requests, cookies and
tracking, and repository links for the links (see Quality gates). No gate
checks for issue titles yet: that rests on the renderer, which is given
the project names of the owner's own config, numbers, durations and dates
only: no repository name, commit SHA or message, tag, environment,
workflow or task reaches the page, which `cmd/forsgren/render_data_test.go`
and, for the commits of lead time, `cmd/forsgren/render_leadtime_test.go`
pin. A finding is fixed in the template, never by
loosening the gate.

## Installing and updating

Run `./sfl.sh pre` (or `./FBP.sh`) and the tools install themselves.
`Scripts/required_tools.txt` lists them, and `Scripts/install_tools.sh` installs
each missing one with Homebrew and upgrades the ones already there. Homebrew
must already be installed. Only the tools the quality gates use are listed.

**Go is pinned separately.** `brew install go` also upgrades an outdated Go for
the whole machine, which would be a surprise if forsgren followed it. So
forsgren does not: `go.mod` carries a `toolchain` line (for example
`toolchain go1.27.1`), and `sfl.sh` and `FBP.sh` export it as `GOTOOLCHAIN`.
Go then downloads that exact toolchain on first use and runs it, whatever
version Homebrew installed. (The `toolchain` line alone is only a minimum, so
the export is what makes the pin exact. Nothing is written to your global Go
config.) Both scripts stop with a clear error if `go.mod` has no `toolchain`
line.

**To move to a new Go version,** edit the `toolchain` line in `go.mod`, and
nothing else, then run `./FBP.sh`. Go downloads the new toolchain on the first
run. Do not set the version anywhere else: `go.mod` is the only place it is
written.

**The Go tools are pinned in `go.mod` too.** golangci-lint, deadcode
(`golang.org/x/tools`) and govulncheck (`golang.org/x/vuln`) are `tool`
lines in `go.mod`, with every module they pull in checksummed in `go.sum`,
and the gates run them through `go tool` (Go builds each once and caches
it), so CI and every machine run the same versions. They are never Homebrew
tools, and never `go install ...@latest`: neither has a lockfile. To move
one to a new version:

```
go get -tool github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.15.0
go get -tool golang.org/x/tools/cmd/deadcode@v0.50.0
go get -tool golang.org/x/vuln/cmd/govulncheck@v1.8.0
go mod tidy
```

then run `./FBP.sh` and commit `go.mod` and `go.sum` together (the go mod
tidy gate is red when the `go mod tidy` is forgotten). A new version can
bring new findings; they are fixed in the code like any other.

**The npm linters are pinned in `package.json`.** Node itself (and with it
`npm`) is a Homebrew tool from `Scripts/required_tools.txt`, so like Go it
follows whatever the formula publishes. The npm tools the gates use,
htmlhint, stylelint and stylelint-config-standard, and jscpd for the html
duplication ratchet, are not: they are `devDependencies` in `package.json`
at an exact version (no `^` or `~`), and `package-lock.json` pins every
package they pull in. Both files are committed. `./sfl.sh` runs `npm ci`
when `node_modules/.bin/htmlhint` or `node_modules/.bin/jscpd` is missing:
`npm ci` installs exactly what the lockfile says into `node_modules/`
(gitignored, never committed) and fails when `package.json` and the
lockfile disagree.
Never use `npm install` in a gate or a workflow, and never install the linters
globally or run them through `npx --yes`.

Two gates keep it that way: **npm manifest policy**
(`Scripts/check_guardrail_packages.sh`) is red on a version range in
`package.json`, on a missing or gitignored `package.json` or
`package-lock.json`, and on a tracked `node_modules/`; **npm audit**
(`Scripts/npm_audit_check.sh`) is red on a high-severity advisory that one
`npm audit fix` cannot heal and no ruled exception covers. When that fix does
heal it, the changed `package-lock.json` rides into the commit.

**Ruled exceptions to npm audit.** An advisory with no fix can be excepted
in `Scripts/npm_audit_exceptions.txt`, one line per advisory:
`advisory|package|re-check date|issue|reason`. An exception needs Yves's
explicit yes recorded on a GitHub issue, which its line names, like every
suppression (see Quality gates). The gate reads `npm audit --json` (with jq,
which macOS and GitHub's macOS images ship) and ignores a finding only while
all of these hold: its GHSA ID and its package are listed; today is on or
before the re-check date; `npm audit --omit=dev` does not report it, so
every path to it runs through devDependencies; and npm offers no fix for
that package without `--force` (its `fixAvailable` is false or SemVer-major).
Each ignored finding is printed once, as `excepted: GHSA-… (package) until
<date>, <issue>`. The exception ends by itself: the gate is red again, with
a ❌ line saying why, once the date has passed ("re-check forsgren#13: is a
fix out?"), on any other advisory, when the advisory reaches a production
path, and when a fix without `--force` exists ("a fix exists: remove the
exception and update"). An exception for an advisory npm no longer reports
is a warning (remove the stale exception), not a red; a malformed line or an
advisory listed twice is red before anything is audited.

**Re-checked weekly** (Yves, forsgren#13): a re-check date may be at most 7
days after today, and the gate is red on one further out, so nobody can set
an exception a month ahead. A re-check means looking for a fix. When one is
out, remove the line and update. When there is none, move the date forward
by at most 7 days and add one line to the entry's history comment in the
file (or note it on the issue). Today's one exception is
GHSA-vfj7-8cjw-p6xm (braces `<= 3.0.3`, no patched version), which reaches
forsgren only through jscpd and stylelint via fast-glob and micromatch
([forsgren#13](https://github.com/yveshanoulle/forsgren/issues/13)).

**To move a linter to a new version,** change its exact pin and the lockfile
together, then run `./FBP.sh`:

```
npm install --save-dev --save-exact stylelint@17.15.0
```

That one command rewrites the pin in `package.json`, re-resolves
`package-lock.json` and updates `node_modules/` (sfl's `npm ci` runs only when
`node_modules` has no htmlhint or no jscpd, so it would not pick a bump up on
its own; forsgren#2 tracks reinstalling on a lockfile change).
Check that `package.json` still shows an exact version, and commit both files.

## The tooling's own fixtures

The rest of the PRE rows test the build and gate tooling itself, so a
broken runner cannot report green:

- **sfl pull contract** (`Scripts/test_sfl_pull.sh`): sfl pulls with
  `--ff-only` and stops with exit 3, naming the recovery command, when it
  cannot fast-forward.
- **npm manifest policy self-test**, **npm-audit self-test** and the other
  `... self-test` rows: each drives its gate on made-up input before the
  gate runs.
- **tool install self-test** (`Scripts/test_install_tools.sh`): the
  installer installs a missing tool, upgrades a present one, and is red when
  Homebrew reports success but the tool is still not runnable, or the list
  is empty.
- **Go toolchain pin self-test** (`Scripts/test_go_toolchain.sh`):
  `Scripts/go_toolchain.sh` prints go.mod's `toolchain` version and is red
  without one.
- **build-site self-test** (`Scripts/test_build_site.sh`): the build
  compiles the binary, renders the site and writes the page count only on
  full success.
- **gate-failure summary**, **step table**
  (`Scripts/test_summarize_gate_failure.sh`,
  `Scripts/test_render_step_table.sh`): sfl's end-of-run reason lines and
  step table, with their counts.
- **sfl drives from the order file**
  (`Scripts/test_sfl_drives_from_order_file.sh`): sfl names no gate label
  itself, every row names an executable script, every `Scripts/test_*.sh`
  is declared by a row, and the secret scan and the data guard carry
  `secret-class`.
- **FullBuildAndPush commit-message block** and **FullBuildAndPush
  build-site page count** (`Scripts/test_fbp_commit_message.sh`,
  `Scripts/test_fbp_build_pagecount.sh`): the real `FBP.sh`, run in a
  throwaway repository with stub gates, prints its message, reaches PRE,
  blocks a secret-class commit with the right hint, signs off its green and
  `*** RED ****` commits as the identity that ran it (a commit that then
  passes `Scripts/check_dco.sh`), and fails the build row
  by name on a missing, unreadable, non-numeric or zero page count.

## Status

The bootstrap is done (forsgren#1, 2026-10-02): the build, the gates, CI
and these docs. Since then `collect` reads GitHub into the history file:
the deployments of the configured projects and the commits they shipped.
The page shows each project's deployment frequency, lead time for
changes and failed deployment recovery time. The other DORA metrics are
planned: change fail rate and rework rate. Installations start from the forsgren-template
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
