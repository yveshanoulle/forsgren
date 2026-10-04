#!/usr/bin/env bash
# npm_audit_check.sh — npm-audit gate with one-shot self-heal and ruled,
# weekly exceptions.
#
# Contract (pinned by test_npm_audit_check.sh):
# Ported from another estate repository Scripts/admin/ — unit 393.
#
#   exit 0 — no high or critical advisory outside a ruled exception, possibly
#            after ONE `npm audit fix` (re-verified); a heal reports the
#            package-lock.json change, which rides into the commit
#            (sqlc-generate precedent). CI stays the strict gatekeeper:
#            Scripts/run_ci_phase.sh turns a heal (a changed tree) red.
#   exit 1 — an advisory remains after the heal, or the exception file is
#            wrong; prints the audit report, a `❌ npm-audit:` line per
#            reason, and a final parseable `npm-audit:` summary line for
#            the caller's error sink.
#   exit 2 — tooling failure (npm or jq missing, no audit report); never a
#            silent pass.
#
# RULED EXCEPTIONS (forsgren#13, Yves's ruling 2026-10-03: option 1, then a
# weekly re-check). Scripts/npm_audit_exceptions.txt lists them, one per
# line: advisory|package|re-check date|issue|reason. A finding is ignored
# only while ALL of these hold:
#   - its advisory ID (GHSA) AND its package are listed;
#   - today is on or before the re-check date;
#   - `npm audit --omit=dev` does not report it: every path to it runs
#     through devDependencies;
#   - npm offers no fix without --force for the advisory's own package:
#     its `fixAvailable` is false or a SemVer-major (forced) fix. (A
#     dependent's own fixAvailable does not count: npm marks globby
#     fixable while the braces under it stays vulnerable.) A patched
#     version, once published, makes that fixAvailable true.
# Every ignored finding prints `excepted: <GHSA> (<package>) until <date>,
# <issue>` once, so it is never silent. The file itself is red when a line
# is malformed, an advisory is listed twice, or a re-check date is more than
# 7 days after today: an exception is re-checked WEEKLY, and nobody can set
# it a month out. An entry whose advisory npm no longer reports is a warning
# (remove the stale exception), not a red. An exception needs Yves's
# explicit yes recorded on a GitHub issue, like every suppression (README,
# Quality gates).
#
# jq is not in Scripts/required_tools.txt: it ships with macOS (/usr/bin/jq
# since macOS 15) and on GitHub's macOS images, like awk. A missing jq is a
# tool error, named.
#
# NPM_AUDIT_TODAY (YYYY-MM-DD, default `date -u +%F`) and
# NPM_AUDIT_EXCEPTIONS (default: npm_audit_exceptions.txt next to this
# script) exist for the self-test only.
set -euo pipefail

# Unit 409 step 3: defaults to the repo root, so the order file can name a
# bare script path. Callers may still override; the fixture does.
pkgdir="${1:-.}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
exceptions="${NPM_AUDIT_EXCEPTIONS:-${script_dir}/npm_audit_exceptions.txt}"
today="${NPM_AUDIT_TODAY:-$(date -u +%F)}"

for tool in npm jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "❌ npm-audit: ${tool} not found on PATH (tooling)" >&2
    exit 2
  fi
done
case "$today" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
  *)
    echo "❌ npm-audit: today (${today}) is not a YYYY-MM-DD date (tooling)" >&2
    exit 2
    ;;
esac

# The exception file, parsed: {errors: [...], entries: [...]}. A missing
# file is no exception at all: the gate is then as strict as before.
parse_program() {
  cat <<'JQ'
def day: strptime("%Y-%m-%d") | mktime;
def real_date: test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") and ((try (day | strftime("%Y-%m-%d")) catch "") == .);
def too_far_ahead($e): (($e.date | day) - ($today | day)) > 7 * 86400;
def problems:
  if (.f | length) != 5 then "want 5 fields (advisory|package|re-check date|issue|reason), got \(.f | length)"
  else
    (if .f[0] | test("^GHSA(-[a-z0-9]{4}){3}$") then empty else "the advisory \(.f[0]) is not a GHSA ID" end),
    (if .f[1] | test("^(@[a-z0-9._-]+/)?[a-z0-9._-]+$") then empty else "the package \(.f[1]) is not an npm package name" end),
    (if .f[2] | real_date then empty else "the re-check date \(.f[2]) is not a real YYYY-MM-DD date" end),
    (if .f[3] | test("^[A-Za-z0-9._-]+#[0-9]+$") then empty else "the issue \(.f[3]) is not repository#number" end),
    (if .f[4] != "" then empty else "the reason is empty" end)
  end;
[ $text | split("\n") | to_entries[]
  | {line: (.key + 1), text: .value}
  | select(.text | test("^[[:space:]]*(#|$)") | not)
  | . + {f: (.text | split("|") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")))} ] as $rows
| [ $rows[] | select([problems] | length == 0)
    | {id: .f[0], package: .f[1], date: .f[2], issue: .f[3], reason: .f[4]} ] as $entries
| { entries: $entries,
    errors: (
      [ $rows[] | . as $r | problems
        | "❌ npm-audit: malformed exception file \($path), line \($r.line): \(.)" ]
      + [ $entries | group_by(.id)[] | select(length > 1)
        | "❌ npm-audit: malformed exception file \($path): \(.[0].id) is listed \(length) times" ]
      + [ $entries[] | select(too_far_ahead(.))
        | "❌ npm-audit: the exception for \(.id) (\(.package)) runs to \(.date), more than 7 days after \($today): an exception may run at most 7 days ahead: re-check weekly (\(.issue))" ]
    ) }
JQ
}

# The verdict on one audit: a line per finding, `❌ ` first when it is red.
# Its input is two reports: all dependencies, then production only.
verdict_program() {
  cat <<'JQ'
input as $full | input as $prod |
def advisory_id: ([(.url // "") | capture("(?<g>GHSA(-[a-z0-9]{4}){3})") | .g] | .[0]) // "npm advisory \(.source)";
def advisories: [.vulnerabilities[] | .via[] | objects
  | {id: advisory_id, name, title, severity, range}] | unique_by([.id, .name]);
def high: .severity == "high" or .severity == "critical";
def entry_of($a): [ $entries[]
  | select(.id == $a.id)          # rule: listed advisory
  | select(.package == $a.name)   # rule: listed package
  ] | .[0];
def expired($e): $today > $e.date;
def on_prod_path($a): any($prod | advisories[]; .id == $a.id);
def fix_exists($e): ($full.vulnerabilities[$e.package].fixAvailable // false) as $f | $f == true or (($f | type) == "object" and $f.isSemVerMajor == false);
def stale($e): any($full | advisories[]; .id == $e.id and .name == $e.package) | not;
def verdict($a; $e):
  if $e == null then "❌ npm-audit: \($a.id) (\($a.name) \($a.range), \($a.severity)) is not excepted: \($a.title)"
  else
    [ (if expired($e) then "❌ npm-audit: the exception for \($a.id) (\($a.name)) passed its re-check date \($e.date): re-check \($e.issue): is a fix out?" else empty end),
      (if on_prod_path($a) then "❌ npm-audit: \($a.id) (\($a.name)) reaches a production dependency (npm audit --omit=dev reports it): the exception covers dev dependencies only, \($e.issue)" else empty end),
      (if fix_exists($e) then "❌ npm-audit: a fix exists for \($a.id) (\($a.name)): remove the exception and update, \($e.issue)" else empty end)
    ] as $reds
    | if ($reds | length) > 0 then $reds[] else "excepted: \($a.id) (\($a.name)) until \($e.date), \($e.issue)" end
  end;
($full | advisories[] | select(high) | verdict(.; entry_of(.))),
($entries[] | select(stale(.)) | "warning: npm-audit: remove the stale exception \(.id) (\(.package)), \(.issue): npm audit no longer reports it")
JQ
}

text=""
if [[ -f "$exceptions" ]]; then
  text="$(cat "$exceptions")"
fi
if ! parsed="$(jq -n -c --arg text "$text" --arg path "$exceptions" --arg today "$today" "$(parse_program)")"; then
  echo "❌ npm-audit: jq could not read the exception file ${exceptions} (tooling)" >&2
  exit 2
fi
errors="$(jq -r '.errors[]' <<< "$parsed")"
if [[ -n "$errors" ]]; then
  printf '%s\n' "$errors"
  echo "❌ npm-audit: the exception file ${exceptions} is wrong: nothing was audited"
  exit 1
fi
entries="$(jq -c '.entries' <<< "$parsed")"

cd "$pkgdir"

# audit_json [npm audit flags]: prints the report, or exits 2 when npm gave
# none (no network, a broken lockfile): a missing report is never clean.
audit_json() {
  local report
  report="$(npm audit --json "$@" 2>/dev/null)" || true
  if ! jq -e '.auditReportVersion == 2 and (.vulnerabilities | type) == "object"' <<< "$report" >/dev/null 2>&1; then
    echo "❌ npm-audit: npm audit --json $* gave no audit report (tooling):" >&2
    printf '%s\n' "$report" >&2
    exit 2
  fi
  printf '%s\n' "$report"
}

# evaluate: audits (all dependencies, then production only) and prints the
# verdict lines; exits 1 when one is red. It runs as `x="$(evaluate)" ||`,
# where set -e is off, so every failure here is checked by hand: a verdict
# jq could not compute is a tool error, never an empty, green one.
evaluate() {
  local full prod lines
  full="$(audit_json)" || exit 2
  prod="$(audit_json --omit=dev)" || exit 2
  if ! lines="$(printf '%s\n%s\n' "$full" "$prod" | jq -n -r \
    --argjson entries "$entries" --arg today "$today" "$(verdict_program)")"; then
    echo "❌ npm-audit: jq could not judge the audit report (tooling)"
    exit 2
  fi
  if [[ -n "$lines" ]]; then
    printf '%s\n' "$lines"
  fi
  if grep -q '^❌' <<< "$lines"; then
    return 1
  fi
  echo "npm-audit: OK: no high-severity advisory outside a ruled exception"
}

first="$(evaluate)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  printf '%s\n' "$first"
  exit 0
fi
if [[ "$rc" -ne 1 ]]; then
  printf '%s\n' "$first"
  exit "$rc"
fi

echo "npm-audit: high-severity advisory found — attempting npm audit fix"
npm audit fix >/dev/null 2>&1 || true

second="$(evaluate)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  printf '%s\n' "$second"
  echo "npm-audit: healed via npm audit fix — package-lock.json updated (change rides into this commit)"
  exit 0
fi
if [[ "$rc" -ne 1 ]]; then
  printf '%s\n' "$second"
  exit "$rc"
fi

npm audit --audit-level=high 2>&1 || true
printf '%s\n' "$second"
echo "❌ npm-audit: vulnerabilities remain after npm audit fix — see report above"
exit 1
