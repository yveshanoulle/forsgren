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
selftest_begin "the auto-update workflow pin"

WF=".github/workflows/auto_update.yml"
METRICS=".github/workflows/metrics.yml"
GO_STEP="Set up Go"
INSTALL_STEP="Install forsgren from this workflow's own commit"
# The opening of a GitHub expression, in double quotes with the dollar
# escaped, so no reader (shellcheck included) takes it for an expansion.
EXPR_OPEN="\${{"

# The helpers below are COPIES of Scripts/test_metrics_workflow.sh's, for the
# refactor step of forsgren#58 to move into one shared library.

# run_blocks <file>: every run: line and the lines of its block, as
# <lineno>:<text>, so a finding names its line.
run_blocks() {
  awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    inrun && $0 !~ /^[[:space:]]*$/ && indent($0) <= runind { inrun=0 }
    inrun { print NR ":" $0; next }
    /^[[:space:]]*(- )?run:/ {
      print NR ":" $0
      runind = indent($0)
      if ($0 ~ /- run:/) runind += 2
      if ($0 ~ /run:[[:space:]]*[|>][-+]?[[:space:]]*$/) inrun=1
    }
  ' "$1"
}

# step_text <file> <step name>: every line of that step, the dash line
# included; nothing when there is no such step.
step_text() {
  awk -v name="$2" '
    /^      - / { instep = ($0 == "      - name: " name) }
    instep { print }
  ' "$1"
}

# step_block <file> <step name> <key>: the block under that step's key
# (run or env), its lines dedented; nothing when there is no such step.
step_block() {
  awk -v name="$2" -v key="$3" '
    function indent(s) { match(s, /^ */); return RLENGTH }
    /^      - / { instep = ($0 == "      - name: " name); inb=0; next }
    instep && inb && $0 !~ /^[[:space:]]*$/ && indent($0) <= 8 { inb=0 }
    instep && inb { if (!cut) { match($0, /^ */); cut = RLENGTH } print substr($0, cut + 1); next }
    instep && $0 ~ ("^        " key ":[[:space:]]*\\|?[[:space:]]*$") { inb=1 }
  ' "$1"
}

# line_of <file> <fixed text>: the line number of its first occurrence.
line_of() {
  grep -nF -- "$2" "$1" | head -1 | cut -d: -f1
}

# later <line> <other line>: true when both are known and the first comes
# after the second.
later() {
  [[ -n "$1" && -n "$2" && "$1" -gt "$2" ]]
}

# on_events <file>: the event names of the column-0 `on:` block, one per line.
on_events() {
  awk '
    /^on:[[:space:]]*$/ { inon=1; next }
    inon && /^[^[:space:]#]/ { inon=0 }
    inon && /^  [A-Za-z_]+:/ { s=$0; sub(/^  /, "", s); sub(/:.*$/, "", s); print s }
  ' "$1"
}

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
# for metrics.yml; install_outcome is a COPY, for the refactor step). STANDING
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

selftest_end "auto_update.yml is not the reusable workflow forsgren#58 rules" \
  "auto_update.yml runs on workflow_call only"
