#!/usr/bin/env bash
# Scripts/precheck.sh
#
# The quick pre-check a writer runs before handing a change back (forsgren#231,
# step 1): FBP's fast static gates, on the changed files only, and the
# self-tests that read a changed file. It commits, pushes, formats and fetches
# nothing, and it is not a gate: FBP and CI stay the verdict. It exists so a
# red that FBP would find after minutes is found by the writer in seconds.
#
# The changed files are the tracked changes against HEAD
# (`git diff --name-only HEAD`) plus the untracked files git does not ignore
# (`git ls-files --others --exclude-standard`). PRECHECK_CHANGED replaces that
# list (newline separated, may be empty): the seam of Scripts/test_precheck.sh.
#
# What runs, by what changed. Every check is the gate's own script, with the
# gate's own configuration, never a second copy of its logic:
#   *.sh                          check_shellcheck.sh (shellcheck -x), on those files
#   .github/workflows/*.yml       check_actionlint.sh, on those files
#   .github/**/*.yml, *.yaml      check_zizmor.sh (the .github directory, as the gate)
#   *.yml, *.yaml                 check_yamllint.sh, on those files
#   *.go                          check_gofmt.sh and check_go_lint.sh (the whole
#                                 module: gofmt and the lint work per package)
#   anything under Scripts/       test_gate_wiring.sh
#   Scripts/test_*.sh             test_git_sandbox_guard.sh
#   *.md                          check_markdown_links.sh
#   plus, for every changed path, every Scripts/test_*.sh whose source mentions
#   its basename (forsgren#231, comment 2). TOO_BROAD below lists the basenames
#   left out because nearly every test would match them.
# A tool that is not installed is a red line, "<tool> not installed", never a
# skipped check. A deleted file is not given to a linter (it is gone) but its
# basename still selects tests: a test that reads it breaks.
#
# Output: one line per check, a check mark or a red cross with the reason (a
# red check is followed by the first lines of its output), then
# `precheck: N checks, M failed` and the elapsed seconds. Exit 1 when any check
# failed, else 0; no changed file is `precheck: 0 checks, 0 failed`, exit 0.
#
# `precheck.sh --gates` lists the gate scripts it runs, one per line, so
# Scripts/test_precheck.sh can pin that each is also a row of
# Scripts/gate_report_order.txt: the pre-check cannot name a gate FBP does not run.
#
# Seams (Scripts/test_precheck.sh): PRECHECK_ROOT (the tree to judge, default
# this repository), PRECHECK_GATES_DIR (where the gate scripts are, default
# beside this script), PRECHECK_CHANGED.
#
# Local invocation: ./Scripts/precheck.sh

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GATES_DIR="${PRECHECK_GATES_DIR:-$HERE}"
ROOT="${PRECHECK_ROOT:-$(cd "$HERE/.." && pwd)}"

# Basenames that name almost every test's subject: running all of them for a
# change to one of these files would be the whole suite.
TOO_BROAD="SHIPPED.md CLAUDE.md README.md TODO.md"

# The gate scripts this pre-check runs: each must be a row of the order file.
GATE_SCRIPTS="Scripts/check_shellcheck.sh Scripts/check_actionlint.sh Scripts/check_yamllint.sh Scripts/check_zizmor.sh Scripts/check_gofmt.sh Scripts/check_go_lint.sh Scripts/test_gate_wiring.sh Scripts/check_markdown_links.sh Scripts/test_git_sandbox_guard.sh"

if [ "${1:-}" = "--gates" ]; then
  for g in $GATE_SCRIPTS; do echo "$g"; done
  exit 0
fi

CHECKS=0
FAILED=0

# result <rc> <name> <detail>: one line, one count.
result() {
  CHECKS=$((CHECKS + 1))
  if [ "$1" -eq 0 ]; then
    echo "✅ $2: $3"
  else
    FAILED=$((FAILED + 1))
    echo "❌ $2: $3"
  fi
}

# run_check <name> <tool> <ok detail> <command...>: the tool must be installed,
# the command runs in the root with no stdin; a red check shows its output.
run_check() {
  local name="$1" tool="$2" okdetail="$3" out rc
  shift 3
  if ! command -v "$tool" >/dev/null 2>&1; then
    result 1 "$name" "$tool not installed"
    return 0
  fi
  out="$(cd "$ROOT" && "$@" < /dev/null 2>&1)" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    result 0 "$name" "$okdetail"
    return 0
  fi
  result 1 "$name" "exit ${rc}"
  printf '%s\n' "$out" | head -n 30 | sed 's/^/    /'
}

# Selecting the changed files.
if [ "${PRECHECK_CHANGED+set}" = set ]; then
  changed="$PRECHECK_CHANGED"
else
  if ! tracked="$(git -C "$ROOT" diff --name-only HEAD 2>&1)"; then
    echo "❌ FAIL: git diff --name-only HEAD failed in ${ROOT}: ${tracked}"
    exit 1
  fi
  if ! untracked="$(git -C "$ROOT" ls-files --others --exclude-standard 2>&1)"; then
    echo "❌ FAIL: git ls-files --others failed in ${ROOT}: ${untracked}"
    exit 1
  fi
  changed="${tracked}"$'\n'"${untracked}"
fi

# present: the changed paths that still exist, one per line, sorted, no repeat.
present=""
all=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  all="${all}${f}"$'\n'
  if [ -f "${ROOT}/${f}" ]; then
    present="${present}${f}"$'\n'
  fi
done <<< "$(printf '%s\n' "$changed" | sort -u)"

# files_matching <ere>: the present paths matching it, as arguments for a loop.
files_matching() {
  printf '%s' "$present" | grep -E "$1" || true
}

# to_array <name> <newline list>: fills the array without mapfile (bash 3.2).
to_array() {
  local name="$1" line
  eval "$name=()"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    eval "$name+=(\"\$line\")"
  done <<< "$2"
}

ALREADY=""

# run_script_check <name> <script> <ok detail> [args...]: a gate script of GATES_DIR.
run_script_check() {
  local name="$1" script="$2" okdetail="$3"
  shift 3
  ALREADY="${ALREADY} ${script}"
  run_check "$name" bash "$okdetail" "${GATES_DIR}/${script}" "$@"
}

run_shellcheck() {
  local files
  to_array files "$(files_matching '\.sh$')"
  [ "${#files[@]}" -gt 0 ] || return 0
  run_check "shellcheck" shellcheck "${#files[@]} file(s)" env SHELLCHECK_ROOT="$ROOT" "${GATES_DIR}/check_shellcheck.sh" "${files[@]}"
}

run_workflow_checks() {
  local wf yml abs f
  to_array wf "$(files_matching '^\.github/workflows/[^/]*\.yml$')"
  if [ "${#wf[@]}" -gt 0 ]; then
    abs=()
    for f in "${wf[@]}"; do abs+=("${ROOT}/${f}"); done
    run_check "actionlint" actionlint "${#wf[@]} workflow(s)" "${GATES_DIR}/check_actionlint.sh" "${ROOT}/.github/workflows" "${abs[@]}"
  fi
  to_array yml "$(files_matching '^\.github/.*\.ya?ml$')"
  if [ "${#yml[@]}" -gt 0 ]; then
    run_check "zizmor" zizmor "${#yml[@]} file(s) changed, the .github directory scanned" "${GATES_DIR}/check_zizmor.sh" "${ROOT}/.github"
  fi
}

run_yamllint() {
  local files
  to_array files "$(files_matching '\.ya?ml$')"
  [ "${#files[@]}" -gt 0 ] || return 0
  run_check "yamllint" yamllint "${#files[@]} file(s)" env YAMLLINT_ROOT="$ROOT" "${GATES_DIR}/check_yamllint.sh" "${files[@]}"
}

run_go_checks() {
  [ -n "$(files_matching '\.go$')" ] || return 0
  run_check "gofmt" gofmt "no Go file unformatted" "${GATES_DIR}/check_gofmt.sh" "$ROOT"
  run_check "go lint" go "golangci-lint found no issue" "${GATES_DIR}/check_go_lint.sh" "$ROOT"
}

run_repo_checks() {
  if [ -n "$(files_matching '^Scripts/')" ] || printf '%s' "$all" | grep -qxF 'Scripts/gate_report_order.txt'; then
    run_script_check "gate wiring" test_gate_wiring.sh "the order file, sfl and CI agree"
  fi
  if [ -n "$(files_matching '^Scripts/test_[^/]*\.sh$')" ]; then
    run_script_check "git sandbox guard" test_git_sandbox_guard.sh "every git-using self-test sources the sandbox"
  fi
  if [ -n "$(files_matching '\.md$')" ]; then
    run_script_check "markdown links" check_markdown_links.sh "every relative link resolves" "$ROOT"
  fi
}

# run_mentioned_tests: every Scripts/test_*.sh in the root whose source names
# the basename of a changed path, each once, not one a check above ran.
run_mentioned_tests() {
  local f base broad tests t seen=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f")"
    for broad in $TOO_BROAD; do
      [ "$base" = "$broad" ] && continue 2
    done
    tests="$(grep -lF -- "$base" "${ROOT}"/Scripts/test_*.sh 2>/dev/null || true)"
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      case " ${seen} ${ALREADY} " in *" $(basename "$t") "*) continue ;; esac
      seen="${seen} $(basename "$t")"
      run_check "test $(basename "$t")" bash "mentions ${base}" "$t"
    done <<< "$tests"
  done <<< "$all"
}

run_shellcheck
run_workflow_checks
run_yamllint
run_go_checks
run_repo_checks
run_mentioned_tests

echo "precheck: ${CHECKS} checks, ${FAILED} failed"
echo "elapsed: ${SECONDS}s"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
