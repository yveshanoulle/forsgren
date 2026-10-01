#!/usr/bin/env bash
# FBP.sh (FullBuildAndPush) as the subagent loop's own identity (ruled
# 2026-09-07 in MenoPower, ported to web-infra 2026-09-19 and to
# konenki-website 2026-09-30, ported here 2026-10-01 (forsgren#1) so Lenka
# can run forsgren's own FBP.sh under the loop's identity too).
#
# Commits made by Claude's subagent loop are authored AND committed by the
# GitHub account agent-Friend and signed with its SSH signing key, so GitHub
# links them to that account and marks them Verified; the push still uses the
# machine's own key, which is the authorisation. Everything is passed to git
# through the environment of this one process — nothing is written to the
# repo's or the machine's git config, so an FBP.sh run by hand keeps the
# identity of whoever runs it.
#
# Twin of web-infra/Scripts/fbp_agent_friend.sh,
# konenki-website/Scripts/fbp_agent_friend.sh and
# MenoPower/Scripts/standalone/fbp_agent_friend.sh; they differ only in how
# the repo root is found (each repo's own convention) and in the name of the
# script they run (here FBP.sh, by Yves's ruling on forsgren#1).
# Hand-run by the loop, never by sfl or a workflow (the gate-wiring check
# that will exempt it arrives with CI, a later step of forsgren#1).
# Usage, from anywhere:  Scripts/fbp_agent_friend.sh [FBP args] "<message>"
set -euo pipefail

SIGNING_KEY="${AGENT_FRIEND_SIGNING_KEY:-$HOME/.ssh/agent-friend-signing}"
if [ ! -r "$SIGNING_KEY" ]; then
  echo "❌ agent-Friend signing key not found: $SIGNING_KEY" >&2
  exit 1
fi

export GIT_AUTHOR_NAME="agent-Friend"
export GIT_AUTHOR_EMAIL="326202683+agent-Friend@users.noreply.github.com"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

# Per-process git config (git 2.31+): sign every commit with the SSH key.
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0="commit.gpgsign"   GIT_CONFIG_VALUE_0="true"
export GIT_CONFIG_KEY_1="gpg.format"       GIT_CONFIG_VALUE_1="ssh"
export GIT_CONFIG_KEY_2="user.signingkey"  GIT_CONFIG_VALUE_2="$SIGNING_KEY"

# FBP.sh lives at the repo root and cds there itself.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/FBP.sh" "$@"
