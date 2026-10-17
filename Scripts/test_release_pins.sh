#!/usr/bin/env bash
# Scripts/test_release_pins.sh
#
# Self-test for Scripts/release_pins.sh (forsgren#221, step 2 of 2). No network:
# a stub gh on PATH plays the git-data API of the two repositories (their files
# are Scripts/testdata/release_pins/*.fixture, the real template files of the
# 1.9.3 release) and records every call and every body it was sent.
#   1. rewrite: the workflow files get the new sha and version in the `uses:`
#      line and in the comment (also the comment that wraps after "release");
#      the README names the new version; a file with no such place is a red
#   2. template: ONE commit with the three files, built from blobs, a tree on
#      the base tree and a commit on the base commit; the branch is moved with
#      a fast-forward PATCH, never forced
#   3. metrics: two files in one commit on the branch forsgren-release-vX.Y.Z,
#      a pull request into the default branch, and the template's branch is
#      not touched
#   4. no FORSGREN_RELEASE_TOKEN: ::error:: naming the secret, exit 1, gh never
#      called, also when the job's own GH_TOKEN is set (no fallback)
#   4b. `token`: the early check of the secret, no gh call
#   5. the token reaches gh as GH_TOKEN, and as nothing else
#   6. a repository that already pins the version -> red, nothing committed
#   7. usage errors
# Mutation proofs: a copy that skips the README, one that falls back to the
# job's token, one that forces the ref move and one that opens no pull request
# must each let their case pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release pins self-test"
D='$'

PINS="Scripts/release_pins.sh"
FIX="Scripts/testdata/release_pins"
[[ -f "$PINS" ]] || selftest_abort "${PINS} does not exist — the pins of the template and the metrics installation move by hand"

SHA="89abcdef0123456789abcdef0123456789abcdef"
VERSION="1.9.4"
OLDSHA="5ed7552d038600680ac8f4d969dac3a51eefce73"
STUBS="${TMP}/bin"
STATE="${TMP}/state"
mkdir -p "$STUBS" "$STATE"
cat > "${STUBS}/gh" <<'STUB'
#!/usr/bin/env bash
# A stub of the git-data API of one repository whose three files are
# ${STUB_STATE}/files/<path>. Every call is logged, with the token it got.
printf '%s|%s\n' "${GH_TOKEN-unset}" "$*" >> "${STUB_LOG:?}"
args=("$@")
expr="."
path=""
input=0
prev=""
for a in "$@"; do
  [ "$prev" = "--jq" ] && expr="$a"
  [ "$a" = "--input" ] && input=1
  case "$a" in repos/*) path="$a" ;; esac
  prev="$a"
done
body=""
if [ "$input" -eq 1 ]; then
  n="$(ls "${STUB_STATE}/bodies" 2> /dev/null | wc -l | tr -d ' ')"
  mkdir -p "${STUB_STATE}/bodies"
  body="${STUB_STATE}/bodies/$((n + 1)).$(printf '%s' "${path#repos/*/*/}" | tr '/?' '__')"
  cat > "$body"
fi
reply() { printf '%s' "$1" | jq -r "${expr}"; }
if [ "${args[0]}" = "pr" ]; then
  [ -f "${STUB_STATE}/pr_fails" ] && exit 1
  echo "https://example.test/pull/1"
  exit 0
fi
case "$path" in
  repos/*/git/ref/heads/*) reply '{"object":{"sha":"BASECOMMIT"}}' ;;
  repos/*/git/commits/BASECOMMIT) reply '{"tree":{"sha":"BASETREE"}}' ;;
  repos/*/git/blobs) reply '{"sha":"blob'"$n"'"}' ;;
  repos/*/git/trees) reply '{"sha":"NEWTREE"}' ;;
  repos/*/git/commits) reply '{"sha":"NEWCOMMIT"}' ;;
  repos/*/git/refs/heads/*)
    [ -f "${STUB_STATE}/patch_fails" ] && exit 1
    reply '{}'
    ;;
  repos/*/git/refs) reply '{}' ;;
  repos/*/contents/*)
    file="${path#repos/*/*/contents/}"
    file="${file%%\?*}"
    [ -f "${STUB_STATE}/files/${file}" ] || exit 1
    jq -n --rawfile c <(base64 < "${STUB_STATE}/files/${file}") '{content: $c}' | jq -r "${expr}"
    ;;
  repos/*) reply '{"default_branch":"main"}' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${STUBS}/gh"

# world <withreadme>: the files of the target repository, a clean log.
world() {
  rm -rf "$STATE" "${TMP}/gh.log"
  mkdir -p "${STATE}/files/.github/workflows"
  cp "${FIX}/forsgren.yml.fixture" "${STATE}/files/.github/workflows/forsgren.yml"
  cp "${FIX}/forsgren-update.yml.fixture" "${STATE}/files/.github/workflows/forsgren-update.yml"
  cp "${FIX}/README.md.fixture" "${STATE}/files/README.md"
  : > "${TMP}/gh.log"
}
pins() {
  PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_STATE="$STATE" GITHUB_REPOSITORY="yveshanoulle/forsgren" \
    RELEASE_TEMPLATE_REPO="acme/tpl" RELEASE_METRICS_REPO="acme/met" capture "${SCRIPT:-$PINS}" "$@"
}
body_of() { cat "${STATE}"/bodies/*"$1"* 2> /dev/null; }

# 1: rewrite
world
OUT="$(GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" < "${FIX}/forsgren-update.yml.fixture")"
if grep -qF "auto_update.yml@${SHA} # v${VERSION}" <<< "$OUT" && grep -qF "release" <<< "$OUT" && grep -qE '^# v1\.9\.4, the same commit' <<< "$OUT" && ! grep -qF "$OLDSHA" <<< "$OUT" && ! grep -qF "1.9.3" <<< "$OUT"; then
  echo "  ok: a workflow file gets the new pin and the wrapped comment names the new release"
else
  fail "the update workflow was not rewritten right. Output: ${OUT}"
fi
OUT="$(GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" < "${FIX}/forsgren.yml.fixture")"
if grep -qF "metrics.yml@${SHA} # v${VERSION}" <<< "$OUT" && grep -qF "pinned by the commit of release v${VERSION}" <<< "$OUT" && ! grep -qF "1.9.3" <<< "$OUT"; then
  echo "  ok: the calling workflow gets the new pin and comment"
else
  fail "the calling workflow was not rewritten right. Output: ${OUT}"
fi
OUT="$(GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite readme "$VERSION" "$SHA" < "${FIX}/README.md.fixture")"
if grep -qF "daily run for forsgren ${VERSION}:" <<< "$OUT" && grep -qF "The rest is the installation's own text." <<< "$OUT"; then
  echo "  ok: the README names the new version and keeps the rest"
else
  fail "the README was not rewritten right. Output: ${OUT}"
fi
OUT="$(printf 'name: x\non: push\n' | GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" 2>&1)" && RC=0 || RC=$?
want_red "a workflow with no pin" "would be skipped"
OUT="$(printf 'uses: other/repo/.github/workflows/metrics.yml@%s # v1.9.3\n' "$OLDSHA" | GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" 2>&1)" && RC=0 || RC=$?
want_red "a pin of another repository is not moved" "would be skipped"
OUT="$(printf 'hello\n' | GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite readme "$VERSION" "$SHA" 2>&1)" && RC=0 || RC=$?
want_red "a README with no version sentence" "would be skipped"

# 2: template
world
FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
want_green "template" "OK: acme/tpl main now pins ${VERSION} (NEWCOMMIT)"
if [[ "$(grep -c 'git/blobs' "${TMP}/gh.log")" -eq 3 ]]; then echo "  ok: three blobs"; else fail "want three blobs. Log: $(cat "${TMP}/gh.log")"; fi
if [[ "$(grep -c 'git/commits --input' "${TMP}/gh.log")" -eq 1 ]]; then echo "  ok: one commit"; else fail "want one commit. Log: $(cat "${TMP}/gh.log")"; fi
tree="$(body_of trees)"
if [[ "$(jq -r '.base_tree' <<< "$tree")" == BASETREE && "$(jq -r '.tree | length' <<< "$tree")" -eq 3 ]] \
  && [[ "$(jq -r '[.tree[].path] | sort | join(",")' <<< "$tree")" == ".github/workflows/forsgren-update.yml,.github/workflows/forsgren.yml,README.md" ]]; then
  echo "  ok: the tree is the base tree plus the three files"
else
  fail "the tree body is not right: ${tree}"
fi
commit="$(body_of "git_commits")"
if [[ "$(jq -r '.message' <<< "$commit")" == "forsgren ${VERSION}: pin and README" && "$(jq -r '.parents[0]' <<< "$commit")" == BASECOMMIT && "$(jq -r '.tree' <<< "$commit")" == NEWTREE ]]; then
  echo "  ok: the commit is on the base commit, with the manual release's message"
else
  fail "the commit body is not right: ${commit}"
fi
if grep -qF -- "-X PATCH repos/acme/tpl/git/refs/heads/main" "${TMP}/gh.log" && ! grep -q 'force' "${TMP}/gh.log" "${STATE}"/bodies/* 2> /dev/null; then
  echo "  ok: the branch is moved with a plain PATCH, never forced"
else
  fail "the ref move is not a plain PATCH. Log: $(cat "${TMP}/gh.log")"
fi
if grep -qF "daily run for forsgren ${VERSION}:" "${STATE}"/bodies/*blobs* && grep -qF "metrics.yml@${SHA} # v${VERSION}" "${STATE}"/bodies/*blobs*; then
  echo "  ok: the blobs hold the new text"
else
  fail "the blobs do not hold the new pins"
fi
if ! grep -v '^rt-token|' "${TMP}/gh.log" | grep -q .; then echo "  ok: every gh call got the release token as GH_TOKEN"; else fail "a gh call ran with another token: $(grep -v '^rt-token|' "${TMP}/gh.log")"; fi

# 3: metrics
world
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "metrics" "OK: acme/met pull request for ${VERSION}: https://example.test/pull/1"
if [[ "$(grep -c 'git/blobs' "${TMP}/gh.log")" -eq 2 ]]; then echo "  ok: two blobs, no README"; else fail "want two blobs. Log: $(cat "${TMP}/gh.log")"; fi
if grep -qF "refs/heads/forsgren-release-v${VERSION}" "${STATE}"/bodies/*git_refs*; then echo "  ok: the branch is forsgren-release-v${VERSION}"; else fail "no branch was created"; fi
if grep -q 'PATCH' "${TMP}/gh.log"; then fail "the default branch of the metrics repository was moved: it must only get a pull request"; else echo "  ok: the default branch is untouched"; fi
if grep -qF "pr create --repo acme/met --base main --head forsgren-release-v${VERSION}" "${TMP}/gh.log"; then echo "  ok: the pull request goes into main"; else fail "pr create is not as pinned. Log: $(cat "${TMP}/gh.log")"; fi

# 4: no token
world
GH_TOKEN="job-token" pins template "$VERSION" "$SHA"
want_red "template without the secret" "::error::FORSGREN_RELEASE_TOKEN is not set"
GH_TOKEN="job-token" pins metrics "$VERSION" "$SHA"
want_red "metrics without the secret" "::error::FORSGREN_RELEASE_TOKEN is not set"
FORSGREN_RELEASE_TOKEN="" GH_TOKEN="job-token" pins metrics "$VERSION" "$SHA"
want_red "an empty secret" "::error::FORSGREN_RELEASE_TOKEN is not set"
if [[ -s "${TMP}/gh.log" ]]; then fail "gh was called without the secret: $(cat "${TMP}/gh.log")"; else echo "  ok: gh is never called without the secret, the job's token is no fallback"; fi

# 4b: the early check
world
FORSGREN_RELEASE_TOKEN="rt-token" pins token
want_green "the early token check" "OK: FORSGREN_RELEASE_TOKEN is set"
GH_TOKEN="job-token" pins token
want_red "the early token check without the secret" "::error::FORSGREN_RELEASE_TOKEN is not set"
if [[ -s "${TMP}/gh.log" ]]; then fail "the early check called gh: $(cat "${TMP}/gh.log")"; fi

# 5/6: already pinned
world
cp "${FIX}/forsgren.yml.fixture" "${TMP}/f.yml"
GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" < "${TMP}/f.yml" > "${STATE}/files/.github/workflows/forsgren.yml"
GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" < "${FIX}/forsgren-update.yml.fixture" > "${STATE}/files/.github/workflows/forsgren-update.yml"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_red "both files already pinned" "no file of acme/met needed a change"
if grep -q 'git/commits --input\|git/refs' "${TMP}/gh.log"; then fail "something was committed although nothing changed"; else echo "  ok: nothing was committed"; fi

world
touch "${STATE}/patch_fails"
FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
want_red "the branch cannot be moved" "nothing is pinned"
world
touch "${STATE}/pr_fails"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_red "the pull request cannot be opened" "the pull request could not be opened"

# 7: usage
pins
want_exit "no mode" 2 "usage"
pins template 1.9 "$SHA"
want_exit "a malformed version" 2 "usage"
pins metrics "$VERSION" abc
want_exit "a short sha" 2 "usage"
pins rewrite banana "$VERSION" "$SHA" < /dev/null
want_exit "an unknown kind" 2 "usage"

# Mutation proofs.
mutant() {
  selftest_mutant "$PINS" "${TMP}/mut/$1/release_pins.sh" "$2" || return 1
  SCRIPT="${TMP}/mut/$1/release_pins.sh"
}

world
if mutant noreadme 's/readme:README.md//'; then
  FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
  if [[ "$(grep -c 'git/blobs' "${TMP}/gh.log")" -eq 3 ]]; then fail "mutation proof: the mutant still moves the README"; else echo "  ok: mutation proof: without the README entry only two files move"; fi
fi
world
if mutant fallback "s/^if \[ -z \".TOKEN\" \]; then/if false; then/"; then
  GH_TOKEN="job-token" pins metrics "$VERSION" "$SHA"
  if grep -qF "::error::" <<< "$OUT"; then fail "mutation proof: the mutant still refuses without the secret"; else echo "  ok: mutation proof: without the check the run goes on with a missing secret"; fi
fi
world
if mutant force 's/-X PATCH "repos/-X PATCH -f force=true "repos/'; then
  FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
  if grep -q 'force' "${TMP}/gh.log"; then echo "  ok: mutation proof: a forced move shows in the log, which the real script never has"; else fail "mutation proof: the mutant did not force"; fi
fi
world
if mutant nopr "s/URL=\".(ghr pr create/URL=\"${D}(echo/"; then
  FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
  if grep -qF "pr create" "${TMP}/gh.log"; then fail "mutation proof: the mutant still opens the pull request"; else echo "  ok: mutation proof: without the call no pull request is opened, which the pinned call case would see"; fi
fi
unset SCRIPT

selftest_end "the release pins do not hold" "release pins: rewrite, one template commit, a metrics branch and pull request, and no run without the token"
