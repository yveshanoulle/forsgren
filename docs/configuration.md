# Configuration

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
  other value is not accepted: forsgren uses the default instead and says so (see
  [A setting that is not accepted](#a-setting-that-is-not-accepted)), naming the key and
  the valid values: `invalid view "Numbers": use standard, numbers or scoring`. Each
  view is also its own page at `/standard/`, `/numbers/` and `/scoring/`, whatever this
  key says. The starter that `init-config` writes for a new installation
  includes `view: standard` (forsgren#51), so a new installation's menu
  marks its view from its first run; an existing config without `view:` keeps
  the plain root, as `init-config` never rewrites an existing file. The starter
  also writes `auto_update: true` and `auto_update_level: major` (forsgren#58,
  #150), so a new installation merges forsgren's releases by itself, a major
  one included. `auto_update_level` is optional: left out, it defaults to
  `major` (forsgren#157), and the legend explains each level (forsgren#156); an existing config without `auto_update:` keeps it off (see [Auto-update](updating-and-releases.md)).
- **`history_days`** is optional (forsgren#57): how deep a repository's
  history goes, in days, a whole number from 30 to 1825 (5 years), written at
  the top level, for example `history_days: 730`. Left out, or without a
  value, it is 365. Anything else (less than 30, more than 1825, a quoted
  value, a decimal or text) is not accepted: forsgren uses the default instead and says so (see
  [A setting that is not accepted](#a-setting-that-is-not-accepted)),
  naming the key and the limit: `invalid history_days "1826": use a whole
  number of days from 30 to 1825`. Up to 1.5.x the least was 1; from 1.6.0 a
  value under 30 is not accepted and 365 is used (forsgren#178), so the
  default DORA window of 30 days always fits. forsgren does not read that far at once:
  a repository's first run reads one chunk (`history_chunk_days`), and each
  later run reads what is new plus one older chunk, until the history reaches
  `history_days` back (see [Collecting deployments](data-files.md#collecting-deployments-collect)). It is also the most any
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
  text) is not accepted: forsgren uses the default instead and says so (see
  [A setting that is not accepted](#a-setting-that-is-not-accepted)), naming the key and the
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
  `8.5` or `8.0`, or text) is not accepted: forsgren uses the default instead and says so (see
  [A setting that is not accepted](#a-setting-that-is-not-accepted)), naming
  the key and the limit: `invalid working_hours "25": use a whole number of
  hours from 1 to 24`. The on-demand threshold of deployment frequency uses
  it, and the legend says the working day in use. The starter that
  `init-config` writes includes `working_hours: 8`.
- **`dora_days`** is optional (forsgren#178): the DORA window, how many days
  back all five DORA metrics count (deployment frequency, lead time for
  changes, failed deployment recovery time, change fail rate and deployment
  rework rate), one of `30`, `90` or `180`, written at the top level, for
  example `dora_days: 180`. Left out, or without a value, it is 30, so nothing
  changes until an installation sets it; DORA usually reports the last six
  months, 180 days. The window needs that much history: `history_days` must be
  at least the window (the default 365 is enough for all three). Anything else
  (`60`, `0`, `365`, a quoted `"90"`, `90.0` or text) is not accepted: forsgren uses the default instead and says so (see
  [A setting that is not accepted](#a-setting-that-is-not-accepted)), naming
  the key and the valid values: `invalid dora_days "60": use 30, 90 or 180`;
  so is a window longer than `history_days`: `invalid dora_days "180":
  history_days is 90, so the history cannot reach back 180 days; raise
  history_days to at least 180 or use a shorter window`. The deployment
  frequency bands keep DORA's rates: their edges are given per 30 days and
  scale with the window (at 8 hours, 1, 5, 30 and 241 in 30 days; 3, 15, 90
  and 721 in 90 days; 6, 30, 180 and 1441 in 180 days), and a project younger
  than the window has its count scaled to the window. The 180-day count that
  tells the two slowest bands apart stays 180 days. The legend says the
  window in use, and whether `dora_days` sets it. `collect`'s one-time
  catch-up of withdrawn failure issues re-reads the failures of this window
  (see [Collecting deployments](data-files.md#collecting-deployments-collect)).
  The days and issues pages keep their own periods. The starter that
  `init-config` writes includes `dora_days: 30`.
- **The page keys** `issues_page`, `days_page`, `numbers_scoring_page`,
  `history_page` and `tbd_page` are optional (forsgren#159, #55, #68, #200,
  from 1.8.2; `tbd_page`, forsgren#253):
  each says how one optional page is handled, written at the top level, for
  example `history_page: true`. Each takes one of three values:
  - `true`: the page is generated and has an entry in the menu.
  - `unlisted`: the page is generated, but it has no entry in any menu,
    its own included, and it carries `<meta name="robots" content="noindex">`.
    It can be opened by its address, so you can look at a page before you
    list it. Unlisted is discoverable, not private: noindex asks compliant
    search engines not to index the page; it does not enforce access control.
    Anyone who knows or guesses the address can open it.
  - `false`: the page is not generated, is removed from the site (with its
    folder, for the Numbers and scoring page) if an earlier run wrote it, and
    has no entry in the menu.

  Left out, or without a value, `issues_page` is `true`, `days_page` is
  `false`, and `numbers_scoring_page`, `history_page` and `tbd_page` are
  `unlisted` (forsgren#200, from 1.8.2; before 1.8.2 both were `false`, see
  [Installing and updating](updating-and-releases.md#installing-and-updating)).
  These built-in defaults are not the starter's values: a new installation
  starts with the Issues page off, because the starter writes
  `issues_page: false` (forsgren#285), while an installation whose config
  leaves `issues_page` out keeps its Issues page, so no page disappears after
  an update without the owner asking for it.
  Only the plain literals `true`, `unlisted` and `false` are accepted; a
  quoted value, `yes`, a number or other text is not accepted: forsgren uses
  the key's default instead and says so (see
  [A setting that is not accepted](#a-setting-that-is-not-accepted)), naming
  the key: `invalid days_page "yes": use true, unlisted or false`. The
  noindex tag is only ever on an unlisted page: switching a page back to
  `true` removes it. A render without a config writes and lists every page.
  The legend explains the three values and the defaults. The starter that
  `init-config` writes includes `issues_page: false`, `days_page: false`,
  `numbers_scoring_page: unlisted`, `history_page: unlisted` and
  `tbd_page: unlisted`. The pages:
  - **`issues_page`**: the Issues page (`issues.html`, forsgren#159).
  - **`days_page`**: the Daily page (`days.html`, forsgren#159). From 1.3.0
    an installation that does not set `days_page` has no Daily page.
  - **`numbers_scoring_page`**: the Numbers and scoring page
    (`/numbers-scoring/`, forsgren#55, from 1.7.0). It shows each metric's
    number and its score in one cell, written number · score, and the Overall
    Performance column (see [The page](pages-and-views.md#the-page));
    `view:` does not name it, so the root page never shows it.
  - **`history_page`**: the History page (`history.html`, forsgren#68, from
    1.8.0), marked beta. It shows the five metrics and Overall Performance
    per period, the calendar half-years that `history_days` reaches back and
    the last 6 months (see [The History page](pages-and-views.md#the-history-page));
    `dora_days` does not change it. In 1.8.0 it defaulted to `true` and in
    1.8.1 to `false`.
  - **`tbd_page`**: the TBD page (`tbd.html`, forsgren#253). It shows the
    Mainline Interval of each project, the mean and the sample standard
    deviation of the time between commits that deployments shipped, from
    `data/commits.csv`, over the `dora_days` window, each deployment's
    first-parent chain at the committer date (forsgren#254), and next to it the
    number of developers who made those commits (forsgren#273; see
    [The TBD page](pages-and-views.md#the-tbd-page)); the legend explains both
    and says that Mainline Lead Time is not on the page yet.
- **The settings page** (`settings.html`, forsgren#74, moved out of the legend
  in forsgren#84, a table since forsgren#141) tabulates every optional key,
  `view`, `auto_update`, `auto_update_level`, `history_days`,
  `history_chunk_days`, `working_hours`, `dora_days`, `issues_page`, `days_page`, `numbers_scoring_page`, `history_page` and `tbd_page`, twelve rows in four columns: **Parameter**;
  **Current value**, the value in use (`major` for an unset
  `auto_update_level`); **Possible values**, built from the config package's
  own constants and limits so the page cannot drift from what `check-config`
  accepts (`standard, numbers, scoring`; `true, false`; `patch, minor, major`; `30 to 1825`; `1 to 365`; `1 to 24`; `30, 90, 180`; `true, unlisted, false` for each of the five page keys),
  a test holds the lists to the config loader; and **Default**, the value
  used when `forsgren.config.yml` does not set the key (forsgren#169):
  `standard`, `false`, `major`, `365`, `100`, `8`, `30`, `true`, `false`,
  `unlisted` and `unlisted`, in the order of the rows. A
  Current value followed by `(not set)` means the file does not set the key,
  so the default applies; a Current value without it is set in the file, even
  to the default's value. For a value that is not accepted the Current value
  says so, with no `(not set)`: `60 is not accepted: use 30, 90 or 180. Using
  the default 30.`, and Default shows that default (forsgren#183). The legend
  explains the Default column and `(not set)`.
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
record block (see [How it gets its data](data-files.md#how-it-gets-its-data)); lead time runs from a change's first
commit. Neither is configured per repository in version 1.

### A setting that is not accepted

A setting with a default (`view`, `auto_update`, `auto_update_level`,
`history_days`, `history_chunk_days`, `working_hours`, `dora_days`,
`issues_page`, `days_page`, `numbers_scoring_page`, `history_page` and `tbd_page`) whose value forsgren
does not accept, a list or
a mapping included, does not stop the run (forsgren#183): forsgren uses that
key's default instead, and says so in three places. The settings page's row
for the key shows the value as written, that it is not accepted and why, and
the default in use. `render`, `collect` and `check-update` write one warning
line per such key on stderr, so in the workflow's log: `config: warning:
forsgren.config.yml: invalid dora_days "60": use 30, 90 or 180; using the
default 30`. `check-config` writes the same warnings, adds `, settings not
accepted: N` to its OK line and exits 0. Up to 1.5.x such a value stopped
the run.

What has no default still stops the run, and `check-config` exits 1 with the
refusal: a file that cannot be read or is empty, YAML that does not parse,
a missing or unsupported `version`, any key forsgren does not know, a second
YAML document in the file, and every mistake in the projects, repositories,
deployments and labels; so a typo never silently does nothing. Every refusal
names the file, the project and repository it is in (or the line, for a
YAML error) and what to write instead, on one line: a line break in a key
or value it quotes is written as `\n`.

Check a config without rendering anything:

```
forsgren check-config --config forsgren.config.yml
```

It prints one line, `OK: forsgren.config.yml is a valid forsgren config
(version 1): projects: 2, repositories: 3`, with `, labels: 4` added when
the file labels rows and `, settings not accepted: 1` when a setting falls
back to its default (with its `config: warning:` line on stderr), and exits
0; it exits 1 with the refusal on stderr when the file is invalid or cannot
be read, and 2 on a usage error.

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
`auto_update_level: major`, `history_days: 365`,
`history_chunk_days: 100`, `working_hours: 8`, `dora_days: 30`,
`issues_page: false`, `days_page: false`, `numbers_scoring_page: unlisted`,
`history_page: unlisted`, `tbd_page: unlisted` and `projects: []`, so
`check-config` accepts it as it is: `projects: 0, repositories: 0`. When the file exists,
whatever it holds (even an invalid or an empty file), it is left byte for
byte and the command prints `kept forsgren.config.yml`; both exit 0. The file
is written whole or not at all, and a file that appears while the command
runs is never replaced. The directory must exist: `init-config` does not
create one, so a mistyped directory is an error. It exits 1 with
`init-config: <path>: <reason>` on a real error (the directory is missing or
not writable, or the path is a directory), and 2 on a usage error. The
metrics workflow runs it on every new install (see [Running forsgren](#running-forsgren)).

## Running forsgren

forsgren renders a static page whose footer says "Forsgren" and the version of
the forsgren that rendered it, and shows each project's deployment frequency,
lead time for changes, failed deployment recovery time and change fail
rate (and the deployment rework rate); every run writes the page in each view too, at
`/standard/`, `/numbers/` and `/scoring/`, and, unless their key is `false`, the Numbers and scoring page at
`/numbers-scoring/`, the History page at `history.html` and the TBD page at `tbd.html`, all unlisted by
default (see [The page](pages-and-views.md#the-page)). That version has one source,
the `version` variable in `cmd/forsgren/main.go`; a release build can set
it with `-ldflags "-X main.version=<version>"`. `forsgren collect` reads
GitHub into the history file (see [Collecting deployments](data-files.md#collecting-deployments-collect)); the daily run
calls it, commits the history to the data repository and renders the page
with each project's deployment frequency, lead time for changes, failed
deployment recovery time and change fail rate from it (see [Deployment
frequency](pages-and-views.md#deployment-frequency), [Lead time for changes](pages-and-views.md#lead-time-for-changes), [Failed deployment recovery time](pages-and-views.md#failed-deployment-recovery-time) and [Change
fail rate](pages-and-views.md#change-fail-rate)).

The first release is `v0.0.1`. Install a release with
`go install github.com/yveshanoulle/forsgren/cmd/forsgren@v0.0.1`; an
installation pins that version. From a checkout of this repository:

```
./Scripts/build_site.sh            # builds .build/bin/forsgren, renders .build/site
.build/bin/forsgren render --out <dir>
```

`forsgren` with no command, or with one it does not know, prints its usage
on stderr and exits 2. The usage names every command and every flag each
one takes (forsgren#180; `cmd/forsgren/usage_test.go` holds it to the
flags the commands define):

```
usage: forsgren render --out <dir> [--config <path>] [--data <path>]
                       [--latest <version>] [--waiting-pr <number>] [--pr-check <status>] [--needs-check <status>]
       forsgren check-config --config <path>
       forsgren init-config --config <path>
       forsgren install-readme --out <path>
       forsgren collect --config <path> --data <path> [--token-expiry <path>] [--cut-report <path>]
       forsgren latest-release [--published <path>]
       forsgren waiting-pull-request --version <x.y.z> [--status <path>]
       forsgren check-needs --config <path> --repository <owner/name> [--status <path>]
                            [--token-expiry <path>]
       forsgren run-summary --latest <version> --waiting-pr <number>
                            --pr-check <ok|no-access|rate-limited|truncated|failed|skipped> --repository <owner/name>
                            [--needs-check <status>] [--readme <status>] [--token-expiry <path>]
                            [--collect-report <path>] [--latest-published <path>]
       forsgren check-update --config <path> --repo <owner/name> --pull <number>
       forsgren install-update --repo <owner/name> --branch <branch> --version <vX.Y.Z> --sha <40-hex>
```

`forsgren render --out <dir> [--config <path>] [--data <path>] [--latest <version>] [--waiting-pr <number>] [--pr-check <status>] [--needs-check <status>]` writes the site (every page
plus `styles.css`) into `<dir>`, creating it when needed, and exits 0; 1 when
the render failed (or the `--config` file is missing or invalid, with
check-config's refusal), 2 on a usage error. `--latest` is the newest forsgren
release, as `forsgren latest-release` prints it: render itself never calls
GitHub, so it stays testable offline, and a value that is missing, equal, older
or not a version adds nothing to the footer. `forsgren latest-release` reads
forsgren's own public repository's latest release (with `GITHUB_TOKEN` when the
environment has one, without otherwise) and prints its version without the
`v`; when the lookup fails it prints nothing, says why on stderr and exits 0,
since a page without news of a release is not an error. With `--published
<path>` (forsgren#194) it also writes the time the release was published to
`<path>`, one UTC RFC 3339 line such as `2026-10-15T09:00:00Z`, for the run
summary's Update line; a release without a publish time writes nothing, and a
file that cannot be written is one line on stderr, the version still printed
and the exit still 0. `--waiting-pr <number>`
(1 or more, anything below is a usage error; leaving it out means none)
is Dependabot's open pull request for it, as `forsgren waiting-pull-request
--version <x.y.z> [--status <path>]` prints it (the open pull requests of
`GITHUB_REPOSITORY`, read with `GITHUB_TOKEN`; with `--status` it also writes
how the lookup went, `ok`, `no-access` for the 403 of a token without
`pull-requests: read`, `rate-limited` when GitHub's rate limit refused it (a
403 or 429 with no request left, never taken for a missing permission),
`truncated` when the list of open pull requests was longer than forsgren
reads (10 pages) and none of the pull requests read moves the pin, or
`failed`, and its exit status is 0 either way); the
footer then names the pull request instead of "is available". A cut list
with no match is not taken for "none is waiting" (forsgren#203): the
lookup prints nothing, writes `truncated` and says on stderr
"waiting-pull-request: acme/app: the list of open pull requests is cut at 10
page(s), so a waiting pull request cannot be ruled out"; a pull request found
in a cut list is still printed, since the match is conclusive.
`--pr-check <status>` is that `--status`: `truncated`, with no
`--waiting-pr`, makes the footer say "0.3.9 is available; unknown (pull
request list truncated)." instead of "0.3.9 is available."; any other value,
or none, changes nothing, and `--waiting-pr` wins over it.
`--needs-check <ok|no-access|rate-limited|failed>` is how `forsgren
check-needs` went (see [The setup issue](updating-and-releases.md)): anything but `ok` adds "needs more
configuration: see the job summary of this run" to the footer, and leaving it
out or `ok` adds nothing. `forsgren
run-summary --latest <version> --waiting-pr <number> --pr-check
<ok|no-access|rate-limited|truncated|failed|skipped> [--needs-check
<ok|no-access|rate-limited|failed>] [--readme <created|replaced|unchanged|failed>]
[--token-expiry <path>] [--collect-report <path>] [--latest-published <path>]
--repository <owner/name>` prints the run's job summary as markdown, a `## forsgren`
heading and then these lines, in this order: Run, Built with, Latest
release, Update, then Token, Collected, Setup and README, each of the last
four only with its flag:

- `Run:` the moment the summary was written, in UTC to the minute,
  "2026-10-15 15:10 UTC" (forsgren#194), so a summary pasted somewhere says
  when it is from.
- `Built with:` the version that built the page, "forsgren <version>".
- `Latest release:` the newest release, or "unknown" when `--latest` is
  empty or not a version.
- `Update:` where the update stands: "up to date", "0.0.10 is waiting in
  pull request `[#7](link)`", or "0.0.10 is available; " followed by
  "pull-request check skipped: grant pull-requests: read in your caller to
  enable it", "the pull-request check hit GitHub's rate limit, the next run
  tries again", "unknown (pull request list truncated)" for `--pr-check
  truncated` (forsgren#203), "the pull-request check failed", "waiting for the 3-day
  cooldown until 2026-10-18" or "no Dependabot pull request yet"; "unknown
  (the latest release could not be read)" when the latest release is
  unknown. The cooldown (forsgren#194) is the `cooldown: default-days` of the
  first `github-actions` update in the checkout's `.github/dependabot.yml`
  that names one, counted from the publish time in the file `--latest-published`
  names (the one `latest-release --published` wrote), and it ends on the
  UTC date shown. A `github-actions` update with no `default-days` (no
  `cooldown` key at all) has Dependabot's documented default of 3 days
  (forsgren#195); `default-days: 0` is no cooldown. With no such file, no
  `github-actions` update, a cooldown of 0, a time that cannot be read or a
  cooldown that is over, the line says "no Dependabot pull request yet".
- `Token:`, only with `--token-expiry`, from the file `collect` wrote (see
  [Collecting deployments](data-files.md#collecting-deployments-collect)): "valid
  for N more days (until YYYY-MM-DD)" from one day left, "valid for N more
  hours (until YYYY-MM-DD HH:MM UTC)" under a day, "valid for less than an
  hour (until YYYY-MM-DD HH:MM UTC)" under an hour (or once the date has
  passed during the run); for a token with no date to count from, "the
  run's own token (GITHUB_TOKEN), renewed every run; nothing expires", "no
  expiry date: a personal token set to no expiration (or more than a year); a
  date under a year makes forsgren warn before it runs out", "unknown: GitHub
  sent an expiry date forsgren cannot read; see the note in the collect step",
  and, when the file is missing or holds anything else, "unknown: collect
  could not ask GitHub: see the failed collect step".
- `Collected:`, only with `--collect-report`, from the file `collect --cut-report`
  wrote (see [The cut report](data-files.md#collecting-deployments-collect)):
  a green run means collection ran correctly, not that all requested history
  was collected (forsgren#64). "complete" only for a report that says so;
  otherwise "incomplete" with `budget reached;` and each repository cut short
  (how far it kept, `issues not read`, `recent read discarded`, and
  `and not progressing` when it was cut short with nothing kept on
  consecutive runs), the time the budget resets, and each repository that
  failed on GitHub's "primary rate limit" or "secondary rate limit". A missing
  file is "unknown: collect wrote no report: see the failed collect step",
  and a file that is no report "unknown: collect's report cannot be read: see
  the collect step", never complete.
- `Setup:`, only with `--needs-check`: "in place, or the setup issue says
  what is missing" for `ok`, else "the setup issue could not be written"
  with the reason and the steps this version needs (see
  [The setup issue](updating-and-releases.md)).
- `README:`, only with `--readme` (forsgren#110), the word `install-readme`
  printed: "created from forsgren 1.9.0's", "replaced with forsgren 1.9.0's"
  (the version that built the page), "unchanged", or, for the word `failed`
  the workflow's README step records, "not pushed: see the README step"; a
  word it does not know adds no line.

`forsgren install-readme --out <path>` (forsgren#110) writes the
installation README of the running version to `<path>`: the text is built
into forsgren (`install/README.md` in this repository) with the version
written into it, so it describes exactly the version that wrote it. It
prints one word and the path: `created` when there was no file, `replaced`
when there was a different one (a hand-edited README is overwritten),
`unchanged` when the file already holds the text, which it then leaves
untouched, its modification time included. The file is written whole,
through a temporary file in the same directory and a rename; the directory
must exist. Exit 0, 1 when the file cannot be read or written (with the
path), 2 on a usage error.

The pull request is linked: the link is fine there, because a run page is
private to the repository, unlike the public page. A flag it cannot use is a
usage error that prints nothing. With `--config`, a config that
lists no projects makes the page show, in place of the table and besides
"Forsgren" and its version in its footer, a how-to for filling `forsgren.config.yml`;
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
  (see [Configuration](#configuration), #14). A fork calling its own copy installs the fork,
  never upstream.
- **`v0.0.1` predates this.** Its `metrics.yml` still requires
  `with: forsgren-version: v0.0.1` under the `uses:` line; the one-line
  form starts with the next release, which has no such input: drop the
  `with:` block when moving to it.
- **A new install gets a starter configuration.** After the checkout the
  workflow runs `forsgren init-config --config forsgren.config.yml`. When
  the file is missing it is written (`version: 1`, `view: standard`,
  `auto_update: true`, `auto_update_level: major`, `projects: []`, a commented example) and that one file, nothing else, is committed to the
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
- **The README is forsgren's file** (forsgren#110). Right after the
  starter step the workflow runs `forsgren install-readme --out README.md`,
  which writes the README of the version the run is, and the run summary's
  README line says what happened. A created or replaced README, and that
  one file alone, is committed to the branch the run is on as
  `github-actions[bot]`, "forsgren: update README.md", and pushed the way
  the starter is; an unchanged one commits nothing, so a daily run adds no
  commit. **A README you edit by hand is replaced on the next run**: keep
  your own notes elsewhere. A README that cannot be written or pushed does not
  stop the day: on a tag whose README changed, when the branch moved during
  the run ("… moved since this run checked it out"), or when the remote
  refuses the push, the step prints an `::error`, records `readme=failed`
  and goes on, so the configuration check, collect, the data commit and the
  page still run. The local README commit is undone, so the data push
  carries `data/` alone. The job then fails at its end, in "Fail the job
  when the README could not be pushed", and the job summary says "README:
  not pushed: see the README step". Nothing is rebased or forced, and the
  next run writes the README again. No new permission:
  `contents: write` already lets the run push.
- **The daily run checks the configuration first.** The workflow checks out
  the data repository (the commit that triggered the run, without leaving
  its token in the checkout) and runs `forsgren check-config --config
  forsgren.config.yml` on the file at the repository root, before it renders
  anything. A setting that is not accepted only warns in the log (see
  [A setting that is not accepted](#a-setting-that-is-not-accepted)). An invalid file (a missing one was just written) fails the job with check-config's
  message in the log and in the run's summary, after a cross mark, and
  nothing is published from it. The message can quote the file, so the log
  shows it with workflow commands stopped: a line of it that starts with
  `::` is printed, never run.
- **The token: a `FORSGREN_TOKEN` secret.** `forsgren collect` reads the
  measured repositories with a read-only token of the installation's own
  (the job's token reaches only the data repository). Make one with the
  permissions its rules need (see [Collecting deployments](data-files.md#collecting-deployments-collect), The token: per
  rule `environment=` Deployments, `workflow=` Actions, and for every rule
  Contents and Metadata), store it as the data repository's Actions secret
  `FORSGREN_TOKEN`, and pass it by name as above. By name, not
  `secrets: inherit`: the called workflow then receives this one secret and
  none of the repository's others. The workflow declares it
  `required: false`: a new install's first run, with the starter's zero
  projects, needs no token and runs before one is made; once
  `forsgren.config.yml` lists a repository, a missing token fails the run
  with collect's message naming `FORSGREN_TOKEN`. Inside the workflow only
  the collect step gets it, in its environment. Give the token an expiry
  date less than a year away. From 14 days before that date the log warns and
  the setup issue lists the token (see [The setup
  issue](updating-and-releases.md), forsgren#177). That warning works only
  while GitHub still accepts the token and sends a valid expiry date with its
  answers: it is not a promise of 14 days' notice. A token that is revoked or
  deleted before its date gives no warning; the first sign is then the
  failed run.
- **The daily run collects and commits the history.** After the check,
  `forsgren collect --config forsgren.config.yml --data
  data/deployments.csv` appends the new final deployments, and their
  commits to `data/commits.csv` (see [Collecting deployments](data-files.md#collecting-deployments-collect)). When `data/`
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
  lets the starter step, the README step and the data step each push their
  one commit.
  Without them the deploy step or a push fails. **Moving to the release
  that adds the starter and collect, change `contents: read` to
  `contents: write` and add the `secrets:` block** in the calling workflow
  (and in the template's copy of it).
- **`pull-requests: read` is optional, and the caller's to grant too**
  (forsgren#40). With it, when a newer forsgren release exists and
  Dependabot has an open pull request in your repository that bumps the
  `uses:` pin to exactly that release, the page footer says "Forsgren <version>
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
  **The pull request is found by what it changes**
  ([#42](https://github.com/yveshanoulle/forsgren/issues/42)): forsgren
  lists the open pull requests by `dependabot[bot]`, reads each one's
  changed files, and takes the highest-numbered one whose files move the
  `metrics.yml` pin to that release. The branch name is not read, so a
  grouped update, another separator or another directory in your
  dependabot.yml is found too. A pull request with more files than forsgren
  reads is skipped and named in the run's log. When the files cannot be
  read, the lookup is unknown as for the list: a 403 is `no-access` (the
  token needs `pull-requests: read`), GitHub's rate limit is
  `rate-limited`, and anything else is `failed`.
- **`issues: write` lets forsgren open its setup issue** (forsgren#73). When
  the running version needs more configuration, `forsgren check-needs` writes
  one issue in the data repository with the job's token. Without the
  permission the run does not fail: the job summary and the page footer say
  what is needed instead (see [The setup issue](updating-and-releases.md)). The workflow declares no
  permissions block, so it takes what your caller grants.
- **GitHub Pages must build from GitHub Actions** (the data repository's
  Settings → Pages → Source). The run deploys to the repository's
  `github-pages` environment.
- The Go the workflow builds with is the one of forsgren's `go.mod`
  toolchain line for that release; the caller sets up nothing.
