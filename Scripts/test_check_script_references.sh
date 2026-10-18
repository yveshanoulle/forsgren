#!/usr/bin/env bash
# canon: test_check_script_references v2
# Scripts/test_check_script_references.sh
#
# Fixture test for Scripts/check_script_references.sh,
# byte-identical across the estate's repositories. The gate's job is to make a
# moved or renamed script loud, and a gate that cannot tell broken from clean is
# worse than none, so it is fed trees with KNOWN answers and its verdict is
# asserted: the exit code, and for the later fixtures the REASON as well.
#   1 clean tree, 2 forward (missing script), 3 reverse (orphan), 4 a script
#   naming only itself, 5 prose scanned, 5b another repository's path, 5c an
#   order file, 5d reverse callers, 6-7 and 11 subdirectories and moves, 13 a
#   standalone folder is red, 20-21 case and external paths, 22-25 a fallback
#   default, a missing path under an existing directory and red-on-zero, 26-28
#   flat Scripts/, 29 a path named only in a comment, 30 the orphan is named.
# Mutation proofs (weakened copies of the gate): A forward resolution always
# true, B no zero-files check, C no flatness check, D the exit status
# swallowed, E comments ignored, F the reverse check off. Each fixture that is
# red must turn green (or lose its reason) under the mutation that removes
# the check it names.
set -uo pipefail

# shellcheck source=Scripts/lib_git_sandbox.sh
source "$(dirname "$0")/lib_git_sandbox.sh"

# Repo root without counting levels. The replaced form is described, never
# quoted: the depth check greps every script for it.
cd "$(cd "$(dirname "$0")" && git rev-parse --show-toplevel)" || exit 1
CHECK="Scripts/check_script_references.sh"
CHECK_ABS="$(pwd)/$CHECK"

tmproot="$(mktemp -d)"
trap 'rm -rf "$tmproot"' EXIT

fail() { echo "❌ FAIL: $1" >&2; exit 1; }

# Builds a tree: Scripts/used.sh plus whatever the caller writes.
make_tree() {
  root="$1"
  mkdir -p "$root/Scripts"
  printf '#!/usr/bin/env bash\necho used\n' > "$root/Scripts/used.sh"
}

# --- Fixture 1: clean tree → must PASS ---
clean="$tmproot/clean"
make_tree "$clean"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\n' > "$clean/caller.sh"
if ! bash "$CHECK_ABS" "$clean" >/dev/null 2>&1; then
  fail "clean tree was rejected — every referenced path exists and every script has a caller"
fi

# --- Fixture 2: caller points at a missing script → must FAIL (forward) ---
broken="$tmproot/broken-forward"
make_tree "$broken"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\nbash Scripts/gone.sh\n' > "$broken/caller.sh"
if bash "$CHECK_ABS" "$broken" >/dev/null 2>&1; then
  fail "a reference to a nonexistent Scripts/gone.sh was NOT caught (forward check)"
fi

# --- Fixture 3: script nobody references → must FAIL (reverse) ---
orphan="$tmproot/broken-reverse"
make_tree "$orphan"
printf '#!/usr/bin/env bash\necho lonely\n' > "$orphan/Scripts/unreferenced.sh"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\n' > "$orphan/caller.sh"
if bash "$CHECK_ABS" "$orphan" >/dev/null 2>&1; then
  fail "a script with no caller was NOT caught (reverse check)"
fi

# --- Fixture 4: a script mentioning only ITSELF is still an orphan ---
# Usage docstrings routinely name their own file; that must not count as a
# caller, or every dead script would look alive.
selfref="$tmproot/self-reference"
make_tree "$selfref"
printf '#!/usr/bin/env bash\n# Usage: bash Scripts/talks_to_itself.sh\necho hi\n' \
  > "$selfref/Scripts/talks_to_itself.sh"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\n' > "$selfref/caller.sh"
if bash "$CHECK_ABS" "$selfref" >/dev/null 2>&1; then
  fail "a script referenced only by its own usage line was NOT caught (reverse check)"
fi

# --- Fixture 5: prose is scanned → must FAIL ---
# The docs are scanned on purpose: a dangling Scripts path in a doc is the
# "we will forget later" this guard catches now.
prose="$tmproot/prose-only"
make_tree "$prose"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\n' > "$prose/caller.sh"
printf 'Plan: add Scripts/not_written_yet.sh next sprint.\n' > "$prose/TODO.md"
if bash "$CHECK_ABS" "$prose" >/dev/null 2>&1; then
  fail "a Scripts path in Markdown that does not exist was NOT caught (docs are scanned)"
fi

# --- Fixture 5b: another repository's script, named as such → must PASS ---
# The repository is the path's first component; this repository has no
# such directory, so the path is not ours to verify.
foreign="$tmproot/foreign-repo"
make_tree "$foreign"
printf '#!/usr/bin/env bash\n# twin of source-repo/Scripts/twin.sh\nbash Scripts/used.sh\n' > "$foreign/caller.sh"
printf 'Ported from source-repo/Scripts/lint/guard.sh and ../source-repo/Scripts/x.sh.\n' > "$foreign/README.md"
if ! bash "$CHECK_ABS" "$foreign" >/dev/null 2>&1; then
  fail "another repository's script, named with its repository as the first component, was treated as a broken reference"
fi

# --- Fixture 5c: an order file naming a missing script → must FAIL ---
orderfile="$tmproot/order-file"
make_tree "$orderfile"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\n' > "$orderfile/caller.sh"
printf 'gone|Scripts/gone.sh|pre|\n' > "$orderfile/Scripts/gate_report_order.txt"
if bash "$CHECK_ABS" "$orderfile" >/dev/null 2>&1; then
  fail "a row of an order file naming a nonexistent Scripts/gone.sh was NOT caught"
fi

# --- Fixture 5d: reverse callers — order file and CLAUDE.md count, other prose not ---
# sfl dispatches every gate from the order file, so its row is the caller;
# CLAUDE.md declares the scripts an agent runs by hand. A README mention is
# no caller: prose that merely names a script would keep a dead one alive.
rev_order="$tmproot/reverse-order"
make_tree "$rev_order"
printf 'used|Scripts/used.sh|pre|\n' > "$rev_order/Scripts/gate_report_order.txt"
printf '#!/usr/bin/env bash\necho ok\n' > "$rev_order/caller.sh"
printf 'run caller.sh\n' > "$rev_order/CLAUDE.md"
if ! bash "$CHECK_ABS" "$rev_order" >/dev/null 2>&1; then
  fail "a script named by an order-file row was reported as having no caller"
fi
rev_claude="$tmproot/reverse-claude"
make_tree "$rev_claude"
printf -- '- Scripts/used.sh, run by hand\n' > "$rev_claude/CLAUDE.md"
if ! bash "$CHECK_ABS" "$rev_claude" >/dev/null 2>&1; then
  fail "a hand-run script declared in CLAUDE.md was reported as having no caller"
fi
rev_readme="$tmproot/reverse-readme"
make_tree "$rev_readme"
printf -- '- Scripts/used.sh, mentioned in prose\n' > "$rev_readme/README.md"
if bash "$CHECK_ABS" "$rev_readme" >/dev/null 2>&1; then
  fail "a script mentioned only in README.md counted as having a caller"
fi

# --- Fixture 6: a script in a SUBDIRECTORY with no caller → must FAIL ---
# The reorganisation moves scripts into per-project subdirectories. A reverse
# check that only globs the top level would silently stop checking every moved
# file — the guard would go quiet exactly when it is needed most.
subdir="$tmproot/subdir-orphan"
make_tree "$subdir"
mkdir -p "$subdir/Scripts/common"
printf '#!/usr/bin/env bash\necho lonely\n' > "$subdir/Scripts/common/unreferenced.sh"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\n' > "$subdir/caller.sh"
if bash "$CHECK_ABS" "$subdir" >/dev/null 2>&1; then
  fail "a script in Scripts/common with no caller was NOT caught (reverse check is not recursive)"
fi

# --- Fixture 7: a stale reference to a MOVED script → must FAIL (forward) ---
# The failure the reorganisation actually risks: the file now lives in a
# subdirectory, a caller still names the old path.
moved="$tmproot/moved"
mkdir -p "$moved/Scripts/common"
printf '#!/usr/bin/env bash\necho moved\n' > "$moved/Scripts/common/used.sh"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\n' > "$moved/caller.sh"
if bash "$CHECK_ABS" "$moved" >/dev/null 2>&1; then
  fail "a caller still naming the pre-move path was NOT caught (forward check)"
fi

# --- Fixture 11: a stale reference INTO a subdirectory → must FAIL (forward) ---
# Fixture 7 covers the pre-move path; this is the post-move one, and it is the
# form every reference the reorganisation rewrites now takes. The forward scan
# matches a single path segment after "Scripts/", so a path with a subdirectory
# in it is not checked — it is not even seen. The guard does not weaken with a
# bang here, it goes quiet: each batch that lands moves more references out of
# its reach while it keeps reporting OK.
subforward="$tmproot/subdir-forward"
make_tree "$subforward"
mkdir -p "$subforward/Scripts/common"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\nbash Scripts/common/gone.sh\n' \
  > "$subforward/caller.sh"
if bash "$CHECK_ABS" "$subforward" >/dev/null 2>&1; then
  fail "a reference to a nonexistent Scripts/common/gone.sh was NOT caught (forward check ignores subdirectories)"
fi

# --- Fixture 13: Scripts/standalone is a subfolder → must FAIL ---
# Scripts/ is kept flat, so that directory is a script below Scripts/*/ like
# any other: red, for the flatness reason. A hand-run script is declared in
# CLAUDE.md instead (fixture 5d).
standalone="$tmproot/standalone-dir"
make_tree "$standalone"
mkdir -p "$standalone/Scripts/standalone"
printf '#!/usr/bin/env bash\necho hand-run diagnostic\n' \
  > "$standalone/Scripts/standalone/lonely.sh"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\n' > "$standalone/caller.sh"
OUT="$(bash "$CHECK_ABS" "$standalone" 2>&1)"; RC=$?
[ "$RC" -ne 0 ] || fail "a script in Scripts/standalone was green — Scripts/ must stay flat "
grep -qF 'SCRIPT IN SUBFOLDER: Scripts/standalone/lonely.sh' <<<"$OUT" \
  || fail "the Scripts/standalone case is red for another reason. Output: $OUT"

# --- Fixtures 20-21: references must resolve CASE-SENSITIVELY ---------------
# macOS is case-insensitive, so `[ -e ../scripts/x.py ]` answers TRUE for a
# path spelled `Scripts/`. Seven references were spelled lowercase and had
# NEVER been checked (2026-08-17); four broke the moment their targets moved.
# GitHub path filters ARE case-sensitive, so the same spelling in a workflow
# `paths:` entry silently matches nothing — a filter covering nothing looks
# exactly like one that works.
#
# Resolution walks the path and requires each component to appear verbatim in
# its parent's listing. No git needed, so the temp trees stay plain directories.

# 20: right file, wrong case -> must FAIL
wrongcase="$tmproot/wrong-case"
make_tree "$wrongcase"
printf '#!/usr/bin/env bash\nbash scripts/used.sh\n' > "$wrongcase/caller.sh"
if bash "$CHECK_ABS" "$wrongcase" >/dev/null 2>&1; then
  fail "a reference spelled scripts/ (lowercase) resolved against Scripts/ — case is not being checked"
fi

# 21: a path outside the repo is not ours to verify -> must PASS
external="$tmproot/external"
make_tree "$external"
printf '#!/usr/bin/env bash\n# prereq: ~/Sources/codescene/launch.sh and /usr/local/bin/tool.sh\nbash Scripts/used.sh\n' \
  > "$external/caller.sh"
if ! bash "$CHECK_ABS" "$external" >/dev/null 2>&1; then
  fail "an absolute or home-relative path outside the repo was treated as a broken reference"
fi

# --- Fixtures 22-25: they assert the REASON as well as the exit ---
run_check() { OUT="$(bash "$1" "$2" 2>&1)"; RC=$?; }

# 22: a default argument's fallback naming a missing script -> must FAIL
# The expansion's dash arrives glued to the path; it must not make the path
# read as another repository's and slip through.
fallback="$tmproot/default-fallback"
make_tree "$fallback"
printf "#!/usr/bin/env bash\nbash Scripts/used.sh\nT=\"\${1:-Scripts/gone.sh}\"\n" > "$fallback/caller.sh"
run_check "$CHECK_ABS" "$fallback"
[ "$RC" -ne 0 ] || fail "a default-argument fallback naming a nonexistent Scripts/gone.sh was NOT caught"
grep -q 'UNRESOLVED REFERENCE: -Scripts/gone.sh' <<<"$OUT" \
  || fail "the fallback case is red for another reason. Output: $OUT"

# 23: a missing path under a directory this repo HAS -> must FAIL
# Only a first component that does not exist here reads as another
# repository; one that exists is ours and is checked.
underdir="$tmproot/under-existing-dir"
make_tree "$underdir"
mkdir -p "$underdir/internal"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\nbash internal/Scripts/gone.sh\n' > "$underdir/caller.sh"
run_check "$CHECK_ABS" "$underdir"
[ "$RC" -ne 0 ] || fail "a nonexistent internal/Scripts/gone.sh under an existing internal/ was NOT caught"
grep -q 'UNRESOLVED REFERENCE: internal/Scripts/gone.sh' <<<"$OUT" \
  || fail "the existing-directory case is red for another reason. Output: $OUT"

# 24: a tree with no file the guard scans -> must FAIL, saying so
emptytree="$tmproot/empty"
mkdir -p "$emptytree"
run_check "$CHECK_ABS" "$emptytree"
[ "$RC" -ne 0 ] || fail "a scan over zero files was green — nothing scanned is not clean"
grep -q 'scanned zero files' <<<"$OUT" \
  || fail "the zero-files case is red for another reason. Output: $OUT"

# 25: files, but no Scripts reference in any of them -> must FAIL, saying so
norefs="$tmproot/no-references"
mkdir -p "$norefs"
printf '#!/usr/bin/env bash\necho nothing to see\n' > "$norefs/caller.sh"
run_check "$CHECK_ABS" "$norefs"
[ "$RC" -ne 0 ] || fail "a scan that extracted zero Scripts references was green — nothing was checked"
grep -q 'extracted zero Scripts paths' <<<"$OUT" \
  || fail "the zero-references case is red for another reason. Output: $OUT"


# --- Fixture 29: a path named ONLY in a comment is still a reference → must FAIL ---
# A comment is where a stale path survives longest, so the scan reads comments.
commented="$tmproot/comment-only"
make_tree "$commented"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\n# see Scripts/removed_long_ago.sh for the old way\n' > "$commented/caller.sh"
run_check "$CHECK_ABS" "$commented"
[ "$RC" -ne 0 ] || fail "a comment naming a nonexistent Scripts/removed_long_ago.sh was NOT caught"
grep -qF 'UNRESOLVED REFERENCE: Scripts/removed_long_ago.sh' <<<"$OUT" \
  || fail "the comment-only case is red for another reason. Output: $OUT"

# 30: the orphan of fixture 4 is NAMED, not only counted.
run_check "$CHECK_ABS" "$selfref"
grep -qF 'UNREFERENCED SCRIPT: Scripts/talks_to_itself.sh' <<<"$OUT" \
  || fail "the self-reference case does not name the orphan. Output: $OUT"

# --- Mutation proofs: each red above is red BECAUSE of the check it names ---
# mutant <name> <sed-expression> — a copy of the gate with one line replaced;
# a sed that changes nothing proves nothing, so that is a failure too.
mutant() {
  MUTANT="$tmproot/$1.sh"
  sed "$2" "$CHECK_ABS" > "$MUTANT"
  if cmp -s "$CHECK_ABS" "$MUTANT"; then
    fail "mutation proof $1: the sed changed nothing in ${CHECK} — its anchor no longer matches, so this proof proves nothing"
  fi
}

# A: the forward resolution. With every path resolving, fixture 2's tree must
# be green, so fixture 2 is red because the path does not resolve.
mutant forward-always-resolves "s/^  if ! resolves_case_sensitively \"\\\$stripped\"; then\$/  if false; then/"
run_check "$CHECK_ABS" "$broken"
grep -q 'UNRESOLVED REFERENCE: Scripts/gone.sh' <<<"$OUT" \
  || fail "mutation proof A: the real gate does not name Scripts/gone.sh on fixture 2. Output: $OUT"
run_check "$MUTANT" "$broken"
[ "$RC" -eq 0 ] \
  || fail "mutation proof A: a gate whose references always resolve is still red on fixture 2 (exit $RC) — red for another reason. Output: $OUT"

# B: red-on-zero. Without the zero-files check, fixture 24's empty tree must
# not report that it scanned zero files: the reason comes from that check.
mutant zero-files-unchecked "s/^if \\[ \"\\\$nscanned\" -eq 0 \\]; then\$/if false; then/"
run_check "$MUTANT" "$emptytree"
if grep -q 'scanned zero files' <<<"$OUT"; then
  fail "mutation proof B: without the zero-files check the gate still says it scanned zero files — the reason comes from elsewhere"
fi

# --- Fixtures 26-28: the flat-Scripts guard ---
FLAT_REASON="scripts must sit directly under Scripts/ — every script finds the root one level up, which holds only while Scripts/ is flat"

# 26: a CALLED script one folder down -> must FAIL, for the flatness reason
# alone: the forward and reverse checks are both satisfied.
nested="$tmproot/nested-script"
make_tree "$nested"
mkdir -p "$nested/Scripts/sub"
printf '#!/usr/bin/env bash\necho nested\n' > "$nested/Scripts/sub/x.sh"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\nbash Scripts/sub/x.sh\n' > "$nested/caller.sh"
run_check "$CHECK_ABS" "$nested"
[ "$RC" -ne 0 ] || fail "a script under Scripts/sub/ was green — Scripts/ must stay flat "
grep -qF "SCRIPT IN SUBFOLDER: Scripts/sub/x.sh — ${FLAT_REASON}" <<<"$OUT" \
  || fail "the nested-script case does not name the flatness reason. Output: $OUT"

# 27: a Python script one folder down -> must FAIL too: the gate's scripts
# are .sh and .py, and flatness covers every script it knows.
nestedpy="$tmproot/nested-python"
make_tree "$nestedpy"
mkdir -p "$nestedpy/Scripts/lib"
printf 'print(1)\n' > "$nestedpy/Scripts/lib/y.py"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\npython3 Scripts/lib/y.py\n' > "$nestedpy/caller.sh"
run_check "$CHECK_ABS" "$nestedpy"
[ "$RC" -ne 0 ] || fail "a Python script under Scripts/lib/ was green — Scripts/ must stay flat "
grep -qF "SCRIPT IN SUBFOLDER: Scripts/lib/y.py — ${FLAT_REASON}" <<<"$OUT" \
  || fail "the nested-Python case does not name the flatness reason. Output: $OUT"

# 28: a DATA file in a subfolder -> must PASS. The ruling is about scripts
# that climb to the root; a fixture or data file runs nothing and climbs
# nowhere, so a data folder under Scripts/ stays allowed.
datadir="$tmproot/data-subfolder"
make_tree "$datadir"
mkdir -p "$datadir/Scripts/fixtures"
printf 'plain data\n' > "$datadir/Scripts/fixtures/x.txt"
printf '#!/usr/bin/env bash\nbash Scripts/used.sh\n' > "$datadir/caller.sh"
run_check "$CHECK_ABS" "$datadir"
[ "$RC" -eq 0 ] || fail "a data file in Scripts/fixtures/ was reported — only scripts must sit directly under Scripts/. Output: $OUT"

# C: the flatness check. Without it, fixture 26's tree must be green, so
# fixture 26 is red because of that check and nothing else.
mutant flat-unchecked "s/^if \\[ -n \"\\\$nested_scripts\" \\]; then\$/if false; then/"
run_check "$MUTANT" "$nested"
[ "$RC" -eq 0 ] \
  || fail "mutation proof C: a gate without the flatness check is still red on fixture 26 (exit $RC) — red for another reason. Output: $OUT"

# D: the exit status. A gate that swallows its status exits 0 on fixture 2,
# so fixture 2 is red because the status is what the gate returns.
mutant status-swallowed "s/^exit \"\\\$status\"\$/exit 0/"
run_check "$MUTANT" "$broken"
[ "$RC" -eq 0 ] \
  || fail "mutation proof D: a gate that swallows its exit status still exits $RC on fixture 2 — the status is not what makes it red. Output: $OUT"
grep -q 'UNRESOLVED REFERENCE: Scripts/gone.sh' <<<"$OUT" \
  || fail "mutation proof D: the swallowing gate no longer even names the finding — the proof changed more than the status. Output: $OUT"

# E: comments ignored. A gate that cuts every line at its first # does not see
# fixture 29's path, so fixture 29 is red because comments are read.
mutant comments-ignored "s/| xargs -0 grep -ohiE /| xargs -0 cat | cut -d# -f1 | grep -ohiE /"
run_check "$MUTANT" "$commented"
if grep -qF 'UNRESOLVED REFERENCE: Scripts/removed_long_ago.sh' <<<"$OUT"; then
  fail "mutation proof E: a gate that ignores comments still names the commented path — the reason comes from elsewhere. Output: $OUT"
fi

# F: the reverse check. Without it, fixture 3's orphan is not reported.
mutant reverse-off "s/^if \\[ -n \"\\\$unreferenced\" \\]; then\$/if false; then/"
run_check "$MUTANT" "$orphan"
[ "$RC" -eq 0 ] \
  || fail "mutation proof F: a gate without the reverse check is still red on fixture 3 (exit $RC) — red for another reason. Output: $OUT"

echo "✅ test_check_script_references: PASS"
