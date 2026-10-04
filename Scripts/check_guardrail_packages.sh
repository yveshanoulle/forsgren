#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

# Guardrail: the npm manifest policy this estate settled on — unit 418.
#
# PORTED FROM agilelean 2026-09-02, where it existed as the opposite rule — it
# asserted that package.json must NOT exist, because that repo pinned its
# linters inside the npx invocation. The estate standardised the other way on a
# reviewer's ruling recorded in
# web-infra/documentation/decision-linter-pinning.md, and this repo, which had
# the manifest all along, had nothing enforcing any of it:
#
#   Repository-executed npm tooling is declared as exact-version
#   devDependencies, with a committed lockfile, installed using `npm ci`.
#   node_modules is never tracked.
#
# WHY, in one line: without a lockfile the REGISTRY decides what executes and
# the repository stays identical while it changes. With one, that change is a
# diff. All three sites run on the same self-hosted Mac, so a transitive
# dependency executed here runs on the machine that later builds the other two —
# the asset being protected is the runner, not the website visitor.
#
# node_modules must never be tracked: `npm ci` creates it in the working tree
# and deletes any existing one first, so it is build output, not source.
#
# THE CLAUSE THIS REPO ACTUALLY FAILED is the exact-version one. Its manifest
# declared `^1.9.2` and `^17.14.1` — ranges — which left the odd state the
# reviewer named: the gate policy says pinned, the manifest says
# compatible-range, and only the lockfile says what runs. The caret does not
# float CI, because `npm ci` installs the lockfile; it just meant the manifest
# was not stating what anyone had chosen.

failed=0

# TRACKED, or on its way there. The strict form — `git ls-files` alone — cannot
# pass on the commit that INTRODUCES these files: sfl runs before
# FullBuildAndPush commits, so the very run that adds them would fail. That is
# not a hypothetical; it is how this gate first ran.
#
# So the question asked is the one that actually matters: will this file be in
# the repository? A file that exists and is not ignored gets committed by the
# add -A the runner does next. A file that is IGNORED never will be, however
# present it looks — which is exactly what was found here: .gitignore banned
# package.json and package-lock.json, so the manifest would have sat in the
# working tree forever while the repo had none.
#
# CI closes the remaining gap for free: it checks out the repository, so an
# uncommitted file simply is not there and the `-f` test fails.
for f in package.json package-lock.json; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    continue
  fi
  if [ ! -f "$f" ]; then
    echo "❌ FAIL: ${f} is missing — without it the registry decides what this repo executes, and nothing here would change to show it"
    failed=1
  elif git check-ignore -q "$f"; then
    echo "❌ FAIL: ${f} exists but .gitignore excludes it — it can never reach the repository, so this gate would pass on a working tree nobody else can reproduce"
    failed=1
  else
    echo "INFO: ${f} is present and not ignored, not yet committed — this run's commit adds it"
  fi
done

tracked="$(git ls-files)"
if grep -q '^node_modules/' <<<"$tracked"; then
  echo "❌ FAIL: node_modules must not be committed — npm ci deletes and recreates it, so a tracked copy is build output masquerading as source."
  failed=1
fi

# EXACT VERSIONS, not ranges. The lockfile already makes `npm ci` deterministic,
# so a caret does not float CI — but it leaves the odd state where the gate
# policy says pinned, the manifest says compatible-range, and only the lockfile
# says what runs. Two honest layers instead: the versions we chose, and the
# graph we resolved.
if [ -f package.json ]; then
  ranged="$(grep -oE '"[^"]+": *"[\^~][^"]+"' package.json || true)"
  if [ -n "$ranged" ]; then
    echo "❌ FAIL: package.json declares a version RANGE where the estate policy is an exact pin:"
    printf '       %s\n' "${ranged//$'\n'/$'\n'       }"
    failed=1
  fi
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "OK: manifest and lockfile committed, versions exact, node_modules untracked"
