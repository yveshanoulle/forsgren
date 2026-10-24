#!/usr/bin/env bash
# Scripts/test_release_removed_names.sh (forsgren#263). forsgren's own.
#
# The unused bump machinery is gone (forsgren#237, step 6). The release tags
# main's head and bumps, tests and commits nothing, so the scripts that did, the
# short Quality for a bump commit (quality.yml scope=bump) and their self-tests,
# gate rows and docs rows no longer exist, and no tracked file but SHIPPED.md (the
# history) names them.
#
# This was the last section of Scripts/test_release_workflow.sh. It reads every
# tracked file, which no list of inputs can state, so it is its own gate and
# runs always: the pin of the workflow reads a short, listed set of files and
# Scripts/gate_inputs.txt lets sfl skip it (forsgren#263). One search per
# name over the tracked files, not one shell loop per file.
#
# Mutation proofs, in a throwaway repository, each red BECAUSE of the change:
#   A. a removed file back                       -> red, naming it;
#   B. a tracked file naming a removed script    -> red, naming file and name;
#   C. a tracked file naming a removed word      -> red, naming file and word;
#   D. quality.yml with the scope input again    -> red;
#   E. SHIPPED.md naming a word                  -> green (the history is exempt).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release removed names"

REMOVED_FILES="Scripts/release_bump.sh Scripts/release_commit.sh Scripts/release_bump_diff.sh Scripts/lib_release_bump_scope.sh Scripts/release_bump_scope.txt Scripts/quality_bump_gates.txt Scripts/run_short_quality.sh Scripts/test_release_bump.sh Scripts/test_release_commit.sh Scripts/test_release_bump_diff.sh Scripts/test_run_short_quality.sh Scripts/test_quality_scope.sh"
REMOVED_WORDS="dispatch-bump scope=bump QS_SHORT_QUALITY QS_DIFF_OUTCOME summary_short_note quality-bump quality-resumed"

# removed_findings <root>: one `removed:` line per finding in the repository at root.
removed_findings() {
  local root="$1" f w names t bad=0
  for f in $REMOVED_FILES; do
    if [[ -e "${root}/${f}" ]]; then
      echo "removed: ${f} still exists"
      bad=1
    fi
  done
  names=""
  for f in $REMOVED_FILES; do names="${names} $(basename "$f")"; done
  for w in $names $REMOVED_WORDS; do
    while IFS= read -r t; do
      echo "removed: ${t} still names ${w}"; bad=1
    done < <(git -C "$root" grep -lF -- "$w" -- . ':(exclude)SHIPPED.md' ':(exclude)Scripts/test_release_workflow.sh' ':(exclude)Scripts/test_release_removed_names.sh' || true)
  done
  if [[ -f "${root}/.github/workflows/quality.yml" ]] && grep -qE '^      scope:' "${root}/.github/workflows/quality.yml"; then
    echo "removed: quality.yml still has the scope input"
    bad=1
  fi
  return "$bad"
}

capture removed_findings "."
want_green "the unused bump scripts, the short Quality and their rows are gone"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
FX="${TMP}/fx"
git init -q -b main "$FX"
mkdir -p "${FX}/Scripts" "${FX}/.github/workflows"
echo 'on: push' > "${FX}/.github/workflows/quality.yml"
echo 'nothing here' > "${FX}/notes.txt"
echo 'history' > "${FX}/SHIPPED.md"
git -C "$FX" add -A
capture removed_findings "$FX"
want_green "the throwaway repository is clean"

echo 'x' > "${FX}/Scripts/release_bump.sh"
capture removed_findings "$FX"
want_red "mutation proof A: a removed file back" "removed: Scripts/release_bump.sh still exists"
rm -f "${FX}/Scripts/release_bump.sh"

echo 'call release_commit.sh' > "${FX}/notes.txt"
capture removed_findings "$FX"
want_red "mutation proof B: a tracked file naming a removed script" "removed: notes.txt still names release_commit.sh"

echo 'uses dispatch-bump' > "${FX}/notes.txt"
capture removed_findings "$FX"
want_red "mutation proof C: a tracked file naming a removed word" "removed: notes.txt still names dispatch-bump"
echo 'nothing here' > "${FX}/notes.txt"

printf 'on:\n  workflow_call:\n    inputs:\n      scope:\n' > "${FX}/.github/workflows/quality.yml"
capture removed_findings "$FX"
want_red "mutation proof D: quality.yml with the scope input again" "removed: quality.yml still has the scope input"
echo 'on: push' > "${FX}/.github/workflows/quality.yml"

echo 'dispatch-bump was removed' > "${FX}/SHIPPED.md"
capture removed_findings "$FX"
want_green "mutation proof E: SHIPPED.md may name a removed word"

selftest_end "the release removed names gate found failures" "release removed names (nothing names the removed bump machinery; five proofs seen)"
