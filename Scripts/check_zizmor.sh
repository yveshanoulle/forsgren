#!/usr/bin/env bash
# Zizmor — GitHub Actions static analysis (workflows + composite actions). Catches
# the template-injection class actionlint does not: untrusted ${{ ... }} context
# values interpolated straight into run: shell, where a malicious value can break
# out and run commands with the runner's token/keys. --min-severity high targets
# that injection class (zizmor rates template-injection High) rather than every
# hygiene audit; --offline needs no GitHub token and stays deterministic. Shared
# source of truth for both sfl.sh and quality.yml (one row of
# Scripts/gate_report_order.txt).
#
# PORTED (forsgren#1, ladder step 19) from web-infra/Scripts/check_zizmor.sh,
# adapted only in its paths: the directory to scan is an optional argument,
# default .github, so Scripts/test_check_zizmor.sh can hand it fixtures.
# zizmor reads the config from that directory (.github/zizmor.yml here) and
# every .yml and .yaml workflow under it. It is red on its own on a directory
# with no workflow (exit 3, "no inputs collected") and on one that does not
# exist (exit 1).
#
# Callers ensure zizmor is installed: sfl through Scripts/install_tools.sh and
# Scripts/required_tools.txt; CI installs nothing, so a missing zizmor there
# is red here, by name.
#
# Local invocation: ./Scripts/check_zizmor.sh [dir]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

zizmor --offline --min-severity high "${1:-.github}"
