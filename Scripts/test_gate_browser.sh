#!/usr/bin/env bash
# canon: test_gate_browser v33
# v33 (forsgren#660, the owner's ruling, option A): the real-Chrome signal cases run with Chrome's code-sign clone off (--disable-features=MacAppCodeSignClone, merged into the one --disable-features Chrome is given, through the wrapper chrome_no_clone.sh) and the engine looks at an empty folder of the case, so they no longer read the folder every Chrome on the machine shares: a clone folder of anyone else cannot change their verdict. closed_verdict asserts instead that the clone is off for this Chrome: its own command line has one --disable-features naming the feature and no --enable-features naming it, and the installed Chrome still knows the feature; a missing, overridden or unknown flag is a reason, never a return to the shared folder. Case 53g keeps its clone assertions on a parent of the test; 53h and 53i are unchanged; case 53j pins the check
# v32 (forsgren#642): case 54b says why its replaced folder is a new one on Linux too: ext4 hands the freed inode of the removed folder to the new one, so the engine compares the birth time as well (browser_gate v19); on the first Linux run the folder was taken for the identified one and removed (Quality run 42406819133)
# v31 (forsgren#642): a signal case's TMPDIR is a folder of its own straight under the temp root (mktemp), its side files under TMP: on Linux Chrome's singleton socket lies in the profile, and under TMP/sig_<label> its path passed the 107 characters of a Unix socket, so Chrome aborted (SIGABRT) during the launch; proof S copies the libraries the wrapper sources, read from it
# v30 adds (forsgren#641): --shard N/M runs only the cases and proofs that Scripts/lib_isolation_shard.sh deals to shard N of M by the seconds of Scripts/browser_gate_selftest_weights.txt (case 8 with 19 to 21 and proof B, which read the CLS it measures; the cases of SERIAL_CASES with the proofs R, Rb, S, X, Z and Dh, one unit), so a CI can run it in several jobs, every case in exactly one; --list prints the cases and proofs a run would start, one per line, and stops before it needs Chrome; without --shard every case runs, as before; a repository without the library refuses --shard (exit 64)
# v29 adds (forsgren#636): case 53f, Chrome killed during the launch while a helper of its process group holds its pipe (its command pipe a FIFO nobody writes, so the launch is surely still on), ends the run within 10 s with `FAIL: browser gate: Chrome died during the launch (PID <pid>, exit <code> | signal <signal>)`, no Chrome, no profile (browser_gate v17); mutation proof Dh, the engine not hearing Chrome's process end, still runs 10 s after the kill; moved from the browser gate process self-test (its v4 case 53f and proof D), so the sites test the engine's newest behaviour; a signal case may take a bound of its own (SIG_WAIT_S, 20 s by default), named in its reason; the file names no path that only forsgren has (a comment named the process self-test's path, and a site's script-references gate, which reads comments, found it unresolved)
# v28 fixes (forsgren#630, step 2): proof S asserts the Chrome the mutation leaves alive, never whether node still held its pipe when the wait began (timing: at load ~6 node had closed it in 2 of 3 runs, and the proof failed with Chrome alive); either branch of the wait ends within 10 s (SIG_GONE_BOUND, as proof Rb sets its bound)
# v27 fixes (forsgren#630, step 1): a signal case waits for its Chrome to end on the signal itself, not for a fixed 10 s: while the node that holds Chrome's pipe is alive 10 s (SIG_HELD_BOUND), once the pipe's other end is closed up to 60 s (SIG_GONE_BOUND), and a bound hit is named (the PIDs still alive, the node whose pipe end closed, the seconds); proof R runs with its Chrome stalled for 15 s (SIG_STALL_CHROME: stopped before the signal, continued after), which turned v26 red as load ~100 did; proof Rb shows the bound named, proof S that Chrome stays because node still holds its pipe
# v26 runs the plain cases side by side (forsgren#632): each is a case_<id> function started through Scripts/lib_parallel_mutants.sh, on its own copy of its fixtures in its own folder, writing the files its case needs and judged for its own reason; two batches (the cases, then 19 to 21, 55a to 55c and the mutation proofs), and between them only the cases of the named list SERIAL_CASES (the signal, kill and timing cases and their proofs R, S, X, Z) one after the other; the log shows the seconds of each batch
# v25 fixes (forsgren#629, CI red, 53e): case 53e kills Chrome only after its load seam has installed the slowdowns and marked the end of the launch (SIG_WAIT_READY, FORSGREN_TEST_READY_MARK); v24 still killed it once a renderer showed, which on a fast hosted runner came inside the launch, so the seam never ran and 'hooked' and 'reaping' were never observed
# v24 fixes (forsgren#629, CI red): the cases that kill Chrome after the launch (53d, 54b, 54c) wait for a mark their seam makes once the engine's launch is over and, for 54b and 54c, once the clone folder is swapped or added (FORSGREN_TEST_READY_MARK, SIG_WAIT_READY); v23 killed as soon as a renderer showed, which on a fast hosted runner came inside the launch or before the 800 ms timer of the swap; a missing mark says the case proves nothing
# v23 adds (estate issue 629, step 2): cases 55a, 55b and 55c, a gate that ends non-zero always says why: the findings after 1 MiB of output arrive whole, an uncaught error in the engine is a named FAIL line (exit 2), an engine killed by a signal is named by the wrapper
# v22 writes the proofs R, S, X and Z as mutant functions started with mutant_run (forsgren#629 step 1), each one alone and collected before the next, because they drive signal cases that share the machine's Chrome and clone folders; without the library they still run one after the other
# v21 folds in the sites' v20 (site issue 63): case 54a, a helper of the gate's Chrome still ending at removal time is waited for and the clone folder removed; case 54b, a clone folder replaced after the launch, and 54c, a new clone folder that is not the identified one, are kept and the reason said (browser_gate v14); the seam cases take a signal, an exit and extra lines of the fake Chrome
# v19 merges the two lines of the canon (estate issue 629): forsgren's v12 (the cases and proofs of browser_gate v6 to v8: the watch from the start, the delayed-delivery load, the paint wait; the side-by-side proofs; the shared helpers) and the sites' v13 to v18 (the cases 52a to 53i of the exits and the proofs R, S, T, U with the seams of browser_gate v9 to v12); the sites' proofs T and U are X and Z here, because T and U are the delayed-delivery proofs; the helper libraries are used when the repository has them, else defined here
# v18 fixes (site issue 61, second part): the real-Chrome cases no longer fail when another Chrome starts on the machine meanwhile (the gate then rightly keeps the clone folders): they require a kept folder to be said on stderr; the removal and the keep are proved on a folder and a process listing of the test (cases 53h, 53i; engine seams of browser_gate v12), and mutation proof T goes through case 53h; case 53g is also judged as a closed run
# v18 fixes (site issue 61):case 53e's slowdowns never took effect (puppeteer.launch on a module namespace cannot be assigned, the engine removes folders with fs.promises.rm, not rmSync); the engine now calls a seam module (browser_gate v12), the file-system slowdown patches fs.promises.rm, the case fails unless each slowdown was marked as seen, and mutation proof U shows a dead seam turns it red
# v17 fixes (estate issue 617): the clone cleanup of signal_case (remove_new_clones) no longer ends the self-test silently when the new folder is already gone (grep -v finding nothing under pipefail aborted the run before proofs R, S and T); cases 52h and 52i pin it on a fake folder, and a folder that cannot be removed still fails
# v16 adds (estate issue 617): every signal_case also proves the code-sign clone folder Chrome makes on macOS (about 1.4 GB, left by a killed Chrome) is removed after its Chrome is gone; case 53g, a clone folder of another Chrome that appears during the launch and is held open by a process of the test is left untouched, and the gate keeps its own folder too, saying so on stderr
# v15 adds (site issue 60): case 53e, a loaded machine (slow reaping, a close() that never answers, a slow file system) slows only the gate; a killed Chrome still ends the run at once
# v13 adds (site issue 59): cases 52g and 53d, a Chrome helper that outlives the browser and writes into the profile
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
# Mutation proofs (each fixture is red BECAUSE of the line mutated; they run side by
# side through Scripts/lib_parallel_mutants.sh, forsgren#382, each on its own copy of
# the fixture and of the engine):
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
# The delayed-delivery load (forsgren#611, decision C on #611, browser_gate v7):
# besides its full-response loads, every page gets one cold load whose HTML the
# server sends in 4 pieces 150 ms apart, so the browser paints a page before it
# has all of it, as a slow runner does now and then (forsgren#558). The fixture
# is a table whose last rows are wider than its first, so a paint before they
# arrive is followed by a shift; it is small enough to arrive in one piece when
# sent whole.
#  54. the table page with the first-paint hold (link rel=expect, blocking=render,
#      to an element at the end)                       -> green, CLS 0, the OK
#                                                         line names the delivery
#  55. the same page without the hold                  -> red, the CLS named with
#                                                         the delayed-delivery load
#  56. the hold pointing at an id the page lacks        -> green (the hold then
#      lasts to the end of the parse)
#   T. the delayed-delivery load removed: case 55 turns green;
#   U. the pieces sent without the pause between them: case 55 turns green;
#   Y. the wait for the paint removed (forsgren#620): case 57 turns green.
#  57. the same page with a main thread busy past all the pieces (a slow runner)
#      -> red as 55: the server waits for the paint between pieces (browser_gate v8)
# The exits (forsgren#381, site issue 34): Chrome closed and its profile folder
# removed on every way out:
#  52. SIGTERM, SIGINT, SIGHUP to the wrapper, SIGTERM to node (under the wrapper
#      and alone) -> exit 143, 130, 129; no Chrome, no profile folder; SIGKILL
#      to node -> Chrome ends with its pipe
#  53. Chrome killed mid-run (an error) -> exit 2; no Chrome, no profile folder
#  52g, 53d (site issue 59). The same with a Chrome helper that outlives the
#      browser and keeps writing into the profile folder: no profile left
#  52h, 52i (estate issue 617). The cleanup of the clone folders on a folder of
#      the test: survives a vanished folder, removes only the new one, fails on
#      one that cannot be removed
#  53g (estate issue 617). Nothing ties a code-sign clone folder to its Chrome,
#      so a second folder appearing during the launch (another Chrome's) makes
#      the gate keep both and say so; the other folder is untouched (macOS only;
#      elsewhere there is no such folder), on a parent of the test (v33). The
#      other real-Chrome cases run with the clone off and assert that it is off.
#  53j (forsgren#660). The check that the clone is off, without a browser: a
#      missing, repeated or overridden flag and a feature this Chrome does not
#      know each give a reason, and closed_verdict is red on it
#  53h, 53i (site issue 61). Who owns a clone folder, decided on a folder and a
#      process listing of the test (FORSGREN_GATE_CLONE_PARENT and
#      FORSGREN_GATE_PS_LISTING of browser_gate v12)
#  53e (site issue 60). A loaded machine slows only the gate (browser_gate v12's
#      FORSGREN_GATE_BROWSER_HOOK); a killed Chrome still ends the run at once;
#      the kill waits for the seam's mark of the end of the launch (v25)
#  53f (forsgren#630, here since v29, forsgren#636). Chrome killed during the
#      launch while a helper of its process group holds its pipe -> exit 2
#      within 10 s, a FAIL naming the death during the launch with Chrome's PID
#      and exit status; no Chrome, no profile folder (browser_gate v17)
#   R. no signal handler in the engine: case 52e leaves the profile folder, with
#      its Chrome stalled for 15 s past the engine's end (v27, forsgren#630);
#   Rb. the same with a bound of 3 s: the reason names the Chrome PIDs left, the
#      node whose pipe end closed and the 3 s (v27);
#   S. the wrapper not forwarding the signal: case 52a leaves Chrome alive, its
#      pipe still held by node;
#   X. (the sites' proof T) the clone folder never removed: case 53h leaves it;
#   Z. (the sites' proof U) the engine never calls the seam: case 53e's marker
#      is missing;
#   Dh. (the process self-test's proof D up to its v4; D here is the baseline
#      selector) the engine not hearing Chrome's process end during the launch:
#      case 53f still runs 10 s after the kill (v29).
# SHARDS (v30, forsgren#641). `--shard N/M` (1 <= N <= M) runs the units dealt to
# shard N: each plain case and each side-by-side proof is a unit, except 19, 20,
# 21 and proof B, which follow case 8 (they compare with the CLS it measures);
# the cases of SERIAL_CASES with their proofs R, Rb, S, X, Z and Dh are one unit,
# `serial`. The units are dealt as Scripts/lib_isolation_shard.sh deals the
# isolation self-tests: by their seconds (Scripts/browser_gate_selftest_weights.txt),
# the heaviest first, each to the shard that weighs least so far, so every case
# runs in exactly one shard, the shards weigh about the same and a new case lands
# in one by itself. The phases keep their order in every shard. `--list` prints
# the cases and proofs the run would start (case_<id>, mutant_<id>, serial_<id>),
# one per line, and stops before anything needs Chrome; Scripts/test_quality_jobs.sh
# holds the shards together to every case once. A bad argument is exit 64.
# These cases and R, Rb, S, X, Z, Dh run one after the other (SERIAL_CASES, v26); every
# other case and proof runs side by side, see "The plain cases" below. forsgren's
# own browser gate process self-test (only forsgren has it, so this canon names
# no path of it, forsgren#636: the cases 52a-52f, 53 and 53c on forty looks and the
# singleton folders of forsgren#613) runs the exits again in its own job, so a
# race in a process case does not hide the checks above. Each ok and FAIL line
# ends with the seconds since the line before it when
# Scripts/lib_gate_browser_selftest.sh is there (forsgren#386).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
GATE="${REPO_ROOT}/Scripts/gate_browser.sh"
ENGINE="${REPO_ROOT}/Scripts/browser_gate.mjs"

usage() {
  echo "usage: test_gate_browser.sh [--shard N/M] [--list]  (1 <= N <= M)" >&2
  exit 64
}
SHARD_N=""
SHARD_M=""
LIST_ONLY=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --shard)
      [[ "$#" -ge 2 && -z "$SHARD_N" && "$2" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]] || usage
      SHARD_N="${BASH_REMATCH[1]}"
      SHARD_M="${BASH_REMATCH[2]}"
      [[ "$SHARD_N" -le "$SHARD_M" ]] || usage
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    *) usage ;;
  esac
done

# The cases and proofs of each phase, in the order they start. The first batch
# starts the slow real-setting and two-variant cases first, so it does not end on
# one of them; 19 to 21 wait for case 8's M and 55a to 55c are defined further
# down, so they start in the second batch, with the mutation proofs. SERIAL_CASES
# (see there) and their proofs run one after the other between and after them.
FIRST_CASES=(8 1 31 32 33 34 30 23 22
  2 3 4 5 6 7 9 10 11 12 13 14 16 17 18 24a 24b 24c 24d 24e 24f 25
  26 27 28 29 35a 35b 35c 35d 35e 35f 36a 36b 36c 37 38 38b 40 39a 39b
  41 42 43 44 45 46 47 48 49a 49b 49c 49d 50 51 54 55 56 57)
SECOND_CASES=(19 20 21 55a 55b 55c)
SECOND_PROOFS=(a b c d e f g h i j k kslow l m n o p q t u y)
SERIAL_CASES=(52h 52i 53j 52a 52b 52c 52d 52e 52f 53 52g 53d 53g 53h 53i 54a 54b 54c 53e 53f)
SERIAL_PROOFS=(r rb s x z dh)
# SHARD_FOLLOWERS: "<unit> <the cases and proofs that run in its shard>" (v30).
SHARD_FOLLOWERS=("case_8 case_19 case_20 case_21 mutant_b")

# is_follower <id>: the id runs in the shard of another unit.
is_follower() {
  local entry
  for entry in "${SHARD_FOLLOWERS[@]}"; do
    [[ " ${entry#* } " == *" $1 "* ]] && return 0
  done
  return 1
}
# shard_units: the units, in start order: the side-by-side cases and proofs that
# follow no other, then serial.
shard_units() {
  local id
  for id in "${FIRST_CASES[@]}" "${SECOND_CASES[@]}"; do
    is_follower "case_${id}" || echo "case_${id}"
  done
  for id in "${SECOND_PROOFS[@]}"; do
    is_follower "mutant_${id}" || echo "mutant_${id}"
  done
  echo serial
}
# unit_ids <unit>: the cases and proofs the unit starts.
unit_ids() {
  local entry
  if [[ "$1" == serial ]]; then
    printf 'serial_%s\n' "${SERIAL_CASES[@]}"
    printf 'mutant_%s\n' "${SERIAL_PROOFS[@]}"
    return 0
  fi
  echo "$1"
  for entry in "${SHARD_FOLLOWERS[@]}"; do
    if [[ "${entry%% *}" == "$1" ]]; then
      tr ' ' '\n' <<< "${entry#* }"
    fi
  done
}
# all_ids: every case and proof of the whole run, from the phase lists alone.
all_ids() {
  printf 'case_%s\n' "${FIRST_CASES[@]}" "${SECOND_CASES[@]}"
  printf 'mutant_%s\n' "${SECOND_PROOFS[@]}"
  printf 'serial_%s\n' "${SERIAL_CASES[@]}"
  printf 'mutant_%s\n' "${SERIAL_PROOFS[@]}"
}
if [[ -n "$SHARD_N" ]]; then
  if [[ ! -f Scripts/lib_isolation_shard.sh ]]; then
    echo "test_gate_browser.sh: --shard needs Scripts/lib_isolation_shard.sh, which this repository does not have" >&2
    exit 64
  fi
  # shellcheck source=Scripts/lib_isolation_shard.sh
  source Scripts/lib_isolation_shard.sh
  if ! SHARD_DEALT="$(shard_units | shard_assign "$SHARD_N" "$SHARD_M" Scripts/browser_gate_selftest_weights.txt)"; then
    echo "❌ FAIL: browser gate self-test: the shards cannot be dealt (see the line above)" >&2
    exit 1
  fi
  RUN_IDS="$(while IFS= read -r unit; do
    if [[ -n "$unit" ]]; then unit_ids "$unit"; fi
  done <<< "$SHARD_DEALT")"
else
  RUN_IDS="$(all_ids)"
fi
if [[ "$LIST_ONLY" -eq 1 ]]; then
  printf '%s\n' "$RUN_IDS" | grep . || true
  exit 0
fi
# runs <id>: this run starts the case or proof.
runs() {
  [[ $'\n'"${RUN_IDS}"$'\n' == *$'\n'"$1"$'\n'* ]]
}

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# The helpers shared with the browser gate process self-test, and the side-by-side
# mutants, are in their own files in forsgren; a repository without a file gets
# the same behaviour here, and a line says so.
if [[ -f Scripts/lib_gate_browser_selftest.sh ]]; then
  # shellcheck source=Scripts/lib_gate_browser_selftest.sh
  source Scripts/lib_gate_browser_selftest.sh
  GATE_BROWSER_LIB=1
else
  GATE_BROWSER_LIB=0
fi
if [[ -f Scripts/lib_parallel_mutants.sh ]]; then
  # shellcheck source=Scripts/lib_parallel_mutants.sh
  source Scripts/lib_parallel_mutants.sh
  PARALLEL_LIB=1
else
  PARALLEL_LIB=0
  # Without the library the proofs run one after the other, each in a subshell
  # as the library runs it (a MUTANT_DIR of its own, its status read back).
  MUTANT_ROOT=""
  MUTANT_N=0
  mutants_init() {
    MUTANT_ROOT="$1/mutants"
    rm -rf "$MUTANT_ROOT"
    mkdir -p "$MUTANT_ROOT"
    MUTANT_N=0
  }
  mutant_run() {
    local status
    MUTANT_N=$((MUTANT_N + 1))
    export MUTANT_DIR="${MUTANT_ROOT}/m${MUTANT_N}"
    mkdir -p "$MUTANT_DIR"
    set +e
    (
      failed=0
      "$@"
      exit "$failed"
    )
    status=$?
    set -e
    if [[ "$status" -ne 0 ]]; then
      failed=1
    fi
  }
  mutants_wait() { :; }
fi
selftest_begin "browser gate self-test"

if [[ "$GATE_BROWSER_LIB" -eq 0 ]]; then
  echo "  skipped: Scripts/lib_gate_browser_selftest.sh not in this repository (its helpers are defined in this file)"
  LAP=$SECONDS
  browser_selftest_require() {
    local need
    for need in "$@"; do
      if [[ ! -e "$need" ]]; then
        selftest_abort "browser gate self-test: ${need} is missing"
      fi
    done
  }
  # page <body-extra> <head-extra> [doctype] [charset]: a clean page, one part changed.
  page() {
    local body="$1" head="$2" doctype="${3-<!doctype html>}" charset="${4-<meta charset=\"utf-8\">}"
    cat << HTML
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
  # The wait for a signal case's Chrome and the stall of proof R (v27, forsgren#630).
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
  # of the case is left (v27, forsgren#630). Chrome ends by itself when the other end
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
  # chrome_alive_why <count>: the reason of a case whose <count> Chrome processes
  # outlived the wait, with what wait_chrome_gone saw (SIG_GONE_WHY).
  chrome_alive_why() {
    echo "${1} Chrome processes of the gate are still alive${SIG_GONE_WHY}"
  }
fi
if [[ "$PARALLEL_LIB" -eq 0 ]]; then
  echo "  skipped: Scripts/lib_parallel_mutants.sh not in this repository (the plain cases and the mutation proofs run one after the other)"
fi

browser_selftest_require "$GATE" "$ENGINE" \
  "${REPO_ROOT}/node_modules/puppeteer-core" "${REPO_ROOT}/node_modules/axe-core"

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

# The plain cases run side by side (forsgren#632), through the runner of the
# mutation proofs (Scripts/lib_parallel_mutants.sh): each is a case_<id> function,
# started by plain_case (mutant_run), that works on its own copy of the fixtures
# it names (own_fixtures: under its own $MUTANT_DIR, which TMP then points at for
# the rest of the case, a subshell), writes the files its case needs into that
# copy, and is judged for its own reason. The fixtures under $FIXTURES are made
# once, at the top level, and no case changes them. Up to v25 the cases ran one
# after the other on shared fixtures, each leaving its files for the next (about
# 876 s on a site). Only the cases of SERIAL_CASES (see there) run one after the
# other, on a quiet machine, between the two side-by-side batches.
FIXTURES="$TMP"
PLAIN_STARTED=" "
# CLS_M_FILE: where case 8 writes the shift its fixture measures, for 19 to 21.
CLS_M_FILE="${FIXTURES}/cls_m"

# own_fixtures <fixture>...: this case's own copy of each fixture, and TMP pointing
# at the folder that holds them, so run_gate and the rest of the case read the copy.
own_fixtures() {
  local name
  for name in "$@"; do
    cp -R "${FIXTURES}/${name}" "${MUTANT_DIR}/${name}"
  done
  TMP="$MUTANT_DIR"
  LAP=$SECONDS
}

# plain_case <id>...: starts case_<id> for each id through the runner.
plain_case() {
  local id
  for id in "$@"; do
    PLAIN_STARTED="${PLAIN_STARTED}${id} "
    mutant_run "case_${id}"
  done
}

# 1 and 15: a clean page, and what its OK line records.
case_1() {
  local need
  own_fixtures clean
  run_gate_real clean
  want_green "1: a clean page" "OK: browser gate: 1 pages x 1 variants (light)"
  for need in "CLS worst 0 " "viewport 1280x800" "variants (light)" "Chrome/" "interval 1000 ms" "no new sideways scroll at 1280x800 and 390x844 (0 baselined)"; do
    if ! grep -qF -- "$need" <<< "$OUT"; then
      fail "15: the OK line does not record '${need}'. Output: ${OUT}"
      return 0
    fi
  done
  echo "  ok: 15: the OK line records the CLS, viewport, browser version, interval and the sideways-scroll widths"
}
case_2() {
  own_fixtures serious
  run_gate serious
  want_red "2: an axe serious violation" "axe color-contrast (serious)"
}
case_3() {
  own_fixtures critical
  run_gate critical
  want_red "3: an axe critical violation" "axe button-name (critical)"
}
case_4() {
  own_fixtures nodoctype
  run_gate nodoctype
  want_red "4: no doctype" "doctype missing"
}
case_5() {
  own_fixtures nocharset
  run_gate nocharset
  want_red "5: no charset" "charset not declared"
}
case_6() {
  own_fixtures console
  run_gate console
  want_red "6: a console error" "console error: fixture boom"
}
case_7() {
  own_fixtures notfound
  run_gate notfound
  want_red "7: a 404 image" "request /missing.png -> 404"
}
# 8 also hands the shift it measures (M) to 19 to 21, which run in the second batch.
case_8() {
  own_fixtures shift
  run_gate_real shift
  want_red "8: a layout shift" "CLS 0."
  want_said "8a: with the default 5 cold loads" "largest of 5 cold loads"
  want_said "8b: a layout shift without a row says so" "no baseline row"
  sed -n 's/.*FAIL: light \/: CLS \([0-9.e-]*\) .*/\1/p' <<< "$OUT" | head -1 > "$CLS_M_FILE"
}
case_9() {
  own_fixtures external
  run_gate external
  want_red "9: a request leaving loopback" "leaves loopback"
}
case_10() {
  own_fixtures nopage
  run_gate nopage
  want_red "10: a manifest page answering 404" "FAIL: light /nope.html: request /nope.html -> 404"
}

# 11: the exception turns the 404 image green (its console error goes too).
case_11() {
  own_fixtures notfound
  printf '/missing.png|fixture: deliberately absent\n' > "${TMP}/notfound/exceptions.txt"
  run_gate notfound
  want_green "11: an exception row for the 404 image" "1 excepted"
}

# 12-14: the exceptions file is closed and fail-closed.
case_12() {
  own_fixtures notfound
  printf '/missing.png|\n' > "${TMP}/notfound/exceptions.txt"
  run_gate notfound
  want_exit "12: an exception without a reason" 2 "has no reason"
}
case_13() {
  own_fixtures clean
  printf '/other.png|fixture: stale\n' > "${TMP}/clean/exceptions.txt"
  run_gate clean
  want_red "13: an exception that matches nothing" "exception /other.png matched nothing"
}
case_14() {
  own_fixtures clean
  rm -f "${TMP}/clean/exceptions.txt"
  run_gate clean
  want_exit "14: a missing exceptions file" 2 "exceptions file not found"
}

# The baseline. Two pale paragraphs, #a and #b, both color-contrast serious.
REASON="fixture, shrink-only"
make_site two "$(page '<p id="a" style="color:#cccccc">pale a</p><p id="b" style="color:#cccccc">pale b</p>' '')"
case_16() {
  own_fixtures two
  printf 'axe|light|/|color-contrast|#a|%s\naxe|light|/|color-contrast|#b|%s\n' "$REASON" "$REASON" > "${TMP}/two/baseline.txt"
  run_gate two
  want_green "16: every axe finding in the baseline" "OK: browser gate"
  want_said "16b: each baselined finding is shown as a WARN" "WARN: baselined axe color-contrast (serious): light /: #a"
  want_said "16c: the other too" "WARN: baselined axe color-contrast (serious): light /: #b"
  want_said "16d: and they are counted" "2 axe findings baselined"
}
case_17() {
  own_fixtures two
  printf 'axe|light|/|color-contrast|#a|%s\n' "$REASON" > "${TMP}/two/baseline.txt"
  run_gate two
  want_red "17: an axe finding the baseline lacks" "FAIL: light /: axe color-contrast (serious): #b (new, not in the baseline)"
}
case_18() {
  own_fixtures two
  printf 'axe|light|/|color-contrast|#a|%s\naxe|light|/|color-contrast|#b|%s\naxe|light|/|color-contrast|#gone|%s\n' "$REASON" "$REASON" "$REASON" > "${TMP}/two/baseline.txt"
  run_gate two
  want_red "18: a baselined axe finding that is gone" "FAIL: stale baseline row: axe|light|/|color-contrast|#gone"
}

# CLS rows. M is the shift the fixture measures, read from the gate itself by
# case 8; 19 to 21 run in the second batch, once M is known.
scaled() { awk -v m="$CLS_M" -v f="$1" 'BEGIN { printf "%.17g", m * f }'; }
case_19() {
  own_fixtures shift
  printf 'cls|light|/|%s|%s\n' "$(scaled 0.999)" "$REASON" > "${TMP}/shift/baseline.txt"
  run_gate_real shift
  want_red "19: a CLS above its recorded value" "FAIL: light /: CLS ${CLS_M} grew above the recorded"
}
case_20() {
  own_fixtures shift
  printf 'cls|light|/|%s|%s\n' "$(scaled 1.001)" "$REASON" > "${TMP}/shift/baseline.txt"
  run_gate_real shift
  want_red "20: a CLS below its recorded value" "FAIL: light /: CLS ${CLS_M} is below the recorded"
  want_said "20b: and it says to lower the row" "lower the row"
}
case_21() {
  own_fixtures shift
  printf 'cls|light|/|%s|%s\n' "$CLS_M" "$REASON" > "${TMP}/shift/baseline.txt"
  run_gate_real shift
  want_green "21: a CLS equal to its recorded value" "WARN: baselined CLS light /: ${CLS_M}"
}
case_22() {
  own_fixtures clean
  printf 'cls|light|/|0.01|%s\n' "$REASON" > "${TMP}/clean/baseline.txt"
  run_gate clean
  want_red "22: a CLS row on a page without a shift" "is below the recorded 0.01"
}
case_23() {
  own_fixtures shift
  : > "${TMP}/shift/baseline.txt"
  run_gate_real shift
  want_red "23: a CLS above 0 with no row" "no baseline row"
}

# with_file <fixture> <file> <content|->: this case's copy of the fixture with that one
# file (exceptions, baseline or variants) holding <content>, or removed for -.
with_file() {
  own_fixtures "$1"
  if [[ "$3" == "-" ]]; then
    rm -f "${TMP}/$1/$2"
  else
    printf '%s' "$3" > "${TMP}/$1/$2"
  fi
}
case_24a() {
  with_file two baseline.txt 'axe|light|/|color-contrast|#a|
'
  run_gate two
  want_exit "24a: an axe row without a reason" 2 "has no reason"
}
case_24b() {
  with_file two baseline.txt 'cls|light|/|0.01|
'
  run_gate two
  want_exit "24b: a CLS row without a reason" 2 "has no reason"
}
case_24c() {
  with_file two baseline.txt "axe|light|/|color-contrast|${REASON}
"
  run_gate two
  want_exit "24c: an axe row without a selector" 2 "a row is"
}
case_24d() {
  with_file two baseline.txt "cls|light|/|large|${REASON}
"
  run_gate two
  want_exit "24d: a CLS row with a value that is no number" 2 "must be a positive number"
}
case_24e() {
  with_file two baseline.txt "other|/|x|${REASON}
"
  run_gate two
  want_exit "24e: a row of an unknown kind" 2 "unknown row"
}
case_24f() {
  with_file two baseline.txt "axe|light|/|color-contrast|#a|${REASON}
axe|light|/|color-contrast|#a|${REASON}
"
  run_gate two
  want_exit "24f: a row listed twice" 2 "listed twice"
}
case_25() {
  with_file two baseline.txt -
  run_gate two
  want_exit "25: a missing baseline file" 2 "baseline file not found"
}

# External requests.
make_site viaexternal "$(page '<img src="http://example.invalid/x.png" alt="away">' '')"
case_26() {
  own_fixtures viaexternal
  printf 'external|http://example.invalid/|fixture: an embed that must not leave\n' > "${TMP}/viaexternal/exceptions.txt"
  run_gate viaexternal
  want_green "26: a listed external request" "WARN: external blocked: light /: http://example.invalid/x.png"
  want_said "26b: counted" "1 external requests blocked"
}
case_27() {
  own_fixtures external
  run_gate external
  want_red "27: an external request that is not listed" "request http://example.invalid/x.png leaves loopback"
}
case_28() {
  own_fixtures clean
  printf 'external|http://elsewhere.invalid/|fixture: never requested\n' > "${TMP}/clean/exceptions.txt"
  run_gate clean
  want_red "28: a listed external prefix no page requests" "FAIL: stale external exception: http://elsewhere.invalid/"
}
case_29() {
  own_fixtures viaexternal
  printf 'external|http://example.invalid/|\n' > "${TMP}/viaexternal/exceptions.txt"
  run_gate viaexternal
  want_exit "29: an external row without a reason" 2 "has no reason"
}

# The variants (v2). #t is pale in the dark look only: under an attribute the
# page's own CSS reads (case 30-32), and under the dark colour scheme (case 33).
make_site themed "$(page '<p id="t">themed text</p>' '<style>:root[data-theme="dark"] #t { color: #cccccc; }</style>')"
printf 'light|attr:data-theme=light\ndark|attr:data-theme=dark\n' > "${TMP}/themed/variants.txt"
case_30() {
  own_fixtures themed
  run_gate themed
  want_red "30: a finding only in an attr: variant" "FAIL: dark /: axe color-contrast (serious): #t (new, not in the baseline)"
  if grep -qF -- "FAIL: light /" <<< "$OUT"; then
    fail "30b: the light variant was blamed for the dark finding. Output: ${OUT}"
  else
    echo "  ok: 30b: the light variant is clean"
  fi
}
case_31() {
  own_fixtures themed
  printf 'axe|dark|/|color-contrast|#t|%s\n' "$REASON" > "${TMP}/themed/baseline.txt"
  run_gate themed
  want_green "31: the same finding baselined for that variant" "OK: browser gate: 1 pages x 2 variants (light, dark)"
  want_said "31b: shown as a WARN with its variant" "WARN: baselined axe color-contrast (serious): dark /: #t"
}
case_32() {
  own_fixtures themed
  printf 'axe|light|/|color-contrast|#t|%s\n' "$REASON" > "${TMP}/themed/baseline.txt"
  run_gate themed
  want_red "32: a row naming the other variant" "FAIL: dark /: axe color-contrast (serious): #t (new, not in the baseline)"
  want_said "32b: and the row of the wrong variant is stale" "FAIL: stale baseline row: axe|light|/|color-contrast|#t"
}

make_site schemed "$(page '<p id="t">schemed text</p>' '<style>@media (prefers-color-scheme: dark) { #t { color: #cccccc; } }</style>')"
printf 'light|scheme:light\ndark|scheme:dark\n' > "${TMP}/schemed/variants.txt"
case_33() {
  own_fixtures schemed
  run_gate schemed
  want_red "33: a finding only in a scheme:dark variant" "FAIL: dark /: axe color-contrast (serious): #t"
}
case_34() {
  own_fixtures schemed
  printf 'axe|dark|/|color-contrast|#t|%s\n' "$REASON" > "${TMP}/schemed/baseline.txt"
  run_gate schemed
  want_green "34: baselined, the scheme:dark run is green, and its OK line names pages x variants and checks" "OK: browser gate: 1 pages x 2 variants (light, dark), 2 checks"
}

# 35: the variants file is closed and fail-closed.
case_35a() {
  with_file clean variants.txt -
  run_gate clean
  want_exit "35a: a missing variants file" 2 "variants file not found"
}
case_35b() {
  with_file clean variants.txt ""
  run_gate clean
  want_exit "35b: a variants file with no row" 2 "lists no variant"
}
case_35c() {
  with_file clean variants.txt 'light|scheme:light
light|scheme:dark
'
  run_gate clean
  want_exit "35c: a variant listed twice" 2 "listed twice"
}
case_35d() {
  with_file clean variants.txt 'light|theme:light
'
  run_gate clean
  want_exit "35d: an unknown how to apply" 2 "unknown how to apply"
}
case_35e() {
  with_file clean variants.txt 'dark|attr:data-theme
'
  run_gate clean
  want_exit "35e: an attr: without a value" 2 "unknown how to apply"
}
case_35f() {
  with_file clean variants.txt 'light
'
  run_gate clean
  want_exit "35f: a row without a how" 2 "a row is name|how to apply"
}

# 36: a baseline row names a variant of the file; the v1 row has none.
case_36a() {
  with_file clean baseline.txt "axe|dusk|/|color-contrast|#a|${REASON}
"
  run_gate clean
  want_exit "36a: a baseline row naming an unknown variant" 2 "is not a variant"
}
case_36b() {
  with_file clean baseline.txt "axe|/|color-contrast|#a|${REASON}
"
  run_gate clean
  want_exit "36b: a row of the v1 format, without a variant" 2 "a row is axe|<variant>"
}
case_36c() {
  with_file clean baseline.txt "cls|/|0.01|${REASON}
"
  run_gate clean
  want_exit "36c: a CLS row of the v1 format, without a variant" 2 "a row is cls|<variant>"
}

# 37-39: the layout-shift override.
case_37() {
  own_fixtures clean
  FORSGREN_CLS_LOADS=2 FORSGREN_CLS_INTERVAL_MS=50 capture "$GATE" "${TMP}/clean/site" "${TMP}/clean/manifest.json" "${TMP}/clean/exceptions.txt" "${TMP}/clean/baseline.txt" "${TMP}/clean/variants.txt"
  want_green "37: the override is honoured" "interval 50 ms"
}
case_38() {
  own_fixtures shift
  run_gate_hit shift
  want_red "38: an override still catches the shift fixture" "largest of 1 cold loads"
}
case_38b() {
  own_fixtures shiftstall
  run_gate_hit shiftstall
  want_red "38b: a page that stalls 800 ms after the load, an override still catches the shift" "largest of 1 cold loads"
}
case_40() {
  own_fixtures shiftslow
  run_gate_hit shiftslow
  want_red "40: a delayed load, an override still catches the shift fixture" "largest of 1 cold loads"
}
case_39a() {
  own_fixtures clean
  FORSGREN_CLS_LOADS=0 capture "$GATE" "${TMP}/clean/site" "${TMP}/clean/manifest.json" "${TMP}/clean/exceptions.txt" "${TMP}/clean/baseline.txt" "${TMP}/clean/variants.txt"
  want_exit "39a: zero loads" 2 "FORSGREN_CLS_LOADS must be a positive integer"
}
case_39b() {
  own_fixtures clean
  FORSGREN_CLS_INTERVAL_MS=fast capture "$GATE" "${TMP}/clean/site" "${TMP}/clean/manifest.json" "${TMP}/clean/exceptions.txt" "${TMP}/clean/baseline.txt" "${TMP}/clean/variants.txt"
  want_exit "39b: an interval that is no number" 2 "FORSGREN_CLS_INTERVAL_MS must be a positive integer"
}

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
# The page holds its first paint until its end (forsgren#558), as the real
# pages do: delivered in pieces (forsgren#611), a long cell painted half-parsed
# would grow and shift, and this case is about sideways scrolling alone.
make_site wraps "$(page "${SCROLL_BOX}<table><tr><th scope=\"row\">Acme</th><td>${LONG_CELL}</td></tr></table></div><p id=\"page-end\">end</p>" '<link rel="expect" href="#page-end" blocking="render">')"
case_41() {
  own_fixtures phonewide
  run_gate phonewide
  want_red "41: a table wider than its box at the phone width" "FAIL: light /: scrolls sideways at 390x844: table 1 is 210 px wider than its box"
  if grep -qF -- "at 1280x800" <<< "$OUT"; then
    fail "41b: the laptop width was blamed for a table that fits it. Output: ${OUT}"
  else
    echo "  ok: 41b: the laptop width is clean"
  fi
}
case_42() {
  own_fixtures laptopwide
  run_gate laptopwide
  want_red "42: a table wider than its box at the laptop width" "FAIL: light /: scrolls sideways at 1280x800: table 1 is 220 px wider than its box"
  want_said "42b: and at the phone width" "FAIL: light /: scrolls sideways at 390x844: table 1 is 1110 px wider than its box"
}
case_43() {
  own_fixtures pagewide
  run_gate pagewide
  want_red "43: a page wider than the window" "FAIL: light /: scrolls sideways at 1280x800: the page is 220 px wider than the window"
}
case_44() {
  own_fixtures wraps
  run_gate wraps
  want_green "44: a long cell that wraps inside its table" "no new sideways scroll at 1280x800 and 390x844 (0 baselined)"
}

# 45-49: the sideways baseline, on case 41's page (210 px at 390x844).
case_45() {
  with_file phonewide baseline.txt "sideways|light|/|390x844|table 1|210|${REASON}
"
  run_gate phonewide
  want_green "45: an overflow equal to its row" "WARN: baselined sideways scroll: light /: at 390x844 table 1 is 210 px wider than its box"
  want_said "45b: and counted" "no new sideways scroll at 1280x800 and 390x844 (1 baselined)"
}
case_46() {
  with_file phonewide baseline.txt "sideways|light|/|390x844|table 1|209|${REASON}
"
  run_gate phonewide
  want_red "46: an overflow above its row" "FAIL: light /: scrolls sideways at 390x844: table 1 is 210 px wider than its box, above the recorded 209 px (grew)"
}
case_47() {
  with_file phonewide baseline.txt "sideways|light|/|390x844|table 1|211|${REASON}
"
  run_gate phonewide
  want_red "47: an overflow below its row" "FAIL: light /: scrolls sideways at 390x844: table 1 is 210 px wider than its box, below the recorded 211 px: shrink the row"
}
case_48() {
  with_file phonewide baseline.txt "sideways|light|/|390x844|table 1|210|${REASON}
sideways|light|/|1280x800|table 1|5|${REASON}
"
  run_gate phonewide
  want_red "48: a row whose overflow is gone" "FAIL: stale baseline row: sideways|light|/|1280x800|table 1|5 no longer scrolls sideways; remove it"
}
case_49a() {
  with_file phonewide baseline.txt 'sideways|light|/|390x844|table 1|210|
'
  run_gate phonewide
  want_exit "49a: a sideways row without a reason" 2 "has no reason"
}
case_49b() {
  with_file phonewide baseline.txt "sideways|light|/|390x844|table 1|0|${REASON}
"
  run_gate phonewide
  want_exit "49b: a px that is no positive whole number" 2 "must be a positive whole number of pixels"
}
case_49c() {
  with_file phonewide baseline.txt "sideways|light|/|800x600|table 1|210|${REASON}
"
  run_gate phonewide
  want_exit "49c: a viewport the gate does not measure" 2 "is not a viewport the gate measures"
}
case_49d() {
  with_file phonewide baseline.txt "sideways|light|/|390x844|table 1|210|${REASON}
sideways|light|/|390x844|table 1|210|${REASON}
"
  run_gate phonewide
  want_exit "49d: a sideways row listed twice" 2 "listed twice"
}

# 50: the CLS interval starts at the load, before the document and axe checks
# (forsgren#377). Those take as long as the machine takes: a hosted runner was
# slow enough that a 1 ms read, started after axe, saw a shift 500 ms after the
# load (proof K). The page reports a shift when it is read after axe ran.
case_50() {
  own_fixtures readorder
  run_gate readorder
  want_green "50: the CLS is read before the axe run, not after it" "OK:"
}

# 51: the same table, a page scrollbar of 15 px: the overflow is the table's
# width less the window's, 210 px, with or without the scrollbar (forsgren#377).
case_51() {
  own_fixtures scrollbar
  run_gate scrollbar
  want_red "51: a page scrollbar does not change the measurement" "FAIL: light /: scrolls sideways at 390x844: table 1 is 210 px wider than its box"
}

# 54-56: the delayed-delivery load (forsgren#611). A table of 30 narrow rows,
# then 30 rows whose first cell is wide: painted before the wide rows arrive,
# the second column moves right when they do. The page is about 3 KB, so the
# first of the 4 pieces ends inside the narrow rows and the wide ones come in
# the later pieces. HOLD is the first-paint hold of forsgren#558.
NARROW_ROWS="$(printf '<tr><td>a</td><td>b</td></tr>%.0s' {1..30})"
WIDE_ROWS="$(printf '<tr><td>a wide first cell of many words</td><td>b</td></tr>%.0s' {1..30})"
HOLD='<link rel="expect" href="#page-end" blocking="render">'
TABLE_BODY="<table><tr><th scope=\"col\">first</th><th scope=\"col\">second</th></tr>${NARROW_ROWS}${WIDE_ROWS}</table>"
make_site held "$(page "${TABLE_BODY}<p id=\"page-end\">end</p>" "$HOLD")"
make_site unheld "$(page "${TABLE_BODY}<p id=\"page-end\">end</p>" '')"
make_site heldnoid "$(page "${TABLE_BODY}<p>end</p>" "$HOLD")"
# A slow runner: the page's main thread is busy (BUSY_JS, 800 ms) longer than all
# the pieces take to arrive (3 x 150 ms), so the first paint comes after the
# last piece unless the server waits for the paint (forsgren#620).
make_site unheldslow "$(page "${TABLE_BODY}<p id=\"page-end\">end</p>" "$BUSY_JS")"
case_54() {
  own_fixtures held
  run_gate held
  want_green "54: a table page that holds its first paint, delivered in pieces" "CLS worst 0 "
  want_said "54b: the OK line names the delayed-delivery load" "each page also loaded once in 4 pieces 150 ms apart"
}
case_55() {
  own_fixtures unheld
  run_gate unheld
  want_red "55: the same page without the hold" "FAIL: light /: CLS 0."
  want_said "55b: the finding names the delayed-delivery load" "1 delayed-delivery load (4 pieces 150 ms apart: 0."
}
case_56() {
  own_fixtures heldnoid
  run_gate heldnoid
  want_green "56: a hold whose id the page lacks lasts to the end of the parse" "CLS worst 0 "
}
case_57() {
  own_fixtures unheldslow
  run_gate unheldslow
  want_red "57: the same page on a slow runner, a busy main thread past all the pieces" "FAIL: light /: CLS 0."
  want_said "57b: the finding names the delayed-delivery load" "1 delayed-delivery load (4 pieces 150 ms apart: 0."
}

# The first batch: every plain case that needs nothing of another case
# (FIRST_CASES, in its order), those of this shard when it is one.
if [[ -n "$SHARD_N" ]]; then
  echo "browser gate self-test: shard ${SHARD_N}/${SHARD_M}: $(grep -c . <<< "$RUN_IDS") of $(all_ids | grep -c .) cases and proofs"
fi
PHASE_START=$SECONDS
mutants_init "$TMP"
for id in "${FIRST_CASES[@]}"; do
  if runs "case_${id}"; then plain_case "$id"; fi
done
mutants_wait
echo "browser gate self-test: the first batch of plain cases, side by side: $((SECONDS - PHASE_START)) s"
CLS_M="$(cat "$CLS_M_FILE" 2> /dev/null || true)"
if runs case_8 && [[ -z "$CLS_M" ]]; then
  fail "the shift fixture did not report a CLS value in case 8, so 19 to 21 compare with 0.05"
  CLS_M=0.05
fi

# SERIAL_CASES: the cases that still run one after the other, on a machine with no
# other case of this self-test running, after the first batch and before the
# second (forsgren#632). Each has its reason:
#  - 52a to 52g, 53, 53d, 54a to 54c: they signal or kill processes found by a
#    pattern and count the Chromes that appear while they run (signal_case): a
#    Chrome of a side-by-side case would be counted as theirs;
#  - 53e: a kill and timing case (a loaded machine is simulated by its seam, and
#    "at once" is timed): other cases would load the machine for real;
#  - 53g, 53h, 53i: they share the clone folder listing and SEAM_* globals with
#    the signal cases;
#  - 52h, 52i, 53j: no browser and under a second, so nothing to win, and they
#    swap the CLONE_PARENT and SIG_ globals the signal cases read;
#  - 53f: a kill and timing case (Chrome killed during the launch, the end
#    timed within 10 s), as 53e;
#  - R, Rb, S, X, Z, Dh (SERIAL_PROOFS): the mutation proofs of those cases (R
#    and Rb wait for a stalled Chrome, forsgren#630), each started alone and
#    collected before the next, below.
# They are one unit of a shard (v30): serial_cases runs them, written inline as
# before, and the proofs R to Dh run in the same shard.
serial_cases() {
echo "browser gate self-test: one after the other (SERIAL_CASES): ${SERIAL_CASES[*]}, then the proofs R Rb S X Z Dh"
PHASE_START=$SECONDS

# The exits (see the header): the signal and kill cases of the sites' line.
# 52-53: the browser is closed and its profile removed on every way out
# (pilot issue 34): a signal to the wrapper or to node, and an error.
# A slow fixture (ten looks) keeps the gate busy; the signal comes once Chrome
# is up. Every Chrome here is found by its own case's profile folder.
make_site slow "$(page '' '')"
: > "${TMP}/slow/variants.txt"
for n in 1 2 3 4 5 6 7 8 9 10; do printf 'look%s|scheme:light\n' "$n" >> "${TMP}/slow/variants.txt"; done

# signal_case <label> <target: self|node> <signal|error|held> <command...>: runs the
# command on the slow fixture with its own TMPDIR, waits for Chrome, sends the
# signal to the command (self) or to the node process under it (node), or kills
# the Chrome (error, held), then waits for the end, up to SIG_WAIT_S seconds
# (20 by default; SIG_WAITED, v29). Sets SIG_UP (1 when its Chrome
# was found by its profile path before the signal), SIG_RC, SIG_CHROME
# (alive), SIG_PROFILE (folders left), SIG_ENDED and SIG_OUT, SIG_CLONE_OFF_WHY
# (see the clone below), and for a case that sets CLONE_PARENT to a folder of the
# test (53g) the clone folders there: SIG_CLONE_MADE (new folders seen once the
# Chrome is up), SIG_CLONE_LEFT (new folders still there at the end) and
# SIG_CLONE_CONCURRENT (Chrome processes of anyone else that started meanwhile).
# The case removes the folders left when nobody else's Chrome started meanwhile.
#
# The code-sign clone (forsgren#660). On macOS every Chrome makes a clone of its
# app in one folder per user, and nothing moves that folder: not TMPDIR, HOME or
# any switch (seen on Chrome 157). So a case that lists it also sees the clones of
# every other Chrome on the machine. The real-Chrome cases therefore run with the
# clone off, through CHROME_UNDER_TEST, and the engine's clone parent is an empty
# folder of the case: nothing here reads the shared folder. The removal of a clone
# is proved on a folder of the test (53g, 53h, 53i, 54a to 54c, proof X).
#
# A renderer of the profile shows that Chrome is up, not that the engine's
# launch is over: Chrome opens its first tab while puppeteer.launch is still
# connecting, and on a fast runner the kill landed inside the launch
# (Target.setDiscoverTargets: Target closed; run 42138308615). A case whose
# meaning is "after the launch" sets SIG_WAIT_READY=1 and runs a seam module
# (FORSGREN_GATE_BROWSER_HOOK, called by the engine right after the launch)
# that creates the file named by FORSGREN_TEST_READY_MARK once it has done what
# the case needs; the signal then waits for that file, never for a time, and
# SIG_READY is 0 when it never came (the case proves nothing, and says so).
# A held case (53f, v29) is up once its profile has the Local State file: its
# Chrome opens no page and never hears puppeteer, so the launch is still on.
SIG_WAIT_READY=0
CLONE_PARENT=""
CLONE_FEATURE=MacAppCodeSignClone
REAL_CHROME="${FORSGREN_CHROME:-}"
if [[ -z "$REAL_CHROME" ]]; then
  for candidate in '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' /usr/bin/google-chrome /usr/bin/google-chrome-stable /usr/bin/chromium /usr/bin/chromium-browser; do
    if [[ -x "$candidate" ]]; then REAL_CHROME="$candidate"; break; fi
  done
fi
# CHROME_UNDER_TEST: the real Chrome with the feature added to the one
# --disable-features it gets (puppeteer passes one, and of several the last wins).
CHROME_UNDER_TEST="${TMP}/chrome_no_clone.sh"
cat > "$CHROME_UNDER_TEST" << EOF
#!/usr/bin/env bash
args=()
features=""
for arg in "\$@"; do
  case "\$arg" in
    --disable-features=*) features="\${features:+\${features},}\${arg#--disable-features=}" ;;
    *) args+=("\$arg") ;;
  esac
done
exec "${REAL_CHROME}" \${args[@]+"\${args[@]}"} "--disable-features=\${features:+\${features},}${CLONE_FEATURE}"
EOF
chmod +x "$CHROME_UNDER_TEST"
# clone_feature_why <chrome>: "" when this Chrome knows the feature, else why not.
# A feature Chrome renamed or dropped would be ignored without a word. Chrome makes
# the clone on macOS only, so there is nothing to know elsewhere.
clone_feature_why() {
  local name framework found
  if [[ "$(uname)" != "Darwin" ]]; then return 0; fi
  name="$(basename "$1")"
  framework="$(dirname "$(dirname "$1")")/Frameworks/${name} Framework.framework/Versions/Current/${name} Framework"
  if [[ ! -f "$framework" ]]; then
    echo "the framework of the Chrome under test was not found at ${framework}, so its code-sign clone cannot be shown to be off"
    return 0
  fi
  found="$(grep -a -c -F -- "$CLONE_FEATURE" "$framework" || true)"
  if [[ "$found" -eq 0 ]]; then
    echo "the Chrome under test does not know the feature ${CLONE_FEATURE}, so the switch would not turn its code-sign clone off"
  fi
}
CLONE_FEATURE_WHY="$(clone_feature_why "$REAL_CHROME")"
# clone_flag_why <command line of Chrome's main process>: "" when it turns the
# clone off, else why it does not.
clone_flag_why() {
  local words word count=0 value="" enabled=""
  if [[ -z "$1" ]]; then
    echo "the command line of its Chrome was not found, so its code-sign clone cannot be shown to be off"
    return 0
  fi
  read -r -a words <<< "$1"
  for word in "${words[@]}"; do
    case "$word" in
      --disable-features=*) count=$((count + 1)); value="${word#--disable-features=}" ;;
      --enable-features=*) enabled="${enabled},${word#--enable-features=}" ;;
    esac
  done
  if [[ "$count" -eq 0 ]]; then
    echo "its Chrome runs without --disable-features, so its code-sign clone is not off"
  elif [[ "$count" -gt 1 ]]; then
    echo "its Chrome has ${count} --disable-features switches and the last one wins, so its code-sign clone may not be off"
  elif [[ ",${value}," != *",${CLONE_FEATURE},"* ]]; then
    echo "the --disable-features of its Chrome does not name ${CLONE_FEATURE}, so its code-sign clone is not off"
  elif [[ "${enabled}," == *",${CLONE_FEATURE},"* ]]; then
    echo "the --enable-features of its Chrome names ${CLONE_FEATURE}, so its code-sign clone is not off"
  fi
}
# chrome_command_line <tmpd>: the command line of the case's main Chrome process,
# empty when it is gone: the one the engine talks to, so the one with the pipe
# switch. Not a shell or perl of a test's wrapper, which may carry the same
# arguments before its exec.
chrome_command_line() {
  { ps -A -ww -o command= || true; } | { grep -F -e "--user-data-dir=${1}/browser-gate-" || true; } | { grep -F -e ' --remote-debugging-pipe' || true; } | { grep -v -F -e ' --type=' || true; } | { grep -v -E '^[^ ]*(bash|perl|sh) ' || true; } | awk 'NR == 1'
}
clone_names() {
  # A glob, so a folder that vanishes while listing cannot fail the listing.
  local d
  if [[ -n "$CLONE_PARENT" ]]; then
    for d in "$CLONE_PARENT"/code_sign_clone.*; do
      if [[ -e "$d" ]]; then basename "$d"; fi
    done
  fi
}
# Main processes of Chromes (any a clone folder could come from) that are not this
# case's (profile folder $1).
other_chromes() {
  { ps -A -o pid=,command= || true; } | { grep -E '[.]app/Contents/MacOS/(Google Chrome|Chromium|Chrome)' || true; } | { grep -v -F -e ' --type=' -e "$1" || true; } | awk '{print $1}' | sort
}

# remove_new_clones <before-file>: removes the clone folders that are not in the
# before-file, the case's own (a folder of the other test case, '.foreign', stays).
remove_new_clones() {
  local new name
  new="$(clone_names | comm -13 "$1" -)"
  while IFS= read -r name; do
    if [[ -z "$name" || "$name" == *.foreign* ]]; then continue; fi
    rm -rf "${CLONE_PARENT:?}/${name}" || { echo "cannot remove the clone folder ${CLONE_PARENT}/${name}" >&2; return 1; }
  done <<< "$new"
}

# The case's TMPDIR is a folder of its own straight under the temp root, its side
# files (.out, .ready, the listings) under TMP (forsgren#642): on Linux Chrome
# binds its singleton socket at <TMPDIR>/.com.google.Chrome.XXXXXX/SingletonSocket,
# and the engine gives Chrome the profile as TMPDIR, so the socket path is the
# case's TMPDIR plus 62 characters. A Unix socket path holds at most 107, and
# under ${TMP}/sig_<label> it was 117 or more: Chrome ends itself on that during
# the launch (LOG(FATAL) "Socket path too long", process_singleton_posix.cc),
# seen as SIGABRT in every case here. macOS puts the socket in its own temp
# folder, whatever TMPDIR says, so the length never showed there.
signal_case() {
  local label="$1" target="$2" sig="$3" root tmpd side pid target_pid
  shift 3
  # One slash, as Chrome writes its --user-data-dir (macOS's TMPDIR ends in /).
  root="${TMPDIR:-/tmp}"
  root="${root%/}"
  tmpd="$(mktemp -d "${root}/sig_${label}.XXXXXX")"
  side="${TMP}/sig_${label}"
  clone_names > "${side}.clones_before"
  other_chromes "$tmpd" > "${side}.others_before"
  rm -f "${side}.ready"
  mkdir -p "${side}.no_clones"
  # A case's own `env FORSGREN_CHROME=` or `FORSGREN_GATE_CLONE_PARENT=` comes after these and wins.
  TMPDIR="$tmpd" FORSGREN_TEST_READY_MARK="${side}.ready" FORSGREN_CHROME="$CHROME_UNDER_TEST" FORSGREN_GATE_CLONE_PARENT="${side}.no_clones" perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' "$@" "${TMP}/slow/site" "${TMP}/slow/manifest.json" "${TMP}/slow/exceptions.txt" "${TMP}/slow/baseline.txt" "${TMP}/slow/variants.txt" > "${side}.out" 2>&1 &
  pid=$!
  SIG_UP=0
  for _ in $(seq 1 150); do
    # Up means a page is open: its renderer exists, the launch is over.
    # Either order of the two flags: Chrome 156 puts --type=renderer before
    # --user-data-dir (pilot issue 30), so the one-order pattern never
    # matched and every case sent its signal only after this 30 s wait.
    if [[ "$sig" == "held" ]]; then
      if [[ -n "$(find "$tmpd" -maxdepth 2 -path '*/browser-gate-*/Local State' 2> /dev/null)" ]]; then SIG_UP=1; break; fi
    elif pgrep -f -- "--user-data-dir=${tmpd}/browser-gate-.*--type=renderer|--type=renderer.*--user-data-dir=${tmpd}/browser-gate-" > /dev/null; then SIG_UP=1; break; fi
    sleep 0.2
  done
  SIG_READY=1
  if [[ "$SIG_WAIT_READY" -eq 1 ]]; then
    SIG_READY=0
    for _ in $(seq 1 150); do
      if [[ -e "${side}.ready" ]]; then SIG_READY=1; break; fi
      if ! kill -0 "$pid" 2> /dev/null; then break; fi
      sleep 0.1
    done
  fi
  SIG_CLONE_MADE="$({ clone_names | comm -13 "${side}.clones_before" - || true; } | wc -l | tr -d ' ')"
  # While Chrome is up: what its own process was started with, past every wrapper.
  SIG_CLONE_OFF_WHY="$(clone_flag_why "$(chrome_command_line "$tmpd")")"
  SIG_PIPE_HOLDER="$(chrome_parent "$tmpd")"
  target_pid="$pid"
  if [[ "$target" == "node" ]]; then
    target_pid="$(pgrep -f -- "node .*mjs ${TMP}/slow/site" | head -1)" || target_pid="$pid"
  fi
  # The stall of proof R (SIG_STALL_CHROME, forsgren#630), see stall_chrome.
  stall_chrome "$tmpd"
  if [[ "$sig" == "error" || "$sig" == "held" ]]; then
    pkill -9 -f -- "--user-data-dir=${tmpd}/browser-gate-" || true
  else
    kill -s "$sig" "$target_pid" || true
  fi
  SIG_ENDED=1
  SIG_WAITED="${SIG_WAIT_S:-20}"
  for _ in $(seq 1 $((SIG_WAITED * 5))); do
    if ! kill -0 "$pid" 2> /dev/null; then break; fi
    sleep 0.2
  done
  if kill -0 "$pid" 2> /dev/null; then
    SIG_ENDED=0
    kill -9 "$pid" || true
  fi
  wait "$pid" 2>/dev/null && SIG_RC=0 || SIG_RC=$?
  wait_chrome_gone "$tmpd"
  SIG_CHROME="$({ pgrep -f -- "--user-data-dir=${tmpd}/browser-gate-" || true; } | wc -l | tr -d ' ')"
  SIG_PROFILE="$(find "$tmpd" -maxdepth 1 -name 'browser-gate-*' | wc -l | tr -d ' ')"
  SIG_OUT="$(cat "${side}.out")"
  SIG_CLONE_LEFT="$({ clone_names | comm -13 "${side}.clones_before" - || true; } | wc -l | tr -d ' ')"
  SIG_CLONE_CONCURRENT="$({ other_chromes "$tmpd" | comm -13 "${side}.others_before" - || true; } | wc -l | tr -d ' ')"
  # Whatever a failed case left behind is ours (found by its folder): clean up.
  pkill -9 -f -- "--user-data-dir=${tmpd}/browser-gate-" || true
  pkill -9 -f -- "${tmpd}/browser-gate-" || true
  if [[ "$SIG_CLONE_LEFT" -ne 0 && "$SIG_CLONE_CONCURRENT" -eq 0 ]]; then
    remove_new_clones "${side}.clones_before"
  fi
  rm -rf "$tmpd" "${side}.clones_before" "${side}.others_before" "${side}.ready" "${side}.no_clones"
}

# ready_why: the reason the last signal_case proves nothing because its seam
# never marked the end of the launch, else "".
ready_why() {
  if [[ "$SIG_READY" -ne 1 ]]; then
    echo "the engine never reached the end of its launch (its seam made no ready mark within 15 s), so the signal would have come during the launch and the case proves nothing"
  fi
}

# closed_verdict: "" when the last signal_case ended with status $1 and left no
# Chrome and no profile folder, else the reason.
#
# Its Chrome counts are only proof when the lookup by profile path found that
# Chrome once (pilot issue 30): a path the lookup cannot match (a //
# that Chrome's own --user-data-dir writes with one slash) sees no Chrome
# ever, so "no Chrome left" passed and the signal came only after the
# 30 s wait.
closed_verdict() {
  if [[ "$SIG_UP" -ne 1 ]]; then
    echo "its Chrome was never found by the profile path ${TMPDIR:-/tmp}/sig_<label>.XXXXXX/browser-gate-*, so no Chrome count of the case proves anything"
  elif [[ -n "$CLONE_FEATURE_WHY" ]]; then
    echo "$CLONE_FEATURE_WHY"
  elif [[ -n "$SIG_CLONE_OFF_WHY" ]]; then
    echo "$SIG_CLONE_OFF_WHY"
  elif [[ "$SIG_READY" -ne 1 ]]; then
    ready_why
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
  elif [[ -n "$CLONE_PARENT" && "$SIG_CLONE_MADE" -eq 0 ]]; then
    # Only a case with a parent of the test (53g); never the shared folder.
    echo "no code-sign clone folder appeared for its Chrome, so its removal is not proved"
  elif [[ -n "$CLONE_PARENT" && "$SIG_CLONE_LEFT" -ne 0 && "$SIG_OUT" != *"left for the nightly cleanup"* ]]; then
    # A kept folder is fine when the gate said so; one left without a word is
    # not. That the gate removes its own clone folder is proved by cases 53h and
    # 53i on a folder of the test.
    echo "the code-sign clone folder of its Chrome is left without a word"
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

# 52h: the cleanup of the clone folders (estate issue 617) on a fake parent
# folder. It must not end non-zero when the new folder is already gone (Chrome
# removed it meanwhile; under set -e a non-zero here ended the whole self-test
# silently before proofs R, S and X), must remove only the folders the case made,
# and must fail when a folder cannot be removed.
REAL_CLONE_PARENT="$CLONE_PARENT"
CLONE_PARENT="${TMP}/fake_clones"
mkdir -p "$CLONE_PARENT/code_sign_clone.old"
printf 'code_sign_clone.old\n' > "${TMP}/fake_before"
rc_gone=0
( remove_new_clones "${TMP}/fake_before" ) || rc_gone=$?
mkdir -p "$CLONE_PARENT/code_sign_clone.new" "$CLONE_PARENT/code_sign_clone.foreign"
rc_new=0
( remove_new_clones "${TMP}/fake_before" ) || rc_new=$?
if [[ "$rc_gone" -ne 0 ]]; then
  fail "52h: the cleanup ended with ${rc_gone} when the new clone folder was already gone"
elif [[ "$rc_new" -ne 0 || -e "$CLONE_PARENT/code_sign_clone.new" || ! -d "$CLONE_PARENT/code_sign_clone.old" || ! -d "$CLONE_PARENT/code_sign_clone.foreign" ]]; then
  fail "52h: the cleanup (exit ${rc_new}) did not remove exactly the new clone folder"
else
  echo "  ok: 52h: the clone cleanup survives a vanished folder and removes only the new one"
fi
mkdir -p "$CLONE_PARENT/code_sign_clone.stuck"
chmod a-w "$CLONE_PARENT"
rc_stuck=0
( remove_new_clones "${TMP}/fake_before" ) 2> /dev/null || rc_stuck=$?
chmod u+w "$CLONE_PARENT"
if [[ "$rc_stuck" -eq 0 ]]; then
  fail "52i: a clone folder that cannot be removed did not fail the cleanup"
else
  echo "  ok: 52i: a clone folder that cannot be removed fails the cleanup"
fi
CLONE_PARENT="$REAL_CLONE_PARENT"

# 53j (forsgren#660): the check that the clone is off, without a browser. A flag
# that is missing, repeated or overridden, and a feature this Chrome does not know,
# each give a reason, and closed_verdict is red on it whatever else went well: a
# case can never pass by going back to the shared folder.
PUPPETEER_LINE="/a/Chrome --enable-features=PdfOopif --host-resolver-rules=MAP * ~NOTFOUND --user-data-dir=/t/browser-gate-x"
FEATURES_OFF="Translate,${CLONE_FEATURE},IsolateSandboxedIframes"
FAKE_APP="${TMP}/fake_app/Contents"
mkdir -p "${FAKE_APP}/MacOS" "${FAKE_APP}/Frameworks/Fake Framework.framework/Versions/Current"
FAKE_FRAMEWORK="${FAKE_APP}/Frameworks/Fake Framework.framework/Versions/Current/Fake Framework"
printf 'some\0bytes\0kNothing\0' > "$FAKE_FRAMEWORK"
why_unknown="$(clone_feature_why "${FAKE_APP}/MacOS/Fake")"
printf 'some\0bytes\0k%s\0' "$CLONE_FEATURE" > "$FAKE_FRAMEWORK"
why_known="$(clone_feature_why "${FAKE_APP}/MacOS/Fake")"
why_absent="$(clone_feature_why "${FAKE_APP}/MacOS/Absent")"
SIG_UP=1
SIG_CLONE_OFF_WHY="$(clone_flag_why "${PUPPETEER_LINE} --disable-features=Translate")"
verdict_flag="$(closed_verdict 2)"
SIG_CLONE_OFF_WHY=""
SAVED_FEATURE_WHY="$CLONE_FEATURE_WHY"
CLONE_FEATURE_WHY="not known"
verdict_feature="$(closed_verdict 2)"
CLONE_FEATURE_WHY="$SAVED_FEATURE_WHY"
if [[ -n "$(clone_flag_why "${PUPPETEER_LINE} --disable-features=${FEATURES_OFF}")" ]]; then
  fail "53j: a single --disable-features naming the feature was not taken as off: $(clone_flag_why "${PUPPETEER_LINE} --disable-features=${FEATURES_OFF}")"
elif [[ "$(clone_flag_why "$PUPPETEER_LINE")" != *"without --disable-features"* ]]; then
  fail "53j: a Chrome without the switch was not named"
elif [[ "$(clone_flag_why "${PUPPETEER_LINE} --disable-features=${FEATURES_OFF} --disable-features=Translate")" != *"the last one wins"* ]]; then
  fail "53j: a second --disable-features, which overrides the first, was not named"
elif [[ "$(clone_flag_why "${PUPPETEER_LINE} --disable-features=${CLONE_FEATURE}Rename")" != *"does not name"* ]]; then
  fail "53j: a --disable-features with only a longer name was taken for the feature"
elif [[ "$(clone_flag_why "${PUPPETEER_LINE} --disable-features=${FEATURES_OFF} --enable-features=${CLONE_FEATURE}")" != *"--enable-features of its Chrome names"* ]]; then
  fail "53j: an --enable-features naming the feature was not named"
elif [[ "$(clone_flag_why "")" != *"was not found"* ]]; then
  fail "53j: a Chrome whose command line was not found was not named"
elif [[ "$(uname)" == "Darwin" && ( "$why_unknown" != *"does not know"* || -n "$why_known" || "$why_absent" != *"was not found"* ) ]]; then
  fail "53j: the feature check said '${why_unknown}' for a framework without the name, '${why_known}' for one with it, '${why_absent}' for none"
elif [[ "$verdict_flag" != *"does not name"* ]]; then
  fail "53j: closed_verdict did not go red on a flag that does not name the feature (got '${verdict_flag}')"
elif [[ "$verdict_feature" != "not known" ]]; then
  fail "53j: closed_verdict did not go red on a feature Chrome does not know (got '${verdict_feature}')"
else
  echo "  ok: 53j: a missing, repeated or overridden flag and an unknown feature each fail closed_verdict"
fi

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
if [[ "$SIG_UP" -ne 1 ]]; then
  fail "52f: its Chrome was never found by the profile path, so the count proves nothing"
elif [[ "$SIG_CHROME" -eq 0 ]]; then
  echo "  ok: 52f: SIGKILL to node cannot be handled, but Chrome ends with its pipe"
else
  fail "52f: ${SIG_CHROME} Chrome processes outlived a killed node"
fi
signal_case chrome_killed self error "$GATE"
want_closed "53: Chrome killed mid-run is an error (exit 2) and leaves no Chrome and no profile" 2

# 52g, 53d (site issue 59): Chrome's helper processes outlive the browser
# and still write into the profile folder, as they do on a loaded machine. No
# load is made: a thin wrapper around the real Chrome starts a helper in
# Chrome's own process group (it execs the real Chrome after) that re-creates a
# folder in the profile every 0.1 s until it is killed. Closing the browser does
# not end it; only ending Chrome's process group does. The case is red unless
# the gate ends the group, removes the folder when nothing writes any more, and
# (53d) sees Chrome gone although the helper still holds the pipe.
SLOW_CHROME="${TMP}/chrome_with_helper.sh"
cat > "$SLOW_CHROME" << EOF
#!/usr/bin/env bash
bash -c 'while :; do mkdir -p "\$0/late"; sleep 0.1; done' "\$HOME" &
exec "${CHROME_UNDER_TEST}" "\$@"
EOF
chmod +x "$SLOW_CHROME"
signal_case helper_term self TERM env FORSGREN_CHROME="$SLOW_CHROME" "$GATE"
want_closed "52g: SIGTERM with a Chrome helper that outlives the browser and writes into the profile: no profile left, exit 143" 143
# 53d kills Chrome after the launch (the case is "mid-run"): the seam marks the
# end of the launch and the kill waits for it. On the hosted runner the kill
# came inside the launch, where the helper's copy of the pipe kept puppeteer
# waiting, and the gate still ran 20 s later (run 42089907412).
LAUNCHED_SEAM="${TMP}/launched_seam.cjs"
cat > "$LAUNCHED_SEAM" << 'SEAM'
const fs = require('node:fs');
module.exports = () => { fs.writeFileSync(process.env.FORSGREN_TEST_READY_MARK, 'launched\n'); };
SEAM
SIG_WAIT_READY=1
signal_case helper_killed self error env FORSGREN_CHROME="$SLOW_CHROME" FORSGREN_GATE_BROWSER_HOOK="$LAUNCHED_SEAM" "$GATE"
SIG_WAIT_READY=0
want_closed "53d: Chrome killed mid-run while a helper holds the pipe and writes into the profile: exit 2, no profile left" 2

# 53g (estate issue 617): another Chrome's clone folder appears during the
# launch (the thin wrapper below makes it, as another Chrome starting at the same
# time would, and a process of the test holds a file in it open). The gate cannot
# tell which of the two new folders is its own, so it keeps both and says so;
# the other one is untouched. macOS only. Both folders are made by the wrapper in
# a parent of the test (v33, forsgren#660), where the real Chrome's clone is off.
if [[ "$(uname)" == "Darwin" ]]; then
  CLONE_PARENT="${TMP}/foreign_clones"
  mkdir -p "$CLONE_PARENT"
  FOREIGN="${CLONE_PARENT}/code_sign_clone.foreign$$"
  FOREIGN_CHROME="${TMP}/chrome_with_foreign_clone.sh"
  cat > "$FOREIGN_CHROME" << EOF
#!/usr/bin/env bash
mkdir -p "${CLONE_PARENT}/code_sign_clone.own$$/Google Chrome.app.bundle"
mkdir -p "${FOREIGN}/Google Chrome.app.bundle"
echo held > "${FOREIGN}/Google Chrome.app.bundle/held"
perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' sleep 300 < "${FOREIGN}/Google Chrome.app.bundle/held" 3<&- 4<&- > /dev/null 2>&1 &
echo \$! > "${TMP}/foreign_holder.pid"
exec "${CHROME_UNDER_TEST}" "\$@"
EOF
  chmod +x "$FOREIGN_CHROME"
  signal_case foreign_clone self error env FORSGREN_CHROME="$FOREIGN_CHROME" FORSGREN_GATE_CLONE_PARENT="$CLONE_PARENT" "$GATE"
  FOREIGN_HOLDER="$(cat "${TMP}/foreign_holder.pid" 2> /dev/null || echo 0)"
  if [[ "$SIG_UP" -ne 1 ]]; then
    fail "53g: its Chrome never came up, so the case proves nothing. Output: ${SIG_OUT}"
  elif [[ ! -f "${FOREIGN}/Google Chrome.app.bundle/held" ]]; then
    fail "53g: the clone folder of another Chrome was removed. Output: ${SIG_OUT}"
  elif [[ "$SIG_CLONE_LEFT" -lt 2 ]]; then
    fail "53g: the gate removed a clone folder it could not tell from another Chrome's (left: ${SIG_CLONE_LEFT}). Output: ${SIG_OUT}"
  elif [[ "$SIG_OUT" != *"left for the nightly cleanup"* ]]; then
    fail "53g: the gate kept the folders without saying so. Output: ${SIG_OUT}"
  else
    echo "  ok: 53g: with a second clone folder during the launch, both are kept, said on stderr, the other one untouched"
  fi
  # Site issue 61: the same run, judged as every real-Chrome case is. A clone
  # folder kept because another Chrome may own it is not a failure when the gate
  # says so; v17 called it "still there" and flaked whenever a second Chrome
  # started on the machine during a case.
  want_closed "53g: the same run, judged as a closed run: no Chrome, no profile, the folders kept with the stated reason" 2
  if [[ "$FOREIGN_HOLDER" -gt 0 ]]; then kill "$FOREIGN_HOLDER" || true; fi
  rm -rf "$FOREIGN"
  CLONE_PARENT=""
fi

# 53h, 53i (site issue 61): who owns a clone folder, decided on a folder and a
# process listing of the test (FORSGREN_GATE_CLONE_PARENT, FORSGREN_GATE_PS_LISTING),
# so that no other Chrome on the machine can change the verdict. The fake Chrome
# makes the folder in the test's parent as the launch starts, then runs the real
# one (whose clone is off, v33).
# clone_seam_case <name> <listing text, may be empty>: sets SEAM_PARENT,
# SEAM_FOLDER; the last signal_case is the killed-Chrome run of the gate (or of
# the engine in $SEAM_CMD).
SEAM_CMD=("$GATE")
SEAM_ENV=()
SEAM_EXTRA=""
SEAM_SIG=error
SEAM_RC=2
clone_seam_case() {
  SEAM_PARENT="${TMP}/seam_${1}"
  SEAM_FOLDER="${SEAM_PARENT}/code_sign_clone.own${1}"
  local chrome="${TMP}/chrome_seam_${1}.sh" listing="${TMP}/seam_${1}.ps"
  mkdir -p "$SEAM_PARENT"
  printf '%s' "$2" > "$listing"
  cat > "$chrome" << EOF
#!/usr/bin/env bash
mkdir -p "${SEAM_FOLDER}/Google Chrome.app.bundle"
${SEAM_EXTRA}
exec "${CHROME_UNDER_TEST}" "\$@"
EOF
  chmod +x "$chrome"
  signal_case "seam_${1}" self "$SEAM_SIG" env FORSGREN_CHROME="$chrome" FORSGREN_GATE_CLONE_PARENT="$SEAM_PARENT" FORSGREN_GATE_PS_LISTING="$listing" ${SEAM_ENV[@]+"${SEAM_ENV[@]}"} "${SEAM_CMD[@]}"
}
# seam_verdict: "" when the last clone_seam_case ended 2 with no Chrome and no profile.
seam_verdict() {
  if [[ "$SIG_UP" -ne 1 ]]; then echo "its Chrome never came up"
  elif [[ "$SIG_READY" -ne 1 ]]; then ready_why
  elif [[ "$SIG_RC" != "$SEAM_RC" || "$SIG_ENDED" -ne 1 ]]; then echo "expected exit ${SEAM_RC}, got ${SIG_RC}"
  elif [[ "$SIG_CHROME" -ne 0 || "$SIG_PROFILE" -ne 0 ]]; then echo "Chrome or its profile is left"
  fi
}
clone_seam_case own ""
why="$(seam_verdict)"
if [[ -n "$why" ]]; then
  fail "53h: ${why}. Output: ${SIG_OUT}"
elif [[ -e "$SEAM_FOLDER" ]]; then
  fail "53h: the clone folder made for its own Chrome (nobody else started) was not removed. Output: ${SIG_OUT}"
else
  echo "  ok: 53h: the one new clone folder, no other Chrome starting, is removed after its Chrome is gone"
fi
clone_seam_case foreign "99999 00:01 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
"
why="$(seam_verdict)"
if [[ -n "$why" ]]; then
  fail "53i: ${why}. Output: ${SIG_OUT}"
elif [[ ! -d "$SEAM_FOLDER" ]]; then
  fail "53i: the clone folder was removed although another Chrome started during the launch. Output: ${SIG_OUT}"
elif [[ "$SIG_OUT" != *"another Chrome started during the launch"* ]]; then
  fail "53i: the folder was kept without the reason on stderr. Output: ${SIG_OUT}"
else
  echo "  ok: 53i: with another Chrome starting during the launch the folder is kept and the reason said"
fi

# 54a, 54b (site issue 63): a kept clone folder is never silent, and a helper of
# the gate's own Chrome that is still ending at removal time is waited for.
# 54a: a helper in a session of its own (the group kill misses it) carries the
# profile path in its command line and lives 2 s after Chrome is gone, as a
# slow-to-end helper does on a loaded machine. The folder must be removed all the
# same (browser_gate v12 kept it).
cat > "${TMP}/seam_extra.txt" << 'EXTRA'
for a in "$@"; do case "$a" in --user-data-dir=*) UD="$a";; esac; done
perl -MPOSIX -e "POSIX::setsid(); exec @ARGV" bash -c "while kill -0 \$1 2> /dev/null; do sleep 0.1; done; sleep 2" "$UD" $$ < /dev/null > /dev/null 2>&1 3<&- 4<&- &
EXTRA
SEAM_EXTRA="$(cat "${TMP}/seam_extra.txt")"
SEAM_SIG=TERM
SEAM_RC=143
clone_seam_case helper ""
SEAM_EXTRA=""
why="$(seam_verdict)"
SEAM_SIG=error
SEAM_RC=2
if [[ -n "$why" ]]; then
  fail "54a: ${why}. Output: ${SIG_OUT}"
elif [[ -e "$SEAM_FOLDER" ]]; then
  fail "54a: the clone folder was kept because a helper of its Chrome was still ending, instead of waiting for it. Output: ${SIG_OUT}"
else
  echo "  ok: 54a: a helper still ending at removal time is waited for, then the clone folder is removed"
fi
# 54b: the folder identified for the Chrome is replaced by another one after
# the launch; the gate does not remove it and must say why. On macOS the new
# folder has a new inode; on Linux (ext4) it may get the removed folder's inode
# back, and only its birth time tells it apart (browser_gate v19).
# The swap runs on the next turn of the engine's event loop after the hook, so
# after the identification, which the engine does synchronously right after the
# hook returns, and it marks itself done (FORSGREN_TEST_READY_MARK); the kill
# waits for the mark. v23 swapped on an 800 ms timer and killed once a renderer
# showed: on the hosted runner the kill came first (or inside the launch, with
# no hook called at all), so the folder was never replaced (run 42138308615).
HOOK_SWAP="${TMP}/hook_swap.cjs"
cat > "$HOOK_SWAP" << 'SEAM'
const fs = require('node:fs');
module.exports = () => {
  const folder = process.env.FORSGREN_TEST_SWAP_FOLDER;
  setImmediate(() => {
    if (process.env.FORSGREN_TEST_ADD_ONLY) {
      fs.mkdirSync(`${folder}late/Google Chrome.app.bundle`, { recursive: true });
    } else {
      fs.rmSync(folder, { recursive: true, force: true });
      fs.mkdirSync(`${folder}/Google Chrome.app.bundle`, { recursive: true });
    }
    fs.writeFileSync(process.env.FORSGREN_TEST_READY_MARK, 'swapped\n');
  });
};
SEAM
SEAM_ENV=(FORSGREN_GATE_BROWSER_HOOK="$HOOK_SWAP" FORSGREN_TEST_SWAP_FOLDER="${TMP}/seam_swap/code_sign_clone.ownswap")
SIG_WAIT_READY=1
clone_seam_case swap ""
SIG_WAIT_READY=0
SEAM_ENV=()
why="$(seam_verdict)"
if [[ -n "$why" ]]; then
  fail "54b: ${why}. Output: ${SIG_OUT}"
elif [[ ! -d "$SEAM_FOLDER" ]]; then
  fail "54b: the folder that replaced the identified one was removed. Output: ${SIG_OUT}"
elif [[ "$SIG_OUT" != *"left for the nightly cleanup (estate issue 617)"* || "$SIG_OUT" != *"replaced"* ]]; then
  fail "54b: the gate kept a clone folder without saying why. Output: ${SIG_OUT}"
else
  echo "  ok: 54b: a clone folder replaced after the launch is kept and the reason said"
fi
# 54c: another new clone folder appears after the launch (the folder identified
# was this Chrome's; this is some other Chrome's, or the case of the identified
# one being another's): it stays and the gate says so.
SEAM_ENV=(FORSGREN_GATE_BROWSER_HOOK="$HOOK_SWAP" FORSGREN_TEST_ADD_ONLY=1 FORSGREN_TEST_SWAP_FOLDER="${TMP}/seam_late/code_sign_clone.ownlate")
SIG_WAIT_READY=1
clone_seam_case late ""
SIG_WAIT_READY=0
SEAM_ENV=()
why="$(seam_verdict)"
if [[ -n "$why" ]]; then
  fail "54c: ${why}. Output: ${SIG_OUT}"
elif [[ -e "$SEAM_FOLDER" || ! -d "${SEAM_FOLDER}late" ]]; then
  fail "54c: the folder of its Chrome was kept, or the late one removed. Output: ${SIG_OUT}"
elif [[ "$SIG_OUT" != *"left for the nightly cleanup (estate issue 617)"* || "$SIG_OUT" != *"remain"* ]]; then
  fail "54c: a clone folder was left without saying so. Output: ${SIG_OUT}"
else
  echo "  ok: 54c: a new clone folder that is not the identified one is kept and said"
fi

# 53e (site issue 60): the night run of a loaded machine took more than 20 s
# to end after Chrome was killed. No load is made: a preload slows only the gate's
# own calls, as load does: close() never answers, the killed group still shows
# for kill(-pgid, 0) for 8 s (slow reaping), and the file system needs 14 s for
# the profile. The run must end at once all the same: a dead Chrome is not
# closed, zombies do not count as a running group, the removal does not block.
LOAD_SEAM="${TMP}/load_seam.cjs"
LOAD_MARKS="${TMP}/load_seam.marks"
: > "$LOAD_MARKS"
cat > "$LOAD_SEAM" << SEAM
const fs = require('node:fs');
const mark = (name) => fs.appendFileSync('${LOAD_MARKS}', name + '\\n');
const kill = process.kill.bind(process);
const killed = new Map();
process.kill = (pid, sig) => {
  if (pid < 0 && sig === 'SIGKILL') killed.set(pid, Date.now());
  if (pid < 0 && sig === 0 && killed.has(pid) && Date.now() - killed.get(pid) < 8000) { mark('reaping'); return true; }
  return kill(pid, sig);
};
// The engine removes folders with fs.promises.rm (not rmSync): the removal is
// done, its answer comes 14 s late.
const rm = fs.promises.rm;
fs.promises.rm = async (...a) => { mark('files'); await rm(...a); await new Promise((resolve) => setTimeout(resolve, 14000)); };
// The engine calls this with its browser (FORSGREN_GATE_BROWSER_HOOK): a
// module namespace of puppeteer-core cannot be assigned to, so the launch is
// not patched from here. Once the close() that never answers is in place it
// marks the end of the launch (FORSGREN_TEST_READY_MARK), which the kill waits
// for: the case is "mid-run", so a kill inside the launch proves nothing.
module.exports = (browser) => {
  browser.close = () => { mark('close'); return new Promise(() => {}); };
  mark('hooked');
  fs.writeFileSync(process.env.FORSGREN_TEST_READY_MARK, 'hooked\n');
};
SEAM
# v24 killed once a renderer showed: on the hosted runner that came inside the
# launch (run 42156971812), so the launch failed, the engine never called the
# seam ('hooked' missing), had no browser whose group it could kill ('reaping'
# missing) and removed only the profile and the clone folder ('files files').
SIG_WAIT_READY=1
signal_case loaded_killed self error env NODE_OPTIONS="--require=${LOAD_SEAM}" FORSGREN_GATE_BROWSER_HOOK="$LOAD_SEAM" "$GATE"
SIG_WAIT_READY=0
want_closed "53e: Chrome killed mid-run on a loaded machine (slow reaping, close() never answers, slow file system): exit 2, no profile left, at once" 2
# The case proves nothing unless each slowdown happened (site issue 61: the
# launch patch was silently ignored for a long time). A killed Chrome is never
# closed (v10), so the close() that never answers is proven by being installed.
for seam_mark in hooked reaping files; do
  if ! grep -qx "$seam_mark" "$LOAD_MARKS"; then
    fail "53e: the slowdown '${seam_mark}' was never observed, so the case proves nothing about a loaded machine. Seen: $(tr '\n' ' ' < "$LOAD_MARKS")"
  else
    echo "  ok: 53e: the slowdown '${seam_mark}' was observed"
  fi
done

# 53f (forsgren#630, browser_gate v17; here since v29, forsgren#636): Chrome
# killed during the launch while another process holds its pipe. The pipe holder
# is the helper of cases 52g and 53d: a thin wrapper starts a process in Chrome's
# own process group that inherits the pipe and writes into the profile until it
# is killed, then execs the real Chrome. Puppeteer's launch never sees the pipe
# close, so an engine that waits for it waits for the holder (here for good: this
# holder never ends by itself). Chrome's command end of the pipe (fd 3) is a FIFO
# nobody writes, so it never answers and the launch is still on when Chrome is
# killed, whatever the machine's speed. The engine must see Chrome's own process
# end and end the run within HELD_BOUND seconds with a FAIL that names it: died
# during the launch, its PID and its exit status.
HOLDER_PIDS="${TMP}/holder.pids"
: > "$HOLDER_PIDS"
DEAF_FIFO="${TMP}/deaf.fifo"
mkfifo "$DEAF_FIFO"
HELD_CHROME="${TMP}/held_chrome.sh"
cat > "$HELD_CHROME" << EOF
#!/usr/bin/env bash
bash -c 'while :; do mkdir -p "\$0/late"; sleep 0.1; done' "\$HOME" &
echo \$! >> "${HOLDER_PIDS}"
exec "${CHROME_UNDER_TEST}" "\$@" --no-startup-window 3<> "${DEAF_FIFO}"
EOF
chmod +x "$HELD_CHROME"
HELD_FAIL='FAIL: browser gate: Chrome died during the launch \(PID [0-9]+, (exit [0-9]+|signal SIG[A-Z0-9]+)\)'
HELD_BOUND=10
# end_holders: a pipe holder that outlived its case (an engine that never ended
# Chrome's group) is ended here, so it cannot hold on into the next case.
end_holders() {
  local holder
  while IFS= read -r holder; do
    if [[ -n "$holder" ]]; then kill -9 "$holder" 2> /dev/null || true; fi
  done < "$HOLDER_PIDS"
  : > "$HOLDER_PIDS"
}
# held_verdict: "" when the last signal_case is closed with exit 2 and its output
# names the death during the launch, else the reason.
held_verdict() {
  local why
  why="$(closed_verdict 2)"
  if [[ -n "$why" ]]; then
    echo "$why"
  elif ! [[ "$SIG_OUT" =~ $HELD_FAIL ]]; then
    echo "the output does not name Chrome's death during the launch with its PID and exit status (a kill after the launch proves nothing here)"
  fi
}
SIG_WAIT_S="$HELD_BOUND" signal_case chrome_killed_held self held env "FORSGREN_CHROME=${HELD_CHROME}" "$GATE"
end_holders
HELD_WHY="$(held_verdict)"
if [[ -n "$HELD_WHY" ]]; then
  fail "53f: Chrome killed during the launch while a helper holds its pipe should end the run within ${HELD_BOUND} s, named: ${HELD_WHY}. Output: ${SIG_OUT}"
else
  echo "  ok: 53f: Chrome killed during the launch while a helper holds its pipe ends the run within ${HELD_BOUND} s with a FAIL naming it, its PID and its exit status"
fi
echo "browser gate self-test: the cases of SERIAL_CASES before the mutation proofs, one after the other: $((SECONDS - PHASE_START)) s"
}
# serial is one unit: its first case stands for all of them.
if runs "serial_${SERIAL_CASES[0]}"; then
  serial_cases
fi

# 55a, 55b, 55c (estate issue 629, step 2): a gate that ends non-zero always
# says why. The red of the first site run ended after 82 warnings in the middle
# of a line, without a FAIL line: the engine wrote to a pipe and ended with
# process.exit(), which drops what a pipe has not yet taken. Three seams make
# the engine end in three silent ways; each must leave a named FAIL line.
# 55a: the engine's report (the findings, printed just before it exits 1) is
# preceded by 1 MiB of text, through the wrapper's fifo: the finding must
# arrive whole, as the last line. On v15 the output stopped at 8192 bytes.
BIG_SEAM="${TMP}/big_seam.cjs"
cat > "$BIG_SEAM" << 'SEAM'
module.exports = () => {
  const log = console.log;
  console.log = (...parts) => log('WARN: seam padding ' + 'x'.repeat(1 << 20) + '\n' + parts.join(' '));
};
SEAM
case_55a() {
  own_fixtures nocharset
  FORSGREN_GATE_BROWSER_HOOK="$BIG_SEAM" run_gate nocharset
  want_red "55a: 1 MiB of output, then a finding: the finding line arrives" "charset not declared"
  if [[ "$(tail -n 1 <<< "$OUT")" != "FAIL: "*"charset not declared"* ]]; then
    fail "55a: the last line of the output is not the whole FAIL line. Last: $(tail -n 1 <<< "$OUT" | cut -c1-200)"
  fi
}
# 55b: an error nobody catches (a timer in the engine throws): a named FAIL
# line and exit 2, not a bare stack.
THROW_SEAM="${TMP}/throw_seam.cjs"
cat > "$THROW_SEAM" << 'SEAM'
module.exports = () => { setTimeout(() => { throw new Error('seam boom'); }, 200); };
SEAM
case_55b() {
  own_fixtures clean
  FORSGREN_GATE_BROWSER_HOOK="$THROW_SEAM" run_gate clean
  want_exit "55b: an uncaught error in the engine: exit 2 and a FAIL line naming it" 2 "FAIL: browser gate: uncaught error: seam boom"
}
# 55c: the engine killed by a signal it cannot catch: the wrapper names the
# signal and says the engine printed no reason.
KILL_SEAM="${TMP}/kill_seam.cjs"
cat > "$KILL_SEAM" << 'SEAM'
module.exports = () => { process.kill(process.pid, 'SIGKILL'); };
SEAM
case_55c() {
  own_fixtures clean
  FORSGREN_GATE_BROWSER_HOOK="$KILL_SEAM" run_gate clean
  want_exit "55c: the engine killed (SIGKILL): the wrapper names the signal" 137 "FAIL: browser gate: the engine was killed by signal KILL (exit 137)"
}

# Mutation proofs, run side by side (Scripts/lib_parallel_mutants.sh, forsgren#382).
# Each proof is a mutant_<letter> function that works on its own copy of the
# fixture (staged here from the fixture as made, with the file the proof's case
# writes) and on its own engine copy under $MUTANT_DIR, so no two share a path.
# The engine copy is run directly, with the real node_modules. Their output comes
# back in the order they were started, each line with its own reason; a mutation
# that changes nothing is a failed proof (selftest_mutant), and a proof that
# aborts fails too. They run in the second batch, with the plain cases 19 to 21
# and 55a to 55c (v26, forsgren#632).

# stage <tag> <fixture>: the proof's own copy of the fixture as it is now.
stage() {
  rm -rf "${TMP}/fx_$1"
  cp -R "${TMP}/$2" "${TMP}/fx_$1"
}

# at_fixture <fixture-dir> <command> [args...]: the command on that fixture, captured.
at_fixture() {
  local dir="$1"
  shift
  capture "$@" "${dir}/site" "${dir}/manifest.json" "${dir}/exceptions.txt" "${dir}/baseline.txt" "${dir}/variants.txt"
}

# run_mutant <engine> <fixture-dir>: the engine copy on the real setting.
run_mutant() {
  FORSGREN_NODE_ROOT="$REPO_ROOT" at_fixture "$2" env -u FORSGREN_CLS_LOADS -u FORSGREN_CLS_INTERVAL_MS node "$1"
}

# mutant_engine <sed-expression>: this proof's engine copy, MUTANT_ENGINE, and the start
# of its seconds; fails (returns 1) when the mutation changed nothing.
mutant_engine() {
  LAP=$SECONDS
  MUTANT_ENGINE="${MUTANT_DIR}/engine.mjs"
  selftest_mutant "$ENGINE" "$MUTANT_ENGINE" "$1"
}

# A: only critical gates -> the serious fixture turns green.
stage a serious
mutant_a() {
  if mutant_engine "s/\['serious', 'critical'\]/['critical']/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_a"
    want_green "mutation proof A: ignoring serious turns case 2 green" "OK:"
  fi
}

# B: the CLS compared rounded -> a growth of 0.1 percent turns green (case 19).
printf 'cls|light|/|%s|%s\n' "$(scaled 0.999)" "$REASON" > "${TMP}/shift/baseline.txt"
stage b shift
mutant_b() {
  if mutant_engine "s/^const compared = .*/const compared = (value) => Math.round(value * 100);/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_b"
    want_green "mutation proof B: a rounded CLS comparison turns case 19 green" "OK:"
  fi
}

# C: a 404 read only from network-failure events -> case 7 no longer says 404.
stage c notfound
mutant_c() {
  if mutant_engine "s/page.on('response'/page.on('response-ignored'/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_c"
    if grep -qF -- "request /missing.png -> 404" <<< "$OUT"; then
      fail "mutation proof C: the 404 was still named without the response status. Output: ${OUT}"
    else
      echo "  ok: mutation proof C: without the response status case 7 loses its 404"
    fi
  fi
}

# D: the baseline match ignores the selector -> a new element on a baselined
# rule turns green. The fixture is case 17's: only #a is in the baseline.
printf 'axe|light|/|color-contrast|#a|%s\n' "$REASON" > "${TMP}/two/baseline.txt"
stage d two
mutant_d() {
  if mutant_engine 's/^\(const axeKey = .*\)[$]{selector}\(.*\)$/\1\2/'; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_d"
    want_green "mutation proof D: ignoring the selector turns case 17 green" "OK:"
  fi
}

# E: the stale check removed -> a baselined finding that is gone turns green.
printf 'axe|light|/|color-contrast|#a|%s\naxe|light|/|color-contrast|#b|%s\naxe|light|/|color-contrast|#gone|%s\n' "$REASON" "$REASON" "$REASON" > "${TMP}/two/baseline.txt"
stage e two
mutant_e() {
  if mutant_engine "s/if (!row.seen)/if (false \&\& !row.seen)/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_e"
    want_green "mutation proof E: without the stale check case 18 turns green" "OK:"
  fi
}

# F: an attr: variant not applied -> the dark look is never checked, case 30 green.
: > "${TMP}/themed/baseline.txt"
stage f themed
mutant_f() {
  if mutant_engine "s/if (variant.attr) await/if (false \&\& variant.attr) await/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_f"
    want_green "mutation proof F: an unapplied attr: variant turns case 30 green" "OK:"
  fi
}

# G: the scheme not emulated per variant -> case 33 turns green.
stage g schemed
mutant_g() {
  if mutant_engine "s/value: variant.scheme/value: 'light'/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_g"
    want_green "mutation proof G: an unemulated scheme turns case 33 green" "OK:"
  fi
}

# H: the override ignored -> the 50 ms of case 37 is not read.
stage h clean
mutant_h() {
  if mutant_engine "s/envPositive('FORSGREN_CLS_INTERVAL_MS', 1000)/1000/"; then
    FORSGREN_CLS_LOADS=2 FORSGREN_CLS_INTERVAL_MS=50 FORSGREN_NODE_ROOT="$REPO_ROOT" at_fixture "${TMP}/fx_h" node "$MUTANT_ENGINE"
    if grep -qF -- "interval 50 ms" <<< "$OUT"; then
      fail "mutation proof H: the override was still read. Output: ${OUT}"
    else
      echo "  ok: mutation proof H: an ignored override loses case 37's 50 ms"
    fi
  fi
}

# I: the default interval changed -> case 15 loses its 1000 ms.
stage i clean
mutant_i() {
  if mutant_engine "s/envPositive('FORSGREN_CLS_INTERVAL_MS', 1000)/envPositive('FORSGREN_CLS_INTERVAL_MS', 500)/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_i"
    if grep -qF -- "interval 1000 ms" <<< "$OUT"; then
      fail "mutation proof I: the default interval was still 1000 ms. Output: ${OUT}"
    else
      echo "  ok: mutation proof I: a changed default interval loses case 15's 1000 ms"
    fi
  fi
}

# J: the default loads changed -> case 8a loses its 5 cold loads.
stage j shift
mutant_j() {
  if mutant_engine "s/envPositive('FORSGREN_CLS_LOADS', 5)/envPositive('FORSGREN_CLS_LOADS', 3)/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_j"
    if grep -qF -- "largest of 5 cold loads" <<< "$OUT"; then
      fail "mutation proof J: the default was still 5 loads. Output: ${OUT}"
    else
      echo "  ok: mutation proof J: a changed default load count loses case 8a's 5 cold loads"
    fi
  fi
}

# K: a layout-shift case given a too short setting turns green: why cases 8 and
# 19-23 keep the real values. Ordered by the test, not by the clock (forsgren#252,
# #275, #384): the fixture moves one tick after the gate's first read of the
# shifts, so the 1 ms read is before the shift on any machine, however long the
# load or the gate's own work took. K asserts the reason: the short setting is
# the one the gate ran with (the OK line says 1 ms) and the same code moving two
# frames after the load is red on the real setting, so only the setting hid it.
: > "${TMP}/lateshift/baseline.txt"
stage k lateshift
stage kcontrol earlyshift
mutant_k() {
  LAP=$SECONDS
  FORSGREN_CLS_LOADS=1 FORSGREN_CLS_INTERVAL_MS=1 at_fixture "${TMP}/fx_k" "$GATE"
  want_green "mutation proof K: a shift case on a too short setting turns green" "interval 1 ms)"
  capture env -u FORSGREN_CLS_LOADS -u FORSGREN_CLS_INTERVAL_MS "$GATE" "${TMP}/fx_kcontrol/site" "${TMP}/fx_kcontrol/manifest.json" "${TMP}/fx_kcontrol/exceptions.txt" "${TMP}/fx_kcontrol/baseline.txt" "${TMP}/fx_kcontrol/variants.txt"
  want_red "mutation proof K, control: the same code moving after the load, on the real setting, is red" "CLS 0."
}
# K with a delayed load (forsgren#275): the 1 ms read still misses the shift
# that follows the read, whatever the load took.
: > "${TMP}/lateshiftslow/baseline.txt"
stage kslow lateshiftslow
mutant_kslow() {
  LAP=$SECONDS
  FORSGREN_CLS_LOADS=1 FORSGREN_CLS_INTERVAL_MS=1 at_fixture "${TMP}/fx_kslow" "$GATE"
  want_green "mutation proof K, delayed load: a 1 ms read still misses the shift" "interval 1 ms)"
}

# L: the sideways-scroll check removed -> case 41 turns green.
stage l phonewide
mutant_l() {
  if mutant_engine "s/^    await check.checkSideways();/    \/\/ removed/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_l"
    want_green "mutation proof L: without the sideways-scroll check case 41 turns green" "OK:"
  fi
}

# M: the comparison loosened -> an overflow of 210 px passes, case 41 turns green.
stage m phonewide
mutant_m() {
  if mutant_engine "s/^const scrollsSideways = .*/const scrollsSideways = (px) => px > 1000;/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_m"
    want_green "mutation proof M: a loosened comparison turns case 41 green" "OK:"
  fi
}

# N: the growth comparison dropped -> case 46 turns green.
printf 'sideways|light|/|390x844|table 1|209|%s\n' "$REASON" > "${TMP}/phonewide/baseline.txt"
stage n phonewide
mutant_n() {
  if mutant_engine "s/^    if (px > row.px) {/    if (false) {/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_n"
    want_green "mutation proof N: without the growth comparison case 46 turns green" "OK:"
  fi
}

# O: the stale check of the sideways rows removed -> case 48 turns green.
printf 'sideways|light|/|390x844|table 1|210|%s\nsideways|light|/|1280x800|table 1|5|%s\n' "$REASON" "$REASON" > "${TMP}/phonewide/baseline.txt"
stage o phonewide
mutant_o() {
  if mutant_engine "s/if (!row.seen) findings.push(\`FAIL: stale baseline row: \${row.key}|\${row.text} no longer/if (false) findings.push(\`FAIL: stale baseline row: \${row.key}|\${row.text} no longer/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_o"
    want_green "mutation proof O: without the sideways stale check case 48 turns green" "OK:"
  fi
}

# P: the CLS read moved back after the axe run (the order before forsgren#377)
# -> case 50 turns red. Asserted the other way round: the mutant is red on it.
stage p readorder
mutant_p() {
  if mutant_engine "s/^    await check.checkLayoutShift();/    \/\/ moved/;s/^    await check.checkAxe();/    await check.checkAxe(); await check.checkLayoutShift();/"; then
    FORSGREN_CLS_LOADS="$SHORT_CLS_LOADS" FORSGREN_CLS_INTERVAL_MS="$SHORT_CLS_INTERVAL_MS" FORSGREN_NODE_ROOT="$REPO_ROOT" at_fixture "${TMP}/fx_p" node "$MUTANT_ENGINE"
    want_red "mutation proof P: a CLS read after the axe run turns case 50 red" "CLS 0.5"
  fi
}

# Q: the page scrollbar not taken away while measuring -> case 51 says 225.
stage q scrollbar
mutant_q() {
  if mutant_engine "s/^  html.style.setProperty('scrollbar-gutter', 'auto', 'important');/  \/\/ kept/"; then
    run_mutant "$MUTANT_ENGINE" "${TMP}/fx_q"
    want_said "mutation proof Q: with the scrollbar kept, case 51 measures 225 px" "table 1 is 225 px wider than its box"
  fi
}

# T: the delayed-delivery load removed -> case 55 turns green: only that load
# sees the page painted before its wide rows arrive.
stage t unheld
mutant_t() {
  if mutant_engine "s/^    this.pieced = true;/    this.pieced = false;/"; then
    FORSGREN_CLS_LOADS="$SHORT_CLS_LOADS" FORSGREN_CLS_INTERVAL_MS="$SHORT_CLS_INTERVAL_MS" FORSGREN_NODE_ROOT="$REPO_ROOT" at_fixture "${TMP}/fx_t" node "$MUTANT_ENGINE"
    want_green "mutation proof T: without the delayed-delivery load case 55 turns green" "CLS worst 0 "
  fi
}

# U: the pieces sent without the pause and without the wait for the paint ->
# case 55 turns green: the pause and that wait are what let the browser paint
# between two pieces.
stage u unheld
mutant_u() {
  if mutant_engine "s/^const DELIVERY_GAP_MS = .*/const DELIVERY_GAP_MS = 0;/;s/^      await delivery.settle();/      \/\/ kept/"; then
    FORSGREN_CLS_LOADS="$SHORT_CLS_LOADS" FORSGREN_CLS_INTERVAL_MS="$SHORT_CLS_INTERVAL_MS" FORSGREN_NODE_ROOT="$REPO_ROOT" at_fixture "${TMP}/fx_u" node "$MUTANT_ENGINE"
    want_green "mutation proof U: pieces without a pause turn case 55 green" "CLS worst 0 "
  fi
}

# Y: the wait for the paint removed, the 150 ms kept -> case 57 turns green: only
# that wait holds the pieces back while a slow page has not painted (forsgren#620).
stage y unheldslow
mutant_y() {
  if mutant_engine "s/^      await delivery.settle();/      \/\/ kept/"; then
    FORSGREN_CLS_LOADS="$SHORT_CLS_LOADS" FORSGREN_CLS_INTERVAL_MS="$SHORT_CLS_INTERVAL_MS" FORSGREN_NODE_ROOT="$REPO_ROOT" at_fixture "${TMP}/fx_y" node "$MUTANT_ENGINE"
    want_green "mutation proof Y: without the wait for the paint case 57 turns green" "CLS worst 0 "
  fi
}

# The second batch: the plain cases that waited for case 8's M, the exit cases
# 55a to 55c, and the mutation proofs, side by side.
PHASE_START=$SECONDS
for id in "${SECOND_CASES[@]}"; do
  if runs "case_${id}"; then plain_case "$id"; fi
done
for proof in "${SECOND_PROOFS[@]}"; do
  if runs "mutant_${proof}"; then mutant_run "mutant_${proof}"; fi
done
mutants_wait
echo "browser gate self-test: the second batch (19 to 21, 55a to 55c, the mutation proofs), side by side: $((SECONDS - PHASE_START)) s"

# The proofs of the exits (R, S, X, Z) drive real signal cases (signal_case): they signal and
# kill processes, share the machine's clone folders and Chrome listing (a case counts the
# clone folders and Chromes that appear while it runs) and the globals SIG_* and SEAM_*, and
# Z shares the marks file. They are written as mutant functions like the others, but each is
# started alone and collected (mutants_wait) before the next starts, so no two run together
# and no case sees another's Chrome or clone folder. Without the library, mutant_run runs
# each one after the other all the same.

# R: no signal handler in the engine (the event name is one no signal sends) ->
# a SIGTERM kills the engine; Chrome ends with its pipe, the profile stays. Its
# Chrome is stalled for 15 s, past v26's fixed 10 s (forsgren#630): a wait that
# does not follow Chrome's end would see it alive and give the wrong reason.
mutant_r() {
  if mutant_engine "s/process.on(name, /process.on(name + 'x', /"; then
    SIG_STALL_CHROME=15
    signal_case mutant_r self TERM env FORSGREN_NODE_ROOT="$REPO_ROOT" node "$MUTANT_ENGINE"
    want_left "mutation proof R: without the handler case 52e leaves the profile" 143 "the profile folder is still there"
  fi
}

# Rb (v27, forsgren#630): the bound of the wait for Chrome is a FAIL that names what
# it waited for. The same mutated engine with a bound of 3 s and a Chrome stalled for
# 8 s: the reason names the PIDs left, the node whose pipe end closed and the 3 s.
RB_WANTED='Chrome processes of the gate are still alive 3 s after the gate ended, the other end of their pipe \(node PID [0-9]+\) closed: PIDs [0-9]+'
mutant_rb() {
  local why
  if mutant_engine "s/process.on(name, /process.on(name + 'x', /"; then
    SIG_STALL_CHROME=8
    SIG_GONE_BOUND=3
    signal_case mutant_rb self TERM env FORSGREN_NODE_ROOT="$REPO_ROOT" node "$MUTANT_ENGINE"
    why="$(closed_verdict 143)"
    if [[ "$why" =~ $RB_WANTED ]]; then
      echo "  ok: mutation proof Rb: a Chrome alive past the bound is named with its PIDs, its pipe's node and the 3 s waited"
    else
      fail "mutation proof Rb: a Chrome alive past the bound of 3 s should be named with its PIDs, its pipe's node and the seconds, got '${why}'. Output: ${SIG_OUT}"
    fi
  fi
}

# S: the wrapper does not forward the signal -> it ends, node and Chrome stay.
# It asserts the Chrome left, never which branch of the wait it took: whether
# node still holds the pipe when the wait begins is timing (v28, forsgren#630),
# and either branch ends within 10 s (SIG_GONE_BOUND, as proof Rb sets it).
mutant_s() {
  local wmut="${MUTANT_DIR}/wmut"
  mkdir -p "${wmut}/Scripts"
  cp Scripts/browser_gate.mjs "${wmut}/Scripts/"
  # The libraries the wrapper sources, read from it, so a library it gains comes
  # along (forsgren#642: lib_browser_baseline.sh).
  while IFS= read -r lib; do cp "$lib" "${wmut}/Scripts/"; done < <(sed -n 's#^source \(Scripts/lib_[a-z_]*\.sh\)$#\1#p' Scripts/gate_browser.sh)
  ln -s "${REPO_ROOT}/node_modules" "${wmut}/node_modules"
  if selftest_mutant Scripts/gate_browser.sh "${wmut}/Scripts/gate_browser.sh" 's/if \[\[ -n "[$]NODE_PID" \]\]; then/if false; then/'; then
    SIG_GONE_BOUND=10
    signal_case mutant_s self TERM "${wmut}/Scripts/gate_browser.sh"
    want_left "mutation proof S: without forwarding case 52a leaves Chrome alive" 143 "Chrome processes of the gate are still alive"
  fi
}

# X (site proof T, renamed: T is the delayed-delivery load here): the identified clone folder is never removed -> case 53h leaves it.
mutant_x() {
  if mutant_engine "s/await attempt(clone.folder, 'Chrome code-sign clone folder');//"; then
    # Through the seamed case 53h (site issue 61), so that other Chromes on the
    # machine cannot hide the missing removal.
    SEAM_CMD=(env FORSGREN_NODE_ROOT="$REPO_ROOT" node "$MUTANT_ENGINE")
    clone_seam_case mutt ""
    SEAM_CMD=("$GATE")
    if [[ -d "$SEAM_FOLDER" && -z "$(seam_verdict)" ]]; then
      echo "  ok: mutation proof X: without the removal case 53h leaves the clone folder"
    else
      fail "mutation proof X: without the removal case 53h should leave the clone folder (verdict: '$(seam_verdict)'). Output: ${SIG_OUT}"
    fi
  fi
}

# Z (site proof U, renamed: U is the pieces without a pause here; site issue 61): the engine never calls the seam -> case 53e's slowdown is
# not installed, which its marker check must see (before v18 this passed unseen).
mutant_z() {
  if mutant_engine "s/if (process.env.FORSGREN_GATE_BROWSER_HOOK) require/if (false) require/"; then
    : > "$LOAD_MARKS"
    signal_case mutant_z self error env FORSGREN_NODE_ROOT="$REPO_ROOT" NODE_OPTIONS="--require=${LOAD_SEAM}" FORSGREN_GATE_BROWSER_HOOK="$LOAD_SEAM" node "$MUTANT_ENGINE"
    if grep -qx hooked "$LOAD_MARKS"; then
      fail "mutation proof Z: with the seam call removed the slowdown was still installed, so case 53e cannot see a dead seam"
    else
      echo "  ok: mutation proof Z: without the seam call 'hooked' is never marked, and case 53e would be red"
    fi
  fi
}

# Dh (the process self-test's proof D up to its v4, forsgren#630; here since v29,
# forsgren#636; D here is the baseline selector): the engine never hears
# Chrome's process end during the launch -> case 53f waits for the pipe holder
# and still runs after its bound.
mutant_dh() {
  local why
  if mutant_engine "s/child.once('exit', died);/child.once('exit-never', died);/"; then
    SIG_WAIT_S="$HELD_BOUND" signal_case mutant_dh self held env "FORSGREN_CHROME=${HELD_CHROME}" FORSGREN_NODE_ROOT="$REPO_ROOT" node "$MUTANT_ENGINE"
    end_holders
    why="$(held_verdict)"
    if [[ "$why" == "the gate was still running ${HELD_BOUND} s after the signal" ]]; then
      echo "  ok: mutation proof Dh: without the watch on Chrome's process case 53f still runs ${HELD_BOUND} s after the kill"
    else
      fail "mutation proof Dh: without the watch on Chrome's process case 53f should still run ${HELD_BOUND} s after the kill, got '${why}'. Output: ${SIG_OUT}"
    fi
  fi
}

PHASE_START=$SECONDS
for proof in "${SERIAL_PROOFS[@]}"; do
  if runs "mutant_${proof}"; then
    mutant_run "mutant_${proof}"
    mutants_wait
  fi
done
echo "browser gate self-test: the proofs R, Rb, S, X, Z and Dh, one after the other: $((SECONDS - PHASE_START)) s"

# Every case_ function is in a phase list and, when this run holds it, was
# started: a case written and never started would pass unseen.
ALL_IDS="$(all_ids)"
while IFS= read -r case_fn; do
  if [[ $'\n'"${ALL_IDS}"$'\n' != *$'\n'"${case_fn}"$'\n'* ]]; then
    fail "${case_fn}: a plain case that is defined but in no phase list"
  elif runs "$case_fn" && [[ "$PLAIN_STARTED" != *" ${case_fn#case_} "* ]]; then
    fail "${case_fn}: a plain case that is defined but never started"
  fi
done < <(declare -F | awk '$3 ~ /^case_/ {print $3}')

echo "browser gate self-test: ${SECONDS} s in total"
if [[ -n "$SHARD_N" ]]; then
  selftest_end "the browser gate self-test (shard ${SHARD_N}/${SHARD_M}) failed" \
    "browser gate (shard ${SHARD_N}/${SHARD_M}): every case of the shard holds, $(grep -c '^mutant_' <<< "$RUN_IDS" || true) mutation proofs seen"
else
  selftest_end "the browser gate self-test failed" "browser gate: every case holds, twenty-six mutations seen"
fi
