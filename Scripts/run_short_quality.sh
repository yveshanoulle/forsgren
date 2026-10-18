#!/usr/bin/env bash
# Scripts/run_short_quality.sh <rows-file> <details-dir>
#
# The PRE gates of the short Quality a release runs on its bump commit
# (forsgren#230, step 2): quality.yml dispatched with scope=bump runs
# Scripts/release_bump_diff.sh, then this, then the site build. forsgren's own;
# the estate's canon runner, Scripts/run_ci_phase.sh, is left as it is and runs
# every row of a phase.
#
# It runs the order-file rows (Scripts/gate_report_order.txt) whose script is
# listed in Scripts/quality_bump_gates.txt, the one list of the short gates,
# in the order file's order, and records them as run_ci_phase.sh does: one
# `<label>|<mark>` line in <rows-file>, a <details-dir>/<slug>.md per gate,
# so Scripts/render_quality_report.sh and render_quality_summary.sh show them
# and name every other gate as skipped. A failing gate does not stop the rest;
# a gate that changes the checked-out tree is red even with exit 0 (CI is
# check-only).
#
# Nothing is skipped silently: before the first gate it prints (and appends to
# $GITHUB_STEP_SUMMARY when that is set) `short Quality for a release bump: N
# gates`, the gates that run, and every gate of the order file that does not.
# A listed script that is no PRE row of the order file, a missing or empty
# list, a missing script: a red, nothing runs on a bad list.
#
# Exit: 0 all passed, 1 a gate failed or the list is bad, 2 a secret-class
# gate failed, 64 usage. Testing seam: RUN_SHORT_QUALITY_ROOT replaces the
# repository root. Self-test: Scripts/test_run_short_quality.sh.

set -uo pipefail

ROOT="${RUN_SHORT_QUALITY_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

ORDER="Scripts/gate_report_order.txt"
LIST="Scripts/quality_bump_gates.txt"

if [ "$#" -ne 2 ]; then
  echo "usage: run_short_quality.sh <rows-file> <details-dir>" >&2
  exit 64
fi
ROWS="$1"
DETAILS="$2"

bad_list() {
  echo "❌ FAIL: short quality: $*" >&2
  exit 1
}

[ -f "$ORDER" ] || bad_list "${ORDER} is missing, so no gate is declared"
[ -f "$LIST" ] || bad_list "${LIST} is missing, so the short gates are not named"

# The list: one script per line, comments and blanks skipped.
listed=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '#'* | '') continue ;; esac
  listed="${listed}${line}"$'\n'
done < "$LIST"
if [ -z "$listed" ]; then
  bad_list "${LIST} lists no gate, a short Quality that runs nothing is not green"
fi

# Every listed script must be a PRE row of the order file.
while IFS= read -r script; do
  [ -n "$script" ] || continue
  if ! awk -F'|' -v s="$script" '$1 !~ /^#/ && $2 == s && $3 == "pre" { found = 1 } END { exit !found }' "$ORDER"; then
    bad_list "${script} is no PRE row of ${ORDER}, but ${LIST} lists it"
  fi
done <<< "$listed"

# The gates that run and the gates that do not, by the order file's labels.
run_labels=""
run_count=0
skip_labels=""
skip_count=0
while IFS='|' read -r label script phase _ || [ -n "${label:-}" ]; do
  case "$label" in '#'* | '') continue ;; esac
  [ "${script:-}" = "n/a" ] && continue
  if grep -qxF -- "${script:-}" <<< "$listed" && [ "${phase:-}" = "pre" ]; then
    run_labels="${run_labels}${run_labels:+, }${label}"
    run_count=$((run_count + 1))
  else
    skip_labels="${skip_labels}${skip_labels:+, }${label}"
    skip_count=$((skip_count + 1))
  fi
done < "$ORDER"

note() {
  echo "**short Quality for a release bump: $((run_count + 2)) gates**"
  echo ""
  echo "Run: the bump diff check, ${run_labels}, the site build."
  echo ""
  echo "Not run (${skip_count} gates of the order file): ${skip_labels}."
}
note
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { note; echo ""; } >> "$GITHUB_STEP_SUMMARY"
fi

mkdir -p "$DETAILS" || exit 1
touch "$ROWS" || exit 1

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
  echo "❌ FAIL: git status failed in ${ROOT}: ${tree_before}" >&2
  exit 1
fi

failed=0
secret_failed=0
while IFS='|' read -r label script phase gate_class || [ -n "${label:-}" ]; do
  case "$label" in '#'* | '') continue ;; esac
  [ "${script:-}" = "n/a" ] && continue
  [ "${phase:-}" = "pre" ] || continue
  grep -qxF -- "$script" <<< "$listed" || continue

  echo "::group::${label}"
  if [ ! -e "$script" ]; then
    out="❌ ${label} declares ${script}, which does not exist"
    rc=1
  elif [ ! -x "$script" ]; then
    out="❌ ${label} declares ${script}, which is not an executable script"
    rc=1
  else
    out="$("./${script}" < /dev/null 2>&1)" && rc=0 || rc=$?
    if ! tree_after="$(git status --porcelain 2>&1)"; then
      out="${out}"$'\n'"❌ FAIL: git status failed after ${label}: ${tree_after}"
      rc=1
    elif [ "$tree_after" != "$tree_before" ]; then
      out="${out}"$'\n'"❌ FAIL: ${label} changed the checked-out tree: CI is check-only and reports what the commit contains. git status --porcelain after it:"$'\n'"${tree_after}"
      [ "$rc" -ne 0 ] || rc=1
      tree_before="$tree_after"
    fi
  fi
  echo "$out"
  echo "::endgroup::"
  record "$label" "$rc" "$out"
  if [ "$rc" -ne 0 ]; then
    failed=$((failed + 1))
    echo "::error title=${label}::${label} failed (exit ${rc}); its output is in the step summary"
    if [ "${gate_class:-}" = "secret-class" ]; then secret_failed=1; fi
  fi
done < "$ORDER"

if [ "$secret_failed" -ne 0 ]; then
  echo "⛔ short Quality: ${failed} of ${run_count} gates failed, one of them SECRET-CLASS, exit 2"
  exit 2
fi
if [ "$failed" -ne 0 ]; then
  echo "❌ short Quality: ${failed} of ${run_count} gates failed"
  exit 1
fi
echo "✅ short Quality: all ${run_count} gates passed"
