# Installing forsgren: instructions for an AI coding agent

You are an AI coding agent. A person pointed you at this file because they
want their own forsgren installation: a GitHub repository of their own (the
**data repository**) that measures the DORA metrics of their repositories once
a day and publishes them as a page on GitHub Pages. forsgren's own
install, which measures forsgren itself, is such a page:
https://forsgren.forsgren.be.

Follow **only this file**, from the top, in order. Do not use other guides,
your memory of forsgren, or other installations as a source. The full
reference is forsgren's [README](README.md) and the docs it lists; this file names the parts of it
you need.

Tested with: forsgren v1.3.3, Claude Code, model claude-sonnet-5-5.
Start your agent with that model (in Claude Code: `claude --model sonnet`).

## Before you start (for the person)

1. Open a new terminal in an empty folder, for example
   `mkdir -p /tmp/forsgren-install && cd /tmp/forsgren-install`. An empty
   folder means no other project's instructions are loaded. The agent
   keeps its work files in a folder inside it. When Claude Code asks
   "Quick safety check: Is this a project you created or one you trust?"
   for this new folder, the empty folder you just made is safe: choose
   "Yes, I trust this folder".
2. Start the agent with the tested model: `claude --model sonnet`.
3. If Claude Code asks "Teach auto mode about your environment?", choose
   "Not now". This file gives the agent everything it needs, and extra
   knowledge about your machine can hide a missing step and make the
   install harder to repeat. Do not choose "Don't show again", which
   changes your settings for every session.
4. Then tell the agent: "Install forsgren for me by following
   https://github.com/yveshanoulle/forsgren/blob/main/agent-installer.md".

In Claude Code's auto mode, a commit or a repository creation can be blocked
when it was not asked for in so many words; the go-sentence the agent asks
for in step 4 is that request.

## How to work through this file

- **Do every step in order.** Each step says what to do, the exact command,
  how to check that it worked, and what to do when it fails.
- **When a step fails, stop.** Show the person the step number, the exact
  command and its exact output, and say which check failed. Do not retry
  with another command, do not work around it, do not guess a fix. The rule
  of this file is: when a step fails, the install is deleted (see Starting
  over), this file is fixed, and the install starts again from the top.
- **A wait is not a failure.** Some steps wait for GitHub or DNS. They say how
  long to wait and what to do when the wait runs out.
- **Placeholders.** Commands use these words in capitals. Replace each with
  its value before you run the command, everywhere, every time:
  - `OWNER`: the account or organisation that owns the data repository.
  - `REPO`: the data repository's name. `OWNER/REPO` is the two together.
  - `VERSION`: the forsgren release the data repository pins, such as
    `vX.Y.Z` (step 8).
  - `SITE`: the page's address, ending with `/` (step 7).
  - `DOMAIN`: the custom domain, when the person wants one.
  - `PARENT`: the domain verified for GitHub Pages (step 13).
  - `WORK`: your work folder, the absolute path of `forsgren-work` inside
    the folder the person started you in (step 1).
  - `acme/app`: a repository to measure.
- **Write values into each command.** Do not rely on shell variables or a
  changed directory carrying over from one command to the next; use the
  absolute paths given here.
- **The person does some steps themselves.** They are marked **Person**.
  Hand the person the text or command as written, wait until they say it is
  done, then do the check yourself.

## What you must never do

- Never name a private repository in a public place: not in a public
  repository's files, commits or issues, and not on the page. The page shows
  project names and labels, so a project name must not be a private
  repository's name either.
- Never print, log, store, commit or ask to see a token. Never run
  `gh auth token`. The person creates the token and sets the secret
  themselves (step 10B).
- Never offer to run a command that sets a secret or token inside your own
  session: no `!` shortcut, and never ask for the token to be pasted to you.
  The person runs it in a separate terminal window, because the token would
  land in the conversation.
- Never push, commit or open anything in `yveshanoulle/forsgren` or in
  `yveshanoulle/forsgren-template`. You only read them.
- Never force-push, and never rewrite history in any repository.
- Never delete anything, except the install the person asked to start over
  (see Starting over), and the work folder `WORK` this file creates.
- Never install tools. When a tool is missing, stop and tell the person.
- Never let a DNS record point at GitHub Pages for a domain that is not
  verified (steps 13 and 15), and never ask anyone to delete the
  verification TXT record.
- Never change the person's git or gh configuration. When a step needs it,
  the person runs the command.
- When a permission check blocks a command (for example Claude Code's auto
  mode denies a commit), stop and report the command and the reason it
  gave. Never suggest a permission rule or a settings change, and never ask
  the person to run the command by hand: both bypass what this file tests.
  The way forward is Starting over, so this file can be fixed.

## Step 1. Check the prerequisites

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
     then start again at step 1. (`workflow` is needed because step 10A
     changes a file under `.github/workflows/`.)
3. `gh api user --jq .login`
   - Works: it prints the login. That login is the default `OWNER`.
4. `command -v curl`
   - Works: it prints a path. `curl` checks the published page (step 12).
   - Fails: stop and tell the person.
5. `go version` (optional)
   - Prints `go version go1.N...`: Go is there; step 9 checks the config
     with it. Go 1.21 or later is needed (it fetches the Go version forsgren
     asks for by itself).
   - Not found or older: note it. Do not install Go. Step 9 then leaves the
     check to the first run.
6. `pwd`
   - Works: it prints the folder the person started you in, an absolute
     path. The person made it empty for this install ("Before you start"),
     so your work files can live inside it, where Claude Code reads and
     writes without asking. `WORK` is that path followed by
     `/forsgren-work`, for example `/tmp/forsgren-install/forsgren-work`.

git is not needed: every change this file makes goes through `gh api`, so
there is no clone, no push and no git credential to set up.

## Step 2. Ask the person every question, in one message

Ask all of these together, before anything is created. Give each default and
why. Show every default with the values you already know filled in: the
login from step 1.3 for `OWNER`, and `forsgren-metrics` for `REPO` (for
example `https://acme.github.io/forsgren-metrics/` for the login `acme`).
Never show the person a placeholder such as `OWNER` or `REPO`.

End the message with this line, word for word:

> Reply with your answers by number, for example '3: project Acme Shop
> with acme/api'. Reply 'defaults' to take every default; question 3 has
> no default, so add your repositories: 'defaults, and 3: …'.

Then wait for the answers.

1. **Owner of the data repository.** Default: the login from step 1.3. It
   can be an organisation where the person may create repositories.
2. **Repository name.** Default: `forsgren-metrics`, because it names
   the tool first, as `forsgren.<your domain>` does, and says what the
   repository and its page hold. Any free name works; it must not
   exist yet under the owner.
3. **The repositories to measure, grouped in projects.** No default. A
   project is a name and the repositories that ship it, each as
   `owner/name`, for example project `Acme Shop` with `acme/api` and
   `acme/ios-app`. Project names are shown on the public page, so choose
   names that may be public. Each repository is listed once in the whole
   file.
4. **What counts as a deployment, per repository.** Default: "find out"
   (you check in step 3 and propose). The three kinds:
   - `environment=production` (the default kind): a GitHub Deployment to
     the environment `production` with a success status. Use it when the
     repository's deploy jobs create GitHub Deployments, which show on the
     repository's front page under "Deployments". `environment=<name>` names
     another environment.
   - `workflow=<file>.yml`: a successful run on the default branch of that
     workflow, by its file name in `.github/workflows/`. Use it when a
     workflow deploys (for example uploads to TestFlight) without GitHub
     Deployments.
   - `release`: a published GitHub Release (not a draft, not a
     prerelease). Use it for apps and tools that ship as releases.
5. **Public or private data repository.** Default: public when every
   measured repository is public; private otherwise. Why:
   - The data repository's `forsgren.config.yml` and `data/` name every
     measured repository, so **it must be private when any measured
     repository is private**. This is not a choice.
   - A public data repository lets the daily run read the measured
     repositories with its own token, so the person makes no token
     (step 10A).
   - GitHub Pages on a private repository needs a paid GitHub plan, and its
     page is still public.
6. **View**, the page the site's root shows. Default: `standard`, the DORA
   bands, the easiest to read. `numbers` shows the raw values and `scoring`
   the DORA Quick Check scores. Every view is also its own page.
7. **Auto-update.** Default: `auto_update: true` with
   `auto_update_level: major`, as forsgren's own starter has it. `major`
   permits major, minor and patch updates; it does not mean a major release
   is safe. Eligible releases are merged automatically, unless the update
   fails or is blocked. What the safeguards check: a release is only cut
   when forsgren's Quality checks are green, Dependabot proposes it only
   after the update wait, and the merge goes through only when the pull
   request changes nothing but the forsgren pin to a published release.
   Nothing checks a release against this installation's own data. Patch
   updates are intended for fixes; minor updates can introduce new
   behaviour. With `auto_update: false` the person merges each update by
   hand.
   Also ask for the **update wait**: how many days old a forsgren release
   must be before Dependabot proposes it. Default: `3`; `0` means as soon
   as it is released. A few days lets a broken release be noticed first.
8. **history_days**, how far back the history goes. Default: `365`. A whole
   number from 30 to 1825. forsgren reads it in chunks of 100 days, one more
   chunk per daily run, so a deeper history fills in over several days.
9. **Custom domain or the github.io address.** Default: no custom domain;
   the page is at `https://OWNER.github.io/REPO/` (fill in the owner and
   the name, with the default name for example
   `https://acme.github.io/forsgren-metrics/`), works at once and has
   HTTPS from the start. Show the person this recommendation as part of the
   question, not only the default: for a custom domain, use the
   conventional name `forsgren.<your domain>`, for example
   `forsgren.example.com`: like `www` for a website, a `forsgren.`
   subdomain tells anyone where the DORA page lives. forsgren's own
   install is at `forsgren.forsgren.be`. Other names work as well. A
   custom domain needs the person to verify the parent domain
   (`example.com`) for GitHub Pages first (a TXT record), unless it is
   verified already, then a DNS record they add at their DNS provider, and
   HTTPS can take up to a day after that.
10. **The Issues page and the Daily page**, which of the two the site
    shows. Default: `issues_page: false` (the Issues page is not generated)
    and `days_page: false` (the Daily page is not generated), as the
    starter writes them. Each is `true`
    (generated and in the menu), `unlisted` (generated, with no menu entry,
    and search engines are asked to skip it) or `false` (not generated). The
    person can put either page in the menu later by setting
    `issues_page: true` or `days_page: true`; the legend of the published
    site says so.
11. **The DORA window**, over how many days the five metrics count back.
    Default: `dora_days: 30`. One of 30, 90 or 180; DORA usually
    reports 180 days, so a person who wants to compare with other reports
    may want `180`. A longer window needs a `history_days` of at least as
    many days as the window (the default `history_days` of 365 is enough),
    and the history behind a longer window fills in over several daily runs.
    The person can change it later; the legend of the published site says
    which window is in use.
12. **The Numbers and scoring page**, whether the site has a page that
    shows, for each metric, its number and its score side by side in one
    cell. Default: `numbers_scoring_page: unlisted` (the page is generated,
    has no menu entry, and search engines are asked to skip it). It is
    `true` (generated and in the menu), `unlisted` or `false` (not
    generated). The person can open an unlisted page at its address,
    `numbers-scoring/`, to look at it, and set `numbers_scoring_page: true`
    to put it in the menu; the legend of the published site says so.
13. **The History page**, whether the site has a page that shows the five
    metrics for every half-year (January to June, July to December) and
    for the last 6 months, a table and a small chart per row, to see
    whether delivery improved. Default: `history_page: unlisted` (the page
    is generated, has no menu entry, and search engines are asked to skip
    it). It is `true` (generated and in the menu), `unlisted` or `false`
    (not generated). The person can open the unlisted page at its address,
    `history.html`, to look at it, and set `history_page: true` to put it in
    the menu. Tell the person that the page fills in over several daily
    runs, because each run reads one
    more chunk of history, and that the default `history_days` of 365 gives about one half-year
    besides the last 6 months, while `history_days: 1825` (5 years) gives up
    to ten half-years; they can raise it now or later. The person can change
    `history_page` later; the legend of the published
    site says so.

14. **Several accounts.** Does anyone commit with more than one GitHub
    account, or through an assistant account? Default: no. If yes, ask for
    the logins (they are in the `author` column of `data/commits.csv` once
    there is data, or in the repository's commit list on GitHub), show the
    `same_developer` lines you would write, such as
    `same_developer: [[maintainer, assistant-account]]`, and write them
    only with the person's yes. The key is described in
    [docs/configuration.md](docs/configuration.md).
15. **Services and their folders.** Only for a repository whose one deployment
    rule ships several things, such as an API, an admin site and an app, each
    its own row on the TBD page (the `services:` key: a deployment task, the
    `task` of its deployments, and a label). Default: no `services`, no rows.
    If the person wants them, ask for each service's label and which folders
    each service is built from, in the repository's own layout, for example
    `api/` and `shared/` for the API. A person who does not know them says
    so: you look and propose in step 3 (item 5), from the deploy workflow,
    and the person says yes, edits it, or skips it. A folder ends in `/`; a file is written
    with its folders and matches exactly; no glob, no absolute path, no `..`.
    A folder two services share, such as `shared/`, is listed in each service
    that uses it, and `shared/` only where the person lists it: forsgren
    guesses nothing. Files in the root of the repository (`.github/`, `go.mod`,
    `Scripts/`, `docs/`) count for no service. Say that a service with no
    folders shows `Per repository` for its Time to deploy per commit and its
    Commits per deployment, and that forsgren then reads the files of each
    commit once (it needs Contents read on the token). Show the `services`
    lines you would write and write them only with the person's yes. The key
    is described in [docs/configuration.md](docs/configuration.md).
16. **Several ways to deploy.** Ask whether a repository deploys in more than
    one way, such as releases and a website published to GitHub Pages. Default:
    no, one `deployment` rule. If yes, ask for each way: what counts as a
    deployment (`release`, `workflow=<file>.yml` or `environment=<name>`), the
    label of its row, and, as in question 15, the folders it is built from.
    A way with no folders shows `Per repository` for its Time to deploy per
    commit and its Commits per deployment. Show the `deployments:` lines you
    would write, for example `release: Releases` and
    `environment=github-pages: {label: Website, paths: [website/]}`, and write
    them only with the person's yes. Whatever the answer, in step 3 you list
    what GitHub records for each repository and, when more than one way is in
    use, propose the `deployments:` lines (item 5); the person says yes,
    edits it, or skips it. The key is described in
    [docs/configuration.md](docs/configuration.md).

## Step 3. Look at every measured repository (read only)

For every repository the person named, replacing `acme/app`:

1. `gh repo view acme/app --json visibility --jq .visibility`
   - Works: `PUBLIC`, `PRIVATE` or `INTERNAL`. Write it down. Treat
     `INTERNAL` as private.
   - `Could not resolve to a Repository`: stop. The name is wrong or the
     person's login cannot see it; ask the person to check it, then start
     again at step 2.
2. When the person said "find out", collect the evidence:
   - GitHub Deployments, per environment:
     `gh api repos/acme/app/deployments --jq '.[].environment'`
   - Workflows:

     ```
     gh api repos/acme/app/actions/workflows \
       --jq '.workflows[].path'
     ```
   - Releases:

     ```
     gh release list -R acme/app -L 5 \
       --exclude-drafts --exclude-pre-releases
     ```
3. Propose the kind, in this order:
   - Deployments to an environment exist: `environment=<that name>`
     (`production` when it is there).
   - Otherwise a workflow whose name or file says it deploys or publishes:
     `workflow=<its file name>`, without the `.github/workflows/` folder.
     Ask the person which workflow it is when more than one could be.
   - Otherwise published releases exist: `release`.
   - None of these: tell the person forsgren will find nothing to count for
     that repository, ask whether to keep it, and offer the help in item 4.
4. Nothing is found, or a deploy job has no environment (a workflow of item 2
   that deploys, whose deploy job has no `environment:` line). Offer the
   help below, each only with the person's yes, and say which repository it
   is for:
   - The deploy runs in a workflow job: propose `environment: production` on
     the deploy job, and show the lines. GitHub then records each deploy of
     that job as a deployment.
   - The deploy runs outside GitHub Actions: propose a record step after the
     deploy. It makes the two calls of
     [Giving a repository the deployments forsgren counts](docs/configuration.md#giving-a-repository-the-deployments-forsgren-counts)
     (made-up names `acme/app`): create a deployment for the commit that went
     live (`gh api repos/acme/app/deployments -f ref=COMMIT_SHA -f
     environment=production`, `ref` is the commit SHA), then a status
     `success` on it. The token that
     makes them needs the repository permission Deployments: Read and write,
     or `deployments: write` in the job's permissions.

   Only with the person's yes, and show the change as text. Never push to a
   product repository on your own: the person makes the change. When it is
   made, check that the next deploy shows:
   `gh api repos/acme/app/deployments --jq '.[0] | {environment, sha}'` names
   the commit that went live. Do not hold the setup for it: write the
   `deployment:` line the person chose and go on.

5. **Propose folders and rules**, for each repository with services (question
   15) and each repository that may deploy in more than one way (question 16).
   Look yourself, read-only, as in item 2 (replacing `acme/app`, `acme/site`
   and the file name):

   ```
   gh api -H 'Accept: application/vnd.github.raw' repos/acme/app/contents/.github/workflows/deploy-web.yml
   gh api repos/acme/app/contents --jq '.[] | select(.type == "dir") | .name'
   gh api 'repos/acme/site/deployments?per_page=100' --jq '.[] | [.environment, .task] | @tsv' | sort | uniq -c
   ```

   - **Folders of a service.** Read the workflow or workflows that deploy
     that service's task (the service key is the `task` of its deployments).
     Ask which workflow it is when more than one could be. Propose the
     folders from `on.push.paths` and `paths-ignore` (a `paths-ignore` entry
     is a folder to leave out, never one to add), the deploy job's
     `working-directory`, and the build context, such as the folder of a
     Dockerfile it builds. Show what you found and why, one line per place,
     and the exact line you would write, such as
     `deploy-web: {label: Web, paths: [web/, shared/]}`. Say in plain words
     when a proposal lists a shared folder, and that files in the root of
     the repository count for no service.
   - **Several ways to deploy.** Use what item 2 listed (Deployments by
     environment and task, releases, deploy workflows). When more than one
     source is in use, for example releases and a `github-pages`
     environment, propose a `deployments:` entry: each rule with a label,
     and `paths` where the folders above found them, for example
     `release: Releases` and
     `environment=github-pages: {label: Website, paths: [website/]}`. Say
     what changes on the page: each rule is its own row, with its own
     Deployments, and the total row counts every deployment of the
     repository; a rule without `paths` shows `Per repository` for its Time
     to deploy per commit and its Commits per deployment. `deployment:` and
     `deployments:` never both: the entry takes the place of the repository's
     `deployment:` line.

   The person says yes, edits it, or skips it, for each repository; the
   default is to skip. Write the lines in step 9 only with the person's yes.

Then decide the token route:

- **Route A**: every measured repository is `PUBLIC`. The data repository is
  public (unless the person chose private) and the daily run uses its own
  token. No personal token.
- **Route B**: at least one measured repository is private. The data
  repository is private, and the person makes a fine-grained token.
  - All private measured repositories must have **one owner**: a
    fine-grained token reads the repositories of one user or organisation
    (it reads every public repository besides). When they have more than
    one owner, stop: this file does not cover that case.

If the person chose public while a measured repository is private, tell them
the data repository must be private, and ask again.

## Step 4. Show the plan and wait for the go

Show the person, in one message:

- `OWNER/REPO`, public or private, and the token route (A or B).
- The full `forsgren.config.yml` you will write (step 9 shows its shape).
- The page address: `https://OWNER.github.io/REPO/`, or `DOMAIN`.
- The update wait, when it is not 3 (step 11 changes it).
- What they will do themselves: on route B the token and its secret
  (step 10B); with a custom domain the domain verification (step 13) and
  the DNS record (step 14).

End the plan with this go-question, with `OWNER/REPO` filled in, with
"and the forsgren.yml change" only on route A, and with "and the
dependabot.yml change" only when the update wait is not 3:

> Reply "go: create OWNER/REPO, switch on its Pages, and commit its
> forsgren.config.yml and the forsgren.yml change and the dependabot.yml
> change" to let me create the repository and commit to it.

Wait for that reply, the sentence as shown, filled in. A bare "go", or any
other reply that does not name these writes: show the sentence again and
wait. Any change to an answer: show the plan again. Nothing is created
before that reply.

## Step 5. Check the name is free and the template is there

1. `gh repo view OWNER/REPO`
   - Works (for this check): it prints `Could not resolve to a Repository`.
   - It shows a repository: stop. The name is taken; ask for another name
     and go back to step 4.
2. Run:

   ```
   gh repo view yveshanoulle/forsgren-template \
     --json isTemplate --jq .isTemplate
   ```

   - Works: `true`.
   - Anything else: stop and report.

## Step 6. Create the data repository from the template

For a public data repository:

```
gh repo create OWNER/REPO --public \
  --template yveshanoulle/forsgren-template
```

For a private one, the same with `--private` instead of `--public`.

Check:

1. It prints the new repository's URL, `https://github.com/OWNER/REPO`.
2. `gh api repos/OWNER/REPO/contents/.github/workflows --jq '.[].name'`
   prints `forsgren-update.yml` and `forsgren.yml`. GitHub copies the
   template's files a few seconds after the repository exists: on a 404 or an
   empty answer, wait 10 seconds and run it again, at most 6 times.
3. `gh repo view OWNER/REPO --json visibility --jq .visibility` prints the
   visibility from the plan.
4. `gh api repos/OWNER/REPO/actions/permissions --jq .enabled` prints
   `true`.

Fails: stop and report. The repository may exist now; the person decides
whether to start over.

## Step 7. Switch on GitHub Pages, built by GitHub Actions

```
gh api -X POST repos/OWNER/REPO/pages -f build_type=workflow
```

Check: `gh api repos/OWNER/REPO/pages --jq .build_type` prints `workflow`.
Then `gh api repos/OWNER/REPO/pages --jq .html_url` prints the page address,
`https://OWNER.github.io/REPO/` (the owner in lower case). That is `SITE`
until a custom domain is set.

Fails: stop and report. A private repository on a free GitHub plan is
refused here (Pages on private repositories needs a paid plan).

## Step 8. Read the pinned forsgren version and make a work folder

```
mkdir -p WORK
gh api -H 'Accept: application/vnd.github.raw' \
  repos/OWNER/REPO/contents/.github/workflows/forsgren.yml \
  > WORK/forsgren.yml
grep -n 'uses:' WORK/forsgren.yml
```

Check: one line, ending in `# vX.Y.Z`. That `vX.Y.Z` is `VERSION`.

Fails (no line, or more than one): stop and report.

## Step 9. Write forsgren.config.yml and check it

Write `WORK/forsgren.config.yml` with your file tool, from the
answers. Shape (the `acme` names stand for the person's):

```yaml
# forsgren configuration: what this installation measures.
# Reference: https://forsgren.be/#configuration
version: 1
view: standard
auto_update: true
auto_update_level: major
history_days: 365
dora_days: 30
issues_page: false
days_page: false
numbers_scoring_page: unlisted
history_page: unlisted
projects:
  - name: Acme Shop
    repositories:
      - name: acme/api
        deployment: environment=production
      - name: acme/ios-app
        deployment: workflow=testflight.yml
  - name: Acme Tools
    repositories:
      - name: acme/cli
        deployment: release
```

- Write `issues_page` and `days_page` with the answers to question 10
  (the defaults are `false` and `false`, as the starter writes them), and `dora_days` with the answer to
  question 11 (the default is `30`) and `numbers_scoring_page` with the
  answer to question 12 (the default is `unlisted`), and `history_page` with the
  answer to question 13 (the default is `unlisted`).
- Write `same_developer` (question 14) only when the person said yes to
  the lines you showed; otherwise leave the key out.
- Write `services` (question 15) only when the person said yes to the lines
  you showed, a service with folders in the long form, for example
  `deploy-api: {label: API, paths: [api/, shared/]}` under the repository's
  `services:`, and the short form `deploy-api: API` only for a service the
  person gave no folders. A repository has either `label` or `services`,
  never both.
- Write the lines the person accepted or edited in step 3 item 5, for
  `services` and `deployments:`; a proposal the person skipped is not written.
- Write `deployments:` (question 16) only when the person said yes to the
  lines you showed, in place of the repository's `deployment:` line: never
  beside `deployment`, `label` or `services`, each rule's value its label or
  `{label: ..., paths: [...]}`.
- Write every other repository's `deployment:` line, also for
  `environment=production`, so the file says what was chosen.
- Indent with spaces only, as shown.
- On a public data repository, check once more that every repository in
  the file was `PUBLIC` in step 3.

Check the file, when step 1.5 found Go:

```
go run github.com/yveshanoulle/forsgren/cmd/forsgren@VERSION \
  check-config --config WORK/forsgren.config.yml
```

- Works: one line, `OK: ... is a valid forsgren config (version 1):
  projects: N, repositories: M`, with N and M the counts of the plan.
  A `config: warning:` line, and `settings not accepted: K` after the
  counts, means forsgren does not accept a setting you wrote and uses its
  default instead; the check still passes. You wrote the file from the
  person's answers, so fix the value as the line asks, show the person the
  change, and run the check again.
- Fails: it prints one line saying what is wrong and where. You wrote the
  file in this step, so fix the file to what the line asks, show the person
  the change, and run the check again. Any other error (a download or Go
  error): stop and report.

Without Go: tell the person the file is checked by the first run (step 12),
which fails before it reads or publishes anything when the file is invalid
(a setting it does not accept is not that: it warns and uses the default).

## Step 10. The token

Do 10A on route A, 10B on route B. Never both.

### 10A. Route A: the run's own token (every measured repository public)

The daily run passes the secret `FORSGREN_TOKEN` to forsgren. On route A it
passes the run's own token instead, which reads public repositories. This
is a change to this one installation's `forsgren.yml`, not to the template.
It is to be confirmed by forsgren#131, the first install made with this
file: until then, the first run (step 12) is the proof.

1. In `WORK/forsgren.yml`, replace this line exactly:

   ```
         FORSGREN_TOKEN: ${{ secrets.FORSGREN_TOKEN }}  # read-only token for the measured repositories
   ```

   with these three lines (same indentation, six spaces):

   ```
         # Every measured repository is public: the run's own token reads
         # them. Copying the template's files over this one undoes it.
         FORSGREN_TOKEN: ${{ secrets.GITHUB_TOKEN }}
   ```

   Check: `grep -c 'secrets.GITHUB_TOKEN' WORK/forsgren.yml`
   prints `1`, and
   `grep -c 'secrets.FORSGREN_TOKEN' WORK/forsgren.yml`
   prints `0`. The line not found as written: stop and report.
2. Upload it as one commit:

   ```
   base64 < WORK/forsgren.yml | tr -d '\n' \
     > WORK/forsgren.yml.b64
   gh api repos/OWNER/REPO/contents/.github/workflows/forsgren.yml \
     --jq .sha
   ```

   The second command prints the file's current sha; use it as `SHA`:

   ```
   gh api -X PUT \
     repos/OWNER/REPO/contents/.github/workflows/forsgren.yml \
     -f message='Read the public repositories with the run token' \
     -F content=@WORK/forsgren.yml.b64 \
     -f sha=SHA --jq .commit.sha
   ```

   Works: it prints a commit sha. Then check the file on GitHub:

   ```
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/.github/workflows/forsgren.yml \
     | diff - WORK/forsgren.yml
   ```

   Works: no output. Fails (an error, or a diff): stop and report.

The run's own token has a limit of 1,000 GitHub API requests an hour. A
first run reads every issue of every measured repository once, so a very
large set can reach it. When the first run's collect step names a rate
limit, stop and report: the fix is route B.

### 10B. Route B: a fine-grained token, made by the person

You never see this token. Hand the person this text, with the values filled
in:

> **Person:** create a read-only token for forsgren.
>
> 1. On github.com: your profile picture → **Settings** → **Developer
>    settings** → **Personal access tokens** → **Fine-grained tokens** →
>    **Generate new token**.
> 2. **Token name:** `forsgren OWNER/REPO`.
> 3. **Expiration:** **Custom**, a date less than one year from today.
>    Never more than a year, and never "No expiration". Put the date in your
>    calendar: when it passes, the daily run fails until you make a new
>    token and set it again (step 3 below). forsgren reminds you as well:
>    from 14 days before the date the log warns and the
>    setup issue lists the token, but only while GitHub still accepts the
>    token: a token revoked or deleted early gives no warning.
> 4. **Resource owner:** the owner of the private repositories to measure.
>    If that is an organisation that reviews tokens, the token reads only
>    public repositories until an organisation owner approves it.
> 5. **Repository access:** **Only select repositories**, and select exactly
>    the measured repositories of that owner. (The token reads every public
>    repository by itself.)
> 6. **Permissions → Repository permissions**, every one **Read-only**:
>    - **Contents**, **Issues** and **Pull requests**: always.
>    - **Deployments**: when a repository uses `environment=`.
>    - **Actions**: when a repository uses `workflow=`.
>    - **Metadata** is added by itself.
>    Nothing else, and nothing with write access.
> 7. **Generate token**, and copy it. Do not paste it to me.
> 8. In your own terminal (not through me), run:
>
>    ```
>    gh secret set FORSGREN_TOKEN -R OWNER/REPO
>    ```
>
>    paste the token when it asks, press Enter, and tell me when it is done.

Never offer to run that command in your own session (no `!` shortcut) and
never take the token pasted to you: it is a separate terminal window only,
because the token would land in the conversation.

The permissions per deployment kind are the table in
[docs/data-files.md](docs/data-files.md#collecting-deployments-collect) (Collecting deployments, The token).

Check, after the person says it is done:
`gh secret list -R OWNER/REPO` shows a line starting with `FORSGREN_TOKEN`.
It shows the name and a date, never the value. Missing: stop and report.

On route B, `forsgren.yml` stays as the template has it.

## Step 11. Commit forsgren.config.yml, before the first run

The first run writes a starter configuration when the file is missing.
Committing the real file first means the starter is never written.

```
base64 < WORK/forsgren.config.yml | tr -d '\n' \
  > WORK/config.b64
gh api -X PUT repos/OWNER/REPO/contents/forsgren.config.yml \
  -f message='Add forsgren.config.yml' \
  -F content=@WORK/config.b64 --jq .commit.sha
```

Works: it prints a commit sha. Then:

```
gh api -H 'Accept: application/vnd.github.raw' \
  repos/OWNER/REPO/contents/forsgren.config.yml \
  | diff - WORK/forsgren.config.yml
```

Works: no output. Fails: stop and report.

**The update wait**, only when the person's answer is not 3 (`N` is their
number of days):

1. Read the file:

   ```
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/.github/dependabot.yml \
     > WORK/dependabot.yml
   grep -n '^ *default-days:' WORK/dependabot.yml
   ```

   Check: one line, `default-days: 3`. Anything else: stop and report.
2. In `WORK/dependabot.yml`, change that line's `3` to `N`, with your file
   tool, and nothing else. Check:
   `grep -n '^ *default-days:' WORK/dependabot.yml` prints one line,
   `default-days: N`.
3. Upload it as one commit:

   ```
   base64 < WORK/dependabot.yml | tr -d '\n' \
     > WORK/dependabot.yml.b64
   gh api repos/OWNER/REPO/contents/.github/dependabot.yml --jq .sha
   ```

   The second command prints the file's sha; use it as `SHA`:

   ```
   gh api -X PUT repos/OWNER/REPO/contents/.github/dependabot.yml \
     -f message='Propose forsgren releases after N days' \
     -F content=@WORK/dependabot.yml.b64 \
     -f sha=SHA --jq .commit.sha
   ```

   Works: it prints a commit sha. Then:

   ```
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/.github/dependabot.yml \
     | diff - WORK/dependabot.yml
   ```

   Works: no output. Fails: stop and report.

## Step 12. The first run

1. Start it:
   `gh workflow run forsgren.yml -R OWNER/REPO`
   Works: it says it created a `workflow_dispatch` event.
2. Wait 10 seconds, then find the run:

   ```
   gh run list -R OWNER/REPO -w forsgren.yml -L 1 \
     --json databaseId,event,status
   ```

   It shows one run with `"event":"workflow_dispatch"`. Its `databaseId` is
   `RUN`. No run yet: wait 10 seconds and look again, at most 6 times.
3. Watch it to the end (a few minutes; forsgren is built first):
   `gh run watch RUN -R OWNER/REPO --exit-status`
   Works: it ends with exit status 0.
   Fails: run `gh run view RUN -R OWNER/REPO --log-failed`, stop, and report
   that output. When it says `check FORSGREN_TOKEN's access` on route A,
   the run's own token was not enough: report it, it is the open question
   of forsgren#131.

Then check what the run did:

4. `gh run view RUN -R OWNER/REPO --json conclusion --jq .conclusion`
   prints `success`.
5. The run kept the configuration:

   ```
   gh api 'repos/OWNER/REPO/commits?per_page=5' \
     --jq '.[].commit.message'
   ```

   No line says `forsgren: add a starter forsgren.config.yml`. A line
   `forsgren: record deployments` is there when the run found deployments.
6. Every measured repository was read:
   `gh run view RUN -R OWNER/REPO --log | grep -E ': [0-9]+ new'`
   prints one line per measured repository, such as
   `acme/app: 3 new, 0 skipped (not final), 12 commits`. A repository
   without a line: stop and report.
7. The page shows each project:
   `curl -fsS SITE | grep -o 'scope="row">[^<]*'`
   prints `scope="row">` and each project name of the config, once each (an
   `&` in a name shows as `&amp;`). Empty answer or a 404: wait 1 minute
   and try again, at most 5 times; then stop and report.
8. The settings page shows the answers. It is a table, Parameter |
   Current value | Possible values | Default, one row per setting. This
   prints each row on one line, separated by `;`:

   ```
   curl -fsS SITEsettings.html | tr -d '\n' \
     | grep -oE '<th scope="row">[a-z_]+</th>([^<]*<td>[^<]*</td>){3}' \
     | sed -E 's/<[^>]+>/;/g; s/; *;/;/g'
   ```

   For example `;view;numbers;standard, numbers, scoring;standard;`. The
   last field of each row is the default of the key: `standard`, `true`, `false`,
   `major`, `365`, `100`, `8`, `30`, `true`, `false`, `unlisted`, `unlisted`, `true`, `median`, `true`, `true`, `true`, `[]`, for the rows
   `view` to `same_developer` in the page's order.
   - The rows `view`, `auto_update`, `auto_update_level`,
     `history_days`, `dora_days`, `issues_page`, `days_page`,
     `numbers_scoring_page` and `history_page` show the value of the config,
     without `(not set)` (the file sets the key).
   - The rows `history_chunk_days`, `working_hours`, `tbd_page` and
     `tbd_figures` are left to their defaults: `history_chunk_days` shows
     `100 (not set)`, `working_hours` shows `8 (not set)`, `tbd_page` shows
     `true (not set)` (the TBD page, `tbd.html`, is generated and in the menu)
     and `tbd_figures` shows `median (not set)` (the TBD table shows the median
     of each measure; `tbd_figures: all` shows the mean, the median and the
     90th percentile). `sub_rows`, `tbd_time_to_main`, `tbd_pr_lead_time` and
     `tbd_bot_pr_lead_time` each show `true (not set)` (every table shows its
     label and service rows, and the TBD table its Time to main, PR Lead Time
     and Bot PR Lead Time columns). The installer does not ask about these.
   - The row `same_developer` shows `[] (not set)` when the person said no to
     question 14, and the lines you wrote, without `(not set)`, when they said
     yes.
   - Eighteen rows in all. A row missing or different: stop and report.
9. The footer names the pinned version:
   `curl -fsS SITE | grep -o 'Forsgren</a> [0-9.]*'`
   prints `Forsgren</a>` and `VERSION` without its `v`.
10. No setup issue: `gh issue list -R OWNER/REPO -l forsgren-setup`
    lists no issue. An issue there: show the person its title and body
    (`gh issue view NUMBER -R OWNER/REPO`), stop and report.

Numbers such as "No deployments" or "No failed deployments" are not a
failure: they show what GitHub holds for the first chunk of history.

Without a custom domain, go to step 17.

## Step 13. Custom domain: verify the parent domain first (Person)

GitHub serves a custom domain only to the account that claims it. A DNS
record that points at GitHub Pages for a domain nobody has verified lets
someone else's repository take it over. So the domain is verified first,
and nothing else about the domain is done until it is.

`PARENT` is the domain to verify: `DOMAIN` itself for an apex domain
(`example.com`), or the domain one level up for a subdomain
(`forsgren.example.com` gives `example.com`). Verifying a domain covers
its immediate subdomains.

A person who has already verified `PARENT` (for another subdomain, say) is
not asked to verify it again, and do not ask the person to copy GitHub's
value: you check the TXT record is in DNS with dig yourself,
`dig +short TXT _github-pages-challenge-OWNER.PARENT`, and it is there when
it prints a value. Empty: this is not the verified domain the person
described, so hand them item 1 as for a new domain. Tell the person that
"verified" rests on the person's word (there is no command that reads it),
and go on to step 14 without items 1 to 3.

There is no GitHub REST endpoint, and no gh command, that tells whether a
user account's Pages domain is verified. So this step has two parts: the
DNS record is checked by you, and the verified state is the person's
confirmation. Both are needed.

1. Hand the person this, with the values filled in:

   > **Person:** verify `PARENT` for GitHub Pages.
   >
   > 1. On github.com: your profile picture → **Settings** → **Pages**
   >    (under "Code, planning, and automation"). For an organisation that
   >    owns the data repository: the organisation's **Settings** →
   >    **Pages** instead.
   > 2. **Add a domain**, enter `PARENT`, and **Add domain**.
   > 3. GitHub shows a TXT record: its name,
   >    `_github-pages-challenge-OWNER.PARENT`, and its value. Add that TXT
   >    record at your DNS provider. Keep it for as long as you use the
   >    domain: removing it can lose the verification.
   > 4. Send me the record's name and value as GitHub shows them (they are
   >    not secret), and tell me when the record is added.

2. You check the TXT record (machine-checked):
   `dig +short TXT _github-pages-challenge-OWNER.PARENT`
   with the name exactly as the person sent it.
   - Works: it prints the value the person sent, in double quotes.
   - Empty or another value: wait 5 minutes and check again, at most 12
     times (an hour). Still not: a wait, not a failure. Tell the person,
     and to ask you to resume at step 13 later. DNS can take up to 24
     hours.
   - `dig` not found: stop and tell the person.
3. **Person:** once your check works, ask the person to click **Verify**
   on that page (under the domain's **...** menu: **Continue verifying**),
   and to tell you whether GitHub now shows `PARENT` as verified.
   - The person confirms it is verified: go on to step 14.
   - Not verified, or no answer: stop. Nothing about the domain is done
     without both checks.

Tell the person which part you checked (the TXT record is in DNS with the
value they sent) and which part rests on their confirmation (GitHub shows
the domain verified).

## Step 14. Custom domain: the DNS record (Person)

First check, again, that the verification record is still there (the
safeguard before any record points at GitHub Pages):
`dig +short TXT _github-pages-challenge-OWNER.PARENT`
prints the value from step 13. Empty or another value: stop. Do not hand
over the DNS record.

Check first whether the record already exists, through the local resolver
and through a public one:

```
dig +short DOMAIN
dig +short @1.1.1.1 DOMAIN
```

A subdomain is right when, in both answers, the first line is exactly
`OWNER.github.io.` (lower case) and the next lines are `185.199.`
addresses; an apex domain, when both print the four addresses below. Right
in both: tell the person the record is already in place and go on to step
15. Ask the person to add or fix the record only when it is missing or
wrong. Then hand the person this, with the values filled in:

> **Person:** at your DNS provider, add the record for `DOMAIN`:
>
> - A subdomain such as `forsgren.example.com`: a **CNAME** record from
>   `forsgren.example.com` to `OWNER.github.io.`, written exactly so: the
>   owner in lower case, no repository name, and **with the dot at the
>   end**. Without that dot, many DNS providers add your own domain to it
>   (`OWNER.github.io.example.com.`).
> - An apex domain such as `example.com`: four **A** records, to
>   `185.199.108.153`, `185.199.109.153`, `185.199.110.153` and
>   `185.199.111.153`.
>
> Never a wildcard record (`*.example.com`). Keep the TXT record from
> before. Tell me when it is added.

After they say it is added, check it twice, through the local resolver and
through a public one, with the same two commands:

- A subdomain works when, in both answers, the first line is exactly
  `OWNER.github.io.` (lower case) and the next lines are `185.199.`
  addresses.
- An apex domain works when both print the four addresses above.
- The first line ends in the person's own domain (for example
  `OWNER.github.io.example.com.`): the likely cause is the CNAME target
  entered without its final dot. Tell the person, ask them to correct the
  record to `OWNER.github.io.`, and check again.
- The public resolver is right and the local one is not: the local one
  still holds the old answer for the record's time to live (TTL). Wait,
  as below, until both agree.
- Not yet: wait 5 minutes and check again, at most 12 times (an hour).
  Still not: this is a wait, not a failure. Tell the person DNS has not
  reached you yet, and to ask you to resume at step 14 later. DNS can take
  up to 24 hours.

Both answers work: go on to step 15, which sets the custom domain.

## Step 15. Custom domain: set it on the repository

Only after steps 13 and 14 worked. GitHub checks DNS when the custom
domain is set; set too early, before the CNAME record exists, the
certificate request does not start (forsgren#173). So first check again,
through a public resolver, that the record resolves:

```
dig +short @1.1.1.1 DOMAIN
```

A subdomain works when the first line is exactly `OWNER.github.io.` (lower
case) and the next lines are `185.199.` addresses; an apex domain works when
it prints the four addresses of step 14. Anything else: stop, and go back to
step 14. Do not set the domain. Then set it:

```
gh api -X PUT repos/OWNER/REPO/pages -f cname=DOMAIN
```

Check: `gh api repos/OWNER/REPO/pages --jq .cname` prints `DOMAIN`. Do not
add a `CNAME` file to the repository: a site built by GitHub Actions does not
use one. From now on `SITE` is `https://DOMAIN/`.

Fails: stop and report.

## Step 16. HTTPS, after the certificate is approved

1. `gh api repos/OWNER/REPO/pages --jq .https_certificate.state`
   - `approved`: go on to 2.
   - `errored` or `bad_authz`: stop and report.
   - Anything else, or nothing: wait 5 minutes and check again, at most 12
     times. Still not `approved`: a wait, not a failure. Tell the person,
     and to ask you to resume at step 16 later; GitHub can take up to 24
     hours.
   - No state at all (an empty answer) through the whole wait: the likely
     cause is that GitHub checked DNS while it was still wrong. Setting the
     same custom domain again starts no new certificate request, so remove
     it first: `gh api -X PUT repos/OWNER/REPO/pages -F cname=null`, wait a
     minute, then set it again with the step-15 call. Do this at most once,
     then wait again as above. If the removal call fails, or the state is
     still empty after that one retry, do not just stop: give the person
     the tip below, and when they are done they ask you to resume at
     step 16. (To be confirmed: removing and re-adding the custom domain was proven by hand
     in Settings > Pages on 2026-10-14; the API form of the removal has not
     been run yet.)
2. `gh api -X PUT repos/OWNER/REPO/pages -F https_enforced=true`
3. Check: `gh api repos/OWNER/REPO/pages --jq .https_enforced` prints
   `true`.
4. Start a run so the page is published at the new address, then check it:
   do step 12's items 1 to 4 again, then
   `curl -fsS https://DOMAIN/ | grep -o 'scope="row">[^<]*'`
   prints each project name, as in step 12 item 7.

The tip for the person, when the state stays empty (this worked on
2026-10-14). Tell them to do it themselves:

1. Open `https://github.com/OWNER/REPO/settings/pages`.
2. Under Custom domain, click Remove.
3. Wait about a minute, until the page shows the github.io address again.
4. Type `DOMAIN` and click Save.
5. Wait for "DNS check successful". Within 15 to 60 minutes "Enforce HTTPS"
   becomes available.

Meanwhile the page stays up at the github.io address, and no DNS change is
needed.

Fails: stop and report.

## Step 17. Tell the person it is done

Tell them, in one message:

- the page address (`SITE`), and that it runs every day at 05:17 UTC by
  itself;
- on route B: the token's expiry date, and that a new token is set with the
  same `gh secret set FORSGREN_TOKEN -R OWNER/REPO`;
- on route A: that copying the template's files over this repository (which
  a release's notes can ask for) brings back the `secrets.FORSGREN_TOKEN`
  line, and step 10A must then be done again;
- the auto-update check below, for when the next forsgren release lands.

Then leave the work folder and remove it, so you do not delete the folder
you are working in:

```
cd WORK/..
rm -r WORK
```

## Later: the first auto-update

This is checked once the next forsgren release after `VERSION` is out, not in
the install session. The template's Dependabot checks every day at 04:00 UTC
and proposes a release once it is 3 days old. An installation that is behind
(a release that waited for a person, or `auto_update: false`) is brought up to
date with [agent-upgrade.md](agent-upgrade.md), not with this file.

1. A newer release exists:
   `gh release list -R yveshanoulle/forsgren -L 1`
   shows a tag newer than `VERSION`.
2. Dependabot proposed it:
   `gh pr list -R OWNER/REPO --app dependabot --state all`
   lists a pull request that moves the forsgren pins. None 4 days after the
   release: report it.
3. The update workflow ran on it:
   `gh run list -R OWNER/REPO -w forsgren-update.yml -L 3`
   shows a run for that pull request, with conclusion `success`.
4. Within `auto_update_level`, the pull request is merged and a
   `forsgren.yml` run follows:
   `gh run list -R OWNER/REPO -w forsgren.yml -L 3`.
   Beyond the level, it stays open and that run's job summary names the
   reason; the person merges it when they are fine with it. With
   `auto_update: false` it always stays open.
5. The pin moved:

   ```
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/.github/workflows/forsgren.yml \
     | grep -E 'uses:|FORSGREN_TOKEN:'
   ```

   The `uses:` line ends with the new `# vX.Y.Z`. On route A the
   `FORSGREN_TOKEN:` line still reads `secrets.GITHUB_TOKEN`.
6. The page footer names the new version (step 12 item 9).

Anything else: report it to the person.

## Changing a setting later

For an install that exists, you can change one setting: a top-level key of
`forsgren.config.yml` (`view`, `auto_update`, `auto_update_level`,
`history_days`, `history_chunk_days`, `working_hours`, `dora_days`,
`issues_page`, `days_page`, `numbers_scoring_page`, `history_page`, `tbd_page`,
`tbd_figures`, `tbd_time_to_main`, `tbd_pr_lead_time`, `tbd_bot_pr_lead_time`,
`sub_rows`, `same_developer`), or the update wait
(`default-days` in `.github/dependabot.yml`, in days). Changes to the
projects and repositories are not covered here. Follow these steps alone;
the install steps above do not apply.

1. Do step 1 (the prerequisites). `WORK` comes from its last item.
2. Ask the person for the repository (`OWNER/REPO`), the setting and its
   new value. `FILE` is `forsgren.config.yml` for a config key, or
   `.github/dependabot.yml` for the update wait; `NAME` is the file's last
   part (`forsgren.config.yml` or `dependabot.yml`).
3. Read the file:

   ```
   mkdir -p WORK
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/FILE > WORK/NAME
   cp WORK/NAME WORK/NAME.orig
   ```

   Fails: stop and report.
4. Change the one line of that setting in `WORK/NAME` with your file tool,
   and nothing else. A config key that is not in the file yet: add it as a
   new top-level line above `projects:`. Show the person the change:
   `diff WORK/NAME.orig WORK/NAME`
5. For a config key, when Go is there (step 1 item 5), check the file with
   step 9's `go run ... check-config --config WORK/forsgren.config.yml`,
   `VERSION` taken from the repository's `forsgren.yml` as in step 8.
   Not `OK`: stop and report.
6. Ask for the go, with the values filled in:

   > Reply "go: commit the NAME change in OWNER/REPO" to let me commit it.

   Wait for that sentence. A bare "go": show the sentence again.
7. Commit it:

   ```
   base64 < WORK/NAME | tr -d '\n' > WORK/NAME.b64
   gh api repos/OWNER/REPO/contents/FILE --jq .sha
   ```

   The second command prints the file's sha; use it as `SHA`:

   ```
   gh api -X PUT repos/OWNER/REPO/contents/FILE \
     -f message='Change SETTING to VALUE' \
     -F content=@WORK/NAME.b64 -f sha=SHA --jq .commit.sha
   ```

   with `SETTING` and `VALUE` filled in. Works: it prints a commit sha.
8. Check it:

   ```
   gh api -H 'Accept: application/vnd.github.raw' \
     repos/OWNER/REPO/contents/FILE | diff - WORK/NAME
   ```

   Works: no output. Fails: stop and report.
9. Leave the work folder and remove it, so you do not delete the folder
   you are working in:

   ```
   cd WORK/..
   rm -r WORK
   ```

   Tell the person when it takes effect: a config key at the next daily
   run (05:17 UTC), the update wait at Dependabot's next daily check
   (04:00 UTC).

## Starting over

When a step failed and the person wants to start again, or asks to start
over (a certificate that never starts is not a reason: see the tip in
step 16):

1. Show the person what will be deleted: the repository `OWNER/REPO`, with
   its configuration, its collected history, its page and, on route B, its
   `FORSGREN_TOKEN` secret. Ask them to confirm by typing the repository's
   full name. Delete nothing else.
2. **Custom domain only** (the install got as far as step 13, or the person
   added a record for `DOMAIN`): before anything is deleted, check the
   domain is still verified, the same two ways as step 13:
   - you: `dig +short TXT _github-pages-challenge-OWNER.PARENT` prints the
     value from step 13;
   - **Person:** confirms GitHub still shows `PARENT` as verified in
     Settings → Pages.

   Both hold: the `DOMAIN` record may stay for the next attempt. Either one
   fails, or you cannot tell: hand the person this before anything else,

   > **Person:** at your DNS provider, remove the CNAME (or the four A
   > records) for `DOMAIN`. Keep the `_github-pages-challenge` TXT record.
   > Tell me when it is removed.

   and check that `dig +short DOMAIN` no longer prints `OWNER.github.io.`
   or `185.199.` addresses (wait 5 minutes and check again, at most 12
   times; still there: a wait, resume at this item later). Delete nothing
   before that check passes.
3. **Person**, in their own terminal (deleting needs a scope the login does
   not have by default):

   ```
   gh auth refresh -h github.com -s delete_repo
   gh repo delete OWNER/REPO
   ```

   `gh repo delete` asks them to type the name again.
4. Check: `gh repo view OWNER/REPO` prints
   `Could not resolve to a Repository`.
5. Leave the work folder and remove it, so you do not delete the folder
   you are working in:

   ```
   cd WORK/..
   rm -r WORK
   ```
6. What stays:
   - the verification TXT record and the verified domain: deleting the
     repository never removes them, and the person keeps the TXT record;
   - the `DOMAIN` record, only when item 2 found the domain verified;
   - on route B, the person's fine-grained token: it can be set again on
     the new repository in step 10B, or deleted in the same settings page.
7. Start again at step 1 of this file. With a custom domain, steps 13 and
   15 check the verification and the record again; a record that is
   already there is checked, not added twice.
