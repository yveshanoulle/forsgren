#!/usr/bin/env bash
# Scripts/test_release_metrics.sh
#
# Self-test for Scripts/release_metrics.sh (forsgren#221, step 5): the Release
# workflow finishes the metrics update itself, a pull request merged and a
# forsgren.yml run green. No network: a stub gh plays forsgren-metrics (its pull
# requests, their files, the runs of forsgren.yml as a numbered sequence of
# answers, the last repeating) and logs every call.
#   1. an open pull request that moves only the pins -> read, squash-merged with
#      its branch deleted, forsgren.yml started on the default branch and
#      waited for -> `OK: metrics: PR #N merged, forsgren run <url> green`
#   2. an open pull request that changes more than the pins -> red, NOT merged
#   3. a merge that is refused -> red
#   4. resume: a merged pull request and a green run after the merge -> already
#      done, nothing merged, no second run; a green run only BEFORE the merge, or
#      only red ones after it -> a run is started; one still going -> waited for,
#      no second run
#   5. the started run ends red or cancelled -> red with its URL; a run that
#      never ends -> red after exactly the bound
#   6. no pull request: pins already on the default branch -> the runs after the
#      commit that changed forsgren.yml are judged; not pinned -> red
#   7. no token -> ::error::, usage
# Mutation proofs: a copy that merges without reading the files, one that does
# not wait for the run, one that takes a red run for done and one that starts a
# second run next to a green one must each let their case pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
selftest_begin "release metrics self-test"
D='$'

METRICS="Scripts/release_metrics.sh"
[[ -f "$METRICS" ]] || selftest_abort "${METRICS} does not exist — the metrics site would not be moved to the release"

SHA="89abcdef0123456789abcdef0123456789abcdef"
OLD="5ed7552d038600680ac8f4d969dac3a51eefce73"
VERSION="1.9.5"
STUBS="${TMP}/bin"
STATE="${TMP}/state"
mkdir -p "$STUBS" "$STATE"
cat > "${STUBS}/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "${GH_TOKEN-unset}" "$*" >> "${STUB_LOG:?}"
S="${STUB_STATE:?}"
case "$1 $2" in
  "pr list") cat "${S}/prs" 2> /dev/null || true ;;
  "pr merge") [ -f "${S}/merge_fails" ] && { echo "HTTP 405" >&2; exit 1; }; : > "${S}/merged" ;;
  "pr view") cat "${S}/merged_at" ;;
  "run list")
    n=$(($(cat "${S}/count" 2> /dev/null || echo 0) + 1))
    echo "$n" > "${S}/count"
    f="${S}/runs.${n}"
    [ -f "$f" ] || f="$(ls "${S}"/runs.* 2> /dev/null | sort -t. -k2 -n | tail -1)"
    if [ -n "$f" ]; then cat "$f"; fi
    ;;
  "workflow run") : > "${S}/dispatched" ;;
  "api "*)
    case "$*" in
      *pulls/*/files*) cat "${S}/files.json" ;;
      *contents/.github/workflows/forsgren.yml*) cat "${S}/forsgren.yml.b64" ;;
      *commits\?path=*) cat "${S}/commit_date" ;;
      *) echo main ;;
    esac
    ;;
esac
STUB
chmod +x "${STUBS}/gh"

PATCH_MAIN=$'@@ -19,7 +19,7 @@\n-    uses: acme/forsgren/.github/workflows/metrics.yml@'"${OLD}"$' # v1.9.4\n+    uses: acme/forsgren/.github/workflows/metrics.yml@'"${SHA}"$' # v1.9.5'
PATCH_UPD=$'@@ -17,4 +17,4 @@\n-    uses: acme/forsgren/.github/workflows/auto_update.yml@'"${OLD}"$' # v1.9.4\n+    uses: acme/forsgren/.github/workflows/auto_update.yml@'"${SHA}"$' # v1.9.5'

# world: a clean stub; pins_files <extra file?> writes the pull request files.
world() {
  rm -rf "${STATE:?}"/*
  : > "${TMP}/gh.log"
  : > "${STATE}/runs.1"
  echo "2026-10-18T10:00:00Z" > "${STATE}/merged_at"
}
good_files() {
  jq -n --arg a "$PATCH_MAIN" --arg b "$PATCH_UPD" \
    '[{filename: ".github/workflows/forsgren.yml", patch: $a}, {filename: ".github/workflows/forsgren-update.yml", patch: $b}]' > "${STATE}/files.json"
}
# prs <number state url mergedAt>: the pull request list.
prs() { printf '%s\t%s\t%s\t%s\n' "$@" > "${STATE}/prs"; }
# runline <n> <id> <status> <conclusion or -> <createdAt>: adds a line to the
# n-th answer of the run list.
runline() {
  local conclusion="$4"
  if [[ "$conclusion" == "-" ]]; then conclusion=""; fi
  printf '%s\t%s\t%s\thttps://example.test/run/%s\t%s\n' "$2" "$3" "$conclusion" "$2" "$5" >> "${STATE}/runs.$1"
}
metrics() {
  PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_STATE="$STATE" GITHUB_REPOSITORY="acme/forsgren" RELEASE_METRICS_REPO="acme/met" \
    RELEASE_METRICS_DELAY=0 RELEASE_METRICS_TRIES="${TRIES:-6}" FORSGREN_RELEASE_TOKEN="${TOKEN-rt-token}" \
    capture "${SCRIPT:-$METRICS}" "$@"
}
called() { grep -qE "$1" "${TMP}/gh.log"; }
BEFORE_MERGE="2026-10-18T09:00:00Z"
AFTER_MERGE="2026-10-18T10:05:00Z"

# 1: an open pull request, only the pins.
world
good_files
prs 19 OPEN https://example.test/pull/19 ""
runline 1 100 completed success "$BEFORE_MERGE"
runline 2 100 completed success "$BEFORE_MERGE"
runline 2 101 in_progress - "$AFTER_MERGE"
runline 3 100 completed success "$BEFORE_MERGE"
runline 3 101 completed success "$AFTER_MERGE"
metrics "$VERSION" "$SHA"
want_green "an open pin pull request" "OK: metrics: PR #19 merged, forsgren run https://example.test/run/101 green"
want_said "the pull request is a line" "pull=19"
want_said "the run is a line" "run=https://example.test/run/101"
if called "^rt-token\|pr merge 19 --repo acme/met --squash --delete-branch"; then echo "  ok: squash-merged with its branch deleted, with the release token"; else fail "the merge call is not as pinned. Log: $(cat "${TMP}/gh.log")"; fi
if called "^rt-token\|workflow run forsgren.yml --repo acme/met --ref main"; then echo "  ok: forsgren.yml is started on the default branch"; else fail "forsgren.yml was not started. Log: $(cat "${TMP}/gh.log")"; fi
if [[ "$(grep -c '^[^|]*|workflow run' "${TMP}/gh.log")" -eq 1 ]]; then echo "  ok: one run is started"; else fail "want one dispatch"; fi
if grep -v '^rt-token|' "${TMP}/gh.log" | has -q .; then fail "a call ran with another token"; else echo "  ok: every call used the release token"; fi

# 2: more than the pins.
world
jq -n --arg a "$PATCH_MAIN" --arg b "$PATCH_UPD" \
  '[{filename: ".github/workflows/forsgren.yml", patch: $a}, {filename: ".github/workflows/forsgren-update.yml", patch: $b}, {filename: "README.md", patch: $a}]' > "${STATE}/files.json"
prs 19 OPEN https://example.test/pull/19 ""
metrics "$VERSION" "$SHA"
want_red "a pull request that changes more than the pins" "pull request #19 changes more than the forsgren pins of this release: it was not merged"
want_said "the finding is named" "README.md, which is no forsgren caller workflow"
if called "pr merge"; then fail "a pull request with another change was merged"; else echo "  ok: it was not merged"; fi
if called "workflow run"; then fail "forsgren.yml was started"; fi

# 3: a refused merge.
world
good_files
prs 19 OPEN https://example.test/pull/19 ""
touch "${STATE}/merge_fails"
metrics "$VERSION" "$SHA"
want_red "a merge that is refused" "pull request #19 could not be merged"

# 4: resume.
world
prs 19 MERGED https://example.test/pull/19 "2026-10-18T10:00:00Z"
runline 1 101 completed success "$AFTER_MERGE"
metrics "$VERSION" "$SHA"
want_green "merged and a green run after: already done" "a forsgren.yml run after the merge is already green"
want_said "the report line" "OK: metrics: PR #19 merged, forsgren run https://example.test/run/101 green"
if called "pr merge|workflow run"; then fail "something was merged or started although it was done"; else echo "  ok: nothing merged, no second run"; fi
world
prs 19 MERGED https://example.test/pull/19 "2026-10-18T10:00:00Z"
runline 1 100 completed success "$BEFORE_MERGE"
runline 2 100 completed success "$BEFORE_MERGE"
runline 2 102 in_progress - "$AFTER_MERGE"
runline 3 100 completed success "$BEFORE_MERGE"
runline 3 102 completed success "$AFTER_MERGE"
metrics "$VERSION" "$SHA"
want_green "only a green run before the merge: a run is started" "OK: metrics: PR #19 merged, forsgren run https://example.test/run/102 green"
if called "workflow run"; then echo "  ok: a run was started"; else fail "no run was started"; fi
world
prs 19 MERGED https://example.test/pull/19 "2026-10-18T10:00:00Z"
runline 1 103 completed failure "$AFTER_MERGE"
runline 2 103 completed failure "$AFTER_MERGE"
runline 2 104 in_progress - "$AFTER_MERGE"
runline 3 103 completed failure "$AFTER_MERGE"
runline 3 104 completed success "$AFTER_MERGE"
metrics "$VERSION" "$SHA"
want_green "only a red run after the merge: a new run is started and judged" "forsgren run https://example.test/run/104 green"
world
prs 19 MERGED https://example.test/pull/19 "2026-10-18T10:00:00Z"
runline 1 105 in_progress - "$AFTER_MERGE"
runline 2 105 completed success "$AFTER_MERGE"
metrics "$VERSION" "$SHA"
want_green "a run still going is waited for" "forsgren run https://example.test/run/105 green"
if called "workflow run"; then fail "a second run was started next to one that is going"; else echo "  ok: no second run next to one that is going"; fi
world
prs 18 CLOSED https://example.test/pull/18 ""
printf '%s\t%s\t%s\t%s\n' 19 MERGED https://example.test/pull/19 "2026-10-18T10:00:00Z" >> "${STATE}/prs"
runline 1 101 completed success "$AFTER_MERGE"
metrics "$VERSION" "$SHA"
want_green "a closed pull request next to the merged one is no matter" "PR #19 merged"

# 5: the run ends red, cancelled, or never.
world
good_files
prs 19 OPEN https://example.test/pull/19 ""
runline 1 100 completed success "$BEFORE_MERGE"
runline 2 100 completed success "$BEFORE_MERGE"
runline 2 106 completed failure "$AFTER_MERGE"
metrics "$VERSION" "$SHA"
want_red "the started run is red" "the forsgren.yml run https://example.test/run/106 in acme/met ended as failure"
world
good_files
prs 19 OPEN https://example.test/pull/19 ""
runline 2 107 completed cancelled "$AFTER_MERGE"
metrics "$VERSION" "$SHA"
want_red "the started run is cancelled" "https://example.test/run/107 in acme/met ended as cancelled"
world
good_files
prs 19 OPEN https://example.test/pull/19 ""
runline 2 108 in_progress - "$AFTER_MERGE"
TRIES=4 metrics "$VERSION" "$SHA"
want_red "a run that never ends" "gave up after 4 polls of 0s: the forsgren.yml run of acme/met is still going"
if [[ "$(grep -c 'run list' "${TMP}/gh.log")" -eq 5 ]]; then echo "  ok: the wait is bounded (the check, then 4 polls)"; else fail "the wait is not bounded to the tries. Log: $(cat "${TMP}/gh.log")"; fi

# 6: no pull request.
world
printf '%s\n' "$(printf 'uses: x@%s # v%s' "$SHA" "$VERSION" | base64)" > "${STATE}/forsgren.yml.b64"
echo "2026-10-18T10:00:00Z" > "${STATE}/commit_date"
runline 1 101 completed success "$AFTER_MERGE"
metrics "$VERSION" "$SHA"
want_green "pins already on the default branch, a green run after" "OK: metrics: PR #none merged, forsgren run https://example.test/run/101 green"
world
printf '%s\n' "$(printf 'uses: x@%s # v1.9.4' "$OLD" | base64)" > "${STATE}/forsgren.yml.b64"
metrics "$VERSION" "$SHA"
want_red "no pull request and not pinned" "no pull request for forsgren-release-v${VERSION} in acme/met, and main does not pin v${VERSION}"

# 7
TOKEN="" metrics "$VERSION" "$SHA"
want_exit "no token" 1 "::error::FORSGREN_RELEASE_TOKEN is not set"
metrics 1.9 "$SHA"
want_exit "a malformed version" 2 "usage"
metrics

# Mutation proofs.
mutant() {
  selftest_mutant "$METRICS" "${TMP}/mut/$1/release_metrics.sh" "$2" || return 1
  mkdir -p "${TMP}/mut/$1/Scripts"
  cp Scripts/release_verify_pin.sh "${TMP}/mut/$1/Scripts/"
  mv "${TMP}/mut/$1/release_metrics.sh" "${TMP}/mut/$1/Scripts/release_metrics.sh"
  SCRIPT="${TMP}/mut/$1/Scripts/release_metrics.sh"
}
world
jq -n --arg a "$PATCH_MAIN" --arg b "$PATCH_UPD" \
  '[{filename: ".github/workflows/forsgren.yml", patch: $a}, {filename: ".github/workflows/forsgren-update.yml", patch: $b}, {filename: "README.md", patch: $a}]' > "${STATE}/files.json"
prs 19 OPEN https://example.test/pull/19 ""
runline 1 100 completed success "$BEFORE_MERGE"
runline 2 101 completed success "$AFTER_MERGE"
if mutant noverify "s/\.\/Scripts\/release_verify_pin\.sh \".VERSION\" \".SHA\"/cat > \/dev\/null/"; then
  metrics "$VERSION" "$SHA"
  if called "pr merge"; then echo "  ok: mutation proof: without reading the files a pull request that changes more than the pins is merged"; else fail "mutation proof: the mutant still refuses. Output: ${OUT}"; fi
fi
unset SCRIPT

world
good_files
prs 19 OPEN https://example.test/pull/19 ""
runline 2 109 completed failure "$AFTER_MERGE"
if mutant nowait "s/^while \[ \".try\" -lt \".TRIES\" \]; do\$/finish \"https:\/\/example.test\/dispatched\"; while false; do/"; then
  metrics "$VERSION" "$SHA"
  if [[ "$RC" -eq 0 ]] && grep -qF "OK: metrics" <<< "$OUT"; then echo "  ok: mutation proof: without the wait a run that ends red is reported done"; else fail "mutation proof: the mutant that does not wait still failed. Output: ${OUT}"; fi
fi
unset SCRIPT

world
good_files
prs 19 OPEN https://example.test/pull/19 ""
runline 2 109 completed failure "$AFTER_MERGE"
if mutant redisdone "s/if \[ \".conclusion\" = success \]; then finish \".url\"; fi/finish \"${D}url\"/"; then
  metrics "$VERSION" "$SHA"
  if [[ "$RC" -eq 0 ]] && grep -qF "run/109 green" <<< "$OUT"; then echo "  ok: mutation proof: a red run taken for done is reported green"; else fail "mutation proof: the mutant still refuses a red run. Output: ${OUT}"; fi
fi
unset SCRIPT

world
prs 19 MERGED https://example.test/pull/19 "2026-10-18T10:00:00Z"
runline 1 101 completed success "$AFTER_MERGE"
runline 2 101 completed success "$AFTER_MERGE"
runline 2 110 completed success "$AFTER_MERGE"
if mutant second "s/^  if \[ \".status\" = completed \] \&\& \[ \".conclusion\" = success \]; then\$/  if false; then/"; then
  metrics "$VERSION" "$SHA"
  if called "workflow run"; then echo "  ok: mutation proof: ignoring the green run starts a second one"; else fail "mutation proof: the mutant did not start a second run. Output: ${OUT}"; fi
fi
unset SCRIPT

selftest_end "the release metrics does not hold" "release metrics: the pins are read, merged and a green forsgren run waited for; resume starts no second run"
