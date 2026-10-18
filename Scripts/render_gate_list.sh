#!/usr/bin/env bash
# Scripts/render_gate_list.sh [order-file]
#
# forsgren#219: the "What we check" list of CONTRIBUTING.md, generated from
# Scripts/gate_report_order.txt so a contributor can read what every run
# checks before running anything. One bullet per gate that has a script, in
# the declared order, `<label>` and its script, with the phase it runs in:
#   - secret scan (`Scripts/check_secrets.sh`, pre)
# `#` lines, blank lines and `n/a` rows (gates this repository does not have)
# are left out. Writes markdown to stdout. CONTRIBUTING.md holds the output
# between its two gate-list markers; Scripts/test_render_quality_report.sh
# fails when the two differ, and the text to paste is this script's output.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

ORDER="${1:-Scripts/gate_report_order.txt}"
[ -f "$ORDER" ] || { echo "❌ FAIL: ${ORDER} is missing" >&2; exit 1; }

bt=$(printf '\140')

grep -v '^#' "$ORDER" | while IFS='|' read -r label script phase _; do
  [ -n "$label" ] || continue
  [ "${script:-}" = "n/a" ] && continue
  printf -- '- %s (%s%s%s, %s)\n' "$label" "$bt" "$script" "$bt" "$phase"
done
