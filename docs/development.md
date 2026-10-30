# Development

## The data guard

The data guard (`Scripts/check_data_guard.sh`, a PRE gate) keeps it that way.
Like the secret scan it is secret-class: a finding blocks the commit itself,
not only the push, so the leak never enters history.
Over the files git tracks and the untracked ones it does not ignore
(`repo_files` in `Scripts/lib_repo_files.sh`, forsgren#204), it fails when:

- a file that looks like installation config or data sits outside
  `testdata/`: anything under a top-level `data/`, `deployments.csv`,
  `commits.csv`, `failures.csv`, `failures_read.csv`, `failures_withdrawn.csv`, `issues.csv`, `issues_full.csv`,
  `issue_bugs.csv`, `issue_bugs_cut.csv`, `reach.csv`, `cut_runs.csv`, `starts_checked.csv`, `commits_backfilled.csv`, `pulls.csv`, `pulls_read.csv`, `pulls_denied.csv`, `pushes.csv`, `pushes_read.csv`, `pushes_denied.csv`, `pushes_cut.csv`, `pushes_checked.csv`, `pushes_fill.csv`, `pushes_github_end.csv`, `push_commits.csv`, `pull_commits.csv`, `pull_commits_filled.csv`, `push_commits_filled.csv`, `pulls_bot_filled.csv`, `commit_files.csv`, `commit_files_filled.csv`, `push_files_filled.csv`, `history.csv`, `*.history.csv`, `forsgren.config.*`,
  `forsgren-config.*`, `config.yml`/`.yaml`/`.json` at any depth, or a
  `*.jsonl` events file.
  Every data file the Go code names (a constant `<Name>File = "<name>.csv"` in
  `internal/collect`, on its own `const` line or inside a `const (` block)
  must be on that list: the gate's self-test reads those constants and fails
  when one is not guarded, so a data file added later cannot be forgotten
  (forsgren#143; the block form since forsgren#255, whose two pull request
  files are declared in one).

Private names are not this gate's business: the private-names gate
(`Scripts/check_private_names.sh`, in [Quality gates](quality-gates.md)) searches every tracked and every untracked,
not-ignored path and file for them.

The data guard checks untracked files too (forsgren#204): FBP commits after
its gates run, so a new data file is judged in the very FBP that would add
it. A file git ignores is left alone, since it will never be committed.

## Working on forsgren

**`./FBP.sh "<message>"`** (FBP = FullBuildAndPush) is the one command for a
change: 

`gofmt -w` over the Go files, `./sfl.sh pre`, `Scripts/build_site.sh`,
`./sfl.sh post`, then `git add -A`, a commit, and a push only when every
phase is green. 
An ordinary red still commits locally, with the subject
`*** RED ****` and the message in the body, so work is never lost, and
skips the push. 
A secret-class red (the secret scan and its self-test, the data guard or the
private-names gate) commits nothing at all. `./FBP.sh --no-commit` runs the gates and the build
only. 
`./FBP.sh --no-push "<message>"` runs the same and commits, but does not push;
it is for changes that only touch FBP.sh, sfl.sh, local-only scripts or their
self-tests. It cannot be combined with `--no-commit`.
Every commit it makes, green or `*** RED ****`, is signed off
(`git commit --signoff`): git adds a `Signed-off-by:` trailer for the
committer identity, yours from `user.name` and `user.email`, or
agent-Friend's under `Scripts/fbp_agent_friend.sh`. That is the Developer
Certificate of Origin sign-off the DCO check on pull requests and on every
push to `main` asks for (see [CI](ci.md) and
[CONTRIBUTING.md](../CONTRIBUTING.md)).

A push refused because the remote moved during the run (a pull request merged
while the gates ran) no longer ends the run (forsgren#283, step 1 of 2,
`Scripts/fbp_push_or_rebase.sh`): FBP fetches and compares the files the
incoming commits changed with the files the local commits changed. When none
is in both, it rebases the local commits onto the remote (`git rebase` keeps
each commit's author and message, so the sign-off stays), pushes, and the git
row of the summary reads `⚠️ (pushed after rebasing onto <shas>; this
combination is tested by CI, not by this run)`. When a file is in both, or the
rebase conflicts, it aborts any rebase, leaves the local commits as they were,
names the files and the command to run (`git pull --rebase --autostash`, then
FBP again) in `❌` lines, and the run is red. A remote that moves again is
rebased over again, at most 3 pushes in all, then the run stops red with the
commits rebased. A push refused for any other reason is red too.
`Scripts/test_fbp_push_or_rebase.sh` pins it. sfl's opening pull rebases the
same way (step 2 of 2, see `./sfl.sh` below).

Its closing summary prints the message, one row per phase with the
gate counts and the page count, and every failure's reason. A run ended by
TERM, INT or HUP ends with `Aborted ❌ (<signal>, exit <n>)` (143, 130, 129),
never `All checks passed`. A run that ends with exit 0 but never reached its
last statement, as when bash 3.2 ends the script on an unbound variable under
`set -u`, is an abort too: the summary says `Aborted ❌` and FBP.sh exits 1
(forsgren#136; `Scripts/test_fbp_abort_exit.sh`).

**`Scripts/build_starter_page.sh [out-dir]`** renders `README.md` into
`.build/starter` (the page forsgren.be shows; see [CI](ci.md)), the way
`Scripts/build_site.sh` renders the metrics site into `.build/site`. It is a
POST gate row of its own, so a README the renderer refuses is red in FBP and CI
before it is ever published.

**Before handing back** (forsgren#439): Writers run their tests red first, and FBP (fail fast, forsgren#441) is the check.

**`./sfl.sh pre|post`** runs one phase of the gates. Before PRE it runs
`git pull --ff-only`. When that cannot fast-forward (local commits not on the
remote, a local RED commit say), it rebases the local commits onto the
upstream if the files the incoming commits changed overlap neither the local
commits nor the staged, unstaged or untracked changes (the same
`fbp_overlap_files` as FBP's refused push; the changes are stashed and popped
with `--index`, so staged stays staged, and only the stash this run made is
popped), and the gates run on the rebased tree (forsgren#283, step 2 of 2,
`Scripts/sfl_pull.sh`). Any overlap or failure stops it (exit 3) with the
files named and `git pull --rebase --autostash` to run, the commits and the
changes as they were. Then it installs the tools (see [The tools](#the-tools)), checks the Node pin, runs
`npm ci` when `node_modules` is missing or stale (see [The tools](#the-tools)),
and exports the Go pin. **It stops at the first red gate**
(forsgren#441, decision #440): each later gate of the phase is printed
`⏭ skipped: <label> (stopped after <label of the red gate>)`, is a `⏭ skip` row
of the step table (never counted as passed), and the last line says
`sfl pre failed, stopped after <label>`; `./sfl.sh --all pre|post` (and
`./FBP.sh --all`) runs every gate, also past a red static block, as CI does. It
prints a step table and an `Errors:` block with
each failed gate's reason, and exits 0 green, 1 red, 2 on a secret-class
red (which stops too and writes no stop sink, so FBP.sh commits nothing). The
**static block** (forsgren#231) is the one place that runs on after a red: the fast static checks
(gofmt check, Go lint, actionlint, shellcheck, yamllint, zizmor, each after its
self-test) sit in the order file between the marker lines
`#! static-block-start` and `#! static-block-end`, straight after the
secret-class rows. The block always runs to its end, so every static finding is
reported; when one is red, sfl runs no later gate: each is printed as
`⏭ skipped: <label> (stopped after the static block)`, is a `⏭ skip` row of the
step table, and the last line says `sfl pre failed, stopped after the static
block`. Whatever gate stopped the phase, sfl writes
`.build/sfl-static-stop.log` (`<sentence>: N gate(s) skipped`); FBP.sh reads it,
skips the build and the POST gates (the POST gates named, the sentence in the
summary), and commits the RED commit locally as for any red, no push. FBP.sh runs the formatters (`gofmt -w`, the source CSS fix) before
sfl, so the block checks the formatted tree. **CI does not stop early**:
`Scripts/run_ci_phase.sh` runs every row of the phase, so a pull request shows
all its reds in one run (pinned by `Scripts/test_sfl_static_block.sh`); the markers start with `#!`, a comment to every reader
but sfl. `Scripts/test_sfl_static_block.sh` pins both.

**Browser rows run only when their inputs changed** (forsgren#262). Before each
of the four browser rows, sfl asks `gate_select` (`Scripts/lib_gate_select.sh`,
over `Scripts/gate_inputs.txt` and the files changed against origin/main). An
unselected row is not run: it is printed `⏭ skipped: <label> (<reason>)`, is a
`⏭ skip` row of the step table and still counts as a step, and its reason is
appended to `.build/sfl-skips.log` (emptied by `sfl.sh pre`); the summary of
`FBP.sh` lists each skipped gate with its reason (forsgren#266). A change to
`sfl.sh` or `FBP.sh` alone skips all four (no browser gate reads them;
forsgren#284). A file no list names runs all four; `FORSGREN_GATE_SELECT_FULL=1` forces a full run. CI runs
every row. `Scripts/test_sfl_gate_skip.sh` pins it.

**`Scripts/gate_report_order.txt`** declares every gate, one row
`<label>|<script>|<phase>|<class>`: the label sfl and CI print, the script
that runs, `pre` or `post`, and `secret-class` or nothing. A gate this repo
does not have is a row `<label>|n/a|<reason>`. sfl and CI both run the
rows in file order, so the file is the one list.

**Adding a gate:** write the script and its self-test (`Scripts/test_*.sh`,
red first, plus a mutation proof), give each a row at its position in the
order file (the self-test in PRE, before its gate), add any Homebrew tool
it needs to `Scripts/required_tools.txt`, and describe it in [Quality gates](quality-gates.md).
`Scripts/test_sfl_drives_from_order_file.sh` is red on a `Scripts/test_*.sh`
no row declares, and the gate-wiring gate on a script neither runner runs.

## The tools

Run `./sfl.sh pre` (or `./FBP.sh`) and the tools install themselves.
`Scripts/required_tools.txt` lists them, and `Scripts/install_tools.sh` installs
each missing one with Homebrew and upgrades the ones already there. Homebrew
must already be installed. Only the tools the quality gates use are listed.
In CI the `quality_2`, `browser_1` and `browser` jobs install only what their
gates need, from `Scripts/required_tools_quality_2_gates.txt`,
`Scripts/required_tools_browser_1_gates.txt` and
`Scripts/required_tools_browser_gates.txt` (the installer's optional argument);
the main job installs the full list (forsgren#447, [docs/ci.md](ci.md)).

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

**Node is pinned to a major in `.nvmrc`.** The file holds one line, a whole
major (currently `26`), and is the only place the pin is written.
`Scripts/check_node_pin.sh` runs in `sfl.sh` right after the tool install (and
as the **Node pin** gate) and is red when the `node` on `PATH` is another
major, naming the running version and the fix. Node cannot download its own
version the way Go does, and Homebrew publishes only `node` (the newest major)
and `node@NN` per major, never a patch you pick, so the pin is the major and
installing it is yours. When the check is red, run what it prints:
`brew install node@26` (a `node@NN` formula is keg-only: put
`/opt/homebrew/opt/node@26/bin` first on `PATH`), or `brew upgrade node` when
26 is Homebrew's current major. **To move to a new Node major,** edit
`.nvmrc` and nothing else, install that major, then run `./FBP.sh`; the stamp
below reinstalls `node_modules` for it. CI reads the same file through
`actions/setup-node` (`node-version-file: .nvmrc`), so the hosted runner uses
the pinned major whatever Homebrew has that day (the **workflow node pin**
gate keeps that step in place).

**The npm linters are pinned in `package.json`.** Node (and with it `npm`) is
a Homebrew tool from `Scripts/required_tools.txt` that the pin above holds to
one major. The npm tools the gates use,
htmlhint, stylelint and stylelint-config-standard, and jscpd for the html
duplication ratchet, are not: they are `devDependencies` in `package.json`
at an exact version (no `^` or `~`), and `package-lock.json` pins every
package they pull in. Both files are committed. `./sfl.sh` runs
`Scripts/npm_sync_install.sh`, which runs `npm ci` when `node_modules` is
missing or was installed from another `package-lock.json` or Node major than
today's: a stamp inside it, `node_modules/.package-lock.sha256`, holds the
lockfile's sha256 and `node<major>`, and is written only after a successful
`npm ci`. So a lockfile bump (a pull, an `npm audit fix`) is reinstalled by
the next run, and a `node_modules` from before the stamp existed is
reinstalled once. `npm ci` installs exactly what the lockfile says into
`node_modules/` (gitignored, never committed) and fails when `package.json`
and the lockfile disagree.
Never use `npm install` in a gate or a workflow, and never install the linters
globally or run them through `npx --yes`.

Three gates keep it that way: **npm lockfile sync**
(`Scripts/check_npm_lock_sync.sh`) is red when `package.json` and
`package-lock.json` disagree, naming each difference and the fix, `npm install
--package-lock-only`, without the network; **npm manifest policy**
(`Scripts/check_guardrail_packages.sh`) is red on a version range in
`package.json`, on a missing or gitignored `package.json` or
`package-lock.json`, and on a `node_modules/` git tracks or does not ignore; **npm audit**
(`Scripts/npm_audit_check.sh`) is red on a moderate, high or critical advisory
(development dependencies included) that one `npm audit fix` cannot heal and
no ruled exception covers; a low advisory is listed as `low: npm-audit: ...`
and stays green. When that fix does
heal it, the changed `package-lock.json` rides into the commit. The heal runs
only under `GATE_FIX=1`, which `sfl.sh` exports and CI never sets; in CI the gate
only checks and is red on the advisory.

**Ruled exceptions to npm audit.** An advisory with no fix can be excepted
in `Scripts/npm_audit_exceptions.txt`, one line per advisory:
`advisory|package|re-check date|issue|reason`. An exception needs Yves's
explicit yes recorded on a GitHub issue, which its line names, like every
suppression (see [Quality gates](quality-gates.md)). The gate reads `npm audit --json` (with jq,
which macOS and GitHub's macOS images ship) and ignores a finding only while
all of these hold: its GHSA ID and its package are listed; today is on or
before the re-check date; `npm audit --omit=dev` does not report it, so
every path to it runs through devDependencies; and npm offers no fix for
that package without `--force` (its `fixAvailable` is false or SemVer-major).
Each ignored finding is printed once, as `excepted: GHSA-… (package) until
<date>, <issue>`. The exception ends by itself: the gate is red again, with
a ❌ line saying why, once the date has passed ("re-check forsgren#13: is a
fix out?"), on any other advisory, when the advisory reaches a production
path, and when a fix without `--force` exists ("a fix exists: remove the
exception and update"). An exception for an advisory npm no longer reports
is a warning (remove the stale exception), not a red; a malformed line or an
advisory listed twice is red before anything is audited.

**Re-checked weekly** (Yves, forsgren#13): a re-check date may be at most 7
days after today, and the gate is red on one further out, so nobody can set
an exception a month ahead. A re-check means looking for a fix. When one is
out, remove the line and update. When there is none, move the date forward
by at most 7 days and add one line to the entry's history comment in the
file (or note it on the issue). Today there is no exception: the file holds
no row (the braces row of forsgren#13 was removed in forsgren#419, when npm
audit stopped reporting it). The gate is red on a moderate, high or critical
advisory (forsgren#434, decision #420); a low one is listed, not red, and is
fixed by updating the lockfile.

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
  can neither fast-forward nor rebase.
- **sfl pull rebase self-test** (`Scripts/test_sfl_pull_rebase.sh`): the
  opening pull's rebase over unrelated incoming commits, and its stop on an
  overlap with the local side untouched, in a temp bare remote and two clones.
- **npm manifest policy self-test**, **npm-audit self-test** and the other
  `... self-test` rows: each drives its gate on made-up input before the
  gate runs.
- **tool install self-test** (`Scripts/test_install_tools.sh`): the
  installer installs a missing tool, upgrades a present one, and is red when
  Homebrew reports success but the tool is still not runnable, or the list
  is empty.
- **Linux tool install self-test** (`Scripts/test_install_tools_linux.sh`,
  forsgren#427): the Linux counterpart of that installer, which the Linux jobs
  of Quality run on `ubuntu-latest` (forsgren#447), with the download stubbed: it installs the pinned
  builds of `Scripts/linux_tool_pins.txt`, refuses a wrong sha256, and is red
  for another version, a tool with no pin, an empty list or another CPU.
- **Go toolchain pin self-test** (`Scripts/test_go_toolchain.sh`):
  `Scripts/go_toolchain.sh` prints go.mod's `toolchain` version and is red
  without one.
- **build-site self-test** (`Scripts/test_build_site.sh`): the build
  compiles the binary, renders the site and writes the page count only on
  full success. It also covers `Scripts/build_fixture_site.sh`, which renders the
  site from the made-up fixture of `Scripts/testdata/fixture_site/` for the
  browser gate (fixture site) (forsgren#226): fourteen pages, a History page with charts, a TBD page with a Mainline Interval row, Daily and
  Issues pages with rows, byte-identical twice, only made-up repositories, red
  when the fixture shows no data, two mutation proofs.
- **gate-failure summary**, **step table**
  (`Scripts/test_summarize_gate_failure.sh`,
  `Scripts/test_render_step_table.sh`): sfl's end-of-run reason lines and
  step table, with their counts.
- **sfl drives from the order file**
  (`Scripts/test_sfl_drives_from_order_file.sh`): sfl names no gate label
  itself, every row names an executable script, every `Scripts/test_*.sh`
  is declared by a row, and the secret scan, the data guard and the
  private-names gate each carry `secret-class`; each of those three pins
  is seen rejecting the order file with its tier stripped, by its own
  FAIL line and not for another reason.
- **FullBuildAndPush commit-message block** and **FullBuildAndPush
  build-site page count** (`Scripts/test_fbp_commit_message.sh`,
  `Scripts/test_fbp_build_pagecount.sh`): the real `FBP.sh`, run in a
  throwaway repository with stub gates, prints its message, reaches PRE,
  blocks a secret-class commit with the right hint, signs off its green and
  `*** RED ****` commits as the identity that ran it (a commit that then
  passes `Scripts/check_dco.sh`), refuses a message that names a private
  name before any gate runs, hands the message to the private-names gate on
  stdin (`--message -`), never prints back an argument that starts like a
  flag, and fails the build row
  by name on a missing, unreadable, non-numeric or zero page count. With no
  sandbox, the commit-message fixture fails once per `run_fbp` call, a
  number it counts itself.
