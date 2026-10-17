#!/usr/bin/env bash
# Scripts/release_token_expiry.sh
#
# The expiry of FORSGREN_RELEASE_TOKEN, shown at the top of every Release run
# (forsgren#221, step 4). One authenticated call on forsgren-template
# (`gh api -i repos/<owner>/forsgren-template`, the token as GH_TOKEN) returns
# the header `github-authentication-token-expiration` ("2026-12-02 00:00:00
# UTC") for a token that expires. One line is printed and appended to
# $GITHUB_STEP_SUMMARY, so it opens the job summary:
#
#   more than 30 days left   ✅ ... valid until <date> (<n> days)
#   30 to 8 days             ⚠️ ... expires on <date> (<n> days): renew it before
#                            the next release, and a ::warning::
#   7 days or fewer          🔴 ... expires on <date> (<n> days): renew it now,
#                            and an ::error::; the run goes on (exit 0)
#   expired; no header (a token without an expiry: not accepted); a date that
#   cannot be read; a call that was refused; no token
#                            ❌ ..., exit 1, before anything is pushed
#
# <n> is whole days left, rounded down. "Now" is RELEASE_NOW (epoch seconds,
# the self-test's seam), else the clock. The template repository is
# <owner>/forsgren-template of GITHUB_REPOSITORY, or RELEASE_TEMPLATE_REPO.
# Exit 0 shown (green, yellow or red tier), 1 ❌, 2 usage.
# Self-test: Scripts/test_release_token_expiry.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_token_expiry.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

if [ "$#" -ne 0 ]; then
  echo "usage: Scripts/release_token_expiry.sh   (FORSGREN_RELEASE_TOKEN in the environment)" >&2
  COMPLETED=1
  exit 2
fi

NAME="FORSGREN_RELEASE_TOKEN"

# show <line>: the line, on stdout and first in the job summary.
show() {
  printf '%s\n' "$1"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"; fi
}

fail_with() {
  show "❌ ${NAME} $1"
  echo "::error::${NAME} $1"
  COMPLETED=1
  exit 1
}

TOKEN="${FORSGREN_RELEASE_TOKEN:-}"
if [ -z "$TOKEN" ]; then fail_with "is not set"; fi

OWNER="${GITHUB_REPOSITORY:-}"
OWNER="${OWNER%%/*}"
REPO="${RELEASE_TEMPLATE_REPO:-${OWNER}/forsgren-template}"

RESPONSE="$(GH_TOKEN="$TOKEN" gh api -i "repos/${REPO}" 2> /dev/null)" \
  || fail_with "could not be used on ${REPO}: it is refused, revoked or expired"

RAW="$(printf '%s\n' "$RESPONSE" | tr -d '\r' | sed -n 's/^[Gg]ithub-[Aa]uthentication-[Tt]oken-[Ee]xpiration: *//p' | head -n 1)"
if [ -z "$RAW" ]; then
  fail_with "has no expiry date: a token without an expiry is not accepted (create a fine-grained token with an expiry under one year)"
fi

# civil_days <y> <m> <d>: days since 1970-01-01 (no date command: BSD and GNU differ).
civil_days() {
  local y=$1 m=$2 d=$3 era yoe doy doe
  m=$((10#$m))
  d=$((10#$d))
  if [ "$m" -le 2 ]; then y=$((y - 1)); fi
  era=$((y / 400))
  yoe=$((y - era * 400))
  doy=$(((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1))
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  echo $((era * 146097 + doe - 719468))
}

DATE_RE='^([0-9]{4})-([0-9]{2})-([0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) UTC$'
if ! [[ "$RAW" =~ $DATE_RE ]]; then
  fail_with "has an expiry date that cannot be read: ${RAW}"
fi
Y="${BASH_REMATCH[1]}"
MO="${BASH_REMATCH[2]}"
D="${BASH_REMATCH[3]}"
EXPIRES=$(($(civil_days "$Y" "$MO" "$D") * 86400 + 10#${BASH_REMATCH[4]} * 3600 + 10#${BASH_REMATCH[5]} * 60 + 10#${BASH_REMATCH[6]}))
NOW="${RELEASE_NOW:-$(date +%s)}"
DATE="${Y}-${MO}-${D}"

if [ "$EXPIRES" -le "$NOW" ]; then fail_with "expired on ${DATE}"; fi
days=$(((EXPIRES - NOW) / 86400))

if [ "$days" -gt 30 ]; then
  show "✅ ${NAME} valid until ${DATE} (${days} days)"
elif [ "$days" -gt 7 ]; then
  show "⚠️ ${NAME} expires on ${DATE} (${days} days): renew it before the next release"
  echo "::warning::${NAME} expires on ${DATE} (${days} days): renew it before the next release"
else
  show "🔴 ${NAME} expires on ${DATE} (${days} days): renew it now"
  echo "::error::${NAME} expires on ${DATE} (${days} days): renew it now"
fi
COMPLETED=1
