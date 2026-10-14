# Upgrading forsgren: instructions for an AI coding agent

Work in progress (forsgren#166): not ready to follow yet.

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

### Before you start (for the person)

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
  - `WORK`: your work folder, the absolute path of `forsgren-work` inside
    the folder the person started you in (step 1).
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
  `yveshanoulle/forsgren-template`. You only read them.
- Never commit anything before the person has replied with the go-sentence of
  step 5. A commit made without it is a failure of this file.
- Never force-push, and never rewrite history in any repository.
- Never put a `Co-Authored-By` line, or any other line naming a tool, in a
  commit message you write.
- Never change the person's data: not `data/`, and not `forsgren.config.yml`
  beyond the keys the person chose in step 5.
- Never lower a pin: you only move it to a newer release.
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
   - The settings page exists from forsgren 0.5.0. A 404, or an answer that
     is not that table (an installation older than 0.8.6 shows a different
     layout), is not a failure: the repository's `forsgren.config.yml` (item
     4) is then the source of the current settings.
3. The page address gives the repository:
   - `https://OWNER.github.io/REPO/`: `OWNER` is the host's first part and
     `REPO` the first path part.
   - A custom domain (any other host): search the person's repositories for
     the one whose Pages custom domain is that host:
     `gh api 'user/repos?per_page=100' --paginate --jq '.[].full_name'`
     then, for each name,
     `gh api repos/NAME/pages --jq .cname` until one prints the host. Also
     search the organisations the login belongs to
     (`gh api user/orgs --jq '.[].login'`). More than one match, or none:
     stop and ask the person for `OWNER/REPO`.
   - Check: `gh api repos/OWNER/REPO/pages --jq '.html_url,.cname'` prints
     `REPORT` (the address, with or without the custom domain).
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
and the same four items work: read, write down, ask, apply the chosen answers.

Then go on to step 5.
