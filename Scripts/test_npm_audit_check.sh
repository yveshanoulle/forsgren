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
#
# forsgren#13 (Yves's ruling, 2026-10-03: option 1, then weekly): the gate
# reads `npm audit --json` and honours a RULED EXCEPTION from
# Scripts/npm_audit_exceptions.txt, narrow and expiring by itself. This
# self-test therefore left the estate harness for forsgren's own
# (Scripts/lib_selftest.sh): it needs its mutation proofs. Its cases:
#
#   1. a clean audit                           -> green, no `npm audit fix`
#   2. an advisory one `npm audit fix` heals   -> green, re-verified, the
#                                                 lockfile change reported
#   3. an advisory the heal leaves             -> red, the report and the
#                                                 `npm-audit:` summary line
#   4. npm missing                             -> exit 2, never a silent pass
#  4b. npm gives no audit report (offline)     -> exit 2, never clean
#   5. excepted, in date, exactly 7 days ahead -> green, the `excepted:`
#                                                 notice printed once, no heal;
#                                                 a dependent's own
#                                                 fixAvailable (npm's globby
#                                                 case) does not count
#   6. on the re-check date itself             -> green
#   7. the re-check date passed                -> red: re-check the issue
#   8. another advisory on the same package    -> red: not excepted
#   9. another package's advisory              -> red: not excepted
#  10. the listed advisory on another package  -> red: not excepted
#  11. the advisory on a production path       -> red: dev dependencies only
#  12. a non-forced fix: fixAvailable true     -> red: a fix exists
#  13. a non-forced fix: not SemVer-major      -> red: a fix exists
#  14. a moderate advisory, not listed         -> green (audit level high)
#  15. a stale exception                       -> green with a warning
#  16. a re-check date 8 days ahead            -> red: re-check weekly
#  17. a malformed exception file (4 fields, an impossible date, a
#      duplicate)                              -> red, no audit run
#  18. MUTATION PROOFS, one per rule: the gate with that rule taken out is
#      green on the case that rule refuses, saying `excepted:`.
#
# OFFLINE: the fake npm on PATH serves canned `npm audit --json` reports from
# Scripts/testdata/npm_audit/ (made-up packages and advisory IDs, in npm 11's
# auditReportVersion 2 shape), and NPM_AUDIT_TODAY pins today.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

CHECK="Scripts/npm_audit_check.sh"
FIXTURES="$(pwd)/Scripts/testdata/npm_audit"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "npm-audit self-test"

[[ -f "$CHECK" ]] || selftest_abort "the npm audit gate ${CHECK} is missing: nothing audits the npm tooling"

pkgdir="${TMP}/pkg"
mkdir -p "$pkgdir"
echo '{}' > "${pkgdir}/package.json"

# Fake npm. The files `full` and `prod` in the state directory name the
# report `npm audit --json` and `npm audit --omit=dev --json` serve; any
# other `npm audit` prints a text report. `npm audit fix` heals (both
# reports become clean) only when NPM_FAKE_HEAL=yes. Like npm, an audit with
# a finding exits 1. Every invocation lands in the calls log.
fakebin="${TMP}/bin"
mkdir -p "$fakebin"
cat > "${fakebin}/npm" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$NPM_FAKE_CALLS"
[ "${1:-}" = "audit" ] || exit 0
if [ "${2:-}" = "fix" ]; then
  if [ "$NPM_FAKE_HEAL" = "yes" ]; then
    echo "$NPM_FAKE_CLEAN" > "$NPM_FAKE_STATE/full"
    echo "$NPM_FAKE_CLEAN" > "$NPM_FAKE_STATE/prod"
  fi
  exit 0
fi
report="$(cat "$NPM_FAKE_STATE/full")"
case " $* " in
  *" --omit=dev "*) report="$(cat "$NPM_FAKE_STATE/prod")" ;;
esac
found=0
grep -q '"via"' "$report" && found=1
case " $* " in
  *" --json "*) cat "$report" ;;
  *)
    echo "# npm audit report (fake)"
    [ "$found" -eq 1 ] && echo "1 or more high severity vulnerabilities"
    ;;
esac
exit "$found"
FAKE
chmod +x "${fakebin}/npm"

export NPM_FAKE_STATE="${TMP}/state"
export NPM_FAKE_CALLS="${TMP}/calls.log"
export NPM_FAKE_CLEAN="${FIXTURES}/clean.json"
export NPM_FAKE_HEAL=no
export NPM_AUDIT_EXCEPTIONS="${TMP}/exceptions.txt"
export NPM_AUDIT_TODAY="2026-10-03"
mkdir -p "$NPM_FAKE_STATE"

ADV="GHSA-h2h2-j3j3-q4q4"
NOTICE="excepted: ${ADV} (acme-braces) until 2026-10-10, forsgren#13"

# serve <full report> [prod report]: what the fake npm answers; the prod
# report defaults to clean (every path a dev path).
serve() {
  echo "$1" > "${NPM_FAKE_STATE}/full"
  echo "${2:-$NPM_FAKE_CLEAN}" > "${NPM_FAKE_STATE}/prod"
  : > "$NPM_FAKE_CALLS"
}

# except <line>...: the exception file, a comment line first.
except() {
  {
    echo "# advisory|package|re-check date|issue|reason"
    printf '%s\n' "$@"
  } > "$NPM_AUDIT_EXCEPTIONS"
}

# the ruled entry, re-checked on 2026-10-10.
except_ruled() {
  except "${ADV}|acme-braces|${1:-2026-10-10}|forsgren#13|dev tooling only; no patched acme-braces"
}

# variant <name> <jq filter>: a fixture derived from excepted.json.
variant() {
  jq "$2" "${FIXTURES}/excepted.json" > "${TMP}/$1.json"
  echo "${TMP}/$1.json"
}

run_check() {
  capture env PATH="${fakebin}:${PATH}" bash "${1:-$CHECK}" "$pkgdir"
}

# no_heal <case>: the gate never ran `npm audit fix`.
no_heal() {
  if grep -q "audit fix" "$NPM_FAKE_CALLS"; then
    fail "$1: npm audit fix ran"
  else
    echo "  ok: $1"
  fi
}

# --- Case 1: clean audit -> green, `npm audit fix` never invoked.
except_ruled
serve "${FIXTURES}/clean.json"
run_check
want_green_ok "a clean audit is green"
no_heal "  ... without npm audit fix"

# --- Case 2: an advisory the heal fixes -> green, re-verified, lockfile named.
except
serve "${FIXTURES}/other.json"
export NPM_FAKE_HEAL=yes
run_check
export NPM_FAKE_HEAL=no
want_green "an advisory npm audit fix heals is green" "package-lock.json"
if grep -q "audit fix" "$NPM_FAKE_CALLS"; then
  echo "  ok:   ... it ran npm audit fix"
else
  fail "the heal path never ran npm audit fix"
fi
audits="$(grep -c -- "--json" "$NPM_FAKE_CALLS" || true)"
if [[ "$audits" -ge 4 ]]; then
  echo "  ok:   ... and audited again after it"
else
  fail "the heal was not re-verified (saw ${audits} JSON audits, want 4: full and prod, twice)"
fi

# --- Case 3: an advisory the heal leaves -> exit 1, report + summary line.
except
serve "${FIXTURES}/other.json"
run_check
want_exit "an advisory the heal leaves is red" 1 "❌ npm-audit:"
want_said "  ... with the audit report" "npm audit report"
want_said "  ... and the parseable summary line" "after npm audit fix"

# --- Case 4: npm missing -> exit 2.
capture env PATH="/usr/bin:/bin" bash "$CHECK" "$pkgdir"
want_rc "a missing npm is a tool error (exit 2)" 2

# --- Case 4b: npm gives no audit report (offline) -> exit 2, never clean.
printf '%s\n' '{"error": {"code": "ENOTFOUND", "summary": "request to the registry failed"}}' > "${TMP}/offline.json"
serve "${TMP}/offline.json"
run_check
want_exit "no audit report is a tool error (exit 2)" 2 "gave no audit report"

# --- Case 5: excepted, in date, exactly 7 days ahead -> green with notice.
except_ruled
serve "${FIXTURES}/excepted.json"
run_check
want_green_ok "an excepted advisory, in date, is green"
want_said "  ... and printed as excepted" "$NOTICE"
if [[ "$(grep -cF -- "$NOTICE" <<< "$OUT")" -eq 1 ]]; then
  echo "  ok:   ... once"
else
  fail "the excepted notice is not printed exactly once. Output: ${OUT}"
fi
no_heal "  ... without npm audit fix"

# --- Case 6: today is the re-check date -> still green.
export NPM_AUDIT_TODAY="2026-10-10"
run_check
want_green "on the re-check date itself it is green" "$NOTICE"

# --- Case 7: the re-check date passed -> red.
export NPM_AUDIT_TODAY="2026-10-11"
run_check
export NPM_AUDIT_TODAY="2026-10-03"
want_red "past the re-check date it is red" "re-check forsgren#13: is a fix out?"

# --- Case 8: a second advisory on the excepted package -> red.
SECOND="$(variant second '.vulnerabilities["acme-braces"].via += [{source: 1000003, name: "acme-braces", dependency: "acme-braces", title: "acme-braces leaks memory", url: "https://github.com/advisories/GHSA-w9w9-x8x8-v7v7", severity: "high", cwe: [], cvss: {score: 7.5, vectorString: null}, range: "<=3.0.3"}]')"
serve "$SECOND"
run_check
want_red "a second advisory on the excepted package is red" "GHSA-w9w9-x8x8-v7v7 (acme-braces <=3.0.3, high) is not excepted"

# --- Case 9: another package's advisory -> red.
serve "${FIXTURES}/other.json"
run_check
want_red "another package's advisory is red" "GHSA-m5m5-p6p6-r7r7 (acme-yaml <2.4.0, high) is not excepted"

# --- Case 10: the listed advisory, but the entry names another package.
except "${ADV}|acme-other|2026-10-10|forsgren#13|dev tooling only"
serve "${FIXTURES}/excepted.json"
run_check
want_red "the listed advisory on an unlisted package is red" "${ADV} (acme-braces <=3.0.3, high) is not excepted"

# --- Case 11: the advisory reaches a production path -> red.
except_ruled
serve "${FIXTURES}/excepted.json" "${FIXTURES}/excepted.json"
run_check
want_red "the advisory on a production path is red" "reaches a production dependency"
if grep -q -- "--omit=dev" "$NPM_FAKE_CALLS"; then
  echo "  ok:   ... found with npm audit --omit=dev"
else
  fail "the production path was not checked with npm audit --omit=dev"
fi

# --- Case 12: a non-forced fix: fixAvailable true on the package itself.
serve "$(variant fixtrue '.vulnerabilities["acme-braces"].fixAvailable = true')"
run_check
want_red "a fix (fixAvailable true) is red" "a fix exists for ${ADV} (acme-braces): remove the exception and update"

# --- Case 13: a non-forced fix: not SemVer-major.
serve "$(variant fixminor '.vulnerabilities["acme-braces"].fixAvailable = {name: "acme-lint", version: "1.4.0", isSemVerMajor: false}')"
run_check
want_red "a fix (not SemVer-major) is red" "a fix exists for ${ADV} (acme-braces): remove the exception and update"

# --- Case 14: an unlisted moderate advisory -> green (audit level high).
serve "$(variant moderate '.vulnerabilities["acme-yaml"] = {name: "acme-yaml", severity: "moderate", isDirect: true, via: [{source: 1000004, name: "acme-yaml", dependency: "acme-yaml", title: "acme-yaml is slow", url: "https://github.com/advisories/GHSA-p3p3-q4q4-r5r5", severity: "moderate", range: "<2.4.0"}], effects: [], range: "<2.4.0", nodes: ["node_modules/acme-yaml"], fixAvailable: false}')"
run_check
want_green "an unlisted moderate advisory is green, as below the audit level" "$NOTICE"

# --- Case 15: a stale exception -> green with a warning.
serve "${FIXTURES}/clean.json"
run_check
want_green_ok "a stale exception is green"
want_said "  ... with a warning" "remove the stale exception ${ADV} (acme-braces)"
if grep -q "❌" <<< "$OUT"; then
  fail "the stale warning carries a red cross. Output: ${OUT}"
fi

# --- Case 16: a re-check date 8 days ahead -> red.
except_ruled "2026-10-11"
serve "${FIXTURES}/excepted.json"
run_check
want_red "a re-check date 8 days ahead is red" "an exception may run at most 7 days ahead: re-check weekly"

# --- Case 17: a malformed exception file -> red, no audit.
except "${ADV}|acme-braces|2026-10-10|forsgren#13"
: > "$NPM_FAKE_CALLS"
run_check
want_red "an entry without its reason is red" "malformed exception file"
if grep -q "audit" "$NPM_FAKE_CALLS"; then
  fail "the gate audited with a malformed exception file"
else
  echo "  ok:   ... before any audit"
fi
except "${ADV}|acme-braces|2026-02-30|forsgren#13|dev tooling only"
run_check
want_red "an impossible re-check date is red" "malformed exception file"
except_ruled
printf '%s\n' "${ADV}|acme-braces|2026-10-09|forsgren#13|again" >> "$NPM_AUDIT_EXCEPTIONS"
run_check
want_red "a duplicate entry is red" "malformed exception file"

# --- Case 18: MUTATION PROOFS. Each rule, taken out of the gate, lets the
# case it refuses through as excepted. A mutant that is still red, or green
# for another reason, proves nothing.
# prove <rule> <sed-expression> <setup>: <setup> prepares the case.
prove() {
  local mutant="${TMP}/mutant-$1/npm_audit_check.sh"
  "$3"
  run_check
  if [[ "$RC" -eq 0 ]]; then
    fail "mutation $1: the case is green on the real gate, so the proof shows nothing"
    return 0
  fi
  selftest_mutant "$CHECK" "$mutant" "$2" || return 0
  "$3"
  run_check "$mutant"
  want_green "mutation $1: without it, the case it refuses is excepted" "excepted: "
}
# Each setup pins today, so no case leaks its date into the next.
setup_expired() { export NPM_AUDIT_TODAY="2026-10-11"; except_ruled; serve "${FIXTURES}/excepted.json"; }
setup_second() { export NPM_AUDIT_TODAY="2026-10-03"; except_ruled; serve "$SECOND"; }
setup_package() { export NPM_AUDIT_TODAY="2026-10-03"; except "${ADV}|acme-other|2026-10-10|forsgren#13|dev tooling only"; serve "${FIXTURES}/excepted.json"; }
setup_prod() { export NPM_AUDIT_TODAY="2026-10-03"; except_ruled; serve "${FIXTURES}/excepted.json" "${FIXTURES}/excepted.json"; }
setup_fix() { export NPM_AUDIT_TODAY="2026-10-03"; except_ruled; serve "${TMP}/fixtrue.json"; }
setup_weekly() { export NPM_AUDIT_TODAY="2026-10-03"; except_ruled "2026-10-11"; serve "${FIXTURES}/excepted.json"; }
setup_malformed() { export NPM_AUDIT_TODAY="2026-10-03"; except "${ADV}|acme-braces|2026-10-10|forsgren#13"; serve "${FIXTURES}/excepted.json"; }

prove "re-check date" 's/^def expired(/def expired(e): false; def unused_expired(/' setup_expired
prove "listed advisory" '/# rule: listed advisory/d' setup_second
prove "listed package" '/# rule: listed package/d' setup_package
prove "dev paths only" 's/^def on_prod_path(/def on_prod_path(a): false; def unused_on_prod_path(/' setup_prod
prove "no fix exists" 's/^def fix_exists(/def fix_exists(e): false; def unused_fix_exists(/' setup_fix
prove "weekly re-check" 's/^def too_far_ahead(/def too_far_ahead(e): false; def unused_too_far_ahead(/' setup_weekly
prove "well-formed file" 's/^def problems:/def problems: empty; def unused_problems:/' setup_malformed

# The stale rule warns instead of refusing: without it, no warning.
if selftest_mutant "$CHECK" "${TMP}/mutant-stale/npm_audit_check.sh" 's/^def stale(/def stale(e): false; def unused_stale(/'; then
  export NPM_AUDIT_TODAY="2026-10-03"
  except_ruled
  serve "${FIXTURES}/clean.json"
  run_check "${TMP}/mutant-stale/npm_audit_check.sh"
  if [[ "$RC" -eq 0 ]] && ! grep -q "stale" <<< "$OUT"; then
    echo "  ok: mutation stale: without it, a stale exception goes unmentioned"
  else
    fail "mutation stale: the mutant still warned, or went red. Output: ${OUT}"
  fi
fi

selftest_end "the npm audit gate does not hold its contract" \
  "the npm audit gate heals, reports, and honours only a narrow, weekly, dev-only exception"
