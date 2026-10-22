#!/usr/bin/env bash
# Scripts/dco_pr_commits.sh
#
# The commits of a pull request, in the shape Scripts/check_dco.sh and
# Scripts/check_commit_messages.sh read (forsgren#213: moved out of
# .github/workflows/dco.yml so its two jobs list them the same way). One line
# per commit, from the commits API (at most 250):
#   <sha> <type>:<login of the linked account, or -> <base64 of the author email> <base64 of the message>
# gh is on every GitHub-hosted runner, and its --jq is gh's own, so the runner
# needs no jq. The token reaches gh through GH_TOKEN in the environment. The
# call goes through dco_api (Scripts/lib_dco_api.sh, forsgren#287): a failed
# call is asked once more after DCO_RETRY_PAUSE seconds (default 5); one that
# answers then lists the commits, with one warning on stderr naming the first
# failure; a second failure is red naming both reasons, and lists nothing.
#
# Usage: Scripts/dco_pr_commits.sh <owner/repo> <pull-request-number>
# Exit: 0 and the lines on stdout; 1 on a wrong call or a call that failed
# twice.
# Fixture: Scripts/test_check_commit_messages.sh (gh stubbed).

set -uo pipefail

if [ "$#" -ne 2 ]; then
  echo "❌ FAIL: usage: Scripts/dco_pr_commits.sh <owner/repo> <pull-request-number>"
  exit 1
fi

# shellcheck source=Scripts/lib_dco_api.sh
source "$(dirname "$0")/lib_dco_api.sh"

dco_api "the commits of pull request #${2}" --paginate "repos/${1}/pulls/${2}/commits" \
  --jq '.[] | "\(.sha) \(if .author == null then "-" else "\(.author.type):\(.author.login)" end) \(.commit.author.email // "" | @base64) \(.commit.message | @base64)"'
