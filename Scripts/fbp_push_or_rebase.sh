#!/usr/bin/env bash
# canon: fbp_push_or_rebase v3
# Scripts/fbp_push_or_rebase.sh <note-file>
#
# forsgren#283, step 1 of 2; ported from the estate canon (estate issue 383),
# the only change: the wrapper here is FBP.sh. Called by FBP.sh when its final
# `git push` was refused. Decides whether the refusal is the remote having
# moved during the run, and if the incoming commits touch other files than the
# local ones, rebases onto the upstream and pushes. When that push is refused
# too (the remote moved once more) the whole cycle repeats: at most 3 pushes in
# total, the refused original included (so 2 rebase cycles),
# each with its own fetch and its own overlap check against the newly incoming
# commits.
#
#   - Not a non-fast-forward refusal (no incoming commits after a fetch):
#     ❌ line, exit 1.
#   - A file changed by both the incoming and the local commits, or a rebase
#     conflict, in any attempt: any started rebase is aborted, the local
#     commits stay as they were, ❌ lines name the overlapping files and the
#     command to run (`git pull --rebase --autostash`, then run FBP.sh
#     again), exit 1.
#   - No overlap: `git rebase @{u}`, `git push`; on success the git row of the
#     summary is written to <note-file>: a warning that names the short shas
#     rebased onto, across all attempts, and says CI tests that combination,
#     not this run. Exit 0.
#   - The push refused after the 3rd push: ❌ "push refused 3 times, remote
#     keeps moving", the local commits stay rebased, exit 1.
#
# The sign-off (DCO, CONTRIBUTING.md) survives the rebase: git rebase keeps
# each commit's author and message, Signed-off-by trailer included, and
# Scripts/check_dco.sh matches the trailer to the author. Pinned by
# Scripts/test_fbp_push_or_rebase.sh.
#
# A failed operation fails, it never warns: the only warning is the one that is
# true, that the pushed combination was not tested by this run.
#
# The overlap list (fbp_overlap_files) and the sha list (fbp_join_shas) are
# shared with sfl's opening pull, which rebases the same way when it cannot
# fast-forward (Scripts/sfl_pull.sh, forsgren#283, step 2). So this file is
# also SOURCED:
# sourced, it defines the functions and runs nothing; run, it handles the
# refused push.

# fbp_join_shas <range> — the short shas of <range>, oldest first, one space
# between them. Names the incoming commits here and at sfl's opening pull.
fbp_join_shas() {
  git rev-list --abbrev-commit --reverse "$1" | tr '\n' ' ' | sed 's/ $//'
}

# fbp_overlap_files — the files changed by the incoming commits (merge base to
# @{u}) that the local side changed too, one per line, sorted. The local side is
# the local commits (merge base to HEAD) plus the staged, unstaged and untracked
# files. At the final push the working tree is clean (FBP.sh has
# just committed), so there only the commits count; at sfl's opening pull the
# uncommitted changes count as well.
fbp_overlap_files() {
  comm -12 <(git diff --name-only 'HEAD...@{u}' | sort -u) <({
    git diff --name-only '@{u}...HEAD'
    git diff --name-only --cached; git diff --name-only; git ls-files --others --exclude-standard # worktree-files
  } | sort -u)
}

# fbp_push_or_rebase <note-file> — the refused-push handling described above;
# exits with the script's status.
fbp_push_or_rebase() {
  # 3 pushes in total: the refused original plus at most 2 rebase-and-push cycles.
  local MAX_PUSHES=3
  local MAX_ATTEMPTS=$((MAX_PUSHES - 1))

  local NOTE_FILE="${1:-}"
  [[ -n "$NOTE_FILE" ]] || { echo "❌ FAIL: Scripts/fbp_push_or_rebase.sh needs the note file as its argument"; exit 2; }

  local onto_all="" attempt=1 incoming_count overlap onto
  while [[ "$attempt" -le "$MAX_ATTEMPTS" ]]; do
    echo "The push was refused — fetching to see why (rebase attempt ${attempt} of ${MAX_ATTEMPTS})..."
    git fetch || { echo "❌ FAIL: git fetch failed, so the refusal cannot be examined"; exit 1; }

    incoming_count=$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
    if [[ "$incoming_count" -eq 0 ]]; then
      echo "❌ FAIL: the push failed and nothing new is on the upstream — this is not a non-fast-forward refusal, so nothing was rebased"
      exit 1
    fi

    overlap=$(fbp_overlap_files) # overlap-check

    if [[ -n "$overlap" ]]; then
      echo "❌ FAIL: the push was refused and the incoming commits change files that the local commits change too — not rebasing, local commits unchanged:"
      while IFS= read -r f; do echo "   ${f}"; done <<< "$overlap"
      echo "   Run: git pull --rebase --autostash   then run FBP.sh again."
      exit 1
    fi

    onto=$(fbp_join_shas 'HEAD..@{u}')
    onto_all="${onto_all:+${onto_all} }${onto}"

    if ! git rebase '@{u}'; then
      git rebase --abort
      echo "❌ FAIL: the rebase onto ${onto} conflicted — aborted, local commits unchanged."
      echo "   Run: git pull --rebase --autostash   then run FBP.sh again."
      exit 1
    fi

    if git push; then
      printf '⚠️ (pushed after rebasing onto %s; this combination is tested by CI, not by this run)\n' "$onto_all" > "$NOTE_FILE"
      echo "⚠️ Rebased onto ${onto_all} and pushed: this combination is tested by CI, not by this run."
      exit 0
    fi

    attempt=$((attempt + 1))
  done

  echo "❌ FAIL: push refused ${MAX_PUSHES} times, remote keeps moving — local commits stay rebased onto ${onto_all}."
  echo "   Run: git pull --rebase --autostash   then run FBP.sh again."
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  fbp_push_or_rebase "$@"
fi
