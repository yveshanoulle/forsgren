#!/usr/bin/env bash
# Scripts/release_agent_proofs.sh
#
# A major release needs a proof run of every agent file on the new major
# (forsgren#148, decision #170; moved here by forsgren#237, step 5b, from a Go
# test on `var version`, which no release bumps any more). The agent files
# (agent-*.md at the repository root) end their intro with
#   Tested with: forsgren v1.3.2, Claude Code, model ...
# or, for an upgrader, "forsgren v0.8.5 → v1.3.0": the last version is the one
# the file was proved on, and its major must be the new one.
#
# Usage: Scripts/release_agent_proofs.sh <major>
# RELEASE_AGENT_FILES (space separated paths) replaces agent-*.md: the seam of
# the self-test. Every file that has no Tested-with line, or one on another
# major, gets a red line naming it; nothing stops at the first. Called by
# Scripts/release_plan.sh when the planned bump is a major.
# Exit: 0 every file proved on the major, 1 red, 2 usage.
# Self-test: Scripts/test_release_agent_proofs.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_agent_proofs.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

usage() {
  echo "usage: Scripts/release_agent_proofs.sh <major>" >&2
  COMPLETED=1
  exit 2
}

[ "$#" -eq 1 ] || usage
MAJOR="$1"
[[ "$MAJOR" =~ ^[0-9]+$ ]] || usage
cd "$(dirname "$0")/.." || exit 1

FILES="${RELEASE_AGENT_FILES:-}"
if [ -z "$FILES" ]; then FILES="$(ls agent-*.md 2> /dev/null || true)"; fi

left=0
for file in $FILES; do
  tested=""
  if [ -f "$file" ]; then
    tested="$(sed -n 's/^Tested with: forsgren \(v[0-9.]* [^ ]* \)\{0,1\}v\([0-9][0-9]*\)\..*$/\2/p' "$file" | head -n 1)"
  fi
  name="${file##*/}"
  if [ -z "$tested" ]; then
    echo "❌ FAIL: release agent proofs: ${name} has no Tested-with line to read a major from"
    left=1
  elif [ "$tested" != "$MAJOR" ]; then
    echo "❌ FAIL: release agent proofs: ${name} was tested on forsgren major ${tested}, not ${MAJOR}: run a new proof and update its Tested-with line"
    left=1
  fi
done
if [ -z "$FILES" ]; then
  echo "❌ FAIL: release agent proofs: there is no agent-*.md: nothing would be proved on major ${MAJOR}"
  left=1
fi
if [ "$left" -ne 0 ]; then
  COMPLETED=1
  exit 1
fi
echo "OK: every agent file has a proof run on forsgren major ${MAJOR}"
COMPLETED=1
