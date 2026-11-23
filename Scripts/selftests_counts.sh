#!/usr/bin/env bash
# Scripts/selftests_counts.sh
#
# How many self-tests a run of .github/workflows/selftests.yml ran, and how
# many a full run runs. It decides nothing itself: it reads the files the
# Self-tests report job already holds.
#
#   Scripts/selftests_counts.sh <rows-file> <labels-file>
#
#   rows-file    the merged rows of the run (`<label>|<mark>` per line, as
#                Scripts/run_ci_phase.sh writes them and
#                Scripts/merge_quality_report.sh merges them; shards joined).
#                May be missing or empty (a run that stopped early, or the
#                start of a run): tests is then 0.
#   labels-file  the self-test rows a full run executes, one label per line:
#                the output of Scripts/selftest_rows.sh.
#
# Prints two lines:
#   tests=<N>    the distinct labels of labels-file that have a row with the
#                mark ✅ or ❌ in rows-file (a self-test that ran, passed or
#                failed; a row of another label, or with another mark, is not
#                counted, so tests is never more than total)
#   total=<M>    the labels of labels-file
# A value that cannot be read is XX, never a guess: an unreadable or empty
# labels-file makes both XX; an unreadable rows-file (it exists but cannot be
# read) makes tests XX. Exit 0 in every such case (the caller reports XX);
# 64 usage. Self-test: Scripts/test_report_dispatch.sh.

set -uo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: selftests_counts.sh <rows-file> <labels-file>" >&2
  exit 64
fi
ROWS="$1"
LABELS="$2"

total="XX"
if [[ -r "$LABELS" ]]; then
  n="$(grep -v '^[[:space:]]*$' "$LABELS" | LC_ALL=C sort -u | grep -c .)" || n=0
  [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]] && total="$n"
fi

tests="XX"
if [[ "$total" != "XX" ]]; then
  if [[ ! -e "$ROWS" ]]; then
    tests=0
  elif [[ -r "$ROWS" ]]; then
    tests="$(LC_ALL=C awk -F'|' '
      FILENAME == ARGV[1] { if ($0 != "") want[$0] = 1; next }
      ($1 in want) && ($2 == "✅" || $2 == "❌") && !($1 in seen) { seen[$1] = 1; n++ }
      END { print n + 0 }
    ' "$LABELS" "$ROWS")" || tests="XX"
    [[ "$tests" =~ ^[0-9]+$ ]] || tests="XX"
  fi
fi

echo "tests=${tests}"
echo "total=${total}"
