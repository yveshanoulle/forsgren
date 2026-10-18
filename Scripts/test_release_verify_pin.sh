#!/usr/bin/env bash
# Scripts/test_release_verify_pin.sh
#
# Self-test for Scripts/release_verify_pin.sh (forsgren#221, step 5): the rule
# a pin pull request must meet before the Release workflow merges it, the rule
# of `forsgren check-update` (internal/update, Decide) for the changed files:
# only the two caller workflows, each by one removed and one added pin line of
# the workflow it calls, to this release's version and commit. The pull
# request's files come in as GitHub's list of {filename, patch}.
#   1. exactly the two pins to the release                    -> OK
#   2. another file, a missing caller, no file, no patch        -> red
#   3. a second changed line (a comment) in a caller            -> red
#   4. another version, another sha, another repository, the
#      wrong workflow for the caller, a removed line that is no pin -> red
# Mutation proofs: a copy that no longer refuses another file, one that does
# not compare the sha and one that accepts a second changed line must each
# let their case pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release verify pin self-test"
D='$'

VERIFY="Scripts/release_verify_pin.sh"
[[ -f "$VERIFY" ]] || selftest_abort "${VERIFY} does not exist — a pin pull request would be merged without being read"

SHA="38a22038986a8e9a64d884face1c1972f1ef7f3f"
OLD="50dbb3ddddfabdf4e4e2486fe694c881860ef4a5"
R="acme/forsgren"

# patch <workflow> <old sha> <new sha> <new version> [extra changed line]
patch() {
  local out
  out="@@ -17,4 +17,4 @@ jobs:\n   contents: write\n"
  out+="-    uses: ${R}/.github/workflows/$1@$2 # v1.9.2\n"
  out+="+    uses: ${R}/.github/workflows/$1@$3 # $4\n"
  if [[ -n "${5:-}" ]]; then out+="${5}\n"; fi
  printf '%b' "$out"
}
# file <name> <patch>: one element of the files list.
file() { jq -n --arg f "$1" --arg p "$2" '{filename: $f, patch: $p}'; }

verify() {
  GITHUB_REPOSITORY="$R" capture "${SCRIPT:-$VERIFY}" "$@" < "${TMP}/files.json"
}
setfiles() { jq -s '.' > "${TMP}/files.json"; }

GOOD_MAIN="$(patch metrics.yml "$OLD" "$SHA" v1.9.4)"
GOOD_UPD="$(patch auto_update.yml "$OLD" "$SHA" v1.9.4)"

{ file .github/workflows/forsgren.yml "$GOOD_MAIN"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; } | setfiles
verify 1.9.4 "$SHA"
want_green "both pins to the release" "OK: the pull request only moves the forsgren pins of both callers to v1.9.4 at ${SHA}"

# 2
{ file .github/workflows/forsgren.yml "$GOOD_MAIN"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; file README.md "$(patch metrics.yml "$OLD" "$SHA" v1.9.4)"; } | setfiles
verify 1.9.4 "$SHA"
want_red "another file is changed" "changes README.md, which is no forsgren caller workflow"
{ file .github/workflows/forsgren.yml "$GOOD_MAIN"; } | setfiles
verify 1.9.4 "$SHA"
want_red "a caller is not moved" "does not change .github/workflows/forsgren-update.yml"
echo '[]' > "${TMP}/files.json"
verify 1.9.4 "$SHA"
want_red "no file" "does not change .github/workflows/forsgren.yml"
{ file .github/workflows/forsgren.yml "$GOOD_MAIN"; jq -n '{filename: ".github/workflows/forsgren-update.yml"}'; } | setfiles
verify 1.9.4 "$SHA"
want_red "a file with no patch" ".github/workflows/forsgren-update.yml: want one removed and one added line, got 0 and 0"

# 3
{ file .github/workflows/forsgren.yml "$(patch metrics.yml "$OLD" "$SHA" v1.9.4 '-# v1.9.2\n+# v1.9.4')"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; } | setfiles
verify 1.9.4 "$SHA"
want_red "a comment line changed too" ".github/workflows/forsgren.yml: want one removed and one added line, got 2 and 2"

# 4
{ file .github/workflows/forsgren.yml "$(patch metrics.yml "$OLD" "$SHA" v1.9.3)"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; } | setfiles
verify 1.9.4 "$SHA"
want_red "another version" ".github/workflows/forsgren.yml: the added line is not the pin of metrics.yml at v1.9.4 and ${SHA}"
{ file .github/workflows/forsgren.yml "$(patch metrics.yml "$OLD" "$OLD" v1.9.4)"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; } | setfiles
verify 1.9.4 "$SHA"
want_red "another sha" ".github/workflows/forsgren.yml: the added line is not the pin of metrics.yml at v1.9.4 and ${SHA}"
{ file .github/workflows/forsgren.yml "$(patch auto_update.yml "$OLD" "$SHA" v1.9.4)"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; } | setfiles
verify 1.9.4 "$SHA"
want_red "the wrong workflow for the caller" ".github/workflows/forsgren.yml: the removed line is not a pin of metrics.yml"
{ file .github/workflows/forsgren.yml "$(patch metrics.yml "$OLD" "$SHA" v1.9.4 | sed 's#acme/forsgren#other/forsgren#g')"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; } | setfiles
verify 1.9.4 "$SHA"
want_red "a pin of another repository" ".github/workflows/forsgren.yml: the removed line is not a pin of metrics.yml"
{ file .github/workflows/forsgren.yml "$(printf '@@ -1 +1 @@\n-name: a\n+uses: %s/.github/workflows/metrics.yml@%s # v1.9.4\n' "$R" "$SHA")"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; } | setfiles
verify 1.9.4 "$SHA"
want_red "a removed line that is no pin" ".github/workflows/forsgren.yml: the removed line is not a pin of metrics.yml"
verify 1.9
want_exit "a malformed version" 2 "usage"
(GITHUB_REPOSITORY="" "$VERIFY" 1.9.4 "$SHA" < "${TMP}/files.json" > "${TMP}/o.txt" 2>&1) && RC=0 || RC=$?
OUT="$(cat "${TMP}/o.txt")"
want_exit "no repository" 2 "usage"

# Mutation proofs.
mutant() {
  selftest_mutant "$VERIFY" "${TMP}/mut/$1/release_verify_pin.sh" "$2" || return 1
  SCRIPT="${TMP}/mut/$1/release_verify_pin.sh"
}
{ file .github/workflows/forsgren.yml "$GOOD_MAIN"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; file README.md "$GOOD_MAIN"; } | setfiles
if mutant otherfile "s/^  if \[ \".known\" -eq 0 \]; then\$/  if false; then/"; then
  verify 1.9.4 "$SHA"
  want_green "mutation proof: without the check another changed file is accepted" "OK:"
fi
{ file .github/workflows/forsgren.yml "$(patch metrics.yml "$OLD" "$OLD" v1.9.4)"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; } | setfiles
if mutant sha "s/@.{SHA} # v/@[0-9a-f]{40} # v/"; then
  verify 1.9.4 "$SHA"
  want_green "mutation proof: without the sha comparison another commit is accepted" "OK:"
fi
{ file .github/workflows/forsgren.yml "$(patch metrics.yml "$OLD" "$SHA" v1.9.4 '-# v1.9.2\n+# v1.9.4')"; file .github/workflows/forsgren-update.yml "$GOOD_UPD"; } | setfiles
if mutant onechange "s/-ne 1 \] || \[ \".{#added\[@\]}\" -ne 1 \]/-lt 1 ] || [ \"${D}{#added[@]}\" -lt 1 ]/"; then
  verify 1.9.4 "$SHA"
  want_green "mutation proof: a second changed line is accepted when only the first pair is read" "OK:"
fi
unset SCRIPT

selftest_end "the release verify pin does not hold" "release verify pin: only the two caller pins moved to this release pass"
