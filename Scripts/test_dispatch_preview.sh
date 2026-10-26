#!/usr/bin/env bash
# Scripts/test_dispatch_preview.sh
#
# Self-test for Scripts/dispatch_preview.sh (forsgren#222), the script that
# starts the preview deploy after a push to main. forsgren's own. No network:
# a stub `curl` on PATH answers with the status a case sets in STUB_STATUS
# (STUB_CURL_RC makes it fail like a connection error) and logs what it was
# called with: its arguments, and what it was handed on stdin. Cases:
#   1. a good sha, a token, status 204             -> OK
#   2. the request: POST to the preview repository's preview.yml dispatches
#      endpoint, ref main, the sha as the input, the token as a Bearer header
#   3. the token is never in the arguments (a process list shows them) and a
#      curlrc is disabled first
#   4. status 200 / 201 / 202 / 302 / 404 / 422 / 500 -> red naming the status
#   5. curl fails outright (no status)             -> red, exit 1
#   6. an empty or unset token                     -> ::error:: naming
#      PREVIEW_DISPATCH_TOKEN, curl never called, GH_TOKEN and GITHUB_TOKEN
#      are not a fallback
#   7. a bad sha (short, long, upper-case, not hex, empty, none) -> ::error::,
#      curl never called
# Mutation proofs: a copy that accepts any 2xx, a copy without the empty-token
# guard and a copy without the sha check must each let the case they exist for
# pass (the mutant is green where the real script is red).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
selftest_begin "dispatch preview self-test"

SCRIPT="Scripts/dispatch_preview.sh"
[[ -f "$SCRIPT" ]] || selftest_abort "${SCRIPT} does not exist: nothing starts the preview deploy"

STUBS="${TMP}/bin"
LOG="${TMP}/curl.log"
mkdir -p "$STUBS"
cat > "${STUBS}/curl" <<'STUB'
#!/usr/bin/env bash
# A curl that answers from the environment. It logs its arguments, and stdin
# when -H @- is given (the way the script hands the token over).
{
  echo "ARGS: $*"
  for arg in "$@"; do
    if [[ "$arg" == "@-" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do echo "STDIN: ${line}"; done
    fi
  done
} >> "${STUB_LOG:?}"
if [[ -n "${STUB_CURL_RC:-}" ]]; then
  exit "$STUB_CURL_RC"
fi
printf '%s' "${STUB_STATUS:-204}"
STUB
chmod +x "${STUBS}/curl"

# DOLLAR builds the sed expressions that hold a dollar sign in double quotes.
DOLLAR='$'
GOOD_SHA="0123456789abcdef0123456789abcdef01234567"

# run_script <script> <sha-args...>: the script against the stub, a token
# set unless the caller exported TOKEN_ENV differently; the log is cleared.
run_script() {
  local script="$1"
  shift
  : > "$LOG"
  capture env -i HOME="$TMP" PATH="${STUBS}:/usr/bin:/bin" STUB_LOG="$LOG" \
    STUB_STATUS="${STUB_STATUS:-204}" STUB_CURL_RC="${STUB_CURL_RC:-}" \
    PREVIEW_DISPATCH_TOKEN="${TOKEN_VALUE-tok_secret_value}" "$script" "$@"
}

# calls: how many times the stub curl was called.
calls() {
  grep -c '^ARGS:' "$LOG" || true
}

want_no_call() {
  if [[ "$(calls)" == 0 ]]; then
    echo "  ok: $1: curl was never called"
  else
    fail "$1: curl was called. Log: $(cat "$LOG")"
  fi
}

# 1 and 2: the good request.
run_script "$SCRIPT" "$GOOD_SHA"
want_green_ok "a 204 is the success"
want_said "the OK line names the sha" "$GOOD_SHA"
if [[ "$(calls)" == 1 ]]; then echo "  ok: one request"; else fail "want one request, got $(calls)"; fi
for want in \
  "-X POST" \
  "https://api.github.com/repos/yveshanoulle/forsgren-metrics-feta/actions/workflows/preview.yml/dispatches" \
  "{\"ref\":\"main\",\"inputs\":{\"sha\":\"${GOOD_SHA}\"}}"; do
  if grep -qF -- "$want" "$LOG"; then echo "  ok: request has: $want"; else fail "the request lacks '$want'. Log: $(cat "$LOG")"; fi
done
if grep -qxF "STDIN: Authorization: Bearer tok_secret_value" "$LOG"; then
  echo "  ok: the token goes in a Bearer header, on stdin"
else
  fail "the token did not reach the Authorization header on stdin. Log: $(cat "$LOG")"
fi

# 3: no token in the arguments, curlrc disabled.
if grep '^ARGS:' "$LOG" | has -qF "tok_secret_value"; then
  fail "the token is in curl's arguments, where a process list shows it"
else
  echo "  ok: the token is not in the arguments"
fi
if grep '^ARGS:' "$LOG" | has -qE '^ARGS: --disable '; then echo "  ok: a curlrc is disabled first"; else fail "curl is not given --disable first. Log: $(cat "$LOG")"; fi

# 4: any status but 204 is red, naming it.
for status in 200 201 202 302 404 422 500; do
  STUB_STATUS="$status" run_script "$SCRIPT" "$GOOD_SHA"
  want_red "status ${status}" "::error::"
  want_said "status ${status} is named" "status ${status}"
done

# 5: curl fails outright.
STUB_CURL_RC=7 run_script "$SCRIPT" "$GOOD_SHA"
want_red "curl fails" "::error::"

# 6: no token, no call, no fallback.
TOKEN_VALUE="" run_script "$SCRIPT" "$GOOD_SHA"
want_red "an empty token" "::error::dispatch_preview: PREVIEW_DISPATCH_TOKEN is empty"
want_no_call "an empty token"
: > "$LOG"
capture env -i HOME="$TMP" PATH="${STUBS}:/usr/bin:/bin" STUB_LOG="$LOG" \
  GH_TOKEN=other_login GITHUB_TOKEN=other_token "$SCRIPT" "$GOOD_SHA"
want_red "an unset token with GH_TOKEN and GITHUB_TOKEN set" "::error::dispatch_preview: PREVIEW_DISPATCH_TOKEN is empty"
want_no_call "an unset token with GH_TOKEN and GITHUB_TOKEN set"

# 7: a bad sha, no call.
for bad in "0123456" "${GOOD_SHA}0" "0123456789ABCDEF0123456789abcdef01234567" "0123456789abcdefg123456789abcdef01234567" ""; do
  run_script "$SCRIPT" "$bad"
  want_red "sha '${bad}'" "::error::"
  want_no_call "sha '${bad}'"
done
run_script "$SCRIPT"
want_red "no sha" "::error::"
want_no_call "no sha"

# Mutation proofs: the mutant is green where the real script is red.
M="${TMP}/mut"
if selftest_mutant "$SCRIPT" "${M}/any2xx.sh" "s/\"${DOLLAR}status\" != \"204\"/\"${DOLLAR}{status:0:1}\" != \"2\"/"; then
  STUB_STATUS=202 run_script "${M}/any2xx.sh" "$GOOD_SHA"
  if [[ "$RC" -eq 0 ]]; then echo "  ok: mutation proof: accepting any 2xx lets status 202 pass"; else fail "mutation proof: a 2xx-accepting copy still failed status 202. Output: $OUT"; fi
fi
if selftest_mutant "$SCRIPT" "${M}/notoken.sh" "s/-z \"${DOLLAR}{PREVIEW_DISPATCH_TOKEN:-}\"/-z \"x\"/"; then
  TOKEN_VALUE="" run_script "${M}/notoken.sh" "$GOOD_SHA"
  if [[ "$RC" -eq 0 && "$(calls)" == 1 ]]; then echo "  ok: mutation proof: without the empty-token guard curl is called with no token"; else fail "mutation proof: the copy without the token guard still refused (exit ${RC}, calls $(calls)). Output: $OUT"; fi
fi
if selftest_mutant "$SCRIPT" "${M}/nosha.sh" 's/\^\[0-9a-f\]{40}\$/^.*$/'; then
  run_script "${M}/nosha.sh" "0123456"
  if [[ "$RC" -eq 0 && "$(calls)" == 1 ]]; then echo "  ok: mutation proof: without the sha check a short sha is sent"; else fail "mutation proof: the copy without the sha check still refused (exit ${RC}, calls $(calls)). Output: $OUT"; fi
fi

selftest_end "the dispatch preview self-test found failures" "dispatch preview (204 only, the token only in a header on stdin, no token or bad sha never calls curl; 3 mutation proofs)"
