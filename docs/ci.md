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
footer reads "Forsgren 1.11.1+dev (c41db9e)" (forsgren#224). A release is
installed as a module at a pinned commit, which records none, and
`Scripts/build_site.sh` builds with `-buildvcs=false`, so both keep the plain
version. The deploy itself lives in the preview repository,
`yveshanoulle/forsgren-metrics-feta`, whose `preview.yml` takes the pushed sha
as its one input. The job only starts it: `Scripts/dispatch_preview.sh <sha>`
POSTs a `workflow_dispatch` with the Actions secret `PREVIEW_DISPATCH_TOKEN`,
a fine-grained token that holds Actions read and write on the preview
repository and nothing else, and requires HTTP 204. Any other answer, an empty
token or a sha that is not 40 lower-case hex digits fails the run; the script
never falls back to another token or login. The job `needs:` every other job,
with no status function in its `if:`, so a commit that fails a gate never
reaches the preview; its `if:` keeps it off pull requests, where no secret
exists; it holds `contents: read` and runs on `macos-latest` like every job
of the file. Its own concurrency group never cancels a run in flight (the
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

**Scope (forsgren#230).** `quality.yml` takes a `scope` when started by hand:
`full` (the default; a push and a pull request are always full) or `bump`, the
short Quality the Release workflow dispatches on its bump commit, with
`green_parent`, `old_version` and `new_version`. With `bump` the run does the
same setup, then FIRST `Scripts/release_bump_diff.sh` (the commit holds only the
version bump on the green parent; when it is red nothing else runs), then
`Scripts/run_short_quality.sh`, which runs only the PRE rows of
`Scripts/quality_bump_gates.txt` (secret scan, Go tests, golden pages, Go lint),
then the site build; POST is skipped. Nothing is skipped silently: the run page
opens with `short Quality for a release bump: N gates`, names the gates that ran
and every gate of the order file that did not, and the summary says it is a
short Quality. `Scripts/test_quality_scope.sh` pins this; the list lives only in
`Scripts/quality_bump_gates.txt`.

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
`Scripts/install_tools.sh`, `npm ci`, the `go.mod` pins and the `.nvmrc` Node pin, as locally.

**On pull requests, safely.** Quality triggers on `pull_request` into
`main`, so a contributor's pull request shows the same gate results as a
local `./FBP.sh` run, and never on `pull_request_target`. A pull request
from a fork runs its own code here, which is safe only because of the two
things the ruling pairs with the trigger: the machine is GitHub's and is
thrown away after the job, and a fork's `pull_request` run gets a read-only
token (`contents: read`) and no secrets. The **quality runner pins** gate
pins this job to `macos-latest`, and the rule holds for every workflow: the
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
(`contents: read`, `pull-requests: read`), and on every push to `main`
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
no account and no one opened it, so no commit of a push is exempt, a bot's
included. Runs on pull requests share a group and a new push cancels the
one in flight; runs on `main` are never cancelled, each commit gets its
own. The check does not run in `sfl` or Quality, since it judges the
commits a pull request or a push brings; its
self-test does (**DCO sign-off self-test**, `Scripts/test_check_dco.sh`,
offline, with mutation proofs for the last-paragraph rule, the email
comparison, the account-type rule and the opener comparison, and a
throwaway repository for the push listing), and **gate wiring** is red when
`dco.yml` stops running the check or the push listing, loses its push
trigger on `main`, or the self-test loses its row.

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
the build script or the workflow itself, on a published release, and by hand.
A release redeploys the page, so it is always rebuilt from the README of the
release's day. The build job runs `Scripts/build_starter_page.sh` into
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
  budget cut short and those that failed on a rate limit; unknown, never
  complete, without the file; forsgren#64), and `--latest-published
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
  setup-stopped run stopped, names a pull request's number, exits 0 on
  whatever it is given, and shows `—` with the reason for a phase that
  never ran or an output that is missing, never 0; its total checks count
  every case-line format of the real gates once, each Go test once, no
  verdict line, a red gate's failures, and name a phase they are missing, a
  gate that never reported and a case-line format they do not know; shown
  failing, each with its own reason, on mutants that write 0 instead, that
  sum only the phases they have, that count verdict lines, and that drop
  the unknown-format guard.
