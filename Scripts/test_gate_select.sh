#!/usr/bin/env bash
# Scripts/test_gate_select.sh (forsgren#262, step 2 of 3). Not canon: forsgren only.
#
# Self-test for gate_select in Scripts/lib_gate_select.sh. The real library runs in
# a throwaway repository with a made-up list of two gates, alpha (inputs:
# Scripts/alpha.sh and src/, but not src/*_test.go or src/**/testdata/) and beta
# (inputs: Scripts/beta.sh and data/), and an origin that holds the fixture:
#    1. nothing changed                          -> skip, both
#    2. a file under alpha's directory           -> alpha runs, naming it; beta skips
#    3. beta's script                            -> beta runs; alpha skips
#    4. a _test.go under alpha's directory       -> skip, both (excluded, not unknown)
#    5. a testdata file under alpha's directory  -> skip, both
#    6. a file no list names (FAIL-SAFE)         -> run, both, naming the file
#    7. a markdown file                          -> skip, both
#    8. an untracked new file under alpha's dir  -> alpha runs
#    9. a staged change                          -> alpha runs
#   10. a committed change not yet on origin     -> alpha runs
#   11. GITHUB_ACTIONS=true, nothing changed     -> run, Quality
#   12. FORSGREN_GATE_SELECT_FULL=1              -> run, forced
#   13. no origin/main                           -> run, naming why
#   14. a label with no list                     -> run, naming why
# Mutation proofs (each is wrong BECAUSE of the line mutated; the mutant must no
# longer say the reason the real library gives):
#   A. the Quality path removed:            case 11 loses "Quality runs every gate";
#   B. the forced path removed:             case 12 loses "FORSGREN_GATE_SELECT_FULL=1";
#   C. a missing origin/main not handled:   case 13 loses "no origin/main";
#   D. the fail-safe removed:               case 6 loses "named by no gate's list";
#   E. the out patterns ignored for a gate: case 4 loses its skip;
#   F. out files counted as unknown:        case 4 runs every gate instead of skipping;
#   G. a listed directory not covering its files: case 2 loses its run;
#   H. untracked files ignored:             case 8 loses its run;
#   I. no `none` rows in the list:          case 16a runs because the workflow is named by no list;
#   J. the Scripts/ closure check removed:  case 21 loses its run for a script in a closure.
#   K. the sfl.sh row removed from the real list: case 22 runs every browser row
#      again, because sfl.sh is named by no list (forsgren#284).
# Cases 16-21: a workflow, a docs file, a release script and a script in no gate's
# closure select nothing; a new top-level file, and a script in a closure that the
# list forgot, select every gate (the fail-safe).
# Cases 22-24 (forsgren#284) run on the real Scripts/gate_inputs.txt: a commit that
# changes only sfl.sh, or only FBP.sh, skips all four browser rows with the reason,
# and a file no list names still runs all four (the fail-safe).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_gate_select.sh
source Scripts/lib_gate_select.sh
selftest_begin "gate select self-test"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
G=(git -c user.name=fixture -c user.email=fixture@example.test)

FX="${TMP}/fx"
ORIGIN="${TMP}/origin.git"
git init -q --bare "$ORIGIN"
git init -q -b main "$FX"
mkdir -p "${FX}/Scripts" "${FX}/src/sub" "${FX}/data" "${FX}/other" "${FX}/.github/workflows" "${FX}/docs"
cp Scripts/lib_gate_select.sh "${FX}/Scripts/"
cat > "${FX}/Scripts/gate_inputs.txt" <<'EOF'
# fixture list
alpha|in|Scripts/alpha.sh
alpha|in|src/
alpha|out|*_test.go
alpha|out|src/**/testdata/
beta|in|Scripts/beta.sh
beta|in|data/
none|out|.github/**
none|out|docs/**
none|out|*.md
none|out|Scripts/release_*.sh
EOF
cat > "${FX}/Scripts/gate_report_order.txt" <<'EOF'
alpha|Scripts/alpha.sh|pre|
beta|Scripts/beta.sh|post|
EOF
printf 'echo alpha\nbash Scripts/helper.sh\n' > "${FX}/Scripts/alpha.sh"
echo 'echo helper' > "${FX}/Scripts/helper.sh"
echo 'echo other check' > "${FX}/Scripts/check_other.sh"
echo 'echo release' > "${FX}/Scripts/release_x.sh"
echo 'on: push' > "${FX}/.github/workflows/w.yml"
echo 'guide' > "${FX}/docs/guide.txt"
echo 'echo beta' > "${FX}/Scripts/beta.sh"
echo 'package src' > "${FX}/src/a.go"
echo 'x' > "${FX}/data/d.csv"
echo 'x' > "${FX}/other/o.txt"
echo 'notes' > "${FX}/NOTES.md"
echo 'echo sfl' > "${FX}/sfl.sh"
echo 'echo fbp' > "${FX}/FBP.sh"
"${G[@]}" -C "$FX" add -A
"${G[@]}" -C "$FX" commit -q -m fixture
git -C "$FX" remote add origin "$ORIGIN"
git -C "$FX" push -q origin main
git -C "$FX" fetch -q origin

# reset: the fixture back to what origin/main holds.
reset() {
  git -C "$FX" reset -q --hard origin/main
  git -C "$FX" clean -q -fd
}
# drive: runs gate_select of a library in the fixture, as a child, the way a gate would.
cat > "${TMP}/drive.sh" <<'DRIVER'
cd "$1" || exit 1
source "$2"
gate_select "$3"
DRIVER
# sel <label> [lib]: gate_select of the fixture, in a clean environment.
sel() {
  capture env -u GITHUB_ACTIONS -u FORSGREN_GATE_SELECT_FULL -u FORSGREN_GATE_INPUTS bash "${TMP}/drive.sh" "$FX" "${2:-Scripts/lib_gate_select.sh}" "$1"
}

sel alpha
want_exit "1a: nothing changed, alpha" 0 "skip: none of the 0 changed files is an input of alpha"
sel beta
want_exit "1b: nothing changed, beta" 0 "skip: none of the 0 changed files is an input of beta"

echo 'package src // edit' >> "${FX}/src/a.go"
sel alpha
want_exit "2a: a file under alpha's directory, alpha" 0 "run: src/a.go is an input of alpha"
sel beta
want_exit "2b: the same change, beta" 0 "skip: none of the 1 changed files is an input of beta"
reset

echo '# edit' >> "${FX}/Scripts/beta.sh"
sel beta
want_exit "3a: beta's script, beta" 0 "run: Scripts/beta.sh is an input of beta"
sel alpha
want_exit "3b: beta's script, alpha" 0 "skip: none of the 1 changed files is an input of alpha"
reset

echo 'package src' > "${FX}/src/a_test.go"
"${G[@]}" -C "$FX" add src/a_test.go
sel alpha
want_exit "4a: a _test.go under alpha's directory, alpha" 0 "skip: none of the 1 changed files is an input of alpha"
sel beta
want_exit "4b: the same file, beta" 0 "skip: none of the 1 changed files is an input of beta"
reset

echo 'package other' > "${FX}/other/x_test.go"
sel alpha
want_exit "4c: a _test.go no list covers (excluded, so not unknown), alpha" 0 "skip: none of the 1 changed files is an input of alpha"
sel beta
want_exit "4d: the same file, beta" 0 "skip: none of the 1 changed files is an input of beta"
reset

mkdir -p "${FX}/src/sub/testdata"
echo 'golden' > "${FX}/src/sub/testdata_x"
echo 'golden' > "${FX}/src/sub/testdata/x.golden"
sel alpha
want_exit "5a: testdata and a name that only contains it, alpha" 0 "run: src/sub/testdata_x is an input of alpha"
rm -f "${FX}/src/sub/testdata_x"
sel alpha
want_exit "5b: a testdata file alone, alpha" 0 "skip: none of the 1 changed files is an input of alpha"
sel beta
want_exit "5c: a testdata file alone, beta" 0 "skip: none of the 1 changed files is an input of beta"
reset

echo 'x' >> "${FX}/other/o.txt"
sel alpha
want_exit "6a: a file no list names, alpha" 0 "run: other/o.txt is named by no gate's list, so every gate runs"
sel beta
want_exit "6b: a file no list names, beta" 0 "run: other/o.txt is named by no gate's list, so every gate runs"
reset

echo 'more' >> "${FX}/NOTES.md"
sel alpha
want_exit "7: a markdown file" 0 "skip: none of the 0 changed files is an input of alpha"
reset

echo 'package src' > "${FX}/src/new.go"
sel alpha
want_exit "8: an untracked new file under alpha's directory" 0 "run: src/new.go is an input of alpha"
reset

echo 'package src // staged' >> "${FX}/src/a.go"
"${G[@]}" -C "$FX" add src/a.go
sel alpha
want_exit "9: a staged change" 0 "run: src/a.go is an input of alpha"
reset

echo 'package src // committed' >> "${FX}/src/a.go"
"${G[@]}" -C "$FX" commit -q -a -m "not yet on origin"
sel alpha
want_exit "10: a committed change not yet on origin" 0 "run: src/a.go is an input of alpha"
reset

capture env -u FORSGREN_GATE_SELECT_FULL GITHUB_ACTIONS=true bash "${TMP}/drive.sh" "$FX" Scripts/lib_gate_select.sh alpha
want_exit "11: GITHUB_ACTIONS=true, nothing changed" 0 "run: full run (Quality runs every gate)"

capture env -u GITHUB_ACTIONS FORSGREN_GATE_SELECT_FULL=1 bash "${TMP}/drive.sh" "$FX" Scripts/lib_gate_select.sh alpha
want_exit "12: FORSGREN_GATE_SELECT_FULL=1, nothing changed" 0 "run: full run (FORSGREN_GATE_SELECT_FULL=1)"

git -C "$FX" update-ref -d refs/remotes/origin/main
sel alpha
want_exit "13: no origin/main" 0 "run: full run (no origin/main to compare against)"
git -C "$FX" fetch -q origin

sel gamma
want_exit "14: a label with no list" 0 "run: gamma has no input list in Scripts/gate_inputs.txt"


# 16-21: the files that are known to be unrelated select nothing.
echo '# edit' >> "${FX}/.github/workflows/w.yml"
sel alpha
want_exit "16a: a workflow only, alpha" 0 "skip: none of the 1 changed files is an input of alpha"
sel beta
want_exit "16b: a workflow only, beta" 0 "skip: none of the 1 changed files is an input of beta"
reset

echo 'more' >> "${FX}/docs/guide.txt"
sel alpha
want_exit "17: a docs file only" 0 "skip: none of the 1 changed files is an input of alpha"
reset

echo '# edit' >> "${FX}/Scripts/release_x.sh"
sel alpha
want_exit "18: a release script only" 0 "skip: none of the 1 changed files is an input of alpha"
reset

echo '# edit' >> "${FX}/Scripts/check_other.sh"
sel alpha
want_exit "19a: a script in no gate's closure, alpha" 0 "skip: none of the 1 changed files is an input of alpha"
sel beta
want_exit "19b: a script in no gate's closure, beta" 0 "skip: none of the 1 changed files is an input of beta"
reset

echo 'x' > "${FX}/newtop.txt"
sel alpha
want_exit "20a: a new top-level file, alpha (fail-safe)" 0 "run: newtop.txt is named by no gate's list, so every gate runs"
sel beta
want_exit "20b: a new top-level file, beta (fail-safe)" 0 "run: newtop.txt is named by no gate's list, so every gate runs"
reset

echo '# edit' >> "${FX}/Scripts/helper.sh"
sel beta
want_exit "21: a script in alpha's closure that its list forgot (fail-safe)" 0 "run: Scripts/helper.sh is named by no gate's list, so every gate runs"
reset

# 22-24 (forsgren#284): the real list, in the fixture. A commit that changes only
# sfl.sh, or only FBP.sh, skips all four browser rows with the reason; a file no
# list names still runs all four (the fail-safe holds on the real list too).
REAL_INPUTS="${REPO_ROOT}/Scripts/gate_inputs.txt"
BROWSER_LABELS=("browser gate self-test" "browser gate" "browser gate (fixture site) self-test" "browser gate (fixture site)")
# sel_real <label> [inputs-file]: gate_select of the fixture over the real list (or another).
sel_real() {
  capture env -u GITHUB_ACTIONS -u FORSGREN_GATE_SELECT_FULL FORSGREN_GATE_INPUTS="${2:-$REAL_INPUTS}" bash "${TMP}/drive.sh" "$FX" Scripts/lib_gate_select.sh "$1"
}
# real_case <case> <file> <want-prefix>: the file alone changed; each browser label says the wanted line.
real_case() {
  local label
  echo '# edit' >> "${FX}/$2"
  for label in "${BROWSER_LABELS[@]}"; do
    sel_real "$label"
    if [[ "$3" == skip ]]; then
      want_exit "$1: only $2 changed, ${label}" 0 "skip: none of the 1 changed files is an input of ${label}"
    else
      want_exit "$1: only $2 changed, ${label} (fail-safe)" 0 "run: $2 is named by no gate's list, so every gate runs"
    fi
  done
  reset
}
real_case 22 sfl.sh skip
real_case 23 FBP.sh skip
real_case 24 other/o.txt run

# 15: the real list: every browser label has input rows the library reads, and the
# real library covers the engine and excludes a test file, as the list says.
for label in "browser gate self-test" "browser gate" "browser gate (fixture site) self-test" "browser gate (fixture site)"; do
  if [[ -z "$(gate_input_rows Scripts/gate_inputs.txt "$label" in)" ]]; then
    fail "15: the real list has no input rows for '${label}'"
  fi
done
if gate_input_covered Scripts/gate_inputs.txt "browser gate" Scripts/browser_gate.mjs \
  && gate_input_excluded Scripts/gate_inputs.txt "browser gate" internal/page/page_test.go \
  && ! gate_input_excluded Scripts/gate_inputs.txt "browser gate" internal/page/page.go; then
  echo "  ok: 15: the real list covers the engine and excludes a test file, not a source file"
else
  fail "15: the real list does not cover the engine, or does not exclude exactly the test files"
fi

# Mutation proofs: a mutated copy of the library is sourced by the fixture, in
# the case the line decides, and must no longer say the reason.
LIB="${REPO_ROOT}/Scripts/lib_gate_select.sh"
proof() {
  if grep -qF -- "$2" <<< "$OUT"; then
    fail "mutation proof $1: the output still said '$2'. Output: ${OUT}"
  else
    echo "  ok: mutation proof $1: $3"
  fi
}
# mutant <name> <sed-expression>: the library with the change, in the fixture; status 1 when it changed nothing.
mutant() {
  selftest_mutant "$LIB" "${FX}/Scripts/mutant_$1.sh" "$2"
}

if mutant A 's/"[$]{GITHUB_ACTIONS:-}" == "true"/"never" == "true"/'; then
  capture env GITHUB_ACTIONS=true bash "${TMP}/drive.sh" "$FX" Scripts/mutant_A.sh alpha
  proof A "Quality runs every gate" "with the Quality path removed, case 11 no longer says Quality runs every gate"
fi

if mutant B 's/"[$]{FORSGREN_GATE_SELECT_FULL:-}" == "1"/"never" == "1"/'; then
  capture env -u GITHUB_ACTIONS FORSGREN_GATE_SELECT_FULL=1 bash "${TMP}/drive.sh" "$FX" Scripts/mutant_B.sh alpha
  proof B "FORSGREN_GATE_SELECT_FULL=1" "with the forced path removed, case 12 no longer says it was forced"
fi

if mutant C 's/if ! changed="[$](changed_files)"; then/changed=""; if false; then/'; then
  git -C "$FX" update-ref -d refs/remotes/origin/main
  sel alpha Scripts/mutant_C.sh
  proof C "no origin/main to compare against" "with the missing origin/main not handled, case 13 no longer says why it runs"
  git -C "$FX" fetch -q origin
fi

echo 'x' >> "${FX}/other/o.txt"
if mutant D 's/if ! gate_input_covered "[$]inputs" "" "[$]c" && ! gate_input_excluded "[$]inputs" "" "[$]c"; then/if false; then/'; then
  sel alpha Scripts/mutant_D.sh
  proof D "named by no gate's list" "without the fail-safe, case 6 no longer says the file is named by no list"
fi
reset

echo 'package src' > "${FX}/src/a_test.go"
"${G[@]}" -C "$FX" add src/a_test.go
if mutant E 's/ && ! gate_input_excluded "[$]inputs" "[$]label" "[$]c"; then/; then/'; then
  sel alpha Scripts/mutant_E.sh
  proof E "skip: none of the 1 changed files is an input of alpha" "with the out patterns ignored for the gate, case 4a no longer skips"
fi
reset

echo 'package other' > "${FX}/other/x_test.go"
if mutant F 's/ && ! gate_input_excluded "[$]inputs" "" "[$]c"; then/; then/'; then
  sel alpha Scripts/mutant_F.sh
  proof F "skip: none of the 1 changed files is an input of alpha" "with out files counted as unknown, case 4c runs every gate instead of skipping"
fi
reset

echo 'package src // edit' >> "${FX}/src/a.go"
if mutant G 's/\[\[ "[$]3" == "[$]p"[*] \]\]/false/'; then
  sel alpha Scripts/mutant_G.sh
  proof G "run: src/a.go is an input of alpha" "with a listed directory not covering its files, case 2a no longer runs"
fi
reset

echo 'package src' > "${FX}/src/new.go"
if mutant H 's/; git ls-files --others --exclude-standard;/;/'; then
  sel alpha Scripts/mutant_H.sh
  proof H "run: src/new.go is an input of alpha" "with untracked files ignored, case 8 no longer runs"
fi
reset


# I: without the none rows the workflow case runs (a list with the rows removed).
grep -v '^none|' "${FX}/Scripts/gate_inputs.txt" > "${TMP}/no_none.txt"
echo '# edit' >> "${FX}/.github/workflows/w.yml"
capture env -u GITHUB_ACTIONS -u FORSGREN_GATE_SELECT_FULL FORSGREN_GATE_INPUTS="${TMP}/no_none.txt" bash "${TMP}/drive.sh" "$FX" Scripts/lib_gate_select.sh alpha
proof I "skip: none of the 1 changed files is an input of alpha" "without the none rows, case 16a runs because the workflow is named by no list"
reset

# J: with the Scripts/ closure check removed, a script that IS in a closure is taken for unrelated.
echo '# edit' >> "${FX}/Scripts/helper.sh"
if mutant J 's/grep -qxF -- "[$]1" <<< "[$]related"/false/'; then
  sel beta Scripts/mutant_J.sh
  proof J "run: Scripts/helper.sh is named by no gate's list" "without the closure check, case 21 no longer runs for a script that is in a closure"
fi
reset

# K: the real list without its sfl.sh row: a commit that changes only sfl.sh runs
# the browser rows again, because sfl.sh is then named by no list.
grep -vxF 'none|out|sfl.sh' "$REAL_INPUTS" > "${TMP}/no_sfl.txt"
if cmp -s "$REAL_INPUTS" "${TMP}/no_sfl.txt"; then fail "mutation K changed nothing: the proof would be vacuous"; fi
echo '# edit' >> "${FX}/sfl.sh"
sel_real "browser gate" "${TMP}/no_sfl.txt"
want_exit "mutation proof K: without the sfl.sh row, the sfl-only commit runs the browser gate" 0 "run: sfl.sh is named by no gate's list, so every gate runs"
reset

selftest_end "the gate select self-test failed" "gate_select: twenty-four cases hold, eleven mutations seen"
