#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Fixture for check_secrets.sh — unit 399.
#
# The case that matters is a PLANTED SECRET being caught. A secret scanner
# that has never been seen catching anything is a scanner nobody has tested,
# and this one carries the heaviest consequence in the repo: its failure
# blocks the commit.
#
# It also pins the ALLOWLIST, in both directions. `${{ secrets.NAME }}` in a
# workflow is a reference, not a value, and every workflow here is full of
# them — an allowlist that failed to cover those would red every run and get
# removed within a day. But an allowlist wide enough to swallow a real key
# beside one is worse than none, so that is asserted too.

CHECK="./Scripts/check_secrets.sh"
TMP="$(mktemp -d)"

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: secret-scan fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap 'rm -rf "$TMP"; finish' EXIT

failures=0
check() { # <name> <expected-rc> <actual-rc>
  if [[ "$2" == "$3" ]]; then echo "  ✅ $1"; else echo "  ❌ $1 — expected exit $2, got $3"; failures=$((failures+1)); fi
}
run() { set +e; "$CHECK" "$1" >/dev/null 2>&1; RC=$?; set -e; }

echo "test_check_secrets"

# --- Case 1: this repo, as it stands.
run "."
check "the working tree is clean" 0 "$RC"

# --- Case 2: a planted private key must be caught, and with exit 2.
#     Assembled at runtime so this fixture does not itself contain a string
#     that trips the scanner it is testing.
leak="$TMP/leak"; mkdir -p "$leak"
{
  printf -- '-----BEGIN %s PRIVATE KEY-----\n' "OPENSSH"
  printf 'b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gt\n'
  printf 'ZWQyNTUxOQAAACDb9uZ0hLDhVvVvxSKrHqbHIkYqcxjyfHVvVGVzdEtleU5vdFJlYWw\n'
  printf -- '-----END %s PRIVATE KEY-----\n' "OPENSSH"
} > "$leak/id_ed25519"
run "$leak"
check "a planted private key is caught, exit 2 (secret-class, not an ordinary red)" 2 "$RC"

# --- Case 3: a workflow secret REFERENCE is not a secret.
ref="$TMP/ref"; mkdir -p "$ref"
# A QUOTED heredoc rather than printf with a single-quoted string: the text is a
# literal GitHub Actions expression and must not expand, and `<<'YAML'` says so
# in a way the linter reads correctly. In single quotes it looks like an
# expansion somebody forgot to make work.
cat > "$ref/wf.yml" <<'YAML'
env:
  KEY: ${{ secrets.HETZNER_SSH_KEY }}
YAML
run "$ref"
check "a \${{ secrets.NAME }} reference is allowlisted, not flagged" 0 "$RC"

# --- Case 4: the allowlist must not swallow a real key sitting beside one.
both="$TMP/both"; mkdir -p "$both"
{
  cat <<'YAML'
env:
  KEY: ${{ secrets.HETZNER_SSH_KEY }}
YAML
  printf -- '-----BEGIN %s PRIVATE KEY-----\n' "OPENSSH"
  printf 'b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gt\n'
  printf -- '-----END %s PRIVATE KEY-----\n' "OPENSSH"
} > "$both/wf.yml"
run "$both"
check "a real key BESIDE an allowlisted reference is still caught" 2 "$RC"

COMPLETED=1

if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_secrets contract"
  exit 1
fi
echo ""
echo "✅ test_check_secrets"
