#!/usr/bin/env bash
# Scripts/test_fbp_commit_message.sh
#
# Issue konenki-website#6: FullBuildAndPush's summary must show the commit message it was
# given — ported from web-infra's guarded `Commit:` block (its
# FBP.sh ~136-142, unit 428): a summary scrolled back to later
# must say which commit it belongs to, and on a TDD ladder every run prints
# an identical-looking block of statuses without it.
#
# Guarded, not unconditional: printing `Commit:` over a blank line would
# read as a message that failed to render, and --no-commit with no message
# is a legitimate run.
#
# Drives the REAL FBP.sh inside a throwaway git sandbox with
# stub sfl.sh / Scripts/build_site.sh / bin/say, the same technique
# web-infra's test_fullbuildandpush_sfl_counts.sh uses for its own unit 428
# cases, so this pins the CONTRACT rather than the source text. The sandbox
# is Scripts/lib_fbp_sandbox.sh (issue konenki-website#14), shared with
# Scripts/test_fbp_build_pagecount.sh.
#
# Issue konenki-website#20 (item 1): case 3 tests that sandbox itself. When mktemp -d
# cannot create the sandbox, fbp_sandbox_run must fail with a named reason
# and touch nothing in the directory it was called from. Under sfl that
# directory is the repo root, so a lib that carried on would overwrite the
# real sfl.sh and Scripts/build_site.sh with its stubs. Case 3 therefore
# calls it from a disposable fake repo, never from this one.
#
# Issue konenki-website#20 (items 1 to 3, step 3): the self-proofs at the end check this
# fixture and the lib from the outside — (a) run_fbp fails with the
# sandbox's own reason when there is no sandbox, (b) the fixture fails when
# it dies part-way, (c) a fixture whose own EXIT trap replaces the lib's
# still leaves no sandbox behind.
# Scripts/test_fbp_build_pagecount.sh carries (a) and (b) for
# its own run_case.
#
# forsgren#1 step 5: cases 1 and 2 also require that the run REACHED PRE
# (assert_reached_pre). Their own checks read only the Commit: block, which
# FBP.sh's EXIT trap prints even when the run stops before Step 1, so while
# every sandbox run aborted at the GOTOOLCHAIN export (no
# Scripts/go_toolchain.sh in the sandbox, fixed in b1f2453) this fixture
# stayed green without exercising anything. The mutation proof after case 2
# runs a FBP.sh that exits there and requires the reached-PRE reason.
#
# forsgren#1 step 12.2d: case 4 drives a secret-class PRE red and checks
# that the blocked-commit message names the row that failed (the data guard
# or the secret scan) instead of assuming gitleaks.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=Scripts/lib_fbp_sandbox.sh
source "${ROOT}/Scripts/lib_fbp_sandbox.sh"

failed=0
fail() { echo "❌ FAIL: $*"; failed=1; }

# Issue konenki-website#20 (item 3): the completion guard every guarded fixture here
# carries. A fixture that dies part-way must fail, never report green: on
# macOS bash 3.2 a set -u abort inside a function can exit 0. COMPLETED is
# set only after the last case. finish replaces the lib's EXIT trap, so it
# runs the lib's cleanup itself first (see Scripts/lib_fbp_sandbox.sh).
COMPLETED=0
finish() {
  fbp_sandbox_cleanup
  if [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: commit-message fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap finish EXIT

# run_fbp <extra args...> — runs the real FBP.sh with <extra
# args...> in a fresh sandbox (Scripts/lib_fbp_sandbox.sh) and leaves the
# captured stdout+stderr in $OUT. The stub build_site.sh writes a valid
# page-count sink (3): since issue konenki-website#8, FullBuildAndPush fails the build step
# when Scripts/build_site.sh leaves no count, and this file checks the
# summary of an otherwise green run, not a red one.
# Issue konenki-website#20 (item 1): when there is no sandbox it fails this fixture once,
# with the sandbox's own reason, and returns 1, so the case skips its
# assertions: case 2's absence check would otherwise pass on empty output.
run_fbp() {
  if ! fbp_sandbox_run 3 "$@"; then
    fail "run_fbp: ${FBP_SANDBOX_REASON}"
    return 1
  fi
  OUT="$(fbp_sandbox_output)"
  # The commit the run made, if any (case 5, road to public step 4).
  COMMIT_SHA="$(fbp_sandbox_commit_sha)"
  COMMIT_AUTHOR="$(fbp_sandbox_commit_author)"
  COMMIT_MSG="$(fbp_sandbox_commit_msg)"
}

# reached_pre_reason — prints why the last run_fbp's output shows no run
# that got past the GOTOOLCHAIN export into PRE; prints nothing when it does.
# forsgren#1 step 5. The marker is the summary's pre gates row: FBP.sh sets
# it to ⏭️ at start-up and changes it only after ./sfl.sh pre has returned,
# which comes after the GOTOOLCHAIN export, so a status other than ⏭️ there
# can only come from a run past that export. The Step 1/4: PRE gates banner
# is checked too, but it is NOT enough on its own: FBP.sh prints it BEFORE
# the export, so the run that aborted at go_toolchain.sh printed it as well.
reached_pre_reason() {
  local row
  if ! grep -Fq "Step 1/4: PRE gates" <<< "$OUT"; then
    echo "never reached PRE: the output has no 'Step 1/4: PRE gates' banner"
    return
  fi
  row="$(awk 'index($0, "  pre gates ") == 1 { print; exit }' <<< "$OUT")"
  case "$row" in
    "")
      echo "never reached PRE: the summary has no pre gates row"
      ;;
    *"⏭️"*)
      echo "never reached PRE: the summary's pre gates row is still ⏭️ ('${row}'), so ./sfl.sh pre never ran — the run stopped before PRE (at the GOTOOLCHAIN export, for one) and the Commit: block came from the EXIT trap alone"
      ;;
  esac
}

# assert_reached_pre <label> — fails the case with reached_pre_reason's
# reason when the last run_fbp did not get into PRE.
assert_reached_pre() {
  local reason
  reason="$(reached_pre_reason)"
  if [ -n "$reason" ]; then
    fail "$1: ${reason}. Output: ${OUT}"
  fi
}

# ---------------------------------------------------------------------------
# Case 1: a run WITH a commit message must show it, labelled.
# ---------------------------------------------------------------------------
if run_fbp --no-commit "6.a: the message this run was given"; then
  grep -Fq "Commit:" <<< "$OUT" \
    || fail "the summary does not print a Commit: label — a block of statuses with no message is one of a dozen identical blocks in scrollback"

  grep -Fq "6.a: the message this run was given" <<< "$OUT" \
    || fail "the summary does not carry the message this run was given, so nothing ties a pasted summary to the commit it belongs to"

  assert_reached_pre "commit message shown"
fi

# ---------------------------------------------------------------------------
# Case 2: a run given NO message must not print an empty label. Pins the
# `[ -n "$COMMIT_MSG" ]` guard around the block: an unconditional Commit:
# would still pass case 1 and fail here.
# ---------------------------------------------------------------------------
if run_fbp --no-commit; then
  grep -Fq "Commit:" <<< "$OUT" \
    && fail "a run given no message still printed the Commit: label — Commit: over a blank line reads as a message that failed to render, and --no-commit with no message is a legitimate run"

  # An absence check passes on any output that lacks the label, a run that
  # never started included, so this one most of all needs the run to be real.
  assert_reached_pre "no message, no label"
fi

# ---------------------------------------------------------------------------
# Mutation proof for the reached-PRE check (forsgren#1 step 5): runs case 1
# against a copy of FBP.sh with exit 1 inserted just before the
# GOTOOLCHAIN export, where the step-4 break stopped every sandbox run. It
# requires that run to fail the reached-PRE check with the pre gates row
# reason, the one the marker was chosen for (the banner is already printed
# there). It also requires that case 1's own Commit: checks still pass on
# that run, which is the gap the check closes: without it, case 1 is green
# on a run that never reached PRE.
#
# Guards: the insertion must change the copy (else the anchor stopped
# matching and this proves nothing), and the mutant must exit non-zero.
# The mutant is handed to Scripts/lib_fbp_sandbox.sh through
# FBP_SANDBOX_FBP_OVERRIDE as a prefix assignment on the one run_fbp call,
# as in Scripts/test_fbp_build_pagecount.sh; its directory comes from
# fbp_sandbox_new_dir, which registers it for the lib's cleanup.
# ---------------------------------------------------------------------------
if ! fbp_sandbox_new_dir; then
  fail "mutation proof (reached PRE): mktemp -d gave no directory, so the reached-PRE check was not seen failing"
else
  pre_mutant="${FBP_SANDBOX_NEW_DIR}/FBP.sh"
  awk '/^if ! GOTOOLCHAIN=/ && !done { print "exit 1"; done = 1 } { print }' "$FBP_SANDBOX_FBP" > "$pre_mutant"
  chmod +x "$pre_mutant"

  if cmp -s "$FBP_SANDBOX_FBP" "$pre_mutant"; then
    fail "mutation proof (reached PRE): inserting exit 1 before the GOTOOLCHAIN export changed nothing in ${FBP_SANDBOX_FBP} — the '^if ! GOTOOLCHAIN=' anchor no longer matches, so this proof proves nothing"
  elif FBP_SANDBOX_FBP_OVERRIDE="$pre_mutant" run_fbp --no-commit "6.a: the message this run was given"; then
    pre_mutant_rc="$(fbp_sandbox_rc)"
    pre_mutant_reason="$(reached_pre_reason)"
    if [ "$pre_mutant_rc" -eq 0 ]; then
      fail "mutation proof (reached PRE): a FBP.sh that exits before the GOTOOLCHAIN export exited 0 — the mutant did not stop where the step-4 break did. Output: ${OUT}"
    elif ! grep -Fq "Commit:" <<< "$OUT" || ! grep -Fq "6.a: the message this run was given" <<< "$OUT"; then
      fail "mutation proof (reached PRE): the run that stopped before PRE did not print the Commit: block — case 1's own checks would catch it, so this proof no longer shows the gap the reached-PRE check closes. Output: ${OUT}"
    else
      case "$pre_mutant_reason" in
        *"pre gates row is still ⏭️"*)
          echo "  ok: a FBP.sh that stops before the GOTOOLCHAIN export fails the reached-PRE check (pre gates row still ⏭️)"
          ;;
        "")
          fail "mutation proof (reached PRE): a FBP.sh that exits before the GOTOOLCHAIN export passed the reached-PRE check — case 1 would stay green on a run that never reached PRE. Output: ${OUT}"
          ;;
        *)
          fail "mutation proof (reached PRE): the run that stopped before PRE failed the reached-PRE check, but not with the pre gates row reason: ${pre_mutant_reason}"
          ;;
      esac
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Case 3: issue konenki-website#20 — a sandbox that cannot be created must stop the run.
# fbp_sandbox_run is called with a mktemp that fails, from inside a fake
# repo that stands in for the repo root sfl runs fixtures from. The wanted
# state: the call exits non-zero, names the reason ("could not create the
# FBP sandbox"), and the fake repo is exactly as it was: its sfl.sh and
# Scripts/build_site.sh byte-unchanged, no bin/say, no FBP.sh
# copied in, its .git/config unchanged.
#
# The failing mktemp is the lib's stub (fbp_sandbox_write_failing_mktemp),
# put first on PATH for this one call only. The fake repo, the stub and the
# saved copies live in one directory this case creates with the real mktemp
# BEFORE the stub goes on PATH, registered with the lib so its cleanup
# removes it.
#
# The call runs through fbp_sandbox_record, in a subshell that cds into the
# fake repo, so the stub PATH and any lib state the call changes stay inside
# it. If the cd fails nothing is called, so a broken setup can never make
# the lib run in this repo; the missing exit status then fails the case.
# With the lib as it was before issue konenki-website#20, the subshell does run
# FullBuildAndPush --no-commit, inside the fake repo.
# ---------------------------------------------------------------------------
if ! fbp_sandbox_new_dir; then
  fail "sandbox not created: mktemp -d gave no directory for the fake repo, so case 3 never ran"
else
  sandbox_case_dir="$FBP_SANDBOX_NEW_DIR"
  fake_repo="${sandbox_case_dir}/repo"
  mkdir -p "${fake_repo}/Scripts" "${sandbox_case_dir}/before"
  printf '#!/usr/bin/env bash\necho fake-repo sfl.sh marker\n' > "${fake_repo}/sfl.sh"
  printf '#!/usr/bin/env bash\necho fake-repo build_site.sh marker\n' > "${fake_repo}/Scripts/build_site.sh"
  git -C "$fake_repo" init -q
  cp "${fake_repo}/sfl.sh" "${sandbox_case_dir}/before/sfl.sh"
  cp "${fake_repo}/Scripts/build_site.sh" "${sandbox_case_dir}/before/build_site.sh"
  cp "${fake_repo}/.git/config" "${sandbox_case_dir}/before/git-config"
  fbp_sandbox_write_failing_mktemp "${sandbox_case_dir}/no-mktemp"

  PATH="${sandbox_case_dir}/no-mktemp:$PATH" fbp_sandbox_record "$sandbox_case_dir" "$fake_repo" \
    fbp_sandbox_run 3 --no-commit
  sandbox_rc="$(fbp_sandbox_record_rc)"
  sandbox_out="$(fbp_sandbox_record_output)"

  case "$sandbox_rc" in
    missing)
      fail "sandbox not created: the case never reached fbp_sandbox_run (no exit status recorded), so nothing was tested"
      ;;
    0)
      fail "sandbox not created: fbp_sandbox_run exited 0 when mktemp -d failed — with no sandbox it must stop, not carry on in the directory it was called from"
      ;;
  esac

  grep -Fq "could not create the FBP sandbox" <<< "$sandbox_out" \
    || fail "sandbox not created: fbp_sandbox_run did not name the reason 'could not create the FBP sandbox'. Output: ${sandbox_out}"

  cmp -s "${sandbox_case_dir}/before/sfl.sh" "${fake_repo}/sfl.sh" \
    || fail "sandbox not created: fbp_sandbox_run overwrote sfl.sh in the directory it was called from — under sfl that is the real repo's sfl.sh"
  cmp -s "${sandbox_case_dir}/before/build_site.sh" "${fake_repo}/Scripts/build_site.sh" \
    || fail "sandbox not created: fbp_sandbox_run overwrote Scripts/build_site.sh in the directory it was called from — under sfl that is the real repo's builder"
  [ -e "${fake_repo}/bin/say" ] \
    && fail "sandbox not created: fbp_sandbox_run created bin/say in the directory it was called from"
  [ -e "${fake_repo}/FBP.sh" ] \
    && fail "sandbox not created: fbp_sandbox_run copied FBP.sh into the directory it was called from — in the real repo that is a copy onto itself, then a run of it"
  cmp -s "${sandbox_case_dir}/before/git-config" "${fake_repo}/.git/config" \
    || fail "sandbox not created: fbp_sandbox_run changed .git/config in the directory it was called from — in the real repo that sets user.email and user.name in its own config"
fi

# ---------------------------------------------------------------------------
# Case 4: forsgren#1 step 12.2d — the blocked-commit message names the
# secret-class row that failed. Two rows are secret-class (the secret scan
# and, by Yves's ruling of 2026-10-02, the data guard), and FullBuildAndPush
# refuses to commit on either. Its message used to assume the secret scan
# ("Fix the gitleaks finding above, rotate the value..."), which is wrong
# advice for a data-guard finding: there is no gitleaks finding and no value
# to rotate.
#
# The stub sfl.sh fails PRE with exit 2 and sfl's own Errors: block naming
# the failed row (FBP_SANDBOX_SFL_PRE_RC/OUTPUT, Scripts/lib_fbp_sandbox.sh).
# The checks read only the blocked-commit message, from its
# "NOT committing" line to its "run FBP.sh again" line: the summary below it
# reprints sfl's Errors: block, so the whole output names the row anyway.
#   a. data guard failed  -> the message names the data guard, and does
#                            not mention gitleaks
#   b. secret scan failed -> the message still sends you to the gitleaks
#                            finding, and does not name the data guard
# ---------------------------------------------------------------------------

# blocked_message — prints the last run's blocked-commit message, from its
# "NOT committing" line to its "run FBP.sh again" line; nothing when the run
# printed none.
blocked_message() {
  awk '/NOT committing/ { on = 1 } on { print } on && /run FBP\.sh again/ { exit }' <<< "$OUT"
}

# run_secret_red <label> <fail-line> — runs FullBuildAndPush --no-commit
# with a PRE that fails secret-class (exit 2) on the row <label>, printing
# the Errors: block sfl prints, and leaves the message in $BLOCKED. Returns
# 1 when the run had no sandbox (run_fbp has failed the fixture already).
run_secret_red() {
  local errors
  errors="$(printf 'Errors:\n  %s ❌\n    %s\n' "$1" "$2")"
  FBP_SANDBOX_SFL_PRE_RC=2 FBP_SANDBOX_SFL_PRE_OUTPUT="${errors}"$'\n' \
    run_fbp --no-commit "12.2d: a secret-class red" || return 1
  BLOCKED="$(blocked_message)"
  if [ -z "$BLOCKED" ]; then
    fail "secret-class red on '$1': FullBuildAndPush printed no blocked-commit message (no 'NOT committing' line), so nothing here was checked. Output: ${OUT}"
    return 1
  fi
}

if run_secret_red "data guard" "❌ FAIL: events.jsonl — looks like installation config or data"; then
  if grep -Fqi "gitleaks" <<< "$BLOCKED"; then
    fail "data-guard red: the blocked-commit message mentions gitleaks, but the data guard failed, not the secret scan — there is no gitleaks finding to fix and no value to rotate. Message: ${BLOCKED}"
  else
    echo "  ok: a data-guard red's blocked-commit message does not mention gitleaks"
  fi
  if grep -Fq "data guard" <<< "$BLOCKED"; then
    echo "  ok: a data-guard red's blocked-commit message names the data guard"
  else
    fail "data-guard red: the blocked-commit message does not name the data guard, the row that blocked the commit. Message: ${BLOCKED}"
  fi
fi

if run_secret_red "secret scan" "❌ FAIL: gitleaks found a leak"; then
  if grep -Fq "gitleaks" <<< "$BLOCKED"; then
    echo "  ok: a secret-scan red's blocked-commit message sends you to the gitleaks finding"
  else
    fail "secret-scan red: the blocked-commit message no longer mentions the gitleaks finding to fix. Message: ${BLOCKED}"
  fi
  if grep -Fq "data guard" <<< "$BLOCKED"; then
    fail "secret-scan red: the blocked-commit message names the data guard, which did not fail. Message: ${BLOCKED}"
  fi
fi

# ---------------------------------------------------------------------------
# Case 5: road to public, step 4 — every commit FBP.sh makes carries a DCO
# sign-off (CONTRIBUTING.md; Yves, 2026-10-02: "we will change fbp to add
# Signed-off-by:"), the green commit and the *** RED **** one alike, so a
# commit FBP.sh made passes the pull-request DCO check unedited. git takes
# the trailer from the committer identity, so it signs as whoever runs it:
# Yves in his own runs, agent-Friend under Scripts/fbp_agent_friend.sh,
# which exports that identity as GIT_AUTHOR_* and GIT_COMMITTER_*.
#   a. a green run under a made-up identity handed over in the environment,
#      as fbp_agent_friend.sh hands over agent-Friend's -> its commit ends
#      in Signed-off-by: <that identity>
#   b. that commit, fed to Scripts/check_dco.sh as the DCO workflow feeds
#      it                                             -> green
#   c. a run with a PRE red, under the sandbox's own identity -> its
#      *** RED **** commit is signed off too
# These runs commit in the sandbox (no --no-commit); it has no remote, so
# the push after a green commit fails, and the cases read the commit, not
# the exit status. Mutation proof: a FBP.sh with --signoff removed must
# fail case a and case b, each with its own reason.
# ---------------------------------------------------------------------------
FRIEND_NAME="Friend Example"
FRIEND_EMAIL="friend@example.org"
FRIEND_SIGNOFF="Signed-off-by: ${FRIEND_NAME} <${FRIEND_EMAIL}>"

# dco_verdict — feeds the last sandbox commit to Scripts/check_dco.sh, in
# the line shape .github/workflows/dco.yml writes, and leaves its output in
# DCO_OUT and its status in DCO_RC. Returns 1 when it has no directory for
# the input (and has failed the fixture already).
dco_verdict() {
  local input
  if ! fbp_sandbox_new_dir; then
    fail "DCO verdict: mktemp -d gave no directory for the check's input"
    return 1
  fi
  input="${FBP_SANDBOX_NEW_DIR}/commits.txt"
  printf '%s - %s %s\n' "$COMMIT_SHA" \
    "$(printf '%s' "$COMMIT_AUTHOR" | base64 | tr -d '\n')" \
    "$(printf '%s' "$COMMIT_MSG" | base64 | tr -d '\n')" > "$input"
  DCO_RC=0
  DCO_OUT="$("${ROOT}/Scripts/check_dco.sh" "$input" 2>&1)" || DCO_RC=$?
}

# signed_off_case <label> <signoff-line> — case a or c on the last run: the
# run committed, and the commit message's last line is <signoff-line>.
signed_off_case() {
  if [ -z "$COMMIT_SHA" ]; then
    fail "$1: the run made no commit, so there is no sign-off to check. Output: ${OUT}"
  elif [ "$(tail -n 1 <<< "$COMMIT_MSG")" = "$2" ]; then
    echo "  ok: $1"
  else
    fail "$1: the commit does not end in '$2' — FBP.sh commits without a DCO sign-off, and the pull-request DCO check would reject it. Message: ${COMMIT_MSG}"
  fi
}

if FBP_SANDBOX_GIT_NAME="$FRIEND_NAME" FBP_SANDBOX_GIT_EMAIL="$FRIEND_EMAIL" \
    run_fbp "5.a: a green commit"; then
  signed_off_case "5.a. a green commit is signed off by the identity that ran FBP.sh" "$FRIEND_SIGNOFF"
  if [ -n "$COMMIT_SHA" ] && dco_verdict; then
    if [ "$DCO_RC" -eq 0 ] && grep -Fq "every one signed off" <<< "$DCO_OUT"; then
      echo "  ok: 5.b. the commit FBP.sh made passes the DCO check"
    else
      fail "5.b. the commit FBP.sh made fails the DCO check (exit ${DCO_RC}): ${DCO_OUT}"
    fi
  fi
fi

if FBP_SANDBOX_SFL_PRE_RC=1 FBP_SANDBOX_SFL_PRE_OUTPUT=$'Errors:\n  gofmt ❌\n' \
    run_fbp "5.c: a red commit"; then
  if [ "$(head -n 1 <<< "$COMMIT_MSG")" != "*** RED ****" ]; then
    fail "5.c. the PRE red did not make a *** RED **** commit, so its sign-off is not what is checked here. Message: ${COMMIT_MSG}. Output: ${OUT}"
  else
    signed_off_case "5.c. a *** RED **** commit is signed off too" "Signed-off-by: t <t@t.t>"
  fi
fi

if ! fbp_sandbox_new_dir; then
  fail "mutation proof (sign-off): mktemp -d gave no directory, so case 5 was not seen failing"
else
  signoff_mutant="${FBP_SANDBOX_NEW_DIR}/FBP.sh"
  sed 's/git commit --signoff /git commit /' "$FBP_SANDBOX_FBP" > "$signoff_mutant"
  chmod +x "$signoff_mutant"
  if cmp -s "$FBP_SANDBOX_FBP" "$signoff_mutant"; then
    fail "mutation proof (sign-off): removing --signoff changed nothing in ${FBP_SANDBOX_FBP} — FBP.sh has no 'git commit --signoff ' to remove, so this proof proves nothing"
  elif FBP_SANDBOX_FBP_OVERRIDE="$signoff_mutant" FBP_SANDBOX_GIT_NAME="$FRIEND_NAME" FBP_SANDBOX_GIT_EMAIL="$FRIEND_EMAIL" \
      run_fbp "5.a: a green commit"; then
    if [ -z "$COMMIT_SHA" ]; then
      fail "mutation proof (sign-off): the FBP.sh without --signoff made no commit, so nothing was seen failing. Output: ${OUT}"
    elif grep -Fq "Signed-off-by:" <<< "$COMMIT_MSG"; then
      fail "mutation proof (sign-off): a FBP.sh without --signoff still made a signed-off commit — the sign-off comes from somewhere else, so case 5 does not prove FBP.sh adds it. Message: ${COMMIT_MSG}"
    else
      echo "  ok: mutation proof: without --signoff, FBP.sh's commit carries no Signed-off-by, so case 5.a is green because FBP.sh signs off"
      if dco_verdict; then
        if [ "$DCO_RC" -ne 0 ] && grep -Fq "has no Signed-off-by trailer" <<< "$DCO_OUT"; then
          echo "  ok: mutation proof: the DCO check rejects that commit for its missing Signed-off-by trailer"
        else
          fail "mutation proof (sign-off): the DCO check did not reject the unsigned commit for its missing trailer (exit ${DCO_RC}): ${DCO_OUT}"
        fi
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Self-proofs, issue konenki-website#20 step 3 (items 1 to 3 of the #14 review). Each one
# runs this fixture, a copy of it, or a small driver, from inside ONE
# directory made here with the real mktemp and registered with the lib, so
# nothing they start runs in this repo.
#
# They cannot recurse. Proof (a) runs this file with a mktemp that always
# fails, so in that child the mktemp -d just below fails too and every proof
# is skipped (its fail line names mktemp, which proof (a) allows). Proof (b)
# runs a copy that exits before it reaches this block.
# ---------------------------------------------------------------------------
if ! fbp_sandbox_new_dir; then
  fail "self-proofs: mktemp -d gave no directory for the proofs, so the caller, completion-guard and trap-chaining proofs never ran"
else
  proof_dir="$FBP_SANDBOX_NEW_DIR"

  # -------------------------------------------------------------------------
  # Proof (a): callers check the run. When fbp_sandbox_run cannot create a
  # sandbox, run_fbp must fail this fixture with the sandbox's own reason
  # ("could not create the FBP sandbox"), once per run_fbp call, and no case
  # may go on to assert against the empty output that run left. Case 1 would
  # otherwise fail with a downstream message about the missing Commit: label,
  # and case 2's absence check would pass vacuously: no output holds no
  # Commit: label.
  #
  # Drives THIS file (not a copy) with the failing mktemp of case 3 first on
  # PATH, from an empty directory under proof_dir. The lib then stops
  # before its subshell (issue konenki-website#20 step 2), and even a lib that did not would
  # write its stubs into that empty directory, never into this repo.
  #
  # Wanted: the run fails; exactly 6 FAIL lines carry the reason, one for
  # each run_fbp call (cases 1 and 2, and case 4's two runs, forsgren#1 step
  # 12.2d, and case 5's two runs, road to public step 4, all of which skip
  # their checks on it); every other FAIL line names mktemp
  # itself (case 3's fake repo and these proofs cannot get a directory
  # either), so no downstream assertion fired. The lib's own stderr line is
  # not a FAIL line and does not count.
  # -------------------------------------------------------------------------
  callers_dir="${proof_dir}/callers"
  mkdir -p "${callers_dir}/cwd"
  fbp_sandbox_write_failing_mktemp "${callers_dir}/no-mktemp"

  PATH="${callers_dir}/no-mktemp:$PATH" fbp_sandbox_record "$callers_dir" "${callers_dir}/cwd" \
    "$BASH" "${ROOT}/Scripts/test_fbp_commit_message.sh"
  callers_rc="$(fbp_sandbox_record_rc)"
  callers_out="$(fbp_sandbox_record_output)"
  callers_fails="$(grep -F '❌ FAIL:' <<< "$callers_out" || true)"
  callers_reasons="$(grep -cF 'could not create the FBP sandbox' <<< "$callers_fails" || true)"
  callers_downstream="$(grep -vF 'could not create the FBP sandbox' <<< "$callers_fails" | grep -vF 'mktemp -d gave no directory' || true)"

  case "$callers_rc" in
    missing)
      fail "callers check the run: the no-sandbox run of this fixture recorded no exit status, so nothing was tested"
      ;;
    0)
      fail "callers check the run: with no sandbox this fixture exited 0 — a run that never happened must fail it. Output: ${callers_out}"
      ;;
  esac

  if [ "$callers_reasons" != "6" ]; then
    fail "callers check the run: with no sandbox, ${callers_reasons:-0} FAIL line(s) carry 'could not create the FBP sandbox', want 6 — one per run_fbp call (cases 1 and 2, case 4's two runs, case 5's two runs), so case 2's absence check cannot pass vacuously on empty output. Output: ${callers_out}"
  fi

  if [ -n "$callers_downstream" ]; then
    fail "callers check the run: with no sandbox, the fixture failed with downstream assertion message(s) instead of the sandbox's reason: ${callers_downstream}"
  fi

  # -------------------------------------------------------------------------
  # Proof (b): the completion guard. A fixture that dies part-way must fail,
  # never report green: on macOS bash 3.2 a set -u abort inside a function
  # can exit 0. Runs a COPY of this file that dies with status 0 after case
  # 1, the way that abort does, written under proof_dir/abort by
  # fbp_sandbox_write_aborting_copy (Scripts/lib_fbp_sandbox.sh).
  #
  # Three guards: the insertion must change the copy (else the Case 2 anchor
  # stopped matching and this proves nothing), the copy must exit non-zero,
  # and it must say why, with the wording every guarded fixture here uses.
  # -------------------------------------------------------------------------
  abort_root="${proof_dir}/abort"
  if ! fbp_sandbox_write_aborting_copy "${ROOT}/Scripts/test_fbp_commit_message.sh" "$abort_root"; then
    fail "completion guard: inserting exit 0 before case 2 changed nothing — the '# Case 2:' anchor no longer matches, so this proof proves nothing"
  else
    fbp_sandbox_record "$abort_root" "$abort_root" \
      "$BASH" "${abort_root}/Scripts/test_fbp_commit_message.sh"
    abort_rc="$(fbp_sandbox_record_rc)"
    abort_out="$(fbp_sandbox_record_output)"

    case "$abort_rc" in
      missing)
        fail "completion guard: the copy that dies after case 1 recorded no exit status, so nothing was tested"
        ;;
      0)
        fail "completion guard: a copy of this fixture that dies after case 1 exited 0 — a fixture that never reaches its later cases must fail, not report green. Output: ${abort_out}"
        ;;
    esac

    grep -Fq "fixture aborted before completing all cases" <<< "$abort_out" \
      || fail "completion guard: the copy that dies after case 1 did not say 'fixture aborted before completing all cases'. Output: ${abort_out}"
  fi

  # -------------------------------------------------------------------------
  # Proof (c): a replaced EXIT trap. A fixture that sets its own EXIT trap
  # AFTER sourcing the lib (as trap finish EXIT does) must still leave no
  # sandbox behind, and its own trap must still run. Nothing is chained,
  # whatever the fail lines below call it: the fixture's trap replaces the
  # lib's EXIT trap, and what removes the sandbox is fbp_sandbox_run itself
  # (issue konenki-website#20 step 4). A driver sources the lib, sets
  # trap 'echo own-trap-ran' EXIT, runs one sandbox, prints where it is and
  # exits without removing it. Not covered here: a directory the fixture
  # itself registered, which such a trap does lose (see the lib's header).
  #
  # The driver runs with a mktemp first on PATH that steers a bare mktemp -d
  # into proof_dir/chain/tmp and hands every other call (FullBuildAndPush's
  # mktemp -t) to the real one. A sandbox the cleanup misses is therefore
  # left inside proof_dir, which this fixture's own cleanup removes.
  #
  # Wanted: own-trap-ran printed, and the sandbox gone.
  # -------------------------------------------------------------------------
  chain_dir="${proof_dir}/chain"
  mkdir -p "${chain_dir}/bin" "${chain_dir}/tmp"
  chain_real_mktemp="$(printf '%q' "$(command -v mktemp)")"
  chain_template="$(printf '%q' "${chain_dir}/tmp/sandbox.XXXXXX")"
  cat > "${chain_dir}/bin/mktemp" <<STEERED
#!/usr/bin/env bash
if [ "\$#" -eq 1 ] && [ "\$1" = "-d" ]; then
  exec ${chain_real_mktemp} -d ${chain_template}
fi
exec ${chain_real_mktemp} "\$@"
STEERED
  chmod +x "${chain_dir}/bin/mktemp"

  cat > "${chain_dir}/driver.sh" <<'DRIVER'
#!/usr/bin/env bash
# Issue konenki-website#20 proof (c): a fixture that sets its own EXIT trap after sourcing
# the lib, runs one sandbox and exits without removing it.
set -uo pipefail
source "$1"
trap 'echo own-trap-ran' EXIT
fbp_sandbox_run 3 --no-commit
echo "sandbox=${FBP_SANDBOX_DIR}"
exit 0
DRIVER

  PATH="${chain_dir}/bin:$PATH" fbp_sandbox_record "$chain_dir" "$chain_dir" \
    "$BASH" "${chain_dir}/driver.sh" "${ROOT}/Scripts/lib_fbp_sandbox.sh"
  chain_out="$(fbp_sandbox_record_output)"
  chain_sandbox="$(sed -n 's/^sandbox=//p' <<< "$chain_out")"

  grep -qx "own-trap-ran" <<< "$chain_out" \
    || fail "trap chaining: the fixture's own EXIT trap, set after sourcing the lib, did not run. Output: ${chain_out}"

  case "$chain_sandbox" in
    "")
      fail "trap chaining: the driver never reported a sandbox, so the lib's cleanup was not tested. Output: ${chain_out}"
      ;;
    "${chain_dir}/tmp/"*)
      [ -e "$chain_sandbox" ] \
        && fail "trap chaining: a fixture that sets its own EXIT trap after sourcing the lib lost the lib's sandbox cleanup — the sandbox ${chain_sandbox} was left behind"
      ;;
    *)
      fail "trap chaining: the sandbox ${chain_sandbox} is not under ${chain_dir}/tmp — the steered mktemp was bypassed, so this proof cannot judge the cleanup. Output: ${chain_out}"
      ;;
  esac
fi

COMPLETED=1

if [ "$failed" -ne 0 ]; then
  echo ""
  echo "FAIL: FullBuildAndPush does not show its commit message in the summary, does not name the secret-class row that blocked the commit, does not sign off its commits, or Scripts/lib_fbp_sandbox.sh carries on without a sandbox (see the FAIL lines above)"
  exit 1
fi

echo "OK: FullBuildAndPush summary shows the guarded Commit: block, its blocked-commit message names the secret-class row that failed, its green and RED commits carry a DCO sign-off from the identity that ran it and pass the DCO check, and Scripts/lib_fbp_sandbox.sh stops when it cannot create a sandbox"
