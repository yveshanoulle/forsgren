#!/usr/bin/env bash
# Scripts/test_check_node_pin.sh
#
# Self-test for Scripts/check_node_pin.sh (forsgren#2), run before the gate it
# validates. A stub `node` printing $NODE_VERSION stands in for the real one;
# the gate runs from a copy of Scripts/ in a throwaway tree with its own pin.
#   1. running major equals the pin           -> green
#   2. a different major                      -> red, naming the running version,
#                                                the pin and `brew install node@26`
#   3. no node on PATH                        -> red, naming the pin and the fix
#   4. a bad pin file                         -> red
#   5. a node that prints garbage             -> red
# Mutation proof: a copy of the gate that does not compare the majors must
# accept case 2's node, so case 2 is red because of the comparison.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REAL_ROOT="$(pwd)"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "node pin gate self-test"

[[ -f Scripts/check_node_pin.sh ]] || selftest_abort "Scripts/check_node_pin.sh does not exist — nothing enforces the Node pin"

# new_tree <name> <pin content> [gate-copy] — a tree with Scripts/node_pin.sh,
# the gate (or the given copy) and a .nvmrc; sets TREE.
new_tree() {
  TREE="${TMP}/$1"
  mkdir -p "${TREE}/Scripts"
  cp "${REAL_ROOT}/Scripts/node_pin.sh" "${TREE}/Scripts/node_pin.sh"
  cp "${3:-${REAL_ROOT}/Scripts/check_node_pin.sh}" "${TREE}/Scripts/check_node_pin.sh"
  chmod +x "${TREE}/Scripts/"*.sh
  printf '%s' "$2" > "${TREE}/.nvmrc"
}

STUBS="${TMP}/bin"
mkdir -p "$STUBS"
cat > "${STUBS}/node" <<'STUB'
#!/usr/bin/env bash
echo "${NODE_VERSION}"
STUB
chmod +x "${STUBS}/node"
NONODE="${TMP}/nonode"
mkdir -p "$NONODE"

# run_gate <node-version> — the tree's gate with the stub node on PATH.
run_gate() {
  NODE_VERSION="$1" PATH="${STUBS}:${PATH}" capture "${TREE}/Scripts/check_node_pin.sh"
}

new_tree equal $'26\n'
run_gate v26.11.1
want_green "1. running major equals the pin" "OK: node v26.11.1 is the pinned major (26)"

new_tree other $'26\n'
run_gate v25.2.0
want_red "2. a different major: names the running version" "node is v25.2.0, but .nvmrc pins Node 26"
want_said "2. a different major: names the fix" "brew install node@26"
want_said "2. a different major: names the upgrade" "brew upgrade node"

new_tree missing $'26\n'
PATH="${NONODE}:/usr/bin:/bin" capture "${TREE}/Scripts/check_node_pin.sh"
want_red "3. no node on PATH" "node is not on PATH, and .nvmrc pins Node 26"
want_said "3. no node on PATH: names the fix" "brew install node@26"

new_tree badpin $'lts/*\n'
run_gate v26.11.1
want_red "4. a bad pin file" "the Node pin could not be read"

new_tree garbage $'26\n'
run_gate "not a version"
want_red "5. a node that prints garbage" "could not read a Node major"

# --- mutation proof: no comparison -> the other major passes ---------------
NO_COMPARE="s/if \\[ \"\\\$major\" != \"\\\$pin\" \\]; then/if false; then/"
MUTANT="${TMP}/mutant_gate.sh"
if selftest_mutant "${REAL_ROOT}/Scripts/check_node_pin.sh" "$MUTANT" "$NO_COMPARE"; then
  new_tree mutated $'26\n' "$MUTANT"
  run_gate v25.2.0
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: without the comparison a different major passes, so case 2 is red because of it"
  else
    fail "mutation proof: the comparison-less gate still failed v25.2.0 (exit ${RC}). Output: ${OUT}"
  fi
fi

selftest_end "the node pin gate does not hold" \
  "node pin gate: the pinned major is green; another major, no node, a bad pin and garbage are red with the fix; mutation proven"
