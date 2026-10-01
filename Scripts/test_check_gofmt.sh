#!/usr/bin/env bash
# Scripts/test_check_gofmt.sh
#
# Self-test for Scripts/check_gofmt.sh, run before the gate it validates.
# Each case is a throwaway git repository under one temp root:
#   1. a formatted file              -> green
#   2. an unformatted tracked file   -> red, naming the file
#   3. an unformatted UNTRACKED file -> red (a new file is checked too)
#   4. an unformatted ignored file   -> green (agent worktrees are skipped)
#   5. no Go files                   -> red
#   6. --fix rewrites the file, and the check-only run is then green
#   7. a file gofmt cannot parse     -> red in check-only mode

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="$(pwd)/Scripts/check_gofmt.sh"

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: gofmt gate self-test aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

FORMATTED=$'package m\n\n// Two returns 2.\nfunc Two() int { return 2 }\n'
UNFORMATTED=$'package m\nfunc   Two()  int {return 2}\n'

# new_repo <name> — an empty git repository with a .gitignore like forsgren's.
new_repo() {
  REPO="${TMP}/$1"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  printf '.claude/worktrees/\n' > "${REPO}/.gitignore"
}

# write_go <path> <content> [track] — writes a Go file; `track` git-adds it.
write_go() {
  mkdir -p "$(dirname "${REPO}/$1")"
  printf '%s' "$2" > "${REPO}/$1"
  if [[ "${3:-}" == "track" ]]; then
    git -C "$REPO" add "$1"
  fi
}

# run_gate [--fix] — runs the gate against $REPO; sets RC and OUT.
run_gate() {
  set +e
  OUT="$("$GATE" "$@" "$REPO" 2>&1)"
  RC=$?
  set -e
}

want_green() {
  if [[ "$RC" -ne 0 ]]; then
    fail "$1: the gate exited ${RC}. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

want_red() {
  if [[ "$RC" -eq 0 ]]; then
    fail "$1: the gate exited 0. Output: ${OUT}"
  elif ! grep -qF -- "$2" <<< "$OUT"; then
    fail "$1: the gate failed without saying '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

new_repo "formatted"
write_go "m.go" "$FORMATTED" track
run_gate
want_green "a formatted file is green"

new_repo "tracked"
write_go "m.go" "$UNFORMATTED" track
run_gate
want_red "an unformatted tracked file is red and named" "not gofmt-formatted: m.go"

new_repo "untracked"
write_go "m.go" "$FORMATTED" track
write_go "new.go" "$UNFORMATTED"
run_gate
want_red "an unformatted untracked file is red and named" "not gofmt-formatted: new.go"

new_repo "ignored"
write_go "m.go" "$FORMATTED" track
write_go ".claude/worktrees/agent/x.go" "$UNFORMATTED"
run_gate
want_green "an unformatted file in an ignored agent worktree is skipped"

new_repo "empty"
run_gate
want_red "no Go files is red" "no Go files found"

new_repo "fix"
write_go "m.go" "$UNFORMATTED" track
run_gate --fix
want_green "--fix succeeds on an unformatted file"
if ! grep -qF "gofmt -w rewrote: m.go" <<< "$OUT"; then
  fail "--fix did not list the file it rewrote. Output: ${OUT}"
fi
if [[ "$(cat "${REPO}/m.go")" != "$(printf '%s' "$UNFORMATTED" | gofmt)" ]]; then
  fail "--fix left m.go unformatted: $(cat "${REPO}/m.go")"
fi
run_gate
want_green "after --fix the check-only run is green"

new_repo "broken"
write_go "m.go" $'package m\nfunc {\n' track
run_gate
want_red "a file gofmt cannot parse is red" "could not parse"

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: the gofmt gate does not tell formatted from unformatted (see the FAIL lines above)"
  exit 1
fi

echo "OK: gofmt gate is red on unformatted (tracked or new), unparsable and missing Go files, skips ignored worktrees, and --fix rewrites"
