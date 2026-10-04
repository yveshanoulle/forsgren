#!/usr/bin/env bash
# Scripts/test_ensure_private_names_file.sh
#
# Self-test for Scripts/ensure_private_names_file.sh (forsgren#52, step
# 12c). CI always fails without a private-names list (the gate exits 2);
# LOCALLY, FBP.sh calls this helper before the PRE gates so a first run needs
# no setup: when no list is given at all, it creates an EMPTY list file at
# ${HOME}/.config/forsgren/private-names and says so in one line. Every HOME
# below is a fake one under a temp root; the real list is never touched.
#
# The helper's interface, as pinned here:
#   Scripts/ensure_private_names_file.sh
#   creates the default file, empty (mkdir -p its directory), and prints one
#   line naming it, only when FORSGREN_PRIVATE_NAMES is empty or unset AND
#   FORSGREN_PRIVATE_NAMES_FILE is unset AND the default file does not
#   exist. It never touches an existing file, never creates anything when
#   FORSGREN_PRIVATE_NAMES_FILE is set (a missing explicit file stays a red
#   in the gate), and never creates it when the env list is given.
#
#   1. fake HOME, no env, no file -> the default file exists, is empty, and
#      the note line names its path; a second run leaves it byte-identical
#      and says nothing; an existing file with content is left
#      byte-identical; FORSGREN_PRIVATE_NAMES_FILE naming a missing path
#      creates nothing; so does a non-empty FORSGREN_PRIVATE_NAMES.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

ENSURE="$(pwd)/Scripts/ensure_private_names_file.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "ensure-private-names-file self-test"

if [[ ! -x "$ENSURE" ]]; then
  selftest_abort "Scripts/ensure_private_names_file.sh is missing or not executable: nothing to test"
fi

# --- 1. no list given: the default file is created, empty, with a note ------
HOME_NEW="${TMP}/home-new"
DEFAULT_NEW="${HOME_NEW}/.config/forsgren/private-names"
mkdir -p "$HOME_NEW"

capture env -u FORSGREN_PRIVATE_NAMES -u FORSGREN_PRIVATE_NAMES_FILE \
  HOME="$HOME_NEW" "$ENSURE"
want_rc "no list given: the helper succeeds" 0
want_said "no list given: the note names the default file" "$DEFAULT_NEW"

if [[ -f "$DEFAULT_NEW" && ! -s "$DEFAULT_NEW" ]]; then
  echo "  ok: no list given: the default file exists and is empty"
else
  fail "no list given: expected an empty file at ${DEFAULT_NEW}. Output: ${OUT}"
fi

capture env -u FORSGREN_PRIVATE_NAMES -u FORSGREN_PRIVATE_NAMES_FILE \
  HOME="$HOME_NEW" "$ENSURE"
if [[ -f "$DEFAULT_NEW" && ! -s "$DEFAULT_NEW" && -z "$OUT" ]]; then
  echo "  ok: a second run leaves the file alone and says nothing"
else
  fail "a second run should change nothing and print nothing. Output: ${OUT}"
fi

# --- an existing file is left byte-identical --------------------------------
HOME_OLD="${TMP}/home-old"
DEFAULT_OLD="${HOME_OLD}/.config/forsgren/private-names"
mkdir -p "$(dirname "$DEFAULT_OLD")"
printf '# made-up\nacme-data\n' > "$DEFAULT_OLD"
cp "$DEFAULT_OLD" "${TMP}/old-before"

capture env -u FORSGREN_PRIVATE_NAMES -u FORSGREN_PRIVATE_NAMES_FILE \
  HOME="$HOME_OLD" "$ENSURE"
if cmp -s "$DEFAULT_OLD" "${TMP}/old-before" && [[ -z "$OUT" ]]; then
  echo "  ok: an existing file is left byte-identical, silently"
else
  fail "an existing file must be untouched and the helper silent. Output: ${OUT}"
fi

# --- an explicit file, missing, creates nothing -----------------------------
HOME_EXPLICIT="${TMP}/home-explicit"
mkdir -p "$HOME_EXPLICIT"
capture env -u FORSGREN_PRIVATE_NAMES HOME="$HOME_EXPLICIT" \
  FORSGREN_PRIVATE_NAMES_FILE="${TMP}/missing-names" "$ENSURE"
if [[ ! -e "${TMP}/missing-names" && ! -e "${HOME_EXPLICIT}/.config" ]]; then
  echo "  ok: FORSGREN_PRIVATE_NAMES_FILE naming a missing path creates nothing"
else
  fail "a missing explicit file must stay missing, and no default created. Output: ${OUT}"
fi

# --- the env list given creates nothing -------------------------------------
HOME_ENV="${TMP}/home-env"
mkdir -p "$HOME_ENV"
capture env -u FORSGREN_PRIVATE_NAMES_FILE HOME="$HOME_ENV" \
  FORSGREN_PRIVATE_NAMES="widget-app" "$ENSURE"
if [[ ! -e "${HOME_ENV}/.config" ]]; then
  echo "  ok: the env list given creates nothing"
else
  fail "the env list given must create no default file. Output: ${OUT}"
fi

selftest_end "the helper does not create an empty private-names list only when none is given" \
  "the helper creates an empty default private-names list with a note when none is given, and touches nothing else"
