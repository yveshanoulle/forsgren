#!/usr/bin/env bash
# Scripts/test_merge_quality_report.sh
#
# Self-test for Scripts/merge_quality_report.sh (forsgren#259, step 2), forsgren's
# own. Quality runs its gates in parallel jobs; each job hands over a rows
# file and a details directory, and the report job merges them into the one
# rows file and details directory the renderers read, so there is one Quality
# report. Cases:
#   1. two jobs' rows and details are merged, nothing lost
#   2. a gate reported by two jobs is red, named (a gate runs in one job only)
#   3. a job that handed nothing over is named, and the merge still succeeds
#      with the others (its gates then show as unmeasured in the report)
#   4. status: all success is success; a failure or a skipped job is failure;
#      a cancelled job is cancelled, whatever else happened; no result is a
#      usage error
#   4b (forsgren#561). verdict: the report job fails after rendering when a
#      gate job is not success: failure, cancelled or skipped (no gate job is
#      skipped by design) exits 1 with a ❌ line naming the job; all success
#      exits 0 with no ❌ line
#   5. usage errors exit 64
#   3b-3e (forsgren#426). the shard rows of one gate (`<gate> (shard N/M)`) are
#      joined into the gate's one row: green only when every shard is green,
#      red naming the shard that failed or reported no row
#   (also: what a job hands over, full and empty, and merged back)
# Each is proved against a mutant of the script that breaks it.

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "merge quality report self-test"

SCRIPT="Scripts/merge_quality_report.sh"
[[ -x "$SCRIPT" ]] || selftest_abort "${SCRIPT} does not exist or is not executable: the jobs' reports cannot be merged into one"

# hand_over <dir> <job> <rows...>: what one job hands over, <job>/rows.md and
# <job>/details/<slug>.md, one details file per row.
hand_over() {
  local dir="$1" job="$2" row slug
  shift 2
  mkdir -p "${dir}/${job}/details"
  : > "${dir}/${job}/rows.md"
  for row in "$@"; do
    printf '%s\n' "$row" >> "${dir}/${job}/rows.md"
    slug="$(printf '%s' "${row%%|*}" | tr -c 'A-Za-z0-9' '_')"
    printf '#### %s\nout of %s\n' "$row" "$job" > "${dir}/${job}/details/${slug}.md"
  done
}

# want_out <case> <text>: the last capture printed exactly <text>.
want_out() {
  if [[ "$OUT" == "$2" ]]; then
    echo "  ok: $1"
  else
    fail "$1: printed '${OUT}', want exactly ${2}"
  fi
}

# --- 1. two jobs merge
A="${TMP}/one"
hand_over "$A" quality-report-main "gate a|✅" "gate b|❌"
hand_over "$A" quality-report-isolation "isolation one|✅" "isolation two|✅"
capture "$SCRIPT" merge "$A" "${TMP}/one.rows" "${TMP}/one.details"
want_green "two jobs are merged" "4 gates from 2 jobs"
if [[ "$(LC_ALL=C sort "${TMP}/one.rows" | tr '\n' ' ')" == "gate a|✅ gate b|❌ isolation one|✅ isolation two|✅ " ]] \
  && [[ -f "${TMP}/one.details/isolation_two.md" && -f "${TMP}/one.details/gate_b.md" ]]; then
  echo "  ok: the merged rows hold every job's rows and the details directory every details file"
else
  fail "the merged rows or details are wrong: $(cat "${TMP}/one.rows" 2> /dev/null) / $(find "${TMP}/one.details" -type f 2> /dev/null | tr '\n' ' ')"
fi

# --- 1b. what a job hands over, then merged back
H="${TMP}/handover-src"
mkdir -p "${H}/details"
printf 'gate a|✅\n' > "${H}/rows.md"
printf '#### gate a\n' > "${H}/details/gate_a.md"
printf '12\n' > "${H}/count.log"
capture "$SCRIPT" handover "${H}/rows.md" "${H}/details" "${TMP}/out-full" "${H}/count.log"
want_green "a job hands over its rows, details and page count" "handed over 1 rows"
if [[ -f "${TMP}/out-full/details/gate_a.md" && -f "${TMP}/out-full/page-count.log" && "$(cat "${TMP}/out-full/rows.md")" == "gate a|✅" ]]; then
  echo "  ok: the hand-over holds rows.md, details/ and page-count.log"
else
  fail "the hand-over is incomplete: $(find "${TMP}/out-full" -type f | sort | tr '\n' ' ')"
fi
capture "$SCRIPT" handover "${TMP}/no-rows" "${TMP}/no-details" "${TMP}/out-empty"
want_green "a job that stopped before its gates still hands over" "handed over 0 rows"
if [[ -f "${TMP}/out-empty/rows.md" && ! -s "${TMP}/out-empty/rows.md" && -d "${TMP}/out-empty/details" ]]; then
  echo "  ok: an empty hand-over is an empty rows.md, so the upload is never empty"
else
  fail "the empty hand-over is wrong: $(find "${TMP}/out-empty" | sort | tr '\n' ' ')"
fi
mkdir -p "${TMP}/round/quality-report-quality" "${TMP}/round/quality-report-isolation"
cp -R "${TMP}/out-full/." "${TMP}/round/quality-report-quality/"
cp -R "${TMP}/out-empty/." "${TMP}/round/quality-report-isolation/"
capture "$SCRIPT" merge "${TMP}/round" "${TMP}/round.rows" "${TMP}/round.details"
want_green "a full and an empty hand-over merge" "merged 1 gates from 2 jobs"
want_said "the empty one is named" "quality-report-isolation handed over no rows"
capture "$SCRIPT" handover "${H}/rows.md"
want_rc "handover without its outputs is a usage error" 64

# --- 2. a gate reported by two jobs
B="${TMP}/two"
hand_over "$B" quality-report-main "gate a|✅" "same gate|✅"
hand_over "$B" quality-report-isolation "same gate|✅"
capture "$SCRIPT" merge "$B" "${TMP}/two.rows" "${TMP}/two.details"
want_red "a gate reported by two jobs is red" "same gate"
want_said "and names both jobs" "quality-report-isolation"

# --- 3. a job that handed nothing over
C="${TMP}/three"
hand_over "$C" quality-report-main "gate a|✅"
mkdir -p "${C}/quality-report-isolation"
capture "$SCRIPT" merge "$C" "${TMP}/three.rows" "${TMP}/three.details"
want_green "a job with no rows still merges the others" "1 gates from 2 jobs"
want_said "the job that handed nothing over is named" "quality-report-isolation handed over no rows"

# --- 3b. shards (forsgren#426): the jobs that run one gate in shards each hand
# over a row named for their shard, `<gate> (shard N/M)`, and the merge joins
# them into the one row of the gate, under the gate's own label, which is what
# the order file declares and the renderers look up.
D="${TMP}/shards"
hand_over "$D" quality-report-main "gate a|✅" "gate z|✅"
hand_over "$D" quality-report-part_1 "split gate (shard 1/2)|✅"
hand_over "$D" quality-report-part_2 "split gate (shard 2/2)|✅"
capture "$SCRIPT" merge "$D" "${TMP}/d.rows" "${TMP}/d.details"
want_green "3b: two green shards merge" "merged 3 gates from 3 jobs"
if [[ "$(tr '\n' ' ' < "${TMP}/d.rows")" == "gate a|✅ gate z|✅ split gate|✅ " ]]; then
  echo "  ok: 3b: the two shard rows are one row under the gate's own label"
else
  fail "3b: the merged rows are $(tr '\n' ' ' < "${TMP}/d.rows")"
fi
if grep -qF 'out of quality-report-part_1' "${TMP}/d.details/split_gate.md" 2> /dev/null \
  && grep -qF 'out of quality-report-part_2' "${TMP}/d.details/split_gate.md" 2> /dev/null; then
  echo "  ok: 3b: the gate's details hold the output of both shards"
else
  fail "3b: the gate's details do not hold both shards: $(cat "${TMP}/d.details/split_gate.md" 2> /dev/null)"
fi

E="${TMP}/shards-red"
hand_over "$E" quality-report-part_1 "split gate (shard 1/2)|✅"
hand_over "$E" quality-report-part_2 "split gate (shard 2/2)|❌"
capture "$SCRIPT" merge "$E" "${TMP}/e.rows" "${TMP}/e.details"
want_green "3c: a red shard still merges" "merged 1 gates from 2 jobs"
want_said "3c: the output names the red shard" "split gate: shard 2/2 failed"
if [[ "$(cat "${TMP}/e.rows")" == "split gate|❌" ]]; then
  echo "  ok: 3c: one red shard makes the gate's row red"
else
  fail "3c: the merged row is $(cat "${TMP}/e.rows")"
fi
if grep -qF '#### split gate (shard 2/2)|❌' "${TMP}/e.details/split_gate.md" 2> /dev/null; then
  echo "  ok: 3c: the gate's details hold the red shard's output"
else
  fail "3c: the details lack the red shard: $(cat "${TMP}/e.details/split_gate.md" 2> /dev/null)"
fi

# A shard that handed over nothing must not leave the gate green.
F="${TMP}/shards-missing"
hand_over "$F" quality-report-part_1 "split gate (shard 1/2)|✅"
mkdir -p "${F}/quality-report-part_2"
capture "$SCRIPT" merge "$F" "${TMP}/f.rows" "${TMP}/f.details"
want_said "3d: the missing shard is named" "split gate: shard 2/2 reported no row"
if [[ "$(cat "${TMP}/f.rows")" == "split gate|❌" ]]; then
  echo "  ok: 3d: a shard that reported nothing makes the gate's row red, never green"
else
  fail "3d: the merged row is $(cat "${TMP}/f.rows")"
fi

# The same shard reported by two jobs is the duplicate of case 2.
G="${TMP}/shards-twice"
hand_over "$G" quality-report-part_1 "split gate (shard 1/2)|✅"
hand_over "$G" quality-report-part_2 "split gate (shard 1/2)|✅"
capture "$SCRIPT" merge "$G" "${TMP}/g.rows" "${TMP}/g.details"
want_red "3e: a shard reported by two jobs is red" "split gate (shard 1/2)"

# --- 4. status
capture "$SCRIPT" status success success
want_green "all success is success" "success"
[[ "$OUT" == "success" ]] || fail "status of two successes printed '${OUT}', want exactly success"
capture "$SCRIPT" status success failure
want_out "a failed job makes the run failure" failure
capture "$SCRIPT" status success skipped
want_out "a skipped job makes the run failure" failure
capture "$SCRIPT" status failure cancelled
want_out "a cancelled job makes the run cancelled" cancelled
capture "$SCRIPT" status ""
want_rc "an empty result is a usage error" 64

# --- 4b. verdict (forsgren#561)
capture "$SCRIPT" verdict quality=success browser=success workflows=success
want_green "4b: every gate job success passes the verdict" ""
if grep -qF '❌' <<< "$OUT"; then fail "4b: an all-success verdict printed a ❌ line: ${OUT}"; else echo "  ok: 4b: an all-success verdict prints no ❌ line"; fi
for bad in failure cancelled skipped; do
  capture "$SCRIPT" verdict quality=success browser="$bad" workflows=success
  want_red "4b: a ${bad} gate job fails the verdict" "❌ browser: ${bad}"
  if grep -qF '❌ quality' <<< "$OUT" || grep -qF '❌ workflows' <<< "$OUT"; then fail "4b: the ${bad} verdict named a job that succeeded: ${OUT}"; fi
done
capture "$SCRIPT" verdict
want_rc "4b: verdict without a job is a usage error" 64
capture "$SCRIPT" verdict quality
want_rc "4b: a verdict argument without = is a usage error" 64

# --- 5. usage
capture "$SCRIPT"
want_rc "no command is a usage error" 64
capture "$SCRIPT" merge "$A"
want_rc "merge without its outputs is a usage error" 64
capture "$SCRIPT" status
want_rc "status without a result is a usage error" 64

# --- mutation proofs
run_mutant() {
  local name="$1" expr="$2"
  selftest_mutant "$SCRIPT" "${TMP}/mut/${name}/merge_quality_report.sh" "$expr" || return 1
  MUT="${TMP}/mut/${name}/merge_quality_report.sh"
}

if run_mutant dup 's/^ *duplicates=1$/duplicates=0/'; then
  capture "$MUT" merge "$B" "${TMP}/m1.rows" "${TMP}/m1.details"
  if [[ "$RC" -eq 0 ]]; then echo "  ok: mutation proof: a merge that never finds a duplicate is green on case 2, so case 2 catches it"; else fail "mutation proof: the no-duplicate-check mutant was still red on case 2"; fi
fi
if run_mutant cancel 's/^ *cancelled) any_cancelled=1 ;;$/cancelled) any_failed=1 ;;/'; then
  capture "$MUT" status failure cancelled
  if [[ "$OUT" != "cancelled" ]]; then echo "  ok: mutation proof: a status that lets failure outrank cancelled is caught"; else fail "mutation proof: the cancel mutant still printed cancelled"; fi
fi
if run_mutant verdictpass 's/^      \*) printf .*failed=1 ;;$/      *) ;;/'; then
  capture "$MUT" verdict browser=failure
  if [[ "$RC" -eq 0 ]]; then echo "  ok: mutation proof: a verdict that forgives a failed job is green on 4b, so 4b catches it"; else fail "mutation proof: the forgiving verdict mutant was still red"; fi
fi

# Shards (forsgren#426): a merge that never joins leaves the shard rows apart,
# and one that forgives a red or missing shard leaves the gate green.
if run_mutant nojoin 's/^  join_shards "[$]rows_out" "[$]details_out"$/  :/'; then
  capture "$MUT" merge "$D" "${TMP}/m3.rows" "${TMP}/m3.details"
  if ! grep -qxF 'split gate|✅' "${TMP}/m3.rows"; then echo "  ok: mutation proof: a merge that never joins the shards is caught by case 3b"; else fail "mutation proof: the no-join mutant still joined the shards"; fi
fi
if run_mutant forgive 's/^    \[ "[$]state" = "ok" \] [|][|] mark="❌"$/    :/'; then
  capture "$MUT" merge "$F" "${TMP}/m4.rows" "${TMP}/m4.details"
  if grep -qxF 'split gate|✅' "${TMP}/m4.rows"; then echo "  ok: mutation proof: a merge that forgives a missing shard leaves the gate green, so cases 3c and 3d catch it"; else fail "mutation proof: the forgiving mutant still made the gate red"; fi
fi

selftest_end "the quality report merge does not hold" "merge_quality_report.sh merges the jobs' rows and details, refuses a gate reported twice and judges the run's status (each proved against a mutant)"
