#!/usr/bin/env bash
# Scripts/check_gofmt.sh
#
# gofmt over every Go file git knows about: tracked AND untracked-but-not-
# ignored, so a new file nobody has added yet is checked too, and an ignored
# agent worktree under .claude/worktrees/ is not.
#
# Two modes (Yves's ruling on forsgren#1: auto-fix in FBP, check-only in CI):
#   check_gofmt.sh [dir]        CHECK-ONLY (gofmt -l): red when any file is
#                               not formatted, naming each one. What sfl's
#                               `gofmt` row and CI run.
#   check_gofmt.sh --fix [dir]  rewrites the files (gofmt -l -w) and lists
#                               the ones it changed. What FBP.sh runs first.
# Zero Go files found is red in both modes: in this repo it means the file
# walk broke, not that everything is formatted.
#
# Fixture: Scripts/test_check_gofmt.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

FIX=false
if [ "${1:-}" = "--fix" ]; then
  FIX=true
  shift
fi

ROOT_DIR="${1:-.}"
cd "$ROOT_DIR" || {
  echo "❌ FAIL: directory not found: ${ROOT_DIR}"
  exit 1
}

# Existing files only: a tracked file deleted in the working tree is still
# listed by git ls-files, and gofmt would fail on it.
FILES=""
while IFS= read -r f; do
  [ -f "$f" ] && FILES="${FILES}${f}"$'\n'
done < <(git ls-files --cached --others --exclude-standard -- '*.go')

if [ -z "$FILES" ]; then
  echo "❌ FAIL: no Go files found — the walk over git ls-files found nothing to check"
  exit 1
fi

count="$(printf '%s' "$FILES" | grep -c '')"

if $FIX; then
  changed="$(printf '%s' "$FILES" | tr '\n' '\0' | xargs -0 gofmt -l -w)"
  rc=$?
  if [ -n "$changed" ]; then
    printf '%s\n' "$changed" | sed 's/^/gofmt -w rewrote: /'
  fi
  if [ "$rc" -ne 0 ]; then
    echo "❌ FAIL: gofmt -w could not format every file (exit ${rc})"
    exit 1
  fi
  echo "OK: gofmt -w over ${count} Go files"
  exit 0
fi

unformatted="$(printf '%s' "$FILES" | tr '\n' '\0' | xargs -0 gofmt -l)"
rc=$?

if [ "$rc" -ne 0 ]; then
  echo "❌ FAIL: gofmt could not parse every file (exit ${rc})"
  exit 1
fi

if [ -n "$unformatted" ]; then
  printf '%s\n' "$unformatted" | sed 's/^/❌ FAIL: not gofmt-formatted: /'
  echo "Fix: gofmt -w <file> (FBP.sh does this for you before its gates)"
  exit 1
fi

echo "OK: ${count} Go files gofmt-formatted"
