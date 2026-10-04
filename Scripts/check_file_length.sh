#!/usr/bin/env bash
# Scripts/check_file_length.sh
#
# Gate: red when a Go production file is longer than the limit (600 lines,
# CONVENTIONS.md, Code).
#
# PORTED (forsgren#1, ladder step 21) from
# source-repo/Scripts/go/check_file_length.py, which another estate repository's sfl and CI run
# as `python3 .../check_file_length.py . 600` in each Go module (shared, the
# API, admin). Its rules, kept:
#   - Go production files only: _test.go files are not judged (they hold
#     fixtures and table-driven cases; another estate repository never passes
#     --include-tests for Go).
#   - a generated file is judged like any other (another estate repository has no exemption).
#   - a line is counted as Python iterates a file, which awk's NR matches: a
#     last line without a newline counts, where `wc -l` would not count it.
#   - more than the limit is red; the limit itself is green.
#   - red lists every file over the limit, longest first.
# Adapted:
#   - bash and awk, not Python: python3 is not in Scripts/required_tools.txt,
#     and listing it there would make every sfl run `brew upgrade` a
#     machine-wide Python; this gate needs nothing a list and a line count
#     cannot do, with tools already listed (go) or in the base system (awk).
#   - the files are the module's own as `go list ./...` sees them, not a
#     directory walk: go.mod's `ignore node_modules` keeps npm's Go out (as
#     it does for go test), a nested module (an agent worktree under
#     .claude/worktrees) and testdata/ are not this module's code, and
#     IgnoredGoFiles brings in a file only another GOOS builds. Another estate repository
#     walks the tree, skipping node_modules and vendor by name.
#   - only the Go mode: another estate repository's --ext (its SQL cap), --exclude and
#     --include-tests have no caller here, so they are not ported.
#   - red on a module with no production .go file: a scan over nothing is no
#     pass (another estate repository prints its OK line for it).
#   - forsgren's FAIL and OK lines.
#
# Exit codes (another estate repository's):
#   0 — every production .go file within the limit
#   1 — a file over the limit (each named with its count), or no file to check
#   2 — tooling error (bad arguments, no root directory, go list failed)
#
# Usage: Scripts/check_file_length.sh [module-dir] [max-lines]
#        (default: the repo root, 600)
# Fixture: Scripts/test_check_file_length.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

ROOT="${1:-.}"
MAX="${2:-600}"
# The go list file lists that hold production code. Test files live in
# TestGoFiles and XTestGoFiles, which are not read; IgnoredGoFiles can hold a
# test file too, which the name filter below drops.
FIELDS="GoFiles CgoFiles IgnoredGoFiles"

case "$MAX" in
  '' | *[!0-9]*)
    echo "❌ FAIL: max-lines must be a whole number, got: ${MAX}" >&2
    exit 2
    ;;
esac

cd "$ROOT" 2>/dev/null || {
  echo "❌ FAIL: root directory not found: ${ROOT}" >&2
  exit 2
}

if ! MODDIR="$(go list -m -f '{{.Dir}}' 2>&1)"; then
  printf '%s\n' "$MODDIR" >&2
  echo "❌ FAIL: ${ROOT} is not a Go module: go list -m failed" >&2
  exit 2
fi

template=''
for field in $FIELDS; do
  template="${template}{{range .${field}}}{{\$.Dir}}/{{.}}{{\"\\n\"}}{{end}}"
done

ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT
if ! files="$(go list -e -f "$template" ./... 2>"$ERR")"; then
  cat "$ERR" >&2
  echo "❌ FAIL: go list could not list the module's files in ${ROOT}" >&2
  exit 2
fi

checked=0
longest=0
longest_file=''
over=''
while IFS= read -r abs; do
  [ -n "$abs" ] || continue
  case "$abs" in *_test.go) continue ;; esac
  rel="${abs#"$MODDIR"/}"
  n="$(awk 'END { print NR }' "$abs")" || {
    echo "❌ FAIL: could not read ${rel}" >&2
    exit 2
  }
  checked=$((checked + 1))
  if [ "$n" -gt "$MAX" ]; then
    over="${over}${n}	${rel}
"
  fi
  if [ "$longest" -lt "$n" ] || [ -z "$longest_file" ]; then
    longest="$n"
    longest_file="$rel"
  fi
done <<EOF
$files
EOF

if [ "$checked" -eq 0 ]; then
  echo "❌ FAIL: no production .go file in ${ROOT} — a scan over nothing is no pass"
  exit 1
fi

if [ -n "$over" ]; then
  printf '%s' "$over" | sort -t '	' -k1,1nr -k2,2 | while IFS='	' read -r n rel; do
    echo "❌ FAIL: ${rel}: ${n} lines, over the ${MAX}-line limit"
  done
  count="$(printf '%s' "$over" | grep -c .)"
  echo "❌ FAIL: ${count} Go production file(s) over ${MAX} lines — split them (CONVENTIONS.md, Code)"
  exit 1
fi

echo "OK: all ${checked} Go production files in ${ROOT} within the ${MAX}-line limit (longest: ${longest_file}, ${longest} lines)"
exit 0
