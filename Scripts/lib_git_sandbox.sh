#!/usr/bin/env bash
# canon: lib_git_sandbox v1
# Scripts/lib_git_sandbox.sh
#
# The one place that makes a git-using self-test independent of the shell it
# is run from. `git -C <sandbox>` does not override an exported GIT_DIR,
# GIT_WORK_TREE or GIT_INDEX_FILE: with them exported, a fixture's
# `git push origin main` went into the caller's repository instead of its
# temporary one, and its `git config` and `git branch` rewrote the caller's
# .git. Every Scripts/test_*.sh that calls git sources this file before its
# first git call (Scripts/test_git_sandbox_guard.sh fails when one does not),
# and Scripts/test_git_sandbox_isolation.sh shows the effect against a decoy.
#
# SOURCED, never run. It sets no shell options. Sourcing it unsets the
# repository-locating variables in the sourcing shell, so every git the
# self-test starts finds its repository from the directory it is given.

# git_sandbox_isolate: unsets every variable by which git locates a repository.
git_sandbox_isolate() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
    GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_PREFIX
}

# git_sandbox_uses_git <file>: a non-comment line runs git, looks it up, or
# names the real git binary or the shared FBP sandbox. The one detector the
# guard and the isolation test both read, so what is demanded to isolate and
# what is run against the decoy cannot drift apart.
git_sandbox_uses_git() {
  # Into a variable first: grep -q closes the pipe early and pipefail would
  # turn a match in a long file into a miss.
  local code
  code="$(grep -v '^[[:space:]]*#' "$1" || true)"
  grep -qE '(^|[^[:alnum:]_./-])git( |$)|command -v git|REAL_GIT|source .*lib_fbp_sandbox\.sh' <<< "$code"
}

# git_sandbox_sources_helper <file>: a non-comment line sources this file.
git_sandbox_sources_helper() {
  local code
  code="$(grep -v '^[[:space:]]*#' "$1" || true)"
  grep -qE '^[[:space:]]*source .*lib_git_sandbox\.sh"?$' <<< "$code"
}

git_sandbox_isolate
