#!/usr/bin/env bash
# canon: test_no_stray_tracked_files v1
# Scripts/test_no_stray_tracked_files.sh
#
# No stray files in what the next commit would carry. The
# canon version, byte-identical across the estate's repositories. This script
# is the gate and its own self-test: it proves its matcher on a scratch
# repository, then judges this repository.
#
# Two kinds of file nobody asked for have turned up in this estate, brought in
# by one careless `git add -A`:
#
#   - Finder .DS_Store files, at any depth;
#   - workflow copies OUTSIDE .github/workflows/: a YAML copy of a workflow
#     under the repository root or Scripts/. It reads like a workflow, is
#     linted by nothing (yamllint and actionlint read .github/workflows/ only),
#     GitHub never runs it, and it drifts from the real workflow unnoticed.
#
# THE RULE, over the paths Scripts/lib_repo_files.sh lists (tracked files AND
# untracked files that git does not ignore, because the commit that follows
# the gates would carry both; an ignored .DS_Store is left out, git will never
# commit it):
#   (a) no path whose last component is exactly .DS_Store, at any depth;
#   (b) no *.yml / *.yaml that GitHub would not run has a top-level `jobs:`
#       key: anywhere outside .github/workflows/, and in any subdirectory of
#       it. That key is what makes a YAML file a workflow; config files such as
#       .yamllint.yml and .actionlint.yaml do not carry it. The content is
#       read from the WORKING TREE copy of each listed path.
#
# SELF-PROVING, and the proof runs FIRST: the same matcher is run on a scratch
# git repository holding one file of each kind, offending and harmless,
# tracked, untracked and ignored. Exactly the offenders must be flagged. Only
# then is the matcher allowed to judge this repository.
#
# MUTATION PROOF, after the verdict: six weakened copies of this script, each
# with one clause of the matcher or of the listing removed, are run in a
# throwaway root. Each must fail its own self-proof, so every clause is
# seen to matter. The proof covers the clauses; the unreadable-file skip is
# not seen failing by it.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

# An inherited GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE (a hook, a wrapper)
# would point the scratch `git init` and `git add` below at THIS repository
# instead of the scratch one. Nothing here needs them.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_repo_files.sh
source Scripts/lib_repo_files.sh
selftest_begin "stray tracked files check"

# stray_offenders <repo-dir> <listing-file>: prints one line per offending
# path, `<reason>: <path>`, and nothing when the tree is clean. Lists
# NUL-separated so a path with spaces stays one path.
#
# The listing goes through a file, not a process substitution: a failing
# `git ls-files` inside `< <(...)` is invisible, and an empty listing reads
# as a clean verdict. Here git failing, or listing nothing, is an error.
stray_offenders() {
  local repo="$1"
  local listing="$2"
  local path
  local base

  if ! repo_files "$repo" -z > "$listing"; then
    echo "git ls-files failed in ${repo}" >&2
    return 2
  fi
  if [[ ! -s "$listing" ]]; then
    echo "git ls-files listed nothing in ${repo} — an empty listing would judge clean while checking nothing" >&2
    return 2
  fi

  while IFS= read -r -d '' path; do
    base="${path##*/}"

    if [[ "$base" == ".DS_Store" ]]; then
      echo "Finder file: ${path}"
      continue
    fi

    case "$path" in
      *.yml|*.yaml) ;;
      *) continue ;;
    esac

    # GitHub runs only files DIRECTLY inside .github/workflows/; a
    # subdirectory there is as dead as Scripts/.
    case "$path" in
      .github/workflows/*/*) ;;
      .github/workflows/*) continue ;;
    esac

    # The listing decides WHICH paths are judged; the content test reads the
    # working-tree file. A path still in the index but deleted from the
    # working tree cannot be read, so it is skipped, not flagged.
    [[ -f "${repo}/${path}" ]] || continue

    if grep -qE '^jobs:' "${repo}/${path}"; then
      echo "workflow copy outside .github/workflows/: ${path}"
    fi
  done < "$listing"
}

# --- Self-proof: the matcher on a scratch repository ------------------------

SCRATCH="${TMP}/repo"
mkdir -p "${SCRATCH}/Scripts" "${SCRATCH}/.github/workflows/sub" "${SCRATCH}/ignored"
git -C "$SCRATCH" init -q
# A machine-wide ignore file must not decide what the scratch repository ignores.
git -C "$SCRATCH" config core.excludesFile /dev/null

cat > "${SCRATCH}/.github/workflows/ci.yml" <<'YML'
name: Workflow
on: push
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo workflow
YML
cat > "${SCRATCH}/.yamllint.yml" <<'YML'
extends: default
rules:
  line-length:
    max: 200
YML
printf 'ignored/\n' > "${SCRATCH}/.gitignore"

# Tracked: a root .DS_Store, one workflow body outside its place, one in a
# subdirectory of its place, and the harmless two.
printf 'finder\n' > "${SCRATCH}/.DS_Store"
cp "${SCRATCH}/.github/workflows/ci.yml" "${SCRATCH}/Scripts/x.yml"
cp "${SCRATCH}/.github/workflows/ci.yml" "${SCRATCH}/.github/workflows/sub/w.yml"
git -C "$SCRATCH" add -A

# Untracked and not ignored (the commit after the gates would carry them): a
# nested .DS_Store and a .yaml workflow copy.
printf 'finder\n' > "${SCRATCH}/Scripts/.DS_Store"
cp "${SCRATCH}/.github/workflows/ci.yml" "${SCRATCH}/Scripts/y.yaml"

# Ignored: git will never commit them, so they are not offenders.
printf 'finder\n' > "${SCRATCH}/ignored/.DS_Store"
cp "${SCRATCH}/.github/workflows/ci.yml" "${SCRATCH}/ignored/z.yml"

expected="$(printf '%s\n' \
  "Finder file: .DS_Store" \
  "Finder file: Scripts/.DS_Store" \
  "workflow copy outside .github/workflows/: Scripts/x.yml" \
  "workflow copy outside .github/workflows/: Scripts/y.yaml" \
  "workflow copy outside .github/workflows/: .github/workflows/sub/w.yml" | sort)"

self_rc=0
self_out="$(stray_offenders "$SCRATCH" "${TMP}/scratch.ls")" || self_rc=$?
self_sorted="$(printf '%s\n' "$self_out" | sed '/^$/d' | sort)"

selfproof_held=0
if [[ "$self_rc" -ne 0 ]]; then
  fail "self-proof: the matcher exited ${self_rc} on the scratch repository — it cannot be trusted to judge this one"
elif [[ "$self_sorted" != "$expected" ]]; then
  fail "self-proof: on the scratch repository the matcher flagged
${self_sorted:-<nothing>}
but must flag exactly
${expected}
(.yamllint.yml is harmless config, .github/workflows/ci.yml is a workflow in its proper place, and everything under ignored/ is ignored)"
else
  selfproof_held=1
  echo "  ok: self-proof flags the tracked and the untracked .DS_Store and workflow copies, and not the harmless, the properly placed or the ignored files"
fi

# The listing failing or empty is an error, not a clean verdict.
mkdir -p "${TMP}/empty" "${TMP}/notrepo"
git -C "${TMP}/empty" init -q
git -C "${TMP}/empty" config core.excludesFile /dev/null
empty_rc=0
stray_offenders "${TMP}/empty" "${TMP}/empty.ls" >/dev/null 2>&1 || empty_rc=$?
if [[ "$empty_rc" -eq 2 ]]; then
  echo "  ok: an empty repository is an error (exit 2), not a clean verdict"
else
  fail "self-proof: an empty repository must give exit 2, got ${empty_rc}"
fi
notrepo_rc=0
GIT_CEILING_DIRECTORIES="$TMP" stray_offenders "${TMP}/notrepo" "${TMP}/notrepo.ls" >/dev/null 2>&1 || notrepo_rc=$?
if [[ "$notrepo_rc" -eq 2 ]]; then
  echo "  ok: a directory that is not a repository is an error (exit 2)"
else
  fail "self-proof: a directory that is not a repository must give exit 2, got ${notrepo_rc}"
fi

# --- The real repository ----------------------------------------------------
#
# Judged only when the self-proof passed: a matcher that failed its own proof
# would produce a verdict on this tree that means nothing either way.

if [[ "$selfproof_held" -eq 1 && "$failed" -eq 0 ]]; then
  real_rc=0
  real_out="$(stray_offenders "." "${TMP}/real.ls")" || real_rc=$?
  if [[ "$real_rc" -ne 0 ]]; then
    fail "the matcher exited ${real_rc} on this repository — no verdict"
  elif [[ -n "$real_out" ]]; then
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        fail "$line"
      fi
    done <<< "$real_out"
  else
    echo "  ok: no .DS_Store and no workflow copy outside .github/workflows/"
  fi
fi

# --- Mutation proof: each clause, removed, fails the self-proof --------------
#
# A weakened copy of THIS script runs in a throwaway root (the script anchors
# itself one directory above its own), and must fail with its self-proof line.
# STRAY_MUTANT_RUN stops a mutant from running the mutants again.

if [[ -z "${STRAY_MUTANT_RUN:-}" ]]; then
  # stray_mutant <name> <script sed-expression | -> <lib sed-expression | ->
  stray_mutant() {
    local name="$1"
    local script_sed="$2"
    local lib_sed="$3"
    local root="${TMP}/mutant-${name}"
    mkdir -p "${root}/Scripts"
    cp Scripts/lib_selftest.sh "${root}/Scripts/lib_selftest.sh"
    cp Scripts/lib_repo_files.sh "${root}/Scripts/lib_repo_files.sh"
    cp Scripts/lib_git_sandbox.sh "${root}/Scripts/lib_git_sandbox.sh"
    cp Scripts/test_no_stray_tracked_files.sh "${root}/Scripts/test_no_stray_tracked_files.sh"
    if [[ "$script_sed" != "-" ]]; then
      selftest_mutant Scripts/test_no_stray_tracked_files.sh "${root}/Scripts/test_no_stray_tracked_files.sh" "$script_sed" || return 0
    fi
    if [[ "$lib_sed" != "-" ]]; then
      selftest_mutant Scripts/lib_repo_files.sh "${root}/Scripts/lib_repo_files.sh" "$lib_sed" || return 0
    fi
    capture env STRAY_MUTANT_RUN=1 "${root}/Scripts/test_no_stray_tracked_files.sh"
    if [[ "$RC" -ne 0 ]] && grep -qF "self-proof:" <<< "$OUT"; then
      echo "  ok: mutation proof: ${name}"
    else
      fail "mutation proof: the copy without ${name} was not caught by the self-proof (exit ${RC}). Output: ${OUT}"
    fi
  }

  stray_mutant "the .DS_Store clause" 's/== "\.DS_Store"/== "NO.DS_Store"/' -
  stray_mutant "the jobs: test" "s/grep -qE '\\^jobs:'/grep -qE '^NOjobs:'/" -
  stray_mutant "the .yaml extension" 's/\*\.yml|\*\.yaml) ;;/*.yml) ;;/' -
  stray_mutant "the workflows subdirectory clause" 's#\.github/workflows/\*/\*) ;;#.github/workflows/NO/*) ;;#' -
  stray_mutant "the untracked files in the listing" - 's/ --others//'
  stray_mutant "the ignore rules in the listing" - 's/ --exclude-standard//'
fi

selftest_end "stray files in what the next commit would carry" "no stray files (matcher proven on a scratch repository first, each clause seen failing in a weakened copy)"
