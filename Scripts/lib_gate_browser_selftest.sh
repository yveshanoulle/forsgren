#!/usr/bin/env bash
# canon: lib_gate_browser_selftest v2
# v2 (forsgren#630): the wait for a signal case's Chrome on the signal itself, its pipe's other end closed or still held, within named bounds (wait_chrome_gone, chrome_alive_why), and the stall of proof R (stall_chrome, stall_why)
# Scripts/lib_gate_browser_selftest.sh
#
# What the two browser gate self-tests share (forsgren#386, decision #411 A):
# the browser gate self-test (the checks of the gate) and the browser gate
# process self-test (the exits: signals and a killed Chrome). Once, so the two
# cannot drift: the seconds on every case line, the check that the gate and its
# dependencies exist, the clean fixture page and the fixture site around it.
#
# SOURCED, never run, after Scripts/lib_selftest.sh and before selftest_begin.
# It sets no shell options. It defines `echo` (see below), so a script that
# sources it reports through that.
#
# Needs from the sourcing self-test: TMP (selftest_begin) for make_site.

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

# browser_selftest_require <path>...: every path exists, else the self-test
# stops with one red naming the first that is missing (the gate under test, the
# engine, puppeteer-core and axe-core from npm ci).
browser_selftest_require() {
  local need
  for need in "$@"; do
    if [[ ! -e "$need" ]]; then
      selftest_abort "${SELFTEST_WHAT}: ${need} is missing"
    fi
  done
}

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

# stall_chrome <tmpd> (forsgren#630): when SIG_STALL_CHROME is above 0, stops the
# Chrome of the signal case whose TMPDIR is <tmpd> and continues it that many
# seconds later, so it sees its pipe close only then, as a CPU-starved machine
# (load ~100) let it. Called right before the signal. SIG_STALLED is 1 when a
# Chrome was stopped; stall_why says why the case proves nothing when a stall was
# asked for and no Chrome could be stopped, else "".
SIG_STALL_CHROME=0
SIG_STALLED=0
stall_chrome() {
  SIG_STALLED=0
  if [[ "$SIG_STALL_CHROME" -gt 0 ]] && pkill -STOP -f -- "--user-data-dir=${1}/browser-gate-"; then
    SIG_STALLED=1
    ( sleep "$SIG_STALL_CHROME"; pkill -CONT -f -- "--user-data-dir=${1}/browser-gate-" || true ) > /dev/null 2>&1 &
  fi
}
stall_why() {
  if [[ "$SIG_STALL_CHROME" -gt 0 && "$SIG_STALLED" -ne 1 ]]; then
    echo "its Chrome could not be stopped for the stall of ${SIG_STALL_CHROME} s, so a slow end of Chrome is not proved"
  fi
}

# chrome_main <tmpd>: the PID of the main Chrome process of the case (the one
# without --type=), empty when it is gone. chrome_parent <tmpd>: its parent, the
# node process that launched it and holds the other end of its pipe.
chrome_main() {
  { ps -A -o pid=,command= || true; } | { grep -F -e "--user-data-dir=${1}/browser-gate-" || true; } | { grep -v -F -e ' --type=' || true; } | awk 'NR == 1 {print $1}'
}
chrome_parent() {
  local main
  main="$(chrome_main "$1")"
  if [[ -n "$main" ]]; then
    { ps -o ppid= -p "$main" || true; } | tr -d ' '
  fi
}

# wait_chrome_gone <tmpd>: waits, once the gate has ended, until no Chrome process
# of the case is left (v2, forsgren#630). Chrome ends by itself when the other end
# of its pipe closes; on a machine at load ~100 that took more than the fixed 10 s
# of v26, and proof R flaked. So it waits for the signal itself, the processes
# gone, within two bounds:
#  - while the node process that holds the pipe (SIG_PIPE_HOLDER, Chrome's parent
#    before the signal) is still Chrome's parent and alive, Chrome cannot see its
#    pipe close: SIG_HELD_BOUND (10 s) for node to close it, then the reason names
#    that node (proof S);
#  - once the pipe's other end is closed, SIG_GONE_BOUND (60 s); hit, the reason
#    names the PIDs still alive, the node whose pipe end closed and the seconds
#    (proof Rb).
# SIG_GONE_WHY is "" when every process ended, else the words for closed_verdict.
SIG_HELD_BOUND=10
SIG_GONE_BOUND=60
wait_chrome_gone() {
  local tmpd="$1" start=$SECONDS parent
  SIG_GONE_WHY=""
  while pgrep -f -- "--user-data-dir=${tmpd}/browser-gate-" > /dev/null; do
    parent="$(chrome_parent "$tmpd")"
    if [[ -n "$SIG_PIPE_HOLDER" && "$parent" == "$SIG_PIPE_HOLDER" ]] && kill -0 "$parent" 2> /dev/null; then
      if (( SECONDS - start >= SIG_HELD_BOUND )); then
        SIG_GONE_WHY=", their pipe still held by node PID ${parent} after ${SIG_HELD_BOUND} s"
        return 0
      fi
    elif (( SECONDS - start >= SIG_GONE_BOUND )); then
      SIG_GONE_WHY=" ${SIG_GONE_BOUND} s after the gate ended, the other end of their pipe (node PID ${SIG_PIPE_HOLDER:-not found}) closed: PIDs $({ pgrep -f -- "--user-data-dir=${tmpd}/browser-gate-" || true; } | tr '\n' ' ' | sed 's/ $//')"
      return 0
    fi
    sleep 0.2
  done
}
# chrome_alive_why <count>: the reason of a case whose <count> Chrome processes
# outlived the wait, with what wait_chrome_gone saw (SIG_GONE_WHY).
chrome_alive_why() {
  echo "${1} Chrome processes of the gate are still alive${SIG_GONE_WHY}"
}
