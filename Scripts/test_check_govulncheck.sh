#!/usr/bin/env bash
# Scripts/test_check_govulncheck.sh
#
# Self-test for Scripts/check_govulncheck.sh, run before the gate it
# validates.
#
# NEW (forsgren#1, ladder step 23). Another estate repository runs govulncheck in sfl
# (run_go_vuln_check) and in CI with no fixture, behind a reachability probe
# of vuln.go.dev that turns "offline" into a skip. Nothing there shows the
# check red on a vulnerable call, nor the offline path a skip rather than a
# pass or a tool error.
#
# OFFLINE, ON PURPOSE. Every case runs against a vulnerability database the
# self-test writes itself (a file:// URL, passed through FORSGREN_VULN_DB),
# holding one made-up entry, GO-2099-0001: the standard library's
# strings.ToUpper, affected from version 0 with no fix. So the cases need no
# network, and their verdict does not move when vuln.go.dev publishes. The
# offline case points FORSGREN_VULN_DB at http://127.0.0.1:9 (the discard
# port: nothing listens, the connection is refused at once).
#
# Each case asserts the exit code AND the reason:
#   1. a module that calls strings.ToUpper             -> red, naming
#                                                          GO-2099-0001
#   2. FIXTURE MUTATION: the same module against a database with no entry
#      -> green: the entry, nothing else, is what reddened case 1
#   3. a module that imports strings but calls only ToLower -> green:
#      govulncheck judges the symbols the code reaches
#   4. the database unreachable (offline)              -> a ⚠️ SKIP line and
#      exit 0: not red, and NOT a silent green (no OK line, the skip says
#      the check did not run and why)
#  4b. the database unreachable and FORSGREN_VULN_DB_REQUIRED=1 (the scheduled
#      run, forsgren#87) -> red, naming the variable and the database: no skip,
#      no pass; 4c. required and reachable -> the same verdicts as without
#   5. MUTATION PROOF: the gate with its reachability probe disabled is red
#      on case 4 as a tool error: the probe is what makes offline a skip
#  5b. a cold runner (forsgren#210): `go tool -n` prints download lines on
#      stderr -> green; 5c. a tool path that is not built -> red; 5d. MUTATION
#      PROOF: the old 2>&1 capture is red there as the exit 127
#   6. a module with no Go package                     -> red: a scan over
#                                                          nothing is no pass
#   7. a module directory that does not exist          -> red

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_govulncheck.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "vulnerability gate self-test"

[[ -x "$GATE" ]] || selftest_abort "the vulnerability gate ${GATE} is missing (or not executable): nothing runs govulncheck"

OFFLINE_DB="http://127.0.0.1:9"

# write_db <dir> <modules.json body> — a vulnerability database in the
# layout govulncheck reads (https://go.dev/security/vuln/database#api).
write_db() {
  mkdir -p "$1/index" "$1/ID"
  printf '{"modified":"2026-01-01T00:00:00Z"}\n' > "$1/index/db.json"
  printf '%s\n' "$2" > "$1/index/modules.json"
  cat > "$1/ID/GO-2099-0001.json" <<'EOF'
{"schema_version":"1.3.1","id":"GO-2099-0001","modified":"2026-01-01T00:00:00Z","summary":"Made-up self-test entry: strings.ToUpper","details":"Not a real vulnerability; Scripts/test_check_govulncheck.sh writes it.","database_specific":{"url":"https://example.com/GO-2099-0001","review_status":"REVIEWED"},"affected":[{"package":{"name":"stdlib","ecosystem":"Go"},"ranges":[{"type":"SEMVER","events":[{"introduced":"0"}]}],"ecosystem_specific":{"imports":[{"path":"strings","symbols":["ToUpper"]}]}}]}
EOF
}

VULN_DB="file://${TMP}/db"
write_db "${TMP}/db" '[{"path":"stdlib","vulns":[{"id":"GO-2099-0001","modified":"2026-01-01T00:00:00Z"}]}]'
EMPTY_DB="file://${TMP}/empty-db"
write_db "${TMP}/empty-db" '[]'

# new_module <name> <strings function> — a main package that prints
# strings.<function>("x").
new_module() {
  MOD="${TMP}/$1"
  mkdir -p "$MOD"
  printf 'module example.com/m\n\ngo 1.26.1\n' > "${MOD}/go.mod"
  printf 'package main\n\nimport (\n\t"fmt"\n\t"strings"\n)\n\nfunc main() { fmt.Println(strings.%s("x")) }\n' "$2" \
    > "${MOD}/main.go"
}

# run_gate <database> [gate] — runs the gate against $MOD; sets RC and OUT.
run_gate() {
  capture env FORSGREN_VULN_DB="$1" "${2:-$GATE}" "$MOD"
}

# want_skip <case> — the last run exited 0 with the ⚠️ SKIP line naming the
# unreachable database, and without the OK line a pass prints.
want_skip() {
  if [[ "$RC" -ne 0 ]]; then
    fail "$1: the gate exited ${RC}, a skip exits 0. Output: ${OUT}"
  elif ! grep -qF -- "⚠️ SKIP: govulncheck did not run" <<< "$OUT"; then
    fail "$1: the gate exited 0 without its ⚠️ SKIP line: a silent green. Output: ${OUT}"
  elif ! grep -qF -- "$OFFLINE_DB" <<< "$OUT"; then
    fail "$1: the skip does not name the unreachable database ${OFFLINE_DB}. Output: ${OUT}"
  elif grep -qF -- "OK:" <<< "$OUT"; then
    fail "$1: a skip printed the OK line of a pass. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# mutant <name> <sed-expression> — a mutated copy of the gate at
# $TMP/<name>/Scripts/, with this repository's go.mod and go.sum beside it so
# `go tool -n govulncheck` resolves the same pinned govulncheck there; sets
# MUTANT, or fails the case when the edit changed nothing (a vacuous proof).
mutant() {
  MUTANT="${TMP}/$1/Scripts/check_govulncheck.sh"
  selftest_mutant "$GATE" "$MUTANT" "$2" || return 1
  cp go.mod go.sum "${TMP}/$1/"
  cp Scripts/lib_go_tool.sh "${TMP}/$1/Scripts/"
}

# --- Case 1: a call to the vulnerable symbol.
new_module "calls-toupper" "ToUpper"
run_gate "$VULN_DB"
want_red "a call to a vulnerable symbol is red, naming the entry" "GO-2099-0001"
want_red "  ... as a finding, not a tool error" "govulncheck found"
CALLS="$MOD"

# --- Case 2: FIXTURE MUTATION. No entry in the database.
MOD="$CALLS"
run_gate "$EMPTY_DB"
want_green_ok "mutation: case 1 against a database without the entry is green"

# --- Case 3: the package imported, the symbol not called.
new_module "calls-tolower" "ToLower"
run_gate "$VULN_DB"
want_green_ok "importing strings without calling ToUpper is green"

# --- Case 4: offline.
MOD="$CALLS"
run_gate "$OFFLINE_DB"
want_skip "an unreachable database is a ⚠️ skip, neither red nor a silent green"

# --- Case 4b: offline where the verdict is required (the scheduled run,
# forsgren#87): an unreachable database is red, never a skip and never a pass.
MOD="$CALLS"
capture env FORSGREN_VULN_DB="$OFFLINE_DB" FORSGREN_VULN_DB_REQUIRED=1 "$GATE" "$MOD"
want_red "a required database that is unreachable is red, not a skip" "FORSGREN_VULN_DB_REQUIRED"
want_said "  ... naming the database" "$OFFLINE_DB"
if grep -qF -- "SKIP" <<< "$OUT" || grep -qF -- "OK:" <<< "$OUT"; then
  fail "a required database that is unreachable printed a skip or an OK line. Output: ${OUT}"
fi

# --- Case 4c: required, and the database answers: the verdicts are the same.
MOD="$CALLS"
capture env FORSGREN_VULN_DB="$VULN_DB" FORSGREN_VULN_DB_REQUIRED=1 "$GATE" "$MOD"
want_red "required and reachable: a vulnerable call is still red as a finding" "govulncheck found"
capture env FORSGREN_VULN_DB="$EMPTY_DB" FORSGREN_VULN_DB_REQUIRED=1 "$GATE" "$MOD"
want_green_ok "required and reachable: a clean scan is still green"

# --- Case 5: MUTATION PROOF. The reachability probe disabled.
if mutant "no-probe" 's/^if ! curl /if false \&\& ! curl /'; then
  run_gate "$OFFLINE_DB" "$MUTANT"
  want_red "mutation: without the probe, offline is red as a tool error" "govulncheck could not run"
fi

# --- Case 5b: a cold runner (forsgren#210). `go tool -n` writes its
# "go: downloading ..." lines on stderr before it prints the path; a go shim
# does the same here. The gate must keep them out of the tool path.
SHIM="${TMP}/shim"
mkdir -p "$SHIM"
REAL_GO="$(command -v go)"
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n govulncheck" ]]; then
  echo "go: downloading golang.org/x/vuln v0.0.0" >&2
  echo "go: downloading golang.org/x/mod v0.0.0" >&2
fi
exec "$REAL_GO" "\$@"
EOF
chmod +x "${SHIM}/go"
MOD="$CALLS"
capture env PATH="${SHIM}:${PATH}" FORSGREN_VULN_DB="$EMPTY_DB" "$GATE" "$MOD"
want_green_ok "cold runner: download lines on stderr of go tool -n do not reach the tool path"
if grep -qF -- "could not run" <<< "$OUT"; then
  fail "cold runner: the gate reported it could not run. Output: ${OUT}"
fi

# --- Case 5d: MUTATION PROOF for 5b. The old capture (2>&1) put back is red
# on the cold runner as the exit 127 of forsgren#210 (the -x check is
# disabled too: it would catch the polluted path with its own message).
if selftest_lib_mutant "$GATE" Scripts/lib_go_tool.sh "${TMP}/stderr-captured" '/go tool -n/s/1")"/1" 2>\&1)"/; s/^  if \[ ! -f .*$/  if false; then/'; then
  capture env PATH="${SHIM}:${PATH}" FORSGREN_VULN_DB="$EMPTY_DB" "$MUTANT" "$MOD"
  want_red "mutation: with stderr captured into the tool path, a cold runner is red as the exit 127" "could not run (exit 127)"
fi

# --- Case 5c: the path go prints is not a built binary: red with its reason.
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n govulncheck" ]]; then
  echo "${TMP}/not-built/govulncheck"
  exit 0
fi
exec "$REAL_GO" "\$@"
EOF
capture env PATH="${SHIM}:${PATH}" FORSGREN_VULN_DB="$EMPTY_DB" "$GATE" "$MOD"
want_red "a tool path that is not built is red, naming the reason" "was not built"


# --- Tool failure (forsgren#216): the tool itself fails. A go shim whose
# `go tool -n govulncheck` names a stub tool that exits $STUB_TOOL_RC: the gate is red as
# a tool that did not run, and never prints the OK line of a pass. The stub says
# nothing: its exit code is the only sign it failed.
cat > "${TMP}/failing-tool" <<'EOF'
#!/bin/sh
exit "${STUB_TOOL_RC:-2}"
EOF
chmod +x "${TMP}/failing-tool"
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n govulncheck" ]]; then
  echo "${TMP}/failing-tool"
  exit 0
fi
exec "$REAL_GO" "\$@"
EOF
capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=2 FORSGREN_VULN_DB="$EMPTY_DB" "$GATE" "$MOD"
want_red "a tool that exits 2 is red, never a pass" "could not run (exit 2)"
if grep -qF -- "OK:" <<< "$OUT"; then
  fail "a tool that exits 2 printed the OK line of a pass. Output: ${OUT}"
fi
capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=1 FORSGREN_VULN_DB="$EMPTY_DB" "$GATE" "$MOD"
want_red "a tool that exits 1 is red, never a pass" "could not run (exit 1)"
if grep -qF -- "OK:" <<< "$OUT"; then
  fail "a tool that exits 1 printed the OK line of a pass. Output: ${OUT}"
fi

# MUTATION PROOF: a helper that swallows the tool's exit code turns the case
# above green, so Scripts/lib_go_tool.sh returning the tool's own code is what
# keeps check_govulncheck.sh red here.
if selftest_lib_mutant "$GATE" Scripts/lib_go_tool.sh "${TMP}/swallowed" '/BIN" "/s/$/ || true/'; then
  capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=2 FORSGREN_VULN_DB="$EMPTY_DB" "$MUTANT" "$MOD"
  want_green_ok "mutation: a helper that swallows the exit code lets the failing tool pass"
fi

# --- Case 6: no Go package.
new_module "no-package" "ToLower"
rm "${MOD}/main.go"
run_gate "$VULN_DB"
want_red "a module with no Go package is red" "no Go package to scan"

# --- Case 7: a module directory that does not exist.
MOD="${TMP}/nope"
run_gate "$VULN_DB"
want_red "a missing module directory is red" "module directory not found"

selftest_end "the vulnerability gate does not tell a vulnerable call from a clean one, or offline from a pass" \
  "vulnerability gate is red on a call to a vulnerable symbol, on no package and on a missing module, green when the symbol is not called or the database has no entry, and an unreachable database is a ⚠️ skip, shown to come from the probe"
