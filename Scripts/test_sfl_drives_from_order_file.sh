#!/usr/bin/env bash
# canon: test_sfl_drives_from_order_file v10
# Scripts/test_sfl_drives_from_order_file.sh
#
# v10 (estate issue 850): one text in every repository of the estate. What
# differs per repository lives in its Scripts/sfl_drives_from_order_file_settings.txt,
# which this file reads and requires: the pre-flight and presentation scripts
# sfl.sh may name (pin 2b), the CI-only fixtures pin 4 forbids from the order
# file, and the rows beyond the secret scan and its self-test that carry the
# secret-class tier. Every tier pin's non-vacuity proof now also requires the
# pin's own FAIL text, not only a red.

set -euo pipefail

cd "$(dirname "$0")/.."

# Temp folders through Scripts/lib_tmp.sh (estate issue 536).
# shellcheck source=Scripts/lib_tmp.sh
source Scripts/lib_tmp.sh

# sfl derives its SEQUENCE AND ITS COMMANDS from Scripts/gate_report_order.txt
# — unit 409 step 3.
#
# THIS IS WHAT CLOSES THE ORDER QUESTION. The estate's gate-parity axis compares
# each repo's order FILE against the canon; it cannot compare execution, because
# execution is a runtime fact and the axis reads files at rest over the API. Of
# the three ways to bridge that — commit a generated "executed order" file (an
# artifact that goes stale, the shape this estate spent 2026-09-01 removing),
# parse sfl.sh for control flow (a mis-parse reports a false clean), or make it
# STRUCTURAL — only the third holds. If the runner takes its order from the
# file, executed order equals declared order by construction and there is
# nothing left to compare.
#
# FIELD 2 IS A SCRIPT PATH (Yves, 2026-09-01: "is it not simpler to add the
# command / script?"). It is, and the first design here was worse: it kept field
# 2 as a fixture basename and mapped the ten non-fixture labels to commands in a
# `case` inside sfl — a SECOND source of truth to keep in sync three ways. I had
# claimed a format change would break the axis; it does not. The axis reads
# field 2 only to ask whether it is the literal `n/a`.
#
# FIELD 3 IS THE EXECUTION PHASE: `pre` or `post`. FIELD 4 IS THE OPTIONAL
# FAILURE CLASS. The secret scan carries `secret-class` in field 4 so sfl can
# preserve its exit-2 contract while phase selection remains independently
# visible in field 3.
#
# Naming the script in the file makes "declared but never run" IMPOSSIBLE rather
# than merely checked: a declared row always names what runs it.
#
# A PATH, not a command line, and that is the one thing this has to get right.
# Six of these gates carried arguments and two were raw `node_modules/.bin/...`
# invocations with quoted globs; storing those as text would mean `eval` or an
# unquoted expansion to rebuild argv, with the glob needing to survive
# unexpanded. Arguments move INSIDE the scripts as defaults — they were per-repo
# constants duplicated at the call site — and the two raw invocations become
# wrappers, which is the estate's own rule that a command body belongs in a
# tested script.

SFL="sfl.sh"
# Overridable so the tier pins can be shown FAILING against a mutated copy — a
# green that was never seen red is a green that might assert nothing.
ORDER="${1:-Scripts/gate_report_order.txt}"
# This repository's values (see the header). Missing or malformed is red.
SETTINGS="Scripts/sfl_drives_from_order_file_settings.txt"

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: order-file drive pins aborted before completing all cases" >&2
    exit 1
  fi
}

trap finish EXIT

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

# The settings: one `<kind>|<value>` per line, blank lines and `#` comments
# ignored. The kinds:
#   preflight|<name>        a script sfl.sh may name outside the dispatch loop
#                           (a pre-flight step, a sourced helper or a
#                           presentation helper; matched as in pin 2b's grep)
#   ci_only_fixture|<path>  a Scripts/test_*.sh that pin 4 requires NOT to be
#                           in the order file
#   secret_class|<label>    one more row that must carry the PRE secret-class
#                           tier (pins 5 and 8 always hold the secret scan and
#                           its self-test)
# Any other line is red: the file is read whole, never partly.
if [[ ! -f "$SETTINGS" ]]; then
  echo "❌ FAIL: ${SETTINGS} is missing — this repository's pre-flight list, CI-only fixtures and secret-class rows have no home" >&2
  exit 1
fi
PREFLIGHT=()
CI_ONLY=()
SECRET_CLASS=()
n=0
while IFS= read -r line || [[ -n "$line" ]]; do
  n=$((n + 1))
  case "$line" in '' | '#'*) continue ;; esac
  kind="${line%%|*}"
  value="${line#*|}"
  if [[ "$line" != *"|"* || -z "$value" || "$value" == *"|"* ]]; then
    fail "${SETTINGS} line ${n} is not <kind>|<value>: ${line}"
    continue
  fi
  case "$kind" in
    preflight) PREFLIGHT+=("$value") ;;
    ci_only_fixture) CI_ONLY+=("$value") ;;
    secret_class) SECRET_CLASS+=("$value") ;;
    *) fail "${SETTINGS} line ${n} has the unknown kind '${kind}': ${line}" ;;
  esac
done < "$SETTINGS"

# Pin 1: the sequence comes from the file.
if ! grep -qF "$ORDER" "$SFL"; then
  fail "sfl.sh never reads ${ORDER} — its order is whatever the call sites happen to say, which is the thing the axis cannot check"
fi

# Pin 2: AND NOWHERE ELSE. One surviving `run_gate "some label"` with a literal
# means that gate's position is decided at its call site, and it would be the
# one gate the axis reports as correctly ordered while it runs somewhere else.
if grep -nE 'run_gate[a-z_]* "[A-Za-z]' "$SFL"; then
  fail "the lines above call run_gate with a LITERAL label — every gate is dispatched from the order file, so a literal call site means that gate's position is not the file's to decide"
fi

# Pin 2b: a gate script invoked by name. The loop runs "./$script"; anything
# naming a Scripts/*.sh literally is a gate running where the file cannot see
# it. `^[^#]*` so a COMMENT mentioning a script is not read as running one.
# Exempt are the `preflight` names of the settings file, each with its reason
# there: presentation helpers sfl's own machinery calls, PRE-FLIGHT steps that
# run before the dispatch loop because they make the gates able to run at all,
# and SOURCED libraries that run no gate. They hold no row; their self-tests
# are order rows. An empty list exempts nothing.
preflight_re="$(IFS='|'; echo "${PREFLIGHT[*]:-}")"
[[ -n "$preflight_re" ]] || preflight_re='^$'
if grep -nE '^[^#]*(\.?/)?Scripts/[a-z_]+\.sh' "$SFL" \
   | grep -vE "$preflight_re"; then
  fail "the lines above run a gate script by name — its position is decided there and not by ${ORDER}, so the estate axis reports an order this run does not follow"
fi

# Pin 2c: a raw linter invocation (estate issue 301 step 3-12). The order file
# names a script path, never a command line, so a linter invoked by sfl.sh
# itself (`npx ...`, `node_modules/.bin/...`) is a gate running where the order
# file cannot see it. The npm install step is a Scripts/ wrapper
# (npm_sync_install.sh) for the same reason: it decides on a lockfile stamp, not
# on whether one marker binary exists.
if grep -nE '^[^#]*\b(npx|node_modules/\.bin)\b' "$SFL"; then
  fail "the lines above invoke a linter directly — the order file names a script path, so the invocation belongs in a Scripts/ wrapper both runners can share"
fi

# Pin 3: every runnable row names a script that exists and is executable. This
# is what makes a dispatch-table guard unnecessary — a row cannot be declared
# without naming what runs it.
rows=0
while IFS='|' read -r label script _rest; do
  case "$label" in \#*|'') continue ;; esac
  [ -n "${script:-}" ] || {
    fail "'${label}' declares no second field at all"
    continue
  }
  [ "$script" = "n/a" ] && continue
  rows=$((rows + 1))
  case "$script" in
    Scripts/*.sh) ;;
    *)
      fail "'${label}' names '${script}', which is not a Scripts/*.sh path — a command line here would have to be re-split into argv, and its quoted globs would not survive"
      continue
      ;;
  esac
  [ -f "$script" ] \
    || fail "'${label}' names ${script}, which does not exist — the report would promise a gate nobody can run"
  [ -x "$script" ] || fail "'${label}' names ${script}, which is not executable"
done < "$ORDER"

if [ "$rows" -eq 0 ]; then
  fail "no runnable rows found in ${ORDER} — the parse is broken, so this check verified nothing"
fi

# Pin 4: every fixture on disk that belongs to the sfl PRE/POST canon is
# declared. A canonical fixture that runs unlabelled never appears in the
# report — the same class of invisible as a gate that never runs.
#
# A `ci_only_fixture` of the settings file is deliberately different: a CI-only
# integrity fixture (a comparison of CI's separately generated candidate with
# committed output, which a local build-then-compare would make tautological),
# so it must NOT be declared.
declared_scripts="$(grep -v '^#' "$ORDER" | cut -d'|' -f2)"
for f in Scripts/test_*.sh; do
  [ -f "$f" ] || continue
  ci_only=0
  for c in ${CI_ONLY[@]+"${CI_ONLY[@]}"}; do
    [[ "$f" == "$c" ]] && ci_only=1
  done
  if [[ "$ci_only" -eq 1 ]]; then
    if grep -qxF "$f" <<< "$declared_scripts"; then
      fail "${f} is declared in ${ORDER} — it is CI-only, not an sfl PRE/POST fixture"
    fi
    continue
  fi
  grep -qxF "$f" <<< "$declared_scripts" \
    || fail "${f} is not named by any row in ${ORDER} — it would run unlabelled and appear in no report"
done

# tier_stripping_proof <pin> <row label> <tier noun> — the non-vacuity proof
# of a secret-class tier pin: the real order file with that row's tier stripped
# must change, and running this check on it must be red with the pin's OWN FAIL
# text ("the <row label> row does not carry the PRE secret-class tier"), not
# for another reason. Every other pin here fails loudly on a repo that has not
# migrated; a tier pin is a single word in one row, and would sit green forever
# if it matched nothing. Runs only on the real order file, never on a mutant.
tier_stripping_proof() {
  local pin="$1" label="$2" noun="$3" _tmp _out
  [ "$ORDER" = "Scripts/gate_report_order.txt" ] || return 0
  _tmp="$(tmp_dir test_sfl_drives_from_order_file)" || exit 1
  sed \
    "s/^${label}|\\(.*\\)|pre|secret-class\$/${label}|\\1|pre|/" \
    "$ORDER" > "${_tmp}/order.txt"

  if cmp -s "$ORDER" "${_tmp}/order.txt"; then
    fail "the ${label} tier-stripping mutation changed nothing — pin ${pin} is matching something other than the row it claims to"
  elif _out="$("$0" "${_tmp}/order.txt" 2>&1)"; then
    fail "an order file with ${noun} REMOVED was accepted — pin ${pin} does not actually guard it"
  elif ! grep -qF "the ${label} row does not carry the PRE secret-class tier" <<< "$_out"; then
    fail "an order file with ${noun} REMOVED was rejected, but not by pin ${pin} (its own FAIL text is missing) — the rejection is for another reason. Output: ${_out}"
  else
    echo "  ok: stripping ${noun} is rejected by pin ${pin}'s own FAIL"
  fi

  rm -rf "$_tmp"
}

# tier_pin <pin> <row label> <why>: the row carries the PRE secret-class tier,
# with its non-vacuity proof.
tier_pin() {
  local pin="$1" label="$2" why="$3"
  if ! grep -qE "^${label}\\|[^|]+\\|pre\\|secret-class\$" "$ORDER"; then
    fail "the ${label} row does not carry the PRE secret-class tier — ${why}"
  fi
  tier_stripping_proof "$pin" "$label" "the ${label} row's secret-class tier"
}

# Pin 5: the SECRET-CLASS TIER lives in field 4 of the file. run_gate_secret is
# what makes sfl exit 2, which FBP.sh reads as "do not commit at all"
# — committing a secret puts it into history, where removing it is a rewrite
# rather than an edit. Leaving that routing as a literal inside sfl would have
# been the one behaviour the order file could not see, and losing it would be
# silent: the scan would still run, still pass, and a real finding would drop
# from blocking the commit to merely blocking the push.
tier_pin 5 "secret scan" "the scan would still run, but a finding would stop blocking the COMMIT and only block the push"

# Pin 8: the SECRET-SCAN SELF-TEST carries the tier as well. Its first case
# scans the real working tree, so a real leak turns it red BEFORE `secret scan`
# runs; sfl stops at the first red gate, and as an ordinary row it would let
# FBP.sh commit the leak as a RED commit.
tier_pin 8 "secret-scan self-test" "a leak in the real tree turns it red first, sfl stops there, and FBP.sh would commit the leak as a RED commit"

# Pins 5+: the `secret_class` rows of the settings file carry the same tier.
# What each guards is what must never reach a public history, so a finding has
# to block the COMMIT, not only the push. Losing the tier would be as silent as
# losing pin 5's: the gate would still run and still be red, and the finding
# would be committed.
for label in ${SECRET_CLASS[@]+"${SECRET_CLASS[@]}"}; do
  tier_pin "5+" "$label" "the gate would still run, but a finding would be committed locally and only block the push"
done

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: sfl does not drive from the order file"
  exit 1
fi

echo "OK: sfl drives from ${ORDER} (${rows} rows, each naming an executable script; no literal-label call sites; every canonical fixture declared)"
