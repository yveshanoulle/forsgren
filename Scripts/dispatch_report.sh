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
# Usage: Scripts/dispatch_report.sh selftests <status> <conclusion> <tests> <total> [<checks>]
#        Scripts/dispatch_report.sh quality <status> <conclusion> [<checks>]
#
#   kind        what is reported: selftests (the Self-tests run) or quality
#               (the Quality run: its start, quality in_progress "", and its
#               result, quality completed <conclusion> with its checks, or
#               without them when the run has no count)
#   status      in_progress | completed
#   conclusion  empty for in_progress; success | failure | cancelled for
#               completed
#   tests       digits (at most 6) or XX (unknown); selftests only
#   total       digits (at most 6) or XX (unknown); selftests only
#   checks      the checks that ran, the number of the run's Total checks
#               row (Scripts/render_quality_summary.sh --checks): 0, or 1 to
#               7 digits without a leading zero. Never XX: a run without a
#               count sends no checks (the receiver keeps its last value).
#               Only when completed.
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
#    "conclusion":...,"tests":...,"total":...[,"checks":...]}}
# or, for quality, {"kind":"quality","status":"in_progress"} at the start (no
# conclusion), {"kind":"quality","status":"completed","conclusion":...[,
# "checks":...]} at the end (every value a string; the receiver accepts
# nothing else) and
# requires HTTP 204. The arguments are checked before anything is sent, so
# the payload only ever holds these fixed shapes. The token goes to curl as a header
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
KINDS="selftests quality"

bad() {
  echo "::error::dispatch_report: $1"
  exit 2
}

kind="${1-}"
[[ " ${KINDS} " == *" ${kind} "* && -n "$kind" ]] || bad "unknown kind '${kind}' (one of: ${KINDS})"
tests=""; total=""; checks=""; has_checks=false
if [[ "$kind" == "quality" ]]; then
  [[ "$#" -eq 3 || "$#" -eq 4 ]] || bad "three arguments: quality <status> <conclusion>, or four with <checks>, got $#"
  base=3
else
  [[ "$#" -eq 5 || "$#" -eq 6 ]] || bad "five arguments: <kind> <status> <conclusion> <tests> <total>, or six with <checks>, got $#"
  base=5
  tests="$4"; total="$5"
fi
status="$2"; conclusion="$3"
if [[ "$#" -gt "$base" ]]; then
  checks="${!#}"; has_checks=true
  [[ "$status" == "completed" ]] || bad "only a completed run has checks (got '${status}')"
fi
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
if [[ "$kind" == "selftests" ]]; then
  [[ "$tests" =~ ^([0-9]{1,6}|XX)$ ]] || bad "tests '${tests}' (digits or XX)"
  [[ "$total" =~ ^([0-9]{1,6}|XX)$ ]] || bad "total '${total}' (digits or XX)"
fi
[[ "$has_checks" == "false" || "$checks" =~ ^(0|[1-9][0-9]{0,6})$ ]] \
  || bad "checks '${checks}' (0, or 1 to 7 digits without a leading zero; never XX)"

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

if [[ "$kind" == "quality" && "$status" == "in_progress" ]]; then
  fields="$(printf '"kind":"%s","status":"%s"' "$kind" "$status")"
  what="(start)"
elif [[ "$kind" == "quality" ]]; then
  fields="$(printf '"kind":"%s","status":"%s","conclusion":"%s"' "$kind" "$status" "$conclusion")"
  what="(no checks count)"
  if [[ "$has_checks" == "true" ]]; then
    fields+="$(printf ',"checks":"%s"' "$checks")"
    what="checks ${checks}"
  fi
else
  fields="$(printf '"kind":"%s","status":"%s","conclusion":"%s","tests":"%s","total":"%s"' "$kind" "$status" "$conclusion" "$tests" "$total")"
  what="${tests}/${total}"
  if [[ "$has_checks" == "true" ]]; then
    fields+="$(printf ',"checks":"%s"' "$checks")"
    what+=", checks ${checks}"
  fi
fi
body="$(printf '{"event_type":"%s","client_payload":{%s}}' "$EVENT_TYPE" "$fields")"
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
echo "OK: ${kind} ${status} ${conclusion:-(running)} ${what} sent (status 204)"
