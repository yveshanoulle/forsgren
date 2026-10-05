#!/usr/bin/env bash
# Scripts/test_auto_update_workflow.sh
#
# Pins .github/workflows/auto_update.yml (forsgren#58, ladder steps 17 to
# 19), the REUSABLE workflow an installation's caller, forsgren-update.yml,
# calls on a Dependabot pull request: it asks `forsgren check-update`
# whether the pull request may be merged, merges it, and starts the
# installation's forsgren.yml. Nothing in forsgren itself runs it, so this
# pin is what proves it, in sfl and Quality, on every run.
#
# Grown one behaviour per cycle, each its own red then green:
#   17a  the file exists and triggers on workflow_call and on nothing else
#        (forsgren's own repository never runs it, no pull request can);
#   17b  no permissions block at workflow or job level (the caller grants);
#   17c  forsgren is installed from this workflow's own commit: the same
#        setup-go as metrics.yml, then the install step, its commit and
#        repository from the job context through env: only;
#   17d  the install step, executed with a stub go: a good commit and
#        repository install, a bad one is refused before go runs;
#   17e  the caller's checkout, pinned, no credentials, of the base commit,
#        after the install step;
#   17f  the guard step (id: guard), after the checkout, runs forsgren
#        check-update with the repository and pull request from env;
#   18a  check-update exits 1: the guard step succeeds, leaves the reason in
#        the step summary, outputs merge=false and calls no gh;
#   18b  check-update exits 2: the guard step fails the job with an ::error
#        naming check-update and its exit status;
#   18c  check-update's output is shown between ::stop-commands:: and its end;
#   19a  exit 0: merge=true, and the merge step (id: merge) merges the pull
#        request, squashed, the branch deleted;
#   19b  then it starts forsgren.yml on the default branch;
#   19c  a failed merge fails the step and starts nothing;
#   (the later cycles are listed in forsgren#58 and add their pins here.)
#
# Read with awk, not a YAML parser, as Scripts/test_metrics_workflow.sh is,
# for its reason: PyYAML is a module, not a command, and nothing here
# installs it.
#
# Usage: Scripts/test_auto_update_workflow.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
selftest_begin "the auto-update workflow pin"

WF=".github/workflows/auto_update.yml"
METRICS=".github/workflows/metrics.yml"
GO_STEP="Set up Go"
INSTALL_STEP="Install forsgren from this workflow's own commit"
# The opening of a GitHub expression, in double quotes with the dollar
# escaped, so no reader (shellcheck included) takes it for an expansion.
EXPR_OPEN="\${{"

# Pin 1: the workflow exists and triggers on workflow_call alone.
if [[ ! -f "$WF" ]]; then
  fail "pin 1: ${WF} does not exist"
else
  events="$(on_events "$WF" | paste -sd, -)"
  if [[ "$events" == "workflow_call" ]]; then
    echo "  ok: ${WF} triggers on workflow_call only"
  else
    fail "pin 1: ${WF} triggers on '${events:-nothing}', not on workflow_call only"
  fi
fi

# Pin 2: no `permissions:` key, at workflow level (column 0) or on a job
# (four spaces in). A STANDING FACT, as metrics.yml's header explains: a
# called workflow can only keep or narrow the permissions its caller's job
# grants, never widen them, so any block here would cut what the caller
# grants (contents: write, pull-requests: write, actions: write) to what the
# block names, and the merge or the dispatch would fail with a 403. Without
# a block the job takes exactly what the caller grants.
if [[ -f "$WF" ]]; then
  found="$(grep -nE '^( {0,4})permissions:' "$WF" | paste -sd' ' - || true)"
  if [[ -z "$found" ]]; then
    echo "  ok: ${WF} has no permissions block"
  else
    fail "pin 2: ${WF} has a permissions block (line ${found}); the caller grants them, and a block here would cut them"
  fi
fi

# Pin 3: forsgren is installed from THIS workflow's own commit, exactly as
# metrics.yml does (STANDING FACTS, ruling on forsgren#4: the caller's one
# `uses: ...@<commit> # vX.Y.Z` line is the only version, so nothing takes a
# version as input):
#   - the step "Set up Go" is metrics.yml's own, line for line (the same
#     commit-pinned actions/setup-go, the same go-version, cache: false), so
#     the two workflows build with one Go and one setup-go;
#   - the install step follows it, and its env: sets FORSGREN_SHA to
#     job.workflow_sha and FORSGREN_REPOSITORY to job.workflow_repository, the
#     called workflow's own commit and repository (the github context is the
#     CALLER's in a called workflow, so it would install the caller's commit);
#   - no run: block expands a ${{ }} expression: values reach the shell
#     through env: only, never as text pasted into the script (template
#     injection, zizmor).
if [[ -f "$WF" ]]; then
  # Comment and blank lines are left out of the comparison: the lines after
  # a step, up to the next one, are the next step's own header comment.
  want_go="$(step_text "$METRICS" "$GO_STEP" | grep -vE '^[[:space:]]*(#|$)' || true)"
  have_go="$(step_text "$WF" "$GO_STEP" | grep -vE '^[[:space:]]*(#|$)' || true)"
  install="$(step_text "$WF" "$INSTALL_STEP")"
  if [[ -z "$have_go" ]]; then
    fail "pin 3: ${WF} has no step '${GO_STEP}'"
  elif [[ "$have_go" != "$want_go" ]]; then
    fail "pin 3: the step '${GO_STEP}' of ${WF} is not the one of ${METRICS}"
  else
    echo "  ok: ${WF} sets up Go as ${METRICS} does"
  fi
  if [[ -z "$install" ]]; then
    fail "pin 3: ${WF} has no step '${INSTALL_STEP}'"
  else
    for want in "FORSGREN_SHA: ${EXPR_OPEN} job.workflow_sha }}" "FORSGREN_REPOSITORY: ${EXPR_OPEN} job.workflow_repository }}"; do
      if grep -qF -- "$want" <<< "$install"; then
        echo "  ok: the install step sets ${want}"
      else
        fail "pin 3: the step '${INSTALL_STEP}' does not set '${want}'"
      fi
    done
    if later "$(line_of "$WF" "$INSTALL_STEP")" "$(line_of "$WF" "$GO_STEP")"; then
      echo "  ok: the install step comes after setup-go"
    else
      fail "pin 3: the step '${INSTALL_STEP}' is not after '${GO_STEP}'"
    fi
  fi
  injected="$(run_blocks "$WF" | grep -F -- "${EXPR_OPEN}" | paste -sd' ' - || true)"
  if [[ -z "$injected" ]]; then
    echo "  ok: no run: block expands a GitHub expression"
  else
    fail "pin 3: a run: block of ${WF} expands a GitHub expression, pass it through env: (line ${injected})"
  fi
fi

# Pin 4: the install step's run: block, EXECUTED here with a stub go on PATH
# that records its arguments (the way Scripts/test_metrics_workflow.sh does
# for metrics.yml; install_outcome is this pin's own, stricter than that
# one's, see Scripts/lib_workflow_steps.sh). STANDING
# FACTS: forsgren is installed only from an exact commit, so a commit that is
# not 40 lower-case hex digits (a tag, a branch, a short or long hash,
# capitals, empty) never reaches the module proxy, and only from one
# owner/name repository; both are refused with an ::error BEFORE go runs.
# A good pair runs exactly `go install
# github.com/<repository>/cmd/forsgren@<commit>` and puts GOBIN on
# $GITHUB_PATH, so the later steps find forsgren.
SHA="1997c4ff09aecd32c30fbdd7eef72485f146e865"
UPSTREAM="yveshanoulle/forsgren"
STUB="${TMP}/stub"
mkdir -p "$STUB"
cat > "${STUB}/go" <<'STUBGO'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GO_CALLS"
STUBGO
chmod +x "${STUB}/go"

# install_outcome <script> <sha> <repository>: `refused` (non-zero, an
# ::error, go never ran), `installed <go args>` (zero, go ran once, GOBIN on
# the path file), or `broken: ...` for any other mix.
install_outcome() {
  local calls="${TMP}/go.calls" log="${TMP}/install.log" rc=0 n
  rm -f "$calls" "${TMP}/github_path"
  : > "$calls"
  PATH="${STUB}:${PATH}" GO_CALLS="$calls" RUNNER_TEMP="${TMP}/runner" \
    GITHUB_PATH="${TMP}/github_path" FORSGREN_SHA="$2" FORSGREN_REPOSITORY="$3" \
    bash "$1" > "$log" 2>&1 || rc=$?
  n="$(wc -l < "$calls" | tr -d ' ')"
  if [[ "$rc" -ne 0 && "$n" -eq 0 ]] && grep -q '^::error' "$log"; then
    echo refused
  elif [[ "$rc" -eq 0 && "$n" -eq 1 ]] && grep -qxF "${TMP}/runner/forsgren-bin" "${TMP}/github_path" 2>/dev/null; then
    echo "installed $(cat "$calls")"
  else
    echo "broken: exit ${rc}, go ran ${n} time(s)"
  fi
}

if [[ -f "$WF" ]]; then
  step_block "$WF" "$INSTALL_STEP" run > "${TMP}/install.sh"
  if [[ ! -s "${TMP}/install.sh" ]]; then
    fail "pin 4: ${WF} has no step '${INSTALL_STEP}' with a run: | block"
  else
    problems=0
    got="$(install_outcome "${TMP}/install.sh" "$SHA" "$UPSTREAM")"
    want="installed install github.com/${UPSTREAM}/cmd/forsgren@${SHA}"
    if [[ "$got" != "$want" ]]; then
      fail "pin 4: for ${UPSTREAM} at ${SHA} the install step gives '${got}', not '${want}'"
      problems=1
    fi
    for v in v0.0.1 latest main e1b36d2 "${SHA:0:39}" "${SHA}0" "$(tr 'a-f' 'A-F' <<< "$SHA")" "${SHA:0:39}g" ''; do
      got="$(install_outcome "${TMP}/install.sh" "$v" "$UPSTREAM")"
      if [[ "$got" != refused ]]; then
        fail "pin 4: the install step gives '${got}' for the commit '${v}', which is not 40 lower-case hex digits; it must refuse before go runs"
        problems=1
      fi
    done
    for v in yveshanoulle yveshanoulle/forsgren/extra '../forsgren' 'yveshanoulle/..' 'evil.example/forsgren' ''; do
      got="$(install_outcome "${TMP}/install.sh" "$SHA" "$v")"
      if [[ "$got" != refused ]]; then
        fail "pin 4: the install step gives '${got}' for the repository '${v}', which is not one owner/name; it must refuse before go runs"
        problems=1
      fi
    done
    if [[ "$problems" -eq 0 ]]; then
      echo "  ok: the install step installs a good commit and refuses a bad commit or repository before go runs"
    fi
  fi
fi

# Pin 5: the step "Check out the caller's repository", after the install
# step (setup-go, install, checkout). STANDING FACTS:
#   - actions/checkout is pinned by the very commit metrics.yml uses (one
#     version of the action in the repository), with persist-credentials:
#     false, so the caller's token is not left in the checkout's git config;
#   - it checks out the pull request's BASE commit,
#     `ref: ${{ github.event.pull_request.base.sha }}`, never the default
#     (the merge commit of a pull_request event, which carries the pull
#     request's own changes) and never its head. forsgren.config.yml is what
#     decides whether the update may be merged (auto_update: true), so it
#     must be the config the maintainer committed: a pull request can then
#     never switch auto_update on for itself. An expression in `with:` is
#     not a template injection, only one in a run: block is (pin 3).
if [[ -f "$WF" ]]; then
  CHECKOUT_STEP="Check out the caller's repository"
  want_uses="$(step_text "$METRICS" "$CHECKOUT_STEP" | grep -E '^        uses: ' || true)"
  have="$(step_text "$WF" "$CHECKOUT_STEP")"
  if [[ -z "$have" ]]; then
    fail "pin 5: ${WF} has no step '${CHECKOUT_STEP}'"
  else
    if grep -qxF -- "$want_uses" <<< "$have"; then
      echo "  ok: the checkout is pinned as ${METRICS}'s is"
    else
      fail "pin 5: the checkout is not '${want_uses#        }' (the commit ${METRICS} pins)"
    fi
    if grep -qE '^          persist-credentials: false[[:space:]]*$' <<< "$have"; then
      echo "  ok: the checkout persists no credentials"
    else
      fail "pin 5: the checkout does not set persist-credentials: false"
    fi
    if grep -qxF -- "          ref: ${EXPR_OPEN} github.event.pull_request.base.sha }}" <<< "$have"; then
      echo "  ok: the checkout is of the pull request's base commit"
    else
      fail "pin 5: the checkout is not of the base commit, ref: ${EXPR_OPEN} github.event.pull_request.base.sha }}; a pull request could change the config that rules its own merge"
    fi
    if later "$(line_of "$WF" "- name: ${CHECKOUT_STEP}")" "$(line_of "$WF" "- name: ${INSTALL_STEP}")"; then
      echo "  ok: the checkout comes after the install step"
    else
      fail "pin 5: the step '${CHECKOUT_STEP}' is not after '${INSTALL_STEP}'"
    fi
  fi
fi

# step_by_id <file> <id> <key>: the block under that key (run or env) of the
# step whose `id:` is <id>, its lines dedented; with key `text`, every line of
# that step. Nothing when no step has the id.
step_by_id() {
  awk -v id="$2" -v key="$3" '
    function indent(s) { match(s, /^ */); return RLENGTH }
    function flush(   i, inb, cut) {
      if (!matched) return
      inb = 0; cut = 0
      for (i = 1; i <= n; i++) {
        if (key == "text") { print buf[i]; continue }
        if (inb && buf[i] !~ /^[[:space:]]*$/ && indent(buf[i]) <= 8) inb = 0
        if (inb) { if (!cut) { match(buf[i], /^ */); cut = RLENGTH } print substr(buf[i], cut + 1); continue }
        if (buf[i] ~ ("^        " key ":[[:space:]]*\\|?[[:space:]]*$")) inb = 1
      }
    }
    /^      - / { flush(); n = 0; matched = 0 }
    { buf[++n] = $0 }
    $0 == "        id: " id { matched = 1 }
    END { flush() }
  ' "$1"
}

# Pin 6: the guard step, `id: guard`, after the checkout, asks forsgren
# whether the pull request may be merged. STANDING FACTS: the job's token
# (`${{ github.token }}`, the caller's) and the pull request's number reach
# the step through env: only, never pasted into the script (pin 3); and the
# run: block calls exactly
# `forsgren check-update --config forsgren.config.yml --repo
# "$GITHUB_REPOSITORY" --pull "$PR_NUMBER"`, GITHUB_REPOSITORY being the
# caller's repository. EXECUTED here with a stub forsgren on PATH that records
# its arguments. What the step does with the exit status is cycles 18a to 18c.

# One stub directory serves pins 6 to 12; what differs from pin to pin is set
# per run, in the environment stub_run passes:
#   forsgren  records its arguments in FG_CALLS (when set), prints STUB_OUT on
#             stdout and STUB_ERR on stderr (each when set), and exits
#             STUB_RC (0 by default);
#   gh        records its arguments in GH_CALLS (when set), and fails a
#             `pr merge` when STUB_GH_MERGE_FAILS is yes.
STUB_JOB="${TMP}/stub-job"
mkdir -p "$STUB_JOB"
cat > "${STUB_JOB}/forsgren" <<'STUBFORSGREN'
#!/usr/bin/env bash
if [[ -n "${FG_CALLS:-}" ]]; then printf '%s\n' "$*" >> "$FG_CALLS"; fi
if [[ -n "${STUB_OUT:-}" ]]; then printf '%s\n' "$STUB_OUT"; fi
if [[ -n "${STUB_ERR:-}" ]]; then printf '%s\n' "$STUB_ERR" >&2; fi
exit "${STUB_RC:-0}"
STUBFORSGREN
cat > "${STUB_JOB}/gh" <<'STUBGH'
#!/usr/bin/env bash
if [[ -n "${GH_CALLS:-}" ]]; then printf '%s\n' "$*" >> "$GH_CALLS"; fi
if [[ "${STUB_GH_MERGE_FAILS:-}" == yes && "${1:-} ${2:-}" == "pr merge" ]]; then
  echo "gh: merge blocked" >&2
  exit 1
fi
STUBGH
chmod +x "${STUB_JOB}/forsgren" "${STUB_JOB}/gh"

# stub_run <script> <stdout file> [NAME=value ...]: runs a step's block with
# the stub forsgren and gh first on PATH, the caller's repository owner/name
# and pull request 42, and the NAME=value pairs (the stubs' parameters, the
# token, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY ...); its stdout in the file, its
# stderr dropped. Returns the block's exit status.
stub_run() {
  env PATH="${STUB_JOB}:${PATH}" GITHUB_REPOSITORY="owner/name" PR_NUMBER=42 "${@:3}" \
    bash "$1" > "$2" 2> /dev/null
}

if [[ -f "$WF" ]]; then
  guard_env="$(step_by_id "$WF" guard env)"
  if [[ -z "$(step_by_id "$WF" guard text)" ]]; then
    fail "pin 6: ${WF} has no guard step (a step with id: guard) asking forsgren check-update whether the pull request may be merged"
  else
    for want in "GITHUB_TOKEN: ${EXPR_OPEN} github.token }}" "PR_NUMBER: ${EXPR_OPEN} github.event.pull_request.number }}"; do
      if grep -qxF -- "$want" <<< "$guard_env"; then
        echo "  ok: the guard step sets ${want}"
      else
        fail "pin 6: the guard step does not set '${want}' in its env:"
      fi
    done
    if later "$(line_of "$WF" "id: guard")" "$(line_of "$WF" "- name: Check out the caller's repository")"; then
      echo "  ok: the guard step comes after the checkout"
    else
      fail "pin 6: the guard step is not after the checkout of the caller's repository"
    fi
    step_by_id "$WF" guard run > "${TMP}/guard.sh"
    calls="${TMP}/fg.calls"
    : > "$calls"
    stub_run "${TMP}/guard.sh" /dev/null FG_CALLS="$calls" GITHUB_TOKEN="t0ken" || true
    want="check-update --config forsgren.config.yml --repo owner/name --pull 42"
    if [[ "$(cat "$calls")" == "$want" ]]; then
      echo "  ok: the guard step runs forsgren ${want}"
    else
      fail "pin 6: the guard step ran forsgren '$(paste -sd';' "$calls")', not '${want}'"
    fi
  fi
fi

# Pin 7: check-update exits 1, the pull request is LEFT FOR A HUMAN: the
# guard step succeeds (the job is green, nothing is wrong), leaves
# check-update's reason line in the job summary, records the output
# `merge=false` and calls no gh. STANDING FACT: that output is the contract of
# the steps after it, which run only `if: steps.guard.outputs.merge ==
# 'true'` (cycle 19a). Exit 2 (a failure of the job) is cycle 18b. EXECUTED
# with the stubs: forsgren printing the reason and exiting 1, gh recording
# any call.
LEFT="left for a human: the pull request changes more than the pin line"

if [[ -f "$WF" && -n "$(step_by_id "$WF" guard text)" ]]; then
  step_by_id "$WF" guard run > "${TMP}/guard-left.sh"
  : > "${TMP}/left.summary"
  : > "${TMP}/left.output"
  : > "${TMP}/left.gh"
  left_rc=0
  stub_run "${TMP}/guard-left.sh" /dev/null STUB_OUT="$LEFT" STUB_RC=1 GH_CALLS="${TMP}/left.gh" \
    GITHUB_TOKEN="t0ken" GITHUB_STEP_SUMMARY="${TMP}/left.summary" GITHUB_OUTPUT="${TMP}/left.output" \
    || left_rc=$?
  if [[ "$left_rc" -eq 0 ]]; then
    echo "  ok: the guard step succeeds when check-update leaves the pull request for a human"
  else
    fail "pin 7: the guard step exited ${left_rc} when check-update exited 1; a pull request left for a human is not a failed job"
  fi
  if grep -qxF -- "$LEFT" "${TMP}/left.summary"; then
    echo "  ok: the reason is in the step summary"
  else
    fail "pin 7: the step summary does not hold the line '${LEFT}'"
  fi
  if [[ "$(cat "${TMP}/left.output")" == "merge=false" ]]; then
    echo "  ok: the guard step records merge=false"
  else
    fail "pin 7: the guard step's output is '$(paste -sd';' "${TMP}/left.output")', not exactly the line merge=false"
  fi
  if [[ ! -s "${TMP}/left.gh" ]]; then
    echo "  ok: the guard step calls no gh"
  else
    fail "pin 7: the guard step called gh: $(paste -sd';' "${TMP}/left.gh")"
  fi
fi

# Pin 8: check-update exits 2 (usage, configuration or network error): the
# guard step FAILS the job, with an ::error workflow command, on stdout, that
# names check-update and its exit status, so the run page says what failed
# and the pull request is neither merged nor silently left. It records no
# `merge=true` and calls no gh. Exit 1 (left for a human) is pin 7. EXECUTED
# with the stubs: forsgren saying why on stderr and exiting 2, gh recording
# any call. The wording of the ::error is not pinned, its substance is: the
# prefix, check-update, and the status 2.

if [[ -f "$WF" && -n "$(step_by_id "$WF" guard text)" ]]; then
  step_by_id "$WF" guard run > "${TMP}/guard-fail.sh"
  : > "${TMP}/fail.summary"
  : > "${TMP}/fail.output"
  : > "${TMP}/fail.gh"
  fail_rc=0
  stub_run "${TMP}/guard-fail.sh" "${TMP}/fail.stdout" \
    STUB_ERR="forsgren: reading forsgren.config.yml: no such file" STUB_RC=2 GH_CALLS="${TMP}/fail.gh" \
    GITHUB_TOKEN="t0ken" GITHUB_STEP_SUMMARY="${TMP}/fail.summary" GITHUB_OUTPUT="${TMP}/fail.output" \
    || fail_rc=$?
  if [[ "$fail_rc" -ne 0 ]]; then
    echo "  ok: the guard step fails when check-update exits 2"
  else
    fail "pin 8: the guard step exited 0 when check-update exited 2; a failed check must fail the job"
  fi
  if grep -E '^::error' "${TMP}/fail.stdout" | grep -F 'check-update' | grep -qE '(^|[^0-9])2([^0-9]|$)'; then
    echo "  ok: the guard step prints an ::error naming check-update and exit 2"
  else
    fail "pin 8: the guard step prints no ::error line naming check-update and its exit status 2 (stdout: '$(paste -sd';' "${TMP}/fail.stdout")')"
  fi
  if grep -qxF 'merge=true' "${TMP}/fail.output"; then
    fail "pin 8: the guard step records merge=true after check-update exited 2"
  else
    echo "  ok: the guard step does not record merge=true"
  fi
  if [[ ! -s "${TMP}/fail.gh" ]]; then
    echo "  ok: the guard step calls no gh when check-update exits 2"
  else
    fail "pin 8: the guard step called gh: $(paste -sd';' "${TMP}/fail.gh")"
  fi
fi

# stop_token_around <log> <text>: the token of the ::stop-commands::<token> /
# ::<token>:: pair the first line holding the text sits between; nothing when
# the text is outside any pair or in no line.
stop_token_around() {
  awk -v text="$2" '
    token == "" && /^::stop-commands::./ { token = substr($0, 18); next }
    token != "" && $0 == "::" token "::" { token = ""; next }
    token != "" && index($0, text) && found == "" { found = token }
    END { print found }
  ' "$1"
}

# Pin 9 (18c): check-update's output is written to the job log between
# `::stop-commands::<token>` and `::<token>::`, on exit 0 and on exit 1, under
# a token that differs from run to run: that output carries a pull request's
# and a configuration's text, which must never run as a workflow command (as
# metrics.yml does for check-config and collect, forsgren#9). EXECUTED with
# the stub forsgren printing STUB_OUT and exiting STUB_RC.

# guard_stdout <stdout file> <rc> <output line>: runs the guard block with the
# stub, its stdout in the file, its GITHUB_OUTPUT in ${TMP}/guard.output.
guard_stdout() {
  : > "${TMP}/guard.output"
  : > "${TMP}/guard.summary"
  stub_run "${TMP}/guard-stop.sh" "$1" STUB_RC="$2" STUB_OUT="$3" \
    GITHUB_TOKEN="t0ken" GITHUB_STEP_SUMMARY="${TMP}/guard.summary" GITHUB_OUTPUT="${TMP}/guard.output" \
    || true
}

if [[ -f "$WF" && -n "$(step_by_id "$WF" guard text)" ]]; then
  step_by_id "$WF" guard run > "${TMP}/guard-stop.sh"
  MERGE_LINE="merge v0.1.3 to v0.2.0"
  guard_stdout "${TMP}/stop0.log" 0 "$MERGE_LINE"
  guard_stdout "${TMP}/stop1.log" 1 "$LEFT"
  guard_stdout "${TMP}/stop0b.log" 0 "$MERGE_LINE"
  token0="$(stop_token_around "${TMP}/stop0.log" "$MERGE_LINE")"
  token1="$(stop_token_around "${TMP}/stop1.log" "$LEFT")"
  token0b="$(stop_token_around "${TMP}/stop0b.log" "$MERGE_LINE")"
  if [[ -n "$token0" ]]; then
    echo "  ok: on exit 0 check-update's output is between ::stop-commands:: and its end"
  else
    fail "pin 9: on exit 0 the guard step's stdout does not hold '${MERGE_LINE}' between ::stop-commands::<token> and ::<token>::"
  fi
  if [[ -n "$token1" ]]; then
    echo "  ok: on exit 1 check-update's output is between ::stop-commands:: and its end"
  else
    fail "pin 9: on exit 1 the guard step's stdout does not hold '${LEFT}' between ::stop-commands::<token> and ::<token>::"
  fi
  if [[ -n "$token0" && -n "$token0b" && "$token0" != "$token0b" && "$token0" != "$token1" ]]; then
    echo "  ok: the stop-commands token differs from run to run"
  else
    fail "pin 9: the stop-commands token is empty or the same in two runs ('${token0}', '${token0b}', '${token1}'); a fixed token can be closed by the text it guards"
  fi
fi

# Pins 10 to 12 (19a to 19c): the merge step. STANDING FACTS: it has id:
# merge and runs only when the guard said so (`if: steps.guard.outputs.merge
# == 'true'`); its env is the job's token as GH_TOKEN, the pull request's
# number and the repository's default branch, never an expression in the
# script (pin 3). Its block, EXECUTED with the stub gh, merges the pull
# request (squash, the branch deleted) and then, as its second and last call,
# starts the installation's forsgren.yml on the default branch, so the merged
# update is measured at once (forsgren#58). A failed merge fails the step and
# starts nothing.
# merge_run <fails yes|no>: the merge step's block with the stub gh; its exit
# status in ${TMP}/merge.rc, the recorded calls in ${TMP}/merge.gh.
merge_run() {
  : > "${TMP}/merge.gh"
  local rc=0
  stub_run "${TMP}/merge.sh" /dev/null GH_CALLS="${TMP}/merge.gh" STUB_GH_MERGE_FAILS="$1" \
    DEFAULT_BRANCH=main GH_TOKEN="t0ken" || rc=$?
  echo "$rc" > "${TMP}/merge.rc"
}

if [[ -f "$WF" && -n "$(step_by_id "$WF" guard text)" ]]; then
  : > "${TMP}/g10.output"
  stub_run "${TMP}/guard-stop.sh" /dev/null STUB_RC=0 STUB_OUT="merge v0.1.3 to v0.2.0" \
    GITHUB_TOKEN="t0ken" GITHUB_STEP_SUMMARY="${TMP}/g10.summary" GITHUB_OUTPUT="${TMP}/g10.output" \
    && g10_rc=0 || g10_rc=$?
  if [[ "$g10_rc" -eq 0 && "$(cat "${TMP}/g10.output")" == "merge=true" ]]; then
    echo "  ok: the guard step records merge=true when check-update exits 0"
  else
    fail "pin 10: on exit 0 the guard step exited ${g10_rc} with the output '$(paste -sd';' "${TMP}/g10.output")', not exactly the line merge=true"
  fi
  merge_text="$(step_by_id "$WF" merge text)"
  if [[ -z "$merge_text" ]]; then
    fail "pin 10: ${WF} has no merge step (a step with id: merge) after the guard"
    fail "pin 11: ${WF} has no merge step, so nothing starts forsgren.yml after a merge"
    fail "pin 12: ${WF} has no merge step, so a failed merge cannot be shown to fail the run and start nothing"
  else
    merge_env="$(step_by_id "$WF" merge env)"
    if grep -qxF -- "        if: steps.guard.outputs.merge == 'true'" <<< "$merge_text"; then
      echo "  ok: the merge step runs only when the guard said merge=true"
    else
      fail "pin 10: the merge step has no line 'if: steps.guard.outputs.merge == 'true''"
    fi
    for want in "GH_TOKEN: ${EXPR_OPEN} github.token }}" "PR_NUMBER: ${EXPR_OPEN} github.event.pull_request.number }}" "DEFAULT_BRANCH: ${EXPR_OPEN} github.event.repository.default_branch }}"; do
      if grep -qxF -- "$want" <<< "$merge_env"; then
        echo "  ok: the merge step sets ${want}"
      else
        fail "pin 10: the merge step does not set '${want}' in its env:"
      fi
    done
    step_by_id "$WF" merge run > "${TMP}/merge.sh"
    merge_run no
    first="$(sed -n 1p "${TMP}/merge.gh")"
    second="$(sed -n 2p "${TMP}/merge.gh")"
    if [[ "$first" == "pr merge 42 --squash --delete-branch --repo owner/name" ]]; then
      echo "  ok: the merge step's first call is gh ${first}"
    else
      fail "pin 10: the merge step's first gh call is '${first}', not 'pr merge 42 --squash --delete-branch --repo owner/name'"
    fi
    if [[ "$second" == "workflow run forsgren.yml --ref main --repo owner/name" && "$(wc -l < "${TMP}/merge.gh" | tr -d ' ')" -eq 2 ]]; then
      echo "  ok: the merge step's second and last call is gh ${second}"
    else
      fail "pin 11: the merge step's second gh call is '${second}' (of $(wc -l < "${TMP}/merge.gh" | tr -d ' ') calls), not 'workflow run forsgren.yml --ref main --repo owner/name' as the last"
    fi
    merge_run yes
    if [[ "$(cat "${TMP}/merge.rc")" -ne 0 && "$(cat "${TMP}/merge.gh")" == "pr merge 42 --squash --delete-branch --repo owner/name" ]]; then
      echo "  ok: a failed merge fails the step and starts no workflow"
    else
      fail "pin 12: with a failing gh pr merge the merge step exited $(cat "${TMP}/merge.rc") and called '$(paste -sd';' "${TMP}/merge.gh")'; it must exit non-zero and call only the pr merge"
    fi
  fi
fi

selftest_end "auto_update.yml is not the reusable workflow forsgren#58 rules" \
  "auto_update.yml runs on workflow_call only"
