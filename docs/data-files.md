# Data files

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

