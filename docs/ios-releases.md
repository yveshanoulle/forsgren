# iOS releases

A recipe for an iOS app whose deployments forsgren should count as the
releases users get (forsgren#665). forsgren counts production GitHub
Deployments (see
[Giving a repository the deployments forsgren counts](configuration.md#giving-a-repository-the-deployments-forsgren-counts)).
For an iOS app the obvious events mislead: a TestFlight upload is not a
release, and the version users get is only known once Apple puts it live in
the App Store, often days after the upload. This page describes a setup
that records each App Store release as one production Deployment on the
exact commit it was built from, and keeps TestFlight uploads out of the
numbers. It is the released boundary of
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
the next minor (`7.3.0` to `7.4.0`); a new major or a chosen minor is a
change by hand. App Store Connect takes no new builds for a version that is
already live, so the bump keeps TestFlight uploads going, and every tag
stays unique. Before the bump is pushed, a self-check reads the version
back from every target and confirms it is one value, higher than the live
version.

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
