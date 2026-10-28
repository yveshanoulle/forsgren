# Hand-off pipelines

A recipe for a repository whose GitHub workflow does not deploy itself: it
hands the change to a system outside GitHub, such as a CD tool (Argo CD, for
example), a mobile pipeline (fastlane, for example) or any other, and that
system does the rest without reporting back to the workflow (forsgren#557).
What each `deployment` rule reads is in
[Giving a repository the deployments forsgren counts](configuration.md#giving-a-repository-the-deployments-forsgren-counts);
this page says how to give forsgren those records when the deploy happens
elsewhere.

## The boundary

forsgren counts what GitHub knows. It reads GitHub Deployments, workflow
runs and releases, and the issues labelled `failure`
(see [How it gets its data](data-files.md#how-it-gets-its-data)). It never
asks the system outside GitHub. So a successful hand-off run means handed
off, not live: the change has left GitHub, and nothing in GitHub says yet
whether it reached users.

Each installation picks the moment it calls "deployed", and records a
deployment at that moment. forsgren takes a deployment's time from its
creation (a GitHub Deployment's `created_at`, a workflow run's
`run_started_at`), never from its status, so the record has to be made when
the boundary is reached. Three common choices:

- **Received**: the outside system accepted the change. Lead time ends at the
  hand-off and leaves out the time the outside system takes. Deployment
  frequency counts hand-offs. Change fail rate and recovery time see a
  failure only when the hand-off itself failed, or when a failure issue is
  filed.
- **Synced**: the outside system applied the change to its target (a cluster
  in sync with the commit, for example). Lead time includes the wait and the
  sync. A sync that fails can be recorded as a failed deployment, so change
  fail rate and recovery time see it.
- **Released**: users have the change (a store release, a finished
  rollout). Lead time includes review and rollout and is the closest to
  DORA's "running in production". Deployment frequency counts releases,
  which are often fewer than hand-offs; a change that never reaches users is
  not counted.

How each number uses the records:
[Deployment frequency](pages-and-views.md#deployment-frequency) counts the
successful deployments of the window;
[lead time for changes](pages-and-views.md#lead-time-for-changes) runs from
each commit's author date to the creation time of the successful deployment
that shipped it;
[change fail rate](pages-and-views.md#change-fail-rate) counts failed
deployments and failure issues against the final deployments;
[failed deployment recovery time](pages-and-views.md#failed-deployment-recovery-time)
runs from a failed deployment to the next success of its stream, and reads
deployments only.

## Route A: record a GitHub Deployment from outside

No workflow is needed. The outside system, for example from a notification
or a webhook it calls when it reaches the boundary, makes two REST calls:

1. `POST /repos/{owner}/{repo}/deployments` with `ref` (the app commit),
   `environment` and, when the repository has services, `task`. The answer
   holds the deployment's `id`.
2. `POST /repos/{owner}/{repo}/deployments/{deployment_id}/statuses` with
   `state` set to `success` or `failure`.

The token needs the repository permission Deployments: Read and write (a
fine-grained token), or `deployments: write` for a workflow's own token.

```
curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/acme/shop/deployments \
  -d '{"ref":"COMMIT_SHA","environment":"production","task":"deploy-web","auto_merge":false,"required_contexts":[]}'

curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/acme/shop/deployments/DEPLOYMENT_ID/statuses \
  -d '{"state":"success"}'
```

`auto_merge: false` keeps GitHub from merging the default branch into the
ref. `required_contexts: []` skips GitHub's check of the commit's status
contexts; without it, GitHub refuses the deployment while a context of the
commit has not passed.

How forsgren counts it (see
[Collecting deployments](data-files.md#collecting-deployments-collect)):

- The rule `environment=<name>` (the default is `environment=production`)
  reads the deployments to that environment and their statuses. A deployment
  is a success when any of its statuses was `success`. It is a failure when
  none was and its newest status other than `inactive` is `failure` or
  `error`. Anything else (no status yet, `pending`, `queued`,
  `in_progress`) is not final: forsgren reads it again on a later run. So a
  deployment that once had `success` stays a success: give the status when
  the outcome at the boundary is known, and record a later failure as a
  failure issue (see [Failures after the hand-off](#failures-after-the-hand-off)).
- The `task` is stored. With `services:`, a map of task to label, each listed
  task gets its own row, and a task left out counts in the project's total
  only (see [Configuration](configuration.md#configuration)). GitHub's
  default task is `deploy`. Under `deployments:`, the rule
  `environment=<name>` is one row of its own.

```yaml
repositories:
  - name: acme/shop
    deployment: environment=production
    services:
      deploy-web: Web
      deploy-worker: Worker
```

The `ref` must be the app commit: the SHA of the commit in the repository
that went live, not a branch name. forsgren stores the deployment's commit
and measures lead time from the commits since the previous success of the
same stream. An outside system that knows an image tag or a build number
needs that mapped back to the commit; the simplest is to build the tag from
the commit SHA, so the notification can send it as `ref`.

## Route B: trigger a small workflow from outside

The outside system starts a workflow in the repository, and that workflow
records the deployment. Two documented ways:

- `POST /repos/{owner}/{repo}/dispatches` with `event_type` and
  `client_payload` starts the workflows that listen to `repository_dispatch`
  with that type. The token needs the repository permission Contents: Read
  and write. The workflow file must be on the default branch.
- `POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches`
  with `ref` and `inputs` starts a workflow that listens to
  `workflow_dispatch`. The token needs the repository permission Actions:
  Read and write.

```
curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/acme/shop/dispatches \
  -d '{"event_type":"deployed","client_payload":{"sha":"COMMIT_SHA","state":"success"}}'
```

A minimal workflow, with `deployments: write` as its only permission. The
run's own commit is the default branch's head, not the deployed commit, so
the commit comes from the payload.

```yaml
name: Record deployment
on:
  repository_dispatch:
    types: [deployed]
permissions: {}
jobs:
  record:
    runs-on: ubuntu-latest
    permissions:
      deployments: write
    steps:
      - name: Record the deployment
        env:
          GH_TOKEN: ${{ github.token }}
          SHA: ${{ github.event.client_payload.sha }}
          STATE: ${{ github.event.client_payload.state }}
        run: |
          case "$STATE" in success|failure) ;; *) echo "state must be success or failure"; exit 1 ;; esac
          id=$(jq -n --arg sha "$SHA" \
            '{ref: $sha, environment: "production", task: "deploy", auto_merge: false, required_contexts: []}' \
            | gh api "repos/$GITHUB_REPOSITORY/deployments" --input - --jq .id)
          gh api "repos/$GITHUB_REPOSITORY/deployments/$id/statuses" -f state="$STATE"
```

The repository keeps the rule `environment=production`, and forsgren counts
these deployments as in Route A. The workflow's own runs are not the
deployments, so do not name it in a `workflow=` rule.

## Route C: keep the triggering workflow

The workflow that hands off can be the record itself, in one of two ways.

**Count its runs.** The rule `workflow=<file>.yml` counts the runs of that
workflow on the default branch: a run that concluded `success` is a
successful deployment, `failure` a failed one, and any other conclusion
(`cancelled`, `skipped`, `timed_out` and the like) is stored as `other`,
which counts as neither. The time is the run's start and the commit its
`head_sha`. This is the received boundary measured at the start of the run,
and a run that failed before the hand-off (a test step, for example) counts
as a failed deployment too.

**Record one deployment right after the hand-off step.** The workflow
records a GitHub Deployment itself, and the repository uses an
`environment=<name>` rule instead. Give the hand-off step an `id` and add
two steps after it to the same job, which needs `deployments: write`:

```yaml
      - id: handoff
        run: ./hand-off.sh
      - name: Record the deployment
        if: steps.handoff.outcome == 'success'
        env:
          GH_TOKEN: ${{ github.token }}
        run: ./record-deployment.sh success
      - name: Record the failed deployment
        if: failure() && steps.handoff.outcome == 'failure'
        env:
          GH_TOKEN: ${{ github.token }}
        run: ./record-deployment.sh failure
```

Here `record-deployment.sh` makes the two calls of Route A with
`ref` set to `$GITHUB_SHA`. The result: a success when the hand-off step
passed, a failure when it ran and failed, and nothing when the run stopped
before the hand-off or was cancelled (the hand-off step is then `skipped` or
`cancelled`, and neither step runs). A failed build or test never counts as
a failed deployment this way.

**A fan-out of targets stays out of the metrics.** The outside system may
roll one hand-off out to many targets (clusters, regions, stores). Both
forms of Route C give one deployment per hand-off, however many targets
follow. A deployment recorded per target would count each target in
deployment frequency, and with a task per target each target is its own
stream, so every commit would count once per target in lead time.

## Failures after the hand-off

A failure that shows up after the hand-off, once users are hit, reaches the
numbers through a failure issue: an issue with the `failure` label and the
record block in its body, at least `failure-start:` (see
[How it gets its data](data-files.md#how-it-gets-its-data)). forsgren reads
these issues on every run.

- [Change fail rate](pages-and-views.md#change-fail-rate) counts it as a
  failed change when it was opened in the window. Per repository the failed
  changes are the larger of the failed deployments and the failure issues,
  so an issue filed about a failed deployment does not count twice.
- [Deployment rework rate](pages-and-views.md#deployment-rework-rate) counts
  a successful deployment created while the issue was open as rework.
- [Failed deployment recovery time](pages-and-views.md#failed-deployment-recovery-time)
  reads deployments only, not issues. An incident after the hand-off reaches
  it only when it is recorded as a failed deployment (a deployment with a
  `failure` status, as in Route A) and a later success of the same stream
  ends it.
- A `service:` line in the record block, with a row's label, counts the
  issue in that row too, and not only in the project's total.

To withdraw a failure issue, remove its `failure` label or close it as not
planned. forsgren takes it back on its next run, and it no longer counts;
an issue that gets its label back counts again (see
[History](data-files.md#history), The withdrawn failures).
