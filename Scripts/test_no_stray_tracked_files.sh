#!/usr/bin/env bash
# Scripts/test_no_stray_tracked_files.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# No stray tracked files — issue #10.
#
# Commit ef13192 ("fixed quality bug so that errors are visible") brought in
# two kinds of file nobody asked for:
#
#   - four Finder .DS_Store files (repo root, Scripts/, Site/, Site/assets/);
#   - workflow copies OUTSIDE .github/workflows/: a root quality.yml and
#     Scripts/quality_candidate_fix.yml, the pre-#9 quality.yml with every
#     unguarded step body still in it.
#
# All of them are gone now: the root quality.yml was removed later, and #10
# deleted the copy and the four .DS_Store files. None of them was referenced
# by anything, and the workflow copy was the worse of the two kinds: it read
# like a workflow, it was linted by nothing (yamllint and actionlint read
# .github/workflows/ only), GitHub never ran it, and it had already drifted
# from the real workflow twice (#7, #9) before anyone noticed it was dead.
#
# THE RULE, over the paths `git ls-files` lists (tracked files only, so an
# untracked .DS_Store that Finder drops in a working copy is not a failure):
#   (a) no tracked path whose last component is exactly .DS_Store, at any
#       depth;
#   (b) no tracked *.yml / *.yaml that GitHub would not run has a top-level
#       `jobs:` key: anywhere outside .github/workflows/, and in any
#       subdirectory of it. That key is what makes a YAML file a workflow;
#       config files such as .yamllint.yml and .actionlint.yaml do not carry
#       it. The content is read from the WORKING TREE copy of each indexed
#       path, not from the index.
#
# SELF-PROVING, and the proof runs FIRST: the same matcher is run on a
# scratch git repository holding one file of each offending kind, plus a
# harmless YAML and a real workflow in its proper place. Both offenders must
# be flagged and neither of the others. Only then is the matcher allowed to
# judge this repository — a matcher nobody has seen flag anything would pass
# a clean tree and a broken one alike. The proof covers a ROOT .DS_Store and
# a Scripts/*.yml copy only; the nested .DS_Store, the .yaml extension, the
# .github/workflows/ subdirectory and the unreadable-file skip are not seen
# failing by it.

# An inherited GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE (a hook, a wrapper)
# would point the scratch `git init` and `git add -A` below at THIS
# repository instead of the scratch one, and the `git -C .` listing of this
# repository at whatever repository they name. Nothing here needs them.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: stray tracked files check aborted before completing" >&2
    exit 1
  fi
}

trap finish EXIT

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

# stray_offenders <repo-dir> <listing-file>: prints one line per offending
# tracked path, `<reason>: <path>`, and nothing when the tree is clean.
# Lists the index NUL-separated so a path with spaces stays one path.
#
# The listing goes through a file, not a process substitution: a failing
# `git ls-files` inside `< <(...)` is invisible, and an empty listing reads
# as a clean verdict. Here git failing, or listing nothing, is an error.
stray_offenders() {
  local repo="$1"
  local listing="$2"
  local path
  local base

  if ! git -C "$repo" ls-files -z > "$listing"; then
    echo "git ls-files failed in ${repo}" >&2
    return 2
  fi
  if [[ ! -s "$listing" ]]; then
    echo "git ls-files listed nothing in ${repo} — an empty index would judge clean while checking nothing" >&2
    return 2
  fi

  while IFS= read -r -d '' path; do
    base="${path##*/}"

    if [[ "$base" == ".DS_Store" ]]; then
      echo "tracked Finder file: ${path}"
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

    # The index decides WHICH paths are judged; the content test reads the
    # working-tree file. A path still in the index but deleted from the
    # working tree cannot be read, so it is skipped, not flagged.
    [[ -f "${repo}/${path}" ]] || continue

    if grep -qE '^jobs:' "${repo}/${path}"; then
      echo "workflow copy outside .github/workflows/: ${path}"
    fi
  done < "$listing"
}

# --- Self-proof: the matcher on a scratch repository ------------------------

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; finish' EXIT

SCRATCH="${TMP}/repo"
mkdir -p "${SCRATCH}/Scripts" "${SCRATCH}/.github/workflows"
git -C "$SCRATCH" init -q

printf 'finder\n' > "${SCRATCH}/.DS_Store"
# One workflow body in two places: only the location may decide the verdict.
cat > "${SCRATCH}/.github/workflows/ci.yml" <<'YML'
name: Workflow
on: push
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo workflow
YML
cp "${SCRATCH}/.github/workflows/ci.yml" "${SCRATCH}/Scripts/x.yml"
cat > "${SCRATCH}/.yamllint.yml" <<'YML'
extends: default
rules:
  line-length:
    max: 200
YML

git -C "$SCRATCH" add -A

expected="$(printf '%s\n' \
  "tracked Finder file: .DS_Store" \
  "workflow copy outside .github/workflows/: Scripts/x.yml" | sort)"

self_rc=0
self_out="$(stray_offenders "$SCRATCH" "${TMP}/scratch.ls")" || self_rc=$?
self_sorted="$(printf '%s\n' "$self_out" | sed '/^$/d' | sort)"

if [[ "$self_rc" -ne 0 ]]; then
  fail "self-proof: the matcher exited ${self_rc} on the scratch repository — it cannot be trusted to judge this one"
elif [[ "$self_sorted" != "$expected" ]]; then
  fail "self-proof: on the scratch repository the matcher flagged
${self_sorted:-<nothing>}
but must flag exactly
${expected}
(.yamllint.yml is harmless config and .github/workflows/ci.yml is a workflow in its proper place)"
else
  echo "  ok: self-proof flags the scratch .DS_Store and Scripts/x.yml, and neither .yamllint.yml nor .github/workflows/ci.yml"
fi

# --- The real repository ----------------------------------------------------
#
# Judged only when the self-proof passed: a matcher that failed its own proof
# would produce a verdict on this tree that means nothing either way.

if [[ "$failed" -eq 0 ]]; then
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
    echo "  ok: no tracked .DS_Store and no workflow copy outside .github/workflows/"
  fi
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: stray tracked files — delete them from the index; git history keeps them"
  exit 1
fi

echo "OK: no stray tracked files (matcher proven on a scratch repository first)"
