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
#      "Render the page";
#  10. the config step, EXECUTED with the stub forsgren refusing with a
#      message whose lines start with `::warning::` and `  ::add-mask::`,
#      leaves no workflow command live in the log: every such line sits
#      between `::stop-commands::<token>` and `::<token>::`, the token
#      differs from run to run (a config cannot know it and turn commands
#      back on), and the message is still shown (forsgren#9, item 1);
#  11. the config step, EXECUTED with the real forsgren, built here from this
#      checkout, in a workspace with no forsgren.config.yml, an invalid one,
#      a valid one, and one whose unknown key carries a line break and
#      `::warning::`: refused with check-config's own message in the log and
#      after the cross mark in the summary, accepted with its OK line and an
#      empty summary, and no workflow command left live (forsgren#9, item 3);
#  12. the step "Write the starter configuration on a new install" (forsgren#12,
#      step 3), whose run: block is EXECUTED here with the real git against a
#      local remote and a stub forsgren: it runs `forsgren init-config
#      --config forsgren.config.yml`; when that says `kept` nothing is
#      committed or pushed; when it says `created` it commits forsgren.config.yml
#      ALONE (another staged file and an untracked one stay out), authored and
#      committed by `github-actions[bot]`, with the message "forsgren: add a
#      starter forsgren.config.yml", and pushes it to the branch the run is
#      on, HEAD:${GITHUB_REF} from the runner's env (`trunk` here, a manual
#      run on `feature` gets it there; no default-branch name is read from
#      any event payload, which a scheduled run may not carry); a kept file
#      exits 0 BEFORE any branch logic, even with no ref at all, so a daily
#      run never fails here; a created one on a ref that is not a branch (a
#      tag) refuses and pushes nothing;
#  13. that push carries the token as an Authorization header in the
#      ENVIRONMENT (GIT_CONFIG_COUNT/KEY_0/VALUE_0, scoped to the server URL)
#      and nowhere else: not in any git argument (ps shows arguments, git's
#      messages quote them), not in a file of the checkout (persist-credentials:
#      false stays meaningful), not in the log;
#  14. the same step with the REAL forsgren: a new install's checkout gets the
#      embedded starter committed, the config check that follows passes on it
#      (projects: 0), and the next run keeps it with no second commit;
#  15. the render step runs `forsgren render --out ... --config
#      forsgren.config.yml`, so the page can say when no projects are
#      configured, executed with the stub;
#  16. the job grants itself `contents: write`, which the push needs;
#  and pin 9 also orders the starter step: after the install and the checkout,
#  before the config check.
#
# WHY THE SHELL IS INLINE, NOT A Scripts/ FILE (the estate rule puts CI
# loop bodies in tested scripts). The job runs in the CALLER's repository
# and checks out the CALLER's repository, never forsgren: forsgren's scripts
# are not on the runner. Fetching one would mean checking out forsgren at the
# very commit the install step has not checked yet. The install checks are
# two regex tests and the config check is one command, its output between
# the two lines that stop and resume workflow commands, and one write, and
# pins 5, 8, 10 and 11 execute those very blocks, so they are tested where
# they live. The starter step (forsgren#12) stays inline for the same reason,
# and its logic is the commit and the push, which only git can do: moving the
# result into the forsgren binary would not remove one git line from the
# YAML. Pins 12 to 14 execute its block with a real git and the real
# forsgren, so it is tested where it lives, too.
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
INIT_STEP="Write the starter configuration on a new install"
CROSS="❌"
CONFIG_CMD="check-config --config forsgren.config.yml"
INIT_CMD="init-config --config forsgren.config.yml"
# A literal dollar, so a sed expression in double quotes can carry ${ } text
# without a reader taking it for an expansion.
D='$'
# The starter commit (forsgren#12): who, and what it says.
BOT_IDENTITY="github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>"
STARTER_SUBJECT="forsgren: add a starter forsgren.config.yml"
# The branch of the made-up installation, and a token that no
# argument, file or log may ever show.
TRUNK="trunk"
SECRET="s3cretToken-acme-9f2"
# The opening of a GitHub expression, in double quotes with the dollar
# escaped, so no reader (shellcheck included) takes it for an expansion.
EXPR_OPEN="\${{"
# v0.0.1's commit: a real one, so the case reads as what a run sees.
SHA="1997c4ff09aecd32c30fbdd7eef72485f146e865"
UPSTREAM="yveshanoulle/forsgren"
# Made-up configs for pin 11, the config step with the real forsgren.
VALID_CONFIG=$'version: 1\nprojects:\n  - name: Acme\n    repositories:\n      - name: acme/app\n'
INVALID_CONFIG="${VALID_CONFIG}"$'        deployment: releases\n'
INJECTING_CONFIG=$'version: 1\nprojects:\n  - name: Acme\n    "x\\n::warning::injected": 1\n    repositories:\n      - name: acme/app\n'

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

# later <line> <other line>: true when both are known and the first comes
# after the second.
later() {
  [[ -n "$1" && -n "$2" && "$1" -gt "$2" ]]
}

# move_step <file> <step name> [<before step name>]: the file with that step
# moved to just before the other step, or removed when no other is named.
move_step() {
  awk -v name="$2" -v before="${3:-}" '
    /^      - / { instep = ($0 == "      - name: " name) }
    instep { held = held $0 "\n"; next }
    { lines[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        if (before != "" && lines[i] == "      - name: " before) printf "%s", held
        print lines[i]
      }
    }
  ' "$1"
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

# Stub forsgren: records its arguments, one call per line; init-config
# writes a starter and says `created <path>` when STUB_INIT is created, else
# says `kept <path>`; otherwise, with STUB_REFUSAL set, it says that on
# stderr and exits 1, else it says OK.
cat > "${STUB}/forsgren" <<'STUBFORSGREN'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FG_CALLS"
if [[ "${1:-}" == init-config ]]; then
  if [[ "${STUB_INIT:-kept}" == created ]]; then
    printf 'version: 1\nprojects: []\n' > "$3"
    echo "created $3"
  else
    echo "kept $3"
  fi
  exit 0
fi
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

# live_commands <log>: every line of the log the runner would take for a
# workflow command (`::` at its start, after any blanks) outside a
# ::stop-commands::<token> ... ::<token>:: pair, as `line <n>: <text>`, and
# a pair never closed. Nothing when every workflow command in it is
# neutralised.
live_commands() {
  awk '
    token == "" && /^::stop-commands::./ { token = substr($0, 18); next }
    token != "" && $0 == "::" token "::" { token = ""; next }
    token == "" && /^[[:space:]]*::/ { print "line " NR ": " $0 }
    END { if (token != "") print "::stop-commands::" token " never ended" }
  ' "$1"
}

# stop_token <log>: the token of the first ::stop-commands:: line, if any.
stop_token() {
  sed -n 's/^::stop-commands::\(..*\)$/\1/p' "$1" | head -1
}

# The real forsgren, built once from this checkout for pin 11.
REAL="${TMP}/real"
mkdir -p "$REAL"
if ! go build -o "${REAL}/forsgren" ./cmd/forsgren > "${TMP}/build.log" 2>&1; then
  selftest_abort "cannot build ./cmd/forsgren for the end-to-end config step: $(cat "${TMP}/build.log")"
fi

# real_config_step <script> <config>: runs the config step with the real
# forsgren in a fresh workspace whose forsgren.config.yml is <config>, or
# that has none when <config> is `-`. Its exit status on stdout; its log in
# ${TMP}/real.log, its step summary in ${TMP}/real-summary.md.
real_config_step() {
  local ws="${TMP}/workspace" rc=0
  rm -rf "$ws"
  mkdir -p "$ws"
  [[ "$2" == - ]] || printf '%s' "$2" > "${ws}/forsgren.config.yml"
  : > "${TMP}/real-summary.md"
  (cd "$ws" && PATH="${REAL}:${PATH}" GITHUB_STEP_SUMMARY="${TMP}/real-summary.md" bash "$1") \
    > "${TMP}/real.log" 2>&1 || rc=$?
  echo "$rc"
}

# real_refusal <what> <rc> <message>: the problem, if any, with the last
# real_config_step refusing <what>: exit 1, <message> in the log, and in the
# summary after the cross mark.
real_refusal() {
  if [[ "$2" -ne 1 ]] || ! grep -qF -- "$3" "${TMP}/real.log" \
    || ! grep -qF -- "${CROSS} $3" "${TMP}/real-summary.md"; then
    echo "with the real forsgren and $1 the config step exits $2, logs '$(paste -sd'|' - < "${TMP}/real.log")' and summarises '$(paste -sd'|' - < "${TMP}/real-summary.md")' — it must fail with '$3' in the log and after the cross mark in the summary"
  fi
}

# The starter step runs with a REAL git (pins 12 to 17): this wrapper on PATH
# records each call's arguments (GIT_ARGV_LOG) and, when the call carries
# config in the environment, that too (GIT_ENV_LOG), then runs the real git.
REAL_GIT="$(command -v git)"
cat > "${STUB}/git" <<'STUBGIT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_ARGV_LOG"
if [[ -n "${GIT_CONFIG_COUNT:-}" ]]; then
  printf 'git %s\t%s=%s\n' "$*" "${GIT_CONFIG_KEY_0:-}" "${GIT_CONFIG_VALUE_0:-}" >> "$GIT_ENV_LOG"
fi
exec "$REAL_GIT" "$@"
STUBGIT
chmod +x "${STUB}/git"
ORIGIN="${TMP}/origin.git"
INSTALL="${TMP}/install"
GIT_ARGV_LOG="${TMP}/git.argv"
GIT_ENV_LOG="${TMP}/git.env"

# iso <git args>: the real git with no user or system config, so neither a
# signing key nor a hook of whoever runs this reaches a case.
iso() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 "$REAL_GIT" "$@" > /dev/null 2>&1
}

# iso_out <git args>: as iso, with its output.
iso_out() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 "$REAL_GIT" "$@" 2>/dev/null
}

# new_install: a made-up installation: a bare remote and a checkout of it,
# both on the default branch ${TRUNK}, with one commit and no
# forsgren.config.yml, as a new install's checkout is.
new_install() {
  rm -rf "$ORIGIN" "$INSTALL"
  iso init --bare "$ORIGIN"
  iso -C "$ORIGIN" symbolic-ref HEAD "refs/heads/${TRUNK}"
  iso init "$INSTALL"
  iso -C "$INSTALL" symbolic-ref HEAD "refs/heads/${TRUNK}"
  printf 'acme app\n' > "${INSTALL}/README.md"
  iso -C "$INSTALL" add README.md
  iso -C "$INSTALL" -c user.name=Setup -c user.email=setup@example.com commit -m "Initial commit"
  iso -C "$INSTALL" remote add origin "$ORIGIN"
  iso -C "$INSTALL" push origin "$TRUNK"
}

# starter_outcome <script> <created|kept|real> <ref> <branch>: runs the
# starter step in the installation's checkout, GITHUB_REF being <ref>, with
# the stub forsgren saying created or kept, or with the real one, and the
# token SECRET; as one line: exit=<rc> commits=<commits on the remote's
# <branch>, 0 when it has none>. The
# step's log is in ${TMP}/starter.log, forsgren's calls in ${TMP}/fg.calls.
starter_outcome() {
  local rc=0 commits path="${STUB}:${PATH}"
  [[ "$2" == real ]] && path="${REAL}:${path}"
  : > "${TMP}/fg.calls"
  : > "$GIT_ARGV_LOG"
  : > "$GIT_ENV_LOG"
  (cd "$INSTALL" && PATH="$path" FG_CALLS="${TMP}/fg.calls" STUB_INIT="$2" GH_TOKEN="$SECRET" \
    GITHUB_REF="$3" GITHUB_SERVER_URL="https://github.com" \
    GIT_ARGV_LOG="$GIT_ARGV_LOG" GIT_ENV_LOG="$GIT_ENV_LOG" REAL_GIT="$REAL_GIT" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 bash "$1") > "${TMP}/starter.log" 2>&1 || rc=$?
  commits="$(iso_out -C "$ORIGIN" rev-list --count "$4" || echo 0)"
  echo "exit=${rc} commits=${commits}"
}

# judge_starter_step <workflow-file>: pin 12, the executed starter step: it
# runs init-config on forsgren.config.yml; a kept file is never committed; a
# created one is committed alone, as github-actions[bot], and pushed to the
# branch the run is on; on a tag it refuses.
judge_starter_step() {
  local script="${TMP}/starter.sh" ref="refs/heads/${TRUNK}" got want calls who files
  step_block "$1" "$INIT_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${INIT_STEP}' with a run: | block — a new install's forsgren.config.yml is never written"
    return 0
  fi
  new_install
  got="$(starter_outcome "$script" kept "$ref" "$TRUNK")"
  want="exit=0 commits=1"
  [[ "$got" == "$want" ]] || echo "for a kept forsgren.config.yml the starter step gives '${got}', not '${want}' — an existing file is never committed or pushed"
  got="$(starter_outcome "$script" kept "" "$TRUNK")"
  [[ "$got" == "$want" ]] || echo "for a kept forsgren.config.yml with no branch ref at all the starter step gives '${got}', not '${want}' — a kept file exits 0 before any branch logic, or every daily run would fail"
  calls="$(paste -sd, - < "${TMP}/fg.calls")"
  [[ "$calls" == "$INIT_CMD" ]] || echo "the starter step runs 'forsgren ${calls}', not 'forsgren ${INIT_CMD}'"
  new_install
  printf 'untracked\n' > "${INSTALL}/other.txt"
  printf 'staged\n' > "${INSTALL}/staged.txt"
  iso -C "$INSTALL" add staged.txt
  got="$(starter_outcome "$script" created "$ref" "$TRUNK")"
  want="exit=0 commits=2"
  if [[ "$got" != "$want" ]]; then
    echo "for a created forsgren.config.yml on its branch the starter step gives '${got}', not '${want}' — the starter is committed and pushed there"
  else
    who="$(iso_out -C "$ORIGIN" log -1 --format='%an <%ae>' "$TRUNK")"
    [[ "$who" == "$BOT_IDENTITY" ]] || echo "the starter commit's author is '${who}', not '${BOT_IDENTITY}'"
    who="$(iso_out -C "$ORIGIN" log -1 --format='%cn <%ce>' "$TRUNK")"
    [[ "$who" == "$BOT_IDENTITY" ]] || echo "the starter commit's committer is '${who}', not '${BOT_IDENTITY}'"
    who="$(iso_out -C "$ORIGIN" log -1 --format='%B' "$TRUNK")"
    [[ "$who" == "$STARTER_SUBJECT" ]] || echo "the starter commit's message is '${who}', not '${STARTER_SUBJECT}'"
    files="$(iso_out -C "$ORIGIN" diff-tree --no-commit-id --name-only -r "$TRUNK" | paste -sd, -)"
    [[ "$files" == "forsgren.config.yml" ]] || echo "the starter commit holds [${files}], not forsgren.config.yml alone — one file only, never the rest of the checkout"
  fi
  new_install
  iso -C "$INSTALL" checkout -b feature
  got="$(starter_outcome "$script" created "refs/heads/feature" feature)"
  want="exit=0 commits=2"
  [[ "$got" == "$want" ]] || echo "for a created forsgren.config.yml on a manual run on feature the starter step gives '${got}', not '${want}' — the starter goes to the branch the run is on"
  got="$(iso_out -C "$ORIGIN" rev-list --count "$TRUNK")"
  [[ "$got" == 1 ]] || echo "a run on feature moved ${TRUNK} to ${got} commits — it must push to the run's own branch only"
  new_install
  got="$(starter_outcome "$script" created "refs/tags/v1" "$TRUNK")"
  want="exit=1 commits=1"
  [[ "$got" == "$want" ]] || echo "for a ref that is not a branch (refs/tags/v1) the starter step gives '${got}', not '${want}' — it must refuse, there is no branch to commit to"
}

# judge_starter_token <workflow-file>: pin 13, the push carries the token and
# never stores or shows it.
judge_starter_token() {
  local script="${TMP}/starter.sh" b64 got want
  step_block "$1" "$INIT_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  b64="$(printf 'x-access-token:%s' "$SECRET" | base64 | tr -d '\n')"
  new_install
  starter_outcome "$script" created "refs/heads/${TRUNK}" "$TRUNK" > /dev/null
  if grep -qF -- "$SECRET" "$GIT_ARGV_LOG" || grep -qF -- "$b64" "$GIT_ARGV_LOG"; then
    echo "the starter step hands the token to git in an argument — ps shows arguments and git's messages quote them; it goes through the environment only"
  fi
  if grep -rqF -- "$SECRET" "$INSTALL" || grep -rqF -- "$b64" "$INSTALL"; then
    echo "the starter step leaves the token on disk in the checkout — with persist-credentials: false nothing may keep it"
  fi
  if grep -qF -- "$SECRET" "${TMP}/starter.log" || grep -qF -- "$b64" "${TMP}/starter.log"; then
    echo "the starter step shows the token in its log"
  fi
  want="http.https://github.com/.extraheader=AUTHORIZATION: basic ${b64}"
  got="$(awk -F'\t' '$1 ~ /^git push / { print $2 }' "$GIT_ENV_LOG")"
  if [[ "$got" != "$want" ]]; then
    echo "the starter step's push carries '${got:-nothing}' in the environment, not '${want}' — without it the push has no credential"
  fi
}

# judge_starter_e2e <workflow-file>: pin 14, with the real forsgren a new
# install gets its starter committed, the config check passes on it, and the
# next run keeps it.
judge_starter_e2e() {
  local script="${TMP}/starter.sh" check="${TMP}/starter-check.sh" ref="refs/heads/${TRUNK}" got want rc=0
  step_block "$1" "$INIT_STEP" run > "$script"
  step_block "$1" "$CHECK_STEP" run > "$check"
  [[ -s "$script" && -s "$check" ]] || return 0
  new_install
  got="$(starter_outcome "$script" real "$ref" "$TRUNK")"
  want="exit=0 commits=2"
  [[ "$got" == "$want" ]] || echo "with the real forsgren a new install's starter step gives '${got}', not '${want}'"
  got="$(iso_out -C "$ORIGIN" show "${TRUNK}:forsgren.config.yml")"
  [[ "$got" == "$(cat internal/config/starter.yml)" ]] || echo "with the real forsgren the committed forsgren.config.yml is not internal/config/starter.yml"
  (cd "$INSTALL" && PATH="${REAL}:${PATH}" GITHUB_STEP_SUMMARY="${TMP}/real-summary.md" bash "$check") > "${TMP}/real.log" 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]] || ! grep -qF -- "projects: 0, repositories: 0" "${TMP}/real.log"; then
    echo "with the real forsgren a new install's config check after the starter step exits ${rc} and logs '$(paste -sd'|' - < "${TMP}/real.log")' — it must pass on the starter, with projects: 0"
  fi
  got="$(starter_outcome "$script" real "$ref" "$TRUNK")"
  [[ "$got" == "$want" ]] || echo "with the real forsgren the next run's starter step gives '${got}', not '${want}' — an existing starter is kept, no second commit"
}

# judge_render_config <workflow-file>: pin 15, the render step hands render
# the config, so the page can say when no projects are configured.
judge_render_config() {
  local script="${TMP}/render.sh" calls="${TMP}/fg.calls" got want
  step_block "$1" "$RENDER_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${RENDER_STEP}' with a run: | block"
    return 0
  fi
  : > "$calls"
  PATH="${STUB}:${PATH}" FG_CALLS="$calls" RUNNER_TEMP="${TMP}/runner" bash "$script" > /dev/null 2>&1 || true
  got="$(paste -sd, - < "$calls")"
  want="render --out ${TMP}/runner/site --config forsgren.config.yml"
  [[ "$got" == "$want" ]] || echo "the render step runs 'forsgren ${got}', not 'forsgren ${want}' — render needs the config to say when no projects are configured"
}

# judge_permissions <workflow-file>: pin 16, the job grants itself
# contents: write, which the starter push needs.
judge_permissions() {
  if ! grep -qE '^      contents:[[:space:]]+write([[:space:]]|$)' "$1"; then
    echo "the job does not grant itself 'contents: write' — the starter commit cannot be pushed to the caller's repository's branch the run is on"
  fi
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

# judge_config_commands <workflow-file>: pin 10, check-config's message
# never runs as a workflow command.
judge_config_commands() {
  local script="${TMP}/config.sh" refusal live first second
  step_block "$1" "$CHECK_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  refusal="check-config: forsgren.config.yml: line 4: unknown key"$'\n'"::warning::injected"$'\n'"  ::add-mask::secret"
  config_outcome "$script" "$refusal" > /dev/null
  live="$(live_commands "${TMP}/config.log")"
  if [[ -n "$live" ]]; then
    echo "for a refusal with workflow commands in it the config step leaves them live in the log ($(paste -sd'|' - <<< "$live")) — a line of check-config's message that starts with :: must not run as a workflow command"
  fi
  if ! grep -qF -- "::warning::injected" "${TMP}/config.log"; then
    echo "for a refusal with workflow commands in it the config step does not show check-config's message in the log"
  fi
  first="$(stop_token "${TMP}/config.log")"
  config_outcome "$script" "$refusal" > /dev/null
  second="$(stop_token "${TMP}/config.log")"
  if [[ -n "$first" && "$first" == "$second" ]]; then
    echo "the config step stops workflow commands with the same token on every run (${first}) — a config that knows it can turn them back on"
  fi
}

# judge_config_e2e <workflow-file>: pin 11, the config step with the real
# forsgren.
judge_config_e2e() {
  local script="${TMP}/config-e2e.sh" rc live ok
  step_block "$1" "$CHECK_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  rc="$(real_config_step "$script" -)"
  real_refusal "no forsgren.config.yml" "$rc" "check-config: forsgren.config.yml: cannot read the config file"
  rc="$(real_config_step "$script" "$INVALID_CONFIG")"
  real_refusal "an invalid forsgren.config.yml" "$rc" \
    'check-config: forsgren.config.yml: project "Acme": repository "acme/app": invalid deployment "releases"'
  rc="$(real_config_step "$script" "$VALID_CONFIG")"
  ok="OK: forsgren.config.yml is a valid forsgren config (version 1): projects: 1, repositories: 1"
  if [[ "$rc" -ne 0 ]] || ! grep -qF -- "$ok" "${TMP}/real.log" || [[ -s "${TMP}/real-summary.md" ]]; then
    echo "with the real forsgren and a valid forsgren.config.yml the config step exits ${rc}, logs '$(paste -sd'|' - < "${TMP}/real.log")' and summarises '$(paste -sd'|' - < "${TMP}/real-summary.md")' — it must pass with '${ok}' and nothing in the summary"
  fi
  rc="$(real_config_step "$script" "$INJECTING_CONFIG")"
  live="$(live_commands "${TMP}/real.log")"
  if [[ "$rc" -ne 1 || -n "$live" ]]; then
    echo "with the real forsgren and an unknown key that carries a line break and ::warning:: the config step exits ${rc} and leaves live in the log: $(paste -sd'|' - <<< "${live:-nothing}") — it must fail with no workflow command live"
  fi
}

# judge_order <workflow-file>: pin 9.
judge_order() {
  local install checkout init check render
  install="$(line_of "$1" "- name: ${INSTALL_STEP}")"
  checkout="$(line_of "$1" "- name: ${CHECKOUT_STEP}")"
  init="$(line_of "$1" "- name: ${INIT_STEP}")"
  check="$(line_of "$1" "- name: ${CHECK_STEP}")"
  render="$(line_of "$1" "- name: ${RENDER_STEP}")"
  if later "$init" "$check"; then
    echo "writes the starter (line ${init}) after the config check (line ${check}) — a new install would fail the check before it has a file"
  fi
  if later "$checkout" "$init"; then
    echo "writes the starter (line ${init}) before checking out the caller's repository (line ${checkout}) — there is no checkout to write it into"
  fi
  if later "$install" "$init"; then
    echo "writes the starter (line ${init}) before installing forsgren (line ${install}) — init-config is not on PATH yet"
  fi
  if later "$check" "$render"; then
    echo "checks the config (line ${check}) after it renders (line ${render}) — a bad config must stop the job before render"
  fi
  if later "$checkout" "$check"; then
    echo "checks out the caller's repository (line ${checkout}) after the config check (line ${check}) — the file is not there yet"
  fi
  if later "$install" "$check"; then
    echo "installs forsgren (line ${install}) after the config check (line ${check}) — check-config is not on PATH yet"
  fi
}

# judge_trigger <workflow-file>: pins 1 and 2, workflow_call alone and no
# inputs.
judge_trigger() {
  local events keys
  events="$(on_events "$1")"
  if [[ "$events" != "workflow_call" ]]; then
    echo "triggers on [$(printf '%s' "$events" | paste -sd, -)], not on workflow_call alone — forsgren's own repository must never run it, and no pull request may"
  fi
  keys="$(call_keys "$1")"
  if [[ -n "$keys" ]]; then
    echo "workflow_call declares [$(printf '%s' "$keys" | paste -sd, -)] — the caller's uses: line is the only version source, so it takes no input"
  fi
}

# judge_expressions <workflow-file>: pin 3, no ${{ }} inside a run: block.
judge_expressions() {
  local runs
  runs="$(run_blocks "$1")"
  if grep -qF "$EXPR_OPEN" <<< "$runs"; then
    echo "expands a \${{ }} expression inside run: (line $(grep -F "$EXPR_OPEN" <<< "$runs" | head -1 | cut -d: -f1)) — values reach the shell through env: only (template injection)"
  fi
}

# judge_install_env <workflow-file>: pin 4, the install step's env:.
judge_install_env() {
  local env
  env="$(step_block "$1" "$INSTALL_STEP" env)"
  if ! grep -qxE "FORSGREN_SHA:[[:space:]]*\\$\\{\\{ job\\.workflow_sha \\}\\}" <<< "$env"; then
    echo "the install step's FORSGREN_SHA is not \${{ job.workflow_sha }} — only the job context gives a called workflow its own commit (github.* is the caller's)"
  fi
  if ! grep -qxE "FORSGREN_REPOSITORY:[[:space:]]*\\$\\{\\{ job\\.workflow_repository \\}\\}" <<< "$env"; then
    echo "the install step's FORSGREN_REPOSITORY is not \${{ job.workflow_repository }} — the repository must come from the same context as the commit"
  fi
}

# judge_install_run <workflow-file>: pin 5, the executed install step.
judge_install_run() {
  local script="${TMP}/install.sh" got want v
  step_block "$1" "$INSTALL_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${INSTALL_STEP}' with a run: | block — nothing installs forsgren from this workflow's own commit"
    return 0
  fi
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
}

# judge_setup_go <workflow-file>: pin 6, setup-go on go.mod's Go, before the
# install step.
judge_setup_go() {
  local install_line setup_line go_version toolchain
  install_line="$(line_of "$1" "- name: ${INSTALL_STEP}")"
  setup_line="$(grep -nE 'uses:[[:space:]]*actions/setup-go@' "$1" | head -1 | cut -d: -f1)"
  if later "$setup_line" "$install_line"; then
    echo "sets up Go (line ${setup_line}) after the install step (line ${install_line}) — go install would run on the runner's own Go"
  fi
  go_version="$(awk '
    /uses:[[:space:]]*actions\/setup-go@/ { insg=1; next }
    insg && /^      - / { insg=0 }
    insg && /^[[:space:]]+go-version:/ { v=$0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/["\047]/, "", v); print v; exit }
  ' "$1")"
  toolchain="$(./Scripts/go_toolchain.sh)"
  if [[ "$go_version" != "${toolchain#go}" ]]; then
    echo "actions/setup-go installs Go '${go_version:-none}', not ${toolchain#go} from go.mod's toolchain line — the release would be built with another Go than sfl, FBP.sh and Quality use"
  fi
}

# judge <workflow-file>: one problem per line, pin by pin; silent when every
# pin holds.
judge() {
  judge_trigger "$1"
  judge_expressions "$1"
  judge_install_env "$1"
  judge_install_run "$1"
  judge_setup_go "$1"
  judge_checkout "$1"
  judge_permissions "$1"
  judge_starter_step "$1"
  judge_starter_token "$1"
  judge_starter_e2e "$1"
  judge_config_step "$1"
  judge_config_commands "$1"
  judge_config_e2e "$1"
  judge_render_config "$1"
  judge_order "$1"
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
  echo "  ok: ${WF} is a workflow_call with no inputs that installs forsgren from its own job.workflow_repository at its own job.workflow_sha, both checked before go install, through env: only, built with go.mod's Go, after the caller's pinned checkout, a starter step that commits a new install's one file with a token that is never stored or shown, a contents: write job, and a config check that fails the job with check-config's message before render, with the real forsgren too, and never runs that message as a workflow command"
fi

# --- Self-proof: each pin, on a mutant of the real metrics.yml, names its reason.
# judged <case> <reason> <mutant>: the judge names <reason> for the mutant.
judged() {
  local got
  got="$(judge "$3")"
  if grep -qF -- "$2" <<< "$got"; then
    echo "  ok: $1 is rejected"
  else
    fail "the mutant with $1 was ACCEPTED (verdict: ${got:-none}) — this pin cannot detect the defect it exists for"
  fi
}

# proves <case> <reason> <sed-expression>
proves() {
  local mutant="${TMP}/mutants/$1.yml"
  selftest_mutant "$WF" "$mutant" "$3" || return 0
  judged "$1" "$2" "$mutant"
}

# proves_moved <case> <reason> <step name> [<before step name>]: as proves,
# on the real metrics.yml with that step moved before the other, or removed.
proves_moved() {
  local mutant="${TMP}/mutants/$1.yml"
  mkdir -p "${TMP}/mutants"
  move_step "$WF" "$3" "${4:-}" > "$mutant"
  if cmp -s "$WF" "$mutant"; then
    fail "moving the step '$3' changed nothing in ${WF}: the proof would be vacuous"
    return 0
  fi
  judged "$1" "$2" "$mutant"
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
proves "workflow commands left on" "leaves them live in the log (line " \
  '/::stop-commands::/d'
proves "commands never resumed" "never ended" \
  '/echo "::.{token}::"/d'
proves "the same token on every run" "the same token on every run" \
  's/^\( *\)token=.*$/\1token=forsgren/'
proves "the real forsgren on another file" "with the real forsgren and no forsgren.config.yml" \
  's/--config forsgren\.config\.yml/--config config.yml/'
proves "a real refusal without its cross mark" "with the real forsgren and an invalid forsgren.config.yml" \
  's/"❌ /"/'
proves "a real valid config refused" "with the real forsgren and a valid forsgren.config.yml" \
  's/ -ne 0 \]\]; then/ -ne 99 ]]; then/'

# The starter step (forsgren#12, step 3).
proves "no starter step" "has no step '${INIT_STEP}'" \
  "s/- name: ${INIT_STEP}\$/- name: Write something else/"
proves "init-config on another file" "the starter step runs 'forsgren init-config --config config.yml'" \
  's/forsgren init-config --config forsgren\.config\.yml/forsgren init-config --config config.yml/'
proves "a starter committed even when kept" "for a kept forsgren.config.yml the starter step gives" \
  "s/\\[\\[ \"${D}result\" != \"created forsgren.config.yml\" \\]\\]/false/"
proves "no starter commit" "for a created forsgren.config.yml on its branch the starter step gives 'exit=0 commits=1'" \
  '/git -c user.name=/,/commit --quiet/d'
proves "the whole checkout committed" "the starter commit holds [forsgren.config.yml,other.txt,staged.txt]" \
  "s/git add -- forsgren.config.yml/git add -A/; s/'forsgren: add a starter forsgren.config.yml' -- forsgren.config.yml/'forsgren: add a starter forsgren.config.yml'/"
proves "another commit author" "the starter commit's author is 'someone <" \
  "s/user\\.name='github-actions\\[bot\\]'/user.name='someone'/"
proves "another author address" "the starter commit's author is 'github-actions[bot] <12345+github-actions" \
  's/41898282+github-actions/12345+github-actions/'
proves "another commit message" "the starter commit's message is 'forsgren: add a config'" \
  "s/add a starter forsgren\\.config\\.yml'/add a config'/"
proves "no push" "for a created forsgren.config.yml on its branch the starter step gives 'exit=0 commits=1'" \
  '/git push --quiet origin/d'
proves "a push to a fixed branch instead of the run's" "for a created forsgren.config.yml on its branch the starter step gives 'exit=0 commits=1'" \
  "s|\"HEAD:${D}{GITHUB_REF}\"|\"HEAD:refs/heads/main\"|"
proves "a starter pushed from a tag" "for a ref that is not a branch (refs/tags/v1)" \
  '/- name: Write the starter/,/git add --/ s/exit 1/exit 0/'
proves "the branch guard before the kept check" "with no branch ref at all" \
  's/^\( *\)exit 0$/\1true/'
proves "the token in an argument" "hands the token to git in an argument" \
  "s|^\\( *\\)git push --quiet origin|\\1git -c \"http.extraheader=AUTHORIZATION: basic ${D}{auth}\" push --quiet origin|"
proves "the token stored in the checkout" "leaves the token on disk in the checkout" \
  "s|^\\( *\\)git push --quiet origin|\\1git config http.extraheader \"AUTHORIZATION: basic ${D}{auth}\"\\n\\1git push --quiet origin|"
proves "the token echoed" "the starter step shows the token in its log" \
  "s|^\\( *\\)git push --quiet origin|\\1echo \"pushing with ${D}{GH_TOKEN}\"\\n\\1git push --quiet origin|"
proves "a push without the header" "the starter step's push carries" \
  's/"AUTHORIZATION: basic /"X-Other: basic /'
proves "a starter that leaves no file" "with the real forsgren a new install's config check after the starter step exits" \
  "s|^\\( *\\)git push --quiet origin.*\$|&\\n\\1rm -f forsgren.config.yml|"
proves "a job that only reads contents" "does not grant itself 'contents: write'" \
  's/^      contents: write /      contents: read /'
proves "render without the config" "the render step runs 'forsgren render --out" \
  's/ --config forsgren\.config\.yml$//'

# Whole steps removed or moved: the config step gone, the config step after
# render (just before "Upload the page"), the install step before setup-go.
proves_moved "a workflow without the config step" "has no step '${CHECK_STEP}'" "$CHECK_STEP"
proves_moved "the config check after render" "after it renders" "$CHECK_STEP" "Upload the page"
proves_moved "the starter after the config check" "writes the starter (line" "$INIT_STEP" "Render the page"
proves_moved "the starter before the checkout" "before checking out the caller's repository" "$INIT_STEP" "$CHECKOUT_STEP"
proves_moved "the install step before setup-go" "after the install step" "$INSTALL_STEP" "Set up Go"

selftest_end "metrics.yml is not the reusable workflow forsgren#4 rules" \
  "metrics.yml runs on workflow_call only, takes no input, installs forsgren from its own job.workflow_repository at its own job.workflow_sha (each checked before go runs, a fork installing itself), passes both through env: only, builds with go.mod's Go after setup-go, writes a new install's starter config with one commit as github-actions[bot] (token in the environment only) and renders with the config, and checks the caller's config before render, with the real forsgren too, its message never run as a workflow command (and each wrong shape is still detected)"
