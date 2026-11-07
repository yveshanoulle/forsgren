#!/usr/bin/env bash
# canon: test_gate_browser_process v7
# v7 (forsgren#642): case 53k, a launch that fails before Chrome's process is seen ending (its pipe closed first, as a dying Chrome's is read on Linux, where 53j got TargetCloseError in Quality run 42406819133) still names the death, Chrome's last lines on stderr and then the launch's own error (browser_gate v19)
# v6 (forsgren#642): Linux. A signal case's TMPDIR is a folder of its own straight under the temp root (tmp_dir), its output under TMP: under TMP/sig_<label> the path of Chrome's singleton socket, which on Linux lies in the profile, passed the 107 characters of a Unix socket and Chrome aborted (SIGABRT) during the launch; the singleton folders are asserted where the platform puts them (own_place_why: in the profile on Linux, outside it on macOS), the decoy of another Chrome lies in the shared temp folder on Linux, and proof V asserts on Linux that the folders go with the profile; case 53j: a Chrome that dies during the launch is named with its last lines on stderr (browser_gate v18); proofs S and Sb copy the libraries the wrapper sources, read from it
# v5 (forsgren#636): case 53f and mutation proof D moved to the canon browser gate self-test (Scripts/test_gate_browser.sh v29, as case 53f and proof Dh), so the sites test browser_gate v17 too; this self-test keeps what is forsgren's own: the exits on forty looks (52a-52f, 53, 53c), the singleton folders of forsgren#613 and the proofs V, W, R, Rb, S and Sb
# v4 (forsgren#630, step 2): case 53f, Chrome killed during the launch while a helper of its group holds its pipe (and its command pipe is a FIFO nobody writes, so the launch is surely still on), ends the run within 10 s with `FAIL: browser gate: Chrome died during the launch (PID <pid>, exit <code> | signal <signal>)`, no Chrome, no profile (browser_gate v17); mutation proof D, the engine not hearing Chrome's process end, keeps the run going past the 10 s; proof S asserts only the Chrome it leaves alive, never whether node still held the pipe (timing: at load ~6 node had closed it in 2 of 3 runs), each branch of the wait within 10 s, and proof Sb forces the branch of a closed pipe (SIG_HOLDER_GONE)
# v3 (forsgren#630): a signal case waits for its Chrome with wait_chrome_gone (lib_gate_browser_selftest v2): 10 s while the node holding its pipe is alive, up to 60 s once the pipe's other end is closed, a bound hit named with the PIDs left, the node and the seconds; proof R runs with its Chrome stalled for 15 s, proof Rb shows the bound named, proof S that node still holds the pipe
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
#      60 s to be gone once its pipe closed (10 s while node still holds it, v3):
#      observable conditions, never a fixed window (forsgren#384, forsgren#630).
#  53j. Chrome aborts during the launch -> exit 2, the FAIL naming the death
#      (PID, SIGABRT) and quoting Chrome's last lines on stderr (browser_gate v18)
#  53k. Chrome closes its pipe during the launch and lives on (the launch's error
#      comes first) -> the same FAIL, then the launch's own error (browser_gate v19)
#  54. The singleton folders of Chrome (forsgren#613): on macOS Chrome makes
#      com.google.Chrome.XXXXXX (SingletonCookie, SingletonSocket) in the system
#      temp folder, whatever TMPDIR says, and a killed Chrome leaves them (on
#      Linux .com.google.Chrome.XXXXXX in its TMPDIR, the profile, v6). Every
#      case above finds the folders of ITS Chrome through the SingletonSocket
#      link of its profile (read while the run is up), removes exactly those
#      after the end, and is red on one still there (the folders are named). A
#      decoy folder of "another Chrome", made beside them, must still be there.
# Mutation proofs (each fixture is red BECAUSE of the line mutated):
#   V. no cleanup of the singleton folders: a killed Chrome (cases 53, 53c) leaves
#      them (named); a Chrome ended by a signal removes its own;
#   W. a cleanup too wide also removes the decoy of another Chrome: red;
#   R. no signal handler in the engine: case 52e leaves the profile folder;
#   S. the wrapper not forwarding the signal: case 52a leaves Chrome alive.
# Case 53f (Chrome killed during the launch while a helper holds its pipe) and
# its proof, D here up to v4, are in the canon browser gate self-test
# (Scripts/test_gate_browser.sh, case 53f and proof Dh, forsgren#636).
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

# own_chrome_dirs <dir>: the singleton folders of the Chrome whose profile is in
# <dir> (forsgren#613): the folder of the target of the profile's SingletonSocket
# link. Found through that profile, which belongs to the process the case
# launched, never by a glob over the system temp folder.
own_chrome_dirs() {
  local link
  while IFS= read -r link; do
    if [[ -n "$link" ]]; then dirname "$(readlink "$link")"; fi
  done < <(find "$1" -maxdepth 2 -path '*/browser-gate-*/SingletonSocket' -type l 2> /dev/null)
}

# chrome_cleanup <mode>: removes the singleton folders recorded in SIG_OWN.
# own: those folders and nothing else; none and wide are the mutants V and W.
chrome_cleanup() {
  local dir
  case "$1" in
    own)
      while IFS= read -r dir; do
        if [[ -n "$dir" ]]; then rm -rf "$dir"; fi
      done <<< "$SIG_OWN"
      ;;
    wide)
      # a cleanup that is too wide: also takes the decoy (a real one would take
      # every folder of the same name pattern; the proof never touches those)
      while IFS= read -r dir; do
        if [[ -n "$dir" ]]; then rm -rf "$dir"; fi
      done <<< "$SIG_OWN"
      rm -rf "$SIG_FOREIGN"
      ;;
  esac
}

# signal_case <label> <target: self|node> <signal|error|launch> <command...>:
# runs the command on the slow fixture with its own TMPDIR, waits until it is
# up (engine_up; for launch: launch_up) for up to 60 s,
# sends the signal to the command (self) or to the node process under it
# (node), or kills the Chrome (error, launch), then waits for the end. Sets SIG_RC, SIG_CHROME (alive after
# wait_chrome_gone, v3), SIG_PROFILE (folders left), SIG_UP, SIG_EARLY (the gate had ended
# before the signal), SIG_OWN (the singleton folders of its Chrome, forsgren#613),
# SIG_LEFT (those still there after the cleanup SIG_CLEANUP: own, none, wide),
# SIG_FOREIGN_GONE (the decoy of another Chrome was removed), SIG_ENDED, SIG_WAITED (the bound, SIG_WAIT_S or 60 s) and SIG_OUT.
# The case's TMPDIR is a folder of its own straight under the temp root, its
# output under TMP (v6, forsgren#642): on Linux Chrome binds its singleton socket
# at <TMPDIR>/.com.google.Chrome.XXXXXX/SingletonSocket, and the engine gives
# Chrome the profile as TMPDIR, so the socket path is the case's TMPDIR plus 62
# characters. A Unix socket path holds at most 107, and under ${TMP}/sig_<label>
# it was 127 or more: Chrome ends itself on that during the launch (LOG(FATAL)
# "Socket path too long", chrome/browser/process_singleton_posix.cc), seen as
# SIGABRT in every case here. macOS puts the socket in its own temp folder,
# whatever TMPDIR says, so the length never showed there. SIG_TMPD is the
# case's TMPDIR, for own_place_why.
signal_case() {
  local label="$1" target="$2" sig="$3" dir first tmpd out pid target_pid up=engine_up
  shift 3
  if [[ "$sig" == "launch" ]]; then up=launch_up; fi
  tmpd="$(tmp_dir "sig_${label}")"
  SIG_TMPD="$tmpd"
  out="${TMP}/sig_${label}.out"
  TMPDIR="$tmpd" perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' "$@" "${TMP}/slow/site" "${TMP}/slow/manifest.json" \
    "${TMP}/slow/exceptions.txt" "${TMP}/slow/baseline.txt" "${TMP}/slow/variants.txt" > "$out" 2>&1 &
  pid=$!
  SIG_UP=0
  for _ in $(seq 1 300); do
    if "$up" "$tmpd"; then
      SIG_UP=1
      break
    fi
    sleep 0.2
  done
  SIG_OWN=""
  SIG_FOREIGN=""
  if [[ "$SIG_UP" -eq 1 ]]; then
    SIG_OWN="$(own_chrome_dirs "$tmpd")"
    if [[ -n "$SIG_OWN" ]]; then
      first="$(head -1 <<< "$SIG_OWN")"
      # The decoy lies where another Chrome's folder would: beside this one on
      # macOS, in the shared temp folder on Linux, where this one is in the profile.
      SIG_FOREIGN="${first%.*}.foreign$$"
      if [[ "$first" == "$tmpd"/* ]]; then SIG_FOREIGN="$(dirname "$tmpd")/$(basename "${first%.*}").foreign$$"; fi
      mkdir -p "$SIG_FOREIGN"
    fi
  fi
  SIG_EARLY=0
  if [[ "$SIG_UP" -eq 1 ]] && ! kill -0 "$pid" 2> /dev/null; then SIG_EARLY=1; fi
  target_pid="$pid"
  if [[ "$target" == "node" ]]; then
    target_pid="$(node_pid)"
    if [[ -z "$target_pid" ]]; then target_pid="$pid"; fi
  fi
  SIG_STALLED=0
  SIG_PIPE_HOLDER=""
  if [[ "$SIG_UP" -eq 1 ]]; then SIG_PIPE_HOLDER="$(chrome_parent "$tmpd")"; fi
  if [[ "$SIG_UP" -eq 0 || "$SIG_EARLY" -eq 1 ]]; then
    : # no signal: the verdict names the missing precondition
  elif [[ "$sig" == "error" || "$sig" == "launch" ]]; then
    pkill -9 -f -- "--user-data-dir=${tmpd}/browser-gate-" || true
  else
    stall_chrome "$tmpd"
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
  # SIG_HOLDER_GONE=1 (proof Sb, forsgren#630): the wait takes the branch of a
  # pipe whose other end is closed, as when node closed it before the wait began.
  if [[ "${SIG_HOLDER_GONE:-0}" -eq 1 ]]; then SIG_PIPE_HOLDER=""; fi
  # Chrome gone: the condition itself, not a fixed window (a fixed 10 s was a
  # clock, forsgren#386), within named bounds (wait_chrome_gone, v3, forsgren#630).
  wait_chrome_gone "$tmpd"
  SIG_CHROME="$({ pgrep -f -- "--user-data-dir=${tmpd}/browser-gate-" || true; } | wc -l | tr -d ' ')"
  SIG_PROFILE="$(find "$tmpd" -maxdepth 1 -name 'browser-gate-*' | wc -l | tr -d ' ')"
  SIG_OUT="$(cat "$out")"
  # Whatever a failed case left behind is ours (found by its folder): clean up.
  pkill -9 -f -- "--user-data-dir=${tmpd}/browser-gate-" || true
  rm -rf "$tmpd"
  chrome_cleanup "${SIG_CLEANUP:-own}"
  SIG_LEFT=""
  while IFS= read -r dir; do
    if [[ -n "$dir" && -e "$dir" ]]; then SIG_LEFT+="${dir} "; fi
  done <<< "$SIG_OWN"
  SIG_FOREIGN_GONE=0
  if [[ -n "$SIG_FOREIGN" ]]; then
    if [[ ! -e "$SIG_FOREIGN" ]]; then SIG_FOREIGN_GONE=1; fi
    rm -rf "$SIG_FOREIGN"
  fi
}

# own_place_why: "" when the singleton folders of the last signal_case are where
# Chrome puts them on this platform (v6, forsgren#642), else the reason. On Linux
# Chrome follows TMPDIR, which the engine sets to the profile, so they are in the
# profile and go with it; on macOS they are in the system temp folder, outside it.
own_place_why() {
  local first
  first="$(head -1 <<< "$SIG_OWN")"
  if [[ "$(uname -s)" == "Linux" && "$first" != "$SIG_TMPD"/browser-gate-* ]]; then
    echo "on Linux the singleton folder of the case's Chrome should be in its profile (Chrome's TMPDIR), found at ${first}"
  elif [[ "$(uname -s)" != "Linux" && "$first" == "$SIG_TMPD"/* ]]; then
    echo "on macOS the singleton folder of the case's Chrome should be in the system temp folder, found at ${first}"
  fi
}

# closed_verdict: "" when the last signal_case ended with status $1 and left no
# Chrome and no profile folder, else the reason.
closed_verdict() {
  if [[ "$SIG_UP" -ne 1 ]]; then
    echo "the gate was not mid-run 60 s after its start (no profile folder, or no connection from Chrome to its server)"
  elif [[ "$SIG_EARLY" -eq 1 ]]; then
    echo "the gate ended before the signal was sent"
  elif [[ -n "$(stall_why)" ]]; then
    stall_why
  elif [[ "$SIG_ENDED" -ne 1 ]]; then
    echo "the gate was still running ${SIG_WAITED} s after the signal"
  elif [[ "$SIG_RC" != "$1" ]]; then
    echo "expected exit $1, got ${SIG_RC}"
  elif [[ "$SIG_CHROME" -ne 0 ]]; then
    chrome_alive_why "$SIG_CHROME"
  elif [[ "$SIG_PROFILE" -ne 0 ]]; then
    echo "the profile folder is still there"
  elif [[ -z "$SIG_OWN" ]]; then
    echo "no singleton folder of the case's Chrome was found (the SingletonSocket link of its profile)"
  elif [[ -n "$(own_place_why)" ]]; then
    own_place_why
  elif [[ "$SIG_FOREIGN_GONE" -ne 0 ]]; then
    echo "the folder of another Chrome was removed with the singleton folders"
  elif [[ -n "$SIG_LEFT" ]]; then
    echo "singleton folders of the case's Chrome are still there: ${SIG_LEFT}"
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
if ! grep -qE "Chrome (ended|disconnected) during the run|Chrome died during the launch|Target closed" <<< "$SIG_OUT"; then
  fail "53c: the usual error is missing. Output: ${SIG_OUT}"
fi

# 53j (forsgren#642, browser_gate v18): a Chrome that dies during the launch is
# named with its own last lines on stderr. On Linux a Chrome LOG(FATAL) ends it
# (seen as SIGABRT) and says why only there (a singleton socket path too long, the
# signal cases of v5). A fake Chrome writes two lines and aborts itself.
ABORT_CHROME="${TMP}/abort_chrome.sh"
printf '#!/bin/sh\necho "a first line of the fake Chrome" >&2\necho "[1:1:FATAL:fake.cc(1)] Check failed: the fake reason" >&2\nkill -ABRT $$\n' > "$ABORT_CHROME"
chmod +x "$ABORT_CHROME"
ABORT_RC=0
ABORT_OUT="$(FORSGREN_CHROME="$ABORT_CHROME" "$GATE" "${TMP}/slow/site" "${TMP}/slow/manifest.json" \
  "${TMP}/slow/exceptions.txt" "${TMP}/slow/baseline.txt" "${TMP}/slow/variants.txt" 2>&1)" || ABORT_RC=$?
ABORT_WANTED="FAIL: browser gate: Chrome died during the launch \(PID [0-9]+, signal SIGABRT\)
Chrome's last lines on stderr:
  a first line of the fake Chrome
  \[1:1:FATAL:fake.cc\(1\)\] Check failed: the fake reason"
if [[ "$ABORT_RC" -ne 2 ]]; then
  fail "53j: a Chrome that aborts during the launch should end the run with exit 2, got ${ABORT_RC}. Output: ${ABORT_OUT}"
elif [[ ! "$ABORT_OUT" =~ $ABORT_WANTED ]]; then
  fail "53j: the FAIL line should name the death and quote Chrome's last lines on stderr. Output: ${ABORT_OUT}"
else
  echo "  ok: 53j: a Chrome that aborts during the launch is named with its last lines on stderr"
fi

# 53k (forsgren#642, browser_gate v19): the launch's own error comes before
# Chrome's 'exit'. On Linux the closed pipe of a dying Chrome was read first,
# puppeteer.launch rejected with TargetCloseError and 53j saw no death and no
# stderr (Quality run 42406819133). This fake closes its pipe (fds 3 and 4)
# after its two lines and lives on, so the launch fails first on any platform;
# puppeteer then ends it (SIGKILL to its group). The FAIL names the death and
# Chrome's lines, then the launch's own error.
CLOSE_CHROME="${TMP}/close_chrome.sh"
printf '#!/bin/sh\necho "a first line of the fake Chrome" >&2\necho "the fake Chrome closes its pipe" >&2\nexec 3>&- 4>&-\nsleep 10\n' > "$CLOSE_CHROME"
chmod +x "$CLOSE_CHROME"
CLOSE_RC=0
CLOSE_OUT="$(FORSGREN_CHROME="$CLOSE_CHROME" "$GATE" "${TMP}/slow/site" "${TMP}/slow/manifest.json" \
  "${TMP}/slow/exceptions.txt" "${TMP}/slow/baseline.txt" "${TMP}/slow/variants.txt" 2>&1)" || CLOSE_RC=$?
CLOSE_WANTED="FAIL: browser gate: Chrome died during the launch \(PID [0-9]+, signal SIGKILL\)
Chrome's last lines on stderr:
  a first line of the fake Chrome
  the fake Chrome closes its pipe
The launch's own error, which came first: [^
]+"
if [[ "$CLOSE_RC" -ne 2 ]]; then
  fail "53k: a Chrome whose pipe closes before its process ends should end the run with exit 2, got ${CLOSE_RC}. Output: ${CLOSE_OUT}"
elif [[ ! "$CLOSE_OUT" =~ $CLOSE_WANTED ]]; then
  fail "53k: the FAIL line should name the death, quote Chrome's last lines on stderr and the launch's own error. Output: ${CLOSE_OUT}"
else
  echo "  ok: 53k: a launch that fails before Chrome's process ends still names the death, its last lines on stderr and the launch's error"
fi

# Mutation proofs: the engine copy is run directly, with the real node_modules.
MUT="${TMP}/mutants"

# V: no cleanup of the singleton folders -> the case names the folders it left
# (this test then removes them itself).
# On Linux the folders are in the profile (own_place_why), which the engine
# removes, so the same run is closed without the cleanup: that is asserted
# there, the folders named in the profile (v6, forsgren#642).
SIG_CLEANUP=none signal_case mutant_v self error "$GATE"
if [[ "$(uname -s)" == "Linux" ]]; then
  want_closed "mutation proof V (Linux): without the cleanup a killed Chrome still leaves no singleton folder: they are in its profile, removed with it" 2
else
  want_left "mutation proof V: without the cleanup a killed Chrome leaves its singleton folders" 2 \
    "singleton folders of the case's Chrome are still there"
fi
for left in $SIG_LEFT; do rm -rf "$left"; done

# W: a cleanup too wide -> the decoy of another
# Chrome goes with them.
SIG_CLEANUP=wide signal_case mutant_w self TERM "$GATE"
want_left "mutation proof W: a cleanup too wide also removes the folder of another Chrome" 143 \
  "the folder of another Chrome was removed"

# R: no signal handler in the engine (the event name is one no signal sends) ->
# a SIGTERM kills the engine; Chrome ends with its pipe, the profile stays. Its
# Chrome is stalled for 15 s past the engine's end (v3, forsgren#630), as a machine
# at load ~100 delayed it: the wait must follow Chrome's end.
if selftest_mutant "$ENGINE" "${MUT}/r.mjs" "s/process.on(name, /process.on(name + 'x', /"; then
  SIG_STALL_CHROME=15 signal_case mutant_r self TERM env FORSGREN_NODE_ROOT="$REPO_ROOT" node "${MUT}/r.mjs"
  want_left "mutation proof R: without the handler case 52e leaves the profile" 143 "the profile folder is still there"
  # Rb (v3, forsgren#630): a bound hit is a FAIL that names what it waited for. The
  # same engine with a bound of 3 s and a Chrome stalled for 8 s: the reason names
  # the PIDs left, the node whose pipe end closed and the 3 s.
  SIG_STALL_CHROME=8 SIG_GONE_BOUND=3 signal_case mutant_rb self TERM env FORSGREN_NODE_ROOT="$REPO_ROOT" node "${MUT}/r.mjs"
  RB_WHY="$(closed_verdict 143)"
  RB_WANTED='Chrome processes of the gate are still alive 3 s after the gate ended, the other end of their pipe \(node PID [0-9]+\) closed: PIDs [0-9]+'
  if [[ "$RB_WHY" =~ $RB_WANTED ]]; then
    echo "  ok: mutation proof Rb: a Chrome alive past the bound is named with its PIDs, its pipe's node and the 3 s waited"
  else
    fail "mutation proof Rb: a Chrome alive past the bound of 3 s should be named with its PIDs, its pipe's node and the seconds, got '${RB_WHY}'. Output: ${SIG_OUT}"
  fi
fi

# S: the wrapper does not forward the signal -> it ends, node and Chrome stay.
# What the mutation causes is Chrome left alive; whether node still holds the
# pipe when the wait begins is timing (at load ~6 node had closed it in 2 of 3
# runs), so S asserts only the Chrome left, in both branches of the wait, each
# within 10 s (SIG_GONE_BOUND as proof Rb sets it). Sb forces the branch of a
# closed pipe (SIG_HOLDER_GONE) so that branch is proved on every run.
WMUT="${TMP}/wmut"
mkdir -p "${WMUT}/Scripts"
cp Scripts/browser_gate.mjs "${WMUT}/Scripts/"
# The libraries the wrapper sources, read from it, so a library it gains comes
# along (forsgren#642: lib_browser_baseline.sh).
while IFS= read -r lib; do cp "$lib" "${WMUT}/Scripts/"; done < <(sed -n 's#^source \(Scripts/lib_[a-z_]*\.sh\)$#\1#p' Scripts/gate_browser.sh)
ln -s "${REPO_ROOT}/node_modules" "${WMUT}/node_modules"
FORWARD='s/if \[\[ -n "[$]NODE_PID" \]\]; then/if false; then/'
if selftest_mutant Scripts/gate_browser.sh "${WMUT}/Scripts/gate_browser.sh" "$FORWARD"; then
  SIG_GONE_BOUND=10 signal_case mutant_s self TERM "${WMUT}/Scripts/gate_browser.sh"
  want_left "mutation proof S: without forwarding case 52a leaves Chrome alive" 143 \
    "Chrome processes of the gate are still alive"
  SIG_HOLDER_GONE=1 SIG_GONE_BOUND=10 signal_case mutant_sb self TERM "${WMUT}/Scripts/gate_browser.sh"
  want_left "mutation proof Sb: without forwarding case 52a leaves Chrome alive, the pipe's other end closed" 143 \
    "Chrome processes of the gate are still alive"
fi

echo "browser gate process self-test: ${SECONDS} s in total"
selftest_end "the browser gate process self-test failed" \
  "browser gate: every exit closes Chrome, removes the profile and the singleton folders of its Chrome, six mutations seen"
