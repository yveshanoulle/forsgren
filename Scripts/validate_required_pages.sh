#!/usr/bin/env bash
# canon: validate_required_pages v1
set -euo pipefail

cd "$(dirname "$0")/.."

# Validates the required-pages manifest — the release's declaration of which pages
# it must serve.
#
# The manifest ships inside the release artifact, and promotion to live reads it
# from the promoted release to decide what to verify over HTTP. A malformed
# manifest would therefore turn promotion into an ambiguous partial check that
# still reports success, which is the weak verification this arc exists to
# remove. So it is validated here, before a release is promotable.
#
# Every rejection names the offending entry: a bare non-zero exit sends whoever
# hits it hunting through the file.
#
# Usage: validate_required_pages.sh [<manifest-path>]
#
# With no argument the manifest is the repository's own, required_pages_manifest
# in Scripts/site_settings.txt (read through Scripts/lib_site_settings.sh), so
# the order file can name a bare script path. An EXPLICIT empty argument is
# still a usage error. The script works from the repository root, so a relative
# path is relative to it.

# shellcheck source=Scripts/lib_site_settings.sh
source Scripts/lib_site_settings.sh
if [[ $# -ge 1 ]]; then
  MANIFEST="$1"
else
  MANIFEST="$(site_settings_get Scripts/site_settings.txt required_pages_manifest)"
fi
if [[ -z "$MANIFEST" ]]; then
  echo "Usage: $0 [<manifest-path>]" >&2
  exit 2
fi

if [[ ! -f "$MANIFEST" ]]; then
  # Absence is a hard failure, never a fallback: a release without its
  # manifest is an invalid release.
  echo "FAIL manifest not found: ${MANIFEST}" >&2
  exit 1
fi

python3 - "$MANIFEST" <<'PY'
import json
import sys

path = sys.argv[1]
problems = []

try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except json.JSONDecodeError as exc:
    print(f"FAIL not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print("FAIL top level must be an object with a requiredPages key", file=sys.stderr)
    sys.exit(1)

if "requiredPages" not in data:
    print("FAIL missing key: requiredPages", file=sys.stderr)
    sys.exit(1)

pages = data["requiredPages"]

if not isinstance(pages, list):
    print("FAIL requiredPages must be an array", file=sys.stderr)
    sys.exit(1)

# An empty list would make promotion verify nothing and still report success.
if not pages:
    print("FAIL requiredPages is empty — promotion would verify nothing", file=sys.stderr)
    sys.exit(1)

seen = set()
for entry in pages:
    if not isinstance(entry, str):
        problems.append(f"not a string: {entry!r}")
        continue
    # A scheme and host would let a manifest point verification at a site other
    # than the one being promoted — green while proving nothing about live.
    if "://" in entry:
        problems.append(f"has a scheme and host: {entry}")
    elif entry.startswith("//"):
        problems.append(f"is protocol-relative: {entry}")
    elif not entry.startswith("/"):
        # Entries are joined onto a base URL, so a missing leading slash
        # silently changes which path gets checked.
        problems.append(f"is not root-relative (needs a leading slash): {entry}")
    if ".." in entry.split("/"):
        problems.append(f"contains a .. segment: {entry}")
    if entry in seen:
        problems.append(f"is a duplicate: {entry}")
    seen.add(entry)

if problems:
    for problem in problems:
        print(f"FAIL entry {problem}", file=sys.stderr)
    sys.exit(1)

for entry in pages:
    print(f"OK   {entry}")
PY
