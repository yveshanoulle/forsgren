"""Count the entries in stylelint's --formatter json output.

Takes any number of files and prints the length of the first one that parses
as a JSON array. stylelint writes this to STDERR rather than stdout (measured
2026-08-22), and reading only one stream made check_lint_coverage report a
coverage gap that did not exist — so the caller hands us both and we take
whichever actually carries the payload. Prints nothing when none parse, which
the caller must treat as BLIND rather than as zero.
"""
import json
import sys

for path in sys.argv[1:]:
    try:
        with open(path, encoding="utf-8") as handle:
            raw = handle.read().strip()
    except OSError:
        continue
    if not raw:
        continue
    try:
        parsed = json.loads(raw)
    except ValueError:
        continue
    if isinstance(parsed, list):
        print(len(parsed))
        break
