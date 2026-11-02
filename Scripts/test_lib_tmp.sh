#!/usr/bin/env bash
# canon: test_lib_tmp v2
# Scripts/test_lib_tmp.sh
#
# Self-test for Scripts/lib_tmp.sh, the helper every temp file and folder of
# this repository is made with. On macOS a mktemp whose template has no path
# (bare, or -t <prefix>) ignores TMPDIR and lands in the per-user folder
# `getconf DARWIN_USER_TEMP_DIR` names (/var/folders/..., the internal disk),
# even when TMPDIR points at the build volume. The helper puts the path in
# the template, so TMPDIR is honoured.
#
# Every case runs the helper in a child bash with TMPDIR pointed at a folder
# under this self-test's own temp root, and asserts the exit status AND the
# reason:
#   1. tmp_dir <name>: a new directory, directly in TMPDIR, named
#      <name>.XXXXXX (six random characters)
#   2. tmp_file <name>: a new regular file, the same way
#   3. two calls with one name: two different paths
#   4. a name with a slash (a/b, ../escape): exit 2, a ❌ line naming the
#      name, nothing created, nothing printed on stdout
#   5. an empty name, and no name at all: exit 2, a ❌ line
#   6. both functions template ${root}/<name>.XXXXXX, root is tmp__root, which
#      reads ${TMPDIR:-/tmp} (the /tmp default of an unset TMPDIR is read,
#      not run: no write outside TMPDIR)
#   7. a TMPDIR ending in a slash: both print the path with one slash, in
#      TMPDIR (v2)
# Mutation proofs (a weakened COPY of the helper, the reason asserted):
#   A. the TMPDIR prefix dropped from the template (`-t <name>`, the macOS
#      form that ignores TMPDIR): case 1 is red because the folder landed in
#      DARWIN_USER_TEMP_DIR, not in TMPDIR (the stray folder is removed)
#   B. the slash refusal dropped: case 4 is red because ../escape made a
#      folder outside TMPDIR
#   C. the trailing slashes kept (tmp__root strips nothing): case 7 is red
#      because the path has a double slash
set -euo pipefail

cd "$(dirname "$0")/.."

LIB="Scripts/lib_tmp.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "lib_tmp self-test"

[[ -f "$LIB" ]] || selftest_abort "${LIB} is missing: no case can run"

# run_helper <lib> <tmpdir> <function> [name...]: the helper in a child bash,
# TMPDIR set to <tmpdir>; stdout in OUT_STDOUT, stdout+stderr in OUT, the
# status in RC.
run_helper() {
  local lib="$1" dir="$2" fn="$3" errf="${TMP}/stderr"
  shift 3
  OUT_STDOUT="$(TMPDIR="$dir" bash -c 'source "$1"; shift; "$@"' _ "$lib" "$fn" "$@" 2>"$errf")" && RC=0 || RC=$?
  OUT="${OUT_STDOUT}$(cat "$errf")"
}

# landed_in <path> <dir>: <path> sits directly in <dir> (both resolved).
landed_in() {
  [[ "$(dirname "$(selftest_resolved "$1")")" == "$(selftest_resolved "$2")" ]]
}

# check_made <case> <kind -d|-f> <dir> <name>: the last run_helper exited 0
# and printed one new <kind> named <name>.XXXXXX directly in <dir>.
check_made() {
  local case="$1" kind="$2" dir="$3" name="$4" base
  base="$(basename "$OUT_STDOUT")"
  if [[ "$RC" -ne 0 ]]; then
    fail "${case}: the helper exited ${RC}. Output: ${OUT}"
  elif ! landed_in "$OUT_STDOUT" "$dir"; then
    fail "${case}: ${OUT_STDOUT} is not in TMPDIR ${dir}: it landed in $(dirname "$OUT_STDOUT")"
  elif ! test "$kind" "$OUT_STDOUT"; then
    fail "${case}: ${OUT_STDOUT} is not new and of the kind test ${kind} wants"
  elif ! [[ "$base" =~ ^${name}\.[A-Za-z0-9]{6}$ ]]; then
    fail "${case}: ${base} is not named ${name}.XXXXXX"
  else
    echo "  ok: ${case}"
  fi
}

# check_refused <case> <dir> <text>: the last run_helper exited 2, said ❌
# and <text>, printed no path, and created nothing in <dir> or beside it.
check_refused() {
  local case="$1" dir="$2" text="$3"
  if [[ "$RC" -ne 2 ]]; then
    fail "${case}: expected exit 2, got ${RC}. Output: ${OUT}"
  elif [[ "$OUT" != *"❌"* || "$OUT" != *"$text"* ]]; then
    fail "${case}: exit 2 without a ❌ line naming '${text}'. Output: ${OUT}"
  elif [[ -n "$OUT_STDOUT" ]]; then
    fail "${case}: a refused name printed a path: ${OUT_STDOUT}"
  elif [[ -n "$(find "$(dirname "$dir")" -mindepth 1 ! -path "$dir")" ]]; then
    fail "${case}: a refused name created something: $(find "$(dirname "$dir")" -mindepth 1 ! -path "$dir")"
  else
    echo "  ok: ${case}"
  fi
}

# fresh_tmpdir <label>: an empty folder alone in its own parent, so a name
# that escapes it (../x) shows up beside it.
fresh_tmpdir() {
  mkdir -p "${TMP}/case_$1/tmpdir"
  printf '%s\n' "${TMP}/case_$1/tmpdir"
}

# 1. tmp_dir
D1="$(fresh_tmpdir dir)"
run_helper "$LIB" "$D1" tmp_dir lib_tmp_case
check_made "tmp_dir makes a new directory named <name>.XXXXXX in TMPDIR" -d "$D1" lib_tmp_case

# 2. tmp_file
D2="$(fresh_tmpdir file)"
run_helper "$LIB" "$D2" tmp_file lib_tmp_case
check_made "tmp_file makes a new regular file named <name>.XXXXXX in TMPDIR" -f "$D2" lib_tmp_case

# 3. two calls, two paths
D3="$(fresh_tmpdir twice)"
run_helper "$LIB" "$D3" tmp_dir same
first="$OUT_STDOUT"
run_helper "$LIB" "$D3" tmp_dir same
if [[ "$RC" -eq 0 && -n "$first" && "$first" != "$OUT_STDOUT" ]]; then
  echo "  ok: two calls with one name make two different paths"
else
  fail "two calls with one name: '${first}' and '${OUT_STDOUT}' (exit ${RC})"
fi

# 4. a slash in the name
for name in "a/b" "../escape"; do
  for fn in tmp_dir tmp_file; do
    D4="$(fresh_tmpdir "slash_${fn}_${name//[^a-z]/_}")"
    run_helper "$LIB" "$D4" "$fn" "$name"
    check_refused "${fn} refuses the name '${name}' (a slash)" "$D4" "$name"
  done
done

# 5. an empty name, no name
for fn in tmp_dir tmp_file; do
  D5="$(fresh_tmpdir "empty_${fn}")"
  run_helper "$LIB" "$D5" "$fn" ""
  check_refused "${fn} refuses an empty name" "$D5" "empty"
  run_helper "$LIB" "$D5" "$fn"
  check_refused "${fn} refuses a missing name" "$D5" "empty"
done

# 6. the template is the TMPDIR form, with /tmp only as the unset default
if grep -qF "mktemp -d \"\${root}/\${1}.XXXXXX\"" "$LIB" && grep -qF "mktemp \"\${root}/\${1}.XXXXXX\"" "$LIB" && grep -qF "root=\"\$(tmp__root)\"" "$LIB" && grep -qF "local root=\"\${TMPDIR:-/tmp}\"" "$LIB"; then
  echo "  ok: both functions template \${root}/<name>.XXXXXX from tmp__root, and tmp__root reads \${TMPDIR:-/tmp}"
else
  fail "${LIB} does not template \${root}/<name>.XXXXXX from tmp__root in both functions with tmp__root reading \${TMPDIR:-/tmp}"
fi

# 7. a TMPDIR that ends in a slash (the macOS default, /var/folders/.../T/):
# the path has no double slash. A path with // is the same folder to the file
# system, but not to a tool that compares it as text: node's path.join writes
# it with one slash, so pgrep -f on the self-test's own path found no Chrome
# (v2).
D7="$(fresh_tmpdir trailing)"
for fn in tmp_dir tmp_file; do
  run_helper "$LIB" "${D7}/" "$fn" lib_tmp_trailing
  if [[ "$RC" -ne 0 ]]; then
    fail "${fn} with TMPDIR ending in a slash: the helper exited ${RC}. Output: ${OUT}"
  elif [[ "$OUT_STDOUT" == *//* ]]; then
    fail "${fn} with TMPDIR ending in a slash printed a path with a double slash: ${OUT_STDOUT}"
  elif ! landed_in "$OUT_STDOUT" "$D7"; then
    fail "${fn} with TMPDIR ending in a slash: ${OUT_STDOUT} is not in TMPDIR ${D7}"
  else
    echo "  ok: ${fn} with TMPDIR ending in a slash prints the path with one slash"
  fi
done

# --- Mutation proofs.
USER_TEMP="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"

# A. the TMPDIR prefix dropped: macOS puts the folder in DARWIN_USER_TEMP_DIR.
MA="${TMP}/mutant_A/lib_tmp.sh"
if selftest_mutant "$LIB" "$MA" "s#mktemp -d \"\${root}/\${1}.XXXXXX\"#mktemp -d -t \"\${1}\"#"; then
  DA="$(fresh_tmpdir mutant_A)"
  run_helper "$MA" "$DA" tmp_dir lib_tmp_mutant
  stray="$OUT_STDOUT"
  if [[ "$RC" -eq 0 && -n "$USER_TEMP" ]] && ! landed_in "$stray" "$DA" && landed_in "$stray" "$USER_TEMP"; then
    echo "  ok: mutation proof A: a helper without the TMPDIR prefix lands in DARWIN_USER_TEMP_DIR (${USER_TEMP}), not in TMPDIR, so case 1 is red for it"
  else
    fail "mutation proof A: the helper without the TMPDIR prefix did not land in DARWIN_USER_TEMP_DIR '${USER_TEMP}' (exit ${RC}, ${stray}), so case 1 proves nothing"
  fi
  # The mutant's stray folder is outside this self-test's root: remove it, and
  # only it (a fresh, empty folder named by the mutant).
  if [[ -n "$stray" && -d "$stray" && "$(basename "$stray")" == lib_tmp_mutant.* ]]; then
    rmdir "$stray"
  fi
fi

# B. the slash refusal dropped: ../escape lands beside TMPDIR.
MB="${TMP}/mutant_B/lib_tmp.sh"
if selftest_mutant "$LIB" "$MB" '/\*\/\*)/,/;;/d'; then
  DB="$(fresh_tmpdir mutant_B)"
  run_helper "$MB" "$DB" tmp_dir "../escape"
  if [[ "$RC" -eq 0 ]] && ! landed_in "$OUT_STDOUT" "$DB"; then
    echo "  ok: mutation proof B: a helper that accepts a slash makes ${OUT_STDOUT##"${TMP}"/} outside TMPDIR, and case 4 catches it"
  else
    fail "mutation proof B: the helper that accepts a slash did not escape TMPDIR (exit ${RC}, ${OUT_STDOUT}), so case 4 proves nothing"
  fi
fi

# C. the trailing slashes kept: the path has a double slash.
MC="${TMP}/mutant_C/lib_tmp.sh"
if selftest_mutant "$LIB" "$MC" 's#root="[$]{root%/}"#break#'; then
  DC="$(fresh_tmpdir mutant_C)"
  run_helper "$MC" "${DC}/" tmp_dir lib_tmp_mutant_c
  if [[ "$RC" -eq 0 && "$OUT_STDOUT" == *//* ]]; then
    echo "  ok: mutation proof C: a helper that keeps the trailing slash prints a double slash, and case 7 catches it"
  else
    fail "mutation proof C: the helper that keeps the trailing slash printed no double slash (exit ${RC}, ${OUT_STDOUT}), so case 7 proves nothing"
  fi
fi

selftest_end "lib_tmp does not hold its contract" \
  "lib_tmp: tmp_dir and tmp_file make <name>.XXXXXX in TMPDIR and refuse an empty name or a slash (exit 2), with one slash after a TMPDIR that ends in one; without the TMPDIR prefix the path lands in DARWIN_USER_TEMP_DIR, and with a slash it escapes TMPDIR (each proved against a weakened helper)"
