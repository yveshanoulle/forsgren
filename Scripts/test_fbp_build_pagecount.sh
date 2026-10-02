#!/usr/bin/env bash
# Scripts/test_fbp_build_pagecount.sh
#
# Issue konenki-website#8, ruled fail fast (Yves, 2026-09-30): FullBuildAndPush's summary
# must show how many pages build_site.sh generated, and a missing,
# non-numeric or zero count must FAIL the build step with a named reason —
# never fall back to the plain row.
#
# Drives the REAL FBP.sh inside a throwaway git sandbox with a
# STUB Scripts/build_site.sh that controls what lands in the page-count
# sink FullBuildAndPush names (.build/site-page-count.log), the same technique
# Scripts/test_fbp_commit_message.sh uses for issue konenki-website#6 — this
# pins the CONTRACT between build_site.sh and FBP.sh, not the
# real builder's own count (Scripts/test_build_site.sh pins that
# separately). The sandbox and its stub are Scripts/lib_fbp_sandbox.sh
# (issue konenki-website#14), shared with the commit-message fixture. The stub writes its
# sink to SITE_PAGE_COUNT_FILE and has no default for it, so
# FullBuildAndPush passing its own path to build_site.sh (issue konenki-website#11) is
# pinned here: case 7 exports a decoy path and still expects a green run.
#
# Issue konenki-website#20 (items 1 and 3, step 3): the self-proofs at the end check this
# fixture from the outside — (a) run_case fails with the sandbox's own
# reason when there is no sandbox, (b) the fixture fails when it dies
# part-way. Scripts/test_fbp_commit_message.sh carries the same
# two for run_fbp, plus (c), no sandbox left behind by a fixture whose own
# EXIT trap replaces the lib's.
#
# Issue konenki-website#17 (cases 8 to 12): the summary rows must not trust raw sink
# content — the PRE and POST gate counts from .build/sfl-counts.log, a NUL
# byte, an unreadable sink and a newline-only sink.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=Scripts/lib_fbp_sandbox.sh
source "${ROOT}/Scripts/lib_fbp_sandbox.sh"

failed=0
fail() { echo "❌ FAIL: $*"; failed=1; }

# Issue konenki-website#20 (item 3): the completion guard every guarded fixture here
# carries. A fixture that dies part-way must fail, never report green: on
# macOS bash 3.2 a set -u abort inside a function can exit 0. COMPLETED is
# set only after the last case. finish replaces the lib's EXIT trap, so it
# runs the lib's cleanup itself first (see Scripts/lib_fbp_sandbox.sh).
COMPLETED=0
finish() {
  fbp_sandbox_cleanup
  if [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: build-pagecount fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap finish EXIT

# assert_run_passed <label> <why>
# Fails the case when the last run_case did not exit 0.
assert_run_passed() {
  local label="$1"
  local why="$2"
  if [ "$RC" -ne 0 ]; then
    fail "${label}: FullBuildAndPush exited ${RC}, want 0 — ${why}"
  fi
}

# assert_run_failed <label> <why>
# Fails the case when the last run_case exited 0.
assert_run_failed() {
  local label="$1"
  local why="$2"
  if [ "$RC" -eq 0 ]; then
    fail "${label}: FullBuildAndPush exited 0 — ${why}"
  fi
}

# assert_post_skipped <label> <subject>
# Fails the case when the last run_case did not skip POST the way a real
# build failure does.
assert_post_skipped() {
  local label="$1"
  local subject="$2"
  grep -Fq "Skipping POST gates because the site build failed" <<< "$OUT" \
    || fail "${label}: POST gates were not skipped — ${subject} must behave exactly like a real build failure"
}

# assert_shown <label> <text> <why>
# Fails the case when the last run_case's output does not hold <text>.
assert_shown() {
  local label="$1"
  local text="$2"
  local why="$3"
  grep -Fq "$text" <<< "$OUT" \
    || fail "${label}: the output does not show '${text}' — ${why}. Output: ${OUT}"
}

# assert_not_shown <label> <text> <why>
# Fails the case when the last run_case's output holds <text>.
assert_not_shown() {
  local label="$1"
  local text="$2"
  local why="$3"
  if grep -Fq "$text" <<< "$OUT"; then
    fail "${label}: the output shows '${text}' — ${why}"
  fi
}

# summary_row <row>
# Prints the first line of the last run_case's output that starts with <row>.
summary_row() {
  awk -v row="$1" 'index($0, row) == 1 { print; exit }' <<< "$OUT"
}

# summary_row_after <row>
# Prints the line after the first line of the last run_case's output that
# starts with <row>.
summary_row_after() {
  awk -v row="$1" 'found { print; exit } index($0, row) == 1 { found = 1 }' <<< "$OUT"
}

# assert_row_one_line <label> <row> <next-row> <why>
# Fails the case when the summary line after the one starting with <row> does
# not start with <next-row>: the <row> summary row broke onto a second line.
assert_row_one_line() {
  local label="$1"
  local row="$2"
  local next_row="$3"
  local why="$4"
  local after
  after="$(summary_row_after "$row")"
  case "$after" in
    "${next_row}"*) ;;
    *)
      fail "${label}: the summary line after '${row}' is '${after}', want the '${next_row}' row — ${why}. Output: ${OUT}"
      ;;
  esac
}

# assert_row_shows_quoted <label> <row> <value>
# Fails the case when the summary row starting with <row> does not show
# <value> the way the build-site row shows a bad page count (issue konenki-website#12):
# through printf %q, so a newline or other control character prints escaped.
# It also fails when that row holds a raw control character. Meant for a
# <value> holding a control character: FullBuildAndPush prints any other
# gate-count value as written, which this check would reject whenever %q
# changes it (a space, for one).
assert_row_shows_quoted() {
  local label="$1"
  local row="$2"
  local value="$3"
  local shown line
  printf -v shown '%q' "$value"
  line="$(summary_row "$row")"
  case "$line" in
    *"${shown}"*) ;;
    *)
      fail "${label}: the '${row}' row is '${line}', want it to show the sfl counts as ${shown} (printf %q, like the page count in the build-site row)"
      ;;
  esac
  case "$line" in
    *[[:cntrl:]]*)
      fail "${label}: the '${row}' row holds a raw control character from .build/sfl-counts.log — it must be shown escaped, never printed raw"
      ;;
  esac
}

# gate_counts_case <label> <pre-counts> <post-counts>
# Runs run_case 3 with the stub sfl.sh writing <pre-counts> to
# .build/sfl-counts.log in PRE and <post-counts> in POST (the
# FBP_SANDBOX_SFL_COUNTS_PRE and FBP_SANDBOX_SFL_COUNTS_POST seams of
# Scripts/lib_fbp_sandbox.sh), then fails the case unless the pre-gates and
# post-gates rows each stay one line and show their counts through printf
# %q. Sink 3 keeps the build green so POST runs.
gate_counts_case() {
  local label="$1"
  local pre="$2"
  local post="$3"
  if FBP_SANDBOX_SFL_COUNTS_PRE="$pre" FBP_SANDBOX_SFL_COUNTS_POST="$post" run_case 3; then
    assert_row_one_line "$label" "  pre gates " "  build site" \
      "the pre-gates row must stay one line, with no raw newline from .build/sfl-counts.log"
    assert_row_one_line "$label" "  post gates " "  git" \
      "the post-gates row must stay one line, with no raw newline from .build/sfl-counts.log"
    assert_row_shows_quoted "$label" "  pre gates " "$pre"
    assert_row_shows_quoted "$label" "  post gates " "$post"
  fi
}

# run_case <sink-content>
# Runs the real FBP.sh --no-commit in a fresh sandbox
# (Scripts/lib_fbp_sandbox.sh) whose stub Scripts/build_site.sh exits 0 and
# writes <sink-content> plus one trailing newline to the SITE_PAGE_COUNT_FILE
# FullBuildAndPush hands it; an empty <sink-content> writes no sink at all.
# The stub line is printf '%s\n' with the value quoted by printf %q, so a
# multi-line <sink-content> such as $'3\n4' lands as two lines, byte for
# byte.
# Cases 8 to 12 shape the stubs further through the issue konenki-website#17 seams of
# Scripts/lib_fbp_sandbox.sh, set as prefix assignments on the run_case call.
# Sets OUT and RC. No label parameter: each case names itself in its own
# fail() and assert_* calls below ("valid count", "missing count", ...), so
# a label passed here would sit unused (shellcheck SC2034).
# Issue konenki-website#20 (item 1): when there is no sandbox it fails this fixture once,
# with the sandbox's own reason, and returns 1, so the case skips its
# assertions instead of failing them against empty output and status -1.
run_case() {
  if ! fbp_sandbox_run "$1" --no-commit; then
    fail "run_case: ${FBP_SANDBOX_REASON}"
    return 1
  fi
  OUT="$(fbp_sandbox_output)"
  RC="$(fbp_sandbox_rc)"
}

# ---------------------------------------------------------------------------
# Case 1: a valid count renders the page-count row, run stays green.
# ---------------------------------------------------------------------------
if run_case 3; then
  assert_shown "valid count" "3 pages generated" "a valid count must show in the build-site row"
  assert_run_passed "valid count" "a valid count must not fail the run"
fi

# ---------------------------------------------------------------------------
# Case 2: no count at all -> fail fast, named reason, POST skipped.
# ---------------------------------------------------------------------------
if run_case ""; then
  assert_shown "missing count" "page count missing" "the build step must fail with this named reason"
  assert_run_failed "missing count" "a missing count must fail fast, never fall back to the plain row"
  assert_post_skipped "missing count" "a fail-fast page count"
fi

# ---------------------------------------------------------------------------
# Case 3: a non-numeric count -> fail fast, named reason.
# ---------------------------------------------------------------------------
if run_case abc; then
  assert_shown "non-numeric count" "page count not numeric" "the build step must fail with this named reason"
  assert_run_failed "non-numeric count" "a malformed count must fail fast"

  # A malformed count skips POST like case 2. Added by issue konenki-website#12 as coverage:
  # this already held when it was written, so it was never seen red.
  assert_post_skipped "non-numeric count" "a malformed count"
fi

# ---------------------------------------------------------------------------
# Case 4: a count of 0 -> fail fast, named reason.
# ---------------------------------------------------------------------------
if run_case 0; then
  # Matched with its opening parenthesis like case 5, so the named reason is
  # asserted and not a substring of some other row. Issue konenki-website#12 coverage, never
  # seen red.
  assert_shown "zero pages" "(0 pages generated)" "the build step must fail with this named reason"

  assert_run_failed "zero pages" "zero generated pages must fail fast, per Yves's ruling on issue konenki-website#8"

  # Issue konenki-website#12 coverage, never seen red.
  assert_post_skipped "zero pages" "a zero count"
fi

# ---------------------------------------------------------------------------
# Case 5: issue konenki-website#12 — a zero count spelled with more than one digit (00) is
# still zero pages: fail fast with the same named reason as case 4, POST
# skipped. The reader must not trust the writer: build_site.sh writes
# $PAGE_COUNT from arithmetic and so never writes 00 itself, but a check
# that only recognised a literal 0 would show it as a green "00 pages
# generated" row.
# Matched on "(0 pages generated)" with its opening parenthesis, because a
# bare "0 pages generated" is a substring of the wrong "00 pages generated".
# ---------------------------------------------------------------------------
if run_case 00; then
  assert_shown "zero pages (00)" "(0 pages generated)" "the build step must fail with this named reason"
  assert_run_failed "zero pages (00)" "a count of 00 is zero generated pages and must fail fast like case 4"
  assert_post_skipped "zero pages (00)" "a zero count"
  assert_not_shown "zero pages (00)" "00 pages generated" "00 must be read as zero, not as a valid page count"
fi

# ---------------------------------------------------------------------------
# Case 6: issue konenki-website#12 — a multi-line sink (3, then 4) is not a page count:
# fail fast with the named "page count not numeric" reason, POST skipped,
# and the summary's build-site row stays ONE line. The raw sink must not
# reach the summary, else its second line breaks the table: the row after
# "  build site" must be the "  post gates" row, not a stray "4)".
# ---------------------------------------------------------------------------
if run_case $'3\n4'; then
  assert_shown "multi-line count" "page count not numeric" "the build step must fail with this named reason"
  assert_run_failed "multi-line count" "a multi-line count must fail fast"
  assert_post_skipped "multi-line count" "a malformed count"
  assert_row_one_line "multi-line count" "  build site " "  post gates" \
    "the build-site row must stay one line, with no raw newline from the sink"
fi

# ---------------------------------------------------------------------------
# Case 7: issue konenki-website#14 (finding 1 from the #11–#13 review) — a
# SITE_PAGE_COUNT_FILE exported in the calling shell must not move the
# count. FullBuildAndPush passes its own path to build_site.sh
# (SITE_PAGE_COUNT_FILE="$PAGE_COUNT_FILE" ./Scripts/build_site.sh), so the
# stub still writes where FullBuildAndPush reads, and the run stays green.
#
# PIN, not a red: this held when it was written. What proves it can fail:
# delete the SITE_PAGE_COUNT_FILE="$PAGE_COUNT_FILE" prefix on that line in
# FBP.sh, and the stub writes the decoy instead. FullBuildAndPush
# finds no count at its own path: the run fails with "page count missing"
# and this case fails on both checks below. (Cases 1, 3 to 6 and 8 to 12
# fail with it, because the stub has no default path and exits non-zero on
# an unset SITE_PAGE_COUNT_FILE; case 2 writes no sink and stays green.) The
# mutation proof right after this case makes exactly that deletion and
# requires the named reason, so the pin is seen failing on every run.
#
# Issue konenki-website#18 (#14 note b): the decoy must also stay UNWRITTEN. A
# FullBuildAndPush that followed the exported path for writing AND reading
# (PAGE_COUNT_FILE="${SITE_PAGE_COUNT_FILE:-...}") would show 3 pages and
# pass both checks above, so the decoy lies outside the sandbox, in a
# directory this fixture owns and still has after the sandbox is removed,
# and the case fails when anything wrote it. The directory comes from
# fbp_sandbox_new_dir, which registers it for the lib's cleanup. COVERAGE:
# this held when it was written, so it was never seen red here.
#
# When mktemp -d gives no directory, case 7 still makes its run_case call
# (the issue konenki-website#20 self-proof counts one per case) with a decoy relative to
# the sandbox, and fails once, naming mktemp, for the check it cannot make.
# ---------------------------------------------------------------------------
case7_decoy=""
if ! fbp_sandbox_new_dir; then
  fail "exported decoy path: mktemp -d gave no directory for the decoy, so case 7 cannot check that the decoy stays unwritten"
  export SITE_PAGE_COUNT_FILE=".build/decoy-page-count.log"
else
  case7_decoy="${FBP_SANDBOX_NEW_DIR}/decoy-page-count.log"
  export SITE_PAGE_COUNT_FILE="$case7_decoy"
fi
case7_ran=0
run_case 3 && case7_ran=1
unset SITE_PAGE_COUNT_FILE

if [ "$case7_ran" -eq 1 ]; then
  assert_shown "exported decoy path" "3 pages generated" \
    "a SITE_PAGE_COUNT_FILE exported in the calling shell moved the count away from where FullBuildAndPush reads it"
  assert_run_passed "exported decoy path" \
    "it must pass its own SITE_PAGE_COUNT_FILE to build_site.sh, whatever the calling shell exported"
  if [ -n "$case7_decoy" ] && [ -e "$case7_decoy" ]; then
    fail "exported decoy path: build_site.sh wrote the exported decoy ${case7_decoy} — FullBuildAndPush must hand it its own path, not follow the calling shell's path for writing and reading alike"
  fi
fi

# ---------------------------------------------------------------------------
# Mutation proof for case 7 (issue konenki-website#14): case 7 was written against a
# FullBuildAndPush it already passed, so on its own it was never seen red.
# This re-runs case 7's setup (exported decoy, sink 3) against a copy of
# FBP.sh with the SITE_PAGE_COUNT_FILE="$PAGE_COUNT_FILE"
# prefix removed, and requires that run to fail with the named "page count
# missing" reason. It also proves the stub honours SITE_PAGE_COUNT_FILE: a
# stub that wrote .build/site-page-count.log whatever the variable said
# would keep the mutant green, and this proof would fail.
#
# Three guards, all needed: the sed must change the copy (else it stopped
# matching and proves nothing), the copy must still run
# ./Scripts/build_site.sh (else it tests a missing build, not a missing
# pass-through), and the run must fail WITH the named reason (a non-zero
# exit for any other reason, such as the stub's own unset-variable abort,
# is not case 7 biting).
#
# The mutant is handed to Scripts/lib_fbp_sandbox.sh through
# FBP_SANDBOX_FBP_OVERRIDE, and the decoy through SITE_PAGE_COUNT_FILE, both
# as prefix assignments on the one run_case call: bash exports them for that
# call only and restores them when it returns. The mutant's directory comes
# from fbp_sandbox_new_dir, which registers it for the lib's cleanup.
# ---------------------------------------------------------------------------
if ! fbp_sandbox_new_dir; then
  fail "mutation proof (case 7): mktemp -d gave no directory, so the pass-through was never removed and case 7 was not seen failing"
else
  mutant="${FBP_SANDBOX_NEW_DIR}/FBP.sh"
  sed 's|SITE_PAGE_COUNT_FILE="[$]PAGE_COUNT_FILE" \(\./Scripts/build_site\.sh\)|\1|' "$FBP_SANDBOX_FBP" > "$mutant"
  chmod +x "$mutant"

  if cmp -s "$FBP_SANDBOX_FBP" "$mutant"; then
    fail "mutation proof (case 7): removing the SITE_PAGE_COUNT_FILE prefix changed nothing in ${FBP_SANDBOX_FBP} — the sed no longer matches, so this proof proves nothing"
  elif ! grep -Eq '^[[:space:]]+\./Scripts/build_site\.sh$' "$mutant"; then
    fail "mutation proof (case 7): the mutated FBP.sh no longer runs ./Scripts/build_site.sh at all — the proof must remove the pass-through, not the build"
  elif SITE_PAGE_COUNT_FILE=".build/decoy-page-count.log" FBP_SANDBOX_FBP_OVERRIDE="$mutant" run_case 3; then
    if [ "$RC" -eq 0 ]; then
      fail "mutation proof (case 7): a FBP.sh without the SITE_PAGE_COUNT_FILE pass-through exited 0 with an exported decoy — case 7 cannot fail, or the stub ignores SITE_PAGE_COUNT_FILE. Output: ${OUT}"
    elif ! grep -Fq "page count missing" <<< "$OUT"; then
      fail "mutation proof (case 7): a FBP.sh without the SITE_PAGE_COUNT_FILE pass-through failed, but not with the named 'page count missing' reason. Output: ${OUT}"
    elif grep -Fq "3 pages generated" <<< "$OUT"; then
      fail "mutation proof (case 7): the mutated run failed with 'page count missing' and still showed '3 pages generated'. Output: ${OUT}"
    else
      echo "  ok: a FBP.sh without the SITE_PAGE_COUNT_FILE pass-through fails case 7 with 'page count missing'"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Case 8: issue konenki-website#17 (item 1) — the PRE and POST gate counts go into the
# summary like the page count does. A multi-line .build/sfl-counts.log
# (written by the stub sfl.sh through the FBP_SANDBOX_SFL_COUNTS_PRE and
# FBP_SANDBOX_SFL_COUNTS_POST seams of Scripts/lib_fbp_sandbox.sh) must not
# break the table: the line after the pre-gates row is the build-site row,
# the line after the post-gates row is the git row, and each row shows its
# counts through printf %q. Sink 3 keeps the build green so POST runs.
# ---------------------------------------------------------------------------
gate_counts_case "multi-line gate counts" \
  $'pre gates 5 passed\npre second line' \
  $'post gates 4 passed\npost second line'

# ---------------------------------------------------------------------------
# Case 9: issue konenki-website#17 (item 1) — a control character in .build/sfl-counts.log
# (a carriage return and an escape sequence, which do not start a new line
# but do rewrite the terminal line) is shown escaped through printf %q in
# the pre-gates and post-gates rows, never printed raw.
# ---------------------------------------------------------------------------
gate_counts_case "control-character gate counts" \
  $'pre gates 5\r\033[31mred' \
  $'post gates 4\r\033[31mred'

# ---------------------------------------------------------------------------
# Case 10: issue konenki-website#17 (item 2) — a page-count sink of 3, a NUL byte and a
# newline is not a page count. $(cat ...) drops the NUL, so it would read
# as 3; it must fail fast with the named "page count not numeric" reason,
# never show "3 pages generated". The sink is written through the
# FBP_SANDBOX_SINK_PRINTF seam, because a shell value cannot hold a NUL.
# ---------------------------------------------------------------------------
if FBP_SANDBOX_SINK_PRINTF='3\000\n' run_case ""; then
  assert_shown "NUL in count" "page count not numeric" \
    "a sink of 3 and a NUL byte must fail the build step with this named reason"
  assert_not_shown "NUL in count" "3 pages generated" \
    "the NUL was dropped and the rest read as a valid count"
  assert_run_failed "NUL in count" "a sink holding a NUL byte is not a page count and must fail fast"
  assert_post_skipped "NUL in count" "a malformed count"
fi

# ---------------------------------------------------------------------------
# Case 11: issue konenki-website#17 (item 3) — a page-count sink that is there and not
# empty but cannot be read (the stub chmods it to 000 through the
# FBP_SANDBOX_SINK_MODE seam) fails the build step with the named
# "page count unreadable" reason in the build-site row. Before issue konenki-website#17
# the read ran under set -e and killed FullBuildAndPush part-way: the
# build-site row stayed at its skipped default (build site ⏭️), the run
# ended Aborted and POST never ran. Only the reason is asserted, not the
# path printed after it. Run as root, chmod 000 does not stop the read and
# this case fails; CI runs it on GitHub's macos-latest as a user.
# ---------------------------------------------------------------------------
if FBP_SANDBOX_SINK_MODE=000 run_case 3; then
  case11_row="$(summary_row "  build site ")"
  case "$case11_row" in
    *"❌ (page count unreadable"*) ;;
    *)
      fail "unreadable count: the build-site row is '${case11_row}', want the named '❌ (page count unreadable' reason. Output: ${OUT}"
      ;;
  esac

  assert_run_failed "unreadable count" "a page count that cannot be read must fail fast"
  assert_post_skipped "unreadable count" "an unreadable count"
fi

# ---------------------------------------------------------------------------
# Case 12: issue konenki-website#17 (item 4) — a sink that holds one newline and nothing
# else holds no count: it fails with the named "page count missing"
# reason, like case 2, not with "page count not numeric: ''" (what it
# printed before issue konenki-website#17). Written
# through the FBP_SANDBOX_SINK_PRINTF seam so the sink is exactly one byte.
# ---------------------------------------------------------------------------
if FBP_SANDBOX_SINK_PRINTF='\n' run_case ""; then
  assert_shown "newline-only count" "page count missing" \
    "a sink holding only a newline must fail the build step with this named reason"
  assert_not_shown "newline-only count" "page count not numeric" \
    "a sink holding only a newline holds no count, so the reason is 'page count missing'"
  assert_run_failed "newline-only count" "a sink with no count must fail fast"
  assert_post_skipped "newline-only count" "a missing count"
fi

# ---------------------------------------------------------------------------
# Self-proofs, issue konenki-website#20 step 3 (items 1 and 3 of the #14 review). Each one
# runs this fixture or a copy of it from inside ONE directory made here with
# the real mktemp and registered with the lib, so nothing they start runs in
# this repo.
#
# They cannot recurse. Proof (a) runs this file with a mktemp that always
# fails, so in that child the mktemp -d just below fails too and both proofs
# are skipped (its fail line names mktemp, which proof (a) allows). Proof (b)
# runs a copy that exits before it reaches this block.
# ---------------------------------------------------------------------------
if ! fbp_sandbox_new_dir; then
  fail "self-proofs: mktemp -d gave no directory for the proofs, so the caller and completion-guard proofs never ran"
else
  proof_dir="$FBP_SANDBOX_NEW_DIR"

  # -------------------------------------------------------------------------
  # Proof (a): callers check the run. When fbp_sandbox_run cannot create a
  # sandbox, run_case must fail this fixture with the sandbox's own reason
  # ("could not create the FBP sandbox"), once per run_case call, and no case
  # may go on to assert against the empty output and the -1 status that run
  # left: before issue konenki-website#20 step 2, every case failed with a downstream
  # message about a missing count row or exit status instead.
  #
  # Drives THIS file (not a copy) with the lib's failing mktemp
  # (fbp_sandbox_write_failing_mktemp) first on PATH, from an empty
  # directory under proof_dir. The lib then stops before its subshell
  # (issue konenki-website#20 step 2), and even a lib that did not would write its stubs into
  # that empty directory, never into this repo.
  #
  # Wanted: the run fails; exactly 12 FAIL lines carry the reason, one for
  # each run_case call of cases 1 to 12 (cases 8 and 9 make theirs through
  # gate_counts_case; the mutation proof never reaches its run_case: its
  # own mktemp -d fails first), so a new case that calls run_case raises the
  # 12 below; every other FAIL line names mktemp itself, so no downstream
  # assertion fired. The lib's own stderr line is not a FAIL line and does
  # not count.
  # -------------------------------------------------------------------------
  callers_dir="${proof_dir}/callers"
  mkdir -p "${callers_dir}/cwd"
  fbp_sandbox_write_failing_mktemp "${callers_dir}/no-mktemp"

  PATH="${callers_dir}/no-mktemp:$PATH" fbp_sandbox_record "$callers_dir" "${callers_dir}/cwd" \
    "$BASH" "${ROOT}/Scripts/test_fbp_build_pagecount.sh"
  callers_rc="$(fbp_sandbox_record_rc)"
  callers_out="$(fbp_sandbox_record_output)"
  callers_fails="$(grep -F '❌ FAIL:' <<< "$callers_out" || true)"
  callers_reasons="$(grep -cF 'could not create the FBP sandbox' <<< "$callers_fails" || true)"
  callers_downstream="$(grep -vF 'could not create the FBP sandbox' <<< "$callers_fails" | grep -vF 'mktemp -d gave no directory' || true)"

  case "$callers_rc" in
    missing)
      fail "callers check the run: the no-sandbox run of this fixture recorded no exit status, so nothing was tested"
      ;;
    0)
      fail "callers check the run: with no sandbox this fixture exited 0 — a run that never happened must fail it. Output: ${callers_out}"
      ;;
  esac

  if [ "$callers_reasons" != "12" ]; then
    fail "callers check the run: with no sandbox, ${callers_reasons:-0} FAIL line(s) carry 'could not create the FBP sandbox', want 12 — one per run_case call (cases 1 to 12). Output: ${callers_out}"
  fi

  if [ -n "$callers_downstream" ]; then
    fail "callers check the run: with no sandbox, the fixture failed with downstream assertion message(s) instead of the sandbox's reason: ${callers_downstream}"
  fi

  # -------------------------------------------------------------------------
  # Proof (b): the completion guard. A fixture that dies part-way must fail,
  # never report green: on macOS bash 3.2 a set -u abort inside a function
  # can exit 0. Runs a COPY of this file that dies with status 0 after case
  # 1, the way that abort does, written under proof_dir/abort by
  # fbp_sandbox_write_aborting_copy (Scripts/lib_fbp_sandbox.sh).
  #
  # Three guards: the insertion must change the copy (else the Case 2 anchor
  # stopped matching and this proves nothing), the copy must exit non-zero,
  # and it must say why, with the wording every guarded fixture here uses.
  # -------------------------------------------------------------------------
  abort_root="${proof_dir}/abort"
  if ! fbp_sandbox_write_aborting_copy "${ROOT}/Scripts/test_fbp_build_pagecount.sh" "$abort_root"; then
    fail "completion guard: inserting exit 0 before case 2 changed nothing — the '# Case 2:' anchor no longer matches, so this proof proves nothing"
  else
    fbp_sandbox_record "$abort_root" "$abort_root" \
      "$BASH" "${abort_root}/Scripts/test_fbp_build_pagecount.sh"
    abort_rc="$(fbp_sandbox_record_rc)"
    abort_out="$(fbp_sandbox_record_output)"

    case "$abort_rc" in
      missing)
        fail "completion guard: the copy that dies after case 1 recorded no exit status, so nothing was tested"
        ;;
      0)
        fail "completion guard: a copy of this fixture that dies after case 1 exited 0 — a fixture that never reaches its later cases must fail, not report green. Output: ${abort_out}"
        ;;
    esac

    grep -Fq "fixture aborted before completing all cases" <<< "$abort_out" \
      || fail "completion guard: the copy that dies after case 1 did not say 'fixture aborted before completing all cases'. Output: ${abort_out}"
  fi
fi

COMPLETED=1

if [ "$failed" -ne 0 ]; then
  echo ""
  echo "FAIL: FullBuildAndPush does not fail fast on a missing/malformed/zero build-site page count"
  exit 1
fi

echo "OK: FullBuildAndPush shows the page count and fails fast when it is missing, non-numeric or zero"
