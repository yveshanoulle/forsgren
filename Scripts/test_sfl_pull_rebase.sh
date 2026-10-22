#!/usr/bin/env bash
# canon: test_sfl_pull_rebase v1
# Scripts/test_sfl_pull_rebase.sh
#
# forsgren#283, step 2 of 2, ported from the estate canon (test_sfl_pull_rebase
# v1) on this repository's self-test harness (Scripts/lib_selftest.sh), its
# cases unchanged: sfl's opening pull rebases when it cannot fast-forward and
# the incoming commits touch other files than the local side (the local
# commits plus the staged, unstaged and untracked changes); it stops, with the
# files named and the local side untouched, when they overlap.
#
# Drives Scripts/sfl_pull.sh (sfl_pull_or_stop, the call sfl.sh stops on with
# `|| exit 3`) in a throwaway sandbox: a temp bare remote and two clones. The
# function's return code is what decides whether sfl's run continues; the
# wiring `sfl_pull_or_stop || exit 3` is pinned by Scripts/test_sfl_pull.sh.
# Nothing outside the temp directory is touched, no machine-wide git config is
# read, no network is used; the sandbox guard below refuses to run any git
# command of a case from outside it.
#
# Cases: (a) a local commit plus a staged and an unstaged change, an incoming
# commit on an unrelated file -> rebased onto the remote, return 0, one commit
# ahead, the staged change still staged, the unstaged one still there, no stash
# left, the incoming sha named; (b) an incoming commit on the staged file ->
# return 3, the file named on a ❌ line with the command to run, HEAD, the
# staged and the unstaged changes and the stash list untouched, no rebase in
# progress; (c) an incoming commit on the file of the local commit -> the same
# stop.
# Mutation proofs: without the overlap check (c) is rebased, and without the
# working-tree part of the shared overlap list (fbp_overlap_files in
# Scripts/fbp_push_or_rebase.sh) (b) is rebased; each case must fail with
# exactly that reason.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "sfl pull rebase self-test"

LIBDIR="$(pwd)/Scripts"
SANDBOX="${TMP}"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@example.invalid
export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@example.invalid

ok() { echo "  ok: $*"; }

# Sandbox guard: every git call of a case goes through g, which refuses a
# directory outside $SANDBOX.
g() {
  local dir="$1"; shift
  case "$(cd "$dir" && pwd -P)/" in
    "$(cd "$SANDBOX" && pwd -P)"/*) ;;
    *) echo "❌ sandbox guard: refusing git in $dir"; exit 2 ;;
  esac
  git -C "$dir" "$@"
}

# make_world NAME — bare remote + clone "local" + clone "other", one seed commit
# with a.txt, b.txt and c.txt. Local then has one unpushed commit on a.txt (the
# RED commit of a previous run), a staged change on c.txt and an unstaged one on
# a.txt. Local edits sit on line 1, incoming ones at the end, so only the
# overlap check (not a merge conflict) can stop the overlapping cases.
make_world() {
  W="$SANDBOX/$1"
  mkdir -p "$W"
  git init -q --bare -b main "$W/remote.git"
  git clone -q "$W/remote.git" "$W/local" 2>/dev/null
  g "$W/local" checkout -q -b main
  local f
  for f in a b c; do printf '%s1\n2\n3\n4\n5\n6\n7\n' "$f" > "$W/local/$f.txt"; done
  g "$W/local" add -A; g "$W/local" commit -q -m seed
  g "$W/local" push -q -u origin main 2>/dev/null
  git clone -q "$W/remote.git" "$W/other" 2>/dev/null
  printf 'a local\n2\n3\n4\n5\n6\n7\n' > "$W/local/a.txt"
  g "$W/local" commit -q -am "*** RED ****"
  printf 'c staged\n2\n3\n4\n5\n6\n7\n' > "$W/local/c.txt"
  g "$W/local" add c.txt
  printf 'a local\n2\n3\n4\n5\n6\n7\nunstaged\n' > "$W/local/a.txt"
}

# incoming FILE — the other clone appends to FILE and pushes; sets IN_SHA.
incoming() {
  printf 'incoming\n' >> "$W/other/$1"
  g "$W/other" commit -q -am "incoming on $1"; g "$W/other" push -q origin HEAD:main 2>/dev/null
  IN_SHA="$(g "$W/other" rev-parse --short HEAD)"
}

# run_pull DIR_OF_SFL_PULL — run sfl_pull_or_stop in the local clone the way
# sfl.sh does (sourced, `|| exit 3`); sets OUT, RC.
run_pull() {
  OUT="$(cd "$W/local" && bash -c 'set -uo pipefail; . "$1/sfl_pull.sh"; sfl_pull_or_stop || exit 3' _ "$1" 2>&1)" && RC=0 || RC=$?
}

# snapshot — HEAD, staged diff, unstaged diff and stash list of the local clone.
snapshot() {
  printf '%s\n--staged--\n%s\n--unstaged--\n%s\n--stash--\n%s\n' \
    "$(g "$W/local" rev-parse HEAD)" "$(g "$W/local" diff --cached)" \
    "$(g "$W/local" diff)" "$(g "$W/local" stash list)"
}

# case_unrelated LIBDIR — (a); returns 0 when the case behaves as wanted.
case_unrelated() {
  make_world "unrelated${2:-}"
  incoming b.txt
  run_pull "$1"
  local rc_ok=0
  [ "$RC" -eq 0 ] || { fail "(a) exit $RC, wanted 0 (the run must continue): $OUT"; rc_ok=1; }
  g "$W/local" merge-base --is-ancestor origin/main HEAD || { fail "(a) the local commit was not rebased onto origin/main"; rc_ok=1; }
  [ "$(g "$W/local" rev-list --count origin/main..HEAD)" = "1" ] || { fail "(a) the local commit is not exactly one commit ahead after the rebase"; rc_ok=1; }
  grep -Fxq "a local" <<< "$(g "$W/local" show HEAD:a.txt 2>/dev/null)" || { fail "(a) the local commit lost its a.txt change"; rc_ok=1; }
  grep -Fxq "incoming" <<< "$(cat "$W/local/b.txt")" || { fail "(a) the incoming b.txt change is not in the working tree"; rc_ok=1; }
  [ "$(g "$W/local" diff --cached --name-only)" = "c.txt" ] || { fail "(a) c.txt is no longer the staged change: '$(g "$W/local" diff --cached --name-only)'"; rc_ok=1; }
  grep -Fxq "unstaged" <<< "$(cat "$W/local/a.txt")" || { fail "(a) the unstaged a.txt change is lost"; rc_ok=1; }
  [ -z "$(g "$W/local" stash list)" ] || { fail "(a) a stash was left behind"; rc_ok=1; }
  grep -Fq "$IN_SHA" <<< "$OUT" || { fail "(a) the incoming sha $IN_SHA is not named: $OUT"; rc_ok=1; }
  [ "$rc_ok" -eq 0 ] && ok "(a) local commit + staged and unstaged change, unrelated incoming commit: rebased, staged change still staged, no stash left, run continues"
  return "$rc_ok"
}

# case_overlap LIBDIR LETTER FILE [TAG] — (b)/(c); returns 0 when stopped as wanted.
case_overlap() {
  local letter="$2" file="$3"
  make_world "overlap-${letter}${4:-}"
  incoming "$file"
  local before; before="$(snapshot)"
  run_pull "$1"
  local rc_ok=0
  [ "$RC" -eq 3 ] || { fail "($letter) exit $RC, wanted 3 (the run must stop)"; rc_ok=1; }
  if [ "$(g "$W/local" rev-parse HEAD)" != "${before%%$'\n'*}" ]; then
    fail "($letter) rebased although the incoming commit touches $file"; rc_ok=1
  fi
  [ "$(snapshot)" = "$before" ] || { fail "($letter) HEAD, the staged or the unstaged changes or the stash list changed"; rc_ok=1; }
  grep -Fq "$file" <<< "$(grep -F '❌' <<< "$OUT")" || { fail "($letter) no ❌ line names $file: $OUT"; rc_ok=1; }
  grep -Fq "git pull --rebase --autostash" <<< "$OUT" || { fail "($letter) the command to run is missing: $OUT"; rc_ok=1; }
  if [ -d "$W/local/.git/rebase-merge" ] || [ -d "$W/local/.git/rebase-apply" ]; then
    fail "($letter) a rebase is still in progress"; rc_ok=1
  fi
  [ "$rc_ok" -eq 0 ] && ok "($letter) incoming commit on $file: stopped with exit 3, $file named, local commit, staged and unstaged changes and stash list untouched"
  return "$rc_ok"
}

case_unrelated "$LIBDIR" || true
case_overlap "$LIBDIR" b c.txt || true
case_overlap "$LIBDIR" c a.txt || true

# mutate NAME FILE SED_EXPR — a copy of sfl_pull.sh and fbp_push_or_rebase.sh in
# $SANDBOX/NAME with FILE rewritten by SED_EXPR; prints the directory, fails
# when nothing changed (a mutation that does not change the file proves nothing).
mutate() {
  local dir="$SANDBOX/$1"
  mkdir -p "$dir"
  cp "$LIBDIR/sfl_pull.sh" "$LIBDIR/fbp_push_or_rebase.sh" "$dir/"
  sed "$3" "$LIBDIR/$2" > "$dir/$2"
  if cmp -s "$LIBDIR/$2" "$dir/$2"; then return 1; fi
  printf '%s' "$dir"
}

# Mutation 1: sfl_pull.sh with its overlap check emptied — (c) must be rebased.
if ! MUT1="$(mutate mut-overlap sfl_pull.sh 's/^\( *SFL_PULL_OVERLAP=\).*# overlap-check$/\1""/')"; then
  fail "mutation 1: the '# overlap-check' line was not found in Scripts/sfl_pull.sh"
else
  mut_out="$(case_overlap "$MUT1" c a.txt -mut1 2>&1)" || true
  if grep -Fq "rebased although the incoming commit touches a.txt" <<< "$mut_out"; then
    ok "mutation 1: without the overlap check (c) fails with 'rebased although the incoming commit touches a.txt'"
  else
    fail "mutation 1: (c) did not fail for the right reason: $mut_out"
  fi
fi

# Mutation 2: the shared overlap list without the working-tree files — (b) must
# be rebased, because c.txt is only staged, not committed.
if ! MUT2="$(mutate mut-worktree fbp_push_or_rebase.sh '/# worktree-files$/d')"; then
  fail "mutation 2: the '# worktree-files' line was not found in Scripts/fbp_push_or_rebase.sh"
else
  mut_out="$(case_overlap "$MUT2" b c.txt -mut2 2>&1)" || true
  if grep -Fq "rebased although the incoming commit touches c.txt" <<< "$mut_out"; then
    ok "mutation 2: without the working-tree files (b) fails with 'rebased although the incoming commit touches c.txt'"
  else
    fail "mutation 2: (b) did not fail for the right reason: $mut_out"
  fi
fi

selftest_end "sfl's opening pull did not rebase or stop as expected" \
  "sfl's opening pull rebases when the incoming files are unrelated, stops with the local side untouched when they overlap"
