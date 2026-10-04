#!/usr/bin/env bash
# Scripts/test_check_html_dupl.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# Fixture for check_html_dupl.sh — unit 397.
#
# Ported from konenki-website 2026-10-01 (forsgren#1, ladder step 11), adapted
# for forsgren's two targets: the html/template files under
# internal/page/templates (the default, as konenki's default is its authored
# SiteSource/) and the generated page, through Scripts/check_html_dupl_site.sh.
# Konenki's cases come first, with its SiteSource/ read as forsgren's
# templates; forsgren's own cases follow.
#
# A ratchet's essential contract is that duplication above its ceiling fails.
# That contract is tested with a synthetic duplicated fixture so it remains
# testable even when the real templates measure 0.00%, as they do today.
#
# Uses the REAL pinned jscpd (node_modules/.bin, installed by sfl's `npm ci`)
# rather than a fake: the thing under test is largely how this script reads
# jscpd's output. A fake can silently diverge from the actual tool's output
# format.
#
# forsgren's own cases and mutation proofs:
#   - a directory with no .html in it is exit 2 NAMING that nothing was
#     scanned, and mutation proof B shows the reason comes from the
#     zero-sources check: without it the same directory is still exit 2, but
#     blamed on jscpd's output format ("BLIND"), the misleading reason this
#     check replaces;
#   - mutation proof A: the duplicated fixture turns green against a copy of
#     the gate whose ceiling comparison always says "under", so its red comes
#     from that comparison;
#   - the generated-page wrapper: a site built into the temp dir (this runs in
#     pre, before Scripts/build_site.sh writes .build/site) passes at its
#     recorded ceiling, the duplicated fixture is red through it, and an empty
#     site is exit 2 with the zero reason.

CHECK="./Scripts/check_html_dupl.sh"
SITE_CHECK="./Scripts/check_html_dupl_site.sh"
REPO_ROOT="$(pwd)"
ZERO_REASON="scanned 0 .html files under"

TMP="$(mktemp -d)"
COMPLETED=0
finish() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: html-dupl fixture aborted before completing all cases" >&2
    exit 1
  fi
}

trap finish EXIT

failures=0

check() {
  # check <name> <expected-rc> <actual-rc>
  if [[ "$2" == "$3" ]]; then
    echo "  ✅ $1"
  else
    echo "  ❌ $1 — expected exit $2, got $3"
    failures=$((failures + 1))
  fi
}

# check_says <name> <needle> — the last run's output carries needle.
check_says() {
  if grep -Fq -- "$2" <<< "$OUT"; then
    echo "  ✅ $1"
  else
    echo "  ❌ $1 — output does not carry '$2'"
    echo "     got: $OUT"
    failures=$((failures + 1))
  fi
}

run() {
  set +e
  OUT="$("$CHECK" "$@" 2>&1)"
  RC=$?
  set -e
}

run_site() {
  set +e
  OUT="$("$SITE_CHECK" "$@" 2>&1)"
  RC=$?
  set -e
}

# run_copy <gate-copy> <args...> — runs a copy of the gate from Scripts/ of a
# throwaway root that links the repository's node_modules, since the gate
# anchors itself with `cd "$(dirname "$0")/.."` and runs jscpd from there.
run_copy() {
  local copy="$1" root
  shift
  root="${TMP}/root-$(basename "$copy" .sh)"
  mkdir -p "${root}/Scripts"
  cp "$copy" "${root}/Scripts/check_html_dupl.sh"
  chmod +x "${root}/Scripts/check_html_dupl.sh"
  ln -s "${REPO_ROOT}/node_modules" "${root}/node_modules"
  set +e
  OUT="$("${root}/Scripts/check_html_dupl.sh" "$@" 2>&1)"
  RC=$?
  set -e
}

make_duplicate_fixture() {
  local fixture_dir="$1"

  mkdir -p "$fixture_dir"

  cat > "${fixture_dir}/first.html" <<'HTML'
<!doctype html>
<html lang="en">
  <body>
    <main>
      <section>
        <h1>Duplicated fixture</h1>
        <p>This deliberately repeated block exists to prove the duplication gate can fail.</p>
        <p>The fixture needs enough repeated tokens and lines for jscpd to identify the clone.</p>
        <p>It is synthetic and does not establish the production duplication ceiling.</p>
        <p>The same complete block appears in a second HTML file below.</p>
        <p>This line adds enough material for the minimum token threshold used by the gate.</p>
        <p>This line also belongs to the deliberate duplicated test content.</p>
        <p>The ratchet must reject this fixture when its ceiling is zero percent.</p>
        <p>A passing result here would mean the duplication checker cannot detect duplication.</p>
        <p>That would make the production ratchet untrustworthy even if the templates are clean.</p>
        <p>The test therefore exercises the real pinned jscpd rather than a fake implementation.</p>
        <p>Both files intentionally contain this same sequence of markup and textual content.</p>
      </section>
    </main>
  </body>
</html>
HTML

  cp "${fixture_dir}/first.html" "${fixture_dir}/second.html"
}

# make_shared_chrome_site <dir> — two pages that share their chrome (a
# header and a footer well over jscpd's 50-token minimum) and nothing else:
# duplication in the OUTPUT of two pages rendered from one layout, none in any
# one page (forsgren#39, step 1).
make_shared_chrome_site() {
  local dir="$1" n
  mkdir -p "$dir"
  for n in first second; do
    cat > "${dir}/${n}.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>shared chrome</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <header>
    <p class="site-name">shared chrome</p>
  </header>
  <main>
    <h1>The ${n} page</h1>
    <p>Only this paragraph of the ${n} page is its own.</p>
  </main>
  <footer>
    <p>The same footer sentence closes both pages of this synthetic site.</p>
  </footer>
</body>
</html>
HTML
  done
}

# make_inside_duplicate_fixture <dir> — ONE page holding the fixture's block
# twice, so its duplication is within a page, whichever way pages are measured.
make_inside_duplicate_fixture() {
  local dir="$1"
  mkdir -p "$dir"
  {
    sed '/<\/section>/,$d' "${FIXTURE_DIR}/first.html"
    sed -n '/<section>/,/<\/section>/p' "${FIXTURE_DIR}/first.html"
    sed -n '/<\/section>/,$p' "${FIXTURE_DIR}/first.html"
  } > "${dir}/only.html"
}

echo "test_check_html_dupl"

# Tooling absence is exit 2 everywhere below; if jscpd cannot be reached at
# all, say so once rather than reporting several identical failures.
run internal/page/templates 99
if [[ "$RC" -eq 2 ]]; then
  echo "  ⚠️  jscpd unavailable — cannot exercise this gate"
  printf '%s\n' "$OUT" | sed 's/^/     /'
  COMPLETED=1
  exit 1
fi

check "the templates pass under a deliberately loose ceiling" 0 "$RC"

# The default invocation is the production contract: the templates and the
# recorded ceiling. This catches an accidental switch of the default target.
run
check "default template ratchet passes at its recorded ceiling" 0 "$RC"
check_says "the default target is internal/page/templates" "in internal/page/templates"

# The number must be the one the ceiling judges. Reporting duplicated TOKENS
# while gating on duplicated LINES prints a true number that is not the
# relevant one, and a reader cannot tell which they are looking at.
run internal/page/templates 99
if grep -qE 'html duplication [0-9]+\.[0-9]+%' <<< "$OUT"; then
  echo "  ✅ reports the measured template percentage on a passing run"
else
  echo "  ❌ a passing run does not print the number — a ratchet nobody can read is just a threshold"
  echo "     got: $OUT"
  failures=$((failures + 1))
fi

FIXTURE_DIR="${TMP}/duplicated"
make_duplicate_fixture "$FIXTURE_DIR"

run "$FIXTURE_DIR" 0
check "FAILS when deliberate duplication exceeds the ceiling" 1 "$RC"
check_says "the red names the ceiling it exceeded" "EXCEEDS the 0% ceiling"

run does-not-exist 99
check "exits 2 on a missing target dir, never 0" 2 "$RC"

# --- forsgren: nothing scanned is red, and says so ---------------------------
EMPTY_DIR="${TMP}/no-html"
mkdir -p "$EMPTY_DIR"
printf 'body {\n  margin: 0;\n}\n' > "${EMPTY_DIR}/styles.css"

run "$EMPTY_DIR" 99
check "exits 2 on a directory with no .html in it, never 0" 2 "$RC"
check_says "the zero red names that nothing was scanned" "$ZERO_REASON"

# --- forsgren: the generated-page wrapper ----------------------------------
set +e
SITE_PAGE_COUNT_FILE="${TMP}/built.count" FORSGREN_BIN_DIR="${TMP}/bin" \
  ./Scripts/build_site.sh "${TMP}/built" > "${TMP}/built.log" 2>&1
BUILD_RC=$?
set -e
check "the generated site builds" 0 "$BUILD_RC"
[[ "$BUILD_RC" -eq 0 ]] || sed 's/^/     /' "${TMP}/built.log"

run_site "${TMP}/built"
check "the generated page passes at its recorded ceiling" 0 "$RC"
check_says "the generated-page run measured the built site" "in ${TMP}/built"

# forsgren#39, step 1: pages rendered from one layout repeat its chrome, which
# is duplication in the output, not in any page; each page is measured alone.
SHARED_DIR="${TMP}/shared-chrome"
make_shared_chrome_site "$SHARED_DIR"
run_site "$SHARED_DIR"
check "the generated-page wrapper passes two pages that only share their chrome" 0 "$RC"

INSIDE_DIR="${TMP}/inside-duplicate"
make_inside_duplicate_fixture "$INSIDE_DIR"
run_site "$INSIDE_DIR"
check "the generated-page wrapper FAILS on duplication inside one page" 1 "$RC"
check_says "the inside-one-page red names the ceiling it exceeded" "EXCEEDS the 0.00% ceiling"

run_site "$EMPTY_DIR"
check "the generated-page wrapper exits 2 on a site with no .html" 2 "$RC"
check_says "the generated-page zero red names that nothing was scanned" "$ZERO_REASON"

# --- Mutation proof A: the ceiling comparison is what reds the fixture -------
MUTANT_A="${TMP}/mutant_a.sh"
sed 's/print (a > b) ? 1 : 0/print 0/' "$CHECK" > "$MUTANT_A"
if cmp -s "$CHECK" "$MUTANT_A"; then
  echo "  ❌ mutation proof A: the sed no longer matches the ceiling comparison, so this proof proves nothing"
  failures=$((failures + 1))
else
  run_copy "$MUTANT_A" "$FIXTURE_DIR" 0
  check "mutation proof A: the duplicated fixture turns green when the ceiling comparison always says under" 0 "$RC"
fi

# --- Mutation proof B: the zero-sources check is what names the zero red -----
MUTANT_B="${TMP}/mutant_b.sh"
sed 's/\[ "[$]sources" = "0" \]/false/; s/\[ -z "[$]sources" \] ||/false ||/' "$CHECK" > "$MUTANT_B"
if cmp -s "$CHECK" "$MUTANT_B"; then
  echo "  ❌ mutation proof B: the sed no longer matches the zero-sources check, so this proof proves nothing"
  failures=$((failures + 1))
else
  run_copy "$MUTANT_B" "$EMPTY_DIR" 99
  if grep -Fq -- "$ZERO_REASON" <<< "$OUT"; then
    echo "  ❌ mutation proof B: the zero reason is still printed with the zero-sources check removed, so it does not come from that check"
    echo "     got: $OUT"
    failures=$((failures + 1))
  else
    echo "  ✅ mutation proof B: with the zero-sources check removed the empty directory is no longer named as nothing scanned (exit ${RC})"
  fi
fi

COMPLETED=1

if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_html_dupl contract"
  exit 1
fi

echo ""
echo "✅ test_check_html_dupl"
