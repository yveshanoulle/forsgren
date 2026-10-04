#!/usr/bin/env bash
# Shellcheck — every tracked shell script, DERIVED rather than named, so a
# new script is covered the moment it is added instead of when someone
# remembers to list it here. Two sources feed the target list:
#   1. every git-tracked *.sh file (any directory, any depth)
#   2. every git-tracked extension-less file whose first line is a bash/sh
#      shebang — a wrapper script without an extension would otherwise slip
#      through both the *.sh glob and human memory
# In another estate repository, where this gate comes from, a named list plus a Scripts/*.sh
# glob used to live here: the glob kept Scripts/ covered automatically, but
# every OTHER directory needed a name added by hand, and one such directory
# (another estate repository's extracted server/sbin/*.sh wrappers) was simply never added —
# it shellchecked nothing, in sfl or CI, until another estate repository's copy of
# Scripts/test_check_shellcheck.sh proved it. forsgren has no server/sbin;
# the self-test keeps that path as fixture data.
#
# EXCLUDE_ALLOWED lists tracked shell scripts deliberately left out of this
# check, one per line. Empty is the normal state: every tracked shell
# script is expected to pass shellcheck as-is. An exclusion needs all
# three of:
#   (a) the entry here;
#   (b) a sentence in README.md's Quality gates naming the script and the
#       reason (another estate repository, where this gate comes from, asks for a row in its
#       documentation/check-parity.md instead; forsgren has no such file);
#   (c) Yves's explicit yes, recorded on a GitHub issue that the README
#       sentence links.
# An exception costs a deliberate, approved decision, never a silent skip
# (ruling 1B, forsgren#1, 2026-10-01). A plain string, not an array: an
# empty bash 3.2 array under `set -u` is a fatal expansion on macOS, and
# this list is expected to stay empty.
#
# Testing seam: SHELLCHECK_ROOT overrides the repo root so
# Scripts/test_check_shellcheck.sh can drive target collection against a
# synthetic git tree (same pattern as another estate repository's check_sfl_ci_parity.sh
# SFL_FILE).
#
# Ported from another estate repository 2026-10-01 (forsgren#1, ladder step 12), the estate
# canon; adapted only in these comments, which named another estate repository's own files.
# sfl.sh runs it from Scripts/gate_report_order.txt, and so does CI, through
# Scripts/run_ci_phase.sh.
#
# Local invocation: ./Scripts/check_shellcheck.sh

set -euo pipefail

ROOT="${SHELLCHECK_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

EXCLUDE_ALLOWED=""

# collect_targets — prints every candidate path, one per line, deduped and
# sorted by the caller.
collect_targets() {
  git ls-files '*.sh'

  # Extension-less tracked files: only worth a `head`+shebang check, since
  # the *.sh glob above already caught every named script.
  git ls-files | while IFS= read -r f; do
    case "$f" in
      *.*) continue ;;
    esac
    [ -f "$f" ] || continue
    first_line=""
    IFS= read -r first_line < "$f" 2>/dev/null || true
    if [[ "$first_line" =~ ^#!.*(bash|/sh)([[:space:]].*)?$ ]]; then
      echo "$f"
    fi
  done
}

targets=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if printf '%s\n' "$EXCLUDE_ALLOWED" | grep -qxF "$f"; then
    continue
  fi
  targets+=("$f")
done < <(collect_targets | sort -u)

if [ "${#targets[@]}" -eq 0 ]; then
  echo "shellcheck: no tracked shell scripts found under $ROOT" >&2
  exit 1
fi

# -x (--external-sources): follow a `source`/`.` target from disk even when
# it isn't one of the files given on this invocation's command line. Without
# it, `source=` directives only resolve when the sourced file happens to be
# ANOTHER of this invocation's targets — which fails for a script that
# sources a sibling introduced in the same, not-yet-committed change: sfl
# runs shellcheck on the working tree BEFORE staging/committing, so a brand
# new sourced file is untracked and `collect_targets`'s `git ls-files` never
# lists it, even though the file genuinely exists on disk and IS what will
# be sourced at runtime. -x reads the real file either way, so it checks
# what actually runs rather than depending on git's index at the moment sfl
# happens to run.
shellcheck -x "${targets[@]}"
