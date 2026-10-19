#!/usr/bin/env bash
# Scripts/check_commit_messages.sh
#
# The private-names check of commit messages (forsgren#213). Not canon:
# forsgren's own, around the canon matcher. This repository is public, and a
# commit message is published with the commit. FBP.sh already refuses a
# message that names a private name, but a commit that never passed through
# FBP.sh (a pull request, a hand-made push) is judged by nothing else, so
# .github/workflows/dco.yml runs this on every commit a pull request or a
# push to main brings. The matcher and the list are the gate's, not a copy:
# every message goes through Scripts/check_private_names.sh --message - (same
# list sources, same case-insensitive substring match, the repository's own
# name left out), on stdin, never in a file or an argument.
#
# INPUT, one line per commit, from a file or stdin, the lines
# Scripts/check_dco.sh reads (Scripts/dco_pr_commits.sh lists a pull
# request's, Scripts/dco_push_commits.sh a push's):
#   <sha> <author account> <base64 of the author email> <base64 of the message>
#
# A hit fails. The FAIL line names the short sha and the number of the commit
# in the list, never the name, never the message and never its subject: a CI
# log and the job summary are public. No history is rewritten: a commit that
# already names a name is reworded by hand (or the name is removed from the
# list), and the check judges only the commits a push or a pull request
# brings.
#
# Red-on-zero: no commit read is red. And in GitHub Actions
# (GITHUB_ACTIONS=true) the list must be there: --message alone passes
# without a list, which is right for FBP.sh on a laptop and wrong in CI, so
# an unset or emptied FORSGREN_PRIVATE_NAMES (a fork's pull request gets no
# secrets) is exit 2 here, naming the Actions secret.
#
# Usage: Scripts/check_commit_messages.sh [commits-file]   (default or -: stdin)
# Exit: 0 every message clean; 1 a name found, a malformed line or no commit;
# 2 the input file missing, no list in Actions, or the matcher could not judge.
# Fixture: Scripts/test_check_commit_messages.sh.

set -uo pipefail
# Tracing off: the list must never reach a trace.
set +x

cd "$(dirname "$0")/.." || exit 1

INPUT="${1:--}"
GATE="./Scripts/check_private_names.sh"

if [ "$INPUT" != "-" ] && [ ! -f "$INPUT" ]; then
  echo "❌ FAIL: commit messages: input file not found: ${INPUT}"
  exit 2
fi

if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  # shellcheck source=Scripts/lib_private_names.sh
  source Scripts/lib_private_names.sh
  private_names_parse "${FORSGREN_PRIVATE_NAMES:-}"
  if [ "$PRIVATE_NAMES_COUNT" -eq 0 ]; then
    echo "❌ FAIL: no list of private names: the Actions secret FORSGREN_PRIVATE_NAMES is not set or holds no names here, so no commit message can be judged. A pull request from a fork gets no secrets: the maintainer runs ./FBP.sh on the branch instead"
    exit 2
  fi
fi

COMMIT_LINE='^([0-9a-f]{7,64}) (-|[A-Za-z]+:[A-Za-z0-9-]+(\[bot\])?) ([A-Za-z0-9+/=]*) ([A-Za-z0-9+/=]+)$'

ROWS=()
while IFS= read -r row || [ -n "$row" ]; do
  [ -n "$row" ] && ROWS+=("$row")
done < <(cat -- "$INPUT")
total=${#ROWS[@]}

if [ "$total" -eq 0 ]; then
  echo "❌ FAIL: commit messages: no commit in the input — nothing checked is not clean"
  exit 1
fi

findings=0
unjudged=0
malformed=0
for ((i = 0; i < total; i++)); do
  row="${ROWS[i]}"
  n=$((i + 1))
  if ! [[ "$row" =~ $COMMIT_LINE ]]; then
    echo "❌ FAIL: commit messages: malformed line ${n} — not <sha> <author account> <base64 author email> <base64 message>"
    malformed=$((malformed + 1))
    continue
  fi
  short="${BASH_REMATCH[1]:0:12}"
  if ! message="$(printf '%s' "${BASH_REMATCH[5]}" | base64 -d 2>/dev/null)"; then
    echo "❌ FAIL: commit messages: commit ${short} (#${n} of ${total}) — its line does not decode as base64"
    malformed=$((malformed + 1))
    continue
  fi
  rc=0
  verdict="$(printf '%s' "$message" | "$GATE" --message - 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "❌ FAIL: commit ${short} names a private name (#${n} of ${total}): reword the commit, the message is not shown here"
    findings=$((findings + 1))
  elif [ "$rc" -ne 0 ]; then
    echo "❌ FAIL: commit ${short} (#${n} of ${total}) could not be judged (exit ${rc}): ${verdict}"
    unjudged=$((unjudged + 1))
  fi
done

if [ "$findings" -ne 0 ] || [ "$malformed" -ne 0 ]; then
  exit 1
fi
if [ "$unjudged" -ne 0 ]; then
  exit 2
fi
echo "OK: ${total} commit messages checked, none names a private name"
