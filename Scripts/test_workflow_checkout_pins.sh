#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Action pins (forsgren#1, ladder step 17), the canon row `checkout pins`.
# PORTED from coachretreat-website, the estate's best-shape copy, adapted
# only in these header comments: the code is coachretreat's, byte for byte.
# The lineage: another estate repository's test_persist_credentials.sh, then another estate repository
# (the sha pin and the step-scoped scan), coachretreat-website (its unit
# 368), and agilelean-website's every-action pin (its unit 399, coachretreat's
# unit 400). Another estate repository's own copy still checks actions/checkout only.
#
# SECURITY, not tidiness. A tag or a branch is resolved when the runner
# fetches it, so whoever controls the action's repository decides what runs
# in forsgren's CI, with the job's token. A commit sha cannot be re-pointed.
#
# Every actions/checkout in this repo must:
#
#   1. Be sha-pinned (40-hex ref, not a floating tag like @v4): a tag can
#      be re-pointed by the action's maintainers; the sha cannot.
#   2. Set persist-credentials: false — checkout persists GITHUB_TOKEN
#      into .git/config for the rest of the job unless disabled; no step
#      in this repo needs it.
#
# STEP-SCOPED SCAN, and this is where coachretreat's port first broke.
# konenki writes
# `- uses: actions/checkout@…` with `uses` ON the dash line (indent 6), so a
# scan that walks forward while indent > the uses-line indent sees `with:` at
# 8 and keeps going. coachretreat writes `- name: Checkout …` and then
# `uses:` on its own line at indent 8 — `with:` is ALSO 8, so that scan broke
# at the first line and reported persist-credentials missing when it was
# right there.
#
# The inherited check was not testing the property, it was testing an
# authoring style, and it could only ever be correct in the repo it was
# written in. This version finds the enclosing STEP (the nearest `- ` line at
# or above) and searches to the next step boundary, so both forms judge the
# same.

# Overridable so the pins can be shown FAILING against a mutated copy — a
# green check that was never seen red is a check that might assert nothing.
# Scripts/test_workflow_checkout_pins_mutations.sh drives that: it strips the
# sha pin, then persist-credentials, and fails if either slips through.
WF_DIR="${1:-.github/workflows}"

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: checkout pins aborted before completing all cases" >&2
    exit 1
  fi
}
trap finish EXIT

failed=0
fail() { echo "❌ FAIL: $*"; failed=1; }

checked=0
for wf in "$WF_DIR"/*.yml; do
  while IFS=: read -r lineno line; do
    [[ -z "$lineno" ]] && continue
    checked=$((checked + 1))

    # Pin 1: sha-pinned ref.
    if ! grep -qE 'actions/checkout@[0-9a-f]{40}' <<< "$line"; then
      fail "${wf}:${lineno} checkout is not sha-pinned: ${line#"${line%%[![:space:]]*}"}"
    fi

    # Pin 2: persist-credentials: false somewhere in the SAME step.
    #
    # Walk back to the step's `- ` line to learn the step indent, then read
    # forward until the next line at that indent or shallower. Whether `uses`
    # sits on the dash line or below a `- name:` no longer matters.
    n="$(wc -l < "$wf")"
    step_start="$lineno"
    step_indent=""
    i="$lineno"
    while [[ "$i" -ge 1 ]]; do
      l="$(sed -n "${i}p" "$wf")"
      if grep -qE '^[[:space:]]*-[[:space:]]' <<< "$l"; then
        step_start="$i"
        step_indent="$(printf '%s' "$l" | sed -E 's/[^ ].*//' | awk '{print length}')"
        break
      fi
      i=$((i - 1))
    done
    if [[ -z "$step_indent" ]]; then
      fail "${wf}:${lineno} could not find the enclosing step for this checkout — scan pattern broken?"
      continue
    fi

    found=""
    i=$((step_start + 1))
    while [[ "$i" -le "$n" ]]; do
      l="$(sed -n "${i}p" "$wf")"
      if [[ -z "${l//[[:space:]]/}" ]]; then i=$((i + 1)); continue; fi
      indent="$(printf '%s' "$l" | sed -E 's/[^ ].*//' | awk '{print length}')"
      # Next step, or out of the steps list entirely.
      if [[ "$indent" -le "$step_indent" ]]; then break; fi
      if grep -qE '^[[:space:]]*persist-credentials:[[:space:]]*false[[:space:]]*$' <<< "$l"; then
        found="yes"
        break
      fi
      i=$((i + 1))
    done
    if [[ "$found" != "yes" ]]; then
      fail "${wf}:${lineno} checkout does not set persist-credentials: false"
    fi
  done < <(grep -nE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*actions/checkout' "$wf")
done

if [[ "$checked" -eq 0 ]]; then
  fail "no actions/checkout found in ${WF_DIR} — scan pattern broken?"
fi

# Pin 3 — EVERY third-party action, not just checkout. coachretreat's unit
# 400, ported from agilelean-website (its unit 399).
#
# FIX THE CLASS, NOT THE INSTANCE. The two pins above grep for the literal
# string `actions/checkout`, so they test ONE INSTANCE of the property: that no
# action here can be re-pointed by its maintainer between two runs. agilelean
# was carrying `actions/setup-node@v4` outside that scan for as long as it had
# existed — the only unpinned action in the estate, invisible to a gate all
# three repos share, because the check was written around the name of the
# action that prompted it.
#
# This repo uses checkout and nothing else, so the pin is green here today.
# That is why Scripts/test_workflow_checkout_pins_mutations.sh proves it
# against a SYNTHETIC second action rather than against these workflows: a gate
# that can only test what the repo happens to contain goes green on the day
# someone adds a second action, which is exactly when it stops being true.
#
# Local references (`./.github/actions/...`, same-repo reusable workflows) are
# skipped — they are this repo's own content at the commit being built, and
# have no upstream to re-point.
pinned=0
for wf in "$WF_DIR"/*.yml; do
  while IFS=: read -r lineno line; do
    [[ -z "$lineno" ]] && continue

    ref="${line#*uses:}"
    ref="${ref%%#*}"
    ref="$(printf '%s' "$ref" | tr -d '[:space:]')"
    [[ -z "$ref" ]] && continue
    case "$ref" in
      ./*) continue ;;
    esac

    pinned=$((pinned + 1))
    if ! grep -qE '@[0-9a-f]{40}$' <<< "$ref"; then
      fail "${wf}:${lineno} action is not sha-pinned: ${ref} — a tag can be re-pointed by its maintainer between two runs, a sha cannot"
    fi
  done < <(grep -nE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*' "$wf")
done

# Same reason as the checkout guard above: a scan that matches nothing must
# fail rather than report a clean estate it never looked at.
if [[ "$pinned" -eq 0 ]]; then
  fail "no uses: lines found in ${WF_DIR} — the third-party scan pattern is broken"
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: workflow checkout pins"
  exit 1
fi

echo "OK: workflow action pins (${checked} checkouts sha-pinned with persist-credentials: false, ${pinned} third-party actions sha-pinned)"
