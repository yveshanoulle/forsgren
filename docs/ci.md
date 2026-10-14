# CI

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
review of such a change is the guard there. The check does not run in
`sfl` or Quality, since a commit on `main` has no pull request; its
self-test does (**DCO sign-off self-test**, `Scripts/test_check_dco.sh`,
offline, with mutation proofs for the last-paragraph rule, the email
comparison, the account-type rule and the opener comparison), and **gate wiring** is red when `dco.yml` stops running
the check or the self-test loses its row.

**The metrics workflow, for installations.** `.github/workflows/metrics.yml`
is the reusable workflow a data repository calls daily (see [Running
forsgren](configuration.md#running-forsgren)). It triggers on `workflow_call` only, so it never runs in this
repository and no pull request can start it. Its one job runs on
`ubuntu-latest`, in the caller's repository and with the caller's token,
checks out the caller's repository only (never forsgren's), and asks for
`pages: write`, `id-token: write` and `contents: write` (the starter step
and the data step each push one commit) and, optionally, `pull-requests:
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
checkout still stores nothing), `forsgren check-config --config
forsgren.config.yml` (its message printed between
`::stop-commands::<token>` and `::<token>::`, a fresh random token per
run, so a line of it that starts with `::` never runs as a workflow
command), `forsgren collect --config forsgren.config.yml --data
data/deployments.csv` (its output shown with workflow commands stopped, its
exit status kept as a step output), a commit of
`data/` alone when it changed, pushed like the starter (an `::error` naming a
branch that moved, never a rebase or a force), `forsgren render --config
forsgren.config.yml --data data/deployments.csv`, then `actions/upload-pages-artifact` and
`actions/deploy-pages` into the `github-pages` environment, and last a step
that fails the job when collect failed. The job
context, not the `github` context: in a called workflow the `github`
context is the caller's. `setup-go` exports `GOTOOLCHAIN=local`, so
`go install` builds with that Go and never switches to another. The commit
and repository reach the shell through `env:`, never as `${{ }}` inside
`run:`. The two checks are regexes inside the workflow, not a script under
`Scripts/`: the job has no checkout of forsgren, and the only commit it
could fetch one at is the one still unchecked, and the starter and data
steps' logic is the commit and the push, which only git can do. The
**metrics workflow** pin below executes those very blocks, the starter and
data steps with a real git against a local remote.
Nothing in this repository runs the workflow, so no gate does; the pin and
actionlint, zizmor, yamllint, checkout pins and workflow triggers, which read
every workflow, are what check it.

**No paths filter, on purpose.** The secret scan, the data guard, stray
tracked files and script references read every tracked file, so a filter
on paths would leave some change that runs no gate.

Six PRE gates keep the CI honest:

- **gate wiring** (`Scripts/test_gate_wiring.sh`, another estate repository's,
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
  --data data/deployments.csv`, records its exit status as the output
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
  token as `GITHUB_TOKEN` (never the caller's secret), outputs a plain
  version, and outputs nothing, never failing the job, for a lookup that
  fails or an answer that is anything else; the step after it, "Look up the
  waiting Dependabot pull request", does the same for a pull request number
  (also with the job's token, and asked only when a latest release was
  found) and outputs its `check` (`ok`, `no-access`, `rate-limited`, `failed`, or `skipped`
  without a latest release) from the status file the lookup wrote, anything
  else counting as `failed`, and the render step passes `--waiting-pr
  <number>` when it is set; the step "Write the run summary" appends
  `forsgren run-summary`'s markdown to `$GITHUB_STEP_SUMMARY` and never fails
  the run (a `run-summary` that fails appends nothing);
  and install, checkout, starter, config
  check, collect, data commit and render come in that order, the fail step
  after publishing. Each pin is shown failing, with its own reason, on a
  mutant of the real file, judged by the pin it is aimed at.
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
