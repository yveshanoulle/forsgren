#!/usr/bin/env bash
# FBP = FullBuildAndPush: runs sfl, commits, and pushes when everything is green.
#
# Ported from another estate repository's FullBuildAndPush.sh 2026-10-01 (forsgren#1,
# ladder step 1); named FBP.sh by Yves's ruling on forsgren#1. Issue numbers
# below are another estate repository's unless they say forsgren.
#
# Phases: gofmt -w (local auto-fix) -> sfl.sh pre -> Scripts/build_site.sh
# (the Go generator into .build/site) -> sfl.sh post -> git.

set -euo pipefail

# Anchored so `./forsgren/FBP.sh "msg"` works from ~/Sources, the same as
# another estate repository's and another estate repository's. The contract remains: quality gates run first,
# the commit ALWAYS happens on an ordinary red so work is never lost, and the
# push happens only when every phase is green.
cd "$(dirname "$0")"

NO_COMMIT=false
COMMIT_MSG=""
POSITIONAL=()

usage() {
  echo "Usage:"
  echo "  $0 \"<commit message>\"   run gates/build, then commit + push"
  echo "  $0 --no-commit           run gates/build only (skip commit + push)"
  echo "                           (flag aliases: -no-commit, --nocommit,"
  echo "                            -nocommit, /noCommit, /no-commit)"
  echo
  echo "On ordinary red the script continues where safe, then commits locally so"
  echo "WIP isn't lost, but skips the push. The subject becomes '*** RED ****'"
  echo "and your message moves to the body, so 'git log --oneline' shows the red"
  echo "state at a glance."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-commit|-no-commit|--nocommit|-nocommit|/noCommit|/no-commit)
      NO_COMMIT=true
      shift
      ;;
    -*|/*)
      echo "ERROR: unrecognised flag '$1'"
      echo "Did you mean --no-commit?"
      echo "(Commit messages cannot start with '-' or '/' — quote your message if needed.)"
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# :- guard: on bash 3.2 (macOS system bash) expanding an empty array under
# `set -u` is an unbound-variable error, which broke --no-commit in another estate repository.
COMMIT_MSG="${POSITIONAL[*]:-}"

if [ -z "$COMMIT_MSG" ] && ! $NO_COMMIT; then
  usage
  exit 1
fi

# Bump FBP_VERSION on every meaningful change to THIS file. The banner
# below is how you confirm which script you actually ran - it names the
# repo because two FBP runs back to back were otherwise
# indistinguishable from their first line (Yves, 2026-08-31). Mirrors
# sfl.sh's banner; editing a Scripts/*.sh does not require a bump.
FBP_VERSION=2

STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
START_EPOCH="$(date +%s)"

PRE_STATUS="⏭️"
BUILD_STATUS="⏭️"
POST_STATUS="⏭️"
GIT_STATUS="⏭️"

PRE_DURATION=0
BUILD_DURATION=0
POST_DURATION=0
GIT_DURATION=0

# The sink sfl.sh writes its gate-count sentence to (sfl.sh's own
# SFL_COUNTS_FILE), read once after PRE and once after POST.
SFL_COUNTS_FILE=".build/sfl-counts.log"
PRE_COUNTS=""
POST_COUNTS=""
# Issue #8: default tail for the build-site row, same shape as PRE/POST
# before their own counts arrive. Overwritten with "<N> pages generated
# (<duration>s)" once build_site.sh's page count is confirmed good.
BUILD_TAIL="(${BUILD_DURATION}s)"

FAILED=false
SECRET_BLOCK=false

# PRE and POST use separate logs so the final summary can repeat every quality
# failure rather than allowing the second sfl phase to overwrite the first.
PRE_LOG="$(mktemp -t forsgren_sfl_pre)"
POST_LOG="$(mktemp -t forsgren_sfl_post)"

print_log_errors() {
  local label="$1"
  local log_file="$2"

  if [ ! -s "$log_file" ]; then
    return
  fi

  if ! grep -qE '^(Errors:|⛔)' "$log_file"; then
    return
  fi

  echo
  echo "${label}:"
  sed -n '/^Errors:/,$p' "$log_file"
}

# secret_class_hints <pre-log> — prints what to do about each secret-class
# row that failed in PRE (forsgren#1 step 12.2d). The secret-class rows are
# the secret scan, the data guard and the private names gate (Yves's ruling,
# 2026-10-02), and the fix differs: a gitleaks finding whose value may need
# rotating, a file that belongs outside this repository, or a private name
# to replace with a made-up one. The failed
# rows come from sfl's own Errors: block in <pre-log> (`  <label> ❌`), so
# this names what sfl reported rather than guessing. A failed row with no
# hint of its own (an ordinary one, or a future secret-class row) prints
# nothing; when no secret-class row is found the last line points at the
# FAIL lines above.
secret_class_hints() {
  local label hinted=false
  while IFS= read -r label; do
    case "$label" in
      "secret scan")
        echo "   secret scan: fix the gitleaks finding above, and rotate the value if it"
        echo "   ever reached a remote."
        hinted=true
        ;;
      "data guard")
        echo "   data guard: its FAIL line above names the file. Move installation config"
        echo "   or data to the installation's private data repository (or under testdata/"
        echo "   if it is a made-up fixture)."
        hinted=true
        ;;
      "private names")
        echo "   private names: the FAIL line above names the file and line (or tracked path #N)."
        echo "   Replace the name with a made-up one such as acme (see Scripts/check_private_names.sh)."
        echo "   If the private-names list itself changed, run Scripts/sync_private_names_secrets.sh."
        hinted=true
        ;;
    esac
  done < <(sed -n '/^Errors:/,$p' "$1" 2>/dev/null | sed -n 's/^  \(.*\) ❌$/\1/p')
  if ! $hinted; then
    echo "   Fix the finding named in the FAIL lines above."
  fi
}

# sfl_counts — prints the sentence the sfl.sh phase that just ran wrote to
# SFL_COUNTS_FILE; nothing when it wrote none. Unlike the page-count read,
# a sink that is there but cannot be read fails cat, and the assignment
# that called sfl_counts then ends the run under set -e (issue #17 review).
sfl_counts() {
  if [ -s "$SFL_COUNTS_FILE" ]; then
    cat "$SFL_COUNTS_FILE"
  fi
}

# gate_row_tail <counts> <duration> — prints the tail of a pre-gates or
# post-gates summary row: <counts>, the sentence sfl.sh wrote to
# .build/sfl-counts.log, or (<duration>s) when that phase left none. Issue
# #17: a value holding a control character (a newline included) prints
# through printf %q, the escaping the build-site row gives a bad page count
# (issue #12), so the row stays one line and a carriage return or an escape
# sequence cannot rewrite it. Any other value prints as written, so the
# ordinary sentence render_step_table.sh writes, such as 34 passed, 0
# failed, 0 skipped (12s), stays readable instead of turning into
# 34\ passed,\ ... (decision logged on issue #17). A byte that is not valid
# UTF-8 and not a control character in the current locale (0xff, for one)
# also prints as written; the row still stays one line (issue #17, item 5,
# kept as a note).
gate_row_tail() {
  local counts="$1"
  local duration="$2"
  case "$counts" in
    '')
      printf '(%ss)' "$duration"
      ;;
    *[[:cntrl:]]*)
      printf '%q' "$counts"
      ;;
    *)
      printf '%s' "$counts"
      ;;
  esac
}

# build_fails_with <reason> — the build step fails with <reason> named in
# its summary row, and POST is skipped as for any failed build.
build_fails_with() {
  BUILD_STATUS="❌ ($1)"
  BUILD_EXIT=1
}

# holds_nul_byte <file> — succeeds when <file> holds a NUL byte: its byte
# count drops once tr deletes every NUL. Under a UTF-8 locale macOS tr stops
# with Illegal byte sequence at a byte that is not valid UTF-8, so a file
# holding such a byte and no NUL succeeds here too (issue #17 review).
holds_nul_byte() {
  [ "$(( $(wc -c < "$1") ))" -ne "$(( $(tr -d '\000' < "$1" | wc -c) ))" ]
}

print_summary() {
  local exit_code=$?
  local finished_at elapsed
  local pre_tail post_tail

  finished_at="$(date '+%Y-%m-%d %H:%M:%S')"
  elapsed="$(( $(date +%s) - START_EPOCH ))"

  pre_tail="$(gate_row_tail "$PRE_COUNTS" "$PRE_DURATION")"
  post_tail="$(gate_row_tail "$POST_COUNTS" "$POST_DURATION")"

  echo
  echo "================================"
  echo "  forsgren Summary"
  echo "================================"
  # Issue #6, ported from another estate repository's FullBuildAndPush.sh (~136-142, unit
  # 428): the message this run was given, first. A summary scrolled back to
  # later must say which commit it belongs to, and on a TDD ladder every run
  # prints an identical-looking block of statuses without it.
  #
  # Guarded, not unconditional: `Commit:` over a blank line reads as a
  # message that failed to render, and --no-commit with no message is a
  # legitimate run.
  if [ -n "$COMMIT_MSG" ]; then
    echo "Commit:"
    echo "\"$COMMIT_MSG\""
    echo "================================"
  fi
  printf "  %-16s %s  %s\n" "pre gates" "$PRE_STATUS" "$pre_tail"
  printf "  %-16s %s  %s\n" "build site" "$BUILD_STATUS" "$BUILD_TAIL"
  printf "  %-16s %s  %s\n" "post gates" "$POST_STATUS" "$post_tail"
  printf "  %-16s %s  (%ss)\n" "git" "$GIT_STATUS" "$GIT_DURATION"

  # The reasons, not just the glyphs. Reprint sfl's own failure blocks rather
  # than recomputing them so the summary cannot disagree with either phase.
  print_log_errors "PRE gate failures" "$PRE_LOG"
  print_log_errors "POST gate failures" "$POST_LOG"

  rm -f "$PRE_LOG" "$POST_LOG"

  echo

  if [ "$exit_code" -eq 0 ]; then
    echo "All checks passed ✅"
  else
    echo "Aborted ❌ (exit $exit_code)"
  fi

  echo "Started:  ${STARTED_AT}"
  echo "Finished: ${finished_at}  (${elapsed}s total)"
  command -v say >/dev/null 2>&1 && say "done" || true
}

trap print_summary EXIT

echo "forsgren FBP.sh v${FBP_VERSION} — Started at ${STARTED_AT}"
echo

echo "================================"
echo "  Step 1/4: PRE gates"
echo "================================"

PRE_START="$(date +%s)"

# Pin Go exactly, from go.mod's toolchain line (see Scripts/go_toolchain.sh).
# sfl.sh exports the same value for its gates, but the gofmt run below and
# build_site.sh between the phases run outside sfl, so FBP exports it too.
if ! GOTOOLCHAIN="$(./Scripts/go_toolchain.sh)"; then
  exit 1
fi
export GOTOOLCHAIN

# gofmt: AUTO-FIX here, CHECK-ONLY everywhere else (Yves's ruling on
# forsgren#1). FBP is the local run, so it rewrites the formatting before the
# gates look; sfl.sh's `gofmt` row (Scripts/check_gofmt.sh without --fix) is
# the check CI will call, and it then sees the fixed tree. A file gofmt cannot
# parse is not fatal here: the check-only row fails on it with the reason.
if ! ./Scripts/check_gofmt.sh --fix; then
  echo "⚠️ gofmt -w could not fix every file — the gofmt gate below says why."
fi

# Remove a previous run's sink before starting this phase. Otherwise an sfl
# failure before rendering could make PRE inherit stale counts from an earlier
# invocation.
rm -f "$SFL_COUNTS_FILE"

# Local pre-flight (forsgren#52): when no private-names list is given, create
# an empty one so a contributor without the list can run FBP; the gate then
# passes with 0 names searched. CI never runs FBP.sh, so CI stays strict.
./Scripts/ensure_private_names_file.sh

# Capture the exit code without tripping `set -e`. An ordinary PRE red does NOT
# stop the pipeline: build and POST still run so one invocation collects all
# failures before preserving the red state in a local commit.
set +e
./sfl.sh pre 2>&1 | tee "$PRE_LOG"
PRE_EXIT=${PIPESTATUS[0]}
set -e

PRE_DURATION="$(($(date +%s) - PRE_START))"

PRE_COUNTS="$(sfl_counts)"

# sfl exit codes:
#   0 = green
#   1 = ordinary quality red
#   2 = secret-class red
#   3 = the opening pull could not fast-forward; sfl ran no gate. Not handled
#       specially here (yet): it reads as an ordinary red below.
#
# An ordinary red continues through build and POST. A secret-class red is
# different: nothing derived from that tree should be generated or committed.
if [ "$PRE_EXIT" -eq 0 ]; then
  PRE_STATUS="✅"
elif [ "$PRE_EXIT" -eq 2 ]; then
  PRE_STATUS="⛔ (secret-class)"
  FAILED=true
  SECRET_BLOCK=true
else
  PRE_STATUS="❌"
  FAILED=true
fi

echo
echo "================================"
echo "  Step 2/4: build site"
echo "================================"

if $SECRET_BLOCK; then
  echo "⏭️ Skipping build because PRE has a secret-class failure."
  BUILD_STATUS="⏭️ (secret-class)"
else
  BUILD_START="$(date +%s)"

  # Issue #8: removed before the build so a stale count from an earlier run
  # cannot be read as this run's — same reason PRE/POST truncate
  # .build/sfl-counts.log before their own phase (Step 1/4, Step 3/4 below).
  # Issue #11: build_site.sh writes its sink wherever SITE_PAGE_COUNT_FILE
  # says (default .build/site-page-count.log). Passed explicitly so a value
  # exported in the calling shell cannot send the count somewhere this step
  # does not read.
  PAGE_COUNT_FILE=".build/site-page-count.log"
  rm -f "$PAGE_COUNT_FILE"

  set +e
  SITE_PAGE_COUNT_FILE="$PAGE_COUNT_FILE" ./Scripts/build_site.sh
  BUILD_EXIT=$?
  set -e

  BUILD_DURATION="$(($(date +%s) - BUILD_START))"
  BUILD_TAIL="(${BUILD_DURATION}s)"

  # Issue #8, ruled fail fast (Yves, 2026-09-30): a missing, non-numeric or
  # zero page count is a BUILD FAILURE with a named reason, never a
  # fallback to the plain row. build_site.sh only writes this sink on its
  # fully successful path (Scripts/build_site.sh, after the render and its
  # page count), so a green BUILD_EXIT with no trustworthy count means
  # the builder's own accounting broke, not that nothing is known.
  # Issue #12: zero is any all-zero count (0, 00, 000 ...), not only a
  # literal 0, because the reader does not trust the writer's spelling of
  # zero. The zero label prints 0 rather than the raw value, and the ok
  # branch needs a non-zero digit, so 00 never shows as a page count. A
  # non-zero count still shows as written (007 stays 007).
  # Issue #12: the not-numeric label shows the value through printf %q, so a
  # newline or other control character in the sink prints escaped ($'3\n4')
  # and the build-site summary row stays one line; a plain word (abc) prints
  # unchanged. %q does not shorten a long value, and bash 3.2 passes a byte
  # that is not valid UTF-8 through unescaped unless the locale counts it as
  # a control character (0xff prints raw; under UTF-8, 0x9b prints as \233).
  # Issue #17: three more sinks get named reasons. A sink that is there but
  # cannot be read is "page count unreadable", with PAGE_COUNT_FILE's
  # relative path: the read runs as an if condition, so a failing cat names
  # the reason in the build-site row (cat prints its own error above it)
  # instead of aborting the run under set -e. A sink holding a NUL byte is
  # "page count not numeric: holds a NUL byte": $(cat) drops a NUL, so
  # holds_nul_byte reads the file itself, never the value read. A sink
  # holding only newlines reads as empty once $(cat) strips them, so it
  # holds no count and is "page count missing", like a sink that is not
  # there.
  if [ "$BUILD_EXIT" -ne 0 ]; then
    BUILD_STATUS="❌"
  elif [ ! -s "$PAGE_COUNT_FILE" ]; then
    build_fails_with "page count missing"
  elif ! PAGE_COUNT="$(cat "$PAGE_COUNT_FILE")"; then
    build_fails_with "page count unreadable: ${PAGE_COUNT_FILE}"
  elif holds_nul_byte "$PAGE_COUNT_FILE"; then
    build_fails_with "page count not numeric: holds a NUL byte"
  else
    case "$PAGE_COUNT" in
      '')
        build_fails_with "page count missing"
        ;;
      *[!0-9]*)
        printf -v PAGE_COUNT_SHOWN '%q' "$PAGE_COUNT"
        build_fails_with "page count not numeric: ${PAGE_COUNT_SHOWN}"
        ;;
      *[!0]*)
        BUILD_STATUS="✅"
        BUILD_TAIL="${PAGE_COUNT} pages generated (${BUILD_DURATION}s)"
        ;;
      *)
        build_fails_with "0 pages generated"
        ;;
    esac
  fi

  if [ "$BUILD_EXIT" -ne 0 ]; then
    FAILED=true
  fi
fi

echo
echo "================================"
echo "  Step 3/4: POST gates"
echo "================================"

if $SECRET_BLOCK; then
  echo "⏭️ Skipping POST gates because PRE has a secret-class failure."
  POST_STATUS="⏭️ (secret-class)"
elif [ "${BUILD_EXIT:-1}" -ne 0 ]; then
  echo "⏭️ Skipping POST gates because the site build failed."
  POST_STATUS="⏭️ (build failed)"
else
  POST_START="$(date +%s)"

  # PRE_COUNTS is already copied into memory. Remove its sink before POST so a
  # POST failure before rendering cannot accidentally reuse PRE's sentence.
  rm -f "$SFL_COUNTS_FILE"

  set +e
  ./sfl.sh post 2>&1 | tee "$POST_LOG"
  POST_EXIT=${PIPESTATUS[0]}
  set -e

  POST_DURATION="$(($(date +%s) - POST_START))"

  POST_COUNTS="$(sfl_counts)"

  if [ "$POST_EXIT" -eq 0 ]; then
    POST_STATUS="✅"
  elif [ "$POST_EXIT" -eq 2 ]; then
    POST_STATUS="⛔ (secret-class)"
    FAILED=true
    SECRET_BLOCK=true
  else
    POST_STATUS="❌"
    FAILED=true
  fi
fi

echo
echo "================================"
echo "  Step 4/4: git add / commit / push"
echo "================================"

# Nothing is staged or committed on a secret-class red. Fix the finding and
# re-run — do not commit and clean up afterwards, because by then what the
# gate guards (a secret, an installation's data, a private name) would
# already be in git history.
if $SECRET_BLOCK; then
  echo
  echo "⛔ SECRET-CLASS failure — NOT committing (what a secret-class gate guards must not enter git history)."
  secret_class_hints "$PRE_LOG"
  echo "   Then run FBP.sh again."
  GIT_STATUS="⛔ (secret-class red — commit blocked)"
else
  GIT_START="$(date +%s)"

  if $NO_COMMIT; then
    echo "--no-commit set — skipping git add / commit / push."
    GIT_STATUS="⏭️ (no-commit)"
  else
    git add -A
    COMMIT_DONE=false

    if git diff --cached --quiet; then
      echo "Nothing new to commit."
    else
      git status --short

      # Every commit is signed off (road to public, step 4): forsgren takes
      # contributions under the Developer Certificate of Origin
      # (CONTRIBUTING.md), and the DCO check on pull requests
      # (Scripts/check_dco.sh) wants a Signed-off-by trailer from the author.
      # git writes it from the committer identity: whoever runs FBP.sh, or
      # agent-Friend under Scripts/fbp_agent_friend.sh. The RED commit too,
      # since it is pushed later, under its green successor.
      # Scripts/test_fbp_commit_message.sh, case 5, pins both.
      if $FAILED; then
        git commit --signoff -m "*** RED ****" -m "$COMMIT_MSG"
      else
        git commit --signoff -m "$COMMIT_MSG"
      fi

      COMMIT_DONE=true
    fi

    PUSH_DONE=false

    if $FAILED; then
      echo "Earlier step failed — skipping push (commit preserved locally)."
    elif UPSTREAM=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null); then
      AHEAD=$(git rev-list --count "@{u}..HEAD")

      if [ "$AHEAD" -gt 0 ]; then
        echo "Pushing ${AHEAD} commit(s) to ${UPSTREAM}..."
        git push
        PUSH_DONE=true
      else
        echo "Nothing to push — branch is up to date with ${UPSTREAM}."
      fi
    else
      echo "No upstream configured — running git push (will set upstream if needed)..."
      git push
      PUSH_DONE=true
    fi

    if $FAILED && $COMMIT_DONE; then
      GIT_STATUS="⚠️ (committed locally, push skipped — earlier ❌)"
    elif $FAILED; then
      GIT_STATUS="➖ (nothing to commit; push skipped — earlier ❌)"
    elif $COMMIT_DONE && $PUSH_DONE; then
      GIT_STATUS="✅"
    elif $PUSH_DONE; then
      GIT_STATUS="✅ (pushed existing commits)"
    elif $COMMIT_DONE; then
      GIT_STATUS="✅ (committed, nothing to push)"
    else
      GIT_STATUS="➖ (nothing to commit or push)"
    fi
  fi

  GIT_DURATION="$(($(date +%s) - GIT_START))"
fi

if $FAILED; then
  exit 1
fi
