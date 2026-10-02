#!/usr/bin/env bash
# Scripts/check_coverage.sh
#
# Gate: the coverage ratchet. Every Go function the coverage profile measures
# is held to its floor in coverage_thresholds.json, and the total to the
# total floor.
#
# PORTED (forsgren#1, ladder step 22) from MenoPower/Scripts/go/check_coverage.py,
# which MenoPower's sfl and CI run over `go tool cover -func` output in each
# Go module (shared, the API, admin). Its rules, kept:
#   - a function measured below its floor is red, named with both numbers.
#   - a floor of 0.0 is tracked, not enforced.
#   - a measured function missing from the thresholds file is red. The
#     estate rule says how to fix it: register it at 0.0, never a guessed
#     floor; FLOORWARN then says it can be raised.
#   - the total measured below the "total" floor is red.
#   - FLOORWARN (MenoPower #504): a floor below the ratchet rule (100.0 at
#     100%, else measured - 0.1, rounded to one decimal; an unregistered
#     function counts as floor 0.0) is counted into ONE line,
#     `FLOORWARN: N coverage floor(s) should be raised in <thresholds>`.
#     It is a warning and never changes the exit code. Each such function
#     is listed with the floor the rule gives it.
#   - a registered function the profile no longer measures (renamed or
#     removed) is a warning, not a red.
#   - the thresholds keys are `go tool cover -func`'s, `<import path of the
#     file>:<function>`, and floors only move up (the estate rule; the gate
#     does not read history, so it cannot hold that one).
# Adapted:
#   - bash and awk, not Python: python3 is not in Scripts/required_tools.txt,
#     and listing it there would make every sfl run `brew upgrade` a
#     machine-wide Python. Without Python there is no JSON parser either
#     (jq is not listed), so the thresholds file is read line by line in ONE
#     fixed shape, the shape MenoPower's files already have:
#         {
#           "_comment": "...",
#           "total": 89.4,
#           "functions": {
#             "<key>": 100.0,
#             ...
#           }
#         }
#     one entry per line, a number with an optional fraction. A line outside
#     that shape is red, named by its line number: the gate never guesses.
#   - no second test run. Scripts/check_go_tests.sh, the Go tests row
#     (only this gate's self-test sits between them), runs `go test -coverprofile=.build/go-coverage.out ./...` and
#     removes that profile whenever it is red, so the profile this gate reads
#     is always from a green run of the current tree. MenoPower's Makefiles
#     run the tests and the checker in one target instead.
#   - no data is red: no profile, or a profile that measures no function.
#     MenoPower passes a total of None silently.
#   - not ported: total_excludes (forsgren has no untestable wiring in its
#     total that needs it) and the --with-db floors (forsgren has no
#     database), each with no caller here.
#   - forsgren's FAIL and OK lines, in the order the profile lists the
#     functions.
#
# Exit codes:
#   0 — every function at or above its floor, and the total too
#   1 — a function below its floor or unregistered, the total below its
#       floor, no coverage data, or an unreadable or missing thresholds file
#   2 — tooling error (no module directory, go tool cover failed)
#
# Usage: Scripts/check_coverage.sh [module-dir] [thresholds-file]
#        (default: the repo root, coverage_thresholds.json in it; the profile
#        is <module-dir>/.build/go-coverage.out)
# Fixture: Scripts/test_check_coverage.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

ROOT="${1:-.}"
THRESHOLDS="${2:-coverage_thresholds.json}"
# Written by Scripts/check_go_tests.sh; the two paths must agree.
PROFILE=".build/go-coverage.out"

cd "$ROOT" 2>/dev/null || {
  echo "❌ FAIL: module directory not found: ${ROOT}" >&2
  exit 2
}

# Not empty, too: awk reads an empty first file as no file at all, and would
# then take the cover output for the thresholds.
if [ ! -s "$THRESHOLDS" ]; then
  echo "❌ FAIL: no thresholds file: ${THRESHOLDS} is missing or empty in ${ROOT}"
  exit 1
fi

if [ ! -s "$PROFILE" ]; then
  echo "❌ FAIL: no coverage data: ${PROFILE} is missing in ${ROOT} — Scripts/check_go_tests.sh writes it on a green run, and removes it on a red one"
  exit 1
fi

FUNCS="$(mktemp)"
trap 'rm -f "$FUNCS"' EXIT
if ! go tool cover -func="$PROFILE" > "$FUNCS" 2>&1; then
  cat "$FUNCS" >&2
  echo "❌ FAIL: go tool cover could not read ${PROFILE} in ${ROOT}" >&2
  exit 2
fi

# Pass 1 (FNR == NR) reads the thresholds file, pass 2 the cover -func
# output. Floors and measured values are compared as numbers, both as written
# with one decimal, so 66.7 and 66.7 are equal.
awk -v thresholds="$THRESHOLDS" '
  function fail(msg) { print "❌ FAIL: " msg; failed++ }
  function num(s) { return s ~ /^-?[0-9]+([.][0-9]+)?$/ }
  # The ratchet rule: the floor a function measured at `actual` should carry.
  function target(actual) {
    if (actual == 100.0) return 100.0
    return sprintf("%.1f", actual - 0.1) + 0
  }

  FNR == NR {
    line = $0
    sub(/^[ \t]+/, "", line)
    sub(/[ \t]+$/, "", line)
    if (line == "" || line == "{") next
    if (in_funcs && (line == "}" || line == "},")) { in_funcs = 0; next }
    if (!in_funcs && line == "}") next
    if (!in_funcs && line ~ /^"_comment"[ \t]*:[ \t]*".*",?$/) next
    if (!in_funcs && line ~ /^"functions"[ \t]*:[ \t]*[{]$/) { in_funcs = 1; next }
    value = line
    sub(/,$/, "", value)
    key = value
    if (key ~ /^"[^"]+"[ \t]*:/) {
      sub(/"[ \t]*:.*$/, "", key)
      sub(/^"/, "", key)
      sub(/^"[^"]+"[ \t]*:[ \t]*/, "", value)
    } else {
      key = ""
    }
    if (key != "" && num(value)) {
      if (!in_funcs && key == "total") { total_floor = value + 0; has_total = 1; next }
      if (in_funcs && !(key in floor)) { floor[key] = value + 0; order[++registered] = key; next }
      if (in_funcs) { fail(thresholds ":" FNR ": " key " is registered twice"); next }
    }
    fail(thresholds ":" FNR ": cannot read this line (one \"key\": number per line, see Scripts/check_coverage.sh): " line)
    next
  }

  $1 == "total:" {
    total = $NF
    sub(/%$/, "", total)
    next
  }

  NF >= 3 {
    file = $1
    sub(/:[0-9]+:$/, "", file)
    key = file ":" $2
    actual = $NF
    sub(/%$/, "", actual)
    actual += 0
    measured[key] = 1
    functions++
    if (!(key in floor)) {
      fail(sprintf("%s: %.1f%% is not registered in %s — register it at 0.0", key, actual, thresholds))
      f = 0.0
    } else {
      f = floor[key]
      if (f > 0 && actual < floor[key]) {
        fail(sprintf("%s: %.1f%% is below its floor %.1f%%", key, actual, f))
      } else {
        printf "  ✅ %s: %.1f%% (floor %.1f%%)\n", key, actual, f
      }
      if (f > 0) enforced++
    }
    if (target(actual) > sprintf("%.1f", f) + 0) {
      raise[++raises] = sprintf("  ⬆️  %s: %.1f%%, floor %.1f%% — raise it to %.1f", key, actual, f, target(actual))
    }
  }

  END {
    if (functions == 0) {
      fail("no coverage data: the profile measures no function")
      exit 1
    }
    if (!has_total) {
      fail(thresholds ": no \"total\" floor")
    } else if (total + 0 < total_floor) {
      fail(sprintf("total: %.1f%% is below its floor %.1f%%", total, total_floor))
    } else {
      printf "  ✅ total: %.1f%% (floor %.1f%%)\n", total, total_floor
    }
    for (i = 1; i <= registered; i++) {
      if (!(order[i] in measured)) {
        printf "  ⚠️  %s: in %s but not in the coverage output (renamed or removed?)\n", order[i], thresholds
      }
    }
    if (raises > 0) {
      print ""
      for (i = 1; i <= raises; i++) print raise[i]
      printf "FLOORWARN: %d coverage floor(s) should be raised in %s\n", raises, thresholds
    }
    print ""
    if (failed > 0) {
      printf "❌ FAIL: %d coverage finding(s) above — a floor is met by testing, never by lowering it\n", failed
      exit 1
    }
    printf "OK: coverage — total %.1f%%, %d function(s) measured, %d enforced at or above their floors\n", total, functions, enforced
  }
' "$THRESHOLDS" "$FUNCS"
