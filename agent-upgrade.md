# Upgrading forsgren: instructions for an AI coding agent

You are an AI coding agent. A person pointed you at this file because they
already have a forsgren installation (a GitHub repository of their own, the
**data repository**, that publishes the DORA metrics of their repositories as
a page on GitHub Pages) and want it brought up to the latest forsgren release.
They may have started on an older release, or have automatic updates switched
off. A new installation is a different job: see
[agent-installer.md](agent-installer.md).

Follow **only this file**, from the top, in order. Do not use other guides,
your memory of forsgren, or other installations as a source. The full
reference is forsgren's [README](README.md) and the docs it lists; this file
names the parts of it you need. What each release asks of an installation is
in that release's notes: you read them in step 4, and you never rely on what
you remember of them.

Tested with: not yet tested. The line is filled in when a fresh agent has
upgraded a real installation by this file alone.

## Before you start (for the person)

1. Open a new terminal in an empty folder, for example
   `mkdir -p /tmp/forsgren-upgrade && cd /tmp/forsgren-upgrade`. An empty
   folder means no other project's instructions are loaded. The agent keeps
   its work files in a folder inside it. When Claude Code asks "Quick safety
   check: Is this a project you created or one you trust?" for this new
   folder, the empty folder you just made is safe: choose "Yes, I trust this
   folder".
2. Start the agent with the tested model: `claude --model sonnet`.
3. If Claude Code asks "Teach auto mode about your environment?", choose
   "Not now". Do not choose "Don't show again", which changes your settings
   for every session.
4. Then tell the agent: "Upgrade my forsgren installation by following
   https://github.com/yveshanoulle/forsgren/blob/main/agent-upgrade.md".
   The agent asks you for one thing: the address of your current forsgren
   report, the page it publishes. Everything else it finds out itself.

In Claude Code's auto mode, a commit can be blocked when it was not asked for
in so many words; the go-sentence the agent asks for in step 5 is that
request.

## How to work through this file

- **Do every step in order.** Each step says what to do, the exact command,
  how to check that it worked, and what to do when it fails.
- **When a step fails, stop.** Show the person the step number, the exact
  command and its exact output, and say which check failed. Do not retry with
  another command, do not work around it, do not guess a fix. The rule of this
  file is: when a step fails, the file is fixed, and the upgrade starts again
  from the top (see Going back for what a half-done upgrade leaves).
- **A wait is not a failure.** Some steps wait for GitHub. They say how long
  to wait and what to do when the wait runs out.
- **Placeholders.** Commands use these words in capitals. Replace each with
  its value before you run the command, everywhere, every time:
  - `REPORT`: the address of the person's current report (step 1).
  - `OWNER`: the account or organisation that owns the data repository.
  - `REPO`: the data repository's name. `OWNER/REPO` is the two together.
  - `VERSION`: the forsgren release the data repository pins today, such as
    `vX.Y.Z` (step 2).
  - `LATEST`: forsgren's latest release, such as `vX.Y.Z` (step 3).
  - `LATESTSHA`: the commit of `LATEST`, 40 hex digits (step 3).
  - `PR`: the number of a waiting Dependabot pull request (step 3).
  - `BRANCH`: the data repository's default branch (step 6).
  - `TAG`: a release's tag, such as `v1.2.0` (step 4).
  - `CANDIDATE`: a repository's full name, `owner/name` (step 2).
  - `FILE`: a file's name, such as `forsgren.yml` (steps 6 to 8).
  - `PATH`: a file's path in the repository, such as
    `.github/workflows/forsgren.yml` (steps 7 and 8).
  - `NAMES`: the config keys a commit message names (step 8).
  - `WORK`: your work folder, the absolute path of `forsgren-work` inside
    the folder the person started you in (step 1).
- **Names made by a command.** `HEADSHA`, `TREESHA`, `BLOB1`, `BLOB2`,
  `NEWTREE`, `NEWCOMMIT`, `MERGECOMMIT`, `RUN`, `NUMBER`, `FIRSTCOMMIT` and
  `BEFORE` stand for the value a command printed; the step that prints it
  names it, and the later commands of that step use it.
- **Write values into each command.** Do not rely on shell variables or a
  changed directory carrying over from one command to the next; use the
  absolute paths given here.
- **The person does some steps themselves.** They are marked **Person**.
  Hand the person the text or command as written, wait until they say it is
  done, then do the check yourself.

## What you must never do

- Never name a private repository in a public place: not in a public
  repository's files, commits or issues, and not on the page.
- Never print, log, store, commit or ask to see a token. Never run
  `gh auth token`.
- Never push, commit or open anything in `yveshanoulle/forsgren` or in
  `yveshanoulle/forsgren-template`. You only read them. These are two exact
  names: a repository named `forsgren` under another owner is an
  installation, not forsgren itself, and it is the one you upgrade.
- Never commit anything before the person has replied with the go-sentence of
  step 5. A commit made without it is a failure of this file.
- Never force-push, and never rewrite history in any repository.
- Never put a `Co-Authored-By` line, or any other line naming a tool, in a
  commit message you write.
- Never change the person's data: not `data/`, and not `forsgren.config.yml`
  beyond the keys the person chose in step 5.
- Never lower a pin: you only move it to a newer release. The one exception
  is Going back, which the person asks for and confirms with its own
  go-sentence.
- Never delete anything, except the work folder `WORK` this file creates.
- Never install tools. When a tool is missing, stop and tell the person.
- Never change the person's git or gh configuration. When a step needs it,
  the person runs the command.
- When a permission check blocks a command (for example Claude Code's auto
  mode denies a commit), stop and report the command and the reason it gave.
  Never suggest a permission rule or a settings change, and never ask the
  person to run the command by hand: both bypass what this file tests.

## Step 1. Check the prerequisites and ask for the report

Run each command and check its output.

1. `gh --version`
   - Works: it prints `gh version` and a number.
   - Fails (command not found): stop. Ask the person to install the GitHub
     CLI from https://cli.github.com and to start again.
2. `gh auth status`
   - Works: it prints `Logged in to github.com account LOGIN`, and the line
     `Token scopes:` contains `'repo'` and `'workflow'`. The token itself is
     shown masked; never try to show it unmasked.
   - Not logged in: stop. **Person:** run `gh auth login` in their own
     terminal, then start again at step 1.
   - `'workflow'` or `'repo'` missing: stop. **Person:** run
     `gh auth refresh -h github.com -s repo,workflow` in their own terminal,
     then start again at step 1. (`workflow` is needed because the pins live
     in files under `.github/workflows/`.)
3. `gh api user --jq .login`
   - Works: it prints the login. It is the person's account.
4. `command -v curl`
   - Works: it prints a path. `curl` reads the published report.
   - Fails: stop and tell the person.
5. `go version` (optional)
   - Prints `go version go1.N...`: Go is there; step 8 checks the config with
     it. Go 1.21 or later is needed.
   - Not found or older: note it. Do not install Go.
6. `pwd`
   - Works: it prints the folder the person started you in, an absolute path.
     `WORK` is that path followed by `/forsgren-work`, for example
     `/tmp/forsgren-upgrade/forsgren-work`.
7. **Ask the person one thing:** "What is the address of your current forsgren
   report, the page it publishes?" For example
   `https://acme.github.io/forsgren-metrics/` or `https://forsgren.example.com/`.
   That address is `REPORT`; write it with a final `/`. Ask nothing else yet:
   step 2 finds the rest out from the report and the repository, and step 5
   asks only what is the person's to decide.

git is not needed: every change this file makes goes through `gh api`, so
there is no clone, no push and no git credential to set up.

## Step 2. Find the installation from its report

Read the report first, then the repository it comes from.

1. The footer names the running forsgren version:
   `curl -fsS REPORT | grep -o 'Forsgren</a> [0-9.]*'`
   - Works: it prints `Forsgren</a>` and a version without its `v`. That is
     the version that built the page; write it down.
   - Empty answer or a 404: stop and report; the address may be wrong.
2. The settings page shows the current configuration, every key with its
   value:
   `curl -fsS REPORTsettings.html | tr -d '\n' | grep -oE '<th scope="row">[a-z_]+</th>([^<]*<td>[^<]*</td>){3}' | sed -E 's/<[^>]+>/;/g; s/; *;/;/g'`
   - Works: one line per setting, such as `;auto_update;true;true, false;False;`:
     the key, its current value, the possible values and, from forsgren 0.8.6
     on, whether it is the default (`True`) or set in the file (`False`).
   - The settings page exists from forsgren 0.5.0. A 404 means the
     installation is older than forsgren 0.5.0 (`curl -f` then ends with an
     error: that is the answer, not a failure of this file; the issues and
     days pages are missing too). An answer that is not that table (an
     installation older than 0.8.6 shows a different layout) is not a
     failure either. In both cases the repository's `forsgren.config.yml`
     (item 5) is the source of the current settings.
3. The page address gives the repository:
   - `https://OWNER.github.io/REPO/`: `OWNER` is the host's first part and
     `REPO` the first path part. `OWNER/REPO` may be `OWNER/forsgren`: an
     installation can carry the tool's name. That is the installation, not
     forsgren itself.
   - A custom domain (any other host): search the person's repositories for
     the one whose Pages custom domain is that host:
     `gh api 'user/repos?per_page=100' --paginate --jq '.[].full_name'`
     then, for each full name as `CANDIDATE`,
     `gh api repos/CANDIDATE/pages --jq .cname` until one prints the host. Also
     search the organisations the login belongs to
     (`gh api user/orgs --jq '.[].login'`). More than one match, or none:
     stop and ask the person for `OWNER/REPO`.
   - Check: `gh api repos/OWNER/REPO/pages --jq '.html_url,.cname'` prints
     `REPORT` (the address, with or without the custom domain).
   - Refuse only these two names, exactly `yveshanoulle/forsgren` or
     `yveshanoulle/forsgren-template`: they are the tool and its template,
     never an installation. Stop and report; the address is not the
     person's report. Any other name, whatever it contains, goes on.
4. The repository gives the pins and the files:

   ```
   mkdir -p WORK
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/.github/workflows/forsgren.yml \
     > WORK/forsgren.yml
   grep -n 'uses:' WORK/forsgren.yml
   ```

   Check: one line that calls
   `yveshanoulle/forsgren/.github/workflows/metrics.yml@` a 40-hex commit and
   ends in `# vX.Y.Z`. That `vX.Y.Z` is `VERSION`. Anything else: stop and
   report; this repository is not a forsgren installation.

   This file supports installations pinned to forsgren 0.2.0 or later. Print
   `0.2.0` and `VERSION` without its `v`, one per line, through `sort -V`
   (as in step 3): when the first line is not `0.2.0`, `VERSION` is
   older than v0.2.0: stop and report (not supported).
5. The update caller, the Dependabot setup and the configuration:

   ```
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/.github/workflows/forsgren-update.yml \
     > WORK/forsgren-update.yml
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/.github/dependabot.yml \
     > WORK/dependabot.yml
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/forsgren.config.yml \
     > WORK/forsgren.config.yml
   grep -n 'uses:' WORK/forsgren-update.yml
   grep -n 'default-days:' WORK/dependabot.yml
   ```

   - `forsgren-update.yml` and `dependabot.yml` may be missing in an
     installation made before auto-update existed: a 404 there is not a
     failure. Note which are missing; step 7 brings them over.
   - When `forsgren-update.yml` exists, its `uses:` line calls
     `yveshanoulle/forsgren/.github/workflows/auto_update.yml@` a 40-hex
     commit and ends in `# vX.Y.Z`. The two files must carry the same version
     and the same commit. Different: stop and report (a half-moved pin).
   - The pinned commit is the one `VERSION` really is:
     `gh api repos/yveshanoulle/forsgren/commits/VERSION --jq .sha` prints the
     commit in `forsgren.yml`. Another commit: stop and report; the pin was
     edited by hand.
   - The footer's version (item 1) differs from the pin (`VERSION` without
     its `v`): not a failure. The page was built by an earlier run than the
     pin (a pin that moved and has not run yet), or the daily run is failing.
     Tell the person in step 5 and let step 9 prove the new version.
   - `forsgren.config.yml` missing: stop and report.
6. Which token the installation uses: in `WORK/forsgren.yml`, the line
   `FORSGREN_TOKEN:` reads `secrets.FORSGREN_TOKEN` (a token the person made)
   or `secrets.GITHUB_TOKEN` (the run's own token, for an installation that
   measures only public repositories). Write it down: step 7 keeps it.
7. The current settings, for step 5: from item 2 when the settings page gave
   them, otherwise from `WORK/forsgren.config.yml`. For each key of
   `auto_update`, `auto_update_level`, `history_days` and `view`, write down
   its value and whether the file sets it. The update wait is
   `default-days` in `WORK/dependabot.yml`.

Then go on to step 3.

## Step 3. Find the latest release and a waiting pull request

1. The latest release is the one GitHub marks Latest in the release list, not
   the tags and not a version written in a file:

   ```
   gh release list -R yveshanoulle/forsgren --exclude-drafts --exclude-pre-releases -L 5
   ```

   - Works: one row has the word `Latest`; its tag, such as `v1.2.0`, is
     `LATEST`.
   - No row says `Latest`: stop and report.
2. Its commit:
   `gh api repos/yveshanoulle/forsgren/commits/LATEST --jq .sha`
   - Works: 40 hex digits. That is `LATESTSHA`.
   - Fails: stop and report.
3. Compare `VERSION` with `LATEST` as numbers, never as text (`v1.10.0` is
   newer than `v1.9.0`): print both without their `v`, one per line, and sort
   them with `sort -V`; the last line is the newer one.
   - `VERSION` is the same as `LATEST`: the installation is already the
     latest release. Tell the person so, and do not stop yet: go to step 9,
     whose checks show whether the installation really runs it, and skip
     steps 4 to 8.
   - `VERSION` is newer than `LATEST`: stop and report. A pin must never be
     lowered, and a release newer than the latest is not published.
   - `VERSION` is older: go on.
4. A waiting Dependabot pull request, if there is one:

   ```
   gh pr list -R OWNER/REPO --app dependabot --state open --json number,headRefName
   ```

   - An empty list: no pull request is waiting. Step 6 moves the pins itself.
   - One or more: for each `number`, as `PR`, read what it changes:

     ```
     gh pr diff PR -R OWNER/REPO --name-only
     gh pr diff PR -R OWNER/REPO | grep -E '^[+-].*uses:'
     ```

     It is the pull request step 6 may merge when the file names are exactly
     `.github/workflows/forsgren.yml` and
     `.github/workflows/forsgren-update.yml` (or the first alone, when the
     installation has no second caller), and the `+` lines end in `# LATEST`
     with `LATESTSHA`. Write down its number. Any other file, or another
     version or commit: do not use it; step 6 moves the pins itself, and the
     pull request is left as it is.
   - Never take the version from a pull request's title: it is a label, and
     the diff is what merges.

Then go on to step 4.

## Step 4. Read what each release asks of an installation

Read each release's notes for what it asks of an installation. A release's
notes are the only source of that; do not decide from the version numbers.

1. List the releases after `VERSION` up to `LATEST`, oldest first:

   ```
   gh release list -R yveshanoulle/forsgren --exclude-drafts --exclude-pre-releases -L 100
   ```

   The rows are newest first: take the tags newer than `VERSION` (compare as in
   step 3), up to and including `LATEST`, and read them from the oldest. A
   `VERSION` older than the list reaches (more than 100 releases back): stop
   and report.
2. Read the notes of each, one at a time:

   ```
   gh release view TAG -R yveshanoulle/forsgren --json body --jq .body
   ```

   with `TAG` each release in turn. Fails: stop and report.
3. For each release, ask these questions of its notes and write down the
   answer in `WORK/asks.md`, one line per release (`TAG: nothing` when it
   asks nothing):
   - A new permission in `.github/workflows/forsgren.yml` or
     `forsgren-update.yml`?
   - A new secret?
   - A new config key in `forsgren.config.yml`, or a key whose default
     changes?
   - A template file to copy or change (`dependabot.yml`, a workflow)?
   - A page that appears, disappears or is hidden?
   - A consequence for `auto_update_level` or the update wait, such as a
     release that an installation at a lower level has to merge by hand?

   Notes that say "No new permission, secret or config key" ask nothing about
   those three; read the rest of the notes for the other questions. A note
   you cannot answer: write down the question as it stands. Step 5 asks the
   person.
4. The installation's own setup issue is a second source, never the first:
   `gh issue list -R OWNER/REPO -l forsgren-setup`. An open issue lists what
   the running version found missing. Add each item to `WORK/asks.md`.
   forsgren only fills it for the version that runs, so an upgrade can need
   more than it says.

Worked example. From 1.3.0 an installation without `days_page` in its
`forsgren.config.yml` loses its Daily page until it sets `days_page: true`.
The 1.3.0 notes ask a question about a page that disappears; `WORK/asks.md`
gets `v1.3.0: the Daily page is hidden unless days_page: true`. Step 5 asks
the person whether to keep the Daily page, and step 8 writes
`days_page: true` only when they say yes. Another release asks something else,
and you handle it the same way: read its notes, write the answer down, ask the
person in step 5, and apply the answer they chose.

Then go on to step 5.

## Step 5. Ask the person what is theirs, then wait for the go

Ask all of it together, in one message, before anything is written. Show every
question with the current value or the default filled in, from step 2 and
`WORK/asks.md`. Never show the person a placeholder such as `OWNER` or
`LATEST`. Ask only what is the person's to decide; what the files already say,
you do not ask again.

End the message with this line, word for word:

> Reply with your answers by number, for example '2: raise the level to
> minor'. Reply 'defaults' to take every default.

Then wait for the answers. The questions, in this order, each only when it
applies:

1. **The release.** Say the installation is on `VERSION` and goes to `LATEST`,
   and if the footer's version differed from the pin in step 2, say so. No
   answer is needed.
2. **A waiting pull request.** Only when step 3 found a Dependabot pull request
   that moves the pins to `LATEST`. Name it (`#PR`) and explain why it waits.
   The size of the step decides: from `VERSION` to `LATEST` it is a major
   update when the major number differs, a minor update when only the minor
   number differs, a patch update otherwise. With `auto_update: true` the
   pull request merges by itself only within `auto_update_level`, so its level
   kept it from merging; with `auto_update: false` nothing merges by itself.
   Offer three ways, and name the default, which is the second:
   - raise the level to the smallest one that permits this step (`minor` for
     a minor update, `major` for a major one), so this and later updates
     merge by themselves; this changes `forsgren.config.yml`;
   - merge it once: step 6 merges the pull request, and the level stays as
     it is;
   - move the pins in step 6 yourself, and leave the pull request as it is.
3. **Each ask of `WORK/asks.md`** that needs the person: one question per
   line, in the words of the release's notes, with the default that keeps the
   installation as it behaves today when that is possible, or the one the
   notes recommend. A line that says `nothing` is not asked.
4. **Auto-update**, showing the current value: `auto_update` true or false
   (default: what it is now), `auto_update_level` (default: what it is now, or
   `major` when the file has none), and the update wait in days (default: what
   `default-days` says now, or `3` when `dependabot.yml` is missing; `0` means
   as soon as a release is out). Offer the starter's setting, `auto_update:
   true` with `major`, only as information.

Then show the plan, in one message: `OWNER/REPO`, `VERSION` to `LATEST`, how
step 6 moves the pins, each file you will write and each line that changes in
it (from the answers), and what the person does themselves. End with this
go-question, with the values filled in, and each "and ..." part only when it
applies:

> Reply "go: upgrade OWNER/REPO from VERSION to LATEST and commit the pin
> change and the dependabot.yml change and the forsgren.config.yml change" to
> let me commit.

Wait for that reply, the sentence as shown, filled in. A bare "go", or any
other reply that does not name these writes: show the sentence again and wait.
Any change to an answer: show the plan again. Nothing is committed before that
reply.

Then go on to step 6.

## Step 6. Move the pins, in one commit

Only after the go of step 5. Both pins move to `LATEST` and `LATESTSHA`, and
nothing else changes in this step. Pick the way from step 5's answer and
step 3's pull request:

- **Route 6a: merge the waiting pull request.** Step 5's answer was "merge it
  once" or "raise the level", and step 3 found a pull request (`PR`) that
  moves exactly both pins to `LATEST`.
- **Route 6b: move the pins yourself.** Every other case.

### Route 6a

```
gh pr merge PR -R OWNER/REPO --squash
```

Works: it says the pull request is merged. Never `--admin`, and never
`--auto`: a pull request that cannot merge now (a failed check, a required
review, a conflict) is not forced. Fails: stop and report its output.

Then go to the read back below.

### Route 6b

1. The branch and its head:

   ```
   gh api repos/OWNER/REPO --jq .default_branch
   ```

   That is `BRANCH`. Then:

   ```
   gh api repos/OWNER/REPO/git/ref/heads/BRANCH --jq .object.sha
   gh api repos/OWNER/REPO/git/commits/HEADSHA --jq .tree.sha
   ```

   The first prints `HEADSHA`, the head commit; use it in the second, which
   prints `TREESHA`. The branch moves daily with data commits, so read the
   head now and not from earlier.
2. Read both caller files at that head into `WORK/new/`, with the person's
   files as they are now:

   ```
   mkdir -p WORK/new
   gh api -H 'Accept: application/vnd.github.raw' \
     'repos/OWNER/REPO/contents/.github/workflows/forsgren.yml?ref=HEADSHA' \
     > WORK/new/forsgren.yml
   gh api -H 'Accept: application/vnd.github.raw' \
     'repos/OWNER/REPO/contents/.github/workflows/forsgren-update.yml?ref=HEADSHA' \
     > WORK/new/forsgren-update.yml
   ```

   `forsgren-update.yml` may be missing (a 404): then this step moves
   `forsgren.yml` alone, and step 7 brings the other file over.
3. For each file in `WORK/new/`: first keep a copy of it as read,
   `cp WORK/new/FILE WORK/new/FILE.orig`; then change its one `uses:` line
   with your file tool: its commit (40 hex digits) to `LATESTSHA` and its
   comment to `# LATEST`, and nothing else. Check:
   `diff WORK/new/FILE.orig WORK/new/FILE` prints exactly one changed line (a
   `<` line and a `>` line), and
   `grep -c 'uses: yveshanoulle/forsgren/.github/workflows/.*@LATESTSHA # LATEST' WORK/new/FILE`
   prints `1`. Anything else: stop and report.
4. Make a blob of each file:

   ```
   gh api -X POST repos/OWNER/REPO/git/blobs -F content=@WORK/new/forsgren.yml -f encoding=utf-8 --jq .sha
   gh api -X POST repos/OWNER/REPO/git/blobs -F content=@WORK/new/forsgren-update.yml -f encoding=utf-8 --jq .sha
   ```

   They print `BLOB1` and `BLOB2`.
5. Make one tree from both. Write `WORK/tree.json` with your file tool (leave
   out the second entry when there is no `forsgren-update.yml`):

   ```
   {"base_tree": "TREESHA", "tree": [
     {"path": ".github/workflows/forsgren.yml", "mode": "100644", "type": "blob", "sha": "BLOB1"},
     {"path": ".github/workflows/forsgren-update.yml", "mode": "100644", "type": "blob", "sha": "BLOB2"}
   ]}
   ```

   then:

   ```
   gh api -X POST repos/OWNER/REPO/git/trees --input WORK/tree.json --jq .sha
   ```

   It prints `NEWTREE`.
6. Make the commit, in one commit for both files, on top of `HEADSHA`, in the
   way Dependabot's would read, with no `Co-Authored-By` and no other trailer:

   ```
   gh api -X POST repos/OWNER/REPO/git/commits \
     -f message='forsgren: bump yveshanoulle/forsgren from VERSION to LATEST' \
     -f tree=NEWTREE -f 'parents[]=HEADSHA' --jq .sha
   ```

   It prints `NEWCOMMIT`.
7. Move the branch to it, never forced:

   ```
   gh api -X PATCH repos/OWNER/REPO/git/refs/heads/BRANCH -f sha=NEWCOMMIT -F force=false --jq .object.sha
   ```

   Works: it prints `NEWCOMMIT`. Fails (the answer says it is not a
   fast-forward, because the branch moved meanwhile, or a branch protection
   refused it): stop and report. Do not run it again with another commit and
   do not force it: nothing has changed on the branch.

### The read back (both routes)

Do not trust the answer of the command; read the branch again.

1. `gh api repos/OWNER/REPO/commits/BRANCH --jq .sha` prints the head. Route
   6b: it is `NEWCOMMIT`. Route 6a: the pull request's merge commit,
   `gh pr view PR -R OWNER/REPO --json mergeCommit --jq .mergeCommit.oid`
   (`MERGECOMMIT`), is the head or lies before it:
   `gh api repos/OWNER/REPO/compare/MERGECOMMIT...BRANCH --jq .status` prints
   `identical` or `ahead` (a data commit of a daily run may follow the merge).
   Anything else, or no merge commit: stop and report.
2. For each caller file that exists:

   ```
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/.github/workflows/FILE \
     | grep -n 'uses:'
   ```

   Works: one line, ending `@LATESTSHA # LATEST`. Another version or commit,
   or a file that still shows `VERSION`: stop and report.
3. Route 6b only: the commit changed exactly the caller files and has no
   trailer:

   ```
   gh api repos/OWNER/REPO/commits/NEWCOMMIT --jq '[.files[].filename]'
   gh api repos/OWNER/REPO/commits/NEWCOMMIT --jq .commit.message
   ```

   The first lists only `.github/workflows/forsgren.yml` and, when it exists,
   `.github/workflows/forsgren-update.yml`. The second is the one line you
   wrote.

The installation's pins are now at `LATEST`. The page still shows `VERSION`
until a run publishes it: step 9 starts one.

Then go on to step 7.

## Step 7. Bring over the template's changes the notes name

forsgren-template is the starting point of every installation, and a release
sometimes asks for a change in the files an installation took from it: a
permission line in a workflow, a change in `dependabot.yml`, a workflow file
that an old installation does not have. The installation's own copies carry
choices of the person (the token line, the update wait), so you change only
the lines a release's notes name. Never copy a whole template file over the
installation's: it would undo those choices (on the public-only route, the
`FORSGREN_TOKEN:` line).

1. What is named: read `WORK/asks.md` (step 4) for lines about a permission, a
   workflow, `dependabot.yml` or a template file. Add a file that is missing
   in the installation (step 2 item 5) when the person chose `auto_update:
   true` in step 5, or when the notes name it. Nothing named: skip this step
   and go on to step 8.
2. Read the template's file and the installation's, as the branch has them
   now (after step 6), for each file that is named. The paths are
   `.github/workflows/forsgren.yml`, `.github/workflows/forsgren-update.yml`
   and `.github/dependabot.yml`:

   ```
   mkdir -p WORK/cur WORK/tpl
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/yveshanoulle/forsgren-template/contents/.github/dependabot.yml \
     > WORK/tpl/dependabot.yml
   gh api -H 'Accept: application/vnd.github.raw' \
     'repos/OWNER/REPO/contents/.github/dependabot.yml?ref=BRANCH' \
     > WORK/cur/dependabot.yml
   ```

   with the other names the same way (the template's
   `.github/workflows/forsgren-update.yml` has the path
   `repos/yveshanoulle/forsgren-template/contents/.github/workflows/forsgren-update.yml`).
   The installation's copy of a missing file is not there (a 404): that is
   expected, and `WORK/cur/FILE` stays absent.
3. The template must be at `LATEST`: in `WORK/tpl/forsgren.yml` (read it too),
   the `uses:` line ends in `# LATEST`. Another version: the template has not
   caught up with the release. Stop and report; do not copy an older template.
4. Compare: `diff WORK/cur/FILE WORK/tpl/FILE`. The diff shows more than the
   notes ask for: the person's choices (the token line, `default-days`) and
   comments. Leave all of that. Make the installation's copy
   `WORK/new/FILE`: start from `WORK/cur/FILE` and change, with your file
   tool, only the lines the notes name, in the template's words (a permission
   line with the template's comment, for example). A file the installation
   does not have: the template's file, changed to the installation's choices
   (its `default-days` is the update wait of step 5, and the
   `FORSGREN_TOKEN:` line is the one step 2 item 6 wrote down).
   Check, for each file: `diff WORK/cur/FILE WORK/new/FILE` shows only the
   lines you meant, the `FORSGREN_TOKEN:` line is the same as in step 2, and
   the `default-days` line is the same as in step 2 unless step 5 changed it.
5. Inside the go of step 5: the plan named the files and lines. A line that
   the plan did not name, or a file it did not name, is not covered. Show the
   person that diff, say what differs from the plan, show the plan again and
   wait for a new go, as in step 5. Nothing is committed before it.
6. Commit it as route 6b of step 6 does, in one commit for all the changed
   files: items 1 and 4 to 7 with `WORK/new/` as the source and the changed
   files in the tree (`mode` `100644`), the message
   `forsgren: bring the template's changes of LATEST into the workflow files`
   (or `...into .github/dependabot.yml`, naming what changed), no
   `Co-Authored-By` and no other trailer, and the branch moved without force.
7. The read back: the head is `NEWCOMMIT`; for each changed file,

   ```
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/PATH | diff - WORK/new/FILE
   ```

   prints nothing; the commit lists exactly those files
   (`gh api repos/OWNER/REPO/commits/NEWCOMMIT --jq '[.files[].filename]'`),
   and the pins in the two caller files still read `@LATESTSHA # LATEST`.
   Fails: stop and report.

Then go on to step 8.

## Step 8. Write the settings the person chose

Write only the settings the person chose in step 5, and nothing else: a key of
`forsgren.config.yml` (a new key a release introduced, `auto_update`,
`auto_update_level`), and the update wait, `default-days` in
`.github/dependabot.yml`. Every other line, key and comment stays as it is,
`projects:` and `data/` included. Nothing chosen: skip this step and go on to
step 9 (every answer was to keep what is there).

1. Read both files as the branch has them now (after steps 6 and 7), with
   `BRANCH` and `HEADSHA` read again as in route 6b item 1 of step 6:

   ```
   mkdir -p WORK/cur WORK/new
   gh api -H 'Accept: application/vnd.github.raw' \
     'repos/OWNER/REPO/contents/forsgren.config.yml?ref=HEADSHA' \
     > WORK/cur/forsgren.config.yml
   gh api -H 'Accept: application/vnd.github.raw' \
     'repos/OWNER/REPO/contents/.github/dependabot.yml?ref=HEADSHA' \
     > WORK/cur/dependabot.yml
   cp WORK/cur/forsgren.config.yml WORK/new/forsgren.config.yml
   cp WORK/cur/dependabot.yml WORK/new/dependabot.yml
   ```

   `dependabot.yml` missing (a 404): the update wait cannot be set; if the
   person chose one, stop and report (step 7 should have brought the file).
2. Change `WORK/new/` with your file tool, one setting at a time:
   - A config key that is in the file: change its value on its line.
   - A config key that is not in the file yet: add it as a new top-level
     line above `projects:`, with the value the person chose, and a comment
     line above it that names the key (taken from the release's notes) when
     the file's other keys have one.
   - `auto_update` and `auto_update_level`: `true` or `false`, and `patch`,
     `minor` or `major`, as literals, never in quotes.
   - The update wait: the number on the line `default-days:` of
     `WORK/new/dependabot.yml`, and nothing else in that file.
3. Show the person the change, the same lines the plan of step 5 named:
   `diff WORK/cur/forsgren.config.yml WORK/new/forsgren.config.yml` and
   `diff WORK/cur/dependabot.yml WORK/new/dependabot.yml`. A line that the
   plan did not name is not covered by the go: show the plan again and wait
   for a new go, as in step 7 item 5.
4. Check the configuration at the new version, when Go is there (step 1 item
   5):

   ```
   go run github.com/yveshanoulle/forsgren/cmd/forsgren@LATEST check-config --config WORK/new/forsgren.config.yml
   ```

   - Works: one line, `OK: ... is a valid forsgren config (version 1): ...`.
   - It names what is wrong: you wrote the file in this step, so fix the file
     to what the line asks, show the person the change, and run the check
     again. Any other error (a download or Go error): stop and report.
   - Without Go: tell the person the first run (step 9) checks the file and
     fails before it publishes anything when it is invalid.
5. Commit it as route 6b of step 6 does, in one commit for the files that
   changed: items 1 and 4 to 7 with `WORK/new/` as the source (the tree holds
   `forsgren.config.yml` and `.github/dependabot.yml`, only the ones that
   changed), the message `forsgren: set NAMES for LATEST` with `NAMES` the
   keys changed (for example `days_page and auto_update_level`), no
   `Co-Authored-By` and no other trailer, and the branch moved without force.
6. The read back: the head is `NEWCOMMIT`; for each changed file,

   ```
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/PATH | diff - WORK/new/FILE
   ```

   prints nothing, the commit lists exactly those files, and the pins in the
   two caller files still read `@LATESTSHA # LATEST`. Fails: stop and report.

Then go on to step 9.

## Step 9. Run it and check the published page

Reached from step 8, or from step 3 when the installation was already at the
latest release (steps 4 to 8 skipped). Start the run yourself: the schedule
can run hours late, and the person should see the result now.

1. Start it:
   `gh workflow run forsgren.yml -R OWNER/REPO`
   Works: it says it created a `workflow_dispatch` event.
2. Wait 10 seconds, then find the run:

   ```
   gh run list -R OWNER/REPO -w forsgren.yml -L 3 --json databaseId,event,status,createdAt
   ```

   Take the newest run with `"event":"workflow_dispatch"` made after you
   started it. Its `databaseId` is `RUN`. No such run yet: wait 10 seconds and
   look again, at most 6 times.
3. Watch it to the end (a few minutes; forsgren is built first):
   `gh run watch RUN -R OWNER/REPO --exit-status`
   Works: it ends with exit status 0.
   Fails: run `gh run view RUN -R OWNER/REPO --log-failed`, stop, and report
   that output. The pins are at `LATEST` now; the person decides whether to
   go back (see Going back).
4. `gh run view RUN -R OWNER/REPO --json conclusion --jq .conclusion`
   prints `success`.

Then check what the run published. GitHub Pages can serve the old page for a
minute or two after a deploy: when a check below shows the old state, wait 1
minute and run that check again, at most 5 times, before you report it.

5. The footer names the new version:
   `curl -fsS REPORT | grep -o 'Forsgren</a> [0-9.]*'`
   prints `Forsgren</a>` and `LATEST` without its `v`. An older version after
   all the retries: stop and report.
6. The settings page shows the chosen settings. Run step 2 item 2's command
   again (`curl ... REPORTsettings.html ...`). Every row the person set in
   step 8 shows their value and ends with `False` (set in the file); every
   key they left alone shows the same value as before; a key new in this
   release that they did not set ends with `True` (the default) and shows the
   default. A row missing or different: stop and report.
7. A page that a release hides or shows (`WORK/asks.md`, step 4): ask for it
   by its address, `curl -sS -o /dev/null -w '%{http_code}' REPORTdays.html`
   (for another page, its file name in place of `days.html`).
   A page the person chose to hide answers `404`; one they chose to show
   answers `200`; `days.html` is the Daily page. Another
   answer after the retries: stop and report.
8. A custom domain, when `REPORT` is not a `github.io` address: it must start
   with `https://`, and `curl -fsS -o /dev/null -w '%{http_code}' REPORT`
   prints `200`. The HTTPS enforcement itself is the person's, not part of
   this upgrade; an `http://` address: tell the person.
9. No setup issue stays open: `gh issue list -R OWNER/REPO -l forsgren-setup`
   lists no open issue. The run closes it by itself when nothing is missing
   any more. An issue still there: show the person its title and body
   (`gh issue view NUMBER -R OWNER/REPO`, with the number the list shows),
   say what it asks, stop and report.

Numbers such as "No deployments" are not a failure: they show what GitHub
holds for the history.

Then go on to step 10.

## Step 10. Tell the person it is done

Tell them, in one message:

- what changed: the installation `OWNER/REPO` went from `VERSION` to
  `LATEST` (or: it was already at `LATEST`), the commits you made (each with
  its short sha and what it changed) or the pull request you merged, and the
  settings that changed with their old and new values;
- what they can check themselves: the page address (`REPORT`), whose footer
  names `LATEST` without its `v`, and its settings page (`REPORTsettings.html`);
- what their auto-update choice means now: with `auto_update: true`, the next
  release within `auto_update_level` merges by itself (see Later); with
  `auto_update: false`, or beyond the level, Dependabot's pull request waits
  for them to merge it;
- that `agent-upgrade.md` can be run again for the next release, and that
  Going back undoes this upgrade.

Then leave the work folder and remove it, so you do not delete the folder
you are working in:

```
cd WORK/..
rm -r WORK
```

## Later: the next release

Nothing runs by itself at once. When the next forsgren release after `LATEST`
is out, Dependabot checks every day at 04:00 UTC and proposes it once it is as
old as the update wait (`default-days`, 3 by default). With `auto_update:
true` the pull request merges by itself when the step is within
`auto_update_level` (patch, minor or major), and `forsgren.yml` runs at once;
otherwise it waits for a person. The section "Later: the first auto-update"
of [agent-installer.md](agent-installer.md) lists the commands that check that
chain. An installation that kept its pins by hand, or whose level kept a
release waiting, is brought up to date by running this file again from the
top: run again whenever the page's footer says a newer release is available.

## Going back

Use this only when the person asks to undo the upgrade, for example after a
failed run in step 9. It undoes the files the upgrade changed, and nothing
else: the history `data/` the daily runs added since stays as it is. Never
force a branch back and never rewrite history; going back is a new commit.

1. What was changed: the commits of this upgrade are the ones you made in
   steps 6, 7 and 8 (or the merge of step 6, route 6a). `BEFORE` is the head
   of the branch just before the first of them:
   `gh api repos/OWNER/REPO/commits/FIRSTCOMMIT --jq .parents[0].sha`
   (with `FIRSTCOMMIT` the oldest of the upgrade's commits). The files to
   restore are those the upgrade's commits list: the two caller files, and
   `.github/dependabot.yml` and `forsgren.config.yml` when steps 7 and 8
   changed them. Restore `forsgren.config.yml` too whenever it gained a key:
   the older forsgren stops on an unknown key, and the run would fail again.
2. Ask the person, naming the files and the versions:

   > Reply "go: restore the files of OWNER/REPO to BEFORE, which moves
   > the pins from LATEST back to VERSION" to let me commit it.

   A bare "go": show the sentence again and wait.
3. Read each file at `BEFORE` and commit it as route 6b of step 6 does, in
   one commit: items 1 and 4 to 7, with the contents read with
   `?ref=BEFORE` as the source (not `WORK/new/`), the message
   `forsgren: go back from LATEST to VERSION`, no `Co-Authored-By` and no
   other trailer, and the branch moved without force. A branch that moved:
   stop and report.
4. The read back as in step 6: the head is the new commit, each restored file
   equals its content at `BEFORE`, and both pins read the `VERSION` commit.
   Then run step 9's items 1 to 5 once, to see the older version publish.

A pull request of Dependabot that the upgrade merged is not reopened; the
next daily check proposes the release again when the person wants it.
