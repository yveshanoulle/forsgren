#!/usr/bin/env bash
# check_script_references.sh [repo-root]
#
# Ported from another estate repository 2026-10-01 (forsgren#1, ladder step 13), from its
# lint/ script directory; "this repo" in the history below means another estate repository.
# forsgren's changes, each for forsgren's layout or file types:
#   1. Scope widened to forsgren's own files: besides the executable callers
#      (.sh, .py, .yml, and .yaml, which forsgren's yamllint also covers), the
#      FORWARD scan reads the order and tool files (.txt) and the docs (.md).
#      Yves wanted the guard to catch a dangling path in a doc or an order
#      file now, not later. A path that names ANOTHER repository's script
#      says so with that repository as its first component, and is skipped
#      (see the forward loop); a bare Scripts path is read as forsgren's own.
#   2. REVERSE callers are the executable files, the .txt order and tool
#      files (sfl dispatches every gate from the order file, so that row IS
#      the caller) and CLAUDE.md, where the scripts an agent runs by hand are
#      declared (forsgren is flat: there is no standalone directory to put
#      them in). Other prose is still no caller, as in another estate repository.
#   3. Resolution bases: forsgren runs everything from its root, so the
#      only base is the root; another estate repository's per-module bases do not exist here.
#      Leading dashes are stripped before resolving, so a default argument
#      written as a parameter expansion with a fallback is still checked.
#   4. The CLIMB ban is NOT ported: forsgren is flat, and every script finds
#      its root one level up by design. Yves ruled on it on forsgren#1
#      (step 15):
#        "Ruling (Yves, 2026-10-01): climb ban — N/A for forsgren, with a
#         flat-folder guard."
#        "This exception is valid only while `Scripts/` remains flat. The
#         script-reference gate must reject scripts in subdirectories.
#         Introducing a script below `Scripts/*/` requires revisiting this
#         ruling before that structure is accepted."
#      So this gate ENFORCES flatness (the FLAT check below): a script (.sh
#      or .py, the scripts this gate knows) one folder or more below
#      Scripts/ is red. A subfolder of scripts means revisiting the ruling
#      first, not widening this check. Data files in a subfolder are not
#      scripts, run nothing, and stay allowed.
#   5. Red on zero: a run that scanned no file, or extracted no Scripts
#      reference at all, is red and says so. Nothing scanned is not clean.
#   6. Findings carry the estate's red-cross marker, so sfl's failure summary
#      quotes them, and the root defaults to the repository's top level, not
#      to the working directory.
#   7. The case-sensitive listing is a glob instead of ls piped into grep, for
#      forsgren's shellcheck gate (see resolves_case_sensitively).
#
# Two-way integrity check over the repo's script directories. Written before
# the Scripts/ reorganisation (2026-08-17) so the move has a detector rather
# than a hope: a file moved without its callers updated, or a caller pointed at
# a path that no longer exists, fails here instead of silently skipping a gate.
#
# FORWARD  — every Scripts path mentioned by a scanned file resolves to a
#            file on disk, CASE-SENSITIVELY. Catches "moved the script, missed
#            a reference", and a lower-cased spelling the filesystem forgives.
# REVERSE  — every script under a script directory is mentioned by at least one
#            caller other than itself. Catches "moved the caller's reference,
#            orphaned the script" and, incidentally, genuinely dead scripts.
#
# Fixture files are excluded from the FORWARD scan: they build temp trees and
# name deliberately-nonexistent paths as their inputs, so
# scanning them reports the guard's own test data as broken references. They
# still count as CALLERS for the reverse check, which is what keeps a fixture's
# subject from looking unreferenced.
#
# A path resolves if it exists as written, OR with a leading ./ or ../ run
# stripped. Resolution keeps the guard about existence rather than about each
# relative path.
#
# The scan reads a path with subdirectories in it (Scripts/<owner>/<file>).
# It did not until 2026-08-17: the match was one segment after Scripts/, so
# every reference the reorganisation rewrote fell out of scope unseen. The
# guard did not go red, it went quiet — five subdirectories' worth of
# references were unchecked while it reported OK.
#
# Concrete example paths are deliberately absent from this header: the forward
# scan reads every scanned file including this one, and a doc example that
# looks like a path is reported as a broken reference. It has no way to tell an
# illustration from a call, which is the correct behaviour.
#
# Fixture: Scripts/test_check_script_references.sh.
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")" && git rev-parse --show-toplevel)}"
cd "$ROOT" || exit 2

# The one script hierarchy, flat in forsgren.
SCRIPT_DIRS="Scripts"

# Scripts run by hand, by design. They have no automated caller and are not
# meant to gain one, so the reverse check would otherwise be red on arrival.
#
# The DIRECTORY is the declaration in another estate repository: a hand-run script in
# Scripts/standalone is exempt from the reverse check. In forsgren that
# directory is a subfolder, so the FLAT check (change 4) makes any script in
# it red; the exemption is kept as ported and is dormant until the ruling is
# revisited. forsgren declares its hand-run scripts in CLAUDE.md instead (see
# change 2 above).
STANDALONE_DIR="Scripts/standalone"

# PERFORMANCE: both directions are driven by ONE tree scan each. The first
# implementation ran a grep per (script, caller) pair -- about 90 x 200 process
# spawns, 105 seconds. As an early sfl step that is a tax on every run, so the
# set logic moved into awk over a single pass.
scanned="$(find . -type f \( -name '*.sh' -o -name '*.py' -o -name '*.yml' -o -name '*.yaml' -o -name '*.txt' -o -name '*.md' \) \
  -not -path './.git/*' -not -path './.claude/*' -not -path '*/__pycache__/*' -not -path '*/node_modules/*' \
  -not -path './.build/*' -not -path '*/venv/*' -not -path '*/site-packages/*' \
  2>/dev/null | sort)"

# Callers for the reverse check: every scanned file except prose, with
# CLAUDE.md as the one prose caller (see change 2 above).
callers="$(printf '%s\n' "$scanned" | grep -vE '\.md$')"
if [ -f ./CLAUDE.md ]; then
  callers="$(printf '%s\n%s\n' "$callers" ./CLAUDE.md | grep -v '^$')"
fi

status=0

nscanned="$(printf '%s\n' "$scanned" | grep -c .)"
if [ "$nscanned" -eq 0 ]; then
  echo "❌ FAIL: script references scanned zero files under ${ROOT} — a scan over nothing is not a clean scan" >&2
  exit 1
fi

# ---------- FORWARD: every referenced path must resolve ----------
# Fixture files are skipped: they name deliberately-nonexistent paths as inputs.
# Case-sensitivity is the point of resolving component by component. macOS
# answers an existence test TRUE for a lower-cased spelling of a real
# directory, so seven such references were never checked (2026-08-17) and four broke
# the moment their targets moved. GitHub's path filters ARE case-sensitive, so
# the same spelling in a workflow `paths:` entry matches nothing while looking
# entirely correct.
#
# forsgren: the directory listing is a glob, not another estate repository's ls piped into
# grep (shellcheck SC2010, a warning forsgren's shellcheck gate is red on). A
# glob expands to the names as the directory stores them, and the test
# compares them case-sensitively, so the check is the same.
has_entry_verbatim() {
  local entry
  for entry in "$1"/* "$1"/.*; do
    [ "${entry##*/}" = "$2" ] && return 0
  done
  return 1
}

resolves_case_sensitively() {
  local path="$1" parent="." comp
  local oldifs="$IFS"
  IFS=/
  for comp in $path; do
    IFS="$oldifs"
    case "$comp" in ''|.) IFS=/; continue ;; esac
    if ! has_entry_verbatim "$parent" "$comp"; then
      IFS="$oldifs"
      return 1
    fi
    parent="${parent}/${comp}"
    IFS=/
  done
  IFS="$oldifs"
  return 0
}

# Extract CASE-INSENSITIVELY, resolve case-sensitively. That pairing is the
# whole trick: -i finds a lower-cased spelling of the directory, which a
# case-anchored pattern could never see, while resolution then rejects it.
# (No example is written out — this file is scanned by the very pattern below,
# and an illustration reads exactly like a call.) Widening the pattern to any
# path-like token instead was tried and abandoned — it pulls in third-party and
# documentation paths (urllib3/connection.py, typeshed/..., URLs in comments),
# which we neither own nor can verify.
refs="$(printf '%s\n' "$scanned" \
  | grep -v '/test_[^/]*$' \
  | tr '\n' '\0' \
  | xargs -0 grep -ohiE '[A-Za-z0-9_./-]*scripts/[A-Za-z0-9_./-]+\.(sh|py)' 2>/dev/null \
  | sort -u)"

if [ -z "$refs" ]; then
  echo "❌ FAIL: script references extracted zero Scripts paths from ${nscanned} file(s) — the extraction matched nothing, so nothing was checked" >&2
  exit 1
fi

for ref in $refs; do
  # Outside the repo, so not ours to verify: absolute paths, home-relative
  # prereqs, URLs.
  case "$ref" in
    /*|~*|*://*) continue ;;
  esac

  # Judge a caller that reaches up from its own directory against the
  # repo-relative path it means.
  stripped="${ref##*../}"
  stripped="${stripped#./}"
  # A default argument's fallback arrives with the expansion's dash glued on.
  while :; do
    case "$stripped" in -*) stripped="${stripped#-}" ;; *) break ;; esac
  done

  # ANOTHER repository's script names that repository as its first
  # component, and is not ours to verify. Only a first component that is not
  # the script directory itself and does not exist here reads that way; a
  # path under a directory forsgren has is checked like any other.
  first="${stripped%%/*}"
  case "$first" in
    [Ss][Cc][Rr][Ii][Pp][Tt][Ss]) ;;
    *) [ -e "$first" ] || continue ;;
  esac

  if ! resolves_case_sensitively "$stripped"; then
    echo "❌ UNRESOLVED REFERENCE: ${ref} — no such path (checked case-sensitively)" >&2
    status=1
  fi
done

# ---------- REVERSE: every script must have a caller other than itself ----------
# One scan produces "file:basename" pairs; awk then answers "is this basename
# mentioned in any file other than the script itself" without re-reading a
# thing. A script naming itself in a usage line is not a caller.
mentions_file="$(mktemp)"
trap 'rm -f "$mentions_file"' EXIT
printf '%s\n' "$callers" \
  | tr '\n' '\0' \
  | xargs -0 grep -oHE '[A-Za-z0-9_][A-Za-z0-9_.-]*\.(sh|py)' 2>/dev/null \
  > "$mentions_file"

scripts=""
for d in $SCRIPT_DIRS; do
  [ -d "$d" ] || continue
  found_here="$(find "$d" -type f \( -name '*.sh' -o -name '*.py' \) \
    -not -path '*/__pycache__/*' 2>/dev/null | sort)"
  scripts="$scripts
$found_here"
done

# Multi-line values cannot travel through awk -v (it rejects embedded
# newlines), so the pairs arrive as a file.
unreferenced="$(printf '%s\n' "$scripts" \
  | awk -v pairs="$mentions_file" -v standalone_dir="$STANDALONE_DIR" '
  BEGIN {
    while ((getline line < pairs) > 0) {
      pos = index(line, ":")
      if (pos == 0) continue
      file = substr(line, 1, pos - 1)
      name = substr(line, pos + 1)
      sub(/^\.\//, "", file)
      files[name] = files[name] " " file
    }
    close(pairs)
  }
  $0 == "" { next }
  {
    path = $0
    sub(/^\.\//, "", path)
    # Living in the standalone directory IS the declaration.
    if (index(path, standalone_dir "/") == 1) next
    nslash = split(path, parts, "/")
    base = parts[nslash]
    cited = 0
    cnt = split(files[base], fl, " ")
    for (i = 1; i <= cnt; i++) {
      if (fl[i] != "" && fl[i] != path) { cited = 1; break }
    }
    if (!cited) print path
  }
')"

if [ -n "$unreferenced" ]; then
  for u in $unreferenced; do
    echo "❌ UNREFERENCED SCRIPT: ${u} — no caller mentions it (an executable file, an order or tool file, or CLAUDE.md)" >&2
  done
  status=1
fi

# ---------- FLAT: no script below Scripts/*/ (forsgren#1, change 4) ----------
# The climb-ban exception holds only while Scripts/ is flat: every script
# reaches the root with one fixed step up. A script one folder down would
# reach a different directory with the same step, which is the relocation
# risk the ban exists for in another estate repository.
nested_scripts=""
if [ -d Scripts ]; then
  nested_scripts="$(find Scripts -mindepth 2 -type f \( -name '*.sh' -o -name '*.py' \) \
    -not -path '*/__pycache__/*' 2>/dev/null | sort)"
fi
if [ -n "$nested_scripts" ]; then
  for n in $nested_scripts; do
    echo "❌ SCRIPT IN SUBFOLDER: ${n} — scripts must sit directly under Scripts/ — the climb-ban exception holds only while Scripts/ is flat; see forsgren#1" >&2
  done
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "✅ script references: every referenced script exists, every script has a caller, and Scripts/ is flat (${nscanned} files scanned)"
fi
exit "$status"
