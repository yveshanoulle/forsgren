#!/usr/bin/env bash
# Scripts/test_release_bump.sh
#
# Self-test for Scripts/release_bump.sh (forsgren#221, step 1 of 2): the
# version bump of a release, done to a copy of this repository's files in a
# temp directory, so the work tree is never left bumped.
#   1. a patch bump        -> OK, the old version is gone from every place
#      that pins it, `go test ./...` passes on the bumped copy, and the
#      files that are history (SHIPPED.md, the npm files) are untouched
#   2. a minor bump -> OK, `go test ./...` passes (the newer-release examples
#      moved to the version after the new one); a major bump -> OK, and
#      `go test ./...` fails ONLY on the agent-file proof run a new major needs
#   3. every golden page and every test that names the version changed
#   4. a version that is malformed, equal to the current one or lower, a
#      missing argument -> exit 2 with its reason, the copy untouched
# Mutation proofs: a copy that no longer rewrites the golden pages must be
# refused by the script itself, naming the page that still holds the old
# version; a copy that also lost that check must let it through (exit 0).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_repo_files.sh
source Scripts/lib_repo_files.sh
selftest_begin "release bump self-test"

BUMP="Scripts/release_bump.sh"
[[ -f "$BUMP" ]] || selftest_abort "${BUMP} does not exist — a release bump would be done by hand and could miss a file that pins the version"

# The tree the cases copy: this repository's files, tracked and untracked.
BASE="${TMP}/base"
mkdir -p "$BASE"
repo_files . -z | tar --null -T - -cf - | tar -x -C "$BASE"
cp "$BUMP" "${BASE}/Scripts/release_bump.sh"

CURRENT="$(sed -n 's/^var version = "\([0-9.]*\)"$/\1/p' "${BASE}/cmd/forsgren/main.go")"
[[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || selftest_abort "cmd/forsgren/main.go has no var version = \"X.Y.Z\""
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"
NEXT_PATCH="${MAJOR}.${MINOR}.$((PATCH + 1))"
NEXT_MINOR="${MAJOR}.$((MINOR + 1)).0"
NEXT_MAJOR="$((MAJOR + 1)).0.0"

# fresh <name>: a new copy of the base tree in ${TMP}/<name>.
fresh() {
  rm -rf "${TMP:?}/$1"
  cp -R "$BASE" "${TMP}/$1"
}

# bump <name> <version>: the script of that copy, run in it.
bump() {
  capture "${TMP}/$1/Scripts/release_bump.sh" "$2"
}

# gotest <name> <case>: go test ./... in the copy.
gotest() {
  if (cd "${TMP}/$1" && go test ./... > "${TMP}/$1.gotest.log" 2>&1); then
    echo "  ok: $2: go test ./... passes"
  else
    fail "$2: go test ./... fails on the bumped copy. Output: $(tail -30 "${TMP}/$1.gotest.log")"
  fi
}

# 1
fresh patch
bump patch "$NEXT_PATCH"
want_green "patch bump" "OK: bumped ${CURRENT} to ${NEXT_PATCH}"
gotest patch "patch bump"
if grep -qF "var version = \"${NEXT_PATCH}\"" "${TMP}/patch/cmd/forsgren/main.go"; then
  echo "  ok: main.go says the new version"
else
  fail "main.go does not say version ${NEXT_PATCH}"
fi
for history in SHIPPED.md package.json package-lock.json; do
  if cmp -s "${BASE}/${history}" "${TMP}/patch/${history}"; then
    echo "  ok: ${history} is untouched"
  else
    fail "${history} changed in a bump: it holds history or dependency versions, not the version of forsgren"
  fi
done

# 3: every golden page and every test file that held the old version changed.
missed=""
while IFS= read -r file; do
  if cmp -s "${BASE}/${file}" "${TMP}/patch/${file}"; then missed="${missed} ${file}"; fi
done < <(cd "$BASE" && grep -rlE "(^|[^0-9.])${CURRENT//./\\.}($|[^0-9]|\\.[^0-9])" cmd/forsgren internal/page)
if [[ -n "$missed" ]]; then
  fail "files that held ${CURRENT} did not change:${missed}"
else
  echo "  ok: every file under cmd/forsgren and internal/page that held ${CURRENT} changed"
fi
goldens="$(cd "$BASE" && grep -rlF "${CURRENT}" internal/page/testdata | wc -l | tr -d ' ')"
if [[ "$goldens" -lt 1 ]]; then
  fail "no golden page holds ${CURRENT} in the base tree: the case above proves nothing about goldens"
else
  echo "  ok: ${goldens} golden pages held the version"
fi

# 2
fresh minor
bump minor "$NEXT_MINOR"
want_green "minor bump" "OK: bumped ${CURRENT} to ${NEXT_MINOR}"
gotest minor "minor bump"
fresh major
bump major "$NEXT_MAJOR"
want_green "major bump" "OK: bumped ${CURRENT} to ${NEXT_MAJOR}"
# A new major also needs a new proof run of each agent file (forsgren#148):
# the bump cannot do that, and exactly that one test says so. Nothing else may fail.
if (cd "${TMP}/major" && go test ./... > "${TMP}/major.gotest.log" 2>&1); then
  fail "major bump: go test ./... passes, but the Tested-with major test should ask for a proof run of the agent files"
else
  others="$(grep -E '^--- FAIL' "${TMP}/major.gotest.log" | grep -vF 'TestEveryAgentFileWasTestedOnTheRunningMajor' || true)"
  if [[ -n "$others" ]]; then
    fail "major bump: go test ./... fails beyond the agent-file proof run: ${others}"
  elif ! grep -qF 'TestEveryAgentFileWasTestedOnTheRunningMajor' "${TMP}/major.gotest.log"; then
    fail "major bump: go test ./... fails, but not on the agent-file proof run. Output: $(tail -20 "${TMP}/major.gotest.log")"
  else
    echo "  ok: major bump: go test ./... fails only on the agent-file proof run a new major needs"
  fi
fi
want_said "a major bump says the agent files need a proof run" "proof run"

# 4
fresh usage
bump usage "1.2"
want_exit "a malformed version" 2 "not X.Y.Z"
bump usage "$CURRENT"
want_exit "the current version" 2 "is not greater than the current ${CURRENT}"
bump usage "0.0.1"
want_exit "a lower version" 2 "is not greater than the current ${CURRENT}"
capture "${TMP}/usage/Scripts/release_bump.sh"
want_exit "no argument" 2 "usage"
if diff -r "$BASE" "${TMP}/usage" > /dev/null; then
  echo "  ok: a refused bump changes nothing"
else
  fail "a refused bump changed files"
fi

# Mutation proofs.
fresh mutant
MUT="${TMP}/mutant/Scripts/release_bump.sh"
selftest_mutant "$BUMP" "$MUT" "s/ -o -name '\\*\\.golden\\.html'//" || true
bump mutant "$NEXT_PATCH"
want_red "mutation proof: a bump that skips the golden pages is refused" "still holds ${CURRENT}"
want_said "the refusal names a golden page" "internal/page/testdata/"

fresh mutant2
MUT2="${TMP}/mutant2/Scripts/release_bump.sh"
selftest_mutant "$BUMP" "$MUT2" "s/ -o -name '\\*\\.golden\\.html'//; s/^verify_nothing_missed\$/true/" || true
bump mutant2 "$NEXT_PATCH"
want_green "mutation proof: without the check, the skipped golden pages pass the script" "OK: bumped"

selftest_end "the release bump does not hold" "release bump: patch and minor bumps leave go test green, a major only the agent-file proof run to do, nothing stays at the old version, a missed file is refused"
