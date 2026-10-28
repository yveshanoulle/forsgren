# Getting started

A short page for your first hour as a contributor.
The reference pages go deeper: [Development](development.md),
[Quality gates](quality-gates.md) and [CI](ci.md).

## What forsgren is

forsgren measures the five DORA metrics for a set of GitHub repositories and
publishes them as a small static page.
It is one Go module.
See the [README](../README.md) for what it produces.

## What you need

- macOS with Homebrew. The gates are scripts that use Homebrew tools, and CI
  runs them on macOS too, so a local run gives the result CI gives.
  If you want to help us out and have a windows machine, contact us and we help you set this up. 
- Go. You need no particular version: `go.mod` has a `toolchain` line, and
  `FBP.sh` and `sfl.sh` export it, so Go downloads that exact toolchain on first use.
- Node, the major version in `.nvmrc`. The gates check it and say what to
  install when it is wrong.

## First run

1. Clone the repository.
2. Run `./Scripts/install_tools.sh`. It installs the Homebrew tools in
   `Scripts/required_tools.txt` and upgrades the ones already there.
   `./FBP.sh` does this too, so this step only lets you see it once.
3. Run `npm ci`. It installs the pinned linters from the lockfile. The gates
   run it for you when `node_modules` is missing or stale.
4. Run `./FBP.sh --no-commit`. It runs every gate and builds the site,
   and commits nothing.

To run only the Go tests, use `go test ./...`.
The Go tests gate runs the same tests.

## Make a change

1. Write the test first and see it fail.
2. Make it pass.
3. Run `./FBP.sh "<message>"`.

FBP means FullBuildAndPush. In order, it does this:

1. It formats the Go files with `gofmt -w`.
2. It runs the PRE gates (`./sfl.sh pre`).
3. It builds the site.
4. It runs the POST gates (`./sfl.sh post`) on the built site.
5. It commits with a sign-off, and pushes only when everything is green.

Good to know:

- **The gates stop at the first red one.** Later gates are printed as
  skipped, and the build and the POST gates do not run. `./FBP.sh --all` runs
  every gate and shows all the reds at once, as CI does.
- **A red run still commits.** The commit is made locally with the subject
  `*** RED ****` and your message in the body, so no work is lost. Nothing is
  pushed. Fix the cause and run `./FBP.sh "<message>"` again.
- **Three reds commit nothing:** the secret scan, the data guard and the
  private-names gate. What they guard must not enter git history. Fix the
  finding named in the output, then run FBP again.
- **`./FBP.sh --no-commit`** runs the gates and the build only.
- **`./FBP.sh --no-push "<message>"`** commits but does not push.
  You cannot combine it with `--no-commit`.
- **The order of the gates** is in `Scripts/gate_report_order.txt`. FBP and CI
  both read it.

## How CI relates

The Quality workflow runs on every push and on every pull request.
It runs the same gate list as FBP, from the same order file.
It does not stop at the first red gate, so a pull request shows all its reds
in one run.
A red row has the same label as in FBP, and `./sfl.sh pre` or `./sfl.sh post`
reproduces it locally.

## Pull requests from forks

Open an issue first for anything larger than a typo.
Then send a pull request against `main`.
Every commit needs a `Signed-off-by` line; `./FBP.sh` adds it
([CONTRIBUTING.md](../CONTRIBUTING.md) explains the Developer Certificate of Origin).

A maintainer must approve the workflow run of a pull request from outside.
A fork gets a read-only token and no secrets.
So the private-names gate is red on a fork's pull request, by design.
The maintainer then runs `./FBP.sh` on the branch.

## Read more

- [CONTRIBUTING.md](../CONTRIBUTING.md): how to propose a change, and the list of gates.
- [Development](development.md): FBP and sfl in full, the tool pins, the data guard.
- [Quality gates](quality-gates.md): what each gate checks.
- [CI](ci.md): what runs on GitHub.
- [Hand-off pipelines](hand-off-pipelines.md): measuring deployments that a workflow hands off outside GitHub.
- [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) and [SECURITY.md](../SECURITY.md).
