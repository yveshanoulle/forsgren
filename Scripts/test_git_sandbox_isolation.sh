#!/usr/bin/env bash
# canon: test_git_sandbox_isolation v1
# Scripts/test_git_sandbox_isolation.sh
#
# Self-test: a self-test run with GIT_DIR, GIT_WORK_TREE and
# GIT_INDEX_FILE exported in the calling shell must not touch that
# repository. `git -C <sandbox>` does not override an exported GIT_DIR, so a
# fixture's `git push origin main` once went into the caller's repository.
#
# The caller's repository here is a DECOY the test builds under its own
# temporary directory, with a bare decoy origin. The variables are set only
# for the child processes, via env, never in this shell. The git-using
# self-tests run with them pointing at the decoy; afterwards the decoy's
# config, HEAD, refs, packed-refs and branch list, and the decoy origin's
# refs and HEAD, must be byte-for-byte what they were.
#
# SCOPE (forsgren#251, decision 249). Quality in CI runs every git-using
# self-test. FBP, and any local run (GITHUB_ACTIONS unset), runs only the
# AFFECTED ones: a self-test is affected when its own file changed, or any file it
# names (the Scripts/ scripts, libraries and data files it calls, followed
# transitively) changed, against the merge base with origin/main, counting
# committed, staged, unstaged and untracked changes. A change to this script or
# to a library it sources, or no origin/main to compare against, means every
# self-test. When none is affected the gate says so and passes; it never skips
# without saying. FORSGREN_ISOLATION_FULL=1 forces the full run.
#
# RUNS (forsgren#251, step 2). Locally each selected self-test runs twice under
# the decoy (the two leak shapes below). In Quality (GITHUB_ACTIONS=true) it runs
# once, under the decoy with GIT_DIR and GIT_INDEX_FILE, and the leak check is
# done after that run.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}
ok() {
  echo "  ok: $*"
}

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

DECOY="${TMP}/decoy"
ORIGIN="${TMP}/decoy-origin.git"
git init -q --bare "$ORIGIN"
git init -q -b main "$DECOY"
echo decoy > "${DECOY}/decoy.txt"
git -C "$DECOY" add -A
git -C "$DECOY" -c user.name=decoy -c user.email=decoy@example.test commit -q -m decoy
git -C "$DECOY" remote add origin "$ORIGIN"
git -C "$DECOY" push -q origin main

# snapshot <repo-git-dir> <out-file>: everything a leak would change.
snapshot() {
  {
    echo "--- config"
    cat "$1/config"
    echo "--- HEAD"
    cat "$1/HEAD"
    echo "--- refs"
    git --git-dir="$1" for-each-ref
    echo "--- packed-refs"
    cat "$1/packed-refs" 2> /dev/null
    echo "--- branches"
    git --git-dir="$1" branch -a
  } > "$2" 2>&1
}

# compare <label> <before> <after>: names WHAT changed.
compare() {
  local label="$1" before="$2" after="$3" section
  if cmp -s "$before" "$after"; then
    ok "${label} unchanged"
    return
  fi
  for section in config HEAD refs packed-refs branches; do
    if ! diff <(sed -n "/^--- ${section}\$/,/^--- /p" "$before") \
      <(sed -n "/^--- ${section}\$/,/^--- /p" "$after") > /dev/null; then
      fail "${label}: the ${section} changed: $(diff <(sed -n "/^--- ${section}\$/,/^--- /p" "$before") <(sed -n "/^--- ${section}\$/,/^--- /p" "$after") | grep '^[<>]' | tr '\n' ' ')"
    fi
  done
}

snapshot "${DECOY}/.git" "${TMP}/decoy.before"
snapshot "$ORIGIN" "${TMP}/origin.before"

# One run per git-using self-test, so a reported leak names the self-test that
# caused it. The list is derived with the guard's own detector, never written
# down: a new git-using self-test is run against the decoy from the day it
# exists. This test and the guard are left out (this one would recurse; the
# guard only reads files).
TESTS=()
for t in Scripts/test_*.sh; do
  case "$t" in
    Scripts/test_git_sandbox_isolation.sh | Scripts/test_git_sandbox_guard.sh) continue ;;
  esac
  if git_sandbox_uses_git "$t"; then
    TESTS+=("$t")
  fi
done
if [[ "${#TESTS[@]}" -lt 3 ]]; then
  fail "only ${#TESTS[@]} git-using self-tests found: the detector is broken, not the repository"
fi

# named_files <file>: the repository files a script's non-comment lines name,
# one path per line. A token that looks like a file name is resolved to
# Scripts/<name>, .github/workflows/<name>, or the path itself when it exists.
named_files() {
  local code token
  code="$(grep -v '^[[:space:]]*#' "$1" || true)"
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    if [[ -f "$token" ]]; then
      echo "$token"
    elif [[ -f "Scripts/${token##*/}" ]]; then
      echo "Scripts/${token##*/}"
    elif [[ -f ".github/workflows/${token##*/}" ]]; then
      echo ".github/workflows/${token##*/}"
    fi
  done < <(grep -oE '[A-Za-z0-9_./-]+[.](sh|mjs|js|py|txt|json|yml|yaml|go)' <<< "$code" | sort -u)
}

# closure <file>: the file and every file it names, transitively.
closure() {
  local seen=$'\n'"$1"$'\n' queue=("$1") i=0 f n
  while [[ "$i" -lt "${#queue[@]}" ]]; do
    f="${queue[$i]}"
    i=$((i + 1))
    case "$f" in *.sh | *.mjs | *.js | *.py) ;; *) continue ;; esac
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      if [[ "$seen" != *$'\n'"$n"$'\n'* ]]; then
        seen+="${n}"$'\n'
        queue+=("$n")
      fi
    done < <(named_files "$f")
  done
  printf '%s' "$seen" | sed '/^$/d'
}

# changed_files: against the merge base with origin/main, the tracked changes
# (committed, staged and unstaged) and the untracked files git does not ignore.
# Non-zero when there is no origin/main to compare against. Markdown is prose.
changed_files() {
  local base
  base="$(git merge-base HEAD origin/main 2> /dev/null)" || return 1
  { git diff --name-only "$base" --; git ls-files --others --exclude-standard; } | { grep -v '[.]md$' || true; } | sort -u
}

# select_tests: sets SELECTED (the affected self-tests) and SCOPE_NOTE (why).
select_tests() {
  local changed t c own
  SELECTED=()
  if [[ "${GITHUB_ACTIONS:-}" == "true" || "${FORSGREN_ISOLATION_FULL:-}" == "1" ]]; then
    SELECTED=("${TESTS[@]}")
    SCOPE_NOTE="full run (Quality, or forced)"
    return
  fi
  if ! changed="$(changed_files)"; then
    SELECTED=("${TESTS[@]}")
    SCOPE_NOTE="full run (no origin/main to compare against)"
    return
  fi
  own="$(closure Scripts/test_git_sandbox_isolation.sh)"
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    if grep -qxF -- "$c" <<< "$own"; then
      SELECTED=("${TESTS[@]}")
      SCOPE_NOTE="full run (${c} is part of this gate)"
      return
    fi
  done <<< "$changed"
  for t in "${TESTS[@]}"; do
    local files code
    files="$(closure "$t")"
    code="$(while IFS= read -r c; do cat "$c"; done <<< "$files")"
    while IFS= read -r c; do
      [[ -z "$c" ]] && continue
      if grep -qxF -- "$c" <<< "$files"; then
        SELECTED+=("$t")
        break
      fi
      # Go code and go.mod change what a self-test that builds or runs the tool does.
      case "$c" in cmd/* | internal/* | go.mod | go.sum)
        if grep -qE 'go (build|run|test|install)|cmd/forsgren' <<< "$code"; then
          SELECTED+=("$t")
          break
        fi ;;
      esac
    done <<< "$changed"
  done
  SCOPE_NOTE="changed or affected only; Quality runs all"
}

select_tests
if [[ "${#SELECTED[@]}" -eq 0 ]]; then
  echo "isolation: 0 of ${#TESTS[@]} self-tests affected, full run in Quality"
  echo "OK: no git-using self-test is affected by the changes; Quality runs all ${#TESTS[@]}"
  exit 0
fi
echo "isolation: ${#SELECTED[@]} of ${#TESTS[@]} self-tests affected (${SCOPE_NOTE})"
TESTS=("${SELECTED[@]}")

# Two shapes of the leak (locally both run; Quality runs the second only, once): all three variables (the 2026-10-18 shell), and
# GIT_DIR with GIT_INDEX_FILE only, which lets fixtures that init a bare
# repository get past the work-tree check and reach their push.
run_variant() {
  local name="$1"
  shift
  local t before_fail
  for t in "${TESTS[@]}"; do
    if [[ ! -f "$t" ]]; then
      fail "${t} does not exist, so its isolation cannot be shown"
      continue
    fi
    env "$@" bash "$t" > "${TMP}/run.out" 2>&1 < /dev/null
    snapshot "${DECOY}/.git" "${TMP}/decoy.after"
    snapshot "$ORIGIN" "${TMP}/origin.after"
    before_fail=$failed
    compare "${t} (${name}): the decoy repository" "${TMP}/decoy.before" "${TMP}/decoy.after"
    compare "${t} (${name}): the decoy origin" "${TMP}/origin.before" "${TMP}/origin.after"
    if [[ "$failed" -ne "$before_fail" ]]; then
      # Later runs compare against what is on disk now, not the first leak again.
      cp "${TMP}/decoy.after" "${TMP}/decoy.before"
      cp "${TMP}/origin.after" "${TMP}/origin.before"
    fi
  done
}

if [[ "${GITHUB_ACTIONS:-}" = "true" ]]; then
  # Quality (forsgren#251, step 2): each self-test runs ONCE, under the decoy,
  # and the leak check is inside that run. The shape without GIT_WORK_TREE is
  # the one that lets a fixture that inits a bare repository get past the
  # work-tree check, so it reaches every push the all-three shape reaches.
  echo "isolation: Quality, each self-test runs once under the decoy"
  run_variant "single run under the decoy: GIT_DIR, GIT_INDEX_FILE" GIT_DIR="${DECOY}/.git" GIT_INDEX_FILE="${DECOY}/.git/index"
else
  run_variant "GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE" \
    GIT_DIR="${DECOY}/.git" GIT_WORK_TREE="$DECOY" GIT_INDEX_FILE="${DECOY}/.git/index"
  run_variant "GIT_DIR, GIT_INDEX_FILE" \
    GIT_DIR="${DECOY}/.git" GIT_INDEX_FILE="${DECOY}/.git/index"
fi

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "❌ FAIL: a self-test escaped its sandbox into the repository named by GIT_DIR (see the FAIL lines above)"
  exit 1
fi
echo "OK: ${#TESTS[@]} git-using self-tests leave a repository named by GIT_DIR untouched"
