#!/usr/bin/env bash
# Scripts/probe_token_expiry.sh <out-file>   (forsgren#269)
#
# The expiry of each fine-grained token forsgren's own workflows use, read
# from GitHub's `github-authentication-token-expiration` response header on
# one cheap authenticated call (GET /user) per token. The secrets arrive in
# the environment, by name: FORSGREN_RELEASE_TOKEN, PREVIEW_DISPATCH_TOKEN and
# FORSGREN_TOKEN. <out-file> gets one line per secret, in that order:
#
#   <SECRET_NAME><TAB><YYYY-MM-DD | never | error: <reason>>
#
#   a header "2026-12-27 10:00:00 UTC"  -> 2026-12-27
#   an answer 2xx with no header         -> never (GitHub sends the header only
#                                           for a token that expires)
#   not set, refused (HTTP 401 ...), curl failed, a header that cannot be read
#                                        -> error: <reason>; never a skip
#
# A token is never an argument and never printed: it reaches curl as a config
# line on stdin. Every secret is probed and the file is written whole; the
# script then exits 1 with one ❌ line per error line, so the job turns red
# after the artifact is uploaded. Exit 0 when no line is an error, 2 usage.
# PROBE_CURL (default curl) and PROBE_URL are the self-test's seams.
# Self-test: Scripts/test_probe_token_expiry.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: probe_token_expiry.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

if [ "$#" -ne 1 ]; then
  echo "usage: Scripts/probe_token_expiry.sh <out-file>   (the three tokens in the environment)" >&2
  COMPLETED=1
  exit 2
fi

OUT_FILE="$1"
CURL="${PROBE_CURL:-curl}"
URL="${PROBE_URL:-https://api.github.com/user}"
NAMES="FORSGREN_RELEASE_TOKEN PREVIEW_DISPATCH_TOKEN FORSGREN_TOKEN"
DATE_RE='^([0-9]{4}-[0-9]{2}-[0-9]{2}) [0-9]{2}:[0-9]{2}:[0-9]{2} UTC$'

# probe <name>: the value for the secret of that name, one line.
probe() {
  local token="${!1:-}" headers rc status raw
  if [ -z "$token" ]; then
    echo "error: secret is not set"
    return
  fi
  headers="$(printf 'header = "Authorization: Bearer %s"\n' "$token" | "$CURL" -sS -D - -o /dev/null --max-time 30 --config - "$URL" 2> /dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "error: curl failed (exit ${rc})"
    return
  fi
  headers="$(printf '%s\n' "$headers" | tr -d '\r')"
  status="$(printf '%s\n' "$headers" | sed -n '1s/^HTTP\/[0-9.]* \([0-9][0-9]*\).*/\1/p')"
  case "$status" in
    2??) ;;
    '')
      echo "error: no HTTP status in the answer"
      return
      ;;
    *)
      echo "error: HTTP ${status}"
      return
      ;;
  esac
  raw="$(printf '%s\n' "$headers" | sed -n 's/^[Gg]ithub-[Aa]uthentication-[Tt]oken-[Ee]xpiration: *//p' | head -n 1)"
  if [ -z "$raw" ]; then
    echo "never"
  elif [[ "$raw" =~ $DATE_RE ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "error: unreadable expiry header: $(printf '%s' "$raw" | tr -d '\t' | cut -c1-40)"
  fi
}

LINES=""
for name in $NAMES; do
  LINES="${LINES}${name}"$'\t'"$(probe "$name")"$'\n'
done
printf '%s' "$LINES" > "$OUT_FILE"

errors=0
while IFS=$'\t' read -r name value; do
  if [[ "$value" == error:* ]]; then
    echo "❌ ${name} ${value}"
    errors=$((errors + 1))
  else
    echo "✅ ${name} ${value}"
  fi
done <<< "$LINES"
if [ "$errors" -gt 0 ]; then
  echo "❌ ${errors} token(s) could not be read: renew or set them (see the lines above)"
  COMPLETED=1
  exit 1
fi
COMPLETED=1
