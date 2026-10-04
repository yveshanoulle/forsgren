#!/usr/bin/env bash
# Scripts/lib_fbp_sandbox.sh
#
# Ported from another estate repository 2026-10-01 (forsgren#1, ladder step 1). Every
# issue number in this file is another estate repository's: the history of why each
# piece exists lives there. forsgren's own changes: the copied script is
# FBP.sh (Yves's ruling on forsgren#1), and the sandbox also stubs
# Scripts/check_gofmt.sh, which FBP.sh runs with --fix before PRE.
#
# Issue source-repo#14, ruled option A (Yves, 2026-09-30): the throwaway sandbox that
# both FBP fixtures drive the REAL FBP.sh in —
# Scripts/test_fbp_commit_message.sh (issue source-repo#6) and
# Scripts/test_fbp_build_pagecount.sh (issues source-repo#8, #12 and
# #17).
# Each fixture used to build its own copy of the same setup; this is that
# setup, once.
#
# SOURCED, never run. It judges nothing on its own: the two fixtures that
# source it are what test it.
#
# It sets no shell options; the sourcing fixture owns those. It DOES set
# EXIT, INT and TERM traps (fbp_sandbox_cleanup below), so a fixture that
# sources it must not set its own traps for those signals without calling
# fbp_sandbox_cleanup from them.
#
# Issue source-repo#20 (item 2): a fixture that sets its own EXIT trap anyway, and never
# calls fbp_sandbox_cleanup, still leaves no sandbox behind. bash keeps one
# EXIT trap, so a later trap ... EXIT replaces the lib's and there is nothing
# to chain onto; instead no sandbox outlives the fbp_sandbox_run that made it
# (see there) once that call returns, and one it never returns from because
# INT or TERM arrived is removed by the lib's INT or TERM trap, which such a
# fixture has left in place. The EXIT trap is then only the backstop for
# directories made with fbp_sandbox_new_dir or registered with
# fbp_sandbox_register_dir, and those are what a replaced EXIT trap that does
# not call fbp_sandbox_cleanup loses: they stay in the temp directory, and no
# test notices (both fixtures' finish calls fbp_sandbox_cleanup, and nothing
# checks that it does).
#
# A sandbox is a fresh git repository holding:
#   - a stub sfl.sh that exits 0, so PRE and POST gates pass without running,
#     and writes no .build/sfl-counts.log unless the caller asks for one,
#     nor fails PRE unless the caller asks for that (fbp_sandbox_write_sfl
#     below);
#   - a stub Scripts/build_site.sh whose page-count sink the caller chooses
#     (fbp_sandbox_run below);
#   - a stub Scripts/check_gofmt.sh that exits 0, so FBP.sh's local gofmt
#     auto-fix has nothing to rewrite;
#   - a stub Scripts/ensure_private_names_file.sh that exits 0, so a sandbox
#     run never creates a private-names list in the real HOME (forsgren#52);
#   - a copy of the REAL Scripts/check_private_names.sh and
#     Scripts/lib_private_names.sh: FBP.sh refuses a commit message that names
#     a private name through the gate's --message mode (forsgren#52), and the
#     sandbox pins that with the real matcher, not a stub;
#   - its own HOME, the empty directory .git/fbp-sandbox-home (inside .git, so
#     git add -A never stages it), exported for the FBP.sh run: the real gate
#     falls back to ${HOME}/.config/forsgren/private-names, and with the real
#     HOME a run would read the machine's own list, so a run's result would
#     depend on the machine. With the sandbox HOME there is no list file
#     unless the caller sets FORSGREN_PRIVATE_NAMES or
#     FORSGREN_PRIVATE_NAMES_FILE, which still win, so every machine sees the
#     same list. Nothing else needs the real HOME: the git identity is the
#     sandbox's own (local config and the GIT_* variables below) and signing
#     is off, so the run needs nothing from a global git config (git looks
#     for one in the sandbox HOME and finds none);
#   - a stub bin/say that exits 0, put first on PATH, so a run is silent;
#   - a copy of the REAL Scripts/go_toolchain.sh and of the repo's go.mod
#     (forsgren#1 step 4): FBP.sh exports GOTOOLCHAIN from them before PRE
#     and stops when it cannot, so a sandbox without them aborts every run
#     before Step 1. They are the real reader and the real toolchain line,
#     not a stub that echoes a constant, so the sandbox exercises the read;
#   - a copy of the real FBP.sh (or, for the mutation proof
#     only, of FBP_SANDBOX_FBP_OVERRIDE), run with the caller's arguments,
#     under the sandbox's own git identity and with commit signing off (see
#     FBP_SANDBOX_GIT_NAME below). A run that commits (no --no-commit) has
#     no remote: its push fails after the commit, and the caller reads the
#     commit (FBP_SANDBOX_COMMIT_MSG below).

FBP_SANDBOX_FBP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/FBP.sh"

# forsgren#1 step 4: the real Go toolchain reader and the go.mod it reads,
# copied into every sandbox beside FBP.sh (see the header). Both are derived
# from FBP_SANDBOX_FBP's directory, the repo root.
FBP_SANDBOX_PRIVATE_NAMES_GATE="$(dirname "$FBP_SANDBOX_FBP")/Scripts/check_private_names.sh"
FBP_SANDBOX_PRIVATE_NAMES_LIB="$(dirname "$FBP_SANDBOX_FBP")/Scripts/lib_private_names.sh"
FBP_SANDBOX_GO_TOOLCHAIN="$(dirname "$FBP_SANDBOX_FBP")/Scripts/go_toolchain.sh"
FBP_SANDBOX_GO_MOD="$(dirname "$FBP_SANDBOX_FBP")/go.mod"

# Issue source-repo#14 (mutation proof): when non-empty, fbp_sandbox_run copies this
# file into the sandbox instead of FBP_SANDBOX_FBP. It exists ONLY so the
# mutation proof in Scripts/test_fbp_build_pagecount.sh can run
# its case 7 against a mutated copy of FBP.sh; that proof sets
# it as a prefix assignment on one call, so bash restores it when the call
# returns. It is reset here, at source time, so a value exported in the
# calling shell can never swap the FullBuildAndPush that every other case
# drives.
FBP_SANDBOX_FBP_OVERRIDE=""

# Issue source-repo#17: four more seams, for cases 8 to 12 of
# Scripts/test_fbp_build_pagecount.sh. Each is read by the
# stubs below only when non-empty, so a caller that sets none of them gets
# the same stubs, byte for byte, as before issue source-repo#17. Each is meant to be
# set as a prefix assignment on one call, like FBP_SANDBOX_FBP_OVERRIDE, and
# each is reset here at source time for the same reason.
#   FBP_SANDBOX_SFL_COUNTS_PRE, FBP_SANDBOX_SFL_COUNTS_POST: the stub sfl.sh
#     writes this value plus one trailing newline to .build/sfl-counts.log
#     when it runs as sfl.sh pre (or post), the sink the real sfl.sh fills
#     with its gate counts. See fbp_sandbox_write_sfl.
#   FBP_SANDBOX_SINK_PRINTF: a printf FORMAT the stub Scripts/build_site.sh
#     writes to its page-count sink instead of <sink-content>, for bytes a
#     shell value cannot hold (3\000\n writes 3, a NUL byte and a newline)
#     or an exact byte sequence (\n writes one newline and nothing else).
#   FBP_SANDBOX_SINK_MODE: a chmod mode the stub Scripts/build_site.sh sets
#     on its page-count sink after writing it (000: the sink is there and
#     not empty, but FullBuildAndPush cannot read it). It needs a sink to
#     act on: with no sink written, the stub chmod fails, says so and the
#     stub still exits 0. Run as root, 000 does not stop the read.
FBP_SANDBOX_SFL_COUNTS_PRE=""
FBP_SANDBOX_SFL_COUNTS_POST=""
FBP_SANDBOX_SINK_PRINTF=""
FBP_SANDBOX_SINK_MODE=""

# forsgren#1 step 12.2d: two more seams, for case 4 of
# Scripts/test_fbp_commit_message.sh, set and reset the same way.
#   FBP_SANDBOX_SFL_PRE_RC: when non-empty, the stub sfl.sh, run as
#     sfl.sh pre, prints FBP_SANDBOX_SFL_PRE_OUTPUT and exits with this
#     status instead of 0 (2 is sfl's secret-class red), so a fixture can
#     drive FullBuildAndPush through a PRE red with sfl's own Errors: block.
#   FBP_SANDBOX_SFL_PRE_OUTPUT: the text that stub prints, byte for byte.
# With FBP_SANDBOX_SFL_PRE_RC empty the stub is the same bytes as before.
FBP_SANDBOX_SFL_PRE_RC=""
FBP_SANDBOX_SFL_PRE_OUTPUT=""

# Road to public, step 4 (the DCO sign-off FBP.sh adds to its commits): one
# more seam, for case 5 of Scripts/test_fbp_commit_message.sh, set and reset
# the same way.
#   FBP_SANDBOX_GIT_NAME, FBP_SANDBOX_GIT_EMAIL: the identity the run
#     commits under, exported as GIT_AUTHOR_* and GIT_COMMITTER_*, the way
#     Scripts/fbp_agent_friend.sh hands FBP.sh agent-Friend's identity.
#     Empty means the sandbox's own, t <t@t.t>.
# Every run gets that identity through the environment, and commit signing
# off, so a sandbox commit neither inherits the identity and signing key of
# the FBP run that started this fixture (fbp_agent_friend.sh exports both)
# nor reaches for a key at all.
FBP_SANDBOX_GIT_NAME=""
FBP_SANDBOX_GIT_EMAIL=""

# Every sandbox this run created, so an interrupted or failing fixture
# leaves none behind in the temp directory. fbp_sandbox_run deletes each one
# itself as soon as it has read its results; the traps remove whatever is
# left, which is only a sandbox whose run was interrupted. A sourcing fixture
# gets the same cleanup for its own temp directories by making them with
# fbp_sandbox_new_dir, or registering them with fbp_sandbox_register_dir
# (every temp directory both fixtures make, such as the one for the mutated
# FBP.sh in Scripts/test_fbp_build_pagecount.sh,
# comes from fbp_sandbox_new_dir).
FBP_SANDBOX_DIRS=()

# The sandbox of the latest fbp_sandbox_run. It is already deleted when
# fbp_sandbox_run returns; the path stays so a caller can say where the run
# was. Empty when the latest run had no sandbox.
FBP_SANDBOX_DIR=""

# The latest run's stdout+stderr and exit status, read out of its sandbox by
# fbp_sandbox_run before it deletes the sandbox, and printed by
# fbp_sandbox_output and fbp_sandbox_rc.
FBP_SANDBOX_OUT=""
FBP_SANDBOX_RC=-1

# The sandbox's HEAD commit after the run, read out the same way (road to
# public, step 4): its sha, author email and full message (git log -1
# --format=%B). All three empty when the run made no commit, which is every
# --no-commit run, since the sandbox starts with none. Printed by
# fbp_sandbox_commit_sha, fbp_sandbox_commit_author and
# fbp_sandbox_commit_msg.
FBP_SANDBOX_COMMIT_SHA=""
FBP_SANDBOX_COMMIT_AUTHOR=""
FBP_SANDBOX_COMMIT_MSG=""

# Why the latest fbp_sandbox_run had no sandbox; empty when it had one. A
# caller whose fbp_sandbox_run failed fails with this, instead of asserting
# against the empty output and the -1 status that run left.
FBP_SANDBOX_REASON=""

# fbp_sandbox_cleanup — removes every registered sandbox. Safe to run more
# than once: an INT or TERM runs it and then exits, which runs it again from
# the EXIT trap, and rm -rf of a sandbox that is already gone does nothing.
# Because INT and TERM are trapped here, bash runs their trap only once the
# foreground command (the sandbox subshell) has returned. A TERM sent to the
# fixture alone therefore removes the sandbox after FullBuildAndPush ends. A
# Ctrl-C goes to the whole foreground process group: the fixture, the
# sandbox subshell, FullBuildAndPush and whichever stub is running. The stubs
# set no traps, so the stub dies with the rest and nothing is left to write
# into the sandbox once the trap removes it (issue source-repo#20 item 4, shown on
# macOS /bin/bash 3.2.57 with a stand-in that sleeps before writing: no
# stub survived and nothing was written). In the same stand-in, a SIGINT
# sent to FullBuildAndPush alone did not stop it at once: it waited for the
# running stub, so that stub had finished before the sandbox was removed. A
# SIGKILL runs no trap and leaves the sandbox behind.
# The array is expanded with the ${arr[@]+...} form because macOS bash 3.2
# treats an empty array as unbound under set -u.
fbp_sandbox_cleanup() {
  local dir
  for dir in ${FBP_SANDBOX_DIRS[@]+"${FBP_SANDBOX_DIRS[@]}"}; do
    rm -rf "$dir"
  done
}

# fbp_sandbox_register_dir <dir> — adds <dir> to the directories the
# cleanup removes. Only the lib's traps run that cleanup: a fixture that
# sets its own EXIT trap must call fbp_sandbox_cleanup from it, or <dir>
# stays behind whenever the fixture exits normally (see the header).
fbp_sandbox_register_dir() {
  FBP_SANDBOX_DIRS+=("$1")
}

# The directory the latest fbp_sandbox_new_dir made; after a failed call,
# whatever mktemp -d printed instead, so a caller can say what it got.
FBP_SANDBOX_NEW_DIR=""

# fbp_sandbox_new_dir — issue source-repo#20: makes a directory with mktemp -d, puts it
# in FBP_SANDBOX_NEW_DIR and registers it for cleanup, with the same catch
# as fbp_sandbox_register_dir: a fixture's own EXIT trap must call
# fbp_sandbox_cleanup, or the directory stays. When mktemp -d fails,
# or hands back no directory, it registers nothing and returns 1: a caller
# must never cd into, or write under, an empty or bogus path.
# FBP_SANDBOX_NEW_DIR is a global, not a local, so the if sees mktemp's exit
# status rather than that of a local declaration.
fbp_sandbox_new_dir() {
  if ! FBP_SANDBOX_NEW_DIR="$(mktemp -d)" || [ -z "$FBP_SANDBOX_NEW_DIR" ] || [ ! -d "$FBP_SANDBOX_NEW_DIR" ]; then
    return 1
  fi
  fbp_sandbox_register_dir "$FBP_SANDBOX_NEW_DIR"
}

trap fbp_sandbox_cleanup EXIT
trap 'fbp_sandbox_cleanup; exit 130' INT
trap 'fbp_sandbox_cleanup; exit 143' TERM

# fbp_sandbox_write_build_site <sink-content> — writes the stub
# Scripts/build_site.sh into the current directory. The stub exits 0 and
# writes <sink-content> plus one trailing newline to the path in
# SITE_PAGE_COUNT_FILE, like the real builder; an empty <sink-content>
# writes no sink at all. The stub line is printf '%s\n' with the value
# quoted by printf %q, so a multi-line <sink-content> such as $'3\n4' lands
# as two lines, byte for byte.
# Issue source-repo#14: the stub reads SITE_PAGE_COUNT_FILE with :? rather than
# defaulting it, so a FullBuildAndPush that stops passing its own path
# fails the build step instead of the stub quietly writing the default path
# FullBuildAndPush happens to read. The only directory it creates is
# .build, so a SITE_PAGE_COUNT_FILE handed to it must lie in .build, in a
# directory the sandbox already has (its root, Scripts, bin) or in one that
# exists outside it. FullBuildAndPush's own path and the case 7 mutation
# proof's decoy in Scripts/test_fbp_build_pagecount.sh lie in
# .build; case 7's own decoy lies in a directory that fixture creates, so
# it can check afterwards that nothing wrote it (issue source-repo#18), and falls back
# to .build only when mktemp -d gives no directory.
# Issue source-repo#17: with FBP_SANDBOX_SINK_PRINTF set, the stub writes that printf
# format to the sink instead and ignores <sink-content>; with
# FBP_SANDBOX_SINK_MODE set, it then chmods the sink to that mode. With
# neither set, the stub is the same bytes as before issue source-repo#17.
fbp_sandbox_write_build_site() {
  local sink="$1"
  local target="\"\${SITE_PAGE_COUNT_FILE:?}\""
  {
    printf '#!/usr/bin/env bash\n'
    if [ -n "$FBP_SANDBOX_SINK_PRINTF" ]; then
      printf 'mkdir -p .build\nprintf %q > %s\n' "$FBP_SANDBOX_SINK_PRINTF" "$target"
    elif [ -n "$sink" ]; then
      printf 'mkdir -p .build\n%s %q > %s\n' "printf '%s\n'" "$sink" "$target"
    fi
    if [ -n "$FBP_SANDBOX_SINK_MODE" ]; then
      printf 'chmod %s %s\n' "$FBP_SANDBOX_SINK_MODE" "$target"
    fi
    printf 'exit 0\n'
  } > Scripts/build_site.sh
  chmod +x Scripts/build_site.sh
}

# fbp_sandbox_write_sfl — issue source-repo#17: writes the stub sfl.sh into the current
# directory. The stub exits 0, unless FBP_SANDBOX_SFL_PRE_RC asks for a PRE
# red (fbp_sandbox_sfl_pre_red_line, forsgren#1 step 12.2d). For each of FBP_SANDBOX_SFL_COUNTS_PRE and
# FBP_SANDBOX_SFL_COUNTS_POST that is non-empty, it writes that value plus
# one trailing newline to .build/sfl-counts.log when its first argument is
# pre (or post), through the line fbp_sandbox_sfl_counts_line prints. With
# both empty the stub is the same bytes as before issue source-repo#17.
fbp_sandbox_write_sfl() {
  {
    printf '#!/usr/bin/env bash\n'
    fbp_sandbox_sfl_counts_line pre "$FBP_SANDBOX_SFL_COUNTS_PRE"
    fbp_sandbox_sfl_counts_line post "$FBP_SANDBOX_SFL_COUNTS_POST"
    fbp_sandbox_sfl_pre_red_line
    printf 'exit 0\n'
  } > sfl.sh
  chmod +x sfl.sh
}

# fbp_sandbox_sfl_pre_red_line — forsgren#1 step 12.2d: prints the stub
# sfl.sh line that, when the stub runs as sfl.sh pre, prints
# FBP_SANDBOX_SFL_PRE_OUTPUT (quoted by printf %q, so it lands byte for byte)
# and exits FBP_SANDBOX_SFL_PRE_RC; prints nothing when that is empty.
fbp_sandbox_sfl_pre_red_line() {
  local phase_arg="\"\$1\""
  if [ -n "$FBP_SANDBOX_SFL_PRE_RC" ]; then
    printf 'if [ %s = pre ]; then printf %%s %q; exit %s; fi\n' "$phase_arg" "$FBP_SANDBOX_SFL_PRE_OUTPUT" "$FBP_SANDBOX_SFL_PRE_RC"
  fi
}

# fbp_sandbox_sfl_counts_line <phase> <counts> — prints the stub sfl.sh line
# that writes <counts> plus one trailing newline to .build/sfl-counts.log
# when the stub runs as sfl.sh <phase>; prints nothing when <counts> is
# empty. <counts> is quoted by printf %q, like the build-site stub, so a
# multi-line value or a control character lands byte for byte.
fbp_sandbox_sfl_counts_line() {
  local phase="$1"
  local counts="$2"
  local phase_arg="\"\$1\""
  if [ -n "$counts" ]; then
    printf 'if [ %s = %s ]; then mkdir -p .build; %s %q > .build/sfl-counts.log; fi\n' "$phase_arg" "$phase" "printf '%s\n'" "$counts"
  fi
}

# fbp_sandbox_run <sink-content> [FullBuildAndPush args...] — builds a fresh
# sandbox (see the header) with fbp_sandbox_write_build_site <sink-content>,
# registers it for cleanup, and runs FBP.sh there with the
# remaining arguments. The FullBuildAndPush it copies is FBP_SANDBOX_FBP, or
# FBP_SANDBOX_FBP_OVERRIDE when that is set (the mutation proof only).
# Issue source-repo#20 (item 2): it then reads the run's stdout+stderr and exit status
# into FBP_SANDBOX_OUT and FBP_SANDBOX_RC (-1 when the run never recorded
# one) and deletes the sandbox, so no sandbox outlives the call, whatever
# EXIT trap the sourcing fixture set. It returns 0 whenever it had a
# sandbox, whatever FullBuildAndPush's own status: that is fbp_sandbox_rc.
# Issue source-repo#20: when mktemp -d fails, or hands back no directory, it prints
# "could not create the FBP sandbox" to stderr, keeps the same line in
# FBP_SANDBOX_REASON and returns 1 BEFORE the subshell, registering nothing
# and leaving FBP_SANDBOX_DIR empty. Without that stop, cd "" leaves the
# subshell where the fixture was called from, which under sfl is the repo
# root: the stubs would overwrite its sfl.sh and Scripts/build_site.sh and
# FullBuildAndPush would run there.
fbp_sandbox_run() {
  local sink="$1"
  shift
  FBP_SANDBOX_DIR=""
  FBP_SANDBOX_OUT=""
  FBP_SANDBOX_RC=-1
  FBP_SANDBOX_REASON=""
  FBP_SANDBOX_COMMIT_SHA=""
  FBP_SANDBOX_COMMIT_AUTHOR=""
  FBP_SANDBOX_COMMIT_MSG=""
  if ! fbp_sandbox_new_dir; then
    FBP_SANDBOX_REASON="could not create the FBP sandbox: mktemp -d gave no directory ('${FBP_SANDBOX_NEW_DIR}'), so FullBuildAndPush was not run"
    echo "$FBP_SANDBOX_REASON" >&2
    return 1
  fi
  FBP_SANDBOX_DIR="$FBP_SANDBOX_NEW_DIR"
  (
    cd "$FBP_SANDBOX_DIR" || exit 1
    git init -q
    git config user.email t@t.t
    git config user.name t
    fbp_sandbox_write_sfl
    mkdir -p Scripts
    fbp_sandbox_write_build_site "$sink"
    printf '#!/usr/bin/env bash\nexit 0\n' > Scripts/check_gofmt.sh
    chmod +x Scripts/check_gofmt.sh
    printf '#!/usr/bin/env bash\nexit 0\n' > Scripts/ensure_private_names_file.sh
    chmod +x Scripts/ensure_private_names_file.sh
    cp "$FBP_SANDBOX_GO_TOOLCHAIN" Scripts/go_toolchain.sh
    cp "$FBP_SANDBOX_PRIVATE_NAMES_GATE" Scripts/check_private_names.sh
    cp "$FBP_SANDBOX_PRIVATE_NAMES_LIB" Scripts/lib_private_names.sh
    cp "$FBP_SANDBOX_GO_MOD" go.mod
    cp "${FBP_SANDBOX_FBP_OVERRIDE:-$FBP_SANDBOX_FBP}" ./FBP.sh
    mkdir -p bin
    printf '#!/usr/bin/env bash\nexit 0\n' > bin/say
    chmod +x bin/say
    export GIT_AUTHOR_NAME="${FBP_SANDBOX_GIT_NAME:-t}"
    export GIT_AUTHOR_EMAIL="${FBP_SANDBOX_GIT_EMAIL:-t@t.t}"
    export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
    export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="commit.gpgsign" GIT_CONFIG_VALUE_0="false"
    mkdir -p .git/fbp-sandbox-home
    export HOME="$PWD/.git/fbp-sandbox-home"
    PATH="$PWD/bin:$PATH" ./FBP.sh "$@" > fbp-out.log 2>&1
    echo "$?" > fbp-rc.log
    if git rev-parse -q --verify HEAD > /dev/null; then
      git log -1 --format=%H > fbp-commit-sha.log
      git log -1 --format=%ae > fbp-commit-author.log
      git log -1 --format=%B > fbp-commit-msg.log
    fi
  )
  FBP_SANDBOX_OUT="$(cat "$FBP_SANDBOX_DIR/fbp-out.log" 2>/dev/null || true)"
  FBP_SANDBOX_RC="$(cat "$FBP_SANDBOX_DIR/fbp-rc.log" 2>/dev/null || echo -1)"
  FBP_SANDBOX_COMMIT_SHA="$(cat "$FBP_SANDBOX_DIR/fbp-commit-sha.log" 2>/dev/null || true)"
  FBP_SANDBOX_COMMIT_AUTHOR="$(cat "$FBP_SANDBOX_DIR/fbp-commit-author.log" 2>/dev/null || true)"
  FBP_SANDBOX_COMMIT_MSG="$(cat "$FBP_SANDBOX_DIR/fbp-commit-msg.log" 2>/dev/null || true)"
  # It stays registered; the cleanup trap's second rm -rf of it does nothing.
  rm -rf "$FBP_SANDBOX_DIR"
  return 0
}

# fbp_sandbox_output — prints the latest run's stdout+stderr; nothing when
# the run never got far enough to write it, or had no sandbox at all.
fbp_sandbox_output() {
  [ -n "$FBP_SANDBOX_OUT" ] || return 0
  printf '%s\n' "$FBP_SANDBOX_OUT"
}

# fbp_sandbox_rc — prints the latest run's exit status; -1 when the run
# never got far enough to record one, or had no sandbox at all.
fbp_sandbox_rc() {
  echo "$FBP_SANDBOX_RC"
}

# fbp_sandbox_commit_sha, fbp_sandbox_commit_author, fbp_sandbox_commit_msg
# — road to public, step 4: print the sandbox's HEAD commit after the latest
# run, its sha, author email and full message; nothing when the run made no
# commit.
fbp_sandbox_commit_sha() {
  [ -n "$FBP_SANDBOX_COMMIT_SHA" ] || return 0
  printf '%s\n' "$FBP_SANDBOX_COMMIT_SHA"
}
fbp_sandbox_commit_author() {
  [ -n "$FBP_SANDBOX_COMMIT_AUTHOR" ] || return 0
  printf '%s\n' "$FBP_SANDBOX_COMMIT_AUTHOR"
}
fbp_sandbox_commit_msg() {
  [ -n "$FBP_SANDBOX_COMMIT_MSG" ] || return 0
  printf '%s\n' "$FBP_SANDBOX_COMMIT_MSG"
}

# ---------------------------------------------------------------------------
# Issue source-repo#20: the mechanics of the self-proofs at the end of both fixtures,
# which run a fixture, a copy of it, a driver or fbp_sandbox_run itself
# from outside and then judge what came back. These only set things up and
# record; each fixture judges the result itself.
# ---------------------------------------------------------------------------

# fbp_sandbox_write_failing_mktemp <dir> — creates <dir> holding an mktemp
# that says so on stderr and exits 1, for a caller to put first on PATH.
# A stub, not a TMPDIR the real one cannot use: macOS mktemp -d falls back
# to the per-user temp directory when TMPDIR is missing, a regular file, or
# not writable, so no TMPDIR value makes it fail there.
fbp_sandbox_write_failing_mktemp() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\necho "mktemp: stub for issue source-repo#20, no temp directory can be created" >&2\nexit 1\n' > "$1/mktemp"
  chmod +x "$1/mktemp"
}

# The record directory of the latest fbp_sandbox_record, read by
# fbp_sandbox_record_rc and fbp_sandbox_record_output.
FBP_SANDBOX_RECORD_DIR=""

# fbp_sandbox_record <record-dir> <cwd> <command...> — runs <command...> in
# a subshell that first cds into <cwd>, with stdin from /dev/null, its
# stdout+stderr in <record-dir>/run.out and its exit status in
# <record-dir>/run.rc, for fbp_sandbox_record_output and
# fbp_sandbox_record_rc to print. If the cd fails the subshell leaves before
# running anything, so a broken setup can never run <command...> in the
# directory the fixture was called from, and no status is recorded. A
# prefix assignment on the call (PATH=... fbp_sandbox_record ...) reaches
# <command...> and ends when the call returns.
fbp_sandbox_record() {
  FBP_SANDBOX_RECORD_DIR="$1"
  local record_cwd="$2"
  shift 2
  (
    cd "$record_cwd" || exit 1
    "$@" > "${FBP_SANDBOX_RECORD_DIR}/run.out" 2>&1 < /dev/null
    echo "$?" > "${FBP_SANDBOX_RECORD_DIR}/run.rc"
  )
}

# fbp_sandbox_record_rc — prints the latest fbp_sandbox_record's exit
# status; missing when none was recorded.
fbp_sandbox_record_rc() {
  cat "${FBP_SANDBOX_RECORD_DIR}/run.rc" 2>/dev/null || echo missing
}

# fbp_sandbox_record_output — prints the latest fbp_sandbox_record's
# stdout+stderr; nothing when none was written.
fbp_sandbox_record_output() {
  cat "${FBP_SANDBOX_RECORD_DIR}/run.out" 2>/dev/null || true
}

# fbp_sandbox_write_aborting_copy <fixture> <root> — writes a copy of
# <fixture> to <root>/Scripts/ with exit 0 inserted just before its first
# "# Case 2:" line, so the copy dies with status 0 after case 1, the way a
# set -u abort inside a function can on macOS bash 3.2. Copies of this lib
# and of FBP_SANDBOX_FBP go beside it, so the copy's ROOT is <root> and its
# case 1 runs a sandbox of its own, cleaned by its own copy of the lib. The
# real Scripts/go_toolchain.sh and go.mod go there too, because that copy of
# the lib copies them into its sandbox from <root> (forsgren#1 step 4).
# Returns 1 when the insertion changed nothing: the anchor no longer
# matches, and a proof built on the copy would prove nothing.
fbp_sandbox_write_aborting_copy() {
  local fixture="$1"
  local root="$2"
  local copy
  copy="${root}/Scripts/$(basename "$fixture")"
  mkdir -p "${root}/Scripts"
  cp "$(dirname "$FBP_SANDBOX_FBP")/Scripts/lib_fbp_sandbox.sh" "${root}/Scripts/lib_fbp_sandbox.sh"
  cp "$FBP_SANDBOX_FBP" "${root}/FBP.sh"
  cp "$FBP_SANDBOX_GO_TOOLCHAIN" "${root}/Scripts/go_toolchain.sh"
  cp "$FBP_SANDBOX_GO_MOD" "${root}/go.mod"
  awk '/^# Case 2:/ && !done { print "exit 0"; done = 1 } { print }' "$fixture" > "$copy"
  if cmp -s "$fixture" "$copy"; then
    return 1
  fi
}
