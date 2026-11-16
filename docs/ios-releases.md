# iOS releases

A recipe for an iOS app whose deployments forsgren should count as the
releases users get (forsgren#665). forsgren counts production GitHub
Deployments (see
[Giving a repository the deployments forsgren counts](configuration.md#giving-a-repository-the-deployments-forsgren-counts)).
For an iOS app the obvious events mislead: a TestFlight upload is not a
release, and the version users get is only known once Apple puts it live in
the App Store, often days after the upload. This page describes a setup
that records each App Store release as one production Deployment on the
exact commit it was built from, keeps TestFlight uploads out of the
numbers, and raises the code's marketing version after each release. It is the released boundary of
[Hand-off pipelines](hand-off-pipelines.md#the-boundary), applied to the
App Store.

The repository keeps the default rule, `environment=production`:

```yaml
repositories:
  - name: acme/ios-app                 # deployment: environment=production is the default
```

## Tag every TestFlight upload

The workflow that uploads a build to TestFlight tags the commit it built
from with `v<marketing version>-<build>`, for example `v7.3.0-412`: the
marketing version is the app's `CFBundleShortVersionString` (the
`MARKETING_VERSION` build setting), and the build is its `CFBundleVersion`,
which is unique for every upload of that version. Push the tag right after
the upload succeeds.

One tag per build, not one per version: a version often has several
uploads, and only one of them goes live. The tag of the build Apple
releases is the only link from the App Store back to the commit.

## Record TestFlight uploads outside production

When the upload workflow records a GitHub Deployment (or uses a job with
`environment:`, which makes GitHub record one), it records it under a
non-production environment, for example `testflight`. forsgren reads only
the environment its rule names, `production` by default, so these
deployments do not count; they stay visible in GitHub's Deployments list.

```yaml
jobs:
  upload:
    runs-on: macos-latest
    environment: testflight
```

Do not name the upload workflow in a `workflow=` rule either: every
successful upload would then count as a deployment.

## The App Store release check

A small workflow records the release. It runs once a day (a `schedule:`
trigger, or any outside dispatcher that starts it) and by hand
(`workflow_dispatch`), for example right after a release goes live, so the
deployment's time is close to the release. Each run:

1. **Reads the live build from the App Store Connect API.**
   `GET /v1/apps/{id}/appStoreVersions?filter[platform]=IOS&include=build`
   lists the app's App Store versions with the build attached to each. It
   keeps the one version whose `appStoreState` is `READY_FOR_SALE`, its
   `versionString`, and the `version` of its attached build (the
   `CFBundleVersion`).
2. **Signs its own token.** The API takes a JSON Web Token signed with ES256
   by an App Store Connect API key: the key ID in the header (`kid`), the
   issuer ID as `iss`, `aud` set to `appstoreconnect-v1`, and an `exp` at
   most 20 minutes after `iat`. Keep the private key in a repository secret
   and give it to one step only, the one that signs the token and calls the
   API, so no other step, action or log can read it.
3. **Maps the build to the commit through its exact tag.** The tag is
   `v<versionString>-<build version>`, built from the answer; the check
   resolves that one ref (`refs/tags/v7.3.0-412`) to its commit (an
   annotated tag to the commit it points at). It is never the highest tag
   for the version: that is the newest upload, which need not be the build
   Apple released.
4. **Records one production Deployment there.** It creates a Deployment with
   `ref` set to the commit's SHA, `environment` `production`,
   `production_environment` `true`, a task name of its own (for example
   `app-store-release`), `auto_merge` `false`, `required_contexts` `[]`, and
   a payload naming the version, the build and the tag; then it gives that
   deployment a `success` status. The job needs `deployments: write` and
   `contents: read`.

The check is idempotent: before it creates anything it lists the production
deployments of that commit and task, and when one already names the same
version and build with a `success` status it does nothing. So the daily run
records a release once, however many days it stays live.

It fails closed: when it cannot be sure, it records nothing and fails the
run, naming why. That is the case for no version in `READY_FOR_SALE` or
more than one, a live version without an attached build, no tag for the
live build, and a history that does not fit (a production deployment
already recorded for a later version or build than the live one). It is
loud on API errors: an answer other than success from Apple or GitHub fails
the run with the status and the endpoint, and is never read as "nothing
live".

## Keep the marketing version consistent

The tag is only exact when every target of the app (the app and its
extensions, widgets and watch app) carries the same marketing version. A
lint gate checks that `MARKETING_VERSION` holds one value for every target
and build configuration of the project, and is red otherwise.

The recommended practice is to bump the marketing version right after a
release: once the live version equals the code's version, move the code to
the next minor (`7.3` to `7.4`). App Store Connect takes no new builds for a
version that is already live, so the bump keeps TestFlight uploads going,
and every tag stays unique.
[Bump the marketing version after a release](#bump-the-marketing-version-after-a-release)
describes a job that does it.

## Bump the marketing version after a release

A second job in the release check workflow raises the code's marketing
version once the App Store has it live, and pushes that one change to the
default branch. This section describes that mechanism and the guarantees
its design and its tests give; it is not a whole release pipeline.

### What starts the bump

The bump job names the record job of [the release check](#the-app-store-release-check)
in `needs:`, so it runs in the same run (the daily one or one by hand,
`workflow_dispatch`) and only after the record job succeeded. When the check
fails closed, there is no bump. The bump job also runs after a check that
found the release already recorded; once the code is ahead of the live
version, the rule below makes it do nothing.

A `workflow_dispatch` input, `bump`, chooses the rule: `none` (the default,
which the daily run uses), `minor` or `major`. A run started by `schedule:`
has no inputs, so the daily run is started as a dispatch, by an outside
dispatcher, as in the example below.

### Where the versions are read

- **The live version** is the record job's own answer, the `versionString`
  of the one App Store version in `READY_FOR_SALE`, handed to the bump job
  as a job output. The bump job does not call Apple again.
- **The code's version** is every `MARKETING_VERSION = <value>;` line of the
  Xcode project file (`path/to/project.pbxproj`). The lines must agree: the
  same check as the lint gate above runs first, and a project whose lines
  hold more than one value, or a value that is not `digits.digits` or
  `digits.digits.digits`, fails the job with nothing written.

### How the next version is chosen

- `none`: when the live version equals the code's, the minor goes up (`7.3`
  to `7.4`). When the code is already ahead of the live version, there is
  nothing to bump: the job is green and changes nothing, which is what every
  daily run after the bump sees. When the code is behind the live version,
  the version went backwards, and the job fails.
- `minor`: the minor goes up, whatever is live.
- `major`: the major goes up and the minor starts at 0 (`7.3` to `8.0`),
  whatever is live.

Versions are compared part by part as numbers, a missing part counting as 0,
so `7.3` equals `7.3.0` and `7.10` is ahead of `7.9`. The new version has
two parts: a third part is dropped (`7.3.1` becomes `7.4`, or `8.0`).

The new project file is written to a temporary folder and checked before it
replaces the old one: the agreement check passes, and every line that held
the code's version holds the new one, the same number of lines. A file that
repeats the version elsewhere, such as a test that expects it, moves in the
same change and is checked the same way. Anything wrong fails the job before
a file is replaced.

### How the change is persisted

The change is one commit, pushed straight to the default branch, without a
pull request. Before it commits, the push step checks once more:

- the run is on the default branch (`GITHUB_REF`), so a run dispatched on
  another branch never pushes that branch to the default one;
- the working tree changed exactly the version files and nothing else;
- the agreement check passes and every `MARKETING_VERSION` holds the new
  version.

The commit uses a bot identity set for that one command, so the runner's own
git configuration (identity, signing, hooks) does not apply. The push sends
`HEAD` to the default branch with no force: when the branch moved after the
job checked it out, the push is refused as not a fast-forward, and the step
fails. There is no retry; dispatch the release check again.

### Token, secret and permissions

A commit pushed with the job's `GITHUB_TOKEN` starts no workflow
([Triggering a workflow from a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow)).
The bump commit should run the default branch's workflows (its CI, and the
TestFlight upload when that runs on push) like any other commit, so the push
uses a token of its own:

- a [fine-grained personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token)
  with access to this one repository and one permission, Contents: Read and
  write;
- kept in a [repository secret](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets),
  in the example below `VERSION_BUMP_TOKEN`;
- in the `env:` of the push step alone: the checkout and the bump step never
  see it.

The job itself holds `contents: read` only, so its own token cannot push.
The checkout sets `persist-credentials: false`, so no token stays in the
checkout's git configuration for a later step. The token reaches git only
through the environment of the one `git push` command (an authorization
header passed with `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0` and
`GIT_CONFIG_VALUE_0`), never on a command line, in a file or in a global
git configuration, and no step prints it. The job has its own `concurrency`
group with `cancel-in-progress: false`, so two bumps never run at once.

### Failure behaviour

Every failure fails the job, names its reason, and leaves the default branch
as it was:

- a missing secret: the push step stops before git runs, naming the secret,
  with nothing committed or pushed;
- a live version or code version that is not `digits.digits` or
  `digits.digits.digits`, project lines that disagree, or code behind the
  live version: nothing is written;
- a run on another branch, or a working tree that changed other files:
  nothing is committed;
- a push the remote refuses (the branch moved, the token cannot write, or a
  branch rule refuses a direct push): nothing is forced and nothing is
  retried.

### A minimal workflow

The record job stands for the release check above; its step writes
`version=<versionString>` to `$GITHUB_OUTPUT`. `path/to/bump-version.sh`
stands for your script with the rules of this section: it writes `old=` and
`new=` to `$GITHUB_OUTPUT` when it changed the files, and nothing when there
is nothing to bump. Pin every action to a full commit SHA.

```yaml
name: App Store release check

on:
  workflow_dispatch:                       # daily by a dispatcher, or by hand
    inputs:
      bump:
        description: "none: bump only when the live version equals the code's; minor or major: force it"
        type: choice
        options: [none, minor, major]
        default: none

permissions:
  contents: read

jobs:
  record:
    runs-on: macos-latest
    permissions:
      contents: read
      deployments: write
    outputs:
      version: ${{ steps.live.outputs.version }}
    steps:
      - id: live
        run: path/to/record-release.sh >> "$GITHUB_OUTPUT"   # the release check above

  bump:
    needs: record                          # only after a successful record
    runs-on: macos-latest
    permissions:
      contents: read                       # the job's token cannot push
    concurrency:
      group: version-bump
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@<full-commit-sha> # vX.Y.Z
        with:
          persist-credentials: false

      - id: bump
        env:
          LIVE_VERSION: ${{ needs.record.outputs.version }}
          BUMP: ${{ inputs.bump }}
        run: path/to/bump-version.sh "$LIVE_VERSION" "$BUMP" >> "$GITHUB_OUTPUT"

      - if: steps.bump.outputs.new != ''
        env:
          VERSION_BUMP_TOKEN: ${{ secrets.VERSION_BUMP_TOKEN }}   # this step only
          NEW_VERSION: ${{ steps.bump.outputs.new }}
        run: |
          set -euo pipefail
          [ -n "$VERSION_BUMP_TOKEN" ] || { echo "VERSION_BUMP_TOKEN is not set: nothing pushed" >&2; exit 1; }
          [ "$GITHUB_REF" = "refs/heads/main" ] || { echo "not a run on main: nothing pushed" >&2; exit 1; }
          git add -- path/to/project.pbxproj
          git -c user.name="github-actions[bot]" \
            -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
            -c commit.gpgsign=false -c core.hooksPath=/dev/null \
            commit -m "Version ${NEW_VERSION} after the App Store release"
          auth="$(printf 'x-access-token:%s' "$VERSION_BUMP_TOKEN" | base64 | tr -d '\n')"
          GIT_CONFIG_COUNT=1 \
            GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" \
            GIT_CONFIG_VALUE_0="AUTHORIZATION: basic ${auth}" \
            git push "https://github.com/${GITHUB_REPOSITORY}.git" HEAD:refs/heads/main   # no force
```

The example leaves out the checks of the push step listed above (the
working tree, the agreement check on the new version); a real push step
runs them before it commits.

## What forsgren then shows

- [Deployment frequency](pages-and-views.md#deployment-frequency) counts App
  Store releases, not uploads.
- [Lead time for changes](pages-and-views.md#lead-time-for-changes) runs
  from each commit's author date to the creation of the release's
  deployment, over the commits since the previous release (see
  [Collecting deployments](data-files.md#collecting-deployments-collect)).
  It includes review and the wait for Apple, plus the time until the check
  runs: up to a day with the daily run alone, which a run by hand after the
  release removes.
- The check records successes only. A failure users see after a release
  reaches [change fail rate](pages-and-views.md#change-fail-rate),
  [deployment rework rate](pages-and-views.md#deployment-rework-rate) and
  [failed deployment recovery time](pages-and-views.md#failed-deployment-recovery-time)
  through a failure issue (see
  [Failures after the hand-off](hand-off-pipelines.md#failures-after-the-hand-off)).

## Common pitfalls

- **TestFlight counted as production.** An upload job with
  `environment: production`, a `workflow=` rule on the upload workflow, or
  a GitHub Release per upload with the `release` rule each count uploads as
  releases, and the deployment frequency is inflated.
- **TestFlight uploads already recorded as production.** An app that
  recorded its uploads as production deployments before it moved to this
  setup keeps them in its history, which only grows. When those deployments
  carry a task of their own, the repository's
  [`exclude`](configuration.md#configuration) key leaves them out of every
  metric and the History without rewriting the files: `task:` the uploads'
  task, and `before:` the time of the switch only when the same task still
  names production deployments that should count after it.
- **Tags per version instead of per build.** A tag `v7.3.0` moved or set on
  the newest upload names the wrong commit when Apple released an earlier
  build of that version, and lead time then counts commits that users do
  not have yet.
- **A version not yet live.** A version that is approved, waiting for the
  developer to release it, or still in review is not `READY_FOR_SALE`, so
  the check records nothing for it yet. The release is recorded on the first
  run after it goes live.
- **Earlier releases.** The check sees only the version live now. Releases
  from before the check existed are not recorded; record them by hand with
  the same two calls (see
  [Route A](hand-off-pipelines.md#route-a-record-a-github-deployment-from-outside))
  if the history should hold them.

## API documentation

- App Store Connect API, list an app's App Store versions:
  https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-appstoreversions
- App Store Connect API, generating tokens for API requests:
  https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
- GitHub REST API, deployments:
  https://docs.github.com/en/rest/deployments/deployments
- GitHub REST API, deployment statuses:
  https://docs.github.com/en/rest/deployments/statuses
- Apple, the marketing version (`CFBundleShortVersionString`):
  https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring
- GitHub Actions, the `workflow_dispatch` event and its inputs:
  https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch
- GitHub Actions, triggering a workflow from a workflow (a push made with
  `GITHUB_TOKEN` starts no workflow):
  https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow
- GitHub Actions, a job's `permissions`:
  https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions
- GitHub Actions, passing job outputs to a dependent job:
  https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/pass-job-outputs
- GitHub Actions, concurrency:
  https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency
- GitHub Actions, using secrets:
  https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets
- GitHub, creating a fine-grained personal access token:
  https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token
- GitHub REST API, the Contents permission of a fine-grained token:
  https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens#repository-permissions-for-contents
- `actions/checkout`, `persist-credentials`:
  https://github.com/actions/checkout
