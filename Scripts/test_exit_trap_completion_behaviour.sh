#!/usr/bin/env bash
# canon: test_exit_trap_completion_behaviour v2
# Scripts/test_exit_trap_completion_behaviour.sh
#
# The BEHAVIOUR behind Scripts/check_exit_trap_completion.sh.
# The gate reads source; this test runs the real scripts it covers.
# The engine is Scripts/lib_exit_trap_probe.sh (see there for what each case
# requires); the cases below are this repository's data: which scripts exist,
# and what each needs in its sandbox before its trap. Which scripts need a case
# is DERIVED from the gate's own rule (probe_require_all), not listed here.
#
# Mutation proofs (the engine is the thing under test, so weakened copies of
# it run on one real case):
#   A. an engine that does not inject the abort: the case is red
#   B. an engine whose verdict accepts exit 0: the case is red
#   C. a script with its guard removed (the trap without the COMPLETED
#      statement): the case is red
#   D. a push wrapper whose abort line no longer says Aborted: red, and an
#      engine without the expected-output check lets it through

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "exit-trap completion behaviour self-test"
# shellcheck source=Scripts/lib_exit_trap_probe.sh
source Scripts/lib_exit_trap_probe.sh

setup_nothing() { :; }

# FullBuildAndPush.sh / FBP.sh: the repository's push wrapper, the one of the two
# that exists. Run with --no-commit in a sandbox that is not a git repository,
# with a say stub, so nothing is committed, pushed or spoken; the abort comes
# before its first step. Its summary must also say 'Aborted ❌'.
FBP=""
for candidate in FullBuildAndPush.sh FBP.sh; do
  if [[ -f "$candidate" ]]; then
    [[ -z "$FBP" ]] || selftest_abort "both ${FBP} and ${candidate} exist — the script under test is ambiguous"
    FBP="$candidate"
  fi
done
[[ -n "$FBP" ]] || selftest_abort "neither FullBuildAndPush.sh nor FBP.sh exists — there is no push wrapper to probe"
PROBE_EXPECT_OUT="Aborted ❌"
probe_case push_wrapper "$FBP" "$ROOT" setup_nothing --no-commit probe

# gate_htmlhint.sh: a stub htmlhint that scans one file, a site dir, a config.
setup_gate_htmlhint() {
  mkdir -p "$1/node_modules/.bin" "$1/Site"
  printf '#!/usr/bin/env bash\necho "Scanned 1 files"\n' > "$1/node_modules/.bin/htmlhint"
  chmod +x "$1/node_modules/.bin/htmlhint"
  : > "$1/.htmlhintrc"
  : > "$1/Site/index.html"
}
probe_case gate_htmlhint Scripts/gate_htmlhint.sh "$ROOT" setup_gate_htmlhint Site

# build_site.sh, for a repository whose build script is in the gate's scope (a
# top-level EXIT trap): a stub go, since the probe is hit before anything is
# rendered but after the `go build` line. A repository whose script is not in
# scope, or has none, has no such case; probe_require_all below still fails for
# any covered script that has no case.
setup_build_site() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/bin/go"
  chmod +x "$1/bin/go"
}
if grep -qxF -- "Scripts/build_site.sh" <<< "$(probe_trapped_scripts "$ROOT")"; then
  probe_case build_site Scripts/build_site.sh "$ROOT" setup_build_site
fi

# This self-test's sibling: its only column-0 trap line sits inside a heredoc
# fixture, so an injected probe would land in fixture text; its real trap comes
# from selftest_begin, and the abort path of that trap is lib_selftest.sh's.
probe_exempt Scripts/test_check_exit_trap_completion.sh "the only column-0 trap line is inside a heredoc fixture; the real trap is selftest_begin's"

# Every other script the gate's rule covers needs nothing before its trap.
while IFS= read -r rel; do
  case "$PROBE_SEEN" in *" ${rel} "*) continue ;; esac
  probe_case "$(tr '/.' '__' <<< "$rel")" "$rel" "$ROOT" setup_nothing
done < <(probe_trapped_scripts "$ROOT")

probe_require_all "$ROOT"

# --- Mutation proofs: weakened copies of the ENGINE, and a script without its guard.

# probe_child <engine-file> <root> [rel] [expected stdout] [script args]: a child
# run of one real case (default: test_sfl_pull.sh) through the given engine, so a
# failure of the weakened engine does not fail this test.
probe_child() {
  local engine="$1" root="$2" rel="${3:-Scripts/test_sfl_pull.sh}" expect="${4:-}" args="${5:-}"
  cat > "$TMP/child.sh" <<CHILD
#!/usr/bin/env bash
set -euo pipefail
cd "$ROOT"
source Scripts/lib_selftest.sh
selftest_begin "child"
source "$engine"
nothing() { :; }
PROBE_EXPECT_OUT="$expect"
probe_case child_case $rel "$root" nothing $args
selftest_end "child failed" "child held"
CHILD
  capture bash "$TMP/child.sh"
}

# C. The real engine on a copy of a real script with its guard removed: red,
# and the reason is the exit of 0. This is the case the whole test exists for.
mkdir -p "$TMP/guardless/Scripts"
cp -R Scripts/. "$TMP/guardless/Scripts/"
sed 's/^trap finish EXIT$/trap : EXIT/' Scripts/test_sfl_pull.sh > "$TMP/guardless/Scripts/test_sfl_pull.sh"
if cmp -s Scripts/test_sfl_pull.sh "$TMP/guardless/Scripts/test_sfl_pull.sh"; then
  fail "the guard removal changed nothing in test_sfl_pull.sh: the proof would be vacuous"
else
  probe_child "$ROOT/Scripts/lib_exit_trap_probe.sh" "$TMP/guardless"
  want_red "C. test_sfl_pull.sh with its guard removed is red: the abort exits 0" "exits 0"
fi

# Control: the same child on the real script is green.
probe_child "$ROOT/Scripts/lib_exit_trap_probe.sh" "$ROOT"
want_green "C. control: the real test_sfl_pull.sh is green through the same child" "child held"

# A. An engine that does not inject the abort: the real case is red.
mkdir -p "$TMP/mutA"
selftest_mutant Scripts/lib_exit_trap_probe.sh "$TMP/mutA/lib.sh" 's/NR == n {/NR == -1 {/' || true
probe_child "$TMP/mutA/lib.sh" "$ROOT"
want_red "A. an engine that does not inject the abort is caught: the probe never aborted the run" "the probe never aborted the run"

# B. An engine that accepts exit 0. The half-guarded script prints the
# 'aborted before completing' line but exits 0: the real engine is red for the
# exit, the weakened one is green, so the exit check is what reddens it.
mkdir -p "$TMP/halfguard/Scripts"
cp -R Scripts/. "$TMP/halfguard/Scripts/"
sed 's/^    exit 1$/    exit 0/' Scripts/test_sfl_pull.sh > "$TMP/halfguard/Scripts/test_sfl_pull.sh"
if cmp -s Scripts/test_sfl_pull.sh "$TMP/halfguard/Scripts/test_sfl_pull.sh"; then
  fail "the half-guard change did nothing in test_sfl_pull.sh: the proof would be vacuous"
else
  probe_child "$ROOT/Scripts/lib_exit_trap_probe.sh" "$TMP/halfguard"
  want_red "B. a guard that prints its line but exits 0 is red: the abort exits 0" "exits 0"
  mkdir -p "$TMP/mutB"
  selftest_mutant Scripts/lib_exit_trap_probe.sh "$TMP/mutB/lib.sh" 's/rc" -eq 0 \]\]/rc" -eq 99 ]]/' || true
  probe_child "$TMP/mutB/lib.sh" "$TMP/halfguard"
  want_green "B. an engine that accepts exit 0 lets the half-guarded script through, so the exit check is what reddens it" "child held"
fi

# D. The push wrapper must say Aborted: a copy whose line says Stopped is red
# for the missing text; an engine without the expected-output check is green.
mkdir -p "$TMP/quiet/Scripts"
cp -R Scripts/. "$TMP/quiet/Scripts/"
sed 's/Aborted ❌/Stopped/' "$FBP" > "$TMP/quiet/$FBP"
if cmp -s "$FBP" "$TMP/quiet/$FBP"; then
  fail "the Aborted rewording changed nothing in ${FBP}: the proof would be vacuous"
else
  probe_child "$ROOT/Scripts/lib_exit_trap_probe.sh" "$TMP/quiet" "$FBP" "Aborted ❌" "--no-commit probe"
  want_red "D. a push wrapper that no longer says Aborted is red: the output does not say" "the output does not say"
  mkdir -p "$TMP/mutD"
  selftest_mutant Scripts/lib_exit_trap_probe.sh "$TMP/mutD/lib.sh" 's/\[\[ -n "[^"]*EXPECT_OUT" \]\] \&\&/false \&\&/' || true
  probe_child "$TMP/mutD/lib.sh" "$TMP/quiet" "$FBP" "Aborted ❌" "--no-commit probe"
  want_green "D. an engine without the expected-output check lets it through, so that check is what reddens it" "child held"
fi

selftest_end "an abort after the EXIT trap of a script the gate covers exits 0, prints no 'aborted before completing', leaves a temp path, or the engine proof failed" \
  "an abort after the EXIT trap of every script the exit-trap gate covers exits non-zero under /bin/bash, says 'aborted before completing' and leaves no temp path (the push wrapper also says Aborted), and a missing guard, a half guard, an engine without the injection, an engine that accepts exit 0, a push wrapper that stops saying Aborted and an engine that skips that check are each caught"
