#!/usr/bin/env bash
# Scripts/sync_private_names_secrets.sh
#
# forsgren#52. The private-names gate reads its list in CI from the Actions
# secret FORSGREN_PRIVATE_NAMES (and Dependabot runs read the Dependabot
# secret of the same name). The LOCAL file is the source of truth; both
# secrets are copies of it. This script copies it:
#
#   gh secret set FORSGREN_PRIVATE_NAMES -R yveshanoulle/forsgren
#   gh secret set FORSGREN_PRIVATE_NAMES --app dependabot -R yveshanoulle/forsgren
#
# Usage: Scripts/sync_private_names_secrets.sh
#
# Run it BY HAND after the file changes: it needs the maintainer's gh login.
# The list source is the file FORSGREN_PRIVATE_NAMES_FILE, else
# ${HOME}/.config/forsgren/private-names, parsed like check_private_names.sh
# (surrounding whitespace and \r stripped; blank lines and lines starting
# with # are not names). The env FORSGREN_PRIVATE_NAMES is NOT a source here.
#
# The names go to gh on stdin, never as an argument, and are never printed:
# the FAIL and OK lines name the file path and a count, not a name.
#
# Exit 0 both secrets set. Exit 1 a gh call failed. Exit 2 no file, or a
# file with no names (the same "no list" code as check_private_names.sh).

set -euo pipefail
# Tracing off: the list must never reach a trace (bash -x, or a CI debug run).
set +x

REPO="yveshanoulle/forsgren"
SECRET="FORSGREN_PRIVATE_NAMES"
FILE="${FORSGREN_PRIVATE_NAMES_FILE:-${HOME:-/nonexistent}/.config/forsgren/private-names}"

if [[ ! -f "$FILE" ]]; then
  echo "❌ FAIL: the private-names file ${FILE} does not exist"
  exit 2
fi

# The names, one per line, in NAMES; their number in COUNT.
NAMES=""
COUNT=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  NAMES+="${line}"$'\n'
  COUNT=$((COUNT + 1))
done < "$FILE"

if [[ "$COUNT" -eq 0 ]]; then
  echo "❌ FAIL: the private-names file ${FILE} has no names in it"
  exit 2
fi

if ! printf '%s' "$NAMES" | gh secret set "$SECRET" -R "$REPO" > /dev/null; then
  echo "❌ FAIL: gh could not set the Actions secret ${SECRET}"
  exit 1
fi
if ! printf '%s' "$NAMES" | gh secret set "$SECRET" --app dependabot -R "$REPO" > /dev/null; then
  echo "❌ FAIL: gh could not set the Dependabot secret ${SECRET}"
  exit 1
fi

echo "OK: synced ${COUNT} names into the Actions and Dependabot secrets"
