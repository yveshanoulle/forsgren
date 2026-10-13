#!/usr/bin/env bash
# Scripts/test_exit_trap_completion_behaviour.sh
#
# forsgren#137: the BEHAVIOUR behind Scripts/check_exit_trap_completion.sh. The
# gate reads source; this fixture runs the real scripts it once flagged.
#
# On bash 3.2 (macOS /bin/bash) a script under `set -e -u` with an EXIT trap
# ends with status 0 after an unbound variable in the main shell. The four
# scripts below now carry the COMPLETED idiom (their trap turns an exit of 0
# without COMPLETED=1 into exit 1). For each, this fixture copies the REAL
# script into a sandbox, injects `: "${G_PROBE}"` right after its top-level
# EXIT trap (the line is found by grep, so it follows edits), runs it with the
# minimal setup it needs, and requires:
#   - a non-zero exit,
#   - the probe named on stderr (so it aborted there, not earlier),
#   - the 'aborted before completing' FAIL line,
#   - no temp directory left behind (the trap still cleans up).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "exit-trap completion behaviour self-test"

PROBE_VAR="G_PROBE"

# probe_case <name> <script> <setup-function> [script args...] — the sandbox
# $TMP/<name> holds Scripts/<script> with the probe injected, bin/, tmp/ (where its
# mktemp stub puts every temp path) and whatever <setup-function> adds.
probe_case() {
  local name="$1" script="$2" setup="$3" dir inject out err rc left
  shift 3
  dir="$TMP/$name"
  mkdir -p "$dir/Scripts" "$dir/bin" "$dir/tmp"
  inject="$(grep -nE -m 1 '^trap .* EXIT' "$ROOT/Scripts/$script" | cut -d: -f1)"
  if [[ -z "$inject" ]]; then
    fail "${name}: Scripts/${script} has no top-level EXIT trap to probe, so nothing was tested"
    return
  fi
  awk -v n="$inject" -v v="$PROBE_VAR" '{ print } NR == n { print ": \"${" v "}\"" }' \
    "$ROOT/Scripts/$script" > "$dir/Scripts/$script"
  chmod +x "$dir/Scripts/$script"
  # macOS mktemp ignores TMPDIR, so a stub puts every temp path of the run in
  # $dir/tmp, where the leftovers are counted. Only the two forms the scripts use.
  cat > "$dir/bin/mktemp" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "-d" ]; then exec /usr/bin/mktemp -d "$dir/tmp/tmp.XXXXXXXX"; fi
exec /usr/bin/mktemp "$dir/tmp/tmp.XXXXXXXX"
EOF
  chmod +x "$dir/bin/mktemp"
  "$setup" "$dir"
  rc=0
  (cd "$dir" && PATH="$dir/bin:$PATH" /bin/bash "./Scripts/$script" "$@" \
    > "$dir/out.log" 2> "$dir/err.log" < /dev/null) || rc=$?
  out="$(cat "$dir/out.log")"
  err="$(cat "$dir/err.log")"
  left="$(find "$dir/tmp" -mindepth 1 | head -n 3)"
  if ! grep -Fq "${PROBE_VAR}: unbound variable" <<< "$err"; then
    fail "${name}: the probe never aborted the run (exit ${rc}), so nothing was tested. stderr: ${err}"
    return
  fi
  local held=true
  if [[ "$rc" -eq 0 ]]; then
    fail "${name}: an abort after ${script}'s EXIT trap exits 0 — a caller takes that as a pass. stdout: ${out}"
    held=false
  fi
  if ! grep -Fq "aborted before completing" <<< "$err"; then
    fail "${name}: an abort after ${script}'s EXIT trap printed no 'aborted before completing' line. stderr: ${err}"
    held=false
  fi
  if [[ -n "$left" ]]; then
    fail "${name}: ${script} left a temp directory behind (its trap must still clean up): ${left}"
    held=false
  fi
  if $held; then
    echo "  ok: ${name}: an abort after ${script}'s EXIT trap exits ${rc}, says 'aborted before completing' and leaves no temp directory"
  fi
}

# 1. build_site.sh: a stub go (the probe is hit before anything is rendered).
setup_build_site() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/bin/go"
  chmod +x "$1/bin/go"
}
probe_case build_site build_site.sh setup_build_site

# 2. gate_htmlhint.sh: a stub htmlhint that scans one file, a site dir, a config.
setup_gate_htmlhint() {
  mkdir -p "$1/node_modules/.bin" "$1/site"
  printf '#!/usr/bin/env bash\necho "Scanned 1 files"\n' > "$1/node_modules/.bin/htmlhint"
  chmod +x "$1/node_modules/.bin/htmlhint"
  : > "$1/.htmlhintrc"
}
probe_case gate_htmlhint gate_htmlhint.sh setup_gate_htmlhint site

# 3. test_sfl_pull.sh: sources Scripts/sfl_pull.sh after the trap.
setup_test_sfl_pull() {
  cp "$ROOT/Scripts/sfl_pull.sh" "$1/Scripts/sfl_pull.sh"
}
probe_case test_sfl_pull test_sfl_pull.sh setup_test_sfl_pull

# 4. test_validate_required_pages.sh: needs nothing before its trap.
setup_nothing() { :; }
probe_case test_validate_required_pages test_validate_required_pages.sh setup_nothing

selftest_end "an abort after the EXIT trap of build_site.sh, gate_htmlhint.sh, test_sfl_pull.sh or test_validate_required_pages.sh exits 0, prints no 'aborted before completing', or leaves a temp directory" \
  "an abort after the EXIT trap of build_site.sh, gate_htmlhint.sh, test_sfl_pull.sh and test_validate_required_pages.sh exits non-zero, says 'aborted before completing' and leaves no temp directory"
