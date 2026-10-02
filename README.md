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
  failure-start: 2030-04-01T09:30+02:00
  failed-build: 12.345
  fixed-build: 12.346
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
Like the secret scan it is secret-class: a finding blocks the commit itself,
not only the push, so the leak never enters history.
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

## Configuration

An installation describes what forsgren measures in one file,
`forsgren.config.yml`, in its data repository. Together with `data/` it is
all an installation's owner owns, so the template contains neither: it holds
only forsgren's own files. Installing a new version is copying the new
template's files over the data repository; that replaces every forsgren file
and never touches `forsgren.config.yml` or `data/`, and the repository keeps
its secrets and Pages address (ruled 2026-10-02, #9). forsgren creates
`data/` when it first stores history and never overwrites history that is
there. One installation measures every project it lists on one page, each
project in its own section (#6).

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
- **`projects`**: at least one. A project is a name and the repositories that
  ship it (a product can be several repositories). Project names are
  unique, ignoring case.
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

A **failure** is an issue labelled `failure` whose body carries the failure
record block (see How it gets its data); lead time runs from a change's first
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
(version 1): projects: 2, repositories: 3`, and exits 0; it exits 1 with
the refusal on stderr when the file is invalid or cannot be read, and 2 on
a usage error.

## Running forsgren

Today forsgren renders one placeholder page, which says "Forsgren 0.0.2":
the version of the forsgren that rendered it. That version has one source,
the `version` variable in `cmd/forsgren/main.go`; a release build can set
it with `-ldflags "-X main.version=<version>"`. Reading GitHub (`collect`)
and the history file come next, after the walking skeleton (#3).

The first release is `v0.0.1`. Install a release with
`go install github.com/yveshanoulle/forsgren/cmd/forsgren@v0.0.1`; an
installation pins that version. From a checkout of this repository:

```
./Scripts/build_site.sh            # builds .build/bin/forsgren, renders .build/site
.build/bin/forsgren render --out <dir>
```

`forsgren render --out <dir>` writes the site (every page plus
`styles.css`) into `<dir>`, creating it when needed, and exits 0; 1 when
the render failed, 2 on a usage error.

**Daily, from an installation's data repository.** An installation does not
build forsgren: its data repository calls forsgren's reusable workflow,
`.github/workflows/metrics.yml`, once a day. That workflow installs
forsgren from the very commit it is called at with `go install`, checks the
data repository's `forsgren.config.yml` with `forsgren check-config`, renders
the page and publishes it to
the data repository's GitHub Pages, on a GitHub-hosted runner, with no server
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
      contents: read
      pages: write
      id-token: write
    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@<commit> # vX.Y.Z
```

- **The `uses:` line is the only version.** Pin it by the full commit of
  a release, its tag in the comment. The workflow takes no input naming a
  version: it installs forsgren from its own commit and repository, which
  GitHub gives a called workflow as `job.workflow_sha` and
  `job.workflow_repository` (the `github` context would name the
  caller's). It refuses anything but a 40-digit commit and one
  `owner/name` before it installs anything. A new template carries the
  new `uses:` line, so copying its files over the data repository updates
  it (see Configuration). A fork calling its own copy installs the fork,
  never upstream.
- **`v0.0.1` predates this.** Its `metrics.yml` still requires
  `with: forsgren-version: v0.0.1` under the `uses:` line; the one-line
  form starts with the next release, which has no such input: drop the
  `with:` block when moving to it.
- **The daily run checks the configuration first.** The workflow checks out
  the data repository (the commit that triggered the run, without leaving
  its token in the checkout) and runs `forsgren check-config --config
  forsgren.config.yml` on the file at the repository root, before it renders
  anything. A missing or invalid file fails the job with check-config's
  message in the log and in the run's summary, after a cross mark, and
  nothing is published from it. The message can quote the file, so the log
  shows it with workflow commands stopped: a line of it that starts with
  `::` is printed, never run. The checkout needs only the `contents:
  read` the caller already grants.
- **The three permissions are the caller's to grant.** A called workflow
  can only keep or narrow what its caller's job grants: `pages: write` and
  `id-token: write` let `actions/deploy-pages` publish, `contents: read` is
  read-only. Without them the deploy step fails.
- **GitHub Pages must build from GitHub Actions** (the data repository's
  Settings → Pages → Source). The run deploys to the repository's
  `github-pages` environment.
- The Go the workflow builds with is the one of forsgren's `go.mod`
  toolchain line for that release; the caller sets up nothing.

## Working on forsgren

**`./FBP.sh "<message>"`** (FBP = FullBuildAndPush) is the one command for a
change: 

`gofmt -w` over the Go files, `./sfl.sh pre`, `Scripts/build_site.sh`,
`./sfl.sh post`, then `git add -A`, a commit, and a push only when every
phase is green. 
An ordinary red still commits locally, with the subject
`*** RED ****` and the message in the body, so work is never lost, and
skips the push. 
A secret-class red (the secret scan or the data guard)
commits nothing at all. `./FBP.sh --no-commit` runs the gates and the build
only. 
Every commit it makes, green or `*** RED ****`, is signed off
(`git commit --signoff`): git adds a `Signed-off-by:` trailer for the
committer identity, yours from `user.name` and `user.email`, or
agent-Friend's under `Scripts/fbp_agent_friend.sh`. That is the Developer
Certificate of Origin sign-off the DCO check on pull requests asks for (see
CI and [CONTRIBUTING.md](CONTRIBUTING.md)).

Its closing summary prints the message, one row per phase with the
gate counts and the page count, and every failure's reason.

**`./sfl.sh pre|post`** runs one phase of the gates. Before PRE it runs
`git pull --ff-only` and stops (exit 3) when that cannot fast-forward, then
installs the tools (see Installing and updating), runs `npm ci` when the
npm linters are missing, and exports the Go pin. It runs every gate of the
phase even after a failure, prints a step table and an `Errors:` block with
each failed gate's reason, and exits 0 green, 1 red, 2 on a secret-class
red.

**`Scripts/gate_report_order.txt`** declares every gate, one row
`<label>|<script>|<phase>|<class>`: the label sfl and CI print, the script
that runs, `pre` or `post`, and `secret-class` or nothing. A gate this repo
does not have is a row `<label>|n/a|<reason>`. sfl and CI both run the
rows in file order, so the file is the one list.

**Adding a gate:** write the script and its self-test (`Scripts/test_*.sh`,
red first, plus a mutation proof), give each a row at its position in the
order file (the self-test in PRE, before its gate), add any Homebrew tool
it needs to `Scripts/required_tools.txt`, and describe it below.
`Scripts/test_sfl_drives_from_order_file.sh` is red on a `Scripts/test_*.sh`
no row declares, and the gate-wiring gate on a script neither runner runs.

## Quality gates

`./FBP.sh` runs the gates in two phases around the build: `./sfl.sh pre`
checks the repository before the site is generated, `Scripts/build_site.sh`
renders the site into `.build/site`, and `./sfl.sh post` checks that
generated output. `Scripts/gate_report_order.txt` declares every gate, its
phase and its order; a gate's self-test always runs in PRE, before the gate
it validates.

Two PRE gates come first and are secret-class, so a finding blocks the
commit itself:

- **secret scan** (`Scripts/check_secrets.sh`, the estate's gitleaks gate):
  gitleaks over the working tree, before anything is staged, under `.gitleaks.toml`
  (the default rules, with `${{ secrets.NAME }}` references allowed, since
  they are names, not values). Red, never skipped, when gitleaks is
  missing. Its self-test (`Scripts/test_check_secrets.sh`) plants a key and
  shows it caught.
- **data guard** (`Scripts/check_data_guard.sh`): see Where configuration
  and data live.

One PRE gate checks the page templates themselves:

- **html duplication** (`Scripts/check_html_dupl.sh`, the estate's ratchet
  from konenki-website): jscpd measures the share of duplicated markup in
  the `html/template` files under `internal/page/templates` and the gate
  compares it to a recorded ceiling, today 0.00%. The ceiling only moves
  down: a red is fixed by removing the duplication, never by raising the
  number. Red on a run that scanned zero `.html` files. jscpd is pinned like
  the linters below.

Two PRE gates run the Go tests and the formatting:

- **Go tests** (`Scripts/check_go_tests.sh`): `go test ./...` over the
  module. Red on a failing test, on a run that found no test at all, and
  on a package under `node_modules` (go.mod's `ignore node_modules` is what
  keeps npm's vendored Go out of `./...`; this is its guard). A green run
  leaves the coverage profile the Go coverage gate reads.
- **gofmt** (`Scripts/check_gofmt.sh`): check-only, `gofmt -l` over every
  Go file git tracks or would add; red naming each unformatted file, and on
  no Go file found. `./FBP.sh` runs the same script with `--fix` before the
  gates, so locally it sees a formatted tree; CI never fixes.

Seven more PRE gates check the Go code:

- **go mod tidy** (`Scripts/check_go_mod_tidy.sh`, MenoPower's check made
  check-only): red when `go.mod` or `go.sum` is not what `go mod tidy`
  would write, a require missing or unneeded, a `go.sum` line missing or
  stale, with the diff tidy would apply. It runs `go mod tidy -diff`, so it
  never rewrites either file; the fix is `go mod tidy`, committed with the
  change that needed it. Red, as a tool error, when tidy could not run (a
  `go.mod` it cannot parse, a module it cannot fetch). Its self-test
  (`Scripts/test_check_go_mod_tidy.sh`) runs offline and shows, by
  mutation, that `-diff` is what makes the gate red instead of a silent
  rewrite.
- **Go lint** (`Scripts/check_go_lint.sh`, MenoPower's): golangci-lint
  over the module under `.golangci.yml`, ported from MenoPower `shared/`,
  its strictest module: govet, errcheck, staticcheck, gosec, dupl
  (80 tokens), funlen (60 lines, 40 statements), lll (120), gocognit (10)
  and gocyclo (above 6 is red), plus the gofmt and goimports formatters,
  test code included. revive is enabled too but runs no rule: the config's
  one entry, which disables `exported`, replaces revive's default rule set
  (as in MenoPower; an open point on forsgren#1). No issue cap, so every finding is listed. Unlike
  `shared/`, gosec's G101 (a hardcoded credential) is not excluded. A
  finding is fixed in the code: an exclusion or `//nolint` needs Yves's
  approved issue. Red on a module with no Go package, and when golangci-lint
  could not run. Its self-test (`Scripts/test_check_go_lint.sh`) shows
  complexity 7 red (in a test file too) and 6 green, a credential red under
  G101, and, by mutation, that the threshold and the missing G101 exclusion
  in `.golangci.yml` are what decide those cases.
- **Go test duplication** (`Scripts/check_test_dupl.sh`, MenoPower's): the
  same `dupl` rule pointed at `_test.go` files only, which `.golangci.yml`
  leaves to it, so test code is judged once. Red on a module with no test
  file.
- **Go file length** (`Scripts/check_file_length.sh`, MenoPower's
  `check_file_length.py` rewritten in bash and awk): red when a Go
  production file is longer than 600 lines, each such file named with its
  count, longest first. `_test.go` files are not judged; a generated file
  is; a last line without a newline counts. The files are the module's own
  as `go list ./...` sees them, so `node_modules` (ignored in `go.mod`) is
  never judged and a file only another GOOS builds is. Red on a module with
  no production `.go` file. Its self-test
  (`Scripts/test_check_file_length.sh`) shows 601 lines red and 600 green,
  and, by mutation, that the comparison, `go.mod`'s ignore line and the
  GOOS-bound file list are what decide those cases.
- **Go coverage** (`Scripts/check_coverage.sh`, MenoPower's
  `check_coverage.py` rewritten in bash and awk): the coverage ratchet.
  Every function `go tool cover -func` measures has a floor in
  `coverage_thresholds.json`, and the total has one too. Red when a function
  or the total is below its floor, naming it with both numbers, and when a
  measured function is not registered: register it at 0.0, never a guessed
  floor (0.0 is tracked, not enforced). A floor below the ratchet rule,
  measured − 0.1 or exactly 100.0 at 100 %, stays green and is counted into
  one `FLOORWARN: N coverage floor(s) should be raised` line, each such
  function listed with the floor to set. Floors only go up: a red is fixed by
  testing, never by lowering a number. It reads the profile the Go-tests gate
  writes (`.build/go-coverage.out`), so the tests run once; that gate removes
  the profile when it is red, and no profile is red here. The thresholds
  file is read in one fixed shape, one `"key": number` per line, and a line
  outside it is red. Its self-test (`Scripts/test_check_coverage.sh`) shows
  each of those cases and, by mutation, that the floor comparison, the 0.1
  buffer and the Go-tests gate's removal of a red run's profile are what
  decide them.
- **Go vulnerabilities** (`Scripts/check_govulncheck.sh`, MenoPower's):
  govulncheck over the module, red when the code reaches a symbol the Go
  vulnerability database lists, naming each entry. When the database does
  not answer (`curl -sf --max-time 5 https://vuln.go.dev/index/db.json`
  fails: offline, refused, a timeout, an HTTP error) the check is skipped,
  as in MenoPower: one `⚠️ SKIP: govulncheck did not run` line naming the
  database, a `::warning::` in GitHub Actions, exit 0, and never the `OK`
  line of a pass. `FORSGREN_VULN_DB` points it at another database. Its
  self-test (`Scripts/test_check_govulncheck.sh`) runs offline against a
  database it writes, with one made-up entry, and shows a call to the listed
  symbol red, an unreachable database a skip and, by mutation, that the
  probe is what makes offline a skip rather than a tool error.
- **Go dead code** (`Scripts/check_deadcode.sh`, MenoPower's): `deadcode
  -test ./...`, red on any function, exported or not, that neither a main
  package nor a test reaches, each named with its file and line. The fix is
  to delete it, never to call it from a test to keep it alive. Red on a
  module with no main package and when deadcode could not run (a module that
  does not compile). Its self-test (`Scripts/test_check_deadcode.sh`) shows
  both kinds of dead function red, a test-only helper green and, by
  mutation, that `-test` is what keeps it green.

Go lint, Go test duplication, Go vulnerabilities and Go dead code run the
golangci-lint, govulncheck and deadcode pinned in `go.mod` (see Installing
and updating).

Seven PRE gates read the repository's own scripts and files:

- **actionlint** (`Scripts/check_actionlint.sh`, the estate's gate in
  coachretreat-website's copy): every `.github/workflows/*.yml` file under
  `.actionlint.yaml`. Valid YAML is not a valid workflow: actionlint knows
  which contexts exist where (a `runner.temp` in a job-level `env:` block
  once made GitHub reject konenki-website's whole workflow, so not one gate
  ran), which keys a step takes, and which runner labels exist. Every job
  here runs on a GitHub-hosted image, so `.actionlint.yaml` declares no
  custom label: a custom label (a self-hosted runner's) is red until it is
  declared there, and declaring one is configuration, not a waiver.
  actionlint also runs shellcheck over every
  `run:` block, and its self-test (`Scripts/test_check_actionlint.sh`) is red
  when that does not happen, since actionlint skips it silently when
  shellcheck is missing. No `-ignore` flag: a suppression needs a finding
  someone has looked at and Yves's explicit yes. One exists:
  `.actionlint.yaml` ignores, for `.github/workflows/metrics.yml` only,
  actionlint's "not defined" on the documented `job.workflow_sha` and
  `job.workflow_repository`, which actionlint 1.7.12 does not know yet
  (rhysd/actionlint#705); approved on
  [forsgren#4](https://github.com/yveshanoulle/forsgren/issues/4#issuecomment-5952631931),
  to be removed once an actionlint release knows them. Red on a directory with no
  workflow file, and when actionlint itself is missing.
- **zizmor** (`Scripts/check_zizmor.sh`, web-infra's gate): the GitHub
  Actions security linter, over `.github` under `.github/zizmor.yml`, every
  `.yml` and `.yaml` workflow. actionlint asks whether a workflow is valid,
  zizmor whether it is safe; the class it exists for is template injection,
  an attacker-controlled `${{ ... }}` (an issue title, a branch name)
  expanded into a `run:` block, where it runs as shell with the job's token
  on the runner. It runs at web-infra's setting: offline, High
  findings only, the default persona. A Medium finding such as a checkout
  that keeps its credentials is not its red; checkout pins owns that rule.
  The config suppresses nothing: a suppression needs a finding someone has
  looked at and Yves's explicit yes recorded on a GitHub issue. Red on a
  directory with no workflow file. Its self-test
  (`Scripts/test_check_zizmor.sh`) shows each of these, with two mutation
  proofs: the severity threshold is what keeps a Medium out, and the
  config is read from the scanned directory.
- **shellcheck** (`Scripts/check_shellcheck.sh`, the estate's gate from
  web-infra): every tracked `*.sh` file, and every tracked file without an
  extension whose first line is a bash or sh shebang, at any depth. The
  targets come from `git ls-files`, so a new script is checked the moment it
  is tracked, with no list to keep up to date. Red on any finding, and on a
  run that found no script. No script is excluded, and an empty
  `EXCLUDE_ALLOWED` is the normal state. An exclusion needs three things:
  the entry in the gate's `EXCLUDE_ALLOWED`, a sentence here naming the
  script and the reason, and Yves's explicit yes recorded on a GitHub issue,
  which that sentence links.
  A finding is fixed in the script. The same rule holds for a single line:
  it may carry a `# shellcheck disable=SCxxxx` only with a comment giving the
  reason, and with Yves's explicit yes recorded on a GitHub issue, which
  that comment links.
- **yamllint** (`Scripts/check_yamllint.sh`, from konenki-website): every
  tracked `.yml` and `.yaml` file under the rules in `.yamllint.yml`
  (konenki-website's). konenki lints its workflow directory by name;
  here the targets come from `git ls-files`, as for shellcheck, so the
  workflow and any other YAML are covered the moment they are tracked.
  `.yamllint.yml` is itself tracked YAML and is linted too, so the list is
  never empty, and a run that found none is red.
- **stray tracked files** (`Scripts/test_no_stray_tracked_files.sh`,
  konenki-website's): red on a tracked `.DS_Store` at any depth, and on a
  tracked `.yml`/`.yaml` with a top-level `jobs:` key anywhere GitHub would
  not run it (outside `.github/workflows/`, or in a subdirectory of it): a
  workflow copy nobody lints and nothing runs. It first proves its matcher
  on a scratch repository holding one offender of each kind.
- **script references** (`Scripts/check_script_references.sh`, MenoPower's
  guard): red when a script, workflow, order or tool file, or doc names a
  `Scripts/` path that does not exist, checked case-sensitively, so a path
  that macOS forgives but GitHub does not is caught too. Red as well on a
  script that nothing calls: no script, workflow or order-file row mentions
  it, and CLAUDE.md does not list it as run by hand. Red on a run that
  scanned no file or found no `Scripts/` path at all. Another repository's
  script is written with that repository as the first part of its path
  (`web-infra/Scripts/...`) and is not checked; a bare `Scripts/` path is
  read as forsgren's own. Unlike the gates above, it reads the working tree,
  untracked files included. It also keeps `Scripts/` flat: a script (`.sh`
  or `.py`) in any subfolder of `Scripts/` is red. MenoPower bans scripts
  that climb to the root with `..`; Yves ruled that ban N/A for forsgren
  while `Scripts/` is flat, because every script then reaches the root with
  the same single step (forsgren#1, 2026-10-01). This gate enforces the
  condition the ruling rests on, so a script subfolder means revisiting
  the ruling first. Data files in a subfolder are not scripts and stay
  allowed.
- **checkout pins** (`Scripts/test_workflow_checkout_pins.sh`, the estate's
  gate in coachretreat-website's copy): every `uses:` in a
  `.github/workflows/*.yml` file ends in a full 40-hex commit SHA, never a
  tag (`@v4`), a branch (`@main`) or a short SHA, because a tag or a branch
  is resolved when the runner fetches it and its owner can re-point it. The
  version goes in a comment after the SHA (`# v7.0.1`), by convention: the
  gate does not check it. A local action
  (`./...`) is this repository's own code and is skipped; a `docker://`
  reference has no exception and is red. Every `actions/checkout` must also
  set `persist-credentials: false`, so the job token is not left in
  `.git/config` for later steps. Red on a directory with no checkout or no
  `uses:` at all. Its proof (`Scripts/test_workflow_checkout_pins_mutations.sh`,
  row `mutation: checkout pins`) runs first and shows each kind of bad ref
  rejected for its own reason.

actionlint, zizmor, shellcheck and yamllint come from Homebrew, through
`Scripts/required_tools.txt` (see Installing and updating). As with the data
guard, untracked files are not checked: `git add -N` a new script first.

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

## CI

`.github/workflows/quality.yml` runs the same gates as `./sfl.sh`, on every
push to `main`, on every pull request into `main`, and by hand (Actions →
Quality → Run workflow).

**What runs where.** Locally, `./FBP.sh` runs `gofmt -w`, `./sfl.sh pre`,
`Scripts/build_site.sh` and `./sfl.sh post`. CI runs the same three phases
with nothing fixed: `Scripts/run_ci_phase.sh pre`, then
`Scripts/build_site.sh` into `.build/site`, then `Scripts/run_ci_phase.sh
post`. Both read `Scripts/gate_report_order.txt` with the same row rules, so
every gate runs in both, in the same order, under the same label. Before the
gates, CI checks out the commit, puts Homebrew's directories first on `PATH`
and exports `GOTOOLCHAIN` from `go.mod` (as `sfl.sh` does), runs
`Scripts/install_tools.sh` (as `sfl.sh` does) and `npm ci`. The runner is a
fresh machine on every run with none of the Homebrew tools the gates need,
so the installer puts them there; installing and upgrading costs nothing
lasting on a machine that is thrown away after the job. A tool still missing
after it fails the Install tools step by name.

**Check-only.** CI reports what the commit contains. gofmt runs as
`gofmt -l` (the `gofmt` row), never with `--fix`, and a gate that changes
the checked-out tree is a red row, even when it exits 0. That is how CI
treats `npm audit`: locally `Scripts/npm_audit_check.sh` may heal an
advisory with one `npm audit fix` and the new `package-lock.json` rides into
the commit; in CI the same heal is red, naming `package-lock.json`. Run
`./FBP.sh` and commit the result.

**Failures.** A failing gate does not stop its phase: every row runs, so one
run reports every failure, as `sfl.sh` does. The build runs after an
ordinary PRE red too; it is skipped after a secret-class finding (the secret
scan or the data guard), as `FBP.sh` skips it, and the POST gates are
skipped when the build did not succeed. The job's summary page lists every gate in the order
file's order, ✅, ❌ or `n/a`, with each gate's output below the table.
Gates that did not run are counted as unmeasured, never as passing.

**The run summary.** Above that table, every run page opens with the run's
key numbers (forsgren#8), written by the job's last step, which runs after a
failure or a cancel too: the status (succeeded, failed or cancelled, and the
phase it stopped in), the gates passed, failed and skipped in PRE and in
POST, the Go tests passed, the total checks (every individual check that
ran, counted once: each case of every self-test and gate, each Go test, and
a gate with no case lines as one; passed and failed), the coverage total
with its floor, the floors to raise (the coverage gate's FLOORWARN count), the pages generated, the
forsgren version, the commit and trigger (push, pull request with its
number, or by hand) and the duration. `Scripts/render_quality_summary.sh`
reads them from what the run already wrote (the gate rows and outputs, the
page-count sink, `cmd/forsgren/main.go`) and from the job's status and step
outcomes, passed through `env:`. A number that does not exist, from a phase
that never ran or an output that is missing, shows as `—` with the reason,
never as 0. The total checks read each gate's output with one case-line
grammar, written out in the renderer: a closing verdict (`OK: …`,
`✅ test_x`, `FAIL: … contract`) is never a case; a phase that never ran
makes the total `—` naming it, never a partial sum; a gate that never
reported is named as skipped, and a gate whose case lines are in a format
the grammar does not know is named rather than counted silently. Adding a
self-test or a case raises the number.

**From a red CI row to a local run.** A CI row carries the label sfl prints,
and the order file names the script and phase behind it:

```
grep '^gofmt|' Scripts/gate_report_order.txt   # gofmt|Scripts/check_gofmt.sh|pre|
./Scripts/check_gofmt.sh                       # that one gate
./sfl.sh pre                                   # or the whole phase
```

A POST gate reads `.build/site`, so run `./Scripts/build_site.sh` first.

**The runner.** The job runs on GitHub's hosted `macos-latest` image
(`runs-on: macos-latest`), a fresh virtual machine per run, thrown away
after it (Yves's ruling on forsgren#1, road to public: the runner swap). It
has Homebrew and a Go to start from; everything else comes from
`Scripts/install_tools.sh`, `npm ci` and the `go.mod` pins, as locally.

**On pull requests, safely.** Quality triggers on `pull_request` into
`main`, so a contributor's pull request shows the same gate results as a
local `./FBP.sh` run, and never on `pull_request_target`. A pull request
from a fork runs its own code here, which is safe only because of the two
things the ruling pairs with the trigger: the machine is GitHub's and is
thrown away after the job, and a fork's `pull_request` run gets a read-only
token (`contents: read`) and no secrets. The **quality trigger scope** gate
pins this job to `macos-latest`, and the rule holds for every workflow: the
**workflow triggers** gate below is red on any of them that triggers on a
pull-request event while one of its jobs runs anywhere but on a
GitHub-hosted runner. A new push to a pull request cancels its run in
flight; runs on `main` are never cancelled, each commit gets its own.

**Repository settings behind the gates.** On top of that, GitHub holds
every workflow run of a pull request from an outside contributor until the
maintainer approves it, and the repository requires every action to be
pinned to a full commit SHA, the rule **checkout pins** checks in the
files. Secret scanning with push protection and Dependabot alerts are on
too, behind the secret scan and npm audit gates. These are settings, not
files: no gate can see them.

**The DCO check, on pull requests.** `.github/workflows/dco.yml` triggers
on `pull_request` (never `pull_request_target`), as Quality does, and may
because its one job runs on a GitHub-hosted runner (`ubuntu-latest`), with
a read-only token (`contents: read`, `pull-requests: read`). It holds every commit of the pull request to the
Developer Certificate of Origin (see [CONTRIBUTING.md](CONTRIBUTING.md)):
`Scripts/check_dco.sh` is red on a commit with no `Signed-off-by:`
trailer, or with one whose email is not the commit author's, naming the
commit and its subject. A trailer counts only as a whole line of the
message's last paragraph, never in the body, mid-line or as the subject;
the emails are compared without case and never printed. Merge commits get no
exception. Bots are (ruled 2026-10-02, for Dependabot's security updates): a
commit is exempt, named as such, when GitHub links it to an account of type
`Bot` and that bot opened the pull request (`pull_request.user`, passed
through `env:`). Never on the commit's author email, which anyone can write,
nor on the linked account alone, which GitHub derives from that email. The job never checks out the pull request's code: it reads the
commit list through the API (`gh api`, the pull request number passed
through `env:`, never as `${{ }}` inside `run:`), and checks out only
`Scripts/check_dco.sh`, at the pull request's base commit, so a pull
request cannot change the check that judges it. A pull request can still
change `dco.yml` itself, which GitHub reads from the pull request: the
review of such a change is the guard there. The check does not run in
`sfl` or Quality, since a commit on `main` has no pull request; its
self-test does (**DCO sign-off self-test**, `Scripts/test_check_dco.sh`,
offline, with mutation proofs for the last-paragraph rule, the email
comparison, the account-type rule and the opener comparison), and **gate wiring** is red when `dco.yml` stops running
the check or the self-test loses its row.

**The metrics workflow, for installations.** `.github/workflows/metrics.yml`
is the reusable workflow a data repository calls daily (see Running
forsgren). It triggers on `workflow_call` only, so it never runs in this
repository and no pull request can start it. Its one job runs on
`ubuntu-latest`, in the caller's repository and with the caller's token,
checks out the caller's repository only (never forsgren's), and asks for
`pages: write`, `id-token: write` and `contents: read` (a top-level
`permissions: {}` gives the workflow nothing else). It takes no inputs: the
caller's `uses: …/metrics.yml@<commit>` line is the only version. Its
steps: set up Go (`actions/setup-go` on exactly `go.mod`'s toolchain,
`cache: false`), check its own `job.workflow_sha` is a full 40-digit commit
and its own `job.workflow_repository` one `owner/name`, then
`go install github.com/<that repository>/cmd/forsgren@<that commit>`,
check out the caller's repository (`actions/checkout`, pinned at Quality's
commit, `persist-credentials: false`), `forsgren check-config --config
forsgren.config.yml` (its message printed between
`::stop-commands::<token>` and `::<token>::`, a fresh random token per
run, so a line of it that starts with `::` never runs as a workflow
command), `forsgren render`, then `actions/upload-pages-artifact` and
`actions/deploy-pages` into the `github-pages` environment. The job
context, not the `github` context: in a called workflow the `github`
context is the caller's. `setup-go` exports `GOTOOLCHAIN=local`, so
`go install` builds with that Go and never switches to another. The commit
and repository reach the shell through `env:`, never as `${{ }}` inside
`run:`. The two checks are regexes inside the workflow, not a script under
`Scripts/`: the job has no checkout of forsgren, and the only commit it
could fetch one at is the one still unchecked. The **metrics workflow** pin
below executes that very block.
Nothing in this repository runs the workflow, so no gate does; the pin and
actionlint, zizmor, yamllint, checkout pins and workflow triggers, which read
every workflow, are what check it.

**No paths filter, on purpose.** The secret scan, the data guard, stray
tracked files and script references read every tracked file, so a filter
on paths would leave some change that runs no gate.

Six PRE gates keep the CI honest:

- **gate wiring** (`Scripts/test_gate_wiring.sh`, konenki-website's,
  adapted): every runnable row of the order file has phase `pre` or `post`
  (any other phase runs in neither); `FBP.sh` and `quality.yml` each run
  PRE, the build and POST in that order; `sfl.sh` and
  `Scripts/run_ci_phase.sh` read a row with the same rules; every script
  that no row names is a declared exemption with the runner it must still
  be run by. It also runs `run_ci_phase.sh` itself, over the real order
  file with a stub at every declared path (each row must run exactly once,
  in its own phase, in file order) and over made-up order files (failures,
  the secret-class exit, the tree check, a phase with no row).
- **quality trigger scope** (`Scripts/test_quality_trigger_scope.sh`): the
  workflow runs on every push to `main` and every `pull_request` into it,
  neither with a `paths` or `paths-ignore` filter, never on
  `pull_request_target`, and on `workflow_dispatch`; and its job runs on
  `macos-latest`, the GitHub-hosted image that makes the pull-request
  trigger safe.
- **workflow triggers** (`Scripts/check_workflow_triggers.sh`, forsgren's
  own): no workflow in `.github/workflows` triggers on `pull_request`,
  `pull_request_target`, `pull_request_review` or
  `pull_request_review_comment` (the two review events also run a fork's
  code) while one of its jobs may run on a self-hosted runner. A job counts
  as GitHub-hosted only when its `runs-on` is a single GitHub image label
  (`ubuntu-*`, `windows-*`, `macos-*`); the `self-hosted` label, a custom
  label, a list, a runner group, an expression such as `${{ matrix.os }}`
  and a reusable-workflow job are all judged as self-hosted, because the
  gate cannot prove otherwise. Red as well on a workflow whose `on:` it
  cannot read, and on a run that found no workflow file. It reads the YAML
  with awk, not a YAML library: PyYAML is a Python module, not a command,
  so nothing here installs it, and a parser that depends on it would stop
  gating on the first machine without it.
- **metrics workflow** (`Scripts/test_metrics_workflow.sh`, forsgren's
  own): `metrics.yml` triggers on `workflow_call` and nothing else, and
  declares no inputs; no `run:` block expands a `${{ }}` expression; the
  step "Install forsgren from this workflow's own commit" takes
  `FORSGREN_SHA` from `${{ job.workflow_sha }}` and `FORSGREN_REPOSITORY`
  from `${{ job.workflow_repository }}`, and its `run:` block, executed
  here with a stub `go`, runs exactly
  `go install github.com/yveshanoulle/forsgren/cmd/forsgren@<commit>` for
  `yveshanoulle/forsgren`, installs `github.com/acme/forsgren` for the fork
  `acme/forsgren`, and refuses before `go` runs any commit that is not 40
  lower-case hex digits (a tag, a branch, `latest`, a short or long hash,
  capitals, surrounding spaces, a trailing `;id` or newline, empty) and any
  repository that is not one `owner/name`; `actions/setup-go` comes before
  that step and installs exactly `go.mod`'s toolchain, so a toolchain bump
  in `go.mod` without one here is red; the step "Check out the caller's
  repository" uses `actions/checkout` at the commit Quality's checkout
  uses, with `persist-credentials: false`; the step "Check the caller's
  forsgren configuration", executed with a stub `forsgren`, runs exactly
  `forsgren check-config --config forsgren.config.yml`, fails the job on a
  refusal with the message in the log and after a cross mark in the step
  summary, and leaves no line of the message that starts with `::` live as a
  workflow command, under a token that differs per run; the same step,
  executed with the real `forsgren` built from the checkout, is refused for
  a missing and an invalid `forsgren.config.yml` and passes a valid one;
  and install, checkout, config check and render come in that order. Each
  pin is shown failing, with its own reason, on a mutant of the real file.
- **quality-report render** (`Scripts/test_render_quality_report.sh`): the
  summary renderer (`Scripts/render_quality_report.sh`) keeps the declared
  order, exits 0 on a report it rendered, tells an empty or partial run from
  a clean one, and does not count an `n/a` row as a gate that should have
  reported.
- **quality-run summary** (`Scripts/test_render_quality_summary.sh`,
  forsgren's own): the run summary (`Scripts/render_quality_summary.sh`)
  renders every number of a green run, says where a red, cancelled or
  setup-stopped run stopped, names a pull request's number, exits 0 on
  whatever it is given, and shows `—` with the reason for a phase that
  never ran or an output that is missing, never 0; its total checks count
  every case-line format of the real gates once, each Go test once, no
  verdict line, a red gate's failures, and name a phase they are missing, a
  gate that never reported and a case-line format they do not know; shown
  failing, each with its own reason, on mutants that write 0 instead, that
  sum only the phases they have, that count verdict lines, and that drop
  the unknown-format guard.

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

**The Go tools are pinned in `go.mod` too.** golangci-lint, deadcode
(`golang.org/x/tools`) and govulncheck (`golang.org/x/vuln`) are `tool`
lines in `go.mod`, with every module they pull in checksummed in `go.sum`,
and the gates run them through `go tool` (Go builds each once and caches
it), so CI and every machine run the same versions. They are never Homebrew
tools, and never `go install ...@latest`: neither has a lockfile. To move
one to a new version:

```
go get -tool github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.15.0
go get -tool golang.org/x/tools/cmd/deadcode@v0.50.0
go get -tool golang.org/x/vuln/cmd/govulncheck@v1.8.0
go mod tidy
```

then run `./FBP.sh` and commit `go.mod` and `go.sum` together (the go mod
tidy gate is red when the `go mod tidy` is forgotten). A new version can
bring new findings; they are fixed in the code like any other.

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
`node_modules` has no htmlhint or no jscpd, so it would not pick a bump up on
its own; forsgren#2 tracks reinstalling on a lockfile change).
Check that `package.json` still shows an exact version, and commit both files.

## The tooling's own fixtures

The rest of the PRE rows test the build and gate tooling itself, so a
broken runner cannot report green:

- **sfl pull contract** (`Scripts/test_sfl_pull.sh`): sfl pulls with
  `--ff-only` and stops with exit 3, naming the recovery command, when it
  cannot fast-forward.
- **npm manifest policy self-test**, **npm-audit self-test** and the other
  `... self-test` rows: each drives its gate on made-up input before the
  gate runs.
- **tool install self-test** (`Scripts/test_install_tools.sh`): the
  installer installs a missing tool, upgrades a present one, and is red when
  Homebrew reports success but the tool is still not runnable, or the list
  is empty.
- **Go toolchain pin self-test** (`Scripts/test_go_toolchain.sh`):
  `Scripts/go_toolchain.sh` prints go.mod's `toolchain` version and is red
  without one.
- **build-site self-test** (`Scripts/test_build_site.sh`): the build
  compiles the binary, renders the site and writes the page count only on
  full success.
- **gate-failure summary**, **step table**
  (`Scripts/test_summarize_gate_failure.sh`,
  `Scripts/test_render_step_table.sh`): sfl's end-of-run reason lines and
  step table, with their counts.
- **sfl drives from the order file**
  (`Scripts/test_sfl_drives_from_order_file.sh`): sfl names no gate label
  itself, every row names an executable script, every `Scripts/test_*.sh`
  is declared by a row, and the secret scan and the data guard carry
  `secret-class`.
- **FullBuildAndPush commit-message block** and **FullBuildAndPush
  build-site page count** (`Scripts/test_fbp_commit_message.sh`,
  `Scripts/test_fbp_build_pagecount.sh`): the real `FBP.sh`, run in a
  throwaway repository with stub gates, prints its message, reaches PRE,
  blocks a secret-class commit with the right hint, signs off its green and
  `*** RED ****` commits as the identity that ran it (a commit that then
  passes `Scripts/check_dco.sh`), and fails the build row
  by name on a missing, unreadable, non-numeric or zero page count.

## Status

The bootstrap is done (forsgren#1, 2026-10-02): the build, the gates, CI
and these docs. forsgren itself renders one placeholder page; reading
GitHub, the history file and the charts come next, then a template
repository for installations. forsgren is open source, under EUPL-1.2 (see
Licence).

## Licence

forsgren is licensed under the European Union Public Licence v. 1.2
(EUPL-1.2): see [LICENSE](LICENSE). Contributions are accepted under the
same licence, with a Developer Certificate of Origin sign-off on every
commit and no CLA: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Report a vulnerability privately, never in a public issue: see
[SECURITY.md](SECURITY.md).
