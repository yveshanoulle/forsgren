#!/usr/bin/env bash
# canon: test_gate_language v2
# Scripts/test_gate_language.sh (estate issue 300)
#
# Self-test for Scripts/gate_language.sh, the LanguageTool gate, run in PRE
# before the gate it validates. LanguageTool itself is a STUB here (a python
# script that flags the words of a rules file), so the unit test needs no Java
# and no dictionary; the real tool is exercised by the gate on the real site.
# Each case is a fixture site, allowlist, baseline and settings file.
#   1. no match at all                                  -> green, the OK line
#   2. an allowlisted word                              -> green, counted
#   3. a baselined row                                  -> green, counted
#   4. a new finding, mode enforce                      -> red, names the finding
#   5. a new finding, mode warn                         -> exit 0, a warning, the OK line says warn-only
#   6. a baseline row whose finding is gone             -> red, stale; in warn only a warning
#   7. a finding twice, the row records one             -> red, one new; the row records two, one left: lower the row
#   8. the same finding at other offsets                -> green, the baseline does not churn
#   9. an emoji before the match (UTF-16 offsets)       -> green, the right text is matched
#  10. LanguageTool missing                             -> exit 2, a red line saying what is missing
#  11. Java missing                                     -> exit 2, a red line saying what is missing
#  12. LanguageTool of another version than the pin     -> red in enforce, a warning in warn
#  13. text in an element with its own lang             -> checked with that language
#  14. a language with no locale setting, a page with no lang -> exit 2
#  15. a missing allowlist, a missing baseline, a malformed baseline -> exit 2
#  16. a failing LanguageTool                           -> exit 2, never a pass
#  17. script, style and head text is not checked; alt text is
#  18. a match on a page marker line is dropped
#  19. LanguageTool runs without network, never with a remote option
#  22. --text mode (v2): the extracted text of the pages, per language, with no
#      LanguageTool, Java, allowlist or baseline; the optional page roots key
#  20. the language settings file: an invalid mode, locale list or version, a
#      missing, unknown or repeated key, a malformed line, no file -> exit 2 each
# Mutation proofs (each fixture is red BECAUSE of the line mutated):
#   A. a new finding not collected: case 4 turns green;
#   B. a stale row not collected: case 6 turns green;
#   C. a missing LanguageTool waived: case 10 turns green;
#   D. the mode ignored (always enforce): case 5 turns red;
#   E. the allowlist ignored: case 2 turns red, as a new finding;
#   F. the version pin not compared: case 12 turns green;
#   G. the network sandbox removed: case 19 sees an open network;
#   H. a page marker match kept: case 18 turns red;
#   I. --text mode not recognised: case 22a no longer exits 0.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
GATE="${REPO_ROOT}/Scripts/gate_language.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "language gate self-test"

[[ -f "$GATE" ]] || selftest_abort "language gate self-test: ${GATE} is missing"

# The stub LanguageTool. --version prints STUB_VERSION (default 6.8). A run
# reads its text file and flags every occurrence of each word of STUB_RULES
# (locale|rule|issue type|word|message) for the locale of -l, with UTF-16
# offsets like the real tool. It logs its arguments and whether a UDP packet
# can leave the machine (STUB_LOG), and exits STUB_RC when that is set.
mkdir -p "${TMP}/bin" "${TMP}/jh/bin"
cat > "${TMP}/bin/languagetool" <<'PY'
#!/usr/bin/env python3
import json, os, socket, sys
args = sys.argv[1:]
if args == ["--version"]:
    print("LanguageTool version %s (stub)" % os.environ.get("STUB_VERSION", "6.8"))
    sys.exit(0)
log = os.environ.get("STUB_LOG")
if log:
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.sendto(b"x", ("127.0.0.1", 9))
        net = "open"
    except OSError:
        net = "blocked"
    with open(log, "a") as handle:
        handle.write("args: %s\nnetwork=%s\n" % (" ".join(args), net))
if os.environ.get("STUB_RC"):
    sys.stderr.write("stub failure\n")
    sys.exit(int(os.environ["STUB_RC"]))
locale = args[args.index("-l") + 1]
text = open(args[-1], encoding="utf-8").read()
matches = []
for line in open(os.environ["STUB_RULES"], encoding="utf-8").read().splitlines():
    if not line.strip():
        continue
    loc, rule, issue, word, message = line.split("|")
    if loc != locale:
        continue
    at = text.find(word)
    while at != -1:
        matches.append({
            "message": message,
            "offset": len(text[:at].encode("utf-16-le")) // 2,
            "length": len(word.encode("utf-16-le")) // 2,
            "rule": {"id": rule, "issueType": issue},
        })
        at = text.find(word, at + len(word))
print(json.dumps({"software": {"name": "LanguageTool", "version": os.environ.get("STUB_VERSION", "6.8")}, "matches": matches}))
PY
chmod +x "${TMP}/bin/languagetool"
printf '#!/bin/sh\nexit 0\n' > "${TMP}/jh/bin/java"
chmod +x "${TMP}/jh/bin/java"

SPELL_NL='nl-BE|MORFOLOGIK_RULE_NL_NL|misspelling'
ROW_ZORBO='index.html|nl-BE|MORFOLOGIK_RULE_NL_NL|Zorbo|Dit is Zorbo nu.'

# mk <name> [nl body]: a fixture with a Dutch and an English page, empty
# allowlist, baseline and rules, and enforce settings.
mk() {
  local d="${TMP}/$1"
  mkdir -p "$d/site"
  printf '<!doctype html>\n<html lang="nl">\n<head><title>Titel</title><style>.x{}</style></head>\n<body>\n<p>%s</p>\n</body>\n</html>\n' \
    "${2-Dit is Zorbo nu.}" > "$d/site/index.html"
  printf '<!doctype html>\n<html lang="en">\n<head><title>Title</title></head>\n<body>\n<p>This is plain text.</p>\n</body>\n</html>\n' \
    > "$d/site/privacy.html"
  : > "$d/allow.txt"
  : > "$d/base.txt"
  : > "$d/rules"
  printf '%s\n' 'language_mode=enforce' 'language_locales=nl:nl-BE,en:en-GB' \
    'language_tool_version=6.8' > "$d/settings.txt"
}

rule() { printf '%s\n' "$2" >> "${TMP}/$1/rules"; }
base() { printf '%s\n' "$2" >> "${TMP}/$1/base.txt"; }
allow() { printf '%s\n' "$2" >> "${TMP}/$1/allow.txt"; }
mode() { sed -i.bak "s/^language_mode=.*/language_mode=$2/" "${TMP}/$1/settings.txt"; rm -f "${TMP}/$1/settings.txt.bak"; }

# run_gate <name> [VAR=value ...]: the gate on the fixture, stub tool, fixture Java.
run_gate() {
  local d="${TMP}/$1"
  shift
  capture env GATE_LANGUAGE_TOOL="${TMP}/bin/languagetool" JAVA_HOME="${TMP}/jh" \
    STUB_RULES="$d/rules" STUB_LOG="$d/log" "$@" \
    "$TARGET" "$d/site" "$d/allow.txt" "$d/base.txt" "$d/settings.txt"
}
TARGET="$GATE"

mk clean
run_gate clean
want_green "1: no match at all" "OK: language gate: 2 pages, 2 languages (nl-BE, en-GB), 0 matches, 0 allowlisted, 0 baselined, 0 new, LanguageTool 6.8, mode enforce"

mk allowed; rule allowed "${SPELL_NL}|Zorbo|Spelfout"; allow allowed Zorbo
run_gate allowed
want_green "2: an allowlisted word" "1 matches, 1 allowlisted, 0 baselined, 0 new"

mk based; rule based "${SPELL_NL}|Zorbo|Spelfout"; base based "${ROW_ZORBO}|1|brand name"
run_gate based
want_green "3: a baselined row" "1 matches, 0 allowlisted, 1 baselined, 0 new"

mk fresh; rule fresh "${SPELL_NL}|Zorbo|Spelfout"
run_gate fresh
want_red "4: a new finding in enforce" "new finding: index.html [nl-BE] MORFOLOGIK_RULE_NL_NL: \"Zorbo\" in \"Dit is Zorbo nu.\" (Spelfout)"
want_rc "4b: the exit status is 1" 1

mk warned; rule warned "${SPELL_NL}|Zorbo|Spelfout"; mode warned warn
run_gate warned
want_green "5a: a new finding in warn exits 0" "warn: new finding: index.html [nl-BE] MORFOLOGIK_RULE_NL_NL: \"Zorbo\" in \"Dit is Zorbo nu.\""
want_said "5b: the OK line says warn-only" "OK: language gate (warn-only): 2 pages, 2 languages (nl-BE, en-GB), 1 matches, 0 allowlisted, 0 baselined, 1 new, LanguageTool 6.8, mode warn"

mk stale; base stale "${ROW_ZORBO}|1|brand name"
run_gate stale
want_red "6a: a baseline row whose finding is gone" "stale baseline row: index.html [nl-BE] MORFOLOGIK_RULE_NL_NL: \"Zorbo\" in \"Dit is Zorbo nu.\" is gone (recorded 1, now 0); remove the row"
mk stalewarn; base stalewarn "${ROW_ZORBO}|1|brand name"; mode stalewarn warn
run_gate stalewarn
want_green "6b: a stale row in warn is a warning" "warn: stale baseline row"

mk twice "Dit is Zorbo nu.</p><p>Dit is Zorbo nu."; rule twice "${SPELL_NL}|Zorbo|Spelfout"; base twice "${ROW_ZORBO}|1|brand name"
run_gate twice
want_red "7a: two findings, the row records one" "new finding: index.html [nl-BE] MORFOLOGIK_RULE_NL_NL: \"Zorbo\""
want_said "7a2: counted as one baselined, one new" "2 matches, 0 allowlisted, 1 baselined, 1 new"
mk once; rule once "${SPELL_NL}|Zorbo|Spelfout"; base once "${ROW_ZORBO}|2|brand name"
run_gate once
want_red "7b: the row records two, one is left" "(recorded 2, now 1); lower the row"

mk moved "A longer opening paragraph before.</p><p>Dit is Zorbo nu."; rule moved "${SPELL_NL}|Zorbo|Spelfout"
base moved 'index.html|nl-BE|MORFOLOGIK_RULE_NL_NL|Zorbo|Dit is Zorbo nu.|1|brand name'
run_gate moved
want_green "8: the same finding at another offset is still baselined" "1 baselined, 0 new"

mk emoji "😀😀</p><p>Dit is Zorbo nu."; rule emoji "${SPELL_NL}|Zorbo|Spelfout"
base emoji 'index.html|nl-BE|MORFOLOGIK_RULE_NL_NL|Zorbo|Dit is Zorbo nu.|1|brand name'
run_gate emoji
want_green "9: an emoji before the match (UTF-16 offsets)" "1 baselined, 0 new"

mk notool
run_gate notool GATE_LANGUAGE_TOOL="${TMP}/absent/languagetool"
want_exit "10: LanguageTool missing" 2 "❌ LanguageTool is missing: ${TMP}/absent/languagetool"

mk nojava
run_gate nojava JAVA_HOME="${TMP}/nojava-home"
want_exit "11: Java missing" 2 "❌ Java is missing: ${TMP}/nojava-home/bin/java"

mk oldver
run_gate oldver STUB_VERSION=6.9
want_red "12a: another LanguageTool version, enforce" "LanguageTool is 6.9, the pinned version is 6.8"
mk oldverwarn; mode oldverwarn warn
run_gate oldverwarn STUB_VERSION=6.9
want_green "12b: another version, warn" "warn: LanguageTool is 6.9, the pinned version is 6.8"

mk spanlang "Dit is <span lang=\"en\">plain Zorbo</span> nu."
rule spanlang 'en-GB|MORFOLOGIK_RULE_EN_GB|misspelling|Zorbo|Spelling mistake'
run_gate spanlang
want_red "13: text in an element with its own lang is checked with that language" "new finding: index.html [en-GB] MORFOLOGIK_RULE_EN_GB: \"Zorbo\""

mk nolocale
sed -i.bak 's/<html lang="en">/<html lang="fr">/' "${TMP}/nolocale/site/privacy.html"
run_gate nolocale
want_exit "14a: a language with no locale setting" 2 "no locale for language 'fr'"
mk nolang
sed -i.bak 's/<html lang="nl">/<html>/' "${TMP}/nolang/site/index.html"
run_gate nolang
want_exit "14b: a page with no lang" 2 "index.html has no lang on its html element"

mk noallow; rm -f "${TMP}/noallow/allow.txt"
run_gate noallow
want_exit "15a: a missing allowlist" 2 "allowlist not found"
mk nobase; rm -f "${TMP}/nobase/base.txt"
run_gate nobase
want_exit "15b: a missing baseline" 2 "baseline not found"
mk noreason; base noreason "${ROW_ZORBO}|1|"
run_gate noreason
want_exit "15c: a baseline row without a reason" 2 "base.txt line 1: a row is page|lang|rule|match|context|count|reason, with a reason"
mk badcount; base badcount "${ROW_ZORBO}|x|brand name"
run_gate badcount
want_exit "15d: a baseline count that is not a number" 2 "count must be a positive whole number"
mk dupkey; base dupkey "${ROW_ZORBO}|1|brand name"; base dupkey "${ROW_ZORBO}|1|again"
run_gate dupkey
want_exit "15e: a baseline row twice" 2 "is listed twice"

mk broken
run_gate broken STUB_RC=3
want_exit "16: a failing LanguageTool is never a pass" 2 "❌ LanguageTool failed (exit 3) for nl-BE"

mk hidden '<script>var Zorbo = 1;</script>Dit is nu.'
sed -i.bak 's#<head><title>Titel</title>#<head><title>Zorbo</title>#' "${TMP}/hidden/site/index.html"
rule hidden "${SPELL_NL}|Zorbo|Spelfout"
run_gate hidden
want_green "17a: script and head text is not checked" "0 matches"
mk alttext '<img src="a.png" alt="Dit is Zorbo nu.">'
rule alttext "${SPELL_NL}|Zorbo|Spelfout"
run_gate alttext
want_red "17b: alt text is checked" "new finding: index.html [nl-BE] MORFOLOGIK_RULE_NL_NL: \"Zorbo\""

mk marker; rule marker "${SPELL_NL}|PAGEMARK|Spelfout"
run_gate marker
want_green "18: a match on a page marker line is dropped" "0 matches"

mk offline
run_gate offline
if grep -qF 'network=blocked' "${TMP}/offline/log" && grep -qF -- '--json' "${TMP}/offline/log" \
  && ! grep -qiF 'remote' "${TMP}/offline/log"; then
  echo "  ok: 19: LanguageTool ran without network, with --json, with no remote option"
else
  fail "19: the stub log does not show a blocked network, --json and no remote option. Log: $(cat "${TMP}/offline/log" 2>/dev/null || echo none)"
fi

mk badmode; mode badmode loud
run_gate badmode
want_exit "20a: an invalid mode" 2 "invalid value for 'language_mode'"
mk badlocales; sed -i.bak 's/^language_locales=.*/language_locales=nl/' "${TMP}/badlocales/settings.txt"
run_gate badlocales
want_exit "20b: an invalid locale list" 2 "invalid value for 'language_locales'"
mk badversion; sed -i.bak 's/^language_tool_version=.*/language_tool_version=six/' "${TMP}/badversion/settings.txt"
run_gate badversion
want_exit "20c: an invalid version" 2 "invalid value for 'language_tool_version'"
mk nokey; sed -i.bak '/^language_tool_version=/d' "${TMP}/nokey/settings.txt"
run_gate nokey
want_exit "20d: a missing key" 2 "required key 'language_tool_version' is missing"
mk unknownkey; echo 'colour=blue' >> "${TMP}/unknownkey/settings.txt"
run_gate unknownkey
want_exit "20e: an unknown key" 2 "unknown key 'colour'"
mk dupsetting; echo 'language_mode=warn' >> "${TMP}/dupsetting/settings.txt"
run_gate dupsetting
want_exit "20f: a repeated key" 2 "duplicate key 'language_mode'"
mk malformedsetting; echo 'language mode = warn' >> "${TMP}/malformedsetting/settings.txt"
run_gate malformedsetting
want_exit "20g: a malformed line" 2 "malformed line 4"
mk nosettings; rm -f "${TMP}/nosettings/settings.txt"
run_gate nosettings
want_exit "20h: no settings file" 2 "settings file not found"

# 22. --text mode: the extractor the baseline report reuses.
mk textmode "Dit is Zorbo nu.</p><p>Tweede zin."
mkdir -p "${TMP}/textmode/out"
capture env GATE_LANGUAGE_TOOL="${TMP}/absent/languagetool" JAVA_HOME="${TMP}/nojava-home" \
  "$TARGET" --text "${TMP}/textmode/out" "${TMP}/textmode/site" "${TMP}/absent-allow" "${TMP}/absent-base" "${TMP}/textmode/settings.txt"
want_green "22a: --text needs no LanguageTool, Java, allowlist or baseline"
if grep -qxF 'PAGEMARK index.html' "${TMP}/textmode/out/text.nl.txt" && grep -qxF 'Dit is Zorbo nu.' "${TMP}/textmode/out/text.nl.txt" \
  && grep -qxF 'Tweede zin.' "${TMP}/textmode/out/text.nl.txt" && grep -qxF 'PAGEMARK privacy.html' "${TMP}/textmode/out/text.en.txt"; then
  echo "  ok: 22b: --text writes a text file per language, a PAGEMARK line before each page"
else
  fail "22b: the --text output is wrong: $(printf '%s ' "${TMP}"/textmode/out/*)"
fi
capture env "$TARGET" --text "${TMP}/nolocale/out" "${TMP}/nolocale/site" "${TMP}/nolocale/allow.txt" "${TMP}/nolocale/base.txt" "${TMP}/nolocale/settings.txt"
want_exit "22c: --text refuses a language with no locale as the gate does" 2 "no locale for language 'fr'"
capture env "$TARGET" --text
want_exit "22d: --text without a directory" 2 "--text needs an output directory"
mk roots; echo 'language_page_roots=site,starter=other/dir' >> "${TMP}/roots/settings.txt"
run_gate roots
want_green "22e: the optional language_page_roots key is accepted" "OK:"
mk badroots; echo 'language_page_roots=a b' >> "${TMP}/badroots/settings.txt"
run_gate badroots
want_exit "22f: a malformed language_page_roots line" 2 "malformed line 4"
mk badroots2; echo 'language_page_roots=/x//y,' >> "${TMP}/badroots2/settings.txt"
run_gate badroots2
want_exit "22g: an invalid language_page_roots value" 2 "invalid value for 'language_page_roots'"

# Mutation proofs: a copy of the gate runs on the same fixtures. The copy lives
# in Scripts/ (it cd-s to its own parent), so it is removed again.
MUT="${REPO_ROOT}/Scripts/.language_mutant.$$.sh"
trap 'rm -f "$MUT"; selftest_cleanup' EXIT

# A: a new finding is not collected -> the new-finding fixture turns green.
if selftest_mutant "$GATE" "$MUT" 's/new\.append(/pass  # (/'; then
  TARGET="$MUT"; run_gate fresh
  want_green "mutation proof A: a new finding not collected turns case 4 green" "0 new"
fi

# B: a stale row is not collected -> the stale fixture turns green.
if selftest_mutant "$GATE" "$MUT" 's/stale\.append(/pass  # (/'; then
  TARGET="$MUT"; run_gate stale
  want_green "mutation proof B: a stale row not collected turns case 6a green" "OK:"
fi

# C: a missing tool is a waiver -> the missing-tool fixture turns green.
if selftest_mutant "$GATE" "$MUT" '/^tool_fail()/s/exit 2; }/COMPLETED=1; exit 0; }/'; then
  TARGET="$MUT"; run_gate notool GATE_LANGUAGE_TOOL="${TMP}/absent/languagetool"
  want_green "mutation proof C: a missing LanguageTool waived turns case 10 green"
fi

# D: the mode is ignored -> the warn fixture turns red.
if selftest_mutant "$GATE" "$MUT" 's/enforcing = (mode == "enforce")/enforcing = True/'; then
  TARGET="$MUT"; run_gate warned
  want_red "mutation proof D: the mode ignored turns case 5 red" "new finding"
fi

# E: the allowlist is ignored -> the allowlisted fixture turns red.
if selftest_mutant "$GATE" "$MUT" 's/if issue == "misspelling" and allowlisted(/if False and allowlisted(/'; then
  TARGET="$MUT"; run_gate allowed
  want_red "mutation proof E: the allowlist ignored turns case 2 red" "new finding"
fi

# F: the version pin is not compared -> the version fixture turns green.
if selftest_mutant "$GATE" "$MUT" 's/if \[\[ ".LT_VERSION" != ".PINNED_VERSION" \]\]; then/if false; then/'; then
  TARGET="$MUT"; run_gate oldver STUB_VERSION=6.9
  want_green "mutation proof F: the version pin not compared turns case 12a green" "OK:"
fi

# G: the network sandbox is removed -> the network is open for LanguageTool.
if selftest_mutant "$GATE" "$MUT" 's/sandbox-exec -p ".SANDBOX_PROFILE" //'; then
  TARGET="$MUT"; rm -f "${TMP}/offline/log"; run_gate offline
  if grep -qF 'network=open' "${TMP}/offline/log" 2>/dev/null; then
    echo "  ok: mutation proof G: without the sandbox the network is open (case 19 would be red)"
  else
    fail "mutation proof G: the gate without its sandbox still shows a blocked network. Log: $(cat "${TMP}/offline/log" 2>/dev/null || echo none). Output: ${OUT}"
  fi
fi

# H: a page marker match is kept -> the marker fixture turns red.
if selftest_mutant "$GATE" "$MUT" 's/if marker_hit:/if False:/'; then
  TARGET="$MUT"; run_gate marker
  want_red "mutation proof H: a marker match kept turns case 18 red" "new finding"
fi

# I: --text mode is not recognised -> the text-only run fails as a normal run.
if selftest_mutant "$GATE" "$MUT" 's/^if \[\[ -n ".TEXT_OUT" \]\]; then$/if false; then/'; then
  TARGET="$MUT"
  capture env GATE_LANGUAGE_TOOL="${TMP}/absent/languagetool" JAVA_HOME="${TMP}/nojava-home" \
    "$TARGET" --text "${TMP}/textmode/out2" "${TMP}/textmode/site" "${TMP}/absent-allow" "${TMP}/absent-base" "${TMP}/textmode/settings.txt"
  if [[ "$RC" -eq 0 ]]; then
    fail "mutation proof I: without the --text branch the run still exits 0. Output: ${OUT}"
  else
    echo "  ok: mutation proof I: without the --text branch the run exits ${RC} (case 22a would be red)"
  fi
fi

rm -f "$MUT"
selftest_end "the language gate self-test failed" "language gate: every case holds, nine mutations seen"
