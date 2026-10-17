#!/usr/bin/env bash
# Scripts/live_check.sh
#
# The live check of the deployed starter page (forsgren#205, step 2 of 2,
# ruling item 3): after every forsgren.be deploy, with curl and no browser,
#   1. http://<host>/ answers 301 or 308 and its Location is exactly
#      https://<host>/
#   2. https://<host>/ answers 200 as text/html with the certificate
#      VALIDATED (curl is never given -k or --insecure, and --disable first
#      keeps a curlrc from adding it), and links a stylesheet
#   3. the stylesheet the page actually links (its href, resolved against the
#      base) answers 200 as text/css
# Every failed check prints a ❌ line naming the check and the value observed,
# and the script exits 1: a failed live check makes its job red, though it
# cannot undo the deploy. A deploy may take a moment to propagate, so the
# whole set is tried up to LIVE_CHECK_TRIES times (default 5), LIVE_CHECK_DELAY
# seconds apart (default 10); the OK line says how many tries it took.
#
# Usage: Scripts/live_check.sh <https-base-url>     e.g. https://forsgren.be
# Exit: 0 every check held, 1 a check failed on the last try, 2 usage.
#
# NOT a local gate: it needs the deployed site. Only the starter page
# workflow runs it. Fixture: Scripts/test_live_check.sh (a stub curl).

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: live_check.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

usage() {
  echo "usage: Scripts/live_check.sh <https-base-url>   (https://host, no path)" >&2
  COMPLETED=1
  exit 2
}

TRIES="${LIVE_CHECK_TRIES:-5}"
DELAY="${LIVE_CHECK_DELAY:-10}"
case "$TRIES" in
  ''|*[!0-9]*|0)
    echo "❌ FAIL: LIVE_CHECK_TRIES must be a positive integer, got '${TRIES}'" >&2
    COMPLETED=1
    exit 2
    ;;
esac
case "$DELAY" in
  ''|*[!0-9]*)
    echo "❌ FAIL: LIVE_CHECK_DELAY must be a number of seconds, got '${DELAY}'" >&2
    COMPLETED=1
    exit 2
    ;;
esac

[[ $# -eq 1 ]] || usage
[[ "$1" =~ ^https://([A-Za-z0-9.-]+)/?$ ]] || usage
HOST="${BASH_REMATCH[1]}"
HTTP_URL="http://${HOST}/"
HTTPS_URL="https://${HOST}/"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; [ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: live_check.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

# --disable first: a curlrc must not be able to switch validation off.
CURL_OPTS=(--disable --silent --show-error --max-time 20 --proto '=http,https')

FAILS=""
note_fail() { # <check> <observed text>
  FAILS="${FAILS}❌ FAIL: live check: $1: $2"$'\n'
}

# fetch <url> — headers in $WORK/headers, body in $WORK/body; sets CURL_RC,
# STATUS and CONTENT_TYPE (media type only, lower case; empty when absent).
fetch() {
  : > "$WORK/headers"
  : > "$WORK/body"
  CURL_RC=0
  curl "${CURL_OPTS[@]}" --output "$WORK/body" --dump-header "$WORK/headers" "$1" 2> "$WORK/stderr" || CURL_RC=$?
  STATUS="$(tr -d '\r' < "$WORK/headers" | awk '/^HTTP\// { s = $2 } END { print s }')"
  CONTENT_TYPE="$(tr -d '\r' < "$WORK/headers" | awk 'tolower($1) == "content-type:" { sub(/^[^:]*:[ \t]*/, ""); sub(/[ \t]*;.*$/, ""); v = tolower($0) } END { print v }')"
}

# curl_failed <check> <url> — records a curl failure; returns 0 when curl failed.
curl_failed() {
  [[ "$CURL_RC" -ne 0 ]] || return 1
  local check="$1"
  case "$CURL_RC" in
    51|58|59|60|77|82|83|90|91) check="certificate validation" ;;
  esac
  note_fail "$check" "curl exit ${CURL_RC} for $2: $(tr '\n' ' ' < "$WORK/stderr")"
  return 0
}

check_redirect() {
  fetch "$HTTP_URL"
  curl_failed "http redirect" "$HTTP_URL" && return
  local location
  location="$(tr -d '\r' < "$WORK/headers" | awk 'tolower($1) == "location:" { print $2 }' | head -1)"
  REDIRECT_STATUS="$STATUS"
  if [[ "$STATUS" != 301 && "$STATUS" != 308 ]]; then
    note_fail "http redirect" "${HTTP_URL} answered ${STATUS:-no status}, want 301 or 308 (Location ${location:-none})"
  elif [[ "$location" == "$HTTPS_URL" ]]; then
    :
  else
    note_fail "http redirect" "${HTTP_URL} answered ${STATUS} with Location ${location:-none}, want Location ${HTTPS_URL}"
  fi
}

# check_page — sets PAGE_OK=1 when the page is right, and STYLESHEET to the
# resolved URL of the first stylesheet it links.
check_page() {
  PAGE_OK=0
  STYLESHEET=""
  fetch "$HTTPS_URL"
  curl_failed "https page" "$HTTPS_URL" && return
  if [[ "$STATUS" != 200 ]]; then
    note_fail "https page" "${HTTPS_URL} answered ${STATUS:-no status}, want 200"
    return
  fi
  if [[ "$CONTENT_TYPE" != text/html ]]; then
    note_fail "https page" "${HTTPS_URL} answered 200 with Content-Type ${CONTENT_TYPE:-none}, want text/html"
    return
  fi
  PAGE_OK=1
  local href
  href="$(stylesheet_href "$WORK/body")"
  if [[ -z "$href" ]]; then
    note_fail "stylesheet" "${HTTPS_URL} has no stylesheet link (<link rel=\"stylesheet\" href=...>)"
    return
  fi
  STYLESHEET="$(resolve "$href")"
}

# stylesheet_href <html file> — the href of the first <link rel=stylesheet>.
stylesheet_href() {
  tr '\n\r' '  ' < "$1" \
    | grep -oiE '<link[^>]*>' \
    | grep -iE "rel=[\"']?stylesheet" \
    | sed -nE "s/.*[[:space:]]href=(\"([^\"]*)\"|'([^']*)').*/\2\3/Ip" \
    | head -1
}

# resolve <href> — against the page, which is the root of the host.
resolve() {
  case "$1" in
    http://*|https://*) printf '%s' "$1" ;;
    //*) printf 'https:%s' "$1" ;;
    /*) printf 'https://%s%s' "$HOST" "$1" ;;
    *) printf '%s%s' "$HTTPS_URL" "$1" ;;
  esac
}

check_stylesheet() {
  [[ "$PAGE_OK" -eq 1 && -n "$STYLESHEET" ]] || return 0
  fetch "$STYLESHEET"
  curl_failed "stylesheet" "$STYLESHEET" && return
  if [[ "$STATUS" != 200 ]]; then
    note_fail "stylesheet" "${STYLESHEET} answered ${STATUS:-no status}, want 200"
  elif [[ "$CONTENT_TYPE" != text/css ]]; then
    note_fail "stylesheet" "${STYLESHEET} answered 200 with Content-Type ${CONTENT_TYPE:-none}, want text/css"
  fi
}

try=1
while :; do
  FAILS=""
  REDIRECT_STATUS=""
  check_redirect
  check_page
  check_stylesheet
  [[ -z "$FAILS" ]] && break
  if [[ "$try" -ge "$TRIES" ]]; then
    printf '%s' "$FAILS"
    echo "❌ FAIL: live check of ${HTTPS_URL} failed after ${try} of ${TRIES} tries"
    COMPLETED=1
    exit 1
  fi
  echo "  try ${try} of ${TRIES} failed, trying again in ${DELAY} s: $(printf '%s' "$FAILS" | head -1)"
  try=$((try + 1))
  sleep "$DELAY"
done

noun="tries"
[[ "$try" -eq 1 ]] && noun="try"
COMPLETED=1
echo "OK: live check of ${HTTPS_URL}: http redirects ${REDIRECT_STATUS} to ${HTTPS_URL}; https page 200 text/html (certificate validated); stylesheet ${STYLESHEET} 200 text/css (${try} ${noun})"
