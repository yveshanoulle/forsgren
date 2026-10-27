# forsgren installation

This README is forsgren's file, written by the daily run for forsgren {{version}}: a change you make here is overwritten.

This repository publishes a [forsgren](https://github.com/yveshanoulle/forsgren)
page for your projects, once a day, on GitHub Pages. forsgren measures the five
DORA metrics from data GitHub already has: deployment frequency, lead time for
changes, failed deployment recovery time, change fail rate and deployment rework
rate, per project and per service.

The page has three views: **standard** (the DORA bands), **numbers** (the raw
values), both with a column of weekend deployments next to deployment
frequency, and **scoring** (each metric's DORA Quick Check score, 0 to 10, and
Overall Performance). `view:` in your config chooses which one is the root page. The settings page
is a table with, for every setting, the value in use, the possible values and the default;
Default shows the default value; a key your config leaves out shows "(not set)" after its current value.
The Daily page, in the menu at the top of every page, shows how many issues
were opened and how many were closed as completed, not planned, duplicate or
other, across all your projects; Lead time, the median time from an issue's
creation to its close as completed, over the issues completed in that period,
and Bugs lead time, the same for issues with the GitHub `bug` label; then Open, how many issues were still open at
the end of each day; Open bugs, how many of those carry the GitHub `bug` label
(the label as it is now, applied to the whole history); Total, how many issues had been created by then, open or
closed; and Open / Total as a percentage. Open and Open bugs show an arrow after each
count: red up (▲ +3) when it rose, green down (▼ −2) when it fell, grey (–) when
it did not change, against the previous period of the same kind. Red and green
mean rose and fell, not worse and better. It has one row per day for the last 30
days, newest first. The Issues page, next to it in the menu, shows the same
columns over longer periods: the days of the current week up to yesterday, then
the weeks of the current month, then the complete months of the current year, then one
row per earlier year back to your first issue.
The first run after an update reads every issue once, and the bug label of
every issue, so both pages have their history back to the first issue.
Rows where nothing happened (no new issue, no close, no reopen) are left out; when
nothing happened at all, the page says so in one line.
The full documentation is in the
[forsgren README](https://github.com/yveshanoulle/forsgren#readme), which lists
the docs; the
[configuration reference](https://github.com/yveshanoulle/forsgren/blob/main/docs/configuration.md)
is the one to open first.

A service can name its folders with `paths` in `forsgren.config.yml`, for
example `deploy-api: {label: API, paths: [api/, shared/]}`. The TBD page then
counts, for that service, only the commits that touch those folders. A service
without `paths` says `Per repository` for its Time to deploy per commit and its
Commits per deployment. forsgren reads the files of each commit once, which
needs **Contents** read on the token; the service row says `Files still being
read` until it has.

This template holds only forsgren's own files. Your configuration and your
history are yours: they are never in the template, so installing a new
version never overwrites them.

## Set up

1. **Use this template** (the green button) to create your own repository.
   Private or public, your choice.
2. **Create a read-only token** for the repositories you want to measure:
   GitHub → Settings → Developer settings → Fine-grained tokens. Give it
   read-only **Deployments** (for `environment=`, the default), **Actions**
   (for `workflow=`), **Contents** (for `release`) and **Issues** (for
   `failure` issues); Metadata is added by itself. Store it in your new repository under
   **Settings → Secrets and variables → Actions → New repository secret**,
   named `FORSGREN_TOKEN`.
3. **Settings → Pages → Source: GitHub Actions**.
4. **Actions → forsgren → Run workflow** once. On a new install the run
   commits a starter `forsgren.config.yml` and publishes a page saying no
   projects are configured yet.
5. **Edit `forsgren.config.yml`** and list your projects and repositories, for
   example:

   ```yaml
   version: 1
   view: standard              # standard, numbers or scoring
   auto_update: true           # Dependabot's forsgren pull requests merge themselves
   auto_update_level: major    # possible options: major, minor, patch
   history_days: 365           # how far back history goes, 30 to 1825 days
   dora_days: 30               # the window of the five DORA metrics: 30, 90 or 180 days
   history_chunk_days: 100     # how many days back each run adds, 1 to 365
   working_hours: 8            # a working day is configured as this many hours, 1 to 24
   issues_page: false          # the Issues page: true, unlisted or false (default true)
   days_page: false            # the Daily page: true, unlisted or false (default false)
   numbers_scoring_page: unlisted   # the Numbers and scoring page: true, unlisted or false (default unlisted)
   history_page: unlisted          # the History page: true, unlisted or false (default unlisted)
   tbd_page: true                  # the TBD page: true, unlisted or false (default true)
   projects:
     - name: Acme Shop
       repositories:
         - name: acme/api                        # default: GitHub Deployments
                                                 # to the environment production
         - name: acme/ios-app
           deployment: workflow=testflight.yml   # a successful run of that workflow
     - name: Acme Tools
       repositories:
         - name: acme/cli
           deployment: release                   # a published GitHub Release
   ```

   `environment=<name>` is the form for another environment. The daily run
   refuses an invalid file with a one-line message; a setting it does not accept is not an invalid file: the run uses the default and the settings page and the log say so.

   The Daily page is hidden by default (forsgren 1.3.0): set `days_page: true`
   to show it. The starter turns the Issues page off (`issues_page: false`): set `issues_page: true` to show it; a config that leaves the key out shows it. The History page and the Numbers and scoring page are generated but left out of the menu by default (`unlisted`); set `true` to list them or `false` to leave them out. The TBD page is in the menu by default (`tbd_page: true`); set `unlisted` to leave it out of the menu or `false` not to generate it.

From then on it runs every day by itself: it collects the new deployments,
commits them to `data/`, keeps this README current for the forsgren version it
runs and publishes the page. If your default branch
refuses pushes from `github-actions[bot]`, allow it to bypass that rule, or
the run cannot commit.

The forsgren job in `.github/workflows/forsgren.yml` grants itself only what it
needs, each permission declared explicitly:

- `contents: write`: commit a new install's starter `forsgren.config.yml`,
  this README and the collected history in `data/`.
- `pages: write` and `id-token: write`: publish to your GitHub Pages.
- `pull-requests: read`: lets forsgren read the merged pull requests for the
  PR Lead Time, and the page footer name Dependabot's waiting pull
  request for a newer forsgren release. Without it the run still succeeds;
  the setup issue names it. A fine-grained `FORSGREN_TOKEN` needs Pull
  requests (read) as well, which the setup issue cannot see, so it never
  says the pull request read works.
- `issues: write`: lets forsgren open its setup issue (below). Without it the
  run still succeeds; its job summary and the page footer say what is missing.

**The setup issue.** When a forsgren version needs more of your installation (a
permission, a secret, a file or a config key), forsgren opens one issue in this
repository, labelled `forsgren-setup`, listing the steps. It is one issue, not
one per version, and it closes itself once everything is in place. It also tells you when `FORSGREN_TOKEN` is within 14 days of expiring, with the date and the command `gh secret set FORSGREN_TOKEN -R <repo>`; the daily run warns in its log too. The check
reads the permissions from the forsgren job in `forsgren.yml`, so declare them
explicitly there: `write-all` and `read-all` are not supported, in keeping with
least privilege.

## What is in here

- `.github/workflows/forsgren.yml`: the daily run. It calls forsgren's
  reusable workflow at a pinned release.
- `.github/workflows/forsgren-update.yml`: merges Dependabot's forsgren pull
  request for you when `forsgren.config.yml` says `auto_update: true`.
- `.github/dependabot.yml`: proposes each new forsgren release as a pull
  request, every day at 04:00 UTC.
- `README.md`: this text, rewritten by the daily run whenever the forsgren
  version it runs has a different one.
- `LICENSE`: its licence.

What you add or the run writes, and what forsgren never overwrites:

- `forsgren.config.yml`: your configuration. The first run writes a starter
  one if you have none; an existing file is never touched.
- `data/`: your history, written and committed by the daily run as
  `github-actions[bot]`: `deployments.csv`, `commits.csv`, `failures.csv` and
  `issues.csv` (what happened to every issue, for the Issues and Daily pages),
  `issue_bugs.csv` (which issues carry the `bug` label, for Open bugs), plus
  `reach.csv` (how far back each repository has been read),
  `failures_read.csv` (when its failure issues were last read),
  `failures_withdrawn.csv` (failure issues that no longer count: the label was
  removed, the issue was closed as not planned, or it is gone),
  `issues_full.csv` (which repositories had their one full read of every
  issue, for the historical Open and Total) and
  `issue_bugs_cut.csv` (which repositories' bug reads stopped at the page cap,
  so Open bugs shows as incomplete) and
  `cut_runs.csv` (which repositories the request budget cut short without
  progress) and `starts_checked.csv` (which repositories had their failure
  starts caught up from the issues' comments) and `commits_backfilled.csv`
  (which repositories had the author, parents and committer date of their
  legacy commits backfilled). The first run
  reads one chunk of `history_chunk_days`; each later run adds one older chunk
  until `history_days` is reached. forsgren never deletes history.

## Installing a new version

**One click, or none.** When forsgren publishes a release, Dependabot opens a
pull request here that moves the pinned `uses:` lines in
`.github/workflows/forsgren.yml` and `.github/workflows/forsgren-update.yml` to
the new release (configured in `.github/dependabot.yml`). It never touches
`forsgren.config.yml` or `data/`.

- With `auto_update: true` in `forsgren.config.yml`, the pull request merges
  itself and forsgren runs right after. `auto_update_level` sets how far an
  update may go: `patch` (0.2.0 to 0.2.1), `minor` (to 0.3.0) or `major` (to
  1.0.0). The starter config has `auto_update: true` and
  `auto_update_level: major`. `major` permits major, minor and patch updates;
  it does not mean a major release is safe. Nothing checks a release against
  your installation's own data. To take fewer updates, set `auto_update_level`
  to `minor` or `patch`.
- Upgrading to forsgren 1.3.0 hides the Daily page of an installation that does
  not set `days_page`; add `days_page: true` to `forsgren.config.yml` to keep
  it.
- Anything else is left for you, with the reason in the run's summary. That
  covers a bigger update than your level, a pull request that changes more
  than the pin lines, or one that is not Dependabot's.
- With `auto_update: false`, or no `auto_update` line, merge the pull request
  yourself; the next run uses the new version.

**When a release changes more than that line** (a permission, a new secret),
its release notes say so. Then copy the files of the new forsgren-template over
your repository once: that replaces forsgren's files (the workflows, this
README) and leaves `forsgren.config.yml` and `data/` as they are. Your
repository keeps its secrets and its Pages address.

What an existing installation must do for a given release is in that
release's notes on the
[forsgren releases page](https://github.com/yveshanoulle/forsgren/releases).

## Licence

The files in this template are under the [0BSD licence](https://github.com/yveshanoulle/forsgren-template/blob/main/LICENSE): use them
as you like, no attribution needed. forsgren itself is EUPL-1.2.
