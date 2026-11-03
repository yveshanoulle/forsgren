#!/usr/bin/env bash
# canon: test_tmp_failure_stops v1
# Scripts/test_tmp_failure_stops.sh
#
# Self-test (forsgren#615) for the scripts that make a temp folder or file
# with Scripts/lib_tmp.sh but run without `set -e`. A failed
# `X="$(tmp_dir name)"` does not stop such a script on its own: it went on with
# an empty path and wrote to /err, /listed, /decoy (a read-only root made that
# loud; a writable one would have written there).
#
# Each case runs one script with TMPDIR at a path that cannot hold a folder (a
# file, so mktemp fails) and wants: a non-zero exit, a `❌ FAIL: <script>:
# cannot make a temp ...` line that names the TMPDIR folder, no `Read-only file
# system` or other write error from a path outside the temp folder, and no new
# entry in /. The gates that need a repository (run_ci_phase, sfl) run in a
# throwaway one whose gate would leave a mark if it ran.
#
# Mutation proof: the check removed from one script (check_data_guard) turns
# its case red, naming that script.
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "tmp failure stops self-test"

BAD="${TMP}/not_a_folder"
: > "$BAD"
GOT="${TMP}/gotmp"
mkdir -p "$GOT"
MODULE="${TMP}/module"
mkdir -p "$MODULE/.build"
printf 'module example.invalid/acme\n\ngo 1.22\n' > "$MODULE/go.mod"
printf 'package acme\n' > "$MODULE/a.go"
printf 'package acme\n' > "$MODULE/a_test.go"
printf '{}\n' > "$MODULE/coverage_thresholds.json"
printf 'mode: set\n' > "$MODULE/.build/go-coverage.out"
mkdir -p "${TMP}/site"
printf "<p>x</p>\n" > "${TMP}/site/index.html"
printf "a { color: red; }\n" > "${TMP}/site/s.css"

ROOT_BEFORE="$(ls -A /)"

# case <script-file> <command...>: the command with TMPDIR at BAD must stop
# with the script's ❌ line.
tmp_case() {
  local script="$1"
  shift
  capture env TMPDIR="$BAD" GOTMPDIR="$GOT" "$@"
  want_red "${script}: a failed tmp_* stops it" "❌ FAIL: ${script}: cannot make a temp"
  if ! grep -qF -- "$BAD" <<< "$OUT"; then
    fail "${script}: its ❌ line does not name the temp folder ${BAD}. Output: ${OUT}"
  fi
  if grep -qE 'Read-only file system|Permission denied' <<< "$OUT"; then
    fail "${script}: it went on and wrote outside the temp folder. Output: ${OUT}"
  fi
  if [[ "$(ls -A /)" != "$ROOT_BEFORE" ]]; then
    fail "${script}: something appeared in /"
  fi
}

tmp_case check_data_guard.sh bash "Scripts/check_data_guard.sh"
tmp_case check_go_tests.sh bash "Scripts/check_go_tests.sh" "$MODULE"
tmp_case check_html_dupl.sh bash "Scripts/check_html_dupl.sh"
tmp_case check_file_length.sh bash "Scripts/check_file_length.sh" "$MODULE"
tmp_case check_coverage.sh bash "Scripts/check_coverage.sh" "$MODULE"
tmp_case check_test_dupl.sh bash "Scripts/check_test_dupl.sh" "$MODULE"
tmp_case check_markdown_links.sh bash "Scripts/check_markdown_links.sh"
tmp_case check_golden_pages.sh bash "Scripts/check_golden_pages.sh"
tmp_case check_script_references.sh bash "Scripts/check_script_references.sh"
tmp_case check_lint_coverage.sh env HTMLHINT_CMD=/usr/bin/true STYLELINT_CMD=/usr/bin/true \
  bash "Scripts/check_lint_coverage.sh" "${TMP}/site"
tmp_case live_check.sh bash "Scripts/live_check.sh" "https://example.invalid"
tmp_case release_pins.sh env GITHUB_REPOSITORY=acme/shop bash "Scripts/release_pins.sh" rewrite workflow 1.0.0 0000000000000000000000000000000000000000

# The two runners, in a throwaway repository whose one gate leaves a mark when
# it runs: it must not run.
sandbox() {
  local root="${TMP}/$1" s
  mkdir -p "${root}/Scripts" "${root}/.build"
  cp Scripts/lib_tmp.sh Scripts/run_ci_phase.sh Scripts/lib_gate_select.sh \
    Scripts/render_step_table.sh Scripts/summarize_gate_failure.sh "${root}/Scripts/"
  cp sfl.sh "${root}/sfl.sh"
  printf '#!/usr/bin/env bash\ntouch "%s/gate_ran"\n' "$TMP" > "${root}/Scripts/gate_g.sh"
  printf 'g|Scripts/gate_g.sh|pre|\ng post|Scripts/gate_g.sh|post|\n' > "${root}/Scripts/gate_report_order.txt"
  : > "${root}/Scripts/gate_inputs.txt"
  printf '#!/usr/bin/env bash\nsfl_pull_or_stop() { return 0; }\n' > "${root}/Scripts/sfl_pull.sh"
  printf '#!/usr/bin/env bash\necho go1.0\n' > "${root}/Scripts/go_toolchain.sh"
  for s in install_tools check_node_pin npm_sync_install; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/Scripts/${s}.sh"
  done
  printf '.build/\n' > "${root}/.gitignore"
  chmod +x "${root}"/sfl.sh "${root}"/Scripts/*.sh
  git -C "$root" init -q -b main
  git -C "$root" add -A
  git -C "$root" -c user.name=t -c user.email=t@example.invalid commit -q -m base
  printf '%s\n' "$root"
}

SB="$(sandbox ci)"
mkdir -p "${TMP}/details"
tmp_case run_ci_phase.sh env RUN_CI_PHASE_ROOT="$SB" bash Scripts/run_ci_phase.sh pre "${TMP}/rows.md" "${TMP}/details"
[[ ! -e "${TMP}/gate_ran" ]] || fail "run_ci_phase.sh: a gate ran with no temp file"

SB="$(sandbox sfl)"
sfl_case() {
  capture env TMPDIR="$BAD" GOTMPDIR="$GOT" bash -c "cd \"$SB\" && ./sfl.sh post"
  want_red "sfl.sh: a failed tmp_dir stops it" "❌ FAIL: sfl.sh: cannot make a temp"
  if ! grep -qF -- "$BAD" <<< "$OUT"; then
    fail "sfl.sh: its ❌ line does not name the temp folder. Output: ${OUT}"
  fi
  if grep -qE 'Read-only file system|Permission denied' <<< "$OUT"; then
    fail "sfl.sh: it went on and wrote outside the temp folder. Output: ${OUT}"
  fi
  [[ ! -e "${TMP}/gate_ran" ]] || fail "sfl.sh: a gate ran with no log folder"
}
sfl_case

# Mutation proof: the check removed from check_data_guard.sh is red.
mkdir -p "${TMP}/mutant"
cp Scripts/check_data_guard.sh Scripts/lib_tmp.sh Scripts/lib_repo_files.sh "${TMP}/mutant/"
sed -i.bak 's/ || { echo "❌ FAIL: check_data_guard.sh: cannot make.*$//' "${TMP}/mutant/check_data_guard.sh"
if cmp -s Scripts/check_data_guard.sh "${TMP}/mutant/check_data_guard.sh"; then
  fail "mutation proof: the sed changed nothing, so it proves nothing"
else
  capture env TMPDIR="$BAD" GOTMPDIR="$GOT" bash "${TMP}/mutant/check_data_guard.sh"
  if [[ "$RC" -ne 0 ]] && grep -qF -- "❌ FAIL: check_data_guard.sh: cannot make a temp" <<< "$OUT"; then
    fail "mutation proof: without its check check_data_guard.sh still stopped with its ❌ line"
  else
    echo "  ok: mutation proof: without its check check_data_guard.sh does not stop with its ❌ line, so the case above is what catches it"
  fi
fi

selftest_end "a script without set -e goes on after a failed tmp_dir/tmp_file" \
  "tmp failure: 14 scripts without set -e (sfl.sh and run_ci_phase.sh included) stop with a ❌ line naming the temp folder when tmp_dir/tmp_file fails, and write nothing outside it (the check removed from one is red)"
