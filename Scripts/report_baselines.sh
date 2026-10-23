#!/usr/bin/env bash
# canon: report_baselines v4
# Scripts/report_baselines.sh <language|browser|image> [data-dir] (estate issue 300)
#
# Renders one gate's baseline data as markdown tables, so what a site has
# agreed to live with is visible on the Quality run page and not only in a data
# file. Quality has one step per section, each `if: always()`, so each shows
# even when a gate is red:
#   language   Scripts/language_baseline.txt (page | language | text | sentence |
#              rule | times | reason) and the words of Scripts/language_allowlist.txt
#   browser    Scripts/browser_gate_baseline.txt, then (v3) every further
#              Scripts/browser_gate_*_baseline.txt, each under a heading (its first
#              comment line, else its name), each as: the axe rows (variant | page |
#              rule | selector | reason), the CLS rows (variant | page | value |
#              reason), the sideways rows (v4, forsgren#350: variant | page |
#              viewport | what | px | reason), then a summary by rule and by page
#              with counts
#   image      Scripts/image_size_exceptions.txt (path | bytes | reason)
#
# THE SENTENCE (v2). The baseline stores a row's recorded context, never the
# sentence. The report finds that context in the visible text of the row's own
# page, extracted by the gate itself (Scripts/gate_language.sh --text, so the text
# is exactly what the gate checked), and shows the enclosing sentence: bounded by
# . ! or ? followed by a space, or by the paragraph, and cut near 200 characters
# with … where it is cut. A page that is not there says "page not found: <page>",
# a context that is not on the page "not found in <page>"; neither is empty and
# neither fails the step, because the gate is red for a stale row anyway. The
# pages are read from language_page_roots of Scripts/language_settings.txt
# (optional, default Site): comma separated dir or prefix=dir entries, a prefix
# putting that dir under prefix/ in the page names, as the baseline keys them.
#
# It reads the data files and runs no gate. The recorded rows are what the
# gate holds the site to (a stale one is red there), so the report lists the
# rows. The allowlist is listed as words only: how often each matched is known
# only to a LanguageTool run, which this report does not make, and it says so.
#
# Output: markdown on stdout, and appended to $GITHUB_STEP_SUMMARY when that is
# set. A file with no row says "no rows (empty baseline)". A file the site does
# not have says so, and exit is 0: a site without that gate still lists the
# step. A file that exists but cannot be read, or has a malformed row, FAILS the
# script (exit 1) and prints nothing else, never a warning. An unknown section,
# or none, is exit 2.
#
# [data-dir] defaults to Scripts and exists for the self-test,
# Scripts/test_report_baselines.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT_FILE="$(mktemp)"
TMPD="$(mktemp -d)"
# On bash 3.2 an abort (an unbound variable under set -eu) ends a script with
# an EXIT trap with status 0. COMPLETED, set as the very last statement, is the
# only way out with 0: an exit of 0 without it is an abort and becomes exit 1.
COMPLETED=0
finish() {
  local rc=$?
  rm -rf "$OUT_FILE" "$TMPD"
  if [ "$rc" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "FAIL: report_baselines.sh aborted before completing (COMPLETED was never set)" >&2
    exit 1
  fi
}
trap finish EXIT

SECTION="${1:-}"
DIR="${2:-Scripts}"
case "$SECTION" in
  language | browser | image) ;;
  *)
    echo "❌ report_baselines: unknown section '${SECTION}': language, browser or image" >&2
    exit 2
    ;;
esac

# need <file> <what>: prints the "this site has none" line and returns 1 when
# the file is absent; exits 1 when it exists and cannot be read.
absent() {
  if [[ ! -e "$1" ]]; then
    printf '_No %s: this site has no \140%s\140._\n' "$2" "$1"
    return 0
  fi
  [[ -f "$1" && -r "$1" ]] || { echo "❌ report_baselines: cannot read ${1}" >&2; exit 1; }
  return 1
}

# Shared awk helpers: a cell is escaped for a markdown table, a code cell is
# literal text.
read -r -d '' AWK_COMMON <<'AWK' || true
function cell(v) { gsub(/\|/, "\\|", v); return v }
function code(v) { return "\140" cell(v) "\140" }
function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
function bad(msg) { print "❌ report_baselines: " FILENAME " line " FNR ": " msg > "/dev/stderr"; failed = 1 }
function skip() { return ($0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]*#/) }

AWK

# sentences_for <baseline> <out-file>: one line per data row of the baseline, in
# order: the sentence of the row from its own page (see THE SENTENCE above).
sentences_for() {
  local base="$1" out="$2" settings="${DIR}/language_settings.txt"
  local roots="Site" entry prefix dir merged="${TMPD}/pages" textdir="${TMPD}/text" any=""
  [[ -f "$settings" && -r "$settings" ]] || { echo "❌ report_baselines: settings file not found: ${settings}" >&2; exit 1; }
  entry="$(grep -E '^language_page_roots=' "$settings" | head -n 1 || true)"
  [[ -z "$entry" ]] || roots="${entry#*=}"
  mkdir -p "$merged"
  local IFS=','
  for entry in $roots; do
    prefix=""
    dir="$entry"
    if [[ "$entry" == *=* ]]; then prefix="${entry%%=*}"; dir="${entry#*=}"; fi
    [[ -d "$dir" ]] || continue
    mkdir -p "${merged}/${prefix}"
    cp -R "${dir}/." "${merged}/${prefix}/"
  done
  unset IFS
  if [[ -n "$(find "$merged" -name '*.html' -print -quit)" ]]; then
    any=1
    ./Scripts/gate_language.sh --text "$textdir" "$merged" "${DIR}/language_allowlist.txt" "$base" "$settings" \
      || { echo "❌ report_baselines: cannot extract the page text (Scripts/gate_language.sh --text failed)" >&2; exit 1; }
  fi
  PYTHONIOENCODING=utf-8 python3 -I - "${any:+$textdir}" "$base" "$out" <<'PY'
import os
import re
import sys

textdir, base, out = sys.argv[1:4]
CAP = 200
BOUNDARIES = ".!?"

by_lang = {}
if textdir:
    for name in sorted(os.listdir(textdir)):
        match = re.match(r"text\.(.+)\.txt$", name)
        if not match:
            continue
        pages = by_lang.setdefault(match.group(1), {})
        page = None
        with open(os.path.join(textdir, name), encoding="utf-8") as handle:
            for line in handle.read().splitlines():
                if line.startswith("PAGEMARK "):
                    page = line[len("PAGEMARK "):].strip()
                    pages[page] = []
                elif line.strip() and page is not None:
                    pages[page].append(line)


def sentence_of(paragraph, start, end):
    left = 0
    for i in range(start - 1, -1, -1):
        if paragraph[i] in BOUNDARIES and i + 1 < len(paragraph) and paragraph[i + 1].isspace():
            left = i + 1
            break
    right = len(paragraph)
    for j in range(end, len(paragraph)):
        if paragraph[j] in BOUNDARIES and (j + 1 == len(paragraph) or paragraph[j + 1].isspace()):
            right = j + 1
            break
    while left < start and paragraph[left].isspace():
        left += 1
    sentence = paragraph[left:right]
    start -= left
    end -= left
    if len(sentence) > CAP:
        pad = max(0, (CAP - (end - start)) // 2)
        a = max(0, start - pad)
        b = min(len(sentence), end + pad)
        sentence = ("…" if a > 0 else "") + sentence[a:b] + ("…" if b < len(sentence) else "")
    return sentence


lines = []
with open(base, encoding="utf-8") as handle:
    for raw in handle:
        row = raw.rstrip("\n")
        if not row.strip() or row.lstrip().startswith("#"):
            continue
        fields = [f.strip() for f in row.split("|")]
        if len(fields) != 7:
            lines.append("")
            continue
        page, locale, _rule, text, ctx = fields[:5]
        lang = locale.split("-")[0].lower()
        text = text.replace("¦", "|")
        ctx = ctx.replace("¦", "|")
        if not any(page in pages for pages in by_lang.values()):
            lines.append("page not found: " + page)
            continue
        paras = by_lang.get(lang, {}).get(page, [])
        found = ""
        for paragraph in paras:
            at = paragraph.find(ctx)
            if at < 0:
                continue
            inner = ctx.find(text)
            if inner < 0:
                inner = 0
                length = len(ctx)
            else:
                length = len(text)
            found = sentence_of(paragraph, at + inner, at + inner + length)
            break
        lines.append(found if found else "not found in " + page)

with open(out, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines) + ("\n" if lines else ""))
PY
}

render_language() {
  local base="${DIR}/language_baseline.txt" allow="${DIR}/language_allowlist.txt" sentence_file
  echo "### Language baselines"
  echo ""
  if ! absent "$base" "language baseline"; then
    sentence_file="${TMPD}/sentences.txt"
    : > "$sentence_file"
    if grep -vE '^[[:space:]]*(#|$)' "$base" | awk -F'|' 'NF != 7 { bad = 1 } END { exit bad }'; then
      if grep -vE '^[[:space:]]*(#|$)' "$base" | grep -q .; then sentences_for "$base" "$sentence_file"; fi
    fi
    awk -F'|' -v SENT="$sentence_file" "${AWK_COMMON}"'
      skip() { next }
      BEGIN { while ((getline sline < SENT) > 0) sent[++nsent] = sline }
      NF != 7 { bad("a row is page|lang|rule|match|context|count|reason"); next }
      {
        count = trim($6)
        if (count !~ /^[0-9]+$/ || count + 0 == 0 || trim($7) == "") { bad("a row needs a positive count and a reason"); next }
        rows++; findings += count
        line[rows] = "| " cell(trim($1)) " | " cell(trim($2)) " | " code(trim($4)) " | " cell(sent[rows]) " | " cell(trim($3)) " | " count " | " cell(trim($7)) " |"
      }
      END {
        if (failed) exit 1
        if (rows == 0) { print "**Baseline** (\140'"$base"'\140): no rows (empty baseline)."; exit 0 }
        print "**Baseline** (\140'"$base"'\140): " rows " rows, " findings " findings. The baseline only shrinks; the gate is red for a stale row."
        print ""
        print "| page | language | text | sentence | rule | times | reason |"
        print "|---|---|---|---|---|---|---|"
        for (i = 1; i <= rows; i++) print line[i]
      }
    ' "$base" || exit 1
  fi
  echo ""
  if ! absent "$allow" "language allowlist"; then
    awk "${AWK_COMMON}"'
      skip() { next }
      { word = trim($0); if (word in seen) { bad(word " is listed twice"); next } seen[word] = 1; n++; words[n] = word }
      END {
        if (failed) exit 1
        if (n == 0) { print "**Allowlist** (\140'"$allow"'\140): no words (empty allowlist)."; exit 0 }
        print "**Allowlist** (\140'"$allow"'\140): " n " words. How often each matched is not shown: this report reads the data files only and does not run LanguageTool."
        print ""
        print "| word |"
        print "|---|"
        for (i = 1; i <= n; i++) print "| " code(words[i]) " |"
      }
    ' "$allow" || exit 1
  fi
}

# render_browser: the baseline of the built site, then any further
# browser_gate_*_baseline.txt of the directory (another site the gate opens),
# each under a heading: the file's first comment line, else its name. A site with
# only the main baseline prints just that.
render_browser() {
  local extra heading
  echo "### Browser baselines"
  echo ""
  render_browser_file "${DIR}/browser_gate_baseline.txt" "browser baseline"
  for extra in "${DIR}"/browser_gate_*_baseline.txt; do
    [[ -e "$extra" ]] || continue
    heading="$(sed -n '1s/^#[[:space:]]*//p' "$extra")"
    [[ -n "$heading" ]] || heading="$(basename "$extra")"
    echo ""
    printf '**%s** (\140%s\140)\n' "$heading" "$extra"
    echo ""
    render_browser_file "$extra" "$(basename "$extra")"
  done
}

# render_browser_file <baseline> <what>: the tables of one browser baseline.
render_browser_file() {
  local base="$1"
  absent "$base" "$2" && return 0
  awk -F'|' "${AWK_COMMON}"'
    function sorted(counts, keys,    k, n, i, j, t) {
      n = 0
      for (k in counts) keys[++n] = k
      for (i = 2; i <= n; i++) {
        t = keys[i]
        for (j = i - 1; j >= 1 && (counts[keys[j]] < counts[t] || (counts[keys[j]] == counts[t] && keys[j] > t)); j--) keys[j + 1] = keys[j]
        keys[j + 1] = t
      }
      return n
    }
    skip() { next }
    $1 == "axe" {
      if (NF < 6) { bad("an axe row is axe|variant|page|rule|selector|reason"); next }
      selector = $5
      for (i = 6; i < NF; i++) selector = selector "|" $i
      reason = trim($NF)
      if (reason == "") { bad("a row needs a reason"); next }
      axe++
      axe_line[axe] = "| " cell(trim($2)) " | " cell(trim($3)) " | " cell(trim($4)) " | " code(trim(selector)) " | " cell(reason) " |"
      by_rule[trim($4)]++
      page_axe[trim($3)]++; pages[trim($3)] = 1
      next
    }
    $1 == "cls" {
      if (NF != 5) { bad("a cls row is cls|variant|page|value|reason"); next }
      if (trim($5) == "") { bad("a row needs a reason"); next }
      cls++
      cls_line[cls] = "| " cell(trim($2)) " | " cell(trim($3)) " | " cell(trim($4)) " | " cell(trim($5)) " |"
      page_cls[trim($3)]++; pages[trim($3)] = 1
      next
    }
    $1 == "sideways" {
      if (NF != 7) { bad("a sideways row is sideways|variant|page|viewport|what|px|reason"); next }
      if (trim($7) == "") { bad("a row needs a reason"); next }
      side++
      side_line[side] = "| " cell(trim($2)) " | " cell(trim($3)) " | " cell(trim($4)) " | " cell(trim($5)) " | " cell(trim($6)) " | " cell(trim($7)) " |"
      page_side[trim($3)]++; pages[trim($3)] = 1
      next
    }
    { bad("a row starts with axe, cls or sideways"); next }
    END {
      if (failed) exit 1
      if (axe + cls + side == 0) { print "**Baseline** (\140'"$base"'\140): no rows (empty baseline)."; exit 0 }
      print "**Baseline** (\140'"$base"'\140): " axe + 0 " axe rows, " cls + 0 " CLS rows, " side + 0 " sideways rows. The baseline only shrinks; the gate is red for a new finding and for a stale row."
      print ""
      print "**axe findings** (" axe + 0 ")"
      print ""
      if (axe == 0) print "no rows (empty baseline)"
      else {
        print "| variant | page | rule | selector | reason |"
        print "|---|---|---|---|---|"
        for (i = 1; i <= axe; i++) print axe_line[i]
      }
      print ""
      print "**CLS values** (" cls + 0 ")"
      print ""
      if (cls == 0) print "no rows (empty baseline)"
      else {
        print "| variant | page | value | reason |"
        print "|---|---|---|---|"
        for (i = 1; i <= cls; i++) print cls_line[i]
      }
      print ""
      print "**Sideways overflow** (" side + 0 ")"
      print ""
      if (side == 0) print "no rows (empty baseline)"
      else {
        print "| variant | page | viewport | what | px | reason |"
        print "|---|---|---|---|---|---|"
        for (i = 1; i <= side; i++) print side_line[i]
      }
      print ""
      print "**By rule** (axe rows)"
      print ""
      nr = sorted(by_rule, rkeys)
      if (nr == 0) print "no rows (empty baseline)"
      else {
        print "| rule | rows |"
        print "|---|---|"
        for (i = 1; i <= nr; i++) print "| " cell(rkeys[i]) " | " by_rule[rkeys[i]] " |"
      }
      print ""
      print "**By page**"
      print ""
      for (p in pages) total[p] = page_axe[p] + page_cls[p] + page_side[p]
      np = sorted(total, pkeys)
      print "| page | axe rows | CLS rows | sideways rows |"
      print "|---|---|---|---|"
      for (i = 1; i <= np; i++) print "| " cell(pkeys[i]) " | " page_axe[pkeys[i]] + 0 " | " page_cls[pkeys[i]] + 0 " | " page_side[pkeys[i]] + 0 " |"
    }
  ' "$base" || exit 1
}

render_image() {
  local base="${DIR}/image_size_exceptions.txt"
  echo "### Image baselines"
  echo ""
  absent "$base" "image size baseline" && return 0
  awk -F'|' "${AWK_COMMON}"'
    skip() { next }
    /^limit_bytes=/ { limit = substr($0, 13); next }
    NF != 3 { bad("a row is path|bytes|reason"); next }
    {
      if (trim($2) !~ /^[0-9]+$/ || trim($3) == "") { bad("a row needs whole bytes and a reason"); next }
      rows++
      line[rows] = "| " code(trim($1)) " | " trim($2) " | " cell(trim($3)) " |"
    }
    END {
      if (failed) exit 1
      lim = (limit == "") ? "" : ", limit " limit " bytes"
      if (rows == 0) { print "**Baseline** (\140'"$base"'\140): no rows (empty baseline)" lim "."; exit 0 }
      print "**Baseline** (\140'"$base"'\140): " rows " images over the limit" lim ". The baseline only shrinks."
      print ""
      print "| path | bytes | reason |"
      print "|---|---|---|"
      for (i = 1; i <= rows; i++) print line[i]
    }
  ' "$base" || exit 1
}

"render_${SECTION}" > "$OUT_FILE"
cat "$OUT_FILE"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  { echo ""; cat "$OUT_FILE"; } >> "$GITHUB_STEP_SUMMARY"
fi
COMPLETED=1
