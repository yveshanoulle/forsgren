#!/usr/bin/env bash
# Scripts/test_git_sandbox_guard.sh
#
# Guard for forsgren#228: every Scripts/test_*.sh that calls git, or that
# drives the shared FBP sandbox (which does), sources Scripts/lib_git_sandbox.sh,
# so an exported GIT_DIR cannot send its fixture's git into the caller's
# repository. A new git-using self-test that forgets the source line fails
# here, naming the file.
#
# Mutation proof: a copy of a git-using self-test without the source line must
# be reported, and the copy with it must not.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "git sandbox guard self-test"

# uses_git <file>: a non-comment line runs git, looks it up, or names the real git binary or the shared FBP sandbox.
uses_git() {
  # Into a variable first: grep -q closes the pipe early and pipefail would
  # turn a match in a long file into a miss.
  local code
  code="$(grep -v '^[[:space:]]*#' "$1" || true)"
  grep -qE '(^|[^[:alnum:]_./-])git( |$)|command -v git|REAL_GIT|source .*lib_fbp_sandbox\.sh' <<< "$code"
}

# sources_helper <file>: a non-comment line sources the helper.
sources_helper() {
  local code
  code="$(grep -v '^[[:space:]]*#' "$1" || true)"
  grep -qE '^[[:space:]]*source .*lib_git_sandbox\.sh"?$' <<< "$code"
}

# unisolated <file>...: the files that use git and do not source the helper.
unisolated() {
  local f
  for f in "$@"; do
    if uses_git "$f" && ! sources_helper "$f"; then
      echo "$f"
    fi
  done
}

checked=0
for f in Scripts/test_*.sh; do
  if uses_git "$f"; then
    checked=$((checked + 1))
  fi
done
if [[ "$checked" -lt 20 ]]; then
  fail "only ${checked} git-using self-tests found: the detector is broken, not the repository"
fi

missing="$(unisolated Scripts/test_*.sh)"
if [[ -n "$missing" ]]; then
  fail "these git-using self-tests do not source Scripts/lib_git_sandbox.sh: $(echo "$missing" | tr '\n' ' ')"
else
  echo "  ok: all ${checked} git-using self-tests source Scripts/lib_git_sandbox.sh"
fi

# Mutation proof: Scripts/test_release_commit.sh without its source line.
mkdir -p "${TMP}/Scripts"
grep -v 'source Scripts/lib_git_sandbox.sh' Scripts/test_release_commit.sh > "${TMP}/Scripts/test_release_commit.sh"
if cmp -s Scripts/test_release_commit.sh "${TMP}/Scripts/test_release_commit.sh"; then
  fail "mutation proof: removing the source line changed nothing in Scripts/test_release_commit.sh, the proof would be vacuous"
elif [[ "$(unisolated "${TMP}/Scripts/test_release_commit.sh")" == "${TMP}/Scripts/test_release_commit.sh" ]]; then
  echo "  ok: mutation proof: a git-using self-test without the source line is reported by name"
else
  fail "mutation proof: a copy of Scripts/test_release_commit.sh without the source line was not reported"
fi

selftest_end "a git-using self-test does not isolate itself from an exported GIT_DIR" "every git-using self-test sources Scripts/lib_git_sandbox.sh"
