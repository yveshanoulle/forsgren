#!/usr/bin/env bash
# Scripts/dispatch_report.sh
#
# Sends the outcome of one of forsgren's own workflow runs to a receiving
# repository as a repository_dispatch (event_type forsgren-report), for a
# maintainer who shows it somewhere this public, GitHub-hosted repository
# cannot reach. forsgren's own. Optional: without the receiver or without the
# token it sends nothing, says so in one ::warning:: and exits 0, so the run
# stays green.
#
# Usage: Scripts/dispatch_report.sh <kind> <status> <conclusion> <tests> <total>
#
#   kind        what is reported, one of: selftests
#   status      in_progress | completed
#   conclusion  empty for in_progress; success | failure | cancelled for
#               completed
#   tests       digits (at most 6) or XX (unknown)
#   total       digits (at most 6) or XX (unknown)
#   REPORT_TARGET_REPO     env: the receiving repository, owner/name (the
#                          repository secret of that name, so the run log masks it). Not written in
#                          this repository's code, so nothing here names it.
#   REPORT_DISPATCH_TOKEN  env: a fine-grained token with Contents: Read and
#                          write on the receiving repository and nothing else
#                          (GitHub requires Contents write for
#                          POST /repos/{owner}/{repo}/dispatches). It is the
#                          ONLY credential used: GH_TOKEN, GITHUB_TOKEN or a
#                          login of the machine are never a fallback.
#
# It POSTs repos/<target>/dispatches with
#   {"event_type":"forsgren-report","client_payload":{"kind":...,"status":...,
#    "conclusion":...,"tests":...,"total":...}}
# (every value a string; the receiver accepts nothing else) and requires
# HTTP 204. The arguments are checked before anything is sent, so the payload
# only ever holds these five fixed shapes. The token goes to curl as a header
# on stdin (-H @-), never in the arguments; --disable first.
#
# Exit 0 sent (204), or skipped (no receiver or no token: one ::warning::).
# Exit 1 the dispatch failed (another status, or no answer): a failed send
# fails, it is never only a warning. Exit 2 a bad argument or a malformed
# REPORT_TARGET_REPO; no request is made then.
# Self-test: Scripts/test_report_dispatch.sh.

set -euo pipefail
# Tracing off: the token must never reach a trace.
set +x

EVENT_TYPE="forsgren-report"
KINDS="selftests"

bad() {
  echo "::error::dispatch_report: $1"
  exit 2
}

[[ "$#" -eq 5 ]] || bad "five arguments: <kind> <status> <conclusion> <tests> <total>, got $#"
kind="$1"; status="$2"; conclusion="$3"; tests="$4"; total="$5"

[[ " ${KINDS} " == *" ${kind} "* && -n "$kind" ]] || bad "unknown kind '${kind}' (one of: ${KINDS})"
case "$status" in
  in_progress)
    [[ -z "$conclusion" ]] || bad "a run in progress has no conclusion (got '${conclusion}')" ;;
  completed)
    case "$conclusion" in
      success|failure|cancelled) ;;
      *) bad "conclusion '${conclusion}' (success, failure or cancelled)" ;;
    esac ;;
  *) bad "status '${status}' (in_progress or completed)" ;;
esac
[[ "$tests" =~ ^([0-9]{1,6}|XX)$ ]] || bad "tests '${tests}' (digits or XX)"
[[ "$total" =~ ^([0-9]{1,6}|XX)$ ]] || bad "total '${total}' (digits or XX)"

if [[ -z "${REPORT_TARGET_REPO:-}" ]]; then
  echo "::warning::dispatch_report: the secret REPORT_TARGET_REPO is not set; the ${kind} outcome was not sent"
  exit 0
fi
if [[ -z "${REPORT_DISPATCH_TOKEN:-}" ]]; then
  echo "::warning::dispatch_report: the secret REPORT_DISPATCH_TOKEN is not set; the ${kind} outcome was not sent"
  exit 0
fi
[[ "$REPORT_TARGET_REPO" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] \
  || bad "REPORT_TARGET_REPO is not owner/name"

body="$(printf '{"event_type":"%s","client_payload":{"kind":"%s","status":"%s","conclusion":"%s","tests":"%s","total":"%s"}}' \
  "$EVENT_TYPE" "$kind" "$status" "$conclusion" "$tests" "$total")"
url="https://api.github.com/repos/${REPORT_TARGET_REPO}/dispatches"

rc=0
code="$(printf 'Authorization: Bearer %s\n' "$REPORT_DISPATCH_TOKEN" \
  | curl --disable --silent --show-error --max-time 30 --proto '=https' \
    --output /dev/null --write-out '%{http_code}' \
    -X POST -H @- \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -d "$body" "$url" 2>/dev/null)" || rc=$?

if [[ "$rc" -ne 0 ]]; then
  echo "::error::dispatch_report: curl failed (exit ${rc}) before GitHub answered; the ${kind} outcome was not sent"
  exit 1
fi
if [[ "$code" != "204" ]]; then
  echo "::error::dispatch_report: GitHub answered status ${code}, not 204; the ${kind} outcome was not sent"
  exit 1
fi
echo "OK: ${kind} ${status} ${conclusion:-(running)} ${tests}/${total} sent (status 204)"
