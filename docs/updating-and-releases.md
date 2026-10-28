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
                     [--pulls-denied <path>] [--pushes-denied <path>]
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
  <version> needs more configuration" (the running version) and its body lists the
  steps of each missing need and each refused setting; title and body are presentation, and a run
  rewrites them.
- **Two headings: missing requirements and refused settings** (forsgren#538).
  The body has a heading "Missing requirements" for what the running version
  needs and is not in place, and a heading "Refused settings" for every
  configuration setting forsgren refused. A list that is empty has no heading.
  Each refused setting is its own item and names the key, the value as written,
  why it is not accepted and the default forsgren uses instead, the facts the
  settings page shows (the same list as `check-config`'s warnings):

  ```
  ## Refused settings

  - [ ] `view`: `weekly` is not accepted: use standard, numbers or scoring. Using the default `standard`.
  ```

  The value is shown in a code span, one line, an empty one as `(empty)`. The
  issue is rewritten on every run, so an item is gone on the next run after
  the configuration is corrected. A refused setting never makes a metrics run
  fail: forsgren runs with the default, and the setup issue is how a
  maintainer who never opens the settings page sees it. It needs no new
  permission (the issue already needs `issues: write`) and opens no second
  issue. A config file that cannot be loaded at all is the metrics run's own
  failure; `check-needs` notes it on stderr and lists no refused setting.
- **What a run does with it.** Something missing or a setting refused, and no
  issue: it opens one.
  Missing or refused and the issue open: it updates it. Missing or refused and
  the issue closed: it reopens and updates it, since the same issue is the
  installation's. Nothing missing, no setting refused and the issue open: it
  closes it with the comment "All items are in
  place as of forsgren <version>.". Nothing to report and no issue, or a closed
  one: nothing.
- **A development build checks nothing** (forsgren#340). A build that names no
  release (the version is `dev`: no `-ldflags` value and no release tag in its
  build information) does not know what it needs, and an unknown version is not
  an older release. `check-needs` says so on stderr, records the status
  `skipped`, makes no request and so opens, updates, reopens or closes no setup
  issue; the run summary's Setup line says "not checked, a development build
  does not know what it needs", and its Update line "unknown (a development
  build)". An installation runs a release, so it is never affected.
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
- **A token's own permissions** cannot be seen, and here the check does not
  report them as missing: it reads the calling workflow, so it names a
  forsgren job without `pull-requests: read`, which is the permission when
  `FORSGREN_TOKEN` is the job's own token (route A of
  [agent-installer.md](../agent-installer.md)), but not a fine-grained
  `FORSGREN_TOKEN` without Pull requests (read) (route B). Such a token gives
  no setup item in advance. The setup issue
  never claims the pull request read works because the workflow line is there
  (decision #314). What it can show is a refusal `collect` saw, below.

**A refused pull request read** (forsgren#321). `--pulls-denied` is the file
`collect` noted the refusals in, `data/pulls_denied.csv` unless the flag names
another (see [Data files](data-files.md#collecting-deployments-collect)). For
each repository it lists, the setup issue gets one item, about a refusal that
was seen and no claim about what works:

- **The job's token (`GITHUB_TOKEN`) was refused**: "forsgren was refused the
  pull request read of acme/app with GITHUB_TOKEN, the job's token. Add
  `pull-requests: read` to the `permissions:` of the forsgren job in
  .github/workflows/forsgren.yml."
- **Another token was refused** (`FORSGREN_TOKEN`, a fine-grained token):
  "forsgren was refused the pull request read of acme/app with FORSGREN_TOKEN.
  Give FORSGREN_TOKEN the repository permission Pull requests: Read for
  acme/app."
- **A line of an older forsgren** (the file's v1, no token name): "forsgren was
  refused the pull request read of acme/app; the file that notes it does not
  name the token." and both fixes, each with the token it is for.

Each item ends with where it comes from and when it goes: it goes away on the
next run after a read of the repository worked, because `collect` then removes
its line. The item names the token by its name only, never its value. A file
that cannot be read or is in no known format fails the check (forsgren#395):
the note on stderr names the file, the status is `failed` and the setup issue is left as it is,
neither written nor closed, because the refusal may still stand; a missing
file notes no refusal.

**A refused push read** (forsgren#414). `--pushes-denied` is the file
`collect` noted the refused push reads in, `data/pushes_denied.csv` unless the
flag names another. It works like the pull request one: one item for each
repository it lists, about a refusal that was seen, with the same file rules.
The two item texts:

- **The job's token (`GITHUB_TOKEN`) was refused**: "forsgren was refused the
  push read of acme/app with GITHUB_TOKEN, the job's token. Add
  `contents: read` to the `permissions:` of the forsgren job in
  .github/workflows/forsgren.yml."
- **Another token was refused** (`FORSGREN_TOKEN`, a fine-grained token):
  "forsgren was refused the push read of acme/app with FORSGREN_TOKEN. Give
  FORSGREN_TOKEN the repository permission Contents: Read for acme/app."

A line of an older forsgren (the file's v1, no token name) gets both fixes, as
the pull request item does. Each item ends with where it comes from and when it
goes: it goes away on the next run after a read of the pushes of the repository
worked.

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
starter then wrote issues_page: true and days_page: false, and since
forsgren#285 it writes issues_page: false). With auto-update on,
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

**Upgrading to 1.8.0** (forsgren#68, #194). A History page appears by
default: `history.html`, the last entry of the menu, "History", with the five
metrics and Overall Performance per calendar half-year and for the last 6
months, each cell its number and score, and a small Trend chart per row (see
[The History page](pages-and-views.md#the-history-page)). A new optional
key, `history_page` (`true` or `false`), switches it; it defaults to `true`,
so to turn the page off set `history_page: false` (see
[Configuration](configuration.md#configuration)); the settings page lists the
key as its eleventh row. The page fills over several daily runs: it shows a
period only once the history is read back to the period's start, and
`history_days` decides how far back it reads (365 by default, so the last 6
months and about one half-year; up to 1825, five years), each run reading one
more `history_chunk_days` chunk back until it gets there. Until then the page
says in one line that the periods fill as the history is collected. The
run's job summary gains a Run line, the moment of the run in UTC; its Token
line now tells apart the run's own token (`GITHUB_TOKEN`, renewed every run),
a token with no expiry date, an expiry date forsgren cannot read and a
`collect` that could not ask GitHub; and its Update line names Dependabot's
cooldown, "waiting for the 3-day cooldown until 2026-10-18", while the
cooldown in your `.github/dependabot.yml` runs (see
[Running forsgren](configuration.md#running-forsgren)). No new permission or
secret is needed. An agent following [agent-upgrade.md](../agent-upgrade.md)
reads the History page in the release notes as a page that appears, and asks
you whether to keep it. 1.8.1 turned the default to `false`; see below.

**Upgrading to 1.8.1** (forsgren#199, #79). The History page is off by
default: `history_page` now defaults to `false`, so an installation that
leaves the key out loses the History page and its menu entry with this
update, and the page is removed from the site. To keep it, set
`history_page: true` (see [Configuration](configuration.md#configuration)).
It comes back on by default once a later release makes the page easier to
read (forsgren#198). The starter that `init-config` writes includes
`history_page: false`, and the settings page's Default column for the key
shows `false`. The legend now shows each level's score, the score the
scoring view gives that level; change fail rate and deployment rework rate
are scored per whole percent, so each of their levels shows the range of
its scores, for example `20%: 10% to below 30%, score 9 to 7.1`. No new
permission, secret or config key is needed.

**Upgrading to 1.8.2** (forsgren#200, #198). The page keys `issues_page`,
`days_page`, `numbers_scoring_page` and `history_page` take one new value,
`unlisted`, besides `true` and `false`: the page is generated but has no menu
entry, and it asks search engines not to index it (noindex). Unlisted is
discoverable, not private: noindex asks compliant search engines not to index
the page; it does not enforce access control. The defaults changed: without
the keys, the History page and the Numbers and scoring page are now
generated and unlisted, reachable at `history.html` and `numbers-scoring/`.
Set `history_page: false` or `numbers_scoring_page: false` to keep a page
out, or `true` to list it in the menu (see
[Configuration](configuration.md#configuration)). `issues_page` still
defaults to `true` and `days_page` to `false`. A value the keys do not
accept now says `use true, unlisted or false`, and the settings page lists
`true, unlisted, false` and the new defaults. The starter that `init-config`
writes includes `numbers_scoring_page: unlisted` and
`history_page: unlisted`. The History page is marked beta, "History (beta)" then (and "History (BETA)" since forsgren#271),
and explains itself: a line under its heading says how to read it; while the
last 6 months are its only period, a second line says why, with the date of
the first deployment and the day the first half-year appears; and with one
period there is no Trend column (see
[The History page](pages-and-views.md#the-history-page)). No new permission
or secret is needed.

**Upgrading to 1.8.3** (forsgren#42, #112). The waiting update is found by
what it changes: forsgren reads the files of Dependabot's open pull requests
and takes the highest-numbered one that moves the `metrics.yml` pin to the
newer release, so "is waiting in pull request #N (merge it to update)" now
also shows when Dependabot groups the update or names its branch differently
(see [Running forsgren](configuration.md#running-forsgren)). When
`check-update` cannot read a pull request or its files for lack of
`pull-requests: read`, its 403 message now names that permission. The legend
explains the issue columns: New is the issues created, Completed, Not
planned and Duplicate the issues closed with that reason, and Other the ones
closed with no reason or one forsgren does not know; and it names two
limits: a reopen is dated when the collection sees it, and a repository with
more issues than the one full read takes has an incomplete older history. No
new permission, secret or config key is needed.

**Upgrading to 1.9.0** (forsgren#110, #195, #202, #203). A minor release.
Two changes show in your own repository; read them before you update.
**The README of your installation is now forsgren's file** (forsgren#110):
each daily run writes `README.md` for the forsgren version it runs and
commits it only when it changed, as `github-actions[bot]`, in a commit that
holds that one file, "forsgren: update README.md". **A README you edited by
hand is replaced on the first run after this update**, so keep your own
notes elsewhere before you update. The README says so in its first lines,
and the run's job summary gains a README line: "created from forsgren
1.9.0's", "replaced with forsgren 1.9.0's" or "unchanged". A README that cannot be
pushed (a tag, a branch that moved during the run, a push the remote refuses)
does not stop the day: the run prints the reason, goes on, and fails at its
end, and the job summary says "README: not pushed: see the README step" (see
[Running forsgren](configuration.md#running-forsgren)).
**No cooldown key now means Dependabot's 3 days** (forsgren#195): when your
`.github/dependabot.yml` updates `github-actions` with no `cooldown`
`default-days`, the Update line of the job summary counts Dependabot's
documented default of 3 days, "waiting for the 3-day cooldown until
2026-10-18", where it said "no Dependabot pull request yet"; set
`default-days: 0` for no cooldown. The Issues and Daily pages gain two
columns after Completed (forsgren#202): Lead time, the median time from an
issue's creation to its Completed close over the issues completed in the
row's period, and Bugs lead time, the same over the issues labelled `bug`,
which shows "— (incomplete)" on the same rule as Open bugs; the legend
explains both (see [Pages and views](pages-and-views.md#the-page)). When the
list of your open pull requests is too long to read in full and Dependabot's
pull request is not among those read, the job summary and the footer say
"0.3.9 is available; unknown (pull request list truncated)" instead of a plain
"is available" (forsgren#203). No new permission, secret or config key is
needed: `contents: write`, which the run already has, pushes the README.

**Upgrading to 1.9.2** (forsgren#208, #206, #207). A patch release. Every
page of your site now carries a meta description, the text a search result
shows under the page's title: one fixed sentence per page, ending "generated
by Forsgren", for example "The DORA numbers per project, without scores
generated by Forsgren" on the numbers view; the root takes the sentence of
the view it shows (see [Pages and views](pages-and-views.md#the-page)). The
sentences name no project, repository, number, date or title. The HTML gates
that check forsgren's own pages are stricter (30 HTMLHint rules, among them
a required meta charset and meta description; see
[Quality gates](quality-gates.md)); nothing changes in what a page shows. No
new permission, secret or config key is needed.

**Upgrading to 1.15.0** (forsgren#254, #255). A minor release. `collect` also
reads the merged pull requests of every measured repository, with each one's
first commit time, into a new data file, `data/pulls.csv`, with its read mark
in `data/pulls_read.csv` (see [History](data-files.md#history)); the first
run reads back to `history_days`. They are the data for the PR Lead Time
on the TBD page (forsgren#256). The forsgren job of your calling workflow now
needs `pull-requests: read` (the template's calling workflow already carries
it), and a fine-grained `FORSGREN_TOKEN` needs Pull requests (read) on the
measured repositories. **Without them nothing stops or fails:** every other
number is still collected and published, `collect` names the missing
permission on stderr, and the setup issue lists the `pull-requests: read`
line (it reads the calling workflow, so it cannot see the token's own
permissions and never claims the pull request read works; decision #314).
No config key or secret is new. An agent following
[agent-upgrade.md](../agent-upgrade.md) reads this as a new permission in
`.github/workflows/forsgren.yml`, brings over the template's line when yours
lacks it, and asks you about the token's permission, which only you can
change.

The same release brings forsgren#254: `data/commits.csv` becomes the commits
format v3, with each commit's parents and committer date (see
[History](data-files.md#history)). A v1 or v2 file is still read, and the
next `collect` rewrites it once as v3; the commits stored before v3 keep
their parents and committer date empty until the backfill of 1.18.0 (below)
fills them (decision 293 of forsgren#254 kept them empty; forsgren#385
changed that). The TBD page's Mainline
Interval now follows each deployment's first-parent chain, each commit placed
at its committer date. A deployment stored before v3 with two commits or more
keeps the old approximation, every commit at its author date, and the cell
names those commits, ` · 3 commits timed by author date` (decision 294 of
forsgren#254; see [The TBD page](pages-and-views.md#the-tbd-page)). Nothing
new is needed for it.

**Upgrading to 1.17.0, which adds `same_developer`** (forsgren#361, decision
#360). A new optional key, `same_developer`,
joins GitHub logins into one developer in the TBD page's Developers count, for
an assistant account that works for someone or a person with two accounts. It
is a list of lists, such as `same_developer: [[maintainer, assistant-account]]`
(see [Configuration](configuration.md)). Nothing changes until you add it: left
out, the key is `[]` and every count stays as it was. An installation can add
the key after updating, and the settings page shows it as a thirteenth row. A
value that is not accepted falls back to `[]` with a warning, like every other
setting. No permission, secret or data file is new, and the stored commits
keep each login. An agent following [agent-upgrade.md](../agent-upgrade.md)
needs to ask you nothing about it.

**Upgrading to 1.18.0, which backfills the legacy commits** (forsgren#385). A
minor release. The first `collect` after the update asks GitHub once for the
author, the parents and the committer date of the commits stored before the
commits format v3 and fills them in `data/commits.csv` (see
[History](data-files.md#history)), so those commits count as developers on the
TBD page and the Mainline Interval stops using the author date for them. It
makes one comparison per stored deployment that has such commits, inside the
daily run, and notes each repository it finished in the new
`data/commits_backfilled.csv`. It stays inside the request budget, so with
much history it can take more than one day: the run's summary says `legacy
commits cut short` for a repository it has not finished, and the next run
continues. Nothing is cut or failed by it, and nothing needs to be
configured. A commit GitHub links to no account keeps an empty author. An
agent following [agent-upgrade.md](../agent-upgrade.md) needs to ask you
nothing about it.

**Upgrading to 1.21.0, which puts the TBD page in the menu** (forsgren#409). A
minor release. The TBD page leaves beta: its title, its heading and the
legend's section heading no longer say BETA, and `tbd_page` is now `true` by
default instead of `unlisted`. An installation whose `forsgren.config.yml` has
no `tbd_page` key gets the TBD page in its menu, after History, with this
release, and the page no longer asks search engines to skip it. To keep it out
of the menu as before, set `tbd_page: unlisted`; `tbd_page: false` does not
generate it. A config that already sets the key is not changed. Nothing new is
needed: no permission, secret or file. An agent following
[agent-upgrade.md](../agent-upgrade.md) needs to ask you nothing about it.

**Upgrading to 1.22.0, which shows the median on the TBD page** (forsgren#423,
#444, #394, #414). Without the key `tbd_figures` in `forsgren.config.yml`, the
TBD table shows the median of each measure only after this release: one
column for each measure, where it showed the mean, the median and the 90th
percentile before. To keep all three figures, add `tbd_figures: all` (see
[Configuration](configuration.md#configuration)). The settings page shows the
key as a new row. Also with this release:

- The headers no longer say (median) or (duration), and the Mainline Interval
  and PR Lead Time lose their deviation, count and share columns. What was in
  their cells is now a numbered note below the table, open by default.
- A project with no deployed commit, no final deployment, no push and no
  merged pull request in the window shows one sentence across its row,
  `currently no data for this project in the last 30 days`, with 30 the
  `dora_days` in force.
- A push read that GitHub refused now gives the setup issue an item, which
  names the refused token and its fix (see
  [The setup issue](#the-setup-issue-check-needs)). It appears on the first run
  after the update that sees a refusal, and goes away when a run reads the
  pushes again. `data/pushes_denied.csv` is written as format v2; a file in
  format v1 is read and written again.

No new permission, secret or config key is required. An agent following
[agent-upgrade.md](../agent-upgrade.md) needs to ask you nothing about it.

**Upgrading to 1.23.0, which gives the TBD page a row per label or service**
(forsgren#422, #452, #395). A project whose repositories have a `label` or
`services` in `forsgren.config.yml` (see
[Configuration](configuration.md#configuration)) gets rows under its total row
on the TBD page after this release, one for each label or service, sorted by
label. A project without labels or services shows its total row alone, as
before. Also with this release:

- A service row shows its own Time to deploy per commit, Deployments, Commits
  per deployment and Developers. Where a figure is per repository, the
  Mainline Interval, the pushes and the pull requests, it says
  `Per repository`. With no final deployment and no deployed
  commit in the window it says `currently no data for this service in the
  last 30 days`. The Notes below the table name such a row `Project: label`.
- With `tbd_figures: all`, the headers of the columns of time to main, time to
  deploy, commits per push and commits per deployment read, for a screen
  reader, such as "the mean of time to main".
- `forsgren check-needs` fails, with a note on stderr that names the file, when
  `data/pulls_denied.csv` or `data/pushes_denied.csv` cannot be read or is in
  no known format. The setup issue is then left as it is, where before the
  items of the refused reads were closed (see
  [The setup issue](#the-setup-issue-check-needs)). Fix the file, or delete
  it: a missing file notes no refusal, and a later refused read notes it again.

No new permission, secret or config key is required. An agent following
[agent-upgrade.md](../agent-upgrade.md) needs to ask you nothing about it.

**Upgrading to 1.25.0, which lets the config turn TBD columns and sub-rows
off** (forsgren#482, #474; with the patch releases after 1.24.2: forsgren#470,
#477, #478, #485, #479). Four new optional keys, all `true` when left out, so
an installation that does not write them sees the page as before (see
[Configuration](configuration.md#configuration)): `tbd_time_to_main`,
`tbd_pr_lead_time` and `tbd_bot_pr_lead_time` each hide one TBD column group
when set to `false`, and `sub_rows: false` shows each project's total row
alone on every table. The settings page lists the four. Also in this series:

- The first `collect` after the update fills, once per repository, the
  commit lists of the merged pull requests and the branch commits of the
  merge pushes stored before 1.24.0 (one request each; see
  [Data files](data-files.md#collecting-deployments-collect)), noted in
  `data/pull_commits_filled.csv` and `data/push_commits_filled.csv`. A run the
  request budget cuts short continues on the next one. Once a repository is
  filled, note 7 on the TBD page no longer names its project.
- The TBD shares show two significant digits (`19%`, `1.3%`, `0.65%`), and
  PR Lead Time now comes before Time to deploy per commit.
- A Bot PR Lead Time column after PR Lead Time counts the pull requests a bot
  opened; note 5 (`Bot pull requests not counted`) is retired.

No new permission or secret is required. The four keys are new config keys,
optional, whose defaults keep the page as it was: an agent following
[agent-upgrade.md](../agent-upgrade.md) asks whether to turn any of them off,
with `true` (as today) as the default answer.

**Upgrading to 1.26.0, which counts a service's own commits** (forsgren#496,
decision #497). For an installation with services (`services:` in
`forsgren.config.yml`, see [Configuration](configuration.md#configuration))
the service rows change after this release. A service row counted every
commit of the repository between two of its deployments, whatever folder the
commit changed, so two services of one repository showed nearly the same
figures. Now a service names its folders with `paths`, and counts only the
commits that touch them:

```yaml
services:
  deploy-api: {label: API, paths: [api/, shared/]}
  deploy-admin: {label: ADMIN, paths: [admin/, shared/]}
```

- A service without `paths` says `Per repository` for the Time to deploy per
  commit and the Commits per deployment until you add `paths`, written as
  `deploy-api: {label: API, paths: [api/, shared/]}`. Its
  Deployments stay its own, and the short form `deploy-ios: IOS` stays valid.
  Nothing else breaks.
- A folder ends in `/`, a file matches exactly; write `shared/` in each
  service that uses it; files in the root of the repository (`.github/`,
  `go.mod`, `Scripts/`, `docs/`) count for no service. The total row and the
  label rows still count every commit. To find the folders, read the folders
  of the repository on GitHub and the `paths:` filter of the service's deploy
  workflow.
- The first `collect` after you add `paths` reads the files each stored commit
  changed, one request per commit (see
  [Data files](data-files.md#commit-files-forsgren496)), in
  `data/commit_files.csv` and `data/commit_files_filled.csv`. It reads them
  last, so fresh data is never held back, and a run the request budget cuts
  short continues on the next one. Until a service's commits are read, they are
  left out of its figures and the row carries note 8, `Files still being read`.
  A repository without a service or a deployment rule that has `paths` costs
  no request. The read
  needs `Contents: Read` on a fine-grained `FORSGREN_TOKEN`, as the push read
  does; without it `collect` says so on stderr and fails nothing.

No new permission or secret is required for an installation that adds no
`paths`; `paths` is a new optional key. An agent following
[agent-upgrade.md](../agent-upgrade.md) asks, for each installation with
services, whether to add the folders now.

The same release brings `deployments:` (forsgren#498, decision #499): a
repository can list several deployment rules with `deployments:`, a map of
rule to label or to `{label: ..., paths: [...]}`, and each rule becomes its own
service row, as forsgren's releases and its website could be. `deployment:`
stays valid and nothing changes for an installation that does not use
`deployments:`; both keys on one repository are refused. See
[Configuration](configuration.md#configuration). No new permission or secret
is required. The upgrader now proposes the folders of a service and the
deployment rules of a repository from what GitHub shows (forsgren#503): an
agent following [agent-upgrade.md](../agent-upgrade.md) reads the deploy
workflows read-only, shows what it found and the lines it would write, and
writes them only with your yes; [agent-installer.md](../agent-installer.md)
does the same for a new installation.

**Upgrading to 1.29.0, which adds the Week page** (forsgren#531, decision #533). A
minor release. A new page, `week.html`, shows the commits and deployments of
each weekday of the `dora_days` window, as a total and as shares of it.
The new key `week_page` is optional and `true` when left out, so an installation without `week_page` in its config gets the Week page in its menu, after TBD, with
this release. To keep it out of the menu, set `week_page: false`: the page is
still written and reachable by its address. Nothing new is needed: no
permission, secret or file. An agent following
[agent-upgrade.md](../agent-upgrade.md) needs to ask you nothing about it.

**Upgrading to 1.29.3, which leaves the Week page's Commits columns out by
default** (forsgren#548, decision #549). A patch release. The Week page shows
Deployments, Failed and Fail rate under Total and under each weekday; the
Commits columns are gone unless the config says `week_commits: true`. The new
key `week_commits` is optional and `false` when left out, so an installation
that wants the Commits columns back sets `week_commits: true`. The commits are
still collected and computed. Nothing new is needed: no permission, secret or
file. An agent following [agent-upgrade.md](../agent-upgrade.md) needs to ask
you nothing about it.

**An installation's page names a newer release** (forsgren#40). The page
footer says "0.0.10 is available" when forsgren has a newer release than the
one that built the page, and, when your caller grants `pull-requests: read`
(see [Running forsgren](configuration.md#running-forsgren)), "0.0.10 is waiting in pull request #N (merge it to
update)" when Dependabot's pull request for it is open in your repository:
the open pull request by Dependabot whose files move the `metrics.yml` pin
to that release, whatever its branch is called (forsgren#42).
Updating is merging that pull request; the template's calling workflow
carries the permission line.

**Cutting a release** (forsgren#148, decision #170; forsgren#237). A release
changes no file: it tags the Quality-green head of `main` as it is, so there is
no bump commit and no version to rewrite in `README.md` and `docs/` (they name
no running version). The version an installation reports is the release's tag,
read by the go tool from the pinned commit. A new MAJOR also needs a new proof
run of each agent file, recorded in its Tested-with line: the release plan
refuses a major until every agent file has one
(`Scripts/release_agent_proofs.sh`).

## The Release workflow

**Before you start a Release: `./Scripts/release_precheck.sh [patch|minor|major]`**
(forsgren#231). One read-only command: it runs the same `Scripts/release_plan.sh`
the Release runs (with `--all`, so it names every block at once, not only the
first kind) and prints the plan's verdict, a table `| Issue | Blocks because | Do |`
of every open issue with commits on main since the latest release, every closed
issue since it without a `patch`, `minor` or `major` label and every issue that
needs a higher bump than the one asked, in the shape of the Release run page
(`Scripts/release_report.sh --table`, the same code), and a ✅ list of the
issues that are ready with their label. With no bump it judges the bump the
labels require. Exit 0: a Release with that bump would pass its plan, or,
when only `tools` issues were closed, there is nothing to release (it says
so: a Release now would tag nothing); exit 1:
it would stop, and the table says what to do first; exit 2: the plan could not
judge. It writes nothing. `Scripts/test_release_precheck.sh` feeds the pre-check
and the Release's report the same data and compares the tables.

**Before the last FBP of a release: `./Scripts/release_check.sh`** (forsgren#445).
Run it with your own `gh` login: it runs the same `release_plan.sh` the Release
runs (`auto --all`) and adds one check the plan does not make, a `*** RED ****`
commit on main since the latest tag, and it prints one line per finding and exits 1,
or `release check: OK, bump=<kind>`. It writes nothing; `Scripts/test_release_check.sh`
is its self-test.

`.github/workflows/release.yml` (forsgren#221) cuts a release in one run. Start
it from the Actions page (Release, Run workflow, on `main`) with the kind of
release, `patch`, `minor` or `major` (the default is `patch`), or through the
API: `gh workflow run release.yml -f bump=minor`. The run does, in this order,
and stops at the first step that fails:

1. **Quality is green on main's head** (`Scripts/release_quality.sh check`).
2. **The plan** (`Scripts/release_plan.sh`), before anything changes. It reads
   the latest release and the issues closed after its publish time. Each
   issue requires the bump of its label, `patch`, `minor` or `major`; the
   highest wins. **A tooling update needs no release** (forsgren#289): an
   issue labelled `tools` (CI, release scripts, build gates, self-tests) and
   none of the three needs no bump; it is listed in the notes of the next
   release under its own heading, Tooling, after the bump headings. An issue
   with `tools` and a bump label counts by its bump label. When only `tools`
   issues were closed since the latest release, the plan names them and says
   there is nothing to release (`release=none`): the run skips every later
   step, tags nothing and ends green, and its summary says nothing was
   released. These issues are not part of a release: the ones labelled
   `decision`, `duplicate`, `invalid`, `wontfix` or `question`, the ones closed
   as not planned, and the ones that the notes of an earlier release already
   name (an issue closed after its release was published is never listed
   twice). The plan stops on every open issue of the repository that has a
   commit on main since the latest release (a `#N` or `forsgren#N` in a commit
   subject; the release-bump commits, issues an earlier release named and
   open `tools` issues without a bump label, whose code ships in the tag with
   no user-facing change, do not count): the release tags main as it is, so its landed code would ship
   while its notes and bump miss it. Every such issue is named, followed by
   "close it, or split it (close the landed part as its own issue, move the
   rest to a new one)". The plan stops when nothing is left, and when an issue has none of
   the three labels and no `tools` label: every such issue is named, followed by "label it patch,
   minor or major". It stops when the requested bump is lower than the
   required one and names the issues that require more, so a minor change is
   never released as a patch. It stops on a major while an agent file has no
   proof run on the new major, and names each such file
   (`Scripts/release_agent_proofs.sh`). Otherwise it prints the next version
   and the release notes, one `- #N title` line per issue, grouped under Major,
   Minor, Patch and Tooling.
3. **The version is new**, no tag and no release of that name
   (`Scripts/release_publish.sh free`).
4. **Main has not moved** (`Scripts/release_quality.sh head`), the step right
   before the publish: the head of `main` must still be the commit Quality was
   proved green on. If it moved, the run stops and names both commits; nothing
   is tagged and the release is started again.
5. **The tag and the release**, in one `gh release create vX.Y.Z --target
   <that commit> --latest` with the notes of the plan
   (`Scripts/release_publish.sh create`). Nothing else makes the tag, so a tag
   never exists without its release, and nothing is committed or pushed.
6. **The install check** (`Scripts/release_verify_install.sh`): `go install` of
   the module at the released commit, into a temporary directory, must report
   the release, `vX.Y.Z`, as its module version, not a pseudo-version. The
   module proxy may need a moment to know the tag, so the check repeats (five
   tries, 30 seconds apart). If it never reports the release, no pin moves:
   installations would show the fallback version of `cmd/forsgren/main.go`, and
   `resume: pins` reruns the check.
7. **The template**: the pins of both caller workflows and the README of
   forsgren-template move to the new release in one commit, through the
   git-data API, the way the manual release did it
   (`Scripts/release_pins.sh template`). The same commit gives the
   `pull-requests: read` line of the calling workflow its comment, which names
   both reads it serves since 1.15.0, the merged pull requests and the
   footer's waiting update; the permission itself is unchanged, and a second
   run changes nothing. The same holds for the header: a comment that says
   `pinned by the commit of release vX.Y.Z` becomes `pinned by a release
   commit, named on the uses: line`, so no file names a version that goes
   stale (forsgren#506). A calling workflow without that line stops the step
   before anything is written. The README is the release's own:
   the step installs forsgren at the released commit with `go install`, as
   the daily run does, and writes the README with that binary's
   `forsgren install-readme`, so the commit holds byte for byte the text the
   next daily run writes, not the previous release's text with a new version
   line. A failed install, or a README that does not name the release, stops
   the step before anything is written, and `resume: pins` runs it again.
8. **The metrics installation**: a pull request in forsgren-metrics that moves
   the pins of its two workflows to the new release
   (`Scripts/release_pins.sh metrics`; it changes the `uses:` lines, as
   Dependabot does, and the header that names a release, as step 7 does
   (forsgren#506), and leaves the other comments). The release is done only when
   the metrics site runs the new version, so the workflow finishes it
   (`Scripts/release_metrics.sh`): it reads the pull request's files
   (`Scripts/release_verify_pin.sh`, the rule of `forsgren check-update` for the
   changed files: exactly the two caller workflows, each by one removed and one
   added pin line of the workflow it calls, to this release's version and
   commit, besides that header change; any other change is a red and nothing is merged), squash-merges it
   and deletes its branch (as the auto-update workflow does), starts
   `forsgren.yml` in forsgren-metrics on its default branch, which Dependabot's
   merge never does because that workflow runs on a schedule or by hand, and
   waits for the run to be green, at most about 20 minutes. The run page says
   `metrics: PR #N merged, forsgren run <url> green`. A red or cancelled run
   fails the step with the run's URL. It is safe to repeat (a resumed run
   with `resume: pins`): a merged pull request skips to the run, a green run
   after the merge is already done, and no second run is started while one is
   green or going. Other installations keep their own Dependabot schedule.

The last step runs whatever happened and prints what was done and what was not
(`Scripts/release_report.sh`). It names the step that failed from the outcome of
each step (`steps.<id>.outcome`, passed to it), not from the log, so a step that
fails before it could record anything, like the token check, is still the one
named. A run that fails halfway says so: a release pushes nothing to `main`,
and a tag exists only together with its release. When only the preview start
failed (forsgren#246), it says the release is published and to start the preview
with `Scripts/dispatch_preview.sh <sha of the release>`, or wait for the next
push to `main`. `SHIPPED.md` is still written by hand.

**The secret `FORSGREN_RELEASE_TOKEN`** is what steps 7 and 8 use, since the
job's own token cannot write to another repository. It is a fine-grained
personal access token of the owner of the repositories:

- resource owner: the account that owns forsgren-template and
  forsgren-metrics; repository access: only those two repositories
- repository permissions: Contents read and write, Pull requests read and
  write, Workflows read and write, and Actions read and write (to start
  forsgren.yml in forsgren-metrics; Metadata read is added by GitHub).
  Nothing else. Workflows is needed because both steps change files under
  `.github/workflows`: without it GitHub answers 403 "Resource not accessible
  by personal access token", and the step says the token needs Workflows: Read
  and write on that repository.
- expiration: a custom date under one year (a token with a longer custom date
  never expires, so keep it under a year)
- stored as the Actions secret `FORSGREN_RELEASE_TOKEN` of the forsgren
  repository

The first line of every Release run page, normal, failed or resumed, is the
token's expiry, read from GitHub's `github-authentication-token-expiration`
header on one authenticated call (`Scripts/release_token_expiry.sh`): more
than 30 days left, a green line with the date; 30 to 8 days, a yellow line and
a warning to renew it before the next release; 7 days or fewer, a red line and
an error annotation, and the run goes on; expired, or a token without an
expiry date, or one that cannot be used, a failed line and the run stops before
anything is pushed.

The run checks it first, so a missing secret stops the run before anything is
pushed, and steps 7 and 8 check it again: without it they fail with an
`::error::` line that names the secret, and never skip.

**When a run fails.** The last step says what to do, in the job summary and as
one `::notice::` line, by the stage the failure is in:

- *Before the release* (the token check, Quality on main, the plan, the
  version check, the head check, the publish): nothing was released and
  nothing is on `main`; a head check that finds `main` moved names both
  commits. Fix the cause (the summary names it where it is known:
  the secret, the issues to label, a version that exists, Quality with a
  link) and start Release again with the same bump.
  When the plan stopped, the run page lists every issue that blocks the
  release in a table, one row per issue, in the plan's order:

  |  | Issue | Blocks because | Do |
  |---|---|---|---|
  | ❌ | #N title (linked to the issue) | closed since vX.Y.Z, no patch, minor or major label | label it patch, minor or major |
  | ❌ | #N title (linked to the issue) | open, with commits on main since vX.Y.Z | close it, or split it (close the landed part as its own issue, move the rest to a new one) |
  | ❌ | #N title (linked to the issue) | needs minor, the run asked for patch | start Release with bump = minor |

  The rows are the plan's own machine lines (`blocking=<N>`, kind, title,
  tag), printed next to its red lines, so the page and the plan cannot
  disagree. The same table is in the step log. The headline of a failed run
  is the annotation `::error::...` in the log and `❌ ...` in the job summary
  (a workflow command is plain text there); both name the issue numbers
  (`blocked by #221, #231`). The generic cause is said only
  when the plan names no issue; "nothing was closed since the last release"
  is one sentence, not a table.
- *The release is published and the install check, the template or the
  metrics step failed*: the summary says the version is released; fix the cause
  (for a 403: the token's Workflows permission; for the install check: wait
  for the module proxy, installations show the fallback version meanwhile),
  then start Release with `resume` set to `pins`
  (`gh workflow run release.yml -f resume=pins`, or Actions, Release, Run
  workflow, resume: pins). A step is never done by hand, no pin moved by
  hand: the way on is always another run.

**Resuming a run that stopped after the release.** When steps 6, 7 or 8 fail, the
release exists and the version is no longer free, so the run cannot simply be
started again. Start it with the input `resume` set to `pins`
(`gh workflow run release.yml -f resume=pins`; the default is `none`). It
finds the latest release (`Scripts/release_resume.sh`: published, not a
draft or prerelease, its tag at the commit the release was made for), skips
Quality, the plan, the head check and the publish, and does only steps 6, 7
and 8 for that release. Both are safe to repeat: a repository that already
pins the version, or a pull request for it that is open or merged, is "already
done", not an error; of several pull requests for the release branch, any open
or merged one is enough, whatever the order. One closed without merging does
not count: the step names it in a note and opens a new pull request, reusing
the release branch when it holds the same pins or moving it when it does not.
The report of a resumed run expects only these steps.

Each script has a self-test that runs in sfl and Quality, and
`Scripts/test_release_workflow.sh` pins the workflow: its trigger, its
permissions (`contents: write`, `actions: read`, `issues: read`), its order,
its commands, which steps `resume: pins` skips and that the secret reaches only
the token check and the two steps that use it.

### Release tags are protected

A repository ruleset, "Protect release tags" (forsgren#225), covers every tag
that matches `v*`: nobody can move one (`update`) or delete one (`deletion`),
and it has no bypass. Creating a tag stays allowed, because the Release workflow
creates the tag together with its release. Installations pin forsgren's
workflows by commit, so a moved tag would not change the code they run, but it
would mislabel a release and the links that name it.

The ruleset was checked when it was set: a test tag `v0.0.0-ruleset-check`
could be created, and moving and deleting it were both refused with
"Cannot update this protected ref". The ruleset was then switched off for a
moment to remove the test tag, and switched back on. Changing the ruleset is a
repository setting (Settings, Rules, Rulesets) for the maintainer.
