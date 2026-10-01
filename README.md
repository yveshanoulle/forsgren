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
| Time to restore | When users hit a failure, how long until it's fixed? |

## How it gets its data

forsgren reads only what is already in GitHub:

- **Deployments:** workflow runs (for example a TestFlight upload) and GitHub
  Deployments, with their commit and end time.
- **Failures:** issues labelled `failure`. Each carries a short record block as
  its own comment:

  ```
  failure-start: 2026-01-15T12:18+01:00
  failed-build: 297.6762
  fixed-build: 298.6788
  ```

  `failure-start` is when users were first hit; the two builds name the
  deployment that caused the failure and the one that fixed it. A failure issue
  without a complete record is reported as incomplete, never silently skipped.

## What it produces

- the current value of each metric, per service
- a history file, so each metric can be shown as a trend
- a static page with the current numbers and a trend chart per metric, safe to
  publish: numbers and dates only, no issue titles, no links into private
  repositories

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

## Status

Early. Nothing is built yet; the first work is setting up the repository's
build and quality tooling. Private for now, possibly open source later.
