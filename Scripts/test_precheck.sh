#!/usr/bin/env bash
# Scripts/test_precheck.sh
#
# Self-test of Scripts/precheck.sh (forsgren#231, step 1): the quick pre-check a
# writer runs before handing a change back. Every case drives it over a
# synthetic root (PRECHECK_ROOT) with an explicit list of changed files
# (PRECHECK_CHANGED, the seam for the list), with PRECHECK_GATES_DIR pointing at
# this repository's real gate scripts, so the real shellcheck and actionlint
# calls are the ones judged:
#   (a) a changed script with an SC2034 finding is red and names file and code;
#   (b) a changed workflow with an actionlint finding is red;
#   (c) a test that mentions the basename of a changed file is run;
#   (d) nothing changed: 'precheck: 0 checks', exit 0;
#   (e) a missing tool is red, never skipped;
#   (f) with no list given, the changed files are the tracked changes against
#       HEAD plus the untracked files that are not ignored;
#   (g) every gate script precheck runs is a row of the order file (parity).
# Mutation proofs: a precheck that skips the test-mention step is caught by (c),
# one that counts a missing tool as a pass by (e).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "precheck self-test"

PRECHECK="${REPO}/Scripts/precheck.sh"
if [[ ! -x "$PRECHECK" ]]; then
  selftest_abort "Scripts/precheck.sh is missing or not executable: nothing to test"
fi

# run_precheck <precheck> <root> <changed files, newline separated> [env...]
run_precheck() {
  local script="$1" root="$2" changed="$3"
  shift 3
  capture env PRECHECK_ROOT="$root" PRECHECK_GATES_DIR="${REPO}/Scripts" PRECHECK_CHANGED="$changed" "$@" "$script"
}

# make_root <name>: a synthetic root with a clean script and a stub test.
make_root() {
  local root="${TMP}/$1"
  mkdir -p "${root}/Scripts" "${root}/tools" "${root}/.github/workflows"
  printf '#!/usr/bin/env bash\necho hi\n' > "${root}/tools/clean.sh"
  printf '%s\n' "$root"
}

# (a) SC2034
root="$(make_root a)"
printf '#!/usr/bin/env bash\nunused=1\necho hi\n' > "${root}/tools/bad.sh"
run_precheck "$PRECHECK" "$root" "tools/bad.sh"
want_red "(a) a changed script with an unused variable is red" "❌ shellcheck"
want_said "(a) the red names the file" "tools/bad.sh"
want_said "(a) the red names the code" "SC2034"
want_said "(a) the summary counts the failure" "precheck: 1 checks, 1 failed"

# (b) actionlint
root="$(make_root b)"
cat > "${root}/.github/workflows/bad.yml" <<'YML'
name: Runner context in job env
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      ROWS: ${{ runner.temp }}/rows.md
    steps:
      - run: echo hi
YML
run_precheck "$PRECHECK" "$root" ".github/workflows/bad.yml"
want_red "(b) a changed workflow with an actionlint finding is red" "❌ actionlint"
want_said "(b) the red names the finding" "runner.temp"

# (c) a test that names the changed file's basename
root="$(make_root c)"
printf '#!/usr/bin/env bash\ntouch "%s/ran-stub"\n# reads clean.sh\n' "$TMP" > "${root}/Scripts/test_stub.sh"
chmod +x "${root}/Scripts/test_stub.sh"
run_precheck "$PRECHECK" "$root" "tools/clean.sh"
want_green "(c) a clean change is green" "precheck: 2 checks, 0 failed"
if [[ -f "${TMP}/ran-stub" ]]; then
  echo "  ok: (c) the test that mentions clean.sh ran"
else
  fail "(c) the test that mentions clean.sh did not run. Output: ${OUT}"
fi
want_said "(c) the run names the test" "test_stub.sh"
rm -f "${TMP}/ran-stub"
run_precheck "$PRECHECK" "$root" "README.md"
if [[ -f "${TMP}/ran-stub" ]]; then
  fail "(c) a too-broad basename (README.md) started a test"
else
  echo "  ok: (c) a too-broad basename starts no test"
fi

# (d) nothing changed
root="$(make_root d)"
run_precheck "$PRECHECK" "$root" ""
want_green "(d) nothing changed: zero checks, exit 0" "precheck: 0 checks, 0 failed"
want_said "(d) the elapsed time is printed" "elapsed:"

# (e) a missing tool
root="$(make_root e)"
if PATH=/usr/bin:/bin command -v shellcheck >/dev/null 2>&1; then
  fail "(e) shellcheck is on /usr/bin:/bin, so the missing-tool case cannot be staged here"
else
  run_precheck "$PRECHECK" "$root" "tools/clean.sh" PATH=/usr/bin:/bin
  want_red "(e) a missing tool is red, not skipped" "shellcheck not installed"
  want_said "(e) the red carries the cross" "❌ shellcheck"
fi

# (f) the changed files from git: tracked changes against HEAD, and untracked files
root="${TMP}/f"
mkdir -p "${root}/tools"
git -C "$root" init -q
printf '#!/usr/bin/env bash\necho one\n' > "${root}/tools/tracked.sh"
git -C "$root" add tools/tracked.sh
git -C "$root" -c user.name=t -c user.email=t@example.invalid commit -q -m base
printf '#!/usr/bin/env bash\necho two\n' > "${root}/tools/tracked.sh"
printf '#!/usr/bin/env bash\necho new\n' > "${root}/tools/fresh.sh"
capture env PRECHECK_ROOT="$root" PRECHECK_GATES_DIR="${REPO}/Scripts" "$PRECHECK"
want_green "(f) git detection runs" "precheck: 1 checks, 0 failed"
want_said "(f) the tracked change and the untracked file are both checked" "shellcheck: 2 file(s)"

# (g) parity: every gate script precheck runs is a row of the order file
capture "$PRECHECK" --gates
want_rc "(g) --gates lists the gate scripts" 0
gates=0
while IFS= read -r g; do
  [[ -n "$g" ]] || continue
  gates=$((gates + 1))
  if grep -qE "^[^#|]*\\|${g//./\\.}\\|" Scripts/gate_report_order.txt; then
    echo "  ok: (g) ${g} is a row of the order file"
  else
    fail "(g) precheck runs ${g}, which is not a row of Scripts/gate_report_order.txt: the two can drift"
  fi
done <<< "$OUT"
if [[ "$gates" -lt 9 ]]; then
  fail "(g) only ${gates} gate scripts listed: the list is broken, not the order file"
fi

# Mutation proofs
selftest_mutant "$PRECHECK" "${TMP}/m1/precheck.sh" 's/^run_mentioned_tests$/true/' || true
root="$(make_root m1)"
printf '#!/usr/bin/env bash\ntouch "%s/ran-stub"\n# reads clean.sh\n' "$TMP" > "${root}/Scripts/test_stub.sh"
chmod +x "${root}/Scripts/test_stub.sh"
rm -f "${TMP}/ran-stub"
run_precheck "${TMP}/m1/precheck.sh" "$root" "tools/clean.sh"
if [[ -f "${TMP}/ran-stub" ]]; then
  fail "mutation proof: a precheck without the test-mention step still ran the test, so (c) does not depend on that step"
else
  echo "  ok: mutation proof: a precheck that skips the test-mention step leaves the mentioning test unrun, which (c) catches"
fi

selftest_mutant "$PRECHECK" "${TMP}/m2/precheck.sh" $'s/result 1 "\\$name" "\\$tool not installed"/result 0 "$name" "$tool not installed"/' || true
root="$(make_root m2)"
run_precheck "${TMP}/m2/precheck.sh" "$root" "tools/clean.sh" PATH=/usr/bin:/bin
if [[ "$RC" -eq 0 ]]; then
  echo "  ok: mutation proof: a precheck that counts a missing tool as a pass exits 0, which (e) catches"
else
  fail "mutation proof: a precheck that counts a missing tool as a pass still exited ${RC}. Output: ${OUT}"
fi

selftest_end "the precheck does not do what its contract says" "precheck: shellcheck, actionlint, the test-mention step, the empty change, the missing tool, git detection and gate parity all hold"
