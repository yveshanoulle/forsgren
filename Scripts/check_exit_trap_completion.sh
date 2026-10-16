#!/usr/bin/env bash
# canon: check_exit_trap_completion v1
# Scripts/check_exit_trap_completion.sh [repo-root]
#
# Gate: red when a shell script runs
# under `set -e` with a top-level EXIT trap and carries no completion flag.
#
# Why. On bash 3.2 (macOS /bin/bash, the shell sfl and the self-hosted runner
# use) a script under `set -e -u` that has an EXIT trap ends with status 0
# after an unbound variable in the main shell, and $? inside the trap is 0
# too. The abort is invisible, so the caller reads it as a pass. The cure is
# a COMPLETED flag: the very last statement sets COMPLETED=1, and the trap
# turns an exit of 0 without it into exit 1 (the push wrapper's
# print_summary; Scripts/lib_selftest.sh's selftest_cleanup, which every test fixture that
# calls selftest_begin gets).
#
# The rule, per *.sh at the repository root and directly in Scripts/: a
# top-level (column 0) `set -...e...` line BEFORE a top-level
# `trap ... EXIT` line is red unless the file also mentions COMPLETED,
# selftest_begin or lib_selftest.sh. Known limits, on purpose: `set -o
# errexit` is not read, a `set -e` placed after the trap is not read (the trap
# then ran without -e), and a column-0 line inside a heredoc is read as code.
# Behaviour is not probed here; each fix was shown by
# injecting an unbound variable after the trap.
#
# Findings carry the red-cross marker, one per script, as file:line of the
# trap. Exit 0 clean, 1 findings, 2 a missing root, and a root with no script
# at all is red: nothing scanned is not clean.
#
# Self-test: Scripts/test_check_exit_trap_completion.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"
ROOT="${1:-$REPO}"

if [ ! -d "$ROOT" ]; then
  echo "❌ FAIL: root dir not found: ${ROOT}"
  exit 2
fi

SET_E='^set +-[A-Za-z]*e[A-Za-z]*( |$)'
EXIT_TRAP='^trap .* EXIT'
COMPLETION='COMPLETED|selftest_begin|lib_selftest\.sh'

scanned=0
findings=0
for file in "$ROOT"/*.sh "$ROOT"/Scripts/*.sh; do
  [ -f "$file" ] || continue
  scanned=$((scanned + 1))
  trap_line="$(grep -nE "$EXIT_TRAP" "$file" | head -n 1 | cut -d: -f1)"
  [ -n "$trap_line" ] || continue
  set_line="$(grep -nE "$SET_E" "$file" | head -n 1 | cut -d: -f1)"
  [ -n "$set_line" ] || continue
  [ "$set_line" -lt "$trap_line" ] || continue
  grep -qE "$COMPLETION" "$file" && continue
  echo "❌ FAIL: ${file#"$ROOT"/}:${trap_line} runs under set -e (line ${set_line}) with an EXIT trap and no COMPLETED flag: on bash 3.2 an abort after the trap exits 0"
  findings=$((findings + 1))
done

if [ "$scanned" -eq 0 ]; then
  echo "❌ FAIL: no script found under ${ROOT}: nothing scanned is not clean"
  exit 1
fi

if [ "$findings" -ne 0 ]; then
  echo ""
  echo "exit-trap completion: ${findings} script(s) can end an abort with exit 0 in ${ROOT}."
  echo "Fix: COMPLETED=0 before the trap, COMPLETED=1 as the last statement, and the trap exits 1 when \$? is 0 and COMPLETED is not 1 (see the push wrapper's print_summary)."
  exit 1
fi

echo "OK: exit-trap completion: ${scanned} script(s) scanned, none runs under set -e with an EXIT trap and no completion flag"
exit 0
