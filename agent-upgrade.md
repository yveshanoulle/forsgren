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
