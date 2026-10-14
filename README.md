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

Moved to [docs/data-files.md](docs/data-files.md).

## What it produces

- the current value of each metric, per service
- a history file, so each metric can be shown as a trend
- a static page with the current numbers and a trend chart per metric, safe to
  publish: numbers and dates only, no issue titles, no links into private
  repositories

## Where configuration and data live

Moved to [docs/data-files.md](docs/data-files.md).

The data guard that keeps it that way is described in [docs/development.md](docs/development.md).

## History

Moved to [docs/data-files.md](docs/data-files.md).

## Deployment frequency

Moved to [docs/pages-and-views.md](docs/pages-and-views.md).

## Lead time for changes

Moved to [docs/pages-and-views.md](docs/pages-and-views.md).

## Failed deployment recovery time

Moved to [docs/pages-and-views.md](docs/pages-and-views.md).

## Change fail rate

Moved to [docs/pages-and-views.md](docs/pages-and-views.md).

## Deployment rework rate

Moved to [docs/pages-and-views.md](docs/pages-and-views.md).

## The page

Moved to [docs/pages-and-views.md](docs/pages-and-views.md).

## Configuration

Moved to [docs/configuration.md](docs/configuration.md).

## Collecting deployments (`collect`)

Moved to [docs/data-files.md](docs/data-files.md).

## Running forsgren

Moved to [docs/configuration.md](docs/configuration.md).

## The setup issue (`check-needs`)

Moved to [docs/updating-and-releases.md](docs/updating-and-releases.md).

## Auto-update (`check-update`)

Moved to [docs/updating-and-releases.md](docs/updating-and-releases.md).

## Working on forsgren

Moved to [docs/development.md](docs/development.md).

## Quality gates

Moved to [docs/quality-gates.md](docs/quality-gates.md).

## CI

Moved to [docs/ci.md](docs/ci.md).

## Privacy

Moved to [docs/pages-and-views.md](docs/pages-and-views.md).

## Installing and updating

The agent install and the newer-release footer: moved to [docs/updating-and-releases.md](docs/updating-and-releases.md).

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
