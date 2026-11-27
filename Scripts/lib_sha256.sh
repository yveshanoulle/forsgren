#!/usr/bin/env bash
# Scripts/lib_sha256.sh
#
# The one way a script of this repository takes a sha256, on every platform
# sfl runs on. macOS has shasum (Perl) and, from macOS 14, sha256sum; Linux has
# sha256sum; Git for Windows has sha256sum and no shasum. The first Windows run
# of sfl stopped at `shasum: command not found` in Scripts/npm_sync_install.sh
# (run 45897778125). Both tools give the same hex digest of the same bytes.
#
#   sha256_of <file>   the lowercase hex sha256 of the file, on one line; a
#                      file of `-` is stdin (both tools read it so)
#
# sha256sum is used when it is on PATH, else shasum -a 256. Neither on PATH, a
# tool that fails, or output that is not 64 hex characters is a failure (exit
# 1) with a line on stderr that says which, never an empty digest a caller could
# compare as if it were one.
#
# SOURCED, never run. It sets no shell options and no traps; the sourcing
# script owns those. Tested by Scripts/test_npm_sync_install.sh (cases 12 to
# 15, with each tool alone on PATH, neither, and a broken one).

sha256_of() {
  local tool out
  if command -v sha256sum > /dev/null 2>&1; then
    tool="sha256sum"
    out="$(sha256sum "$1")" || { echo "❌ FAIL: sha256_of: sha256sum failed on $1" >&2; return 1; }
  elif command -v shasum > /dev/null 2>&1; then
    tool="shasum -a 256"
    out="$(shasum -a 256 "$1")" || { echo "❌ FAIL: sha256_of: shasum -a 256 failed on $1" >&2; return 1; }
  else
    echo "❌ FAIL: sha256_of: neither sha256sum nor shasum is on PATH (Git for Windows and Linux have sha256sum, macOS has shasum)" >&2
    return 1
  fi
  out="${out%% *}"
  if ! [[ "$out" =~ ^[0-9a-f]{64}$ ]]; then
    echo "❌ FAIL: sha256_of: ${tool} gave no sha256 for $1 (got '${out}')" >&2
    return 1
  fi
  printf '%s\n' "$out"
}
