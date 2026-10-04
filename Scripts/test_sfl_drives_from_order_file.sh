#!/usr/bin/env bash
# Scripts/test_sfl_drives_from_order_file.sh
#
# Ported from another estate repository 2026-10-01 (forsgren#1). forsgren's change:
# pin 4 has no CI-only exemption (forsgren has no test_check_built_site.sh).
# Pin 5 (the secret-class tier on the secret scan row) came back with the
# secret scan, ladder step 3. Pin 6 (the same tier on the data guard row) is
# forsgren's own: Yves's ruling of 2026-10-02 (forsgren#1, step 12.2) that the
# data guard works like the secret scan. Pin 7 (the same tier on the private
# names row) is #52's: the gate guards what must never reach a public history.

set -euo pipefail

cd "$(dirname "$0")/.."

# sfl derives its SEQUENCE AND ITS COMMANDS from Scripts/gate_report_order.txt
# — unit 409 step 3.
#
# THIS IS WHAT CLOSES THE ORDER QUESTION. Another estate repository's gate-parity axis compares
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
# Overridable so pin 5 can be shown FAILING against a mutated copy — a green
# that was never seen red is a green that might assert nothing.
ORDER="${1:-Scripts/gate_report_order.txt}"

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
for f in Scripts/test_*.sh; do
  [ -f "$f" ] || continue

  grep -v '^#' "$ORDER" | cut -d'|' -f2 | grep -qxF "$f" \
    || fail "${f} is not named by any row in ${ORDER} — it would run unlabelled and appear in no report"
done

# Pin 5: the SECRET-CLASS TIER lives in field 4 of the file. run_gate_secret is
# what makes sfl exit 2, which FBP.sh reads as "do not commit at all"
# — committing a secret puts it into history, where removing it is a rewrite
# rather than an edit. Leaving that routing as a literal inside sfl would have
# been the one behaviour the order file could not see, and losing it would be
# silent: the scan would still run, still pass, and a real finding would drop
# from blocking the commit to merely blocking the push.
if ! grep -qE '^secret scan\|[^|]+\|pre\|secret-class$' "$ORDER"; then
  fail "the secret scan row does not carry the PRE secret-class tier — the scan would still run, but a finding would stop blocking the COMMIT and only block the push"
fi

# Non-vacuity for pin 5: the same file with the tier stripped must be rejected.
# Every other pin here fails loudly on a repo that has not migrated; this one is
# a single word in one row, and would sit green forever if it matched nothing.
if [ "$ORDER" = "Scripts/gate_report_order.txt" ]; then
  _tmp="$(mktemp -d)"
  sed \
    's/^secret scan|\(.*\)|pre|secret-class$/secret scan|\1|pre|/' \
    "$ORDER" > "${_tmp}/order.txt"

  if cmp -s "$ORDER" "${_tmp}/order.txt"; then
    fail "the tier-stripping mutation changed nothing — pin 5 is matching something other than the row it claims to"
  elif "$0" "${_tmp}/order.txt" >/dev/null 2>&1; then
    fail "an order file with the secret-class tier REMOVED was accepted — pin 5 does not actually guard it"
  else
    echo "  ok: stripping the secret-class tier is rejected"
  fi

  rm -rf "$_tmp"
fi

# Pin 6: the DATA GUARD carries the same tier (Yves, 2026-10-02, forsgren#1
# step 12.2: "it works like the secret scan"). What it guards, an
# installation's config or data, is what must
# never reach a public history, so a finding has to block the COMMIT, not only
# the push. Losing the tier would be as silent as losing pin 5's: the guard
# would still run and still be red, and the finding would be committed.
if ! grep -qE '^data guard\|[^|]+\|pre\|secret-class$' "$ORDER"; then
  fail "the data guard row does not carry the PRE secret-class tier — the guard would still run, but a finding would be committed locally and only block the push"
fi

# Non-vacuity for pin 6, as for pin 5: the same file with the data guard's
# tier stripped must be rejected. The anchor names the row, not its
# self-test, whose label also starts with "data guard".
if [ "$ORDER" = "Scripts/gate_report_order.txt" ]; then
  _tmp="$(mktemp -d)"
  sed \
    's/^data guard|\(.*\)|pre|secret-class$/data guard|\1|pre|/' \
    "$ORDER" > "${_tmp}/order.txt"

  if cmp -s "$ORDER" "${_tmp}/order.txt"; then
    fail "the data-guard tier-stripping mutation changed nothing — pin 6 is matching something other than the row it claims to"
  elif "$0" "${_tmp}/order.txt" >/dev/null 2>&1; then
    fail "an order file with the data guard's secret-class tier REMOVED was accepted — pin 6 does not actually guard it"
  else
    echo "  ok: stripping the data guard's secret-class tier is rejected"
  fi

  rm -rf "$_tmp"
fi

# Pin 7: the PRIVATE NAMES gate carries the same tier (forsgren#52). What it
# guards, a private repository name in a public file, is what must never reach
# a public history, so a finding has to block the COMMIT, not only the push.
# Losing the tier would be as silent as losing pin 5's: the gate would still
# run and still be red, and the finding would be committed.
if ! grep -qE '^private names\|[^|]+\|pre\|secret-class$' "$ORDER"; then
  fail "the private names row does not carry the PRE secret-class tier — the gate would still run, but a finding would be committed locally and only block the push"
fi

# Non-vacuity for pin 7, as for pins 5 and 6: the same file with the private
# names row's tier stripped must be rejected.
if [ "$ORDER" = "Scripts/gate_report_order.txt" ]; then
  _tmp="$(mktemp -d)"
  sed \
    's/^private names|\(.*\)|pre|secret-class$/private names|\1|pre|/' \
    "$ORDER" > "${_tmp}/order.txt"

  if cmp -s "$ORDER" "${_tmp}/order.txt"; then
    fail "the private-names tier-stripping mutation changed nothing — pin 7 is matching something other than the row it claims to"
  elif "$0" "${_tmp}/order.txt" >/dev/null 2>&1; then
    fail "an order file with the private names row's secret-class tier REMOVED was accepted — pin 7 does not actually guard it"
  else
    echo "  ok: stripping the private names row's secret-class tier is rejected"
  fi

  rm -rf "$_tmp"
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: sfl does not drive from the order file"
  exit 1
fi

echo "OK: sfl drives from ${ORDER} (${rows} rows, each naming an executable script; no literal-label call sites; every canonical fixture declared)"