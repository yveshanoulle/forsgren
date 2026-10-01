#!/usr/bin/env bash
# test_npm_audit_check.sh — fixture test for npm_audit_check.sh.
#
# Ported from MenoPower's admin gate — unit 393. This repo ships htmlhint and
# stylelint as devDependencies and audited them NOWHERE: not in sfl, not in
# CI. A linter's own dependency tree is still a dependency tree.
#
# Why the original exists: on 2026-07-21 a fresh upstream advisory turned the
# npm-audit gate red, and the step hard-exited without recording an error — the summary
# said "Errors: none" while the actual report lived only in the terminal
# scroll-back. The gate's contract is now: self-heal fixable advisories with
# ONE `npm audit fix` (sqlc-generate precedent — the lockfile change rides into
# the commit), re-verify, and on a heal that doesn't stick fail with the full
# report PLUS a parseable `npm-audit:` summary line for the error sink. A fake
# `npm` drives every mode — an unexercised script mode is broken until a
# fixture drives it.
set -euo pipefail

# Repo root without counting levels — rule C.
cd "$(cd "$(dirname "$0")" && git rev-parse --show-toplevel)"
CHECK="Scripts/npm_audit_check.sh"

tmproot="$(mktemp -d)"
trap 'rm -rf "$tmproot"' EXIT

pkgdir="$tmproot/pkg"
mkdir -p "$pkgdir"
echo '{}' > "$pkgdir/package.json"

# Fake npm: the state file decides the audit verdict; `audit fix` heals only
# when NPM_FAKE_HEAL=yes. Every invocation lands in the calls log.
fakebin="$tmproot/bin"
mkdir -p "$fakebin"
cat > "$fakebin/npm" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$NPM_FAKE_CALLS"
if [ "${1:-}" = "audit" ] && [ "${2:-}" = "fix" ]; then
  if [ "$NPM_FAKE_HEAL" = "yes" ]; then echo clean > "$NPM_FAKE_STATE"; fi
  exit 0
fi
if [ "${1:-}" = "audit" ]; then
  if [ "$(cat "$NPM_FAKE_STATE")" = "vulnerable" ]; then
    echo "# npm audit report"
    echo "brace-expansion  3.0.0 - 5.0.6"
    echo "Severity: high"
    echo "1 high severity vulnerability"
    exit 1
  fi
  echo "found 0 vulnerabilities"
  exit 0
fi
exit 0
FAKE
chmod +x "$fakebin/npm"

export NPM_FAKE_STATE="$tmproot/state"
export NPM_FAKE_CALLS="$tmproot/calls.log"

run_check() {
  PATH="$fakebin:$PATH" bash "$CHECK" "$pkgdir"
}

# --- Case 1: clean audit → exit 0 and `npm audit fix` is never invoked ---
echo clean > "$NPM_FAKE_STATE"
: > "$NPM_FAKE_CALLS"
export NPM_FAKE_HEAL=no
if ! out="$(run_check 2>&1)"; then
  echo "FAIL: clean audit was rejected" >&2
  exit 1
fi
if grep -q "audit fix" "$NPM_FAKE_CALLS"; then
  echo "FAIL: audit fix ran on a clean audit" >&2
  exit 1
fi

# --- Case 2: vulnerable + fix heals → exit 0, re-verified, lockfile reported ---
echo vulnerable > "$NPM_FAKE_STATE"
: > "$NPM_FAKE_CALLS"
export NPM_FAKE_HEAL=yes
if ! out="$(run_check 2>&1)"; then
  echo "FAIL: healable audit did not end green" >&2
  exit 1
fi
if ! grep -q "audit fix" "$NPM_FAKE_CALLS"; then
  echo "FAIL: heal path never ran npm audit fix" >&2
  exit 1
fi
audits="$(grep -c "audit --audit-level" "$NPM_FAKE_CALLS" || true)"
if [ "${audits}" -lt 2 ]; then
  echo "FAIL: heal was not re-verified with a second audit (saw ${audits})" >&2
  exit 1
fi
case "$out" in
  *"npm audit fix"*"package-lock.json"*) : ;;
  *)
    echo "FAIL: heal output does not report the package-lock.json change" >&2
    exit 1
    ;;
esac

# --- Case 3: vulnerable + fix does NOT stick → exit 1, report + summary line ---
echo vulnerable > "$NPM_FAKE_STATE"
: > "$NPM_FAKE_CALLS"
export NPM_FAKE_HEAL=no
set +e
out="$(run_check 2>&1)"
status=$?
set -e
if [ "$status" -ne 1 ]; then
  echo "FAIL: unfixable vulnerability exited ${status} (want 1)" >&2
  exit 1
fi
case "$out" in
  *"npm audit report"*) : ;;
  *)
    echo "FAIL: failure output lost the audit report details" >&2
    exit 1
    ;;
esac
case "$out" in
  *"npm-audit:"*"after npm audit fix"*) : ;;
  *)
    echo "FAIL: no parseable npm-audit: summary line for the error sink" >&2
    exit 1
    ;;
esac

# --- Case 4: npm missing from PATH → exit 2 (tooling, never a silent pass) ---
set +e
out="$(PATH="/usr/bin:/bin" bash "$CHECK" "$pkgdir" 2>&1)"
status=$?
set -e
if [ "$status" -ne 2 ]; then
  echo "FAIL: missing npm exited ${status} (want 2)" >&2
  exit 1
fi

echo "PASS"
