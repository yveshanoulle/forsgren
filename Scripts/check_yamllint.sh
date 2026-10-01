#!/usr/bin/env bash
# Yamllint — every tracked YAML file. Config in .yamllint.yml.
#
# Ported from konenki-website 2026-10-01 (forsgren#1, ladder step 12), which
# ported it from web-infra (its unit 411 put it in the canon). konenki lints
# .github/workflows/ and web-infra adds its compose stacks/, each a NAMED
# directory. forsgren had no workflow directory when this was ported (CI came
# in forsgren#1 step 14), and `yamllint .github/workflows/` on a directory
# that does not exist exits 255. So the targets here are DERIVED, the way Scripts/check_shellcheck.sh
# derives its own: every git-tracked *.yml / *.yaml at any depth. A workflow,
# a .golangci.yml or any other YAML is covered the moment it is tracked,
# instead of when someone remembers to name its directory.
#
# Never empty today: .yamllint.yml is itself tracked YAML and is linted under
# its own rules. So zero targets means the collection broke, and it is red,
# never a green over nothing.
#
# NOT what actionlint does. actionlint reads a workflow as a WORKFLOW and misses
# nothing about its schema; yamllint reads it as YAML — indentation that parses
# but means something else, trailing whitespace, a duplicate key where the last
# one silently wins.
#
# Testing seam: YAMLLINT_ROOT overrides the repo root so
# Scripts/test_check_yamllint.sh can drive target collection against a
# synthetic git tree (same seam as check_shellcheck.sh's SHELLCHECK_ROOT).
# The config is always this repository's .yamllint.yml, so the fixture tests
# the rules that run here.
#
# Local invocation: ./Scripts/check_yamllint.sh

set -euo pipefail

CONFIG="$(cd "$(dirname "$0")/.." && pwd)/.yamllint.yml"
ROOT="${YAMLLINT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

if ! command -v yamllint >/dev/null 2>&1; then
  echo "❌ FAIL: yamllint is not installed — this gate cannot run, and a gate that cannot run must not report a pass" >&2
  echo "   brew install yamllint" >&2
  exit 1
fi

# The listing goes through a variable, not a process substitution: a failing
# `git ls-files` inside `< <(...)` is invisible, and an empty listing would
# then read as "no YAML here".
if ! listing="$(git ls-files '*.yml' '*.yaml')"; then
  echo "❌ FAIL: git ls-files failed in ${ROOT} — no verdict" >&2
  exit 1
fi

# A plain loop rather than mapfile: bash 3.2 has no mapfile.
targets=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  targets+=("$f")
done <<< "$listing"

if [ "${#targets[@]}" -eq 0 ]; then
  echo "❌ FAIL: yamllint: no tracked .yml or .yaml file found under ${ROOT} — .yamllint.yml alone should be one, so the collection is broken" >&2
  exit 1
fi

# Same reasoning as konenki's shellcheck gate: the full report to a gitignored
# file, because sfl's summary block quotes only its first lines.
mkdir -p .build
rc=0
yamllint -c "$CONFIG" "${targets[@]}" 2>&1 | tee .build/yamllint.log || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "(full report: ${ROOT}/.build/yamllint.log)" >&2
fi
exit "$rc"
