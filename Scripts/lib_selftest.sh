#!/usr/bin/env bash
# Scripts/lib_selftest.sh
#
# forsgren's own (forsgren#1, ladder step 24, refactor): the harness of
# forsgren's own gate self-tests, once. Each of them carried its own copy of
# the same temp root, completion guard, fail helper, red/green assertions,
# mutant writer and closing verdict; this is that code, once, with one
# wording: every failure line starts `❌ FAIL:`, every case that holds
# prints `  ok: <case>`, and the closing line is `OK: <claim>` or
# `❌ FAIL: <claim not held>`.
#
# The fixtures ported from another repository of the estate keep their own
# harness, so a port back stays a diff of cases, not of scaffolding.
#
# SOURCED, never run. It judges nothing on its own: the self-tests that
# source it are what test it. It sets no shell options (the sourcing
# self-test owns those) and works under `set -euo pipefail`. selftest_begin
# sets an EXIT trap, so a self-test that sources it sets none of its own.
#
# The variables it shares with the self-test that sources it:
#   TMP        the temp root, removed on exit
#   COMPLETED  1 once the last case ran (selftest_end sets it)
#   failed     1 once any case failed
#   OUT, RC    the output (stdout and stderr) and exit status of the last
#              `capture`

# selftest_begin <what>: a fresh temp root in TMP and the completion guard.
# A self-test that dies part-way must fail, never report green: on macOS
# bash 3.2 a set -u abort inside a function can exit 0. <what> names the
# self-test in the abort line.
selftest_begin() {
  SELFTEST_WHAT="$1"
  TMP="$(mktemp -d)"
  COMPLETED=0
  failed=0
  trap selftest_cleanup EXIT
}

# selftest_cleanup: the EXIT trap. Removes TMP, and turns an exit before
# selftest_end into a red, named.
selftest_cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: ${SELFTEST_WHAT} aborted before completing all cases" >&2
    exit 1
  fi
}

# fail <message>: one failed case; the run goes on, so one run reports
# every failure.
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

# selftest_abort <message>: a precondition failed (the gate under test is
# missing, say), so no case can run: one red, named, and the run stops.
selftest_abort() {
  echo "❌ FAIL: $*"
  COMPLETED=1
  exit 1
}

# capture <command> [args...]: runs it; its stdout and stderr in OUT, its
# exit status in RC. A non-zero status does not stop a `set -e` self-test.
capture() {
  OUT="$("$@" 2>&1)" && RC=0 || RC=$?
}

# want_green <case> [text]: the last capture exited 0 and, when <text> (a
# fixed string) is given, said it.
want_green() {
  if [[ "$RC" -ne 0 ]]; then
    fail "$1: the gate exited ${RC}. Output: ${OUT}"
  elif [[ -n "${2:-}" ]] && ! grep -qF -- "$2" <<< "$OUT"; then
    fail "$1: the gate exited 0 without saying '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# want_green_ok <case>: the last capture exited 0 AND printed its gate's OK
# line, so an exit 0 that skipped the check is not a pass.
want_green_ok() {
  want_green "$1" "OK:"
}

# want_red <case> <reason>: the last capture exited non-zero AND said
# <reason> (a fixed string). A red without its reason is a red for something
# else, and proves nothing about this case.
want_red() {
  if [[ "$RC" -eq 0 ]]; then
    fail "$1: the gate exited 0. Output: ${OUT}"
  elif ! grep -qF -- "$2" <<< "$OUT"; then
    fail "$1: the gate failed without saying '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# want_exit <case> <rc> <text>: the last capture exited exactly <rc> AND
# said <text> (a fixed string).
want_exit() {
  if [[ "$RC" == "$2" ]] && grep -qF -- "$3" <<< "$OUT"; then
    echo "  ok: $1"
  else
    fail "$1 — expected exit $2 with: $3; got exit ${RC}. Output: ${OUT}"
  fi
}

# want_rc <case> <rc>: the last capture exited exactly <rc>.
want_rc() {
  if [[ "$RC" == "$2" ]]; then
    echo "  ok: $1"
  else
    fail "$1 — expected exit $2, got exit ${RC}. Output: ${OUT}"
  fi
}

# want_said <case> <text>: the last capture's output contains <text> (a
# fixed string), whatever its exit status.
want_said() {
  if grep -qF -- "$2" <<< "$OUT"; then
    echo "  ok: $1"
  else
    fail "$1: the output does not say '$2'. Output: ${OUT}"
  fi
}

# selftest_mutant <source> <mutant> <sed-expression>: writes <mutant>, an
# executable copy of <source> with <sed-expression> applied, creating its
# directory. When the expression changed nothing, the proof would be
# vacuous: that is a failed case, and the return status is 1, so the caller
# skips the run.
selftest_mutant() {
  mkdir -p "$(dirname "$2")"
  sed "$3" "$1" > "$2"
  chmod +x "$2"
  if cmp -s "$1" "$2"; then
    fail "the mutation $3 changed nothing in $1: the proof would be vacuous"
    return 1
  fi
}

# selftest_mutant_green <source> <mutant> <sed-expression> <fixture-dir> <ok text> <fail text>:
# the mutation proof every pattern-driven gate repeats. Writes the mutant
# (see selftest_mutant), runs it on <fixture-dir>, and requires exit 0: a
# fixture that is red for the pattern turns green once the pattern is
# neutralised, so it was red BECAUSE of it. Prints `  ok: mutation proof:
# <ok text>`, or fails with `mutation proof: <fail text> (exit N). Output: ...`.
selftest_mutant_green() {
  if selftest_mutant "$1" "$2" "$3"; then
    capture "$2" "$4"
    if [[ "$RC" -eq 0 ]]; then
      echo "  ok: mutation proof: $5"
    else
      fail "mutation proof: $6 (exit $RC). Output: $OUT"
    fi
  fi
}

# selftest_end <claim not held> <claim>: the closing verdict. Exits 1 with
# the first after any failed case, else prints the second as the OK line.
selftest_end() {
  COMPLETED=1
  if [[ "$failed" -ne 0 ]]; then
    echo ""
    echo "❌ FAIL: $1 (see the FAIL lines above)"
    exit 1
  fi
  echo "OK: $2"
}
