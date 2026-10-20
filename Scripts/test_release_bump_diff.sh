#!/usr/bin/env bash
# Scripts/test_release_bump_diff.sh
#
# Self-test for Scripts/release_bump_diff.sh (forsgren#230, step 1 of 2): the
# check that a release's bump commit holds nothing but the version bump. The
# fixture is a small repository in a temp directory with the files a bump
# touches, a green commit, and the bump made by the real
# Scripts/release_bump.sh (a patch bump), committed on top of it.
#   1. the real bump on the green commit                          -> OK
#   2. one other line changed in an allowed file                  -> red, file:line
#   3. a version replaced in a line that also changes more        -> red, file:line
#   4. a line added, a line removed (an uneven hunk)              -> red
#   5. a file outside the set (SHIPPED.md), a new file, a mode    -> red
#   6. the parent is not the green commit, a merge commit         -> red
#   7. an unknown commit -> red; a malformed version, no argument -> exit 2
# Mutation proofs: a copy that no longer compares the parent must let the
# wrong-parent bump pass, one that accepts any line of an allowed file must
# let the extra-line bump pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release bump diff self-test"

DIFF="Scripts/release_bump_diff.sh"
[[ -f "$DIFF" ]] || selftest_abort "${DIFF} does not exist — a bump commit would be released without being read"

OLD_V="1.2.3"
NEW_V="1.2.4"
FX="${TMP}/fx"

# g <args>: git in the fixture, with an identity and no signing.
g() {
  git -C "$FX" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"
}

# The fixture: the files a bump touches, one file it must not, the scripts.
mkdir -p "$FX/cmd/forsgren" "$FX/internal/page/testdata" "$FX/docs" "$FX/Scripts"
printf 'package main\n\nvar version = "%s"\n\nfunc c() int { return 3 }\n' "$OLD_V" > "$FX/cmd/forsgren/main.go"
printf '# Title\n\nPage footer: Forsgren <version>\nsecond line\n' > "$FX/README.md"
printf '# Guide\n\nforsgren <version>\nneeds more configuration\n\nUpgrading to 1.2.2\n' > "$FX/docs/guide.md"
printf '# Shipped\n' > "$FX/SHIPPED.md"
cp Scripts/release_bump.sh Scripts/release_bump_diff.sh Scripts/lib_release_bump_scope.sh Scripts/release_bump_scope.txt "$FX/Scripts/"
g init -q -b main
g add -A
g commit -q -m green
GREEN="$(g rev-parse HEAD)"

# bump_on <branch> <parent>: the real bump of the fixture, in the work tree
# on a new branch at <parent>, left uncommitted.
bump_on() {
  g checkout -q -b "$1" "$2"
  (cd "$FX" && Scripts/release_bump.sh "$NEW_V" > "${TMP}/bump.log" 2>&1) || selftest_abort "the real bump of the fixture failed: $(cat "${TMP}/bump.log")"
}
# commit_bump: commits everything in the work tree and prints the sha.
commit_bump() {
  g add -A
  g commit -q -m "bump"
  g rev-parse HEAD
}
# check <script> <bump> [green]: the script of the fixture (or a mutant), run there.
run_diff() {
  capture "$1" "$2" "${3:-$GREEN}" "$OLD_V" "$NEW_V"
}
DIFFSCRIPT="${FX}/Scripts/release_bump_diff.sh"

# 1
bump_on good "$GREEN"
GOOD="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$GOOD"
want_green "the real bump on the green commit" "OK: ${GOOD} only bumps ${OLD_V} to ${NEW_V} on top of the green ${GREEN}"
git_changed="$(g diff --name-only "$GREEN" "$GOOD" | wc -l | tr -d ' ')"
if [[ "$git_changed" -ge 1 ]]; then
  echo "  ok: the fixture bump changed ${git_changed} files (the case above is not vacuous)"
else
  fail "the fixture bump changed only ${git_changed} files, the green case proves little"
fi

# 2: one other line in an allowed file (the unrelated line of main.go is line 5).
bump_on extraline "$GREEN"
sed -i.bak 's#return 3#return 4#' "$FX/cmd/forsgren/main.go"
rm "$FX/cmd/forsgren/main.go.bak"
EXTRALINE="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$EXTRALINE"
want_red "one other line changed in an allowed file" "❌ FAIL: bump diff: cmd/forsgren/main.go:5 changes more than the version"

# 3: the version replaced in a line that also changes something else.
bump_on moreinline "$GREEN"
sed -i.bak "s#var version = \"${NEW_V}\"#var version = \"${NEW_V}\" // and more#" "$FX/cmd/forsgren/main.go"
rm "$FX/cmd/forsgren/main.go.bak"
MOREINLINE="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$MOREINLINE"
want_red "a bumped line that also changes more" "❌ FAIL: bump diff: cmd/forsgren/main.go:3 changes more than the version"
bump_on halfbump "$GREEN"
sed -i.bak "s#var version = \"${NEW_V}\"#var version = \"9.9.9\"#" "$FX/cmd/forsgren/main.go"
rm "$FX/cmd/forsgren/main.go.bak"
HALFBUMP="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$HALFBUMP"
want_red "the version replaced by another version" "❌ FAIL: bump diff: cmd/forsgren/main.go:3 changes more than the version"

# 4: an uneven hunk.
bump_on uneven "$GREEN"
printf 'func d() int { return 4 }\n' >> "$FX/cmd/forsgren/main.go"
UNEVEN="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$UNEVEN"
want_red "a line added next to the bump" "❌ FAIL: bump diff: cmd/forsgren/main.go:6 changes more than the version (0 lines removed, 1 added)"

# 5: files outside the set.
bump_on shipped "$GREEN"
printf 'a new entry\n' >> "$FX/SHIPPED.md"
SHIPPED="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$SHIPPED"
want_red "SHIPPED.md changed" "❌ FAIL: bump diff: SHIPPED.md: is not a file the bump changes"
bump_on readme "$GREEN"
printf 'more\n' >> "$FX/README.md"
README_CHANGED="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$README_CHANGED"
want_red "README.md changed (the docs name no running version)" "❌ FAIL: bump diff: README.md: is not a file the bump changes"
bump_on docs "$GREEN"
printf 'more\n' >> "$FX/docs/guide.md"
DOC_CHANGED="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$DOC_CHANGED"
want_red "a doc changed" "❌ FAIL: bump diff: docs/guide.md: is not a file the bump changes"
bump_on newfile "$GREEN"
printf 'echo hi\n' > "$FX/cmd/forsgren/extra.go"
NEWFILE="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$NEWFILE"
want_red "a new file" "❌ FAIL: bump diff: cmd/forsgren/extra.go: the bump A, it only modifies files"
bump_on script "$GREEN"
printf '# more\n' >> "$FX/Scripts/release_bump.sh"
SCRIPT_CHANGED="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$SCRIPT_CHANGED"
want_red "a script changed" "❌ FAIL: bump diff: Scripts/release_bump.sh: is not a file the bump changes"
bump_on mode "$GREEN"
chmod +x "$FX/cmd/forsgren/main.go"
MODE="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$MODE"
want_red "a mode change" "❌ FAIL: bump diff: cmd/forsgren/main.go: the mode changed from 100644 to 100755"

# 6: the parent. A bump on a commit that is not the green one, and a merge.
g checkout -q -b other "$GREEN"
g commit -q --allow-empty -m "another commit"
OTHER="$(g rev-parse HEAD)"
bump_on wrongparent "$OTHER"
WRONGPARENT="$(commit_bump)"
run_diff "$DIFFSCRIPT" "$WRONGPARENT"
want_red "the parent is not the green commit" "❌ FAIL: bump diff: the parent is ${OTHER}, not the green ${GREEN}"
MERGE="$(g commit-tree "$(g rev-parse "${GOOD}^{tree}")" -p "$GREEN" -p "$OTHER" -m merge)"
run_diff "$DIFFSCRIPT" "$MERGE"
want_red "a merge commit" "❌ FAIL: bump diff: ${MERGE} is a merge commit"

# 7
run_diff "$DIFFSCRIPT" "0000000000000000000000000000000000000001"
want_red "an unknown commit" "is no commit of this repository"
capture "$DIFFSCRIPT" "$GOOD" "$GREEN" "1.2" "$NEW_V"
want_exit "a malformed version" 2 "usage"
capture "$DIFFSCRIPT"
want_exit "no argument" 2 "usage"

# Mutation proofs: each on a copy of the fixture repository, so the mutant
# finds its libraries and the same commits.
mutant() {
  rm -rf "${TMP:?}/mut/$1"
  mkdir -p "${TMP}/mut"
  cp -R "$FX" "${TMP}/mut/$1"
  selftest_mutant "$DIFF" "${TMP}/mut/$1/Scripts/release_bump_diff.sh" "$2"
}
if mutant parent 's/if \[ "[$]PARENT" != "[$]GREEN" \]; then/if false; then/'; then
  run_diff "${TMP}/mut/parent/Scripts/release_bump_diff.sh" "$WRONGPARENT"
  want_green "mutation proof: without the parent comparison a bump on another commit is accepted" "OK:"
fi
if mutant lines 's/if (bump([$]rem\[[$]i\]) ne [$]add\[[$]i\])/if (0)/'; then
  run_diff "${TMP}/mut/lines/Scripts/release_bump_diff.sh" "$EXTRALINE"
  want_green "mutation proof: accepting any line of an allowed file lets the extra line pass" "OK:"
fi

selftest_end "the release bump diff does not hold" "release bump diff: only the version bump on the green parent passes, an extra line, an extra file and another parent are refused"
