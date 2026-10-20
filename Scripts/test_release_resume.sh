#!/usr/bin/env bash
# Scripts/test_release_resume.sh
#
# Self-test for Scripts/release_resume.sh (forsgren#221, the `resume: pins` run
# of the Release workflow). No network: a stub gh answers from files.
#   1. the latest release exists, is published and its tag is at the commit the
#      release targets -> OK, with version=, tag= and sha= lines
#   2. an annotated tag is followed to its commit
#   3. no release / a draft / a prerelease / a tag that is no vX.Y.Z -> red
#   4. a tag at another commit than the release targets, or no tag -> red
#   5. a release that targets a branch name (an older release) -> the tag's
#      commit is used, no comparison
#   6. publish is no mode any more (forsgren#237, step 5b) -> exit 2
#   7. usage errors, no GITHUB_REPOSITORY -> exit 2
# Mutation proofs: a copy that no longer compares the tag's commit with the
# release's target, and one that accepts a draft, must each let their case pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release resume self-test"

RESUME="Scripts/release_resume.sh"
[[ -f "$RESUME" ]] || selftest_abort "${RESUME} does not exist — a run that stopped after the release cannot be resumed"

SHA="0123456789abcdef0123456789abcdef01234567"
OTHER="fedcba9876543210fedcba9876543210fedcba98"
TAB=$'\t'
STUBS="${TMP}/bin"
STATE="${TMP}/state"
mkdir -p "$STUBS" "$STATE"
cat > "${STUBS}/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LOG:?}"
case "$1 $2" in
  "release view")
    [ -f "${STUB_STATE:?}/release" ] || { echo "release not found" >&2; exit 1; }
    cat "${STUB_STATE}/release"
    ;;
  "api repos/"*)
    case "$2" in
      */git/matching-refs/*)
        expr=""
        prev=""
        for a in "$@"; do
          [ "$prev" = "--jq" ] && expr="$a"
          prev="$a"
        done
        { cat "${STUB_STATE}/tags" 2> /dev/null || echo '[]'; } | jq -r "$expr"
        ;;
      */git/ref/tags/*) [ -f "${STUB_STATE}/ref" ] || { echo "Not Found (HTTP 404)" >&2; exit 1; }; cat "${STUB_STATE}/ref" ;;
      */git/tags/*) cat "${STUB_STATE}/tagobj" ;;
    esac
    ;;
esac
STUB
chmod +x "${STUBS}/gh"

# world <release line> <ref line>: the stubbed repository.
world() {
  rm -rf "${STATE:?}"/* "${TMP}/gh.log"
  : > "${TMP}/gh.log"
  if [[ -n "${1:-}" ]]; then printf '%s\n' "$1" > "${STATE}/release"; fi
  if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" > "${STATE}/ref"; fi
}
resume() {
  PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_STATE="$STATE" GITHUB_REPOSITORY="acme/app" capture "${SCRIPT:-$RESUME}" "${@:-pins}"
}

world "v1.9.4${TAB}false${TAB}false${TAB}${SHA}" "commit ${SHA}"
resume
want_green "a published release at its tag" "OK: resuming v1.9.4 at ${SHA}"
want_said "version line" "version=1.9.4"
want_said "tag line" "tag=v1.9.4"
want_said "sha line" "sha=${SHA}"

world "v1.9.4${TAB}false${TAB}false${TAB}${SHA}" "tag ${OTHER}"
echo "${SHA}" > "${STATE}/tagobj"
resume
want_green "an annotated tag is followed" "sha=${SHA}"

world ""
resume
want_red "no release" "no latest release"
world "v1.9.4${TAB}true${TAB}false${TAB}${SHA}" "commit ${SHA}"
resume
want_red "a draft" "is a draft"
world "v1.9.4${TAB}false${TAB}true${TAB}${SHA}" "commit ${SHA}"
resume
want_red "a prerelease" "is a prerelease"
world "banana${TAB}false${TAB}false${TAB}${SHA}" "commit ${SHA}"
resume
want_red "a tag that is no vX.Y.Z" "is not a vX.Y.Z tag"
world "v1.9.4${TAB}false${TAB}false${TAB}${SHA}" "commit ${OTHER}"
resume
want_red "a tag at another commit than the release targets" "is at ${OTHER}, but the release targets ${SHA}"
world "v1.9.4${TAB}false${TAB}false${TAB}${SHA}" ""
resume
want_red "no tag" "has no tag"

world "v1.9.4${TAB}false${TAB}false${TAB}main" "commit ${SHA}"
resume
want_green "a release that targets a branch" "sha=${SHA}"

resume extra
want_exit "an argument" 2 "usage"
(PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_STATE="$STATE" GITHUB_REPOSITORY="" "$RESUME" > "${TMP}/o.txt" 2>&1) && RC=0 || RC=$?
OUT="$(cat "${TMP}/o.txt")"
want_exit "no repository" 2 "usage"

mutant() {
  selftest_mutant "$RESUME" "${TMP}/mut/$1/release_resume.sh" "$2" || return 1
  SCRIPT="${TMP}/mut/$1/release_resume.sh"
}
world "v1.9.4${TAB}false${TAB}false${TAB}${SHA}" "commit ${OTHER}"
if mutant nocompare "s/^if \[\[ \".TARGET\" =~ .*; then\$/if false; then/"; then
  resume
  want_green "mutation proof: without the comparison a tag at another commit is accepted" "OK: resuming"
fi
world "v1.9.4${TAB}true${TAB}false${TAB}${SHA}" "commit ${SHA}"
if mutant nodraft "s/^if \[ \".DRAFT\" = true \]; then/if false; then/"; then
  resume
  want_green "mutation proof: without the check a draft is resumed" "OK: resuming"
fi
unset SCRIPT

# There is no resume: publish any more (forsgren#237, step 5b): a release tags
# the Quality-green head of main, so a run that stopped before the publish made
# nothing and is simply started again.
resume publish
want_exit "publish is no mode any more" 2 "usage"
if grep -qF "bump commit" <<< "$OUT"; then fail "the usage still speaks of a bump commit. Output: ${OUT}"; else echo "  ok: the usage speaks of no bump commit"; fi

selftest_end "the release resume does not hold" "release resume: the latest published release at its tag's commit is found, anything else is refused"
