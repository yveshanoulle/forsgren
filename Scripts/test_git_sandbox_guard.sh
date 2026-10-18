#!/usr/bin/env bash
# canon: test_git_sandbox_guard v1
# Scripts/test_git_sandbox_guard.sh
#
# Guard: every Scripts/test_*.sh that calls git, or that drives the shared FBP
# sandbox (which does), sources Scripts/lib_git_sandbox.sh, so an exported
# GIT_DIR cannot send its fixture's git into the caller's repository. A new
# git-using self-test that forgets the source line fails here, naming the
# file. Known limit: a test that only runs a git-using script is not seen.
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

# unisolated <file>...: the files that use git and do not source the helper.
unisolated() {
  local f
  for f in "$@"; do
    if git_sandbox_uses_git "$f" && ! git_sandbox_sources_helper "$f"; then
      echo "$f"
    fi
  done
}

# A floor, not a count: a detector that finds almost nothing is broken.
MIN_GIT_TESTS=5

checked=0
victim=""
for f in Scripts/test_*.sh; do
  if git_sandbox_uses_git "$f"; then
    checked=$((checked + 1))
    if [[ -z "$victim" && "$f" != "Scripts/test_git_sandbox_guard.sh" ]]; then
      victim="$f"
    fi
  fi
done
if [[ "$checked" -lt "$MIN_GIT_TESTS" ]]; then
  fail "only ${checked} git-using self-tests found, the floor is ${MIN_GIT_TESTS}: the detector is broken, not the repository"
fi

missing="$(unisolated Scripts/test_*.sh)"
if [[ -n "$missing" ]]; then
  fail "these git-using self-tests do not source Scripts/lib_git_sandbox.sh: $(echo "$missing" | tr '\n' ' ')"
else
  echo "  ok: all ${checked} git-using self-tests source Scripts/lib_git_sandbox.sh"
fi

# Mutation proof: the first other git-using self-test, without its source line.
if [[ -z "$victim" ]]; then
  fail "mutation proof: no git-using self-test besides this one to mutate"
else
  mkdir -p "${TMP}/Scripts"
  mutant="${TMP}/${victim}"
  grep -v 'source Scripts/lib_git_sandbox.sh' "$victim" > "$mutant" || true
  if cmp -s "$victim" "$mutant"; then
    fail "mutation proof: removing the source line changed nothing in ${victim}, the proof would be vacuous"
  elif [[ "$(unisolated "$mutant")" == "$mutant" ]]; then
    echo "  ok: mutation proof: a git-using self-test without the source line is reported by name"
  else
    fail "mutation proof: a copy of ${victim} without the source line was not reported"
  fi
fi

selftest_end "a git-using self-test does not isolate itself from an exported GIT_DIR" "every git-using self-test sources Scripts/lib_git_sandbox.sh"
