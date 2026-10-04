#!/usr/bin/env bash
# Scripts/sync_private_names_secrets.sh
#
# forsgren#52, step 3 (STUB: the red). It will read the private-names list
# (FORSGREN_PRIVATE_NAMES_FILE, else ~/.config/forsgren/private-names), drop
# the # comment lines, and pipe it on stdin to `gh secret set
# FORSGREN_PRIVATE_NAMES` for Actions and for Dependabot, never printing a name.
exit 0
