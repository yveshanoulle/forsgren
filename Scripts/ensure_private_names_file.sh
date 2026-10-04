#!/usr/bin/env bash
# Scripts/ensure_private_names_file.sh
#
# forsgren#52 (step 12c): LOCAL pre-flight. FBP.sh runs it just before the
# PRE gates (sfl.sh pre).
#
# What: when no private-names list is given at all, it creates an EMPTY list
# file at the default path (private_names_file in
# Scripts/lib_private_names.sh: ${HOME}/.config/forsgren/private-names),
# mode 600 because names will go in it, and prints one line naming the path.
# It does nothing, silently, when
#   - env FORSGREN_PRIVATE_NAMES is non-empty (the list is given), or
#   - FORSGREN_PRIVATE_NAMES_FILE is set (an explicit file: a missing one
#     stays a red in the gate), or
#   - the default file already exists (never touched, never rewritten).
#
# Why: Yves's ruling: CI always fails without a list (the gate exits 2).
# Locally, a contributor without the list can still run FBP.sh: the empty
# file makes the gate pass with 0 names searched. CI never runs FBP.sh, so CI
# stays strict.
#
# It prints a path, never a name.

set -euo pipefail
set +x

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=Scripts/lib_private_names.sh
source "${ROOT}/Scripts/lib_private_names.sh"

if [[ -n "${FORSGREN_PRIVATE_NAMES:-}" || -n "${FORSGREN_PRIVATE_NAMES_FILE+set}" ]]; then
  exit 0
fi

file="$(private_names_file)"
if [[ -e "$file" ]]; then
  exit 0
fi

mkdir -p "$(dirname "$file")"
(umask 077 && : > "$file")
echo "ℹ️ created an empty private-names list at ${file}; add private names there, one per line (forsgren#52)"
