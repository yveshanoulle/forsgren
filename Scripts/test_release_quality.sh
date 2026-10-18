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
#   6. dispatch starts quality.yml on the ref, then waits, also while no run
#      has appeared yet
#   7. a run that never ends / never appears           -> red after exactly
#      the bound, naming the commit
#   8. dispatch that gh refuses                        -> red, nothing awaited
#   9. usage errors                                    -> exit 2
#  10. dispatch-bump (forsgren#230, step 2) starts quality.yml on the ref with
#      scope=bump and the green parent, the old and the new version as inputs,
#      then waits as dispatch does; bad shas and versions -> exit 2
# Mutation proofs: a copy that dispatches the bump with the full scope, and one that takes a failed run for green, one that does not
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
  "workflow run")
    if [ -f "${STUB_SEQ}/dispatch_fails" ]; then echo "HTTP 403" >&2; exit 1; fi
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
  PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/gh.log" STUB_SEQ="${TMP}/seq" \
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

runs "" "" "$OK_RUN"
run dispatch "$SHA" main
want_green "dispatch, the run appears on poll 3" "poll 3"
if ! grep -qxF "workflow run quality.yml --ref main" "${TMP}/gh.log"; then fail "gh was not told to run quality.yml on main. Log: $(cat "${TMP}/gh.log")"; else echo "  ok: quality.yml is started on the ref"; fi

runs "$GOING"
TRIES=4 run check "$SHA"
want_red "a run that never ends" "gave up after 4 polls"
want_said "the commit is named" "$SHA"
if [[ "$(grep -c '^run list' "${TMP}/gh.log")" -ne 4 ]]; then fail "the wait was not exactly 4 polls. Log: $(cat "${TMP}/gh.log")"; else echo "  ok: the wait is bounded to the tries"; fi

runs ""
TRIES=3 run dispatch "$SHA" main
want_red "a run that never appears" "no run yet on ${SHA}"

runs "$OK_RUN"
touch "${TMP}/seq/dispatch_fails"
run dispatch "$SHA" main
want_red "a dispatch gh refuses" "could not start quality.yml on main"
if grep -q '^run list' "${TMP}/gh.log"; then fail "it waited for a run after the dispatch failed"; fi
rm -f "${TMP}/seq/dispatch_fails"

GREEN="89abcdef0123456789abcdef0123456789abcdef"
BUMP_ARGS="-f scope=bump -f green_parent=${GREEN} -f old_version=1.10.0 -f new_version=1.11.0"
runs "" "$OK_RUN"
run dispatch-bump "$SHA" main "$GREEN" 1.10.0 1.11.0
want_green "dispatch-bump, the run appears on poll 2" "poll 2"
bump_dispatch_findings() {
  grep -qxF "workflow run quality.yml --ref main ${BUMP_ARGS}" "${TMP}/gh.log" \
    || echo "gh was not told to run quality.yml on main with ${BUMP_ARGS}. Log: $(cat "${TMP}/gh.log")"
}
if [[ -z "$(bump_dispatch_findings)" ]]; then echo "  ok: quality.yml is started with scope=bump and the parent and versions"; else fail "$(bump_dispatch_findings)"; fi
runs "$OK_RUN"
run dispatch "$SHA" main
if grep -qF -- "scope=" "${TMP}/gh.log"; then fail "a plain dispatch passes a scope: $(cat "${TMP}/gh.log")"; else echo "  ok: a plain dispatch passes no scope, so it runs the full Quality"; fi
run dispatch-bump "$SHA" main "$GREEN" 1.10.0
want_exit "dispatch-bump without the new version" 2 "usage"
run dispatch-bump "$SHA" main abc 1.10.0 1.11.0
want_exit "dispatch-bump with a short green parent" 2 "usage"
run dispatch-bump "$SHA" main "$GREEN" 1.10 1.11.0
want_exit "dispatch-bump with a malformed version" 2 "usage"

run
want_exit "no mode" 2 "usage"
run check
want_exit "no sha" 2 "usage"
run check abc
want_exit "a short sha" 2 "usage"
run dispatch "$SHA"
want_exit "dispatch without a ref" 2 "usage"

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
if mutant fullscope 's/ -f scope=bump//'; then
  runs "$OK_RUN"
  run dispatch-bump "$SHA" main "$GREEN" 1.10.0 1.11.0
  if [[ -n "$(bump_dispatch_findings)" ]]; then
    echo "  ok: mutation proof: a dispatch-bump without scope=bump is named: it would run the full Quality"
  else
    fail "mutation proof: the mutant without scope=bump still dispatched the bump scope"
  fi
fi
if mutant noparent 's/ -f green_parent="[$]4"//'; then
  runs "$OK_RUN"
  run dispatch-bump "$SHA" main "$GREEN" 1.10.0 1.11.0
  if [[ -n "$(bump_dispatch_findings)" ]]; then
    echo "  ok: mutation proof: a dispatch-bump without the green parent is named"
  else
    fail "mutation proof: the mutant without the green parent still passed it"
  fi
fi
unset SCRIPT

selftest_end "the release quality check does not hold" "release quality: green, going, failed, absent, dispatched and bounded runs all judged right"
