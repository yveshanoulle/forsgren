#!/usr/bin/env bash
# Scripts/test_release_agent_proofs.sh
#
# Self-test for Scripts/release_agent_proofs.sh (forsgren#237, step 5b): a
# major release needs a proof run of every agent file on the new major. The
# rule moved here from a Go test on `var version`, which no release bumps any
# more; release_plan.sh calls this script when the planned bump is a major.
# Fixture agent files (RELEASE_AGENT_FILES) in the shape of the real ones:
#   1. every file proved on the major                     -> OK
#   2. one file proved on an older major                  -> red naming only it
#   3. the arrow form "v0.8.5 → v1.3.0" reads its last version
#   4. a file with no Tested-with line, a missing file    -> red naming each
#   5. every stale file is named, not only the first
#   6. the real agent files: proved on one common major M, so M passes and M+1
#      names every one of them (the rule is not vacuous on the repository)
#   7. usage errors                                       -> exit 2
# Mutation proofs: a copy that cannot read the arrow form, and one that takes a
# file without a proof line for proved, must each let the case they exist for
# pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release agent proofs self-test"
D='$'

PROOFS="Scripts/release_agent_proofs.sh"
[[ -f "$PROOFS" ]] || selftest_abort "${PROOFS} does not exist — a major release would ship agent files nobody proved on it"

F="${TMP}/agents"
mkdir -p "$F"
printf '# A\n\nTested with: forsgren v2.0.1, Claude Code, model claude-sonnet-5-5.\n' > "${F}/agent-one.md"
printf '# B\n\nTested with: forsgren v0.8.5 \xe2\x86\x92 v2.0.0, Claude Code, model claude-sonnet-5-5.\n' > "${F}/agent-two.md"
printf '# C\n\nTested with: forsgren v1.3.2, Claude Code, model claude-sonnet-5-5.\n' > "${F}/agent-old.md"
printf '# D\n\nNo proof line.\n' > "${F}/agent-none.md"
printf '# E\n\nTested with: forsgren v0.8.5 \xe2\x86\x92 v1.3.0, Claude Code, model claude-sonnet-5-5.\n' > "${F}/agent-arrow.md"

# proofs <major> <file>...: the script on those files.
proofs() {
  local major="$1"
  shift
  RELEASE_AGENT_FILES="$*" capture "${SCRIPT:-$PROOFS}" "$major"
}

proofs 2 "${F}/agent-one.md" "${F}/agent-two.md"
want_green "every file proved on major 2" "OK: every agent file has a proof run on forsgren major 2"

proofs 2 "${F}/agent-one.md" "${F}/agent-old.md"
want_red "one file proved on major 1" "agent-old.md was tested on forsgren major 1"
if grep -qF "agent-one.md" <<< "$OUT"; then fail "the file proved on major 2 is named. Output: ${OUT}"; else echo "  ok: only the stale file is named"; fi
want_said "it says what to do" "run a new proof and update its Tested-with line"

proofs 2 "${F}/agent-arrow.md"
want_red "the arrow form reads its last version" "agent-arrow.md was tested on forsgren major 1"
proofs 1 "${F}/agent-arrow.md"
want_green "the arrow form passes for its last major" "OK: every agent file has a proof run on forsgren major 1"

proofs 2 "${F}/agent-none.md"
want_red "a file with no Tested-with line" "agent-none.md has no Tested-with line to read a major from"
proofs 2 "${F}/does-not-exist.md"
want_red "a file that does not exist" "does-not-exist.md has no Tested-with line to read a major from"

proofs 2 "${F}/agent-old.md" "${F}/agent-arrow.md" "${F}/agent-none.md" "${F}/agent-one.md"
want_red "several stale files" "agent-old.md was tested on forsgren major 1"
want_said "the second stale file is named too" "agent-arrow.md was tested on forsgren major 1"
want_said "the file with no line is named too" "agent-none.md has no Tested-with line"

# 6. The real agent files.
REAL="$(ls agent-*.md)"
[[ -n "$REAL" ]] || fail "the repository has no agent-*.md: nothing would be proved on a major"
majors="$(for f in $REAL; do sed -n 's/^Tested with: forsgren \(v[0-9.]* [^ ]* \)\{0,1\}v\([0-9][0-9]*\)\..*$/\2/p' "$f"; done | sort -u)"
if [[ "$(wc -l <<< "$majors" | tr -d ' ')" -ne 1 || -z "$majors" ]]; then
  fail "the real agent files are not all tested on one major (got: $(tr '\n' ' ' <<< "$majors")): a release that is not a major needs them on one"
else
  echo "  ok: the real agent files are tested on one major, ${majors}"
  capture "$PROOFS" "$majors"
  want_green "the real agent files pass for their own major" "OK: every agent file has a proof run on forsgren major ${majors}"
  capture "$PROOFS" "$((majors + 1))"
  for f in $REAL; do want_said "the next major names ${f}" "${f} was tested on forsgren major ${majors}"; done
fi

capture "$PROOFS"
want_exit "no major" 2 "usage"
capture "$PROOFS" two
want_exit "a major that is no number" 2 "usage"
capture "$PROOFS" 2 3
want_exit "two arguments" 2 "usage"

# Mutation proofs.
mutant() {
  selftest_mutant "$PROOFS" "${TMP}/mut/$1/release_agent_proofs.sh" "$2" || return 1
  SCRIPT="${TMP}/mut/$1/release_agent_proofs.sh"
}
if mutant noarrow 's/ \\(v\[0-9.]\* \[^ ]\* \\)\\{0,1\\}v/ v/'; then
  proofs 1 "${F}/agent-arrow.md"
  if [[ "$RC" -eq 0 ]]; then
    fail "mutation proof: the mutant that cannot read the arrow form still passed it. Output: ${OUT}"
  else
    echo "  ok: mutation proof: without the arrow form an upgrader's last version is not read"
  fi
fi
unset SCRIPT
if mutant noline "s/| head -n 1)\"/| head -n 1)\"; tested=\"${D}{tested:-${D}MAJOR}\"/"; then
  proofs 2 "${F}/agent-none.md"
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof: the mutant that takes a missing proof line for proved still refused it. Output: ${OUT}"
  else
    echo "  ok: mutation proof: with a fallback a file with no proof line passes unchecked"
  fi
fi
unset SCRIPT

selftest_end "the agent proof check does not hold" "release agent proofs: a major needs every agent file proved on it, each stale or unproved file is named"
