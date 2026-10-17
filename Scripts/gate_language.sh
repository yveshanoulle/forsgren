#!/usr/bin/env bash
# canon: gate_language v1
# Scripts/gate_language.sh (estate issue 300)
#
# The language gate (POST): the visible text of every built page, checked by
# LanguageTool on THIS machine, offline. Self-test: Scripts/test_gate_language.sh.
#
# WHAT IS CHECKED. Per HTML file of the site directory: the text a visitor
# reads, in the language of its html lang attribute, or of the nearest element
# with its own lang attribute. Not checked: head, script, style, pre, svg; an
# inline code, kbd or samp element counts as the one word `code`. The values of
# alt, title and aria-label are checked too. A language is mapped to a
# LanguageTool locale by language_locales in Scripts/language_settings.txt (an
# unmapped language, or a page with no lang, is exit 2, never skipped).
#
# LOCAL ONLY. The command-line tool is the only mode used: no server, no remote
# rules, no n-gram or other download. Every run is wrapped in sandbox-exec with
# the network denied, so no site text can leave the machine even by a mistake in
# a configuration. No sandbox-exec, or a profile that cannot be applied, is
# exit 2.
#
# THE TWO DATA FILES (both required; a missing file is exit 2, never a waiver):
#   Scripts/language_allowlist.txt   one word per line (# comments): names,
#       brands, places. LanguageTool's command line has no personal dictionary,
#       so the gate drops a SPELLING match (issue type misspelling) whose text is
#       in the list, or whose words all are.
#   Scripts/language_baseline.txt    one row per remaining finding:
#       page|lang|rule|match|context|count|reason
#       page relative to the site directory; lang the LanguageTool locale; match
#       the flagged text; context up to 12 characters either side of it inside
#       its paragraph; count how often it occurs; reason required. A row is keyed
#       by those five fields, NEVER by an offset, so editing text elsewhere does
#       not churn the file. A literal | in a field is written as the broken bar.
#       The baseline only SHRINKS, like the image size baseline: a finding not
#       listed is new; one that occurs more often than recorded is new; a row
#       whose finding is gone, or occurs less often, is stale (remove the row or
#       lower the count). Add no row to clear a red unless the finding is judged
#       a false positive or an accepted exception, with its reason.
#
# MODE, language_mode in Scripts/language_settings.txt:
#   enforce  a new finding or a stale row is red (exit 1)
#   warn     the same are printed as warnings and the gate exits 0; the OK line
#            says it is warn-only
# A missing or failing LanguageTool or Java is exit 2 in BOTH modes: a gate that
# cannot run never reports a pass. A LanguageTool of another version than
# language_tool_version is red in enforce and a warning in warn (a dictionary
# change moves the findings).
#
# THE SETTINGS, Scripts/language_settings.txt (key=value, # comments, all three
# required, none repeated, none unknown, else exit 2): language_mode (enforce or
# warn), language_locales (comma separated lang:locale pairs, e.g.
# nl:nl-BE,en:en-GB) and language_tool_version (the version the baseline was
# recorded with). A separate file, read here, so the site settings reader stays
# as it is in every repository. The site directory comes from site_dir of
# Scripts/site_settings.txt unless it is given.
#
# Usage: gate_language.sh [site-dir [allowlist [baseline [language-settings]]]]
# Environment: GATE_LANGUAGE_TOOL names the languagetool command (default: the
# one on PATH, else the Homebrew keg path, which a CI runner without the
# Homebrew PATH still finds); JAVA_HOME defaults to the Homebrew openjdk@17
# LanguageTool depends on (the keg is not linked, so no other job sees it).

set -euo pipefail

cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
# On bash 3.2 an abort (an unbound variable under set -eu) ends a script with
# an EXIT trap with status 0. COMPLETED, set as the very last statement, is the
# only way out with 0: an exit of 0 without it is an abort and becomes exit 1.
COMPLETED=0
finish() {
  local rc=$?
  rm -rf "$WORK"
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: gate_language.sh aborted before completing (COMPLETED was never set)" >&2
    exit 1
  fi
}
trap finish EXIT

tool_fail() { echo "❌ $*" >&2; exit 2; }

# shellcheck source=Scripts/lib_site_settings.sh
source Scripts/lib_site_settings.sh
SITE_DIR="${1:-}"
if [[ -z "$SITE_DIR" ]]; then
  SITE_DIR="$(site_settings_get Scripts/site_settings.txt site_dir)" || exit 2
fi
SITE_DIR="${SITE_DIR%/}"
ALLOWLIST="${2:-Scripts/language_allowlist.txt}"
BASELINE="${3:-Scripts/language_baseline.txt}"
SETTINGS="${4:-Scripts/language_settings.txt}"

# language_setting <key>: the value of <key> in the settings file, after the
# whole file is validated (a missing file, a malformed, unknown, repeated or
# missing key and an invalid value are each exit 2, with the reason).
language_setting() {
  local line key value n=0 seen=" " k found=""
  [[ -f "$SETTINGS" ]] || tool_fail "language gate: settings file not found: ${SETTINGS}"
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    case "$line" in '' | '#'*) continue ;; esac
    [[ "$line" =~ ^[a-z][a-z0-9_]*=[^[:space:]]+$ ]] || tool_fail "language gate: malformed line ${n} in ${SETTINGS}: ${line}"
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      language_mode) [[ "$value" =~ ^(enforce|warn)$ ]] || tool_fail "language gate: invalid value for 'language_mode' (line ${n} of ${SETTINGS}): ${value}; enforce or warn" ;;
      language_locales) [[ "$value" =~ ^[a-z]{2,3}:[A-Za-z]{2,3}(-[A-Za-z0-9]+)*(,[a-z]{2,3}:[A-Za-z]{2,3}(-[A-Za-z0-9]+)*)*$ ]] || tool_fail "language gate: invalid value for 'language_locales' (line ${n} of ${SETTINGS}): ${value}; lang:locale pairs" ;;
      language_tool_version) [[ "$value" =~ ^[0-9]+(\.[0-9]+)+$ ]] || tool_fail "language gate: invalid value for 'language_tool_version' (line ${n} of ${SETTINGS}): ${value}" ;;
      *) tool_fail "language gate: unknown key '${key}' (line ${n} of ${SETTINGS})" ;;
    esac
    case "$seen" in *" ${key} "*) tool_fail "language gate: duplicate key '${key}' (line ${n} of ${SETTINGS})" ;; esac
    seen="${seen}${key} "
    [[ "$key" == "$1" ]] && found="$value"
  done < "$SETTINGS"
  for k in language_mode language_locales language_tool_version; do
    case "$seen" in *" ${k} "*) ;; *) tool_fail "language gate: required key '${k}' is missing from ${SETTINGS}" ;; esac
  done
  printf '%s\n' "$found"
}
MODE="$(language_setting language_mode)"
LOCALES="$(language_setting language_locales)"
PINNED_VERSION="$(language_setting language_tool_version)"

[[ -d "$SITE_DIR" ]] || tool_fail "language gate: site dir not found: ${SITE_DIR}"
[[ -f "$ALLOWLIST" ]] || tool_fail "language gate: allowlist not found: ${ALLOWLIST}"
[[ -f "$BASELINE" ]] || tool_fail "language gate: baseline not found: ${BASELINE}"

# LanguageTool and Java: found, or the gate fails and says what is missing.
LT_BIN="${GATE_LANGUAGE_TOOL:-}"
if [[ -z "$LT_BIN" ]]; then
  LT_BIN="$(command -v languagetool || true)"
  [[ -n "$LT_BIN" ]] || LT_BIN="/opt/homebrew/opt/languagetool/bin/languagetool"
fi
[[ -x "$LT_BIN" ]] || tool_fail "LanguageTool is missing: ${LT_BIN} (brew install languagetool)"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
[[ -x "${JAVA_HOME}/bin/java" ]] || tool_fail "Java is missing: ${JAVA_HOME}/bin/java (LanguageTool runs on openjdk@17, installed with it by brew)"

# No network for LanguageTool, enforced by the operating system.
SANDBOX_PROFILE='(version 1)(allow default)(deny network*)'
command -v sandbox-exec >/dev/null 2>&1 || tool_fail "sandbox-exec is missing: LanguageTool cannot be run without network, so it is not run"
sandbox-exec -p "$SANDBOX_PROFILE" /usr/bin/true >/dev/null 2>&1 || tool_fail "sandbox-exec cannot apply the no-network profile: LanguageTool is not run"
run_lt() { sandbox-exec -p "$SANDBOX_PROFILE" "$LT_BIN" "$@"; }

set +e
VERSION_OUT="$(run_lt --version 2>&1 </dev/null)"
vrc=$?
set -e
[[ "$vrc" -eq 0 ]] || tool_fail "LanguageTool failed (exit ${vrc}) on --version: ${VERSION_OUT}"
LT_VERSION="$(printf '%s\n' "$VERSION_OUT" | sed -n 's/^LanguageTool version \([0-9][0-9.]*\).*/\1/p' | head -n 1)"
[[ -n "$LT_VERSION" ]] || tool_fail "cannot read the LanguageTool version from: ${VERSION_OUT}"
if [[ "$LT_VERSION" != "$PINNED_VERSION" ]]; then
  VERSION_MSG="LanguageTool is ${LT_VERSION}, the pinned version is ${PINNED_VERSION} (language_tool_version in ${SETTINGS})"
  if [[ "$MODE" == "enforce" ]]; then
    echo "❌ ${VERSION_MSG}"
    exit 1
  fi
  echo "⚠️ warn: ${VERSION_MSG}"
fi

# The visible text of every page, one file per language.
PYTHONIOENCODING=utf-8 python3 -I - "$SITE_DIR" "$LOCALES" "$WORK" <<'PY'
import os
import re
import sys
from html.parser import HTMLParser

site, locales, work = sys.argv[1:4]
locale_of = dict(pair.split(":", 1) for pair in locales.split(","))

SKIP = {"script", "style", "pre", "noscript", "svg", "head", "template"}
CODE = {"code", "kbd", "samp"}
HEADINGS = {"h1", "h2", "h3", "h4", "h5", "h6"}
BLOCK = {
    "p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "section",
    "article", "header", "footer", "nav", "main", "tr", "td", "th", "table", "br",
    "blockquote", "dt", "dd", "dl", "button", "label", "option", "select",
    "figure", "figcaption", "aside", "summary", "details",
}
VOID = {"br", "img", "input", "meta", "link", "hr", "source", "wbr", "area",
        "base", "col", "embed", "track"}


def fail(message):
    print("❌ " + message, file=sys.stderr)
    sys.exit(2)


def primary(value):
    return value.strip().lower().split("-")[0]


class Page(HTMLParser):
    def __init__(self, name):
        super().__init__(convert_charrefs=True)
        self.name = name
        self.stack = []
        self.skip = 0
        self.cur = []
        self.cur_lang = None
        self.body = {}
        self.attrs = {}
        self.seen_attrs = set()
        self.has_html = False

    def lang(self):
        for _tag, value in reversed(self.stack):
            if value:
                return value
        return None

    def flush(self):
        text = re.sub(r"\s+", " ", "".join(self.cur)).strip()
        self.cur = []
        if text:
            self.body.setdefault(self.cur_lang, []).append(text)

    def add(self, text):
        if self.skip > 0:
            return
        if not self.cur:
            self.cur_lang = self.lang()
        self.cur.append(text)

    def handle_starttag(self, tag, attributes):
        found = dict(attributes)
        if tag == "html":
            self.has_html = True
        own = primary(found["lang"]) if found.get("lang") else None
        if tag != "html":
            for kind in ("alt", "title", "aria-label"):
                value = (found.get(kind) or "").strip()
                if value and self.skip <= 0:
                    where = own or self.lang()
                    if (where, value) not in self.seen_attrs:
                        self.seen_attrs.add((where, value))
                        self.attrs.setdefault(where, []).append(value)
        if tag in VOID:
            if tag == "br":
                if any(t in HEADINGS for t, _ in self.stack):
                    self.add(" ")
                else:
                    self.flush()
            return
        if tag in BLOCK or own:
            self.flush()
        self.stack.append((tag, own))
        if tag in SKIP:
            self.skip += 1
        elif tag in CODE:
            self.add(" code ")
            self.skip += 1

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if tag in BLOCK or (self.stack and self.stack[-1][1]):
            self.flush()
        for index in range(len(self.stack) - 1, -1, -1):
            if self.stack[index][0] == tag:
                for closed, _ in self.stack[index:]:
                    if closed in SKIP or closed in CODE:
                        self.skip -= 1
                del self.stack[index:]
                break

    def handle_data(self, data):
        self.add(data)


pages = sorted(
    os.path.relpath(os.path.join(root, name), site)
    for root, _dirs, names in os.walk(site)
    for name in names
    if name.endswith(".html")
)
if not pages:
    fail("language gate: no HTML file under " + site + ": nothing scanned is not clean")

text = {}
for rel in pages:
    with open(os.path.join(site, rel), encoding="utf-8") as handle:
        source = handle.read()
    match = re.search(r"<html\b[^>]*\blang\s*=\s*[\"']?([A-Za-z-]+)", source)
    if not match:
        fail("language gate: " + rel + " has no lang on its html element")
    page = Page(rel)
    page.feed(source)
    page.close()
    page.flush()
    groups = {}
    for lang, paragraphs in page.body.items():
        groups.setdefault(lang or primary(match.group(1)), []).extend(paragraphs)
    for lang, values in page.attrs.items():
        groups.setdefault(lang or primary(match.group(1)), []).extend(values)
    for lang, paragraphs in groups.items():
        if lang not in locale_of:
            fail("language gate: no locale for language '" + lang + "' (" + rel
                 + "); add it to language_locales in Scripts/language_settings.txt")
        text.setdefault(lang, []).append((rel, paragraphs))

with open(os.path.join(work, "langs.txt"), "w", encoding="utf-8") as langs:
    for pair in locales.split(","):
        lang, locale = pair.split(":", 1)
        if lang not in text:
            continue
        with open(os.path.join(work, "text." + lang + ".txt"), "w", encoding="utf-8") as out:
            for rel, paragraphs in text[lang]:
                out.write("PAGEMARK " + rel + "\n\n")
                out.write("\n\n".join(paragraphs) + "\n\n")
        langs.write(lang + " " + locale + "\n")
with open(os.path.join(work, "pages.txt"), "w", encoding="utf-8") as count:
    count.write(str(len(pages)) + "\n")
PY

# LanguageTool, once per language, offline.
while read -r lang locale; do
  set +e
  run_lt -l "$locale" --json -c utf-8 "${WORK}/text.${lang}.txt" </dev/null >"${WORK}/lt.${lang}.json" 2>"${WORK}/lt.${lang}.err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    tool_fail "LanguageTool failed (exit ${rc}) for ${locale}: $(tail -n 3 "${WORK}/lt.${lang}.err" | tr '\n' ' ')"
  fi
done < "${WORK}/langs.txt"

# The findings against the allowlist and the baseline.
set +e
PYTHONIOENCODING=utf-8 python3 -I - "$WORK" "$MODE" "$LT_VERSION" "$ALLOWLIST" "$BASELINE" <<'PY'
import bisect
import json
import os
import sys

work, mode, version, allow_path, base_path = sys.argv[1:6]
enforcing = (mode == "enforce")
WINDOW = 12
MARK = "PAGEMARK "


def config_error(message):
    print("❌ language gate: " + message, file=sys.stderr)
    sys.exit(2)


def clean(value):
    return " ".join(value.replace("|", "¦").split())


allowed = set()
with open(allow_path, encoding="utf-8") as handle:
    for number, line in enumerate(handle, 1):
        word = line.strip()
        if not word or word.startswith("#"):
            continue
        if word in allowed:
            config_error(allow_path + " line " + str(number) + ": " + word + " is listed twice")
        allowed.add(word)


def allowlisted(text):
    return text in allowed or (bool(text.split()) and all(w in allowed for w in text.split()))


base = {}
reasons = {}
with open(base_path, encoding="utf-8") as handle:
    for number, line in enumerate(handle, 1):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        at = base_path + " line " + str(number)
        fields = [f.strip() for f in line.split("|")]
        if len(fields) != 7 or not all(fields[:5]) or not fields[6]:
            config_error(at + ": a row is page|lang|rule|match|context|count|reason, with a reason")
        if not fields[5].isdigit() or int(fields[5]) == 0:
            config_error(at + ": count must be a positive whole number")
        key = tuple(fields[:5])
        if key in base:
            config_error(at + ": " + " | ".join(key) + " is listed twice")
        base[key] = int(fields[5])

pages_total = int(open(os.path.join(work, "pages.txt")).read())
langs = [row.split() for row in open(os.path.join(work, "langs.txt")).read().splitlines() if row.strip()]

found = {}
total = 0
allowlisted_n = 0
for lang, locale in langs:
    with open(os.path.join(work, "text." + lang + ".txt"), encoding="utf-8") as handle:
        text = handle.read()
    units = text.encode("utf-16-le")

    def piece(start, end):
        return units[2 * start:2 * end].decode("utf-16-le", errors="ignore")

    line_starts = []
    line_ends = []
    page_at = []
    page = None
    cursor = 0
    for line in text.splitlines(keepends=True):
        width = len(line.encode("utf-16-le")) // 2
        body = line.rstrip("\r\n")
        line_starts.append(cursor)
        line_ends.append(cursor + len(body.encode("utf-16-le")) // 2)
        if body.startswith(MARK):
            page = body[len(MARK):].strip()
        page_at.append((page, body.startswith(MARK)))
        cursor += width

    with open(os.path.join(work, "lt." + lang + ".json"), encoding="utf-8") as handle:
        result = json.load(handle)
    for match in result.get("matches", []):
        offset = match["offset"]
        length = match["length"]
        row = bisect.bisect_right(line_starts, offset) - 1
        marker_hit = page_at[row][1]
        if marker_hit:
            continue
        total += 1
        page = page_at[row][0]
        found_text = clean(piece(offset, offset + length))
        before = piece(max(line_starts[row], offset - WINDOW), offset)
        after = piece(offset + length, min(line_ends[row], offset + length + WINDOW))
        ctx = clean(before + piece(offset, offset + length) + after)
        rule = clean(match["rule"]["id"])
        text_clean = found_text
        issue = match["rule"].get("issueType", "")
        if issue == "misspelling" and allowlisted(piece(offset, offset + length).strip()):
            allowlisted_n += 1
            continue
        key = (page, locale, rule, text_clean, ctx)
        found.setdefault(key, []).append(match.get("message", ""))

baselined = 0
new = []
stale = []
for key in sorted(found):
    items = found[key]
    held = min(len(items), base.get(key, 0))
    baselined += held
    for item in items[held:]:
        new.append((key, item))
for key in sorted(base):
    now = len(found.get(key, []))
    if base[key] > now:
        stale.append((key, base[key], now))


def where(key):
    return key[0] + " [" + key[1] + "] " + key[2] + ": \"" + key[3] + "\" in \"" + key[4] + "\""


mark = "❌ " if enforcing else "⚠️ warn: "
for key, item in new:
    print(mark + "new finding: " + where(key) + " (" + item + ")")
for key, recorded, now in stale:
    if now == 0:
        print(mark + "stale baseline row: " + where(key) + " is gone (recorded " + str(recorded) + ", now 0); remove the row")
    else:
        print(mark + "stale baseline row: " + where(key) + " occurs less often (recorded " + str(recorded) + ", now " + str(now) + "); lower the row")

if enforcing and (new or stale):
    print("❌ language gate: " + str(total) + " matches, " + str(allowlisted_n) + " allowlisted, " + str(baselined)
          + " baselined, " + str(len(new)) + " new, " + str(len(stale)) + " stale baseline row(s); "
          "fix the text, or list the finding with its reason in " + base_path + " / " + allow_path)
    sys.exit(1)

names = ", ".join(locale for _lang, locale in langs)
label = "language gate" if enforcing else "language gate (warn-only)"
print("OK: " + label + ": " + str(pages_total) + " pages, " + str(len(langs)) + " languages (" + names + "), "
      + str(total) + " matches, " + str(allowlisted_n) + " allowlisted, " + str(baselined) + " baselined, "
      + str(len(new)) + " new, LanguageTool " + version + ", mode " + mode)
PY
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi
COMPLETED=1
