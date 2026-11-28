#!/usr/bin/env bash
# Scripts/check_dco.sh
#
# The DCO sign-off check (road to public, step 4). Not canon: forsgren's own.
# The ruling on forsgren#1: forsgren is EUPL-1.2, and every contribution is
# made under the Developer Certificate of Origin 1.1 (CONTRIBUTING.md), so
# every commit carries a Signed-off-by trailer from its author.
# .github/workflows/dco.yml runs this on every pull request and on every push
# to main (forsgren#81), on that push's commits only (on a push
# Scripts/dco_push_check.sh runs it, after leaving the commits of a merged
# pull request whose own DCO run succeeded to that run, forsgren#267, and
# with the pusher and the list of the commit before the push, forsgren#725);
# sfl and Quality do not run it (Quality runs its self-test).
#
# INPUT, one line per commit, from a file or stdin:
#   <sha> <author account> <base64 of the author email> <base64 of the message>
# <author account> is <type>:<login> of the GitHub account GitHub linked the
# commit to (the commits API's .author: type User, Bot, ...), or - when it
# linked it to none. The workflow writes it from the pull request's commit
# list (gh api, with gh's built-in jq; jq itself became a listed tool in
# forsgren#2, see Scripts/required_tools.txt), and on a push from git with
# Scripts/dco_push_commits.sh, whose account is always -. base64 keeps a
# message with any content on one line, so no message can forge the start of
# another commit. The format is plain text so that Scripts/test_check_dco.sh
# runs offline.
# The second argument is THE ACCOUNT GITHUB AUTHENTICATED for these commits,
# <type>:<login>:<id>: who opened the pull request (the event's
# pull_request.user), or who pushed (the push event's sender); the fourth
# says which, opener (the default) or pusher. The third is the list of
# exempt automation identities, .github/dco-exempt-identities.conf, as it
# was BEFORE the change judged (the workflow hands over the base commit's
# file for a pull request, and Scripts/dco_push_check.sh the file of the
# commit main was at for a push). With no account, an account without its
# id, no list or a list that is not there, no commit is exempt.
#
# THE RULE, per commit:
#   - its trailers are its LAST paragraph (after the last blank line, once
#     trailing blank lines and CRs are dropped), and never the subject
#     paragraph: a message that is one paragraph has no trailers;
#   - one line of that paragraph is, whole, `Signed-off-by: Name <email>`
#     (the key spelled as `git commit -s` writes it);
#   - that email is the commit author's, compared without case. A sign-off
#     by someone else is not the author's certificate.
# A Signed-off-by in the body, mid-line or as the subject is no sign-off.
#
# THE ONE SIGNER PAIR (forsgren#676, option A): GitHub records a Dependabot
# pull request it squash-merges as authored by Dependabot's noreply email,
# while Dependabot signs its commits off with another address. Exactly one
# author email and one sign-off line, both in SIGNER_PAIR_* below, count as
# the same signer: the author email as written (not without case), and the
# whole trailer line, name and email, as written (trailing blanks aside).
# Any other author with that sign-off, or that author with any other
# sign-off than the pair's, is red; nothing else is relaxed.
# Merge commits get no exception: a pull request that merges main into its
# branch signs that merge off too (`git merge --signoff`; `-s` there picks
# the merge strategy, it does not sign off).
#
# THE ONE EXEMPTION, registered automation identities (forsgren#725; before
# it, ruled 2026-10-02, any Bot account that opened the pull request). A
# sign-off is a person's certificate; an automation identity (a GitHub App's
# bot account: a dependency update service, a coding agent) is no person
# and certifies nothing. Its commit is EXEMPT from the sign-off, and named
# as exempt, which is not a certification by that identity. A commit is
# exempt only when ALL hold:
#   - its author email is the noreply address of an identity in the list,
#     <id>+<login>@users.noreply.github.com, id and login both (a login can
#     be registered again, an id cannot);
#   - GitHub authenticated that same account, id and login, as the one that
#     pushed the commit to main or that opened the pull request;
#   - in a pull request, GitHub also linked the commit to that Bot account.
# The second is the provenance, and the only fact here nobody can write: a
# commit's author name and email are text its maker chooses, and GitHub
# links a commit to an account by that email, so neither proves anything.
# Who pushed and who opened a pull request are what GitHub's own login
# established: to be named there as an App's bot takes that App's key. So
# a person who authors a commit under a listed identity and pushes it, or
# opens a pull request with it, is the authenticated account, is not that
# identity, and the commit is not exempt.
# What this cannot see: who pushed a commit into a pull request's branch.
# Only the listed account and people with write access can push to the
# branch of a pull request that account opened, as before forsgren#725.
#
# An automation identity never passes by signing off:
#   - an exempt commit that carries a Signed-off-by is red: the identity
#     certifies nothing, so the line would claim what nobody declared. One
#     line is left alone: Dependabot's own, the signer pair's, which
#     GitHub's service writes on its commits and nobody here controls;
#   - a commit whose author is a bot's noreply address (or that GitHub
#     linked to a Bot account) and that is NOT exempt is red, signed off or
#     not: an identity that is not listed, or a listed one GitHub did not
#     authenticate for this push or pull request. The signer pair aside.
# Every commit by a person is held to THE RULE, whoever pushed it.
#
# This check is the authority only where GitHub hands it the authenticated
# account: in .github/workflows/dco.yml. FBP.sh leaves the sign-off off for
# a listed identity from the local file and the local git identity, which
# is a convenience and proves nothing; the workflow judges the push.
#
# Red-on-zero: no commit read is red. Nothing checked is not signed off.
# The FAIL lines name the short sha, the subject as written, and why; they
# never print the author's email or the sign-off's.
#
# Usage: Scripts/check_dco.sh [commits-file [account [list [opener|pusher]]]]
#   commits-file: default, or -, stdin; account: <type>:<login>[:<id>]
# Exit: 0 every commit signed off or exempt, 1 a finding, a malformed line,
# a malformed account, role or list, or no commit, 2 the input file missing.
# Fixture: Scripts/test_check_dco.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

INPUT="${1:--}"
ACTOR_ARG="${2:-}"
LIST="${3:-}"
ROLE="${4:-opener}"

# An account: <type>:<login>, and :<id> when GitHub authenticated it. A login
# is letters, digits and hyphens; a GitHub App's bot account adds [bot],
# which no person's login can hold.
ACCOUNT='^([A-Za-z]+):([A-Za-z0-9-]+(\[bot\])?)(:([0-9]+))?$'
# A line of the list: <id>|<login>, the login a bot account's.
LIST_LINE='^[0-9]+\|[A-Za-z0-9-]+\[bot\]$'
BOT_NOREPLY='[bot]@users.noreply.github.com'

# The one signer pair (THE ONE SIGNER PAIR above): the author email GitHub
# records for a Dependabot squash merge, and Dependabot's own sign-off line.
SIGNER_PAIR_AUTHOR='49699333+dependabot[bot]@users.noreply.github.com'
SIGNER_PAIR_SIGNOFF='Signed-off-by: dependabot[bot] <support@github.com>'

case "$ROLE" in
  opener) BROUGHT="which opened this pull request" ;;
  pusher) BROUGHT="which pushed it" ;;
  *)
    echo "❌ FAIL: DCO: the account's role is neither opener nor pusher — no commit can be judged against it"
    exit 1
    ;;
esac

# The account GitHub authenticated. actor_email is the noreply address of
# that account when it is a Bot with its id, else empty: nobody is exempt.
actor_login="-"
actor_email=""
if [ -n "$ACTOR_ARG" ]; then
  if ! [[ "$ACTOR_ARG" =~ $ACCOUNT ]]; then
    echo "❌ FAIL: DCO: the account GitHub authenticated (the pull request's opener, or the pusher) is not <type>:<login>[:<id>] — no commit can be judged against it"
    exit 1
  fi
  actor_login="${BASH_REMATCH[2]}"
  if [ "${BASH_REMATCH[1]}" = "Bot" ] && [ -n "${BASH_REMATCH[5]}" ]; then
    actor_email="${BASH_REMATCH[5]}+${actor_login}@users.noreply.github.com"
  fi
fi

if [ "$INPUT" != "-" ] && [ ! -f "$INPUT" ]; then
  echo "❌ FAIL: DCO: input file not found: ${INPUT}"
  exit 2
fi

# The list: the noreply address of every identity in it, one per line. A
# list that is not there lists nobody; a line in another shape is red for
# every commit, never skipped: a list half read is not the list.
listed_emails=""
if [ -n "$LIST" ] && [ -f "$LIST" ]; then
  entryno=0
  while IFS= read -r entry || [ -n "$entry" ]; do
    entryno=$((entryno + 1))
    entry="${entry%$'\r'}"
    case "$entry" in '' | '#'*) continue ;; esac
    if ! [[ "$entry" =~ $LIST_LINE ]]; then
      echo "❌ FAIL: DCO: line ${entryno} of the list of exempt automation identities is not <id>|<login>[bot] — no commit can be judged against a list that cannot be read"
      exit 1
    fi
    listed_emails="${listed_emails}${entry%%|*}+${entry#*|}@users.noreply.github.com"$'\n'
  done < "$LIST"
fi

# exempt_identity: the commit in $email and $account is an exempt automation
# identity's (THE ONE EXEMPTION above). One condition per line; the mutation
# proofs in Scripts/test_check_dco.sh rewrite each by its exact text.
exempt_identity() {
  [ -n "$actor_email" ] || return 1
  grep -qxF -- "$email" <<< "$listed_emails" || return 1
  [ "$email" = "$actor_email" ] || return 1
  [ "$ROLE" = "pusher" ] || [ "$account" = "Bot:${actor_login}" ] || return 1
}

# bot_author: the commit names an automation identity as its author: a bot's
# noreply address (without case), or an account GitHub calls a Bot.
bot_author() {
  local lower
  lower="$(printf '%s' "$email" | tr '[:upper:]' '[:lower:]')"
  [[ "$lower" == *"$BOT_NOREPLY" ]] || [[ "$account" == Bot:* ]]
}

# platform_signoff: the sign-off lines in $signoffs are the signer pair's one
# line, on the signer pair's author.
platform_signoff() {
  [ "$email" = "$SIGNER_PAIR_AUTHOR" ] && [ "$signoffs" = "$SIGNER_PAIR_SIGNOFF" ]
}

# trailer_block <verdict|signoffs> <author-email>: reads one message on
# stdin. verdict prints signed, mismatch or unsigned; signoffs prints every
# Signed-off-by line of the trailer block, trailing blanks dropped. The
# mutation proofs in Scripts/test_check_dco.sh rewrite the `while (start > 1`
# line, the tolower comparison line and the signer pair line, each by its
# exact text: keep the three on their own line.
trailer_block() {
  awk -v mode="$1" -v author="$2" -v pair_author="$SIGNER_PAIR_AUTHOR" \
      -v pair_signoff="$SIGNER_PAIR_SIGNOFF" '
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
          trailer = line[i]
          sub(/[ \t]+$/, "", trailer)
          if (author == pair_author && trailer == pair_signoff) matched = 1
          if (mode == "signoffs") print trailer
        }
      }
      if (mode == "signoffs") exit
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
  subject="$(head -n 1 <<<"$message" | tr -d '\r')"
  signoffs="$(printf '%s\n' "$message" | trailer_block signoffs "")"
  # The exemption. An exempt commit carries no sign-off; the mutation proofs
  # rewrite the `if [ -n "$signoffs" ]` line by its exact text.
  if exempt_identity; then
    if [ -n "$signoffs" ] && ! platform_signoff; then
      echo "❌ FAIL: DCO: commit ${short} (${subject}) is by the automation identity ${actor_login} and carries a Signed-off-by trailer — an automation identity certifies nothing, so its commits carry no sign-off (CONTRIBUTING.md, Automation identities)"
      findings=$((findings + 1))
      continue
    fi
    echo "ℹ️  DCO: commit ${short} (${subject}) is exempt: authored by the registered automation identity ${actor_login}, ${BROUGHT}"
    exempt=$((exempt + 1))
    continue
  fi
  if [ -z "$email" ]; then
    echo "❌ FAIL: DCO: commit ${short} (${subject}) has no author email — a sign-off cannot be matched to its author"
    findings=$((findings + 1))
    continue
  fi
  NOT_EXEMPT="its author is an automation identity that is not exempt here: only one listed in .github/dco-exempt-identities.conf that GitHub authenticated as the pusher, or as the pull request's opener, is (CONTRIBUTING.md, Automation identities)"
  case "$(printf '%s\n' "$message" | trailer_block verdict "$email")" in
    signed)
      # An automation identity never passes by signing off. The mutation
      # proof rewrites the if line by its exact text.
      if bot_author && ! platform_signoff; then
        echo "❌ FAIL: DCO: commit ${short} (${subject}) is signed off by an automation identity, which certifies nothing — ${NOT_EXEMPT}"
        findings=$((findings + 1))
      fi
      ;;
    mismatch)
      echo "❌ FAIL: DCO: commit ${short} (${subject}) is signed off, but not by its author — the Signed-off-by email must be the commit author's email"
      findings=$((findings + 1))
      ;;
    *)
      if bot_author; then
        echo "❌ FAIL: DCO: commit ${short} (${subject}) has no Signed-off-by trailer, and ${NOT_EXEMPT}"
      else
        echo "❌ FAIL: DCO: commit ${short} (${subject}) has no Signed-off-by trailer — add one with git commit --amend -s (or git rebase --signoff for several), see CONTRIBUTING.md"
      fi
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
  echo "✅ DCO: ${commits} commit(s): $((commits - exempt)) signed off by its author, ${exempt} by a registered automation identity that GitHub authenticated, exempt"
  exit 0
fi
echo "✅ DCO: ${commits} commit(s), every one signed off by its author"
exit 0
