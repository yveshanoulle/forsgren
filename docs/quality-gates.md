# Quality gates

## Quality gates

`./FBP.sh` runs the gates in two phases around the build: `./sfl.sh pre`
checks the repository before the site is generated, `Scripts/build_site.sh`
renders the site into `.build/site`, and `./sfl.sh post` checks that
generated output. `Scripts/gate_report_order.txt` declares every gate, its
phase and its order; a gate's self-test always runs in PRE, before the gate
it validates. The six static gates (gofmt, Go lint, actionlint, shellcheck,
yamllint, zizmor) and their self-tests form the static block, right after the
secret-class rows; a red row in it stops the run early with every later gate
skipped and named (forsgren#231; [development.md](development.md)). On
Quality, actionlint, shellcheck, yamllint and zizmor with their self-tests run
in their own `lint` job, its own red/green check (forsgren#282;
[ci.md](ci.md)); gofmt and Go lint stay in the main job.

Three PRE gates come first and are secret-class, so a finding blocks the
commit itself:

- **secret scan** (`Scripts/check_secrets.sh`, the estate's gitleaks gate):
  gitleaks over the working tree, before anything is staged, under `.gitleaks.toml`
  (the default rules, with `${{ secrets.NAME }}` references allowed, since
  they are names, not values). Red, never skipped, when gitleaks is
  missing. Its self-test (`Scripts/test_check_secrets.sh`) plants a key and
  shows it caught.
- **data guard** (`Scripts/check_data_guard.sh`): see [The data
  guard](development.md#the-data-guard).
- **private names** (`Scripts/check_private_names.sh`): this repository is
  public, so no tracked or untracked (not ignored) file or path may name a private
  repository. The list of names is kept outside the repository: in the file
  `~/.config/forsgren/private-names` (or the file `FORSGREN_PRIVATE_NAMES_FILE`
  points to), one name per line, `#` for comments; that file is the source
  of truth. In CI the Actions secret `FORSGREN_PRIVATE_NAMES`, the same names
  newline-separated, which `quality.yml` passes to the PRE step through
  `env`, and the Dependabot secret of the same name are synchronized copies,
  never edited on their own: after changing the file, run
  `./Scripts/sync_private_names_secrets.sh` by hand (it needs the
  maintainer's `gh` login) and it sets both, for the repository the
  clone's `origin` remote names (or `SYNC_REPO=<owner>/<repo>`; no tracked
  file writes the name). An external fork pull request
  receives neither secret, so the gate fails there (exit 2, no list); that
  is intended: CI always fails without the secret or with an emptied one.
  In GitHub Actions a missing or empty secret is exit 2 with a line that
  names it, `the Actions secret FORSGREN_PRIVATE_NAMES is not set or is
  empty here`, and says a fork's pull request gets no secrets, so the
  maintainer runs `./FBP.sh` on the branch instead; a local run with no list
  names the three local sources. An empty `FORSGREN_PRIVATE_NAMES_FILE`
  counts as unset, in the gate and in `Scripts/ensure_private_names_file.sh`
  alike. A repository-specific EXTRA list adds names that only this
  repository must keep out, merged with the shared list and never replacing
  it: locally the file `FORSGREN_PRIVATE_NAMES_EXTRA_FILE` points to, else
  `~/.config/forsgren/private-names-extra/<name>` (`<name>` is the basename
  of the origin remote URL without `.git`); in CI the Actions secret
  `FORSGREN_PRIVATE_NAMES_EXTRA`, which `quality.yml` passes through `env`.
  A missing extra list is fine; an extra file that exists but cannot be read
  is exit 2. `./Scripts/sync_private_names_secrets.sh` also syncs the extra
  file, when it is there, into the Actions and Dependabot secrets
  `FORSGREN_PRIVATE_NAMES_EXTRA`, and leaves them alone when it is not.
  The gate searches
  `git ls-files` and `git ls-files -o --exclude-standard` (what `git add -A`
  would stage), case-insensitively, for a substring (a listed name
  inside a longer token is a hit). Its failure line
  names `file:line`, or `tracked path #N in git ls-files`, and never the
  name, so the gate's own output reveals none. The repository's own name (the
  basename of its `origin` remote, ignoring case) is left out of the list, in the
  scan and in `--message` (canon v2, forsgren#241); no origin keeps every name. A commit message is checked too:
  `FBP.sh` hands it to `Scripts/check_private_names.sh --message -` (the
  same list and matching, the message on stdin, never in a file an interrupt
  could leave behind, no repository scan) first of all, and on
  a hit it makes no commit, runs no gate, prints one `❌` line that never holds
  the name or the message, and exits non-zero; with no list or an empty one the
  message check passes. No list, an env list with no
  names, a missing names file, or no tracked file is exit 2 and a red, never a
  silent pass; locally an existing names file with no names passes with
  `0 names searched`. Known limit: names are matched as bytes in each file's
  own encoding, so a file in an encoding that is not ASCII-compatible (UTF-16
  or UTF-32, for example) is not searched effectively: a name in it is not
  found and the file passes. The names never touch the disk: the gate hands
  them to `grep` through a process substitution, not a temp file. Its
  self-test (`Scripts/test_check_private_names.sh`) uses made-up names and
  proves with a mutant that prints the matched line that the no-name check
  can fail.
  Locally, `FBP.sh` creates an empty list file when none exists, so the gate
  passes with `0 names searched`; CI never does.

Two PRE gates check the page templates and the pages they render:

- **html duplication** (`Scripts/check_html_dupl.sh`, the estate canon; its
  target and ceiling are read from `Scripts/site_settings.txt`, see Site
  settings below): jscpd measures the share of duplicated markup in
  the `html/template` files under `internal/page/templates` and the gate
  compares it to a recorded ceiling, today 0.00%. The ceiling only moves
  down: a red is fixed by removing the duplication, never by raising the
  number. Red on a run that scanned zero `.html` files. jscpd is pinned like
  the linters below.
- **site settings** (`Scripts/lib_site_settings.sh` and
  `Scripts/site_settings.txt`, the estate canon, forsgren#215): the values
  the shared gate scripts read per repository, through one reader that fails
  closed (a missing file, an unknown or missing key is exit 2, never a
  guessed default): `site_dir=.build/site` (the generated site, read by
  HTMLHint, Stylelint and lint coverage), `html_dupl_target` and
  `html_dupl_ceiling` (the templates, 0.00%), `required_pages_manifest`. The
  reader accepts one optional leading dot per path component, which
  `.build/site` needs. Its self-test is `Scripts/test_lib_site_settings.sh`.
  The other per-repository data of the canon gates sit in empty exception
  files, each with a required reason per row and a red for a row that excuses
  nothing: `Scripts/htmlhint_exceptions.txt`,
  `Scripts/privacy_posture_exceptions.txt`,
  `Scripts/workflow_trigger_exceptions.txt` and
  `Scripts/required_pages_exclusions.txt`.
- **golden pages** (`Scripts/check_golden_pages.sh`, forsgren's own,
  forsgren#12 step 8): the build renders the page without an installation's
  config or history, so the POST gates below never see the page with data
  or the no-projects line. This gate runs three of them, HTMLHint, privacy
  posture and html duplication, generated page, on each golden page of
  `internal/page/testdata` (the pages the Go tests pin byte for byte to what
  forsgren renders, the page with data from a made-up history), each page
  alone as the site's one page is. A finding names the page and the gate.
  Red on a directory with no golden page.

Two PRE gates run the Go tests and the formatting:

- **Go tests** (`Scripts/check_go_tests.sh`): `go test ./...` over the
  module. Red on a failing test, on a run that found no test at all, and
  on a package under `node_modules` (go.mod's `ignore node_modules` is what
  keeps npm's vendored Go out of `./...`; this is its guard). A green run
  leaves the coverage profile the Go coverage gate reads. One of the tests
  guards a release (forsgren#148, decision #170; forsgren#237):
  - **Docs name no running version** (`cmd/forsgren/docs_version_test.go`,
    forsgren#237): no "Forsgren X.Y.Z" and no "forsgren X.Y.Z needs more
    configuration" in `README.md` and `docs/*.md`, wrapped lines joined, with
    any X.Y.Z (the docs write `<version>`). Since forsgren#340 `main.go` holds
    no version (a build without version information says `dev`), so the test
    no longer looks for the released version. Other versions ("From 1.3.0", "v0.8.7 to v1.0.0") name past
    releases on purpose and are allowed. `TestDocsStillSayWhereTheVersionIs`
    keeps the pin from going vacuous.
  - **Tested-with major** moved to the release plan (forsgren#237, step 5b):
    no release bumps `version` any more, so a test on it could not see a new
    major. `Scripts/release_plan.sh` refuses a major until each agent file's
    Tested-with line (the last version on it) names the new major, through
    `Scripts/release_agent_proofs.sh`; its self-test also holds the real agent
    files to one common major, so the rule cannot go vacuous.
- **gofmt** (`Scripts/check_gofmt.sh`): check-only, `gofmt -l` over every
  Go file git tracks or would add; red naming each unformatted file, and on
  no Go file found. `./FBP.sh` runs the same script with `--fix` before the
  gates, so locally it sees a formatted tree; CI never fixes.

Seven more PRE gates check the Go code:

- **go mod tidy** (`Scripts/check_go_mod_tidy.sh`, another estate repository's check made
  check-only): red when `go.mod` or `go.sum` is not what `go mod tidy`
  would write, a require missing or unneeded, a `go.sum` line missing or
  stale, with the diff tidy would apply. It runs `go mod tidy -diff`, so it
  never rewrites either file; the fix is `go mod tidy`, committed with the
  change that needed it. Red, as a tool error, when tidy could not run (a
  `go.mod` it cannot parse, a module it cannot fetch). Its self-test
  (`Scripts/test_check_go_mod_tidy.sh`) runs offline and shows, by
  mutation, that `-diff` is what makes the gate red instead of a silent
  rewrite.
- **Go lint** (`Scripts/check_go_lint.sh`, another estate repository's): golangci-lint
  over the module under `.golangci.yml`, ported from another estate repository `shared/`,
  its strictest module: govet, errcheck, staticcheck, gosec, dupl
  (80 tokens), funlen (60 lines, 40 statements), lll (120), gocognit (10)
  and gocyclo (above 6 is red), plus the gofmt and goimports formatters,
  test code included. revive is enabled too but runs no rule: the config's
  one entry, which disables `exported`, replaces revive's default rule set
  (as in another estate repository; an open point on forsgren#1). No issue cap, so every finding is listed. Unlike
  `shared/`, gosec's G101 (a hardcoded credential) is not excluded. A
  finding is fixed in the code: an exclusion or `//nolint` needs Yves's
  approved issue. Red on a module with no Go package, and when golangci-lint
  could not run. Its self-test (`Scripts/test_check_go_lint.sh`) shows
  complexity 7 red (in a test file too) and 6 green, a credential red under
  G101, and, by mutation, that the threshold and the missing G101 exclusion
  in `.golangci.yml` are what decide those cases.
- **Go test duplication** (`Scripts/check_test_dupl.sh`, another estate repository's): the
  same `dupl` rule pointed at `_test.go` files only, which `.golangci.yml`
  leaves to it, so test code is judged once. Red on a module with no test
  file, and a tooling error (exit 2) when the tool exits 1 without a `(dupl)`
  line (forsgren#217).
- **Go file length** (`Scripts/check_file_length.sh`, another estate repository's
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
- **Go coverage** (`Scripts/check_coverage.sh`, another estate repository's
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
- **Go vulnerabilities** (`Scripts/check_govulncheck.sh`, another estate repository's):
  govulncheck over the module, red when the code reaches a symbol the Go
  vulnerability database lists, naming each entry. When the database does
  not answer (`curl -sf --max-time 5 https://vuln.go.dev/index/db.json`
  fails: offline, refused, a timeout, an HTTP error) the check is skipped,
  as in another estate repository: one `⚠️ SKIP: govulncheck did not run` line naming the
  database, a `::warning::` in GitHub Actions, exit 0, and never the `OK`
  line of a pass. With `FORSGREN_VULN_DB_REQUIRED=1` (the scheduled run,
  forsgren#87) an unreachable database is red instead, never a skip.
  `FORSGREN_VULN_DB` points it at another database. Its
  self-test (`Scripts/test_check_govulncheck.sh`) runs offline against a
  database it writes, with one made-up entry, and shows a call to the listed
  symbol red, an unreachable database a skip (red when required) and, by mutation, that the
  probe is what makes offline a skip rather than a tool error.
  The tool path comes from `go tool -n govulncheck` on stdout alone: on a
  fresh runner go's `go: downloading ...` lines stay on stderr, and a path
  that is not an executable is red with its own line (forsgren#210). The
  self-test fakes that runner with a `go` shim, and shows by mutation that
  the old `2>&1` capture is the exit 127 of the first scheduled run.
- **Go dead code** (`Scripts/check_deadcode.sh`, another estate repository's): `deadcode
  -test ./...`, red on any function, exported or not, that neither a main
  package nor a test reaches, each named with its file and line. The fix is
  to delete it, never to call it from a test to keep it alive. Red on a
  module with no main package and when deadcode could not run (a module that
  does not compile). Its self-test (`Scripts/test_check_deadcode.sh`) shows
  both kinds of dead function red, a test-only helper green and, by
  mutation, that `-test` is what keeps it green.

Go lint, Go test duplication, Go vulnerabilities and Go dead code run the
golangci-lint, govulncheck and deadcode pinned in `go.mod` (see [The
tools](development.md#the-tools)).

They resolve and run the tool through one sourced helper,
`Scripts/lib_go_tool.sh` (forsgren#216): the path is what `go tool -n <tool>`
prints on stdout alone, it must be an executable file, and the tool's own exit
code comes back unchanged, so a tool that fails is never reported as a pass.
Its self-test is `Scripts/test_lib_go_tool.sh`. Each gate and its class are
listed in [Gate classification](gate-classification.md).

Seven PRE gates read the repository's own scripts and files:

- **actionlint** (`Scripts/check_actionlint.sh`, the estate's gate in
  coachretreat-website's copy): every `.github/workflows/*.yml` file under
  `.actionlint.yaml`. Valid YAML is not a valid workflow: actionlint knows
  which contexts exist where (a `runner.temp` in a job-level `env:` block
  once made GitHub reject another estate repository's whole workflow, so not one gate
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
- **zizmor** (`Scripts/check_zizmor.sh`, another estate repository's gate): the GitHub
  Actions security linter, over `.github` under `.github/zizmor.yml`, every
  `.yml` and `.yaml` workflow. actionlint asks whether a workflow is valid,
  zizmor whether it is safe; the class it exists for is template injection,
  an attacker-controlled `${{ ... }}` (an issue title, a branch name)
  expanded into a `run:` block, where it runs as shell with the job's token
  on the runner. It runs at another estate repository's setting: offline, High
  findings only, the default persona. A Medium finding such as a checkout
  that keeps its credentials is not its red; checkout pins owns that rule.
  The config suppresses nothing: a suppression needs a finding someone has
  looked at and Yves's explicit yes recorded on a GitHub issue. Red on a
  directory with no workflow file. Its self-test
  (`Scripts/test_check_zizmor.sh`) shows each of these, with two mutation
  proofs: the severity threshold is what keeps a Medium out, and the
  config is read from the scanned directory.
- **shellcheck** (`Scripts/check_shellcheck.sh`, the estate's gate from
  another estate repository): every `*.sh` file, and every file without an
  extension whose first line is a bash or sh shebang, at any depth, that git
  tracks or does not ignore. The targets come from `repo_files` (see the
  rule below), so a new script is checked the moment it exists, with no list
  to keep up to date. Red on any finding, and on a
  run that found no script. No script is excluded, and an empty
  `EXCLUDE_ALLOWED` is the normal state. An exclusion needs three things:
  the entry in the gate's `EXCLUDE_ALLOWED`, a sentence here naming the
  script and the reason, and Yves's explicit yes recorded on a GitHub issue,
  which that sentence links.
  A finding is fixed in the script. The same rule holds for a single line:
  it may carry a `# shellcheck disable=SCxxxx` only with a comment giving the
  reason, and with Yves's explicit yes recorded on a GitHub issue, which
  that comment links.
- **Files a step adds are judged in that step** (forsgren#204): FBP commits
  after its gates run, so a new file is still untracked while they do. The
  shellcheck, yamllint, markdown links, npm manifest policy and data guard
  gates list their files through `repo_files` in `Scripts/lib_repo_files.sh`
  (`git ls-files --cached --others --exclude-standard`): the tracked files and
  the untracked ones that git does not ignore, which the next commit will
  carry; an ignored file is left alone. The self-test of each gate has a case
  with an untracked file that has a finding and one with an ignored file.
  `check_gofmt.sh` and `check_private_names.sh` already did the same.
- **yamllint** (`Scripts/check_yamllint.sh`, from another estate repository): every
  `.yml` and `.yaml` file that git tracks or does not ignore, under the rules
  in `.yamllint.yml` (another estate repository's). konenki lints its workflow
  directory by name; here the targets come from `repo_files`, as for
  shellcheck, so the
  workflow and any other YAML are covered the moment they exist.
  `.yamllint.yml` is itself tracked YAML and is linted too, so the list is
  never empty, and a run that found none is red.
- **quality trigger scope** and **quality runner pins**
  (`Scripts/test_quality_trigger_scope.sh`, the sites' shared canon, and
  `Scripts/test_quality_runner_pins.sh`, forsgren's own; forsgren#240): the
  shared one is red when `quality.yml` has a `paths-ignore` filter, a `paths`
  filter that lacks a glob the gates read, or no `pull_request` trigger (no
  filter at all passes and reads no settings). The pins are red on a missing
  push or `pull_request` trigger on `main`, any `paths` or `paths-ignore` on
  either, a `pull_request_target`, no `workflow_dispatch`, and any job off
  `macos-latest`; each is proven against a synthetic workflow that must be
  rejected.
- **stray tracked files** (`Scripts/test_no_stray_tracked_files.sh`,
  another estate repository's): red on a tracked `.DS_Store` at any depth, and on a
  tracked `.yml`/`.yaml` with a top-level `jobs:` key anywhere GitHub would
  not run it (outside `.github/workflows/`, or in a subdirectory of it): a
  workflow copy nobody lints and nothing runs. It first proves its matcher
  on a scratch repository holding one offender of each kind.
- **script references** (`Scripts/check_script_references.sh`, another estate repository's
  guard): red when a script, workflow, order or tool file, or doc names a
  `Scripts/` path that does not exist, checked case-sensitively, so a path
  that macOS forgives but GitHub does not is caught too. Red as well on a
  script that nothing calls: no script, workflow or order-file row mentions
  it, and CLAUDE.md does not list it as run by hand. Red on a run that
  scanned no file or found no `Scripts/` path at all. Another repository's
  script is written with that repository as the first part of its path
  (`source-repo/Scripts/...`) and is not checked; a bare `Scripts/` path is
  read as forsgren's own. Unlike the gates above, it reads the working tree,
  untracked files included. It also keeps `Scripts/` flat: a script (`.sh`
  or `.py`) in any subfolder of `Scripts/` is red. Another estate repository bans scripts
  that climb to the root with `..`; Yves ruled that ban N/A for forsgren
  while `Scripts/` is flat, because every script then reaches the root with
  the same single step (forsgren#1, 2026-10-01). This gate enforces the
  condition the ruling rests on, so a script subfolder means revisiting
  the ruling first. Data files in a subfolder are not scripts and stay
  allowed.
- **npm lockfile sync** (`Scripts/check_npm_lock_sync.sh`, forsgren's own,
  forsgren#2): `package.json` and `package-lock.json` must agree. The
  dependencies, devDependencies, optionalDependencies and peerDependencies of
  `package.json` are compared, by name and exact version, with the same four
  of the lockfile's root entry (`packages[""]`), offline, with jq. Red with
  one line per difference (a version that differs, a dependency the lockfile
  lacks, one only the lockfile has) and the fix, `npm install
  --package-lock-only`. CI finds the same mismatch at `npm ci`; this says it
  in PRE, before anything runs on a tree that does not match its manifest.
  Its self-test (`Scripts/test_check_npm_lock_sync.sh`) runs first.
- **npm install sync** (`Scripts/npm_sync_install.sh`, forsgren#2): not a
  gate but sfl's install step, with a row for its self-test
  (`Scripts/test_npm_sync_install.sh`). It runs `npm ci` when `node_modules`
  is missing or was installed from another lockfile or Node major, judged by
  a stamp, `node_modules/.package-lock.sha256`, holding the lockfile's sha256
  and `node<major>`. The stamp is written only after a successful `npm ci`.
- **Node pin** (`Scripts/check_node_pin.sh`, forsgren's own, forsgren#2,
  decision #190): the `node` on `PATH` must be the major pinned in `.nvmrc`
  (one line, a whole major, read by `Scripts/node_pin.sh`). Red with the
  running `node --version`, the pinned major and the fix (`brew install
  node@26`, or `brew upgrade node` when that major is Homebrew's current one),
  and red when node is missing or `.nvmrc` is malformed. It cannot repair
  anything: Node does not download itself the way Go does, so installing is
  the maintainer's. `sfl.sh` runs it right after the tool install. Two
  self-tests (`Scripts/test_node_pin.sh`, `Scripts/test_check_node_pin.sh`)
  run first.
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
- **workflow node pin** (`Scripts/test_workflow_node_pin.sh`, forsgren's own,
  forsgren#2): a workflow that runs `npm`, `npx` or `node` in a `run:` line
  must have an `actions/setup-node` step pinned by a full commit SHA with a
  `# vX.Y.Z` comment, setting `node-version-file: .nvmrc`, and placed before
  the first step that runs `Scripts/install_tools.sh` or `npm ci`. Red with
  the workflow's path and the broken part otherwise. This is CI's half of the
  Node pin: the same file, `.nvmrc`, that the **Node pin** gate enforces
  locally. Its fixtures are synthetic workflows (one per broken shape) plus
  the real ones, and a mutation proof shows the SHA check is what refuses a
  tag.
- **git sandbox isolation** (`Scripts/test_git_sandbox_isolation.sh`, forsgren#228,
  scope forsgren#251): every git-using self-test runs with `GIT_DIR` and its
  companions pointing at a decoy repository. Quality runs all of them, each
  ONCE, under the decoy with `GIT_DIR` and `GIT_INDEX_FILE` (the shape that
  reaches every push the all-three shape reaches), the leak check done after
  that single run (`isolation: Quality, each self-test runs once under the
  decoy`, forsgren#251 step 2); locally each runs twice, once per leak shape.
  Locally (FBP, `GITHUB_ACTIONS` unset) only the affected ones run: a self-test whose
  own file, or any file it names (followed transitively), changed against the
  merge base with `origin/main`, counting committed, staged, unstaged and
  untracked changes. A change to the gate or a library it sources, or no
  `origin/main`, runs all; none affected prints `isolation: 0 of N self-tests
  affected, full run in Quality` and passes. A Go change (`cmd/`, `internal/`,
  `go.mod`, `go.sum`) counts for a self-test that builds or runs the tool only
  while some non-test Go file can start a program (forsgren#258): it imports
  `os/exec`, or calls `os.StartProcess` or `syscall.Exec`, `ForkExec` or
  `StartProcess`; `*_test.go` and `testdata` do not count. The check reads the
  working tree at gate time, so a change that adds such a file turns the old
  rule back on at once. Today none does, so a Go change selects nothing; the
  gate prints `isolation: Go changes select nothing, no non-test Go file starts
  a program`, or `isolation: Go changes count, <file> starts a program`.
  `FORSGREN_ISOLATION_FULL=1` forces the full run. In Quality this gate runs in
  its own `isolation` job (forsgren#259); the browser gates and their
  self-tests run in the `browser` job. Its scope self-test, which also proves the Quality single run (each
  self-test once; a leaking self-test turns it red naming the self-test, the
  single run and the reason), is `Scripts/test_git_sandbox_isolation_scope.sh`.
- **quality jobs pin** and **merge quality report self-test**
  (`Scripts/test_quality_jobs.sh` and `Scripts/test_merge_quality_report.sh`,
  forsgren's own, forsgren#259): Quality runs its slowest gates in parallel
  jobs of one workflow (docs/ci.md, Jobs). In CI the git sandbox isolation
  self-test and the step summary isolation gate run in the `isolation` job,
  and actionlint, shellcheck, yamllint and zizmor with their self-tests in the
  `lint` job (forsgren#282; `Scripts/ci_job_groups.txt`; the order file is
  unchanged, and `sfl.sh` and FBP run every row as before).
  The pin is red when the isolation job is missing, off `macos-latest` or
  without the main job's setup (the lint and browser jobs likewise, the lint
  job running exactly its PRE rows, and the browser job must run
  PRE, its own site build, then POST), when a `run_ci_phase.sh` call lacks its job
  name, when a step names an isolation or lint gate itself, when the group
  file does not give the lint job exactly its nine rows or a lint row is no
  pre row, when a job's hand-over is
  not `if: always()` or not under its name, when the report job lacks a job in
  `needs:`, `if: always()`, the merge, or a gate job's `QS_<JOB>_RESULT` in
  the status from the jobs' results,
  when `continue-on-error` softens a job, when another workflow is named
  Quality, or when `release_quality.sh` reads a job and not the run. The
  merge self-test proves the hand-over, the merge, the duplicate refusal and
  the status (cancelled outranks failure, a skipped job is a failure).
- **dependabot config** (`Scripts/test_dependabot_config.sh`, forsgren's own,
  forsgren#86): `.github/dependabot.yml` declares `gomod` and `github-actions`,
  each at directory `/`, with `schedule: interval: cron` (04:00 UTC, so a
  weekend release is seen; `interval: daily` runs Monday to Friday only), a
  `commit-message` prefix, `groups` with `patterns`, `cooldown` with
  `default-days: 3`, and a comment line directly above each of `schedule:`,
  `commit-message:`, `groups:` and `cooldown:`. Red with the file and the
  broken part. Its fixtures are synthetic files (one per broken shape) plus the
  real one, and three mutation proofs show the comment, cooldown and groups
  checks are what refuse their file.

actionlint, zizmor, shellcheck and yamllint come from Homebrew, through
`Scripts/required_tools.txt` (see [The tools](development.md)). shellcheck
and yamllint, like the data guard, also check the untracked files git does
not ignore (forsgren#204), so a new script or workflow is judged in the FBP
that adds it.

The POST gates, on the generated site:

- **HTMLHint** (`Scripts/gate_htmlhint.sh`): every `.html` file under the
  rules in `.htmlhintrc`. Red on a finding, and on a run that scanned zero
  files, since nothing linted is not clean. `.htmlhintrc` turns on 32 rules
  (forsgren#206, #207, #208, #215): the 32 of the estate's canon, among them
  `meta-charset-require`, `doctype-html5`, `inline-style-disabled`,
  `meta-description-require`, `h1-require` and `meta-viewport-require`, so
  every page must declare its charset (a page without one still passes
  Lighthouse when the server sends a charset header; htmlhint reads the file
  itself), carry a meta description, a viewport and one `<h1>` (see
  [Pages and views](pages-and-views.md#the-page)). The same file holds for
  the built site, the golden pages and the starter page.
  `Scripts/test_gate_htmlhint.sh` runs the real `htmlhint` and gives each of
  the 32 rules a row: a minimal page that breaks only that rule must be red
  and name that rule and no other (`tagname-specialchars` also trips
  `tag-pair`, which an end tag with no start tag always does). Its mutation
  proof turns each rule off in a copy of `.htmlhintrc` and sees its row stop
  naming it, so every row is red because of its rule, and the self-test is
  red when `.htmlhintrc` holds more or fewer rules than its list, or a canon
  rule is neither on nor a row of `Scripts/htmlhint_exceptions.txt` (empty
  here: forsgren turns every canon rule on).
- **starter page build** (`Scripts/build_starter_page.sh`, forsgren's own,
  forsgren#132): renders `README.md` with `./cmd/readmepage` into
  `.build/starter` (`index.html`, `styles.css`, the same stylesheet the
  metrics site links, and `CNAME` holding `forsgren.be`, which GitHub Pages
  reads for the custom domain). Red when the renderer refuses
  the README (a construct outside its subset, a link that is neither https,
  an anchor nor a path in the repository) or the page cannot be written, and
  a failed build writes nothing into the output directory. Its self-test is
  `Scripts/test_build_starter_page.sh`, with a mutation proof for the
  `CNAME` line; `STARTER_README` points the script at another file so the
  self-test can feed it a README the renderer refuses.
- **starter page HTMLHint** and **starter page privacy posture**
  (`Scripts/gate_htmlhint_starter.sh` and
  `Scripts/check_privacy_posture_starter.sh`, forsgren#132): the two gates
  above, unchanged, run on `.build/starter`; each wrapper only names the
  directory, because a row of the order file names a script, not a command
  line. Both take a directory argument too. `Scripts/test_starter_page_gates.sh`
  runs copies of them in a throwaway root with the real `htmlhint`, and
  proves by mutation that the default directory is what makes an unpaired
  tag red.
- **starter page links** (`Scripts/check_starter_links.sh`, forsgren's own,
  forsgren#132, decision forsgren#149): every `href` and `src` of the page in
  `.build/starter` is an `#anchor`, the page's own `styles.css`, or an https link into
  `github.com/yveshanoulle/forsgren`, `github.com/yveshanoulle/forsgren-template`
  or `forsgren.forsgren.be`, and nothing else. The names end where they end:
  `forsgren-templates` and `forsgren.forsgren.be.example.org` are findings,
  as are an http link, a relative link and a `src` off the list. It is a new
  check, not an exemption of **repository links**, which keeps its rule for
  the metrics site. The FAIL line names `file:line` and the host, never the
  link, so a private repository path cannot reach an sfl or CI summary. Red
  on a directory with no page (a scan over nothing). Its self-test is
  `Scripts/test_check_starter_links.sh`, with a mutation proof that the
  allowlist is what turns a foreign link red.
- **Stylelint** (`Scripts/gate_stylelint.sh`): every `.css` file under
  `.stylelintrc.json` (stylelint-config-standard plus another estate repository's
  overrides). Red on a finding, and on a glob that matches no file. The gate
  is the estate canon: CI only checks. Under `GATE_FIX=1` it would add
  `--fix`, but forsgren's stylesheet is not authored in `.build/site`: it is
  `internal/page/styles.css`, embedded with `go:embed` and copied into every
  build, so a fix on the generated copy is lost on the next build and CI
  stays red on the source. Therefore `FBP.sh` runs
  `Scripts/fix_source_css.sh` with `GATE_FIX=1` on the SOURCE, before the pre
  gates and the build, so the build copies the fixed source. The script does
  nothing without `GATE_FIX=1`, is no order-file row and is named by no
  workflow; its self-test, `Scripts/test_fix_source_css.sh` (its own row),
  pins that the fix reaches the source and never the generated copy, that
  `FBP.sh` runs it before the build, and that CI never fixes.
- **html duplication, generated page** (`Scripts/check_html_dupl_site.sh`):
  the same ratchet over `.build/site`, with its own ceiling, today 0.00%,
  measured one page at a time (every `.html` under the site, subfolders
  too, each staged alone, as the golden-pages gate does). It catches what
  the template scan cannot see, such as a page template that pastes the
  header instead of calling it. Pages rendered from one layout repeat its
  chrome, so measuring them as one set would red the ceiling with clean
  templates; duplication within a page is still held to 0.00%, and a red
  names the page by its path in the site. A tooling failure (the measuring
  script ending other than 0 or 1, or `mktemp -d` failing) is exit 2, never
  a red over the ceiling.
- **lint coverage** (`Scripts/check_lint_coverage.sh`): each linter opened
  every `.html` and `.css` file the site ships, no fewer and no more. A glob
  that stops matching is a smaller job that still reports success; this is
  the gate that notices.
- **required pages** (`Scripts/validate_required_pages.sh` and
  `Scripts/test_required_pages_covers_site.sh`): the pages the site must
  ship are listed, hand-authored, in `internal/page/required-pages.json`
  (today `/`, `/legend.html`, `/settings.html`, `/days.html`, `/issues.html`,
  `/standard/`, `/numbers/` and `/scoring/`). The first checks that list's shape: valid JSON, a
  non-empty `requiredPages` array of root-relative paths, no scheme or host,
  no `..`, no duplicates. The second checks it against `.build/site`: every
  `.html` file there, in subfolders too, is listed (`standard/index.html` as
  `/standard/`), and every listed page was generated. Both
  are red on a missing file or an empty list, and the second on a site with
  no `.html` page at all. A new page means a new line in the list, in the
  same commit as its template.
- **privacy posture** (`Scripts/check_privacy_posture.sh`, the estate's gate
  from another estate repository): the page collects nothing. Red on a form, an
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
  site with no `.html` page. No exception: forsgren's own repository is red
  like any other (forsgren#162; the footer links https://forsgren.be/, the
  project page, which links GitHub itself; the no-projects page links
  https://forsgren.be/#configuration, forsgren#172, and
  `internal/page/repolinks_test.go` runs this gate on a site rendered with
  no projects). The failure line names the file and line, never
  the path it matched, so a private repository's name cannot reach a commit
  message.
- **community files** (`Scripts/check_community_files.sh`, forsgren's own):
  `CODE_OF_CONDUCT.md` exists at the repository root and names the reporting
  address `conduct@hanoulle.be`; `SECURITY.md` exists and names the private
  reporting route (the Security tab's "Report a vulnerability", or the
  advisories URL); neither has a template placeholder left (any bracket that
  is not a Markdown link); and this README links both in plain Markdown, not
  inside a code block, a code span or a comment. Every finding is reported in
  one run.
- **markdown links** (`Scripts/check_markdown_links.sh`, forsgren's own,
  forsgren#147): every relative link in a Markdown file git tracks or does
  not ignore (an inline
  `[text](path)` or a reference definition `[label]: path`, outside a fenced
  block, an HTML comment and an inline code span) resolves, from the file's
  own directory, to such a file or a directory that holds one, spelled
  with the right case. A link with a scheme and a `//host` link are not
  checked. An `#anchor` (on a Markdown file, or a pure `#anchor` for the file
  itself) must name a heading of that file by GitHub's rules: ATX `#`
  headings outside fences and comments, lower case, spaces to hyphens,
  punctuation dropped, a repeated heading numbered `-1`, `-2`
  (`Scripts/markdown_heading_slugs.awk`). A setext heading and an HTML `id`
  are not seen, so a link to one is red; an anchor into a directory or a
  non-Markdown file, one with a non-ASCII byte or a `%` escape, and one that
  starts with `user-content-` are not checked. Red on a root with no Markdown file or no relative link. The
  failure line names `file:line` and the link as written; every finding is
  reported in one run.
- **exit-trap completion** (`Scripts/check_exit_trap_completion.sh`, forsgren's
  own, forsgren#137, found by #136): a shell script, at the repository root or
  directly in `Scripts/`, that has a top-level `set -e` before a top-level
  `trap ... EXIT` is red unless it carries the completion idiom (a `COMPLETED`
  flag set as its last statement, `selftest_begin` or `lib_selftest.sh`). On
  bash 3.2 an unbound variable after such a trap ends the script with exit 0,
  so a caller reads an abort as a pass; the idiom turns an exit of 0 without
  the flag into exit 1. The rule reads source only (its limits are in the
  script's header); `Scripts/test_exit_trap_completion_behaviour.sh` is the
  other half, which copies each real script (`build_site.sh`,
  `gate_htmlhint.sh`, `test_sfl_pull.sh`, `test_validate_required_pages.sh`)
  into a sandbox, injects an unbound variable right after its trap and
  requires a non-zero exit, the probe named, the "aborted before completing"
  line and no temporary directory left behind. Its self-test is
  `Scripts/test_check_exit_trap_completion.sh`.

- **language gate** (`Scripts/gate_language_pages.sh` running the canon
  `Scripts/gate_language.sh`, self-tests `Scripts/test_gate_language.sh` and
  `Scripts/test_gate_language_pages.sh`, forsgren#220): after the build and the
  starter page build, the text a visitor reads on every page of `.build/site` and
  `.build/starter` (the latter as `starter/index.html`), plus `alt`, `title` and
  `aria-label`, is checked by LanguageTool 6.8 in `en-GB`. It runs on this
  machine under `sandbox-exec` with the network denied, never against a remote
  service. Mode `enforce` (`Scripts/language_settings.txt`): red for a finding
  that is neither in `Scripts/language_allowlist.txt` (names and terms, spelling
  matches only) nor in `Scripts/language_baseline.txt` (false positives and
  accepted style hints, a reason on every row, keyed by page, language, rule,
  match and context and never by offset), and red for a baseline row whose finding
  is gone. A missing LanguageTool, Java or sandbox-exec is red; another
  LanguageTool version than `language_tool_version` is red. CI installs
  LanguageTool with the other Homebrew tools (`Scripts/required_tools.txt`).
  `Scripts/report_baselines.sh` shows the baselines on the Quality run page.
- **browser gate** (`Scripts/gate_browser.sh`, engine `Scripts/browser_gate.mjs`,
  self-test `Scripts/test_gate_browser.sh`, forsgren#205, the estate's shared
  gate): after the build, every page of `internal/page/required-pages.json` is
  opened from `.build/site`, served on 127.0.0.1, in the installed Chrome
  (puppeteer-core 25.14.0, axe-core 4.14.0, exact devDependencies) at 1280x800,
  once per variant of `Scripts/browser_gate_variants.txt` (one: `light|scheme:light`).
  Red on an axe serious or critical finding, a missing doctype or charset, a
  console or page error, a failed request, a request that leaves loopback, and a
  layout shift (CLS) other than exactly 0, the largest of five cold loads, and
  sideways scrolling (forsgren#350): at 1280x800 and at 390x844 the page may not
  be wider than the window, nor any table wider than the box it sits in
  (scrollWidth above clientWidth), each finding naming the page, the width and
  the overflow in pixels; one rule for every page with a table (the engine
  `browser_gate v5`, decisions #365 and #380; the CLS stays measured at 1280x800 alone).
  v4 = v3 plus the CLS interval from the load (default 1000 ms, no second read
  after axe) and the sideways measurement without scrollbar room (forsgren#377);
  the baseline format is unchanged, no migration.
  v5 = v4 plus the exits (forsgren#381): Chrome is closed and its profile folder
  removed on the end, an error, and SIGINT, SIGTERM or SIGHUP (exit 130, 143,
  129); Chrome runs on a pipe; the wrapper forwards the signals to node and
  waits. The findings and the exit statuses 0, 1 and 2 are unchanged.
  The TBD table (class `wraps`) has no minimum width and wraps its cells; every
  other table keeps its minimum width and scrolls inside its box (forsgren#38),
  and today's overflow of those is in the baselines as `sideways` rows
  (`sideways|<variant>|<page>|<viewport>|<what>|<px>|reason`, decision #364):
  an overflow above its row is red, one below it is red until the row shrinks,
  a row whose overflow is gone is red, and an overflow with no row is red. Chrome
  runs with a fresh temporary profile, the sandbox on, a scrubbed environment and
  a loopback-only resolver. The shrink-only baseline
  (`Scripts/browser_gate_baseline.txt`) holds one sideways row (the settings
  table at 390x844) and the exceptions (`Scripts/browser_gate_exceptions.txt`)
  have no rows; a missing file is exit 2.
  axe-core is an automated gate, not proof of WCAG conformance. No new workflow,
  trigger, secret or permission.

- **browser gate (fixture site)** (`Scripts/gate_browser_fixture.sh`, self-test
  `Scripts/test_gate_browser_fixture.sh`, forsgren#226, forsgren only, not canon):
  the build renders the site without a config or history, so the browser gate
  above never opened a History chart or a Daily or Issues table.
  `Scripts/build_fixture_site.sh` renders `forsgren render` with the made-up
  fixture of `Scripts/testdata/fixture_site/` (a config of two projects, the
  repositories acme/api, acme/ios-app and acme/cli, and the files `collect` keeps:
  deployments, commits, failures, issues, issue bugs, reach and merged pull
  requests, forsgren#350, decision #336; the render time
  pinned to the goldens' 2026-10-03 12:00 UTC) into a temporary directory, and is
  red when the History page has no chart, the Daily or Issues page no rows, or
  the TBD page no Mainline Interval or no Mainline Lead Time with pull requests, so
  the fixture cannot go back to the placeholder. This gate then runs the browser
  gate's engine (`Scripts/browser_gate.mjs`) on that site: the same checks, the
  same manifest, exceptions and variants, and its own shrink-only baseline,
  `Scripts/browser_gate_fixture_baseline.txt` (only a ruling adds a row: today
  the sideways rows of decision #364, every table but the TBD one;
  `Scripts/report_baselines.sh browser` shows it on the Quality page). The
  canon `gate_browser.sh` is unchanged. The fixture build is checked by cases 20
  to 36 of `Scripts/test_build_site.sh`, the gate by its self-test (the data site
  clean, a finding only on a data page, the baseline, stale rows, exit 2 cases,
  the default build, mutation proofs H and I).

- **browser gate inputs** (`Scripts/test_gate_inputs.sh`, forsgren#262 step 1
  of 3, forsgren only, not canon): `Scripts/gate_inputs.txt` lists what each of
  the four browser rows reads, so a later step can run a browser gate only when
  a commit touches one of its inputs. The non-script inputs are written out
  (`cmd/`, `internal/`, `go.mod`, `go.sum`, `package.json`,
  `package-lock.json`, `Scripts/testdata/fixture_site/`,
  `internal/page/required-pages.json`, the `browser_gate_*` data files), with
  `*_test.go` and the `testdata/` of the Go trees excluded (decision
  forsgren#281); the script inputs are the closure of each gate's script. The
  self-test is red when a label has no row, a listed path does not exist, a
  script or data file of a gate's closure is not listed, or a gate that lists
  the Go trees does not exclude tests. It also holds the guard that makes the
  exclusion safe: no `go:embed` line of a non-test Go file and neither
  `Scripts/build_site.sh` nor `Scripts/build_fixture_site.sh` may read
  `testdata/` or a `_test.go` file; `go list` is read as well, so a directory
  pattern that comes to hold a testdata file is caught. Seven mutation proofs: a
  script dropped from a list, a nonexistent path, a missing exclusion, a
  `go:embed` of a testdata file, a `go:embed` of a test file, a build script
  reading a testdata file, and a directory pattern holding one.
  `install/README.md` is embedded but not part of the rendered site; markdown is
  never a change for the selector, so it selects nothing.

- **browser gate selection** (`Scripts/lib_gate_select.sh`, self-test
  `Scripts/test_gate_select.sh`, forsgren#262 step 2 of 3, forsgren only, not
  canon): `gate_select <label>` prints `run: <reason>` or `skip: <reason>` from the
  files changed against the merge base with origin/main (committed, staged,
  unstaged and untracked; markdown is prose) and `Scripts/gate_inputs.txt`. A
  changed file under one of the gate's inputs, and matching none of its
  exclusions, selects it. FAIL-SAFE: a changed file that no gate's list names,
  neither as an input nor as an excluded pattern, selects every listed gate. Files
  known to be unrelated select nothing: the `none|out|...` rows of the list
  (workflows, docs, markdown, the release scripts, and the runners `sfl.sh` and
  `FBP.sh`, which run the browser rows but which no browser gate reads;
  forsgren#284) and a file under `Scripts/`
  that is in the closure of no gate's script, so a commit that touches only
  those skips all four; a new top-level file or directory still runs them.
  `GITHUB_ACTIONS=true` (Quality), `FORSGREN_GATE_SELECT_FULL=1`, a missing
  origin/main and a label no list holds select all. `changed_files`, `named_files`
  and `closure` live there and the git sandbox isolation gate sources them. The
  self-test runs it in throwaway repositories (twenty-four cases; 22 to 24 on the
  real list: only `sfl.sh`, only `FBP.sh`, and a file no list names) with eleven
  mutation proofs, each asserting the reason text.

- **browser gate skip** (`sfl.sh`, self-test `Scripts/test_sfl_gate_skip.sh`,
  forsgren#262 step 3 of 3, forsgren only, not canon): before a row whose label
  has `in` rows in `Scripts/gate_inputs.txt` (the four browser rows) runs,
  `sfl.sh` asks `gate_select`. On a skip the row's script does not run: the step
  is still counted, printed `⏭ skipped: <label> (<reason>)`, a `⏭ skip` row of
  the step table, and `<label><TAB><reason>` is appended to
  `.build/sfl-skips.log` (`sfl.sh pre` empties it, post appends; forsgren#266
  reads it). A selected row prints `▶ selected: <label> (<reason>)` and runs.
  CI (`Scripts/run_ci_phase.sh`) does not select: Quality runs every row. The
  self-test runs the real `sfl.sh` in throwaway repositories (a docs-only
  change, a change to the gates' inputs, a forced full run, CI) with three
  mutation proofs, each asserting the reason: the skip ignored, the log line
  dropped, the log never emptied.

- **release workflow gate skip and the removed names gate** (forsgren#263,
  forsgren only, not canon): the `release workflow` row
  (`Scripts/test_release_workflow.sh`) has `in` rows in
  `Scripts/gate_inputs.txt` too: the workflow, the three workflows it is pinned
  against, the release scripts it names and the libraries it sources, the closure
  of its script, which `Scripts/test_gate_inputs.sh` derives and holds. That
  self-test also fails when the gate's script lists or searches the repository
  (`git ls-files`, `git grep`, `find`, `grep -r`), because then it reads files no
  list can name. The scan of every tracked file for the removed bump machinery
  (forsgren#237) was the last section of that pin and read all of them; it is now
  the always-run row `release removed names`
  (`Scripts/test_release_removed_names.sh`, one search per name, about 3 s,
  five mutation proofs in a throwaway repository). Quality runs both rows
  always.

- **FBP push-or-rebase** (`Scripts/fbp_push_or_rebase.sh`, self-test
  `Scripts/test_fbp_push_or_rebase.sh`, forsgren#283 step 1 of 2, ported from
  the estate canon): when FBP.sh's final push is refused because the remote moved
  during the run, the helper fetches and compares the files changed by the
  incoming commits (merge base to `@{u}`) with those of the local commits. No
  file in both: `git rebase @{u}` (author and message kept, so the
  Signed-off-by trailer the DCO check matches to the author stays), push, and the
  git row `⚠️ (pushed after rebasing onto <shas>; this combination is tested by
  CI, not by this run)`; a remote that moves again is rebased over again, at most
  3 pushes. A file in both, a rebase conflict, a third refused push or a refusal with
  nothing incoming: any rebase aborted, `❌` lines naming the files and
  `git pull --rebase --autostash`, the git row `❌ (push refused, remote moved —
  see above)`, exit 1. Sourced, it only defines `fbp_overlap_files` and
  `fbp_join_shas`, for sfl's opening pull (step 2, the next item). The self-test drives a copy
  of the real FBP.sh in throwaway repositories whose bare origin moves during the
  run (six cases) with one mutation proof: without the overlap check the
  same-file case is pushed and the scenario fails on the missing file name.

- **sfl pull rebase** (`Scripts/sfl_pull.sh`, self-test
  `Scripts/test_sfl_pull_rebase.sh`, forsgren#283 step 2 of 2, ported from the
  estate canon): when sfl's opening `git pull --ff-only` cannot fast-forward
  (local commits not on the remote, typically a local RED commit), it sources
  `Scripts/fbp_push_or_rebase.sh` and asks `fbp_overlap_files` which files the
  incoming commits changed that the local side changed too: the local commits
  and the staged, unstaged and untracked changes. None: the changes are stashed
  (`--include-untracked`), the local commits rebased onto `@{u}`, and the stash
  popped with `--index`, so staged stays staged; only the stash this run
  created is popped (the stash ref compared before and after). The line names
  the incoming short shas and says the gates run on the rebased tree. An
  overlap, no upstream, a failed fetch, nothing incoming or a failed rebase:
  `❌` lines naming the files, `git pull --rebase --autostash` to run, exit 3,
  HEAD, the staged and unstaged changes and the stash list as they were. The
  self-test drives the real `sfl_pull_or_stop` in a temp bare remote and two
  clones (three cases) with two mutation proofs, each asserting its reason:
  without the overlap check the local commit's file is rebased, and without the
  working-tree part of the overlap list the staged file is rebased.

- **live check** (`Scripts/live_check.sh`, self-test `Scripts/test_live_check.sh`,
  forsgren#205 step 2 of 2, ruling item 3): after every forsgren.be deploy, the
  `live-check` job of `starter_page.yml` (needs `deploy`, runs only when the
  deploy step published, `contents: read`) runs `Scripts/live_check.sh
  https://forsgren.be`, with curl and no browser. It checks that `http://` answers
  301 or 308 with exactly `https://<host>/` as Location, that `https://` answers
  200 as `text/html` with the certificate validated (curl is never given `-k`
  or `--insecure`, and `--disable` keeps a curlrc from adding it) and links a
  stylesheet, and that the stylesheet the page actually links (its href,
  resolved against the base) answers 200 as `text/css`. Every failed check is a
  `❌ FAIL: live check: <check>: <observed value>` line and exit 1, so the job
  is red, though it cannot undo the deploy; success is one `OK:` line with the
  status codes, content types and the number of tries. A deploy may take a
  moment to show, so the set is tried up to `LIVE_CHECK_TRIES` times (5),
  `LIVE_CHECK_DELAY` seconds apart (10). It is not a local gate, because it
  needs the deployed site. The self-test (a pre row) puts a stub `curl` on
  PATH, covers each check passing and failing by name, the href forms, the
  bounded retry, that validation is never off and the usage errors, and proves
  four mutants (no redirect check, no Location assertion, `--insecure`, no
  stylesheet check). No new secret; the job adds no permission.

forsgren has no privacy-pages gate: that one is another estate repository's, pinning
the content of a privacy policy forsgren does not serve. The order file
declares it `n/a` with its reason, and the privacy posture gate keeps that
reason true.

A finding in the generated page is fixed in the template under
`internal/page/`, never by loosening a rule in the config.
