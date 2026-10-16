#!/usr/bin/env bash
# canon: node_pin v1
# Scripts/node_pin.sh
#
# Prints the Node major this repository runs its npm tooling on, read from .nvmrc
# ONE line, a whole major such as `26`. .nvmrc is
# the one place the pin is written; Scripts/check_node_pin.sh enforces it and
# CI's setup-node reads the same file.
#
# THE MAJOR, not an exact version: Homebrew publishes `node` (the newest
# major) and `node@NN` per major, never a chosen patch release, so a patch pin
# could not be installed. Go can pin exactly because Go downloads its own
# toolchain; Node cannot.
#
# Exits 1, with a message on stderr and nothing on stdout, when the file is
# missing or is not exactly one whole number.
#
# Usage: Scripts/node_pin.sh [file]   (default: the repo's .nvmrc)
# Fixture: Scripts/test_node_pin.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

PIN_FILE="${1:-.nvmrc}"

if [ ! -f "$PIN_FILE" ]; then
  echo "❌ FAIL: no ${PIN_FILE} — without it the Node version is whatever is installed on this machine; add one holding the major, for example: 26" >&2
  exit 1
fi

lines="$(grep -c '' "$PIN_FILE" || true)"
pin="$(head -n 1 "$PIN_FILE")"

if [ "$lines" -ne 1 ] || ! [[ "$pin" =~ ^[0-9]+$ ]]; then
  echo "❌ FAIL: ${PIN_FILE} must hold exactly one line, a whole Node major such as 26 (found ${lines} line(s), first: '${pin}')" >&2
  exit 1
fi

echo "$pin"
