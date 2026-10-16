#!/usr/bin/env bash
# canon: test_node_pin v1
# Scripts/test_node_pin.sh
#
# Self-test for Scripts/node_pin.sh: the Node major is read from
# one line of .nvmrc. Each case is a throwaway pin file:
#   1. `26` and a newline               -> prints 26, rc 0
#   2. `26` with no final newline       -> prints 26
#   3. no such file                     -> red, naming the file, stdout empty
#   4. an empty file                    -> red
#   5. `v26`, `26.11.1`, `lts/*`        -> red (a whole major only)
#   6. two lines                        -> red
#   7. the repo's real .nvmrc           -> a major
# Mutation proof: a copy of the script that does not check the format must
# accept `lts/*`, so case 5 is red because of the check.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

SCRIPT="$(pwd)/Scripts/node_pin.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "node pin self-test"

[[ -f "$SCRIPT" ]] || selftest_abort "${SCRIPT} does not exist — nothing reads the Node pin"

# pin_file <name> <content> — writes a pin file; sets PIN.
pin_file() {
  PIN="${TMP}/$1"
  printf '%s' "$2" > "$PIN"
}

# stdout_of <script> <file> — the script's stdout alone, in STDOUT; its status in RC.
stdout_of() {
  RC=0
  STDOUT="$("$1" "$2" 2>"${TMP}/err")" || RC=$?
  OUT="$(cat "${TMP}/err")"
}

pin_file one $'26\n'
stdout_of "$SCRIPT" "$PIN"
if [[ "$RC" -eq 0 && "$STDOUT" == "26" ]]; then echo "  ok: 1. 26 and a newline"; else fail "1. rc=${RC} stdout=${STDOUT}"; fi

pin_file nonl '26'
stdout_of "$SCRIPT" "$PIN"
if [[ "$RC" -eq 0 && "$STDOUT" == "26" ]]; then echo "  ok: 2. 26 without a final newline"; else fail "2. rc=${RC} stdout=${STDOUT}"; fi

stdout_of "$SCRIPT" "${TMP}/no-such"
want_red "3. no such file" "no ${TMP}/no-such"
[[ -z "$STDOUT" ]] || fail "3. a failed read printed on stdout: ${STDOUT}"

pin_file empty ''
stdout_of "$SCRIPT" "$PIN"
want_red "4. an empty file" "must hold exactly one line"

for bad in 'v26' '26.11.1' 'lts/*' ' 26'; do
  pin_file bad "$bad"$'\n'
  stdout_of "$SCRIPT" "$PIN"
  want_red "5. '${bad}' is not a whole major" "must hold exactly one line, a whole Node major"
done
pin_file lts $'lts/*\n'
LTS_FILE="$PIN"

pin_file two $'26\n27\n'
stdout_of "$SCRIPT" "$PIN"
want_red "6. two lines" "found 2 line(s)"

stdout_of "$SCRIPT" "$(pwd)/.nvmrc"
if [[ "$RC" -eq 0 && "$STDOUT" =~ ^[0-9]+$ ]]; then echo "  ok: 7. the repo's .nvmrc pins major ${STDOUT}"; else fail "7. the repo's .nvmrc: rc=${RC} stdout=${STDOUT}"; fi

# --- mutation proof: no format check -> lts/* is accepted ---------------------
NO_FORMAT="s/if \\[ \"\\\$lines\" -ne 1 \\] || ! \\[\\[ \"\\\$pin\" =~ \\^\\[0-9\\]+\\\$ \\]\\]; then/if false; then/"
if selftest_mutant "$SCRIPT" "${TMP}/mutant/Scripts/node_pin.sh" "$NO_FORMAT"; then
  RC=0
  "${TMP}/mutant/Scripts/node_pin.sh" "$LTS_FILE" >/dev/null 2>&1 || RC=$?
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: without the format check lts/* is accepted, so case 5 is red because of it"
  else
    fail "mutation proof: the check-less script still refused lts/* (exit ${RC})"
  fi
fi

selftest_end "the node pin reader does not hold" \
  "node pin: one whole major per .nvmrc is read; a missing file, an empty file, v26, 26.11.1, lts/* and two lines are refused; mutation proven"
