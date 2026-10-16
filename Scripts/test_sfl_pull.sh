#!/usr/bin/env bash
# canon: test_sfl_pull v1
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# Scripts/test_sfl_pull.sh
#
# The sfl pull contract, shared by every repo of the estate: `git pull --ff-only`;
# on anything else, print the manual recovery command to stderr and stop with
# exit 3, never warn-and-continue.
#
# THIS FIXTURE ALSO PINS THE WIRING. It is not enough for Scripts/sfl_pull.sh
# to behave correctly in isolation (cases 1/2/3 below) if sfl.sh never calls it, or if the old warn-and-continue
# step ("Update from origin (git pull --ff-only)", sfl.sh's Step 1) is still
# sitting there beside it. Both angles are asserted so a half-port — the
# shared function landing without sfl.sh being rewired to use it, or the
# reverse — still reds here.
#
# sfl.sh sources Scripts/sfl_pull.sh and runs `sfl_pull_or_stop || exit 3` as
# its opening pull; the wiring pins below keep it that way.
#
# MUTATION PROOF, at the end: the behavioural cases run against weakened copies
# of Scripts/sfl_pull.sh (a failed pull that returns 0, a pull without --ff-only,
# a silent failure), and each copy must be red. The script under test is the
# optional first argument; without one it is the real script and the mutation
# proof runs.
SRC="${1:-Scripts/sfl_pull.sh}"
SELF="${PWD}/Scripts/test_sfl_pull.sh"

COMPLETED=0
finish() {
  if [ "$COMPLETED" -ne 1 ]; then
    echo "❌ FAIL: sfl-pull fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap finish EXIT

failed=0
fail() { echo "❌ FAIL: $*"; failed=1; }

echo "test_sfl_pull"

# --- Wiring pins against sfl.sh ---------------------------------------

if grep -q 'WARN: git pull --ff-only refused' sfl.sh || grep -q 'Proceeding with current local state for now' sfl.sh; then
  fail "sfl.sh still warns and continues on a diverged pull (its old 'Update from origin' step) instead of stopping with exit 3"
else
  echo "OK:   the old warn-and-continue pull step is gone from sfl.sh"
fi

if grep -q 'source Scripts/sfl_pull.sh' sfl.sh && grep -qE 'sfl_pull_or_stop *\|\| *exit 3' sfl.sh; then
  echo "OK:   sfl.sh sources Scripts/sfl_pull.sh and stops with exit 3 when sfl_pull_or_stop fails"
else
  fail "sfl.sh does not source Scripts/sfl_pull.sh and call sfl_pull_or_stop with '|| exit 3' — its opening pull is not wired to the shared contract"
fi

# --- Behavioural pins on Scripts/sfl_pull.sh itself --------------------

if [ ! -f "$SRC" ]; then
  fail "${SRC} does not exist yet — the shared pull contract has no implementation to source"
else
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/bin"

  cat > "$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALLS"
exit "${GIT_RESULT:-0}"
EOF
  chmod +x "$TMP/bin/git"

  PATH="$TMP/bin:$PATH"
  export PATH
  GIT_CALLS="$TMP/git-calls.log"
  export GIT_CALLS

  # shellcheck source=Scripts/sfl_pull.sh
  source "$SRC"

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

  rm -rf "$TMP"
fi

# --- Mutation proof: weakened copies of Scripts/sfl_pull.sh must be red here.
if [ $# -eq 0 ]; then
  MUT="$(mktemp -d)"
  mutant_must_fail() { # <label> <sed-expression>
    local m="$MUT/sfl_pull_$RANDOM.sh"
    sed "$2" "$SRC" > "$m"
    if cmp -s "$SRC" "$m"; then
      fail "mutation '$1' changed nothing: it proves nothing"; return
    fi
    if "$SELF" "$m" >/dev/null 2>&1; then
      fail "mutation '$1' PASSED this fixture: the cases do not guard it"
    else
      echo "OK:   mutation '$1' is red"
    fi
  }
  mutant_must_fail "a failed pull returns 0" 's/^  return 3$/  return 0/'
  mutant_must_fail "the pull is not --ff-only" 's/git pull --ff-only; then/git pull; then/'
  mutant_must_fail "the recovery command is not named" 's/git pull --rebase --autostash/git pull/'
  rm -rf "$MUT"
fi

COMPLETED=1

if [ "$failed" -ne 0 ]; then
  echo
  echo "FAIL: sfl pull contract is not preserved"
  exit 1
fi

echo
echo "OK: sfl pull uses ff-only, stops with exit 3 on divergence, and sfl.sh is wired to it"
