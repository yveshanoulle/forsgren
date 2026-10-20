#!/usr/bin/env bash
# Scripts/test_release_quality.sh
#
# Self-test for Scripts/release_quality.sh (forsgren#221, step 2 of 2). No
# network: a stub gh on PATH answers `run list` from a numbered sequence of
# fixtures (the last one repeats) and logs every call.
#   1. check, a completed success                      -> OK, polled once
#   2. check, a run still going, then a success        -> OK on poll 2
#   3. check, only a failed run                        -> red naming the run
#   4. check, a failed run and a later success         -> OK (a re-run)
#   5. check, no run at all                            -> red, at once
#   6. a run that never ends                           -> red after exactly
#      the bound, naming the commit
#   7. usage errors                                    -> exit 2
#   8. dispatch is not a mode any more (forsgren#237, step 6): the Release
#      workflow starts no Quality run
#  11. head <sha> (forsgren#237, step 5a): green when main's head is the sha, red
#      naming both shas when main moved, red when the head cannot be read
# Mutation proofs: a copy that never compares the head must let a moved main
# pass; one that takes a failed run for green, one that does not
# wait (gives up on a running run) and one that has no bound must each let the
# case they exist for pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release quality self-test"
D='$'

CHECK="Scripts/release_quality.sh"
[[ -f "$CHECK" ]] || selftest_abort "${CHECK} does not exist — nothing waits for Quality on a release commit"

SHA="0123456789abcdef0123456789abcdef01234567"
TAB=$'\t'
STUBS="${TMP}/bin"
mkdir -p "$STUBS" "${TMP}/seq"
cat > "${STUBS}/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LOG:?}"
case "$1 $2" in
  "run list")
    n=$(($(cat "${STUB_SEQ:?}/count" 2> /dev/null || echo 0) + 1))
    echo "$n" > "${STUB_SEQ}/count"
    f="${STUB_SEQ}/runs.${n}"
    [ -f "$f" ] || f="$(ls "${STUB_SEQ}"/runs.* | sort -t. -k2 -n | tail -1)"
    cat "$f"
    ;;
  "api repos/acme/forsgren/git/ref/heads/main")
    if [ -f "${STUB_SEQ}/api_fails" ]; then echo "HTTP 500" >&2; exit 1; fi
    cat "${STUB_SEQ}/main_sha"
    ;;
esac
STUB
chmod +x "${STUBS}/gh"

# runs <line>...: the fixtures; one argument per poll, lines of one poll
# separated by @@.
runs() {
  rm -f "${TMP}"/seq/*
  : > "${TMP}/gh.log"
  local n=0 poll
  for poll in "$@"; do
    n=$((n + 1))
    printf '%s\n' "${poll//@@/$'\n'}" | sed '/^$/d' > "${TMP}/seq/runs.${n}"
  done
}

run() {
  GITHUB_REPOSITORY=acme/forsgren PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_SEQ="${TMP}/seq" \
    RELEASE_QUALITY_DELAY=0 RELEASE_QUALITY_TRIES="${TRIES:-5}" capture "${SCRIPT:-$CHECK}" "$@"
}
OK_RUN="completed${TAB}success${TAB}https://example.test/run/1"
BAD_RUN="completed${TAB}failure${TAB}https://example.test/run/2"
GOING="in_progress${TAB}${TAB}https://example.test/run/3"

runs "$OK_RUN"
run check "$SHA"
want_green "a green run" "OK: Quality is green on ${SHA}"
want_said "it says the poll" "poll 1"
if ! grep -qF -- "--commit ${SHA}" "${TMP}/gh.log"; then fail "gh was not asked for the runs of the commit. Log: $(cat "${TMP}/gh.log")"; fi

runs "$GOING" "$OK_RUN"
run check "$SHA"
want_green "a run still going, then green" "poll 2"

runs "$BAD_RUN"
run check "$SHA"
want_red "only a failed run" "Quality is not green on ${SHA}: https://example.test/run/2 (failure)"

runs "${BAD_RUN}@@${OK_RUN}"
run check "$SHA"
want_green "a failed run and a later success" "OK: Quality is green"

runs ""
run check "$SHA"
want_red "no run at all" "no Quality run on ${SHA}"
if [[ "$(grep -c '^run list' "${TMP}/gh.log")" -ne 1 ]]; then fail "check polled more than once for no run at all"; fi

runs "$GOING"
TRIES=4 run check "$SHA"
want_red "a run that never ends" "gave up after 4 polls"
want_said "the commit is named" "$SHA"
if [[ "$(grep -c '^run list' "${TMP}/gh.log")" -ne 4 ]]; then fail "the wait was not exactly 4 polls. Log: $(cat "${TMP}/gh.log")"; else echo "  ok: the wait is bounded to the tries"; fi

# 11 (forsgren#237, step 5a): head <sha> proves main's head still is the commit
# Quality was proved green on, before a tag is made at it.
MOVED="fedcba9876543210fedcba9876543210fedcba98"
printf '%s\n' "$SHA" > "${TMP}/seq/main_sha"
run head "$SHA"
want_green "main's head is the commit" "OK: main's head is ${SHA}"
printf '%s\n' "$MOVED" > "${TMP}/seq/main_sha"
run head "$SHA"
want_red "main has moved" "main has moved: its head is ${MOVED}, not ${SHA}"
want_said "the commit Quality was proved on is named" "Quality was proved green on ${SHA}"
touch "${TMP}/seq/api_fails"
run head "$SHA"
want_red "gh cannot read main" "could not read the head of main"
rm -f "${TMP}/seq/api_fails"
printf '\n' > "${TMP}/seq/main_sha"
run head "$SHA"
want_red "gh answers no sha" "could not read the head of main"
run head abc
want_exit "head with a short sha" 2 "usage"
run head
want_exit "head without a sha" 2 "usage"

run
want_exit "no mode" 2 "usage"
run check
want_exit "no sha" 2 "usage"
run check abc
want_exit "a short sha" 2 "usage"
run dispatch "$SHA" main
want_exit "dispatch is no mode any more" 2 "usage"

# Mutation proofs.
mutant() {
  local name="$1"
  selftest_mutant "$CHECK" "${TMP}/mut/${name}/release_quality.sh" "$2" || return 1
  SCRIPT="${TMP}/mut/${name}/release_quality.sh"
}

if mutant failgreen "s/\[ \".conclusion\" = success \]/[ -n \"${D}conclusion\" ]/"; then
  runs "$BAD_RUN"
  run check "$SHA"
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof: the mutant that ignores a failed run still refused it. Output: ${OUT}"
  else
    echo "  ok: mutation proof: without the failure check a failed run is not refused"
  fi
fi
if mutant nowait 's/pending=1/pending=0/'; then
  runs "$GOING"
  TRIES=4 run check "$SHA"
  want_red "mutation proof: a run still going is no longer waited for" "no Quality run on ${SHA}"
fi
if mutant unbounded "s/while \[ \".try\" -lt \".TRIES\" \]; do/while [ \"${D}try\" -lt 3 ]; do/"; then
  runs "$GOING"
  TRIES=1 run check "$SHA"
  if [[ "$(grep -c '^run list' "${TMP}/gh.log")" -eq 1 ]]; then
    fail "mutation proof: the mutant with a fixed bound still honoured the tries. Output: ${OUT}"
  else
    echo "  ok: mutation proof: without the tries the bound is no longer the caller's"
  fi
fi
unset SCRIPT

if mutant headblind 's/if \[ "[$]HEAD_SHA" != "[$]SHA" \]; then/if false; then/'; then
  printf '%s\n' "$MOVED" > "${TMP}/seq/main_sha"
  run head "$SHA"
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof: the mutant that never compares the head still refused a moved main. Output: ${OUT}"
  else
    echo "  ok: mutation proof: without the comparison a moved main is not refused"
  fi
fi

selftest_end "the release quality check does not hold" "release quality: green, going, failed, absent and bounded runs all judged right"
