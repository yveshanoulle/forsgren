#!/usr/bin/env bash
# canon: test_check_guardrail_packages v1
# Scripts/test_check_guardrail_packages.sh
#
# Self-test for Scripts/check_guardrail_packages.sh, the npm manifest policy
# gate, run before the gate it validates. A ported gate comes
# with its fixtures, seen green, plus one mutation seen red.
#
# The gate anchors itself with `cd "$(dirname "$0")/.."`, so each case copies
# it into Scripts/ of a throwaway git repository and runs that copy.
#   1. exact pins, manifest and lockfile tracked      -> green
#   2. a caret range in package.json                  -> red, quoting the range
#   3. a tilde range in package.json                  -> red, quoting the range
#   4. no package-lock.json                           -> red, naming the file
#   5. package-lock.json present but gitignored       -> red, naming the file
#   6. node_modules/ tracked                          -> red
#   8. node_modules/ untracked and not ignored        -> red
#   9. node_modules/ ignored                          -> green
#  10. node_modules a symlink, under the real .gitignore -> green
#  11. node_modules a symlink, not ignored              -> red
#   7. manifest and lockfile present, not yet added   -> green, with the INFO
#                                                        line (the commit that
#                                                        introduces them)
# Mutation proof: case 2 against a copy of the gate whose range check is
# removed must turn green, so case 2 is red BECAUSE of that check, not because
# of something else in its repository.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="$(pwd)/Scripts/check_guardrail_packages.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "npm manifest policy self-test"

[[ -f "$GATE" ]] || selftest_abort "${GATE} does not exist — the npm manifest policy has no gate to validate"

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
  cp "$(dirname "$GATE")/lib_repo_files.sh" "${REPO}/Scripts/lib_repo_files.sh"
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
  capture "${REPO}/Scripts/check_guardrail_packages.sh"
}

# --- 1. exact pins, both files tracked -> green ----------------------------
new_repo exact
write_file package.json "$EXACT_MANIFEST" track
write_file package-lock.json "$LOCKFILE" track
run_gate
want_green "1. exact pins, manifest and lockfile tracked" \
  "OK: manifest and lockfile committed, versions exact"

# --- 2. a caret range -> red ----------------------------------------------
new_repo caret
write_file package.json "${EXACT_MANIFEST/\"17.14.1\"/\"^17.14.1\"}" track
write_file package-lock.json "$LOCKFILE" track
run_gate
want_red "2. a caret range in package.json" '"stylelint": "^17.14.1"'

# --- 3. a tilde range -> red ----------------------------------------------
new_repo tilde
write_file package.json "${EXACT_MANIFEST/\"1.9.2\"/\"~1.9.2\"}" track
write_file package-lock.json "$LOCKFILE" track
run_gate
want_red "3. a tilde range in package.json" '"htmlhint": "~1.9.2"'

# --- 4. no lockfile -> red ------------------------------------------------
new_repo nolock
write_file package.json "$EXACT_MANIFEST" track
run_gate
want_red "4. no package-lock.json" "package-lock.json is missing"

# --- 5. lockfile gitignored -> red ----------------------------------------
new_repo ignored
write_file .gitignore $'package-lock.json\n' track
write_file package.json "$EXACT_MANIFEST" track
write_file package-lock.json "$LOCKFILE"
run_gate
want_red "5. package-lock.json gitignored" \
  "package-lock.json exists but .gitignore excludes it"

# --- 6. node_modules tracked -> red ---------------------------------------
new_repo nodemods
write_file package.json "$EXACT_MANIFEST" track
write_file package-lock.json "$LOCKFILE" track
write_file node_modules/acme/index.js $'module.exports = 1;\n' track
run_gate
want_red "6. node_modules/ tracked" "node_modules must not be committed"

# --- 7. both present, not yet added -> green with INFO ---------------------
new_repo untracked
write_file package.json "$EXACT_MANIFEST"
write_file package-lock.json "$LOCKFILE"
run_gate
want_green "7. manifest and lockfile present, not yet added" \
  "INFO: package-lock.json is present and not ignored, not yet committed"

# --- 8. node_modules new, untracked, not ignored -> red  -------
# The commit that adds it would carry it, so the gate refuses it before.
new_repo nodemods-new
write_file package.json "$EXACT_MANIFEST" track
write_file package-lock.json "$LOCKFILE" track
write_file node_modules/acme/index.js $'module.exports = 1;\n'
run_gate
want_red "8. node_modules/ untracked and not ignored" "node_modules must not be committed"

# --- 9. node_modules ignored -> green --------------------------------------
new_repo nodemods-ignored
write_file .gitignore $'node_modules/\n' track
write_file package.json "$EXACT_MANIFEST" track
write_file package-lock.json "$LOCKFILE" track
write_file node_modules/acme/index.js $'module.exports = 1;\n'
run_gate
want_green "9. node_modules/ ignored" "OK: manifest and lockfile committed"

# --- 10. node_modules as a SYMLINK, under this repository's .gitignore ------
# Writer agents symlink node_modules into a worktree for the HTML gates. A
# .gitignore pattern with a trailing slash matches only a directory, so the
# symlink would be an untracked, not-ignored entry. The
# fixture carries the real .gitignore, so this case reads the real entry.
new_repo nodemods-symlink
cp "$(dirname "$GATE")/../.gitignore" "${REPO}/.gitignore"
git -C "$REPO" add .gitignore
write_file package.json "$EXACT_MANIFEST" track
write_file package-lock.json "$LOCKFILE" track
mkdir -p "${TMP}/elsewhere/node_modules/acme"
printf 'module.exports = 1;\n' > "${TMP}/elsewhere/node_modules/acme/index.js"
ln -s "${TMP}/elsewhere/node_modules" "${REPO}/node_modules"
run_gate
want_green "10. a node_modules symlink, ignored by the repository's own .gitignore" "OK: manifest and lockfile committed"

# --- 11. the same symlink, in a repository that does not ignore it -> red ---
# git add -A would commit the link, so the gate must see it: a bare
# node_modules entry, not only one with a slash after it.
new_repo nodemods-symlink-unignored
write_file package.json "$EXACT_MANIFEST" track
write_file package-lock.json "$LOCKFILE" track
ln -s "${TMP}/elsewhere/node_modules" "${REPO}/node_modules"
run_gate
want_red "11. a node_modules symlink that git does not ignore" "node_modules must not be committed"

# --- Mutation proof --------------------------------------------------------
# Case 2 against a gate whose range check is gone must turn green; otherwise
# case 2's red came from something else in its repository.
MUTANT="${TMP}/check_guardrail_packages.no-range-check.sh"
if selftest_mutant "$GATE" "$MUTANT" 's/\[\\^~\]/[!]/'; then
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

# Mutation proof 2: a gate that lists TRACKED files
# only (git ls-files, as this repo's gate did before) must accept the untracked
# node_modules of case 8 and the symlink of case 11. Both cases are red because
# of the tracked-plus-untracked listing, not of something else in the repository.
MUTANT2="${TMP}/check_guardrail_packages.tracked-only.sh"
if selftest_mutant "$GATE" "$MUTANT2" "s/^listed=\"\$(repo_files \\.)\"/listed=\"\$(git ls-files)\"/"; then
  new_repo mutant-tracked-only "$MUTANT2"
  write_file package.json "$EXACT_MANIFEST" track
  write_file package-lock.json "$LOCKFILE" track
  write_file node_modules/acme/index.js $'module.exports = 1;\n'
  run_gate
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof: case 8 is still red with a tracked-only listing, so its red does not come from the untracked listing. Output: ${OUT}"
  else
    echo "  ok: mutation proof: case 8 turns green with a tracked-only listing"
  fi
  new_repo mutant-tracked-only-link "$MUTANT2"
  write_file package.json "$EXACT_MANIFEST" track
  write_file package-lock.json "$LOCKFILE" track
  ln -s "${TMP}/elsewhere/node_modules" "${REPO}/node_modules"
  run_gate
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof: case 11 is still red with a tracked-only listing. Output: ${OUT}"
  else
    echo "  ok: mutation proof: case 11 turns green with a tracked-only listing"
  fi
fi

selftest_end "npm manifest policy self-test" \
  "npm manifest policy gate passes exact pins and catches ranges, a missing or ignored lockfile and tracked node_modules"
