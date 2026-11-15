# Dependabot merge policy

forsgren merges its own routine Dependabot updates through a fail-closed
policy, and any repository can run the same policy through a reusable
workflow, `.github/workflows/dependabot_merge_policy.yml` (forsgren#666).
forsgren's own `.github/workflows/dependabot_merge.yml` is one of its
callers. This page is for the maintainer of a repository that wants
Dependabot's safe updates merged without a manual click: what the workflow
decides, the caller to add, the settings file and the security model.

It is not `auto_update.yml`, which merges only the pull request that bumps an
installation's forsgren pin (see
[Updating and releases](updating-and-releases.md)).

## What it decides

When one of your expected workflows completes for a Dependabot pull request,
the policy reads the GitHub API only and calls the pull request ELIGIBLE only
when every condition holds:

- it was opened by `dependabot[bot]`, from a branch `dependabot/<ecosystem>/...`
  of your own repository (a fork's branch, or a head repository that is
  deleted, blocks), and its head is still the commit the run was for;
- every dependency in the `updated-dependencies` block of the head commit's
  message is allowed by an `allow` line of your settings file (a grouped
  pull request only when every member is), and none matches a `deny` line,
  whatever the `allow` lines say (forsgren#668);
- with a `deny github_actions` line in your settings file, no `uses:` line
  the pull request adds or removes in a workflow file names a denied
  reference; when the policy cannot tell (the list of changed files is not
  read whole, a workflow file has no patch in GitHub's answer, or a `uses:`
  line is not in the plain `owner/repository[/path]@ref` form), the pull
  request is not eligible;
- every workflow your settings file expects has a completed, successful run
  for the pull request's current head commit; a missing, skipped, failed,
  queued or stale (older head) run blocks;
- the pull request is open, mergeable and clean, and not behind the default
  branch.

Any API error or answer it cannot read is NOT ELIGIBLE, with the reason. The
decision goes to the run's step summary and to one comment on the pull
request, updated in place. In mode `on`, an ELIGIBLE pull request is
squash-merged at exactly the head commit the policy checked
(`gh pr merge --squash --match-head-commit`), so a pull request that moved in
between is refused.

## The caller

Add one workflow to your repository. In this example the repository is
`acme/shop` and its pull requests run one workflow, `CI`:

```yaml
# .github/workflows/dependabot-merge.yml
name: Dependabot merge

on:
  workflow_run:  # zizmor: ignore[dangerous-triggers]
    workflows: [CI]
    types: [completed]

permissions:
  contents: read
  pull-requests: write
  actions: read

jobs:
  policy:
    uses: yveshanoulle/forsgren/.github/workflows/dependabot_merge_policy.yml@<commit> # vX.Y.Z
    with:
      settings-file: .github/dependabot-merge.conf
      mode: ${{ vars.DEPENDABOT_AUTOMERGE }}
    secrets:
      DEPENDABOT_MERGE_TOKEN: ${{ secrets.DEPENDABOT_MERGE_TOKEN }}
```

- **Pin by commit.** `<commit>` is the full 40-character commit of a forsgren
  release, with the release named in the comment, as for `metrics.yml`. The
  called workflow fetches its scripts at exactly that commit
  (`job.workflow_sha`) and refuses to run from a branch or a tag name.
  Dependabot's `github-actions` updates move the pin like any other action.
- **`workflows:`** lists exactly the workflows of your settings file's
  `workflow` lines, by their `name:`; a completion of any of them starts a
  new decision.
- **`permissions:`** are what the called workflow declares and needs:
  `contents: read` (the settings file, the head commit, the compare),
  `pull-requests: write` (the pull request and its one comment) and
  `actions: read` (the runs of the expected workflows). A called workflow can
  never get more than its caller grants; a caller that grants less stops the
  run before any step.
- **`settings-file`** is the path of your settings file (below); the default
  is `.github/dependabot-merge.conf`. It is always read from your default
  branch, never from the pull request.
- **`mode`** is the kill switch, best kept in a repository variable,
  `DEPENDABOT_AUTOMERGE`: `off` logs only and comments nothing; `dry-run`,
  unset or any other value comments "dry run: would merge" or "dry run: would
  not merge" and merges nothing; `on` comments "eligible: merging" or "not
  eligible: no merge" and merges an eligible pull request. Start with
  `dry-run`.
- **`secrets:`** passes one secret by name, `DEPENDABOT_MERGE_TOKEN`; never
  use `secrets: inherit`. Only the merge step reads it, and only in mode
  `on` for an eligible pull request. It is a fine-grained personal access
  token with Contents and Pull requests read and write on your repository: a
  merge made with it starts your push workflows on the merge commit, which a
  merge with the job token would not. An empty or missing token fails the
  merge step; the workflow never falls back to the job token.
- **zizmor.** zizmor's `dangerous-triggers` audit reports every
  `workflow_run` trigger, so the caller carries one inline ignore of that
  rule on the `workflow_run:` line (on that line, not above it, so a later
  risky trigger is still reported). The called workflow needs no ignore. The
  exception is safe because of what the called workflow does and does not
  do, listed under [Security](#security).

## The settings file

A plain text file in your repository, one rule per line; empty lines and
lines starting with `#` are comments. The policy carries no categories of
its own: what may merge is only what this file allows, and a file with no
`allow` line or no `workflow` line merges nothing.

```text
# .github/dependabot-merge.conf
# allow <ecosystem> <dependency-type or *> <update-type> [<dependency-name>]
allow github_actions * semver-patch
allow github_actions * semver-minor
allow npm_and_yarn direct:development semver-patch
allow npm_and_yarn direct:development semver-minor

# deny <ecosystem> <dependency-name, or a name prefix followed by *>
deny npm_and_yarn left-pad

# workflow <file> <name>
workflow .github/workflows/ci.yml CI
```

- `allow <ecosystem> <dependency-type> <update-type>`: the ecosystem as in
  Dependabot's branch name `dependabot/<ecosystem>/...` (`github_actions`,
  `npm_and_yarn`, `go_modules`, ...); the dependency type and update type as
  in the `updated-dependencies` block of Dependabot's commit message, the
  update type without its `version-update:` prefix (`semver-patch`,
  `semver-minor`, `semver-major`); `*` matches any dependency type. An
  optional fourth field names one dependency, as in the
  `updated-dependencies` block: the rule then allows that dependency only
  (forsgren#674). A line with fewer than three fields or more than four is
  not understood, and nothing merges.
- `deny <ecosystem> <pattern>` (forsgren#668): a dependency that never
  merges through the policy, whatever the `allow` lines say; a grouped pull
  request with any member it matches is not eligible. The pattern is a
  dependency name as in the `updated-dependencies` block, or a name prefix
  followed by `*` (`@acme/*` matches every package of the `@acme` scope);
  `*` anywhere else, or a line without exactly two fields, is not
  understood, and nothing merges. Names are compared ignoring case, in every
  ecosystem, so a `deny` line can only block more. With a `deny
  github_actions` line, the policy also reads the files the pull request
  changes and holds every `uses:` line it adds or removes in a workflow file
  (`.github/workflows/*.yml` or `*.yaml`, or a composite action's
  `action.yml` or `action.yaml`) to the rule, by its `owner/repository` and
  by everything before the `@`; a comment, a local action (`./...`) and a
  `docker://` image name no repository. A changed file list it cannot read
  whole, a workflow file without a patch or a `uses:` line it cannot read
  makes the pull request not eligible.
- `workflow <file> <name>`: a workflow that must have a completed,
  successful run for the pull request's current head commit; both the file
  and the name must match, so a renamed or added workflow cannot stand in
  for it. List every workflow that runs on your pull requests.

forsgren's own file allows GitHub Actions patch and minor updates and npm
development patch and minor updates (forsgren#677: wherever patches merge
on their own, minors of the same ecosystem and dependency type do too), and
keeps Go modules, Docker and every major update a manual merge. Before
forsgren#677 it allowed the minor updates of one npm development
dependency only, `puppeteer-core`, the driver of its browser gates, which
fail when they test nothing (forsgren#674), with a line that names it. Keep
yours as narrow; widen it one line at a time, naming the dependency where
one is enough.

### In a forsgren installation

The pull request that moves the forsgren pin is a `github_actions` update
too, so an `allow github_actions` line also matches it, beside
`auto_update.yml`, which decides that pull request by your `auto_update` and
`auto_update_level` settings. Leave that pull request to `auto_update.yml`
with one `deny` line for the repository your forsgren `uses:` lines name:

```text
# The forsgren pin is auto_update.yml's: auto_update and auto_update_level decide it.
deny github_actions <owner>/<repository>
```

`<owner>/<repository>` is the part before `/.github/workflows/` on the
`uses:` line of your forsgren caller. With it, a forsgren release never
merges through this policy, whatever its update type and your `allow`
lines, and the other Actions updates still merge as the `allow` lines
say.

## Security

- The caller's `workflow_run` workflow runs from your default branch, with
  your repository's Actions secrets, never the pull request's copy of any
  workflow.
- The called job runs only for a run of event `pull_request` on a
  `dependabot/` branch of your own repository, on GitHub's hosted
  `ubuntu-latest`.
- It never checks out your repository, so no pull-request code reaches the
  runner. It fetches exactly three forsgren scripts with a sparse checkout at
  its own pinned commit, without credentials, downloads no artifact and uses
  no cache.
- The settings file comes from your default branch through the API, so a
  pull request cannot widen what may merge.
- The merge token is read in the merge step alone, after the policy said
  ELIGIBLE and with mode `on`; every value from the event or an input
  reaches the shell through `env:`, never as an expression inside `run:`.
- The policy checks the author, the head repository, the `dependabot/`
  branch and the head commit itself, so a run started for something else
  decides nothing.
