#!/usr/bin/env bash
set -uo pipefail

# check_lint_coverage.sh — did the linters actually OPEN every file that ships?
#
# Unit 394, ported from coachretreat-website; the site-shaped answer to
# another estate repository's admin_template_files.sh.
#
# WHY. Both linters are invoked through globs. A glob that stops matching is
# not an error — it is a smaller job that finishes sooner and reports success.
# Admin learned this the expensive way: templates moved into subdirectories,
# `templates/*.html` is not recursive, and lint coverage silently shrank from
# every template to the one remaining top-level file. Nothing went red.
#
# Admin guards it by pinning an EXPECTED COUNT. This checks the stronger
# property directly: what the linter reports having scanned, against what the
# site actually ships. A count pin notices a file being added; this notices a
# file being MISSED, which is the failure that matters — and it needs no
# number kept in sync by hand.
#
# It is the same defect as unit 390 one level down: there the workflow was
# green about gates its trigger never reached; here a linter is green about a
# file it never opened. Green means "nothing to report", and "I found nothing
# wrong" is indistinguishable from "I looked at nothing".
#
# Usage: check_lint_coverage.sh [site-dir]  (default: .build/site)
#   HTMLHINT_CMD / STYLELINT_CMD override the binaries (the fixture fakes them).

# House pattern: resolve to the repo root before touching any relative path.
# SITE, node_modules/.bin and the linter globs are all repo-relative, so
# without this the script only works when the caller already happens to be
# standing in the right place.
cd "$(dirname "$0")/.." || exit 1

# Unit 409 step 3: defaults to this repo's site dir so gate_report_order.txt
# can name a bare script path. The argument was a per-repo constant duplicated
# at the call site; a caller may still override it, and the fixture does.
# forsgren (ported 2026-10-01, forsgren#1 ladder step 8): the default is
# .build/site, where Scripts/build_site.sh renders the site. With the Usage
# line above and the gate_htmlhint.sh naming in the --config comment below,
# the only change from another estate repository's copy.
SITE="${1:-.build/site}"

# The JSON counter lives in its own file: it has to read two possible streams
# and report "unreadable" distinctly from "zero", which is more than belongs
# inline in a shell string.
LINT_JSON_COUNT="Scripts/lint_json_count.py"

HTMLHINT_CMD="${HTMLHINT_CMD:-node_modules/.bin/htmlhint}"
# konenki passes --config; so does Scripts/gate_htmlhint.sh, and a check that
# lints under different rules than the gate is measuring a different thing.
# AN ARRAY, not a string. As a string it had to be left unquoted at the call
# site to split into two arguments, and an unquoted expansion also GLOBS — a
# caller whose args contained a `*` would have had it expanded against the
# working directory. `read -ra` splits on whitespace and does not glob, so the
# split stays deliberate and stays here. The seam is unchanged for callers:
# HTMLHINT_ARGS is still a string in the environment, and an empty one still
# means "use the default", exactly as the `:-` did.
read -r -a htmlhint_args <<<"${HTMLHINT_ARGS:---config .htmlhintrc}"
STYLELINT_CMD="${STYLELINT_CMD:-node_modules/.bin/stylelint}"

if [ ! -d "$SITE" ]; then
  echo "lint-coverage: site dir not found: $SITE" >&2
  exit 2
fi

want_html="$(find "$SITE" -type f -name '*.html' | wc -l | tr -d ' ')"
want_css="$(find "$SITE" -type f -name '*.css' | wc -l | tr -d ' ')"

# A site with no files to lint is a broken invocation, not a clean one.
if [ "$want_html" -eq 0 ] && [ "$want_css" -eq 0 ]; then
  echo "lint-coverage: no .html or .css found under ${SITE} — wrong directory?" >&2
  exit 2
fi

failed=0

# --- HTML. htmlhint prints "Scanned N files" whether or not it found errors.
html_out="$("$HTMLHINT_CMD" "${htmlhint_args[@]}" "${SITE}/**/*.html" 2>&1)"
got_html="$(printf '%s\n' "$html_out" | sed -nE 's/.*Scanned ([0-9]+) file.*/\1/p' | tail -1)"
if [ -z "$got_html" ]; then
  echo "lint-coverage: could not read a scanned-file count from htmlhint — its output format changed, so this check is blind" >&2
  printf '%s\n' "$html_out" >&2
  failed=1
elif [ "$got_html" -ne "$want_html" ]; then
  echo "lint-coverage: htmlhint scanned ${got_html} file(s), ${SITE} ships ${want_html}" >&2
  find "$SITE" -type f -name '*.html' | sort | sed 's/^/  ships: /' >&2
  failed=1
else
  echo "OK   html  ${got_html}/${want_html} scanned"
fi

# --- CSS. stylelint has no count line; its JSON formatter names every file
# it opened, which is a stronger answer than a count anyway.
# BOTH streams are captured, and whichever parses as JSON is used.
# stylelint writes its --formatter json output to STDERR, not stdout —
# measured 2026-08-22: stdout was empty while stderr held the array. Reading
# one stream made this check report a coverage gap that did not exist, and
# discarding stderr made "stylelint failed" and "stylelint opened nothing"
# arrive as the same 0. A number whose cause is unknown is worse than none.
css_out_f="$(mktemp)"
css_err="$(mktemp)"
"$STYLELINT_CMD" "${SITE}/**/*.css" --formatter json >"$css_out_f" 2>"$css_err"
css_rc=$?
got_css="$(python3 "$LINT_JSON_COUNT" "$css_out_f" "$css_err" 2>/dev/null)"
css_json="$(cat "$css_out_f")"
rm -f "$css_out_f"
if [ -z "$got_css" ]; then
  echo "lint-coverage: stylelint produced no readable JSON (exit ${css_rc}) — BLIND, not clean" >&2
  echo "  stylelint stderr:" >&2
  sed 's/^/    /' "$css_err" >&2
  echo "  stylelint stdout:" >&2
  printf '%s\n' "${css_json:-(empty)}" | sed 's/^/    /' >&2
  rm -f "$css_err"
  failed=1
elif [ "$got_css" -ne "$want_css" ]; then
  rm -f "$css_err"
  echo "lint-coverage: stylelint opened ${got_css} file(s), ${SITE} ships ${want_css}" >&2
  find "$SITE" -type f -name '*.css' | sort | sed 's/^/  ships: /' >&2
  failed=1
else
  rm -f "$css_err"
  echo "OK   css   ${got_css}/${want_css} opened"
fi

if [ "$failed" -ne 0 ]; then
  echo "lint-coverage: a linter did not open every file this site ships" >&2
  exit 1
fi

echo "OK: lint coverage (html ${want_html}, css ${want_css} — every shipped file opened)"
