#!/usr/bin/env bash
# Scripts/test_npm_sync_install.sh
#
# Self-test for Scripts/npm_sync_install.sh, sfl's npm install step
# (forsgren#2, ladder step 2), run before sfl relies on it. No network: a stub
# `npm` first on PATH records each call in $NPM_LOG and, unless NPM_FAIL is
# set, creates node_modules/ like `npm ci` does (it deletes the old one first).
#   1. no node_modules                      -> npm ci runs, the stamp is written
#   2. stamp equals the lockfile's hash     -> npm ci does not run
#   3. the lockfile changed                 -> npm ci runs, the stamp follows
#   4. node_modules without a stamp         -> npm ci runs, the stamp is written
#   5. npm ci fails                         -> exit 1, red cross, no stamp
#   6. npm ci fails after a lockfile change -> the OLD stamp is gone too, so the
#                                              next run installs again
#   7. no package-lock.json                 -> red, npm ci does not run
# Mutation proof: case 2 against a copy of the script that never compares
# the stamp must run npm ci, so case 2 holds BECAUSE of the comparison.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

SCRIPT="$(pwd)/Scripts/npm_sync_install.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "npm install sync self-test"

[[ -f "$SCRIPT" ]] || selftest_abort "${SCRIPT} does not exist — sfl has no npm install step to validate"

STUBS="${TMP}/bin"
mkdir -p "$STUBS"
cat > "${STUBS}/npm" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$NPM_LOG"
if [ -n "${NPM_FAIL:-}" ]; then
  echo "npm ERR! stub failure" >&2
  exit 1
fi
rm -rf node_modules
mkdir -p node_modules/.bin
STUB
chmod +x "${STUBS}/npm"
export NPM_LOG="${TMP}/npm.log"
export PATH="${STUBS}:${PATH}"

STAMP_FILE="node_modules/.package-lock.sha256"

# new_dir <name> <lock-content> — a directory with a lockfile; sets DIR.
new_dir() {
  DIR="${TMP}/$1"
  mkdir -p "$DIR"
  printf '%s' "$2" > "${DIR}/package-lock.json"
  : > "$NPM_LOG"
}

# ci_runs — how many times the stub npm was called.
ci_runs() {
  wc -l < "$NPM_LOG" | tr -d ' '
}

# lock_hash <dir> — the sha256 of the directory's lockfile.
lock_hash() {
  shasum -a 256 "$1/package-lock.json" | awk '{ print $1 }'
}

# want_runs <case> <count> — the stub npm was called exactly <count> times.
want_runs() {
  if [[ "$(ci_runs)" == "$2" ]]; then
    echo "  ok: $1"
  else
    fail "$1: npm ci ran $(ci_runs) times, wanted $2"
  fi
}

# want_stamp <case> <dir> — the stamp holds the hash of the directory's lockfile.
want_stamp() {
  if [[ "$(cat "$2/${STAMP_FILE}" 2>/dev/null)" == "$(lock_hash "$2")" ]]; then
    echo "  ok: $1"
  else
    fail "$1: the stamp is missing or does not hold the lockfile hash"
  fi
}

# want_no_stamp <case> <dir> — there is no stamp.
want_no_stamp() {
  if [[ -e "$2/${STAMP_FILE}" ]]; then
    fail "$1: a stamp exists"
  else
    echo "  ok: $1"
  fi
}

# run_script <script> — runs it on DIR; sets RC and OUT.
run_script() {
  capture "$1" "$DIR"
}

# --- 1. no node_modules ----------------------------------------------------
new_dir fresh 'lock one'
run_script "$SCRIPT"
want_green_ok "1. no node_modules: runs"
want_runs "1. npm ci ran once" 1
want_stamp "1. the stamp holds the lockfile hash" "$DIR"
SAME_DIR="$DIR"

# --- 2. same stamp -> no npm ci ---------------------------------------------
: > "$NPM_LOG"
run_script "$SCRIPT"
want_green_ok "2. same stamp"
want_runs "2. npm ci did not run" 0

# --- 3. changed lockfile -> npm ci, new stamp --------------------------------
printf '%s' 'lock two' > "${SAME_DIR}/package-lock.json"
: > "$NPM_LOG"
run_script "$SCRIPT"
want_green_ok "3. changed lockfile"
want_runs "3. npm ci ran" 1
want_stamp "3. the stamp follows the lockfile" "$SAME_DIR"

# --- 4. node_modules without a stamp -----------------------------------------
new_dir nostamp 'lock one'
mkdir -p "${DIR}/node_modules/.bin"
run_script "$SCRIPT"
want_green_ok "4. node_modules without a stamp"
want_runs "4. npm ci ran" 1
want_stamp "4. the stamp was written" "$DIR"

# --- 5. failing npm ci -> red, no stamp -----------------------------------------
new_dir failing 'lock one'
NPM_FAIL=1 capture "$SCRIPT" "$DIR"
want_red "5. npm ci fails" "❌ FAIL: npm ci failed"
want_no_stamp "5. no stamp after a failure" "$DIR"

# --- 6. failure after a change -> the old stamp does not survive -----------------
new_dir failafter 'lock one'
run_script "$SCRIPT"
printf '%s' 'lock two' > "${DIR}/package-lock.json"
NPM_FAIL=1 capture "$SCRIPT" "$DIR"
want_red "6. npm ci fails after a lockfile change" "❌ FAIL: npm ci failed"
want_no_stamp "6. the old stamp is gone" "$DIR"

# --- 7. no lockfile --------------------------------------------------------------
new_dir nolock 'x'
rm "${DIR}/package-lock.json"
: > "$NPM_LOG"
run_script "$SCRIPT"
want_red "7. no package-lock.json" "package-lock.json is missing"
want_runs "7. npm ci did not run" 0

# --- mutation proof: the stamp is never compared -> case 2 runs npm ci -----------
NEVER_EQUAL="s/\\[ \"\\\$stamp\" = \"\\\$want\" \\]/false/"
if selftest_mutant "$SCRIPT" "${TMP}/mutant/Scripts/npm_sync_install.sh" "$NEVER_EQUAL"; then
  : > "$NPM_LOG"
  DIR="$SAME_DIR"
  capture "${TMP}/mutant/Scripts/npm_sync_install.sh" "$DIR"
  if [[ "$(ci_runs)" == "1" ]]; then
    echo "  ok: mutation proof: without the comparison npm ci runs again, so case 2 holds because of it"
  else
    fail "mutation proof: the comparison-less script did not run npm ci for an unchanged lockfile"
  fi
fi

selftest_end "the npm install sync does not hold" \
  "npm install sync: installs when node_modules or the stamp is missing or stale, skips when current, writes the stamp only after success; mutation proven"
