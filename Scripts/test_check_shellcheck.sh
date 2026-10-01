#!/usr/bin/env bash
# Fixture test for Scripts/check_shellcheck.sh — the guard that keeps every
# tracked shell script under shellcheck, not just the ones a human
# remembered to name.
#
# Drives the checker against synthetic git trees (via SHELLCHECK_ROOT), so
# the pins never depend on this repo's real file layout — and so a fixture
# in server/sbin/ with a real shellcheck error proves the coverage gap
# (server/sbin/*.sh was never checked before target collection was
# derived) is actually closed, not just described.
#
# Pinned behaviours:
#   1. a clean synthetic tree (well-formed scripts only)         -> exit 0
#   2. a server/sbin/*.sh fixture with a real shellcheck finding -> exit 1,
#      naming that file (the coverage gap this test exists for)
#   3. the same finding, but the file sits under Scripts/ instead
#      (the glob this check always had)                          -> exit 1
#   4. an extension-less tracked file with a bash shebang and a real
#      finding is caught too                                     -> exit 1
#   5. an extension-less tracked file with NO shebang (e.g. a data
#      file with no extension) is left alone, clean tree stays    -> exit 0
#   6. a *.sh file that is merely mentioned in another file's text
#      (a comment, a doc) but not itself tracked is not invented
#      out of thin air                                            -> exit 0
#   7. an empty EXCLUDE_ALLOWED does not blow up on bash 3.2 under
#      `set -u` (same empty-string-not-array shape as
#      check_sfl_ci_parity.sh's SFL_ONLY_ALLOWED)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_UNDER_TEST="${ROOT}/Scripts/check_shellcheck.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failed=0
assert_log() { [[ -n "${ASSERTS_LOG:-}" ]] && echo "ASSERT: $1" >> "$ASSERTS_LOG" || true; }
ok()   { assert_log "check_shellcheck: $*"; echo "OK:   $*"; }
fail() { assert_log "check_shellcheck: $*"; echo "❌ FAIL: $*"; failed=1; }

indent_out() { echo "      ${1//$'\n'/$'\n'      }"; }

# make_case <case-dir> — an empty git repo (no identity needed: this check
# only ever calls `git ls-files`, which reads the index, never `git commit`).
make_case() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
}

# add_file <case-dir> <relative-path> <content> — writes and stages a file.
add_file() {
  local dir="$1" path="$2" content="$3"
  mkdir -p "$(dirname "${dir}/${path}")"
  printf '%s' "$content" > "${dir}/${path}"
  chmod +x "${dir}/${path}"
  git -C "$dir" add "$path"
}

# run_guard <case-dir> — sets RC and OUT.
run_guard() {
  local dir="$1"
  OUT="$(SHELLCHECK_ROOT="$dir" bash "$SCRIPT_UNDER_TEST" 2>&1)"
  RC=$?
}

CLEAN_SH='#!/usr/bin/env bash
set -euo pipefail
echo "hello"
'

# A finding real enough to fail the default invocation (SC2086: unquoted
# expansion) without needing any particular severity — any finding at all
# fails shellcheck's default exit code. The $1/$name below are literal
# fixture text being written to a file for the SCRIPT UNDER TEST to
# analyze, not a shell expansion in this test file: the quoted heredoc
# delimiter ('EOF') keeps them unexpanded. `read -d ''` keeps the trailing
# newline a `$(cat <<'EOF')` would strip, and returns 1 at end of input,
# hence `|| true`.
IFS= read -r -d '' BROKEN_SH <<'EOF' || true
#!/usr/bin/env bash
name=$1
echo $name
EOF

# 1. Clean synthetic tree.
A="$TMP/clean"
make_case "$A"
add_file "$A" "Scripts/ok.sh" "$CLEAN_SH"
add_file "$A" "server/sbin/ok.sh" "$CLEAN_SH"
run_guard "$A"
if [ "$RC" -eq 0 ]; then
  ok "a clean synthetic tree passes"
else
  fail "clean tree should pass, got exit $RC"
  indent_out "$OUT"
fi

# 2. The coverage gap this test exists for: server/sbin/*.sh was never
#    named anywhere in the old check, so a real error there went uncaught.
B="$TMP/sbin_broken"
make_case "$B"
add_file "$B" "Scripts/ok.sh" "$CLEAN_SH"
add_file "$B" "server/sbin/webinfra-example.sh" "$BROKEN_SH"
run_guard "$B"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'server/sbin/webinfra-example.sh'; then
  ok "a shellcheck error under server/sbin/ fails the guard, named"
else
  fail "server/sbin error should fail the guard and be named, got exit $RC"
  indent_out "$OUT"
fi

# 3. The same finding under Scripts/ — the glob this check always had,
#    pinned so target collection is proven on both an old and a new path.
C="$TMP/scripts_broken"
make_case "$C"
add_file "$C" "Scripts/broken.sh" "$BROKEN_SH"
run_guard "$C"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'Scripts/broken.sh'; then
  ok "a shellcheck error under Scripts/ still fails the guard, named"
else
  fail "Scripts/ error should fail the guard and be named, got exit $RC"
  indent_out "$OUT"
fi

# 4. Extension-less tracked file with a bash shebang: this check's second
#    target source. Its own name has no .sh to glob on.
D="$TMP/extensionless_broken"
make_case "$D"
add_file "$D" "server/sbin/webinfra-wrapper" "$BROKEN_SH"
run_guard "$D"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'server/sbin/webinfra-wrapper'; then
  ok "an extension-less bash-shebang file with a finding fails the guard, named"
else
  fail "extension-less shebang file should fail the guard and be named, got exit $RC"
  indent_out "$OUT"
fi

# 5. Extension-less tracked file with NO shebang (a data file, say) must
#    not be treated as a shell script — collection is shebang-gated, not
#    "every extension-less file".
E="$TMP/extensionless_data"
make_case "$E"
add_file "$E" "Scripts/ok.sh" "$CLEAN_SH"
add_file "$E" "data/manifest" "not a script, just data
"
run_guard "$E"
if [ "$RC" -eq 0 ]; then
  ok "an extension-less file with no shebang is left alone"
else
  fail "extension-less non-shebang file should not be shellchecked, got exit $RC"
  indent_out "$OUT"
fi

# 6. A *.sh name that only appears in another file's TEXT (a comment) but
#    is never itself written or staged must not be invented as a target —
#    collection reads `git ls-files`, not grep over file contents.
F="$TMP/mentioned_only"
make_case "$F"
add_file "$F" "Scripts/mentions.sh" '#!/usr/bin/env bash
# see also server/sbin/not-a-real-file.sh for details
echo "hi"
'
run_guard "$F"
if [ "$RC" -eq 0 ]; then
  ok "a filename only mentioned in a comment is not invented as a target"
else
  fail "comment-only filename should not be treated as a real target, got exit $RC"
  indent_out "$OUT"
fi

# 7. Empty EXCLUDE_ALLOWED does not trip an unbound-variable error on
#    bash 3.2 (checked against the last run's output — any of the passing
#    cases above already exercised this path).
if printf '%s\n' "$OUT" | grep -qi "unbound variable"; then
  fail "empty EXCLUDE_ALLOWED tripped an unbound-variable error"
  indent_out "$OUT"
else
  ok "empty EXCLUDE_ALLOWED expands safely"
fi

if [ "$failed" -ne 0 ]; then
  echo "❌ check_shellcheck fixture failed"
  exit 1
fi
echo "✅ check_shellcheck fixture passed"
