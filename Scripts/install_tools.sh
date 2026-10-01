#!/usr/bin/env bash
# Installs and refreshes the Homebrew tools this repo's gates need, from
# Scripts/required_tools.txt. Unit 414.
#
# THIS SCRIPT IS MEANT TO BE IDENTICAL IN EVERY REPO OF THE ESTATE. Everything
# that differs between repos lives in the list it reads. Keep it that way: a
# tool name added here rather than to the list is how four copies of one script
# stop being one script.
#
# NO PATH EXPORT HERE, deliberately. sfl.sh sets the Homebrew path before
# calling this; adding it here would also override the path the fixture uses to
# stand up a fake toolchain, and the fixture would then be testing this machine
# rather than this script.
#
# Local invocation: ./Scripts/install_tools.sh [tools-file]

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

TOOLS_FILE="${1:-Scripts/required_tools.txt}"
# Testing seam. The fixture points this at a stub that records what it was asked
# and, for `install`, creates the tool it claims to have installed — so the case
# that matters can be staged: Homebrew exiting 0 without providing the command.
BREW="${BREW:-brew}"

if [ ! -f "$TOOLS_FILE" ]; then
  echo "❌ FAIL: no tool list at ${TOOLS_FILE} — every gate that needs a tool would run against whatever happens to be on this machine" >&2
  exit 1
fi

tools=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [ -n "$line" ] || continue
  tools+=("$line")
done < "$TOOLS_FILE"

# NON-VACUITY, before any expansion of the array — which on bash 3.2 under
# `set -u` is itself fatal when empty. A list that has quietly become empty must
# not read as "all tools present": web-infra's grant audit reported `none` for
# weeks on exactly that shape.
if [ "${#tools[@]}" -eq 0 ]; then
  echo "❌ FAIL: ${TOOLS_FILE} declares no tools — this run would install nothing, check nothing, and report success" >&2
  exit 1
fi

# Always update first, so the per-tool upgrade below sees current formulae
# rather than a stale cache. Never fatal: an offline machine should still be
# able to run its gates with what it has.
NONINTERACTIVE=1 HOMEBREW_NO_ASK=1 "$BREW" update >/dev/null 2>&1 || true

missing=""
for tool in "${tools[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    NONINTERACTIVE=1 HOMEBREW_NO_ASK=1 "$BREW" upgrade "$tool" >/dev/null 2>&1 || true
    echo "✅ ${tool}"
    continue
  fi

  echo "INFO: installing missing tool: ${tool}"
  NONINTERACTIVE=1 HOMEBREW_NO_ASK=1 "$BREW" install "$tool" >/dev/null 2>&1 || true

  # THE CHECK THIS SCRIPT EXISTS FOR. `brew install` exiting 0 is not evidence
  # that the command is runnable — a formula can be a cask, a keg-only pour, or
  # simply not on the path afterwards. Without this, the gate needing the tool
  # is the thing that discovers it, and a gate discovers it as `command not
  # found` inside a step that reports its own exit code.
  if command -v "$tool" >/dev/null 2>&1; then
    echo "✅ ${tool} (installed)"
  else
    echo "❌ FAIL: ${tool} is still not runnable after ${BREW} install — the gates needing it would run against nothing" >&2
    missing="${missing}${tool} "
  fi
done

if [ -n "$missing" ]; then
  echo "❌ FAIL: tools missing after install: ${missing}" >&2
  exit 1
fi

echo "OK: ${#tools[@]} required tools present"
