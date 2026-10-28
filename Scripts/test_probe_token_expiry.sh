#!/usr/bin/env bash
# Scripts/test_probe_token_expiry.sh
#
# Self-test for Scripts/probe_token_expiry.sh (forsgren#269) and for the pin of
# .github/workflows/token_expiry_probe.yml. No network: a stub curl (PROBE_CURL)
# answers from a file per token and reads its config from stdin, as curl does.
#   1. a dated header           -> <NAME><TAB>2026-12-27, the time cut off
#   2. a 200 with no header     -> never
#   3. HTTP 401, a curl failure, an unreadable header, a secret not set
#                               -> error: <reason> on its line, the other
#                                  lines still written, exit 1, a ❌ naming it
#   4. a token is never in the arguments, stdin carries it, never in output
#   5. usage
#   6. the workflow: schedule and workflow_dispatch only, contents: read, the
#      three secrets in env, the artifact uploaded when the probe failed
# Mutation proofs: an error line that exits 0; a missing header taken as an
# error; a token on the command line.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
selftest_begin "token expiry probe self-test"
D='$'
T=$'\t'

PROBE="Scripts/probe_token_expiry.sh"
WORKFLOW=".github/workflows/token_expiry_probe.yml"
[[ -f "$PROBE" ]] || selftest_abort "${PROBE} does not exist — a token that expires would be seen only when a workflow stops"

STUBS="${TMP}/bin"
STATE="${TMP}/state"
mkdir -p "$STUBS" "$STATE"
cat > "${STUBS}/curl" << 'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LOG:?}"
token="$(sed -n 's/^header = "Authorization: Bearer \(.*\)"$/\1/p')"
if [ -z "$token" ]; then echo "stub: no token on stdin" >&2; exit 2; fi
if [ -f "${STUB_STATE:?}/${token}.fail" ]; then exit 7; fi
cat "${STUB_STATE}/${token}"
STUB
chmod +x "${STUBS}/curl"

# answer <token> <status> [header value]
answer() {
  {
    printf 'HTTP/2 %s\r\ncontent-type: application/json\r\n' "$2"
    if [[ -n "${3:-}" ]]; then printf 'github-authentication-token-expiration: %s\r\n' "$3"; fi
    printf 'x-ratelimit-limit: 5000\r\n\r\n'
  } > "${STATE}/$1"
}
reset() {
  rm -f "${STATE:?}"/*
  : > "${TMP}/curl.log"
  answer rel-token 200 "2026-12-27 10:00:00 UTC"
  answer prev-token 200 "2027-01-05 00:00:00 UTC"
  answer fg-token 200 "2026-11-30 23:59:59 UTC"
}
probe() {
  PATH="${STUBS}:${PATH}" PROBE_CURL="${STUBS}/curl" STUB_LOG="${TMP}/curl.log" STUB_STATE="$STATE" \
    FORSGREN_RELEASE_TOKEN="${REL-rel-token}" PREVIEW_DISPATCH_TOKEN="${PREV-prev-token}" FORSGREN_TOKEN="${FG-fg-token}" \
    capture "${SCRIPT:-$PROBE}" "${TMP}/token-probed.tsv"
}
want_line() {
  if grep -qxF -- "$2" "${TMP}/token-probed.tsv"; then echo "  ok: $1"; else fail "$1: the file lacks the line '$2'. File: $(cat "${TMP}/token-probed.tsv" 2> /dev/null)"; fi
}

# 1
reset
probe
want_green "three dated tokens" "FORSGREN_TOKEN"
want_line "the header time is cut to the date" "FORSGREN_RELEASE_TOKEN${T}2026-12-27"
want_line "second token" "PREVIEW_DISPATCH_TOKEN${T}2027-01-05"
want_line "third token" "FORSGREN_TOKEN${T}2026-11-30"
if [[ "$(grep -c . "${TMP}/token-probed.tsv")" == 3 ]]; then echo "  ok: one line per secret"; else fail "the file does not hold three lines"; fi

# 2
reset
answer prev-token 200
probe
want_green "a token without an expiry header is not an error" "PREVIEW_DISPATCH_TOKEN never"
want_line "it is never" "PREVIEW_DISPATCH_TOKEN${T}never"

# 3
reset
answer prev-token 401
probe
want_red "a refused token" "❌ PREVIEW_DISPATCH_TOKEN error: HTTP 401"
want_line "the refused line" "PREVIEW_DISPATCH_TOKEN${T}error: HTTP 401"
want_line "the other tokens are still probed" "FORSGREN_TOKEN${T}2026-11-30"
reset
touch "${STATE}/fg-token.fail"
probe
want_red "curl fails" "❌ FORSGREN_TOKEN error: curl failed (exit 7)"
reset
answer rel-token 200 "next tuesday"
probe
want_red "an unreadable header" "❌ FORSGREN_RELEASE_TOKEN error: unreadable expiry header: next tuesday"
reset
REL="" probe
want_red "a secret not set" "❌ FORSGREN_RELEASE_TOKEN error: secret is not set"
want_line "its line is written, not skipped" "FORSGREN_RELEASE_TOKEN${T}error: secret is not set"
if [[ "$(grep -c . "${TMP}/curl.log")" == 2 ]]; then echo "  ok: no call without a token"; else fail "curl was called for an unset secret: $(cat "${TMP}/curl.log")"; fi

# 4
reset
probe
if grep -qE 'rel-token|prev-token|fg-token' "${TMP}/curl.log"; then fail "a token is in the arguments of curl: $(cat "${TMP}/curl.log")"; else echo "  ok: no token in the arguments"; fi
if grep -qE 'rel-token|prev-token|fg-token' <<< "$OUT"; then fail "a token is in the output"; else echo "  ok: no token in the output"; fi

# 5
PATH="${STUBS}:${PATH}" capture "$PROBE"
want_exit "no argument" 2 "usage"

# 6 the workflow
code() { grep -vE '^[[:space:]]*#' "$1"; }
if [[ ! -f "$WORKFLOW" ]]; then
  fail "${WORKFLOW} does not exist: nothing probes the tokens on a schedule"
else
  events="$(awk '/^on:/{i=1;next} i&&/^[^[:space:]#]/{i=0} i&&/^  [a-z_]+:/{s=$1;sub(/:/,"",s);print s}' "$WORKFLOW" | LC_ALL=C sort | tr '\n' ' ')"
  if [[ "$events" == "schedule workflow_dispatch " ]]; then echo "  ok: schedule and workflow_dispatch only"; else fail "workflow triggers: ${events}"; fi
  if awk '/^permissions:/{getline; if ($0=="  contents: read") ok=1} END{exit !ok}' "$WORKFLOW" && ! code "$WORKFLOW" | has -qE ': write|write-all'; then echo "  ok: contents: read only"; else fail "workflow permissions are not contents: read alone"; fi
  for s in FORSGREN_RELEASE_TOKEN PREVIEW_DISPATCH_TOKEN FORSGREN_TOKEN; do
    if code "$WORKFLOW" | has -qF "${s}: ${D}{{ secrets.${s} }}"; then echo "  ok: ${s} comes from the secret of that name"; else fail "the workflow does not pass ${s} from secrets.${s}"; fi
  done
  if code "$WORKFLOW" | has -qF './Scripts/probe_token_expiry.sh token-probed.tsv'; then echo "  ok: the probe script writes token-probed.tsv"; else fail "the workflow does not run the script on token-probed.tsv"; fi
  if code "$WORKFLOW" | has -qF 'name: token-expiry-probe' && code "$WORKFLOW" | has -qF 'if: always()'; then echo "  ok: the artifact is uploaded even when the probe fails"; else fail "no always() upload of token-expiry-probe"; fi
  if code "$WORKFLOW" | has -qF 'persist-credentials: false'; then echo "  ok: checkout keeps no credentials"; else fail "checkout persists credentials"; fi
fi

# Mutation proofs
mutant() {
  selftest_mutant "$PROBE" "${TMP}/mut/$1/probe_token_expiry.sh" "$2" || return 1
  SCRIPT="${TMP}/mut/$1/probe_token_expiry.sh"
}
if mutant exit0 's/^  exit 1$/  exit 0/'; then
  reset
  answer prev-token 401
  probe
  if [[ "$RC" -eq 0 ]]; then echo "  ok: mutation proof: an error line that exits 0 is caught"; else fail "mutation proof: the mutant still exits ${RC}"; fi
fi
if mutant nohdr 's/^    echo "never"$/    echo "error: no header"/'; then
  reset
  answer prev-token 200
  probe
  if [[ "$RC" -eq 1 ]]; then echo "  ok: mutation proof: a missing header taken as an error is caught"; else fail "mutation proof: the mutant exits ${RC} on a missing header"; fi
fi
if mutant argv "s/-D - -o/-H \"Authorization: Bearer ${D}token\" -D - -o/"; then
  reset
  probe
  if grep -qE 'rel-token' "${TMP}/curl.log"; then echo "  ok: mutation proof: a token in the arguments is caught"; else fail "mutation proof: the mutant still keeps the token out of the arguments"; fi
fi
unset SCRIPT

selftest_end "the token expiry probe does not hold" "token expiry probe: dated, never, and every error kind land on the right line, the token stays out of arguments and output"
