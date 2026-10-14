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
  other value is refused by `check-config` and `render`, naming the key and
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
  history goes, in days, a whole number from 1 to 1825 (5 years), written at
  the top level, for example `history_days: 730`. Left out, or without a
  value, it is 365. Anything else (zero, a negative number, more than 1825, a
  quoted value, a decimal or text) is refused by `check-config` and `render`,
  naming the key and the limit: `invalid history_days "1826": use a whole
  number of days from 1 to 1825`. forsgren does not read that far at once:
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
- **`issues_page`** and **`days_page`** are optional (forsgren#159): whether
  the Issues page (`issues.html`) and the Daily page (`days.html`) are
  generated, each `true` or `false`, written at the top level, for example
  `issues_page: true` and `days_page: false`. Left out, or without a value,
  `issues_page` is `true` (the page is shown) and `days_page` is `false` (the
  page is hidden). Only the literals `true` and `false` are accepted; a quoted
  value, `yes`, a number or text is refused by `check-config` and `render`,
  naming the key: `invalid days_page "yes": use true or false`. A page that
  is `false` is not generated, is removed from the site if an earlier run
  wrote it, and has no entry in the menu. From 1.3.0 an installation that
  does not set `days_page` has no Daily page until it sets `days_page: true`.
  The legend says how to show or hide the two pages. The starter that
  `init-config` writes includes `issues_page: true` and `days_page: false`.
- **The settings page** (`settings.html`, forsgren#74, moved out of the legend
  in forsgren#84, a table since forsgren#141) tabulates every optional key,
  `view`, `auto_update`, `auto_update_level`, `history_days`,
  `history_chunk_days`, `working_hours`, `issues_page` and `days_page`, in four columns: **Parameter**;
  **Current value**, the value in use (`major` for an unset
  `auto_update_level`); **Possible values**, built from the config package's
  own constants and limits so the page cannot drift from what `check-config`
  accepts (`standard, numbers, scoring`; `true, false`; `patch, minor, major`; `1 to 1825`; `1 to 365`; `1 to 24`; `true, false` for each of the two page keys),
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
record block (see [How it gets its data](data-files.md#how-it-gets-its-data)); lead time runs from a change's first
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
`auto_update_level: major`, `history_days: 365`,
`history_chunk_days: 100` and `projects: []`, so
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

forsgren renders a static page whose footer says "Forsgren 1.4.0", the version of
the forsgren that rendered it, and shows each project's deployment frequency,
lead time for changes, failed deployment recovery time and change fail
rate (and the deployment rework rate); every run writes the page in each view too, at
`/standard/`, `/numbers/` and `/scoring/` (see [The page](pages-and-views.md#the-page)). That version has one source,
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
check-needs` went (see [The setup issue](updating-and-releases.md)): anything but `ok` adds "needs more
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
pull-request check failed", and a Setup line, see [The setup issue](updating-and-releases.md)); the link is fine there, because a run page is
private to the repository, unlike the public page. A flag it cannot use is a
usage error that prints nothing. With `--config`, a config that
lists no projects makes the page show, in place of the table and besides
"Forsgren 1.4.0" in its footer, a how-to for filling `forsgren.config.yml`;
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
  the collect step gets it, in its environment.
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
  lets the starter step and the data step each push their one commit.
  Without them the deploy step or a push fails. **Moving to the release
  that adds the starter and collect, change `contents: read` to
  `contents: write` and add the `secrets:` block** in the calling workflow
  (and in the template's copy of it).
- **`pull-requests: read` is optional, and the caller's to grant too**
  (forsgren#40). With it, when a newer forsgren release exists and
  Dependabot has an open pull request in your repository that bumps the
  `uses:` pin to exactly that release, the page footer says "Forsgren 1.4.0
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
  what is needed instead (see [The setup issue](updating-and-releases.md)). The workflow declares no
  permissions block, so it takes what your caller grants.
- **GitHub Pages must build from GitHub Actions** (the data repository's
  Settings → Pages → Source). The run deploys to the repository's
  `github-pages` environment.
- The Go the workflow builds with is the one of forsgren's `go.mod`
  toolchain line for that release; the caller sets up nothing.
