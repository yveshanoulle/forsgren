#!/usr/bin/env bash
# Scripts/test_check_private_names.sh
#
# Self-test for Scripts/check_private_names.sh (forsgren#52), run before the
# gate it validates. The gate keeps the real private repository names out of
# this public repository's tracked files. The list of names lives OUTSIDE the
# repository (Yves's ruling, 2026-10-04): locally in a file, in CI in an
# Actions secret passed through env. Every name below is made up
# (acme-secret-repo, globex-internal); none is a real repository.
#
# The gate's interface, as pinned here:
#   Scripts/check_private_names.sh [repo-dir]    (default: the current directory)
#   list source, first that is set and non-empty wins:
#     1. env FORSGREN_PRIVATE_NAMES, newline-separated (CI secret)
#     2. the file FORSGREN_PRIVATE_NAMES_FILE, else
#        $HOME/.config/forsgren/private-names, one name per line
#   blank lines and lines starting with # are not names.
#   exit 0 clean (prints an OK: line), 1 a name found, 2 no list available.
#
# THE MATCH RULE (decided here): a name matches case-insensitively, as a
# WHOLE NAME. It must not be directly preceded or followed by a letter, a
# digit, `_` or `-`; any other character (/, space, `.`, quote, line start or
# end) is a boundary. So `acme-secret-repo` is found in `github.com/Acme-Secret-Repo`
# and in `acme-secret-repo.` but NOT in `acme-secret-repository` or in
# `my-acme-secret-repo`: those are different names, and a fixture or prose may
# legitimately contain them.
#
# The FAIL line names `file:line` (or `tracked path #N in git ls-files` for a
# path hit) and never the matched name or path, so a CI log never reveals it.
#
#   1. a clean tree                                -> exit 0, OK:
#   2. a tracked file with a listed name           -> exit 1, `file:line`, and
#                                                     the output has no name
#   3. the same name in other letter case          -> exit 1
#   4. the list from the file (FORSGREN_PRIVATE_NAMES_FILE)   -> works
#   5. the list from the default file under $HOME  -> works
#   6. the list from env (FORSGREN_PRIVATE_NAMES)  -> works, no name printed
#   7. no list at all                              -> exit 2, a message
#   8. a list with only comments and blanks        -> exit 2: a scan for nothing
#   9. a name only inside a longer word            -> exit 0 (see the rule)
#  10. a name at a boundary (slash, dot, quote)    -> exit 1
#  11. an untracked file with a name               -> exit 0 (only tracked
#                                                     files are judged)
#  12. a repository with no tracked files          -> exit 2,
#                                                     the scan read nothing
#  13. a tracked PATH with a name                  -> exit 1, `tracked path #N`,
#                                                     never the path or name
# Mutation proof: a copy of the gate that prints the matched line must reveal
# the name, so the no-name assertion can fail.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="$(pwd)/Scripts/check_private_names.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "private-names gate self-test"

if [[ ! -x "$GATE" ]]; then
  selftest_abort "Scripts/check_private_names.sh is missing or not executable: nothing to test"
fi

NAME_A="acme-secret-repo"
NAME_B="globex-internal"

NAMES_FILE="${TMP}/names-file"
printf '# made-up private names\n%s\n\n%s\n' "$NAME_A" "$NAME_B" > "$NAMES_FILE"
NAMES_ENV="$(printf '%s\n\n%s' "$NAME_A" "$NAME_B")"
EMPTY_FILE="${TMP}/empty-names"
printf '# only a comment\n\n   \n' > "$EMPTY_FILE"
EMPTY_HOME="${TMP}/empty-home"
mkdir -p "$EMPTY_HOME"

# new_repo <name>: a git repository with one ordinary tracked file.
new_repo() {
  REPO="${TMP}/$1"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  write_file "main.go" $'package main\n\nfunc main() {}\n' track
}

# write_file <path> <content> [track]: writes a file; `track` git-adds it.
write_file() {
  mkdir -p "$(dirname "${REPO}/$1")"
  printf '%s' "$2" > "${REPO}/$1"
  if [[ "${3:-}" == "track" ]]; then
    git -C "$REPO" add "$1"
  fi
}

# run_file_with <gate> <names-file>: the list from the file; env list unset.
run_file_with() {
  capture env -u FORSGREN_PRIVATE_NAMES HOME="$EMPTY_HOME" \
    FORSGREN_PRIVATE_NAMES_FILE="$2" "$1" "$REPO"
}

# run_file <names-file>: run_file_with the gate under test.
run_file() {
  run_file_with "$GATE" "$1"
}

# run_home <home>: no env list, no file variable: only the default file under
# <home> can supply a list.
run_home() {
  capture env -u FORSGREN_PRIVATE_NAMES -u FORSGREN_PRIVATE_NAMES_FILE \
    HOME="$1" "$GATE" "$REPO"
}

# run_env <list>: the list from env; no file anywhere.
run_env() {
  capture env -u FORSGREN_PRIVATE_NAMES_FILE HOME="$EMPTY_HOME" \
    FORSGREN_PRIVATE_NAMES="$1" "$GATE" "$REPO"
}

# reveals <text...>: succeeds when OUT contains any of the texts, ignoring case.
reveals() {
  local text
  for text in "$@"; do
    if grep -qiF -- "$text" <<< "$OUT"; then
      REVEALED="$text"
      return 0
    fi
  done
  return 1
}

# want_not_said <case> <text...>: the output contains none of the texts.
want_not_said() {
  local case_name="$1"
  shift
  if reveals "$@"; then
    fail "${case_name}: the output reveals '${REVEALED}'. Output: ${OUT}"
  else
    echo "  ok: ${case_name}: the output names no private name"
  fi
}

new_repo "clean"
write_file "README.md" $'# acme-app\nNothing private here.\n' track
run_file "$NAMES_FILE"
want_green_ok "a clean tree is green"

new_repo "listed"
write_file "docs/notes.md" $'line one\nsee acme-secret-repo for details\n' track
run_file "$NAMES_FILE"
want_red "a listed name is red, naming file:line" "docs/notes.md:2"
want_not_said "a listed name" "$NAME_A" "$NAME_B"

new_repo "case"
write_file "docs/notes.md" $'ACME-Secret-Repo\n' track
run_file "$NAMES_FILE"
want_red "matching is case-insensitive" "docs/notes.md:1"
want_not_said "case-insensitive match" "$NAME_A"

new_repo "default-file"
write_file "docs/notes.md" $'globex-internal\n' track
DEFAULT_HOME="${TMP}/home-with-list"
mkdir -p "${DEFAULT_HOME}/.config/forsgren"
cp "$NAMES_FILE" "${DEFAULT_HOME}/.config/forsgren/private-names"
run_home "$DEFAULT_HOME"
want_red "the default file under HOME is read" "docs/notes.md:1"

new_repo "from-file"
write_file "a.txt" $'ok\n' track
write_file "b/c.txt" $'x\ny\nGlobex-Internal\n' track
run_file "$NAMES_FILE"
want_red "the list from FORSGREN_PRIVATE_NAMES_FILE, second name, right line" "b/c.txt:3"
want_not_said "the list from the file" "$NAME_A" "$NAME_B"

new_repo "from-env"
write_file "docs/notes.md" $'a\nb\nacme-secret-repo\n' track
run_env "$NAMES_ENV"
want_red "the list from FORSGREN_PRIVATE_NAMES (CI secret)" "docs/notes.md:3"
want_not_said "the list from env" "$NAME_A" "$NAME_B"

new_repo "env-second-name"
write_file "docs/notes.md" $'globex-internal\n' track
run_env "$NAMES_ENV"
want_red "every name of a newline-separated env list is searched" "docs/notes.md:1"

new_repo "no-list"
run_home "$EMPTY_HOME"
want_exit "no list at all is exit 2, loudly" 2 "FORSGREN_PRIVATE_NAMES"
want_not_said "no list" "$NAME_A"

new_repo "empty-list"
run_file "$EMPTY_FILE"
want_exit "a list with no names is exit 2: a scan for nothing" 2 "no names"
capture env -u FORSGREN_PRIVATE_NAMES_FILE HOME="$EMPTY_HOME" \
  FORSGREN_PRIVATE_NAMES=$'\n  \n# c\n' "$GATE" "$REPO"
want_exit "an env list with no names is exit 2" 2 "no names"

new_repo "missing-file"
run_file "${TMP}/does-not-exist"
want_exit "a names file that does not exist is exit 2" 2 "does-not-exist"

new_repo "substring"
write_file "docs/notes.md" $'acme-secret-repository\nmy-acme-secret-repo\nacme-secret-repo2\nxacme-secret-repo\nacme-secret-repo_v2\n' track
run_file "$NAMES_FILE"
want_green_ok "a name inside a longer word is not a match"

new_repo "boundaries"
write_file "a.md" $'https://github.com/acme-secret-repo\n' track
write_file "b.md" $'"globex-internal".\n' track
write_file "c.md" $'(acme-secret-repo)\n' track
write_file "d.md" $'acme-secret-repo.\n' track
run_file "$NAMES_FILE"
want_red "a name at a boundary is found (a.md)" "a.md:1"
want_said "a name at a boundary is found (b.md)" "b.md:1"
want_said "a name at a boundary is found (c.md)" "c.md:1"
want_said "a name at a boundary is found (d.md)" "d.md:1"

new_repo "untracked"
write_file "scratch.md" $'acme-secret-repo\n'
run_file "$NAMES_FILE"
want_green_ok "an untracked file is not judged"

new_repo "nothing-tracked"
git -C "$REPO" rm -q --cached main.go
run_file "$NAMES_FILE"
want_exit "a repository with no tracked files is exit 2: the scan read nothing" 2 "no tracked files"

new_repo "path"
write_file "docs/Acme-Secret-Repo.notes.md" $'harmless\n' track
write_file "docs/other.md" $'harmless\n' track
run_file "$NAMES_FILE"
want_red "a tracked path with a name is red, by its number" "tracked path #"
want_not_said "a tracked path" "$NAME_A" "docs/Acme" "notes.md"

# A tracked path that names a private name AND whose content does too: the
# content hit's `file:line` must not print the path, or the name leaks.
new_repo "path-and-content"
write_file "docs/acme-secret-repo.md" $'see acme-secret-repo for details\n' track
run_file "$NAMES_FILE"
want_red "a path and its content both naming a name is red" "tracked path #"
want_not_said "a path that names a name, with a content hit" "$NAME_A" "docs/acme"

# A tracked symlink is stored as its target text. A target that names a name
# is a hit, even when the link dangles; it is reported by number, never by
# name or path.
new_repo "symlink-target"
ln -s acme-secret-repo "${REPO}/link"
git -C "$REPO" add link
run_file "$NAMES_FILE"
want_red "a symlink whose target names a name is red" "tracked path #"
want_said "a symlink target hit says so" "(link target)"
want_not_said "a symlink target" "$NAME_A" "$NAME_B"

# The gate turns tracing off for itself: under bash -x, a trace of the list
# would print every name.
new_repo "traced"
capture env -u FORSGREN_PRIVATE_NAMES_FILE HOME="$EMPTY_HOME" \
  FORSGREN_PRIVATE_NAMES="$NAMES_ENV" bash -x "$GATE" "$REPO"
want_green_ok "a traced run on a clean tree is green"
want_not_said "a bash -x run" "$NAME_A" "$NAME_B"

# Mutation proof: the no-name assertion can fail. A gate that prints the
# matched line (the mutation turns `file:line` into `file:line:content`) must
# be caught by the very assertion the cases above use.
new_repo "reveal"
write_file "docs/notes.md" $'see acme-secret-repo for details\n' track
MUTANT="${TMP}/mutant/Scripts/check_private_names.sh"
if selftest_mutant "$GATE" "$MUTANT" "s/lineno=\${hit%%:\*}/lineno=\$hit/"; then
  run_file_with "$MUTANT" "$NAMES_FILE"
  if [[ "$RC" -eq 1 ]] && reveals "$NAME_A"; then
    echo "  ok: mutation proof: a gate that prints the matched line fails the no-name assertion"
  else
    fail "mutation proof: the mutant gate that prints the matched line was not caught (exit ${RC}). Output: ${OUT}"
  fi
  run_file "$NAMES_FILE"
  if reveals "$NAME_A"; then
    fail "the real gate reveals the name on the mutation proof's repository. Output: ${OUT}"
  else
    echo "  ok: mutation proof: the real gate, on the same repository, reveals nothing"
  fi
fi

selftest_end "the private-names gate does not keep listed names out of tracked files, or passes without a list" \
  "private-names gate is red with file:line (never the name) on a listed name, case-insensitively and as a whole name, reads its list from a file or from env, and is exit 2 when no list or no tracked file is there"
