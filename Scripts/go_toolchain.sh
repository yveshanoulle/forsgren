#!/usr/bin/env bash
# Scripts/go_toolchain.sh
#
# Prints the exact Go toolchain forsgren builds with, read from the `toolchain`
# line of go.mod (for example `go1.27.1`). sfl.sh and FBP.sh export it as
# GOTOOLCHAIN, so go.mod stays the ONE place the version is written.
#
# WHY GOTOOLCHAIN. A `toolchain` line in go.mod is only a minimum: with the
# default GOTOOLCHAIN=auto, go runs the newer of the local Go and that line, so
# a Homebrew upgrade to a newer Go would silently change forsgren's builds.
# GOTOOLCHAIN=<that version> makes the pin exact: go downloads that toolchain
# on first use and runs it. Never `go env -w GOTOOLCHAIN=...`: that writes
# machine-wide config, shared with every other project on the machine.
#
# Exits 1, with a message on stderr, when go.mod has no toolchain line.
#
# Usage: Scripts/go_toolchain.sh [go.mod]   (default: the repo's go.mod)
# Fixture: Scripts/test_go_toolchain.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

GO_MOD="${1:-go.mod}"

if [ ! -f "$GO_MOD" ]; then
  echo "❌ FAIL: no go.mod at ${GO_MOD} — there is no Go toolchain to pin" >&2
  exit 1
fi

version="$(awk '$1 == "toolchain" { print $2; exit }' "$GO_MOD")"

if [ -z "$version" ]; then
  echo "❌ FAIL: ${GO_MOD} has no toolchain line — without it the Go version is whatever is installed on this machine; add one, for example: toolchain go1.27.1" >&2
  exit 1
fi

echo "$version"
