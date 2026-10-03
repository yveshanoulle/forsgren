#!/usr/bin/env bash
# Scripts/test_check_golden_pages.sh
#
# Self-test for Scripts/check_golden_pages.sh, run before the gate it
# validates (forsgren#12, step 8). The gate runs the page gates (HTMLHint,
# privacy posture, html duplication) on each golden page of
# internal/page/testdata, the pages the Go tests pin byte for byte to what
# forsgren renders: the build renders the page without an installation's
# config or history, so the page WITH data is otherwise never scanned.
#
# Cases, each against a made-up golden directory under one temp root:
#   1. one clean golden page                      -> green, the count named
#   2. a golden page with a form                  -> red, the file and
#                                                    "privacy posture" named
#   3. a golden page with a duplicated id         -> red, the file and
#                                                    "HTMLHint" named
#   4. a golden page that repeats a block         -> red, the file and
#                                                    "html duplication" named
#   5. two clean golden pages that share the      -> green: each page is
#      page chrome                                   scanned alone, as the
#                                                    site's one page is
#   6. a page not named *.golden.html             -> not scanned, green
#   7. a directory with no golden page            -> red: nothing scanned
#   8. a directory that does not exist            -> exit 2
#
# Usage: Scripts/test_check_golden_pages.sh

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "the golden-pages gate self-test"

GATE="Scripts/check_golden_pages.sh"
if [[ ! -x "$GATE" ]]; then
  selftest_abort "${GATE} not found or not executable — the page with data is scanned by no gate"
fi

# page <file> <main>: a made-up page in the page's own chrome, with <main>
# as the body of its main element.
page() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<PAGE
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>forsgren</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <header>
    <p class="site-name">forsgren</p>
  </header>
  <main>
$2
  </main>
  <footer>
    <p>The four DORA metrics, from data GitHub already has.</p>
  </footer>
</body>
</html>
PAGE
}

CLEAN_MAIN='    <h1>Forsgren 0.0.2</h1>
    <section>
      <h2>Acme Shop</h2>
      <dl>
        <dt>Last 7 days</dt>
        <dd>3</dd>
      </dl>
    </section>'

# A block long enough for jscpd's 50-token minimum, twice in one page.
BLOCK='    <section>
      <h2>Acme Shop</h2>
      <dl>
        <dt>Last 7 days</dt><dd>3</dd>
        <dt>Latest deployment</dt><dd>2026-10-01</dd>
        <dt>DORA band</dt><dd>Daily to weekly, 12 production deployments in the last 30 days</dd>
        <dt>Rollbacks</dt><dd>none</dd>
        <dt>Restores</dt><dd>none</dd>
      </dl>
    </section>'

D="${TMP}/clean"
page "${D}/index.clean.golden.html" "$CLEAN_MAIN"
capture "$GATE" "$D"
want_green "one clean golden page" "OK: 1 golden page(s)"

D="${TMP}/form"
page "${D}/index.clean.golden.html" "$CLEAN_MAIN"
page "${D}/index.form.golden.html" "${CLEAN_MAIN}
    <form action=\"/\"><input name=\"q\"></form>"
capture "$GATE" "$D"
want_red "a golden page with a form is red" "index.form.golden.html: privacy posture"

D="${TMP}/htmlhint"
page "${D}/index.ids.golden.html" '    <h1 id="top">Forsgren</h1>
    <p id="top">twice</p>'
capture "$GATE" "$D"
want_red "a golden page with a duplicated id is red" "index.ids.golden.html: HTMLHint"

D="${TMP}/dupl"
page "${D}/index.dupl.golden.html" "${BLOCK}
${BLOCK}"
capture "$GATE" "$D"
want_red "a golden page that repeats a block is red" "index.dupl.golden.html: html duplication"

D="${TMP}/two"
page "${D}/index.one.golden.html" "$CLEAN_MAIN"
page "${D}/index.two.golden.html" "${CLEAN_MAIN}
    <p>No projects configured yet: add them to forsgren.config.yml.</p>"
capture "$GATE" "$D"
want_green "two golden pages that share the chrome, each scanned alone" "OK: 2 golden page(s)"

D="${TMP}/other"
page "${D}/index.clean.golden.html" "$CLEAN_MAIN"
page "${D}/notes.html" "${CLEAN_MAIN}
    <form action=\"/\"><input name=\"q\"></form>"
capture "$GATE" "$D"
want_green "a page not named *.golden.html is not scanned" "OK: 1 golden page(s)"

D="${TMP}/empty"
mkdir -p "$D"
capture "$GATE" "$D"
want_red "a directory with no golden page is red" "no *.golden.html"

capture "$GATE" "${TMP}/missing"
want_rc "a directory that does not exist exits 2" 2

selftest_end "the golden-pages gate does not judge the rendered pages as it should" \
  "the golden-pages gate runs HTMLHint, privacy posture and html duplication on each golden page alone, names the page and the gate that is red, and is red on a directory with no golden page"
