#!/usr/bin/env bash
# Scripts/sfl_pull.sh
#
# Ported unchanged from another estate repository 2026-10-01 (forsgren#1).
#
# sfl's opening pull is verified before any check runs. A pull that cannot
# fast-forward is a hard stop, never an auto-rebase — rewriting local commits
# is the person's decision, not sfl's. The message names the exact recovery
# command instead. Return code 3 is reserved for "origin moved or no upstream".
# Fixture: Scripts/test_sfl_pull.sh.

# sfl_pull_or_stop — runs `git pull --ff-only` with its own output left
# visible, so a network error is still readable. Returns 0 on a clean
# fast-forward, including already up to date. On any other outcome it prints
# the recovery command to stderr and returns 3.
sfl_pull_or_stop() {
  if git pull --ff-only; then
    return 0
  fi

  printf 'sfl: origin moved or no upstream — run: git pull --rebase --autostash  then re-run\n' >&2
  return 3
}
