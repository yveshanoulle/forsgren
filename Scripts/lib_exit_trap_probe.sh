#!/usr/bin/env bash
# canon: lib_exit_trap_probe v1
# Scripts/lib_exit_trap_probe.sh
#
# The shared engine of the exit-trap behaviour test,
# byte-identical across the estate's repositories. SOURCED, never run. The
# per-repository part is the test that sources it
# (Scripts/test_exit_trap_completion_behaviour.sh): its cases name the scripts
# and what each needs before its trap.
#
# What it probes. On bash 3.2 (macOS /bin/bash) a script under `set -e -u`
# with an EXIT trap ends with status 0 after an unbound variable in the main
# shell. A script that carries the COMPLETED idiom has a trap that turns an
# exit of 0 without COMPLETED=1 into exit 1. The gate
# (Scripts/check_exit_trap_completion.sh) reads the source for the idiom; this
# engine runs the real script: it copies it into a sandbox, injects
# `: "${PROBE_VAR}"` (an unbound variable) on the line right after its first
# top-level EXIT trap (found by grep, so it follows edits), runs it under
# /bin/bash with the setup the case gives, and requires
#   - the probe named on stderr (it aborted there, not earlier),
#   - a non-zero exit,
#   - the 'aborted before completing' line,
#   - no temp path left behind (the trap still cleans up),
#   - and, when the case sets PROBE_EXPECT_OUT, that text on stdout.
#
# It needs the sourcing test to have run selftest_begin
# (Scripts/lib_selftest.sh), for TMP, fail and the closing verdict.
#
# The scripts the gate knows are DERIVED, not listed: probe_trapped_scripts
# applies the gate's own rule (a top-level `set -...e...` line before a
# top-level `trap ... EXIT` line, at the root and in Scripts/), and
# probe_require_all fails for each such script that has no probe_case and no
# probe_exempt, so a new script cannot join the gate's scope unprobed.

PROBE_VAR="PROBE_UNSET_VARIABLE"
PROBE_SEEN=""
PROBE_EXPECT_OUT=""

# probe_trapped_scripts <root>: the root-relative paths the gate's rule covers.
probe_trapped_scripts() {
  local root="$1" file trap_line set_line
  for file in "$root"/*.sh "$root"/Scripts/*.sh; do
    [[ -f "$file" ]] || continue
    trap_line="$(grep -nE -m 1 '^trap .* EXIT' "$file" | cut -d: -f1 || true)"
    [[ -n "$trap_line" ]] || continue
    set_line="$(grep -nE -m 1 '^set +-[A-Za-z]*e[A-Za-z]*( |$)' "$file" | cut -d: -f1 || true)"
    [[ -n "$set_line" ]] || continue
    [[ "$set_line" -lt "$trap_line" ]] || continue
    echo "${file#"$root"/}"
  done
}

# probe_sandbox <dir> <relpath> <root>: <dir> holds a copy of <root>/Scripts/
# and the root's *.sh, with <relpath> replaced by itself plus the probe right
# after its top-level EXIT trap; bin/ with a mktemp stub and a say stub; tmp/,
# where the stub puts every temp path. Returns 1 when the script has no such
# trap to probe.
probe_sandbox() {
  local dir="$1" rel="$2" root="$3" inject
  mkdir -p "$dir/bin" "$dir/tmp"
  cp -R "$root/Scripts" "$dir/Scripts"
  cp "$root"/*.sh "$dir/" 2>/dev/null || true
  inject="$(grep -nE -m 1 '^trap .* EXIT' "$root/$rel" | cut -d: -f1 || true)"
  [[ -n "$inject" ]] || return 1
  awk -v n="$inject" -v v="$PROBE_VAR" '{ print } NR == n { print ": \"${" v "}\"" }' \
    "$root/$rel" > "$dir/$rel"
  chmod +x "$dir/$rel"
  # macOS mktemp ignores TMPDIR, so a stub puts every temp path of the run in
  # $dir/tmp, where the leftovers are counted. Only the two forms used.
  cat > "$dir/bin/mktemp" <<STUB
#!/usr/bin/env bash
if [ "\${1:-}" = "-d" ]; then exec /usr/bin/mktemp -d "$dir/tmp/tmp.XXXXXXXX"; fi
exec /usr/bin/mktemp "$dir/tmp/tmp.XXXXXXXX"
STUB
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/say"
  chmod +x "$dir/bin/mktemp" "$dir/bin/say"
}

# probe_verdict <name> <rel> <dir> <rc>: judges the run in <dir>, which exited <rc>.
probe_verdict() {
  local name="$1" rel="$2" dir="$3" rc="$4" out err left held=true
  out="$(cat "$dir/out.log")"
  err="$(cat "$dir/err.log")"
  left="$(find "$dir/tmp" -mindepth 1 | head -n 3)"
  if ! grep -Fq "${PROBE_VAR}: unbound variable" <<< "$err"; then
    fail "${name}: the probe never aborted the run (exit ${rc}), so nothing was tested. stderr: ${err}"
    return
  fi
  if [[ "$rc" -eq 0 ]]; then
    fail "${name}: an abort after ${rel}'s EXIT trap exits 0 — a caller takes that as a pass. stdout: ${out}"
    held=false
  fi
  if ! grep -Fq "aborted before completing" <<< "${err}${out}"; then
    fail "${name}: an abort after ${rel}'s EXIT trap printed no 'aborted before completing' line. stderr: ${err}"
    held=false
  fi
  if [[ -n "$left" ]]; then
    fail "${name}: ${rel} left a temp path behind (its trap must still clean up): ${left}"
    held=false
  fi
  if [[ -n "$PROBE_EXPECT_OUT" ]] && ! grep -Fq "$PROBE_EXPECT_OUT" <<< "$out"; then
    fail "${name}: the output does not say '${PROBE_EXPECT_OUT}'. stdout: ${out}"
    held=false
  fi
  if $held; then
    echo "  ok: ${name}: an abort after ${rel}'s EXIT trap exits ${rc}, says 'aborted before completing' and leaves no temp path"
  fi
}

# probe_case <name> <rel> <root> <setup-function> [script args...]: probes
# <root>/<rel> in the sandbox $TMP/<name> plus what <setup-function> adds
# (it gets the sandbox dir), and judges the run. The engine runs the script
# with the sandbox as its working directory and /bin/bash.
probe_case() {
  local name="$1" rel="$2" root="$3" setup="$4" dir rc=0
  shift 4
  PROBE_SEEN="${PROBE_SEEN} ${rel} "
  dir="$TMP/$name"
  if ! probe_sandbox "$dir" "$rel" "$root"; then
    fail "${name}: ${rel} has no top-level EXIT trap to probe, so nothing was tested"
    PROBE_EXPECT_OUT=""
    return
  fi
  "$setup" "$dir"
  (cd "$dir" && PATH="$dir/bin:$PATH" /bin/bash "./$rel" "$@" \
    > "$dir/out.log" 2> "$dir/err.log" < /dev/null) || rc=$?
  probe_verdict "$name" "$rel" "$dir" "$rc"
  PROBE_EXPECT_OUT=""
}

# probe_exempt <rel> <reason>: <rel> is deliberately not probed; the reason is
# printed, so an exemption is never silent.
probe_exempt() {
  PROBE_SEEN="${PROBE_SEEN} $1 "
  echo "  exempt: $1: $2"
}

# probe_require_all <root>: every script the gate's rule covers has a probe_case
# or a probe_exempt, and none was named that the rule does not cover.
probe_require_all() {
  local root="$1" rel rels
  rels="$(probe_trapped_scripts "$root")"
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    case "$PROBE_SEEN" in
      *" ${rel} "*) ;;
      *) fail "${rel} is in the gate's scope (set -e, then a top-level EXIT trap) and has no probe_case or probe_exempt" ;;
    esac
  done <<< "$rels"
  echo "  ok: every script the gate's rule covers has a case or an exemption"
}
