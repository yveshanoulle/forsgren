#!/usr/bin/env bash
# Scripts/open_selftests_failure_issue.sh (forsgren#686)
#
# Opens the ONE issue of a red Self-tests run on main. The failure_issue job of
# .github/workflows/selftests.yml runs it after the report, on a push only.
# Nothing waits on the Self-tests workflow (the Release and the preview chain to
# Quality), so without this a red self-test on main would be seen by nobody.
#
#   Scripts/open_selftests_failure_issue.sh
#
# Reads, from the environment the job sets (never a ${{ }} inside run:):
#   SELFTESTS_REPOSITORY  owner/name of the repository
#   SELFTESTS_RUN_ID      the red run's id
#   SELFTESTS_SHA         the commit the run checked (40 hex characters)
#   SELFTESTS_SERVER_URL  https://github.com, for the run's link
#   GH_TOKEN              the job's own token (gh reads it; this script never
#                         prints it)
#
# The title names the run, "Self-tests failed on main: run <id> (<short sha>)",
# so a rerun of the same run (a new attempt) finds the issue its first attempt
# opened among the open issues and opens no second one. No label: a red
# self-test is a broken test of a gate, not a failure users hit, so it must not
# feed the change fail rate or the recovery time this repository measures of
# itself. The body names the commit, links the run and says what holds and
# what does not.
#
# Exit 0: the issue was opened, or was already open. 1: gh failed (named; the
# job is then red, so the run page says the issue was not opened). 64: an input
# is missing or malformed (named). Self-test:
# Scripts/test_selftests_failure_issue.sh.

set -uo pipefail

repo="${SELFTESTS_REPOSITORY:-}"
run_id="${SELFTESTS_RUN_ID:-}"
sha="${SELFTESTS_SHA:-}"
server="${SELFTESTS_SERVER_URL:-}"

bad=""
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || bad="SELFTESTS_REPOSITORY '${repo}' is no owner/name"
[[ "$run_id" =~ ^[0-9]+$ ]] || bad="${bad:+${bad}; }SELFTESTS_RUN_ID '${run_id}' is no run id"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || bad="${bad:+${bad}; }SELFTESTS_SHA '${sha}' is no full commit sha"
[[ "$server" =~ ^https://[A-Za-z0-9.-]+$ ]] || bad="${bad:+${bad}; }SELFTESTS_SERVER_URL '${server}' is no https server address"
if [[ -n "$bad" ]]; then
  echo "❌ open_selftests_failure_issue: ${bad}" >&2
  exit 64
fi

title="Self-tests failed on main: run ${run_id} (${sha:0:7})"
run_url="${server}/${repo}/actions/runs/${run_id}"

if ! open_titles="$(gh issue list -R "$repo" --state open --search "\"run ${run_id}\" in:title" --limit 100 --json title --jq '.[].title')"; then
  echo "❌ open_selftests_failure_issue: gh could not list the open issues of ${repo}, so no issue was opened for run ${run_id}" >&2
  exit 1
fi
if grep -qxF -- "$title" <<< "$open_titles"; then
  echo "The issue '${title}' is already open: no second one."
  exit 0
fi

body="The Self-tests workflow failed on main at commit ${sha}: ${run_url}

The self-tests check the gates themselves; Quality checks the commit. Quality, the release and the preview do not wait on this workflow, so nothing was held back. The report on the run page names the red self-test; \`./FBP.sh --with-selftests\` runs every self-test locally.

Opened by the failure_issue job of .github/workflows/selftests.yml (forsgren#686)."

if ! url="$(gh issue create -R "$repo" --title "$title" --body "$body")"; then
  echo "❌ open_selftests_failure_issue: gh could not open the issue '${title}' in ${repo}" >&2
  exit 1
fi
echo "Opened ${url:-the issue}: ${title}"
