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
#   6. publish mode (the bump commit is on main, no release yet): the bump commit of the version in main.go must BE main's head (a head
#      that moved past it is refused, both shas named); a tag or release
#      that exists, or no bump commit, is red
#   7. usage errors, no GITHUB_REPOSITORY -> exit 2
# Mutation proofs: a copy that no longer compares the tag's commit with the
# release's target, and one that accepts a draft, must each let their case pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

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

# publish: the bump commit is on main, no release exists yet.
W="${TMP}/repo"
mkdir -p "${W}/Scripts" "${W}/cmd/forsgren"
cp Scripts/release_resume.sh Scripts/release_publish.sh "${W}/Scripts/"
git -C "$W" init -q -b main
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
gc() { git -C "$W" -c user.name=t -c user.email=t@example.test commit -q "$@"; }
echo 'var version = "1.9.4"' > "${W}/cmd/forsgren/main.go"
git -C "$W" add -A
gc -m "release 1.9.4 (1/1): bump to 1.9.4, #1"
echo 'var version = "1.9.5"' > "${W}/cmd/forsgren/main.go"
git -C "$W" add -A
gc -m "release 1.9.5 (1/1): bump to 1.9.5, #3 #5"
BUMP="$(git -C "$W" rev-parse HEAD)"
publish_mode() {
  (cd "$W" && PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_STATE="$STATE" GITHUB_REPOSITORY="acme/app" "${1:-./Scripts/release_resume.sh}" publish) > "${TMP}/o.txt" 2>&1 && RC=0 || RC=$?
  OUT="$(cat "${TMP}/o.txt")"
}
world ""
publish_mode
want_green "publish: main's head is the bump commit" "OK: resuming v1.9.5 at ${BUMP} (the bump commit is main's head, no release yet)"
want_said "publish: version line" "version=1.9.5"
want_said "publish: sha line" "sha=${BUMP}"
world "v1.9.5${TAB}false${TAB}false${TAB}${BUMP}"
publish_mode
want_red "publish: a release exists" "already a tag or a release"
world ""
echo '[{"ref":"refs/tags/v1.9.5"}]' > "${STATE}/tags"
publish_mode
want_red "publish: a tag exists" "already a tag or a release"
rm -f "${STATE}/tags"
# main moved past the bump commit: refused, both shas named.
echo other > "${W}/other.txt"
git -C "$W" add -A
gc -m "something later"
HEADC="$(git -C "$W" rev-parse HEAD)"
world ""
publish_mode
want_red "publish: main has moved past the bump commit" "main's head ${HEADC} is not the bump commit ${BUMP}"
want_said "publish: the advice" "Fix main and run a new release instead"
if grep -qF "sha=" <<< "$OUT"; then fail "publish: a moved head printed a sha to release. Output: ${OUT}"; else echo "  ok: nothing to release is printed"; fi
# Mutation proof: publishing a moved head is what the case above catches.
selftest_mutant "$RESUME" "${W}/Scripts/mutant_head.sh" "s/^  if \\[ \".HEAD_SHA\" != \".BUMP_SHA\" \\]; then\$/  if false; then/" || true
publish_mode ./Scripts/mutant_head.sh
if [[ "$RC" -eq 0 ]] && grep -qF "OK: resuming v1.9.5" <<< "$OUT"; then echo "  ok: mutation proof: without the check a moved head is published"; else fail "mutation proof: the mutant still refuses a moved head. Output: ${OUT}"; fi
git -C "$W" reset -q --hard HEAD~1
echo 'var version = "1.9.6"' > "${W}/cmd/forsgren/main.go"
git -C "$W" add -A
gc -m "edit without a bump commit"
publish_mode
want_red "publish: no bump commit for the version" "no bump commit"
# Mutation proof: without the look for the bump commit that refusal is lost.
selftest_mutant "$RESUME" "${W}/Scripts/mutant.sh" "s/^  \\[\\[ \".BUMP_SHA\" =~ .* red .*$/  true/" || true
world ""
publish_mode ./Scripts/mutant.sh
if grep -qF "no bump commit" <<< "$OUT"; then fail "mutation proof: the mutant still says there is no bump commit. Output: ${OUT}"; else echo "  ok: mutation proof: without the check a version with no bump commit is no longer named"; fi

selftest_end "the release resume does not hold" "release resume: the latest published release at its tag's commit is found, anything else is refused"
