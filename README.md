# forsgren

Measure the five DORA metrics for a set of GitHub repositories, from GitHub
data, and publish them as a small static status page.

Named after Dr. Nicole Forsgren, whose research with DORA (and the book
*Accelerate*, with Jez Humble and Gene Kim) defined the first four of these metrics.

## The five metrics

forsgren shows each metric as its DORA band next to the figures it comes from,
for every project. The definitions, with the rulings behind them, are in
[Pages and views](docs/pages-and-views.md). The numbers count back over the
last 30 days, or over 90 or 180 days when `dora_days` in the config says so.

**[Deployment frequency](docs/pages-and-views.md#deployment-frequency)** answers
how often you ship to users. The page shows its band with the number of
successful deployments of the last 30 days: "Between once per day and once per
week · 12".

**[Lead time for changes](docs/pages-and-views.md#lead-time-for-changes)** answers
how long a commit takes to reach users. The page shows its band with the median
and the number of commits of the last 30 days: "Less than one hour · 17 min (37)".

**[Failed deployment recovery time](docs/pages-and-views.md#failed-deployment-recovery-time)**
answers how long it takes, when a deployment fails and needs immediate
intervention, until a successful one recovers it. The page shows its band with
the median and the number of recoveries: "Less than one day · 3 h (2)".

**[Change fail rate](docs/pages-and-views.md#change-fail-rate)** answers what
share of deployments causes a failure users hit. The page shows its band with
the rate and the failed changes: "20% · 15% (2 of 13)".

**[Deployment rework rate](docs/pages-and-views.md#deployment-rework-rate)**
answers what share of deployments is unplanned, made to fix a problem users hit.
The page shows its band with the rate and the rework deployments:
"20% · 14% (1 of 7)".

## What it produces

- the current value of each metric, per service
- the history in `data/` (deployments, commits, failure issues and issue
  events), which the metrics are calculated from
- a static page with the metrics table in three views (standard, numbers,
  scoring), an optional Numbers and scoring page (each metric's number and
  score in one cell, shown with `numbers_scoring_page: true`), the Issues and Daily pages (each can be hidden with `issues_page` and
  `days_page`; Daily is hidden by default) with their Open and Open bugs
  columns and trend arrows, a History page (each metric's number and score
  per half-year and for the last 6 months, with a trend chart per row; hide
  it with `history_page: false`), and the Settings and Legend pages, safe to publish: numbers and
  dates only, no issue titles, no links into private repositories

## A live example

forsgren measures itself, and publishes the page at
<https://forsgren.forsgren.be>.

This README is also the project page, forsgren.be: it is rendered to one page
and published on every change to it; see [CI](docs/ci.md).

## Installing

An installation is a data repository of your own (private when it measures
private repositories), made from the
[forsgren-template](https://github.com/yveshanoulle/forsgren-template)
repository. It keeps your `forsgren.config.yml` and its `data/`, runs forsgren
once a day from a one-line workflow pin, and publishes the page on GitHub Pages.
Create it from the template and follow the template's own README, or point an AI
coding agent at [agent-installer.md](agent-installer.md): it asks what only you
can decide and creates your data repository from the template step by step.
Each new forsgren release then arrives as a Dependabot pull request.
For an existing installation that is behind the latest release, or has
automatic updates switched off, point a coding agent at
[agent-upgrade.md](agent-upgrade.md): you give it the address of your current
report, and it finds the rest, reads what each release asks of you, and asks
only what is yours to decide. To remove an installation, its page, its custom
domain and its history, point a coding agent at
[agent-delete.md](agent-delete.md): it shows you what will go and deletes
nothing before you reply with the go it asks for.

## Configuration

Every `forsgren.config.yml` key is described in [docs/configuration.md](docs/configuration.md).

## Documentation

- [Configuration](docs/configuration.md): every `forsgren.config.yml` key, and running forsgren from an installation's workflow.
- [Pages and views](docs/pages-and-views.md): the five metrics in full, the page and its views, what each cell means, and privacy.
- [Data files](docs/data-files.md): how forsgren gets its data, the `data/*.csv` formats, and collecting deployments.
- [Updating and releases](docs/updating-and-releases.md): the setup issue, auto-update, Dependabot and installing a new version.
- [Development](docs/development.md): working on forsgren, the tools and their pins, the data guard.
- [Quality gates](docs/quality-gates.md): every gate FBP and CI run, and what each one checks.
- [CI](docs/ci.md): what runs on GitHub, the metrics workflow for installations, and how a red row maps to a local run.

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
