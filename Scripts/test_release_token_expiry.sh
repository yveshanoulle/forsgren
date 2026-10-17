#!/usr/bin/env bash
# Scripts/test_release_token_expiry.sh
#
# Self-test for Scripts/release_token_expiry.sh (forsgren#221, step 4): the
# line about FORSGREN_RELEASE_TOKEN that opens every Release run page. No
# network and no wall clock: a stub gh answers `gh api -i` with the response
# headers of a file, and "now" is RELEASE_NOW, 2026-10-18 00:00:00 UTC.
#   1. more than 30 days left               -> ✅ valid until <date> (<n> days)
#   2. 30 to 8 days                         -> ⚠️ and a ::warning::
#   3. 7 days or fewer                      -> 🔴 and an ::error::, exit 0 (the
#                                              run continues)
#   4. expired, no header (a token without an expiry, said so), an unreadable
#      date, a refused call, no token       -> ❌, exit 1
#   5. the line is the first of the job summary; the token reaches gh as GH_TOKEN
#   6. usage
# The tier edges are 31/30 and 8/7 days, exactly. Mutation proofs: a copy with
# each edge moved by one day, and a copy that takes no header for fine, must
# each be caught.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release token expiry self-test"
D='$'

EXPIRY="Scripts/release_token_expiry.sh"
[[ -f "$EXPIRY" ]] || selftest_abort "${EXPIRY} does not exist — the token's expiry would show only when it has already stopped a release"

NOW=1792281600
STUBS="${TMP}/bin"
STATE="${TMP}/state"
mkdir -p "$STUBS" "$STATE"
cat > "${STUBS}/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "${GH_TOKEN-unset}" "$*" >> "${STUB_LOG:?}"
if [ -f "${STUB_STATE:?}/refused" ]; then echo "gh: Bad credentials (HTTP 401)" >&2; exit 1; fi
cat "${STUB_STATE}/response"
STUB
chmod +x "${STUBS}/gh"

# respond <expiry value or "-">: the response headers the stub answers with.
respond() {
  rm -f "${STATE}/refused" "${TMP}/gh.log"
  : > "${TMP}/gh.log"
  {
    printf 'HTTP/2.0 200 OK\r\n'
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    if [[ "$1" != "-" ]]; then printf 'github-authentication-token-expiration: %s\r\n' "$1"; fi
    printf 'X-Ratelimit-Limit: 5000\r\n\r\n{"id":1}\n'
  } > "${STATE}/response"
}
expiry() {
  PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_STATE="$STATE" GITHUB_REPOSITORY="acme/forsgren" \
    RELEASE_TEMPLATE_REPO="acme/tpl" RELEASE_NOW="$NOW" FORSGREN_RELEASE_TOKEN="${TOKEN-rt-token}" \
    capture "${SCRIPT:-$EXPIRY}" "$@"
}

# 1
respond "2026-12-02 00:00:00 UTC"
expiry
want_green "45 days left" "✅ FORSGREN_RELEASE_TOKEN valid until 2026-12-02 (45 days)"
if grep -q '::warning::\|::error::' <<< "$OUT"; then fail "the long tier prints an annotation. Output: ${OUT}"; fi
respond "2026-11-18 00:00:00 UTC"
expiry
want_green "31 days left is the first green day" "✅ FORSGREN_RELEASE_TOKEN valid until 2026-11-18 (31 days)"
respond "2026-11-17 23:00:00 UTC"
expiry
want_green "30 days and 23 hours is 30 days: the warning tier" "⚠️ FORSGREN_RELEASE_TOKEN expires on 2026-11-17 (30 days): renew it before the next release"

# 2
respond "2026-11-17 00:00:00 UTC"
expiry
want_green "30 days left" "⚠️ FORSGREN_RELEASE_TOKEN expires on 2026-11-17 (30 days): renew it before the next release"
want_said "30 days: a ::warning::" "::warning::FORSGREN_RELEASE_TOKEN expires on 2026-11-17 (30 days)"
respond "2026-10-26 00:00:00 UTC"
expiry
want_green "8 days left is the last warning day" "⚠️ FORSGREN_RELEASE_TOKEN expires on 2026-10-26 (8 days)"
if grep -q '::error::' <<< "$OUT"; then fail "the warning tier prints an ::error::. Output: ${OUT}"; fi

# 3
respond "2026-10-25 23:00:00 UTC"
expiry
want_green "7 days and 23 hours is 7 days: the red tier" "🔴 FORSGREN_RELEASE_TOKEN expires on 2026-10-25 (7 days)"
want_said "7 days: an ::error::" "::error::FORSGREN_RELEASE_TOKEN expires on 2026-10-25 (7 days)"
respond "2026-10-19 00:00:00 UTC"
expiry
want_green "1 day left, the run continues" "🔴 FORSGREN_RELEASE_TOKEN expires on 2026-10-19 (1 days)"
respond "2026-10-18 00:00:01 UTC"
expiry
want_green "one second left, the run continues" "🔴 FORSGREN_RELEASE_TOKEN expires on 2026-10-18 (0 days)"

# 4
respond "2026-10-18 00:00:00 UTC"
expiry
want_red "expired this second" "❌ FORSGREN_RELEASE_TOKEN expired on 2026-10-18"
respond "2026-10-17 00:00:00 UTC"
expiry
want_red "expired yesterday" "❌ FORSGREN_RELEASE_TOKEN expired on 2026-10-17"
respond "-"
expiry
want_red "no expiry header" "❌ FORSGREN_RELEASE_TOKEN has no expiry date"
want_said "it says what that means" "a token without an expiry is not accepted"
respond "next tuesday"
expiry
want_red "an unreadable date" "❌ FORSGREN_RELEASE_TOKEN has an expiry date that cannot be read: next tuesday"
respond "2026-12-02 00:00:00 UTC"
touch "${STATE}/refused"
expiry
want_red "a refused call" "❌ FORSGREN_RELEASE_TOKEN could not be used"
respond "2026-12-02 00:00:00 UTC"
TOKEN="" expiry
want_red "no token" "❌ FORSGREN_RELEASE_TOKEN is not set"
if [[ -s "${TMP}/gh.log" ]]; then fail "gh was called without a token"; else echo "  ok: gh is not called without a token"; fi

# 5
respond "2026-12-02 00:00:00 UTC"
rm -f "${TMP}/summary.md"
printf 'earlier text\n' > "${TMP}/summary.md"
: > "${TMP}/summary.md"
GITHUB_STEP_SUMMARY="${TMP}/summary.md" expiry
if [[ "$(head -n 1 "${TMP}/summary.md")" == "✅ FORSGREN_RELEASE_TOKEN valid until 2026-12-02 (45 days)" ]]; then echo "  ok: the line opens the job summary"; else fail "the summary does not open with the line: $(cat "${TMP}/summary.md")"; fi
if grep -q '^::' "${TMP}/summary.md"; then fail "an annotation is in the job summary"; else echo "  ok: no annotation in the job summary"; fi
if grep -q '^rt-token|api -i repos/acme/tpl' "${TMP}/gh.log"; then echo "  ok: the token is GH_TOKEN of one authenticated call on the template"; else fail "the call is not as pinned. Log: $(cat "${TMP}/gh.log")"; fi
respond "-"
: > "${TMP}/summary.md"
GITHUB_STEP_SUMMARY="${TMP}/summary.md" expiry
if grep -qF "❌ FORSGREN_RELEASE_TOKEN has no expiry date" "${TMP}/summary.md"; then echo "  ok: a failing line is in the job summary too"; else fail "the failing line is not in the summary"; fi

# 6
expiry extra
want_exit "an argument" 2 "usage"

# Mutation proofs: one per tier edge, and the missing header.
mutant() {
  selftest_mutant "$EXPIRY" "${TMP}/mut/$1/release_token_expiry.sh" "$2" || return 1
  SCRIPT="${TMP}/mut/$1/release_token_expiry.sh"
}
if mutant edge30 's/-gt 30 \]/-gt 31 ]/'; then
  respond "2026-11-18 00:00:00 UTC"
  expiry
  if grep -qF "✅" <<< "$OUT"; then fail "mutation proof: the mutant with the edge at 31 still says green on day 31"; else echo "  ok: mutation proof: moving the 30/31 edge turns day 31 yellow"; fi
fi
if mutant edge30b 's/-gt 30 \]/-gt 29 ]/'; then
  respond "2026-11-17 00:00:00 UTC"
  expiry
  if grep -qF "⚠️" <<< "$OUT"; then fail "mutation proof: the mutant with the edge at 29 still warns on day 30"; else echo "  ok: moving the edge the other way turns day 30 green"; fi
fi
if mutant edge7 's/-gt 7 \]/-gt 8 ]/'; then
  respond "2026-10-26 00:00:00 UTC"
  expiry
  if grep -qF "⚠️" <<< "$OUT"; then fail "mutation proof: the mutant with the edge at 8 still warns on day 8"; else echo "  ok: mutation proof: moving the 8/7 edge turns day 8 red"; fi
fi
if mutant edge7b 's/-gt 7 \]/-gt 6 ]/'; then
  respond "2026-10-25 00:00:00 UTC"
  expiry
  if grep -qF "🔴" <<< "$OUT"; then fail "mutation proof: the mutant with the edge at 6 still says red on day 7"; else echo "  ok: moving the edge the other way turns day 7 yellow"; fi
fi
if mutant nohdr "s/^if \[ -z \".RAW\" \]; then\$/if [ -z \"${D}RAW\" ]; then echo \"✅ no expiry\"; COMPLETED=1; exit 0; fi; if false; then/"; then
  respond "-"
  expiry
  if [[ "$RC" -eq 0 ]]; then echo "  ok: mutation proof: with no header taken as fine the check passes a token without an expiry"; else fail "mutation proof: the mutant still refuses a token without an expiry. Output: ${OUT}"; fi
fi
unset SCRIPT

selftest_end "the release token expiry does not hold" "release token expiry: the four tiers and their edges, no header, unreadable, expired and refused are all judged right"
