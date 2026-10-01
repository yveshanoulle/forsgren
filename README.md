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

## Where configuration and data live

Not in this repository. It holds code only. An installation keeps its
configuration (which repositories and services, workflow names, labels, the
health URL) and its data (`history.csv`, the raw events fetched from GitHub)
in a separate private data repository, made from a template, and passes them
to forsgren as paths. Test fixtures are made up (`acme/app`) and live only
under `testdata/`.

The data guard (`Scripts/check_data_guard.sh`, a PRE gate) keeps it that way.
Over the files git tracks, it fails when:

- a file that looks like installation config or data sits outside
  `testdata/`: `history.csv`, `*.history.csv`, `forsgren.config.*`,
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

## Quality gates

`./FBP.sh` runs the gates in two phases around the build: `./sfl.sh pre`
checks the repository before the site is generated, `Scripts/build_site.sh`
renders the site into `.build/site`, and `./sfl.sh post` checks that
generated output. `Scripts/gate_report_order.txt` declares every gate, its
phase and its order; a gate's self-test always runs in PRE, before the gate
it validates.

The POST gates, on the generated site:

- **HTMLHint** (`Scripts/gate_htmlhint.sh`): every `.html` file under the
  rules in `.htmlhintrc`. Red on a finding, and on a run that scanned zero
  files, since nothing linted is not clean.
- **Stylelint** (`Scripts/gate_stylelint.sh`): every `.css` file under
  `.stylelintrc.json` (stylelint-config-standard plus konenki-website's
  overrides). Red on a finding, and on a glob that matches no file.
- **lint coverage** (`Scripts/check_lint_coverage.sh`): each linter opened
  every `.html` and `.css` file the site ships, no fewer and no more. A glob
  that stops matching is a smaller job that still reports success; this is
  the gate that notices.

A finding in the generated page is fixed in the template under
`internal/page/`, never by loosening a rule in the config.

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

**The npm linters are pinned in `package.json`.** Node itself (and with it
`npm`) is a Homebrew tool from `Scripts/required_tools.txt`, so like Go it
follows whatever the formula publishes. The linters the post gates use,
htmlhint, stylelint and stylelint-config-standard, are not: they are
`devDependencies` in `package.json` at an exact version (no `^` or `~`), and
`package-lock.json` pins every package they pull in. Both files are committed.
`./sfl.sh` runs `npm ci` when `node_modules/.bin/htmlhint` is missing: `npm ci`
installs exactly what the lockfile says into `node_modules/` (gitignored,
never committed) and fails when `package.json` and the lockfile disagree.
Never use `npm install` in a gate or a workflow, and never install the linters
globally or run them through `npx --yes`.

Two gates keep it that way: **npm manifest policy**
(`Scripts/check_guardrail_packages.sh`) is red on a version range in
`package.json`, on a missing or gitignored `package.json` or
`package-lock.json`, and on a tracked `node_modules/`; **npm audit**
(`Scripts/npm_audit_check.sh`) is red on a high-severity advisory that one
`npm audit fix` cannot heal. When that fix does heal it, the changed
`package-lock.json` rides into the commit.

**To move a linter to a new version,** change its exact pin and the lockfile
together, then run `./FBP.sh`:

```
npm install --save-dev --save-exact stylelint@17.15.0
```

That one command rewrites the pin in `package.json`, re-resolves
`package-lock.json` and updates `node_modules/` (sfl's `npm ci` runs only when
`node_modules` has no htmlhint, so it would not pick a bump up on its own).
Check that `package.json` still shows an exact version, and commit both files.

## Status

Early. Nothing is built yet; the first work is setting up the repository's
build and quality tooling. Private for now, possibly open source later.
