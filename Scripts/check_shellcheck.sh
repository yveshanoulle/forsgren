#!/usr/bin/env bash
# canon: check_shellcheck v2
# Shellcheck — every shell script git tracks or will commit (tracked, or
# untracked and not ignored: Scripts/lib_repo_files.sh), DERIVED rather than
# named, so a new script is covered the moment it is added instead of when
# someone remembers to list it here. Two sources feed the target list:
#   1. every such *.sh file (any directory, any depth)
#   2. every such extension-less file whose first line is a bash/sh
#      shebang — a wrapper script without an extension would otherwise slip
#      through both the *.sh glob and human memory
# A named list plus a Scripts/*.sh glob used to live here in several sites of
# the estate: the glob kept Scripts/ covered automatically, but every OTHER
# directory needed a name added by hand, and one such directory (extracted
# server wrappers) was simply never added — it shellchecked nothing, in sfl or
# CI. The self-test keeps such a path as fixture data.
#
# Scripts/shellcheck_exclusions.txt lists tracked shell scripts deliberately
# left out of this check, one path per line. Empty is the normal state: every
# shell script is expected to pass shellcheck as-is. An exclusion needs all
# three of: the entry there; a sentence in documentation/gate-classification.md
# naming the script and the reason; an explicit yes recorded on an issue that
# sentence links. The file is required and read fail closed: missing, a
# malformed line or an entry that is not a file is red, never a skip. It is
# always this repository's file (next to this script), not the SHELLCHECK_ROOT
# fixture's.
#
# Testing seam: SHELLCHECK_ROOT overrides the repo root so
# Scripts/test_check_shellcheck.sh can drive target collection against a
# synthetic git tree.
#
# Byte-identical across the estate's repositories: what differs per site is data.
# sfl.sh runs it from Scripts/gate_report_order.txt, and so does CI, through
# Scripts/run_ci_phase.sh.
#
# Optional file list (estate issue 301): with paths after the program name
# (relative to the root), only those files are checked, with the same -x
# call and the same exclusions file; without, the derived list
# above, exactly as before. A listed path that is not a file is red, named. A
# list whose files are all excluded checks nothing and says so.
#
# Local invocation: ./Scripts/check_shellcheck.sh [file...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/lib_repo_files.sh
source "${SCRIPT_DIR}/lib_repo_files.sh"

ROOT="${SHELLCHECK_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
EXCLUSIONS_FILE="${SCRIPT_DIR}/shellcheck_exclusions.txt"
cd "$ROOT"

# Same PATH sfl.sh sets. CI invokes this script directly rather than through
# sfl, and a Homebrew tool that is not on the runner's PATH would otherwise read
# as "no such command" rather than as the tool it is.
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "❌ FAIL: shellcheck is not installed — this gate cannot run, and a gate that cannot run must not report a pass" >&2
  echo "   brew install shellcheck" >&2
  exit 1
fi

# A plain string, not an array: an empty bash 3.2 array under `set -u` is a
# fatal expansion on macOS, and this list is expected to stay empty.
EXCLUDE_ALLOWED=""
if [ ! -f "$EXCLUSIONS_FILE" ]; then
  echo "❌ FAIL: shellcheck: ${EXCLUSIONS_FILE} is missing — there is no default, and no verdict without it" >&2
  exit 1
fi
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '' | '#'*) continue ;; esac
  if ! [[ "$line" =~ ^[A-Za-z0-9_][A-Za-z0-9_./-]*$ ]] || [ ! -f "$ROOT/$line" ]; then
    echo "❌ FAIL: shellcheck: ${EXCLUSIONS_FILE}: '${line}' is not a path of an existing file — fix the line, the gate does not guess" >&2
    exit 1
  fi
  EXCLUDE_ALLOWED="${EXCLUDE_ALLOWED}${line}"$'\n'
done < "$EXCLUSIONS_FILE"

# collect_targets — prints every candidate path, one per line, deduped and
# sorted by the caller.
collect_targets() {
  repo_files . '*.sh'

  # Extension-less files: only worth a `head`+shebang check, since
  # the *.sh glob above already caught every named script.
  repo_files . | while IFS= read -r f; do
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
if [ "$#" -gt 0 ]; then
  for f in "$@"; do
    if [ ! -f "$f" ]; then
      echo "❌ FAIL: shellcheck: listed file not found: ${f}" >&2
      exit 1
    fi
    if grep -qxF "$f" <<< "$EXCLUDE_ALLOWED"; then
      continue
    fi
    targets+=("$f")
  done
  if [ "${#targets[@]}" -eq 0 ]; then
    echo "shellcheck: every listed file is in the exclusions file, nothing to check"
    exit 0
  fi
else
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -qxF "$f" <<< "$EXCLUDE_ALLOWED"; then
      continue
    fi
    targets+=("$f")
  done < <(collect_targets | sort -u)
fi

if [ "${#targets[@]}" -eq 0 ]; then
  echo "shellcheck: no shell scripts found under $ROOT" >&2
  exit 1
fi

# -x (--external-sources): follow a `source`/`.` target from disk even when
# it isn't one of the files given on this invocation's command line. Without
# it, `source=` directives only resolve when the sourced file happens to be
# ANOTHER of this invocation's targets — which fails for a script that
# sources a sibling introduced in the same, not-yet-committed change: sfl
# runs shellcheck on the working tree BEFORE staging/committing, so a brand
# new sourced file is untracked; `collect_targets` lists untracked, not-ignored
# files too, and -x also reads one that is ignored or not a
# target, since the file genuinely exists on disk and IS what will
# be sourced at runtime. -x reads the real file either way, so it checks
# what actually runs rather than depending on git's index at the moment sfl
# happens to run.
#
# THE WHOLE REPORT GOES TO A FILE. sfl's end-of-run Errors: block quotes only
# the first few lines of a failing gate, the wrong size for a linter reading
# many scripts at once. .build/ is gitignored, so the log is readable after the
# run without being committed.
mkdir -p .build
rc=0
shellcheck -x "${targets[@]}" 2>&1 | tee .build/shellcheck.log || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "(full report: ${ROOT}/.build/shellcheck.log)" >&2
fi
exit "$rc"
