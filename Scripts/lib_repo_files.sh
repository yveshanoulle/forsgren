#!/usr/bin/env bash
# Scripts/lib_repo_files.sh
#
# forsgren's own (forsgren#204). The one way a file-scanning gate lists the
# files it judges: the tracked files AND the untracked ones that git does not
# ignore. FBP commits after its gates run, so a file a step adds is still
# untracked while they do; a gate that listed only `git ls-files` judged it
# for the first time in the next step, and CI, which sees the committed
# tree, failed on what the local run had passed (the vulncheck pin test,
# forsgren#87). An ignored file is left out: git will never commit it.
#
#   repo_files <dir> [git ls-files options and pathspecs...]
#
# prints the listing of the git work tree at <dir>, one path per line (add -z
# for NUL-separated), relative to <dir>; the pathspecs narrow it, for
# example repo_files . '*.sh'. It is `git ls-files --cached --others
# --exclude-standard`, so a path is never listed twice and it exits non-zero
# when git does (the caller checks, a failed listing is no verdict).
#
# SOURCED, never run. It judges nothing on its own: the self-tests of the
# gates that source it are its test (Scripts/test_check_shellcheck.sh,
# test_check_yamllint.sh, test_check_markdown_links.sh,
# test_check_guardrail_packages.sh and test_check_data_guard.sh each have a
# case with an untracked file and one with an ignored file). It sets no shell
# options and no traps; the sourcing script owns those.

repo_files() {
  local dir="$1"
  shift
  git -C "$dir" ls-files --cached --others --exclude-standard "$@"
}
