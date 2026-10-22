#!/usr/bin/env bash
# canon: sfl_pull v2
# Scripts/sfl_pull.sh
#
# sfl's opening pull is verified before any check runs. Return code 3 is
# reserved for "origin moved or no upstream": sfl.sh stops on it.
# Fixtures: Scripts/test_sfl_pull.sh (the contract and its wiring, git stubbed)
# and Scripts/test_sfl_pull_rebase.sh (the rebase, real git in a sandbox).
#
# forsgren#283, step 2 of 2, ported from the estate canon (sfl_pull v2): a pull
# that cannot fast-forward (local commits not on the remote, typically a local
# RED commit) is rebased onto the upstream when the files the incoming commits
# changed overlap neither the local commits nor the staged, unstaged or
# untracked changes, the same overlap list the final push of FBP.sh uses
# (fbp_overlap_files, Scripts/fbp_push_or_rebase.sh, step 1). The gates then
# run on the rebased tree, so what is pushed is what was tested. Any overlap, a
# failed fetch, no upstream or a failed rebase: a hard stop, the local commits
# and the uncommitted changes left as they were, and the recovery command
# named.

# shellcheck source=Scripts/fbp_push_or_rebase.sh
. "$(dirname "${BASH_SOURCE[0]}")/fbp_push_or_rebase.sh"

# sfl_pull_or_stop — runs `git pull --ff-only` with its own output left
# visible, so a network error is still readable. Returns 0 on a clean
# fast-forward, including already up to date, and after a rebase onto unrelated
# incoming commits. On any other outcome it prints the recovery command to
# stderr and returns 3.
sfl_pull_or_stop() {
  if git pull --ff-only; then
    return 0
  fi
  if sfl_pull_rebase_unrelated; then
    return 0
  fi

  printf 'sfl: origin moved or no upstream — run: git pull --rebase --autostash  then re-run\n' >&2
  return 3
}

# sfl_pull_rebase_unrelated — the rebase of sfl_pull_or_stop. Returns 0 when the
# local commits now sit on the upstream with the uncommitted changes restored as
# they were (staged stays staged); non-zero, with a ❌ line, otherwise.
sfl_pull_rebase_unrelated() {
  local upstream incoming_shas ahead stash_before stash_after stashed=false
  if ! upstream=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null); then
    echo "❌ the pull cannot fast-forward and there is no upstream to rebase onto."
    return 1
  fi
  if ! git fetch; then
    echo "❌ git fetch failed — nothing rebased."
    return 1
  fi
  if [ "$(git rev-list --count 'HEAD..@{u}')" -eq 0 ]; then
    echo "❌ the pull cannot fast-forward, but ${upstream} has no new commits — nothing to rebase onto."
    return 1
  fi
  incoming_shas=$(fbp_join_shas 'HEAD..@{u}')
  ahead=$(git rev-list --count '@{u}..HEAD')

  SFL_PULL_OVERLAP=$(fbp_overlap_files) # overlap-check
  if [ -n "$SFL_PULL_OVERLAP" ]; then
    echo "❌ ${upstream} moved (${incoming_shas}) and changed files your local commits or uncommitted changes changed too: $(printf '%s' "$SFL_PULL_OVERLAP" | tr '\n' ' ')"
    echo "   Nothing rebased; your commits and your staged and unstaged changes are as they were."
    return 1
  fi

  # git rebase refuses a dirty tree. The stash keeps the index (pop --index), so
  # a staged change comes back staged. A stash ref that did not change means
  # there was nothing to stash, and nothing is popped: only the stash this run
  # created is ever popped, an older one stays put.
  stash_before=$(git rev-parse -q --verify refs/stash || true)
  if [ -n "$(git status --porcelain)" ]; then
    if ! git stash push -q --include-untracked -m "sfl opening pull (forsgren#283)"; then
      echo "❌ could not stash the uncommitted changes — nothing rebased."
      return 1
    fi
    stash_after=$(git rev-parse -q --verify refs/stash || true)
    if [ "$stash_after" != "$stash_before" ]; then
      stashed=true
    fi
  fi

  echo "${upstream} moved (${incoming_shas}) on other files — rebasing ${ahead} local commit(s) onto it..."
  if ! git rebase -q '@{u}'; then
    if [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
      git rebase --abort || true
    fi
    if $stashed && ! git stash pop -q --index; then
      echo "❌ rebase onto ${upstream} failed and your uncommitted changes could not be re-applied — they are in the stash: git stash pop --index"
      return 1
    fi
    echo "❌ rebase onto ${upstream} (${incoming_shas}) failed — rebase aborted, nothing changed."
    return 1
  fi
  if $stashed && ! git stash pop -q --index; then
    echo "❌ rebased onto ${upstream}, but your uncommitted changes could not be re-applied — they are in the stash: git stash pop --index"
    return 1
  fi
  echo "sfl: rebased onto ${upstream} (${incoming_shas}); the gates run on the rebased tree."
  return 0
}
