# CI

## CI

`.github/workflows/quality.yml` runs the same gates as `./sfl.sh`, on every
push to `main`, on every pull request into `main`, and by hand (Actions →
Quality → Run workflow).

**The preview.** After every push to `main`, once Quality is green for that
commit, the `preview` job at the end of `quality.yml` starts the deploy of a
preview site, <https://feta.forsgren.forsgren.be> (forsgren#222). It shows what
the next release will look like on real data: the collected data of the public
metrics installation, rendered with the newest code on `main`. It never
collects, so any difference from the live metrics site comes from the code
alone, and the footer says so: the preview is built from the checkout with
`go install ./cmd/forsgren`, which records the commit in the binary, so its
footer reads "Forsgren <last release tag>+dev (c41db9e)" (forsgren#224, forsgren#237). A release is
installed as a module at a pinned commit, which records none, so it keeps the
plain version. `Scripts/build_site.sh` builds with `-buildvcs=false`, which
records neither a commit nor a release tag, so its pages read "Forsgren dev"
(forsgren#340) unless `FORSGREN_BUILD_VERSION` sets a version. A preview built
without a usable tag reads "Forsgren dev (c41db9e)" and never a stale release
number. The deploy itself lives in the preview repository,
`yveshanoulle/forsgren-metrics-feta`, whose `preview.yml` takes the pushed sha
as its one input. The job only starts it: `Scripts/dispatch_preview.sh <sha>`
POSTs a `workflow_dispatch` with the Actions secret `PREVIEW_DISPATCH_TOKEN`,
a fine-grained token that holds Actions read and write on the preview
repository and nothing else, and requires HTTP 204. Any other answer, an empty
token or a sha that is not 40 lower-case hex digits fails the run; the script
never falls back to another token or login. The job `needs:` every other job,
with no status function in its `if:`, so a commit that fails a gate never
reaches the preview; its `if:` keeps it off pull requests, where no secret
exists; it holds `contents: read` and runs on `macos-latest`; it starts
after every gate job, so it takes none of their macOS slots. Its own concurrency group never cancels a run in flight (the
shas are started in push order; of several waiting runs GitHub keeps the
newest). It is not a `workflow_run` workflow: that is a dangerous trigger.

**What runs where.** Locally, `./FBP.sh` runs `gofmt -w`, `./sfl.sh pre`,
`Scripts/build_site.sh` and `./sfl.sh post`. CI runs the same three phases
with nothing fixed: `Scripts/run_ci_phase.sh pre`, then
`Scripts/build_site.sh` into `.build/site`, then `Scripts/run_ci_phase.sh
post`. Both read `Scripts/gate_report_order.txt` with the same row rules, so
every gate runs in both, in the same order, under the same label. Before the
gates, CI checks out the commit, puts Homebrew's directories first on `PATH`
and exports `GOTOOLCHAIN` from `go.mod` (as `sfl.sh` does), sets up Node from
`.nvmrc` with `actions/setup-node` (the Node pin `sfl.sh` checks), runs
`Scripts/install_tools.sh` (as `sfl.sh` does) and `npm ci`. The runner is a
fresh machine on every run with none of the Homebrew tools the gates need,
so the installer puts them there; installing and upgrading costs nothing
lasting on a machine that is thrown away after the job. A tool still missing
after it fails the Install tools step by name.

**Which tools each macOS job installs** (forsgren#447, step 4). The main
`quality` job runs the full `Scripts/install_tools.sh`, the whole of
`Scripts/required_tools.txt`: it runs the language gate (LanguageTool), the
secret scan (gitleaks) and the exit-trap gate. The other three macOS jobs pass
the installer a list of their own, so a job installs only what its gates and
its site build run, not the 75 to 219 seconds of the full set:
`quality_2` takes `Scripts/required_tools_quality_2_gates.txt` (go, node, jq),
`browser_1` takes `Scripts/required_tools_browser_1_gates.txt` (node) and
`browser` takes `Scripts/required_tools_browser_gates.txt` (go, node). Each list
was read from the scripts of the job's rows in `Scripts/ci_job_groups.txt` and
the scripts those call. A tool a gate needs and its list lacks is not skipped:
the gate fails with `command not found`. `Scripts/test_quality_jobs.sh` pins
each job's install command, each list's content, and that no gate of a job
names a tool of the full list that the job's list lacks; a gate moved to
another job (forsgren#447, steps 5 to 7) therefore needs its tools in that
job's list in the same change.

**Jobs** (forsgren#259, decision #260). Quality is one workflow with parallel
jobs and one verdict: the run's conclusion is success only when every job
succeeded, and that conclusion is what the Release reads
(`Scripts/release_quality.sh` lists the runs of `quality.yml` and reads each
run's status and conclusion, never a job). The main job `quality` runs every gate that
`Scripts/ci_job_groups.txt` does not give to another job. The jobs `isolation_1`
and `isolation_2` (forsgren#426, named `Isolation gates 1/2` and `Isolation
gates 2/2`) run the git sandbox isolation self-test in two shards, one each,
with the same setup as the main job: checkout, the gate environment, Node,
the tool install and `npm ci` (on Linux since forsgren#447, below). They build
no site, since it is a PRE row. The `summary` job (forsgren#425, named `Summary isolation gates`) runs the
step summary isolation gate with the same setup: the two gates took 15 minutes
in one job (the self-test 9 min 27 s, the gate 4 min 15 s, the setup 1.5
minutes) and now run side by side, about 11 and 6 minutes; the self-test's own
9 min 27 s is then halved by the two shards, about 6 to 7 minutes per shard job
with its setup (forsgren#426); the self-tests are dealt to the shards by their seconds, heaviest first to the lighter shard (`Scripts/git_sandbox_isolation_weights.txt`, a default weight for a self-test with no row, forsgren#446), so the two shards take about the same time. The report job's status takes the results of the
isolation jobs and of the summary job too, and the `preview` job `needs:` them.

**The Lint gates job runs on Linux** (forsgren#427). The `lint` job (actionlint,
shellcheck, yamllint and zizmor with their self-tests) runs on `ubuntu-latest`,
not `macos-latest`: these tools behave the same on Linux and read files only, and
a Linux runner starts without the queue GitHub warns of for macOS arm64. Since
forsgren#447 five more jobs run on Linux (below); the gate jobs that stay on
macOS are the ones where the language gate needs `sandbox-exec`, the gates meet
bash 3.2 and BSD tools, and the browser gates meet Chrome. The job
keeps the steps of the others, but its Install tools step is
`Scripts/install_tools_linux.sh Scripts/required_tools_linux.txt` (the estate's
`Scripts/install_tools.sh` stays the Homebrew installer, unchanged), which installs the
four tools from the builds pinned in `Scripts/linux_tool_pins.txt`, no Homebrew
and no piped script. Each download's sha256 is compared with the pin before
anything is unpacked, yamllint (Python) is installed with `pip install
--require-hashes` from `Scripts/linux_yamllint_requirements.txt`, and every tool
is run and must report the pinned version, since the image ships its own
shellcheck. The versions are the ones Homebrew installs on the Mac today
(actionlint 1.7.12, shellcheck 0.11.0, yamllint 1.38.0, zizmor 1.31.1), so a
finding on CI is the finding `./sfl.sh` shows; the checksums are actionlint's
published `checksums.txt` line and, for shellcheck and zizmor, which publish
none, the sha256 of the release file when the pin was written. Raising a pin
means changing its row there and the Homebrew formula's version in the same
change. The runner pins gate names the image of every job (the Linux jobs
below and this one on `ubuntu-latest`, every other job on `macos-latest`);
`Scripts/test_install_tools_linux.sh` runs the Linux installer on the Mac with
the download stubbed, for this job's list and for the list of the other Linux
jobs. The workflow's permissions are unchanged (`contents: read`) and no secret
is read by this job, as before.

**The Linux gate jobs** (forsgren#447, step 3). GitHub runs at most 5 macOS
jobs at once for the account, and Quality started 8 macOS gate jobs together,
so 3 waited for a slot and the run grew by up to 5 minutes. The jobs whose
gates need nothing of macOS now run on `ubuntu-latest`: `workflows`,
`summary`, `isolation_1`, `isolation_2` and `report`, with `lint` six Linux
jobs. Quality then starts 4 macOS gate jobs together (`quality`, `quality_2`,
`browser_1` and `browser`), one slot under the limit, and the `preview` job,
the fifth macOS job, starts only after every gate job. The runner pins gate is
red on a Linux job back on macOS, a macOS job on Linux, another image, and on
more than 5 `macos-latest` jobs with no `needs:`. What stays on macOS and why:
the main job holds the secret scan (Homebrew's gitleaks), the language gate
(`sandbox-exec`, LanguageTool and its Java) and the site build its POST gates
read; `quality_2` holds the exit-trap completion behaviour gate, which proves
the idiom against bash 3.2, the bash a Mac runs scripts with; the two browser
jobs open the hosted image's Chrome. What moved and why it can: the `workflows`
gates read the workflows and scripts with bash, awk, sed and grep, run the
steps' scripts against stubs and build forsgren with Go, and the workflows they
pin run on `ubuntu-latest` themselves (except Quality); the git sandbox
isolation self-test (`isolation_1`, `isolation_2`) and the step summary
isolation gate (`summary`) only check that a self-test leaves a decoy
repository or a decoy step summary alone, whatever the self-test's own verdict;
the `report` job merges and renders the hand-overs with bash and awk. The four
gate jobs keep the steps of the others, but their Install tools step is
`Scripts/install_tools_linux.sh Scripts/required_tools_linux_gates.txt`, the
lint job's installer with its own list: shellcheck and yamllint, the two tools
the isolation shards' self-tests run (the shellcheck and yamllint self-tests),
from the same pinned, checksum-verified builds. Go, Node (from
`actions/setup-node`), jq and Python ship with the image; the `report` job
installs nothing. The scripts these jobs run were checked for the GNU and BSD
differences (`sed -i`, `date`, `stat`, `grep -P`, `readlink -f`, `mktemp`,
`xargs`, `find -printf`, `base64` line wrapping, `uniq -c` padding, `awk`
being mawk on Linux, `/bin/sh` being dash); the one that differed, the checkout
pins mutations' `sed -i ''`, now writes a copy with plain `sed`, the same on
both. Expected minutes, before step 4 measures them (macOS medians in
brackets): `workflows` about 7 to 8 (9.0), `summary` about 4 (4.7),
`isolation_1` and `isolation_2` about 4 each (4.8 and 4.5), `report` about 0.3
(0.3); the setup is shorter, the pinned install of two tools taking seconds
where Homebrew took 41 to 93.

**Shards** (forsgren#426). A gate that is too long for one job runs in several,
each with a shard of its own. A row of `Scripts/ci_job_groups.txt` may carry a
third field, `<job>|<label>|<args>`, the arguments the job runs the gate with,
and the same label may stand in several jobs: `isolation_1|git sandbox
isolation self-test|--shard 1/2` and `isolation_2|git sandbox isolation
self-test|--shard 2/2`. The main job skips the gate, each shard job runs it with
its arguments, and `Scripts/run_ci_phase.sh` records its row as `<label> (shard
N/M)` (the arguments without their dashes), so a red names its shard in the
error line, the row and the details. `Scripts/test_git_sandbox_isolation.sh`
takes `--shard N/M` and runs the self-tests at positions N, N+M, N+2M of the
sorted list of git-using self-tests (index modulo M, in the C locale): every
self-test runs in exactly one shard and a new one lands in one by itself, with
no list to edit; a bad shard (`0/2`, `3/2`, `x`) is a usage error, exit 64. The
sharding is of the whole list, before the scope picks the affected ones, so the
split does not move with the commit. Without the argument the gate runs all, as
`FBP.sh` and `sfl.sh` do: they run every order-file row once, never a shard.
`Scripts/merge_quality_report.sh merge` joins the shard rows of one gate into
the one row under the gate's own label, the one the order file declares: green
only when every shard reported green, red naming the shard that failed
(`<gate>: shard 2/2 failed`) or reported no row (`reported no row`), so a shard
job that died early never leaves the gate green. The gate's details hold the
output of every shard. Another long gate shards the same way: its rows get
`--shard` in the group file, one job each in `quality.yml`, and a test of
`--shard` in the gate's own script. `Scripts/run_ci_phase.sh <pre|post> <rows>
<details> [job]` takes the job as its fourth argument (default `main`): a gate
the group file lists runs in that job only, every other gate in the main job,
so a gate is never in two jobs or none, and a group file that names a gate the
order file does not have is red. Each gate job hands over its rows, details
and page count as the artifact `quality-report-<job>`; the `report` job
(`if: always()`, `needs:` every gate job) downloads them,
`Scripts/merge_quality_report.sh` merges them (a gate reported by two jobs is
red, a job that handed over nothing is named and its gates read as unmeasured)
and the two renderers write the one Quality report to its run page, with the
status taken from the jobs' results. The `preview` job `needs:` all of them.
The `browser` job (step 3) runs the browser gate process self-test (the exits,
forsgren#386), the browser gate
and the browser gate on the fixture site with its self-test, with the same
setup (the hosted image's Chrome, puppeteer-core and axe-core from `npm ci`).
The browser gate reads the built site, so the job runs its PRE rows, builds
its own site with `Scripts/build_site.sh`, then runs its POST rows, all with
the job name `browser`.
The `browser_1` job (forsgren#447) runs the browser gate self-test alone, with
the same setup and the job name `browser_1`. It was 256 s of the browser job's
558 s of gates, so the browser job took about 10.6 minutes; split, `browser_1`
is about 5.6 minutes and `browser` about 6.5. It builds no site: the self-test
is a PRE row and reads no built site. The order file is unchanged. The report
job's status takes its result too, and the `preview` job `needs:` it.
The `lint` job (forsgren#282) runs actionlint, shellcheck, yamllint and zizmor
with their self-tests, the lint rows of the order file's static block, with the
same setup and the job name `lint`, so a lint finding is its own red check on
the run. It builds no site: all are PRE rows. The order file is unchanged: the
rows keep their pre phase and their place, so `sfl.sh` and `FBP.sh` run them,
and stop after the static block, as before. The report job's status takes the
lint job's result with the others'.
The `workflows` job (forsgren#408) runs the gates that read only the workflows
and the wiring of the gates: gate wiring, the checkout pins and their
mutations, the pins of the metrics, release, starter page, vulncheck,
auto-update and preview workflows, and the quality jobs pin. It has the same
setup, builds no site (all are PRE rows) and has the job name `workflows`. They
were measured at about 260 s of the main job's PRE step, which took 11 to 14
minutes, so the main job was the critical path at 13 to 15 minutes against 8
for the next job; with them in their own job the main job is about 10 minutes.
The order file is unchanged. The report job's status takes its result too, and
the `preview` job `needs:` it.
The `quality_2` job (forsgren#447) runs nine of the main job's slower gates
and the Go coverage gate, about 180 s together since step 5: the browser gate
inputs self-test, golden pages, the git sandbox isolation
scope self-test, the exit-trap completion behaviour, the CI phase runner
self-test, Go tests, the quality-run summary, the markdown-links self-test, the
HTMLHint self-test and the html duplication generated page self-test. Go tests
and Go coverage stay together because the coverage gate reads the profile the
Go tests gate writes. It has the same setup on `macos-latest` (the exit-trap
completion behaviour gate needs bash 3.2), builds no site
(all are PRE rows and none reads `.build/site`) and has the job name
`quality_2`. The order file is unchanged: every gate keeps its row, so the jobs'
gates together are the order file's rows, each once
(`Scripts/test_quality_jobs.sh` pins that). The report job's status takes its
result too, and the `preview` job `needs:` it.
Go-only gates run on Linux (forsgren#447, steps 5 and 6). The `lint` job also
runs Go lint and its self-test (124 s on the Mac, 146 s at most; they left
`quality_2`), and the `workflows` job also runs go mod tidy, the Go test
duplication self-test and the Go vulnerabilities self-test (85 s, 106 s at
most; they left the main job; the two gates themselves stay in the main job).
Go ships with the hosted Linux image and `GOTOOLCHAIN` comes from `go.mod`, as
for the other Linux jobs, and the Go tools run from `go.mod` (`go tool`), so
neither tools list changes. `quality_2` keeps Go tests and Go coverage together
and so still needs go, node and jq. Expected: Quality gates 2/2 about 7.5
minutes less 2 (measured 9.3, 7.5, 9.7), Quality gates about 1.4 minutes less,
Lint and Workflow gates about 2 and 1.4 minutes more (Workflow gates measured
4.8, 3.4, 5.4).

The three baselines steps stay in the main job: they read the built site.
`Scripts/test_quality_jobs.sh` pins the layout.

**By hand.** `quality.yml` takes no inputs when started by hand: the run is the
full Quality, as on a push. The short Quality for a release bump commit
(forsgren#230) is gone since forsgren#237: the Release workflow makes no bump
commit, it tags the Quality-green head of main.

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
key numbers (forsgren#8), written by the report job's step, which runs after a
failure or a cancel too: the status (succeeded, failed or cancelled, the
phase it stopped in, and what was red: the phase steps and the gate jobs
outside the main job, `red in: PRE, lint job`; forsgren#282), the gates passed, failed and skipped in PRE and in
POST, the Go tests passed, the total checks (every individual check that
ran, counted once: each case of every self-test and gate, each Go test, and
a gate with no case lines as one; passed and failed), the coverage total
with its floor, the floors to raise (the coverage gate's FLOORWARN count), the pages generated, the
forsgren version, the commit and trigger (push, pull request with its
number, or by hand) and the duration. `Scripts/render_quality_summary.sh`
reads them from what the run already wrote (the gate rows and outputs, the
page-count sink, `cmd/forsgren/main.go`) and from the job's status and step
outcomes, passed through `env:`. The gate jobs are the jobs of
`Scripts/ci_job_groups.txt`, in its order, each read from its
`QS_<JOB>_RESULT` (`needs.<job>.result`): a red one is named in the red list
(`red in: isolation_2 job, browser job`), a cancelled or skipped one as such
(`browser job cancelled`), never as red, and a run whose every job and phase
is green keeps its line. A number that does not exist, from a phase
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

**The runner.** Each job runs on a GitHub-hosted image, `macos-latest` or,
for the Linux jobs above, `ubuntu-latest`, a fresh virtual machine per run,
thrown away after it (Yves's ruling on forsgren#1, road to public: the runner
swap). The macOS image has Homebrew and a Go to start from; everything else
comes from `Scripts/install_tools.sh` (on Linux `Scripts/install_tools_linux.sh`
with the job's list), `npm ci`, the `go.mod` pins and the `.nvmrc` Node pin, as
locally.

**On pull requests, safely.** Quality triggers on `pull_request` into
`main`, so a contributor's pull request shows the same gate results as a
local `./FBP.sh` run, and never on `pull_request_target`. A pull request
from a fork runs its own code here, which is safe only because of the two
things the ruling pairs with the trigger: the machine is GitHub's and is
thrown away after the job, and a fork's `pull_request` run gets a read-only
token (`contents: read`) and no secrets. The **quality runner pins** gate
pins each job to its image (`macos-latest`, or `ubuntu-latest` for the Linux
jobs, forsgren#427 and forsgren#447),
and the rule holds for every workflow: the
**workflow triggers** gate below is red on any of them that triggers on a
pull-request event while one of its jobs runs anywhere but on a
GitHub-hosted runner. A new push to a pull request cancels its run in
flight; runs on `main` are never cancelled, each commit gets its own.

**The private-names secret.** The PRE step gets the Actions secret
`FORSGREN_PRIVATE_NAMES` through `env:`, the list the **private names**
gate searches for (see [Quality gates](quality-gates.md)). When the secret
is not set or is empty, the gate fails with exit 2 and a line that names
it: `the Actions secret FORSGREN_PRIVATE_NAMES is not set or is empty here`
(forsgren#81). A fork's pull request gets no secrets, so on one the gate is
always red; the line says so, and the maintainer runs `./FBP.sh` on the
branch instead.

**Repository settings behind the gates.** On top of that, GitHub holds
every workflow run of a pull request from an outside contributor until the
maintainer approves it, and the repository requires every action to be
pinned to a full commit SHA, the rule **checkout pins** checks in the
files. Secret scanning with push protection and Dependabot alerts are on
too, behind the secret scan and npm audit gates. These are settings, not
files: no gate can see them.

**The DCO check, on pull requests and on every push to main.**
`.github/workflows/dco.yml` triggers on `pull_request` (never
`pull_request_target`), as Quality does, and may because its one job runs
on a GitHub-hosted runner (`ubuntu-latest`), with a read-only token
(`contents: read`, `pull-requests: read`, `checks: read`), and on every push to `main`
(forsgren#81: forsgren does not work through pull requests, so until then
no commit on `main` was checked). It holds every commit of the pull
request, and every commit the push brings, to the
Developer Certificate of Origin (see [CONTRIBUTING.md](../CONTRIBUTING.md)):
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
review of such a change is the guard there. On a push, the job checks out
the pushed commit with its history and `Scripts/dco_push_commits.sh` lists
only the pushed range, `before..after` (the two shas through `env:`),
oldest first, in the check's input lines; a push that creates a branch is
checked on its head commit, and a range with no commit in it is red, never
an empty pass. Commits of an earlier push are not judged again. A push names
no account and no one opened it, so no commit of a push is exempt as a bot's,
a direct push included. A pull request merged with GitHub's merge button
lands its commits and a merge commit on `main` (forsgren#267), so
`Scripts/dco_push_check.sh` first asks the API which pull requests each
pushed commit belongs to (`GET /repos/{repo}/commits/{sha}/pulls`, `gh api`,
with the job token and the repository through `env:`). A commit of a merged
pull request of this repository whose **DCO sign-off** check run (made by
GitHub Actions) succeeded on that pull request's head is already judged by
that run, which knew who opened the pull request, so it is not judged again
and the output says so; the merge commit GitHub made for it (committed by
GitHub, verified by GitHub, its second parent that head) is exempt, and the
output says so. Every other pushed commit gets the strict rule above: a
commit of a pull request whose DCO run failed or is missing, a pull request
that is not merged or is another repository's, a squash or rebase commit
(not one of the pull request's commits), a merge commit that GitHub did not
make, verify or whose second parent is another, and every direct push. A
failed API call is asked once more after a short pause (forsgren#287:
GitHub once answered a pull request lookup with an empty body, and a
signed-off push turned red): `Scripts/lib_dco_api.sh`, which the push check
and the pull request listing (`Scripts/dco_pr_commits.sh`) share, waits
`DCO_RETRY_PAUSE` seconds (default 5) and asks again. A retry that answers
goes on with one `⚠️` line naming the first failure; a second failure is red
naming both reasons, never a pass, so an outage or a missing permission
still shows its cause. The workflow's token
reads `contents`, `pull-requests` and `checks` and writes nothing. Runs on pull requests share a group and a new push cancels the
one in flight; runs on `main` are never cancelled, each commit gets its
own. The check does not run in `sfl` or Quality, since it judges the
commits a pull request or a push brings; its
self-test does (**DCO sign-off self-test**, `Scripts/test_check_dco.sh`,
offline, with mutation proofs for the last-paragraph rule, the email
comparison, the account-type rule and the opener comparison, a
throwaway repository for the push listing, and a stub `gh` for the push
check, one mutation proof per condition of its two exemptions, and one for
the retry), and **gate wiring** is red when
`dco.yml` stops running the check or the push listing, loses its push
trigger on `main`, does not check out `Scripts/lib_dco_api.sh` in both jobs,
or the self-test loses its row.

**Private names in commit messages (forsgren#213).** This repository is
public and a commit message is published with its commit. `FBP.sh` refuses a
message that names a private name, but a pull request's commits and a push
made by hand never pass through it, so the second job of `dco.yml`
(**Private names in commit messages**) judges the message of every commit a
pull request or a push to `main` brings with the same matcher and list as the
private names gate: `Scripts/check_commit_messages.sh` sends each message, on
stdin, to `Scripts/check_private_names.sh --message -` (canon v2, unchanged:
the list from the Actions secrets `FORSGREN_PRIVATE_NAMES` and
`FORSGREN_PRIVATE_NAMES_EXTRA`, a case-insensitive substring match, the
repository's own name left out). A hit is red and names the short sha and the
commit's number in the list; the output never holds a name, a message or a
subject. History is never rewritten: the commit is reworded by hand, or the
name leaves the list. The job lives in `dco.yml`, not in `quality.yml`,
because that workflow already runs on every pull request and every push to
`main` without checking out the pull request's code (the check comes from the
base commit, so a pull request cannot change what judges it), has the full
history a push's range needs, and has the two commit listings:
`Scripts/dco_pr_commits.sh` (the commits API, moved out of the workflow so
both jobs list a pull request the same way) and `Scripts/dco_push_commits.sh`.
A push is listed with `--fresh`: a range `before..after` is listed as the DCO
job lists it, but a new branch (an all-zero `before`) or a `before` the
checkout does not have (a force-push removed it) cannot say which commits are
new, so every commit of the pushed head that is on no other remote branch and
no tag is listed, never the head commit alone and never nothing; a commit
another branch or a tag already holds was pushed before and is not judged
again. A list with no commit is red. In Actions the list must exist: unlike
`--message` alone, which passes without a list on a laptop, the check is
exit 2 with no secret or an emptied one, and so on a fork's pull request,
which gets no secrets. Its self-test is the **commit messages self-test**
(`Scripts/test_check_commit_messages.sh`, offline, a throwaway repository with
made-up names, mutation proofs for judging only the last commit and for
skipping the range when `before` is unavailable), and **gate wiring** is red
when `dco.yml` stops running the check, the pull request listing or the push
listing with `--fresh`.

**The metrics workflow, for installations.** `.github/workflows/metrics.yml`
is the reusable workflow a data repository calls daily (see [Running
forsgren](configuration.md#running-forsgren)). It triggers on `workflow_call` only, so it never runs in this
repository and no pull request can start it. Its one job runs on
`ubuntu-latest`, in the caller's repository and with the caller's token,
checks out the caller's repository only (never forsgren's), and asks for
`pages: write`, `id-token: write` and `contents: write` (the starter step,
the README step and the data step each push one commit) and, optionally, `pull-requests:
read` (forsgren#40), all as the caller grants them: the workflow has no
`permissions:` block, so its job takes exactly what the caller's job grants
and a caller that has not added the optional one still starts (a token
without it is a 403 the lookup of the waiting Dependabot pull request treats
as unknown). Its concurrency group is the caller's
repository, `cancel-in-progress: false`. It takes no inputs: the
caller's `uses: …/metrics.yml@<commit>` line is the only version. Its one
secret, `FORSGREN_TOKEN`, is optional and reaches the collect step's `env:`
only. Its
steps: set up Go (`actions/setup-go` on exactly `go.mod`'s toolchain,
`cache: false`), check its own `job.workflow_sha` is a full 40-digit commit
and its own `job.workflow_repository` one `owner/name`, then
`go install github.com/<that repository>/cmd/forsgren@<that commit>`,
check out the caller's repository (`actions/checkout`, pinned at Quality's
commit, `persist-credentials: false`), `forsgren init-config --config
forsgren.config.yml` and, when it created the file, one commit of that file
alone as `github-actions[bot]`, pushed to the branch the run is on with the token
in git's environment only (so it is in no argument, file or log and the
checkout still stores nothing), `forsgren install-readme --out README.md`
and, when it created or replaced the README, one commit of `README.md` alone,
"forsgren: update README.md", pushed the same way (an `::error` on a tag, a
branch that moved or a refused push, recorded as `readme=failed`, and the run goes on;
forsgren#110), `forsgren check-config --config
forsgren.config.yml` (its message printed between
`::stop-commands::<token>` and `::<token>::`, a fresh random token per
run, so a line of it that starts with `::` never runs as a workflow
command), `forsgren collect --config forsgren.config.yml --data
data/deployments.csv --token-expiry "${RUNNER_TEMP}/token-expiry" --cut-report
"${RUNNER_TEMP}/collect-report"` (its output shown with workflow commands stopped, its
exit status kept as a step output), a commit of
`data/` alone when it changed, pushed like the starter (an `::error` naming a
branch that moved, never a rebase or a force), `forsgren render --config
forsgren.config.yml --data data/deployments.csv` (with `--latest`,
`--waiting-pr` and `--pr-check` from the lookups), `forsgren run-summary`
appended to the job summary (with `--readme` from the README step), then `actions/upload-pages-artifact` and
`actions/deploy-pages` into the `github-pages` environment, and last two steps
that fail the job when collect failed and when the README could not be pushed
(`readme=failed`; it runs unless the run was cancelled). The job
context, not the `github` context: in a called workflow the `github`
context is the caller's. `setup-go` exports `GOTOOLCHAIN=local`, so
`go install` builds with that Go and never switches to another. The commit
and repository reach the shell through `env:`, never as `${{ }}` inside
`run:`. The two checks are regexes inside the workflow, not a script under
`Scripts/`: the job has no checkout of forsgren, and the only commit it
could fetch one at is the one still unchecked, and the starter and data
steps' logic is the commit and the push, which only git can do. The
**metrics workflow** pin below executes those very blocks, the starter,
README and data steps with a real git against a local remote.
Nothing in this repository runs the workflow, so no gate does; the pin and
actionlint, zizmor, yamllint, checkout pins and workflow triggers, which read
every workflow, are what check it.

**The starter page, forsgren.be.** The project's own page is `README.md`
rendered to one HTML page and published to GitHub Pages at
<https://forsgren.be>. `.github/workflows/starter_page.yml` builds it on a
push to `main` that touches the README, the renderer (`cmd/readmepage`,
`internal/readmepage`), the stylesheet it ships (`internal/page/styles.css`),
the build script or the workflow itself, and by hand. A published release does
not redeploy it: the page carries nothing from a release (forsgren#527). The
build job runs `Scripts/build_starter_page.sh` into
`.build/starter` (`index.html`, `styles.css`, the same stylesheet the metrics
site uses, and a `CNAME` holding `forsgren.be`) and uploads that folder; the
deploy job, the only one holding `pages: write` and `id-token: write`,
publishes it to the `github-pages` environment. The renderer reads a small
subset of Markdown and refuses everything else, naming the file and the line
(`README.md:3: unsupported Markdown, a line starting with ">": > quoted`; an
error found inside a line, such as a bad link or an image, names the first
line of its block), so a README that grows a table or a raw HTML block fails
the build instead of publishing a wrong page; every relative link in it becomes a link into the
repository on `main`. The gates that read the page (HTMLHint, the privacy
posture, and the starter-page links, which allow only this repository,
forsgren-template and the live example) are in [Quality gates](quality-gates.md).
To build it locally: `./Scripts/build_starter_page.sh`, then open
`.build/starter/index.html`.

What had to be set up once, on the repository and not in a file:

- **GitHub Pages** enabled with the source "GitHub Actions" (Settings, Pages).
  Until it is, a release-triggered run skips the deploy with a notice saying
  so, and a push or a manual run fails at the deploy step by name.
- **The `github-pages` environment** limits deployments to chosen refs: a
  branch rule for `main` and a tag rule for `v*`. Without the `v*` tag rule a
  release run builds, then is refused at the deploy job, because a release
  runs on its tag, not on `main`.
- **The custom domain** `forsgren.be`, set in Settings, Pages, only after the
  DNS is complete (the apex A and AAAA records and a `www` CNAME to GitHub
  Pages). Set earlier, GitHub's check fails and leaves the site without a
  certificate; a domain whose certificate stays empty or new is fixed by
  removing the custom domain and adding it again. HTTPS is enforced and
  `www.forsgren.be` redirects to the apex.

**No paths filter, on purpose.** The secret scan, the data guard, stray
tracked files and script references read every tracked file, so a filter
on paths would leave some change that runs no gate.

Nine PRE gates keep the CI honest:

- **gate wiring** (`Scripts/test_gate_wiring.sh`, another estate repository's,
  adapted): every runnable row of the order file has phase `pre` or `post`
  (any other phase runs in neither); `FBP.sh` and `quality.yml` each run
  PRE, the build and POST in that order; `sfl.sh` and
  `Scripts/run_ci_phase.sh` read a row with the same rules; every script
  that no row names is a declared exemption with the runner it must still
  be run by. It holds the gate-count ratchet: `MIN_GATES` is the number of
  rows of the order file (n/a rows included), it may only go up, and a
  self-proof removes one row and requires the count to fall under it.
- **CI phase runner** (`Scripts/test_run_ci_phase.sh`, the estate canon):
  runs `Scripts/run_ci_phase.sh` over the real order file with a stub at
  every declared path (each row must run exactly once, in its own phase, in
  file order) and over made-up order files (failures, the secret-class exit,
  malformed rows, a missing or non-executable script, the tree check, a
  phase with no row), and against weakened copies of the runner.
- **quality trigger scope** (`Scripts/test_quality_trigger_scope.sh`, the
  sites' shared canon, forsgren#240): the workflow has no `paths` or
  `paths-ignore` filter, or a `paths` filter that holds every glob the gates
  read; it must have a `pull_request` trigger.
- **quality runner pins** (`Scripts/test_quality_runner_pins.sh`, forsgren's
  own, forsgren#240): the workflow runs on every push to `main` and every `pull_request` into it,
  neither with a `paths` or `paths-ignore` filter, never on
  `pull_request_target`, and on `workflow_dispatch`; and each job runs on
  the GitHub-hosted image it names, `ubuntu-latest` for the Linux jobs and
  `macos-latest` for the others (a hosted image is what makes the
  pull-request trigger safe), with at most 5 `macos-latest` jobs starting
  together (forsgren#447).
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
- **starter page workflow** (`Scripts/test_starter_page_workflow.sh`,
  forsgren's own, forsgren#132): `starter_page.yml` renders `README.md` and
  publishes it to GitHub Pages (forsgren.be). It triggers on a push to `main`
  filtered to the README, the renderer, the stylesheet, the build script and
  itself, on a published release, and by hand, never on a pull request; the
  workflow has `contents: read` and only the deploy job adds `pages: write`
  and `id-token: write`; all three jobs run on `ubuntu-latest`; every action is
  pinned at the very commit `metrics.yml` pins; the build step runs exactly
  `./Scripts/build_starter_page.sh` and uploads `.build/starter`; no `run:`
  block expands a `${{ }}` expression. A release-triggered run first asks
  `gh api repos/<repository>/pages`: a 404 skips the deploy with a notice
  naming the cause (Pages is not enabled), any other failure fails the step,
  and a push or a manual run is not checked. The check is executed in the
  test with a stub `gh`. The real file must hold every pin and each pin is
  proved by a mutant that breaks it. GitHub Pages must be enabled on the
  repository with the source "GitHub Actions" for the deploy to succeed. A
  third job, `live-check` (forsgren#205), needs `deploy`, runs only when the
  deploy step really published (the deploy job's `deployed` output) and runs
  `./Scripts/live_check.sh https://forsgren.be` with `contents: read`; the pin
  holds its needs, condition, permission, checkout and command, each proved by
  a mutant.
- **vulncheck workflow** (`Scripts/test_vulncheck_workflow.sh`, forsgren's
  own, forsgren#87): `vulncheck.yml` runs `Scripts/check_govulncheck.sh`, the
  script of the Go vulnerabilities gate, once a day (one cron entry at an
  off-peak minute) and by hand, so a vulnerability published on a day nobody
  pushes still turns a run red; Quality runs only on a push or a pull request.
  It triggers on `schedule` and `workflow_dispatch` and on nothing else,
  never a push or a pull request; it has `contents: read`, one job on
  `ubuntu-latest`, `actions/checkout` (no persisted credentials) and
  `actions/setup-go` pinned at the very commits `metrics.yml` pins, and takes
  `GOTOOLCHAIN` from `Scripts/go_toolchain.sh`; govulncheck is the version
  `go.mod` pins. The scan step sets `FORSGREN_VULN_DB_REQUIRED=1`: a
  vulnerability database it cannot reach fails the run (the gate would
  otherwise skip with a warning and exit 0, which on a schedule reads as
  green), and a found vulnerability fails it with the script's own `❌` line
  naming the IDs and the fixed version. A failed scheduled run is visible in
  Actions; no issue is opened. The real file must hold every pin and each
  pin is proved by a mutant that breaks it.
- **token expiry probe** (`Scripts/test_probe_token_expiry.sh`, forsgren's
  own, forsgren#269): `token_expiry_probe.yml` runs weekly (Mondays, one cron
  entry at an off-peak minute) and by hand, with `contents: read` only.
  `Scripts/probe_token_expiry.sh` makes one `GET /user` call per token with
  the Actions secrets `FORSGREN_RELEASE_TOKEN`, `PREVIEW_DISPATCH_TOKEN` and
  `FORSGREN_TOKEN` (the token goes to curl on stdin, never in an argument or
  the output), reads `github-authentication-token-expiration` and writes
  `token-probed.tsv`, one line per secret, `<SECRET_NAME><TAB><YYYY-MM-DD |
  never | error: <reason>>`, uploaded as the artifact `token-expiry-probe`
  even when the probe fails. A header `2026-12-27 10:00:00 UTC` is the date
  `2026-12-27`; an answer with no header is `never` (GitHub sends the header
  only for a token that expires); a secret not set, a refused call (HTTP 401),
  a failed curl or an unreadable header is an `error:` line, never a skip, and
  turns the run red with a `❌` line naming the secret after the artifact is
  uploaded. The self-test uses a stub curl and pins the workflow.
- **release workflow** (`Scripts/test_release_workflow.sh`, forsgren's own,
  forsgren#221): `release.yml` releases patch, minor or major in one run,
  started by hand or through the API (`workflow_dispatch` only, the input
  `bump` a choice of patch, minor, major, default patch; one release at a
  time, never cancelled). The top level has `contents: read`; the one job, on
  `ubuntu-latest`, adds exactly `contents: write`, `actions: write` and
  `issues: read`. It uses `actions/checkout` (no persisted credentials) and
  `actions/setup-go` at the commits `metrics.yml` pins, and every step is a
  tested script: Quality on main, the plan, the new version, the bump and
  `go test`, the signed-off commit, Quality dispatched on it, the release,
  the template pins, the metrics pin pull request, the report. No `run:` block
  expands a `${{ }}` expression, the tag is made only by
  `Scripts/release_publish.sh`, and the secret `FORSGREN_RELEASE_TOKEN` is in
  the env of exactly three steps. The scripts' self-tests are order-file rows.
  See [Updating and releases](updating-and-releases.md#the-release-workflow).
- **preview deploy** (`Scripts/test_dispatch_preview.sh` and
  `Scripts/test_preview_workflow.sh`, forsgren's own, forsgren#222): the
  script's self-test runs it against a stub `curl`: 204 is the only success; a
  200, 202, 302, 404, 422 or 500, or a curl that fails, fails naming the
  status; an empty token (with `GH_TOKEN` and `GITHUB_TOKEN` set or not) and a
  bad sha fail without calling curl; the token reaches curl as a header on
  stdin, never in its arguments. Three mutation proofs: a copy that accepts any
  2xx, one without the empty-token guard and one without the sha check each
  let their case pass. The workflow pin reads the `preview` job of
  `quality.yml`: its `needs:` names every other job (a gate job added later
  must be added), its `if:` is exactly the push-to-main condition and holds no
  `always()`, `failure()`, `cancelled()` or `success()`, it runs on
  `macos-latest` with `contents: read`, the fixed non-cancelling group,
  `actions/checkout` at the very commit `metrics.yml` pins without persisted
  credentials, the one secret reference of the file in the start step's
  `env:`, the exact command, no `${{ }}` in a `run:` block, nothing that
  softens a failed start, and no `workflow_run` in the file; each pin is
  proved by a mutant of the real file (a missing `needs:`, a missing
  push-only condition, `always()` added, a gate job left out of `needs:`).
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
  the starter step, executed with a real git against a local remote and
  with a stub and the real `forsgren`, commits a created
  `forsgren.config.yml` alone as `github-actions[bot]`, unsigned even under
  a hostile inherited git environment, pushes it to the run's branch with
  the token in git's environment only (pin 13), exits 0 for a kept file
  before any branch logic and refuses on a tag, and the workflow has no
  `permissions:` block and names no `pull-requests:` permission (pin 16: a
  called workflow that asks for more than its caller grants stops the run,
  so it takes what the caller grants);
  `workflow_call` declares the one secret `FORSGREN_TOKEN`, `required:
  false`, and the only `${{ secrets… }}` in the file is the collect step's
  `env:`; the collect step, executed with a stub and with the real
  `forsgren`, runs exactly `forsgren collect --config forsgren.config.yml
  --data data/deployments.csv --token-expiry ${RUNNER_TEMP}/token-expiry
  --cut-report ${RUNNER_TEMP}/collect-report` (the files the needs step and
  the run summary read), records its exit status as the output
  `status` and succeeds, keeps the token out of arguments, files, the log
  and outputs, with no token passes the starter and records a failure
  naming `FORSGREN_TOKEN` for a configured repository, and, as the config
  step does, leaves no line of collect's output (both streams) that starts
  with `::` live as a workflow command, under a token that differs per run,
  with the stub and with the real `forsgren`; the data step,
  executed with a real git against a local remote, commits nothing when
  `data/` is unchanged (on a tag too), else one commit of `data/` alone as
  `github-actions[bot]`, unsigned even under a hostile inherited git
  environment, pushed to the run's branch with the token as pin 13 has it,
  refused on a tag, and failing with an `::error` naming a branch that
  moved, with no rebase and no force; the last step fails the job for any
  collect status but 0, and collect failing after storing still commits and
  pushes; the job's concurrency group is keyed on `github.repository` with
  `cancel-in-progress: false`; the render step, executed with a stub, runs
  exactly `forsgren render --out <dir> --config forsgren.config.yml --data
  data/deployments.csv`, plus `--latest <version>` when the step before it
  found one; that step, "Look up the latest forsgren release", gets the job's
  token as `GITHUB_TOKEN` (never the caller's secret), runs `forsgren
  latest-release --published "${RUNNER_TEMP}/latest-published"` (the publish
  time, for the summary's cooldown, forsgren#194), outputs a plain
  version, and outputs nothing, never failing the job, for a lookup that
  fails or an answer that is anything else; the step after it, "Look up the
  waiting Dependabot pull request", does the same for a pull request number
  (also with the job's token, and asked only when a latest release was
  found; the pull request is found by its files moving the `metrics.yml` pin
  to that release, never by its branch name, forsgren#42) and outputs its `check` (`ok`, `no-access`, `rate-limited`, `truncated`, `failed`, or `skipped`
  without a latest release) from the status file the lookup wrote, anything
  else counting as `failed`, and the render step passes `--waiting-pr
  <number>` when it is set and `--pr-check <check>` when the check is set
  (forsgren#203); the step "Write the run summary" appends
  `forsgren run-summary`'s markdown to `$GITHUB_STEP_SUMMARY` and never fails
  the run (a `run-summary` that fails appends nothing); it passes `--token-expiry
  "${RUNNER_TEMP}/token-expiry"`, the file collect writes, for the summary's
  Token line (days or hours left, the run's own token, no expiry date, an
  unreadable date, or unknown), `--collect-report
  "${RUNNER_TEMP}/collect-report"`, the report collect writes, for the
  Collected line (complete, or incomplete with the repositories the request
  budget cut short, `issues and pull requests not read`, those whose pull
  requests alone it cut short, `<repo> pull requests cut short (deployments
  and issues read)` (forsgren#320), those whose backfill of the legacy
  commits it cut short, `<repo> legacy commits cut short (deployments, issues
  and pull requests read)` (forsgren#385), and those that failed on a rate limit;
  unknown, never complete, without the file; forsgren#64), and `--latest-published
  "${RUNNER_TEMP}/latest-published"`, the file the lookup step writes, for
  the Update line's Dependabot cooldown, and `--readme <word>` only when the
  README step's `readme` output is set (forsgren#110); the step "Write the
  installation README" (pin 35), executed with the real `forsgren` and a
  real git against a local remote, runs `forsgren install-readme --out
  README.md`, outputs the word it printed as `readme`, commits a created or
  replaced `README.md` alone, "forsgren: update README.md", as
  `github-actions[bot]` (unsigned under a hostile inherited git
  environment), pushes it with the token as pin 13 has it, commits and
  pushes nothing for an unchanged README, refuses a changed one on a tag by
  name, and names a branch that moved or a refused push in an `::error`, with no
  rebase, no force and no local commit left behind; both record `readme=failed` and
  exit 0, and the data step after them still pushes `data/` alone, the run
  summary says "README: not pushed: see the README step" and the step "Fail the job
  when the README could not be pushed" (`if: ${{ !cancelled() }}`, after collect's
  own fail step) fails the job for that output only; and the whole job for the README (pin 36: the
  starter, README and summary steps run together in the workflow's order)
  gives a new installation the starter commit, the README commit and
  "README: created from forsgren X.Y.Z's", an installation with a
  hand-written README one bot commit of `README.md` alone and "replaced
  with forsgren X.Y.Z's", and its next run no commit and "README:
  unchanged";
  and install, checkout, starter, README, config
  check, collect, data commit and render come in that order, the fail step
  after publishing. Each pin is shown failing, with its own reason, on a
  mutant of the real file, judged by the pin it is aimed at.
- **quality-report render** (`Scripts/test_render_quality_report.sh`): the
  summary renderer (`Scripts/render_quality_report.sh`) keeps the declared
  order, exits 0 on a report it rendered, tells an empty or partial run from
  a clean one, and does not count an `n/a` row as a gate that should have
  reported. Its gate table (forsgren#219) is `| Gate | Checks | Result |`:
  Checks is the number of `ok:` and check-mark lines in the gate's own output,
  `not counted` (never 0) when the gate prints none and `not readable` when its
  details file cannot be read; the Gate cell is the plain label (GitHub keeps
  no in-page link or anchor in a job summary, so none is written). Under the
  table the page lists the details of the gates that are not green only (forsgren#235,
  canon `render_quality_report v3`); a green gate's full output stays in
  the job log, so a green run ends after the table. `CONTRIBUTING.md` lists every
  gate between two markers, generated by `Scripts/render_gate_list.sh` (canon
  `render_gate_list v1`, pinned by `Scripts/test_gate_wiring.sh`) from the
  order file, and the same test fails when the two differ. Shown failing, each with
  its own reason, on mutants that show 0, link a label,
  call an unreadable gate not counted and count the verdict line.
- **quality-run summary** (`Scripts/test_render_quality_summary.sh`,
  forsgren's own): the run summary (`Scripts/render_quality_summary.sh`)
  renders every number of a green run, says where a red, cancelled or
  setup-stopped run stopped, names a red gate job in its red list and a
  cancelled or skipped one as such, names a pull request's number, exits 0 on
  whatever it is given, and shows `—` with the reason for a phase that
  never ran or an output that is missing, never 0; its total checks count
  every case-line format of the real gates once, each Go test once, no
  verdict line, a red gate's failures, and name a phase they are missing, a
  gate that never reported and a case-line format they do not know; shown
  failing, each with its own reason, on mutants that write 0 instead, that
  sum only the phases they have, that count verdict lines, that drop
  the unknown-format guard, that leave a red gate job unnamed, that name a
  cancelled job as red, and that name the jobs in another order.
