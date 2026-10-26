#!/usr/bin/env bash
# canon: test_gate_browser_process v1
# Scripts/test_gate_browser_process.sh (forsgren#386, decision #411 A)
#
# The second self-test of the browser gate (Scripts/gate_browser.sh): the exits,
# split from the browser gate self-test (its checks) so a race in a process case no longer
# hides its forty deterministic cases, and the selector can skip it when only
# the checks of the gate changed. Run in PRE, after that self-test, in the same
# job. The real Chrome, never a fake: Chrome closed and its profile folder
# removed on every way out (forsgren#381, browser_gate v5, v6 since
# forsgren#386):
#  52. SIGTERM, SIGINT, SIGHUP to the wrapper, SIGTERM to node (under the wrapper
#      and alone) -> exit 143, 130, 129; no Chrome, no profile folder; SIGKILL
#      to node -> Chrome ends with its pipe
#      (52a SIGTERM wrapper, 52b SIGTERM node under the wrapper, 52c SIGINT,
#      52d SIGHUP, 52e SIGTERM engine alone, 52f SIGKILL node)
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
# Mutation proofs (each fixture is red BECAUSE of the line mutated):
#   R. no signal handler in the engine: case 52e leaves the profile folder;
#   S. the wrapper not forwarding the signal: case 52a leaves Chrome alive.
# There is no mutation proof for case 53c (forsgren#443). Proof U, the old engine
# with waitForInitialPage: true kept running in case 53c, went: it raced on a
# hosted runner, where the kill marker (the profile folder) can come before
# Chrome connects, so even the old engine ended at once. Case 53c stays as a pin;
# it was seen failing against the v5 engine when it was written (forsgren#386).
# Each ok and FAIL line ends with the seconds since the line before it, the
# case's own duration (Scripts/lib_gate_browser_selftest.sh).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
GATE="${REPO_ROOT}/Scripts/gate_browser.sh"
ENGINE="${REPO_ROOT}/Scripts/browser_gate.mjs"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
# shellcheck source=Scripts/lib_gate_browser_selftest.sh
source Scripts/lib_gate_browser_selftest.sh
selftest_begin "browser gate process self-test"

browser_selftest_require "$GATE" "$ENGINE" \
  "${REPO_ROOT}/node_modules/puppeteer-core" "${REPO_ROOT}/node_modules/axe-core"

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
  for candidate in '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
    /usr/bin/google-chrome /usr/bin/google-chrome-stable /usr/bin/chromium /usr/bin/chromium-browser; do
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
  TMPDIR="$tmpd" perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' "$@" "${TMP}/slow/site" "${TMP}/slow/manifest.json" \
    "${TMP}/slow/exceptions.txt" "${TMP}/slow/baseline.txt" "${TMP}/slow/variants.txt" > "${tmpd}.out" 2>&1 &
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
FORWARD='s/if \[\[ -n "[$]NODE_PID" \]\]; then/if false; then/'
if selftest_mutant Scripts/gate_browser.sh "${WMUT}/Scripts/gate_browser.sh" "$FORWARD"; then
  signal_case mutant_s self TERM "${WMUT}/Scripts/gate_browser.sh"
  want_left "mutation proof S: without forwarding case 52a leaves Chrome alive" 143 \
    "Chrome processes of the gate are still alive"
fi

echo "browser gate process self-test: ${SECONDS} s in total"
selftest_end "the browser gate process self-test failed" \
  "browser gate: every exit closes Chrome and removes the profile, two mutations seen"
