#!/usr/bin/env bash
# Scripts/test_gate_browser_fixture.sh (forsgren#226). Not canon: forsgren only.
#
# Self-test for Scripts/gate_browser_fixture.sh, run in PRE before the gate it
# validates. The real Chrome and the real axe-core, never a fake: each case is a
# fixture site served on 127.0.0.1 and run through the gate. The engine's own
# cases (every check, the baseline, the exceptions, the variants) are
# Scripts/test_gate_browser.sh's; these are about the data site:
#   1. a clean data site                              -> green, the data run named
#   2. a finding only on a page of the data site      -> red, naming that page
#   3. the same finding in the data baseline          -> green, a WARN
#   4. a data baseline row that matches nothing       -> red, stale
#   5. a missing baseline file                        -> exit 2
#   6. a site directory that does not exist           -> exit 2
#   7. no site given: the gate builds the fixture site itself and opens its
#      History page (a chart)                         -> green
#   8. a fixture site that cannot be built            -> exit 2, naming it
# Mutation proofs (each fixture is red BECAUSE of the line mutated):
#   H. the engine not run on the data site: case 2 turns green;
#   I. the engine's status dropped: case 2 exits 0 with its FAIL line.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

REPO_ROOT="$(pwd)"
GATE="${REPO_ROOT}/Scripts/gate_browser_fixture.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "browser gate (fixture site) self-test"

for need in "$GATE" "${REPO_ROOT}/Scripts/browser_gate.mjs" "${REPO_ROOT}/node_modules/puppeteer-core" "${REPO_ROOT}/node_modules/axe-core"; do
  if [[ ! -e "$need" ]]; then
    selftest_abort "browser gate (fixture site) self-test: ${need} is missing"
  fi
done

# page <body-extra>: a clean page, one part added.
page() {
  cat <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>fixture</title>
<link rel="icon" href="data:,">
<link rel="stylesheet" href="/styles.css">
</head>
<body>
<main>
<h1>Fixture</h1>
<p>Plain text.</p>
$1
</main>
</body>
</html>
HTML
}

# make_site <name> <history body>: a data site with "/" and "/history.html",
# a manifest of both, an empty exceptions file and baseline, one variant.
make_site() {
  local dir="${TMP}/$1"
  mkdir -p "$dir/site"
  page '' > "$dir/site/index.html"
  page "$2" > "$dir/site/history.html"
  printf 'body { color: #111; background: #fff; }\n' > "$dir/site/styles.css"
  printf '{"requiredPages": ["/", "/history.html"]}\n' > "$dir/manifest.json"
  : > "$dir/exceptions.txt"
  : > "$dir/baseline.txt"
  printf 'light|scheme:light\n' > "$dir/variants.txt"
}

# run_gate <name> [gate]: the gate on the site of <name>, with its files.
run_gate() {
  capture "${2:-$GATE}" "${TMP}/$1/site" "${TMP}/$1/manifest.json" "${TMP}/$1/exceptions.txt" "${TMP}/$1/baseline.txt" "${TMP}/$1/variants.txt"
}

REASON="fixture, shrink-only"
make_site clean ''
make_site pale '<p id="t" style="color:#cccccc">pale chart legend</p>'

run_gate clean
want_green "1: a clean data site" "OK: browser gate: 2 pages x 1 variants (light)"
want_said "1b: the output names the data run" "the site rendered from fixture data"

run_gate pale
want_red "2: a finding only on a page of the data site" "FAIL: light /history.html: axe color-contrast (serious): #t (new, not in the baseline)"
want_said "2b: the output names the data run" "the site rendered from fixture data"

printf 'axe|light|/history.html|color-contrast|#t|%s\n' "$REASON" > "${TMP}/pale/baseline.txt"
run_gate pale
want_green "3: the same finding in the data baseline" "WARN: baselined axe color-contrast (serious): light /history.html: #t"

printf 'axe|light|/history.html|color-contrast|#t|%s\naxe|light|/history.html|color-contrast|#gone|%s\n' "$REASON" "$REASON" > "${TMP}/pale/baseline.txt"
run_gate pale
want_red "4: a data baseline row that matches nothing" "FAIL: stale baseline row: axe|light|/history.html|color-contrast|#gone"
: > "${TMP}/pale/baseline.txt"

rm -f "${TMP}/clean/baseline.txt"
run_gate clean
want_exit "5: a missing baseline file" 2 "baseline file not found"
: > "${TMP}/clean/baseline.txt"

capture "$GATE" "${TMP}/nowhere" "${TMP}/clean/manifest.json" "${TMP}/clean/exceptions.txt" "${TMP}/clean/baseline.txt" "${TMP}/clean/variants.txt"
want_exit "6: a site directory that does not exist" 2 "site dir not found"

# 7: the default site is the fixture site; only "/" and "/history.html" are asked for.
capture "$GATE" "" "${TMP}/clean/manifest.json" "${TMP}/clean/exceptions.txt" "${TMP}/clean/baseline.txt" "${TMP}/clean/variants.txt"
want_green "7: the gate builds the fixture site and its History page passes" "OK: browser gate: 2 pages x 1 variants (light)"

FORSGREN_FIXTURE_DIR="${TMP}/nowhere" capture "$GATE" "" "${TMP}/clean/manifest.json" "${TMP}/clean/exceptions.txt" "${TMP}/clean/baseline.txt" "${TMP}/clean/variants.txt"
want_exit "8: a fixture site that cannot be built" 2 "the fixture site could not be built"

# Mutation proofs: a copy of the gate in its own root, with the engine, the
# settings library and node_modules beside it (the gate changes into its root).
GATE_ROOT="${TMP}/gateroot"
mkdir -p "${GATE_ROOT}/Scripts"
cp Scripts/lib_site_settings.sh Scripts/browser_gate.mjs Scripts/site_settings.txt "${GATE_ROOT}/Scripts/"
ln -s "${REPO_ROOT}/node_modules" "${GATE_ROOT}/node_modules"
MUTANT="${GATE_ROOT}/Scripts/gate_browser_fixture.sh"

# H: the engine never runs -> case 2 turns green.
if selftest_mutant "$GATE" "$MUTANT" 's/^node Scripts[/]browser_gate.mjs/true Scripts\/browser_gate.mjs/'; then
  run_gate pale "$MUTANT"
  want_green "mutation proof H: without the engine run case 2 turns green" "the site rendered from fixture data"
fi

# I: the engine's status dropped -> the FAIL line is printed, the exit is 0.
if selftest_mutant "$GATE" "$MUTANT" 's/^  exit "[$]rc"/  COMPLETED=1; exit 0/'; then
  run_gate pale "$MUTANT"
  if [[ "$RC" -eq 0 ]] && grep -qF -- "FAIL: light /history.html: axe color-contrast (serious)" <<< "$OUT"; then
    echo "  ok: mutation proof I: without the engine's status case 2 exits 0 with its FAIL line"
  else
    fail "mutation proof I: the engine's status was still read (exit ${RC}). Output: ${OUT}"
  fi
fi

selftest_end "the browser gate (fixture site) self-test failed" "browser gate (fixture site): every case holds, two mutations seen"
