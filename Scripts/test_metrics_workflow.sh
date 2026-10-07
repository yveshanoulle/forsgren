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
#      forsgren.config.yml --data data/deployments.csv`, so the page can say
#      when no projects are configured and show each project's deployment
#      frequency from the history (forsgren#12, step 7), executed with the
#      stub;
#  16. the workflow has NO permissions block, at the top or on the job, and
#      names no `pull-requests:` permission (forsgren#40): a called workflow
#      that asks for more than its caller grants stops the run before any
#      step, so a block here would break every install whose caller has not
#      been updated; without one the job takes what the caller's job grants;
#  17. workflow_call declares ONE secret, FORSGREN_TOKEN, with required: false
#      (forsgren#12, step 6): a new install's first runs, with the starter's
#      zero projects, start before its owner made a token, and collect itself
#      names a missing token once there are projects (pin 21); pin 2 lets
#      secrets through and still refuses inputs;
#  18. the token reaches the step "Collect deployments" and nothing else: its
#      env: sets `FORSGREN_TOKEN: ${{ secrets.FORSGREN_TOKEN }}`, and that is
#      the only ${{ }} expression in the file that reads secrets (no job or
#      workflow env:, no other step);
#  19. that step, EXECUTED here with a stub forsgren in the installation's
#      checkout, runs exactly `forsgren collect --config forsgren.config.yml
#      --data data/deployments.csv` with FORSGREN_TOKEN in its environment,
#      exits 0 and records collect's exit status as the step output
#      `status`: 0 when collect stored, 1 when it stored the others and then
#      failed, its message still in the log;
#  20. that token is in no argument of forsgren, no file of the checkout, not
#      in the step's log and not in its outputs;
#  21. the same step with the REAL forsgren: the starter configuration and no
#      token record status=0 and write no data/; a configured repository and
#      an empty token (a secret not made yet) record status=1 with collect's
#      message naming FORSGREN_TOKEN;
#  22. the step "Commit the collected deployments", EXECUTED with the real git
#      against a local remote: data/ unchanged commits nothing and exits 0,
#      also on a tag (a non-branch ref is refused only when there is
#      something to commit); a changed data/ (a new history and its commits
#      file, an appended one) is ONE commit of data/ alone, both files of
#      collect in it (forsgren#16: data/commits.csv; another staged file and
#      an untracked one stay out), authored and committed by github-actions[bot], "forsgren:
#      record deployments", pushed to HEAD:${GITHUB_REF}; under a hostile
#      inherited GIT_AUTHOR_*/GIT_COMMITTER_*/GIT_CONFIG_* environment it is
#      still the bot's and unsigned; on a tag it refuses and pushes nothing;
#  23. that push carries the job token as pin 13's does: an Authorization
#      header in the environment, in no argument, file or log;
#  24. when the branch moved since the checkout (another push), the data step
#      fails with an ::error naming that cause, and neither rebases nor
#      forces: the other commit stays the remote's tip;
#  25. the step "Fail the job when collect failed" reads COLLECT_STATUS from
#      ${{ steps.collect.outputs.status }} (the collect step has id: collect)
#      and, EXECUTED, exits 0 for status 0 and 1 with an ::error for any other
#      status or none; and the three steps in a row, collect failing after
#      storing, commit and push the stored data/ and then fail the job;
#  26. the job's concurrency group is keyed on ${{ github.repository }}, the
#      caller's repository, with cancel-in-progress: false, so a scheduled
#      run and a manual one queue instead of racing on the data/ push;
#  27. the collect step, EXECUTED with the stub forsgren printing lines that
#      start with `::warning::` (stdout) and `  ::add-mask::` (stderr) and
#      failing, leaves no workflow command live in the log: collect's output,
#      both streams, is shown between `::stop-commands::<token>` and
#      `::<token>::` under a token that differs from run to run, as pin 10
#      has it for check-config, and the step still records status=1
#      (forsgren#12, step 8);
#  28. the same with the REAL forsgren: collect's message naming a missing
#      FORSGREN_TOKEN is logged inside that pair, and a configuration whose
#      unknown key carries a line break and `::warning::` records status=1
#      with no workflow command live, as pin 11 has it for check-config;
#  29. the step "Look up the latest forsgren release" (forsgren#40) hands
#      forsgren the job's token as GITHUB_TOKEN (`${{ github.token }}`, never
#      a secret), and, EXECUTED with the stub, outputs `latest=<version>` for
#      a plain version, `latest=` for a lookup that exits non-zero or prints
#      anything else (a failed lookup is never an error, and a line break or
#      workflow command in the output is never an output);
#  30. the render step takes that output through env: only (`LATEST:
#      ${{ steps.latest.outputs.latest }}`) and, EXECUTED with the stub,
#      passes `--latest <version>` to render when it is set and nothing
#      when it is empty;
#  31. the step "Look up the waiting Dependabot pull request" (forsgren#40,
#      option 1) hands forsgren the job's token as GITHUB_TOKEN, and,
#      EXECUTED with the stub, outputs `waiting=<number>` for a plain
#      number, `waiting=` for a failed lookup, a non-number or an answer with
#      a second line, and never asks when there is no latest release;
#  32. the render step takes that output through env: only (`WAITING:
#      ${{ steps.waiting.outputs.waiting }}`) and, EXECUTED with the stub,
#      passes `--waiting-pr <number>` when it is set;
#  33. the step "Write the run summary" (forsgren#40) takes LATEST, WAITING,
#      PR_CHECK (the waiting step's `check` output: ok, no-access,
#      rate-limited, failed or skipped) and NEEDS_CHECK (the needs step's
#      `check` output, forsgren#73) through env: only and, EXECUTED with the
#      stub, appends `forsgren run-summary --latest ... --waiting-pr ...
#      --pr-check ... --needs-check ... --repository $GITHUB_REPOSITORY`'s markdown to
#      $GITHUB_STEP_SUMMARY, and never fails the run: a run-summary that
#      fails appends nothing and the step exits 0; and pin 31 adds that the
#      waiting step outputs `check=` from the status file its lookup writes
#      (`--status`), skipped without a latest release;
#  34. the step "Check what this forsgren version needs" (forsgren#73) hands
#      forsgren the job's token as GITHUB_TOKEN, runs from the checkout root
#      (no working-directory) and, EXECUTED with the stub, runs exactly
#      `forsgren check-needs --config forsgren.config.yml --repository
#      $GITHUB_REPOSITORY --status ${RUNNER_TEMP}/needs-status` (the
#      repository through the environment, as pin 3 demands: no expression in
#      a run: block), next to the waiting step's status file, and never
#      fails the run, whatever check-needs does; pin 9 puts it after the
#      checkout and the config check and before "Write the run summary",
#      which reads its status; and pin 16 adds that the documented caller
#      permissions name `issues: write`, with its reason: the setup issue;
#  and pin 9 also orders the steps: install, checkout, starter, config check,
#  collect, data commit, render, and the fail step after "Publish to GitHub
#  Pages", so what was stored is committed and published before the job
#  fails.
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
# forsgren, so it is tested where it lives, too. The collect, data and fail
# steps (forsgren#12, step 6) stay inline for the same reason, and pins 19 to
# 25, 27 and 28 execute their blocks the same way.
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
# naming its own reason, so a broken matcher cannot pass in silence. Each
# mutant is judged by the pin it is aimed at alone: judging each by every
# pin, which executes real steps, would multiply this self-test's run time.
#
# Usage: Scripts/test_metrics_workflow.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# The cases own their environment for the starter step: an identity or config
# inherited from whoever runs this (fbp_agent_friend.sh exports both) never
# reaches one. The hostile case sets its own, inside the subshell that runs it.
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE GIT_CONFIG_PARAMETERS
while IFS= read -r inherited; do
  unset "$inherited"
done < <(compgen -v | grep -E '^GIT_CONFIG_(COUNT|KEY_[0-9]+|VALUE_[0-9]+)$' || true)

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
selftest_begin "the metrics workflow pin"

WF=".github/workflows/metrics.yml"
INSTALL_STEP="Install forsgren from this workflow's own commit"
CHECKOUT_STEP="Check out the caller's repository"
CHECK_STEP="Check the caller's forsgren configuration"
RENDER_STEP="Render the page"
LATEST_STEP="Look up the latest forsgren release"
WAITING_STEP="Look up the waiting Dependabot pull request"
SUMMARY_STEP="Write the run summary"
NEEDS_STEP="Check what this forsgren version needs"
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
# The collect, data and fail steps (forsgren#12, step 6).
COLLECT_STEP="Collect deployments"
DATA_STEP="Commit the collected deployments"
FAIL_STEP="Fail the job when collect failed"
PUBLISH_STEP="Publish to GitHub Pages"
COLLECT_CMD="collect --config forsgren.config.yml --data data/deployments.csv"
DATA_SUBJECT="forsgren: record deployments"
# The one line that hands the installation's token to the collect step.
TOKEN_ENV="FORSGREN_TOKEN: ${EXPR_OPEN} secrets.FORSGREN_TOKEN }}"
# A made-up FORSGREN_TOKEN that no argument, file, log or output may show.
COLLECT_SECRET="c0llectToken-acme-4d7"
# What the data step's ::error says when the branch moved under it.
MOVED="moved since this run checked it out"
# v0.0.1's commit: a real one, so the case reads as what a run sees.
SHA="1997c4ff09aecd32c30fbdd7eef72485f146e865"
UPSTREAM="yveshanoulle/forsgren"
# Made-up configs for pin 11, the config step with the real forsgren.
VALID_CONFIG=$'version: 1\nprojects:\n  - name: Acme\n    repositories:\n      - name: acme/app\n'
INVALID_CONFIG="${VALID_CONFIG}"$'        deployment: releases\n'
INJECTING_CONFIG=$'version: 1\nprojects:\n  - name: Acme\n    "x\\n::warning::injected": 1\n    repositories:\n      - name: acme/app\n'

# call_keys <file>: the keys under `on: workflow_call:`, one per line.
call_keys() {
  awk '
    /^  workflow_call:/ { incall=1; next }
    incall && /^ {0,2}[^[:space:]#]/ { incall=0 }
    incall && /^    [A-Za-z_-]+:/ { s=$0; sub(/^    /, "", s); sub(/:.*$/, "", s); print s }
  ' "$1"
}

# secret_names <file>: the secrets `on: workflow_call: secrets:` declares,
# one per line.
secret_names() {
  awk '
    /^  workflow_call:/ { incall=1; next }
    incall && /^ {0,2}[^[:space:]#]/ { incall=0 }
    incall && /^    secrets:/ { insec=1; next }
    incall && /^    [^[:space:]#]/ { insec=0 }
    incall && insec && /^      [A-Za-z_][A-Za-z0-9_]*:/ { s=$0; sub(/^ +/, "", s); sub(/:.*$/, "", s); print s }
  ' "$1"
}

# secret_required <file>: the `required:` value of the declared secret
# FORSGREN_TOKEN; nothing when it has none.
secret_required() {
  awk '
    /^  workflow_call:/ { incall=1; next }
    incall && /^ {0,2}[^[:space:]#]/ { incall=0 }
    incall && /^      FORSGREN_TOKEN:[[:space:]]*$/ { intok=1; next }
    intok && /^ {0,6}[^[:space:]#]/ { intok=0 }
    intok && /^        required:/ { v=$0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]*(#.*)?$/, "", v); print v }
  ' "$1"
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
# says `kept <path>`; collect writes to FG_TOKEN_SEEN whether FORSGREN_TOKEN
# is STUB_TOKEN (yes or no, never the token), and with STUB_COLLECT store
# appends a line to data/deployments.csv, with store-fail does that and then
# fails as collect does, with inject prints workflow commands on stdout and
# stderr and fails, with none (the default) stores nothing; otherwise,
# with STUB_REFUSAL set, it says that on stderr and exits 1, else it says OK.
# waiting-pull-request writes STUB_PRSTATUS (printf %b) to the file its last
# argument names, when set, then prints STUB_WAITING and exits with
# STUB_WAITING_RC; check-needs writes STUB_NEEDSSTATUS the same way and exits
# with STUB_NEEDS_RC; run-summary prints STUB_SUMMARY and exits with
# STUB_SUMMARY_RC.
# latest-release prints STUB_LATEST (printf %b: \n is a line break) and exits
# with STUB_LATEST_RC (0 by default).
cat > "${STUB}/forsgren" <<'STUBFORSGREN'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FG_CALLS"
if [[ "${1:-}" == collect ]]; then
  if [[ -n "${FORSGREN_TOKEN:-}" && "${FORSGREN_TOKEN}" == "${STUB_TOKEN:-}" ]]; then
    echo yes > "${FG_TOKEN_SEEN:-/dev/null}"
  else
    echo no > "${FG_TOKEN_SEEN:-/dev/null}"
  fi
  if [[ "${STUB_COLLECT:-none}" == inject ]]; then
    echo "::warning::injected-by-collect"
    echo "  ::add-mask::collect-mask" >&2
    echo "collect: 1 of 1 repositories failed" >&2
    exit 1
  fi
  if [[ "${STUB_COLLECT:-none}" != none ]]; then
    mkdir -p data
    printf '# forsgren history v1\nacme stored\n' >> data/deployments.csv
    echo "acme/app: 1 new, 0 skipped (not final)"
  fi
  if [[ "${STUB_COLLECT:-none}" == store-fail ]]; then
    echo "collect: acme/web: check FORSGREN_TOKEN's access to acme/web" >&2
    echo "collect: 1 of 2 repositories failed" >&2
    exit 1
  fi
  exit 0
fi
if [[ "${1:-}" == init-config ]]; then
  if [[ "${STUB_INIT:-kept}" == created ]]; then
    printf 'version: 1\nprojects: []\n' > "$3"
    echo "created $3"
  else
    echo "kept $3"
  fi
  exit 0
fi
if [[ "${1:-}" == latest-release ]]; then
  printf '%b' "${STUB_LATEST:-}"
  exit "${STUB_LATEST_RC:-0}"
fi
if [[ "${1:-}" == run-summary ]]; then
  printf '%b' "${STUB_SUMMARY:-}"
  exit "${STUB_SUMMARY_RC:-0}"
fi
if [[ "${1:-}" == check-needs ]]; then
  if [[ -n "${STUB_NEEDSSTATUS:-}" && "$#" -ge 2 && "${*:$#-1:1}" == --status ]]; then
    printf '%b' "$STUB_NEEDSSTATUS" > "${@:$#}"
  fi
  exit "${STUB_NEEDS_RC:-0}"
fi
if [[ "${1:-}" == waiting-pull-request ]]; then
  if [[ -n "${STUB_PRSTATUS:-}" && "$#" -ge 2 && "${*:$#-1:1}" == --status ]]; then
    printf '%b' "$STUB_PRSTATUS" > "${@:$#}"
  fi
  printf '%b' "${STUB_WAITING:-}"
  exit "${STUB_WAITING_RC:-0}"
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

# stopped_text <log> <fixed text>: where the first line holding the text is,
# `stopped` inside a ::stop-commands::<token> ... ::<token>:: pair or `live`
# outside one; nothing when no line holds it.
stopped_text() {
  awk -v text="$2" '
    token == "" && /^::stop-commands::./ { token = substr($0, 18); next }
    token != "" && $0 == "::" token "::" { token = ""; next }
    index($0, text) { print (token == "" ? "live" : "stopped"); exit }
  ' "$1"
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
# forsgren.config.yml, as a new install's checkout is. Built with git once,
# then copied from that pristine pair: every pin and every mutant starts
# from many fresh installations, and a copy costs no git process.
new_install() {
  rm -rf "$ORIGIN" "$INSTALL"
  if [[ -d "${TMP}/pristine" ]]; then
    cp -R "${TMP}/pristine/origin.git" "$ORIGIN"
    cp -R "${TMP}/pristine/install" "$INSTALL"
    return 0
  fi
  iso init --bare "$ORIGIN"
  iso -C "$ORIGIN" symbolic-ref HEAD "refs/heads/${TRUNK}"
  iso init "$INSTALL"
  iso -C "$INSTALL" symbolic-ref HEAD "refs/heads/${TRUNK}"
  printf 'acme app\n' > "${INSTALL}/README.md"
  iso -C "$INSTALL" add README.md
  iso -C "$INSTALL" -c user.name=Setup -c user.email=setup@example.com commit -m "Initial commit"
  iso -C "$INSTALL" remote add origin "$ORIGIN"
  iso -C "$INSTALL" push origin "$TRUNK"
  mkdir -p "${TMP}/pristine"
  cp -R "$ORIGIN" "$INSTALL" "${TMP}/pristine/"
}

# git_step_outcome <script> <created|kept|real> <ref> <branch> [hostile]:
# runs a step that commits and pushes (the starter step, the data step) in
# the installation's checkout, GITHUB_REF being <ref>, with
# the stub forsgren saying created or kept, or with the real one, and the
# token SECRET; as one line: exit=<rc> commits=<commits on the remote's
# <branch>, 0 when it has none>. The
# step's log is in ${TMP}/step.log, forsgren's calls in ${TMP}/fg.calls.
git_step_outcome() {
  local rc=0 commits path="${STUB}:${PATH}"
  [[ "$2" == real ]] && path="${REAL}:${path}"
  : > "${TMP}/fg.calls"
  : > "$GIT_ARGV_LOG"
  : > "$GIT_ENV_LOG"
  (
    cd "$INSTALL"
    if [[ "${5:-}" == hostile ]]; then
      export GIT_AUTHOR_NAME="Outer Author" GIT_AUTHOR_EMAIL="outer-author@example.com"
      export GIT_COMMITTER_NAME="Outer Committer" GIT_COMMITTER_EMAIL="outer-committer@example.com"
      export GIT_CONFIG_COUNT=3
      export GIT_CONFIG_KEY_0="commit.gpgsign" GIT_CONFIG_VALUE_0="true"
      export GIT_CONFIG_KEY_1="gpg.format" GIT_CONFIG_VALUE_1="ssh"
      export GIT_CONFIG_KEY_2="user.signingkey" GIT_CONFIG_VALUE_2="/nonexistent"
    fi
    PATH="$path" FG_CALLS="${TMP}/fg.calls" STUB_INIT="$2" GH_TOKEN="$SECRET" \
      GITHUB_REF="$3" GITHUB_SERVER_URL="https://github.com" \
      GIT_ARGV_LOG="$GIT_ARGV_LOG" GIT_ENV_LOG="$GIT_ENV_LOG" REAL_GIT="$REAL_GIT" \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 bash "$1"
  ) > "${TMP}/step.log" 2>&1 || rc=$?
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
  got="$(git_step_outcome "$script" kept "$ref" "$TRUNK")"
  want="exit=0 commits=1"
  [[ "$got" == "$want" ]] || echo "for a kept forsgren.config.yml the starter step gives '${got}', not '${want}' — an existing file is never committed or pushed"
  got="$(git_step_outcome "$script" kept "" "$TRUNK")"
  [[ "$got" == "$want" ]] || echo "for a kept forsgren.config.yml with no branch ref at all the starter step gives '${got}', not '${want}' — a kept file exits 0 before any branch logic, or every daily run would fail"
  calls="$(paste -sd, - < "${TMP}/fg.calls")"
  [[ "$calls" == "$INIT_CMD" ]] || echo "the starter step runs 'forsgren ${calls}', not 'forsgren ${INIT_CMD}'"
  new_install
  printf 'untracked\n' > "${INSTALL}/other.txt"
  printf 'staged\n' > "${INSTALL}/staged.txt"
  iso -C "$INSTALL" add staged.txt
  got="$(git_step_outcome "$script" created "$ref" "$TRUNK")"
  want="exit=0 commits=2"
  if [[ "$got" != "$want" ]]; then
    echo "for a created forsgren.config.yml on its branch the starter step gives '${got}', not '${want}' — the starter is committed and pushed there"
  else
    bot_findings "for a created forsgren.config.yml" "starter commit" "$TRUNK"
    who="$(iso_out -C "$ORIGIN" log -1 --format='%B' "$TRUNK")"
    [[ "$who" == "$STARTER_SUBJECT" ]] || echo "the starter commit's message is '${who}', not '${STARTER_SUBJECT}'"
    files="$(iso_out -C "$ORIGIN" diff-tree --no-commit-id --name-only -r "$TRUNK" | paste -sd, -)"
    [[ "$files" == "forsgren.config.yml" ]] || echo "the starter commit holds [${files}], not forsgren.config.yml alone — one file only, never the rest of the checkout"
  fi
  new_install
  got="$(git_step_outcome "$script" created "$ref" "$TRUNK" hostile)"
  want="exit=0 commits=2"
  if [[ "$got" != "$want" ]]; then
    echo "with an outer identity and a signing config inherited from the environment the starter step gives '${got}', not '${want}' — git's environment outranks git -c, so the commit must set its own identity and config in the environment"
  else
    bot_findings "with an inherited outer identity" "starter commit" "$TRUNK"
  fi
  new_install
  iso -C "$INSTALL" checkout -b feature
  got="$(git_step_outcome "$script" created "refs/heads/feature" feature)"
  want="exit=0 commits=2"
  [[ "$got" == "$want" ]] || echo "for a created forsgren.config.yml on a manual run on feature the starter step gives '${got}', not '${want}' — the starter goes to the branch the run is on"
  got="$(iso_out -C "$ORIGIN" rev-list --count "$TRUNK")"
  [[ "$got" == 1 ]] || echo "a run on feature moved ${TRUNK} to ${got} commits — it must push to the run's own branch only"
  new_install
  got="$(git_step_outcome "$script" created "refs/tags/v1" "$TRUNK")"
  want="exit=1 commits=1"
  [[ "$got" == "$want" ]] || echo "for a ref that is not a branch (refs/tags/v1) the starter step gives '${got}', not '${want}' — it must refuse, there is no branch to commit to"
}

# judge_starter_token <workflow-file>: pin 13, the push carries the token and
# never stores or shows it.
judge_starter_token() {
  local script="${TMP}/starter.sh"
  step_block "$1" "$INIT_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  new_install
  git_step_outcome "$script" created "refs/heads/${TRUNK}" "$TRUNK" > /dev/null
  push_token_findings "the starter step"
}

# push_token_findings <step label>: after a git_step_outcome that pushed,
# one line per place the job token SECRET showed up (a git argument, a file
# of the checkout, the step's log), and when the push did not carry it as
# an Authorization header in git's environment.
push_token_findings() {
  local b64 got want
  b64="$(printf 'x-access-token:%s' "$SECRET" | base64 | tr -d '\n')"
  if grep -qF -- "$SECRET" "$GIT_ARGV_LOG" || grep -qF -- "$b64" "$GIT_ARGV_LOG"; then
    echo "$1 hands the token to git in an argument — ps shows arguments and git's messages quote them; it goes through the environment only"
  fi
  if grep -rqF -- "$SECRET" "$INSTALL" || grep -rqF -- "$b64" "$INSTALL"; then
    echo "$1 leaves the token on disk in the checkout — with persist-credentials: false nothing may keep it"
  fi
  if grep -qF -- "$SECRET" "${TMP}/step.log" || grep -qF -- "$b64" "${TMP}/step.log"; then
    echo "$1 shows the token in its log"
  fi
  want="http.https://github.com/.extraheader=AUTHORIZATION: basic ${b64}"
  got="$(awk -F'\t' '$1 ~ /^git push / { print $2 }' "$GIT_ENV_LOG")"
  if [[ "$got" != "$want" ]]; then
    echo "$1's push carries '${got:-nothing}' in the environment, not '${want}' — without it the push has no credential"
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
  got="$(git_step_outcome "$script" real "$ref" "$TRUNK")"
  want="exit=0 commits=2"
  [[ "$got" == "$want" ]] || echo "with the real forsgren a new install's starter step gives '${got}', not '${want}'"
  got="$(iso_out -C "$ORIGIN" show "${TRUNK}:forsgren.config.yml")"
  [[ "$got" == "$(cat internal/config/starter.yml)" ]] || echo "with the real forsgren the committed forsgren.config.yml is not internal/config/starter.yml"
  (cd "$INSTALL" && PATH="${REAL}:${PATH}" GITHUB_STEP_SUMMARY="${TMP}/real-summary.md" bash "$check") > "${TMP}/real.log" 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]] || ! grep -qF -- "projects: 0, repositories: 0" "${TMP}/real.log"; then
    echo "with the real forsgren a new install's config check after the starter step exits ${rc} and logs '$(paste -sd'|' - < "${TMP}/real.log")' — it must pass on the starter, with projects: 0"
  fi
  got="$(git_step_outcome "$script" real "$ref" "$TRUNK")"
  [[ "$got" == "$want" ]] || echo "with the real forsgren the next run's starter step gives '${got}', not '${want}' — an existing starter is kept, no second commit"
}

# render_calls <script> [<NAME=value> ...]: the forsgren calls, joined by
# commas, of the render step's script run with the stub, RUNNER_TEMP and the
# assignments in its environment.
render_calls() {
  local calls="${TMP}/fg.calls"
  : > "$calls"
  PATH="${STUB}:${PATH}" FG_CALLS="$calls" RUNNER_TEMP="${TMP}/runner" env "${@:2}" bash "$1" > /dev/null 2>&1 || true
  paste -sd, - < "$calls"
}

# judge_render_config <workflow-file>: pin 15, the render step hands render
# the config, so the page can say when no projects are configured, and the
# history, so it shows each project's deployment frequency.
judge_render_config() {
  local script="${TMP}/render.sh" got want
  step_block "$1" "$RENDER_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${RENDER_STEP}' with a run: | block"
    return 0
  fi
  got="$(render_calls "$script")"
  want="render --out ${TMP}/runner/site --config forsgren.config.yml --data data/deployments.csv"
  [[ "$got" == "$want" ]] || echo "the render step runs 'forsgren ${got}', not 'forsgren ${want}' — render needs the config to say when no projects are configured, and the history to show the deployment frequency"
}

# lookup_outcome <script> <stub output> <stub exit status>: what the lookup
# step does with a stub latest-release that prints that and exits with that:
# `exit=<rc> output=<its GITHUB_OUTPUT lines, joined by |> calls=<forsgren
# calls>`.
lookup_outcome() {
  local rc=0 out="${TMP}/lookup.out" calls="${TMP}/fg.calls"
  : > "$out"
  : > "$calls"
  PATH="${STUB}:${PATH}" FG_CALLS="$calls" GITHUB_OUTPUT="$out" STUB_LATEST="$2" STUB_LATEST_RC="$3" \
    bash "$1" > /dev/null 2>&1 || rc=$?
  echo "exit=${rc} output=$(paste -sd'|' - < "$out") calls=$(paste -sd, - < "$calls")"
}

# judge_job_token <workflow-file> <step name> <who> <why>: the step's env:
# hands forsgren the job's token as GITHUB_TOKEN, and never the caller's
# FORSGREN_TOKEN; <who> names the step in a finding, <why> is the reason the
# job's token is needed.
judge_job_token() {
  local env
  env="$(step_block "$1" "$2" env)"
  if ! grep -qxF -- "GITHUB_TOKEN: ${EXPR_OPEN} github.token }}" <<< "$env"; then
    echo "${3}'s env: does not set GITHUB_TOKEN to the job's token — ${4}"
  fi
  if grep -qF -- "FORSGREN_TOKEN" <<< "$env"; then
    echo "${3}'s env: hands FORSGREN_TOKEN over — it reaches the collect step only"
  fi
}

# judge_latest_lookup <workflow-file>: pin 29, the lookup step.
judge_latest_lookup() {
  local script="${TMP}/lookup.sh" got want
  judge_job_token "$1" "$LATEST_STEP" "the lookup step" \
    "unauthorized calls from shared runner addresses hit GitHub's limit"
  step_block "$1" "$LATEST_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${LATEST_STEP}' with a run: | block"
    return 0
  fi
  got="$(lookup_outcome "$script" "0.0.10\n" 0)"
  want="exit=0 output=latest=0.0.10 calls=latest-release"
  [[ "$got" == "$want" ]] || echo "the lookup step gives '${got}', not '${want}' — a plain version is the step's output"
  got="$(lookup_outcome "$script" "" 1)"
  want="exit=0 output=latest= calls=latest-release"
  [[ "$got" == "$want" ]] || echo "for a lookup that fails the lookup step gives '${got}', not '${want}' — a failed lookup is not an error and the page says nothing of releases"
  got="$(lookup_outcome "$script" "nightly" 0)"
  want="exit=0 output=latest= calls=latest-release"
  [[ "$got" == "$want" ]] || echo "for an answer that is not a version the lookup step gives '${got}', not '${want}' — only a plain version becomes an output"
  got="$(lookup_outcome "$script" "0.0.10\nevil=1\n" 0)"
  want="exit=0 output=latest= calls=latest-release"
  [[ "$got" == "$want" ]] || echo "for an answer with a second line the lookup step gives '${got}', not '${want}' — a line break must never add an output"
}

# waiting_outcome <script> <LATEST> <stub output> <stub exit status> <stub
# status file content>: as lookup_outcome, for the waiting step, with LATEST
# in its environment; the runner's temp directory shows as RUNNER_TEMP.
waiting_outcome() {
  local rc=0 out="${TMP}/waiting.out" calls="${TMP}/fg.calls"
  : > "$out"
  : > "$calls"
  rm -rf "${TMP}/runner"
  mkdir -p "${TMP}/runner"
  PATH="${STUB}:${PATH}" FG_CALLS="$calls" GITHUB_OUTPUT="$out" LATEST="$2" STUB_WAITING="$3" STUB_WAITING_RC="$4" \
    STUB_PRSTATUS="$5" RUNNER_TEMP="${TMP}/runner" bash "$1" > /dev/null 2>&1 || rc=$?
  echo "exit=${rc} output=$(paste -sd'|' - < "$out") calls=$(paste -sd, - < "$calls" | sed "s|${TMP}/runner/|RUNNER_TEMP/|g")"
}

# judge_waiting_lookup <workflow-file>: pin 31, the waiting-pull-request step.
judge_waiting_lookup() {
  local script="${TMP}/waiting.sh" got want
  judge_job_token "$1" "$WAITING_STEP" "the waiting step" "the pull requests are read with it"
  step_block "$1" "$WAITING_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${WAITING_STEP}' with a run: | block"
    return 0
  fi
  got="$(waiting_outcome "$script" "0.0.10" "7\n" 0 ok)"
  want="exit=0 output=waiting=7|check=ok calls=waiting-pull-request --version 0.0.10 --status RUNNER_TEMP/waiting-status"
  [[ "$got" == "$want" ]] || echo "the waiting step gives '${got}', not '${want}' — a plain number is the step's output, and the status the lookup wrote is its check"
  got="$(waiting_outcome "$script" "0.0.10" "" 1 "")"
  want="exit=0 output=waiting=|check=failed calls=waiting-pull-request --version 0.0.10 --status RUNNER_TEMP/waiting-status"
  [[ "$got" == "$want" ]] || echo "for a lookup that fails the waiting step gives '${got}', not '${want}' — a failed lookup is not an error, and with no status written its check is failed"
  got="$(waiting_outcome "$script" "0.0.10" "" 0 "no-access")"
  want="exit=0 output=waiting=|check=no-access calls=waiting-pull-request --version 0.0.10 --status RUNNER_TEMP/waiting-status"
  [[ "$got" == "$want" ]] || echo "for a token without pull-requests: read the waiting step gives '${got}', not '${want}' — its check says no-access, so the run summary can name the permission"
  got="$(waiting_outcome "$script" "0.0.10" "" 0 "rate-limited")"
  want="exit=0 output=waiting=|check=rate-limited calls=waiting-pull-request --version 0.0.10 --status RUNNER_TEMP/waiting-status"
  [[ "$got" == "$want" ]] || echo "for a lookup that hit GitHub's rate limit the waiting step gives '${got}', not '${want}' — its check says rate-limited, so the run summary never asks for a permission the caller grants"
  got="$(waiting_outcome "$script" "0.0.10" "seven" 0 ok)"
  want="exit=0 output=waiting=|check=ok calls=waiting-pull-request --version 0.0.10 --status RUNNER_TEMP/waiting-status"
  [[ "$got" == "$want" ]] || echo "for an answer that is not a number the waiting step gives '${got}', not '${want}' — only a plain number becomes an output"
  got="$(waiting_outcome "$script" "0.0.10" "7\nevil=1\n" 0 ok)"
  [[ "$got" == "$want" ]] || echo "for an answer with a second line the waiting step gives '${got}', not '${want}' — a line break must never add an output"
  got="$(waiting_outcome "$script" "0.0.10" "7\n" 0 "ok\nevil=1")"
  want="exit=0 output=waiting=7|check=failed calls=waiting-pull-request --version 0.0.10 --status RUNNER_TEMP/waiting-status"
  [[ "$got" == "$want" ]] || echo "for a status file that says anything but ok, no-access, rate-limited or failed the waiting step gives '${got}', not '${want}' — only those four become the check"
  got="$(waiting_outcome "$script" "" "7\n" 0 ok)"
  want="exit=0 output=waiting=|check=skipped calls="
  [[ "$got" == "$want" ]] || echo "with no latest release the waiting step gives '${got}', not '${want}' — there is no version to look a pull request up for, so its check is skipped"
}

# needs_outcome <script> <stub exit status>: what the needs step does, in a
# workspace with GITHUB_REPOSITORY acme/data, as `exit=<rc> calls=<forsgren
# calls>`; the runner's temp directory shows as RUNNER_TEMP.
needs_outcome() {
  local rc=0 calls="${TMP}/fg.calls"
  : > "$calls"
  rm -rf "${TMP}/runner"
  mkdir -p "${TMP}/runner"
  PATH="${STUB}:${PATH}" FG_CALLS="$calls" GITHUB_REPOSITORY="acme/data" GITHUB_OUTPUT="${TMP}/needs.out" STUB_NEEDS_RC="$2" STUB_NEEDSSTATUS="ok" \
    RUNNER_TEMP="${TMP}/runner" bash "$1" > /dev/null 2>&1 || rc=$?
  echo "exit=${rc} calls=$(paste -sd, - < "$calls" | sed "s|${TMP}/runner/|RUNNER_TEMP/|g")"
}

# judge_needs_check <workflow-file>: pin 34, the needs step.
judge_needs_check() {
  local script="${TMP}/needs.sh" got want
  if [[ -z "$(step_text "$1" "$NEEDS_STEP")" ]]; then
    echo "has no step '${NEEDS_STEP}' — nothing opens forsgren's setup issue when this version needs more configuration"
    return 0
  fi
  judge_job_token "$1" "$NEEDS_STEP" "the needs step" "the setup issue is opened with it"
  if step_text "$1" "$NEEDS_STEP" | grep -qE '^        working-directory:'; then
    echo "the needs step sets a working-directory — check-needs checks the checkout root"
  fi
  step_block "$1" "$NEEDS_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${NEEDS_STEP}' with a run: | block"
    return 0
  fi
  want="exit=0 calls=check-needs --config forsgren.config.yml --repository acme/data --status RUNNER_TEMP/needs-status"
  got="$(needs_outcome "$script" 0)"
  [[ "$got" == "$want" ]] || echo "the needs step gives '${got}', not '${want}' — the status file sits next to the waiting step's"
  got="$(needs_outcome "$script" 1)"
  [[ "$got" == "$want" ]] || echo "for a check-needs that fails the needs step gives '${got}', not '${want}' — checking the needs never fails the run"
}

# summary_outcome <script> <stub summary> <stub exit status>: what the run
# summary step does, with LATEST 0.0.10, WAITING 7, PR_CHECK ok and NEEDS_CHECK no-access in its
# environment and a stub run-summary that prints that and exits with that:
# `exit=<rc> summary=<what reached the job summary file> calls=<forsgren calls>`.
summary_outcome() {
  local rc=0 summary="${TMP}/run-summary.md" calls="${TMP}/fg.calls"
  : > "$summary"
  : > "$calls"
  PATH="${STUB}:${PATH}" FG_CALLS="$calls" GITHUB_STEP_SUMMARY="$summary" GITHUB_REPOSITORY="acme/data" \
    LATEST="0.0.10" WAITING="7" PR_CHECK="ok" NEEDS_CHECK="no-access" STUB_SUMMARY="$2" STUB_SUMMARY_RC="$3" bash "$1" > /dev/null 2>&1 || rc=$?
  echo "exit=${rc} summary=$(paste -sd'|' - < "$summary") calls=$(paste -sd, - < "$calls")"
}

# judge_run_summary <workflow-file>: pin 33, the run summary step.
judge_run_summary() {
  local script="${TMP}/summary.sh" env got want
  env="$(step_block "$1" "$SUMMARY_STEP" env)"
  for line in "LATEST: ${EXPR_OPEN} steps.latest.outputs.latest }}" "WAITING: ${EXPR_OPEN} steps.waiting.outputs.waiting }}" \
    "PR_CHECK: ${EXPR_OPEN} steps.waiting.outputs.check }}" "NEEDS_CHECK: ${EXPR_OPEN} steps.needs.outputs.check }}"; do
    if ! grep -qxF -- "$line" <<< "$env"; then
      echo "the run summary step's env: does not set '${line}' — the summary is told what the lookups found through env: only"
    fi
  done
  step_block "$1" "$SUMMARY_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${SUMMARY_STEP}' with a run: | block"
    return 0
  fi
  got="$(summary_outcome "$script" "## forsgren\n- Update: up to date\n" 0)"
  want="exit=0 summary=## forsgren|- Update: up to date calls=run-summary --latest 0.0.10 --waiting-pr 7 --pr-check ok --needs-check no-access --repository acme/data"
  [[ "$got" == "$want" ]] || echo "the run summary step gives '${got}', not '${want}' — forsgren run-summary's markdown is appended to \$GITHUB_STEP_SUMMARY"
  got="$(summary_outcome "$script" "half a sum" 1)"
  want="exit=0 summary= calls=run-summary --latest 0.0.10 --waiting-pr 7 --pr-check ok --needs-check no-access --repository acme/data"
  [[ "$got" == "$want" ]] || echo "for a run-summary that fails the run summary step gives '${got}', not '${want}' — a summary never fails the run, and half of one is never appended"
}

# judge_render_waiting <workflow-file>: pin 32, the render step passes the
# waiting pull request on.
judge_render_waiting() {
  local script="${TMP}/render.sh" env got want
  env="$(step_block "$1" "$RENDER_STEP" env)"
  if ! grep -qxF -- "WAITING: ${EXPR_OPEN} steps.waiting.outputs.waiting }}" <<< "$env"; then
    echo "the render step's env: does not set WAITING from steps.waiting.outputs.waiting — render is not told the waiting pull request"
  fi
  step_block "$1" "$RENDER_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  got="$(render_calls "$script" LATEST=0.0.10 WAITING=7)"
  want="render --out ${TMP}/runner/site --config forsgren.config.yml --data data/deployments.csv --latest 0.0.10 --waiting-pr 7"
  [[ "$got" == "$want" ]] || echo "with WAITING set the render step runs 'forsgren ${got}', not 'forsgren ${want}' — the footer names the pull request only when render is given it"
}

# judge_render_latest <workflow-file>: pin 30, the render step passes the
# lookup's output on.
judge_render_latest() {
  local script="${TMP}/render.sh" env got want
  env="$(step_block "$1" "$RENDER_STEP" env)"
  if ! grep -qxF -- "LATEST: ${EXPR_OPEN} steps.latest.outputs.latest }}" <<< "$env"; then
    echo "the render step's env: does not set LATEST from steps.latest.outputs.latest — render is not told the latest release"
  fi
  step_block "$1" "$RENDER_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  got="$(render_calls "$script" LATEST=0.0.10)"
  want="render --out ${TMP}/runner/site --config forsgren.config.yml --data data/deployments.csv --latest 0.0.10"
  [[ "$got" == "$want" ]] || echo "with LATEST set the render step runs 'forsgren ${got}', not 'forsgren ${want}' — the footer names a newer release only when render is given it"
}

# judge_permissions <workflow-file>: pin 16 (and pin 34's issues: write), no permissions block and no
# pull-requests permission: the called workflow takes what its caller's job
# grants and never asks for more, which would stop the run of a caller that
# does not grant it.
judge_permissions() {
  if grep -qE '^(  )?(  )?permissions:' "$1"; then
    echo "the workflow has a permissions block — a called workflow that asks for more than its caller grants stops the run before any step, and one that asks for less cannot use what a caller adds (pull-requests: read); it takes the caller's"
  fi
  if grep -qE '^[[:space:]]+pull-requests:' "$1"; then
    echo "the workflow names a pull-requests permission — callers that do not grant it would fail to start; the caller grants it, and the lookup treats a 403 as unknown"
  fi
  if ! grep -qE '^#[[:space:]]+issues: write[[:space:]]' "$1"; then
    echo "the documented caller permissions do not list 'issues: write' — a caller must grant it for forsgren to open its setup issue"
  elif ! grep -A3 -E '^#[[:space:]]+issues: write[[:space:]]' "$1" | grep -qF 'setup issue'; then
    echo "the documented 'issues: write' does not give its reason, the setup issue — it lets forsgren open it when this version needs more configuration; without it, the job summary and page footer say so"
  fi
}

# judge_secret <workflow-file>: pin 17, the one declared secret, not required.
judge_secret() {
  local names required
  names="$(secret_names "$1" | paste -sd, -)"
  if [[ "$names" != FORSGREN_TOKEN ]]; then
    echo "workflow_call declares the secrets [${names}], not FORSGREN_TOKEN alone — the one token collect reads"
  fi
  required="$(secret_required "$1")"
  if [[ "$required" != false ]]; then
    echo "FORSGREN_TOKEN is declared required: ${required:-unset}, not required: false — a new install (no projects yet) must run before its owner made a token, and collect names a missing one itself"
  fi
}

# collect_outcome <script> <none|store|store-fail|real> <token>: runs the
# collect step in the installation's checkout, FORSGREN_TOKEN being <token>
# as the step's env: hands it, with the stub forsgren storing nothing,
# storing, or storing and then failing, or with the real one; as one line:
# exit=<rc> output=<its GITHUB_OUTPUT lines, comma-joined>. Its log in
# ${TMP}/collect.log, its outputs in ${TMP}/collect.out, forsgren's calls in
# ${TMP}/fg.calls, whether the stub got the token in ${TMP}/fg.token.
collect_outcome() {
  local rc=0 path="${STUB}:${PATH}"
  [[ "$2" == real ]] && path="${REAL}:${path}"
  : > "${TMP}/fg.calls"
  : > "${TMP}/fg.token"
  : > "${TMP}/collect.out"
  (
    cd "$INSTALL"
    PATH="$path" FG_CALLS="${TMP}/fg.calls" FG_TOKEN_SEEN="${TMP}/fg.token" \
      STUB_COLLECT="$2" STUB_TOKEN="$3" FORSGREN_TOKEN="$3" \
      GITHUB_OUTPUT="${TMP}/collect.out" bash "$1"
  ) > "${TMP}/collect.log" 2>&1 || rc=$?
  echo "exit=${rc} output=$(paste -sd, - < "${TMP}/collect.out")"
}

# judge_collect_step <workflow-file>: pin 19, the executed collect step.
judge_collect_step() {
  local script="${TMP}/collect.sh" got want calls
  step_block "$1" "$COLLECT_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${COLLECT_STEP}' with a run: | block — no deployment is ever collected into data/"
    return 0
  fi
  new_install
  got="$(collect_outcome "$script" store "$COLLECT_SECRET")"
  want="exit=0 output=status=0"
  [[ "$got" == "$want" ]] || echo "for a collect that stores the collect step gives '${got}', not '${want}'"
  calls="$(paste -sd, - < "${TMP}/fg.calls")"
  [[ "$calls" == "$COLLECT_CMD" ]] || echo "the collect step runs 'forsgren ${calls}', not 'forsgren ${COLLECT_CMD}'"
  if [[ "$(cat "${TMP}/fg.token")" != yes ]]; then
    echo "the collect step does not hand collect FORSGREN_TOKEN in its environment — collect cannot read GitHub"
  fi
  new_install
  got="$(collect_outcome "$script" store-fail "$COLLECT_SECRET")"
  want="exit=0 output=status=1"
  [[ "$got" == "$want" ]] || echo "for a collect that fails after storing the collect step gives '${got}', not '${want}' — it records collect's exit status and lets the job commit and publish what the other repositories stored"
  if ! grep -qF -- "collect: 1 of 2 repositories failed" "${TMP}/collect.log"; then
    echo "for a collect that fails the collect step does not show collect's message in its log"
  fi
}

# judge_collect_token <workflow-file>: pins 18 and 20, FORSGREN_TOKEN reaches
# the collect step's env: only, and never an argument, a file, the log or an
# output.
judge_collect_token() {
  local script="${TMP}/collect.sh" env lines
  env="$(step_block "$1" "$COLLECT_STEP" env)"
  if ! grep -qxF -- "$TOKEN_ENV" <<< "$env"; then
    echo "the collect step's env: does not set ${TOKEN_ENV} — collect has no token"
  fi
  lines="$(grep -nF -- "$EXPR_OPEN" "$1" | grep -E '^[0-9]+:[^#]*secrets' | cut -d: -f1 | paste -sd, - || true)"
  if [[ "$lines" == *,* ]]; then
    echo "hands a secret to more than the collect step's env: (lines ${lines}) — FORSGREN_TOKEN reaches the one step that needs it, never another step or the job"
  fi
  step_block "$1" "$COLLECT_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  new_install
  collect_outcome "$script" store-fail "$COLLECT_SECRET" > /dev/null
  if grep -qF -- "$COLLECT_SECRET" "${TMP}/fg.calls"; then
    echo "the collect step hands FORSGREN_TOKEN to forsgren in an argument — ps shows arguments; collect reads it from the environment only"
  fi
  if grep -rqF -- "$COLLECT_SECRET" "$INSTALL"; then
    echo "the collect step leaves FORSGREN_TOKEN in a file of the checkout — the data step commits what is there"
  fi
  if grep -qF -- "$COLLECT_SECRET" "${TMP}/collect.log"; then
    echo "the collect step shows FORSGREN_TOKEN in its log"
  fi
  if grep -qF -- "$COLLECT_SECRET" "${TMP}/collect.out"; then
    echo "the collect step writes FORSGREN_TOKEN to a step output"
  fi
}

# judge_collect_e2e <workflow-file>: pin 21, the collect step with the real
# forsgren, with no token: fine with no projects, named with one.
judge_collect_e2e() {
  local script="${TMP}/collect-e2e.sh" got want
  step_block "$1" "$COLLECT_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  new_install
  cp internal/config/starter.yml "${INSTALL}/forsgren.config.yml"
  got="$(collect_outcome "$script" real "")"
  want="exit=0 output=status=0"
  if [[ "$got" != "$want" ]]; then
    echo "with the real forsgren, the starter configuration (no projects) and no FORSGREN_TOKEN the collect step gives '${got}', not '${want}' — a new install runs before its owner made a token"
  fi
  if [[ -e "${INSTALL}/data" ]]; then
    echo "with the real forsgren and no projects the collect step creates data/ — nothing was collected"
  fi
  new_install
  printf '%s' "$VALID_CONFIG" > "${INSTALL}/forsgren.config.yml"
  got="$(collect_outcome "$script" real "")"
  want="exit=0 output=status=1"
  if [[ "$got" != "$want" ]] || ! grep -qF -- "FORSGREN_TOKEN is not set" "${TMP}/collect.log"; then
    echo "with the real forsgren, a configured repository and no FORSGREN_TOKEN the collect step gives '${got}' and logs '$(paste -sd'|' - < "${TMP}/collect.log")' — it must record status=1 with collect's message naming FORSGREN_TOKEN"
  fi
}

# judge_collect_commands <workflow-file>: pin 27, collect's output never
# runs as a workflow command.
judge_collect_commands() {
  local script="${TMP}/collect.sh" got live first second
  step_block "$1" "$COLLECT_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  new_install
  got="$(collect_outcome "$script" inject "$COLLECT_SECRET")"
  live="$(live_commands "${TMP}/collect.log")"
  if [[ -n "$live" ]]; then
    echo "for collect output with workflow commands in it the collect step leaves them live in the log ($(paste -sd'|' - <<< "$live")) — a line of collect's output that starts with :: must not run as a workflow command"
  fi
  if ! grep -qF -- "::warning::injected-by-collect" "${TMP}/collect.log" \
    || ! grep -qF -- "collect: 1 of 1 repositories failed" "${TMP}/collect.log"; then
    echo "for collect output with workflow commands in it the collect step does not show collect's output, stdout and stderr, in the log"
  fi
  [[ "$got" == "exit=0 output=status=1" ]] || echo "for collect output with workflow commands in it the collect step gives '${got}', not 'exit=0 output=status=1'"
  first="$(stop_token "${TMP}/collect.log")"
  new_install
  collect_outcome "$script" inject "$COLLECT_SECRET" > /dev/null
  second="$(stop_token "${TMP}/collect.log")"
  if [[ -n "$first" && "$first" == "$second" ]]; then
    echo "the collect step stops workflow commands with the same token on every run (${first}) — output that knows it can turn them back on"
  fi
}

# judge_collect_commands_e2e <workflow-file>: pin 28, the collect step with
# the real forsgren logs collect's message with workflow commands stopped.
judge_collect_commands_e2e() {
  local script="${TMP}/collect-commands-e2e.sh" got where live
  step_block "$1" "$COLLECT_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  new_install
  printf '%s' "$VALID_CONFIG" > "${INSTALL}/forsgren.config.yml"
  collect_outcome "$script" real "" > /dev/null
  where="$(stopped_text "${TMP}/collect.log" "FORSGREN_TOKEN is not set")"
  if [[ "$where" != stopped ]]; then
    echo "with the real forsgren and no FORSGREN_TOKEN the collect step logs collect's message ${where:-nowhere}, not between ::stop-commands:: and its end — collect's output must never run as a workflow command"
  fi
  new_install
  printf '%s' "$INJECTING_CONFIG" > "${INSTALL}/forsgren.config.yml"
  got="$(collect_outcome "$script" real "")"
  live="$(live_commands "${TMP}/collect.log")"
  if [[ "$got" != "exit=0 output=status=1" || -n "$live" ]]; then
    echo "with the real forsgren and an unknown key that carries a line break and ::warning:: the collect step gives '${got}' and leaves live in the log: $(paste -sd'|' - <<< "${live:-nothing}") — it must record status=1 with no workflow command live"
  fi
}

# store_data: what collect leaves in the installation's checkout, a new
# data/deployments.csv and data/commits.csv, beside an untracked and a
# staged file that are not collect's.
store_data() {
  mkdir -p "${INSTALL}/data"
  printf '# forsgren history v1\nacme stored\n' > "${INSTALL}/data/deployments.csv"
  printf '# forsgren commits v1\nacme commit\n' > "${INSTALL}/data/commits.csv"
  printf 'untracked\n' > "${INSTALL}/other.txt"
  printf 'staged\n' > "${INSTALL}/staged.txt"
  iso -C "$INSTALL" add staged.txt
}

# bot_findings <what> <commit label> <branch>: the problem, if any, with the
# remote <branch>'s last commit: its author and committer must be
# github-actions[bot], and it must be unsigned.
bot_findings() {
  local who
  who="$(iso_out -C "$ORIGIN" log -1 --format='%an <%ae>' "$3")"
  [[ "$who" == "$BOT_IDENTITY" ]] || echo "$1 the $2's author is '${who}', not '${BOT_IDENTITY}'"
  who="$(iso_out -C "$ORIGIN" log -1 --format='%cn <%ce>' "$3")"
  [[ "$who" == "$BOT_IDENTITY" ]] || echo "$1 the $2's committer is '${who}', not '${BOT_IDENTITY}'"
  if iso_out -C "$ORIGIN" cat-file commit "$3" | grep -q '^gpgsig'; then
    echo "$1 the $2 is signed — it must be unsigned"
  fi
}

# judge_data_step <workflow-file>: pin 22, the executed data step.
judge_data_step() {
  local script="${TMP}/data.sh" ref="refs/heads/${TRUNK}" got want files
  step_block "$1" "$DATA_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${DATA_STEP}' with a run: | block — what collect stores in data/ is never committed"
    return 0
  fi
  new_install
  got="$(git_step_outcome "$script" kept "$ref" "$TRUNK")"
  want="exit=0 commits=1"
  [[ "$got" == "$want" ]] || echo "with data/ unchanged the data step gives '${got}', not '${want}' — nothing to commit, nothing pushed"
  got="$(git_step_outcome "$script" kept refs/tags/v1 "$TRUNK")"
  [[ "$got" == "$want" ]] || echo "with data/ unchanged on a tag the data step gives '${got}', not '${want}' — a ref that is not a branch is refused only when there is something to commit"
  new_install
  store_data
  got="$(git_step_outcome "$script" kept "$ref" "$TRUNK")"
  want="exit=0 commits=2"
  if [[ "$got" != "$want" ]]; then
    echo "for changed data/ on its branch the data step gives '${got}', not '${want}' — one commit of data/, pushed there"
  else
    bot_findings "for changed data/" "data commit" "$TRUNK"
    got="$(iso_out -C "$ORIGIN" log -1 --format='%B' "$TRUNK")"
    [[ "$got" == "$DATA_SUBJECT" ]] || echo "the data commit's message is '${got}', not '${DATA_SUBJECT}'"
    files="$(iso_out -C "$ORIGIN" diff-tree --no-commit-id --name-only -r "$TRUNK" | paste -sd, -)"
    [[ "$files" == "data/commits.csv,data/deployments.csv" ]] || echo "the data commit holds [${files}], not data/ alone with both of collect's files — what collect stored, never the rest of the checkout"
  fi
  new_install
  mkdir -p "${INSTALL}/data"
  printf '# forsgren history v1\nacme old\n' > "${INSTALL}/data/deployments.csv"
  iso -C "$INSTALL" add data/deployments.csv
  iso -C "$INSTALL" -c user.name=Setup -c user.email=setup@example.com commit -m "An earlier history"
  iso -C "$INSTALL" push origin "$TRUNK"
  printf 'acme new\n' >> "${INSTALL}/data/deployments.csv"
  got="$(git_step_outcome "$script" kept "$ref" "$TRUNK")"
  want="exit=0 commits=3"
  [[ "$got" == "$want" ]] || echo "for an appended data/deployments.csv the data step gives '${got}', not '${want}' — the daily run's change is committed and pushed too"
  new_install
  store_data
  got="$(git_step_outcome "$script" kept "$ref" "$TRUNK" hostile)"
  want="exit=0 commits=2"
  if [[ "$got" != "$want" ]]; then
    echo "with an outer identity and a signing config inherited from the environment the data step gives '${got}', not '${want}' — the commit sets its own identity and config in its environment"
  else
    bot_findings "with an inherited outer identity" "data commit" "$TRUNK"
  fi
  new_install
  store_data
  got="$(git_step_outcome "$script" kept refs/tags/v1 "$TRUNK")"
  want="exit=1 commits=1"
  [[ "$got" == "$want" ]] || echo "for changed data/ on a ref that is not a branch (refs/tags/v1) the data step gives '${got}', not '${want}' — it must refuse, there is no branch to commit to"
}

# judge_data_token <workflow-file>: pin 23, the data push carries the job
# token and never stores or shows it.
judge_data_token() {
  local script="${TMP}/data.sh"
  step_block "$1" "$DATA_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  new_install
  store_data
  git_step_outcome "$script" kept "refs/heads/${TRUNK}" "$TRUNK" > /dev/null
  push_token_findings "the data step"
}

# judge_data_moved <workflow-file>: pin 24, a branch that moved since the
# checkout fails the data step by name, with no rebase and no force.
judge_data_moved() {
  local script="${TMP}/data.sh" other="${TMP}/other" got want tip
  step_block "$1" "$DATA_STEP" run > "$script"
  [[ -s "$script" ]] || return 0
  new_install
  rm -rf "$other"
  iso clone "$ORIGIN" "$other"
  printf 'other\n' > "${other}/OTHER.md"
  iso -C "$other" add OTHER.md
  iso -C "$other" -c user.name=Other -c user.email=other@example.com commit -m "Another push"
  iso -C "$other" push origin "$TRUNK"
  tip="$(iso_out -C "$ORIGIN" rev-parse "$TRUNK")"
  store_data
  got="$(git_step_outcome "$script" kept "refs/heads/${TRUNK}" "$TRUNK")"
  want="exit=1 commits=2"
  [[ "$got" == "$want" ]] || echo "with the branch moved since the checkout the data step gives '${got}', not '${want}' — it must fail, never rebase or force"
  if [[ "$(iso_out -C "$ORIGIN" rev-parse "$TRUNK")" != "$tip" ]]; then
    echo "with the branch moved since the checkout the data step replaced the commit another pushed — it must never force"
  fi
  if ! grep -E '^::error' "${TMP}/step.log" | grep -qF -- "$MOVED"; then
    echo "with the branch moved since the checkout the data step does not name the cause in an ::error saying '${MOVED}' (log: $(paste -sd'|' - < "${TMP}/step.log"))"
  fi
}

# fail_outcome <script> <status>: the fail step with COLLECT_STATUS being
# <status>, as one line: exit=<rc> error=<yes|no>, yes when it logged an
# ::error.
fail_outcome() {
  local rc=0 error=no
  COLLECT_STATUS="$2" bash "$1" > "${TMP}/fail.log" 2>&1 || rc=$?
  if grep -q '^::error' "${TMP}/fail.log"; then error=yes; fi
  echo "exit=${rc} error=${error}"
}

# judge_fail_step <workflow-file>: pin 25, the job fails at its end when
# collect failed, and the three steps in a row.
judge_fail_step() {
  local script="${TMP}/fail.sh" collect="${TMP}/collect.sh" data="${TMP}/data.sh" env got want v status rc=0
  step_block "$1" "$FAIL_STEP" run > "$script"
  if [[ ! -s "$script" ]]; then
    echo "has no step '${FAIL_STEP}' with a run: | block — a failed collect would leave the job green"
    return 0
  fi
  env="$(step_block "$1" "$FAIL_STEP" env)"
  if ! grep -qxF -- "COLLECT_STATUS: ${EXPR_OPEN} steps.collect.outputs.status }}" <<< "$env"; then
    echo "the fail step's COLLECT_STATUS is not ${EXPR_OPEN} steps.collect.outputs.status }} — it cannot know collect's exit status"
  fi
  if ! step_text "$1" "$COLLECT_STEP" | grep -qx '        id: collect'; then
    echo "the collect step has no id: collect — steps.collect.outputs.status would be empty"
  fi
  for v in 0 1 2 ''; do
    got="$(fail_outcome "$script" "$v")"
    want="exit=1 error=yes"
    [[ "$v" == 0 ]] && want="exit=0 error=no"
    [[ "$got" == "$want" ]] || echo "with COLLECT_STATUS=${v} the fail step gives '${got}', not '${want}'"
  done
  step_block "$1" "$COLLECT_STEP" run > "$collect"
  step_block "$1" "$DATA_STEP" run > "$data"
  [[ -s "$collect" && -s "$data" ]] || return 0
  new_install
  collect_outcome "$collect" store-fail "$COLLECT_SECRET" > /dev/null
  status="$(sed -n 's/^status=//p' "${TMP}/collect.out" | head -1)"
  got="$(git_step_outcome "$data" kept "refs/heads/${TRUNK}" "$TRUNK")"
  COLLECT_STATUS="$status" bash "$script" > "${TMP}/fail.log" 2>&1 || rc=$?
  got="${got} fail-step=${rc}"
  want="exit=0 commits=2 fail-step=1"
  [[ "$got" == "$want" ]] || echo "when collect fails after storing, the data and fail steps give '${got}', not '${want}' — what the others stored is committed and pushed, then the job fails at its end"
}

# judge_concurrency <workflow-file>: pin 26, runs of one installation queue.
judge_concurrency() {
  local block group
  block="$(awk '
    /^    concurrency:[[:space:]]*$/ { inc=1; next }
    inc && $0 !~ /^      / && $0 !~ /^[[:space:]]*$/ { inc=0 }
    inc { print }
  ' "$1")"
  if [[ -z "$block" ]]; then
    echo "the job has no concurrency: block — a scheduled run and a manual one would race on the data/ push"
    return 0
  fi
  group="$(sed -n 's/^      group:[[:space:]]*//p' <<< "$block")"
  if [[ "$group" != *"${EXPR_OPEN} github.repository }}"* ]]; then
    echo "the job's concurrency group is '${group}', not keyed on ${EXPR_OPEN} github.repository }}, the caller's repository"
  fi
  if ! grep -qxE '      cancel-in-progress:[[:space:]]*false[[:space:]]*' <<< "$block"; then
    echo "the job's concurrency does not set cancel-in-progress: false — a second run would cancel one mid-push"
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
  local install checkout init check render collect data publish failstep lookup needs
  lookup="$(line_of "$1" "- name: ${LATEST_STEP}")"
  install="$(line_of "$1" "- name: ${INSTALL_STEP}")"
  checkout="$(line_of "$1" "- name: ${CHECKOUT_STEP}")"
  init="$(line_of "$1" "- name: ${INIT_STEP}")"
  check="$(line_of "$1" "- name: ${CHECK_STEP}")"
  render="$(line_of "$1" "- name: ${RENDER_STEP}")"
  collect="$(line_of "$1" "- name: ${COLLECT_STEP}")"
  data="$(line_of "$1" "- name: ${DATA_STEP}")"
  publish="$(line_of "$1" "- name: ${PUBLISH_STEP}")"
  failstep="$(line_of "$1" "- name: ${FAIL_STEP}")"
  if later "$check" "$collect"; then
    echo "collects (line ${collect}) before the config check (line ${check}) — collect would read a configuration nobody checked"
  fi
  if later "$collect" "$data"; then
    echo "commits data/ (line ${data}) before collect (line ${collect}) — there is nothing to commit yet"
  fi
  if later "$data" "$render"; then
    echo "commits data/ (line ${data}) after it renders (line ${render}) — a failed render or publish would drop what collect stored"
  fi
  if later "$publish" "$failstep"; then
    echo "fails the job for collect (line ${failstep}) before it publishes (line ${publish}) — what the other repositories stored must be published first"
  fi
  if later "$init" "$check"; then
    echo "writes the starter (line ${init}) after the config check (line ${check}) — a new install would fail the check before it has a file"
  fi
  if later "$checkout" "$init"; then
    echo "writes the starter (line ${init}) before checking out the caller's repository (line ${checkout}) — there is no checkout to write it into"
  fi
  if later "$install" "$init"; then
    echo "writes the starter (line ${init}) before installing forsgren (line ${install}) — init-config is not on PATH yet"
  fi
  needs="$(line_of "$1" "- name: ${NEEDS_STEP}")"
  if later "$checkout" "$needs"; then
    echo "checks the needs (line ${needs}) before checking out the caller's repository (line ${checkout}) — there is no checkout to check"
  fi
  if later "$check" "$needs"; then
    echo "checks the needs (line ${needs}) before the config check (line ${check}) — it would read a configuration nobody checked"
  fi
  if later "$needs" "$(line_of "$1" "- name: ${SUMMARY_STEP}")"; then
    echo "checks the needs (line ${needs}) after the run summary — the summary reads its status"
  fi
  if later "$(line_of "$1" "- name: ${WAITING_STEP}")" "$render"; then
    echo "looks up the waiting pull request after it renders — render is given the lookup's output"
  fi
  if later "$lookup" "$(line_of "$1" "- name: ${WAITING_STEP}")"; then
    echo "looks up the waiting pull request before the latest release (line ${lookup}) — it needs that version"
  fi
  if later "$lookup" "$render"; then
    echo "looks up the latest release (line ${lookup}) after it renders (line ${render}) — render is given the lookup's output"
  fi
  if later "$install" "$lookup"; then
    echo "looks up the latest release (line ${lookup}) before installing forsgren (line ${install}) — latest-release is not on PATH yet"
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
  keys="$(call_keys "$1" | grep -vx secrets || true)"
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
  judge_latest_lookup "$1"
  judge_render_latest "$1"
  judge_waiting_lookup "$1"
  judge_render_waiting "$1"
  judge_run_summary "$1"
  judge_needs_check "$1"
  judge_secret "$1"
  judge_collect_step "$1"
  judge_collect_token "$1"
  judge_collect_e2e "$1"
  judge_collect_commands "$1"
  judge_collect_commands_e2e "$1"
  judge_data_step "$1"
  judge_data_token "$1"
  judge_data_moved "$1"
  judge_fail_step "$1"
  judge_concurrency "$1"
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
  echo "  ok: ${WF} is a workflow_call with no inputs that installs forsgren from its own job.workflow_repository at its own job.workflow_sha, both checked before go install, through env: only, built with go.mod's Go, after the caller's pinned checkout, a starter step that commits a new install's one file with a token that is never stored or shown, a contents: write job, a config check that fails the job with check-config's message before render, with the real forsgren too, and never runs that message as a workflow command, a collect step that alone gets FORSGREN_TOKEN (an optional secret), records collect's status and never runs collect's output as a workflow command, a data step that commits and pushes data/ alone as github-actions[bot] and fails by name when the branch moved, a fail step after publishing, and one run at a time per caller repository"
fi

# --- Self-proof: each pin, on a mutant of the real metrics.yml, names its reason.
# Each mutant is judged by the one pin it is aimed at, never by every pin:
# the pins execute real steps (a real git, the real forsgren), so a mutant
# judged by all of them costs seconds, and judging by the aimed pin alone
# also proves that pin, not another, names the reason.
# judged <judge> <case> <reason> <mutant>: <judge>, the function of the pin
# the mutant is aimed at, names <reason> for the mutant.
judged() {
  local got
  got="$("$1" "$4")"
  if grep -qF -- "$3" <<< "$got"; then
    echo "  ok: $2 is rejected"
  else
    fail "the mutant with $2 was ACCEPTED by ${1} (verdict: ${got:-none}) — this pin cannot detect the defect it exists for"
  fi
}

# proves <judge> <case> <reason> <sed-expression>: the real metrics.yml
# mutated by the sed expression, judged by <judge>.
proves() {
  local mutant="${TMP}/mutants/$2.yml"
  selftest_mutant "$WF" "$mutant" "$4" || return 0
  judged "$1" "$2" "$3" "$mutant"
}

# proves_moved <judge> <case> <reason> <step name> [<before step name>]: as
# proves, on the real metrics.yml with that step moved before the other, or
# removed when no other is named.
proves_moved() {
  local mutant="${TMP}/mutants/$2.yml"
  mkdir -p "${TMP}/mutants"
  move_step "$WF" "$4" "${5:-}" > "$mutant"
  if cmp -s "$WF" "$mutant"; then
    fail "moving the step '$4' changed nothing in ${WF}: the proof would be vacuous"
    return 0
  fi
  judged "$1" "$2" "$3" "$mutant"
}

proves judge_trigger "a push trigger" "not on workflow_call alone" \
  's/^  workflow_call:$/  push:\n  workflow_call:/'
proves judge_trigger "a forsgren-version input back" "workflow_call declares [inputs]" \
  's/^  workflow_call:$/  workflow_call:\n    inputs:\n      forsgren-version:\n        type: string\n        required: true/'
proves judge_expressions "the commit pasted into run:" "expands a \${{ }} expression inside run:" \
  "s/@\\\${FORSGREN_SHA}\"\$/@\${{ job.workflow_sha }}\"/"
proves judge_install_env "the caller's commit" "FORSGREN_SHA is not" \
  's/job\.workflow_sha }}/github.workflow_sha }}/'
proves judge_install_env "the caller's repository" "FORSGREN_REPOSITORY is not" \
  's/job\.workflow_repository }}/github.repository }}/'
proves judge_install_run "no install step" "has no step '${INSTALL_STEP}'" \
  "s/- name: ${INSTALL_STEP}\$/- name: Install something else/"
proves judge_install_run "checks that accept anything" "for the commit 'latest'" \
  's/^\( *\)exit 1$/\1exit 0/'
proves judge_install_run "a commit check without its end anchor" "for the commit '${SHA}0'" \
  's/{40}\$/{40}/'
proves judge_install_run "a repository check that lets a third element through" "for the repository 'yveshanoulle/forsgren/extra'" \
  's/\[A-Za-z0-9_\.-\]\*\$/[A-Za-z0-9_.\/-]*$/'
proves judge_install_run "upstream installed for every caller" "for the fork acme/forsgren" \
  "s|github.com/\\\${FORSGREN_REPOSITORY}/cmd|github.com/yveshanoulle/forsgren/cmd|"
proves judge_install_run "go install at another version" "the install step gives 'installed install github.com/${UPSTREAM}/cmd/forsgren@v0.0.1'" \
  "s/@\\\${FORSGREN_SHA}\"\$/@v0.0.1\"/"
proves judge_setup_go "setup-go on another Go" "actions/setup-go installs Go '1.0.0'" \
  "s/^\(          go-version: \).*\$/\1'1.0.0'/"

proves judge_checkout "no checkout pin" "not actions/checkout pinned by a full 40-digit commit" \
  's|actions/checkout@[0-9a-f]\{40\}  # v7.0.1|actions/checkout@v7|'
proves judge_checkout "another checkout commit" "not at 3d3c42e5aac5ba805825da76410c181273ba90b1 as Quality's own checkout is" \
  's|actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1|actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b2|'
proves judge_checkout "persist-credentials true" "does not set persist-credentials: false" \
  's/persist-credentials: false/persist-credentials: true/'
proves judge_checkout "no checkout step" "has no step '${CHECKOUT_STEP}'" \
  "s/- name: ${CHECKOUT_STEP}\$/- name: Check out something else/"
proves judge_config_step "no config step name" "has no step '${CHECK_STEP}'" \
  "s/- name: ${CHECK_STEP}\$/- name: Check something else/"
proves judge_config_step "check-config on another file" "for a valid config the config step gives" \
  's/--config forsgren\.config\.yml/--config config.yml/'
proves judge_config_step "a config step that lets a refusal pass" "for a refused config the config step gives 'exit=0" \
  '/- name: Check the caller/,/- name: Render/ s/exit 1/exit 0/'
proves judge_config_step "a refusal without its cross mark" "for a refused config the config step gives 'exit=1 calls=${CONFIG_CMD} log=shown summary=check-config" \
  's/"❌ /"/'
proves judge_config_commands "workflow commands left on" "leaves them live in the log (line " \
  '/::stop-commands::/d'
proves judge_config_commands "commands never resumed" "never ended" \
  '/echo "::.{token}::"/d'
proves judge_config_commands "the same token on every run" "the same token on every run" \
  's/^\( *\)token=.*$/\1token=forsgren/'
proves judge_config_e2e "the real forsgren on another file" "with the real forsgren and no forsgren.config.yml" \
  's/--config forsgren\.config\.yml/--config config.yml/'
proves judge_config_e2e "a real refusal without its cross mark" "with the real forsgren and an invalid forsgren.config.yml" \
  's/"❌ /"/'
proves judge_config_e2e "a real valid config refused" "with the real forsgren and a valid forsgren.config.yml" \
  's/ -ne 0 \]\]; then/ -ne 99 ]]; then/'

# The starter step (forsgren#12, step 3).
proves judge_starter_step "no starter step" "has no step '${INIT_STEP}'" \
  "s/- name: ${INIT_STEP}\$/- name: Write something else/"
proves judge_starter_step "init-config on another file" "the starter step runs 'forsgren init-config --config config.yml'" \
  's/forsgren init-config --config forsgren\.config\.yml/forsgren init-config --config config.yml/'
proves judge_starter_step "a starter committed even when kept" "for a kept forsgren.config.yml the starter step gives" \
  "s/\\[\\[ \"${D}result\" != \"created forsgren.config.yml\" \\]\\]/false/"
proves judge_starter_step "no starter commit" "for a created forsgren.config.yml on its branch the starter step gives 'exit=0 commits=1'" \
  '/^ *GIT_CONFIG_COUNT=0 /,/git commit --quiet/d'
proves judge_starter_step "the whole checkout committed" "the starter commit holds [forsgren.config.yml,other.txt,staged.txt]" \
  "s/git add -- forsgren.config.yml/git add -A/; s/'forsgren: add a starter forsgren.config.yml' -- forsgren.config.yml/'forsgren: add a starter forsgren.config.yml'/"
proves judge_starter_step "another commit author" "the starter commit's author is 'someone <" \
  "s/GIT_AUTHOR_NAME='github-actions\\[bot\\]'/GIT_AUTHOR_NAME='someone'/"
proves judge_starter_step "another author address" "the starter commit's author is 'github-actions[bot] <12345+github-actions" \
  "s/GIT_AUTHOR_EMAIL='41898282+github-actions/GIT_AUTHOR_EMAIL='12345+github-actions/"
proves judge_starter_step "another committer" "the starter commit's committer is 'someone <" \
  "s/GIT_COMMITTER_NAME='github-actions\\[bot\\]'/GIT_COMMITTER_NAME='someone'/"
proves judge_starter_step "an identity left to -c" "with an inherited outer identity the starter commit's author is 'Outer Author <outer-author@example.com>'" \
  "/GIT_AUTHOR_NAME=/d; /GIT_COMMITTER_NAME=/d; s/git commit --quiet/git -c user.name=bot -c user.email=bot@example.com commit --quiet/"
proves judge_starter_step "the inherited config left alone" "with an outer identity and a signing config inherited from the environment the starter step gives 'exit=128 commits=1'" \
  '/^ *GIT_CONFIG_COUNT=0 /d'
proves judge_starter_step "another commit message" "the starter commit's message is 'forsgren: add a config'" \
  "s/add a starter forsgren\\.config\\.yml'/add a config'/"
proves judge_starter_step "no push" "for a created forsgren.config.yml on its branch the starter step gives 'exit=0 commits=1'" \
  '/git push --quiet origin/d'
proves judge_starter_step "a push to a fixed branch instead of the run's" "for a created forsgren.config.yml on its branch the starter step gives 'exit=0 commits=1'" \
  "s|\"HEAD:${D}{GITHUB_REF}\"|\"HEAD:refs/heads/main\"|"
proves judge_starter_step "a starter pushed from a tag" "for a ref that is not a branch (refs/tags/v1)" \
  '/- name: Write the starter/,/git add --/ s/exit 1/exit 0/'
proves judge_starter_step "the branch guard before the kept check" "with no branch ref at all" \
  's/^\( *\)exit 0$/\1true/'
proves judge_starter_token "the token in an argument" "hands the token to git in an argument" \
  "s|^\\( *\\)git push --quiet origin|\\1git -c \"http.extraheader=AUTHORIZATION: basic ${D}{auth}\" push --quiet origin|"
proves judge_starter_token "the token stored in the checkout" "leaves the token on disk in the checkout" \
  "s|^\\( *\\)git push --quiet origin|\\1git config http.extraheader \"AUTHORIZATION: basic ${D}{auth}\"\\n\\1git push --quiet origin|"
proves judge_starter_token "the token echoed" "the starter step shows the token in its log" \
  "s|^\\( *\\)git push --quiet origin|\\1echo \"pushing with ${D}{GH_TOKEN}\"\\n\\1git push --quiet origin|"
proves judge_starter_token "a push without the header" "the starter step's push carries" \
  's/"AUTHORIZATION: basic /"X-Other: basic /'
proves judge_starter_e2e "a starter that leaves no file" "with the real forsgren a new install's config check after the starter step exits" \
  "s|^\\( *\\)git push --quiet origin.*\$|&\\n\\1rm -f forsgren.config.yml|"
proves judge_permissions "a permissions block back on the job" "the workflow has a permissions block" \
  "s/^    runs-on: ubuntu-latest\$/&\\n    permissions:\\n      contents: write/"
proves judge_permissions "a top-level permissions block back" "the workflow has a permissions block" \
  "s/^jobs:\$/permissions: {}\\n\\njobs:/"
proves judge_permissions "a job demanding pull-requests: read" "the workflow names a pull-requests permission" \
  "s/^    runs-on: ubuntu-latest\$/&\\n    permissions:\\n      pull-requests: read/"
proves judge_render_config "render without the config" "the render step runs 'forsgren render --out" \
  '/forsgren render /s/ --config forsgren\.config\.yml//'
proves judge_render_config "render without the history" "the render step runs 'forsgren render --out" \
  '/forsgren render /s/ --data data\/deployments\.csv//'

# The latest release (forsgren#40).
proves judge_waiting_lookup "a waiting lookup without the job token" "does not set GITHUB_TOKEN to the job's token" \
  "/GITHUB_TOKEN: \\${D}{{ github.token }}/{x;s/^/x/;/^xx\$/{x;d;};x;}"
proves judge_waiting_lookup "a waiting lookup that fails the job" "for a lookup that fails the waiting step gives" \
  "s/--status \"\\${D}status_file\" || true/--status \"\\${D}status_file\"/"
proves judge_waiting_lookup "a waiting output that is not checked" "for an answer that is not a number" \
  "/if \\[\\[ ! \"\\${D}waiting\" =~/,/^          fi${D}/d"
proves judge_run_summary "a run summary that is not appended" "the run summary step gives" \
  "s|>> \"\\${D}GITHUB_STEP_SUMMARY\"||"
proves judge_run_summary "a run summary without the check in env" "does not set 'PR_CHECK" \
  "/PR_CHECK: \\${D}{{ steps.waiting.outputs.check }}/d"
proves judge_run_summary "a run summary without the needs check in env" "does not set 'NEEDS_CHECK" \
  "/NEEDS_CHECK: \\${D}{{ steps.needs.outputs.check }}/d"
proves judge_run_summary "a run summary without the needs check passed" "the run summary step gives" \
  "s| --needs-check \"\\${D}NEEDS_CHECK\"||"
proves judge_waiting_lookup "a waiting step without its check" "for a token without pull-requests: read the waiting step gives" \
  "/echo \"check=/d"
proves judge_render_waiting "a render without the waiting pull request" "with WAITING set the render step runs" \
  "s/ \\${D}{WAITING:+--waiting-pr \"\\${D}WAITING\"}//"
proves judge_render_waiting "a render without WAITING in env" "does not set WAITING from steps.waiting.outputs.waiting" \
  "/WAITING: \\${D}{{ steps.waiting.outputs.waiting }}/d"
proves judge_latest_lookup "a lookup without the job token" "does not set GITHUB_TOKEN to the job's token" \
  "/GITHUB_TOKEN: \\${D}{{ github.token }}/d"
proves judge_latest_lookup "a lookup with the caller's secret" "hands FORSGREN_TOKEN over" \
  "s|^\\( *\\)GITHUB_TOKEN: \\${D}{{ github.token }}|&\\n\\1FORSGREN_TOKEN: x|"
proves judge_latest_lookup "a lookup that fails the job" "for a lookup that fails the lookup step gives" \
  's/forsgren latest-release || true/forsgren latest-release/'
proves judge_latest_lookup "a lookup output that is not checked" "for an answer that is not a version" \
  "/if \\[\\[ ! \"\\${D}latest\" =~/,/^          fi${D}/d"
proves judge_render_latest "a render without the latest release" "with LATEST set the render step runs" \
  "s/ \\${D}{LATEST:+--latest \"\\${D}LATEST\"}//"
proves judge_render_latest "a render without LATEST in env" "does not set LATEST from steps.latest.outputs.latest" \
  "/LATEST: \\${D}{{ steps.latest.outputs.latest }}/d"

# What this version needs (forsgren#73).
proves judge_needs_check "a needs step without the job token" "the needs step's env: does not set GITHUB_TOKEN to the job's token" \
  "/GITHUB_TOKEN: \\${D}{{ github.token }}/{x;s/^/x/;/^xxx\$/{x;d;};x;}"
proves judge_needs_check "a needs step with the caller's secret" "the needs step's env: hands FORSGREN_TOKEN over" \
  "/- name: Check what this forsgren version needs/,/run: |/s|^\\( *\\)GITHUB_TOKEN: \\${D}{{ github.token }}|&\\n\\1FORSGREN_TOKEN: x|"
proves judge_needs_check "a needs step on another config file" "the needs step gives" \
  "s/check-needs --config forsgren\\.config\\.yml/check-needs --config config.yml/"
proves judge_needs_check "a needs step without its status file" "the needs step gives" \
  "/check-needs/s| --status \"\\${D}status_file\"||"
proves judge_needs_check "a needs step that fails the job" "for a check-needs that fails the needs step gives" \
  "/check-needs/s/ || true\$//"
proves judge_permissions "no issues: write in the documented permissions" "do not list 'issues: write'" \
  "/^#   issues: write/d"
proves judge_permissions "an issues: write without its reason" "does not give its reason, the setup issue" \
  "s/its setup issue/its repair/;s/^#   issues: write .*/#   issues: write        for something/"

# The token (forsgren#12, step 6).
proves judge_secret "a required token" "FORSGREN_TOKEN is declared required: true" \
  's/^        required: false$/        required: true/'
proves judge_secret "a second secret" "not FORSGREN_TOKEN alone" \
  's/^    secrets:$/    secrets:\n      OTHER_TOKEN:\n        required: false/'
proves judge_secret "no secret declared" "workflow_call declares the secrets []" \
  '/^    secrets:$/,/^        required: false$/d'
proves judge_collect_token "the token in the job's env" "hands a secret to more than the collect step's env:" \
  "s/^    runs-on: ubuntu-latest\$/&\n    env:\n      ${TOKEN_ENV}/"
proves judge_collect_token "the token in the data step" "hands a secret to more than the collect step's env:" \
  "/- name: ${DATA_STEP}/,/run: |/ s/^          GH_TOKEN: .*\$/&\n          ${TOKEN_ENV}/"
proves judge_collect_token "a collect step without the token" "the collect step's env: does not set" \
  '/^ *FORSGREN_TOKEN: .*secrets\.FORSGREN_TOKEN/d'

# The collect step.
proves judge_collect_step "no collect step" "has no step '${COLLECT_STEP}'" \
  "s/- name: ${COLLECT_STEP}\$/- name: Collect something else/"
proves judge_collect_step "collect on another history" "the collect step runs 'forsgren collect --config forsgren.config.yml --data deployments.csv'" \
  's|--data data/deployments\.csv|--data deployments.csv|'
proves judge_collect_token "the token as an argument" "hands FORSGREN_TOKEN to forsgren in an argument" \
  "s|forsgren collect --config|forsgren collect --token \"${D}FORSGREN_TOKEN\" --config|"
proves judge_collect_step "the token dropped" "does not hand collect FORSGREN_TOKEN" \
  "/- name: ${COLLECT_STEP}/,/- name: ${DATA_STEP}/ s|^\\( *\\)status=0${D}|\\1unset FORSGREN_TOKEN\\n&|"
proves judge_collect_token "the token in a file" "leaves FORSGREN_TOKEN in a file of the checkout" \
  "/- name: ${COLLECT_STEP}/,/- name: ${DATA_STEP}/ s|^\\( *\\)status=0${D}|\\1printf '%s' \"${D}FORSGREN_TOKEN\" > .forsgren-token\\n&|"
proves judge_collect_token "the token echoed by collect's step" "the collect step shows FORSGREN_TOKEN in its log" \
  "/- name: ${COLLECT_STEP}/,/- name: ${DATA_STEP}/ s|^\\( *\\)status=0${D}|\\1echo \"collecting with ${D}{FORSGREN_TOKEN}\"\\n&|"
proves judge_collect_token "the token in an output" "writes FORSGREN_TOKEN to a step output" \
  "s|^\\( *\\)echo \"status=|\\1echo \"token=${D}{FORSGREN_TOKEN}\" >> \"${D}GITHUB_OUTPUT\"\\n&|"
proves judge_collect_step "a failing collect that stops the job" "for a collect that fails after storing the collect step gives 'exit=1" \
  's#\(--data data/deployments\.csv[^|]*\) || status=.*#\1#'
proves judge_collect_step "collect's status not recorded" "for a collect that fails after storing the collect step gives 'exit=0 output=state=1'" \
  's/echo "status=/echo "state=/'
proves judge_collect_e2e "a collect step that skips a missing token" "with the real forsgren, a configured repository and no FORSGREN_TOKEN" \
  "/- name: ${COLLECT_STEP}/,/- name: ${DATA_STEP}/ s|^\\( *\\)status=0${D}|\\1[[ -n \"${D}{FORSGREN_TOKEN:-}\" ]] \\|\\| exit 0\\n&|"
proves judge_collect_e2e "a collect step that demands a token" "with the real forsgren, the starter configuration (no projects) and no FORSGREN_TOKEN" \
  "/- name: ${COLLECT_STEP}/,/- name: ${DATA_STEP}/ s|^\\( *\\)status=0${D}|\\1: \"${D}{FORSGREN_TOKEN:?FORSGREN_TOKEN is not set}\"\\n&|"

# collect's output with workflow commands stopped (forsgren#12, step 8).
COLLECT_RANGE="/- name: ${COLLECT_STEP}/,/- name: ${DATA_STEP}/"
proves judge_collect_commands "collect's workflow commands left on" "for collect output with workflow commands in it the collect step leaves them live in the log (line " \
  "${COLLECT_RANGE} { /::stop-commands::/d; }"
proves judge_collect_commands "collect's commands never resumed" "never ended" \
  "${COLLECT_RANGE} { /echo \"::.{token}::\"/d; }"
proves judge_collect_commands "the same collect token on every run" "the collect step stops workflow commands with the same token on every run" \
  "${COLLECT_RANGE} s/^\\( *\\)token=.*${D}/\\1token=forsgren/"
proves judge_collect_commands "collect's stderr outside the stop" "leaves them live in the log (line 1:   ::add-mask::collect-mask)" \
  "${COLLECT_RANGE} s/ 2>&1)\" || status/)\" || status/"
proves judge_collect_commands "collect's output not shown" "does not show collect's output, stdout and stderr, in the log" \
  "${COLLECT_RANGE} { /printf .*${D}output/d; }"
proves judge_collect_commands_e2e "the real collect's message with commands on" "with the real forsgren and no FORSGREN_TOKEN the collect step logs collect's message live" \
  "${COLLECT_RANGE} { /::stop-commands::/d; }"

# The data step.
proves judge_data_step "no data step" "has no step '${DATA_STEP}'" \
  "s/- name: ${DATA_STEP}\$/- name: Commit something else/"
proves judge_data_step "data/ committed even when unchanged" "with data/ unchanged the data step gives" \
  "s|\\[\\[ -z \"${D}(git status --porcelain -- data/)\" \\]\\]|false|"
proves judge_data_step "the whole checkout committed with the data" "the data commit holds [data/commits.csv,data/deployments.csv,other.txt,staged.txt]" \
  "s|git add -- data/|git add -A|; s|'forsgren: record deployments' -- data/|'forsgren: record deployments'|"
proves judge_data_step "another data author" "for changed data/ the data commit's author is 'someone <" \
  "/- name: ${DATA_STEP}/,\$ s/GIT_AUTHOR_NAME='github-actions\\[bot\\]'/GIT_AUTHOR_NAME='someone'/"
proves judge_data_step "another data committer" "for changed data/ the data commit's committer is 'someone <" \
  "/- name: ${DATA_STEP}/,\$ s/GIT_COMMITTER_NAME='github-actions\\[bot\\]'/GIT_COMMITTER_NAME='someone'/"
proves judge_data_step "a data identity left to -c" "with an inherited outer identity the data commit's author is 'Outer Author <outer-author@example.com>'" \
  "/- name: ${DATA_STEP}/,\$ { /GIT_AUTHOR_NAME=/d; /GIT_COMMITTER_NAME=/d; s/git commit --quiet/git -c user.name=bot -c user.email=bot@example.com commit --quiet/; }"
proves judge_data_step "the data step's inherited config left alone" "with an outer identity and a signing config inherited from the environment the data step gives 'exit=128" \
  "/- name: ${DATA_STEP}/,\$ { /^ *GIT_CONFIG_COUNT=0 /d; }"
proves judge_data_step "another data message" "the data commit's message is 'forsgren: data'" \
  "s/'forsgren: record deployments'/'forsgren: data'/"
proves judge_data_step "no data push" "for changed data/ on its branch the data step gives 'exit=0 commits=1'" \
  '/push_log=/d'
proves judge_data_step "data pushed to a fixed branch" "for changed data/ on its branch the data step gives 'exit=0 commits=1'" \
  "/- name: ${DATA_STEP}/,\$ s|\"HEAD:${D}{GITHUB_REF}\"|\"HEAD:refs/heads/main\"|"
proves judge_data_step "data pushed from a tag" "for changed data/ on a ref that is not a branch (refs/tags/v1)" \
  "/- name: ${DATA_STEP}/,/git add --/ s/exit 1/exit 0/"
proves judge_data_step "the branch guard before the change check" "with data/ unchanged on a tag the data step gives" \
  "s|^\\( *\\)if \\[\\[ -z \"${D}(git status --porcelain -- data/)\" \\]\\]; then|\\1if [[ \"${D}GITHUB_REF\" != refs/heads/* ]]; then exit 1; fi\\n&|"
proves judge_data_token "the data token in an argument" "the data step hands the token to git in an argument" \
  "s|push_log=\"${D}(git push|push_log=\"${D}(git -c \"http.extraheader=AUTHORIZATION: basic ${D}{auth}\" push|"
proves judge_data_token "the data token stored in the checkout" "the data step leaves the token on disk in the checkout" \
  "s|^\\( *\\)push_log=|\\1git config http.extraheader \"AUTHORIZATION: basic ${D}{auth}\"\\n&|"
proves judge_data_token "the data token echoed" "the data step shows the token in its log" \
  "s|^\\( *\\)push_log=|\\1echo \"pushing with ${D}{GH_TOKEN}\"\\n&|"
proves judge_data_token "a data push without the header" "the data step's push carries" \
  "/- name: ${DATA_STEP}/,\$ s/\"AUTHORIZATION: basic /\"X-Other: basic /"
proves judge_data_moved "a forced data push" "the data step replaced the commit another pushed" \
  "s|push_log=\"${D}(git push --quiet|push_log=\"${D}(git push --force --quiet|"
proves judge_data_moved "a rebased data push" "with the branch moved since the checkout the data step gives 'exit=0 commits=3'" \
  "s|^\\( *\\)push_log=|\\1git -c user.name=x -c user.email=x@example.com pull --rebase --autostash --quiet origin \"${D}{GITHUB_REF}\"\\n&|"
proves judge_data_moved "a refused push without its cause" "does not name the cause in an ::error" \
  "s/${MOVED}/was refused/"

# The fail step, and the three steps in a row.
proves judge_fail_step "no fail step" "has no step '${FAIL_STEP}'" \
  "s/- name: ${FAIL_STEP}\$/- name: Fail something else/"
proves judge_fail_step "a fail step that never fails" "with COLLECT_STATUS=1 the fail step gives 'exit=0" \
  "/- name: ${FAIL_STEP}/,\$ s/exit 1/exit 0/"
proves judge_fail_step "a fail step that lets a missing status pass" "with COLLECT_STATUS= the fail step gives 'exit=0" \
  "s/if \\[\\[ \"${D}COLLECT_STATUS\" != 0 \\]\\]/if [[ -n \"${D}COLLECT_STATUS\" \\&\\& \"${D}COLLECT_STATUS\" != 0 ]]/"
proves judge_fail_step "the fail step on another status" "the fail step's COLLECT_STATUS is not" \
  's/steps\.collect\.outputs\.status/steps.collect.outcome/'
proves judge_fail_step "a collect step without its id" "the collect step has no id: collect" \
  '/^        id: collect$/d'
proves judge_fail_step "a failed collect that throws away what it stored" "when collect fails after storing, the data and fail steps give 'exit=0 commits=1 fail-step=1'" \
  "s|^\\( *\\)echo \"status=|\\1if [[ \"${D}status\" -ne 0 ]]; then rm -rf data; fi\\n&|"

# Concurrency.
proves judge_concurrency "no concurrency" "the job has no concurrency: block" \
  '/^    concurrency:$/,/^      cancel-in-progress:/d'
proves judge_concurrency "a concurrency group for every repository" "not keyed on" \
  's/^\(      group: \).*$/\1forsgren-metrics/'
proves judge_concurrency "a run that cancels the one in flight" "does not set cancel-in-progress: false" \
  's/cancel-in-progress: false/cancel-in-progress: true/'

# Whole steps removed or moved: the config step gone, the config step after
# render (just before "Upload the page"), the install step before setup-go.
proves_moved judge_config_step "a workflow without the config step" "has no step '${CHECK_STEP}'" "$CHECK_STEP"
proves_moved judge_order "the config check after render" "after it renders" "$CHECK_STEP" "Upload the page"
proves_moved judge_order "the starter after the config check" "writes the starter (line" "$INIT_STEP" "Render the page"
proves_moved judge_order "the starter before the checkout" "before checking out the caller's repository" "$INIT_STEP" "$CHECKOUT_STEP"
proves_moved judge_setup_go "the install step before setup-go" "after the install step" "$INSTALL_STEP" "Set up Go"
proves_moved judge_order "collect before the config check" "collects (line" "$COLLECT_STEP" "$CHECK_STEP"
proves_moved judge_order "the data commit before collect" "there is nothing to commit yet" "$DATA_STEP" "$COLLECT_STEP"
proves_moved judge_order "the data commit after render" "would drop what collect stored" "$DATA_STEP" "Upload the page"
proves_moved judge_order "the fail step before publishing" "before it publishes" "$FAIL_STEP" "$RENDER_STEP"
proves_moved judge_order "the needs step before the checkout" "before checking out the caller's repository" "$NEEDS_STEP" "$CHECKOUT_STEP"
proves_moved judge_order "the needs step before the config check" "before the config check" "$NEEDS_STEP" "$CHECK_STEP"
proves_moved judge_order "the needs step after the run summary" "after the run summary" "$NEEDS_STEP" "Upload the page"

selftest_end "metrics.yml is not the reusable workflow forsgren#4 rules" \
  "metrics.yml runs on workflow_call only, takes no input, installs forsgren from its own job.workflow_repository at its own job.workflow_sha (each checked before go runs, a fork installing itself), passes both through env: only, builds with go.mod's Go after setup-go, writes a new install's starter config with one commit as github-actions[bot] (token in the environment only) and renders with the config and the history, and checks the caller's config before render, with the real forsgren too, its message never run as a workflow command, then collects with FORSGREN_TOKEN in that one step's env only, its output never run as a workflow command, commits and pushes data/ alone (failing by name, never rebasing or forcing, when the branch moved), publishes, and fails the job at its end when collect failed, one run at a time per caller repository (and each wrong shape is still detected)"
