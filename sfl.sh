#!/usr/bin/env bash
# sfl.sh
# Ported from konenki-website's sfl.sh 2026-10-01 (forsgren#1, ladder step 1):
# a pure dispatcher over Scripts/gate_report_order.txt, run in two phases
# around the Go site build. Unit numbers below are the estate's history
# (web-infra, konenki-website), kept so the why can be found.
#
# Anchor to the repo regardless of where the script is invoked from — Yves runs
# ./forsgren/sfl.sh from ~/Sources, same as MenoPower's and web-infra's
# scripts, which all do this on their first line.
cd "$(dirname "$0")" || exit 1

# Bump VERSION on every meaningful change to THIS file (a new step, a widened
# check, a changed invocation). The banner below is how you confirm which sfl
# you actually ran - a stale number hides changed behavior. Editing a
# Scripts/*.sh that sfl merely calls does not require a bump.
# Form ported from web-infra 2026-08-31: it names the file, so a pasted log
# says which script produced it, not just "the script".
VERSION=1

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
# already been built. A pull that cannot fast-forward is a hard stop, never an
# auto-rebase — rewriting local commits is the person's decision, not sfl's.
# Exit 3 is reserved for this condition so FBP.sh can distinguish it later;
# FBP.sh does not handle that exit specially yet.
# Fixture: Scripts/test_sfl_pull.sh.
if [[ "$PHASE" == "pre" ]]; then
  echo
  echo "Pulling latest from remote..."
  # shellcheck source=Scripts/sfl_pull.sh
  source Scripts/sfl_pull.sh
  sfl_pull_or_stop || exit 3
fi

# The gates call go, git and the shell tools by name; Homebrew's prefixes go
# first so a GUI-launched shell finds them. The tool installer
# (Scripts/install_tools.sh + required_tools.txt) and the pinned npm linters
# arrive in later steps of the forsgren#1 ladder; until then a missing tool
# fails its gate with `command not found`, which the gate-failure summary
# quotes.
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

# Every gate here is CHECK-ONLY, the way CI will run it. The one local fix,
# gofmt -w, belongs to FBP.sh, which runs it before calling sfl (Yves's ruling
# on forsgren#1: auto-fix in FBP, check-only in CI).

FAIL=0
# Failing gate names, one per line. A plain string, not an array: an empty
# bash 3.2 array under `set -u` is a fatal expansion on macOS.
FAILED_GATES=""

# Runs one gate and remembers its name on failure, so the end of the run
# names WHAT failed — a bare "❌ sfl failed" forces reading the scroll-back
# (web-infra's FBP prints the same Errors: list).
# Unit 399. A secret-class failure is not an ordinary red. An ordinary red
# still commits locally, deliberately, so work in progress is not lost — but
# committing a SECRET puts it into git history, where removing it is a
# rewrite rather than an edit. Tracked separately; sfl exits 2, which
# FBP.sh reads as "do not commit at all".
SECRET_FAIL=0

run_gate_secret() {
  local before=$FAIL

  run_gate "$@"

  if [ "$FAIL" -ne "$before" ]; then
    SECRET_FAIL=$((SECRET_FAIL + 1))
  fi
}

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
# they start disagreeing. Same path web-infra uses.
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
# supplies the ORDER, SCRIPT, PHASE and — for the secret scan — CLASS.
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
while IFS='|' read -r label script phase gate_class || [ -n "${label:-}" ]; do
  case "$label" in
    \#*|'') continue ;;
  esac

  [ -n "${label:-}" ] || continue
  [ "${script:-}" = "n/a" ] && continue
  [ "${phase:-}" = "$PHASE" ] || continue

  if [ ! -x "$script" ]; then
    echo "❌ ${label} declares ${script}, which is not an executable script"
    FAIL=1
    FAILED_GATES="${FAILED_GATES}  ${label} ❌"$'\n'
    FAILED_GATES="${FAILED_GATES}    declared script is not executable: ${script}"$'\n'
    continue
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

  echo "❌ sfl ${PHASE} failed"
  exit 1
fi

echo "✅ sfl ${PHASE} green"
