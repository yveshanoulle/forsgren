#!/usr/bin/env bash
# Scripts/run_ci_phase.sh <pre|post> <rows-file> <details-dir>
#
# CI's gate loop (forsgren#1, ladder step 14). .github/workflows/quality.yml
# calls it twice, `pre` before Scripts/build_site.sh and `post` after it, the
# way FBP.sh calls `./sfl.sh pre` and `./sfl.sh post` around the same build.
#
# NEW: no repository of the estate has a phase-aware CI loop. konenki-website
# names every gate in its own workflow step (and Scripts/test_gate_wiring.sh
# there checks the two lists agree); agilelean-website and coachretreat-website
# loop over the order file in one workflow step, without phases. Here the
# loop reads Scripts/gate_report_order.txt with sfl.sh's own row rules, so
# sfl and CI run the same rows, in the same order, under the same labels, by
# construction rather than by two lists kept in step:
#   - `#` lines and blank lines are skipped;
#   - a row whose script is `n/a` is skipped (it declares a gate this repo
#     does not have, with the reason);
#   - a row runs only in the phase its third field names;
#   - a last line with no trailing newline is still read;
#   - a declared script that is not executable is a red row, named;
#   - a failing gate does NOT stop the phase: every row of the phase runs, so
#     one run reports every failure, as sfl does;
#   - a failure on a `secret-class` row makes the exit 2, as sfl's does.
# Scripts/test_gate_wiring.sh pins all of this, at runtime, against stub
# gates, and against the real order file.
#
# Extracted from the workflow rather than written inline in it: a loop in YAML
# is a loop nothing outside CI ever runs (estate rule after MenoPower's
# deploy-i18n.yml, 2026-06-11).
#
# THE ONE THING CI DOES THAT sfl DOES NOT: it is check-only, and it checks
# that it was. sfl may fix (npm_audit_check.sh heals with one `npm audit fix`,
# and the lockfile change rides into the commit); CI must report what the
# commit CONTAINS, not what it could be fixed into. So after each gate the
# runner compares `git status --porcelain` with what it was before that gate,
# and a gate that changed the checked-out tree is a red row, named, even when
# it exited 0. No gate list is kept for this: any gate that writes is caught.
#
# Per gate, the body of konenki-website/Scripts/report_ci_step.sh, which runs one
# workflow step (its issue #9): the output captured guarded, so it survives
# GitHub's `shell: bash` (`bash --noprofile --norc -e -o pipefail`), echoed to
# the log, one `<label>|<mark>` line appended to <rows-file>, and
# <details-dir>/<slug>.md written (slug: the label with every character
# outside A-Za-z0-9 turned into _). Scripts/render_quality_report.sh renders
# both into the step summary, in declared order.
#
# Each gate gets /dev/null as stdin: the loop reads the order file on stdin,
# and a gate that read its own stdin would swallow the rows after it.
#
# Exit: 0 all rows of the phase passed; 1 a row failed, or the phase has no
# row at all (a phase that ran nothing is not green); 2 a secret-class row
# failed; 64 bad usage.
#
# Testing seam: RUN_CI_PHASE_ROOT replaces the repository root, so
# Scripts/test_gate_wiring.sh can run the loop over a synthetic order file
# and stub gates.

set -uo pipefail

ROOT="${RUN_CI_PHASE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

ORDER="Scripts/gate_report_order.txt"

usage() {
  echo "usage: run_ci_phase.sh <pre|post> <rows-file> <details-dir>" >&2
  exit 64
}

[ "$#" -eq 3 ] || usage
PHASE="$1"
ROWS="$2"
DETAILS="$3"
case "$PHASE" in
  pre|post) ;;
  *) usage ;;
esac

if [ ! -f "$ORDER" ]; then
  echo "❌ FAIL: ${ORDER} is missing — every gate is declared there, so without it no gate runs" >&2
  exit 1
fi

mkdir -p "$DETAILS" || exit 1
touch "$ROWS" || exit 1

# record <label> <rc> <output>: the row and the details file for one gate.
record() {
  local label="$1" rc="$2" out="$3" mark slug
  if [ "$rc" -eq 0 ]; then mark="✅"; else mark="❌"; fi
  printf '%s|%s\n' "$label" "$mark" >> "$ROWS"
  slug="$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')"
  {
    echo ""
    echo "#### ${mark} ${label}"
    echo ""
    if [ -n "$out" ]; then
      echo '```'
      echo "$out"
      echo '```'
    else
      echo "_no output_"
    fi
  } > "${DETAILS}/${slug}.md"
}

if ! tree_before="$(git status --porcelain 2>&1)"; then
  echo "❌ FAIL: git status failed in ${ROOT} — without it a gate that changes the tree cannot be told apart from one that does not: ${tree_before}" >&2
  exit 1
fi

ran=0
failed=0
secret_failed=0
failed_labels=""

while IFS='|' read -r label script phase gate_class || [ -n "${label:-}" ]; do
  case "$label" in
    \#*|'') continue ;;
  esac
  [ "${script:-}" = "n/a" ] && continue
  [ "${phase:-}" = "$PHASE" ] || continue

  ran=$((ran + 1))
  echo "::group::${label}"

  if [ ! -x "${script:-}" ]; then
    out="❌ ${label} declares ${script:-nothing}, which is not an executable script"
    rc=1
  else
    out="$("./${script}" < /dev/null 2>&1)" && rc=0 || rc=$?

    if ! tree_after="$(git status --porcelain 2>&1)"; then
      out="${out}"$'\n'"❌ FAIL: git status failed after ${label}: ${tree_after}"
      rc=1
    elif [ "$tree_after" != "$tree_before" ]; then
      out="${out}"$'\n'"❌ FAIL: ${label} changed the checked-out tree — CI is check-only and reports what the commit contains, not what a gate could fix it into. Run ./FBP.sh locally and commit the result. git status --porcelain after it:"$'\n'"${tree_after}"
      [ "$rc" -ne 0 ] || rc=1
      tree_before="$tree_after"
    fi
  fi

  echo "$out"
  echo "::endgroup::"
  record "$label" "$rc" "$out"

  if [ "$rc" -ne 0 ]; then
    failed=$((failed + 1))
    failed_labels="${failed_labels}  ${label} ❌"$'\n'
    echo "::error title=${label}::${label} failed (exit ${rc}); its output is in the step summary"
    if [ "${gate_class:-}" = "secret-class" ]; then
      secret_failed=1
    fi
  fi
done < "$ORDER"

if [ "$ran" -eq 0 ]; then
  echo "❌ FAIL: ${ORDER} declares no ${PHASE} row — a CI phase that ran nothing is not green" >&2
  exit 1
fi

if [ "$failed" -ne 0 ]; then
  echo ""
  echo "Errors:"
  printf '%s' "$failed_labels"
  if [ "$secret_failed" -ne 0 ]; then
    echo "⛔ CI ${PHASE}: ${failed} of ${ran} gates failed, one of them SECRET-CLASS — exit 2"
    exit 2
  fi
  echo "❌ CI ${PHASE}: ${failed} of ${ran} gates failed"
  exit 1
fi

echo ""
echo "✅ CI ${PHASE}: all ${ran} gates passed"
