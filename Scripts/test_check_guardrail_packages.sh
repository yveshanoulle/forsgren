#!/usr/bin/env bash
# Scripts/test_check_guardrail_packages.sh
#
# Self-test for Scripts/check_guardrail_packages.sh, the npm manifest policy
# gate (forsgren#1, ladder step 7), run before the gate it validates.
#
# NEW IN forsgren. The gate is ported byte-identical from konenki-website
# (where it is also identical to coachretreat-website's copy), but no repo of
# the estate has a self-test for it: there it runs unvalidated. forsgren's
# rule is that a ported gate comes with its fixtures, seen green, plus one
# mutation seen red, so this file is forsgren's own.
#
# The gate anchors itself with `cd "$(dirname "$0")/.."`, so each case copies
# it into Scripts/ of a throwaway git repository and runs that copy.
#   1. exact pins, manifest and lockfile tracked      -> green
#   2. a caret range in package.json                  -> red, quoting the range
#   3. a tilde range in package.json                  -> red, quoting the range
#   4. no package-lock.json                           -> red, naming the file
#   5. package-lock.json present but gitignored       -> red, naming the file
#   6. node_modules/ tracked                          -> red
#   7. manifest and lockfile present, not yet added   -> green, with the INFO
#                                                        line (the commit that
#                                                        introduces them)
# Mutation proof: case 2 against a copy of the gate whose range check is
# removed must turn green, so case 2 is red BECAUSE of that check, not because
# of something else in its repository.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="$(pwd)/Scripts/check_guardrail_packages.sh"

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: npm manifest policy self-test aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

if [[ ! -f "$GATE" ]]; then
  fail "${GATE} does not exist — the npm manifest policy has no gate to validate"
  COMPLETED=1
  exit 1
fi

EXACT_MANIFEST='{
  "name": "acme-app",
  "private": true,
  "devDependencies": {
    "htmlhint": "1.9.2",
    "stylelint": "17.14.1"
  }
}
'
LOCKFILE='{
  "name": "acme-app",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {}
}
'

# new_repo <name> [gate-copy] — a git repository with the gate (or the given
# copy of it) at Scripts/check_guardrail_packages.sh.
new_repo() {
  REPO="${TMP}/$1"
  mkdir -p "${REPO}/Scripts"
  git -C "$REPO" init -q
  cp "${2:-$GATE}" "${REPO}/Scripts/check_guardrail_packages.sh"
  chmod +x "${REPO}/Scripts/check_guardrail_packages.sh"
}

# write_file <path> <content> [track] — writes a file; `track` git-adds it.
write_file() {
  mkdir -p "$(dirname "${REPO}/$1")"
  printf '%s' "$2" > "${REPO}/$1"
  if [[ "${3:-}" == "track" ]]; then
    git -C "$REPO" add -f "$1"
  fi
}

# run_gate — runs the repository's copy of the gate; sets RC and OUT.
run_gate() {
  set +e
  OUT="$("${REPO}/Scripts/check_guardrail_packages.sh" 2>&1)"
  RC=$?
  set -e
}

# expect_red <case> <needle> — the gate failed and its output carries needle.
expect_red() {
  if [[ "$RC" -eq 0 ]]; then
    fail "$1: the gate passed — want red. Output: ${OUT}"
  elif ! grep -Fq -- "$2" <<< "$OUT"; then
    fail "$1: the gate failed, but its output does not carry '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# expect_green <case> [needle] — the gate passed (and printed needle).
expect_green() {
  if [[ "$RC" -ne 0 ]]; then
    fail "$1: the gate failed — want green. Output: ${OUT}"
  elif [[ -n "${2:-}" ]] && ! grep -Fq -- "$2" <<< "$OUT"; then
    fail "$1: the gate passed, but its output does not carry '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# --- 1. exact pins, both files tracked -> green ----------------------------
new_repo exact
write_file package.json "$EXACT_MANIFEST" track
write_file package-lock.json "$LOCKFILE" track
run_gate
expect_green "1. exact pins, manifest and lockfile tracked" \
  "OK: manifest and lockfile committed, versions exact"

# --- 2. a caret range -> red ----------------------------------------------
new_repo caret
write_file package.json "${EXACT_MANIFEST/\"17.14.1\"/\"^17.14.1\"}" track
write_file package-lock.json "$LOCKFILE" track
run_gate
expect_red "2. a caret range in package.json" '"stylelint": "^17.14.1"'

# --- 3. a tilde range -> red ----------------------------------------------
new_repo tilde
write_file package.json "${EXACT_MANIFEST/\"1.9.2\"/\"~1.9.2\"}" track
write_file package-lock.json "$LOCKFILE" track
run_gate
expect_red "3. a tilde range in package.json" '"htmlhint": "~1.9.2"'

# --- 4. no lockfile -> red ------------------------------------------------
new_repo nolock
write_file package.json "$EXACT_MANIFEST" track
run_gate
expect_red "4. no package-lock.json" "package-lock.json is missing"

# --- 5. lockfile gitignored -> red ----------------------------------------
new_repo ignored
write_file .gitignore $'package-lock.json\n' track
write_file package.json "$EXACT_MANIFEST" track
write_file package-lock.json "$LOCKFILE"
run_gate
expect_red "5. package-lock.json gitignored" \
  "package-lock.json exists but .gitignore excludes it"

# --- 6. node_modules tracked -> red ---------------------------------------
new_repo nodemods
write_file package.json "$EXACT_MANIFEST" track
write_file package-lock.json "$LOCKFILE" track
write_file node_modules/acme/index.js $'module.exports = 1;\n' track
run_gate
expect_red "6. node_modules/ tracked" "node_modules must not be committed"

# --- 7. both present, not yet added -> green with INFO ---------------------
new_repo untracked
write_file package.json "$EXACT_MANIFEST"
write_file package-lock.json "$LOCKFILE"
run_gate
expect_green "7. manifest and lockfile present, not yet added" \
  "INFO: package-lock.json is present and not ignored, not yet committed"

# --- Mutation proof --------------------------------------------------------
# Case 2 against a gate whose range check is gone must turn green; otherwise
# case 2's red came from something else in its repository.
MUTANT="${TMP}/check_guardrail_packages.no-range-check.sh"
sed 's/\[\\^~\]/[!]/' "$GATE" > "$MUTANT"
if cmp -s "$GATE" "$MUTANT"; then
  fail "mutation proof: removing the range check changed nothing in ${GATE} — the sed no longer matches, so this proof proves nothing"
else
  new_repo mutant "$MUTANT"
  write_file package.json "${EXACT_MANIFEST/\"17.14.1\"/\"^17.14.1\"}" track
  write_file package-lock.json "$LOCKFILE" track
  run_gate
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof: case 2 is still red with the range check removed, so its red does not come from that check. Output: ${OUT}"
  else
    echo "  ok: mutation proof: case 2 turns green with the range check removed"
  fi
fi

COMPLETED=1
if [[ "$failed" -ne 0 ]]; then
  echo "❌ FAIL: npm manifest policy self-test"
  exit 1
fi
echo "OK: npm manifest policy gate passes exact pins and catches ranges, a missing or ignored lockfile and tracked node_modules"
