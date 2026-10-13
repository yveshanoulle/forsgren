#!/usr/bin/env bash
# Scripts/test_check_exit_trap_completion.sh
#
# Self-test of Scripts/check_exit_trap_completion.sh (forsgren#137): fixture
# trees, a flagged script and the clean shapes beside it, plus a mutation proof
# per pattern. Fixtures are written under $TMP, never the real tree.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_exit_trap_completion.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "exit-trap completion self-test"

# new_root <name> <script-path> — a tree holding one script, its text read
# from stdin (a quoted heredoc at the call, so the fixture text is data and
# never a single-quoted shell string).
new_root() {
  ROOT="$TMP/$1"
  mkdir -p "$ROOT/$(dirname "$2")"
  cat > "$ROOT/$2"
}

# flagged_script — the text of a script the gate must flag, trap on line 4.
flagged_script() {
  cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo work
EOF
}

new_root flagged Scripts/a.sh < <(flagged_script)
capture "$GATE" "$ROOT"
want_red "1. set -e, an EXIT trap and no completion flag is red, with file:line of the trap" "Scripts/a.sh:4 runs under set -e (line 2) with an EXIT trap and no COMPLETED flag"

new_root flaggedroot a.sh < <(flagged_script)
capture "$GATE" "$ROOT"
want_red "2. a script at the repository root is read too" "a.sh:4 runs under set -e"

new_root completed Scripts/a.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || exit 1' EXIT
echo work
COMPLETED=1
EOF
capture "$GATE" "$ROOT"
want_green_ok "3. a COMPLETED flag is clean"

new_root selftest Scripts/a.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source Scripts/lib_selftest.sh
selftest_begin "x"
trap 'selftest_cleanup' EXIT
EOF
capture "$GATE" "$ROOT"
want_green_ok "4. selftest_begin (lib_selftest.sh) is clean"

new_root noerrexit Scripts/a.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
trap 'rm -rf x' EXIT
EOF
capture "$GATE" "$ROOT"
want_green_ok "5. set -uo without -e is not read: the quirk needs errexit"

new_root notrap Scripts/a.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo work
EOF
capture "$GATE" "$ROOT"
want_green_ok "6. no EXIT trap is clean"

new_root indented Scripts/a.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
f() {
  trap 'rm -rf x' EXIT
}
EOF
capture "$GATE" "$ROOT"
want_green_ok "7. an indented trap is not top-level and is clean"

new_root setafter Scripts/a.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
trap 'rm -rf x' EXIT
set -e
EOF
capture "$GATE" "$ROOT"
want_green_ok "8. a set -e after the trap is not read"

new_root two Scripts/a.sh < <(flagged_script)
flagged_script > "$ROOT/Scripts/b.sh"
capture "$GATE" "$ROOT"
want_red "9. every flagged script is named, with a count" "2 script(s) can end an abort with exit 0"

mkdir -p "$TMP/empty"
capture "$GATE" "$TMP/empty"
want_red "10. a tree with no script is red: nothing scanned is not clean" "nothing scanned is not clean"

capture "$GATE" "$TMP/missing"
want_rc "11. a missing root exits 2" 2

# Mutation proofs: the flagged fixture is red BECAUSE of each pattern.
mutate() {
  mkdir -p "$TMP/mutant-$1/Scripts"
  selftest_mutant_green "$GATE" "$TMP/mutant-$1/Scripts/check_exit_trap_completion.sh" \
    "s|^$1=.*|$1='$2'|" "$TMP/flagged" \
    "$3 turns case 1 green, so it is red because of the pattern" \
    "with $1 neutralised the flagged fixture is still red"
}
mutate COMPLETION '.' "a completion pattern that matches anything"
mutate SET_E 'NEVER-MATCHES-ANY-SET-LINE' "a set pattern that never matches"
mutate EXIT_TRAP 'NEVER-MATCHES-ANY-TRAP-LINE' "a trap pattern that never matches"

selftest_end "the exit-trap completion gate does not flag a set -e script with an EXIT trap and no completion flag" \
  "exit-trap completion gate is red on set -e with an EXIT trap and no COMPLETED flag (root and Scripts/, every script named), a tree with no script and exits 2 on a missing root, is green on a COMPLETED flag, selftest_begin, no -e, no trap, an indented trap and a set -e after the trap, and its patterns are what redden the case"
