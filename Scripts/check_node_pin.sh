#!/usr/bin/env bash
# canon: check_node_pin v1
# Scripts/check_node_pin.sh
#
# The Node pin gate: the node on PATH must be the
# major .nvmrc pins (Scripts/node_pin.sh). Red otherwise, naming the running
# `node --version`, the pinned major and the fix. Node cannot download its own
# toolchain the way Go does, so this gate cannot repair anything: installing
# Node is the maintainer's, and the message says exactly what to run.
#
# Run by sfl.sh right after Scripts/install_tools.sh, and as a PRE row.
#
# Usage: Scripts/check_node_pin.sh [pin-file]   (default: .nvmrc)
# Exit: 0 the running major is the pinned one, 1 a different major, no node on
#       PATH, or a pin file node_pin.sh refuses.
# Fixture: Scripts/test_check_node_pin.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: check_node_pin.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

fail_now() {
  echo "❌ FAIL: $*"
  COMPLETED=1
  exit 1
}

if ! pin="$(./Scripts/node_pin.sh "$@")"; then
  fail_now "the Node pin could not be read (see above)"
fi

fix="install Node ${pin} with: brew install node@${pin} (a keg-only major: put /opt/homebrew/opt/node@${pin}/bin first on PATH), or, when ${pin} is Homebrew's current major, brew upgrade node"

if ! command -v node >/dev/null 2>&1; then
  fail_now "node is not on PATH, and .nvmrc pins Node ${pin} — ${fix}"
fi

running="$(node --version 2>/dev/null || true)"
major="${running#v}"
major="${major%%.*}"

if ! [[ "$major" =~ ^[0-9]+$ ]]; then
  fail_now "could not read a Node major from 'node --version' (got '${running}') — ${fix}"
fi

if [ "$major" != "$pin" ]; then
  fail_now "node is ${running}, but .nvmrc pins Node ${pin} — ${fix}"
fi

COMPLETED=1
echo "OK: node ${running} is the pinned major (${pin})"
