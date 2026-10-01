#!/usr/bin/env bash
# npm_audit_check.sh — npm-audit gate with one-shot self-heal.
#
# Contract (pinned by test_npm_audit_check.sh):
# Ported from MenoPower Scripts/admin/ — unit 393.
#
#   exit 0 — audit clean, possibly after ONE `npm audit fix` (re-verified);
#            a heal reports the package-lock.json change, which rides into
#            the commit (sqlc-generate precedent). CI stays the strict
#            gatekeeper: quality.yml runs plain `npm audit` with no heal.
#   exit 1 — vulnerabilities remain after the heal; prints the full audit
#            report plus a final parseable `npm-audit:` summary line for
#            the caller's error sink.
#   exit 2 — tooling failure (npm missing); never a silent pass.
set -euo pipefail

# Unit 409 step 3: defaults to the repo root, so the order file can name a
# bare script path. Callers may still override; the fixture does.
pkgdir="${1:-.}"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm-audit: npm not found on PATH (tooling)" >&2
  exit 2
fi

cd "$pkgdir"

run_audit() {
  npm audit --audit-level=high 2>&1
}

if first="$(run_audit)"; then
  printf '%s\n' "$first"
  exit 0
fi

echo "npm-audit: high-severity advisory found — attempting npm audit fix"
npm audit fix >/dev/null 2>&1 || true

if second="$(run_audit)"; then
  echo "npm-audit: healed via npm audit fix — package-lock.json updated (change rides into this commit)"
  exit 0
fi

printf '%s\n' "$second"
echo "npm-audit: vulnerabilities remain after npm audit fix — see report above"
exit 1
