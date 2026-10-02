#!/usr/bin/env bash
# Scripts/check_dco.sh
#
# The DCO sign-off check (road to public, step 4). Not canon: forsgren's own.
# The ruling on forsgren#1: forsgren is EUPL-1.2, and every contribution is
# made under the Developer Certificate of Origin 1.1 (CONTRIBUTING.md), so
# every commit of a pull request carries a Signed-off-by trailer from its
# author. .github/workflows/dco.yml runs this on every pull request; sfl and
# Quality do not, since a commit on main has no pull request.
#
# INPUT, one line per commit, from a file or stdin:
#   <sha> <author account> <base64 of the author email> <base64 of the message>
# <author account> is <type>:<login> of the GitHub account GitHub linked the
# commit to (the commits API's .author: type User, Bot, ...), or - when it
# linked it to none. The workflow writes it from the pull request's commit
# list (gh api, with gh's built-in jq; jq itself is not a listed tool here,
# see Scripts/check_coverage.sh). base64 keeps a message with any content on
# one line, so no message can forge the start of another commit. The
# format is plain text so that Scripts/test_check_dco.sh runs offline.
# The second argument is the account that opened the pull request,
# <type>:<login> (the event's pull_request.user); with none, no commit is
# exempt.
#
# THE RULE, per commit:
#   - its trailers are its LAST paragraph (after the last blank line, once
#     trailing blank lines and CRs are dropped), and never the subject
#     paragraph: a message that is one paragraph has no trailers;
#   - one line of that paragraph is, whole, `Signed-off-by: Name <email>`
#     (the key spelled as `git commit -s` writes it);
#   - that email is the commit author's, compared without case. A sign-off
#     by someone else is not the author's certificate.
# A Signed-off-by in the body, mid-line, or as the subject is no sign-off.
# Merge commits get no exception: a pull request that merges main into its
# branch signs that merge off too (`git merge --signoff`; `-s` there picks
# the merge strategy, it does not sign off).
#
# THE ONE EXEMPTION, bots (ruled by Yves 2026-10-02: Dependabot's commits
# carry no Signed-off-by, and a bot certifies nothing). A commit is exempt,
# and named as exempt, when BOTH hold:
#   - GitHub linked it to an account of type Bot (dependabot[bot] and other
#     GitHub Apps; a person's account is a User);
#   - that Bot account opened the pull request.
# Never on the author's name or email (`...[bot]@users.noreply.github.com`
# is a string anyone can put in a commit), and not on the linked account
# alone: GitHub links a commit to an account by its author email, so a
# contributor who writes a bot's noreply email gets the bot's account. Who
# opened the pull request is what GitHub authenticated, and a bot's pull
# request branch is pushed by the bot and by people with write access only.
# A human commit in a bot's pull request is held to the rule.
#
# Red-on-zero: no commit read is red. Nothing checked is not signed off.
# The FAIL lines name the short sha, the subject as written, and why; they
# never print the author's email or the sign-off's.
#
# Usage: Scripts/check_dco.sh [commits-file [opener]]
#   commits-file: default, or -, stdin; opener: <type>:<login>
# Exit: 0 every commit signed off or exempt, 1 a finding, a malformed line,
# a malformed opener or no commit, 2 the input file missing.
# Fixture: Scripts/test_check_dco.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

INPUT="${1:--}"
OPENER="${2:-}"

# An account: <type>:<login>. A login is letters, digits and hyphens; a
# GitHub App's bot account adds [bot], which no person's login can hold.
ACCOUNT='^[A-Za-z]+:[A-Za-z0-9-]+(\[bot\])?$'

opener="-"
if [ -n "$OPENER" ]; then
  if ! [[ "$OPENER" =~ $ACCOUNT ]]; then
    echo "❌ FAIL: DCO: the pull request opener is not <type>:<login> — no commit can be judged against it"
    exit 1
  fi
  opener="$OPENER"
fi
opener_login="${opener#*:}"

if [ "$INPUT" != "-" ] && [ ! -f "$INPUT" ]; then
  echo "❌ FAIL: DCO: input file not found: ${INPUT}"
  exit 2
fi

# judge <author-email>: reads one message on stdin, prints signed, mismatch
# or unsigned. The mutation proofs in Scripts/test_check_dco.sh rewrite the
# `while (start > 1` line and the tolower comparison line, each by its exact
# text: keep both on their own line.
judge() {
  awk -v author="$1" '
    { sub(/\r$/, ""); line[NR] = $0 }
    END {
      n = NR
      while (n > 0 && line[n] ~ /^[ \t]*$/) n--
      first = 1
      while (first <= n && line[first] ~ /^[ \t]*$/) first++
      # The trailer block: the last paragraph, never the subject paragraph.
      start = n
      while (start > 1 && line[start - 1] !~ /^[ \t]*$/) start--
      if (start <= first) start = n + 1
      found = 0; matched = 0
      for (i = start; i <= n; i++) {
        if (line[i] ~ /^Signed-off-by: [^<>]+ <[^<>]+>[ \t]*$/) {
          found = 1
          email = line[i]
          sub(/^[^<]*</, "", email)
          sub(/>[ \t]*$/, "", email)
          if (tolower(email) == tolower(author)) matched = 1
        }
      }
      if (matched) print "signed"
      else if (found) print "mismatch"
      else print "unsigned"
    }'
}

COMMIT_LINE='^([0-9a-f]{7,64}) (-|[A-Za-z]+:[A-Za-z0-9-]+(\[bot\])?) ([A-Za-z0-9+/=]*) ([A-Za-z0-9+/=]+)$'

commits=0
findings=0
exempt=0
lineno=0
while IFS= read -r row || [ -n "$row" ]; do
  lineno=$((lineno + 1))
  [ -n "$row" ] || continue
  if ! [[ "$row" =~ $COMMIT_LINE ]]; then
    echo "❌ FAIL: DCO: malformed line ${lineno} — not <sha> <author account> <base64 author email> <base64 message>"
    findings=$((findings + 1))
    continue
  fi
  sha="${BASH_REMATCH[1]}"
  account="${BASH_REMATCH[2]}"
  short="${sha:0:12}"
  commits=$((commits + 1))
  if ! email="$(printf '%s' "${BASH_REMATCH[4]}" | base64 -d 2>/dev/null)" \
     || ! message="$(printf '%s' "${BASH_REMATCH[5]}" | base64 -d 2>/dev/null)"; then
    echo "❌ FAIL: DCO: commit ${short} — its line does not decode as base64"
    findings=$((findings + 1))
    continue
  fi
  subject="$(printf '%s\n' "$message" | head -n 1 | tr -d '\r')"
  # The exemption. The mutation proofs in Scripts/test_check_dco.sh rewrite
  # this if line by its exact text: keep it whole, on its own line.
  if [ "$account" = "Bot:${opener_login}" ] && [ "$opener" = "Bot:${opener_login}" ]; then
    echo "ℹ️  DCO: commit ${short} (${subject}) is exempt: authored by the bot account ${opener_login}, which opened this pull request"
    exempt=$((exempt + 1))
    continue
  fi
  if [ -z "$email" ]; then
    echo "❌ FAIL: DCO: commit ${short} (${subject}) has no author email — a sign-off cannot be matched to its author"
    findings=$((findings + 1))
    continue
  fi
  case "$(printf '%s\n' "$message" | judge "$email")" in
    signed) ;;
    mismatch)
      echo "❌ FAIL: DCO: commit ${short} (${subject}) is signed off, but not by its author — the Signed-off-by email must be the commit author's email"
      findings=$((findings + 1))
      ;;
    *)
      echo "❌ FAIL: DCO: commit ${short} (${subject}) has no Signed-off-by trailer — add one with git commit --amend -s (or git rebase --signoff for several), see CONTRIBUTING.md"
      findings=$((findings + 1))
      ;;
  esac
done < <(if [ "$INPUT" = "-" ]; then cat; else cat -- "$INPUT"; fi)

if [ "$commits" -eq 0 ] && [ "$findings" -eq 0 ]; then
  echo "❌ FAIL: DCO: no commit to check — a list of nothing is not a list of signed-off commits"
  exit 1
fi

if [ "$findings" -ne 0 ]; then
  echo ""
  echo "DCO: ${findings} finding(s) in ${commits} commit(s). Every commit needs a Signed-off-by trailer from its author (CONTRIBUTING.md, Developer Certificate of Origin)."
  exit 1
fi

if [ "$exempt" -ne 0 ]; then
  echo "✅ DCO: ${commits} commit(s): $((commits - exempt)) signed off by its author, ${exempt} by the bot account that opened the pull request, exempt"
  exit 0
fi
echo "✅ DCO: ${commits} commit(s), every one signed off by its author"
exit 0
