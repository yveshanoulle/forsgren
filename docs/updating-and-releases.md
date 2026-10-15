# Updating and releases

## The setup issue (`check-needs`)

Each forsgren release declares what an installation needs: a permission, a
secret, a file or a config key. The declarations are `internal/needs/needs.yml`,
built into the binary, each from the release that introduced it on, so an
entry applies to that release and every later one. Every metrics run checks the
needs of the running version, so this is configuration compliance, not only a
step of moving to a release: a need that is fixed stays fixed, and one that is
removed again later is found again. Its command line, which `metrics.yml` runs
in the step "Check what this forsgren version needs":

```
forsgren check-needs --config <path> --repository <owner/name> [--status <path>] [--token-expiry <path>]
```

`--config` is the installation's `forsgren.config.yml` (the config keys a need
asks for are its top-level keys), `--repository` is the installation's own
repository, where the issue lives, and `--status` writes how the issue's write
went (`ok`, `no-access`, `rate-limited` or `failed`). The job's token is
`GITHUB_TOKEN`. It prints the steps of each missing need and exits 0 once its
flags are valid, whatever the check or the write did; 2 is a usage error. The
workflow passes the status on as `render --needs-check` and
`run-summary --needs-check`.

`--token-expiry` is the file that `collect --token-expiry` wrote (forsgren#177):
the expiry date GitHub named in its answers to `FORSGREN_TOKEN`, and only to
that token. A run knows one of three things:

- **The token expires within 14 days, or has expired.** The setup issue gets
  one more item: the date, and the `gh secret set FORSGREN_TOKEN` command to
  set a new token.
- **The token expires later than that.** The item is gone, and with nothing
  else missing the issue closes. So once a new token is set, the next run
  that sees its date removes the item.
- **The date is unknown**: no file, or one that holds no date (collect failed,
  GitHub refused the token, or its answers named no valid date). An item the
  open issue already carries stays, with its date; no item is ever added. An
  unknown date never adds the item and never removes it.

The warning works only while GitHub still accepts the token and sends a valid
expiry date with its answers: it is not a promise of 14 days' notice. A token
that is revoked or deleted before its date gives no warning; the first sign
is then the failed run.

- **One setup issue per installation, not per version.** It carries the label
  `forsgren-setup`, but its identity is a hidden marker, an HTML comment on the
  first line of its body; the label only narrows the lookup. An issue with
  the label and no marker is never touched, and if you remove the label from
  the managed issue, the next run opens a new one. Its title is "forsgren
  1.7.3 needs more configuration" (the running version) and its body lists the
  steps of each missing need; title and body are presentation, and a run
  rewrites them.
- **What a run does with it.** Something missing and no issue: it opens one.
  Missing and the issue open: it updates it. Missing and the issue closed:
  it reopens and updates it, since the same issue is the installation's. Nothing
  missing and the issue open: it closes it with the comment "All items are in
  place as of forsgren <version>.". Nothing missing and no issue, or a closed
  one: nothing.
- **Without `issues: write`** the write is refused, and the run does not fail:
  the job summary of the run says "the setup issue could not be written" and
  lists what this version needs, and the page footer says "needs more
  configuration: see the job summary of this run". A rate limit or any other
  failure does the same, with its own words. The summary and the footer speak
  only when something is really missing.
- **Nothing missing is `ok`**, even if closing the old issue failed: the failed
  close goes to the job log only.

**Known limits.** A check that cannot see something reports it as missing, so
a false alarm is possible but never a silent pass.

- **Permissions** are read from the installation's
  `.github/workflows/forsgren.yml` (a renamed caller file reads as missing).
  forsgren requires permissions to be declared explicitly on the forsgren job in
  that file. `write-all` and `read-all` are intentionally unsupported, because
  forsgren follows least-privilege security practice. Workflow-level
  (top-of-file) `permissions:` are not supported by the check, even though the
  job inherits them, and with no `permissions:` at all the repository's default
  token permissions cannot be seen, so an explicit declaration is required. A
  successful issue write does not count as proof: it shows the capability, not
  the supported configuration.
- **A secret** is only seen when the workflow passes it in, so only secrets
  that `metrics.yml` passes to forsgren can be declared.
- **A file** is checked in the run's checkout, so `check-needs` runs at the
  checkout root; the `metrics.yml` step pins it.

## Auto-update (`check-update`)

An installation can let forsgren's own updates merge themselves
([#58](https://github.com/yveshanoulle/forsgren/issues/58)). It is off until
the config switches it on, and a new install's starter does, at `major` (see
[Configuration](configuration.md#configuration)). The chain, for each forsgren release:

1. Dependabot opens one grouped pull request that moves the pins of both
   caller files, `.github/workflows/forsgren.yml` (which calls `metrics.yml`)
   and `.github/workflows/forsgren-update.yml` (which calls `auto_update.yml`),
   to the new release.
2. On that pull request the caller `forsgren-update.yml` runs forsgren's
   reusable `auto_update.yml`, from the new pin the pull request carries. The
   workflow installs forsgren from its own commit, as `metrics.yml` does, and
   checks out the caller's repository at the pull request's base commit, so a
   pull request never switches auto-update on for itself.
3. `forsgren check-update` decides (below).
4. When it says merge, the workflow squash-merges the pull request, deletes
   its branch and starts `forsgren.yml` on the default branch, so the new
   release publishes the page now and not at the next daily run.
5. When it says install (exit 3, below), the workflow installs the newest
   release within the level itself and starts `forsgren.yml`; the pull request
   stays open ([#62](https://github.com/yveshanoulle/forsgren/issues/62)).

**The two keys** of `forsgren.config.yml` (see [Configuration](configuration.md#configuration)):

- **`auto_update`** is `true` or `false`, and only those literals (a quoted
  value, `yes` or a number is not accepted: it is off, the default, and
  `check-update` and `check-config` warn about it, see
  [A setting that is not accepted](configuration.md#a-setting-that-is-not-accepted)).
  Absent, or without a value, it is off, so an existing config keeps its
  behaviour until it opts in.
- **`auto_update_level`** is `patch`, `minor` or `major`: the largest step
  an update may take and still merge itself. It is optional and
  defaults to `major`: with `auto_update: true` and no level, the level is
  `major`, and any value other than the three is not accepted: the level is
  then `major`, the default, and the warning names the three. At `patch`,
  v0.2.0 to v0.2.1 merges and v0.3.0 does not; at `minor`, v0.3.0 merges (and
  every patch) and v1.0.0 does not; at `major`, v1.0.0 merges as well. A
  level only limits what merges: a pull request beyond it is left for you,
  and a release within the level is installed meanwhile (see below).

  A new installation's starter writes `major`; an existing file keeps the
  level it has, as `init-config` never rewrites it. `major` permits major,
  minor and patch updates; it does not mean a major release is safe. Patch
  updates are intended for fixes, and minor updates can introduce new
  behaviour. A release is only cut when forsgren's Quality checks are green,
  Dependabot proposes it only after the update wait, and the merge goes
  through only when the pull request changes nothing but the forsgren pin to
  a published release (the guard, below). Nothing checks a release against
  this installation's own data. The starter wrote `patch` before 1.0.0, so an
  installation made then may still be at `patch` or `minor`; for it, v0.8.7
  to v1.0.0 is a major update that waits for you.

**What the guard checks.** The pull request merges only when every one of
these holds, and otherwise it is left for a human with one reason line:

- the pull request's author is `dependabot[bot]`;
- the config at the pull request's base commit has `auto_update: true`;
- the diff changes nothing but pin lines: every changed file is one of the
  two callers, each changes one `uses: yveshanoulle/forsgren/.github/workflows/...@<sha> # vX.Y.Z`
  line to another, and a caller pins the workflow it calls (`metrics.yml` in
  `forsgren.yml`, `auto_update.yml` in `forsgren-update.yml`);
- the pins move from the same version to the same version and commit in every
  file, and when the repository has both caller files at the base commit, the
  pull request moves both (a pull request that moves only one is left for you,
  [#61](https://github.com/yveshanoulle/forsgren/issues/61));
- the new version is a release version (`vX.Y.Z`), an upgrade of the old one,
  and within `auto_update_level`;
- forsgren has a published release for the new version, not a draft and not a
  prerelease, and its tag points at exactly the pinned commit.

**`check-update`** is the command the workflow runs:

```
forsgren check-update --config forsgren.config.yml --repo <owner/name> --pull <number>
```

`--config` is the installation's config file (the caller files are looked
up next to it, which in the workflow is the checkout of the base commit),
`--repo` the data repository and `--pull` Dependabot's pull request in it
(1 or more). It reads the pull request, its files and forsgren's release
with `GITHUB_TOKEN`, which needs `pull-requests: read`, and prints one line,
or two for exit 3:

- exit 0: `merge <old> to <new>`, for example `merge v0.2.0 to v0.2.1`;
- exit 1: `left for a human: <reason>`, for example `left for a human:
  v0.2.1 to v0.3.0 is a minor update; auto_update_level is patch`. With
  `auto_update` off it prints `left for a human: auto_update is off` and asks
  GitHub for nothing;
- exit 3: `install <old> to <new> at <sha>`, then the exit 1 line, for
  example `install v0.2.1 to v0.2.2 at 0123456789abcdef0123456789abcdef01234567`
  and `left for a human: v0.2.1 to v0.3.0 is a minor update;
  auto_update_level is patch`. It is given only when every check passed but
  the level (the pull request goes further than `auto_update_level` allows)
  and forsgren has a release that is newer than the installed version, within
  the level, published (not a draft, not a prerelease) and a release version;
  `<new>` is the newest such release and `<sha>` the commit its tag points at.
  With no such release it is exit 1, as before; any other reason to leave the
  pull request never looks at the releases;
- exit 2: a usage, config or network error, with the message on stderr and
  nothing on stdout (a flag missing or invalid, a config that is invalid (a
  setting that is not accepted only warns and uses its default), an
  answer of GitHub that is an error, or a pull request with more files than
  forsgren reads).

**A release within the level (`install-update`).** Dependabot proposes only
the newest release, so with `auto_update_level: patch` and v0.2.1 installed,
v0.3.0 is left for you while the patch release v0.2.2 would have been safe.
On exit 3 the workflow installs v0.2.2 itself, with `forsgren install-update`:

```
forsgren install-update --repo <owner/name> --branch <branch> --version <vX.Y.Z> --sha <40-hex>
```

`--repo` is the data repository, `--branch` its default branch, `--version`
the release to install and `--sha` the commit its tag points at (both taken
from check-update's first line, which the workflow checks against a release
version and 40 lower-case hex digits first). It reads each caller file as it
is at the head of the branch, through the API, because the branch moves daily
with data commits and the pull request's base commit may be stale; moves the
pin of each caller file that exists there to the release; and writes all of
them in one commit, `forsgren: install <version> within auto_update_level
(forsgren#62)`, that follows the head it read the files at. The branch is
moved without force, so a branch that moved meanwhile, or is protected
against the job's token, fails the command with the branch unchanged. It
reads `GITHUB_TOKEN`, which needs `contents: write`, and prints `installed
<version> on <branch> as <commit>`:

- exit 0: installed;
- exit 2: a usage error (a flag missing or invalid, named on stderr), an
  answer of GitHub that is an error, a caller file without exactly one pin
  line of its workflow, or no caller file at the head of the branch. A caller
  file that is not there is skipped.

Then the workflow starts `forsgren.yml`, as it does after a merge (a commit
made with the job's token triggers no other workflow), and the bigger pull
request stays open: Dependabot refreshes it, and merging it is yours. The
job summary holds both lines of check-update's output. A failing
`install-update` fails the run and starts nothing.

**What you see.** When the pull request is left for you, the workflow puts
the reason in the run's job summary, the run stays green and nothing is
merged: review the pull request and merge it yourself if it is fine. When
check-update fails (exit 2) or the merge fails, the run fails, and a failed
merge starts nothing. When a release within the level is installed instead,
the summary says so and why the pull request stays open, and the run is green.

**The caller grants three permissions**, all `write`, because a called
workflow can only keep or narrow what its caller's job grants:
`contents: write` to merge or to write the install commit,
`pull-requests: write` to merge the pull request and `actions: write` to start
`forsgren.yml`. The last is needed because a
merge made with the job's token triggers no other workflow, so without the
explicit start the merged update would wait for the next daily run. The
workflow declares no permissions block of its own.

**The template's Dependabot setup.** The template's `.github/dependabot.yml`
groups the pins of both caller files into one pull request, checks every day
at 04:00 UTC, weekends included (`interval: cron`, `cronjob: "0 4 * * *"`;
`interval: daily` runs Monday to Friday only), and waits 3 days after a
release before it proposes it (a cooldown).

**To switch auto-update off**, set `auto_update: false` in
`forsgren.config.yml` (or remove the key). Dependabot still opens its pull
request, `forsgren-update.yml` runs and leaves it for you with `auto_update is
off`, and merging it is the update, as before (see [Configuration](configuration.md#configuration)).

## Installing and updating

**To install forsgren with an AI coding agent,** point the agent at
[agent-installer.md](../agent-installer.md): it asks what only you can decide
and creates your data repository from the template step by step
(forsgren#142).

**To upgrade an existing installation with an AI coding agent,** point the
agent at [agent-upgrade.md](../agent-upgrade.md): it reads your current report,
the release notes between your pin and the latest release, and asks only what
is yours to decide, then moves the pins and checks the run. Use it when an
installation is behind, when automatic updates are off, or when a release asks
you for a choice, as the next paragraph does (forsgren#166).

**To remove an installation with an AI coding agent,** point the agent at
[agent-delete.md](../agent-delete.md): from the address of your report it
finds the data repository, shows you what will go (the repository and all its
history in `data/`, which cannot be recovered after a delete), offers to
archive it instead or to download it first, and changes nothing before your
go. It removes the custom domain and the page first, then deletes or archives
the repository, and hands you what only you can do: the DNS record, the
verification record and, on route B, the fine-grained token (forsgren#174).

**Upgrading to 1.3.0 hides the Daily page** (forsgren#159). From 1.3.0 an
installation that does not set days_page loses its Daily page until it sets
days_page: true. The Issues page stays (issues_page: true is the default; the
starter writes issues_page: true and days_page: false). With auto-update on,
the merged update removes `days.html` from the site at the next run. To keep
the Daily page, add `days_page: true` to `forsgren.config.yml` before or
after the update, and the next run generates it again. An agent following
[agent-upgrade.md](../agent-upgrade.md) asks you about it before it moves the
pins.

**Upgrading to 1.6.0** (forsgren#178, #183). A new optional key,
`dora_days` (30, 90 or 180), sets the window of the five DORA metrics; it
defaults to 30, so nothing changes until you set it, and a longer window needs
`history_days` of at least as many days (see
[Configuration](configuration.md#configuration)). `history_days` now accepts
30 to 1825 (it was 1 to 1825): raise a lower value to at least 30 before the
update, or the default 365 is used. A setting forsgren does not accept no
longer stops the run: its default is used, the settings page says so in the
key's row, the log warns with a `config: warning:` line and `check-config`
passes with `settings not accepted: N`. The one-time catch-up of withdrawn
failure issues re-reads the `dora_days` window, but an installation that
already ran it and later widens `dora_days` gets no second catch-up (see
[Collecting deployments](data-files.md#collecting-deployments-collect));
this is rare. An agent following [agent-upgrade.md](../agent-upgrade.md) asks
you only whether you want a longer window, and checks `history_days`.

**Upgrading to 1.7.0** (forsgren#55). A new optional key,
`numbers_scoring_page` (`true` or `false`), adds the Numbers and scoring page
at `/numbers-scoring/`, each metric's number and its score in one cell, and
its menu entry after Scoring. It defaults to `false`, so nothing changes
until you set `numbers_scoring_page: true` (see
[Configuration](configuration.md#configuration)); the settings page lists
the key as its tenth row. An agent following
[agent-upgrade.md](../agent-upgrade.md) asks you nothing about it.

**An installation's page names a newer release** (forsgren#40). The page
footer says "0.0.10 is available" when forsgren has a newer release than the
one that built the page, and, when your caller grants `pull-requests: read`
(see [Running forsgren](configuration.md#running-forsgren)), "0.0.10 is waiting in pull request #N (merge it to
update)" when Dependabot's pull request for it is open in your repository.
Updating is merging that pull request; the template's calling workflow
carries the permission line.

**Cutting a release** (forsgren#148, decision #170). A release bump of
`version` in `cmd/forsgren/main.go` must update the version strings in
`README.md` and `docs/` in the same change, or the docs version pin fails; a
new MAJOR also needs a new proof run of each agent file, recorded in its
Tested-with line, or the Tested-with major test fails.
