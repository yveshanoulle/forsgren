#!/usr/bin/env bash
# canon: test_gate_browser v8
# Scripts/test_gate_browser.sh (forsgren#205)
#
# Self-test for Scripts/gate_browser.sh, the browser gate, run in PRE before the
# gate it validates. The real Chrome and the real axe-core, never a fake: each
# case is a fixture site served on 127.0.0.1 and run through the gate.
#   1. a clean page                              -> green, the OK line
#   2. an axe serious violation (low contrast)   -> red, naming axe color-contrast
#   3. an axe critical violation (unnamed button) -> red, naming axe button-name
#   4. no doctype                                -> red, naming the doctype
#   5. no charset (the server sends none)        -> red, naming the charset
#   6. a console error                           -> red, naming the console error
#   7. an image answering 404                    -> red, naming the resource and 404
#   8. a layout shift                            -> red, naming the CLS
#   9. a request that leaves loopback            -> red, naming it
#  10. a manifest page that answers 404          -> red, naming 404
#  11. an exception row for the 404 image        -> green, counted as excepted
#  12. an exception row without a reason         -> exit 2 (fail-closed)
#  13. an exception row that matches nothing     -> red (stale)
#  14. a missing exceptions file                 -> exit 2
#  15. the OK line records the CLS, viewport, browser version and interval
# The shrink-only baseline (estate issue 305, Scripts/browser_gate_baseline.txt;
# every row starts with its variant, v2):
#  16. every axe finding in the baseline               -> green, each shown as a WARN
#  17. an axe finding the baseline lacks               -> red, new
#  18. a baselined axe finding that is gone            -> red, stale
#  19. a page CLS above its recorded value             -> red, grew
#  20. a page CLS below its recorded value             -> red, lower the row
#  21. a page CLS equal to its recorded value          -> green, shown as a WARN
#  22. a CLS row on a page that has no shift           -> red, stale
#  23. a CLS above 0 with no row                       -> red, no baseline row
#  24. a row without a reason, a malformed row, a
#      duplicate row, an unknown kind of row           -> exit 2
#  25. a missing baseline file                         -> exit 2
# The external exceptions (external|<url prefix>|<reason>):
#  26. a listed external request                       -> green, blocked, shown, counted
#  27. an external request that is not listed          -> red, leaves loopback
#  28. a listed prefix that no page requests           -> red, stale
#  29. an external row without a reason                -> exit 2
# The variants (v2, Scripts/browser_gate_variants.txt, name|how to apply):
#  30. a finding only in an attr: variant              -> red, naming that variant
#  31. the same finding baselined for that variant     -> green, a WARN with the variant
#  32. the baseline row naming the other variant       -> red (new in dark, stale in light)
#  33. a finding only in a scheme:dark variant         -> red, naming dark
#  34. the same finding baselined, the OK line names pages x variants and the checks -> green
#  35. a variants file that is missing, has no row, repeats a name, has an
#      unknown how, or a malformed attr:               -> exit 2
#  36. a baseline row naming no known variant, and the v1 row without one -> exit 2
# Mutation proofs (each fixture is red BECAUSE of the line mutated):
#   A. the severity filter widened to ignore serious: case 2 turns green;
#   B. the CLS compared rounded: case 19 turns green (a small growth passes);
#   C. a 404 read only from network-failure events: case 7 stops saying 404;
#   D. the baseline match ignoring the selector: case 17 turns green (a new
#      element on a baselined rule passes);
#   E. the stale check removed: case 18 turns green;
#   F. an attr: variant not applied: case 30 turns green (the dark look never
#      checked);
#   G. the scheme not emulated per variant: case 33 turns green.
# The layout-shift override (forsgren#247, decision 249): the loads and the
# interval are read from FORSGREN_CLS_LOADS and FORSGREN_CLS_INTERVAL_MS, the
# default stays 5 loads at 1000 ms. Every case but the layout-shift ones runs with
# the short setting (1 load, 300 ms). The layout-shift fixtures set a flag after
# the page moved and answer the gate's read of the shifts once it is set (30 s
# bound), so no clock decides whether the read sees the shift (forsgren#386);
# the cases that need a shift caught under an override read after 50 ms:
#  37. the override is honoured (2 loads, 50 ms)        -> the OK line says 50 ms
#  38. an override still catches the shift fixture      -> red, 1 cold loads
#  38b. a page that stalls 800 ms after the load         -> still red under the override
#  39. an override that is no positive integer           -> exit 2
#  40. a load delayed 800 ms (forsgren#275)              -> the short setting is still red
#   H. the override ignored: case 37 stops saying 50 ms;
#   I. the default interval changed: case 15 loses 1000 ms;
#   J. the default loads changed: case 8 loses 5 cold loads;
#   K. a layout-shift case given a too short setting (1 ms) turns green; the
#      page moves one tick after the gate's first read of the shifts, so the
#      read is before the shift on any machine; the control moves it two frames
#      after the load and the real setting is red (forsgren#252, #275, #384).
# Sideways scrolling (forsgren#350): every page at a laptop and a phone width,
# 1280x800 and 390x844, is red when the page, or the box a table sits in,
# scrolls sideways (scrollWidth above clientWidth), naming the page, the width
# and the overflow in pixels; one rule for every page with a table:
#  41. a table wider than its scroll box at the phone width only -> red, 390x844
#  42. a table wider than its scroll box at the laptop width too -> red, 1280x800
#  43. a page wider than the window (no scroll box)              -> red, the page
#  44. a long cell that wraps inside its table                   -> green
# The sideways baseline (v3, decision #364: today's overflow outside the TBD
# page, shrink-only), sideways|<variant>|<page>|<viewport>|<what>|<px>|reason:
#  45. the overflow equal to its row        -> green, a WARN, counted
#  46. the overflow above its row           -> red, grew
#  47. the overflow below its row           -> red, shrink the row
#  48. a row whose overflow is gone         -> red, stale
#  49. a row without a reason, a px that is no positive whole number, a
#      viewport the gate does not measure, a row listed twice -> exit 2
#   L. the check removed: case 41 turns green;
#   M. the comparison loosened (an overflow of 1000 px allowed): case 41 turns
#      green;
#   N. the growth comparison dropped: case 46 turns green;
#   O. the stale check of the sideways rows removed: case 48 turns green.
# The CLS interval starts at the load (forsgren#377):
#  50. a page that reports a shift when it is read after the axe run -> green
#   P. the CLS read moved back after the axe run: case 50 turns red.
# The sideways measurement does not depend on a scrollbar (forsgren#377, .1):
#  51. case 41's table on a page that shows a 15 px page scrollbar -> red, still
#      210 px (a measurement that reads the box beside the scrollbar says 225)
#   Q. the scrollbar not hidden while measuring: case 51 says 225.
# The exits (forsgren#381, browser_gate v5, v6 since forsgren#386): Chrome closed
# and its profile folder removed on every way out:
#  52. SIGTERM, SIGINT, SIGHUP to the wrapper, SIGTERM to node (under the wrapper
#      and alone) -> exit 143, 130, 129; no Chrome, no profile folder; SIGKILL
#      to node -> Chrome ends with its pipe
#  53. Chrome killed mid-run (an error) -> exit 2; no Chrome, no profile folder
#  53c. Chrome killed while the run starts (a Chrome that opens no initial page,
#      through FORSGREN_CHROME) -> exit 2 within 15 s with the usual error; no
#      Chrome, no profile folder (forsgren#386, browser_gate v6)
#      The signal comes once the run is provably mid-run: the profile folder
#      exists and Chrome holds a connection to the gate's own server, i.e. it
#      is loading a fixture page, which only happens after the launch resolved
#      and the engine's Chrome watch is attached (Chrome's first about:blank
#      renderer, the old "up", exists during the launch, forsgren#386); never
#      after a delay. The fixture has forty looks so the gate is still running;
#      a gate not up in 60 s, or ended before the signal, is red with that
#      reason (forsgren#383). The gate gets up to 60 s to end, and Chrome up to
#      60 s to be gone: observable conditions, never a fixed window (forsgren#384).
# Each ok and FAIL line ends with the seconds since the line before it, the
# case's own duration, so the CI log shows what is slow (forsgren#386).
#   R. no signal handler in the engine: case 52e leaves the profile folder;
#   S. the wrapper not forwarding the signal: case 52a leaves Chrome alive.
# There is no mutation proof for case 53c (forsgren#443). Proof U, the old engine
# with waitForInitialPage: true kept running in case 53c, went: it raced on a
# hosted runner, where the kill marker (the profile folder) can come before
# Chrome connects, so even the old engine ended at once. Case 53c stays as a pin;
# it was seen failing against the v5 engine when it was written (forsgren#386).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
GATE="${REPO_ROOT}/Scripts/gate_browser.sh"
ENGINE="${REPO_ROOT}/Scripts/browser_gate.mjs"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
# Seconds per case: every ok and FAIL line of this run ends with the seconds
# since the line before it, which is the duration of the case it reports, so the
# CI log shows what is slow (forsgren#386). echo is shadowed here, so the
# helpers of lib_selftest.sh (want_*, fail) report through it too.
LAP=$SECONDS
echo() {
  case "${1-}" in
    "  ok: "* | "❌ FAIL: "*)
      builtin echo "$* ($((SECONDS - LAP)) s)"
      LAP=$SECONDS
      ;;
    *) builtin echo "$@" ;;
  esac
}
selftest_begin "browser gate self-test"

for need in "$GATE" "$ENGINE" "${REPO_ROOT}/node_modules/puppeteer-core" "${REPO_ROOT}/node_modules/axe-core"; do
  if [[ ! -e "$need" ]]; then
    selftest_abort "browser gate self-test: ${need} is missing"
  fi
done

# page <body-extra> <head-extra> [doctype] [charset]: a clean page, one part changed.
page() {
  local body="$1" head="$2" doctype="${3-<!doctype html>}" charset="${4-<meta charset=\"utf-8\">}"
  cat <<HTML
${doctype}
<html lang="en">
<head>
${charset}
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>fixture</title>
<link rel="icon" href="data:,">
<link rel="stylesheet" href="/styles.css">
${head}
</head>
<body>
<main>
<h1>Fixture</h1>
<p>Plain text.</p>
${body}
</main>
</body>
</html>
HTML
}

# make_site <name> <index.html content>: a site with that page, a stylesheet,
# a manifest of "/" and an empty exceptions file, under $TMP/<name>.
make_site() {
  local dir="${TMP}/$1"
  mkdir -p "$dir/site"
  printf '%s\n' "$2" > "$dir/site/index.html"
  printf 'body { color: #111; background: #fff; }\n' > "$dir/site/styles.css"
  printf '{"requiredPages": ["/"]}\n' > "$dir/manifest.json"
  : > "$dir/exceptions.txt"
  : > "$dir/baseline.txt"
  printf 'light|scheme:light\n' > "$dir/variants.txt"
}

# The short setting: the cases that never assert on layout shift.
SHORT_CLS_LOADS=1
SHORT_CLS_INTERVAL_MS=300
run_gate() {
  FORSGREN_CLS_LOADS="$SHORT_CLS_LOADS" FORSGREN_CLS_INTERVAL_MS="$SHORT_CLS_INTERVAL_MS" capture "$GATE" "${TMP}/$1/site" "${TMP}/$1/manifest.json" "${TMP}/$1/exceptions.txt" "${TMP}/$1/baseline.txt" "${TMP}/$1/variants.txt"
}

# run_gate_hit: one load read after HIT_CLS_INTERVAL_MS, for the cases that
# need a shift fixture to be caught under an override (38, 38b, 40). The
# interval is short on purpose: the fixture answers the read only once it has
# moved (WAIT_JS), so the interval decides nothing (forsgren#386; it was a
# fixed 2500 ms, a margin of 1.7 s, forsgren#384).
HIT_CLS_INTERVAL_MS=50
run_gate_hit() {
  FORSGREN_CLS_LOADS=1 FORSGREN_CLS_INTERVAL_MS="$HIT_CLS_INTERVAL_MS" capture "$GATE" "${TMP}/$1/site" "${TMP}/$1/manifest.json" "${TMP}/$1/exceptions.txt" "${TMP}/$1/baseline.txt" "${TMP}/$1/variants.txt"
}

# run_gate_real: the real setting (the default, whatever the caller exports),
# for the cases that assert on layout shift or on the interval text.
run_gate_real() {
  capture env -u FORSGREN_CLS_LOADS -u FORSGREN_CLS_INTERVAL_MS "$GATE" "${TMP}/$1/site" "${TMP}/$1/manifest.json" "${TMP}/$1/exceptions.txt" "${TMP}/$1/baseline.txt" "${TMP}/$1/variants.txt"
}

make_site clean "$(page '' '')"
make_site serious "$(page '<p style="color:#cccccc">pale text</p>' '')"
make_site critical "$(page '<button></button>' '')"
make_site nodoctype "$(page '' '' '')"
make_site nocharset "$(page '' '' '<!doctype html>' '')"
make_site console "$(page '<script>console.error("fixture boom")</script>' '')"
make_site notfound "$(page '<img src="/missing.png" alt="absent">' '')"
# The shift fixtures never race the gate's read (forsgren#384, #386). A shift
# that the page moves on a clock is a race against the machine: a hosted runner
# delayed the frames of a load past the 300 ms read of case 38, and a fixed
# 2500 ms was only a margin. So each fixture is ordered by something the test
# controls:
#  - shift: two animation frames after the load event (after the first paint,
#    since a move before it is no shift). The page sets a flag (window.__moved)
#    after it moved and two frames more (the observer has delivered the shift),
#    and answers the gate's read of window.__shifts only then (WAIT_JS: the
#    read is a promise, which the gate's evaluate waits for), at most 30 s. So
#    cases 8 and 19-23 (the real 1000 ms) and 38, 38b and 40 (50 ms) read the
#    shift on any machine, whatever the interval. shiftstall delays the move a
#    further 800 ms, the machine's own delay made on purpose.
#  - lateshift (proof K): the page moves one tick after the first read of
#    window.__shifts, so the read is before the shift on any machine: no clock
#    decides it.
#  - earlyshift (proof K control): the same code, but it moves two animation
#    frames after the load and sets the flag like shift, so the real setting
#    reads it.
# lateshift_js <read|frames>: when the page moves.
lateshift_js() {
  printf '%s' '<script>(function () { var mode = "'"$1"'"; var real = window.__shifts; var moved = false; function move() { if (moved) return; moved = true; var d = document.createElement("div"); d.style.height = "120px"; d.textContent = "late"; document.querySelector("main").prepend(d); if (window.__markMoved) window.__markMoved(); } if (mode === "read") { Object.defineProperty(window, "__shifts", { configurable: true, get: function () { setTimeout(move, 0); return real; } }); } else { window.addEventListener("load", function () { requestAnimationFrame(function () { requestAnimationFrame(move); }); }); } })();</script>'
}
LATE_JS="$(lateshift_js read)"
# WAIT_JS: window.__shifts answers the gate's read with a promise that resolves
# with the observed shifts once the page called __markMoved (it moved, and two
# frames have passed so the observer has the entry), or after 30 s. The
# observer still pushes into window.__shifts, so the promise has a push that
# forwards to the real array.
WAIT_JS='<script>(function () { var real = window.__shifts; window.__moved = false; var answer = new Promise(function (resolve) { window.__markMoved = function () { window.__moved = true; requestAnimationFrame(function () { requestAnimationFrame(function () { resolve(real); }); }); }; setTimeout(function () { resolve(real); }, 30000); }); answer.push = function (value) { return real.push(value); }; Object.defineProperty(window, "__shifts", { configurable: true, get: function () { return answer; } }); })();</script>'
SHIFT_JS="${WAIT_JS}"'<script>window.addEventListener("load", function () { requestAnimationFrame(function () { requestAnimationFrame(function () { var d = document.createElement("div"); d.style.height = "120px"; d.textContent = "late"; document.querySelector("main").prepend(d); window.__markMoved(); }); }); });</script>'
make_site shift "$(page '' "$SHIFT_JS")"
make_site lateshift "$(page '' "$LATE_JS")"
make_site earlyshift "$(page '' "${WAIT_JS}$(lateshift_js frames)")"
STALL_JS="${WAIT_JS}"'<script>window.addEventListener("load", function () { setTimeout(function () { requestAnimationFrame(function () { requestAnimationFrame(function () { var d = document.createElement("div"); d.style.height = "120px"; d.textContent = "late"; document.querySelector("main").prepend(d); window.__markMoved(); }); }); }, 800); });</script>'
make_site shiftstall "$(page '' "$STALL_JS")"
# The delay seam (forsgren#275): the same two pages after a script that blocks
# the parse for 800 ms, as a starved machine delays the load. With the shift
# timed from the script's parse (the fixtures as they were up to #252) the
# short setting then missed the shift in 13 of 30 runs (the move came before
# the first paint) and the 1 ms read of proof K saw it in 20 of 30 (the move
# came before the read); anchored to the load, neither can happen.
BUSY_JS='<script>var t0 = Date.now(); while (Date.now() - t0 < 800) {}</script>'
make_site shiftslow "$(page '' "${SHIFT_JS}${BUSY_JS}")"
make_site lateshiftslow "$(page '' "${LATE_JS}${BUSY_JS}")"
# The read-order seam (forsgren#377): the gate reads the shifts through
# window.__shifts. This page turns that read into a fake shift of 0.5 when axe
# is already on the page, i.e. when the read came after the axe run. A gate
# that starts its interval at the load, before the document and axe checks,
# reads first and is green; the speed of the machine decides nothing.
AFTER_AXE_JS='<script>(function () { var real = window.__shifts; Object.defineProperty(window, "__shifts", { configurable: true, get: function () { return window.axe ? [0.5] : real; } }); })();</script>'
make_site readorder "$(page '' "$AFTER_AXE_JS")"
make_site external "$(page '<img src="http://example.invalid/x.png" alt="away">' '')"
make_site nopage "$(page '' '')"
printf '{"requiredPages": ["/", "/nope.html"]}\n' > "${TMP}/nopage/manifest.json"

run_gate_real clean
want_green "1: a clean page" "OK: browser gate: 1 pages x 1 variants (light)"
CLEAN_OUT="$OUT"

run_gate serious
want_red "2: an axe serious violation" "axe color-contrast (serious)"
run_gate critical
want_red "3: an axe critical violation" "axe button-name (critical)"
run_gate nodoctype
want_red "4: no doctype" "doctype missing"
run_gate nocharset
want_red "5: no charset" "charset not declared"
run_gate console
want_red "6: a console error" "console error: fixture boom"
run_gate notfound
want_red "7: a 404 image" "request /missing.png -> 404"
run_gate_real shift
want_red "8: a layout shift" "CLS 0."
want_said "8a: with the default 5 cold loads" "largest of 5 cold loads"
want_said "8b: a layout shift without a row says so" "no baseline row"
run_gate external
want_red "9: a request leaving loopback" "leaves loopback"
run_gate nopage
want_red "10: a manifest page answering 404" "FAIL: light /nope.html: request /nope.html -> 404"

# 11: the exception turns the 404 image green (its console error goes too).
printf '/missing.png|fixture: deliberately absent\n' > "${TMP}/notfound/exceptions.txt"
run_gate notfound
want_green "11: an exception row for the 404 image" "1 excepted"

# 12-14: the exceptions file is closed and fail-closed.
printf '/missing.png|\n' > "${TMP}/notfound/exceptions.txt"
run_gate notfound
want_exit "12: an exception without a reason" 2 "has no reason"
printf '/other.png|fixture: stale\n' > "${TMP}/clean/exceptions.txt"
run_gate clean
want_red "13: an exception that matches nothing" "exception /other.png matched nothing"
rm -f "${TMP}/clean/exceptions.txt"
run_gate clean
want_exit "14: a missing exceptions file" 2 "exceptions file not found"
: > "${TMP}/clean/exceptions.txt"

# 15: what is recorded.
for need in "CLS worst 0 " "viewport 1280x800" "variants (light)" "Chrome/" "interval 1000 ms" "no new sideways scroll at 1280x800 and 390x844 (0 baselined)"; do
  if ! grep -qF -- "$need" <<< "$CLEAN_OUT"; then
    fail "15: the OK line does not record '${need}'. Output: ${CLEAN_OUT}"
  fi
done
echo "  ok: 15: the OK line records the CLS, viewport, browser version, interval and the sideways-scroll widths"

# The baseline. Two pale paragraphs, #a and #b, both color-contrast serious.
REASON="fixture, shrink-only"
make_site two "$(page '<p id="a" style="color:#cccccc">pale a</p><p id="b" style="color:#cccccc">pale b</p>' '')"
printf 'axe|light|/|color-contrast|#a|%s\naxe|light|/|color-contrast|#b|%s\n' "$REASON" "$REASON" > "${TMP}/two/baseline.txt"
run_gate two
want_green "16: every axe finding in the baseline" "OK: browser gate"
want_said "16b: each baselined finding is shown as a WARN" "WARN: baselined axe color-contrast (serious): light /: #a"
want_said "16c: the other too" "WARN: baselined axe color-contrast (serious): light /: #b"
want_said "16d: and they are counted" "2 axe findings baselined"

printf 'axe|light|/|color-contrast|#a|%s\n' "$REASON" > "${TMP}/two/baseline.txt"
run_gate two
want_red "17: an axe finding the baseline lacks" "FAIL: light /: axe color-contrast (serious): #b (new, not in the baseline)"

printf 'axe|light|/|color-contrast|#a|%s\naxe|light|/|color-contrast|#b|%s\naxe|light|/|color-contrast|#gone|%s\n' "$REASON" "$REASON" "$REASON" > "${TMP}/two/baseline.txt"
run_gate two
want_red "18: a baselined axe finding that is gone" "FAIL: stale baseline row: axe|light|/|color-contrast|#gone"

# CLS rows. M is the shift the fixture measures, read from the gate itself.
run_gate_real shift
CLS_M="$(sed -n 's/.*FAIL: light \/: CLS \([0-9.e-]*\) .*/\1/p' <<< "$OUT" | head -1)"
if [[ -z "$CLS_M" ]]; then
  fail "the shift fixture did not report a CLS value. Output: ${OUT}"
  CLS_M=0.05
fi
scaled() { awk -v m="$CLS_M" -v f="$1" 'BEGIN { printf "%.17g", m * f }'; }

printf 'cls|light|/|%s|%s\n' "$(scaled 0.999)" "$REASON" > "${TMP}/shift/baseline.txt"
run_gate_real shift
want_red "19: a CLS above its recorded value" "FAIL: light /: CLS ${CLS_M} grew above the recorded"
printf 'cls|light|/|%s|%s\n' "$(scaled 1.001)" "$REASON" > "${TMP}/shift/baseline.txt"
run_gate_real shift
want_red "20: a CLS below its recorded value" "FAIL: light /: CLS ${CLS_M} is below the recorded"
want_said "20b: and it says to lower the row" "lower the row"
printf 'cls|light|/|%s|%s\n' "$CLS_M" "$REASON" > "${TMP}/shift/baseline.txt"
run_gate_real shift
want_green "21: a CLS equal to its recorded value" "WARN: baselined CLS light /: ${CLS_M}"

printf 'cls|light|/|0.01|%s\n' "$REASON" > "${TMP}/clean/baseline.txt"
run_gate clean
want_red "22: a CLS row on a page without a shift" "is below the recorded 0.01"
: > "${TMP}/clean/baseline.txt"

: > "${TMP}/shift/baseline.txt"
run_gate_real shift
want_red "23: a CLS above 0 with no row" "no baseline row"

printf 'axe|light|/|color-contrast|#a|\n' > "${TMP}/two/baseline.txt"
run_gate two
want_exit "24a: an axe row without a reason" 2 "has no reason"
printf 'cls|light|/|0.01|\n' > "${TMP}/two/baseline.txt"
run_gate two
want_exit "24b: a CLS row without a reason" 2 "has no reason"
printf 'axe|light|/|color-contrast|%s\n' "$REASON" > "${TMP}/two/baseline.txt"
run_gate two
want_exit "24c: an axe row without a selector" 2 "a row is"
printf 'cls|light|/|large|%s\n' "$REASON" > "${TMP}/two/baseline.txt"
run_gate two
want_exit "24d: a CLS row with a value that is no number" 2 "must be a positive number"
printf 'other|/|x|%s\n' "$REASON" > "${TMP}/two/baseline.txt"
run_gate two
want_exit "24e: a row of an unknown kind" 2 "unknown row"
printf 'axe|light|/|color-contrast|#a|%s\naxe|light|/|color-contrast|#a|%s\n' "$REASON" "$REASON" > "${TMP}/two/baseline.txt"
run_gate two
want_exit "24f: a row listed twice" 2 "listed twice"

rm -f "${TMP}/two/baseline.txt"
run_gate two
want_exit "25: a missing baseline file" 2 "baseline file not found"

# External requests.
make_site viaexternal "$(page '<img src="http://example.invalid/x.png" alt="away">' '')"
printf 'external|http://example.invalid/|fixture: an embed that must not leave\n' > "${TMP}/viaexternal/exceptions.txt"
run_gate viaexternal
want_green "26: a listed external request" "WARN: external blocked: light /: http://example.invalid/x.png"
want_said "26b: counted" "1 external requests blocked"

run_gate external
want_red "27: an external request that is not listed" "request http://example.invalid/x.png leaves loopback"

printf 'external|http://elsewhere.invalid/|fixture: never requested\n' > "${TMP}/clean/exceptions.txt"
run_gate clean
want_red "28: a listed external prefix no page requests" "FAIL: stale external exception: http://elsewhere.invalid/"
: > "${TMP}/clean/exceptions.txt"

printf 'external|http://example.invalid/|\n' > "${TMP}/viaexternal/exceptions.txt"
run_gate viaexternal
want_exit "29: an external row without a reason" 2 "has no reason"

# The variants (v2). #t is pale in the dark look only: under an attribute the
# page's own CSS reads (case 30-32), and under the dark colour scheme (case 33).
make_site themed "$(page '<p id="t">themed text</p>' '<style>:root[data-theme="dark"] #t { color: #cccccc; }</style>')"
printf 'light|attr:data-theme=light\ndark|attr:data-theme=dark\n' > "${TMP}/themed/variants.txt"
run_gate themed
want_red "30: a finding only in an attr: variant" "FAIL: dark /: axe color-contrast (serious): #t (new, not in the baseline)"
if grep -qF -- "FAIL: light /" <<< "$OUT"; then
  fail "30b: the light variant was blamed for the dark finding. Output: ${OUT}"
else
  echo "  ok: 30b: the light variant is clean"
fi

printf 'axe|dark|/|color-contrast|#t|%s\n' "$REASON" > "${TMP}/themed/baseline.txt"
run_gate themed
want_green "31: the same finding baselined for that variant" "OK: browser gate: 1 pages x 2 variants (light, dark)"
want_said "31b: shown as a WARN with its variant" "WARN: baselined axe color-contrast (serious): dark /: #t"

printf 'axe|light|/|color-contrast|#t|%s\n' "$REASON" > "${TMP}/themed/baseline.txt"
run_gate themed
want_red "32: a row naming the other variant" "FAIL: dark /: axe color-contrast (serious): #t (new, not in the baseline)"
want_said "32b: and the row of the wrong variant is stale" "FAIL: stale baseline row: axe|light|/|color-contrast|#t"

make_site schemed "$(page '<p id="t">schemed text</p>' '<style>@media (prefers-color-scheme: dark) { #t { color: #cccccc; } }</style>')"
printf 'light|scheme:light\ndark|scheme:dark\n' > "${TMP}/schemed/variants.txt"
run_gate schemed
want_red "33: a finding only in a scheme:dark variant" "FAIL: dark /: axe color-contrast (serious): #t"
printf 'axe|dark|/|color-contrast|#t|%s\n' "$REASON" > "${TMP}/schemed/baseline.txt"
run_gate schemed
want_green "34: baselined, the scheme:dark run is green, and its OK line names pages x variants and checks" "OK: browser gate: 1 pages x 2 variants (light, dark), 2 checks"
: > "${TMP}/schemed/baseline.txt"

# 35: the variants file is closed and fail-closed.
rm -f "${TMP}/clean/variants.txt"
run_gate clean
want_exit "35a: a missing variants file" 2 "variants file not found"
: > "${TMP}/clean/variants.txt"
run_gate clean
want_exit "35b: a variants file with no row" 2 "lists no variant"
printf 'light|scheme:light\nlight|scheme:dark\n' > "${TMP}/clean/variants.txt"
run_gate clean
want_exit "35c: a variant listed twice" 2 "listed twice"
printf 'light|theme:light\n' > "${TMP}/clean/variants.txt"
run_gate clean
want_exit "35d: an unknown how to apply" 2 "unknown how to apply"
printf 'dark|attr:data-theme\n' > "${TMP}/clean/variants.txt"
run_gate clean
want_exit "35e: an attr: without a value" 2 "unknown how to apply"
printf 'light\n' > "${TMP}/clean/variants.txt"
run_gate clean
want_exit "35f: a row without a how" 2 "a row is name|how to apply"
printf 'light|scheme:light\n' > "${TMP}/clean/variants.txt"

# 36: a baseline row names a variant of the file; the v1 row has none.
printf 'axe|dusk|/|color-contrast|#a|%s\n' "$REASON" > "${TMP}/clean/baseline.txt"
run_gate clean
want_exit "36a: a baseline row naming an unknown variant" 2 "is not a variant"
printf 'axe|/|color-contrast|#a|%s\n' "$REASON" > "${TMP}/clean/baseline.txt"
run_gate clean
want_exit "36b: a row of the v1 format, without a variant" 2 "a row is axe|<variant>"
printf 'cls|/|0.01|%s\n' "$REASON" > "${TMP}/clean/baseline.txt"
run_gate clean
want_exit "36c: a CLS row of the v1 format, without a variant" 2 "a row is cls|<variant>"
: > "${TMP}/clean/baseline.txt"

# 37-39: the layout-shift override.
FORSGREN_CLS_LOADS=2 FORSGREN_CLS_INTERVAL_MS=50 capture "$GATE" "${TMP}/clean/site" "${TMP}/clean/manifest.json" "${TMP}/clean/exceptions.txt" "${TMP}/clean/baseline.txt" "${TMP}/clean/variants.txt"
want_green "37: the override is honoured" "interval 50 ms"
run_gate_hit shift
want_red "38: an override still catches the shift fixture" "largest of 1 cold loads"
run_gate_hit shiftstall
want_red "38b: a page that stalls 800 ms after the load, an override still catches the shift" "largest of 1 cold loads"
run_gate_hit shiftslow
want_red "40: a delayed load, an override still catches the shift fixture" "largest of 1 cold loads"
FORSGREN_CLS_LOADS=0 capture "$GATE" "${TMP}/clean/site" "${TMP}/clean/manifest.json" "${TMP}/clean/exceptions.txt" "${TMP}/clean/baseline.txt" "${TMP}/clean/variants.txt"
want_exit "39a: zero loads" 2 "FORSGREN_CLS_LOADS must be a positive integer"
FORSGREN_CLS_INTERVAL_MS=fast capture "$GATE" "${TMP}/clean/site" "${TMP}/clean/manifest.json" "${TMP}/clean/exceptions.txt" "${TMP}/clean/baseline.txt" "${TMP}/clean/variants.txt"
want_exit "39b: an interval that is no number" 2 "FORSGREN_CLS_INTERVAL_MS must be a positive integer"

# 41-44: sideways scrolling (forsgren#350). The body has no margin, so the
# overflow is the table's width less the window's: 600 - 390 = 210 px.
SCROLL_BOX='<div style="overflow-x: auto" role="region" aria-label="wide table" tabindex="0">'
make_site phonewide "$(page "${SCROLL_BOX}<table style=\"width: 600px\"><tr><th scope=\"col\">wide</th></tr></table></div>" '<style>body { margin: 0; }</style>')"
make_site laptopwide "$(page "${SCROLL_BOX}<table style=\"width: 1500px\"><tr><th scope=\"col\">wide</th></tr></table></div>" '<style>body { margin: 0; }</style>')"
make_site pagewide "$(page '<div style="width: 1500px">wide</div>' '<style>body { margin: 0; }</style>')"
# 51: case 41's table on a page that always shows a 15 px page scrollbar.
# Whether Chrome gives a page scrollbar room is the system's choice (classic or
# overlay scrollbars) and headless Chrome hides them, so the page makes its own
# 15 px: it leaves the room a classic scrollbar takes unless the root's
# scrollbar-gutter is set inline on <html>, which is what the gate does.
SCROLLBAR_CSS='<style>body { margin: 0; min-height: 2000px; } html:not([style*="scrollbar-gutter"]) body { padding-right: 15px; }</style>'
make_site scrollbar "$(page "${SCROLL_BOX}<table style=\"width: 600px\"><tr><th scope=\"col\">wide</th></tr></table></div>" "$SCROLLBAR_CSS")"
LONG_CELL="$(printf 'note %.0s' {1..120})"
make_site wraps "$(page "${SCROLL_BOX}<table><tr><th scope=\"row\">Acme</th><td>${LONG_CELL}</td></tr></table></div>" '')"
run_gate phonewide
want_red "41: a table wider than its box at the phone width" "FAIL: light /: scrolls sideways at 390x844: table 1 is 210 px wider than its box"
if grep -qF -- "at 1280x800" <<< "$OUT"; then
  fail "41b: the laptop width was blamed for a table that fits it. Output: ${OUT}"
else
  echo "  ok: 41b: the laptop width is clean"
fi
run_gate laptopwide
want_red "42: a table wider than its box at the laptop width" "FAIL: light /: scrolls sideways at 1280x800: table 1 is 220 px wider than its box"
want_said "42b: and at the phone width" "FAIL: light /: scrolls sideways at 390x844: table 1 is 1110 px wider than its box"
run_gate pagewide
want_red "43: a page wider than the window" "FAIL: light /: scrolls sideways at 1280x800: the page is 220 px wider than the window"
run_gate wraps
want_green "44: a long cell that wraps inside its table" "no new sideways scroll at 1280x800 and 390x844 (0 baselined)"

# 45-49: the sideways baseline, on case 41's page (210 px at 390x844).
printf 'sideways|light|/|390x844|table 1|210|%s\n' "$REASON" > "${TMP}/phonewide/baseline.txt"
run_gate phonewide
want_green "45: an overflow equal to its row" "WARN: baselined sideways scroll: light /: at 390x844 table 1 is 210 px wider than its box"
want_said "45b: and counted" "no new sideways scroll at 1280x800 and 390x844 (1 baselined)"
printf 'sideways|light|/|390x844|table 1|209|%s\n' "$REASON" > "${TMP}/phonewide/baseline.txt"
run_gate phonewide
want_red "46: an overflow above its row" "FAIL: light /: scrolls sideways at 390x844: table 1 is 210 px wider than its box, above the recorded 209 px (grew)"
printf 'sideways|light|/|390x844|table 1|211|%s\n' "$REASON" > "${TMP}/phonewide/baseline.txt"
run_gate phonewide
want_red "47: an overflow below its row" "FAIL: light /: scrolls sideways at 390x844: table 1 is 210 px wider than its box, below the recorded 211 px: shrink the row"
printf 'sideways|light|/|390x844|table 1|210|%s\nsideways|light|/|1280x800|table 1|5|%s\n' "$REASON" "$REASON" > "${TMP}/phonewide/baseline.txt"
run_gate phonewide
want_red "48: a row whose overflow is gone" "FAIL: stale baseline row: sideways|light|/|1280x800|table 1|5 no longer scrolls sideways; remove it"
printf 'sideways|light|/|390x844|table 1|210|\n' > "${TMP}/phonewide/baseline.txt"
run_gate phonewide
want_exit "49a: a sideways row without a reason" 2 "has no reason"
printf 'sideways|light|/|390x844|table 1|0|%s\n' "$REASON" > "${TMP}/phonewide/baseline.txt"
run_gate phonewide
want_exit "49b: a px that is no positive whole number" 2 "must be a positive whole number of pixels"
printf 'sideways|light|/|800x600|table 1|210|%s\n' "$REASON" > "${TMP}/phonewide/baseline.txt"
run_gate phonewide
want_exit "49c: a viewport the gate does not measure" 2 "is not a viewport the gate measures"
printf 'sideways|light|/|390x844|table 1|210|%s\nsideways|light|/|390x844|table 1|210|%s\n' "$REASON" "$REASON" > "${TMP}/phonewide/baseline.txt"
run_gate phonewide
want_exit "49d: a sideways row listed twice" 2 "listed twice"
: > "${TMP}/phonewide/baseline.txt"

# 50: the CLS interval starts at the load, before the document and axe checks
# (forsgren#377). Those take as long as the machine takes: a hosted runner was
# slow enough that a 1 ms read, started after axe, saw a shift 500 ms after the
# load (proof K). The page reports a shift when it is read after axe ran.
: > "${TMP}/readorder/baseline.txt"
run_gate readorder
want_green "50: the CLS is read before the axe run, not after it" "OK:"

# 51: the same table, a page scrollbar of 15 px: the overflow is the table's
# width less the window's, 210 px, with or without the scrollbar (forsgren#377).
run_gate scrollbar
want_red "51: a page scrollbar does not change the measurement" "FAIL: light /: scrolls sideways at 390x844: table 1 is 210 px wider than its box"

# 52-53: the browser is closed and its profile removed on every way out
# (forsgren#381): a signal to the wrapper or to node, and an error.
# A slow fixture (forty looks, minutes of work) keeps the gate busy; the signal
# comes once the gate's profile folder exists and a page is open in its Chrome,
# not after a delay: on a fast machine a delay outlasted the whole run
# (forsgren#383). Every Chrome here is found by its own case's profile folder.
make_site slow "$(page '' '')"
: > "${TMP}/slow/variants.txt"
for n in $(seq 1 40); do printf 'look%s|scheme:light\n' "$n" >> "${TMP}/slow/variants.txt"; done

# node_pid: the engine of the signal cases (its command line names the slow site).
node_pid() {
  pgrep -f -- "node .*mjs ${TMP}/slow/site" | head -1 || true
}

# engine_up <dir>: the run is provably mid-run: the profile folder of the case
# exists and Chrome holds a connection to the engine's own server, i.e. it is
# loading a fixture page. That happens only after puppeteer.launch resolved and
# the engine's Chrome watch is attached; the renderer of Chrome's first
# about:blank page (the old condition) exists during the launch (forsgren#386).
# A fixture page cannot reach a listener of the test (the engine blocks every
# request that leaves its own server, and answers the exception row of a
# blocked one without sending it), so the connection to the engine's server is
# the hit that can be observed.
engine_up() {
  local npid
  [[ -n "$(find "$1" -maxdepth 1 -name 'browser-gate-*' 2> /dev/null)" ]] || return 1
  npid="$(node_pid)"
  [[ -n "$npid" ]] || return 1
  lsof -nP -a -p "$npid" -iTCP -sTCP:ESTABLISHED 2> /dev/null | has -q ESTABLISHED
}

# launch_up <dir>: the profile of the case's Chrome has its Local Storage
# folder, the last thing Chrome's start creates (measured: about 15 ms after
# puppeteer.launch resolved with no initial page to wait for, 4 of 4 kills with
# it ended in 30 s on the v5 engine; with the first helper process or the
# Local State file as the condition the kill came before the connection and
# ended in 1 s, so they are no proof). The kill comes with the launch over or
# nearly over, and no page exists.
launch_up() {
  [[ -n "$(find "$1" -maxdepth 3 -path '*/browser-gate-*/Default/Local Storage' 2> /dev/null)" ]]
}

# real_chrome: the Chrome the engine finds (FORSGREN_CHROME, else its candidates).
real_chrome() {
  local candidate
  if [[ -n "${FORSGREN_CHROME:-}" ]]; then
    echo "$FORSGREN_CHROME"
    return
  fi
  for candidate in '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' /usr/bin/google-chrome /usr/bin/google-chrome-stable /usr/bin/chromium /usr/bin/chromium-browser; do
    if [[ -e "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done
}

# signal_case <label> <target: self|node> <signal|error|launch> <command...>:
# runs the command on the slow fixture with its own TMPDIR, waits until it is
# up (engine_up; for launch: launch_up) for up to 60 s, sends the signal to the
# command (self) or to the node process under it (node), or kills the Chrome
# (error, launch), then waits for the end. Sets SIG_RC, SIG_CHROME (alive, polled
# up to 60 s), SIG_PROFILE (folders left), SIG_UP, SIG_EARLY (the gate had ended
# before the signal), SIG_ENDED, SIG_WAITED (the bound, SIG_WAIT_S or 60 s) and SIG_OUT.
signal_case() {
  local label="$1" target="$2" sig="$3" tmpd pid target_pid up=engine_up
  shift 3
  if [[ "$sig" == "launch" ]]; then up=launch_up; fi
  tmpd="${TMP}/sig_${label}"
  mkdir -p "$tmpd"
  TMPDIR="$tmpd" perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' "$@" "${TMP}/slow/site" "${TMP}/slow/manifest.json" "${TMP}/slow/exceptions.txt" "${TMP}/slow/baseline.txt" "${TMP}/slow/variants.txt" > "${tmpd}.out" 2>&1 &
  pid=$!
  SIG_UP=0
  for _ in $(seq 1 300); do
    if "$up" "$tmpd"; then
      SIG_UP=1
      break
    fi
    sleep 0.2
  done
  SIG_EARLY=0
  if [[ "$SIG_UP" -eq 1 ]] && ! kill -0 "$pid" 2> /dev/null; then SIG_EARLY=1; fi
  target_pid="$pid"
  if [[ "$target" == "node" ]]; then
    target_pid="$(node_pid)"
    if [[ -z "$target_pid" ]]; then target_pid="$pid"; fi
  fi
  if [[ "$SIG_UP" -eq 0 || "$SIG_EARLY" -eq 1 ]]; then
    : # no signal: the verdict names the missing precondition
  elif [[ "$sig" == "error" || "$sig" == "launch" ]]; then
    pkill -9 -f -- "--user-data-dir=${tmpd}/browser-gate-" || true
  else
    kill -s "$sig" "$target_pid" || true
  fi
  SIG_ENDED=1
  SIG_WAITED="${SIG_WAIT_S:-60}"
  for _ in $(seq 1 $((SIG_WAITED * 5))); do
    if ! kill -0 "$pid" 2> /dev/null; then break; fi
    sleep 0.2
  done
  if kill -0 "$pid" 2> /dev/null; then
    SIG_ENDED=0
    kill -9 "$pid" || true
  fi
  wait "$pid" 2>/dev/null && SIG_RC=0 || SIG_RC=$?
  # Chrome gone: one poll of the condition itself, up to 60 s, not a fixed
  # window (a fixed 10 s was a clock, forsgren#386).
  for _ in $(seq 1 300); do
    if ! pgrep -f -- "--user-data-dir=${tmpd}/browser-gate-" > /dev/null; then break; fi
    sleep 0.2
  done
  SIG_CHROME="$({ pgrep -f -- "--user-data-dir=${tmpd}/browser-gate-" || true; } | wc -l | tr -d ' ')"
  SIG_PROFILE="$(find "$tmpd" -maxdepth 1 -name 'browser-gate-*' | wc -l | tr -d ' ')"
  SIG_OUT="$(cat "${tmpd}.out")"
  # Whatever a failed case left behind is ours (found by its folder): clean up.
  pkill -9 -f -- "--user-data-dir=${tmpd}/browser-gate-" || true
  rm -rf "$tmpd"
}

# closed_verdict: "" when the last signal_case ended with status $1 and left no
# Chrome and no profile folder, else the reason.
closed_verdict() {
  if [[ "$SIG_UP" -ne 1 ]]; then
    echo "the gate was not mid-run 60 s after its start (no profile folder, or no connection from Chrome to its server)"
  elif [[ "$SIG_EARLY" -eq 1 ]]; then
    echo "the gate ended before the signal was sent"
  elif [[ "$SIG_ENDED" -ne 1 ]]; then
    echo "the gate was still running ${SIG_WAITED} s after the signal"
  elif [[ "$SIG_RC" != "$1" ]]; then
    echo "expected exit $1, got ${SIG_RC}"
  elif [[ "$SIG_CHROME" -ne 0 ]]; then
    echo "${SIG_CHROME} Chrome processes of the gate are still alive"
  elif [[ "$SIG_PROFILE" -ne 0 ]]; then
    echo "the profile folder is still there"
  fi
}

# want_closed <case> <rc>: the last signal_case is closed_verdict-clean.
want_closed() {
  local why
  why="$(closed_verdict "$2")"
  if [[ -n "$why" ]]; then
    fail "$1: ${why}. Output: ${SIG_OUT}"
  else
    echo "  ok: $1"
  fi
}

# want_left <case> <rc> <reason>: the last signal_case is NOT clean, for that
# reason (the mutation proofs: red BECAUSE of the line mutated).
want_left() {
  local why
  why="$(closed_verdict "$2")"
  if [[ "$why" == *"$3"* ]]; then
    echo "  ok: $1"
  else
    fail "$1: wanted the reason '$3', got '${why}'. Output: ${SIG_OUT}"
  fi
}

signal_case term_wrapper self TERM "$GATE"
want_closed "52a: SIGTERM to the wrapper closes Chrome, removes the profile, exits 143" 143
signal_case term_node node TERM "$GATE"
want_closed "52b: SIGTERM to node under the wrapper: the same, exit 143" 143
signal_case int_wrapper self INT "$GATE"
want_closed "52c: SIGINT to the wrapper: exit 130" 130
signal_case hup_wrapper self HUP "$GATE"
want_closed "52d: SIGHUP to the wrapper: exit 129" 129
signal_case term_engine self TERM node "$ENGINE"
want_closed "52e: SIGTERM to the engine run by itself: exit 143" 143
signal_case kill_node node KILL "$GATE"
if [[ "$SIG_UP" -ne 1 || "$SIG_EARLY" -eq 1 ]]; then
  fail "52f: the signal was not sent while the gate ran: $(closed_verdict 0)"
elif [[ "$SIG_CHROME" -eq 0 ]]; then
  echo "  ok: 52f: SIGKILL to node cannot be handled, but Chrome ends with its pipe"
else
  fail "52f: ${SIG_CHROME} Chrome processes outlived a killed node"
fi
signal_case chrome_killed self error "$GATE"
want_closed "53: Chrome killed mid-run is an error (exit 2) and leaves no Chrome and no profile" 2

# 53c: Chrome killed while the run starts (forsgren#386, browser_gate v6): a
# Chrome that opens no initial page (FORSGREN_CHROME, the engine's own setting)
# is killed once its helpers run. The engine used to wait 30 s for that page
# whatever happened to Chrome; now its watch is on from the launch, so the run
# ends within seconds with the usual error.
NOWINDOW_CHROME="${TMP}/nowindow_chrome.sh"
printf '#!/bin/sh\nexec "%s" "$@" --no-startup-window\n' "$(real_chrome)" > "$NOWINDOW_CHROME"
chmod +x "$NOWINDOW_CHROME"
SIG_WAIT_S=15 signal_case chrome_killed_launch self launch env "FORSGREN_CHROME=${NOWINDOW_CHROME}" "$GATE"
want_closed "53c: Chrome killed during the launch ends the run within 15 s: exit 2, no Chrome, no profile" 2
if ! grep -qE "Chrome (ended|disconnected) during the run|Target closed" <<< "$SIG_OUT"; then
  fail "53c: the usual error is missing. Output: ${SIG_OUT}"
fi

# Mutation proofs: the engine copy is run directly, with the real node_modules.
MUT="${TMP}/mutants"
run_mutant() {
  FORSGREN_NODE_ROOT="$REPO_ROOT" capture env -u FORSGREN_CLS_LOADS -u FORSGREN_CLS_INTERVAL_MS node "$1" "${TMP}/$2/site" "${TMP}/$2/manifest.json" "${TMP}/$2/exceptions.txt" "${TMP}/$2/baseline.txt" "${TMP}/$2/variants.txt"
}

# A: only critical gates -> the serious fixture turns green.
if selftest_mutant "$ENGINE" "${MUT}/a.mjs" "s/\['serious', 'critical'\]/['critical']/"; then
  run_mutant "${MUT}/a.mjs" serious
  want_green "mutation proof A: ignoring serious turns case 2 green" "OK:"
fi

# B: the CLS compared rounded -> a growth of 0.1 percent turns green (case 19).
printf 'cls|light|/|%s|%s\n' "$(scaled 0.999)" "$REASON" > "${TMP}/shift/baseline.txt"
if selftest_mutant "$ENGINE" "${MUT}/b.mjs" "s/^const compared = .*/const compared = (value) => Math.round(value * 100);/"; then
  run_mutant "${MUT}/b.mjs" shift
  want_green "mutation proof B: a rounded CLS comparison turns case 19 green" "OK:"
fi

# C: a 404 read only from network-failure events -> case 7 no longer says 404.
if selftest_mutant "$ENGINE" "${MUT}/c.mjs" "s/page.on('response'/page.on('response-ignored'/"; then
  run_mutant "${MUT}/c.mjs" notfound
  if grep -qF -- "request /missing.png -> 404" <<< "$OUT"; then
    fail "mutation proof C: the 404 was still named without the response status. Output: ${OUT}"
  else
    echo "  ok: mutation proof C: without the response status case 7 loses its 404"
  fi
fi

# D: the baseline match ignores the selector -> a new element on a baselined
# rule turns green. The fixture is case 17's: only #a is in the baseline.
printf 'axe|light|/|color-contrast|#a|%s\n' "$REASON" > "${TMP}/two/baseline.txt"
if selftest_mutant "$ENGINE" "${MUT}/d.mjs" 's/^\(const axeKey = .*\)[$]{selector}\(.*\)$/\1\2/'; then
  run_mutant "${MUT}/d.mjs" two
  want_green "mutation proof D: ignoring the selector turns case 17 green" "OK:"
fi

# E: the stale check removed -> a baselined finding that is gone turns green.
printf 'axe|light|/|color-contrast|#a|%s\naxe|light|/|color-contrast|#b|%s\naxe|light|/|color-contrast|#gone|%s\n' "$REASON" "$REASON" "$REASON" > "${TMP}/two/baseline.txt"
if selftest_mutant "$ENGINE" "${MUT}/e.mjs" "s/if (!row.seen)/if (false \&\& !row.seen)/"; then
  run_mutant "${MUT}/e.mjs" two
  want_green "mutation proof E: without the stale check case 18 turns green" "OK:"
fi

# F: an attr: variant not applied -> the dark look is never checked, case 30 green.
: > "${TMP}/themed/baseline.txt"
if selftest_mutant "$ENGINE" "${MUT}/f.mjs" "s/if (variant.attr) await/if (false \&\& variant.attr) await/"; then
  run_mutant "${MUT}/f.mjs" themed
  want_green "mutation proof F: an unapplied attr: variant turns case 30 green" "OK:"
fi

# G: the scheme not emulated per variant -> case 33 turns green.
if selftest_mutant "$ENGINE" "${MUT}/g.mjs" "s/value: variant.scheme/value: 'light'/"; then
  run_mutant "${MUT}/g.mjs" schemed
  want_green "mutation proof G: an unemulated scheme turns case 33 green" "OK:"
fi

# H: the override ignored -> the 50 ms of case 37 is not read.
if selftest_mutant "$ENGINE" "${MUT}/h.mjs" "s/envPositive('FORSGREN_CLS_INTERVAL_MS', 1000)/1000/"; then
  FORSGREN_CLS_LOADS=2 FORSGREN_CLS_INTERVAL_MS=50 FORSGREN_NODE_ROOT="$REPO_ROOT" capture node "${MUT}/h.mjs" "${TMP}/clean/site" "${TMP}/clean/manifest.json" "${TMP}/clean/exceptions.txt" "${TMP}/clean/baseline.txt" "${TMP}/clean/variants.txt"
  if grep -qF -- "interval 50 ms" <<< "$OUT"; then
    fail "mutation proof H: the override was still read. Output: ${OUT}"
  else
    echo "  ok: mutation proof H: an ignored override loses case 37's 50 ms"
  fi
fi

# I: the default interval changed -> case 15 loses its 1000 ms.
if selftest_mutant "$ENGINE" "${MUT}/i.mjs" "s/envPositive('FORSGREN_CLS_INTERVAL_MS', 1000)/envPositive('FORSGREN_CLS_INTERVAL_MS', 500)/"; then
  run_mutant "${MUT}/i.mjs" clean
  if grep -qF -- "interval 1000 ms" <<< "$OUT"; then
    fail "mutation proof I: the default interval was still 1000 ms. Output: ${OUT}"
  else
    echo "  ok: mutation proof I: a changed default interval loses case 15's 1000 ms"
  fi
fi

# J: the default loads changed -> case 8a loses its 5 cold loads.
if selftest_mutant "$ENGINE" "${MUT}/j.mjs" "s/envPositive('FORSGREN_CLS_LOADS', 5)/envPositive('FORSGREN_CLS_LOADS', 3)/"; then
  run_mutant "${MUT}/j.mjs" shift
  if grep -qF -- "largest of 5 cold loads" <<< "$OUT"; then
    fail "mutation proof J: the default was still 5 loads. Output: ${OUT}"
  else
    echo "  ok: mutation proof J: a changed default load count loses case 8a's 5 cold loads"
  fi
fi

# K: a layout-shift case given a too short setting turns green: why cases 8 and
# 19-23 keep the real values. Ordered by the test, not by the clock (forsgren#252,
# #275, #384): the fixture moves one tick after the gate's first read of the
# shifts, so the 1 ms read is before the shift on any machine, however long the
# load or the gate's own work took. K asserts the reason: the short setting is
# the one the gate ran with (the OK line says 1 ms) and the same code moving two
# frames after the load is red on the real setting, so only the setting hid it.
: > "${TMP}/lateshift/baseline.txt"
FORSGREN_CLS_LOADS=1 FORSGREN_CLS_INTERVAL_MS=1 capture "$GATE" "${TMP}/lateshift/site" "${TMP}/lateshift/manifest.json" "${TMP}/lateshift/exceptions.txt" "${TMP}/lateshift/baseline.txt" "${TMP}/lateshift/variants.txt"
want_green "mutation proof K: a shift case on a too short setting turns green" "interval 1 ms)"
run_gate_real earlyshift
want_red "mutation proof K, control: the same code moving after the load, on the real setting, is red" "CLS 0."
# K with a delayed load (forsgren#275): the 1 ms read still misses the shift
# that follows the read, whatever the load took.
: > "${TMP}/lateshiftslow/baseline.txt"
FORSGREN_CLS_LOADS=1 FORSGREN_CLS_INTERVAL_MS=1 capture "$GATE" "${TMP}/lateshiftslow/site" "${TMP}/lateshiftslow/manifest.json" "${TMP}/lateshiftslow/exceptions.txt" "${TMP}/lateshiftslow/baseline.txt" "${TMP}/lateshiftslow/variants.txt"
want_green "mutation proof K, delayed load: a 1 ms read still misses the shift" "interval 1 ms)"

# L: the sideways-scroll check removed -> case 41 turns green.
if selftest_mutant "$ENGINE" "${MUT}/l.mjs" "s/^    await check.checkSideways();/    \/\/ removed/"; then
  run_mutant "${MUT}/l.mjs" phonewide
  want_green "mutation proof L: without the sideways-scroll check case 41 turns green" "OK:"
fi

# M: the comparison loosened -> an overflow of 210 px passes, case 41 turns green.
if selftest_mutant "$ENGINE" "${MUT}/m.mjs" "s/^const scrollsSideways = .*/const scrollsSideways = (px) => px > 1000;/"; then
  run_mutant "${MUT}/m.mjs" phonewide
  want_green "mutation proof M: a loosened comparison turns case 41 green" "OK:"
fi

# N: the growth comparison dropped -> case 46 turns green.
printf 'sideways|light|/|390x844|table 1|209|%s\n' "$REASON" > "${TMP}/phonewide/baseline.txt"
if selftest_mutant "$ENGINE" "${MUT}/n.mjs" "s/^    if (px > row.px) {/    if (false) {/"; then
  run_mutant "${MUT}/n.mjs" phonewide
  want_green "mutation proof N: without the growth comparison case 46 turns green" "OK:"
fi

# O: the stale check of the sideways rows removed -> case 48 turns green.
printf 'sideways|light|/|390x844|table 1|210|%s\nsideways|light|/|1280x800|table 1|5|%s\n' "$REASON" "$REASON" > "${TMP}/phonewide/baseline.txt"
if selftest_mutant "$ENGINE" "${MUT}/o.mjs" "s/if (!row.seen) findings.push(\`FAIL: stale baseline row: \${row.key}|\${row.text} no longer/if (false) findings.push(\`FAIL: stale baseline row: \${row.key}|\${row.text} no longer/"; then
  run_mutant "${MUT}/o.mjs" phonewide
  want_green "mutation proof O: without the sideways stale check case 48 turns green" "OK:"
fi
: > "${TMP}/phonewide/baseline.txt"

# P: the CLS read moved back after the axe run (the order before forsgren#377)
# -> case 50 turns red. Asserted the other way round: the mutant is red on it.
if selftest_mutant "$ENGINE" "${MUT}/p.mjs" "s/^    await check.checkLayoutShift();/    \/\/ moved/;s/^    await check.checkAxe();/    await check.checkAxe(); await check.checkLayoutShift();/"; then
  FORSGREN_NODE_ROOT="$REPO_ROOT" FORSGREN_CLS_LOADS="$SHORT_CLS_LOADS" FORSGREN_CLS_INTERVAL_MS="$SHORT_CLS_INTERVAL_MS" capture node "${MUT}/p.mjs" "${TMP}/readorder/site" "${TMP}/readorder/manifest.json" "${TMP}/readorder/exceptions.txt" "${TMP}/readorder/baseline.txt" "${TMP}/readorder/variants.txt"
  want_red "mutation proof P: a CLS read after the axe run turns case 50 red" "CLS 0.5"
fi

# Q: the page scrollbar not taken away while measuring -> case 51 says 225.
if selftest_mutant "$ENGINE" "${MUT}/q.mjs" "s/^  html.style.setProperty('scrollbar-gutter', 'auto', 'important');/  \/\/ kept/"; then
  run_mutant "${MUT}/q.mjs" scrollbar
  want_said "mutation proof Q: with the scrollbar kept, case 51 measures 225 px" "table 1 is 225 px wider than its box"
fi

# R: no signal handler in the engine (the event name is one no signal sends) ->
# a SIGTERM kills the engine; Chrome ends with its pipe, the profile stays.
if selftest_mutant "$ENGINE" "${MUT}/r.mjs" "s/process.on(name, /process.on(name + 'x', /"; then
  signal_case mutant_r self TERM env FORSGREN_NODE_ROOT="$REPO_ROOT" node "${MUT}/r.mjs"
  want_left "mutation proof R: without the handler case 52e leaves the profile" 143 "the profile folder is still there"
fi

# S: the wrapper does not forward the signal -> it ends, node and Chrome stay.
WMUT="${TMP}/wmut"
mkdir -p "${WMUT}/Scripts"
cp Scripts/browser_gate.mjs Scripts/lib_site_settings.sh "${WMUT}/Scripts/"
ln -s "${REPO_ROOT}/node_modules" "${WMUT}/node_modules"
if selftest_mutant Scripts/gate_browser.sh "${WMUT}/Scripts/gate_browser.sh" 's/if \[\[ -n "[$]NODE_PID" \]\]; then/if false; then/'; then
  signal_case mutant_s self TERM "${WMUT}/Scripts/gate_browser.sh"
  want_left "mutation proof S: without forwarding case 52a leaves Chrome alive" 143 "Chrome processes of the gate are still alive"
fi

echo "browser gate self-test: ${SECONDS} s in total"
selftest_end "the browser gate self-test failed" "browser gate: every case holds, nineteen mutations seen"
