#!/usr/bin/env bash
# Scripts/test_check_go_lint.sh
#
# Self-test for Scripts/check_go_lint.sh, run before the gate it validates.
#
# NEW (forsgren#1, ladder step 20). Another estate repository runs golangci-lint in sfl and CI
# with no fixture, so nothing there shows its config catching what it exists
# to catch. A gate that has never been seen red is a hope.
#
# Each case is a throwaway Go module under one temp root, linted with THIS
# repository's .golangci.yml (or a mutation of it) and the golangci-lint
# pinned in go.mod. Each case asserts the exit code AND the reason:
#   1. a clean module                               -> green
#   2. a function with cyclomatic complexity 7      -> red, naming gocyclo
#   3. the same function in a _test.go file         -> red, naming gocyclo:
#                                                      test code is gated too
#   4. complexity 6, the threshold itself           -> green: gocyclo reports
#                                                      only what is ABOVE 6
#   5. a hardcoded credential-looking string        -> red, naming gosec G101
#      (Yves's ruling, forsgren#1: no G101 exclusion; this repository's
#      config must let it through as red)
#   6. MUTATION PROOF: the config with gocyclo's min-complexity raised to 7
#      turns case 2 green: the threshold in .golangci.yml is what reddens it
#   7. MUTATION PROOF: the config with another estate repository shared/'s blanket G101
#      exclusion appended turns case 5 green: case 5 is not vacuous, the
#      config is what judges it
#   8. a module with no Go package                  -> red: a lint over
#                                                      nothing is no pass
#   9. a module directory that does not exist       -> red
#  10. a config golangci-lint cannot load           -> red, as a tool error:
#      a linter that did not run is never mistaken for a clean result

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_go_lint.sh"
CONFIG=".golangci.yml"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "Go lint gate self-test"

[[ -x "$GATE" ]] || selftest_abort "the Go lint gate ${GATE} is missing (or not executable): nothing runs golangci-lint"
[[ -f "$CONFIG" ]] || selftest_abort "no ${CONFIG}: the Go lint gate has no config to judge with"

# new_module <name> — a module with one clean package `m`.
new_module() {
  MOD="${TMP}/$1"
  mkdir -p "$MOD"
  printf 'module example.com/m\n\ngo 1.26.1\n' > "${MOD}/go.mod"
  printf '// Package m is a lint fixture.\npackage m\n\n// Two returns 2.\nfunc Two() int { return 2 }\n' \
    > "${MOD}/m.go"
}

# write_branches <file> <ifs> — a function with <ifs> sequential `if`s:
# cyclomatic complexity <ifs> + 1, cognitive complexity <ifs> (below
# gocognit's 10), short enough for funlen.
write_branches() {
  local file="$1" ifs="$2" i
  {
    printf 'package m\n\n// Grade adds one for each threshold n passes.\nfunc Grade(n int) int {\n'
    for ((i = 1; i <= ifs; i++)); do
      printf '\tif n > %d {\n\t\tn++\n\t}\n' "$i"
    done
    printf '\treturn n\n}\n'
  } > "$file"
}

# run_gate [config] — runs the gate against $MOD; sets RC and OUT.
run_gate() {
  capture "$GATE" "$MOD" "${1:-$CONFIG}"
}

# mutate_config <name> <awk-program> — writes a mutation of .golangci.yml to
# $TMP/<name>.yml (golangci-lint reads the format from the extension) and
# sets MUTANT; fails the case when the mutation changed nothing.
mutate_config() {
  MUTANT="${TMP}/$1.yml"
  awk "$2" "$CONFIG" > "$MUTANT"
  if cmp -s "$CONFIG" "$MUTANT"; then
    fail "mutation $1 changed nothing in ${CONFIG}: the proof would be vacuous"
    return 1
  fi
}

# --- Case 1: a clean module.
new_module "clean"
run_gate
want_green_ok "a clean module is green"

# --- Case 2: cyclomatic complexity 7.
new_module "cyclo7"
write_branches "${MOD}/grade.go" 6
run_gate
want_red "complexity 7 is red, naming gocyclo" "(gocyclo)"
want_red "  ... and its complexity" "cyclomatic complexity 7"
CYCLO7="$MOD"

# --- Case 3: the same in a test file.
new_module "cyclo7-test"
write_branches "${MOD}/grade_test.go" 6
run_gate
want_red "complexity 7 in a _test.go file is red, naming gocyclo" "(gocyclo)"

# --- Case 4: complexity 6, the threshold itself.
new_module "cyclo6"
write_branches "${MOD}/grade.go" 5
run_gate
want_green_ok "complexity 6 is green (gocyclo reports above 6)"

# --- Case 5: a hardcoded credential-looking string.
new_module "g101"
# gosec's G101 judges a credential-named variable by its value's entropy, so
# a plain word ("hunter2") is not reported: the value is made up and
# random-looking. It is assembled from two halves because the secret scan
# reads this script and would take the whole literal for a leak; it is a
# fixture, not a secret, and needs no secret-scan allowlist entry.
CRED="$(printf '%s%s' 'f8Kq2xVz' '9Lw3Tn7R')"
printf 'package m\n\n// DBPassword is a hardcoded credential.\nvar DBPassword = "%s"\n' "$CRED" \
  > "${MOD}/cred.go"
run_gate
want_red "a hardcoded credential is red, naming gosec G101" "G101"
want_red "  ... reported by gosec" "(gosec)"
G101="$MOD"

# --- Case 6: MUTATION PROOF. gocyclo's threshold raised to 7.
# shellcheck disable=SC2016 # an awk program, not a shell expansion
if mutate_config "cyclo-raised" '
  /^    gocyclo:/ { in_cyclo = 1 }
  in_cyclo && /min-complexity:/ { sub(/min-complexity: *[0-9]+/, "min-complexity: 7"); in_cyclo = 0 }
  { print }'; then
  MOD="$CYCLO7"
  run_gate "$MUTANT"
  want_green_ok "mutation: gocyclo min-complexity 7 turns case 2 green"
fi

# --- Case 7: MUTATION PROOF. Another estate repository shared/'s blanket G101 exclusion.
if mutate_config "g101-excluded" '
  { print }
  /^    rules:$/ { print "      - linters: [gosec]"; print "        text: \"G101\"" }'; then
  MOD="$G101"
  run_gate "$MUTANT"
  want_green_ok "mutation: a blanket G101 exclusion turns case 5 green"
fi

# --- Case 7b: a cold runner (forsgren#210). `go tool -n` writes its
# "go: downloading ..." lines on stderr before it prints the path; a go shim
# does the same here. The gate must keep them out of the tool path.
SHIM="${TMP}/shim"
mkdir -p "$SHIM"
REAL_GO="$(command -v go)"
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n golangci-lint" ]]; then
  echo "go: downloading golang.org/x/tools v0.0.0" >&2
  echo "go: downloading golang.org/x/mod v0.0.0" >&2
fi
exec "$REAL_GO" "\$@"
EOF
chmod +x "${SHIM}/go"
new_module "cold"
capture env PATH="${SHIM}:${PATH}" "$GATE" "$MOD" "$CONFIG"
want_green_ok "cold runner: download lines on stderr of go tool -n do not reach the tool path"
if grep -qF -- "could not run" <<< "$OUT"; then
  fail "cold runner: the gate reported it could not run. Output: ${OUT}"
fi

# --- Case 7bb: MUTATION PROOF. The old 2>&1 capture put back (the -x check
# disabled too: it would catch the polluted path with its own message) is red
# on the cold runner as an exit 127.
if selftest_lib_mutant "$GATE" Scripts/lib_go_tool.sh "${TMP}/stderr-captured" '/go tool -n/s/1")"/1" 2>\&1)"/; s/^  if \[ ! -f .*$/  if false; then/'; then
  MUTANT_GATE="$MUTANT"
  capture env PATH="${SHIM}:${PATH}" "$MUTANT_GATE" "$MOD" "$(pwd)/${CONFIG}"
  want_red "mutation: with stderr captured into the tool path, a cold runner is red as the exit 127" "could not run"
fi

# --- Case 7bc: the path go prints is not a built binary: red with its reason.
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n golangci-lint" ]]; then
  echo "${TMP}/not-built/golangci-lint"
  exit 0
fi
exec "$REAL_GO" "\$@"
EOF
capture env PATH="${SHIM}:${PATH}" "$GATE" "$MOD" "$CONFIG"
want_red "a tool path that is not built is red, naming the reason" "was not built"

# --- Tool failure (forsgren#216): the tool itself fails. A go shim whose
# `go tool -n golangci-lint` names a stub tool that exits $STUB_TOOL_RC: the gate is red as
# a tool that did not run, and never prints the OK line of a pass. The stub says
# nothing: its exit code is the only sign it failed.
cat > "${TMP}/failing-tool" <<'EOF'
#!/bin/sh
exit "${STUB_TOOL_RC:-2}"
EOF
chmod +x "${TMP}/failing-tool"
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n golangci-lint" ]]; then
  echo "${TMP}/failing-tool"
  exit 0
fi
exec "$REAL_GO" "\$@"
EOF
capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=2 "$GATE" "$MOD" "$CONFIG"
want_red "a tool that exits 2 is red, never a pass" "could not run (exit 2)"
if grep -qF -- "OK:" <<< "$OUT"; then
  fail "a tool that exits 2 printed the OK line of a pass. Output: ${OUT}"
fi
capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=1 "$GATE" "$MOD" "$CONFIG"
want_red "a tool that exits 1 is red, never a pass" "FAIL"
if grep -qF -- "OK:" <<< "$OUT"; then
  fail "a tool that exits 1 printed the OK line of a pass. Output: ${OUT}"
fi

# MUTATION PROOF: a helper that swallows the tool's exit code turns the case
# above green, so Scripts/lib_go_tool.sh returning the tool's own code is what
# keeps check_go_lint.sh red here.
if selftest_lib_mutant "$GATE" Scripts/lib_go_tool.sh "${TMP}/swallowed" '/BIN" "/s/$/ || true/'; then
  capture env PATH="${SHIM}:${PATH}" STUB_TOOL_RC=2 "$MUTANT" "$MOD" "$(pwd)/${CONFIG}"
  want_green_ok "mutation: a helper that swallows the exit code lets the failing tool pass"
fi

# --- Lock (forsgren#437): golangci-lint takes a machine-wide file lock on
# start, so two gates in two checkouts at once refused each other ("parallel
# golangci-lint is running", exit 3) and read as a lint verdict. A stub
# stands in for the tool (the real one is never run here): it refuses with
# the lock message unless it is given --allow-parallel-runners, or always
# when $STUB_LOCK_ALWAYS is set. The gate must pass the flag, and a refusal
# that still comes must read as a tooling error naming the lock.
cat > "${TMP}/lock-tool" <<'EOF'
#!/bin/sh
if [ -z "${STUB_LOCK_ALWAYS:-}" ]; then
  for a in "$@"; do
    if [ "$a" = "--allow-parallel-runners" ]; then exit 0; fi
  done
fi
echo "Error: parallel golangci-lint is running"
exit 3
EOF
chmod +x "${TMP}/lock-tool"
cat > "${SHIM}/go" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "tool -n golangci-lint" ]]; then
  echo "${TMP}/lock-tool"
  exit 0
fi
exec "$REAL_GO" "\$@"
EOF
capture env PATH="${SHIM}:${PATH}" "$GATE" "$MOD" "$CONFIG"
want_green_ok "two runs at once: the gate passes --allow-parallel-runners, so the lock never refuses it"
capture env PATH="${SHIM}:${PATH}" STUB_LOCK_ALWAYS=1 "$GATE" "$MOD" "$CONFIG"
want_red "a lock refusal is a tooling error naming the lock" "holds golangci-lint's machine-wide lock"
want_said "  ... and says it is no verdict on the code" "not a verdict on the code"
want_said "  ... with the red cross FAIL line" "❌ FAIL"
if grep -qF -- "issue(s)" <<< "$OUT"; then
  fail "a lock refusal was counted as lint issues. Output: ${OUT}"
fi

# MUTATION PROOF: the gate without --allow-parallel-runners is refused by the
# lock, so the flag is what keeps two runs from failing each other.
if selftest_lib_mutant Scripts/lib_go_tool.sh "$GATE" "${TMP}/no-flag" 's/ --allow-parallel-runners//'; then
  capture env PATH="${SHIM}:${PATH}" "${TMP}/no-flag/Scripts/check_go_lint.sh" "$MOD" "$(pwd)/${CONFIG}"
  want_red "mutation: without the flag the lock refuses the gate" "holds golangci-lint's machine-wide lock"
fi

# --- Case 8: no Go package.
new_module "no-package"
rm "${MOD}/m.go"
run_gate
want_red "a module with no Go package is red" "no Go package to lint"

# --- Case 9: a module directory that does not exist.
MOD="${TMP}/nope"
run_gate
want_red "a missing module directory is red" "module directory not found"

# --- Case 10: a config golangci-lint cannot load.
new_module "bad-config"
printf 'version: "999"\n' > "${TMP}/bad.yml"
run_gate "${TMP}/bad.yml"
want_red "a config golangci-lint cannot load is red, as a tool error" "golangci-lint could not run"

selftest_end "the Go lint gate does not tell green from red" \
  "Go lint gate is red on complexity 7 (in production and test code), on a hardcoded credential (G101, not excluded), on no package, on a missing module and on a config that cannot load, green on a clean module and at complexity 6, and both mutations of .golangci.yml flip their case"
