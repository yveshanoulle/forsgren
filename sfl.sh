#!/usr/bin/env bash
# sfl.sh
# Ported from another estate repository's sfl.sh 2026-10-01 (forsgren#1, ladder step 1):
# a pure dispatcher over Scripts/gate_report_order.txt, run in two phases
# around the Go site build. Unit numbers below are the estate's history
# (another estate repository, another estate repository), kept so the why can be found.
#
# Anchor to the repo regardless of where the script is invoked from — Yves runs
# ./forsgren/sfl.sh from ~/Sources, same as another estate repository's and another estate repository's
# scripts, which all do this on their first line.
cd "$(dirname "$0")" || exit 1

# Bump VERSION on every meaningful change to THIS file (a new step, a widened
# check, a changed invocation). The banner below is how you confirm which sfl
# you actually ran - a stale number hides changed behavior. Editing a
# Scripts/*.sh that sfl merely calls does not require a bump.
# Form ported from another estate repository 2026-08-31: it names the file, so a pasted log
# says which script produced it, not just "the script".
VERSION=8

# forsgren#214: FBP.sh FIXES what the gates can fix (the npm audit heal runs
# only under GATE_FIX=1); CI never sets it and only checks.
export GATE_FIX=1

usage() {
  echo "Usage:"
  echo "  $0 pre    run PRE-BUILD quality gates"
  echo "  $0 post   run POST-BUILD quality gates"
}

PHASE="${1:-}"

if [[ "$PHASE" != "pre" && "$PHASE" != "post" ]]; then
  usage
  exit 2
fi

echo "sfl.sh v${VERSION} — ${PHASE} — Started at $(date '+%Y-%m-%d %H:%M:%S')"

# forsgren runs sfl in two phases around the build. Synchronise only before
# PRE: pulling again before POST could change the source after .build/site has
# already been built. A pull that cannot fast-forward rebases the local commits
# onto the upstream when the incoming commits touch none of the files of the
# local commits or of the staged, unstaged or untracked changes (staged stays
# staged), so the gates below run on the rebased tree (forsgren#283, step 2 of
# 2). Any overlap or failure is a hard stop, the local side left as it was.
# Exit 3 is reserved for this condition so FBP.sh can distinguish it later;
# FBP.sh does not handle that exit specially yet.
# Fixtures: Scripts/test_sfl_pull.sh, Scripts/test_sfl_pull_rebase.sh.
if [[ "$PHASE" == "pre" ]]; then
  echo
  echo "Pulling latest from remote..."
  # shellcheck source=Scripts/sfl_pull.sh
  source Scripts/sfl_pull.sh
  sfl_pull_or_stop || exit 3
fi

# The gates call go, git, npm and the shell tools by name; Homebrew's prefixes
# go first so a GUI-launched shell finds them.
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

# The tools the gates need that npm cannot pin, from Scripts/required_tools.txt.
# PRE-FLIGHT, before any gate: a gate whose tool is absent does not fail
# cleanly, it reports whatever `command not found` exits with inside a step
# that summarises its own exit code. Same script the rest of the estate uses;
# only the list differs. Fixture: Scripts/test_install_tools.sh.
./Scripts/install_tools.sh

# The Node pin: .nvmrc holds the major, and the node on PATH, which
# install_tools.sh may just have installed, must be it. Red with the fix
# command; Node cannot fetch its own version the way Go does. The same check
# is a PRE row. Fixtures: Scripts/test_node_pin.sh, Scripts/test_check_node_pin.sh.
./Scripts/check_node_pin.sh || exit 1

# Tooling mirrors another estate repository (forsgren#1, ladder step 7): the linters are
# pinned devDependencies in package.json + package-lock.json, installed into
# node_modules and invoked by path — NOT global installs and NOT `npx --yes`,
# which silently tracks whatever the registry publishes. One pinned version for
# CI and for here. `npm ci`, never `npm install`: it installs exactly the
# lockfile and fails when package.json and the lockfile disagree.
# AFTER install_tools.sh, unlike konenki where it runs before it: node comes
# from Scripts/required_tools.txt, so on a fresh machine npm exists only once
# the installer has run.
# Scripts/npm_sync_install.sh runs `npm ci` when node_modules is missing or was
# installed from another package-lock.json than the one in the tree (a stamp
# inside node_modules holds the lockfile's hash; forsgren#2). It replaces the
# check on node_modules/.bin/htmlhint and .bin/jscpd, which never noticed a
# lockfile change. A node_modules without the stamp is installed once more.
# Fixture: Scripts/test_npm_sync_install.sh.
./Scripts/npm_sync_install.sh || exit 1

# Pin Go exactly. go.mod's `toolchain` line is only a minimum (GOTOOLCHAIN=auto
# runs the newer of it and the local Go, and install_tools.sh may just have
# upgraded Go), so the version is exported from that line: one source of truth.
# Never `go env -w`, which writes machine-wide config. Fixture:
# Scripts/test_go_toolchain.sh.
if ! GOTOOLCHAIN="$(./Scripts/go_toolchain.sh)"; then
  exit 1
fi
export GOTOOLCHAIN

# The gates here are CHECK-ONLY, as CI runs them, with one exception: the npm
# audit row (Scripts/npm_audit_check.sh) may heal an advisory with one
# `npm audit fix`, and the lockfile change rides into the commit; CI turns
# that same heal into a red row. The other local fix, gofmt -w, belongs to
# FBP.sh, which runs it before calling sfl (Yves's ruling on forsgren#1:
# auto-fix in FBP, check-only in CI).

FAIL=0
# Failing gate names, one per line. A plain string, not an array: an empty
# bash 3.2 array under `set -u` is a fatal expansion on macOS.
FAILED_GATES=""
SKIPPED_GATES=0

# Runs one gate and remembers its name on failure, so the end of the run
# names WHAT failed — a bare "❌ sfl failed" forces reading the scroll-back
# (another estate repository's FBP prints the same Errors: list).
# Unit 399. A secret-class failure is not an ordinary red. An ordinary red
# still commits locally, deliberately, so work in progress is not lost — but
# committing a SECRET puts it into git history, where removing it is a
# rewrite rather than an edit. Tracked separately; sfl exits 2, which
# FBP.sh reads as "do not commit at all". forsgren has three secret-class
# rows: the secret scan; the data guard, whose installation data must not
# enter history either (Yves's ruling, 2026-10-02, forsgren#1 step 12.2);
# and the private names gate (forsgren#52), which alone handles private
# names: the data guard no longer does.
SECRET_FAIL=0

run_gate_secret() {
  local before=$FAIL

  run_gate "$@"

  if [ "$FAIL" -ne "$before" ]; then
    SECRET_FAIL=$((SECRET_FAIL + 1))
  fi
}

# forsgren#231, step 2: THE STATIC BLOCK. Scripts/gate_report_order.txt marks
# the fast static checks between two `#!` lines. When a row of the block is red
# sfl runs no further row of the phase: each is reported as skipped, by name,
# the summary says `stopped after the static block`, and the sentence is also
# written to STOP_SINK, which FBP.sh reads to skip the build and the POST gates
# the same way. CI (Scripts/run_ci_phase.sh) does not stop: it runs every row.
# Fixture: Scripts/test_sfl_static_block.sh.
BLOCK_FAIL_FROM=0
STOPPED=0
STOP_SENTENCE="stopped after the static block"
STOP_SINK=".build/sfl-static-stop.log"
rm -f "$STOP_SINK"

# forsgren#262, step 3 of 3: GATE SELECTION. A row whose label has `in` rows in
# Scripts/gate_inputs.txt (the four browser rows) is asked gate_select
# (Scripts/lib_gate_select.sh) before it runs. On `skip: <reason>` its script
# does not run: the step is counted, printed `⏭ skipped: <label> (<reason>)`,
# a `⏭ skip` row of the step table, and `<label><TAB><reason>` is appended to
# SKIPS_SINK, which pre empties and post appends to (forsgren#266 reads it).
# CI (Scripts/run_ci_phase.sh) does not select: Quality runs every row.
# Fixture: Scripts/test_sfl_gate_skip.sh.
# shellcheck source=Scripts/lib_gate_select.sh
source Scripts/lib_gate_select.sh
GATE_INPUTS="Scripts/gate_inputs.txt"
SKIPS_SINK=".build/sfl-skips.log"
mkdir -p .build
if [[ "$PHASE" == "pre" ]]; then
  : > "$SKIPS_SINK"
fi

# Unit 404. Each gate's output is teed to a log so the block at the end can
# quote the REASON, not just the name. Naming the gate was never enough: it
# says WHICH one, and the why stays up the log among every passing gate.
GATE_LOG_DIR="$(mktemp -d)"
GATE_N=0

# Unit 405. One row per gate, in execution order, for the end-of-run table.
# A FILE rather than parallel arrays: bash 3.2 is the shell here, and an empty
# array expanded under `set -u` is a fatal error on macOS — the trap that has
# bitten this estate twice. A file is also what render_step_table.sh takes, so
# nothing has to be marshalled at the end.
STEP=0

# Count only gates belonging to the requested phase. +1 is the sfl-internal
# step-count self-check that always runs last.
PHASE_GATE_COUNT="$(
  awk -F'|' -v phase="$PHASE" '
    $0 !~ /^#/ && NF >= 3 && $3 == phase && $2 != "n/a" {
      count++
    }

    END {
      print count + 0
    }
  ' Scripts/gate_report_order.txt
)"
TOTAL_STEPS=$((PHASE_GATE_COUNT + 1))

STEP_ROWS="${GATE_LOG_DIR}/steps.tsv"
: > "$STEP_ROWS"

# Unit 407. Counts sink for FBP.sh's one-line summary, which read
# `sfl ✅ (11s)` — a glyph and a duration. Written by render_step_table.sh from
# its own rows, never recounted here: two places counting the same gates is how
# they start disagreeing. Same path another estate repository uses.
mkdir -p .build
SFL_COUNTS_FILE=".build/sfl-counts.log"
: > "$SFL_COUNTS_FILE"
START=$SECONDS

trap 'rm -rf "${GATE_LOG_DIR}"' EXIT

run_gate() {
  local name="$1"
  shift

  STEP=$((STEP + 1))
  echo
  printf '[%d/%d] ==> %s\n' "$STEP" "$TOTAL_STEPS" "$name"

  # Declared BEFORE the pipeline: any command between it and PIPESTATUS resets
  # it, and `local` is a command.
  local log rc t0
  GATE_N=$((GATE_N + 1))
  log="${GATE_LOG_DIR}/gate_${GATE_N}.log"
  t0=$SECONDS

  "$@" 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}

  if [ "$rc" -ne 0 ]; then
    FAIL=1
    FAILED_GATES="${FAILED_GATES}  ${name} ❌"$'\n'
    FAILED_GATES="${FAILED_GATES}$(./Scripts/summarize_gate_failure.sh "$log")"$'\n'
    printf '%s\t%s\t%s\n' "$name" "❌ FAIL" "$((SECONDS - t0))" >> "$STEP_ROWS"
  else
    printf '%s\t%s\t%s\n' "$name" "✅ pass" "$((SECONDS - t0))" >> "$STEP_ROWS"
  fi
}

# skip_step <label> <reason>: a row that is not run, still counted, named and
# a row of the step table.
skip_step() {
  STEP=$((STEP + 1))
  printf '[%d/%d] ==> %s\n' "$STEP" "$TOTAL_STEPS" "$1"
  echo "⏭ skipped: $1 ($2)"
  printf '%s\t%s\t%s\n' "$1" "⏭ skip" "0" >> "$STEP_ROWS"
}

# sfl-INTERNAL steps: counted in the progress counter and shown in the table,
# but NOT estate gates. gate_report_order.txt declares the gates the estate
# compares across its repos and the CI report renders from it; sfl's own
# arithmetic self-check belongs in neither. Declaring it there would put a row
# in the CI report that no CI step can ever fill, so every run would report one
# gate short and warn "unmeasured".
#
# Forwarding "$@" rather than naming a label is exactly what run_gate_secret
# above already does. test_sfl_drives_from_order_file.sh fails the build when a run_gate call
# names a label literally (a quoted argument starting with a letter); the
# forwarded "$@" passes that check only because `$` is not a letter, and the
# literal label at the run_step call site below passes because it is not a
# run_gate call.
run_step() {
  run_gate "$@"
}

# Last step, always: the expected total is derived from the canonical order
# file for the selected phase. The self-check proves execution and declaration
# still agree.
check_step_total() {
  # run_gate has already counted THIS step before invoking us, so $STEP is the
  # final total and needs no adjustment.
  if [ "$STEP" -ne "$TOTAL_STEPS" ]; then
    echo "❌ TOTAL_STEPS=${TOTAL_STEPS} but this run executed ${STEP} steps"
    return 1
  fi

  echo "OK: TOTAL_STEPS=${TOTAL_STEPS} matches the ${STEP} steps executed"
}

# --- THE GATES ------------------------------------------------------------
#
# Every gate is dispatched from Scripts/gate_report_order.txt. The file
# supplies the ORDER, SCRIPT, PHASE and — for the secret scan and the data
# guard — CLASS.
#
# Field 3 is the phase:
#   pre  = repository/source/checker gates before the site build
#   post = generated/deployable-site gates after the site build
#
# Field 4 carries the class. `secret-class` routes through run_gate_secret,
# which makes sfl exit 2 so FBP.sh refuses to commit at all.
#
# `read` returns non-zero when it reaches EOF without a trailing newline, even
# though it has populated the fields from that final line. The second condition
# keeps that final declared gate executable instead of silently dropping it.
while IFS='|' read -r label script phase gate_class || [ -n "${label:-}${script:-}" ]; do
  # The block markers (forsgren#231): comments to every other reader.
  case "$label" in
    "#! static-block-start")
      BLOCK_FAIL_FROM=$FAIL
      continue
      ;;
    "#! static-block-end")
      if [ "$FAIL" -ne "$BLOCK_FAIL_FROM" ]; then
        STOPPED=1
        echo
        echo "❌ The static block is red: ${STOP_SENTENCE}. The later gates of this phase are skipped, named below."
      fi
      continue
      ;;
  esac
  case "$label" in
    \#*) continue ;;
    '') [ -z "${script:-}${phase:-}${gate_class:-}" ] && continue ;;
  esac
  [ "${script:-}" = "n/a" ] && continue

  # Validate the row before the phase filter: a row that fits no phase must be
  # red, not invisible. The same rules as Scripts/run_ci_phase.sh, which
  # Scripts/test_gate_wiring.sh pins line for line.
  bad=""
  if [ -z "${label:-}" ]; then
    label="(row with no label)"
    bad="the row has no label"
  elif [ -z "${script:-}" ]; then
    bad="the row names no script"
  else
    case "$script" in
      Scripts/*.sh) ;;
      *) bad="its script ${script} is not a Scripts/<name>.sh path" ;;
    esac
    case "$script" in
      *..*|*[!A-Za-z0-9_./-]*) bad="its script ${script} is not a plain Scripts/<name>.sh path" ;;
    esac
  fi
  if [ -z "$bad" ]; then
    case "${phase:-}" in
      pre|post) ;;
      *) bad="its phase '${phase:-}' is neither pre nor post, so no phase would ever run it" ;;
    esac
    case "${gate_class:-}" in
      ''|empty|secret-class) ;;
      *) bad="its class '${gate_class:-}' is neither empty nor secret-class" ;;
    esac
  fi
  if [ -z "$bad" ]; then
    [ "$phase" = "$PHASE" ] || continue
  fi

  if [ -n "$bad" ]; then
    echo "❌ ${label} is a malformed row of Scripts/gate_report_order.txt: ${bad}"
    FAIL=1
    FAILED_GATES="${FAILED_GATES}  ${label} ❌"$'\n'
    FAILED_GATES="${FAILED_GATES}    malformed order-file row: ${bad}"$'\n'
    continue
  fi

  if [ ! -e "$script" ]; then
    echo "❌ ${label} declares ${script}, which does not exist"
    FAIL=1
    FAILED_GATES="${FAILED_GATES}  ${label} ❌"$'\n'
    FAILED_GATES="${FAILED_GATES}    declared script does not exist: ${script}"$'\n'
    continue
  fi

  if [ ! -x "$script" ]; then
    echo "❌ ${label} declares ${script}, which is not an executable script"
    FAIL=1
    FAILED_GATES="${FAILED_GATES}  ${label} ❌"$'\n'
    FAILED_GATES="${FAILED_GATES}    declared script is not executable: ${script}"$'\n'
    continue
  fi

  if [ "$STOPPED" -eq 1 ]; then
    SKIPPED_GATES=$((SKIPPED_GATES + 1))
    skip_step "$label" "$STOP_SENTENCE"
    continue
  fi

  if [[ -n "$(gate_input_rows "$GATE_INPUTS" "$label" in)" ]]; then
    selected="$(gate_select "$label")"
    if [[ "$selected" == skip:* ]]; then
      skip_step "$label" "${selected#skip: }"
      printf '%s\t%s\n' "$label" "${selected#skip: }" >> "$SKIPS_SINK"
      continue
    fi
    echo
    echo "▶ selected: ${label} (${selected#run: })"
  fi

  if [ "${gate_class:-}" = "secret-class" ]; then
    run_gate_secret "$label" "./$script"
  else
    run_gate "$label" "./$script"
  fi
done < Scripts/gate_report_order.txt

run_step "step-count self-check (TOTAL_STEPS)" check_step_total

./Scripts/render_step_table.sh \
  "$STEP_ROWS" \
  "$((SECONDS - START))" \
  "$SFL_COUNTS_FILE"

echo

if [[ $FAIL -ne 0 ]]; then
  echo "Errors:"
  printf '%s' "$FAILED_GATES"

  if [[ $SECRET_FAIL -ne 0 ]]; then
    echo "⛔ sfl failed with a SECRET-CLASS finding — exit 2, commit will be blocked"
    exit 2
  fi

  if [ "$STOPPED" -eq 1 ]; then
    mkdir -p .build
    echo "${STOP_SENTENCE}: ${SKIPPED_GATES} gate(s) skipped" > "$STOP_SINK"
    echo "❌ sfl ${PHASE} failed, ${STOP_SENTENCE} (${SKIPPED_GATES} later gate(s) skipped, named above)"
    exit 1
  fi

  echo "❌ sfl ${PHASE} failed"
  exit 1
fi

echo "✅ sfl ${PHASE} green"
