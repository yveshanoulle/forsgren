#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# Renders the Quality run report — unit 406, ported from coachretreat-website
# (its unit 401).
#
# Ported from another estate repository 2026-10-01 (forsgren#1, ladder step 14); "HERE"
# below means konenki. forsgren's changes:
#   1. An `n/a` row (`<label>|n/a|<reason>`) is not counted in the total: it
#      declares a gate this repo does not have, so it can never report, and
#      counting it made every run "unmeasured" (coachretreat-website, with two
#      n/a rows, reads "N of N+2" on a run where every gate ran). It is shown
#      in the table as `n/a`, so the reader still sees the declaration.
#   2. The unmeasured note names what skips gates here: Scripts/run_ci_phase.sh
#      runs every row of a phase even after a failure, so only a failed
#      build, a secret-class finding or a job that stopped early leaves gates
#      unrun.
# Pinned by Scripts/test_render_quality_report.sh, case 6.
#
# WHY IT LEFT THE WORKFLOW. In coachretreat this block exited 1 on every run for
# a day and no local check could see it, because nothing outside the workflow
# ever executed it; sfl was green throughout. HERE the defect was quieter:
# `cat "$ROWS"` and `cat "$DETAILS"` are both append-ordered, so the table and
# the body rendered in RUN order while gate_report_order.txt exists precisely to
# fix that — the index and the thing it indexes disagreeing, which is worse than
# either being wrong alone. Same cure: a renderer that lives in YAML is a
# renderer nobody tests.
#
# Usage:
#   ./Scripts/render_quality_report.sh <rows-file> <details-dir> [order-file]
#
# Writes markdown to stdout. The caller redirects it into $GITHUB_STEP_SUMMARY.
#
# `set -uo pipefail` and NOT -e, deliberately, matching the step it replaces: a
# report must render whatever it has, including a half-finished run. That makes
# the EXIT STATUS load-bearing in a way that is easy to get wrong — see the
# trailing-row case in Scripts/test_render_quality_report.sh.

ROWS="${1:?usage: render_quality_report.sh <rows-file> <details-dir> [order-file]}"
DETAILS="${2:?usage: render_quality_report.sh <rows-file> <details-dir> [order-file]}"
ORDER="${3:-Scripts/gate_report_order.txt}"

total="$(grep -v '^#' "$ORDER" | grep '|' | grep -vc '^[^|]*|n/a|')"
ran=0
[ -f "${ROWS:-}" ] && ran="$(grep -c '|' "$ROWS" || true)"

echo "## Quality"
echo ""
if [ "$ran" -eq 0 ]; then
  echo "**No gate reported.** The job stopped before any gate ran —"
  echo "check the setup steps, not the gates."
else
  echo "| Gate | Result |"
  echo "|---|:-:|"
  # Declared order, not run order: the site reports must list the same gates
  # in the same places to be read side by side.
  grep -v '^#' "$ORDER" | while IFS='|' read -r label script _; do
    [ -n "$label" ] || continue
    if [ "${script:-}" = "n/a" ]; then echo "| ${label} | n/a |"; continue; fi
    mark="$(awk -F'|' -v l="$label" '$1 == l { print $2 }' "$ROWS")"
    if [ -n "$mark" ]; then echo "| ${label} | ${mark} |"; fi
  done
  echo ""
  echo "_${ran} of ${total} gates reported._"
  if [ "$ran" -lt "$total" ]; then
    echo ""
    echo "> A failed build or a secret-class finding skips the POST gates, and a"
    echo "> job that stopped early skips everything after it. The gates that did"
    echo "> not report are not passing — they are unmeasured."
  fi
  echo ""
  # Detail in the SAME declared order as the table above.
  grep -v '^#' "$ORDER" | while IFS='|' read -r label _; do
    [ -n "$label" ] || continue
    slug="$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')"
    # `if`, not `[ -f … ] && cat`. THIS LINE IS THE WHOLE UNIT. As the last
    # command of the last loop of the last group, its status became the step's:
    # a declared row with no details file — an `n/a` gate, or any gate the run
    # never reached — returned 1, and the report failed while every gate
    # passed. `if … fi` returns 0 when the condition is false.
    if [ -f "${DETAILS}/${slug}.md" ]; then cat "${DETAILS}/${slug}.md"; fi
  done
fi
