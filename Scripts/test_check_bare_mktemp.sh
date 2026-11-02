#!/usr/bin/env bash
# canon: test_check_bare_mktemp v2
# Scripts/test_check_bare_mktemp.sh
#
# Self-test for Scripts/check_bare_mktemp.sh, the gate that keeps every temp
# path under TMPDIR. On macOS a mktemp whose template has no path (bare, or
# -t <prefix>) ignores TMPDIR and writes to /var/folders on the internal disk.
#
# The fixtures are synthetic git trees (BARE_MKTEMP_ROOT). The command word is
# spelled through MK below, never literally in a call, so this self-test is
# not itself a finding of the gate it tests.
#
# Each case asserts the exit status AND the reason:
#   1. a bare call, `-d` alone, `-t <prefix>`, a template without a path
#      (name.XXXXXX), `-p <dir>`: each red, named <file>:<line> with the fix
#   2. the same bare call in a workflow (.github/workflows/*.yml), in an
#      extension-less script with a bash shebang, and in an untracked,
#      not-ignored script: each red, named
#   3. two calls on one line, the first templated, the second bare: red
#   4. the templated forms ("${TMPDIR:-/tmp}/x", "$TMPDIR/x", "/abs/x",
#      "$VAR/x", "${VAR}/x", "$1/x", options before the template), the
#      helper (tmp_dir, tmp_file), a comment and a sentence that only name
#      the command: green, with the OK line
#   5. a bare call in an ignored file: green (git will never commit it)
#   6. a tree with no shell script or workflow: red, never a green over nothing
#   7. the exemption list: a reasoned entry exempts its file (green); an entry
#      without a reason, a path that is no file, an entry that exempts no bare
#      call and a missing list are each red, named
#   8. this repository, as it is: green
# Mutation proofs (a weakened COPY of the gate turns a red case green, the
# reason asserted by running the case the weakening defeats):
#   A. the exit status swallowed: case 1
#   B. the -t rule dropped: the -t fixture of case 1
#   C. any template accepted as a path: the name.XXXXXX fixture of case 1
#   D. workflows left out of the listing: the workflow of case 2
#   E. only the first call of a line judged: case 3
#   F. a missing exemption list read as empty: case 7
#
# v2 (found in another estate repository): it sources
# Scripts/lib_git_sandbox.sh, so an exported GIT_DIR cannot send the
# fixtures' git into the caller's repository (the git sandbox guard of that
# repository was red on v1).
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

GATE="Scripts/check_bare_mktemp.sh"
MK='mk''temp'

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "bare mktemp self-test"

[[ -f "$GATE" ]] || selftest_abort "${GATE} is missing: no case can run"
GATE_ABS="$(pwd)/${GATE}"

# new_tree <name>: an empty git work tree under TMP; prints its path.
new_tree() {
  local dir="${TMP}/tree_$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf '%s\n' "$dir"
}

# put <tree> <path> <content> [track]: writes a file; "track" stages it.
put() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
  chmod +x "$1/$2"
  if [[ "${4:-}" == track ]]; then git -C "$1" add "$2"; fi
}

# run_gate <tree> [gate]: the gate (default the real one) on <tree>.
run_gate() {
  capture env BARE_MKTEMP_ROOT="$1" bash "${2:-$GATE_ABS}"
}

# gate_copy <dir> <exemptions|->: a plain copy of the gate with its lib and
# its own exemption list ("-" for none); prints the copy's path.
gate_copy() {
  mkdir -p "$1/Scripts"
  cp "$GATE" Scripts/lib_repo_files.sh "$1/Scripts/"
  rm -f "$1/Scripts/bare_mktemp_exemptions.txt"
  if [[ "$2" != "-" ]]; then printf '%s' "$2" > "$1/Scripts/bare_mktemp_exemptions.txt"; fi
  printf '%s\n' "$1/Scripts/check_bare_mktemp.sh"
}

# mutant <label> <sed-expression>: a weakened copy of the gate with its lib
# and an empty exemption list; sets MUTANT, status 1 when the sed changed nothing.
mutant() {
  local home="${TMP}/mutant_$1/Scripts"
  mkdir -p "$home"
  cp Scripts/lib_repo_files.sh "$home/"
  : > "$home/bare_mktemp_exemptions.txt"
  MUTANT="$home/check_bare_mktemp.sh"
  selftest_mutant "$GATE" "$MUTANT" "$2"
}

# mutant_proof <label> <sed> <tree> <ok text>: the weakened copy is green on
# a tree the real gate is red on.
mutant_proof() {
  if mutant "$1" "$2"; then
    run_gate "$3" "$MUTANT"
    if [[ "$RC" -eq 0 ]]; then
      echo "  ok: mutation proof $1: $4"
    else
      fail "mutation proof $1: the weakened copy stayed red (exit ${RC}), so the case is not red for the stated reason. Output: ${OUT}"
    fi
  fi
}

SHEBANG='#!/usr/bin/env bash'

# 1. bare forms, one per tree, each red, named, with the fix.
# declare_red <var> <label> <line> <reason>: a tree whose Scripts/a.sh has
# <line> on line 3; the gate must be red there for <reason>. The tree's path
# goes in <var> (no command substitution: a failed case must reach `failed`).
declare_red() {
  local label="$2" line="$3" why="$4" tree
  tree="$(new_tree "red_${label}")"
  put "$tree" "Scripts/a.sh" "${SHEBANG}
echo start
${line}" track
  run_gate "$tree"
  want_red "case 1 ${label}: red, named Scripts/a.sh:3" "Scripts/a.sh:3:"
  want_said "case 1 ${label}: the reason is given" "$why"
  want_said "case 1 ${label}: the fix is given" "tmp_dir <name>"
  printf -v "$1" '%s' "$tree"
}
declare_red T_BARE bare "x=\"\$(${MK})\"" "no template"
declare_red T_D dir "x=\"\$(${MK} -d)\"" "no template"
declare_red T_T0 prefix "x=\"\$(${MK} -t acme)\"" "-t"
# -t with a path-looking prefix: only the -t rule makes it red (mutation B).
declare_red T_T prefix_path "x=\"\$(${MK} -t \"\${TMPDIR:-/tmp}/acme\")\"" "-t"
declare_red T_NAME nopath "x=\"\$(${MK} -d name.XXXXXX)\"" "does not start with a path"
declare_red T_P pdir "x=\"\$(${MK} -p \"\$TMPDIR\" name.XXXXXX)\"" "-p"
declare_red T_BACKTICK backtick "x=\`${MK}\`" "no template"

# 2. a workflow, an extension-less script, an untracked script.
T_WF="$(new_tree workflow)"
put "$T_WF" "Scripts/ok.sh" "${SHEBANG}
echo fine" track
put "$T_WF" ".github/workflows/q.yml" "on: push
jobs:
  j:
    steps:
      - run: |
          d=\"\$(${MK} -d)\"" track
run_gate "$T_WF"
want_red "case 2 a bare call in a workflow: red, named" ".github/workflows/q.yml:6:"

T_EXT="$(new_tree extensionless)"
put "$T_EXT" "bin/tool" "${SHEBANG}
f=\"\$(${MK})\"" track
run_gate "$T_EXT"
want_red "case 2 a bare call in an extension-less bash script: red, named" "bin/tool:2:"

T_UNTRACKED="$(new_tree untracked)"
put "$T_UNTRACKED" "Scripts/ok.sh" "${SHEBANG}
echo fine" track
put "$T_UNTRACKED" "Scripts/new.sh" "${SHEBANG}
f=\"\$(${MK} -d)\""
run_gate "$T_UNTRACKED"
want_red "case 2 a bare call in an untracked, not-ignored script: red, named" "Scripts/new.sh:2:"

# 3. two calls on one line, the second bare.
T_TWO="$(new_tree two_calls)"
put "$T_TWO" "Scripts/a.sh" "${SHEBANG}
a=\"\$(${MK} -d \"\${TMPDIR:-/tmp}/a.XXXXXX\")\"; b=\"\$(${MK})\"" track
run_gate "$T_TWO"
want_red "case 3 the second, bare call of a line: red, named" "Scripts/a.sh:2:"

# 4. the templated forms, the helper, a comment and a sentence: green.
T_GREEN="$(new_tree green)"
put "$T_GREEN" "Scripts/a.sh" "${SHEBANG}
# a bare ${MK} in a comment is no call
a=\"\$(${MK} -d \"\${TMPDIR:-/tmp}/a.XXXXXX\")\"
b=\"\$(${MK} \"\$TMPDIR/b.XXXXXX\")\"
c=\"\$(${MK} -d \"/abs/c.XXXXXX\")\"
d=\"\$(${MK} -d \"\$TMP/d.XXXXXX\")\"
e=\"\$(${MK} -d \"\${TMP}/e.XXXXXX\")\"
f=\"\$(${MK} \"\$1/.f.XXXXXX\" 2>/dev/null)\" || true
g=\"\$(${MK} -q -d \"\${TMPDIR:-/tmp}/g.XXXXXX\")\"
h=\"\$(tmp_dir h)\"
i=\"\$(tmp_file i)\"
echo \"a bare ${MK} call is red\"
echo \"\$a\$b\$c\$d\$e\$f\$g\$h\$i\"" track
put "$T_GREEN" ".github/workflows/q.yml" "on: push
jobs:
  j:
    steps:
      - run: |
          d=\"\$(${MK} -d \"\${RUNNER_TEMP}/d.XXXXXX\")\"" track
run_gate "$T_GREEN"
want_green "case 4 the templated forms, the helper, a comment and a sentence: green" "OK:"

# 5. an ignored file.
T_IGN="$(new_tree ignored)"
put "$T_IGN" "Scripts/ok.sh" "${SHEBANG}
echo fine" track
put "$T_IGN" ".gitignore" "scratch/" track
put "$T_IGN" "scratch/x.sh" "${SHEBANG}
f=\"\$(${MK})\""
run_gate "$T_IGN"
want_green "case 5 a bare call in an ignored file: green" "OK:"

# 6. nothing to scan.
T_NONE="$(new_tree none)"
put "$T_NONE" "README.md" "no shell here" track
run_gate "$T_NONE"
want_red "case 6 a tree with no shell script or workflow: red" "no shell script or workflow"

# 7. the exemption list.
T_EX="$(new_tree exempt)"
put "$T_EX" "Scripts/legacy.sh" "${SHEBANG}
f=\"\$(${MK})\"" track
copy="$(gate_copy "${TMP}/copy_reasoned" "# path|reason
Scripts/legacy.sh|a reasoned fixture entry
")"
run_gate "$T_EX" "$copy"
want_green "case 7 a reasoned entry exempts its file" "OK:"
copy="$(gate_copy "${TMP}/copy_empty" "")"
run_gate "$T_EX" "$copy"
want_red "case 7 the same file without its entry: red, named" "Scripts/legacy.sh:2:"
copy="$(gate_copy "${TMP}/copy_noreason" "Scripts/legacy.sh|
")"
run_gate "$T_EX" "$copy"
want_red "case 7 an entry without a reason: red, named" "Scripts/legacy.sh|"
copy="$(gate_copy "${TMP}/copy_nofile" "Scripts/gone.sh|a reason
")"
run_gate "$T_EX" "$copy"
want_red "case 7 an entry whose path is no file: red, named" "Scripts/gone.sh"
put "$T_EX" "Scripts/clean.sh" "${SHEBANG}
echo fine" track
copy="$(gate_copy "${TMP}/copy_stale" "Scripts/legacy.sh|a reason
Scripts/clean.sh|a reason that no longer holds
")"
run_gate "$T_EX" "$copy"
want_red "case 7 an entry that exempts no bare call: red, named" "Scripts/clean.sh exempts no bare"
copy="$(gate_copy "${TMP}/copy_missing" "-")"
run_gate "$T_EX" "$copy"
want_red "case 7 a missing exemption list: red, named" "bare_mktemp_exemptions.txt is missing"

# 8. this repository.
capture bash "$GATE_ABS"
want_green "case 8 this repository has no bare call" "OK:"

# --- Mutation proofs.
mutant_proof A 's/^exit "[$]status"$/exit 0/' "$T_BARE" \
  "a gate that swallows its exit status turns case 1 green"
mutant_proof B 's/^      \*t\*) echo .*/      *t*) ;;/' "$T_T" \
  "a gate without the -t rule lets -t <prefix> through, so the -t rule is what catches it"
mutant_proof C 's/^PATH_RE=.*/PATH_RE=".*"/' "$T_NAME" \
  "a gate that takes any template as a path lets name.XXXXXX through, so the path rule is what catches it"
mutant_proof D "s#'.github/workflows/\\*.yml' '.github/workflows/\\*.yaml'##" "$T_WF" \
  "a gate that lists no workflow lets the workflow call through, so the listing is what catches it"
mutant_proof E 's/^      rest="[$]after"$/      rest=""/' "$T_TWO" \
  "a gate that judges only the first call of a line lets the second through, so case 3 is what catches it"
# F: the missing-list check and the read of the list both neutralised, so a
# copy with no list runs; on a clean tree it must go green.
if mutant F 's/^if \[ ! -f "[$]EXEMPTIONS_FILE" \]; then$/if false; then/;s#^done < "[$]EXEMPTIONS_FILE"$#done < /dev/null#'; then
  rm -f "${TMP}/mutant_F/Scripts/bare_mktemp_exemptions.txt"
  run_gate "$T_GREEN" "$MUTANT"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof F: a gate that reads a missing list as empty goes green without it, so the missing-list case of 7 is what catches it"
  else
    fail "mutation proof F: the weakened copy stayed red (exit ${RC}). Output: ${OUT}"
  fi
fi

selftest_end "the bare mktemp gate does not hold its contract" \
  "check_bare_mktemp: a call without a path in its template (bare, -d, -t, -p, name.XXXXXX) is red with file:line and the fix, in scripts, extension-less scripts, workflows and untracked files; templated calls and the lib_tmp helper are green; the exemption list is reasoned and fail closed (each proved against a weakened gate)"
