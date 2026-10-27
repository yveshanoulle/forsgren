# Data files

## How it gets its data

forsgren reads only what is already in GitHub:

- **Deployments:** workflow runs (for example a TestFlight upload) and GitHub
  Deployments, with their commit and end time. Failed deployment recovery
  time comes from these alone, the failed ones and the successes after them
  (see [Failed deployment recovery time](pages-and-views.md#failed-deployment-recovery-time)).
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
  named on stderr by `collect`, never silently skipped (see [Collecting
  deployments](#collecting-deployments-collect), The failure issues). The builds are not used yet.

## Where configuration and data live

Not in this repository. It holds code only. An installation keeps its
configuration (which repositories and services, workflow names, labels, the
health URL) and its data (`data/deployments.csv`, the deployments fetched
from GitHub, `data/commits.csv`, their commits, `data/failures.csv`,
the failure issues, `data/issues.csv`, what happened to every issue,
`data/issue_bugs.csv`, which issues carry the `bug` label, `data/pulls.csv`,
the merged pull requests, and `data/pushes.csv`, the pushes to main) in a separate private
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
format v3, with each commit's parents and committer date, forsgren#254; v2
added the author of each commit, forsgren#273; v1 and v2 files are still
read); `data/deployments.csv` does not change. `collect` writes it,
always next to the `--data` file (see [Collecting deployments](#collecting-deployments-collect), The commits
of each deployment):

```
# forsgren commits v3
repository,kind,deployment_id,commit,authored_at,deployed_at,author,parents,committed_at
acme/app,environment,1001,<40 hex>,2026-09-01T09:00:00Z,2026-09-01T10:00:00Z,ada-dev,<40 hex> <40 hex>,2026-09-01T09:30:00Z
```

- One line per commit per deployment. `repository`, `kind` and
  `deployment_id` are the deployment's key in `deployments.csv`;
  `authored_at` is the commit's author date and `deployed_at` the
  deployment's `created_at`, copied so lead time needs no join. Both are UTC.
- `author` (format v2, decision 274 of forsgren#273) is the GitHub login of
  the commit's author: the account GitHub links the commit to, taken from the
  top-level `author` of GitHub's comparison answer (not from `commit.author`,
  which holds the name and the email as git records them). It is never an
  email address and never a name: only the shape of a login is accepted (letters,
  digits, hyphens and underscores, and for a bot account the suffix `[bot]`).
  A commit that GitHub links to no account, because its email belongs to no
  user, has an empty `author`: unknown, never guessed. When GitHub answers
  such a commit with its placeholder login `invalid-email-address` instead,
  the line keeps that login as GitHub gave it, and what counts developers
  takes it for an unknown author, never a person (forsgren#355), so a line
  stored before reads the same. A bot account is stored as GitHub names it, `dependabot[bot]`: leaving bots out is the job of what
  counts developers, not of the file. One person with several email addresses
  is one login. The login is already public on GitHub next to the commit.
- `parents` (format v3, forsgren#254) are the SHAs of the commit's parents,
  taken from the `parents` of GitHub's comparison answer in GitHub's order,
  the first parent first, parted by one space, as `git log` lists them: a
  merge's first parent is the line it was made on, the second the line it
  brought in. Empty means none known: a commit stored before v3, or a root
  commit, which a comparison of two deployments does not reach. Only SHAs are
  accepted. The Mainline Interval follows the first parents and places those
  commits at `committed_at` (see [The TBD page](pages-and-views.md#the-tbd-page)).
- `committed_at` (format v3, forsgren#254) is the commit's git committer date
  (`commit.committer.date` of the answer), UTC, whole seconds: when the commit
  landed where it is now. Empty when GitHub gives none or the commit was stored
  before v3; never the author date in its place.
- The project and the task are not repeated: the project comes from the
  config, as for deployment frequency, and the task is the deployment's own.
- The same rules as `deployments.csv`: created with its version line,
  appended only, refused untouched when its version is unknown or a line is
  malformed. A commit already there for the same deployment (repository
  ignoring case, kind, ID and the same SHA) is skipped; a call with nothing
  new leaves the file alone. The author, the parents and the committer date
  are not part of the key: a commit already held keeps the ones it was stored
  with.
- **v1 and v2 files.** A `commits.csv` written before the author column (the
  commits format v1, six columns) or before the parents and committer date (the
  commits format v2, seven columns) is still read, what it lacks empty. The
  first `collect` that appends to it, also when it has no new commit, writes it
  again once as v3: every line kept as it was with the columns it lacks empty,
  then the new lines with theirs, through a temporary file in the same
  directory and a rename, so an interrupted run leaves the old file. The
  authors, parents and committer dates of commits stored before are not known
  when the file is rewritten: the legacy backfill below asks GitHub for them
  once. A file with a version it does not know, or a line that is not in the
  format, is still refused untouched.
- **The legacy backfill** (forsgren#385). A line of a commit stored before v3
  has no parents and no committer date, and one stored before v2 no author
  either (`Commit.Legacy`). The first `collect` of a release that has the
  backfill compares, once per repository, each stored deployment that has such
  lines with the previous success of its stream, the comparison it uses for a
  new deployment (one request for up to 250 commits, not one per commit), and
  fills only the empty author, parents and committer date of the matching
  lines, whatever the age of the deployment. A commit GitHub links to no
  account keeps an empty author, and nothing is invented. The file is
  rewritten whole, in file order, through a temporary file and a rename, and
  only when a line changed. A deployment with no previous success is not
  compared, and a deployment GitHub no longer lists (a rewritten history, a
  list cut at the page limit) keeps its legacy lines; stderr says `collect:
  backfill: deployment 1002: ...; its legacy commits stay without author`,
  and the repository still counts as done. The request budget applies: before
  each comparison one request is reserved, and a repository cut short keeps
  what it filled and continues on the next run, which can take more than one
  day (see the cut report below). Within a repository the backfill runs after
  its pull requests and before its push read (forsgren#416): the first push
  read costs one comparison per push and could spend the whole budget, so a
  repair of data the page already shows goes first. A backfill that is cut
  short or fails stops the repository's run, so the push read sends no
  request after it; a push read cut short afterwards is no cut of the
  backfill, which is then noted done. The note of the repositories done is
  `data/commits_backfilled.csv`, described after the starts catch-up note.

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

**The withdrawn failures** (forsgren#155) are kept next to it in
`data/failures_withdrawn.csv`, with its own format version (the failures
withdrawn format v1): one line each time a stored failure issue stops
counting, or counts again.

```
# forsgren failures withdrawn v1
repository,issue,withdrawn,reason,at
acme/app,42,true,label_removed,2026-10-01T06:00:00Z
acme/app,43,true,not_planned,2026-10-01T06:00:00Z
acme/app,44,true,issue_gone,2026-10-01T06:00:00Z
acme/app,42,false,,2026-10-03T06:00:00Z
```

- `failures.csv` only grows, so an issue that turns out not to be a failure
  cannot leave it; this file takes it back instead. `withdrawn` is `true` or
  `false`; `at` is when `collect` saw it, UTC, to the second.
- `reason` says why a line with `withdrawn` `true` takes the issue back:
  `label_removed`, the issue no longer carries the `failure` label (the label
  is the ruling, forsgren#6); `not_planned`, it was closed as not planned;
  `issue_gone`, GitHub no longer has it (deleted or transferred). A line with
  `withdrawn` `false` reinstates the issue and has no reason. Any other
  reason, or a reason on a reinstatement, is refused.
- The newest line of an issue wins (key: repository, ignoring case, and issue
  number): above, issue 42 lost its label, then got it back, and counts
  again. An issue gets a new line only when its `withdrawn` or `reason`
  differs from its newest line; an issue no line names counts.
- A withdrawn issue is left out of change fail rate and rework rate when the
  page is rendered, as if it were not in `failures.csv` (see [Pages and
  views](pages-and-views.md#change-fail-rate)); its lines in `failures.csv`
  stay as they are.
- Otherwise the same rules as `deployments.csv`: created with its version
  line, refused untouched when its version is unknown or a line is
  malformed, naming the line; a refused file stops the collect run before
  GitHub is asked anything and fails the render with its own message.
- The data guard knows its name: a `failures_withdrawn.csv` that git tracks
  or does not ignore, outside `testdata/` blocks the commit, like the other data files.

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

**The bugs cut note** (forsgren#140) is kept in `data/issue_bugs_cut.csv`,
next to the history, with its own format version (the bugs cut format v1):
one line per repository whose last bug read stopped at the 10,000 issues cap,
so its bug flags, and the Open bugs column, may be incomplete.

```
# forsgren bugs cut v1
repository,cut_at
acme/app,2026-10-14T06:00:00Z
```

- `cut_at` is the start of the run whose bug read of the repository stopped
  at the cap, in UTC, to the second. Lines are sorted by repository.
- A run writes the line when the repository's bug read stopped at the cap,
  moving its time when it is already there, and removes the line when the
  bug read was complete. A repository that failed keeps its line as it was.
- Unlike the files above it is rewritten whole, like `data/reach.csv`: through
  a temporary file that is renamed over it, and only when a line changed. A
  missing file notes no repository.
- An unknown version or a malformed line refuses the collect run before
  GitHub is asked anything, and fails the render with its own message,
  naming the file.
- While it notes any repository, every row of the Open bugs column shows
  `— (incomplete)` instead of a number (see
  [Pages and views](pages-and-views.md)).
- The data guard knows its name: an `issue_bugs_cut.csv` that git tracks
  or does not ignore, outside `testdata/` blocks the commit, like the other data files.

**The cut runs note** (forsgren#64) is kept in `data/cut_runs.csv`, next to
the history, with its own format version (the cut runs format v1): one line per
repository that the request budget cut short without keeping a day, since the
first run of that streak.

```
# forsgren cut runs v1
repository,first_cut_at
acme/app,2026-10-14T06:00:00Z
```

- `first_cut_at` is the start of the first run of the streak, in UTC, to the
  second. Lines are sorted by repository.
- A run writes the line when it cut the repository short and kept nothing (no
  record and no read mark moved), keeping the time of a line that is already
  there. A run that kept something, or read the repository to its end, removes
  the line; a repository that failed keeps its line as it was.
- A repository cut short that already has the line is reported as stalled: it
  made no progress on two runs in a row (see the cut report below). The first
  run it makes none is reported as `no`.
- Rewritten whole like `data/reach.csv`, through a temporary file renamed over
  it, and only when a line changed. A missing file notes no repository. An
  unknown version or a malformed line refuses the collect run before GitHub is
  asked anything, naming the file.
- The data guard knows its name: a `cut_runs.csv` that git tracks or does not
  ignore, outside `testdata/` blocks the commit, like the other data files.

**The starts catch-up note** (forsgren#245) is kept in `data/starts_checked.csv`,
next to the history, with its own format version (the starts checked format
v1): one line per repository whose stored failure issues had their empty
`failure_start` caught up from the issues' comments (forsgren#37).

```
# forsgren starts checked v1
repository,checked_at
acme/app,2026-10-21T06:00:00Z
```

- A repository without a line is caught up once: each of its stored failure
  issues with an empty `failure_start` that is open or was opened in the DORA
  window, and that no withdrawal takes back, has its comments read once, and a
  record block found there is stored as a new line of the failure. A refused
  read fails the repository.
- The lines are written only when every repository of the run finished: a run
  that failed or was cut short anywhere writes none, and does the catch-up
  again, which stores only what it finds. An installation that has done it gets
  no second one; a repository added to the configuration later gets its own.
- Rewritten whole like `data/reach.csv`, and only when a line changed. A
  missing file notes no repository. An unknown version or a malformed line
  refuses the collect run before GitHub is asked anything, naming the file.
- The data guard knows its name: a `starts_checked.csv` that git tracks or
  does not ignore, outside `testdata/` blocks the commit, like the other data
  files.

**The commits backfill note** (forsgren#385) is kept in
`data/commits_backfilled.csv`, next to the history, with its own format version
(the commits backfilled format v1): one line per repository whose legacy
commits had their author, parents and committer date backfilled (see the
commits above).

```
# forsgren commits backfilled v1
repository,backfilled_at
acme/app,2026-10-25T06:00:00Z
```

- A repository without a line is backfilled; once every one of its comparisons
  was tried, it is noted, also when some lines stayed legacy because GitHub no
  longer lists their commits.
- The lines are written only when every repository of the run finished: a run
  that failed or was cut short anywhere, a cut backfill included, writes none,
  and the backfill continues on the next run, which compares only deployments
  that still have legacy lines. An installation that has done it gets no second
  one; a repository added to the configuration later gets its own.
- Rewritten whole like `data/reach.csv`, and only when a line changed. A
  missing file notes no repository. An unknown version or a malformed line
  refuses the collect run before GitHub is asked anything, naming the file.
- The data guard knows its name: a `commits_backfilled.csv` that git tracks or
  does not ignore, outside `testdata/` blocks the commit, like the other data
  files.

**The merged pull requests**, for the PR Lead Time (forsgren#255,
forsgren#256), are kept in `data/pulls.csv`, next to the history, with its own
format version (the pulls format v2, forsgren#345):

```
# forsgren pulls v2
repository,number,created_at,merged_at,merge_commit,updated_at,first_commit_at,first_commit_cut,created_stands_in,bot
acme/app,42,2026-09-01T10:00:00Z,2026-09-03T15:00:00Z,<40 hex>,2026-09-03T15:01:00Z,2026-08-30T09:00:00Z,false,false,false
acme/app,43,2026-09-02T08:00:00Z,2026-09-02T09:00:00Z,<40 hex>,2026-09-02T09:00:00Z,,false,true,true
acme/app,44,2026-09-02T10:00:00Z,2026-09-02T11:00:00Z,<40 hex>,2026-09-02T11:00:00Z,2026-09-02T09:00:00Z,false,false,
```

- One line per merged pull request. A pull request closed without a merge is
  not stored. No title, no body, no author and no branch name is stored: a
  branch name can identify people, and no metric uses it (decision #305).
  `collect` does not read the branch name either (decision #322), nor the
  author's login: only the author's account type, for the `bot` column.
- `repository` is `owner/name` and `number` the pull request's number.
- `created_at`, `merged_at` and `updated_at` are the pull request's created,
  merged and updated time, UTC, to the second. `updated_at` is a snapshot:
  GitHub's updated time when `collect` first stored the pull request. It is
  not kept current and is never the pull request's latest update on GitHub: a
  stored line is never written again, so a later comment or label does not
  move it. Where the next read starts is never taken from this file: the read
  mark in `data/pulls_read.csv` alone decides that (decision #304).
- `merge_commit` is the SHA of the commit the merge made, 40 or 64 lower-case
  hex digits.
- `first_commit_at` is the pull request's first commit time, UTC, to the
  second. First commit time is the earliest Git author timestamp among the
  commits in the pull request. Cherry-picked commits retain their original
  author timestamps. No age cut-off is applied. It approximates when the work
  began; it is not a guaranteed measurement of branch lifetime (decision
  #298).
- `first_commit_cut` is `true` when the commit list was cut, so the first
  commit may be missing from what was read: GitHub lists at most 250 commits
  of a pull request, so 250 commits read is cut (249 is complete), and so is a
  list that stopped at the page limit. The time is kept: it is the earliest of
  the commits read, so the lead time it gives is a lower bound, never exact
  (decisions #299, #301). The flag stays even when all the dates read are
  equal. Otherwise `false`. A pull request is marked as cut when a page or
  GitHub limit prevents reading its complete commit history. If the request
  budget is exhausted during that read, the pull request is not stored and is
  retried on the next collection run. Budget exhaustion is a resumable
  interruption, not a permanent data cut (decision #308).
- `created_stands_in` is `true` when the commit list gave no usable date (no
  commit, or a commit without an author date, or an answer forsgren cannot
  read): then `first_commit_at` is empty and the pull request's created time
  stands in for its first commit time (decisions #300, #303, #313). It is
  never `true` because the list was cut, so a line is never cut and standing
  in at once. `first_commit_at` is empty exactly when it is `true`, and a
  valid time exactly when it is `false`: a line with a stand-in and a time,
  or with neither, is refused when it is read and never written (decision
  #303). Otherwise `false`.
- `bot` says whether a bot account opened the pull request (forsgren#345):
  `true` when GitHub's account type of the author (`user.type`) is `Bot`,
  Dependabot among them, `false` only when it is `User`, and empty when the
  author's type is not known: GitHub named no author or no type, it is any
  other type (`Organization`, `Mannequin`; #349), or the line was stored
  before this column. Such a pull request is still stored. Empty is never
  read as a person. The login itself is
  never read or stored (#255's no-authors rule). PR Lead Time counts
  the `false` lines only; a `true` line and an empty one are left out of it
  and counted apart in its cell (forsgren#345).
- A file of the pulls format v1, without the `bot` column, is still read,
  every pull request's `bot` empty (not known). The first `collect` run that
  appends to it, whether or not it stores a pull request, rewrites it once as
  v2, whole, through a temporary file: every old line kept as it was, its
  `bot` column empty, then the new lines. Nothing is backfilled: an old line
  stays not known for good (#293).
- Held by repository (ignoring case) and number, as GitHub numbers a
  repository's issues and pull requests from one sequence: a pull request
  already in the file is skipped, the first line staying whatever a later read
  says (decision #306). `first_commit_cut` and `created_stands_in` describe
  the quality of the stored measurement, not a state waiting for a
  correction: both stay for that record for good. A correction, if one is
  ever needed, is an explicit, versioned migration, never a silent change to
  a stored line's values (the v2 upgrade above keeps every value of every
  line, `bot` empty). The new lines of a run are in merge order (merged time,
  repository, number).
- Otherwise the same rules as `deployments.csv`: created with its version
  line, appended only, refused untouched when its version is unknown or a line
  is malformed, naming the line. A run with nothing to store still writes the
  file with its two header lines (decision #312). An unreadable file refuses
  the collect run before GitHub is asked anything.
- The data guard knows its name: a `pulls.csv` that git tracks or does not
  ignore, outside `testdata/` blocks the commit, like the other data files.

**The pulls read mark** (forsgren#255) is kept in `data/pulls_read.csv`, next
to the history, with its own format version (the pulls read format v1): one
line per repository whose closed pull requests were read to the end.

```
# forsgren pulls read v1
repository,read_at
acme/app,2026-10-23T06:00:00Z
```

- `read_at` is the start of the run that last read the repository's closed
  pull requests, in UTC, to the second. Lines are sorted by repository.
- The next run reads the pull requests updated since that time less a day
  (never before `history_days` back), and a repository without a line reads
  back to `history_days` (decision #304). This line alone decides where the
  read resumes; `pulls.csv` is never read for it.
- The line moves only after a read that ended, and only after the pull
  requests it read are stored: a read that a missing `pull-requests`
  permission or the request budget stopped keeps the line as it was, so the
  next run reads the rest, the interrupted pull request included, and no pull
  request is skipped (decisions #304, #308). A read cut at the page limit
  moves it (decision #309).
- Rewritten whole like `data/reach.csv`, and only when a line changed. A
  missing file notes no repository. An unknown version or a malformed line
  refuses the collect run before GitHub is asked anything, naming the file.
- The data guard knows its name: a `pulls_read.csv` that git tracks or does
  not ignore, outside `testdata/` blocks the commit, like the other data
  files.

**The pulls denied mark** (forsgren#337) is kept in `data/pulls_denied.csv`,
next to the history, with its own format version (the pulls denied format
v2, forsgren#321): one line per repository whose pull request read GitHub
refused.

```
# forsgren pulls denied v2
repository,denied_at,token
acme/app,2026-10-23T06:00:00Z,FORSGREN_TOKEN
```

- `repository` is `owner/name` in lower case (decision #339); `denied_at` is
  the start of the run that GitHub last refused the read, in UTC, to the
  second. `token` is the name of the token that was refused,
  `FORSGREN_TOKEN` or `GITHUB_TOKEN` (the job's own), so the setup issue can
  name the right fix. Only a name: no token value and no error text is stored,
  and a `token` column that is not an upper-case variable name refuses the
  file on read and on write, without quoting it. Lines are sorted by
  repository. The v1 format, without the `token` column, is still read, every
  token name empty, and the next save writes the file again as v2.
- Written when GitHub answers the pull request read with a 403 that is not
  the rate limit: the token cannot read the repository's pull requests (no
  `pull-requests: read`). A later refused run moves the time.
- Cleared, the repository's line removed, after a pull request read that ends
  without an error: merged pull requests, none, or a list cut at the page
  limit, which GitHub did answer (decision #332). A budget stop or any other
  error leaves the file as it was: neither says whether the token can read
  pull requests.
- Kept apart from the other states of the pull request read: a budget stop is
  a `pulls-cut` line of the cut report (see below), never a line here; an
  incomplete read (a list cut at the page limit) clears the line; and a
  repository with no merged pull request in the window has no line, so it
  shows `-`.
- The TBD page reads it: a project with a repository named here shows
  `Pull requests not readable` in its PR Lead Time cell, in place of a
  lead time, of `-` and of `No pull requests have been collected yet`, even
  when its other repositories were read: one refused repository makes the
  project's whole cell not readable. The names are compared with the config's
  ignoring case (decision #339), and a line of a repository no project lists
  is left out.
- `forsgren check-needs` reads it (`--pulls-denied`, this file by default) and
  adds one setup issue item per repository named here, with the token's name
  and the permission it needs; the item goes away once the line is cleared
  (see [The setup issue](updating-and-releases.md#the-setup-issue-check-needs),
  forsgren#321). A file that cannot be read or is in no known format makes the
  check fail and leaves the setup issue as it is (forsgren#395).
- Rewritten whole like `data/reach.csv`, and only when a line changed. A
  missing file notes no repository, so nothing is not readable. An unknown
  version or a malformed line refuses the collect run before GitHub is asked
  anything, and fails the render, naming the file, as the other data files
  do.
- The data guard knows its name: a `pulls_denied.csv` that git tracks or does
  not ignore, outside `testdata/` blocks the commit, like the other data
  files.

**The pushes to main**, for time to main and batch size per push
(forsgren#397, decision #400), are kept in `data/pushes.csv`, next to the
history, with its own format version (the pushes format v1):

```
# forsgren pushes v1
repository,pushed_at,before,after,kind,bot,commits
acme/app,2026-10-23T10:00:00Z,<40 hex>,<40 hex>,push,false,3
acme/app,2026-10-23T11:30:00Z,<40 hex>,<40 hex>,pr_merge,true,1
acme/app,2026-10-23T12:00:00Z,<40 hex>,<40 hex>,force_push,,
```

- One line per push to the repository's default branch, from GitHub's
  repository activity list. No login and no actor name is stored: only
  whether a bot made the push.
- `repository` is `owner/name`; `pushed_at` is the push's time, UTC, to the
  second; `before` and `after` are the branch's tip before and after the
  push, 40 or 64 lower-case hex digits.
- `kind` is `push` (a direct push), `pr_merge` (a pull request merge) or
  `force_push`; GitHub's other kinds of activity (a branch created or
  deleted, a merge queue merge) are not stored.
- `bot` is `true` when GitHub's account type of the actor is `Bot`, `false`
  only for `User`, and empty when it is not known. Empty is never read as a
  person.
- `commits` is the number of commits the push added to the first-parent
  chain: the compare of `before...after`, walked from `after` through each
  first parent while it is a commit of the compare. A straight push of three
  commits is 3, a merge commit that brought a branch in is 1. It is empty
  when the number cannot be told, never a guessed one: the compare failed
  (no ancestor, a commit GitHub does not have), was cut at GitHub's or the
  page limit, or did not reach `after`; and always for a `force_push`, which
  asks for no compare. `collect` names each such push on stderr.
- Held by repository (ignoring case), `after` and `pushed_at`: a push
  already in the file is skipped, the first line staying whatever a later
  read says. The new lines of a run are in time order.
- Otherwise the same rules as `pulls.csv`: created with its version line,
  appended only, refused untouched when its version is unknown or a line is
  malformed, naming the line. An unreadable file refuses the collect run
  before GitHub is asked anything.
- The data guard knows its name: a `pushes.csv` that git tracks or does not
  ignore, outside `testdata/` blocks the commit, like the other data files.

**The commits of each push** (forsgren#397, step 3; format v2 forsgren#463) are
kept in `data/push_commits.csv`, next to the history, with its own format
version (the push commits format v2):

```
# forsgren push commits v2
repository,after,sha,author,authored_at,first_parent,parents
acme/app,<40 hex>,<40 hex>,acme-dev,2026-10-23T09:30:00Z,true,1
acme/app,<40 hex>,<40 hex>,acme-dev,2026-10-23T08:10:00Z,false,1
```

- One line per commit of the compare of a push, from the same compare (no
  extra request), oldest first: every commit of a whole compare, not only the
  first-parent chain. `first_parent` is `true` for the commits that make the
  `commits` count of the push's line in `pushes.csv` and `false` for the
  branch commits a merge brought in. `after` is the push's `after` SHA, which
  with `repository` and `pushed_at` keys the push; `sha` is the commit.
- `parents` is the commit's parent count, a decimal (a root commit has 0). It
  is empty when unknown: a line of the format v1 is read with `first_parent`
  true and `parents` empty, and the first append rewrites the whole file as v2.
  The empty `parents` is what tells data from before the change; the page's
  note 7 reads it (see [Pages and views](pages-and-views.md#the-tbd-page)).
- `author` is the GitHub login of the commit's author, empty when GitHub
  links the commit to no account, only a login's shape accepted; never a name
  or an email address. `authored_at` is the git author date, UTC, to the
  second.
- Held by repository (ignoring case), `after` and `sha`: a commit already in
  the file is skipped. A push whose `commits` is empty (a force push, a
  compare that failed or was cut) has no lines.
- The Time to main and the shares count the `first_parent` lines only; the
  Mainline Lead Time counts the others too, and leaves the commits with two
  parents or more out.
- `collect` writes it before `pushes.csv` for the same repository, so a push
  is never stored without its commits: when this file cannot be written, the
  repository fails and its pushes are read again by the next run.
- Pushes stored earlier are not read again for their commits, with one
  exception: the history fill (forsgren#470, see
  [Collecting deployments](#collecting-deployments-collect)) compares each
  stored `pr_merge` push that has a line of unknown parents once more and
  replaces its lines by the ones a push read writes today, the merge's branch
  commits included. The file is then rewritten whole, the other lines and the
  order of the pushes unchanged.
- Otherwise the same rules as `commits.csv`: created with its version line,
  appended only, refused untouched when its version is unknown or a line is
  malformed, naming the line. An unreadable file refuses the collect run
  before GitHub is asked anything.
- The data guard knows its name: a `push_commits.csv` that git tracks or does
  not ignore, outside `testdata/` blocks the commit, like the other data
  files.

**The commits of each merged pull request** (forsgren#463, steps 5 and 6) are
kept in `data/pull_commits.csv`, next to the history, with its own format
version (the pull commits format v1):

```
# forsgren pull commits v1
repository,number,sha,author,authored_at
acme/app,42,<40 hex>,acme-dev,2026-08-30T09:00:00Z
```

- One line per commit of the commit list of a merged pull request, from the
  request `collect` already makes for its first commit time (no extra
  request). `number` is the pull request's number; `sha` the commit. They are
  there for the Mainline Lead Time of a squash merge, where the originals'
  own author dates stand in for the squash commit's.
- `author` is the GitHub login of the commit's author, empty when GitHub
  links the commit to no account; login only, never a name or an email
  address. `authored_at` is the git author date, UTC, to the second.
- Held by repository (ignoring case), `number` and `sha`.
- `collect` writes a pull request's lines before its line in `pulls.csv`, so
  a pull request is never stored without its commits. A list GitHub cut (250
  commits) is stored as read. A pull request whose created time stands in for
  its first commit time (no usable commit list) has no lines.
- Pull requests stored before this file existed had no lines. The history fill
  (forsgren#470, see [Collecting deployments](#collecting-deployments-collect))
  reads the commit list of each of them once and appends its lines; a pull
  request whose created time stands in is not read.
- Otherwise the same rules as `commits.csv`: created with its version line,
  appended only, refused untouched when its version is unknown or a line is
  malformed, naming the line. An unreadable file refuses the collect run
  before GitHub is asked anything.
- The data guard knows its name: a `pull_commits.csv` that git tracks or does
  not ignore, outside `testdata/` blocks the commit, like the other data
  files.

**The pushes read mark** (forsgren#397) is kept in `data/pushes_read.csv`,
next to the history, with its own format version (the pushes read format
v1): one line per repository whose pushes were read to the end.

```
# forsgren pushes read v1
repository,read_at
acme/app,2026-10-23T06:00:00Z
```

- `read_at` is the start of the run that last read the repository's pushes,
  in UTC, to the second. Lines are sorted by repository.
- The next run reads the pushes since that time less a day (never before
  `history_days` back); a repository without a line reads back to
  `history_days`.
- The line moves only after a read that ended: a read that a missing
  permission, the request budget or an error stopped keeps the line as it
  was. A list cut at the page limit moves it, with a note on stderr that
  older pushes may be skipped for good.
- Rewritten whole like `data/reach.csv`, and only when a line changed. A
  missing file notes no repository. An unknown version or a malformed line
  refuses the collect run before GitHub is asked anything, naming the file.
- The data guard knows its name: a `pushes_read.csv` that git tracks or does
  not ignore, outside `testdata/` blocks the commit, like the other data
  files.

**The pushes denied mark** (forsgren#397) is kept in `data/pushes_denied.csv`,
next to the history, with its own format version (the pushes denied format
v2, forsgren#414): one line per repository whose push read GitHub refused.

```
# forsgren pushes denied v2
repository,denied_at,token
acme/app,2026-10-23T06:00:00Z,FORSGREN_TOKEN
```

- `repository` is `owner/name` in lower case; `denied_at` is the start of the
  run that GitHub last refused the read, in UTC, to the second. `token` is the
  name of the token that was refused, `FORSGREN_TOKEN` or `GITHUB_TOKEN` (the
  job's own), so the setup issue can name the right fix. Only a name: no token
  value and no error text is stored, and a `token` column that is not an
  upper-case variable name refuses the file on read and on write. Lines are
  sorted by repository. The v1 format, without the `token` column, is still
  read, every token name empty, and the next save writes the file again as v2.
- Written when GitHub answers the activity list with a 403 that is not the
  rate limit: the token cannot read the repository's contents (no
  `contents: read`). A later refused run moves the time.
- Cleared, the repository's line removed, after a push read that ends without
  an error: pushes, none, or a list cut at the page limit. A budget stop or
  any other error leaves the file as it was.
- The TBD page reads it: a project with a repository named here shows `Push
  activity not readable` in the push groups (see
  [The TBD page](pages-and-views.md#the-tbd-page)).
- `forsgren check-needs` reads it too (`--pushes-denied`, this file by
  default) and adds one setup issue item per repository named here, with the
  token's name and the permission it needs; the item goes away once the line is
  cleared (see
  [The setup issue](updating-and-releases.md#the-setup-issue-check-needs),
  forsgren#414). A file that cannot be read or is in no known format makes the
  check fail and leaves the setup issue as it is (forsgren#395).
- Rewritten whole like `data/reach.csv`, and only when a line changed. A
  missing file notes no repository. An unknown version or a malformed line
  refuses the collect run before GitHub is asked anything, naming the file.
- The data guard knows its name: a `pushes_denied.csv` that git tracks or does
  not ignore, outside `testdata/` blocks the commit, like the other data
  files.

**The two history fill marks** (forsgren#470) are kept in
`data/pull_commits_filled.csv` and `data/push_commits_filled.csv`, next to the
history, each with its own format version (the pull commits filled format v1
and the push commits filled format v1): one line per repository whose one-time
fill is done, the pull requests' commits in the first and the merge pushes'
lines in the second.

The pull requests fill starts only after the pull request read of the same
repository ended whole. A read cut short by the request budget or refused
(403) leaves the fill to the next run, with no warning, report line or request
of its own (forsgren#491). The merge pushes fill runs before the push read, so
it has no such wait.

```
# forsgren pull commits filled v1
repository,filled_at
acme/app,2026-10-27T06:00:00Z
```

```
# forsgren push commits filled v1
repository,filled_at
acme/app,2026-10-27T06:00:00Z
```

- `filled_at` is the start of the run that finished the repository's fill, in
  UTC, to the second. Lines are sorted by repository.
- A repository with a line is not filled again; one without is filled by the
  next run. A line is written as soon as the repository's fill finished, also
  when GitHub could not give some of what it asked for (named on stderr). A
  fill that a missing permission, the request budget or an error stopped
  writes no line, and the next run continues with what is still missing.
- The TBD page reads both: note 7 is not set by a repository whose fill is
  done (decision #484, see
  [The TBD page](pages-and-views.md#the-tbd-page)), so what the fill could not
  read does not keep the note on.
- Rewritten whole like `data/reach.csv`, and only when a line changed. A
  missing file notes no repository. An unknown version or a malformed line
  refuses the collect run, and the render, naming the file.
- The data guard knows their names: a `pull_commits_filled.csv` or a
  `push_commits_filled.csv` that git tracks or does not ignore, outside
  `testdata/` blocks the commit, like the other data files.

**The pulls bot fill mark** (forsgren#500) is kept in
`data/pulls_bot_filled.csv`, next to the history, in its own format (the pulls
bot filled format v1): one line per repository whose one-time fill of the
opener of its stored merged pull requests is done.

A pull request stored before the bot column (forsgren#345) has an empty `bot`
column in `data/pulls.csv`, unknown, and counts in neither PR Lead Time nor Bot
PR Lead Time. Once per repository, after its pull requests are read and the
two fills above and the push read are done, `collect` reads each stored pull request of the
repository with an unknown `bot` once (`GET /repos/{owner}/{repo}/pulls/{number}`,
the request budget reserved first) and sets the column from the account type
of its opener: `Bot` is `true`, `User` is `false`, anything else stays empty.
Every stored pull request counts, not only those of the DORA window. Like the
pull requests fill it starts only after the pull request read of the same
repository ended whole.

```
# forsgren pulls bot filled v1
repository,filled_at
acme/app,2026-10-27T06:00:00Z
```

- `filled_at` is the start of the run that finished the repository's fill, in
  UTC, to the second. Lines are sorted by repository.
- `data/pulls.csv` stays append-only with the first line staying: the fill
  changes the `bot` column of the lines it read and nothing else, and writes
  the file whole once, only when a line changed (a file of the version 1 is
  written once as version 2).
- A pull request GitHub answers 404 or 410 for is named on stderr and stays
  unknown; it does not keep the repository from being noted.
- A missing permission (403) stores what was filled, notes no fill, writes the
  denied mark of the pull request read and fails nothing. At the request budget
  what was filled is stored, no mark is written, the repository is reported
  incomplete, never failed (a `pulls-bot-fill-cut` line in the cut report and
  `acme/app history fill cut short (the next run continues)` on the job
  summary's Collected line), nothing else of the run is held back (it runs
  after the push read), and the next run continues with the pull requests still unknown. Any other error
  fails the repository, after what was filled is stored.
- Rewritten whole like `data/reach.csv`, and only when a line changed. A
  missing file notes no repository. An unknown version or a malformed line
  refuses the collect run, naming the file.
- The data guard knows its name: a `pulls_bot_filled.csv` that the repository
  tracks or does not ignore, outside `testdata/` blocks the commit, like the
  other data files.

### Commit files (forsgren#496)

A service with `paths` (see [Configuration](configuration.md)) counts only
the commits that touch them, so `collect` keeps the files each deployed commit
changed in `data/commit_files.csv`, next to the history (the commit files
format v1, package `internal/history`, columns `repository,sha,path`):

```
# forsgren commit files v1
repository,sha,path
acme/app,0123456789abcdef0123456789abcdef01234567,api/main.go
acme/app,0123456789abcdef0123456789abcdef01234567,web/old.go
```

- One line per file a commit changed; a rename has a line for the new name and
  one for the previous name. A path is relative to the repository root, never
  the content of a file.
- A commit that was read and changes no file is one line with an empty path, so
  it is not read again; a commit with no line has not been read yet. A commit
  GitHub lists with more than 3000 files is stored as read, and named on stderr.
- It costs one `GET /repos/{owner}/{repo}/commits/{sha}` per commit, the request budget
  reserved first, newest deployment first. Every stored commit of
  `data/commits.csv` is read, not only those of the DORA window, so a wider
  `dora_days` later finds them read. The files are read last for a repository,
  after the fresh data: its deployments, issues, pull requests, the fills, the
  legacy backfill and the push read are stored first, so the first fill of a big
  installation, which can cost thousands of requests over several daily runs,
  never holds back fresh data. It runs only for a repository with a service that
  has `paths`; any other repository costs no request.
- Lines are held by repository (ignoring case), commit SHA and path, new lines
  sorted by them; the file is appended to, never rewritten.
- A missing `contents: read` permission (403) stores what was read, says so on
  stderr and fails nothing; it writes no denied mark. At the request budget what
  was read is stored, the repository is reported incomplete, never failed (a
  `commit-files-cut` line in the cut report and `acme/app commit files cut
  short (the next run continues)` on the job summary's Collected line), and the
  next run continues with the commits still without lines. A commit GitHub no
  longer has (history rewritten) is named on stderr and stays unread. Any other
  error fails the repository, after what was read is stored.
- A missing file is none, so every commit of a service with `paths` is unread.
  An unknown version or a malformed line refuses the collect run and the
  render, naming the file.

**The commit files mark** is kept in `data/commit_files_filled.csv`, next to
the history, in its own format (the commit files filled format v1,
`repository,filled_at`, a mark file like `data/reach.csv`): one line per
repository for which a run found every stored commit read, the one-time fill
done. It does not stop a commit stored later from being read.

- The data guard knows both names: a `commit_files.csv` or a
  `commit_files_filled.csv` that the repository tracks or does not ignore,
  outside `testdata/`, blocks the commit, like the other data files.

## Collecting deployments (`collect`)

```
FORSGREN_TOKEN=<token> forsgren collect --config forsgren.config.yml --data data/deployments.csv [--token-expiry <path>] [--cut-report <path>]
```

`collect` reads, for every repository in the config, that repository's
deployments from GitHub's REST API by its `deployment` rule (what a
repository must hold for each rule, and how to check it, is in
[Giving a repository the deployments forsgren counts](configuration.md#giving-a-repository-the-deployments-forsgren-counts)),
and appends the
final ones to the history (see [History](#history)), the commits of each new
successful one to `data/commits.csv` next to it, the repository's
failure issues to `data/failures.csv` next to it, and the events of all its
issues to `data/issues.csv` next to it and which of them carry the `bug` label to
`data/issue_bugs.csv` (see [Issue events](#issue-events-forsgren76) below). It prints one line per
repository, `acme/app: 3 new, 1 skipped (not final), 12 commits`: `new` is
what was appended, `skipped (not final)` is what is still running and is
stored by a later run, `commits` is the commits stored for the new
deployments. A deployment already in the history is skipped without a
count. When it stored failure issues the line goes on with
`, 2 failure issues`, the issues new or changed since the last run, and when
it stored merged pull requests with `, 4 merged pull requests`: the pull
requests newly stored by this run, never the repository's total, and nothing
when it stored none (decision #311; see The merged pull requests below).

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
`history_days` (365), see [Configuration](configuration.md#configuration) (forsgren#57).

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
  file that is renamed over it, and only when a reach moved or a row is added. It is needed
  because the oldest stored deployment cannot tell a quiet stretch from one
  that was not read yet. An installation that has none starts each repository
  with stored deployments at its oldest stored deployment: everything since
  was read by the runs so far. When that deployment is already as far back as
  `history_days` there is no older chunk to read, and the run still notes it
  as the repository's reach (forsgren#196, from 1.8.0), so the History page
  has a row for every repository after one run. `render` and `collect` compare
  repository names ignoring case.
- `render` reads `data/reach.csv` too, for the History page (forsgren#68,
  from 1.8.0): a period shows a row's numbers only when every repository of
  the row was read back to the period's start; a repository with a later
  reach, or with no row in the file yet, makes that row a dash in that period,
  and a period no row has data for is left out. A missing file is no reach
  at all, so the History page says it has no history to show yet; a file
  with another format version or a malformed line fails the render with
  its message (exit 1), like the other files `render` reads.
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
in `data/commits.csv`, each with its author date, its author's GitHub login
(empty when GitHub links the commit to no account; forsgren#273), the
deployment's `created_at`, its parents in GitHub's order, the first parent
first, and its committer date (empty when GitHub gives none; forsgren#254).

- **A stream** is a repository's deployments by one rule with the same
  environment or workflow and the same `task`: a repository deploying
  `deploy-api` and `deploy-admin` to production measures each against its
  own previous deployment. A release's task is its tag, a new one with
  each release, so a repository's releases are one stream. Repository
  names are compared ignoring case.
- **Several rules** (forsgren#498). A repository written with `deployments:`
  has one stream for each rule: `collect` reads each rule on its own, one
  after the other, and stores what they read together. With `deployments:` a
  stored deployment belongs to the rule with its kind and name (`environment`
  and its environment, `workflow` and its file, or `release`), which is how the
  page finds the deployments of a rule's row; the history format does not
  change. The repository has one reach in `data/reach.csv`, so it moves to the
  latest reach the rules give, and a rule just added is read from its first
  chunk.
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
  line of its record block (body, else comments) are stored (see [History](#history)). An issue already stored is
  stored again only when one of them changed: closed, or reopened.
- **The record block is read from the issue's body, then its comments** (forsgren#37), the lines
  `failure-start:`, `failed-build:` and `fixed-build:` alone on their
  line, as forsgren#6 rules. `failure-start` is read as ISO 8601 with an
  offset, to the minute (`2026-09-20T09:12+02:00`) or the second; a body
  without one, or with a time in another form, stores the issue with an
  empty `failure_start` and a warning: `collect: acme/app: failure issue
  #43 has no failure-start line forsgren can read in its body or its
  comments`, once, when the issue is first stored (not again when it is
  closed or reopened). The body wins: when it has a `failure-start`, the
  comments are not requested, and a newer block in a comment does not
  override it. Otherwise the issue's comments are read, one request, every
  page up to the limit, oldest first, and the first comment with a
  `failure-start` is the block (the lines of different comments are never
  combined); a list cut at the page limit is named on stderr. A refused read
  of the comments fails the repository like the other reads, never an empty
  `failure_start`. An issue is looked at again only when it is listed again,
  that is when its update time moved (a new or edited comment included). The
  issue counts all the same: change fail rate needs only when it was opened.
- A list cut at the page limit is stored and named on stderr: `collect:
  acme/app: read the newest 10 page(s) of failure issues only; older ones
  were not read`.
- **Not verified against live GitHub.** That `since` filters by the update
  time, and that a pull request is any item with a `pull_request` field,
  come from GitHub's REST reference and are pinned against made-up answers
  only.

**Withdrawn failure issues** (forsgren#155). The daily read of every issue
(see [Issue events](#issue-events-forsgren76)) also lists an issue whose
labels changed, since that updates it. A stored failure issue it lists
without the `failure` label (compared ignoring case) is withdrawn as
`label_removed`; one it lists closed as not planned is withdrawn as
`not_planned`; a withdrawn issue it lists again as a failure is reinstated.
This adds no request. The lines are written with the repository's other
issue lines, after its failure issues, and a `failures_withdrawn.csv` that
cannot be written fails the repository, so its deployments are not stored
either.

- **The one-time catch-up.** An installation from before forsgren#155 has
  stored failures that may have lost their label long ago, which no `since`
  list shows again. The first run that finds no `failures_withdrawn.csv`
  therefore re-reads each stored failure issue that can still count, open or
  opened in the DORA window (`dora_days`: the last 30 days unless the config
  sets 90 or 180, forsgren#178), and not already in that run's daily read:
  `issues/{number}`, one request per issue, once per installation. Its
  cost is one request per such issue (an older closed failure no longer
  counts and is not asked). An issue GitHub answers 410 for, or 404 once the
  repository's own issue list was read in the same run, is withdrawn as
  `issue_gone`; any other error, a 403 or the rate limit among them, fails
  the repository. What the catch-up finds is held until the end of the run
  and written only when every repository succeeded, which creates the file,
  even with no line, so the catch-up is not done again; a run that failed
  anywhere writes no withdrawals at all, and the next run does the catch-up
  again.
- The catch-up reads the window in force when it runs. An installation that
  already ran it and later widens `dora_days` gets no second catch-up: a
  failure issue opened 31 to 180 days ago that lost its label before 1.4.1
  and that the daily read no longer lists stays counted. This is rare: it
  needs a withdrawal before 1.4.1 on an issue older than 30 days.
- Outside the catch-up, an issue that is deleted or transferred is not seen
  as gone: GitHub no longer lists it, so it keeps counting as its stored
  lines say (see the known limits of the issue events).

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

**The request budget (forsgren#64).** GitHub says on every answer how many
requests the token has left (`X-RateLimit-Remaining`), how many it gets an
hour (`X-RateLimit-Limit`) and when that starts over (`X-RateLimit-Reset`).
When fewer than max(100, 5% of the limit) are left, 250 for a token with 5,000
an hour, `collect` starts no further request, so the rest of the hour is left
to the run's last steps (the render, the release and pull request lookups) and
to anything else using the token. The repository it was reading is cut short,
and stderr says so with the reset time, `collect: cut short: acme/app: GitHub's
request budget is nearly used (80 of 5000 left); it resets at
2026-10-01T01:00:00Z`. Every repository after it is cut short the same way,
before its first request, because the budget is the token's. The repositories
already done keep what they stored, and the run exits 0: a run that meets the
limit is not a failure. A request GitHub refuses with none left is not this: it
stays a failed repository, as above, and GitHub's two limits are named apart
(forsgren#64, step 3): the primary one, `GitHub's primary rate limit is reached;
it resets at <UTC>`, and the secondary one, a `Retry-After` or a 429 that says
nothing else, `GitHub's secondary rate limit is reached; GitHub asks to retry
after <n> seconds`. Neither is the budget's cut, and both are still a rate
limit (`ErrRateLimit`) for a caller that treats them alike.

A repository cut short keeps what it read whole (forsgren#64, decision #239).
Lists come newest first, so a cut leaves the newest days read. A deployment
counts as read only with its statuses and, for a success, its commits
comparison, and each UTC calendar day only when all its deployments do. So the
statuses are read only while the budget has room left for the comparisons of
the successes read so far, the comparisons are sent newest first, and what is
stored is every day after the day of the item the budget stopped at: its
deployments and their commits (no commit twice: a success compared again on a
later run adds nothing, the commits file skips it). The read mark
(`reach.csv`) moves only to the start of the oldest such day, for the first
chunk and the older chunk. The day the cut fell in, and everything older, is
read again by the next run. Nothing else moves: a cut that keeps no day moves
no mark, and each run names the repository as cut short, so a repository that
cannot advance is visible, never mistaken for progress. A cut in the recent
read (what is new since the last run) of a repository with a read mark keeps
its whole days only while the next run's window, which starts 7 days before
the newest deployment stored, still reaches the oldest deployment that was not
read, which is newer than the newest one stored before the run; otherwise it
stores none of it and the next run reads it again. A deployment read later
that lies between two stored successes gets no commits and a warning, so no
commit counts twice. A cut in the read of the issues, which is stored whole or not
at all with the marks that say it was read (`failures_read.csv`,
`issues_full.csv`, `issue_bugs_cut.csv`), keeps the deployments and moves
none of those marks. The one-time withdrawn-failures catch-up waits until no
repository was cut short or failed.

A repository progresses on every run as long as one day of its history fits in
the budget. A chunk with a single day that needs more than about 4,750
requests (about 2 per deployment: its statuses and its comparison) is never
finished; the way out is a smaller `history_chunk_days`, which makes the
chunk read per run smaller.

**The merged pull requests** (forsgren#255). After a repository's
deployments and issues are stored, `collect` reads its closed pull requests
updated since its line in `data/pulls_read.csv` less a day, newest updated
first, and stores the merged ones in `data/pulls.csv` (see
[History](#history)), each with its first commit time from its commits, and
those commits in `data/pull_commits.csv` (see [History](#history)), written
before the pull request's own line.

- A pull request closed without a merge, merged before `history_days` back
  (even when it was updated inside it, decision #310), or already stored is
  not asked for its commits and not stored.
- A pull request's commits are read only while the request budget has room
  for all their pages (3 at most). At the budget the pull requests read whole
  are stored and the mark stays, so the next run reads the rest; one whose
  commit list the budget would stop is not stored and is read again next run
  (decision #308). Its deployments and issues are already stored, so the
  repository is reported as incomplete, never failed: a `pulls-cut` line in
  the cut report (see below) and `acme/app pull requests cut short
  (deployments and issues read)` on the job summary's Collected line
  (decision #307).
- The created time stands in for the first commit time in two cases, each
  named on stderr: the commit list gives no usable date (no commit, or a
  commit without an author date), or a commit page forsgren cannot read,
  whose warning names the repository and the pull request, `collect: acme/app:
  pull request 14: the answer for its commits is malformed or unreadable`
  (decision #313). A server error, a rate limit or a 403 is never a stand-in:
  a 403 is the missing permission below, and the others fail the repository
  as the last point says. A cut list keeps its time with `first_commit_cut`.
- **Without the pull requests permission** (a 403 that is not the rate limit)
  nothing fails: the pull requests read so far are stored, the mark stays,
  stderr names the missing permission and the rest of the repository is
  collected (Yves's ruling on #255). The setup issue names it (see
  [The setup issue](updating-and-releases.md)). The repository gets a line in
  `data/pulls_denied.csv` (see [History](#history)), so the TBD page says its
  pull requests are not readable instead of showing none (forsgren#337).
- A list cut at the page limit is an incomplete read: stderr says so, and
  that older pull requests may be skipped for good, since the mark moves (the
  list is newest first, so the same mark would read the same pages again;
  decision #309).
- Any other error fails the repository, after its deployments and issues are
  stored.

**The pushes to main** (forsgren#397). After a repository's deployments,
issues and pull requests are stored, `collect` reads the activity of its
default branch (`GET /repos/{owner}/{repo}/activity?ref=refs/heads/<branch>`,
newest first) since its line in `data/pushes_read.csv` less a day, and stores
the pushes, pull request merges and force pushes in `data/pushes.csv` (see
[History](#history)), each with the number of commits it added to the
first-parent chain from the compare of its two tips, and every commit of that
compare, the branch commits of a merge too, in
`data/push_commits.csv` (see [History](#history)). A push already stored is
not compared again.

- A compare that fails or is cut leaves `commits` empty and is named on
  stderr, with the repository and the two tips; it never fails the repository.
  A force push is stored without a compare.
- **Without the contents permission** (a 403 that is not the rate limit)
  nothing fails: stderr names the missing permission, the mark stays, and the
  repository gets a line in `data/pushes_denied.csv` with the name of the
  token that was refused (see [History](#history)). The setup issue names the
  refused token and its fix as an item (see
  [The setup issue](updating-and-releases.md#the-setup-issue-check-needs)).
  Contents (read) is the permission every rule already needs for comparing
  commits (GitHub's reference lists it for the repository activity list, for
  fine-grained tokens and for the job token alike), so an installation that
  collects deployments has it already.
- At the request budget the pushes compared so far are stored and the mark
  stays, so the next run reads the rest; the repository is not failed, and a
  `pushes-cut` line of the cut report says so (see below). A
  first read of a busy repository costs one compare request per push.
- A list cut at the page limit is an incomplete read: stderr says so, and
  that older pushes may be skipped for good, since the mark moves.
- Any other error fails the repository, after its deployments, issues and
  pull requests were stored.
- The branch read is the repository's default branch, asked of GitHub once
  per repository and run (the `workflow=` rule shares the request).

**The history fill** (forsgren#470). Data stored before forsgren#463 lacks
what the Mainline Lead Time needs: the commit lists of merged pull requests
and the branch commits of merge pushes. `collect` fills both once per
repository, for everything stored, not only the DORA window, so a wider
`dora_days` later finds them too. It is noted per repository in the two fill
marks (see [History](#history)).

- **The pull requests' commits**, after the merged pull requests are read:
  each stored pull request of the repository with no line in
  `data/pull_commits.csv` and a real first commit time gets its commit list
  read (the budget reserved first, as for a new pull request) and its lines
  appended. A list GitHub answers unreadably is named on stderr and left
  without lines.
- **The merge pushes' lines**, after the legacy commits backfill and before
  the push read: each stored `pr_merge` push with a line of unknown parents in
  `data/push_commits.csv` is compared again (one request each; pushes that
  share a tip are compared once) and its lines are replaced. A compare that
  fails, is cut or does not reach the push's tip leaves its lines as they are,
  named on stderr.
- A missing permission (pull requests, or contents for the compares) stores
  what was filled, writes the denied mark as the read would, and fails
  nothing.
- At the request budget what was filled is stored, no fill mark is written
  and the repository is reported incomplete, never failed: a
  `pull-commits-fill-cut` or `push-commits-fill-cut` line in the cut report
  (see below) and `acme/app history fill cut short (the next run continues)`
  on the job summary's Collected line. A merge push fill cut short also
  leaves the push read to the next run, so no request is sent after it.
- Any other error fails the repository, after what was filled is stored.

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

Every rule also reads the repository's merged pull requests, for the
PR Lead Time (forsgren#255, from 1.15.0), which needs Pull requests
(read) as well. A token without it fails nothing: `collect` stores everything
else and names the missing permission on stderr (see The merged pull
requests above). The setup issue cannot see a fine-grained token's
permissions, so it gives no item for one without Pull requests (read), and it
never claims the pull request read works (decision #314; see
[The setup issue](updating-and-releases.md#the-setup-issue-check-needs)). An installation whose caller passes the run's own token as
`FORSGREN_TOKEN` (every measured repository public, route A of
[agent-installer.md](../agent-installer.md)) has the permissions its caller's
job grants, so there the caller's `pull-requests: read` is that permission.

Comparing two commits, for the commits of each deployment, needs Contents
with every rule. A token without it fails the repository from its second
successful deployment on, with `check FORSGREN_TOKEN's access`, when
GitHub answers 401 or 403; a 404 would read as a commit GitHub does not
have and skip each deployment with a warning instead (not verified against
live GitHub, see above). Metadata is
in every fine-grained token. A classic token needs `repo` for
private repositories (no scope for public ones).

**The cut report** (forsgren#64, step 3b). With `--cut-report <path>`,
`collect` writes what the run left incomplete, for the job summary to say that
a green run is not the same as a complete history. `collect` removes the file of an earlier
run before anything else, and writes none for a run it refused (an unreadable
history), so no file is unknown, never complete. The file is text:

```
# forsgren collect report v1
incomplete resets=2026-10-01T01:00:00Z
cut acme/app kept=2026-06-22 recent=discarded issues=unread progress=stalled
pulls-cut acme/shop
backfill-cut acme/lib
pushes-cut acme/api
pull-commits-fill-cut acme/lib
push-commits-fill-cut acme/lib
pulls-bot-fill-cut acme/lib
failed acme/web secondary-rate-limit
```

- The second line is `complete`, or `incomplete resets=<UTC RFC 3339>` when
  any repository, its pull requests, its backfill of the legacy commits, its
  pushes or one of its history fills was cut short at the request budget.
- A `cut` line names such a repository: `kept` is the UTC day its read mark
  moved to (`none` when it kept no day), `recent` what became of the read of
  what is new (`read` whole, `kept` in part, `discarded`), `issues` is always
  `unread` (a cut repository stores nothing of its issues, and its pull
  requests are not read either) and `progress` is `yes` when it kept
  something, `no` the first run it kept nothing, and `stalled` when it kept
  nothing again (the cut runs note above). The job summary says `issues and
  pull requests not read` for it (decision #327).
- A `pulls-cut` line names a repository whose deployments and issues were
  read whole but whose pull requests the request budget cut short:
  incomplete, never failed, and the rest is read by the next run (decision
  #307).
- A `backfill-cut` line names a repository whose deployments, issues and pull
  requests were read whole but whose backfill of the legacy commits the
  request budget cut short (forsgren#385): incomplete, never failed, and the
  job summary says `acme/lib legacy commits cut short (deployments, issues and
  pull requests read)`. What it filled is stored, and the next run continues.
- A `pushes-cut` line names a repository whose deployments, issues and pull
  requests were read whole but whose pushes to the default branch the request
  budget cut short (forsgren#397): incomplete, never failed, and the job
  summary says `acme/api pushes cut short (deployments, issues and pull
  requests read)`. The pushes compared are stored, and the next run reads the
  rest.
- A `pulls-bot-fill-cut` line names a repository whose one-time fill of the
  bot status of the stored pull requests the request budget cut short
  (forsgren#500): incomplete, never failed, and the job summary says `acme/lib
  history fill cut short (the next run continues)`. What was filled is stored,
  and the next run continues.
- A `pull-commits-fill-cut` and a `push-commits-fill-cut` line name a
  repository whose history fill of the stored pull requests' commits, or of
  the stored merge pushes' lines, the request budget cut short (forsgren#470):
  incomplete, never failed, and the job summary says `acme/lib history fill
  cut short (the next run continues)`. What was filled is stored, and the
  next run continues.
- A `failed` line names a repository that failed: `primary-rate-limit`,
  `secondary-rate-limit` or `error`.

**The token's expiry date** (forsgren#177). GitHub names a token's expiry
date in every answer. Only the answers to `FORSGREN_TOKEN` count. An answer
without the date keeps the one an earlier answer of the run named, and a
date forsgren cannot read is ignored, with one `collect: note:` line on
stderr per run. With `--token-expiry <path>`, `collect` writes that
date to the file, as one UTC RFC 3339 line such as `2027-01-12T08:35:47Z`.
`check-needs` and `run-summary` read it from there. `collect` removes the file of an earlier
run before anything else, so a run that fails (no token, a refused token, a
bad config) leaves none and `check-needs` sees an unknown date, never an old
one. Without a date the file holds one word instead (forsgren#194):
`no-expiry` for a token that answered without an expiry date,
`no-expiry run-token` when that token is the job's own (it starts with
`ghs_`, and nothing else of the token is looked at or written), and
`unreadable` for a token that answered with an expiry header forsgren cannot
read and no date it can (the `collect: note:` line shows it; the file does not repeat it). A
token that never got an answer leaves no file. `check-needs` reads every
word, and no file, as an unknown date; `run-summary`'s Token line tells the
four apart (see [Running forsgren](configuration.md#running-forsgren)). The file is written
whole (beside it, then renamed over it). A file that cannot be written or
removed fails the run. From 14 days before the date, and once it has passed, `collect` also
warns on stderr: a `collect: warning:` line that names the date and the
command `gh secret set FORSGREN_TOKEN -R <owner/name>` to set a new token.
The warning never changes the exit code.

### Issue events (forsgren#76)

Besides the failure issues, each run reads the issues of the repository,
whatever their labels (`Client.Issues`: `issues?state=all&since=`, 100 per
page, pull requests left out, up to the page limit), and appends their
events to `data/issues.csv` (see [History](#history)). It asks since the same time as
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

An event already stored is skipped (see [History](#history)), so reading the same issues
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
stored is skipped (see [History](#history), Bug flags). If the list stopped at the
10,000 issues cap, stderr says so (`the bug read stopped at 100 page(s) of
issues; the stored bug flags are kept`), what was read is stored and no flag is
removed, because an issue it did not reach may still carry the label; the run
goes on, and the repository is noted in `data/issue_bugs_cut.csv` (see
[History](#history), The bugs cut note), so the Open bugs column shows
`— (incomplete)` until a later run reads its bug list in full and removes the
note (forsgren#140). A refused list (GitHub errors) fails the repository, like a refused
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
  too: a warning, and every Open bugs cell shows `— (incomplete)` instead of a
  number until a complete bug read (forsgren#140).
