#!/usr/bin/env bash
# canon: check_bare_mktemp v1 + forsgren#615 (unchecked tmp_dir/tmp_file)
# Scripts/check_bare_mktemp.sh
#
# Every temp path honours TMPDIR (the estate sweep; forsgren#612). On
# macOS a mktemp whose template has no path in it ignores TMPDIR and writes to
# the per-user folder `getconf DARWIN_USER_TEMP_DIR` names (/var/folders/...,
# the internal disk), even when TMPDIR points at the build volume: the bare
# call, `-d` alone, `-t <prefix>`, and a template without a path
# (name.XXXXXX, made in the working directory). This gate is red on each, with
# <file>:<line>, the reason and the fix.
#
# What it reads: every shell script and workflow git tracks or will commit
# (tracked, or untracked and not ignored: Scripts/lib_repo_files.sh), the way
# Scripts/check_shellcheck.sh lists them: every *.sh, every extension-less file
# whose first line is a bash/sh shebang, and .github/workflows/*.yml|*.yaml.
#
# What is a call: the command word in command position (line start, after
# `$(`, a backtick, `(`, `;`, `|`, `&`, `!`, `{` or then/do/else/if/while/
# until/time/exec/command), on a line that is not a comment. A sentence that
# only names the command is not one. Every call of a line is judged.
#
# What is green: the first argument after the options is a template that
# starts with a path: "/..., "${TMPDIR:-/tmp}/..., "$TMPDIR/..., or any
# "$VAR/... / "${VAR}/... (a variable holding a folder, then a slash). The
# helper (Scripts/lib_tmp.sh: tmp_dir <name>, tmp_file <name>) is such a call.
# Red: no template; `-t` (a prefix, not a path); `-p`/--tmpdir (the estate
# puts the folder in the template); a template that does not start with a
# path, including a variable without a slash after it (it cannot be shown to
# hold a folder). A call split over lines with `\` is red: its template is not
# on the line.
#
# Scripts/bare_mktemp_exemptions.txt lists files whose calls must stay, one
# `<path>|<reason>` per line. Empty is the normal state. The list is required
# and read fail closed: missing, a line without a reason, a path that is no
# file, and an entry that exempts no bare call are each red, named. It is
# always this repository's list (next to this script), not the fixture's.
#
# forsgren#615: a shell script without `set -e` must check the helper's status:
# `X="$(tmp_dir name)"` alone does not stop it when the folder cannot be made,
# and it goes on with an empty path (writing to /err, /listed). In such a
# script a `$(tmp_dir ...)` or `$(tmp_file ...)` assignment with no `||` after
# it (and not the condition of an `if !`) is red, with <file>:<line> and the
# fix. A script with `set -e` (a line starting `set -` with an e among its
# flags) is not judged. Scripts/test_tmp_failure_stops.sh runs the scripts.
#
# Testing seam: BARE_MKTEMP_ROOT overrides the repository root, so
# Scripts/test_check_bare_mktemp.sh can run the gate on synthetic git trees.
#
# sfl.sh runs it from Scripts/gate_report_order.txt, and so does CI, through
# Scripts/run_ci_phase.sh.
#
# forsgren's copy reads the list of scanned files for the stale-exemption
# check from a here-string, not a pipe into grep -q (forsgren#428's rule,
# Scripts/check_pipe_grep_q.sh); the verdicts are the canon's.
#
# Local invocation: ./Scripts/check_bare_mktemp.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/lib_repo_files.sh
source "${SCRIPT_DIR}/lib_repo_files.sh"

ROOT="${BARE_MKTEMP_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
EXEMPTIONS_FILE="${SCRIPT_DIR}/bare_mktemp_exemptions.txt"
cd "$ROOT"

FIX="fix: source Scripts/lib_tmp.sh and use tmp_dir <name> or tmp_file <name>, or put the folder in the template: -d \"\${TMPDIR:-/tmp}/<name>.XXXXXX\""

# The command word in command position, and a template that starts with a path.
CALL_RE='(^|[;&|(`!{]|(^|[[:space:]])(then|do|else|if|while|until|time|exec|command))[[:space:]]*mktemp'
PATH_RE='^["'"'"']?(/|\$\{?[A-Za-z0-9_]+(:-[^}]*)?\}?/)'

status=0

# --- the exemption list
EXEMPT=""
if [ ! -f "$EXEMPTIONS_FILE" ]; then
  echo "❌ FAIL: bare mktemp: ${EXEMPTIONS_FILE} is missing; there is no default, and no verdict without it" >&2
  exit 1
fi
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '' | '#'*) continue ;; esac
  path="${line%%|*}"
  reason="${line#*|}"
  if [[ "$line" != *"|"* ]] || [[ -z "${reason// /}" ]] || ! [[ "$path" =~ ^[A-Za-z0-9_.][A-Za-z0-9_./-]*$ ]] || [ ! -f "$path" ]; then
    echo "❌ bare mktemp: ${EXEMPTIONS_FILE}: '${line}' is not '<path of an existing file>|<reason>'; fix the line, the gate does not guess" >&2
    status=1
    continue
  fi
  EXEMPT="${EXEMPT}${path}"$'\n'
done < "$EXEMPTIONS_FILE"

# --- the files
collect_targets() {
  repo_files . '*.sh' '.github/workflows/*.yml' '.github/workflows/*.yaml'
  repo_files . | while IFS= read -r f; do
    case "$f" in *.*) continue ;; esac
    [ -f "$f" ] || continue
    first_line=""
    IFS= read -r first_line < "$f" 2>/dev/null || true
    if [[ "$first_line" =~ ^#!.*(bash|/sh)([[:space:]].*)?$ ]]; then
      echo "$f"
    fi
  done
}

# judge <args>: the text after the command word. Prints the reason the call
# is bare, or nothing when its template starts with a path.
judge() {
  local a="$1" tok
  while :; do
    a="${a#"${a%%[![:space:]]*}"}"
    case "$a" in
      --tmpdir*)
        echo "--tmpdir names the folder outside the template"
        return
        ;;
      -[A-Za-z]*) ;;
      *) break ;;
    esac
    tok="${a%%[[:space:]]*}"
    case "$tok" in
      *t*) echo "-t takes a prefix, not a path: macOS puts it in DARWIN_USER_TEMP_DIR"; return ;;
      *p*) echo "-p names the folder outside the template"; return ;;
    esac
    a="${a#"$tok"}"
  done
  case "$a" in
    '' | ')'* | '`'* | ';'* | '|'* | '&'* | '>'* | '<'* | '2>'* | \\*)
      echo "no template: macOS ignores TMPDIR and writes to DARWIN_USER_TEMP_DIR"
      return
      ;;
  esac
  if ! [[ "$a" =~ $PATH_RE ]]; then
    echo "the template does not start with a path, so TMPDIR is not honoured"
  fi
}

# scan <file>: one ❌ line per bare call, with the line and the fix. Status 0
# when it found a bare call, 1 when the file has none.
scan() {
  local f="$1" n=0 line rest after why found=1 pre
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    rest="${line#"${line%%[![:space:]]*}"}"
    case "$rest" in '#'*) continue ;; esac
    while [[ "$rest" =~ $CALL_RE ]]; do
      pre="${rest%%"${BASH_REMATCH[0]}"*}"
      after="${rest#"${pre}${BASH_REMATCH[0]}"}"
      case "$after" in
        '' | [[:space:]\;\&\|\)\`]*)
          why="$(judge "$after")"
          if [ -n "$why" ]; then
            echo "❌ ${f}:${n}: ${why}"
            echo "   ${line#"${line%%[![:space:]]*}"}"
            echo "   ${FIX}"
            found=0
          fi
          ;;
      esac
      rest="$after"
    done
  done < "$f"
  return "$found"
}

FIX_UNCHECKED="fix: end the assignment with || { echo \"❌ FAIL: <script>: cannot make a temp folder under \${TMPDIR:-/tmp}\" >&2; exit 1; } (or add set -e)"
UNCHECKED_RE='=\$?"?\$\((tmp_dir|tmp_file)[[:space:]]'
SET_E_RE='^[[:space:]]*set[[:space:]]+-[A-Za-z]*e'

# scan_unchecked <file>: one ❌ line per unchecked tmp_dir/tmp_file assignment
# in a shell script without set -e. Status 0 when it found one, 1 when none.
scan_unchecked() {
  local f="$1" n=0 line rest found=1
  case "$f" in *.yml | *.yaml) return 1 ;; esac
  if grep -qE "$SET_E_RE" "$f"; then
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    rest="${line#"${line%%[![:space:]]*}"}"
    case "$rest" in '#'* | 'if !'* | '! '*) continue ;; esac
    if [[ "$rest" =~ $UNCHECKED_RE ]] && [[ "$rest" != *'||'* ]]; then
      echo "❌ ${f}:${n}: a tmp_dir/tmp_file assignment is not checked, and this script has no set -e: a failure goes on with an empty path"
      echo "   ${rest}"
      echo "   ${FIX_UNCHECKED}"
      found=0
    fi
  done < "$f"
  return "$found"
}

files=0
bare_files=0
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  files=$((files + 1))
  if grep -qxF "$f" <<< "$EXEMPT"; then
    if ! scan "$f" > /dev/null; then
      echo "❌ bare mktemp: the exemption ${f} exempts no bare call; remove its line from ${EXEMPTIONS_FILE}"
      status=1
    fi
    continue
  fi
  if scan "$f"; then
    bare_files=$((bare_files + 1))
    status=1
  fi
  if scan_unchecked "$f"; then
    bare_files=$((bare_files + 1))
    status=1
  fi
done < <(collect_targets | sort -u)

if [ "$files" -eq 0 ]; then
  echo "❌ FAIL: bare mktemp: no shell script or workflow found under ${ROOT}; a scan over nothing is no pass" >&2
  exit 1
fi

# An exemption whose file is not among the scanned ones exempts nothing.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if ! grep -qxF "$p" <<< "$(collect_targets)"; then
    echo "❌ bare mktemp: the exemption ${p} is not a scanned shell script or workflow; remove its line from ${EXEMPTIONS_FILE}"
    status=1
  fi
done <<< "$EXEMPT"

if [ "$status" -ne 0 ]; then
  echo "❌ FAIL: bare mktemp: ${bare_files} file(s) with a call whose template has no path (see above)" >&2
else
  echo "OK: bare mktemp: every call in ${files} shell scripts and workflows has a path in its template"
fi
exit "$status"
