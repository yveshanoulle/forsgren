#!/usr/bin/env bash
# Scripts/test_metrics_workflow.sh
#
# Pins .github/workflows/metrics.yml, the REUSABLE workflow an installation's
# data repository calls once a day (forsgren#4, walking skeleton step 2 of
# #3). forsgren's own: no repo of the estate has a reusable workflow. It
# installs forsgren from the very commit the caller calls it at, renders the
# page and publishes it to the caller's GitHub Pages. Nothing in forsgren
# itself runs it, so no gate runs it either: this pin is what proves it, in
# sfl and Quality, on every run.
#
# ONE VERSION SOURCE (ruling on forsgren#4, 2026-10-02): the caller's single
# `uses: …/metrics.yml@<SHA> # vX.Y.Z` line is the only version. The
# workflow takes no input naming a forsgren version; it installs forsgren
# from its OWN commit and repository, which GitHub gives a called workflow
# in the job context: job.workflow_sha and job.workflow_repository ("the
# commit SHA" / "the owner/repo of the repository containing the workflow
# file that defines the current job"). The github context will not do:
# "When a reusable workflow is triggered by a caller workflow, the github
# context is always associated with the caller workflow", so
# github.workflow_sha is the CALLER's commit.
#
# THE PINS, on metrics.yml:
#   1. it triggers on workflow_call and on nothing else: forsgren's own
#      repository never runs it (it would publish forsgren's Pages), and no
#      pull request can;
#   2. workflow_call declares no inputs: no second version source, under
#      forsgren-version or any other name;
#   3. no run: block expands a ${{ }} expression: the commit and repository
#      reach the shell through env: only, never as text pasted into the
#      script (template injection);
#   4. the step "Install forsgren from this workflow's own commit" exists,
#      and its env: sets FORSGREN_SHA to ${{ job.workflow_sha }} and
#      FORSGREN_REPOSITORY to ${{ job.workflow_repository }}, the called
#      workflow's own commit and repository (never github.*, the caller's);
#   5. that step's run: block, EXECUTED here with a stub go on PATH that
#      records its arguments:
#        - runs exactly `go install
#          github.com/yveshanoulle/forsgren/cmd/forsgren@<sha>` for the
#          commit 1997c4ff… (v0.0.1) of yveshanoulle/forsgren;
#        - for a fork, acme/forsgren, installs github.com/acme/forsgren,
#          never upstream: the commit and the repository come from the same
#          context, so a fork runs its own code or (when its go.mod still
#          declares upstream's module path) fails by name in go install;
#        - refuses, before go runs at all, every commit that is not 40
#          lower-case hex digits (a tag, a branch, latest, a short or long
#          hash, capitals, a trailing newline, space or command, empty) and
#          every repository that is not one owner/name (a bare owner, a
#          third path element, a leading dot, a space, a newline, a `;`,
#          another host, empty). Executed, not grepped: the checks are
#          pinned by what they do;
#   6. actions/setup-go installs exactly the Go of go.mod's toolchain line
#      (Scripts/go_toolchain.sh), the Go that sfl, FBP.sh and Quality build
#      with, and comes before the install step. setup-go exports
#      GOTOOLCHAIN=local, so go install uses that Go and never switches: the
#      pin is the whole choice, and a toolchain bump in go.mod without one
#      here is red;
#   7. the step "Check out the caller's repository" exists: actions/checkout
#      pinned by a full commit, the very one Quality's own checkout uses
#      (one version of the action in the repository), with
#      persist-credentials: false, so the caller's token is not left in the
#      checkout's git config;
#   8. the step "Check the caller's forsgren configuration", whose run: block
#      is EXECUTED here with a stub forsgren on PATH, runs exactly
#      `forsgren check-config --config forsgren.config.yml`; on success it
#      exits 0 and writes no failure to $GITHUB_STEP_SUMMARY; on a refusal it
#      prints check-config's message, writes it to $GITHUB_STEP_SUMMARY with
#      a cross mark before it, and exits non-zero, so the job fails with the
#      message and nothing is rendered or published from a bad config;
#   9. the order: install, then checkout, then the config check, then
#      "Render the page".
#
# WHY THE SHELL IS INLINE, NOT A Scripts/ FILE (the estate rule puts CI
# loop bodies in tested scripts). The job runs in the CALLER's repository
# and checks out the CALLER's repository, never forsgren: forsgren's scripts
# are not on the runner. Fetching one would mean checking out forsgren at the
# very commit the install step has not checked yet. The install checks are
# two regex tests and the config check is one command and one write, and
# pins 5 and 8 execute those very blocks, so they are tested where they live.
#
# Read with awk and grep, not a YAML parser, as
# Scripts/test_quality_trigger_scope.sh and Scripts/check_workflow_triggers.sh
# are, for their reason: PyYAML is a module, not a command, and nothing here
# installs it. The shape read is the one metrics.yml is written in: `on:` at
# column 0, its events two spaces in; a step starts at `      - `, its keys
# eight spaces in; a `run: |` or `env:` block is every following line
# indented deeper than its key.
#
# Self-proving: each pin is shown failing on a mutant of the real metrics.yml,
# naming its own reason, so a broken matcher cannot pass in silence.
#
# Usage: Scripts/test_metrics_workflow.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "the metrics workflow pin"

WF=".github/workflows/metrics.yml"
INSTALL_STEP="Install forsgren from this workflow's own commit"
CHECKOUT_STEP="Check out the caller's repository"
CHECK_STEP="Check the caller's forsgren configuration"
RENDER_STEP="Render the page"
CROSS="❌"
CONFIG_CMD="check-config --config forsgren.config.yml"
# The opening of a GitHub expression, in double quotes with the dollar
# escaped, so no reader (shellcheck included) takes it for an expansion.
EXPR_OPEN="\${{"
# v0.0.1's commit: a real one, so the case reads as what a run sees.
SHA="1997c4ff09aecd32c30fbdd7eef72485f146e865"
UPSTREAM="yveshanoulle/forsgren"

# on_events <file>: the event names of the column-0 `on:` block, one per line.
on_events() {
  awk '
    /^on:[[:space:]]*$/ { inon=1; next }
    inon && /^[^[:space:]#]/ { inon=0 }
    inon && /^  [A-Za-z_]+:/ { s=$0; sub(/^  /, "", s); sub(/:.*$/, "", s); print s }
  ' "$1"
}

# call_keys <file>: the keys under `on: workflow_call:`, one per line.
call_keys() {
  awk '
    /^  workflow_call:/ { incall=1; next }
    incall && /^ {0,2}[^[:space:]#]/ { incall=0 }
    incall && /^    [A-Za-z_-]+:/ { s=$0; sub(/^    /, "", s); sub(/:.*$/, "", s); print s }
  ' "$1"
}

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

# step_text <file> <step name>: every line of that step, the dash line
# included; nothing when there is no such step.
step_text() {
  awk -v name="$2" '
    /^      - / { instep = ($0 == "      - name: " name) }
    instep { print }
  ' "$1"
}

# line_of <file> <fixed text>: the line number of its first occurrence.
line_of() {
  grep -nF -- "$2" "$1" | head -1 | cut -d: -f1
}

# Stub go: records its arguments, one call per line, and succeeds.
STUB="${TMP}/stub"
mkdir -p "$STUB"
cat > "${STUB}/go" <<'STUBGO'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GO_CALLS"
STUBGO
chmod +x "${STUB}/go"

# install_outcome <script> <sha> <repository>: what the install step does
# with them: `refused` (non-zero, go never ran), `installed <go args>` (zero,
# go ran once), or `broken: …` for any other mix.
install_outcome() {
  local calls="${TMP}/go.calls" rc=0 n
  rm -f "$calls" "${TMP}/github_path"
  : > "$calls"
  PATH="${STUB}:${PATH}" GO_CALLS="$calls" RUNNER_TEMP="${TMP}/runner" \
    GITHUB_PATH="${TMP}/github_path" FORSGREN_SHA="$2" FORSGREN_REPOSITORY="$3" \
    bash "$1" >/dev/null 2>&1 || rc=$?
  n="$(wc -l < "$calls" | tr -d ' ')"
  if [[ "$rc" -ne 0 && "$n" -eq 0 ]]; then
    echo refused
  elif [[ "$rc" -eq 0 && "$n" -eq 1 ]]; then
    echo "installed $(cat "$calls")"
  else
    echo "broken: exit ${rc}, go ran ${n} time(s)"
  fi
}

# Stub forsgren: records its arguments, one call per line; with
# STUB_REFUSAL set it says that on stderr and exits 1, else it says OK.
cat > "${STUB}/forsgren" <<'STUBFORSGREN'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FG_CALLS"
if [[ -n "${STUB_REFUSAL:-}" ]]; then
  printf '%s\n' "$STUB_REFUSAL" >&2
  exit 1
fi
echo "OK: stub"
STUBFORSGREN
chmod +x "${STUB}/forsgren"

# config_outcome <script> <refusal>: what the config step does when check-config
# says OK (empty <refusal>) or refuses with <refusal>, as one line:
# exit=<rc> calls=<forsgren args> log=<shown|hidden> summary=<summary file>.
# <log> says whether check-config's message reached the job log.
config_outcome() {
  local calls="${TMP}/fg.calls" summary="${TMP}/summary.md" log="${TMP}/config.log" rc=0 shown=hidden
  rm -f "$calls" "$summary" "$log"
  : > "$calls"
  : > "$summary"
  PATH="${STUB}:${PATH}" FG_CALLS="$calls" STUB_REFUSAL="$2" \
    GITHUB_STEP_SUMMARY="$summary" bash "$1" > "$log" 2>&1 || rc=$?
  if [[ -n "$2" ]] && grep -qF -- "$2" "$log"; then shown=shown; fi
  echo "exit=${rc} calls=$(paste -sd, - < "$calls") log=${shown} summary=$(cat "$summary")"
}

# judge_checkout <workflow-file>: pin 7, the caller's checkout.
judge_checkout() {
  local text uses ref want
  text="$(step_text "$1" "$CHECKOUT_STEP")"
  if [[ -z "$text" ]]; then
    echo "has no step '${CHECKOUT_STEP}' — the caller's forsgren.config.yml is not on the runner to check"
    return 0
  fi
  uses="$(grep -E '^[[:space:]]+uses:' <<< "$text" | head -1 || true)"
  ref="$(sed -n 's/^[[:space:]]*uses:[[:space:]]*actions\/checkout@\([0-9a-f]\{40\}\)\([[:space:]].*\)\{0,1\}$/\1/p' <<< "$uses")"
  if [[ -z "$ref" ]]; then
    echo "the checkout step uses '${uses#*uses: }', not actions/checkout pinned by a full 40-digit commit — a tag can be re-pointed, a commit cannot"
    return 0
  fi
  want="$(sed -n 's/^[[:space:]-]*uses:[[:space:]]*actions\/checkout@\([0-9a-f]\{40\}\).*$/\1/p' .github/workflows/quality.yml | head -1)"
  if [[ "$ref" != "$want" ]]; then
    echo "the checkout step is pinned at ${ref}, not at ${want} as Quality's own checkout is — one version of actions/checkout in this repository"
  fi
  if ! grep -qE '^[[:space:]]+persist-credentials:[[:space:]]*false[[:space:]]*$' <<< "$text"; then
    echo "the checkout step does not set persist-credentials: false — the caller's token would stay in the checkout's git config for every later step"
  fi
}

# judge_config_step <workflow-file>: pin 8, the executed config check.
judge_config_step() {
  local script="${TMP}/config.sh" got want refusal
  step_block "$1" "$CHECK_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${CHECK_STEP}' with a run: | block — a missing or invalid forsgren.config.yml is not caught before render"
    return 0
  fi
  got="$(config_outcome "$script" "")"
  want="exit=0 calls=${CONFIG_CMD} log=hidden summary="
  [[ "$got" == "$want" ]] || echo "for a valid config the config step gives '${got}', not '${want}'"
  refusal="check-config: forsgren.config.yml: cannot read the config file"
  got="$(config_outcome "$script" "$refusal")"
  want="exit=1 calls=${CONFIG_CMD} log=shown summary=${CROSS} ${refusal}"
  [[ "$got" == "$want" ]] || echo "for a refused config the config step gives '${got}', not '${want}' — the job must fail with check-config's message in the log and in the step summary after a cross mark"
}

# judge_order <workflow-file>: pin 9.
judge_order() {
  local install checkout check render
  install="$(line_of "$1" "- name: ${INSTALL_STEP}")"
  checkout="$(line_of "$1" "- name: ${CHECKOUT_STEP}")"
  check="$(line_of "$1" "- name: ${CHECK_STEP}")"
  render="$(line_of "$1" "- name: ${RENDER_STEP}")"
  if [[ -n "$check" && -n "$render" && "$check" -gt "$render" ]]; then
    echo "checks the config (line ${check}) after it renders (line ${render}) — a bad config must stop the job before render"
  fi
  if [[ -n "$check" && -n "$checkout" && "$checkout" -gt "$check" ]]; then
    echo "checks out the caller's repository (line ${checkout}) after the config check (line ${check}) — the file is not there yet"
  fi
  if [[ -n "$check" && -n "$install" && "$install" -gt "$check" ]]; then
    echo "installs forsgren (line ${install}) after the config check (line ${check}) — check-config is not on PATH yet"
  fi
}

# judge <workflow-file>: one problem per line; silent when every pin holds.
judge() {
  local wf="$1" events keys runs env script got v want setup_line install_line go_version toolchain
  events="$(on_events "$wf")"
  if [[ "$events" != "workflow_call" ]]; then
    echo "triggers on [$(printf '%s' "$events" | paste -sd, -)], not on workflow_call alone — forsgren's own repository must never run it, and no pull request may"
  fi

  keys="$(call_keys "$wf")"
  if [[ -n "$keys" ]]; then
    echo "workflow_call declares [$(printf '%s' "$keys" | paste -sd, -)] — the caller's uses: line is the only version source, so it takes no input"
  fi

  runs="$(run_blocks "$wf")"
  if grep -qF "$EXPR_OPEN" <<< "$runs"; then
    echo "expands a \${{ }} expression inside run: (line $(grep -F "$EXPR_OPEN" <<< "$runs" | head -1 | cut -d: -f1)) — values reach the shell through env: only (template injection)"
  fi

  env="$(step_block "$wf" "$INSTALL_STEP" env)"
  if ! grep -qxE "FORSGREN_SHA:[[:space:]]*\\$\\{\\{ job\\.workflow_sha \\}\\}" <<< "$env"; then
    echo "the install step's FORSGREN_SHA is not \${{ job.workflow_sha }} — only the job context gives a called workflow its own commit (github.* is the caller's)"
  fi
  if ! grep -qxE "FORSGREN_REPOSITORY:[[:space:]]*\\$\\{\\{ job\\.workflow_repository \\}\\}" <<< "$env"; then
    echo "the install step's FORSGREN_REPOSITORY is not \${{ job.workflow_repository }} — the repository must come from the same context as the commit"
  fi

  script="${TMP}/install.sh"
  step_block "$wf" "$INSTALL_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${INSTALL_STEP}' with a run: | block — nothing installs forsgren from this workflow's own commit"
  else
    got="$(install_outcome "$script" "$SHA" "$UPSTREAM")"
    want="installed install github.com/${UPSTREAM}/cmd/forsgren@${SHA}"
    [[ "$got" == "$want" ]] || echo "for ${UPSTREAM} at ${SHA} the install step gives '${got}', not '${want}'"
    got="$(install_outcome "$script" "$SHA" acme/forsgren)"
    want="installed install github.com/acme/forsgren/cmd/forsgren@${SHA}"
    [[ "$got" == "$want" ]] || echo "for the fork acme/forsgren the install step gives '${got}', not '${want}' — a fork must install its own repository, never upstream in silence"
    for v in v0.0.1 latest main e1b36d2 "${SHA:0:39}" "${SHA}0" \
             "$(tr 'a-f' 'A-F' <<< "$SHA")" "${SHA:0:39}g" "${SHA} " " ${SHA}" \
             "${SHA};id" "${SHA}"$'\n'main ''; do
      got="$(install_outcome "$script" "$v" "$UPSTREAM")"
      [[ "$got" == refused ]] || echo "the install step gives '${got}' for the commit '$(printf '%q' "$v")', which is not 40 lower-case hex digits — it must refuse before go runs"
    done
    for v in yveshanoulle yveshanoulle/forsgren/extra .hidden/forsgren yveshanoulle/.forsgren \
             '../forsgren' 'yveshanoulle/forsgren ' 'yveshanoulle/forsgren;id' \
             "yveshanoulle/forsgren"$'\n'x 'evil.example/forsgren' ''; do
      got="$(install_outcome "$script" "$SHA" "$v")"
      [[ "$got" == refused ]] || echo "the install step gives '${got}' for the repository '$(printf '%q' "$v")', which is not one owner/name — it must refuse before go runs"
    done
  fi

  install_line="$(line_of "$wf" "- name: ${INSTALL_STEP}")"
  setup_line="$(grep -nE 'uses:[[:space:]]*actions/setup-go@' "$wf" | head -1 | cut -d: -f1)"
  if [[ -n "$install_line" && -n "$setup_line" ]] && [[ "$setup_line" -gt "$install_line" ]]; then
    echo "sets up Go (line ${setup_line}) after the install step (line ${install_line}) — go install would run on the runner's own Go"
  fi

  go_version="$(awk '
    /uses:[[:space:]]*actions\/setup-go@/ { insg=1; next }
    insg && /^      - / { insg=0 }
    insg && /^[[:space:]]+go-version:/ { v=$0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/["\047]/, "", v); print v; exit }
  ' "$wf")"
  toolchain="$(./Scripts/go_toolchain.sh)"
  if [[ "$go_version" != "${toolchain#go}" ]]; then
    echo "actions/setup-go installs Go '${go_version:-none}', not ${toolchain#go} from go.mod's toolchain line — the release would be built with another Go than sfl, FBP.sh and Quality use"
  fi

  judge_checkout "$wf"
  judge_config_step "$wf"
  judge_order "$wf"
}

if [[ ! -f "$WF" ]]; then
  selftest_abort "${WF} not found — an installation's data repository has no forsgren workflow to call"
fi

verdict="$(judge "$WF")"
if [[ -n "$verdict" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && fail "${WF} ${line}"
  done <<< "$verdict"
else
  echo "  ok: ${WF} is a workflow_call with no inputs that installs forsgren from its own job.workflow_repository at its own job.workflow_sha, both checked before go install, through env: only, built with go.mod's Go"
fi

# --- Self-proof: each pin, on a mutant of the real metrics.yml, names its reason.
# proves <case> <reason> <sed-expression>
proves() {
  local mutant="${TMP}/mutants/$1.yml" got
  selftest_mutant "$WF" "$mutant" "$3" || return 0
  got="$(judge "$mutant")"
  if grep -qF -- "$2" <<< "$got"; then
    echo "  ok: $1 is rejected"
  else
    fail "the mutant with $1 was ACCEPTED (verdict: ${got:-none}) — this pin cannot detect the defect it exists for"
  fi
}

proves "a push trigger" "not on workflow_call alone" \
  's/^  workflow_call:$/  push:\n  workflow_call:/'
proves "a forsgren-version input back" "workflow_call declares [inputs]" \
  's/^  workflow_call:$/  workflow_call:\n    inputs:\n      forsgren-version:\n        type: string\n        required: true/'
proves "the commit pasted into run:" "expands a \${{ }} expression inside run:" \
  "s/@\\\${FORSGREN_SHA}\"\$/@\${{ job.workflow_sha }}\"/"
proves "the caller's commit" "FORSGREN_SHA is not" \
  's/job\.workflow_sha }}/github.workflow_sha }}/'
proves "the caller's repository" "FORSGREN_REPOSITORY is not" \
  's/job\.workflow_repository }}/github.repository }}/'
proves "no install step" "has no step '${INSTALL_STEP}'" \
  "s/- name: ${INSTALL_STEP}\$/- name: Install something else/"
proves "checks that accept anything" "for the commit 'latest'" \
  's/^\( *\)exit 1$/\1exit 0/'
proves "a commit check without its end anchor" "for the commit '${SHA}0'" \
  's/{40}\$/{40}/'
proves "a repository check that lets a third element through" "for the repository 'yveshanoulle/forsgren/extra'" \
  's/\[A-Za-z0-9_\.-\]\*\$/[A-Za-z0-9_.\/-]*$/'
proves "upstream installed for every caller" "for the fork acme/forsgren" \
  "s|github.com/\\\${FORSGREN_REPOSITORY}/cmd|github.com/yveshanoulle/forsgren/cmd|"
proves "go install at another version" "the install step gives 'installed install github.com/${UPSTREAM}/cmd/forsgren@v0.0.1'" \
  "s/@\\\${FORSGREN_SHA}\"\$/@v0.0.1\"/"
proves "setup-go on another Go" "actions/setup-go installs Go '1.0.0'" \
  "s/^\(          go-version: \).*\$/\1'1.0.0'/"

proves "no checkout pin" "not actions/checkout pinned by a full 40-digit commit" \
  's|actions/checkout@[0-9a-f]\{40\}  # v7.0.1|actions/checkout@v7|'
proves "another checkout commit" "not at 3d3c42e5aac5ba805825da76410c181273ba90b1 as Quality's own checkout is" \
  's|actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1|actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b2|'
proves "persist-credentials true" "does not set persist-credentials: false" \
  's/persist-credentials: false/persist-credentials: true/'
proves "no checkout step" "has no step '${CHECKOUT_STEP}'" \
  "s/- name: ${CHECKOUT_STEP}\$/- name: Check out something else/"
proves "no config step name" "has no step '${CHECK_STEP}'" \
  "s/- name: ${CHECK_STEP}\$/- name: Check something else/"
proves "check-config on another file" "for a valid config the config step gives" \
  's/--config forsgren\.config\.yml/--config config.yml/'
proves "a config step that lets a refusal pass" "for a refused config the config step gives 'exit=0" \
  '/- name: Check the caller/,/- name: Render/ s/exit 1/exit 0/'
proves "a refusal without its cross mark" "for a refused config the config step gives 'exit=1 calls=${CONFIG_CMD} log=shown summary=check-config" \
  's/"❌ /"/'

# Removing the config step altogether: the mutant must differ from the real
# file, and be refused for the missing step.
removed="${TMP}/mutants/no-config-step.yml"
mkdir -p "${TMP}/mutants"
awk -v name="$CHECK_STEP" '
  /^      - / { instep = ($0 == "      - name: " name) }
  !instep { print }
' "$WF" > "$removed"
if cmp -s "$WF" "$removed"; then
  fail "removing the step '${CHECK_STEP}' changed nothing in ${WF}: the proof would be vacuous"
else
  got="$(judge "$removed")"
  if grep -qF "has no step '${CHECK_STEP}'" <<< "$got"; then
    echo "  ok: a workflow without the config step is rejected"
  else
    fail "the mutant without the step '${CHECK_STEP}' was ACCEPTED (verdict: ${got:-none}) — a missing config check would pass"
  fi
fi

# The order pin for the config step: it moved to just before "Upload the page"
# (after render).
late="${TMP}/mutants/config-after-render.yml"
awk -v name="$CHECK_STEP" '
  /^      - / { instep = ($0 == "      - name: " name) }
  instep { held = held $0 "\n"; next }
  { lines[++n] = $0 }
  END {
    for (i = 1; i <= n; i++) {
      if (lines[i] == "      - name: Upload the page") printf "%s", held
      print lines[i]
    }
  }
' "$WF" > "$late"
got="$(judge "$late")"
if grep -qF "after it renders" <<< "$got"; then
  echo "  ok: the config check after render is rejected"
else
  fail "the mutant with the config check after render was ACCEPTED (verdict: ${got:-none}) — the order pin cannot detect it"
fi

# The order pin: the install step moved to just before "Set up Go".
reorder="${TMP}/mutants/reorder.yml"
awk -v name="$INSTALL_STEP" '
  /^      - / { instep = ($0 == "      - name: " name) }
  instep { held = held $0 "\n"; next }
  { lines[++n] = $0 }
  END {
    for (i = 1; i <= n; i++) {
      if (lines[i] == "      - name: Set up Go") printf "%s", held
      print lines[i]
    }
  }
' "$WF" > "$reorder"
got="$(judge "$reorder")"
if grep -qF "after the install step" <<< "$got"; then
  echo "  ok: the install step before setup-go is rejected"
else
  fail "the mutant with the install step before setup-go was ACCEPTED (verdict: ${got:-none}) — the order pin cannot detect it"
fi

selftest_end "metrics.yml is not the reusable workflow forsgren#4 rules" \
  "metrics.yml runs on workflow_call only, takes no input, installs forsgren from its own job.workflow_repository at its own job.workflow_sha (each checked before go runs, a fork installing itself), passes both through env: only, and builds with go.mod's Go after setup-go (and each wrong shape is still detected)"
