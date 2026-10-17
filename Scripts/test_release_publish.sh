#!/usr/bin/env bash
# Scripts/test_release_publish.sh
#
# Self-test for Scripts/release_publish.sh (forsgren#221, step 2 of 2). A stub
# gh on PATH answers from files and logs every call.
#   1. free: no tag, no release                  -> OK
#   2. free: the tag exists / the release exists -> red (a longer tag with the
#      same prefix is no hit)
#   3. create: one `gh release create vX.Y.Z --target <sha> --latest` with the
#      notes file and the title, and no other call that makes a tag or a ref
#   4. create fails and leaves no tag            -> red, says no tag is left
#   5. create fails and a tag exists             -> red, names the tag without
#      a release
#   6. create "succeeds" but the release cannot be read -> red
#   7. an empty or missing notes file            -> red before gh is called
#   8. usage errors, a missing GITHUB_REPOSITORY -> exit 2
# Mutation proofs: a copy without --latest, one that targets the branch and
# not the sha and one that no longer looks for a leftover tag must each let
# their case pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release publish self-test"

PUBLISH="Scripts/release_publish.sh"
[[ -f "$PUBLISH" ]] || selftest_abort "${PUBLISH} does not exist — a release would be made by hand"

SHA="0123456789abcdef0123456789abcdef01234567"
STUBS="${TMP}/bin"
STATE="${TMP}/state"
mkdir -p "$STUBS" "$STATE"
cat > "${STUBS}/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LOG:?}"
case "$1 $2" in
  "api repos/"*)
    expr=""
    prev=""
    for a in "$@"; do
      [ "$prev" = "--jq" ] && expr="$a"
      prev="$a"
    done
    { cat "${STUB_STATE:?}/tags" 2> /dev/null || echo '[]'; } | jq -r "$expr"
    ;;
  "release view") [ -f "${STUB_STATE:?}/release" ] ;;
  "release create")
    if [ -f "${STUB_STATE:?}/create_fails" ]; then echo "HTTP 500" >&2; exit 1; fi
    [ -f "${STUB_STATE}/no_release" ] || : > "${STUB_STATE}/release"
    ;;
esac
STUB
chmod +x "${STUBS}/gh"

reset() {
  rm -f "${STATE}"/* "${TMP}/gh.log"
  : > "${TMP}/gh.log"
}
publish() {
  PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_STATE="$STATE" GITHUB_REPOSITORY="acme/app" capture "${SCRIPT:-$PUBLISH}" "$@"
}
printf 'notes\n' > "${TMP}/notes.md"
: > "${TMP}/empty.md"

reset
publish free 1.9.4
want_green "a free version" "OK: v1.9.4 is free"
echo '[{"ref":"refs/tags/v1.9.40"}]' > "${STATE}/tags"
publish free 1.9.4
want_green "a longer tag with the same prefix is no hit" "OK: v1.9.4 is free"
echo '[{"ref":"refs/tags/v1.9.4"}]' > "${STATE}/tags"
publish free 1.9.4
want_red "the tag exists" "the tag v1.9.4 already exists"
reset
: > "${STATE}/release"
publish free 1.9.4
want_red "the release exists" "a release v1.9.4 already exists"

reset
publish create 1.9.4 "$SHA" "${TMP}/notes.md"
want_green "create" "OK: released v1.9.4 at ${SHA}, marked Latest"
if grep -qxF "release create v1.9.4 --repo acme/app --target ${SHA} --title forsgren 1.9.4 --notes-file ${TMP}/notes.md --latest" "${TMP}/gh.log"; then
  echo "  ok: one release create call, with the target, the title, the notes and --latest"
else
  fail "the release create call is not as pinned. Log: $(cat "${TMP}/gh.log")"
fi
if grep -E 'git/refs|git/tags|tag create' "${TMP}/gh.log" | grep -q .; then fail "a tag was made by another call than release create. Log: $(cat "${TMP}/gh.log")"; else echo "  ok: no other call makes a tag"; fi

reset
touch "${STATE}/create_fails"
publish create 1.9.4 "$SHA" "${TMP}/notes.md"
want_red "create fails, no tag" "no tag v1.9.4 was left behind"
echo '[{"ref":"refs/tags/v1.9.4"}]' > "${STATE}/tags"
publish create 1.9.4 "$SHA" "${TMP}/notes.md"
want_red "create fails, a tag is left" "a tag without its release"

reset
touch "${STATE}/no_release"
publish create 1.9.4 "$SHA" "${TMP}/notes.md"
want_red "create without a readable release" "cannot be read"
rm -f "${STATE}/no_release"

reset
publish create 1.9.4 "$SHA" "${TMP}/empty.md"
want_red "empty notes" "missing or empty"
publish create 1.9.4 "$SHA" "${TMP}/none.md"
want_red "missing notes" "missing or empty"
if grep -q 'release create' "${TMP}/gh.log"; then fail "gh release create was called without notes"; fi

publish
want_exit "no mode" 2 "usage"
publish free 1.9
want_exit "a malformed version" 2 "usage"
publish create 1.9.4 abc "${TMP}/notes.md"
want_exit "a short sha" 2 "usage"
(unset GITHUB_REPOSITORY; PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_STATE="$STATE" GITHUB_REPOSITORY="" "$PUBLISH" free 1.9.4 > "${TMP}/o.txt" 2>&1) && RC=0 || RC=$?
OUT="$(cat "${TMP}/o.txt")"
want_exit "no repository" 2 "usage"

# Mutation proofs.
mutant() {
  selftest_mutant "$PUBLISH" "${TMP}/mut/$1/release_publish.sh" "$2" || return 1
  SCRIPT="${TMP}/mut/$1/release_publish.sh"
}

reset
if mutant nolatest 's/ --latest; then/; then/'; then
  publish create 1.9.4 "$SHA" "${TMP}/notes.md"
  if grep -qF -- "--latest" "${TMP}/gh.log"; then fail "mutation proof: the mutant still passes --latest"; else echo "  ok: mutation proof: without --latest the call no longer marks Latest"; fi
fi
reset
if mutant branch "s/--target \".SHA\"/--target main/"; then
  publish create 1.9.4 "$SHA" "${TMP}/notes.md"
  if grep -qF -- "--target ${SHA}" "${TMP}/gh.log"; then fail "mutation proof: the mutant still targets the sha"; else echo "  ok: mutation proof: a call that targets the branch is no longer pinned to the bump commit"; fi
fi
reset
touch "${STATE}/create_fails"
echo '[{"ref":"refs/tags/v1.9.4"}]' > "${STATE}/tags"
if mutant noleft 's/^if tag_exists; then$/if false; then/'; then
  publish create 1.9.4 "$SHA" "${TMP}/notes.md"
  if grep -qF "a tag without its release" <<< "$OUT"; then fail "mutation proof: the mutant still names the leftover tag"; else echo "  ok: mutation proof: without the look the leftover tag is no longer named"; fi
fi
unset SCRIPT

selftest_end "the release publish does not hold" "release publish: one release call makes the tag, a free version is required, a leftover tag is named"
