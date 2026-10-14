#!/usr/bin/env bash
# Scripts/test_build_starter_page.sh
#
# Self-test for Scripts/build_starter_page.sh (forsgren#132), run before the
# gate row that builds the starter page. Forsgren's own.
#
# Each case asserts the exit code AND the reason:
#   1. the real README                                  -> green, index.html
#      with the page's heading and an absolute link
#   2. the same build                                   -> CNAME holds the domain
#   3. a README with a construct the renderer refuses   -> red, says why, and
#      writes nothing into the output directory
#   4. a README that does not exist                     -> red, names it
#   5. an output directory that is a regular file       -> red, says so
#   6. MUTATION PROOF: the script with its CNAME line removed still builds
#      the page but writes no CNAME: that line is what writes it

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="./Scripts/build_starter_page.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "build-starter-page self-test"

[[ -x "$GATE" ]] || selftest_abort "the build script ${GATE} is missing (or not executable): nothing builds the starter page"

# cname_is_domain <dir> — the dir's CNAME holds exactly the domain.
cname_is_domain() {
  [[ "$(cat "$1/CNAME" 2>/dev/null || true)" == "forsgren.be" ]]
}

capture "$GATE" "${TMP}/happy"
want_green "the real README builds" "index.html and CNAME (forsgren.be)"
if grep -qF '<h1 id="forsgren">forsgren</h1>' "${TMP}/happy/index.html" 2>/dev/null \
  && grep -qF 'href="https://github.com/yveshanoulle/forsgren/blob/main/LICENSE"' "${TMP}/happy/index.html"; then
  echo "  ok: index.html has the heading and an absolute link"
else
  fail "index.html lacks the heading or the absolute LICENSE link"
fi
if cname_is_domain "${TMP}/happy"; then
  echo "  ok: CNAME holds the domain"
else
  fail "CNAME does not hold exactly forsgren.be"
fi

cat > "${TMP}/fence.md" <<'MARKDOWN'
# T

```
code
```
MARKDOWN
STARTER_README="${TMP}/fence.md" capture "$GATE" "${TMP}/fenced"
want_red "a README outside the subset fails" "unsupported Markdown"
want_said "the failure names the build step" "readmepage could not render"
if [[ ! -e "${TMP}/fenced/index.html" ]]; then
  echo "  ok: a failed build writes nothing into the output directory"
else
  fail "a failed build left a page in the output directory"
fi

STARTER_README="${TMP}/gone.md" capture "$GATE" "${TMP}/gone"
want_red "a missing README fails" "gone.md"

printf 'not a directory\n' > "${TMP}/file"
capture "$GATE" "${TMP}/file"
want_red "an output directory that is a file fails" "cannot create the output directory"

if selftest_mutant "$GATE" "${TMP}/mutant/Scripts/build_starter_page.sh" '/CNAME/d'; then
  # The mutant lives in a copy of the script's directory; it cds to its own
  # parent, so it needs the repository around it.
  cp -R cmd internal go.mod go.sum README.md "${TMP}/mutant/" 2>/dev/null || true
  capture "${TMP}/mutant/Scripts/build_starter_page.sh" "${TMP}/mutant-out"
  if [[ "$RC" -ne 0 || ! -s "${TMP}/mutant-out/index.html" ]]; then
    fail "mutation proof: the mutant did not build the page (exit ${RC}), so its missing CNAME proves nothing. Output: ${OUT}"
  elif cname_is_domain "${TMP}/mutant-out"; then
    fail "mutation proof: the script without its CNAME line still wrote the CNAME"
  else
    echo "  ok: mutation proof: without its CNAME line the script writes no CNAME"
  fi
fi

selftest_end "the build-starter-page self-test found failures" "build-starter-page self-test (cases and a mutation proof)"
