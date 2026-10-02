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
#      here is red.
#
# WHY THE CHECKS ARE INLINE, NOT A Scripts/ FILE (the estate rule puts CI
# loop bodies in tested scripts). The job runs in the CALLER's repository
# and checks nothing out: forsgren's scripts are not on the runner. Fetching
# one would mean checking out forsgren at the very commit it has not checked
# yet. The checks are two regex tests, and pin 5 executes that very block,
# so they are tested where they live.
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
