#!/usr/bin/env bash
# canon: test_gate_wiring v15
# Scripts/test_gate_wiring.sh
#
# v15 (estate issue 850): one text in every repository of the estate. What
#   differs per repository (its exemption arms, its own pins and their mutation
#   proofs, the files only its proofs replace) lives in the repository's own
#   Scripts/gate_wiring_local_cases.sh, which this file sources and requires;
#   the floor stays in Scripts/gate_wiring_floor.txt. Shared: the fixture loop,
#   the script loop and its default verdict, the Node pin, the GATE_FIX pin,
#   the gate count ratchet, the mutation proof engine (a proof names the text
#   its mutant must keep) and the matcher self-proof; the baseline steps pin
#   is a function the local cases call where the workflow has those steps.
# v14: MIN_GATES and the history of its raises live in the per-repository data
#   file Scripts/gate_wiring_floor.txt; a missing file, no value, 0, a value
#   that is no whole number or two value lines are red (fail closed); three
#   more mutation proofs (the file ignored, a missing file passing, comment
#   lines counted).
# v13: the gate count is red below MIN_GATES, green at it, and green above it
#   with the warning "Raise MIN_GATES from X to Y" (a `⚠️ warn: ` line and a
#   warning annotation on the CI run's summary page); the removed-gate
#   self-proof shrinks the order file to one row under the floor.
# v12, v11: a sourced helper of one self-test is exempt only when that
#   self-test sources it by name (now arms of the local cases).

set -euo pipefail

cd "$(dirname "$0")/.."

# Every gate must be wired into BOTH runners, sfl.sh and CI — the sfl/CI
# parity guard (unit 396, rewritten by estate issue 301 step 3-9).
#
# sfl.sh dispatches every gate from Scripts/gate_report_order.txt, and CI runs
# the same file through Scripts/run_ci_phase.sh, phase by phase, so a gate
# declared there runs in both runners with no second registration. What this
# check pins:
#   - every fixture (Scripts/test_*.sh) is declared in the order file, unless
#     the local cases say why it is not;
#   - every other Scripts/*.sh is either declared there, or a declared
#     exemption of the local cases, each with its reason and the runner or
#     consumer it must still be invoked by (a validator nobody invokes is a
#     file, not a gate);
#   - the pins below and the local cases' own pins on the runners themselves.
#
# Matching is on `Scripts/<name>` and NOT on the bare basename: every gate's
# name is a substring of its own fixture's name (`check_actionlint.sh` inside
# `test_check_actionlint.sh`), so a basename search would report a gate as
# wired when only its fixture was.
#
# Only a word that RUNS something counts as an invocation (runs_script, the
# estate's issues 13, 15 and 18): the script must stand where a command
# stands, so a script that is only mentioned (in a comment, an echo, a YAML
# name: or as another command's argument) is not wired. runs_script lives in
# Scripts/lib_runs_script.sh; its header lists what it models. After its
# verdicts on the real runners, the matcher self-proof near the end of this
# file feeds it sample files.

# The runner paths are overridable ONLY so the mutation proofs near the end of
# this file can re-run this whole check against a mutated copy of sfl.sh,
# FBP.sh, quality.yml or the order file (the local cases may add files of
# their own). Nothing else sets them; sfl and CI always run against the real
# files.
SFL="${GATE_WIRING_SFL_OVERRIDE:-sfl.sh}"
FULL_BUILD="${GATE_WIRING_FBP_OVERRIDE:-FBP.sh}"
CI="${GATE_WIRING_CI_OVERRIDE:-.github/workflows/quality.yml}"
ORDER="${GATE_WIRING_ORDER_OVERRIDE:-Scripts/gate_report_order.txt}"
# This repository's own arms and pins (see the header).
LOCAL_CASES="Scripts/gate_wiring_local_cases.sh"

# is_mutation_rerun: this run is a proof re-running the check with one of
# the files above replaced, so it must not start proofs of its own.
is_mutation_rerun() {
  [[ -n "${GATE_WIRING_CI_OVERRIDE:-}${GATE_WIRING_FBP_OVERRIDE:-}${GATE_WIRING_SFL_OVERRIDE:-}${GATE_WIRING_ORDER_OVERRIDE:-}" ]] \
    || gate_wiring_local_is_rerun
}

COMPLETED=0

finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: gate wiring check aborted before completing" >&2
    exit 1
  fi
}

trap finish EXIT

failed=0

fail() {
  echo "❌ FAIL: $*"
  failed=1
}

for f in "$SFL" "$FULL_BUILD" "$CI" "$ORDER"; do
  [[ -f "$f" ]] || {
    echo "❌ FAIL: $f not found" >&2
    exit 1
  }
done

# runs_script <file> <script>: defined once, in the sourced helper.
# shellcheck source=Scripts/lib_runs_script.sh
source Scripts/lib_runs_script.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
# Temp folders and files through Scripts/lib_tmp.sh (estate issue 536).
# shellcheck source=Scripts/lib_tmp.sh
source Scripts/lib_tmp.sh
# The local cases' pins may name sandbox gates by label, so this file counts as
# git-using for the git sandbox guard; an exported GIT_DIR must not reach it.
# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

# sfl_runs <script-basename> (also order_names): an order-file row names
# Scripts/<basename>. sfl's invocation list IS the order file (unit 409 step
# 3), and CI's loop reads the same file.
sfl_runs() {
  grep -qxF "Scripts/$1" <<< "$(grep -v '^#' "$ORDER" | cut -d'|' -f2)"
}
order_names() {
  sfl_runs "$1"
}

# require_fixture <script> [consequence]: an exempted script that must still
# carry its own Scripts/test_<script>. The consequence, when given, follows
# the fail line after a dash.
require_fixture() {
  [[ -f "Scripts/test_$1" ]] \
    || fail "${1} has no Scripts/test_${1}${2:+ — $2}"
}

# The local cases define, and this file calls:
#   gate_wiring_local_is_rerun        a file only they override is replaced
#   gate_wiring_local_original <var>  prints the file their override <var>
#                                     replaces (none: nothing, status 1)
#   gate_wiring_local_fixture <base>  status 0 when they judged that fixture
#                                     themselves, 1 for the default (a row)
#   gate_wiring_local_script <base>   status 0 when <base> is a declared
#                                     exemption they judged, 1 for the
#                                     default (a row, else red)
#   gate_wiring_local_pins            their pins, after both loops
#   gate_wiring_local_proofs          their mutation proofs (top level only)
if [[ ! -f "$LOCAL_CASES" ]]; then
  echo "❌ FAIL: ${LOCAL_CASES} is missing — this repository's exemption arms and pins have no home, so the check cannot judge its scripts" >&2
  exit 1
fi
# shellcheck source=Scripts/gate_wiring_local_cases.sh
source "$LOCAL_CASES"

# --- The fixtures ----------------------------------------------------------
#
# CI runs a fixture through run_ci_phase.sh, which reads the same order file; a
# fixture declared there is therefore run by both runners.
n_fixture=0
for path in Scripts/test_*.sh; do
  [[ -f "$path" ]] || continue
  base="$(basename "$path")"
  n_fixture=$((n_fixture + 1))
  gate_wiring_local_fixture "$base" && continue
  sfl_runs "$base" \
    || fail "${base} is not declared in ${ORDER}, which is what sfl runs and what CI's loop runs — it passes nowhere but the file system"
done

if [[ "$n_fixture" -eq 0 ]]; then
  fail "no Scripts/test_*.sh matched — the glob is broken, so this check verified nothing"
fi

# --- The scripts outside the fixtures ----------------------------------------
#
# DECLARED EXEMPTIONS are the local cases' arms. Each names WHY, so the list
# reads as decisions rather than as the check being worn down, and each names
# the runner or consumer the script must still be invoked by. Anything that is
# neither declared nor exempt is a validator nobody runs.
n_gate=0
n_exempt=0
for path in Scripts/*.sh; do
  base="$(basename "$path")"
  case "$base" in
    test_*) continue ;;
  esac

  # THIS FILE'S OWN DATA, not a gate: the local cases are sourced by this
  # check, by the name it holds, and never run alone.
  if [[ "$base" == "$(basename "$LOCAL_CASES")" ]]; then
    n_exempt=$((n_exempt + 1))
    grep -qxF "LOCAL_CASES=\"Scripts/${base}\"" Scripts/test_gate_wiring.sh \
      || fail "${base} holds this repository's arms and pins and Scripts/test_gate_wiring.sh never names it — a library nobody uses is a file"
    continue
  fi

  if gate_wiring_local_script "$base"; then
    n_exempt=$((n_exempt + 1))
    continue
  fi

  n_gate=$((n_gate + 1))
  sfl_runs "$base" \
    || fail "${base} is a script no order-file row names and no declared exemption covers — a validator nobody runs is a file, not a gate"
done

if [[ "$n_gate" -eq 0 ]]; then
  fail "no Scripts/*.sh is named by an order-file row — the glob or the parse is broken, so this check verified nothing"
fi

# --- The order file and the CI loop ------------------------------------------
#
# The one property kept from the retired label comparison (unit 409 step 3):
# sfl dispatches every gate FROM the file, so a literal label at a call site
# would decide that gate's position outside it.
# Scripts/test_sfl_drives_from_order_file.sh pins the rest.
if grep -qE 'run_gate[a-z_]* "[A-Za-z]' "$SFL"; then
  fail "sfl.sh has gone back to naming a gate label literally — its position would then be decided at the call site rather than by ${ORDER}, which is the drift this check used to detect after the fact and unit 409 removed the possibility of"
fi
# CI reads the order file through the loop the local cases' pins require of
# quality.yml.
grep -qF 'gate_report_order.txt' Scripts/run_ci_phase.sh \
  || fail "Scripts/run_ci_phase.sh does not read gate_report_order.txt — CI would report a different order from sfl"

# --- The Node pin in sfl's pre-flight (estate issue 301 step 3-25) -----------
#
# The Node pin runs in sfl's pre-flight, after install_tools.sh (which may
# install Node) and before npm_sync_install.sh (whose stamp records the Node
# major). check_node_pin.sh is also a PRE row, but the pre-flight call is what
# makes the install step see a wrong Node first, so it is pinned here.
sfl_node_pin_problems() {
  local file="$1" install pin sync
  install="$(grep -nE '^\./Scripts/install_tools\.sh' "$file" | head -n 1 | cut -d: -f1 || true)"
  pin="$(grep -nE '^\./Scripts/check_node_pin\.sh' "$file" | head -n 1 | cut -d: -f1 || true)"
  sync="$(grep -nE '^\./Scripts/npm_sync_install\.sh' "$file" | head -n 1 | cut -d: -f1 || true)"
  if [[ -z "$pin" ]]; then echo "sfl.sh never runs Scripts/check_node_pin.sh"; return; fi
  if [[ -z "$install" || "$pin" -le "$install" ]]; then echo "sfl.sh runs check_node_pin.sh before install_tools.sh"; fi
  if [[ -z "$sync" || "$pin" -ge "$sync" ]]; then echo "sfl.sh runs check_node_pin.sh after npm_sync_install.sh"; fi
}
problems="$(sfl_node_pin_problems "$SFL")"
[[ -z "$problems" ]] || fail "sfl.sh's Node pin call is misplaced: ${problems}"
_t="$(tmp_dir test_gate_wiring)" || exit 1
sed -E 's#^\./Scripts/check_node_pin\.sh.*$#: skipped#' "$SFL" > "${_t}/nopin.sh"
awk '/^\.\/Scripts\/check_node_pin\.sh/ { next } { print } /^\.\/Scripts\/npm_sync_install\.sh/ { print "./Scripts/check_node_pin.sh || exit 1" }' "$SFL" > "${_t}/late.sh"
cmp -s "$SFL" "${_t}/nopin.sh" && fail "the no-node-pin mutation changed nothing — the Node pin check matches something other than the call"
grep -qF 'never runs Scripts/check_node_pin.sh' <<< "$(sfl_node_pin_problems "${_t}/nopin.sh")" \
  || fail "an sfl.sh without the Node pin call was accepted — the Node pin check does not guard it"
grep -qF 'after npm_sync_install.sh' <<< "$(sfl_node_pin_problems "${_t}/late.sh")" \
  || fail "an sfl.sh running the Node pin after the npm install was accepted — the Node pin check does not guard the order"
rm -rf "$_t"

# --- The baselines on the run page (estate issue 300) ------------------------
#
# Called by the local cases of a repository whose Quality run shows the
# baselines: one step per gate, each by name, each `if: always()` (so it shows
# when a gate is red), each calling Scripts/report_baselines.sh with its own
# section: Language baselines, Browser baselines, Image baselines.
baseline_step_problems() {
  local wf="$1" pair name arg block
  for pair in "Language baselines:language" "Browser baselines:browser" "Image baselines:image"; do
    name="${pair%%:*}"
    arg="${pair##*:}"
    block="$(awk -v n="      - name: ${name}" '
      $0 == n { on = 1; print; next }
      on && /^      - / { exit }
      on { print }
    ' "$wf")"
    if [[ -z "$block" ]]; then
      echo "the workflow has no step named '${name}'"
      continue
    fi
    grep -qE '^[[:space:]]+if: always\(\)[[:space:]]*$' <<< "$block" \
      || echo "the step '${name}' is not 'if: always()', so it would vanish when a gate is red"
    grep -qE "^[[:space:]]*\./Scripts/report_baselines\.sh ${arg}[[:space:]]*$" <<< "$(grep -vE '^[[:space:]]*#' <<< "$block")" \
      || echo "the step '${name}' does not run ./Scripts/report_baselines.sh ${arg}"
  done
}
# baseline_step_pin: the pin on quality.yml, and, at the top level, its
# mutation proofs.
baseline_step_pin() {
  local problems _t
  problems="$(baseline_step_problems "$CI")"
  [[ -z "$problems" ]] || fail "quality.yml must show the baselines, one step per gate: ${problems}"
  is_mutation_rerun && return 0
  _t="$(tmp_dir test_gate_wiring)" || exit 1
  sed -E 's#^      - name: Browser baselines$#      - name: Browser baselines (renamed)#' "$CI" > "${_t}/renamed.yml"
  sed -E '/name: Image baselines/,$ s#^        if: always\(\)$#        if: success()#' "$CI" > "${_t}/notalways.yml"
  sed -E 's#^( *)\./Scripts/report_baselines\.sh language$#\1: report_baselines.sh language#' "$CI" > "${_t}/nocall.yml"
  cmp -s "$CI" "${_t}/renamed.yml" && fail "the renamed-step mutation changed nothing — the baseline steps pin matches something other than the step names"
  cmp -s "$CI" "${_t}/notalways.yml" && fail "the not-always mutation changed nothing — the baseline steps pin matches something other than the condition"
  cmp -s "$CI" "${_t}/nocall.yml" && fail "the no-call mutation changed nothing — the baseline steps pin matches something other than the call"
  grep -qF "no step named 'Browser baselines'" <<< "$(baseline_step_problems "${_t}/renamed.yml")" \
    || fail "a quality.yml without the Browser baselines step was accepted — the baseline steps pin does not guard the step names"
  grep -qF "'Image baselines' is not 'if: always()'" <<< "$(baseline_step_problems "${_t}/notalways.yml")" \
    || fail "a quality.yml whose Image baselines step is not always() was accepted — the baseline steps pin does not guard the condition"
  grep -qF "does not run ./Scripts/report_baselines.sh language" <<< "$(baseline_step_problems "${_t}/nocall.yml")" \
    || fail "a quality.yml whose Language baselines step does not call the report was accepted — the baseline steps pin does not guard the call"
  rm -rf "$_t"
}

# --- This repository's own pins ----------------------------------------------
gate_wiring_local_pins

# --- FBP FIXES, CI ONLY CHECKS (estate issue 301 step 3-5) -------------------
#
# sfl.sh exports GATE_FIX=1 (the gates that can fix, fix under it); no workflow
# may set it, or CI would change files instead of reporting what the commit
# contains. Mutations built here: an sfl.sh without the export, and a workflow
# copy that mentions GATE_FIX, must each be rejected. Not re-run inside a
# mutation rerun, where sfl.sh is a deliberately mutated copy.
fix_wiring_problems() {
  local sfl="$1" wf="$2"
  grep -qE '^export GATE_FIX=1$' "$sfl" || echo "sfl.sh does not export GATE_FIX=1"
  if grep -rqF 'GATE_FIX' "$wf"; then echo "a workflow mentions GATE_FIX"; fi
}
if ! is_mutation_rerun; then
  WF_DIR=".github/workflows"
  problems="$(fix_wiring_problems "$SFL" "$WF_DIR")"
  [[ -z "$problems" ]] || fail "FBP must fix and CI only check: ${problems}"
  _t="$(tmp_dir test_gate_wiring)" || exit 1
  grep -v '^export GATE_FIX=1$' "$SFL" > "${_t}/sfl.sh"
  mkdir -p "${_t}/wf"
  cp "$WF_DIR"/*.yml "${_t}/wf/"
  printf '# GATE_FIX=1\n' >> "${_t}/wf/quality.yml"
  if cmp -s "$SFL" "${_t}/sfl.sh"; then
    fail "the no-export mutation changed nothing — the GATE_FIX pin matches something other than the export line"
  elif ! grep -qF 'does not export' <<< "$(fix_wiring_problems "${_t}/sfl.sh" "$WF_DIR")"; then
    fail "an sfl.sh without the GATE_FIX export was accepted — the GATE_FIX pin does not guard it"
  fi
  if ! grep -qF 'a workflow mentions' <<< "$(fix_wiring_problems "$SFL" "${_t}/wf")"; then
    fail "a workflow that mentions GATE_FIX was accepted — the GATE_FIX pin does not guard CI staying check-only"
  fi
  rm -rf "$_t"
fi

# --- The gate count is a RATCHET: gates go up, never down --------------------
#
# THE VERDICT (canon v13, the ruling on decision 81):
#   below MIN_GATES  red: a gate was removed;
#   equal            green;
#   above            green, with the warning "Raise MIN_GATES from X to Y",
#                    Y the counted rows: in CI a warning annotation, which the
#                    run's summary page lists, and a `⚠️ warn: ` line in the
#                    gate's output (a warn row where sfl.sh has one). The
#                    warning never fails the run.
# Why an annotation and not a line this check appends to $GITHUB_STEP_SUMMARY:
# the step summary isolation gate runs this check (it names the summary
# renderers) with the summary pointed at a decoy that must stay empty, so a
# line written here would turn that gate red exactly when this one warns.
# Raising MIN_GATES to the counted rows is routine and belongs in the change
# that adds the gates; lowering it needs an explicit yes. A MIN_GATES that is
# not a positive whole number is red: a floor of 0 or of nothing measures
# nothing.
#
# THE FLOOR FILE (canon v14, the 9 Nov part of the ruling on decision 81): each
# repository keeps its MIN_GATES, and the history of its raises, in
# Scripts/gate_wiring_floor.txt, so this file carries no repository value. The
# value is the one line of that file that is neither blank nor a comment,
# spaces around it ignored. A missing file is red, and so is a value that is
# no positive whole number: none, 0, text, or two value lines. It fails closed.
#
# Yves, 2026-08-31: "so that gates can not go down, only up". Same rule as the
# coverage ratchet and the duplication ceiling: raise MIN_GATES whenever a row
# lands, never lower it to make a red go away. It counts the rows of the order
# file that are not comments (n/a rows included: a declared absence is a row).
# It counts rather than pinning the list, deliberately: swapping one gate for
# another keeps the count and passes; the named arms and the estate's
# gate-parity axis catch that from outside, because the removed one reappears
# as missing against the canon.
#
# Until canon v13 the self-proof below removed one row and required the count
# to fall under the floor, so the floor had to track the count exactly. Since
# v13 it shrinks the file to one row under the floor, and a count above the
# floor is green with the warning to raise it.
GATE_FLOOR_FILE="Scripts/gate_wiring_floor.txt"

gate_count_of() {
  grep -v '^#' "$1" | grep -c . || true
}

# The five functions between the FLOOR VERDICT markers are the verdict; the
# mutation proofs below copy this block out of this file, change one thing and
# run the cases against the copy.
# FLOOR VERDICT BEGIN
# gate_floor_verdict <counted> <floor> [<where>]: prints the verdict line, if
# there is one, and fails only when the count is red. <where> names the floor
# in the bad-floor line (default MIN_GATES).
gate_floor_verdict() {
  local counted="$1" floor="$2" where="${3:-MIN_GATES}"
  if [[ ! "$floor" =~ ^[1-9][0-9]*$ ]]; then
    echo "${where} is '${floor}', not a positive whole number — a floor that is missing, empty or 0 measures nothing"
    return 1
  fi
  if [[ "$counted" -lt "$floor" ]]; then
    echo "gate count fell to ${counted}, ratchet is ${floor} — a gate was removed. Restore it; lowering MIN_GATES needs an explicit yes, also when a gate was legitimately merged into another"
    return 1
  fi
  if [[ "$counted" -gt "$floor" ]]; then
    echo "Raise MIN_GATES from ${floor} to ${counted}"
  fi
  return 0
}

# gate_floor_warn <text>: the warning where each runner shows it: a
# `⚠️ warn: ` line in the gate's output, and the `::warning` line, which the
# CI runner (Scripts/run_ci_phase.sh prints every gate's output) turns into an
# annotation on the run's summary page.
gate_floor_warn() {
  echo "⚠️ warn: $1"
  echo "::warning title=gate wiring::$1"
}

# gate_floor_check <counted> <floor> [<where>]: the verdict and its output. Red
# below the floor and on a floor that is no positive whole number; a warning is
# green.
gate_floor_check() {
  local verdict rc=0
  verdict="$(gate_floor_verdict "$1" "$2" "${3:-MIN_GATES}")" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "❌ FAIL: ${verdict}"
    return 1
  fi
  [[ -n "$verdict" ]] || return 0
  gate_floor_warn "$verdict"; return 0
}

# gate_floor_of <file>: prints the floor the file declares: its lines that are
# neither blank nor a comment, spaces around each trimmed, joined by a space,
# so two value lines print a value no floor check accepts. Prints nothing for
# a file without a value line.
gate_floor_of() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | { grep -v -e '^#' -e '^$' || true; } | paste -sd ' ' -
}

# gate_floor_from_file <counted> <file>: the verdict with the floor read from
# the floor file; a missing file is red.
gate_floor_from_file() {
  if [[ ! -f "$2" ]]; then
    echo "❌ FAIL: the floor file $2 is missing — MIN_GATES has no value, so the gate count measures nothing"; return 1
  fi
  gate_floor_check "$1" "$(gate_floor_of "$2")" "MIN_GATES in $2"
}
# FLOOR VERDICT END

declared="$(gate_count_of "$ORDER")"
gate_floor_from_file "$declared" "$GATE_FLOOR_FILE" || failed=1
MIN_GATES=""
if [[ -f "$GATE_FLOOR_FILE" ]]; then
  MIN_GATES="$(gate_floor_of "$GATE_FLOOR_FILE")"
fi

# Self-proof: the same verdict, against a copy of the order file shrunk to
# one row under the floor, MUST be red. Without this the ratchet would pass
# the moment it stopped reading the file, and could never be shown failing.
if [[ "$MIN_GATES" =~ ^[1-9][0-9]*$ && "$declared" -ge "$MIN_GATES" ]]; then
  SHRUNK="$(tmp_file test_gate_wiring_shrunk)" || exit 1
  grep -v '^#' "$ORDER" | grep . | tail -n +"$((declared - MIN_GATES + 2))" > "$SHRUNK"
  if [[ "$(gate_count_of "$SHRUNK")" -ne "$((MIN_GATES - 1))" ]]; then
    fail "the shrunk copy of ${ORDER} has $(gate_count_of "$SHRUNK") rows, not MIN_GATES - 1 = $((MIN_GATES - 1)) — the self-proof proves nothing"
  elif gate_floor_verdict "$(gate_count_of "$SHRUNK")" "$MIN_GATES" > /dev/null; then
    fail "the ratchet cannot detect a removed gate — it is measuring nothing"
  fi
  rm -f "$SHRUNK"
fi

# The verdict's cases (the ruling on decision 81, the floor in a data file
# since v14): the floor is read from a floor file written for each case; below
# is red, equal is green and silent, above is green with the warning carrying
# the counted rows as the new floor, as a warn line and as an annotation;
# comments, blank lines and spaces around the value are ignored; a missing
# file, no value, 0, a value that is no whole number and two values are red.
# floor_cases prints one line per case that went wrong and fails if one did; it
# runs against whatever gate_floor_from_file is defined, so the mutation proofs
# can run it against a changed copy.
#
# floor_case <label> <counted> <file text or MISSING> <expected status>
#            <expected line or ->:
#   one case; the file text is written with printf '%b' (so \n is a line
#   break) to ${FLOOR_CASE_FILE}, which MISSING leaves absent; the expected
#   line must be a whole line of the output, and `-` means the output must be
#   empty.
floor_case() {
  local label="$1" counted="$2" text="$3" want_rc="$4" want_out="$5" out rc=0
  rm -f "$FLOOR_CASE_FILE"
  [[ "$text" == "MISSING" ]] || printf '%b' "$text" > "$FLOOR_CASE_FILE"
  out="$(gate_floor_from_file "$counted" "$FLOOR_CASE_FILE")" || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    echo "case ${label}: exit ${rc}, expected ${want_rc}. Output: ${out}"
  elif [[ "$want_out" == "-" && -n "$out" ]]; then
    echo "case ${label}: printed '${out}', expected nothing"
  elif [[ "$want_out" != "-" ]] && ! grep -qxF -- "$want_out" <<< "$out"; then
    echo "case ${label}: the output has no line '${want_out}'. Output: ${out}"
  fi
}

floor_cases() {
  local found f="$FLOOR_CASE_FILE"
  local bad="not a positive whole number — a floor that is missing, empty or 0 measures nothing"
  found="$(
    floor_case "below (111 under 112)" 111 '112\n' 1 "❌ FAIL: gate count fell to 111, ratchet is 112 — a gate was removed. Restore it; lowering MIN_GATES needs an explicit yes, also when a gate was legitimately merged into another"
    floor_case "equal (112 at 112)" 112 '112\n' 0 -
    floor_case "above, the warn row (114 over 112)" 114 '112\n' 0 "⚠️ warn: Raise MIN_GATES from 112 to 114"
    floor_case "above, the annotation (114 over 112)" 114 '112\n' 0 "::warning title=gate wiring::Raise MIN_GATES from 112 to 114"
    floor_case "a documented file (comments, a blank line, spaces)" 112 '# the floor\n\n  112  \n# history\n' 0 -
    floor_case "a documented file, below (111 under 112)" 111 '# the floor\n112\n' 1 "❌ FAIL: gate count fell to 111, ratchet is 112 — a gate was removed. Restore it; lowering MIN_GATES needs an explicit yes, also when a gate was legitimately merged into another"
    floor_case "the floor file missing" 112 MISSING 1 "❌ FAIL: the floor file ${f} is missing — MIN_GATES has no value, so the gate count measures nothing"
    floor_case "the floor file empty" 112 '' 1 "❌ FAIL: MIN_GATES in ${f} is '', ${bad}"
    floor_case "the floor file only comments" 112 '# the floor\n\n' 1 "❌ FAIL: MIN_GATES in ${f} is '', ${bad}"
    floor_case "floor 0" 112 '0\n' 1 "❌ FAIL: MIN_GATES in ${f} is '0', ${bad}"
    floor_case "floor not a number" 112 'abc\n' 1 "❌ FAIL: MIN_GATES in ${f} is 'abc', ${bad}"
    floor_case "two floors" 112 '112\n113\n' 1 "❌ FAIL: MIN_GATES in ${f} is '112 113', ${bad}"
  )"
  [[ -z "$found" ]] && return 0
  echo "$found"
  return 1
}

if ! is_mutation_rerun; then
  floor_case_dir="$(tmp_dir test_gate_wiring_floor_cases)" || exit 1
  FLOOR_CASE_FILE="${floor_case_dir}/gate_wiring_floor.txt"
  if found="$(floor_cases)"; then
    echo "  ok: the gate count verdict, the floor read from its file: below red, equal green, above green with the warning (warn line and annotation), a missing, empty, 0, non-numeric or doubled floor red"
  else
    while IFS= read -r line; do
      fail "the gate count verdict: ${line}"
    done <<< "$found"
  fi

  # Mutation proofs: each copy of the verdict changes one thing and the cases
  # must go red on it.
  SELF_FILE="Scripts/$(basename "$0")"
  floor_tmp="$(tmp_dir test_gate_wiring_floor)" || exit 1
  awk '/^# FLOOR VERDICT BEGIN$/ { on = 1 } on { print } /^# FLOOR VERDICT END$/ { on = 0 }' "$SELF_FILE" > "${floor_tmp}/verdict.sh"
  [[ -s "${floor_tmp}/verdict.sh" ]] || fail "the FLOOR VERDICT block of ${SELF_FILE} is missing — the verdict's mutation proofs prove nothing"
  floor_mutant() {
    local name="$1" expr="$2"
    sed -E "$expr" "${floor_tmp}/verdict.sh" > "${floor_tmp}/${name}.sh"
    if cmp -s "${floor_tmp}/verdict.sh" "${floor_tmp}/${name}.sh"; then
      fail "the ${name} mutation of the gate count verdict changed nothing — the sed no longer matches"
    elif (
      # shellcheck source=/dev/null # a mutated copy of the verdict above
      source "${floor_tmp}/${name}.sh"
      floor_cases > /dev/null
    ); then
      fail "a gate count verdict with the ${name} mutation passed every case — the cases do not guard it"
    else
      echo "  ok: the gate count verdict with the ${name} mutation is rejected"
    fi
  }
  floor_mutant below_green 's/("[$]counted") -lt "[$]floor"/\1 -lt 0/'
  floor_mutant equal_warned 's/("[$]counted") -gt ("[$]floor")/\1 -ge \2/'
  floor_mutant silent_above 's/echo "Raise MIN_GATES from/: "Raise MIN_GATES from/'
  floor_mutant wrong_new_floor 's/(from ([$][{]floor[}]) to )[$][{]counted[}]/\1\2/'
  floor_mutant warning_fails 's/(gate_floor_warn "[$]verdict"); return 0/\1; return 1/'
  floor_mutant no_annotation 's/echo ("::warning title=gate wiring::)[$]1"/: \1"/'
  floor_mutant bad_floor_accepted 's/\^\[1-9\]\[0-9\]\*\$/^[0-9]*$/'
  floor_mutant file_ignored 's/gate_floor_of "[$]2"/echo 112/'
  floor_mutant missing_file_open 's/(so the gate count measures nothing"); return 1/\1; return 0/'
  floor_mutant comments_counted "s/grep -v -e '\\^#' -e '\\^[$]'/cat/"
  rm -rf "$floor_tmp" "$floor_case_dir"
fi

# --- Mutation proofs: a mention is not an invocation -------------------------
#
# Each proof re-runs this whole check against a copy of one file (a runner,
# the order file, or a file the local cases name) whose real invocation is
# turned into a comment, or one rule broken, while other lines keep MENTIONING
# it. The check under test must reject that copy, by name.
#
# mutation_proof <override-var> <mention> <sed-expr> <expected> <label>
#   <override-var>  GATE_WIRING_CI_OVERRIDE (the sed mutates $CI),
#                   GATE_WIRING_FBP_OVERRIDE ($FULL_BUILD),
#                   GATE_WIRING_SFL_OVERRIDE ($SFL),
#                   GATE_WIRING_ORDER_OVERRIDE ($ORDER), or one of the local
#                   cases' (gate_wiring_local_original names its file)
#   <mention>       text the mutant must still contain (else the proof tests
#                   a deletion, not a mention)
#   <sed-expr>      the -E expression that makes the mutant
#   <expected>      the substring the rejecting fail line must contain
#   <label>         what the mutant is, for the messages
#
# Three guards, all needed: the mutant must differ from the original (else the
# sed stopped matching and the proof proves nothing), the mutant must still
# contain <mention>, and the re-run must fail WITH the expected message (a
# non-zero exit for any other reason is not the check biting).
#
# Runs only at the top level: the re-run sees an override set and skips this
# block, so it cannot recurse.
#
# rerun_with <override-var> <file>: re-runs this whole check with <file> in
# place of the file <override-var> names, printing its output (stderr
# included) and exiting with its status.
rerun_with() {
  env "${1}=${2}" "./Scripts/$(basename "$0")" 2>&1
}

mutation_proof() {
  local override_var="$1" mention="$2" sed_expr="$3" expected="$4" label="$5"
  local original mutated rc out

  # The override variable and the file it replaces are one pairing; deriving
  # the file here means a call cannot mutate one file and inject it as another.
  case "$override_var" in
    GATE_WIRING_CI_OVERRIDE) original="$CI" ;;
    GATE_WIRING_FBP_OVERRIDE) original="$FULL_BUILD" ;;
    GATE_WIRING_SFL_OVERRIDE) original="$SFL" ;;
    GATE_WIRING_ORDER_OVERRIDE) original="$ORDER" ;;
    *)
      if ! original="$(gate_wiring_local_original "$override_var")"; then
        fail "mutation proof: unknown override variable ${override_var}"
        return 0
      fi
      ;;
  esac

  MUTANT_N=$((MUTANT_N + 1))
  mutated="${MUTATION_TMP}/${MUTANT_N}.$(basename "$original")"
  sed -E "$sed_expr" "$original" > "$mutated"

  if cmp -s "$original" "$mutated"; then
    fail "mutation proof: ${label} — the sed changed nothing in ${original}, so this case proves nothing"
    return 0
  fi

  if ! grep -qF -- "$mention" "$mutated"; then
    fail "mutation proof: ${label} no longer mentions ${mention} at all — the case must keep a mention to prove a mention is not an invocation"
    return 0
  fi

  rc=0
  out="$(rerun_with "$override_var" "$mutated")" || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    fail "mutation proof: ${label} PASSED the gate wiring check — a mention is not an invocation"
  elif ! grep -qF -- "$expected" <<< "$out"; then
    fail "mutation proof: ${label} failed, but not with the expected message (${expected}). Output: ${out}"
  else
    echo "  ok: ${label} is rejected"
  fi
}

# --- Matcher self-proof: runs_script on sample files (the estate's issue 18) -
#
# The mutation proofs only show that runs_script rejects what the real
# runners happen to contain today. These feed it sample files, one form per
# file, each naming Scripts/probe.sh: a form that only MENTIONS the script
# must be rejected, and a form that RUNS it must be accepted. The file
# extension says what the sample is (.yml a workflow, .sh a shell script),
# as it does for the real runners. Items are those of the estate's issue 18;
# "guard" samples are the real call shapes of quality.yml, sfl.sh, FBP.sh and
# the fixtures that source a helper, plus one call through bash (no runner
# has that shape today; it pins the wrapper rule), so that a stricter matcher
# cannot start rejecting them. The local cases may feed it samples of their
# own.
MATCHER_N=0

# matcher_sample <ext>: copies stdin into a fresh sample file with extension
# <ext> and sets MATCHER_FILE to its path.
matcher_sample() {
  MATCHER_N=$((MATCHER_N + 1))
  MATCHER_FILE="${MUTATION_TMP}/matcher_${MATCHER_N}.$1"
  cat > "$MATCHER_FILE"
}

# matcher_fail <item> <what went wrong>: fails naming the issue item and
# shows the sample the verdict was wrong on.
matcher_fail() {
  fail "runs_script (issue 18 ${1}): ${2} Sample (${MATCHER_FILE##*/}):"
  sed 's/^/      | /' "$MATCHER_FILE"
}

# matcher_rejects <item> <label> <ext> < sample: runs_script must NOT count
# the sample as running Scripts/probe.sh.
matcher_rejects() {
  matcher_sample "$3"
  if runs_script "$MATCHER_FILE" probe.sh; then
    matcher_fail "$1" "${2} counted as running Scripts/probe.sh, but it only mentions it."
  else
    echo "  ok: runs_script rejects ${2}"
  fi
}

# matcher_accepts <item> <label> <ext> < sample: runs_script MUST count the
# sample as running Scripts/probe.sh.
matcher_accepts() {
  matcher_sample "$3"
  if runs_script "$MATCHER_FILE" probe.sh; then
    echo "  ok: runs_script accepts ${2}"
  else
    matcher_fail "$1" "${2} was not counted as running Scripts/probe.sh, but it runs it."
  fi
}

matcher_self_proof() {
  # Item 2: another command takes the path as an argument.
  matcher_rejects "item 2" "a chmod +x line in a run block" yml <<'SAMPLE'
      - name: Render report
        run: |
          chmod +x ./Scripts/probe.sh
          ./Scripts/other.sh "$ROWS" "$DETAILS"
SAMPLE
  matcher_rejects "item 2" "a cp line copying the script" sh <<'SAMPLE'
cp "${ROOT}/Scripts/probe.sh" "${dir}/Scripts/probe.sh"
SAMPLE
  matcher_rejects "item 2" "a [ -x ] test of the script" sh <<'SAMPLE'
[ -x ./Scripts/probe.sh ] || exit 1
SAMPLE
  matcher_rejects "item 2, issue 14 note a" "the script passed as an argument to another script" sh <<'SAMPLE'
PATH="${dir}/bin:$PATH" "$BASH" "${dir}/driver.sh" "${ROOT}/Scripts/probe.sh" > "${dir}/run.out" 2>&1
SAMPLE

  # Item 3: YAML keys other than run: hold text, not commands.
  matcher_rejects "item 3" "a YAML - name: value" yml <<'SAMPLE'
      - name: Run ./Scripts/probe.sh
        run: |
          ./Scripts/other.sh
SAMPLE
  matcher_rejects "item 3" "a YAML name: value that is not the first key" yml <<'SAMPLE'
      - uses: actions/checkout@v4
        name: Scripts/probe.sh self-test
SAMPLE
  matcher_rejects "item 3" "a YAML if: expression" yml <<'SAMPLE'
      - if: hashFiles('Scripts/probe.sh') != ''
        run: ./Scripts/other.sh
SAMPLE

  # Item 4: heredoc bodies and multi-line strings are data.
  matcher_rejects "item 4" "a quoted heredoc body" sh <<'SAMPLE'
cat > "$f" <<'EOF'
./Scripts/probe.sh
EOF
SAMPLE
  matcher_rejects "item 4" "an unquoted <<- heredoc body in a run block" yml <<'SAMPLE'
        run: |
          cat <<-EOF >> "$GITHUB_STEP_SUMMARY"
          ./Scripts/probe.sh "$ROWS"
          EOF
SAMPLE
  matcher_rejects "item 4" "the continuation line of a multi-line double-quoted string" sh <<'SAMPLE'
echo "Regenerate with
  ./Scripts/probe.sh, then commit"
SAMPLE
  matcher_rejects "item 4" "a backslash continuation line of an echo" sh <<'SAMPLE'
echo "Regenerate with" \
  ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 4" "a > block scalar under env:" yml <<'SAMPLE'
      - name: Hint
        env:
          HINT: >
            ./Scripts/probe.sh
        run: ./Scripts/other.sh
SAMPLE
  matcher_rejects "item 4" "a | block scalar under with:" yml <<'SAMPLE'
      - uses: actions/github-script@v7
        with:
          script: |
            ./Scripts/probe.sh
SAMPLE

  # Item 5: an echo, printf, comment, : or test AFTER real code.
  matcher_rejects "item 5" "an echo inside a { } group" sh <<'SAMPLE'
{ echo; echo ./Scripts/probe.sh; }
SAMPLE
  matcher_rejects "item 5" "a comment after true" sh <<'SAMPLE'
true # ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 5" "a comment after a real call of another script" sh <<'SAMPLE'
./Scripts/other.sh # replaces ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 5" "a : no-op" sh <<'SAMPLE'
: ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 5" "a test -x" sh <<'SAMPLE'
test -x ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 5" "a printf after ;" sh <<'SAMPLE'
rc=0; printf '%s\n' ./Scripts/probe.sh
SAMPLE
  matcher_rejects "item 5" "an echo after && on a one-line run:" yml <<'SAMPLE'
      - run: true && echo ./Scripts/probe.sh
SAMPLE

  # Item 6: a real call fed by echo or printf through a pipe.
  matcher_accepts "item 6" "a call fed by printf through a pipe" yml <<'SAMPLE'
        run: |
          printf '%s\n' x | ./Scripts/probe.sh
SAMPLE
  matcher_accepts "item 6" "a call fed by echo through a pipe" sh <<'SAMPLE'
echo x | ./Scripts/probe.sh
SAMPLE

  # Item 9: the match is on the whole path, not on part of a longer one.
  matcher_rejects "item 9" "a call of Scripts/probe.sh.bak" yml <<'SAMPLE'
        run: |
          ./Scripts/probe.sh.bak "$ROWS"
SAMPLE
  matcher_rejects "item 9" "a call of LegacyScripts/probe.sh" sh <<'SAMPLE'
./LegacyScripts/probe.sh
SAMPLE

  # Guards: the real call shapes, which must stay accepted. These held when
  # they were written.
  matcher_accepts "guard" "a call in a run: | block" yml <<'SAMPLE'
        run: |
          set -uo pipefail
          ./Scripts/probe.sh "$ROWS" "$DETAILS"
SAMPLE
  matcher_accepts "guard" "a one-line - run: call" yml <<'SAMPLE'
      - run: ./Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a call captured in an if test" yml <<'SAMPLE'
        run: |
          if out="$(./Scripts/probe.sh "$GENERATED_SITE" Site 2>&1)"; then
            rc=0
          fi
SAMPLE
  matcher_accepts "guard" "a call captured before && rc=0 || rc=\$?" yml <<'SAMPLE'
        run: |
          out="$(./Scripts/probe.sh 2>&1)" && rc=0 || rc=$?
SAMPLE
  matcher_accepts "guard" "a call in a run block after an env: block scalar" yml <<'SAMPLE'
      - name: Hint
        env:
          HINT: >
            see the docs
        run: |
          ./Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a call after a heredoc has ended" sh <<'SAMPLE'
cat > "$f" <<'EOF'
text
EOF
./Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a call with an env-assignment prefix" sh <<'SAMPLE'
  SITE_PAGE_COUNT_FILE="$PAGE_COUNT_FILE" ./Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a call inside a command substitution" sh <<'SAMPLE'
    FAILED_GATES="${FAILED_GATES}$(./Scripts/probe.sh "$log")"$'\n'
SAMPLE
  matcher_accepts "guard" "a call whose arguments continue on the next line" sh <<'SAMPLE'
./Scripts/probe.sh \
  "$STEP_FILE"
SAMPLE
  matcher_accepts "guard" "a source of the ROOT-prefixed path" sh <<'SAMPLE'
source "${ROOT}/Scripts/probe.sh"
SAMPLE
  matcher_accepts "guard" "an indented source Scripts/probe.sh" sh <<'SAMPLE'
  source Scripts/probe.sh
SAMPLE
  matcher_accepts "guard" "a call through bash" sh <<'SAMPLE'
bash ./Scripts/probe.sh
SAMPLE
}

if ! is_mutation_rerun; then
  MUTATION_TMP="$(tmp_dir test_gate_wiring_mutations)" || exit 1
  trap 'rm -rf "$MUTATION_TMP"; finish' EXIT
  MUTANT_N=0

  gate_wiring_local_proofs
  matcher_self_proof
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: gate wiring"
  exit 1
fi

echo "OK: gate wiring (${n_gate} gate scripts and ${n_fixture} fixtures declared in ${ORDER}, ${n_exempt} declared exemptions run by their required runners, the gate count ${declared} at or above the ratchet of ${MIN_GATES}, and this repository's own pins)"
