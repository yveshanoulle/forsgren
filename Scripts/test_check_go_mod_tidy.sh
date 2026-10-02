#!/usr/bin/env bash
# Scripts/test_check_go_mod_tidy.sh
#
# Self-test for Scripts/check_go_mod_tidy.sh, run before the gate it
# validates.
#
# NEW (forsgren#1, ladder step 23). MenoPower checks tidiness in CI and in
# its Makefiles (`go mod tidy`, then `git status --porcelain go.mod go.sum`)
# with no fixture. forsgren's gate is check-only (`go mod tidy -diff`): it
# must never rewrite go.mod, so a red here is a red, not a silent fix that
# rides into the commit.
#
# OFFLINE, ON PURPOSE. Each case is a throwaway module example.com/m that
# depends on a second throwaway module, example.com/dep, through a `replace`
# to its directory, and every go command here runs with GOPROXY=off: no case
# needs the network, so none can go red for a reason other than its own.
#
# Each case asserts the exit code AND the reason:
#   1. a tidy go.mod                                   -> green
#   2. a needed require missing                        -> red, the diff
#                                                         adding it shown
#   3. the gate left case 2's go.mod as it was         -> check-only
#   4. an unneeded require                             -> red, the diff
#                                                         removing it shown
#   5. FIXTURE MUTATION: case 2's go.mod after `go mod tidy` -> green: the
#      missing line, nothing else, is what reddened case 2
#   6. MUTATION PROOF: the gate with `go mod tidy -diff` turned into
#      `go mod tidy` is green on case 2 AND rewrites its go.mod: `-diff` is
#      what makes the gate red and keeps it from writing
#   7. a go.mod go cannot parse                        -> red, as a tool
#      error: a tidy that did not run is never a clean result
#   8. a module directory with no go.mod               -> red
#   9. a module directory that does not exist          -> red

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/check_go_mod_tidy.sh"

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "❌ FAIL: go mod tidy gate self-test aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

if [[ ! -x "$GATE" ]]; then
  echo "❌ FAIL: the go mod tidy gate ${GATE} is missing (or not executable): nothing checks go.mod and go.sum are tidy"
  COMPLETED=1
  exit 1
fi

export GOPROXY=off

failed=0
fail() {
  echo "❌ FAIL: $*"
  failed=1
}

mkdir -p "${TMP}/dep"
printf 'module example.com/dep\n\ngo 1.26.1\n' > "${TMP}/dep/go.mod"
printf '// Package dep is a tidy fixture.\npackage dep\n\n// One returns 1.\nfunc One() int { return 1 }\n' \
  > "${TMP}/dep/dep.go"

REQUIRE='require example.com/dep v0.0.0-00010101000000-000000000000'

# new_module <name> <imports dep: yes|no> <requires dep: yes|no> — the
# go.mod is written the way `go mod tidy` writes it.
new_module() {
  MOD="${TMP}/$1"
  mkdir -p "$MOD"
  {
    printf 'module example.com/m\n\ngo 1.26.1\n\nreplace example.com/dep => ../dep\n'
    if [[ "$3" == "yes" ]]; then
      printf '\n%s\n' "$REQUIRE"
    fi
  } > "${MOD}/go.mod"
  if [[ "$2" == "yes" ]]; then
    printf 'package m\n\nimport "example.com/dep"\n\n// Two returns 2.\nfunc Two() int { return dep.One() + 1 }\n' \
      > "${MOD}/m.go"
  else
    printf 'package m\n\n// Two returns 2.\nfunc Two() int { return 2 }\n' > "${MOD}/m.go"
  fi
}

# run_gate [gate] — runs the gate against $MOD; sets RC and OUT.
run_gate() {
  set +e
  OUT="$("${1:-$GATE}" "$MOD" 2>&1)"
  RC=$?
  set -e
}

want_green() {
  if [[ "$RC" -ne 0 ]]; then
    fail "$1: the gate exited ${RC}. Output: ${OUT}"
  elif ! grep -qF -- "OK:" <<< "$OUT"; then
    fail "$1: the gate exited 0 without its OK line. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# want_red <case> <reason> — the last run failed and said <reason>.
want_red() {
  if [[ "$RC" -eq 0 ]]; then
    fail "$1: the gate exited 0. Output: ${OUT}"
  elif ! grep -qF -- "$2" <<< "$OUT"; then
    fail "$1: the gate failed without saying '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

# mutant <name> <sed-expression> — a mutated copy of the gate at
# $TMP/<name>/Scripts/; sets MUTANT, or fails the case when the edit changed
# nothing (a vacuous proof).
mutant() {
  mkdir -p "${TMP}/$1/Scripts"
  MUTANT="${TMP}/$1/Scripts/check_go_mod_tidy.sh"
  sed "$2" "$GATE" > "$MUTANT"
  chmod +x "$MUTANT"
  if cmp -s "$GATE" "$MUTANT"; then
    fail "mutation $1 changed nothing in ${GATE}: the proof would be vacuous"
    return 1
  fi
}

# --- Case 1: tidy.
new_module "tidy" yes yes
run_gate
want_green "a tidy go.mod is green"

# --- Case 2: a needed require missing.
new_module "missing" yes no
cp "${MOD}/go.mod" "${TMP}/missing.go.mod"
run_gate
want_red "a missing require is red, as not tidy" "go.mod and go.sum are not tidy"
want_red "  ... the diff adds the require" "+${REQUIRE}"
MISSING="$MOD"

# --- Case 3: check-only.
if cmp -s "${TMP}/missing.go.mod" "${MISSING}/go.mod"; then
  echo "  ok: the gate left case 2's go.mod as it was (check-only)"
else
  fail "the gate rewrote case 2's go.mod: a check must never fix what it judges"
fi

# --- Case 4: an unneeded require.
new_module "unneeded" no yes
run_gate
want_red "an unneeded require is red, as not tidy" "go.mod and go.sum are not tidy"
want_red "  ... the diff removes the require" "-${REQUIRE}"

# --- Case 5: FIXTURE MUTATION. Case 2 after go mod tidy.
new_module "missing-tidied" yes no
(cd "$MOD" && go mod tidy >/dev/null 2>&1) || fail "go mod tidy failed on the case 5 fixture"
run_gate
want_green "mutation: case 2's module after go mod tidy is green"

# --- Case 6: MUTATION PROOF. The gate without -diff.
new_module "missing-no-diff" yes no
cp "${MOD}/go.mod" "${TMP}/no-diff.go.mod"
if mutant "no-diff" 's/go mod tidy -diff/go mod tidy/'; then
  run_gate "$MUTANT"
  want_green "mutation: without -diff, case 2 is green"
  if cmp -s "${TMP}/no-diff.go.mod" "${MOD}/go.mod"; then
    fail "mutation: without -diff, case 2's go.mod was not rewritten: the proof shows nothing"
  else
    echo "  ok: mutation: ... because it rewrote go.mod"
  fi
fi

# --- Case 7: a go.mod go cannot parse.
new_module "unparsable" yes yes
printf 'module example.com/m\n\ngo 1.26.1\n\nrequire (\n' > "${MOD}/go.mod"
run_gate
want_red "an unparsable go.mod is red, as a tool error" "go mod tidy could not run"

# --- Case 8: no go.mod.
new_module "no-go-mod" no no
rm "${MOD}/go.mod"
run_gate
want_red "a module directory with no go.mod is red" "no go.mod in"

# --- Case 9: a module directory that does not exist.
MOD="${TMP}/nope"
run_gate
want_red "a missing module directory is red" "module directory not found"

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: the go mod tidy gate does not tell a tidy go.mod from an untidy one (see the FAIL lines above)"
  exit 1
fi

echo "OK: go mod tidy gate is red on a missing and on an unneeded require, on an unparsable go.mod, on no go.mod and on a missing module, green on a tidy module, never rewrites go.mod, and -diff is shown to be what makes it red"
