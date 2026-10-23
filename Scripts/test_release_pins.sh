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
#   1c. the calling workflow's `pull-requests: read` comment gets the wording of
#      decision #315 (forsgren#320 step 4), every other line unchanged, a
#      second rewrite a no-op, the pins kind and the update workflow untouched
#   8b. a template forsgren.yml (kind `caller`) with no `pull-requests: read`
#      line is a red with nothing written; the pins kind needs no such line
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
#   8. the template README is the release's own (forsgren#286): the text
#      `forsgren install-readme` of the binary `go install`ed at the released
#      sha writes, byte for byte, the daily run's command; a body line the
#      template's README lacks arrives in the same commit as the pins; the
#      metrics step never installs; a failed install or a README that does not
#      name the release is a red with nothing committed
# Mutation proofs: a copy that skips the README, one that falls back to the
# job's token, one that forces the ref move and one that opens no pull request
# must each let their case pass; and for 8, one that rewrites the old README's
# version line again, one that installs another ref than the released sha and
# one that skips the early version check of the released README; and for 1c,
# one without the comment rewrite and one that is right once but not stable;
# and for 8b, one without the check of the line.

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
if [ "${args[0]}" = "pr" ] && [ "${args[1]}" = "list" ]; then
  { cat "${STUB_STATE}/pr_list.json" 2> /dev/null || echo '[]'; } | jq -r "${expr}"
  exit 0
fi
if [ "${args[0]}" = "pr" ]; then
  [ -f "${STUB_STATE}/pr_fails" ] && exit 1
  echo "https://example.test/pull/1"
  exit 0
fi
case "$path" in
  repos/*/git/ref/heads/forsgren-release-v*)
    [ -f "${STUB_STATE}/branch_commit" ] || { echo "Not Found (HTTP 404)" >&2; exit 1; }
    reply '{"object":{"sha":"'"$(cat "${STUB_STATE}/branch_commit")"'"}}'
    ;;
  repos/*/git/ref/heads/*) reply '{"object":{"sha":"BASECOMMIT"}}' ;;
  repos/*/git/commits/BASECOMMIT) reply '{"tree":{"sha":"BASETREE"}}' ;;
  repos/*/git/commits/OLDBRANCH) reply '{"tree":{"sha":"'"$(cat "${STUB_STATE}/branch_tree")"'"}}' ;;
  repos/*/git/blobs) reply '{"sha":"blob'"$n"'"}' ;;
  repos/*/git/trees)
    if [ -f "${STUB_STATE}/trees_403" ]; then
      echo "gh: Resource not accessible by personal access token (HTTP 403)" >&2
      exit 1
    fi
    reply '{"sha":"NEWTREE"}' ;;
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
# A stub go: `go install <module>@<sha>` logs its arguments and GOBIN and puts
# a forsgren in GOBIN whose `install-readme --out <path>` writes
# ${STUB_STATE}/released.md, the text the released binary writes.
cat > "${STUBS}/go" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "${GOBIN-unset}" "$*" >> "${STUB_GO_LOG:?}"
[ "${1:-}" = install ] || exit 1
[ -f "${STUB_STATE}/go_fails" ] && { echo "go: module lookup disabled" >&2; exit 1; }
mkdir -p "${GOBIN:?}"
cat > "${GOBIN}/forsgren" <<'BIN'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_GO_LOG:?}"
[ "${1:-}" = install-readme ] && [ "${2:-}" = --out ] || exit 2
cp "${STUB_STATE}/released.md" "$3" || exit 1
echo "created $3"
BIN
chmod +x "${GOBIN}/forsgren"
STUB
chmod +x "${STUBS}/go"
# The README the release writes: install/README.md with the version filled
# in, as install.Text does. Its body is not the template fixture's.
RELEASED="${TMP}/released.md"
perl -pe "s/\\{\\{version\\}\\}/${VERSION}/g" install/README.md > "$RELEASED"
RELEASED_LINE="This repository publishes a [forsgren](https://github.com/yveshanoulle/forsgren)"
grep -qF "$RELEASED_LINE" "$RELEASED" || selftest_abort "install/README.md no longer holds the line this self-test expects: ${RELEASED_LINE}"

# world <withreadme>: the files of the target repository, a clean log.
world() {
  rm -rf "$STATE" "${TMP}/gh.log" "${TMP}/go.log"
  mkdir -p "${STATE}/files/.github/workflows"
  cp "${FIX}/forsgren.yml.fixture" "${STATE}/files/.github/workflows/forsgren.yml"
  cp "${FIX}/forsgren-update.yml.fixture" "${STATE}/files/.github/workflows/forsgren-update.yml"
  cp "${FIX}/README.md.fixture" "${STATE}/files/README.md"
  cp "$RELEASED" "${STATE}/released.md"
  : > "${TMP}/gh.log"
  : > "${TMP}/go.log"
}
pins() {
  PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_GO_LOG="${TMP}/go.log" STUB_STATE="$STATE" GITHUB_REPOSITORY="yveshanoulle/forsgren" \
    RELEASE_TEMPLATE_REPO="acme/tpl" RELEASE_METRICS_REPO="acme/met" capture "${SCRIPT:-$PINS}" "$@"
}
body_of() { cat "${STATE}"/bodies/*"$1"* 2> /dev/null; }
# readme_blob: the content of the blob that holds the README, exactly.
readme_blob() {
  local f
  for f in "${STATE}"/bodies/*git_blobs*; do
    [[ -f "$f" ]] || continue
    if jq -r '.content' "$f" | grep -qF "written by the daily run"; then
      jq -j '.content' "$f"
      return 0
    fi
  done
  return 1
}

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
# 1c: the comment of the pull-requests: read line (forsgren#320 step 4,
# decision #315): the release brings it to the agreed wording, every other
# line byte for byte the same, and a second run changes nothing.
PR_OLD="pull-requests: read  # optional: lets the page footer name Dependabot's waiting pull request for a newer forsgren release; without it the footer only says the release is available"
PR_NEW="      pull-requests: read  # lets forsgren collect merged pull requests for Mainline Lead Time (from 1.15.0) and the page footer name Dependabot's waiting pull request; without it collect still stores everything else and the setup issue names it"
grep -qF "$PR_OLD" "${FIX}/forsgren.yml.fixture" || selftest_abort "the forsgren.yml fixture no longer holds the old pull-requests: read comment this self-test expects"
GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" < "${FIX}/forsgren.yml.fixture" > "${TMP}/once.yml"
if grep -qxF "$PR_NEW" "${TMP}/once.yml" && ! grep -qF "$PR_OLD" "${TMP}/once.yml"; then
  echo "  ok: the calling workflow's pull-requests: read comment gets the agreed wording"
else
  fail "the pull-requests: read comment was not brought to the agreed wording. Line: $(grep -F 'pull-requests:' "${TMP}/once.yml")"
fi
# every line but the pin, the release comment and the pull-requests line is unchanged
if diff <(grep -vE 'metrics\.yml@|commit of release|pull-requests:' "${FIX}/forsgren.yml.fixture") \
  <(grep -vE 'metrics\.yml@|commit of release|pull-requests:' "${TMP}/once.yml") > /dev/null \
  && [[ "$(wc -l < "${FIX}/forsgren.yml.fixture")" -eq "$(wc -l < "${TMP}/once.yml")" ]]; then
  echo "  ok: every other line of the calling workflow is byte for byte the same"
else
  fail "the rewrite changed another line of the calling workflow: $(diff "${FIX}/forsgren.yml.fixture" "${TMP}/once.yml")"
fi
GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" < "${TMP}/once.yml" > "${TMP}/twice.yml"
if cmp -s "${TMP}/once.yml" "${TMP}/twice.yml"; then
  echo "  ok: a second rewrite of the calling workflow changes nothing"
else
  fail "a second rewrite changed the calling workflow: $(diff "${TMP}/once.yml" "${TMP}/twice.yml")"
fi
OUT="$(GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" < "${FIX}/forsgren-update.yml.fixture")"
if grep -qxF "      pull-requests: write  # merge the pull request" <<< "$OUT"; then
  echo "  ok: the update workflow's pull-requests: write line keeps its comment"
else
  fail "the update workflow's pull-requests: write comment changed. Output: ${OUT}"
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

# 1b: the pins kind (forsgren-metrics): the uses lines only, as Dependabot moves them
OUT="$(GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite pins "$VERSION" "$SHA" < "${FIX}/forsgren.yml.fixture")"
if grep -qF "metrics.yml@${SHA} # v${VERSION}" <<< "$OUT" && grep -qF "pinned by the commit of release v1.9.3" <<< "$OUT" && grep -qF "$PR_OLD" <<< "$OUT"; then
  echo "  ok: the pins kind moves the pin and leaves the comment"
else
  fail "the pins kind did not leave the comment alone. Output: ${OUT}"
fi
OUT="$(printf 'name: x\n' | GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite pins "$VERSION" "$SHA" 2>&1)" && RC=0 || RC=$?
want_red "the pins kind with no pin" "would be skipped"

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

# 8: the template README is the release's own (forsgren#286)
world
FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
want_green "template with the released README" "OK: acme/tpl main now pins ${VERSION} (NEWCOMMIT)"
readme_blob > "${TMP}/written.md" || : > "${TMP}/written.md"
if grep -qF "$RELEASED_LINE" "${TMP}/written.md" && ! grep -qF "The rest is the installation's own text." "${TMP}/written.md"; then
  echo "  ok: the README carries the released body, not the template's old one"
else
  fail "the README blob does not carry the released body line '${RELEASED_LINE}': only the version line moved. Blob: $(head -c 400 "${TMP}/written.md")"
fi
if cmp -s "$RELEASED" "${TMP}/written.md"; then
  echo "  ok: the README is byte for byte what install-readme of the release writes"
else
  fail "the README blob is not byte for byte what install-readme of ${VERSION} writes"
fi
if [[ "$(grep -c "|install github.com/yveshanoulle/forsgren/cmd/forsgren@${SHA}${D}" "${TMP}/go.log")" -eq 1 ]] && grep -qE '^install-readme --out ' "${TMP}/go.log"; then
  echo "  ok: the README comes from go install at the released sha and its install-readme, the daily run's commands"
else
  fail "the README was not written by install-readme of the binary installed at ${SHA}. go log: $(cat "${TMP}/go.log")"
fi
if [[ "$(grep -c 'git/commits --input' "${TMP}/gh.log")" -eq 1 ]]; then echo "  ok: pins and README in one commit"; else fail "want one commit for pins and README. Log: $(cat "${TMP}/gh.log")"; fi
world
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
if [[ -s "${TMP}/go.log" ]]; then fail "the metrics step installed forsgren: $(cat "${TMP}/go.log")"; else echo "  ok: the metrics step installs nothing"; fi
world
touch "${STATE}/go_fails"
FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
want_red "a failed install of the release" "cannot install forsgren at ${SHA}"
nothing_committed() {
  if grep -q 'git/blobs\|git/commits --input\|PATCH' "${TMP}/gh.log"; then fail "$1: something was written. Log: $(cat "${TMP}/gh.log")"; else echo "  ok: $1: nothing was written"; fi
}
nothing_committed "a failed install"
world
perl -pi -e "s/forsgren ${VERSION}:/forsgren 1.9.4-0.20261022-89abcdef0123:/" "${STATE}/released.md"
FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
want_red "a released README that does not name the release" "the README of the release does not name ${VERSION}"
nothing_committed "a README of another version"

# 8b: a calling workflow with no pull-requests: read line is a red, nothing
# written (forsgren#320 step 4): the comment of decision #315 would be skipped
# silently. The kind `caller` is forsgren.yml's; the update workflow and the
# pins kind (forsgren-metrics) need no such line.
grep -vF "pull-requests: read" "${FIX}/forsgren.yml.fixture" > "${TMP}/noprread.yml"
OUT="$(GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite caller "$VERSION" "$SHA" < "${TMP}/noprread.yml" 2>&1)" && RC=0 || RC=$?
want_red "a calling workflow with no pull-requests: read line" "has no pull-requests: read line"
OUT="$(GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite caller "$VERSION" "$SHA" < "${FIX}/forsgren.yml.fixture" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" -eq 0 ]] && grep -qxF "$PR_NEW" <<< "$OUT" && grep -qF "metrics.yml@${SHA} # v${VERSION}" <<< "$OUT"; then
  echo "  ok: the caller kind moves the pin and writes the comment"
else
  fail "the caller kind did not rewrite the calling workflow (exit ${RC}). Output: ${OUT}"
fi
OUT="$(GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite pins "$VERSION" "$SHA" < "${TMP}/noprread.yml" 2>&1)" && RC=0 || RC=$?
want_green "the pins kind needs no pull-requests: read line" "metrics.yml@${SHA} # v${VERSION}"
world
cp "${TMP}/noprread.yml" "${STATE}/files/.github/workflows/forsgren.yml"
FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
want_red "a template whose forsgren.yml has no pull-requests: read line" "acme/tpl:.github/workflows/forsgren.yml has no pull-requests: read line"
nothing_committed "a template with no pull-requests: read line"
world
cp "${TMP}/noprread.yml" "${STATE}/files/.github/workflows/forsgren.yml"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "metrics with no pull-requests: read line still moves its pins" "OK: acme/met pull request for ${VERSION}"

# 3: metrics
world
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "metrics" "OK: acme/met pull request for ${VERSION}: https://example.test/pull/1"
if [[ "$(grep -c 'git/blobs' "${TMP}/gh.log")" -eq 2 ]]; then echo "  ok: two blobs, no README"; else fail "want two blobs. Log: $(cat "${TMP}/gh.log")"; fi
if grep -qF "commit of release v1.9.3" "${STATE}"/bodies/*blobs* && ! grep -qF "commit of release v${VERSION}" "${STATE}"/bodies/*blobs*; then echo "  ok: the metrics pull request changes the pins only, the comments stay"; else fail "the metrics blobs changed a comment"; fi
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
cp "$RELEASED" "${STATE}/files/README.md"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "metrics already on the pin is already done" "already done: acme/met already pins ${VERSION}"
FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
want_green "template already on the pin is already done" "already done: acme/tpl already pins ${VERSION}"
if grep -q 'git/commits --input\|git/refs\|PATCH\|pr create' "${TMP}/gh.log"; then fail "something was written although everything was already pinned"; else echo "  ok: nothing was written"; fi

# prs <url state>...: the pull requests the stub lists for the release branch.
prs() {
  local out="[" sep="" pair
  for pair in "$@"; do
    out+="${sep}{\"url\":\"${pair% *}\",\"state\":\"${pair#* }\"}"
    sep=","
  done
  echo "${out}]" > "${STATE}/pr_list.json"
}
P18="https://example.test/pull/18"
P19="https://example.test/pull/19"
nothing_written() {
  if grep -q 'git/commits --input\|git/refs\|PATCH\|pr create' "${TMP}/gh.log"; then fail "$1: something was written"; else echo "  ok: $1: nothing was written"; fi
}

world
prs "${P18} OPEN"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "an open pull request is already done" "already done: pull request ${P18} (OPEN)"
prs "${P18} MERGED"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "a merged pull request is already done" "(MERGED)"
prs "${P18} CLOSED" "${P19} MERGED"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "a closed and a merged one (closed listed first) is done" "already done: pull request ${P19} (MERGED)"
nothing_written "closed plus merged"
prs "${P18} CLOSED" "${P19} OPEN"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "a closed and an open one (closed listed first) is done" "already done: pull request ${P19} (OPEN)"
nothing_written "closed plus open"

# Closed without merging, nothing else: a NEW pull request, the branch recreated.
world
prs "${P18} CLOSED"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "closed only: a new pull request" "OK: acme/met pull request for ${VERSION}: https://example.test/pull/1"
want_said "the closed one is named" "note: pull request ${P18} was closed without merging; opening a new one"
if grep -qF "refs/heads/forsgren-release-v${VERSION}" "${STATE}"/bodies/*git_refs*; then echo "  ok: the branch is created again"; else fail "the branch was not created"; fi
if grep -qF "pr create" "${TMP}/gh.log"; then echo "  ok: a pull request is opened"; else fail "no pull request was opened"; fi
world
prs "${P18} CLOSED" "${P19} CLOSED"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "two closed ones: a new pull request" "opening a new one"

# The branch still exists: reused when it holds the right tree, else moved.
world
prs "${P18} CLOSED"
echo "OLDBRANCH" > "${STATE}/branch_commit"
echo "NEWTREE" > "${STATE}/branch_tree"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "a branch with the right content is reused" "OK: acme/met pull request for ${VERSION}"
want_said "it says so" "branch forsgren-release-v${VERSION} already holds these pins"
if grep -q 'git/refs' "${TMP}/gh.log" && ! grep -q 'git/refs/heads/forsgren-release-v' "${TMP}/gh.log"; then fail "the branch was created although it exists"; else echo "  ok: the existing branch is not created again"; fi
if grep -qF "pr create" "${TMP}/gh.log"; then echo "  ok: a pull request is opened on it"; else fail "no pull request was opened on the reused branch"; fi
world
prs "${P18} CLOSED"
echo "OLDBRANCH" > "${STATE}/branch_commit"
echo "OTHERTREE" > "${STATE}/branch_tree"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_green "a branch with other content is moved" "OK: acme/met pull request for ${VERSION}"
want_said "it says so" "holds other content; moving it"
if grep -qF "PATCH repos/acme/met/git/refs/heads/forsgren-release-v${VERSION}" "${TMP}/gh.log"; then echo "  ok: the branch is moved to the new commit"; else fail "the stale branch was not moved. Log: $(cat "${TMP}/gh.log")"; fi

# 403 on the workflow files
world
touch "${STATE}/trees_403"
FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
want_red "a 403 writing the tree names the cause" "the token needs Workflows: Read and write on acme/tpl"
want_said "it names the files" ".github/workflows"
FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
want_red "a 403 for the metrics repository" "the token needs Workflows: Read and write on acme/met"

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
if mutant noreadme 's/released:README.md//'; then
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
world
cp "${FIX}/forsgren.yml.fixture" "${TMP}/f.yml"
GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" < "${TMP}/f.yml" > "${STATE}/files/.github/workflows/forsgren.yml"
GITHUB_REPOSITORY=yveshanoulle/forsgren "$PINS" rewrite workflow "$VERSION" "$SHA" < "${FIX}/forsgren-update.yml.fixture" > "${STATE}/files/.github/workflows/forsgren-update.yml"
cp "$RELEASED" "${STATE}/files/README.md"
if mutant notidempotent "s/echo \"OK: already done: .{TARGET} already pins .{VERSION}\"/red \"no file of ${D}{TARGET} needed a change\"/"; then
  FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
  want_red "mutation proof: a template step that fails on an already-moved pin" "needed a change"
fi
world
touch "${STATE}/trees_403"
if mutant nocause "s/the token needs Workflows: Read and write on/the token lacks something on/"; then
  FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
  if grep -qF "Workflows: Read and write" <<< "$OUT"; then fail "mutation proof: the mutant still names the cause"; else echo "  ok: mutation proof: without the hint a 403 does not name the permission"; fi
fi
world
prs "${P18} CLOSED" "${P19} MERGED"
if mutant firstonly "s/'\\.\\[\\] | \\[\\.url/'.[0] | [.url/"; then
  FORSGREN_RELEASE_TOKEN="rt-token" pins metrics "$VERSION" "$SHA"
  if grep -qF "pr create" "${TMP}/gh.log"; then echo "  ok: mutation proof: picking the first listed pull request opens a duplicate next to a merged one"; else fail "mutation proof: the first-only mutant did not open a duplicate. Output: ${OUT}"; fi
fi
world
if mutant oldreadme 's/released:README.md/readme:README.md/'; then
  FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
  readme_blob > "${TMP}/written.md" || : > "${TMP}/written.md"
  if [[ "$RC" -eq 0 ]] && ! grep -qF "$RELEASED_LINE" "${TMP}/written.md" && grep -qF "The rest is the installation's own text." "${TMP}/written.md"; then
    echo "  ok: mutation proof: rewriting the old README's version line commits the old body, which case 8 sees"
  else
    fail "mutation proof: the old-README mutant did not commit the old body (exit ${RC}). Output: ${OUT}"
  fi
fi
world
if mutant otherref "s#/cmd/forsgren@.{SHA}#/cmd/forsgren@latest#"; then
  FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
  if grep -qF "|install github.com/yveshanoulle/forsgren/cmd/forsgren@latest" "${TMP}/go.log" && ! grep -qF "@${SHA}" "${TMP}/go.log"; then
    echo "  ok: mutation proof: an install of another ref shows in the go log, which case 8 pins to the released sha"
  else
    fail "mutation proof: the other-ref mutant did not install @latest. go log: $(cat "${TMP}/go.log")"
  fi
fi
world
perl -pi -e "s/forsgren ${VERSION}:/forsgren 1.9.4-0.20261022-89abcdef0123:/" "${STATE}/released.md"
if mutant noversioncheck 's/^  pinned released "..WORK.\/released.md" \\$/  true \\/'; then
  FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
  if ! grep -qF "the README of the release does not name" <<< "$OUT" && grep -q 'git/blobs' "${TMP}/gh.log"; then
    echo "  ok: mutation proof: without the early version check blobs are written before a pseudo-version README is refused, which case 8 sees"
  else
    fail "mutation proof: the no-version-check mutant still refused before writing (exit ${RC}). Output: ${OUT}"
  fi
fi
unset SCRIPT
# 1c's proofs: without the pull-requests rewrite the old comment stays, and a
# rewrite that is right once but changes a line it already rewrote is caught
# by the second run.
if selftest_mutant "$PINS" "${TMP}/mut/noprcomment/release_pins.sh" 's/pull-requests:\[ \\t\]\*read/never-matches/'; then
  GITHUB_REPOSITORY=yveshanoulle/forsgren "${TMP}/mut/noprcomment/release_pins.sh" rewrite workflow "$VERSION" "$SHA" < "${FIX}/forsgren.yml.fixture" > "${TMP}/mut.yml"
  if grep -qF "$PR_OLD" "${TMP}/mut.yml" && ! grep -qxF "$PR_NEW" "${TMP}/mut.yml"; then
    echo "  ok: mutation proof: without the pull-requests rewrite the old comment stays, which 1c sees"
  else
    fail "mutation proof: the no-comment mutant still rewrote the pull-requests: read comment"
  fi
fi
NOTIDEM=$'/pull-requests:\\[ \\\\t\\]\\*read/{s/^ *s{/        $x = \\/names it$\\/m; s{/;s/mg;\'$/mg; s{(names it)$}{$1 again}m if $x;\'/;}'
if selftest_mutant "$PINS" "${TMP}/mut/notidem/release_pins.sh" "$NOTIDEM"; then
  GITHUB_REPOSITORY=yveshanoulle/forsgren "${TMP}/mut/notidem/release_pins.sh" rewrite workflow "$VERSION" "$SHA" < "${FIX}/forsgren.yml.fixture" > "${TMP}/mut1.yml"
  GITHUB_REPOSITORY=yveshanoulle/forsgren "${TMP}/mut/notidem/release_pins.sh" rewrite workflow "$VERSION" "$SHA" < "${TMP}/mut1.yml" > "${TMP}/mut2.yml"
  if grep -qxF "$PR_NEW" "${TMP}/mut1.yml" && ! cmp -s "${TMP}/mut1.yml" "${TMP}/mut2.yml"; then
    echo "  ok: mutation proof: a rewrite right once but not stable changes the file on the second run, which 1c sees"
  else
    fail "mutation proof: the not-idempotent mutant was not right once and different twice. Once: $(grep -F 'pull-requests:' "${TMP}/mut1.yml")"
  fi
fi
# 8b's proof: without the check a template with no pull-requests: read line
# is committed, the comment skipped silently.
world
cp "${TMP}/noprread.yml" "${STATE}/files/.github/workflows/forsgren.yml"
if mutant noprcheck 's/pr_read ".kind" "..WORK.\/new" ||/true ||/'; then
  FORSGREN_RELEASE_TOKEN="rt-token" pins template "$VERSION" "$SHA"
  if [[ "$RC" -eq 0 ]] && grep -q 'git/commits --input' "${TMP}/gh.log"; then
    echo "  ok: mutation proof: without the check a template with no pull-requests: read line is committed, which 8b sees"
  else
    fail "mutation proof: the no-check mutant still refused (exit ${RC}). Output: ${OUT}"
  fi
fi
unset SCRIPT

selftest_end "the release pins do not hold" "release pins: rewrite, one template commit, a metrics branch and pull request, and no run without the token"
