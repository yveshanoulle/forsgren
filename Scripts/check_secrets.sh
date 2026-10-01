#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# gitleaks — secret scanning. Unit 399.
#
# WHY THIS REPO NEEDED IT. Every other repo in the estate gates on gitleaks
# in BOTH runners — web-infra, MenoPower, agileRetroflection. The two site
# repos had it in neither, which made them the only places a leaked secret
# could be committed with nothing objecting.
#
# The realistic exposure is not the HTML. It is someone pasting a token
# inline into a workflow while debugging a deploy — which is exactly what
# happened with the fastlane-certs PAT (MenoPower, 2026-07-08). These repos
# have deploy workflows and SSH keys in secrets, so they have the shape.
#
# SECRET-CLASS: this exits 2, not 1, and sfl turns that into its own exit 2
# so FullBuildAndPush REFUSES TO COMMIT. An ordinary red still commits
# locally to keep the WIP; a secret-class red must not, because committing it
# puts the secret into git history where removing it is a rewrite rather than
# an edit. The distinction is the whole point of the tier.
#
# Config is .gitleaks.toml, copied from web-infra: default ruleset plus an
# allowlist for `${{ secrets.NAME }}` references, which are names not values.
#
# Exit: 0 clean, 2 secret found or tooling missing.

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks: not found on PATH — cannot scan for secrets." >&2
  echo "  This does not skip. A secret scan that did not run is not a clean" >&2
  echo "  one, and this is the check whose failure blocks the commit." >&2
  echo "  Install: brew install gitleaks" >&2
  exit 2
fi

TARGET="${1:-.}"

# --no-git scans the working tree, so a secret is caught BEFORE it is staged.
# Scanning history instead would only tell us it is already too late.
# --no-color as a FLAG, not via a NO_COLOR env var: gitleaks colours its
# output by default and CI does not set NO_COLOR, so the first run filled the
# report with raw escape sequences while every other gate rendered clean. A
# flag holds regardless of who invokes it.
if gitleaks detect --source "$TARGET" --config .gitleaks.toml \
     --no-git --no-banner --no-color -v; then
  echo "OK: gitleaks (no secrets in the working tree)"
  exit 0
fi

echo "gitleaks: SECRET-CLASS finding above." >&2
echo "  Nothing will be committed. Remove the secret, rotate it if it ever" >&2
echo "  reached a remote, then re-run — do not commit and clean up after." >&2
exit 2
