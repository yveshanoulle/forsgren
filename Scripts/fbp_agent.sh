#!/usr/bin/env bash
# Scripts/fbp_agent.sh: FBP.sh as an agent's own identity, the bot of the agent's GitHub App.
# Successor of Scripts/fbp_agent_friend.sh, which hard-codes one shared account and signs with
# that account's key; the old script stays for rollback until the shared account is retired.
# The same text in every repository that has it: the repo root is the folder above Scripts/.
#
# The identity is NOT written here: it comes from the repository's LOCAL git config
# (user.name / user.email, set once per checkout by the agent's migration tool), or from
# --identity "Name <email>". It is exported as author AND committer for this one process, so
# a global or CI identity never leaks into the commit. Nothing is written to any git config.
# A bot identity (…[bot]@users.noreply.github.com) must also push with its App: the local
# credential helpers for https://github.com must start with the "" reset (which drops every
# inherited helper) and name git-credential-app.sh, the helper that answers with a short-lived
# App installation token; else this refuses (no silent push with someone else's login).
# Commits are not signed: a GitHub App bot has no signing key.
# Hand-run by the agent, never by sfl or a workflow.
# Usage, from anywhere:
#   Scripts/fbp_agent.sh [--identity "Name <email>"] [FBP args] "<message>"
#   Scripts/fbp_agent.sh [--identity "Name <email>"] --print-identity   (dry run: prints, runs nothing)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
name=""; email=""; print_only=0
if [ "${1:-}" = "--identity" ]; then
  id="${2:?--identity needs \"Name <email>\"}"; shift 2
  name="${id% <*}"; email="${id##*<}"; email="${email%>}"
  [ -n "$name" ] && [ -n "$email" ] && [ "$name" != "$id" ] || { echo "❌ --identity must be \"Name <email>\"" >&2; exit 2; }
fi
if [ "${1:-}" = "--print-identity" ]; then print_only=1; shift; fi
if [ -z "$name" ]; then
  name="$(git -C "$ROOT" config --local --get user.name || true)"
  email="$(git -C "$ROOT" config --local --get user.email || true)"
  [ -n "$name" ] && [ -n "$email" ] || { echo "❌ no local user.name/user.email in $ROOT (run the agent's migration tool or pass --identity)" >&2; exit 1; }
fi

helpers="$(git -C "$ROOT" config --local --get-all credential.https://github.com.helper || true)"
case "$email" in
  *"[bot]@users.noreply.github.com")
    first="$(printf '%s\n' "$helpers" | head -n 1)"
    if [ -n "$first" ] || ! grep -q 'git-credential-app\.sh' <<< "$helpers"; then
      echo "❌ $name is a bot but the local credential helpers do not reset and use git-credential-app.sh; refusing (no fallback login)" >&2
      exit 1
    fi ;;
esac

export GIT_AUTHOR_NAME="$name" GIT_AUTHOR_EMAIL="$email"
export GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email"

if [ "$print_only" -eq 1 ]; then
  echo "author:    $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>"
  echo "committer: $GIT_COMMITTER_NAME <$GIT_COMMITTER_EMAIL>"
  echo "push via:  $(printf '%s\n' "$helpers" | tail -n 1)"
  exit 0
fi
exec "$ROOT/FBP.sh" "$@"
