#!/usr/bin/env bash
# Scripts/test_fix_source_css.sh
#
# Self-test for Scripts/fix_source_css.sh and its place in the run (forsgren#215),
# run in PRE. The Stylelint gate (Scripts/gate_stylelint.sh) is canon: in CI it
# only checks, and under GATE_FIX=1 it fixes the GENERATED .build/site, which
# the next build overwrites. forsgren's CSS is generated from the source
# internal/page/styles.css (go:embed), so the fix has to land in the source,
# before the build, and only in FBP. This test pins that, with the REAL
# stylelint from node_modules/.bin and the real .stylelintrc.json. Each case
# runs a copy of the script from Scripts/ of a throwaway root that holds a copy
# of the config and a link to the repository's node_modules.
#
#   1. GATE_FIX=1: a source stylesheet with #ffffff (the standard config wants
#      #fff) is FIXED in place, the run is green
#   2. the same run NEVER touches a generated copy: a stale .build/site/styles.css
#      holding the same fault is left byte for byte as it was
#   3. GATE_FIX unset (CI, and a stray call): the source is left unchanged, the
#      run is exit 0 and says that nothing was fixed
#   4. GATE_FIX=0 is not fix mode either
#   5. a missing source file under GATE_FIX=1 is exit 2, never a pass
#   6. ORDER: FBP.sh runs the fix BEFORE Scripts/build_site.sh and before
#      `./sfl.sh pre`, and sets GATE_FIX=1 for that call
#   7. CI NEVER FIXES: no workflow, Scripts/run_ci_phase.sh or order-file row
#      names the script, and no workflow mentions GATE_FIX
# Mutation proofs:
#   A. a copy of the script that ignores GATE_FIX fixes the file in case 3's
#      setup, so case 3 is red BECAUSE of the guard
#   B. an FBP.sh copy with the fix moved after the build is rejected by case 6's
#      check, and a workflow copy that names the script is rejected by case 7's

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
FIX="${REPO_ROOT}/Scripts/fix_source_css.sh"
CONFIG="${REPO_ROOT}/.stylelintrc.json"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
selftest_begin "source CSS fix self-test"

for need in "$FIX" "$CONFIG" "${REPO_ROOT}/node_modules/.bin/stylelint" FBP.sh; do
  [[ -e "$need" ]] || selftest_abort "${need} does not exist — the source CSS fix cannot be validated (run npm ci)"
done

GOOD_CSS='body {
  margin: 0;
  color: #fff;
}
'
BAD_CSS='body {
  margin: 0;
  color: #ffffff;
}
'

# new_root <name> [script-copy] — a throwaway root with the script (or the given
# copy), the config, a bad source stylesheet at internal/page/styles.css and a
# bad generated copy at .build/site/styles.css, node_modules linked in.
new_root() {
  ROOT="${TMP}/$1"
  mkdir -p "${ROOT}/Scripts" "${ROOT}/internal/page" "${ROOT}/.build/site"
  cp "${2:-$FIX}" "${ROOT}/Scripts/fix_source_css.sh"
  chmod +x "${ROOT}/Scripts/fix_source_css.sh"
  cp "$CONFIG" "${ROOT}/.stylelintrc.json"
  printf '%s' "$BAD_CSS" > "${ROOT}/internal/page/styles.css"
  printf '%s' "$BAD_CSS" > "${ROOT}/.build/site/styles.css"
  ln -s "${REPO_ROOT}/node_modules" "${ROOT}/node_modules"
}

source_css() { cat "${ROOT}/internal/page/styles.css"; }
generated_css() { cat "${ROOT}/.build/site/styles.css"; }

# --- 1 and 2. GATE_FIX=1 fixes the source and never the generated copy -------
new_root fix
capture env GATE_FIX=1 "${ROOT}/Scripts/fix_source_css.sh"
want_green "1. GATE_FIX=1 run is green"
if [[ "$(source_css)" == "$(printf '%s' "$GOOD_CSS")" ]]; then
  echo "  ok: 1. the source stylesheet is fixed in place (#ffffff became #fff)"
else
  fail "1. the source stylesheet was not fixed: $(source_css)"
fi
if [[ "$(generated_css)" == "$(printf '%s' "$BAD_CSS")" ]]; then
  echo "  ok: 2. the generated .build/site/styles.css is left exactly as it was"
else
  fail "2. the generated copy was changed: $(generated_css)"
fi

# --- 3. GATE_FIX unset: nothing is changed, nothing fails ---------------------
new_root unset
capture env -u GATE_FIX "${ROOT}/Scripts/fix_source_css.sh"
want_green "3. a run without GATE_FIX is exit 0" "nothing is fixed"
if [[ "$(source_css)" == "$(printf '%s' "$BAD_CSS")" ]]; then
  echo "  ok: 3. a run without GATE_FIX leaves the source unchanged (CI never fixes)"
else
  fail "3. a run without GATE_FIX CHANGED the source: $(source_css)"
fi

# --- 4. GATE_FIX=0 is not fix mode ---------------------------------------------
new_root zero
capture env GATE_FIX=0 "${ROOT}/Scripts/fix_source_css.sh"
want_green "4. GATE_FIX=0 is exit 0" "nothing is fixed"
if [[ "$(source_css)" == "$(printf '%s' "$BAD_CSS")" ]]; then
  echo "  ok: 4. GATE_FIX=0 leaves the source unchanged"
else
  fail "4. GATE_FIX=0 CHANGED the source: $(source_css)"
fi

# --- 5. a missing source is exit 2 --------------------------------------------
new_root missing
rm "${ROOT}/internal/page/styles.css"
capture env GATE_FIX=1 "${ROOT}/Scripts/fix_source_css.sh"
want_exit "5. a missing source stylesheet" 2 "source CSS not found"

# --- 6. ORDER in FBP.sh -------------------------------------------------------
# first_line <file> <regex>: the number of the first matching line, or nothing.
first_line() { grep -nE -m 1 -- "$2" "$1" | cut -d: -f1 || true; }

# fbp_problems <FBP.sh>: what is wrong with where the fix runs.
fbp_problems() {
  local f="$1" fix build pre
  fix="$(first_line "$f" '^[[:space:]]*if ! GATE_FIX=1 \./Scripts/fix_source_css\.sh')"
  build="$(first_line "$f" '^[[:space:]]*(SITE_PAGE_COUNT_FILE="[^"]*" )?\./Scripts/build_site\.sh')"
  pre="$(first_line "$f" '^\./sfl\.sh pre ')"
  [[ -n "$fix" ]] || { echo "FBP.sh does not run GATE_FIX=1 ./Scripts/fix_source_css.sh"; return; }
  [[ -n "$build" ]] || { echo "FBP.sh has no build_site.sh line to order the fix against"; return; }
  [[ -n "$pre" ]] || { echo "FBP.sh has no ./sfl.sh pre line to order the fix against"; return; }
  [[ "$fix" -lt "$build" ]] || echo "the source CSS fix runs after the build, so the build copies the unfixed source"
  [[ "$fix" -lt "$pre" ]] || echo "the source CSS fix runs after the pre gates"
}
problems="$(fbp_problems FBP.sh)"
if [[ -z "$problems" ]]; then
  echo "  ok: 6. FBP.sh runs GATE_FIX=1 ./Scripts/fix_source_css.sh before the pre gates and before the build"
else
  fail "6. ${problems}"
fi

# --- 7. CI never fixes --------------------------------------------------------
ci_problems() {
  local wf="$1" runner="$2" order="$3"
  if grep -rqF 'fix_source_css' "$wf"; then echo "a workflow names fix_source_css.sh"; fi
  if grep -rqF 'GATE_FIX' "$wf"; then echo "a workflow mentions GATE_FIX"; fi
  if grep -qF 'fix_source_css' "$runner"; then echo "the CI phase runner names fix_source_css.sh"; fi
  if grep -v '^#' "$order" | cut -d'|' -f2 | has -qxF 'Scripts/fix_source_css.sh'; then
    echo "an order-file row runs fix_source_css.sh, so sfl and CI would both run it"
  fi
}
problems="$(ci_problems .github/workflows Scripts/run_ci_phase.sh Scripts/gate_report_order.txt)"
if [[ -z "$problems" ]]; then
  echo "  ok: 7. no workflow, CI runner or order-file row runs the fix, and no workflow mentions GATE_FIX"
else
  fail "7. CI would fix: ${problems}"
fi

# --- Mutation proof A: a script that ignores GATE_FIX --------------------------
if selftest_mutant "$FIX" "${TMP}/mutant-src/fix_source_css.sh" "s/^if \\[\\[ \"\${GATE_FIX:-}\" != \"1\" \\]\\]; then\$/if false; then/"; then
  new_root mutantA "${TMP}/mutant-src/fix_source_css.sh"
  capture env -u GATE_FIX "${ROOT}/Scripts/fix_source_css.sh"
  if [[ "$(source_css)" == "$(printf '%s' "$GOOD_CSS")" ]]; then
    echo "  ok: mutation A: without the GATE_FIX guard a run in CI mode fixes the source, which case 3 refuses"
  else
    fail "mutation A: a script without the GATE_FIX guard still left the source unchanged, so case 3 proves nothing"
  fi
fi

# --- Mutation proof B: the order and the CI checks bite ------------------------
mkdir -p "${TMP}/mutB"
awk '
  /^# Source CSS fix \(forsgren#215\)/ { hold = 1 }
  hold { buf = buf $0 "\n"; if ($0 == "fi") { hold = 0 } ; next }
  { print }
  END { printf "%s", buf }
' FBP.sh > "${TMP}/mutB/FBP.sh"
if cmp -s FBP.sh "${TMP}/mutB/FBP.sh"; then
  fail "mutation B: moving the fix to the end of FBP.sh changed nothing: the proof would be vacuous"
elif [[ -n "$(fbp_problems "${TMP}/mutB/FBP.sh")" ]]; then
  echo "  ok: mutation B: an FBP.sh with the fix moved after the build is rejected by case 6's check"
else
  fail "mutation B: an FBP.sh with the fix moved to the end was accepted, so case 6 does not guard the order"
fi
mkdir -p "${TMP}/mutC/wf"
cp .github/workflows/*.yml "${TMP}/mutC/wf/"
printf '# ./Scripts/fix_source_css.sh\n' >> "${TMP}/mutC/wf/quality.yml"
if [[ -n "$(ci_problems "${TMP}/mutC/wf" Scripts/run_ci_phase.sh Scripts/gate_report_order.txt)" ]]; then
  echo "  ok: mutation C: a workflow that names the script is rejected by case 7's check"
else
  fail "mutation C: a workflow naming the script was accepted, so case 7 does not guard CI staying check-only"
fi

selftest_end "the source CSS fix does not fix only the source, only in fix mode, before the build, and never in CI" \
  "the source CSS fix repairs internal/page/styles.css under GATE_FIX=1, never touches the generated copy, changes nothing without GATE_FIX, runs in FBP.sh before the pre gates and the build, and CI never runs it"
