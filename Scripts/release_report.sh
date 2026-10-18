#!/usr/bin/env bash
# Scripts/release_report.sh
#
# What a Release run did, for its last step (forsgren#221), which runs
# whatever happened. Two inputs:
#
#   - the log file: the steps that do work append one line each,
#     `<step id>: <what was done>`. The ids, in order: token, quality, plan,
#     free, bump, test, commit, quality-bump, quality-resumed, publish, template, metrics-pr,
#     metrics (the last one logs `PR #N merged, forsgren run <url> green`).
#   - the outcomes, in the environment variable RELEASE_STEP_OUTCOMES, one
#     `<step id>=<outcome>` line per step of the job (the workflow passes
#     steps.<id>.outcome of every step, the way the maintenance summary does).
#     The failed step is read from them, never inferred from the log: a step
#     that records nothing, or fails before it could, is still the one named.
#     The step ids, in order: main, checkout, setup-go, log, then the logged
#     ones above, with `resume` (Find the release to resume) after token. With
#     RELEASE_RESUME=pins (a resumed run) only token, resume, template and
#     metrics are expected.
#
#   - when the plan step failed, the plan's own output (RELEASE_PLAN_OUTPUT, a
#     file; the workflow tees the plan there): its `blocking=` machine lines
#     (forsgren#232) become a table `| Issue | Blocks because | Do |` in
#     "What to do next", and the ::error:: line names the issue numbers.
#
# Usage: Scripts/release_report.sh <log-file> <job-status>
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

ALL_IDS="main checkout setup-go log token resume quality plan free bump test commit quality-bump quality-resumed publish template metrics-pr metrics"
LOGGED_IDS="token quality plan free bump test commit quality-bump publish template metrics-pr metrics"
# A resumed run (RELEASE_RESUME=pins) skips everything between the token check and the pins.
if [ "${RELEASE_RESUME:-}" = pins ]; then LOGGED_IDS="token resume template metrics-pr metrics"; fi
if [ "${RELEASE_RESUME:-}" = publish ]; then LOGGED_IDS="token resume quality-resumed publish template metrics-pr metrics"; fi

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
    bump) echo "Bump the version in the working tree" ;;
    test) echo "Test the bumped tree" ;;
    commit) echo "Commit the bump and push it to main" ;;
    quality-bump) echo "Quality is green on the bump commit" ;;
    quality-resumed) echo "Quality is green on the resumed bump commit" ;;
    publish) echo "Create the tag and the release" ;;
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
    rows="${rows}| ${link} ${title} | ${reason} | ${action} |
"
    BLOCKED_NUMS="${BLOCKED_NUMS}${BLOCKED_NUMS:+, }#${number}"
    n_blocked=$((n_blocked + 1))
  done <<< "$(grep '^blocking=' "$file" || true)"
  [ "$n_blocked" -gt 0 ] || return 0
  BLOCKED_TABLE="| Issue | Blocks because | Do |
|---|---|---|
${rows%
}"
}
if [ "$failed_id" = plan ]; then blocking_table; fi

# What to do next, by the stage the failure is in. ADVICE goes to the job
# summary, NOTICE (one line) to the run as a ::notice::. A step is never to be
# done by hand: the way on is always another Release run.
ADVICE=""
NOTICE=""
QUALITY_LINK="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-owner/forsgren}/actions/workflows/quality.yml"
advise() {
  local name bump sha version next
  name="$(name_of "$failed_id")"
  bump="${RELEASE_BUMP:-the same}"
  sha="$(line_value '^(commit: sha=|resume: tag=.* at )' | sed -E 's/^commit: sha=([0-9a-f]+).*/\1/; s/^resume: tag=.* at ([0-9a-f]+).*/\1/')"
  version="$(line_value '^publish: ' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
  if [ -z "$version" ]; then version="$(line_value '^resume: tag=' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"; fi
  case "$failed_id" in
    template | metrics-pr | metrics)
      ADVICE="${version:-This release} is released.
Next: fix the cause (for a 403: the token's Workflows permission), then start Release with resume = pins: gh workflow run release.yml -f resume=pins, or Actions → Release → Run workflow → resume: pins."
      NOTICE="Release failed at the step '${name}': ${version:-this release} is released. Fix the cause (for a 403: the token's Workflows permission), then start Release with resume = pins: gh workflow run release.yml -f resume=pins"
      ;;
    quality-bump | quality-resumed | publish)
      ADVICE="The bump commit ${sha:-of this run} is on main and no release exists.
Do not start Release again with a bump: the version is already bumped and the bump step would refuse it.
resume = publish works only while main's head is still the bump commit; if main has moved on, fix main and run a new release instead.
Next: fix the cause (Quality: ${QUALITY_LINK}), then start Release with resume = publish: gh workflow run release.yml -f resume=publish, or Actions → Release → Run workflow → resume: publish."
      NOTICE="Release failed at the step '${name}': the bump commit is on main and no release exists. Fix the cause, then start Release with resume = publish: gh workflow run release.yml -f resume=publish"
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
${BLOCKED_TABLE}"
          elif [ -n "${RELEASE_PLAN_OUTPUT:-}" ] && [ -f "$RELEASE_PLAN_OUTPUT" ] && grep -q 'nothing was closed since' "$RELEASE_PLAN_OUTPUT"; then
            cause="Cause: nothing was closed since the last release."
          else
            cause="Cause: label the issues the plan names patch, minor or major (or choose the bump it names, or nothing was closed since the last release), and close or split every open issue it names that already has commits on main."
          fi
          ;;
        free) cause="Cause: that version already exists as a tag or a release; see the Releases page." ;;
        quality) cause="Cause: Quality is not green on main: ${QUALITY_LINK}" ;;
        bump | test) cause="Cause: the bump or the tests on the bumped tree failed; read the step log." ;;
        commit) cause="Cause: the commit or its push was refused (has main moved since the run began?)." ;;
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

{
  if [ "$STATUS" = success ]; then
    echo "Release run finished. Done:"
    printf '%s' "$DONE"
  else
    if [ -n "$failed_id" ]; then
      echo "::error::The release run ended as ${STATUS} at the step '$(name_of "$failed_id")' (${failed_id})${BLOCKED_NUMS:+, blocked by ${BLOCKED_NUMS}}."
    elif [ -z "${RELEASE_STEP_OUTCOMES:-}" ]; then
      echo "::error::The release run ended as ${STATUS}; the failed step is unknown (the step outcomes were not passed)."
    else
      echo "::error::The release run ended as ${STATUS}; no step reports a failure (a step outside the list, or the run was stopped)."
    fi
    echo "Already done:"
    if [ -n "$DONE" ]; then printf '%s' "$DONE"; else echo "- nothing"; fi
    echo "Not done: ${MISSING:-nothing}"
    echo "A bump commit that was pushed stays on main, a tag exists only together with its release."
    if [ -n "$ADVICE" ]; then
      echo "What to do next:"
      printf '%s\n' "$ADVICE"
    fi
  fi
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
if [ -n "$NOTICE" ]; then echo "::notice::${NOTICE}"; fi
COMPLETED=1
