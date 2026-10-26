#!/usr/bin/env bash
# canon: check_pipe_grep_q v1
# Scripts/check_pipe_grep_q.sh [repo-root]
#
# Gate: red when a shell script pipes a producer into `grep -q`.
#
# Why. Under `set -o pipefail`, `producer | grep -q pattern` reads as "not
# found" when grep -q leaves at its first match and the producer, still
# writing, dies of SIGPIPE. It shows only once the producer writes more than
# the pipe buffer (about 16 KB), so the check passes until a file grows
# (forsgren#425: a test went on passing for the wrong reason when quality.yml
# reached 33 KB). The cure is Scripts/lib_has.sh: `producer | has -qE pattern`
# reads all of stdin before it matches (forsgren#428).
#
# The rule, per *.sh at the repository root and directly in Scripts/: a
# pipe into grep (or egrep) whose arguments hold a quiet flag, `-q` alone or
# inside a cluster (`-qE`, `-vqxF`, `-Fqi`, `-rq`), or `--quiet`/`--silent`,
# is red. A line that ends in a pipe or a backslash is read together with the
# next line, so `producer \
#   | grep -q x` is found. A comment line is not code and is not read. A
# `grep -q` that names a file or reads a here-string has no producer to kill
# and is fine. Known limit, on purpose: the text of a quoted string or a
# heredoc that looks like the pipe is read as code; a fixture that needs the
# text builds it from parts (see Scripts/test_check_pipe_grep_q.sh).
#
# Findings carry the red-cross marker, one per match, as file:line. Exit 0
# clean, 1 findings, 2 a missing root, and a root with no script at all is
# red: nothing scanned is not clean.
#
# Self-test: Scripts/test_check_pipe_grep_q.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"
ROOT="${1:-$REPO}"

if [ ! -d "$ROOT" ]; then
  echo "❌ FAIL: root dir not found: ${ROOT}"
  exit 2
fi

# PIPE_QUIET: a single pipe (not the two of ||), then grep or egrep, then any
# arguments up to a flag cluster holding q (or --quiet, --silent), none of them
# crossing another pipe, a semicolon, an ampersand or a closing parenthesis (so
# the -eq of a test after a command substitution is no flag).
PIPE_QUIET='(^|[^|])[|][[:space:]]*e?grep[[:space:]]+([^|;&)]*[[:space:]])?(-[A-Za-z]*q|--quiet|--silent)'

scanned=0
findings=0
for file in "$ROOT"/*.sh "$ROOT"/Scripts/*.sh; do
  [ -f "$file" ] || continue
  scanned=$((scanned + 1))
  hits="$(awk -v re="$PIPE_QUIET" '
    /^[[:space:]]*#/ { next }
    {
      if (stmt == "") { start = NR }
      stmt = stmt $0 " "
      if ($0 ~ /\\[[:space:]]*$/ || $0 ~ /[^|][|][[:space:]]*$/ || $0 ~ /^[|][[:space:]]*$/) { next }
      if (stmt ~ re) { print start }
      stmt = ""
    }
    END { if (stmt != "" && stmt ~ re) { print start } }
  ' "$file")"
  [ -n "$hits" ] || continue
  while IFS= read -r line; do
    echo "❌ FAIL: ${file#"$ROOT"/}:${line} pipes a producer into grep -q: under pipefail grep leaving" \
      "at its first match can kill the producer with SIGPIPE and a found pattern reads as missing" \
      "(use has from Scripts/lib_has.sh)"
    findings=$((findings + 1))
  done <<< "$hits"
done

if [ "$scanned" -eq 0 ]; then
  echo "❌ FAIL: no script found under ${ROOT}: nothing scanned is not clean"
  exit 1
fi

if [ "$findings" -ne 0 ]; then
  echo ""
  echo "pipe into grep -q: ${findings} place(s) in ${ROOT} can read a found pattern as missing."
  echo "Fix: source Scripts/lib_has.sh and write the pipe's end as has -q... instead of grep -q... (forsgren#428)."
  exit 1
fi

echo "OK: pipe into grep -q: ${scanned} script(s) scanned, none pipes a producer into grep -q"
exit 0
