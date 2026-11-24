#!/usr/bin/env bash
# Scripts/test_report_dispatch.sh
#
# Self-test of Scripts/dispatch_report.sh (the outcome of a run sent to the
# maintainer's receiving repository as a repository_dispatch) and
# Scripts/selftests_counts.sh (how many self-tests ran, of how many), the
# two steps of .github/workflows/selftests.yml that run them, and the checks
# step of .github/workflows/quality.yml's report job. forsgren's own.
# No network: a stub `curl` on PATH logs its arguments and stdin and answers
# with STUB_STATUS (STUB_CURL_RC fails it like a connection error).
#
# Counts:
#   C1. tests: the distinct listed labels with a ✅ or ❌ row; a row of an
#       unlisted label, another mark, or twice, is not counted; total: the
#       listed labels
#   C2. no rows file (the start of a run): tests=0
#   C3. an empty or missing labels file: both XX
#   C4. a usage error: exit 64
# Dispatch:
#   D1. completed: one POST to repos/<target>/dispatches, the exact body
#       (event_type forsgren-report, five string values), the token a Bearer
#       header on stdin, never in the arguments, --disable first; OK line
#   D2. in_progress with an empty conclusion: sent, conclusion ""
#   D3. no REPORT_TARGET_REPO, or no REPORT_DISPATCH_TOKEN: ::warning::,
#       exit 0, curl never called; GH_TOKEN and GITHUB_TOKEN are no fallback
#   D4. a bad kind, status, conclusion, tests or total (an injection attempt
#       among them): exit 2, curl never called
#   D5. a target that is not owner/name: exit 2, curl never called
#   D6. any status but 204, or curl failing: exit 1, named
#   D7. neither the receiver nor the token is ever printed (the run log is public)
#   D8. a completed selftests outcome with checks: the exact body, checks a
#       sixth string value
#   D9. kind quality: quality completed <conclusion> <checks>, the exact body
#       (kind, status, conclusion, checks)
#   D10. refused, exit 2, curl never called: checks -1, 1.5, 01, XX, empty,
#       eight digits, a leading space, an injection; checks on a run in
#       progress; quality in progress, with five or three arguments
# Workflow:
#   W1. the report_start job: ubuntu-latest, no needs, contents: read, its
#       step runs Scripts/dispatch_report.sh selftests in_progress with the
#       two secrets in its env
#   W2. the report job's last step: if: always(), runs
#       Scripts/dispatch_report.sh selftests completed, the counts from
#       Scripts/selftests_counts.sh, the conclusion from
#       merge_quality_report.sh status
#   W2. also: checks from Scripts/render_quality_summary.sh --selftests
#       --checks; a run without a count sends its outcome without checks and
#       the step exits 1
#   W3. the secret appears only as the env value of those two steps, and no
#       run: line expands a ${{ }} expression of the two secrets
#   W4. quality.yml's report job: its last step "Report the checks", if:
#       always() and never on a pull request, checks from
#       Scripts/render_quality_summary.sh --checks (a missing count exits 1,
#       nothing sent), Scripts/dispatch_report.sh quality completed; the two
#       secrets only as the env of that step, no run: line expands them
# Mutation proofs (each copy lets through what the real script refuses):
#   A. the tests check removed: a payload text is sent
#   B. the token guard removed: curl is called with no token
#   C. any 2xx accepted: 202 passes
#   D. the in_progress conclusion check removed: a conclusion is sent
#   E. counts: any mark counted
#   F. counts: unlisted labels counted
#   G. the checks check removed: a payload text is sent as checks
#   H. quality's completed-only check removed: quality in progress is sent

# The expected request texts and the mutation texts hold a literal $, so they stay in
# single quotes.
# shellcheck disable=SC2016
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
selftest_begin "report dispatch self-test"

SCRIPT="Scripts/dispatch_report.sh"
COUNTS="Scripts/selftests_counts.sh"
WORKFLOW=".github/workflows/selftests.yml"
for f in "$SCRIPT" "$COUNTS" "$WORKFLOW"; do
  [[ -f "$f" ]] || selftest_abort "${f} does not exist"
done

STUBS="${TMP}/bin"
LOG="${TMP}/curl.log"
mkdir -p "$STUBS"
cat > "${STUBS}/curl" <<'STUB'
#!/usr/bin/env bash
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

DOLLAR='$'

# send <script> <args...>: the script against the stub; TARGET_VALUE and
# TOKEN_VALUE override the two inputs (empty: unset in effect).
send() {
  local script="$1"
  shift
  : > "$LOG"
  capture env -i HOME="$TMP" PATH="${STUBS}:/usr/bin:/bin" STUB_LOG="$LOG" \
    STUB_STATUS="${STUB_STATUS:-204}" STUB_CURL_RC="${STUB_CURL_RC:-}" \
    REPORT_TARGET_REPO="${TARGET_VALUE-acme/receiver}" \
    REPORT_DISPATCH_TOKEN="${TOKEN_VALUE-tok_secret_value}" "$script" "$@"
}

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

want_logged() {
  if grep -qF -- "$2" "$LOG"; then echo "  ok: $1"; else fail "$1: the request lacks '$2'. Log: $(cat "$LOG")"; fi
}

# ---- counts --------------------------------------------------------------
LABELS="${TMP}/labels.txt"
ROWS="${TMP}/rows.md"
printf '%s\n' "alpha self-test" "beta self-test" "gamma self-test" "delta self-test" > "$LABELS"
printf '%s\n' "alpha self-test|✅" "beta self-test|❌" "alpha self-test|✅" "gamma self-test|⏭" \
  "quality only gate|✅" "" > "$ROWS"

capture "$COUNTS" "$ROWS" "$LABELS"
want_said "C1 tests counts the listed rows marked ✅ or ❌ once each" "tests=2"
want_said "C1 total counts every listed label" "total=4"
want_rc "C1 exit 0" 0

capture "$COUNTS" "${TMP}/no_rows.md" "$LABELS"
want_said "C2 no rows file: tests=0" "tests=0"
want_said "C2 no rows file: total stays" "total=4"

: > "${TMP}/empty.txt"
capture "$COUNTS" "$ROWS" "${TMP}/empty.txt"
want_said "C3 empty labels: tests XX" "tests=XX"
want_said "C3 empty labels: total XX" "total=XX"
capture "$COUNTS" "$ROWS" "${TMP}/missing.txt"
want_said "C3 missing labels: total XX" "total=XX"
want_rc "C3 exit 0 (the caller reports XX)" 0

capture "$COUNTS" "$ROWS"
want_rc "C4 one argument is a usage error" 64

# ---- dispatch ------------------------------------------------------------
send "$SCRIPT" selftests completed success 12 34
want_green_ok "D1 a 204 is the success"
if [[ "$(calls)" == 1 ]]; then echo "  ok: D1 one request"; else fail "D1 want one request, got $(calls)"; fi
want_logged "D1 POST" "-X POST"
want_logged "D1 the receiver's dispatches endpoint" "https://api.github.com/repos/acme/receiver/dispatches"
want_logged "D1 the exact body" '{"event_type":"forsgren-report","client_payload":{"kind":"selftests","status":"completed","conclusion":"success","tests":"12","total":"34"}}'
if grep -qxF "STDIN: Authorization: Bearer tok_secret_value" "$LOG"; then
  echo "  ok: D1 the token goes in a Bearer header, on stdin"
else
  fail "D1 the token did not reach the Authorization header on stdin. Log: $(cat "$LOG")"
fi
if grep '^ARGS:' "$LOG" | has -qF "tok_secret_value"; then
  fail "D1 the token is in curl's arguments"
else
  echo "  ok: D1 the token is not in the arguments"
fi
if grep '^ARGS:' "$LOG" | has -qE '^ARGS: --disable '; then echo "  ok: D1 a curlrc is disabled first"; else fail "D1 curl is not given --disable first"; fi

send "$SCRIPT" selftests in_progress "" 0 XX
want_green_ok "D2 a start is sent"
want_logged "D2 an empty conclusion and XX" '"status":"in_progress","conclusion":"","tests":"0","total":"XX"'

TARGET_VALUE="" send "$SCRIPT" selftests completed success 1 2
want_exit "D3 no receiver: a warning, exit 0" 0 "::warning::dispatch_report: the secret REPORT_TARGET_REPO is not set"
want_no_call "D3 no receiver"
TOKEN_VALUE="" send "$SCRIPT" selftests completed success 1 2
want_exit "D3 no token: a warning, exit 0" 0 "::warning::dispatch_report: the secret REPORT_DISPATCH_TOKEN is not set"
want_no_call "D3 no token"
: > "$LOG"
capture env -i HOME="$TMP" PATH="${STUBS}:/usr/bin:/bin" STUB_LOG="$LOG" REPORT_TARGET_REPO=acme/receiver \
  GH_TOKEN=other_login GITHUB_TOKEN=other_token "$SCRIPT" selftests completed success 1 2
want_exit "D3 GH_TOKEN and GITHUB_TOKEN are no fallback" 0 "REPORT_DISPATCH_TOKEN is not set"
want_no_call "D3 GH_TOKEN and GITHUB_TOKEN set"

while IFS='#' read -r why a b c d e; do
  send "$SCRIPT" "$a" "$b" "$c" "$d" "$e"
  want_exit "D4 ${why}" 2 "::error::dispatch_report:"
  want_no_call "D4 ${why}"
done <<'CASES'
unknown kind#release#completed#success#1#2
empty kind##completed#success#1#2
kind with a space#selftests x#completed#success#1#2
unknown status#selftests#queued#success#1#2
in_progress with a conclusion#selftests#in_progress#success#1#2
completed without a conclusion#selftests#completed##1#2
conclusion timed_out#selftests#completed#timed_out#1#2
tests with a quote#selftests#completed#success#1","x":"y#2
tests negative#selftests#completed#success#-1#2
tests too long#selftests#completed#success#1234567#2
tests lower-case xx#selftests#completed#success#xx#2
total with a dollar#selftests#completed#success#1#$(id)
total empty#selftests#completed#success#1#
CASES
send "$SCRIPT" selftests completed success 1
want_exit "D4 four arguments" 2 "five arguments"
want_no_call "D4 four arguments"

for bad in "receiver" "acme/receiver/extra" "acme/re ceiver" 'acme/$(id)'; do
  TARGET_VALUE="$bad" send "$SCRIPT" selftests completed success 1 2
  want_exit "D5 target '${bad}'" 2 "REPORT_TARGET_REPO is not owner/name"
  want_no_call "D5 target '${bad}'"
done

for status in 200 202 401 403 404 422 500; do
  STUB_STATUS="$status" send "$SCRIPT" selftests completed failure 1 2
  want_exit "D6 status ${status} fails, named" 1 "status ${status}, not 204"
done
STUB_CURL_RC=7 send "$SCRIPT" selftests completed failure 1 2
want_exit "D6 curl fails" 1 "curl failed (exit 7)"

# D7: the receiver and the token never reach the output (the run log is public).
for st in 204 404; do
  STUB_STATUS="$st" send "$SCRIPT" selftests completed success 1 2
  if grep -qF -e "acme/receiver" -e "tok_secret_value" <<< "$OUT"; then fail "D7 status ${st}: the output names the receiver or the token: $OUT"; else echo "  ok: D7 status ${st}: neither the receiver nor the token is printed"; fi
done
STUB_CURL_RC=6 send "$SCRIPT" selftests completed success 1 2
if grep -qF -e "acme/receiver" -e "tok_secret_value" <<< "$OUT"; then fail "D7 curl failing: the output names the receiver or the token: $OUT"; else echo "  ok: D7 curl failing: neither the receiver nor the token is printed"; fi

# D8: checks with a completed selftests outcome.
send "$SCRIPT" selftests completed failure 100 101 4695
want_green_ok "D8 a selftests outcome with checks is sent"
want_logged "D8 the exact body, checks the sixth value" '{"event_type":"forsgren-report","client_payload":{"kind":"selftests","status":"completed","conclusion":"failure","tests":"100","total":"101","checks":"4695"}}'
send "$SCRIPT" selftests completed success 1 2 0
want_green_ok "D8 checks 0 is a count, sent"

# D9: kind quality.
send "$SCRIPT" quality completed success 4698
want_green_ok "D9 a quality run's checks are sent"
want_logged "D9 the exact body" '{"event_type":"forsgren-report","client_payload":{"kind":"quality","status":"completed","conclusion":"success","checks":"4698"}}'

# D10: a bad checks value, or a bad shape with checks.
for bad in -1 1.5 01 XX "" 12345678 " 1" '1","x":"y'; do
  send "$SCRIPT" quality completed success "$bad"
  want_exit "D10 quality checks '${bad}'" 2 "::error::dispatch_report: checks"
  want_no_call "D10 quality checks '${bad}'"
  send "$SCRIPT" selftests completed success 1 2 "$bad"
  want_exit "D10 selftests checks '${bad}'" 2 "::error::dispatch_report: checks"
  want_no_call "D10 selftests checks '${bad}'"
done
send "$SCRIPT" selftests in_progress "" 0 2 5
want_exit "D10 checks on a run in progress" 2 "only a completed run has checks"
want_no_call "D10 checks on a run in progress"
send "$SCRIPT" quality in_progress "" 5
want_exit "D10 quality in progress" 2 "quality is only sent completed"
want_no_call "D10 quality in progress"
send "$SCRIPT" quality completed success 1 2
want_exit "D10 quality with five arguments" 2 "quality takes four arguments"
want_no_call "D10 quality with five arguments"
send "$SCRIPT" quality completed success
want_exit "D10 quality with three arguments" 2 "quality takes four arguments"
want_no_call "D10 quality with three arguments"

# ---- workflow ------------------------------------------------------------
# job_of <job>: the lines of one job of the workflow.
job_of() {
  awk -v j="  $1:" '
    $0 == j { on = 1; print; next }
    on && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { on = 0 }
    on && /^[^[:space:]#]/ { on = 0 }
    on { print }
  ' "$WORKFLOW"
}
START="$(job_of report_start)"
REPORT="$(job_of report)"
code_of() { grep -vE '^[[:space:]]*#' <<< "$1"; }

want_in() {
  if code_of "$2" | has -qxF -- "$3"; then echo "  ok: $1"; else fail "$1: no line '$3'"; fi
}
want_in "W1 report_start runs on ubuntu-latest" "$START" "    runs-on: ubuntu-latest"
want_in "W1 report_start reads only" "$START" "      contents: read   # the checkout of Scripts/dispatch_report.sh"
if code_of "$START" | has -qE '^    needs:'; then fail "W1 report_start waits for another job"; else echo "  ok: W1 report_start waits for nothing"; fi
for job in START REPORT; do
  want_in "W1/W2 ${job}: the receiver secret in env" "${!job}" "          REPORT_TARGET_REPO: ${DOLLAR}{{ secrets.REPORT_TARGET_REPO }}"
  want_in "W1/W2 ${job}: the secret in env" "${!job}" "          REPORT_DISPATCH_TOKEN: ${DOLLAR}{{ secrets.REPORT_DISPATCH_TOKEN }}"
done
want_in "W1 the start is sent" "$START" '          ./Scripts/dispatch_report.sh selftests in_progress "" 0 "$total"'
want_in "W2 the outcome is sent with its checks" "$REPORT" '            ./Scripts/dispatch_report.sh selftests completed "$conclusion" "${tests:-XX}" "${total:-XX}" "$checks"'
want_in "W2 the checks come from the summary's counter" "$REPORT" '          if checks="$(./Scripts/render_quality_summary.sh --selftests --checks "${dir}/quality_rows.md" "${dir}/quality_details" "${dir}/selftests_order.txt")"; then'
want_in "W2 without a count the outcome is sent without checks" "$REPORT" '            ./Scripts/dispatch_report.sh selftests completed "$conclusion" "${tests:-XX}" "${total:-XX}" || true'
want_in "W2 without a count the step is red" "$REPORT" '            exit 1'
want_in "W2 the summary has its own Total checks row" "$REPORT" '          ./Scripts/render_quality_summary.sh --selftests "$rows" "$details" "$order" >> "$GITHUB_STEP_SUMMARY" || rc=$?'
want_in "W2 the counts come from selftests_counts.sh" "$REPORT" '          counts="$(./Scripts/selftests_counts.sh "${dir}/quality_rows.md" "$labels")"'
want_in "W2 the labels come from selftest_rows.sh" "$REPORT" '          ./Scripts/selftest_rows.sh > "$labels" || : > "$labels"'
if code_of "$REPORT" | has -qE 'conclusion="[$][(][.]/Scripts/merge_quality_report[.]sh status'; then
  echo "  ok: W2 the conclusion comes from merge_quality_report.sh status"
else
  fail "W2 the conclusion is not taken from merge_quality_report.sh status"
fi
last_step="$(code_of "$REPORT" | grep -E '^      - name: ' | tail -1)"
if [[ "$last_step" == "      - name: Report the outcome" ]]; then echo "  ok: W2 the outcome is the report job's last step"; else fail "W2 the last step is '${last_step}'"; fi
if code_of "$REPORT" | awk '/^      - name: Report the outcome$/ { on = 1; next } on && /^      - / { on = 0 } on' | has -qxF '        if: always()'; then
  echo "  ok: W2 the outcome step runs always"
else
  fail "W2 the outcome step is not if: always()"
fi
n="$(code_of "$(cat "$WORKFLOW")" | grep -c 'secrets\.REPORT_DISPATCH_TOKEN' || true)"
m="$(code_of "$(cat "$WORKFLOW")" | grep -cxF "          REPORT_DISPATCH_TOKEN: ${DOLLAR}{{ secrets.REPORT_DISPATCH_TOKEN }}" || true)"
if [[ "$n" == 2 && "$m" == 2 ]]; then echo "  ok: W3 the secret is only the env of the two steps"; else fail "W3 the secret appears ${n} times, ${m} as the env of a step"; fi
if code_of "$(cat "$WORKFLOW")" | grep -E 'dispatch_report|REPORT_' | grep -vE '^          REPORT_(TARGET_REPO|DISPATCH_TOKEN): ' | has -qF "${DOLLAR}{{"; then
  fail "W3 a run: line expands an expression of the report inputs"
else
  echo "  ok: W3 no run: line expands an expression of the report inputs"
fi

# W4: quality.yml's report job sends the Quality run's checks.
QWORKFLOW=".github/workflows/quality.yml"
[[ -f "$QWORKFLOW" ]] || selftest_abort "${QWORKFLOW} does not exist"
QREPORT="$(WORKFLOW="$QWORKFLOW" job_of report)"
QSTEP="$(code_of "$QREPORT" | awk '/^      - name: Report the checks$/ { on = 1 } on && /^      - / && !/Report the checks/ { on = 0 } on')"
q_last="$(code_of "$QREPORT" | grep -E '^      - name: ' | tail -1)"
if [[ "$q_last" == "      - name: Report the checks" ]]; then echo "  ok: W4 the checks are the Quality report job's last step"; else fail "W4 the last step is '${q_last}'"; fi
want_in "W4 always, never on a pull request" "$QSTEP" "        if: always() && github.event_name != 'pull_request'"
want_in "W4 the receiver secret in env" "$QSTEP" "          REPORT_TARGET_REPO: ${DOLLAR}{{ secrets.REPORT_TARGET_REPO }}"
want_in "W4 the token secret in env" "$QSTEP" "          REPORT_DISPATCH_TOKEN: ${DOLLAR}{{ secrets.REPORT_DISPATCH_TOKEN }}"
want_in "W4 the checks come from the summary's counter" "$QSTEP" '          if ! checks="$(./Scripts/render_quality_summary.sh --checks "${dir}/quality_rows.md" "${dir}/quality_details" "${dir}/quality_order.txt")"; then'
want_in "W4 a missing count is red" "$QSTEP" '            exit 1'
want_in "W4 the checks are sent as kind quality" "$QSTEP" '          ./Scripts/dispatch_report.sh quality completed "$conclusion" "$checks"'
qn="$(code_of "$(cat "$QWORKFLOW")" | grep -cE 'secrets\.REPORT_(DISPATCH_TOKEN|TARGET_REPO)' || true)"
qm="$(code_of "$QSTEP" | grep -cE "^          REPORT_(DISPATCH_TOKEN|TARGET_REPO): [$][{][{] secrets[.]REPORT_(DISPATCH_TOKEN|TARGET_REPO) [}][}]$" || true)"
if [[ "$qn" == 2 && "$qm" == 2 ]]; then echo "  ok: W4 the two secrets are only the env of the checks step"; else fail "W4 the secrets appear ${qn} times in quality.yml, ${qm} as the env of the checks step"; fi
if code_of "$(cat "$QWORKFLOW")" | grep -E 'dispatch_report|REPORT_' | grep -vE '^          REPORT_(TARGET_REPO|DISPATCH_TOKEN): ' | has -qF "${DOLLAR}{{"; then
  fail "W4 a run: line of quality.yml expands an expression of the report inputs"
else
  echo "  ok: W4 no run: line of quality.yml expands an expression of the report inputs"
fi

# ---- mutation proofs -----------------------------------------------------
M="${TMP}/mut"
if selftest_mutant "$SCRIPT" "${M}/notests.sh" 's/\[\[ "\$tests" =~ .*$/true/'; then
  send "${M}/notests.sh" selftests completed success '1","x":"y' 2
  if [[ "$RC" -eq 0 && "$(calls)" == 1 ]]; then echo "  ok: mutation proof A: without the tests check a payload text is sent"; else fail "mutation proof A: the copy still refused (exit ${RC}). Output: $OUT"; fi
fi
if selftest_mutant "$SCRIPT" "${M}/notoken.sh" "s/-z \"${DOLLAR}{REPORT_DISPATCH_TOKEN:-}\"/-z \"x\"/"; then
  TOKEN_VALUE="" send "${M}/notoken.sh" selftests completed success 1 2
  if [[ "$RC" -eq 0 && "$(calls)" == 1 ]]; then echo "  ok: mutation proof B: without the token guard curl is called with no token"; else fail "mutation proof B: the copy still skipped (exit ${RC}, calls $(calls)). Output: $OUT"; fi
fi
if selftest_mutant "$SCRIPT" "${M}/any2xx.sh" "s/\"${DOLLAR}code\" != \"204\"/\"${DOLLAR}{code:0:1}\" != \"2\"/"; then
  STUB_STATUS=202 send "${M}/any2xx.sh" selftests completed success 1 2
  if [[ "$RC" -eq 0 ]]; then echo "  ok: mutation proof C: accepting any 2xx lets 202 pass"; else fail "mutation proof C: the copy still failed 202. Output: $OUT"; fi
fi
if selftest_mutant "$SCRIPT" "${M}/noprogress.sh" 's/\[\[ -z "\$conclusion" \]\] || bad/true || bad/'; then
  send "${M}/noprogress.sh" selftests in_progress success 1 2
  if [[ "$RC" -eq 0 && "$(calls)" == 1 ]]; then echo "  ok: mutation proof D: without the in_progress check a conclusion is sent"; else fail "mutation proof D: the copy still refused (exit ${RC}). Output: $OUT"; fi
fi
if selftest_mutant "$COUNTS" "${M}/anymark.sh" 's/ && (\$2 == "✅" || \$2 == "❌")//'; then
  capture "${M}/anymark.sh" "$ROWS" "$LABELS"
  if grep -qxF "tests=3" <<< "$OUT"; then echo "  ok: mutation proof E: counting any mark counts the skipped row"; else fail "mutation proof E: the copy still says: $OUT"; fi
fi
if selftest_mutant "$COUNTS" "${M}/unlisted.sh" 's/(\$1 in want) && //'; then
  capture "${M}/unlisted.sh" "$ROWS" "$LABELS"
  if grep -qxF "tests=3" <<< "$OUT"; then echo "  ok: mutation proof F: counting unlisted labels counts the Quality row"; else fail "mutation proof F: the copy still says: $OUT"; fi
fi

if selftest_mutant "$SCRIPT" "${M}/nochecks.sh" 's/\[\[ "\$has_checks" == "false" || .*$/true \\/'; then
  send "${M}/nochecks.sh" quality completed success '1","x":"y'
  if [[ "$RC" -eq 0 && "$(calls)" == 1 ]]; then echo "  ok: mutation proof G: without the checks check a payload text is sent"; else fail "mutation proof G: the copy still refused (exit ${RC}). Output: $OUT"; fi
fi
if selftest_mutant "$SCRIPT" "${M}/qprogress.sh" 's/\[\[ "\$status" == "completed" \]\] || bad "quality/true || bad "quality/'; then
  send "${M}/qprogress.sh" quality in_progress "" 5
  if [[ "$RC" -eq 0 && "$(calls)" == 1 ]]; then echo "  ok: mutation proof H: without quality's completed-only check a run in progress is sent"; else fail "mutation proof H: the copy still refused (exit ${RC}). Output: $OUT"; fi
fi

selftest_end "the report dispatch self-test found failures" "report dispatch (strict payload of five values, six with checks, or kind quality's four, 204 only, token only on stdin, skipped with a warning without receiver or token, counts from the listed rows, checks from the summary's counter, the two Self-tests steps and Quality's checks step; 8 mutation proofs)"
