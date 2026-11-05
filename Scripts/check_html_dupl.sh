#!/usr/bin/env bash
# canon: check_html_dupl v8
# Scripts/check_html_dupl.sh

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# HTML duplication RATCHET — unit 397, adapted from the admin check of the
# estate's application repository.
#
# The canon version, byte-identical across the estate's repositories
# What differs per repository is DATA, in
# Scripts/site_settings.txt, read through Scripts/lib_site_settings.sh:
#   html_dupl_target   the directory measured when no argument is given
#   the ceiling        in percent, when no second argument is given, in one
#                      of two forms (see 5. below):
#     html_dupl_ceiling               one ceiling, whatever jscpd runs
#     html_dupl_ceiling_jscpd<major>  one ceiling per jscpd major
# A missing or invalid settings file is exit 2, never a guessed default. A
# repository that measures more than one target (a generated page as well as
# its authored source) does it with a thin wrapper of its own that calls this
# script with an explicit target and ceiling: the arguments override the
# settings, so the canon stays identical and the second target is a documented
# difference outside it, not a fork of it.
#
#   1. jscpd is a pinned devDependency (exact version in package.json and
#      package-lock.json), invoked by path from node_modules/.bin, never
#      `npx --yes`: a different version is a different number, and a ratchet
#      cannot float. A missing binary is exit 2 with no fallback.
#   2. ZERO FILES SCANNED IS RED (exit 2), with that reason. jscpd 4.2.4 over a
#      directory with no .html writes no report at all, and jscpd 5.x writes
#      one with 0 sources; either reads as "nothing scanned", never as clean.
#      The count comes from jscpd's own JSON report
#      (statistics.total.sources), what jscpd OPENED, not a separate find.
#   3. THE PIN STAYS CHECKED. package.json's devDependencies must name a jscpd
#      version, read at run time: no readable pin (no package.json, one that
#      is no JSON, or no jscpd in it) is exit 2. The pin is what SHOULD run;
#      whether the installed jscpd matches it is the npm dependency policy's
#      check (npm ci, the lockfile sync gate), so a jscpd that differs from
#      the pin never fails this gate by itself.
#   4. THE LABEL NAMES THE JSCPD THAT RAN (v7). Every OK and red line names
#      the version `jscpd --version` answers (4.2.4 answers `4.2.4`, 5.4.2
#      answers `jscpd 5.4.2`), as jscpd@<version>. A failing --version, or an
#      answer that is no x.y.z version, is the label `jscpd@unknown`, never
#      the pin, and the gate still measures. Measurement output says what ran;
#      the pin says what should run; neither stands in for the other.
#   5. THE CEILING FORM IS THE SETTINGS LIB'S. When the repository's
#      Scripts/lib_site_settings.sh declares the key family
#      html_dupl_ceiling_jscpd in SITE_SETTINGS_FAMILIES (lib v3 and later),
#      the ceiling is the running major's html_dupl_ceiling_jscpd<major> line:
#      the same files can measure 8.37% with jscpd 4.2.4 and 15.94% with
#      5.4.2, so a ceiling is only meaningful for the major it was measured
#      with, and main can carry the next major's ceiling ahead of a Dependabot
#      bump. In that form an unreadable version, or a running major with no
#      line, is exit 2: never another major's ceiling. Otherwise (lib v2, no
#      family) the ceiling is html_dupl_ceiling, whatever jscpd runs. A
#      ceiling argument overrides both, and then no version is needed.
#   Self-test: Scripts/test_check_html_dupl.sh.
#
# The bar is a CEILING at the measured value, and the direction is DOWN. The
# gate fails if duplication RISES. Lower the ceiling in site_settings.txt
# deliberately whenever the number improves; never raise it to make a red go
# away.
#
# TOOL VERSION IS PINNED, AND THAT IS LOAD-BEARING. A ratchet compares a
# measurement to a recorded constant, so the measurement must not depend on
# what happens to be installed: the same files measured 8.67% with jscpd 4.2.4
# and 7.84% with 5.0.15. That is why the label names the jscpd that ran: a
# number read without its version cannot be compared with a ceiling.
#
# jscpd MEASURES; this script GATES. Everything it reads comes from jscpd's
# JSON report (the json reporter, written to a temp folder): the files
# scanned (statistics.total.sources), the percentage
# (statistics.total.percentage, shown with two decimals) and the clones
# (duplicates[]). jscpd's console wording is never parsed, so a jscpd whose
# console text changes (5.x prints "(50.0%) over threshold (0.0%)" where 4.2.4
# printed "(50%) over threshold (0%)", and 5.x ignores NO_COLOR) gates the
# same. jscpd runs without a threshold, so it exits 0 whatever it finds and the
# ceiling comparison is this script's own; its console output is shown only
# when it fails.
#
# A jscpd failure (any exit but 0) is shown as jscpd printed it, exit 2.
# Exit: 0 at or under the ceiling, 1 over it, 2 tooling or nothing scanned.
# Usage: check_html_dupl.sh [target-dir] [max-pct]  (defaults: site_settings.txt)

export NO_COLOR=1
export FORCE_COLOR=0

TARGET_DIR="${1:-}"
MAX_PCT="${2:-}"
SETTINGS="Scripts/site_settings.txt"
if [ -z "$TARGET_DIR" ] || [ -z "$MAX_PCT" ]; then
  # shellcheck source=Scripts/lib_site_settings.sh
  source Scripts/lib_site_settings.sh
  [ -n "$TARGET_DIR" ] || TARGET_DIR="$(site_settings_get "$SETTINGS" html_dupl_target)" || exit 2
fi

pinned="$(node -e 'const v = require(process.argv[1]).devDependencies.jscpd; if (!v) process.exit(1); process.stdout.write(v)' \
  "$(pwd)/package.json" 2>/dev/null)" || {
  echo "html-dupl: no jscpd pin readable from package.json devDependencies — the dependency policy names no jscpd." >&2
  exit 2
}
JSCPD_PIN="jscpd@${pinned}"
JSCPD="$(pwd)/node_modules/.bin/jscpd"

# shellcheck source=Scripts/lib_tmp.sh
source Scripts/lib_tmp.sh
REPORT_DIR="$(tmp_dir check_html_dupl_report_dir)" || { echo "❌ FAIL: check_html_dupl.sh: cannot make a temp folder under ${TMPDIR:-/tmp}" >&2; exit 1; }
trap 'rm -rf "$REPORT_DIR"' EXIT

run_jscpd() {
  # Pinned in package.json + package-lock.json and run by path, deliberately
  # NOT falling back to a PATH install or npx: a different version is a
  # different number, and a ratchet cannot float.
  if [ -x "$JSCPD" ]; then
    "$JSCPD" "$@"
  else
    return 127
  fi
}

say_not_installed() {
  echo "html-dupl: ${JSCPD_PIN} is not installed at node_modules/.bin/jscpd — cannot measure (run npm ci)." >&2
  echo "  This does not skip: an unmeasured ratchet is not a passing one." >&2
}

# The jscpd that runs, as it answers --version, matched in bash (no pipe).
JSCPD_ANSWER="$(run_jscpd --version 2>/dev/null)"
vstatus=$?
if [ "$vstatus" -eq 127 ]; then
  say_not_installed
  exit 2
fi
JSCPD_MAJOR=""
if [ "$vstatus" -eq 0 ] && [[ "$JSCPD_ANSWER" =~ ^(jscpd[[:space:]]+)?v?(([0-9]+)\.[0-9]+\.[0-9]+[^[:space:]]*)$ ]]; then
  JSCPD_MAJOR="${BASH_REMATCH[3]}"
  JSCPD_LABEL="jscpd@${BASH_REMATCH[2]}"
else
  JSCPD_LABEL="jscpd@unknown"
fi

# The ceiling, when no argument gives it, in the form the settings lib declares.
if [ -z "$MAX_PCT" ]; then
  if [[ " ${SITE_SETTINGS_FAMILIES:-} " == *" html_dupl_ceiling_jscpd "* ]]; then
    if [ -z "$JSCPD_MAJOR" ]; then
      echo "html-dupl: could not read the running jscpd's version (\`jscpd --version\` exit ${vstatus}, said: ${JSCPD_ANSWER:0:200}) — cannot pick its ceiling from ${SETTINGS}." >&2
      exit 2
    fi
    MAX_PCT="$(site_settings_get "$SETTINGS" "html_dupl_ceiling_jscpd${JSCPD_MAJOR}")" || exit 2
    if [ -z "$MAX_PCT" ]; then
      echo "html-dupl: ${JSCPD_LABEL} runs (major ${JSCPD_MAJOR}), and ${SETTINGS} has no html_dupl_ceiling_jscpd${JSCPD_MAJOR} line — no ceiling for the running major." >&2
      echo "  Measure the target with jscpd ${JSCPD_MAJOR} and add that line; never reuse another major's ceiling." >&2
      exit 2
    fi
  else
    MAX_PCT="$(site_settings_get "$SETTINGS" html_dupl_ceiling)" || exit 2
    if [ -z "$MAX_PCT" ]; then
      echo "html-dupl: ${SETTINGS} has no html_dupl_ceiling line — no ceiling." >&2
      exit 2
    fi
  fi
fi

if [ ! -d "$TARGET_DIR" ]; then
  echo "html-dupl: target dir not found: ${TARGET_DIR}" >&2
  exit 2
fi

# No threshold: jscpd exits 0 whatever it finds, and the json reporter writes
# what this script reads.
out="$(cd "$TARGET_DIR" && run_jscpd -k 50 -r json -o "$REPORT_DIR" . -p "**/*.html" 2>&1)"
status=$?

if [ "$status" -eq 127 ]; then
  say_not_installed
  exit 2
fi

# Without a threshold jscpd exits 0 on any finding, so a non-zero exit is a real
# failure: show it, never hide it.
if [ "$status" -ne 0 ]; then
  echo "html-dupl: ${JSCPD_LABEL} failed (exit ${status}) — cannot measure:" >&2
  printf '%s\n' "$out" | sed -E 's/\x1b\[[0-9;]*m//g' | tail -20 >&2
  exit 2
fi

# The report, one fact per line: sources=<n>, pct=<two decimals>, and a
# clone=<format>: <file> lines <start>-<end> = <file> lines <start>-<end> line
# per clone. A field missing from the report leaves its line out.
report="$(node -e '
  const r = require(process.argv[1]);
  const t = (r.statistics || {}).total || {};
  const lines = [];
  if (Number.isInteger(t.sources)) lines.push("sources=" + t.sources);
  if (typeof t.percentage === "number") lines.push("pct=" + t.percentage.toFixed(2));
  const at = (f) => f.name + " lines " + f.start + "-" + f.end;
  for (const d of r.duplicates || []) lines.push("clone=" + d.format + ": " + at(d.firstFile) + " = " + at(d.secondFile));
  process.stdout.write(lines.join("\n"));
' "${REPORT_DIR}/jscpd-report.json" 2>/dev/null)"

# Nothing scanned is not clean. jscpd 4.2.4 writes no report at all when its
# pattern matches no file (5.x writes one with 0 sources), so a missing report
# counts as zero too.
sources="$(sed -n 's/^sources=//p' <<<"$report")"
if [ -z "$sources" ] || [ "$sources" = "0" ]; then
  echo "html-dupl: ${JSCPD_LABEL} scanned 0 .html files under ${TARGET_DIR} — nothing measured is not clean." >&2
  exit 2
fi

pct="$(sed -n 's/^pct=//p' <<<"$report")"

if [ -z "$pct" ]; then
  echo "html-dupl: could not read a percentage from ${JSCPD_LABEL}'s JSON report — BLIND, not clean." >&2
  echo "  Its report format changed, so this ratchet is measuring nothing." >&2
  exit 2
fi

# The comparison is ours, not jscpd's: its own -t semantics differ between
# versions, and the whole point of the pin is that this number means one thing.
over="$(awk -v a="$pct" -v b="$MAX_PCT" 'BEGIN { print (a > b) ? 1 : 0 }')"

if [ "$over" -eq 1 ]; then
  echo "html-dupl: ${JSCPD_LABEL} measured ${pct}% duplication in ${TARGET_DIR}:"
  sed -n 's/^clone=/  clone /p' <<<"$report"
  echo "html-dupl: duplication ${pct}% EXCEEDS the ${MAX_PCT}% ceiling." >&2
  echo "  The ceiling only ever moves DOWN. Do not raise it to clear this —" >&2
  echo "  remove the duplication instead." >&2
  exit 1
fi

echo "OK: html duplication ${pct}% over ${sources} file(s) in ${TARGET_DIR} (ceiling ${MAX_PCT}%, ${JSCPD_LABEL}) — ratchet holds"
exit 0
