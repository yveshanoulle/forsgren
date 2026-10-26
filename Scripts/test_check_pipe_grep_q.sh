#!/usr/bin/env bash
# canon: test_check_pipe_grep_q v1
# Scripts/test_check_pipe_grep_q.sh
#
# Self-test of Scripts/check_pipe_grep_q.sh (forsgren#428) and of the helper it
# sends scripts to, Scripts/lib_has.sh: fixture trees written under $TMP, one
# script per case, each shape of a producer piped into a quiet grep red and the
# shapes beside it green, a mutation proof per pattern, and the helper finding
# a pattern after more output than a pipe holds, which the plain pipe does not.
#
# The fixture text is built from parts (GREP, the line formats): a line of this
# file that held the pipe itself would be red for the gate that scans it.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_pipe_grep_q.sh"
GREP="grep"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "pipe into grep -q self-test"
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh

# new_root <name> <line>...: a tree holding Scripts/a.sh whose body is the
# lines. printf's format is fixed, so the lines are data.
new_root() {
  ROOT="$TMP/$1"
  shift
  mkdir -p "$ROOT/Scripts"
  { echo '#!/usr/bin/env bash'; printf '%s\n' "$@"; } > "$ROOT/Scripts/a.sh"
}

# red_case <name> <case> <line>...: the tree is red, naming Scripts/a.sh:2.
red_case() {
  local name="$1" label="$2"
  shift 2
  new_root "$name" "$@"
  capture "$GATE" "$ROOT"
  want_red "$label" "Scripts/a.sh:2 pipes a producer into grep -q"
}

# green_case <name> <case> <line>...: the tree is clean.
green_case() {
  local name="$1" label="$2"
  shift 2
  new_root "$name" "$@"
  capture "$GATE" "$ROOT"
  want_green_ok "$label"
}

red_case plain "1. a producer piped into a plain quiet grep is red, with file:line" "cat f | ${GREP} -q pat"
red_case ere "2. -qE is read" "cat f | ${GREP} -qE 'a|b'"
red_case cluster "3. a cluster with the q in the middle (-vqxF) is read" "cat f | ${GREP} -vqxF -- pat"
red_case last "4. a cluster with the q before others (-Fqi) is read" "cat f | ${GREP} -Fqi pat"
red_case long "5. --quiet is read" "cat f | ${GREP} --quiet pat"
red_case later "6. a quiet flag after other flags is read" "cat f | ${GREP} -E -q pat"
red_case pipeend "7. a pipe ending the line, the grep on the next, is read" "cat f |" "  ${GREP} -q pat"
red_case backslash "8. a backslash continuation, the pipe first on the next line, is read" \
  "cat f \\" "  | ${GREP} -q pat"
red_case andand "9. a quiet grep after && and a pipe is read" "true && cat f | ${GREP} -q pat"

green_case has "10. the helper is clean" "cat f | has -qE pat"
green_case file "11. a quiet grep on a file has no producer and is clean" "${GREP} -q pat f"
green_case herestring "12. a here-string has no producer and is clean" "${GREP} -q pat <<< \"\$x\""
green_case oror "13. || is not a pipe" "test -f f || ${GREP} -q pat f"
green_case comment "14. a comment is not code" "# cat f | ${GREP} -q pat"
green_case noq "15. a pipe into grep without a quiet flag is clean" "cat f | ${GREP} -c pat"
green_case other "16. a quiet grep after a semicolon, no pipe, is clean" \
  "cat f | cat; ${GREP} -q pat f"

green_case eq "16b. -eq of a test after a command substitution is no flag" \
  "[ \"\$(cat f | ${GREP} -c pat)\" -eq 2 ]"

new_root two "cat f | ${GREP} -q a" "cat f | ${GREP} -qE b"
capture "$GATE" "$ROOT"
want_red "17. every match is named, with a count" "2 place(s)"

mkdir -p "$TMP/empty"
capture "$GATE" "$TMP/empty"
want_red "18. a tree with no script is red: nothing scanned is not clean" "nothing scanned is not clean"

capture "$GATE" "$TMP/missing"
want_rc "19. a missing root exits 2" 2

# The helper. Under pipefail a producer that writes more than a pipe holds,
# its match first, dies of SIGPIPE when a quiet grep leaves at that match.
big_producer() {
  echo needle
  head -c 300000 /dev/zero | tr '\0' x
}
set -o pipefail
if big_producer | ${GREP} -q needle; then
  fail "20. the plain pipe found the pattern: the premise (SIGPIPE under pipefail) does not hold here"
else
  echo "  ok: 20. premise: the plain pipe loses a present pattern after 300 KB (${PIPESTATUS[0]}/${PIPESTATUS[1]})"
fi
if big_producer | has -q needle; then
  echo "  ok: 21. has finds the pattern after 300 KB of output"
else
  fail "21. has did not find a pattern the producer wrote first"
fi
if big_producer | has -q absent; then
  fail "22. has found a pattern that is not there"
else
  echo "  ok: 22. has is red for a pattern that is not there"
fi
if printf '' | has -qv anything; then
  fail "23. has saw a line in empty input (-v matched)"
else
  echo "  ok: 23. empty input is no line at all"
fi
if printf 'a\n\n' | has -qx ''; then
  echo "  ok: 24. a trailing empty line survives"
else
  fail "24. has lost a trailing empty line"
fi
set +o pipefail

# Mutation proofs: each red fixture is red BECAUSE of its pattern.
mutant_name() { echo "$TMP/mutant-$1/Scripts/check_pipe_grep_q.sh"; }

# The quiet-grep pattern never matching: case 1 turns green.
selftest_mutant_green "$GATE" "$(mutant_name pattern)" \
  "s|^PIPE_QUIET=.*|PIPE_QUIET='NEVER-MATCHES-ANY-LINE'|" "$TMP/plain" \
  "a pattern that never matches turns case 1 green, so it is red because of the pattern" \
  "with the pattern neutralised the plain fixture is still red"

# No joining of a pipe at the end of a line: case 7 turns green.
selftest_mutant_green "$GATE" "$(mutant_name join)" \
  "s|^      if (\\\$0 ~ .*|      if (0) { next }|" "$TMP/pipeend" \
  "a gate that never joins lines turns case 7 green, so a pipe ending the line is found BECAUSE of the join" \
  "with the join dropped a pipe ending the line is still red"

# mutant_red <name> <sed> <fixture> <ok text> <fail text>: the opposite proof,
# for a rule that keeps a clean shape clean: without it the fixture is red.
mutant_red() {
  if selftest_mutant "$GATE" "$(mutant_name "$1")" "$2"; then
    capture "$(mutant_name "$1")" "$3"
    if [[ "$RC" -ne 0 ]] && grep -qF -- "pipes a producer into grep -q" <<< "$OUT"; then
      echo "  ok: mutation proof: $4"
    else
      fail "mutation proof: $5 (exit $RC). Output: $OUT"
    fi
  fi
}
mutant_red comment 's|^    /\^\[\[:space:\]\]\*#/ { next }|    |' "$TMP/comment" \
  "a gate that reads comments turns case 14 red, so a comment is clean BECAUSE it is skipped" \
  "with the comment rule dropped the comment fixture is still green"
OROR_PATTERN='[|][[:space:]]*e?grep[[:space:]]+([^|;\&)]*[[:space:]])?(-[A-Za-z]*q|--quiet|--silent)'
mutant_red oror "s#^PIPE_QUIET=.*#PIPE_QUIET='${OROR_PATTERN}'#" "$TMP/oror" \
  "a gate that counts || as a pipe turns case 13 red, so || is clean BECAUSE of the rule" \
  "with the || rule dropped the || fixture is still green"

CLAIM="pipe-into-grep-q gate is red on every shape of a producer piped into a quiet grep (-q, -qE, -vqxF, -Fqi,"
CLAIM+=" --quiet, a later flag, a pipe ending the line, a continuation), names each match with a count, a tree"
CLAIM+=" with no script and exits 2 on a missing root, is green on has, a file operand, a here-string, ||, a"
CLAIM+=" comment, no quiet flag, its patterns are what redden the case, and has finds a pattern after 300 KB"
CLAIM+=" where the plain pipe loses it"
selftest_end "the pipe-into-grep-q gate does not flag a producer piped into a quiet grep, or has misses a pattern" \
  "$CLAIM"
