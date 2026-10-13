#!/usr/bin/env bash
# Scripts/test_sfl_pull.sh
#
# Ported unchanged from another estate repository 2026-10-01 (forsgren#1): a stub git
# on PATH pins that sfl pulls with --ff-only and stops with exit 3, naming
# the recovery command, when it cannot fast-forward.

set -euo pipefail

cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
# Issue forsgren#137. On bash 3.2 an abort (an unbound variable under set -eu)
# ends a script with an EXIT trap with status 0, and $? in the trap is 0 too.
# COMPLETED, set as the very last statement, is the only way out with 0: an
# exit of 0 without it is an abort and becomes exit 1. Gate:
# Scripts/check_exit_trap_completion.sh.
COMPLETED=0
finish() {
  local rc=$?
  rm -rf "$$TMP"
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: test_sfl_pull.sh aborted before completing (COMPLETED was never set)" >&2
    exit 1
  fi
}
trap finish EXIT

mkdir -p "$TMP/bin"

cat > "$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALLS"
exit "${GIT_RESULT:-0}"
EOF
chmod +x "$TMP/bin/git"

export PATH="$TMP/bin:$PATH"
export GIT_CALLS="$TMP/git-calls.log"

# shellcheck source=Scripts/sfl_pull.sh
source Scripts/sfl_pull.sh


failed=0

fail() {
  echo "❌ FAIL: $*"
  failed=1
}

echo "[1/3] clean fast-forward succeeds"
: > "$GIT_CALLS"
GIT_RESULT=0
export GIT_RESULT

if ! sfl_pull_or_stop >"$TMP/stdout" 2>"$TMP/stderr"; then
  fail "successful git pull --ff-only was rejected"
fi

if ! grep -qxF "pull --ff-only" "$GIT_CALLS"; then
  fail "successful path did not run exactly: git pull --ff-only"
fi

if [ -s "$TMP/stderr" ]; then
  fail "successful pull unexpectedly wrote a recovery message"
fi

echo "[2/3] failed fast-forward returns 3"
: > "$GIT_CALLS"
GIT_RESULT=1
export GIT_RESULT

set +e
sfl_pull_or_stop >"$TMP/stdout" 2>"$TMP/stderr"
rc=$?
set -e

if [ "$rc" -ne 3 ]; then
  fail "failed git pull returned ${rc}; expected 3"
fi

if ! grep -qxF "pull --ff-only" "$GIT_CALLS"; then
  fail "failure path did not run exactly: git pull --ff-only"
fi

echo "[3/3] failure names the manual recovery command"
if ! grep -qF "git pull --rebase --autostash" "$TMP/stderr"; then
  fail "failure did not name the manual rebase/autostash recovery command"
fi

if [[ "$failed" -ne 0 ]]; then
  echo
  echo "FAIL: sfl pull contract is not preserved"
  exit 1
fi

echo
echo "OK: sfl pull uses ff-only and stops with exit 3 when it cannot fast-forward"
COMPLETED=1
