#!/usr/bin/env bash
# canon: test_report_baselines v1
# Scripts/test_report_baselines.sh (estate issue 300)
#
# Self-test for Scripts/report_baselines.sh, which renders the baseline data
# files as markdown tables for the Quality run page, run in PRE. Each case is a
# fixture data directory.
#   1. language: the rows (page, language, text, rule, times, reason) and the allowlist words
#   2. language: an empty baseline and an empty allowlist             -> "no rows (empty baseline)"
#   3. language: no files                                             -> a line saying so, exit 0
#   4. browser: axe and CLS rows, a selector with a pipe, the counts by rule and by page
#   5. browser: an empty baseline, no file
#   6. image: the rows (path, bytes, reason) and the limit; empty; no file
#   7. an unknown section, and none                                   -> exit 2
#   8. a file that cannot be read, a directory in its place           -> exit 1, never a warning
#   9. a malformed row                                                -> exit 1, no table on stdout
#  10. $GITHUB_STEP_SUMMARY gets the same markdown appended
#  11. no <br> in any output; the real repository's data renders for each section
# Mutation proofs (each fixture loses what its case asserts):
#   A. the counts by rule dropped: case 4 no longer lists the rule counts;
#   B. the reason column dropped: case 1 no longer lists the reason;
#   C. an unreadable file only warns: case 8 no longer exits 1;
#   D. the allowlist section dropped: case 1 no longer lists the words;
#   E. a missing file errors: case 3 no longer says "this site has no";
#   F. an empty file prints a table: case 2 no longer says "no rows (empty baseline)";
#   G. a malformed row is printed: case 9 no longer fails naming the row format;
#   H. an unknown section exits 0: case 7 no longer exits 2;
#   I. a selector with a pipe is not escaped: case 4 no longer has the escaped cell.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
TOOL="${REPO_ROOT}/Scripts/report_baselines.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "report_baselines self-test"

[[ -f "$TOOL" ]] || selftest_abort "report_baselines self-test: ${TOOL} is missing"

TARGET="$TOOL"
# run <section> <dir>
run() { capture "$TARGET" "$1" "$2"; }

# want_lacks <case> <text>: the last capture does NOT say <text>.
want_lacks() {
  if grep -qF -- "$2" <<< "$OUT"; then
    fail "$1: the output still says '$2'. Output: ${OUT}"
  else
    echo "  ok: $1"
  fi
}

D="${TMP}/full"; mkdir -p "$D"
cat > "$D/language_baseline.txt" <<'DATA'
# comment
a.html|nl-BE|RULE_ONE|Foo bar|ctx Foo bar ctx|2|because it is a name
b.html|en-GB|RULE_TWO|Baz|ctx Baz|1|Dutch chrome, intended
DATA
printf '# words\nZorbo\npasskey\n' > "$D/language_allowlist.txt"
cat > "$D/browser_gate_baseline.txt" <<'DATA'
# comment
axe|light|/|color-contrast|.nav-link|reason one
axe|dark|/|color-contrast|a[href|=x]|reason two
axe|light|/b.html|aria-required-parent|ul|reason three
cls|light|/|0.5|reason four
DATA
printf '# comment\nlimit_bytes=1000\nSite/a.png|2000|logo, shrink-only\n' > "$D/image_size_exceptions.txt"

run language "$D"
want_green "1a: language rows are listed with the text and the rule" "| a.html | nl-BE | \`Foo bar\` | RULE_ONE | 2 | because it is a name |"
want_said "1b: the table header" "| page | language | text | rule | times | reason |"
want_said "1c: the second row" "| b.html | en-GB | \`Baz\` | RULE_TWO | 1 | Dutch chrome, intended |"
want_said "1d: the totals" "2 rows, 3 findings"
want_said "1e: the allowlist words" "| \`Zorbo\` |"
want_said "1f: the allowlist says it does not count matches" "does not run LanguageTool"

E="${TMP}/empty"; mkdir -p "$E"
: > "$E/language_baseline.txt"; : > "$E/language_allowlist.txt"; : > "$E/browser_gate_baseline.txt"
printf 'limit_bytes=1000\n' > "$E/image_size_exceptions.txt"
run language "$E"
want_said "2a: an empty language baseline" "no rows (empty baseline)"
want_said "2b: an empty allowlist" "no words (empty allowlist)"

N="${TMP}/none"; mkdir -p "$N"
run language "$N"
want_green "3a: no language files, a line saying so" "this site has no \`${N}/language_baseline.txt\`"
want_said "3b: the section heading is still there" "### Language baselines"

run browser "$D"
want_green "4a: an axe row" "| light | / | color-contrast | \`.nav-link\` | reason one |"
want_said "4b: a selector with a pipe is escaped" "| dark | / | color-contrast | \`a[href\\|=x]\` | reason two |"
want_said "4c: a CLS row" "| light | / | 0.5 | reason four |"
want_said "4d: the count by rule" "| color-contrast | 2 |"
want_said "4e: the count by page" "| / | 2 | 1 |"
want_said "4f: the second page" "| /b.html | 1 | 0 |"
run browser "$E"
want_green "5a: an empty browser baseline" "no rows (empty baseline)"
run browser "$N"
want_green "5b: no browser file" "this site has no \`${N}/browser_gate_baseline.txt\`"

run image "$D"
want_green "6a: an image row" "| \`Site/a.png\` | 2000 | logo, shrink-only |"
want_said "6b: the limit" "limit 1000 bytes"
run image "$E"
want_green "6c: an empty image baseline" "no rows (empty baseline)"
run image "$N"
want_green "6d: no image file" "this site has no \`${N}/image_size_exceptions.txt\`"

run bogus "$D"
want_exit "7a: an unknown section" 2 "unknown section 'bogus'"
capture "$TARGET"
want_exit "7b: no section" 2 "unknown section ''"

U="${TMP}/unreadable"; mkdir -p "$U"
printf 'x|y|z|w|v|1|r\n' > "$U/language_baseline.txt"; chmod 000 "$U/language_baseline.txt"
run language "$U"
want_exit "8a: a file that cannot be read fails" 1 "cannot read ${U}/language_baseline.txt"
V="${TMP}/dirfile"; mkdir -p "$V/browser_gate_baseline.txt"
run browser "$V"
want_exit "8b: a directory in its place fails" 1 "cannot read ${V}/browser_gate_baseline.txt"

M="${TMP}/malformed"; mkdir -p "$M"
printf 'only|three|fields\n' > "$M/language_baseline.txt"
run language "$M"
want_exit "9a: a malformed language row" 1 "line 1: a row is page|lang|rule|match|context|count|reason"
want_lacks "9b: no table on a malformed file" "| page |"
printf 'zzz|x\n' > "$M/browser_gate_baseline.txt"
run browser "$M"
want_exit "9c: a browser row of an unknown kind" 1 "a row starts with axe or cls"
printf 'a.png|many|why\n' > "$M/image_size_exceptions.txt"
run image "$M"
want_exit "9d: an image row with bad bytes" 1 "a row needs whole bytes and a reason"

S="${TMP}/summary.md"
GITHUB_STEP_SUMMARY="$S" capture "$TARGET" image "$D"
if [[ "$RC" -eq 0 ]] && grep -qF '| 2000 | logo, shrink-only |' "$S"; then
  echo "  ok: 10: the same markdown is appended to GITHUB_STEP_SUMMARY"
else
  fail "10: GITHUB_STEP_SUMMARY does not carry the table (exit ${RC}). File: $(cat "$S" 2>/dev/null || echo none)"
fi

for section in language browser image; do
  capture "$TARGET" "$section" "Scripts"
  want_green "11a: the real repository's ${section} data renders" "### "
  want_lacks "11b: no <br> in the real ${section} output" "<br>"
done
run browser "$D"
want_lacks "11c: no <br> in a table" "<br>"

# Mutation proofs: a copy of the tool runs on the same fixtures; it lives in
# Scripts/ (it cd-s to its own parent), so it is removed again.
MUT="${REPO_ROOT}/Scripts/.report_baselines_mutant.$$.sh"
trap 'rm -f "$MUT"; chmod 600 "$U/language_baseline.txt" 2>/dev/null || true; selftest_cleanup' EXIT

if selftest_mutant "$TOOL" "$MUT" 's/nr = sorted(by_rule, rkeys)/nr = 0/'; then
  TARGET="$MUT"; run browser "$D"
  want_lacks "mutation proof A: without the counts by rule the rule count is gone (case 4d)" "| color-contrast | 2 |"
fi
if selftest_mutant "$TOOL" "$MUT" 's/ " | " cell(trim(.7)) " |"//'; then
  TARGET="$MUT"; run language "$D"
  want_lacks "mutation proof B: without the reason column the reason is gone (case 1a)" "because it is a name"
fi
if selftest_mutant "$TOOL" "$MUT" '/cannot read/s/exit 1; }/return 0; }/'; then
  TARGET="$MUT"; run language "$U"
  if [[ "$RC" -eq 1 ]]; then
    fail "mutation proof C: a tool that only warns about an unreadable file still exits 1 (case 8a would not be red). Output: ${OUT}"
  else
    echo "  ok: mutation proof C: an unreadable file that only warns exits ${RC}, not 1 (case 8a would be red)"
  fi
fi
if selftest_mutant "$TOOL" "$MUT" 's/if ! absent ".allow" "language allowlist"; then/if false; then/'; then
  TARGET="$MUT"; run language "$D"
  want_lacks "mutation proof D: without the allowlist section the words are gone (case 1e)" "| \`Zorbo\` |"
fi

if selftest_mutant "$TOOL" "$MUT" '/printf .*this site has no/s/.*/    echo "missing" >\&2; exit 1/'; then
  TARGET="$MUT"; run language "$N"
  want_lacks "mutation proof E: a missing file that errors no longer says the site has none (case 3a)" "this site has no"
fi
if selftest_mutant "$TOOL" "$MUT" 's/if (rows == 0) {/if (0) {/'; then
  TARGET="$MUT"; run language "$E"
  want_lacks "mutation proof F: an empty file that prints a table no longer says it is empty (case 2a)" "no rows (empty baseline)"
fi
if selftest_mutant "$TOOL" "$MUT" '/NF != 7 { bad("a row is page/d'; then
  TARGET="$MUT"; run language "$M"
  want_lacks "mutation proof G: a malformed row that is printed no longer fails naming the row format (case 9a)" "a row is page|lang|rule|match|context|count|reason"
fi
if selftest_mutant "$TOOL" "$MUT" 's/^    exit 2$/    COMPLETED=1; exit 0/'; then
  TARGET="$MUT"; run bogus "$D"
  if [[ "$RC" -eq 2 ]]; then
    fail "mutation proof H: the tool with an unknown-section exit of 0 still exits 2. Output: ${OUT}"
  else
    echo "  ok: mutation proof H: an unknown section exits ${RC}, not 2 (case 7a would be red)"
  fi
fi
if selftest_mutant "$TOOL" "$MUT" 's/"\\\\|", v/"|", v/'; then
  TARGET="$MUT"; run browser "$D"
  want_lacks "mutation proof I: an unescaped pipe in a selector no longer has the escaped cell (case 4b)" "a[href\\|=x]"
fi

rm -f "$MUT"
selftest_end "the report_baselines self-test failed" "report_baselines: every case holds, nine mutations seen"
