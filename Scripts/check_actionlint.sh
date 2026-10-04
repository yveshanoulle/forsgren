#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# actionlint — static analysis for .github/workflows/*.yml.
#
# WHY THIS EXISTS. Valid YAML is not a valid workflow. On 2026-08-22
# another estate repository shipped `${{ runner.temp }}` in a job-level `env:` block:
# every local check was green, the file parsed as YAML, and GitHub refused it
# outright — *Unrecognized named-value: 'runner'*. The whole workflow failed
# to load, so **not one gate ran**, and the only thing that reported the
# problem was GitHub itself, after the push.
#
# Until this gate existed, every workflow edit in these repos was verified by
# pushing it. actionlint knows which contexts are available where, which is
# exactly the class of mistake that shipped.
#
# NO AUTO-INSTALL, deliberately. Another estate repository's sfl installs missing tools with
# brew; these repos do not, because installing software is not a thing a lint
# gate should do behind your back. A missing binary is reported with the
# remedy and fails.
#
# It does NOT skip when the tool is absent. sfl and CI both run on babacar,
# so a missing actionlint is a MACHINE FAULT in either case, and reporting
# green would hide it — the lesson from check_compose_config.sh, which used
# to print SKIP and exit 0 and kept lint green for a full day while the
# runner could not resolve docker at all.
#
# Local invocation: ./Scripts/check_actionlint.sh [workflow-dir]

WF_DIR="${1:-.github/workflows}"

if ! command -v actionlint >/dev/null 2>&1; then
  echo "actionlint: not found on PATH — cannot validate any workflow." >&2
  echo "  This check does not skip: sfl and CI both run on babacar, so a" >&2
  echo "  missing tool here is a machine fault, not a local convenience." >&2
  echo "  Install: brew install actionlint" >&2
  exit 3
fi

if [ ! -d "$WF_DIR" ]; then
  echo "actionlint: workflow dir not found: ${WF_DIR}" >&2
  exit 3
fi

count="$(find "$WF_DIR" -maxdepth 1 -name '*.yml' -type f | wc -l | tr -d ' ')"
if [ "$count" -eq 0 ]; then
  echo "actionlint: no workflows found under ${WF_DIR} — wrong directory?" >&2
  exit 3
fi

# NO -ignore flags. Every finding actionlint reported on first run was either
# real (an unused loop variable, ungrouped redirects — both fixed) or a
# configuration gap (self-hosted labels, now declared in .actionlint.yaml).
# Suppressions are added only for a finding someone has looked at and ruled
# on — an -ignore added pre-emptively silences the rule before it has ever
# said anything, which is how a gate arrives already half-asleep.
actionlint -config-file .actionlint.yaml "$WF_DIR"/*.yml

echo "OK: actionlint (${count} workflow(s) validated)"
