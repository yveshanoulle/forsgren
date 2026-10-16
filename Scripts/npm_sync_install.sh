#!/usr/bin/env bash
# canon: npm_sync_install v1
# Scripts/npm_sync_install.sh
#
# sfl's npm install step, the canon version: runs `npm ci` when
# node_modules is missing, or was installed from another package-lock.json
# than the one in the tree, and otherwise leaves it alone.
#
# WHY. sfl used to run `npm ci` only when a marker binary was missing
# (htmlhint, stylelint), so a devDependency added later (jscpd) was never
# installed on a machine that already had the others, and after a lockfile change (a pull, an npm audit
# fix) it kept running the old node_modules until someone reinstalled by hand.
#
# HOW. node_modules/.package-lock.sha256 holds the sha256 of the
# package-lock.json that node_modules was installed from. It lives INSIDE
# node_modules, so `npm ci` (which deletes node_modules) and a manual removal
# both drop it and force the next run to install. It is written only after a
# successful `npm ci`, and removed before one starts, so a failed install never
# leaves a stamp that vouches for a half-built tree. A node_modules without a
# stamp (installed before this step existed) is installed once more.
# The stamp is `<lockfile sha256> node<major>`: a Node major change reinstalls
# too, because the installed tree (native addons, engines checks) is the
# product of both. Stamps written before the Node major joined it (the hash
# alone) differ, so those trees are installed once more.
#
# Usage: Scripts/npm_sync_install.sh [dir]   (default: the repo root)
# Exit: 0 node_modules matches the lockfile (installed now or already),
#       1 package-lock.json missing or `npm ci` failed.
# Fixture: Scripts/test_npm_sync_install.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: npm_sync_install.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

fail_now() {
  echo "❌ FAIL: $*"
  COMPLETED=1
  exit 1
}

DIR="${1:-.}"
cd "$DIR" || fail_now "directory not found: ${DIR}"

STAMP_FILE="node_modules/.package-lock.sha256"

[ -f package-lock.json ] || fail_now "package-lock.json is missing — npm ci has nothing to install"

lock_hash="$(shasum -a 256 package-lock.json | awk '{ print $1 }')"
[ -n "$lock_hash" ] || fail_now "could not hash package-lock.json"

node_version="$(node --version 2>/dev/null || true)"
node_major="${node_version#v}"
node_major="${node_major%%.*}"
[[ "$node_major" =~ ^[0-9]+$ ]] || fail_now "could not read a Node major from 'node --version' (got '${node_version}') — npm ci needs node"

want="${lock_hash} node${node_major}"

stamp=""
if [ -f "$STAMP_FILE" ]; then
  stamp="$(cat "$STAMP_FILE")"
fi

if [ -d node_modules ] && [ "$stamp" = "$want" ]; then
  COMPLETED=1
  echo "OK: node_modules was installed from this package-lock.json and Node major (${want})"
  exit 0
fi

if [ ! -d node_modules ]; then
  reason="node_modules is missing"
elif [ -z "$stamp" ]; then
  reason="node_modules has no lockfile stamp"
else
  reason="package-lock.json or the Node major changed since node_modules was installed"
fi

echo "INFO: installing pinned devDependencies (npm ci): ${reason}"
rm -f "$STAMP_FILE"
if ! npm ci; then
  fail_now "npm ci failed — node_modules is not in sync with package-lock.json, and no stamp was written"
fi

mkdir -p node_modules
printf '%s\n' "$want" > "$STAMP_FILE"
COMPLETED=1
echo "OK: npm ci installed node_modules from package-lock.json (${want})"
