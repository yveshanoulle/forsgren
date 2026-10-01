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
}

# ---------------------------------------------------------------------------
# Case 1: a run WITH a commit message must show it, labelled.
# ---------------------------------------------------------------------------
if run_fbp --no-commit "6.a: the message this run was given"; then
  grep -Fq "Commit:" <<< "$OUT" \
    || fail "the summary does not print a Commit: label — a block of statuses with no message is one of a dozen identical blocks in scrollback"

  grep -Fq "6.a: the message this run was given" <<< "$OUT" \
    || fail "the summary does not carry the message this run was given, so nothing ties a pasted summary to the commit it belongs to"
fi

# ---------------------------------------------------------------------------
# Case 2: a run given NO message must not print an empty label. Pins the
# `[ -n "$COMMIT_MSG" ]` guard around the block: an unconditional Commit:
# would still pass case 1 and fail here.
# ---------------------------------------------------------------------------
if run_fbp --no-commit; then
  grep -Fq "Commit:" <<< "$OUT" \
    && fail "a run given no message still printed the Commit: label — Commit: over a blank line reads as a message that failed to render, and --no-commit with no message is a legitimate run"
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
  # Wanted: the run fails; exactly 2 FAIL lines carry the reason, one for
  # each run_fbp call (cases 1 and 2); every other FAIL line names mktemp
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

  if [ "$callers_reasons" != "2" ]; then
    fail "callers check the run: with no sandbox, ${callers_reasons:-0} FAIL line(s) carry 'could not create the FBP sandbox', want 2 — one per run_fbp call (cases 1 and 2), so case 2's absence check cannot pass vacuously on empty output. Output: ${callers_out}"
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
  echo "FAIL: FullBuildAndPush does not show its commit message in the summary, or Scripts/lib_fbp_sandbox.sh carries on without a sandbox (see the FAIL lines above)"
  exit 1
fi

echo "OK: FullBuildAndPush summary shows the guarded Commit: block, and Scripts/lib_fbp_sandbox.sh stops when it cannot create a sandbox"
