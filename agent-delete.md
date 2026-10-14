# Removing forsgren: instructions for an AI coding agent

You are an AI coding agent. A person pointed you at this file because they
have a forsgren installation (a GitHub repository of their own, the **data
repository**, that publishes the DORA metrics of their repositories as a page
on GitHub Pages) and want it removed: the page, its custom domain if it has
one, and the repository with its history. Installing is a different job: see
[agent-installer.md](agent-installer.md); bringing an installation up to the
latest release is [agent-upgrade.md](agent-upgrade.md).

Follow **only this file**, from the top, in order. Do not use other guides,
your memory of forsgren, or other installations as a source. Removing is the
one job of the three that cannot be undone: a deleted repository and its
history are gone. So every step reads first, and nothing is changed before the
person has replied with the go-sentence of step 3.

Tested with: not yet tested. The first proof run follows (forsgren#174).
Start your agent with the model the other two files name (in Claude Code:
`claude --model sonnet`).

## Before you start (for the person)

1. Open a new terminal in an empty folder, for example
   `mkdir -p /tmp/forsgren-delete && cd /tmp/forsgren-delete`. An empty
   folder means no other project's instructions are loaded. The agent keeps
   its work files in a folder inside it, and a download of your data, when you
   ask for one, next to that folder. When Claude Code asks "Quick safety
   check: Is this a project you created or one you trust?" for this new
   folder, the empty folder you just made is safe: choose "Yes, I trust this
   folder".
2. Start the agent: `claude --model sonnet`.
3. If Claude Code asks "Teach auto mode about your environment?", choose
   "Not now". Do not choose "Don't show again", which changes your settings
   for every session.
4. Then tell the agent: "Remove my forsgren installation by following
   https://github.com/yveshanoulle/forsgren/blob/main/agent-delete.md".
   The agent asks you for one thing: the address of your forsgren report, the
   page it publishes. Everything else it finds out itself, and it shows you
   what will go before anything is changed.

In Claude Code's auto mode, deleting a repository can be blocked when it was
not asked for in so many words; the go-sentence the agent asks for in step 3
is that request.

## How to work through this file

- **Do every step in order.** Each step says what to do, the exact command,
  how to check that it worked, and what to do when it fails.
- **When a step fails, stop.** Show the person the step number, the exact
  command and its exact output, and say which check failed. Do not retry with
  another command, do not work around it, do not guess a fix. The rule of this
  file is: when a step fails, the file is fixed, and the removal starts again
  from the top; every step reads the state again, so a step already done is
  seen as done.
- **A wait is not a failure.** Some steps wait for GitHub or DNS. They say how
  long to wait and what to do when the wait runs out.
- **Placeholders.** Commands use these words in capitals. Replace each with
  its value before you run the command, everywhere, every time:
  - `REPORT`: the address of the person's report (step 1).
  - `OWNER`: the account or organisation that owns the data repository.
  - `REPO`: the data repository's name. `OWNER/REPO` is the two together.
  - `CANDIDATE`: a repository's full name, `owner/name` (step 2).
  - `BRANCH`: the data repository's default branch (step 2).
  - `DOMAIN`: the custom domain, when the report has one (step 2).
  - `PARENT`: the domain verified for GitHub Pages: `DOMAIN` itself for an
    apex domain (`example.com`), the domain one level up for a subdomain
    (`forsgren.example.com` gives `example.com`) (step 2).
  - `START`: the folder the person started you in, an absolute path (step 1).
  - `WORK`: your work folder, `START` followed by `/forsgren-work` (step 1).
- **Names made by a command.** `LOGIN` stands for the login a command printed
  (step 1). `PUT` and `DELETE` in a command are HTTP methods, and `TXT` in a
  `dig` command is the DNS record type: write them as they are.
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
- Never delete, archive, change or open anything in `yveshanoulle/forsgren` or
  in `yveshanoulle/forsgren-template`. You only read them. These are two exact
  names: a repository named `forsgren` under another owner is an
  installation, not forsgren itself, and it may be the one you remove.
- Never delete or archive a repository that step 2 did not find to be a
  forsgren installation, or any repository other than the one the go-sentence
  of step 3 names.
- Never change anything before the person has replied with the go-sentence of
  step 3. A change made without it is a failure of this file.
- Never delete anything, except the repository and its page named in that
  go-sentence, and the work folder `WORK` this file creates. A download of
  step 4 is the person's: never remove it.
- Never force-push, and never rewrite history in any repository.
- Never change a DNS record or a token yourself: those are the person's steps
  (step 6).
- Never install tools. When a tool is missing, stop and tell the person.
- Never change the person's git or gh configuration. When a step needs it,
  the person runs the command.
- When a permission check blocks a command (for example Claude Code's auto
  mode denies a deletion), stop and report the command and the reason it gave.
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
     `Token scopes:` contains `'repo'`. The token itself is shown masked;
     never try to show it unmasked.
   - Not logged in: stop. **Person:** run `gh auth login` in their own
     terminal, then start again at step 1.
   - `'repo'` missing: stop. **Person:** run
     `gh auth refresh -h github.com -s repo` in their own terminal, then start
     again at step 1.
   - Note whether `Token scopes:` contains `'delete_repo'`. It usually does
     not: deleting a repository needs that scope, and step 5 has the person
     add it. Do not ask for it now.
3. `gh api user --jq .login`
   - Works: it prints the login. It is the person's account.
4. `command -v curl` and `command -v dig`
   - Works: each prints a path. `curl` reads the report, `dig` the DNS.
   - Fails: stop and tell the person.
5. `pwd`
   - Works: it prints the folder the person started you in, an absolute path.
     That is `START`. `WORK` is `START` followed by `/forsgren-work`, for
     example `/tmp/forsgren-delete/forsgren-work`.
6. **Ask the person one thing:** "What is the address of your forsgren report,
   the page it publishes?" For example
   `https://acme.github.io/forsgren-metrics/` or `https://forsgren.example.com/`.
   That address is `REPORT`; write it with a final `/`. Ask nothing else yet:
   step 2 finds the rest out, and step 3 asks only what is the person's to
   decide.

git is not needed: this file changes nothing through git, so there is no
clone and no git credential to set up.

## Step 2. Find the installation from its report

Read the report first, then the repository it comes from. This step only
reads.

1. The footer names the running forsgren version:
   `curl -fsS REPORT | grep -o 'Forsgren</a> [0-9.]*'`
   - Works: it prints `Forsgren</a>` and a version. Write it down.
   - Empty answer, or a 404: the page may already be gone (a removal that
     stopped half-way). Do not stop yet: ask the person for `OWNER/REPO`
     and go on at item 3's check with it.
2. The page address gives the repository:
   - `https://OWNER.github.io/REPO/`: `OWNER` is the host's first part and
     `REPO` the first path part. There is no custom domain.
   - A custom domain (any other host): that host is `DOMAIN`. Search the
     person's repositories for the one whose Pages custom domain is that host:
     `gh api 'user/repos?per_page=100' --paginate --jq '.[].full_name'`
     then, for each full name as `CANDIDATE`,
     `gh api repos/CANDIDATE/pages --jq .cname` (a 404 means that repository
     has no page). Also search the organisations the login belongs to
     (`gh api user/orgs --jq '.[].login'`, then
     `gh api 'orgs/CANDIDATE/repos?per_page=100' --paginate --jq '.[].full_name'`
     with the organisation as `CANDIDATE`). Go through every repository, not
     only to the first match, and write down two things: the repository whose
     custom domain is `DOMAIN` (that is `OWNER/REPO`; more than one, or none:
     stop and ask the person for `OWNER/REPO`), and every other repository
     whose custom domain is `PARENT` or ends in `.PARENT`. Those others are
     the person's other sites on that domain; step 6 needs them.
   - `OWNER/REPO` may be `OWNER/forsgren`: an installation can carry the
     tool's name. That is the installation, not forsgren itself.
   - Refuse only these two names, exactly `yveshanoulle/forsgren` or
     `yveshanoulle/forsgren-template`: they are the tool and its template,
     never an installation. Stop and report; this file never removes them.
     Any other name, whatever it contains, goes on.
3. The repository:
   `gh api repos/OWNER/REPO --jq '.full_name,.visibility,.archived,.default_branch,.permissions.admin,.size'`
   - Works: six lines. The fourth is `BRANCH`. The fifth must be `true`: only
     an administrator of the repository can delete it. `false`: stop and
     report; the person who administers it has to run this file. The sixth is
     the repository's size in kilobytes, for step 3.
   - `true` on the third line: the repository is already archived. Say so in
     step 3; it can still be deleted.
   - A 404: stop and report; the repository is already gone or the login
     cannot see it.
4. It is a forsgren installation:

   ```
   mkdir -p WORK
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/.github/workflows/forsgren.yml \
     > WORK/forsgren.yml
   grep -n 'uses:' WORK/forsgren.yml
   grep -n 'FORSGREN_TOKEN:' WORK/forsgren.yml
   ```

   - The first `grep` prints one line that calls
     `yveshanoulle/forsgren/.github/workflows/metrics.yml@` a 40-hex commit.
     Anything else, or a 404 for the file: stop and report; this repository is
     not a forsgren installation, and this file does not remove it.
   - The second `grep` gives the token route: `secrets.FORSGREN_TOKEN` is
     route B, a fine-grained token the person made; `secrets.GITHUB_TOKEN` is
     route A, the run's own token, with nothing for the person to revoke.
5. What the history holds:
   `gh api repos/OWNER/REPO/contents/data --jq '.[].name'`
   lists the files in `data/` (a 404: there is no `data/` yet). And when it
   started:
   `gh api 'repos/OWNER/REPO/commits?path=data&per_page=1' --jq '.[0].commit.author.date'`
   is the newest data commit, and
   `gh api 'repos/OWNER/REPO/commits?per_page=100' --paginate --jq '.[-1].commit.author.date'`
   prints one date per page of commits, the last line being the oldest
   commit's. Write down the files and the two dates.
6. Its page:
   `gh api repos/OWNER/REPO/pages --jq '.html_url,.cname,.https_enforced'`
   - Works: the page address, the custom domain (`null` when there is none)
     and whether HTTPS is enforced. With a custom domain the second line is
     `DOMAIN`.
   - A 404: the page is already switched off. Note it; step 5 skips its
     page items.
7. The custom domain's DNS, only when there is a `DOMAIN`:

   ```
   dig +short DOMAIN
   dig +short TXT _github-pages-challenge-OWNER.PARENT
   ```

   The first prints `OWNER.github.io.` (lower case) and `185.199.` addresses
   for a subdomain, or four `185.199.` addresses for an apex domain: the
   record that points the domain at GitHub Pages. The second prints the
   verification record, a value in double quotes, or nothing when `PARENT`
   was verified under another name. Write both down; step 6 and step 7 use
   them. Neither is a failure: this step only reads.

Then go on to step 3.

## Step 3. Show what will go, ask, and wait for the go

Say it all together, in one message, before anything is changed. Fill in
every value from step 2. Never show the person a placeholder such as `OWNER`
or `DOMAIN`.

1. **What will go.** The repository `OWNER/REPO` (its visibility, its size),
   with all its history in `data/`: the files of step 2 item 5, collected from
   the oldest date to the newest. Deleting a repository cannot be undone: its
   history cannot be recovered afterwards, by you, by the person, or by
   forsgren. Also its page at `REPORT`, its custom domain `DOMAIN` (when
   there is one), its daily run, and, on route B, the `FORSGREN_TOKEN`
   secret stored in it.
2. **The choice**, numbered, with the default named:
   - **1. Delete (the default).** The page goes, then the repository with its
     history. This is what the person asked for, and it leaves nothing behind
     that still runs, costs or holds the domain.
   - **2. Archive.** The page goes, the repository stays, read-only, with its
     history; the daily run stops. For a person who may want the history
     later. The repository can be deleted later by running this file again.
   - **Download first** (yes or no, default yes). Before the delete, a copy of
     the repository as it is now (`data/`, `forsgren.config.yml` and the
     workflow files, without the git history) is saved to
     `START/OWNER-REPO.tar.gz`, outside the work folder, and kept. It costs
     a few seconds and is the only way back after a delete; the person
     removes it when they no longer want it.
3. **What the person will do themselves** (step 6): when deleting needs it,
   add the `delete_repo` scope to their gh login with one command (step 5);
   with a custom domain, remove the DNS record for `DOMAIN` at their DNS
   provider, and decide whether the verification record of `PARENT` stays
   (it stays when another of their sites uses that domain: name those sites
   from step 2 item 2); on route B, delete the fine-grained token
   `forsgren OWNER/REPO`.

End the message with the go-question for the default, with the values filled
in, and the "and its custom domain DOMAIN" part only when there is one:

> Reply "go: delete OWNER/REPO, its page and its custom domain DOMAIN" to let me delete it.

For an archive, the sentence is:

> Reply "go: archive OWNER/REPO, switch off its page and remove its custom
> domain DOMAIN" to let me archive it.

Say in the same message that a reply of "no download" leaves out the
download.

Wait for that reply, the sentence as shown, filled in. A bare "go", a go that
names another repository, or any other reply that does not name the
repository: show the sentence again and wait. Nothing is changed before that
reply.

Then go on to step 4.

## Step 4. Download the repository first, when chosen

Not chosen: skip this step and go on to step 5 (the reply said "no download").

The copy goes into `START`, next to the work folder and not in `WORK`, which
step 8 removes:

```
gh api repos/OWNER/REPO/tarball/BRANCH > START/OWNER-REPO.tar.gz
tar -tzf START/OWNER-REPO.tar.gz | grep -c '/data/'
```

- Works: the second command prints a number above `0` (the files of
  `data/`, with the folder itself). A repository with no `data/` prints `0`:
  that is right when step 2 item 5 found none.
- Fails, or `0` when step 2 found files in `data/`: stop and report. Nothing
  is deleted without the copy the person chose.

Then go on to step 5.

## Step 5. Remove the custom domain and the page, then the repository

Only after the go of step 3. In this order, each read back before the next:
the custom domain first, so the domain is released while the repository still
exists, then the page, then the repository.

1. **The custom domain**, only when step 2 item 6 printed one:

   ```
   gh api -X PUT repos/OWNER/REPO/pages -F cname=null
   gh api repos/OWNER/REPO/pages --jq .cname
   ```

   - Works: the second command prints `null` or an empty line.
   - Fails, or it still prints `DOMAIN`: do not just stop. **Person:** open
     `https://github.com/OWNER/REPO/settings/pages`, under Custom domain
     click Remove, and tell you when the page shows the github.io address
     again. Then read it back with the second command. Still `DOMAIN`: stop
     and report.
2. **The page**, unless step 2 item 6 found it already off:

   ```
   gh api -X DELETE repos/OWNER/REPO/pages
   gh api repos/OWNER/REPO/pages
   ```

   - Works: the first prints nothing; the second fails with `Not Found`
     (HTTP 404): the page is switched off.
   - The first fails, or the second still answers: stop and report.
3. **Archive** (the person chose 2): `gh repo archive OWNER/REPO --yes`, then
   read back `gh api repos/OWNER/REPO --jq .archived`: it prints `true`.
   Anything else: stop and report. Go on to step 6.
4. **Delete** (the default). Check the scope first: `gh auth status`, and
   look for `'delete_repo'` on the `Token scopes:` line.
   - Missing (the usual case): **Person:** run, in their own terminal,

     ```
     gh auth refresh -h github.com -s delete_repo
     ```

     and follow what it asks (a code in the browser), then tell you it is
     done. Check `gh auth status` again: `'delete_repo'` is now there. Still
     missing: stop and report.
5. Delete it:

   ```
   gh repo delete OWNER/REPO --yes
   ```

   Works: it says the repository was deleted. Fails: stop and report its
   output.
6. Read back; do not trust the answer of the command:
   `gh repo view OWNER/REPO`
   fails with `Could not resolve to a Repository`. The repository still
   shows: stop and report.

Then go on to step 6.

## Step 6. What the person does themselves (Person)

Hand the person the items that apply, together, in one message, with the
values filled in, and wait until they say each is done.

> **Person:**
>
> 1. **The DNS record** (only with a custom domain): at your DNS provider,
>    remove the CNAME record for `DOMAIN` (or the four A records to
>    `185.199.` addresses, for an apex domain). Do this first, before
>    anything about the verification: a record that points at GitHub Pages
>    with no site behind it can be taken by someone else's repository while
>    the domain is not verified.
> 2. **The verification** (only with a custom domain, and only after 1): the
>    TXT record `_github-pages-challenge-OWNER.PARENT` and the verified domain
>    `PARENT` in your profile's **Settings** → **Pages**. Keep both when
>    another of your sites uses that domain (these: the list from step 2), or
>    when you may use the domain for GitHub Pages again. With
>    no other site on it, they may go: remove `PARENT` from Settings → Pages
>    (its **...** menu), then the TXT record at your DNS provider.
> 3. **The token** (route B only): on github.com, your profile picture →
>    **Settings** → **Developer settings** → **Personal access tokens** →
>    **Fine-grained tokens**, open `forsgren OWNER/REPO`, and **Delete** it.
>    It read your measured repositories and is no longer needed. The
>    `FORSGREN_TOKEN` secret is gone with the repository: there is nothing to
>    do for it (on an archive, it stays in the archived repository, unused).
> 4. **The delete scope** (when you added it in step 5): you may take it off
>    your gh login again, in your own terminal:
>    `gh auth refresh -h github.com -r delete_repo`.
>
> Tell me when they are done, and which of 2 you chose.

You cannot check the token or the verified domain: there is no command that
lists them. Those two rest on the person's word; say so in step 8. The DNS
records you check in step 7.

Then go on to step 7.

## Step 7. Check the page and the domain

GitHub Pages can serve a page for some minutes after it is switched off: when
a check below shows the old state, wait 1 minute and run it again, at most 10
times, before you report it.

1. The page:
   `curl -sS -o /dev/null -w '%{http_code}' REPORT`
   prints `404`. With a custom domain whose DNS record is already removed,
   `curl` cannot reach the host at all and prints `000` with an error: that
   is gone too. A `200` after the retries: stop and report.
2. With a custom domain, the github.io address as well:
   `curl -sS -o /dev/null -w '%{http_code}' https://OWNER.github.io/REPO/`
   prints `404`.
3. With a custom domain, the DNS record no longer points at GitHub, through
   the local resolver and through a public one:

   ```
   dig +short DOMAIN
   dig +short @1.1.1.1 DOMAIN
   ```

   - Works: neither prints `OWNER.github.io.` nor a `185.199.` address.
   - Still there: DNS has not caught up (the record's time to live). Wait 5
     minutes and check again, at most 12 times (an hour). Still there: a
     wait, not a failure. Tell the person, and to ask you to resume at step 7
     later; DNS can take up to 24 hours.
4. When the person removed the verification (step 6, item 2):
   `dig +short TXT _github-pages-challenge-OWNER.PARENT` prints nothing,
   after the same wait as item 3. When they kept it: it still prints the
   value of step 2.

Then go on to step 8.

## Step 8. Tell the person it is done

Tell them, in one message:

- what was removed: the repository `OWNER/REPO` (deleted, or archived), its
  page at `REPORT`, its custom domain `DOMAIN` when there was one;
- where the copy is, when step 4 made one: `START/OWNER-REPO.tar.gz`, theirs
  to keep or delete;
- what you checked (step 7: the page answers 404, the DNS record no longer
  points at GitHub) and what rests on their word (the token deleted, the
  verified domain kept or removed);
- what stays: on an archive, the repository with its history, read-only;
  a verification record they chose to keep.

Then leave the work folder and remove it, so you do not delete the folder
you are working in:

```
cd WORK/..
rm -r WORK
```
