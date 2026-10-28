#!/usr/bin/env bash
# Scripts/gate_language_pages.sh (forsgren#220)
#
# The language gate over every page forsgren ships: the generated metrics site
# (.build/site) and the starter page (.build/starter, forsgren#132). The canon
# gate, Scripts/gate_language.sh, checks one directory, and a row of the order
# file names a script, not a command line, so this wrapper puts both in one
# temporary directory (the starter page as starter/index.html) and runs the
# gate on it. One run, one baseline, one report: a finding on the starter page
# is keyed by the page starter/index.html. The exit status and the output are
# the gate's own.
#
# The built site renders the TBD page with the median only (the default), so
# the all-figures table, with its own header aria-labels, was never read
# (forsgren#452). The golden page of that table (internal/page/testdata, pinned
# byte for byte to what forsgren renders with tbd_figures: all) goes in too, as
# golden/tbd.all.html: no extra build, so no change of the order of the gates.
#
# The terms (forsgren#369, decision #372 A): the dictionary of the pages
# (internal/dictionary/dictionary.yml, forsgren#370) is the list of terms the
# pages use on purpose, so its entry names and the labels they are shown as
# (the `shown` lists) are written to a plain list, one per line, which the
# canon gate takes with --terms: a term is allowed on every page for spelling
# and for the style rules the gate lists (TRUNK_BOOT), so the word trunk of
# Trunk-based development needs no baseline row. A dictionary line this reader
# cannot read (a name or a label that is not a double-quoted string, a shown
# value that is not a list of them) is exit 2, never a skipped term.
#
# Usage: Scripts/gate_language_pages.sh [site-dir [starter-dir [golden-page
#        [dictionary]]]]
#        (default: .build/site, .build/starter,
#        internal/page/testdata/tbd.all.golden.html and
#        internal/dictionary/dictionary.yml)
# Fixture: Scripts/test_gate_language_pages.sh.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

SITE="${1:-.build/site}"
STARTER="${2:-.build/starter}"
GOLDEN="${3:-internal/page/testdata/tbd.all.golden.html}"
DICTIONARY="${4:-internal/dictionary/dictionary.yml}"

PAGES="$(mktemp -d)"
TERMS="$(mktemp)"
# On bash 3.2 an abort (an unbound variable under set -eu) ends a script with
# an EXIT trap with status 0. COMPLETED, set as the very last statement, is the
# only way out with 0: an exit of 0 without it is an abort and becomes exit 1.
COMPLETED=0
finish() {
  local rc=$?
  rm -rf "$PAGES" "$TERMS"
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: gate_language_pages.sh aborted before completing (COMPLETED was never set)" >&2
    exit 1
  fi
}
trap finish EXIT

[[ -d "$SITE" ]] || { echo "❌ language gate: site dir not found: ${SITE}" >&2; exit 2; }
[[ -f "${STARTER}/index.html" ]] || { echo "❌ language gate: starter page not found: ${STARTER}/index.html" >&2; exit 2; }
[[ -f "$GOLDEN" ]] || { echo "❌ language gate: all-figures TBD golden page not found: ${GOLDEN}" >&2; exit 2; }

[[ -f "$DICTIONARY" ]] || { echo "❌ language gate: dictionary not found: ${DICTIONARY}" >&2; exit 2; }

# terms_of <dictionary>: every entry name and every shown label, once each
# (case ignored), one per line.
PYTHONIOENCODING=utf-8 python3 -I - "$DICTIONARY" > "$TERMS" <<'PY' || exit 2
import json
import re
import sys

path = sys.argv[1]
seen = set()
terms = []


def fail(number, line, what):
    print("❌ language gate: dictionary " + path + " line " + str(number) + ": " + what + ": " + line,
          file=sys.stderr)
    sys.exit(2)


def add(value):
    value = " ".join(value.split())
    if value and value.lower() not in seen:
        seen.add(value.lower())
        terms.append(value)


with open(path, encoding="utf-8") as handle:
    for number, raw in enumerate(handle, 1):
        line = raw.rstrip("\n")
        name = re.match(r"^- name: (.*)$", line)
        shown = re.match(r"^  shown: (.*)$", line)
        try:
            if name:
                value = json.loads(name.group(1))
                if not isinstance(value, str):
                    raise ValueError("not a string")
                add(value)
            elif shown:
                values = json.loads(shown.group(1))
                if not isinstance(values, list) or not all(isinstance(v, str) for v in values):
                    raise ValueError("not a list of strings")
                for value in values:
                    add(value)
        except ValueError:
            fail(number, line, "a name must be a double-quoted string and shown a list of them")

if not terms:
    print("❌ language gate: dictionary " + path + " holds no entry name", file=sys.stderr)
    sys.exit(2)
print("\n".join(terms))
PY

cp -R "${SITE}/." "$PAGES/"
mkdir -p "${PAGES}/starter"
cp "${STARTER}/index.html" "${PAGES}/starter/index.html"
mkdir -p "${PAGES}/golden"
cp "$GOLDEN" "${PAGES}/golden/tbd.all.html"

# GATE_LANGUAGE_PAGES_GATE is the testing seam: the self-test points it at a
# stub that records the directory it is given.
set +e
if [[ -n "${GATE_LANGUAGE_PAGES_GATE:-}" ]]; then
  "$GATE_LANGUAGE_PAGES_GATE" --terms "$TERMS" "$PAGES"
else
  ./Scripts/gate_language.sh --terms "$TERMS" "$PAGES"
fi
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi
COMPLETED=1
