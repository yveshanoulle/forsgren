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

One PRE gate checks the page templates themselves:

- **html duplication** (`Scripts/check_html_dupl.sh`, the estate's ratchet
  from konenki-website): jscpd measures the share of duplicated markup in
  the `html/template` files under `internal/page/templates` and the gate
  compares it to a recorded ceiling, today 0.00%. The ceiling only moves
  down: a red is fixed by removing the duplication, never by raising the
  number. Red on a run that scanned zero `.html` files. jscpd is pinned like
  the linters below.

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

## Privacy

The public page shows numbers and dates only. It carries no issue titles and
no links into private repositories, makes no third-party requests (no web
fonts, analytics or CDNs: everything it loads is served with it), sets no
cookies, uses no browser storage and tracks no one. Two POST gates check the
generated page on every run, privacy posture for the requests, cookies and
tracking, and repository links for the links (see Quality gates). No gate
checks for issue titles yet: that rests on the renderer, which is given
numbers and dates only. A finding is fixed in the template, never by
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
