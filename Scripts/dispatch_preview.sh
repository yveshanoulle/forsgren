#!/usr/bin/env bash
# Scripts/dispatch_preview.sh
#
# Starts the preview deploy (forsgren#222). forsgren's own. After a push to
# main, .github/workflows/preview.yml runs this with the pushed sha; the
# preview repository's workflow preview.yml then builds forsgren at that sha
# and renders the already collected data of the public metrics installation
# at the preview site. The preview never collects.
#
# Usage: Scripts/dispatch_preview.sh <sha>
#
#   <sha>                      the full commit, 40 lower-case hex digits (the
#                              input the preview workflow checks again)
#   PREVIEW_DISPATCH_TOKEN     env: the fine-grained token that holds Actions
#                              read and write on the preview repository and
#                              nothing else. It is the ONLY credential used:
#                              an empty or unset one is a failure, and
#                              GH_TOKEN, GITHUB_TOKEN or a login of the
#                              machine are never a fallback (on a self-hosted
#                              runner an empty token would silently become the
#                              maintainer's login).
#
# It POSTs repos/yveshanoulle/forsgren-metrics-feta/actions/workflows/
# preview.yml/dispatches with {"ref":"main","inputs":{"sha":"<sha>"}} and
# requires HTTP 204. Any other status, or a curl that gets none, fails
# naming it. A failed start fails the run, never only a warning.
#
# The token goes to curl as a header file on stdin (-H @-), never in the
# arguments, where a process list shows it. --disable first: a curlrc must
# not be able to add anything.
#
# Exit 0 started (204). Exit 1 the start failed. Exit 2 a bad sha or no token;
# no request is made then.

set -euo pipefail
# Tracing off: the token must never reach a trace.
set +x

REPO="yveshanoulle/forsgren-metrics-feta"
WORKFLOW="preview.yml"

sha="${1:-}"
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::dispatch_preview: the sha must be 40 lower-case hex digits"
  exit 2
fi
if [[ -z "${PREVIEW_DISPATCH_TOKEN:-}" ]]; then
  echo "::error::dispatch_preview: PREVIEW_DISPATCH_TOKEN is empty or not set; no other login is used, so the preview was not started"
  exit 2
fi

body="{\"ref\":\"main\",\"inputs\":{\"sha\":\"${sha}\"}}"
url="https://api.github.com/repos/${REPO}/actions/workflows/${WORKFLOW}/dispatches"

rc=0
status="$(printf 'Authorization: Bearer %s\n' "$PREVIEW_DISPATCH_TOKEN" \
  | curl --disable --silent --show-error --max-time 30 --proto '=https' \
    --output /dev/null --write-out '%{http_code}' \
    -X POST -H @- \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -d "$body" "$url" 2>/dev/null)" || rc=$?

if [[ "$rc" -ne 0 ]]; then
  echo "::error::dispatch_preview: curl failed (exit ${rc}) before GitHub answered; the preview was not started"
  exit 1
fi
if [[ "$status" != "204" ]]; then
  echo "::error::dispatch_preview: GitHub answered status ${status}, not 204; the preview was not started"
  exit 1
fi
echo "OK: preview deploy started at ${sha} (${REPO}/${WORKFLOW}, status 204)"
