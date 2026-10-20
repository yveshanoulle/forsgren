#!/usr/bin/env bash
# Scripts/release_report.sh
#
# What a Release run did, for its last step (forsgren#221), which runs
# whatever happened. Two inputs:
#
#   - the log file: the steps that do work append one line each,
#     `<step id>: <what was done>`. The ids, in order: token, quality, plan,
#     free, head, publish, verify-install, template, metrics-pr, metrics (the
#     last one logs `PR #N merged, forsgren run <url> green`). A release makes
#     no bump commit (forsgren#237): it tags main's Quality-green head.
#   - the outcomes, in the environment variable RELEASE_STEP_OUTCOMES, one
#     `<step id>=<outcome>` line per step of the job (the workflow passes
#     steps.<id>.outcome of every step, the way the maintenance summary does).
#     The failed step is read from them, never inferred from the log: a step
#     that records nothing, or fails before it could, is still the one named.
#     The step ids, in order: main, checkout, setup-go, log, then the logged
#     ones above, with `resume` (Find the release to resume) after token. With
#     RELEASE_RESUME=pins (a resumed run) only token, resume, verify-install,
#     template and metrics are expected.
#
#   - when the plan step failed, the plan's own output (RELEASE_PLAN_OUTPUT, a
#     file; the workflow tees the plan there): its `blocking=` machine lines
#     (forsgren#232) become a table `| Issue | Blocks because | Do |` in
#     "What to do next", and the ::error:: line names the issue numbers.
#
# Usage: Scripts/release_report.sh <log-file> <job-status>
#        Scripts/release_report.sh --table <plan-output-file>
# The second form (forsgren#231, step 3) prints only the table of blocking
# issues and the list of ready issues, rendered from the plan's output by the
# same functions the run summary uses, and exits 0. Scripts/release_precheck.sh
# calls it, so the pre-check and the Release run page cannot differ in shape.
# On success it prints the done steps. On any other status it prints an
# ::error:: line that names the first step whose outcome is failure (or
# cancelled), its id in brackets, then what was already done and what was not
# (the logged steps without a line). With no outcomes, or none that failed, it
# says the failed step is unknown. It writes the same text to
# $GITHUB_STEP_SUMMARY when that is set, and always exits 0: it reports, the
# failed step already failed the run.
# Self-test: Scripts/test_release_report.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_report.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

if [ "$#" -ne 2 ]; then
  echo "usage: Scripts/release_report.sh <log-file> <job-status>" >&2
  COMPLETED=1
  exit 2
fi
LOG="$1"
STATUS="$2"
TABLE_ONLY=0
if [ "$LOG" = "--table" ]; then
  TABLE_ONLY=1
  RELEASE_PLAN_OUTPUT="$STATUS"
  LOG=/dev/null
  STATUS=table
fi

ALL_IDS="main checkout setup-go log token resume quality plan free head publish verify-install template metrics-pr metrics"
LOGGED_IDS="token quality plan free head publish verify-install template metrics-pr metrics"
# A resumed run (RELEASE_RESUME=pins) skips everything between the token check
# and the install check.
if [ "${RELEASE_RESUME:-}" = pins ]; then LOGGED_IDS="token resume verify-install template metrics-pr metrics"; fi

# name_of <id>: the step's name in release.yml.
name_of() {
  case "$1" in
    main) echo "Require a run on main" ;;
    checkout) echo "Check out main" ;;
    setup-go) echo "Set up Go" ;;
    log) echo "Start the log of what is done" ;;
    token) echo "Check the release token is set" ;;
    resume) echo "Find the release to resume" ;;
    quality) echo "Quality is green on main" ;;
    plan) echo "Plan the release" ;;
    free) echo "Check the version is new" ;;
    head) echo "Check main has not moved" ;;
    publish) echo "Create the tag and the release" ;;
    verify-install) echo "Check an install of the release reports its version" ;;
    template) echo "Move the pins and README of forsgren-template" ;;
    metrics-pr) echo "Open the pin pull request in forsgren-metrics" ;;
    metrics) echo "Merge the pin pull request and run forsgren in forsgren-metrics" ;;
    *) echo "$1" ;;
  esac
}

# outcome_of <id>: the outcome the workflow passed for that step, or nothing.
outcome_of() {
  printf '%s\n' "${RELEASE_STEP_OUTCOMES:-}" | sed -n "s/^$1=//p" | head -n 1
}

DONE=""
MISSING=""
for step in $LOGGED_IDS; do
  line=""
  if [ -f "$LOG" ]; then line="$(grep -m1 "^${step}: " "$LOG" || true)"; fi
  if [ -n "$line" ]; then
    DONE="${DONE}- ${line}
"
  else
    MISSING="${MISSING}${MISSING:+, }${step}"
  fi
done

failed_id=""
for step in $ALL_IDS; do
  outcome="$(outcome_of "$step")"
  if [ "$outcome" = failure ] || [ "$outcome" = cancelled ]; then
    failed_id="$step"
    break
  fi
done

# line_value <regex>: the first line of the log matching it, or nothing.
line_value() {
  if [ -f "$LOG" ]; then grep -m1 -E "$1" "$LOG" || true; fi
}

# blocking_table: the issues a stopped plan names (forsgren#232), from the
# machine lines `blocking=<N> TAB <kind> TAB <title> TAB <tag>` of the plan's
# own output (RELEASE_PLAN_OUTPUT, the file the workflow tees the plan to).
# Sets BLOCKED_TABLE (a markdown table, one row per issue, in the plan's
# order) and BLOCKED_NUMS (#221, #231); both stay empty when the plan names no
# issue. The issue is a link when the repository is known (GH_REPO, else
# GITHUB_REPOSITORY), else a plain #N.
BLOCKED_TABLE=""
BLOCKED_NUMS=""
blocking_table() {
  local file="${RELEASE_PLAN_OUTPUT:-}" repo link number kind title tag asked reason action rows="" n_blocked=0
  [ -n "$file" ] && [ -f "$file" ] || return 0
  repo="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
  asked="${RELEASE_BUMP:-a lower bump}"
  while IFS="$(printf '\t')" read -r number kind title tag; do
    number="${number#blocking=}"
    [ -n "$number" ] || continue
    title="${title//|/\\|}"
    link="#${number}"
    if [ -n "$repo" ]; then link="[#${number}](${GITHUB_SERVER_URL:-https://github.com}/${repo}/issues/${number})"; fi
    case "$kind" in
      unlabelled)
        reason="closed since ${tag}, no patch, minor or major label"
        action="label it patch, minor or major"
        ;;
      open-with-commits)
        reason="open, with commits on main since ${tag}"
        action="close it, or split it (close the landed part as its own issue, move the rest to a new one)"
        ;;
      needs-*)
        reason="needs ${kind#needs-}, the run asked for ${asked}"
        action="start Release with bump = ${kind#needs-}"
        ;;
      *)
        reason="the plan names it (${kind})"
        action="read the plan step"
        ;;
    esac
    rows="${rows}| ❌ | ${link} ${title} | ${reason} | ${action} |
"
    BLOCKED_NUMS="${BLOCKED_NUMS}${BLOCKED_NUMS:+, }#${number}"
    n_blocked=$((n_blocked + 1))
  done <<< "$(grep '^blocking=' "$file" || true)"
  [ "$n_blocked" -gt 0 ] || return 0
  BLOCKED_TABLE="|  | Issue | Blocks because | Do |
|---|---|---|---|
${rows%
}"
}
if [ "$failed_id" = plan ]; then blocking_table; fi

# ready_list: the issues a plan run with --all says are ready, from its
# `ready=<N> TAB <bump> TAB <title> TAB <tag>` lines; READY_LIST is empty when
# there are none. The same link rule as the table.
READY_LIST=""
ready_list() {
  local file="${RELEASE_PLAN_OUTPUT:-}" repo link number bump title tag
  [ -n "$file" ] && [ -f "$file" ] || return 0
  repo="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
  while IFS="$(printf '\t')" read -r number bump title tag; do
    number="${number#ready=}"
    [ -n "$number" ] || continue
    link="#${number}"
    if [ -n "$repo" ]; then link="[#${number}](${GITHUB_SERVER_URL:-https://github.com}/${repo}/issues/${number})"; fi
    READY_LIST="${READY_LIST}- ✅ ${link} ${title} (${bump})
"
  done <<< "$(grep '^ready=' "$file" || true)"
}

if [ "$TABLE_ONLY" -eq 1 ]; then
  blocking_table
  ready_list
  if [ -n "$BLOCKED_TABLE" ]; then printf '%s\n' "$BLOCKED_TABLE"; fi
  if [ -n "$READY_LIST" ]; then
    if [ -n "$BLOCKED_TABLE" ]; then echo; fi
    printf 'Ready for the release:\n%s' "$READY_LIST"
  fi
  COMPLETED=1
  exit 0
fi

# What to do next, by the stage the failure is in. ADVICE goes to the job
# summary, NOTICE (one line) to the run as a ::notice::. A step is never to be
# done by hand: the way on is always another Release run.
ADVICE=""
NOTICE=""
QUALITY_LINK="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-owner/forsgren}/actions/workflows/quality.yml"
advise() {
  local name bump version next
  name="$(name_of "$failed_id")"
  bump="${RELEASE_BUMP:-the same}"
  version="$(line_value '^publish: ' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
  if [ -z "$version" ]; then version="$(line_value '^resume: tag=' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"; fi
  case "$failed_id" in
    template | metrics-pr | metrics)
      ADVICE="${version:-This release} is released.
Next: fix the cause (for a 403: the token's Workflows permission), then start Release with resume = pins: gh workflow run release.yml -f resume=pins, or Actions → Release → Run workflow → resume: pins."
      NOTICE="Release failed at the step '${name}': ${version:-this release} is released. Fix the cause (for a 403: the token's Workflows permission), then start Release with resume = pins: gh workflow run release.yml -f resume=pins"
      ;;
    verify-install)
      ADVICE="${version:-This release} is released, but go install at its sha does not report it yet, so installations show the fallback version meanwhile.
Next: wait for the module proxy to know the tag, then start Release with resume = pins, which reruns the install check first: gh workflow run release.yml -f resume=pins, or Actions → Release → Run workflow → resume: pins. Do not move a pin by hand."
      NOTICE="Release failed at the step '${name}': ${version:-this release} is released, but installations show the fallback version until go install at its sha reports it. Start Release with resume = pins (it reruns the check): gh workflow run release.yml -f resume=pins. Do not move a pin by hand."
      ;;
    resume)
      ADVICE="Nothing was changed by this run.
Next: fix the cause and start the same resume again (resume = ${RELEASE_RESUME:-pins})."
      NOTICE="Release failed at the step '${name}': fix the cause and start the same resume again."
      ;;
    *)
      cause=""
      case "$failed_id" in
        token) cause="Cause: the secret FORSGREN_RELEASE_TOKEN is not set, empty, expired or without an expiry date (the first line of this summary says which); it is a fine-grained token with Contents, Pull requests and Workflows read and write on forsgren-template and forsgren-metrics." ;;
        plan)
          if [ -n "$BLOCKED_TABLE" ]; then
            cause="The plan stopped; these issues block the release:

${BLOCKED_TABLE}
"
          elif [ -n "${RELEASE_PLAN_OUTPUT:-}" ] && [ -f "$RELEASE_PLAN_OUTPUT" ] && grep -q 'nothing was closed since' "$RELEASE_PLAN_OUTPUT"; then
            cause="Cause: nothing was closed since the last release."
          else
            cause="Cause: label the issues the plan names patch, minor or major (or choose the bump it names, or nothing was closed since the last release), close or split every open issue it names that already has commits on main, and for a major give every agent file a proof run on the new major."
          fi
          ;;
        free) cause="Cause: that version already exists as a tag or a release; see the Releases page." ;;
        quality) cause="Cause: Quality is not green on main: ${QUALITY_LINK}" ;;
        head) cause="Cause: main has moved since the run began, so Quality was proved green on an older commit; nothing was tagged. The step log names both shas." ;;
        publish) cause="Cause: gh release create failed; if a tag v<version> exists without its release, delete that tag first (the step log says so)." ;;
      esac
      next="fix the cause and start Release again with the same bump (${bump})."
      if [ -n "$BLOCKED_TABLE" ]; then next="do what the table says, then start Release again (with the same bump unless a row says otherwise)."; fi
      ADVICE="Nothing was released and nothing was pushed to main.
${cause:+${cause}
}Next: ${next}"
      NOTICE="Release failed at the step '${name}': nothing was released. ${BLOCKED_NUMS:+Blocked by ${BLOCKED_NUMS}. }Fix the cause and start Release again with the same bump (${bump})."
      ;;
  esac
}
if [ "$STATUS" != success ] && [ -n "$failed_id" ]; then advise; fi

# The headline of a failed run is a workflow command in the log (::error::,
# an annotation) and the same sentence with a red ❌ in the job summary, where
# a workflow command is plain text. HEADLINE is empty on success.
HEADLINE=""
if [ "$STATUS" != success ]; then
  if [ -n "$failed_id" ]; then
    HEADLINE="The release run ended as ${STATUS} at the step '$(name_of "$failed_id")' (${failed_id})${BLOCKED_NUMS:+, blocked by ${BLOCKED_NUMS}}."
  elif [ -z "${RELEASE_STEP_OUTCOMES:-}" ]; then
    HEADLINE="The release run ended as ${STATUS}; the failed step is unknown (the step outcomes were not passed)."
  else
    HEADLINE="The release run ended as ${STATUS}; no step reports a failure (a step outside the list, or the run was stopped)."
  fi
fi
BODY=""
if [ "$STATUS" = success ]; then
  BODY="Release run finished. Done:
${DONE%
}"
else
  BODY="Already done:
${DONE:-- nothing
}"
  BODY="${BODY%
}
Not done: ${MISSING:-nothing}
A release pushes nothing to main, and a tag exists only together with its release."
  if [ -n "$ADVICE" ]; then
    BODY="${BODY}
What to do next:
${ADVICE}"
  fi
fi
if [ -n "$HEADLINE" ]; then
  printf '::error::%s\n%s\n' "$HEADLINE" "$BODY"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '❌ %s\n%s\n' "$HEADLINE" "$BODY" >> "$GITHUB_STEP_SUMMARY"; fi
else
  printf '%s\n' "$BODY"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n' "$BODY" >> "$GITHUB_STEP_SUMMARY"; fi
fi
if [ -n "$NOTICE" ]; then echo "::notice::${NOTICE}"; fi
COMPLETED=1
