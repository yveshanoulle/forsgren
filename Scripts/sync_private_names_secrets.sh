#!/usr/bin/env bash
# canon: sync_private_names_secrets v1
# Scripts/sync_private_names_secrets.sh
#
# The private-names gate reads its list in CI from the Actions
# secret FORSGREN_PRIVATE_NAMES (and Dependabot runs read the Dependabot
# secret of the same name). The LOCAL file is the source of truth; both
# secrets are copies of it. This script copies it:
#
#   gh secret set FORSGREN_PRIVATE_NAMES -R <owner>/<repo>
#   gh secret set FORSGREN_PRIVATE_NAMES --app dependabot -R <owner>/<repo>
#
# <owner>/<repo> is this clone's own origin (git remote get-url origin), or
# env SYNC_REPO when set: the repository name is NEVER written in a tracked
# file here, since the list of private names keeps it out of them.
#
# The repository's EXTRA list, when its file is there, goes the same way into
# the Actions and Dependabot secrets FORSGREN_PRIVATE_NAMES_EXTRA (the file is
# FORSGREN_PRIVATE_NAMES_EXTRA_FILE, else
# ${HOME}/.config/forsgren/private-names-extra/<origin basename>, see
# Scripts/lib_private_names.sh). With no such file the extra secrets are not
# touched. An extra file that exists but cannot be read is exit 2, before any
# gh call.
#
# Usage: Scripts/sync_private_names_secrets.sh
#
# Run it BY HAND after the file changes: it needs the maintainer's gh login.
# The list source is the file FORSGREN_PRIVATE_NAMES_FILE, else
# ${HOME}/.config/forsgren/private-names, parsed as check_private_names.sh
# parses it, by the same Scripts/lib_private_names.sh (surrounding whitespace
# and \r stripped; blank lines and lines starting with # are not names). The env FORSGREN_PRIVATE_NAMES is NOT a source here.
#
# The names go to gh on stdin, never as an argument, and are never printed:
# the FAIL and OK lines name the file path and a count, not a name.
#
# Exit 0 both secrets set. Exit 1 a gh call failed. Exit 2 no file, a file
# that cannot be read, or a file with no names (the same "no list" code as
# check_private_names.sh); no gh call is made then.

set -euo pipefail
# Tracing off: the list must never reach a trace (bash -x, or a CI debug run).
set +x

# The list parsing, shared with Scripts/check_private_names.sh.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=Scripts/lib_private_names.sh
source "${ROOT}/Scripts/lib_private_names.sh"

REPO="${SYNC_REPO:-}"
if [[ -z "$REPO" ]]; then
  url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  REPO="$(printf '%s' "$url" | sed -E 's#^(git@[^:]+:|https?://[^/]+/|ssh://[^/]+/)##; s#\.git$##')"
fi
if [[ ! "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "❌ FAIL: cannot tell this repository from the origin remote; set SYNC_REPO=<owner>/<repo>"
  exit 2
fi
SECRET="FORSGREN_PRIVATE_NAMES"
FILE="$(private_names_file)"

if [[ ! -f "$FILE" ]]; then
  echo "❌ FAIL: the private-names file ${FILE} does not exist"
  exit 2
fi

if ! private_names_read "$FILE" LIST; then
  echo "❌ FAIL: the private-names file ${FILE} cannot be read"
  exit 2
fi
private_names_parse "$LIST"
if [[ "$PRIVATE_NAMES_COUNT" -eq 0 ]]; then
  echo "❌ FAIL: the private-names file ${FILE} has no names in it"
  exit 2
fi

# set_secret <kind> [gh option...]: hands the names on stdin to
# `gh secret set`; <kind> names the secret in the FAIL line.
# The extra list, read before any gh call so an unreadable file stops the run
# first. EXTRA_TEXT stays empty when there is no extra file.
EXTRA_SECRET="FORSGREN_PRIVATE_NAMES_EXTRA"
EXTRA_TEXT=""
EXTRA_FILE="$(private_names_extra_file "$ROOT")" || EXTRA_FILE=""
if [[ -n "$EXTRA_FILE" && -e "$EXTRA_FILE" ]]; then
  if ! private_names_read "$EXTRA_FILE" EXTRA_TEXT; then
    echo "❌ FAIL: the extra private-names file ${EXTRA_FILE} cannot be read"
    exit 2
  fi
fi
SHARED_COUNT="$PRIVATE_NAMES_COUNT"
SHARED_NAMES="$PRIVATE_NAMES"

set_secret() {
  local kind="$1"
  shift
  if ! printf '%s' "$PRIVATE_NAMES" | gh secret set "$SECRET" "$@" -R "$REPO" > /dev/null; then
    echo "❌ FAIL: gh could not set the ${kind} secret ${SECRET}"
    exit 1
  fi
}

set_secret Actions
set_secret Dependabot --app dependabot

# The extra secrets, only when the extra file holds names: the same two calls
# for FORSGREN_PRIVATE_NAMES_EXTRA, on the extra names alone.
if [[ -n "$EXTRA_TEXT" ]]; then
  private_names_parse "$EXTRA_TEXT"
  if [[ "$PRIVATE_NAMES_COUNT" -gt 0 ]]; then
    SECRET="$EXTRA_SECRET"
    set_secret Actions
    set_secret Dependabot --app dependabot
    echo "OK: synced ${PRIVATE_NAMES_COUNT} extra names into the Actions and Dependabot secrets ${EXTRA_SECRET}"
  fi
fi
PRIVATE_NAMES="$SHARED_NAMES"
PRIVATE_NAMES_COUNT="$SHARED_COUNT"

echo "OK: synced ${PRIVATE_NAMES_COUNT} names into the Actions and Dependabot secrets"
