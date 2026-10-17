#!/usr/bin/env bash
# Scripts/test_live_check.sh
#
# Self-test for Scripts/live_check.sh (forsgren#205, step 2 of 2), the check
# the starter page workflow runs against the live site after every deploy.
# forsgren's own. No network: a stub `curl` on PATH answers like a site whose
# every answer a case sets through the environment, and logs the arguments it
# was called with. Each case asserts the OK line, or the ❌ line that NAMES the
# failing check and the observed value, so a red for the wrong reason fails.
#   1. a site that is right                      -> OK, with status codes and
#                                                   content types, on try 1
#   2. 308 instead of 301                        -> OK
#   3. http answers 302 / 200 / a redirect to
#      http / a redirect to another host         -> red, "http redirect"
#   4. a certificate curl refuses (exit 60)      -> red, "certificate validation"
#   5. the page answers 404 / text/plain / has
#      no stylesheet link                        -> red, "https page" / "stylesheet"
#   6. the stylesheet answers 404 / text/plain   -> red, "stylesheet"
#   7. href styles.css, /styles.css and an
#      absolute URL                              -> the stylesheet the page
#                                                   links is the one fetched
#   8. a page that fails twice, then answers     -> OK, "3 tries"
#   9. a page that never answers                 -> red after exactly the bound
#  10. curl is never given -k or --insecure, and is told to ignore a curlrc
#  11. a missing or malformed argument, a bad try count -> exit 2
# Mutation proofs: a copy without the redirect check, without the Location
# assertion, with --insecure added and without the stylesheet check must each
# let the case they exist for pass.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "live check self-test"

CHECK="Scripts/live_check.sh"
[[ -f "$CHECK" ]] || selftest_abort "${CHECK} does not exist — nothing checks the live site after a deploy"

STUBS="${TMP}/bin"
mkdir -p "$STUBS"
cat > "${STUBS}/curl" <<'STUB'
#!/usr/bin/env bash
# A curl that answers from the environment. It understands exactly the
# options live_check.sh uses: --output/--dump-header FILE, the URL last.
printf '%s\n' "$*" >> "${STUB_LOG:?}"
out=""
hdr=""
insecure=0
prev=""
for arg in "$@"; do
  case "$prev" in
    --output|-o) out="$arg" ;;
    --dump-header|-D) hdr="$arg" ;;
  esac
  case "$arg" in
    -k|--insecure) insecure=1 ;;
  esac
  prev="$arg"
  url="$arg"
done
host="example.test"
respond() { # status content-type [location] [body-file]
  {
    printf 'HTTP/2 %s\r\n' "$1"
    [[ -n "$2" ]] && printf 'Content-Type: %s\r\n' "$2"
    [[ -n "${3:-}" ]] && printf 'Location: %s\r\n' "$3"
    printf '\r\n'
  } > "$hdr"
  if [[ -n "${4:-}" ]]; then cat "$4" > "$out"; else : > "$out"; fi
  exit 0
}
case "$url" in
  "http://${host}/")
    respond "${HTTP_STATUS:-301}" "" "${HTTP_LOCATION-https://${host}/}"
    ;;
  "https://${host}/")
    if [[ "${CERT:-ok}" == bad && "$insecure" -eq 0 ]]; then
      echo "curl: (60) SSL certificate problem" >&2
      exit 60
    fi
    n=$(( $(cat "${STUB_COUNT:?}" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$STUB_COUNT"
    if [[ "$n" -le "${PAGE_FAILS:-0}" ]]; then respond 503 "text/html"; fi
    respond "${PAGE_STATUS:-200}" "${PAGE_CT-text/html; charset=utf-8}" "" "${PAGE_BODY:?}"
    ;;
  *)
    printf '%s\n' "$url" >> "${STUB_CSS_LOG:?}"
    respond "${CSS_STATUS:-200}" "${CSS_CT-text/css}"
    ;;
esac
STUB
chmod +x "${STUBS}/curl"

page_with() { # <link html> — a page body file
  local f="${TMP}/page-$RANDOM.html"
  printf '<!doctype html>\n<html><head><meta charset="utf-8">\n%s\n</head><body><p>hi</p></body></html>\n' "$1" > "$f"
  echo "$f"
}
GOOD_PAGE="$(page_with '<link rel="stylesheet" href="styles.css">')"

# run_check [script] [arg] — the check against the stub; the environment of the
# case is whatever the caller exported on the same line (env VAR=... run_check).
run_check() {
  : > "${TMP}/curl.log"
  : > "${TMP}/css.log"
  rm -f "${TMP}/count"
  PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/curl.log" STUB_CSS_LOG="${TMP}/css.log" STUB_COUNT="${TMP}/count" \
    LIVE_CHECK_TRIES="${LIVE_CHECK_TRIES:-5}" LIVE_CHECK_DELAY=0 PAGE_BODY="${PAGE_BODY:-$GOOD_PAGE}" \
    capture "${1:-$CHECK}" "${2-https://example.test}"
}
page_fetches() { cat "${TMP}/count" 2>/dev/null || echo 0; }

# --- 1. 2. a site that is right ----------------------------------------------
run_check
want_green "1. a site that is right" "OK: live check of https://example.test/"
want_said "1. the OK line names the redirect" "http redirects 301 to https://example.test/"
want_said "1. the OK line names the page" "https page 200 text/html (certificate validated)"
want_said "1. the OK line names the stylesheet" "stylesheet https://example.test/styles.css 200 text/css"
want_said "1. the OK line counts the tries" "1 try"

HTTP_STATUS=308 run_check
want_green "2. 308 is a redirect too" "http redirects 308 to https://example.test/"

# --- 3. the http redirect ------------------------------------------------------
HTTP_STATUS=302 run_check
want_red "3. a 302 is not permanent: names the check" "❌ FAIL: live check: http redirect"
want_said "3. a 302: names the observed status" "answered 302"

HTTP_STATUS=200 HTTP_LOCATION='' run_check
want_red "3. no redirect at all: names the check" "❌ FAIL: live check: http redirect"
want_said "3. no redirect: names the observed status" "answered 200"

HTTP_LOCATION=http://example.test/ run_check
want_red "3. a redirect to http: names the check" "❌ FAIL: live check: http redirect"
want_said "3. a redirect to http: names the observed Location" "Location http://example.test/"

HTTP_LOCATION=https://other.test/ run_check
want_red "3. a redirect to another host: names the check" "❌ FAIL: live check: http redirect"
want_said "3. a redirect to another host: names the observed Location" "Location https://other.test/"

# --- 4. the certificate --------------------------------------------------------
CERT=bad LIVE_CHECK_TRIES=2 run_check
want_red "4. a refused certificate: names the check" "❌ FAIL: live check: certificate validation"
want_said "4. a refused certificate: names curl's exit" "curl exit 60"

# --- 5. the page -----------------------------------------------------------------
PAGE_STATUS=404 LIVE_CHECK_TRIES=1 run_check
want_red "5. a 404 page: names the check" "❌ FAIL: live check: https page"
want_said "5. a 404 page: names the observed status" "answered 404"

PAGE_CT=text/plain LIVE_CHECK_TRIES=1 run_check
want_red "5. a page that is not html: names the check" "❌ FAIL: live check: https page"
want_said "5. a page that is not html: names the observed type" "Content-Type text/plain"

PAGE_BODY="$(page_with '<link rel="icon" href="favicon.svg">')" LIVE_CHECK_TRIES=1 run_check
want_red "5. no stylesheet link: names the check" "❌ FAIL: live check: stylesheet"
want_said "5. no stylesheet link: says what is missing" "no stylesheet link"

# --- 6. the stylesheet -----------------------------------------------------------
CSS_STATUS=404 LIVE_CHECK_TRIES=1 run_check
want_red "6. a 404 stylesheet: names the check" "❌ FAIL: live check: stylesheet"
want_said "6. a 404 stylesheet: names the url and status" "https://example.test/styles.css answered 404"

CSS_CT=text/plain LIVE_CHECK_TRIES=1 run_check
want_red "6. a stylesheet that is not css: names the check" "❌ FAIL: live check: stylesheet"
want_said "6. a stylesheet that is not css: names the observed type" "Content-Type text/plain"

# --- 7. the href is parsed and resolved ------------------------------------------
resolves_to() { # <case> <link html> <url that must be fetched>
  PAGE_BODY="$(page_with "$2")" run_check
  want_green "7. $1" "stylesheet $3 200 text/css"
  if ! grep -qxF "$3" "${TMP}/css.log"; then
    fail "7. $1: the stylesheet fetched was '$(tr '\n' ' ' < "${TMP}/css.log")', not $3"
  fi
}
resolves_to "a relative href" '<link rel="stylesheet" href="styles.css">' "https://example.test/styles.css"
resolves_to "a root-relative href" '<link rel="stylesheet" href="/assets/site.css">' "https://example.test/assets/site.css"
resolves_to "an absolute href, attributes in another order" "<link href='https://example.test/abs.css' rel='stylesheet'>" "https://example.test/abs.css"
resolves_to "a link tag over two lines" $'<link rel="stylesheet"\n  href="two.css">' "https://example.test/two.css"

# --- 8. 9. the bounded retry -----------------------------------------------------
PAGE_FAILS=2 run_check
want_green "8. a page that fails twice, then answers" "3 tries"

PAGE_FAILS=99 LIVE_CHECK_TRIES=3 run_check
want_red "9. a page that never answers: names the check" "❌ FAIL: live check: https page"
want_said "9. a page that never answers: names the observed status" "answered 503"
if [[ "$(page_fetches)" != 3 ]]; then
  fail "9. the retry is not bounded by LIVE_CHECK_TRIES: the page was fetched $(page_fetches) times, want 3"
else
  echo "  ok: 9. the page was fetched exactly 3 times"
fi

# --- 10. curl is never told to skip validation -----------------------------------
run_check
if grep -qE -- '(^| )(-k|--insecure)( |$)' "${TMP}/curl.log"; then
  fail "10. curl was called with -k or --insecure: $(cat "${TMP}/curl.log")"
elif grep -qvE -- '^--disable ' "${TMP}/curl.log"; then
  fail "10. a curl call does not start with --disable, so a curlrc could add -k: $(cat "${TMP}/curl.log")"
else
  echo "  ok: 10. every curl call starts with --disable and none passes -k or --insecure"
fi

# --- 11. usage -------------------------------------------------------------------
PATH="${STUBS}:${PATH}" capture "$CHECK"
want_exit "11. no argument" 2 "usage: Scripts/live_check.sh <https-base-url>"
run_check "$CHECK" http://example.test
want_exit "11. an http base" 2 "usage: Scripts/live_check.sh <https-base-url>"
run_check "$CHECK" https://example.test/some/path
want_exit "11. a base with a path" 2 "usage: Scripts/live_check.sh <https-base-url>"
LIVE_CHECK_TRIES=0 run_check
want_exit "11. zero tries" 2 "LIVE_CHECK_TRIES must be a positive integer"
LIVE_CHECK_TRIES=many run_check
want_exit "11. a try count that is not a number" 2 "LIVE_CHECK_TRIES must be a positive integer"

# --- mutation proofs ---------------------------------------------------------------
MUT="${TMP}/mutants"

if selftest_mutant "$CHECK" "${MUT}/no_redirect.sh" 's/^  check_redirect$/  :/'; then
  HTTP_STATUS=200 HTTP_LOCATION='' run_check "${MUT}/no_redirect.sh"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: without the redirect check a site with no redirect passes, so case 3 is red because of it"
  else
    fail "mutation proof: the redirect-less check still failed (exit ${RC}). Output: ${OUT}"
  fi
fi

NO_LOCATION="s/\\[\\[ \"\\\$location\" == \"\\\$HTTPS_URL\" \\]\\]/true/"
if selftest_mutant "$CHECK" "${MUT}/no_location.sh" "$NO_LOCATION"; then
  HTTP_LOCATION=https://other.test/ run_check "${MUT}/no_location.sh"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: without the Location assertion a redirect to another host passes, so case 3 asserts it"
  else
    fail "mutation proof: the Location-less check still failed (exit ${RC}). Output: ${OUT}"
  fi
fi

if selftest_mutant "$CHECK" "${MUT}/insecure.sh" 's/--disable /--disable --insecure /'; then
  CERT=bad run_check "${MUT}/insecure.sh"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: with --insecure a refused certificate passes, so case 4 is red because validation is on"
  else
    fail "mutation proof: the --insecure check still failed (exit ${RC}). Output: ${OUT}"
  fi
fi

if selftest_mutant "$CHECK" "${MUT}/no_css.sh" 's/^  check_stylesheet$/  :/'; then
  CSS_STATUS=404 run_check "${MUT}/no_css.sh"
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: without the stylesheet check a 404 stylesheet passes, so case 6 is red because of it"
  else
    fail "mutation proof: the stylesheet-less check still failed (exit ${RC}). Output: ${OUT}"
  fi
fi

selftest_end "the live check self-test found failures" \
  "live check: a right site is OK with its codes and types; the redirect, the certificate, the page and the stylesheet each fail by name with the observed value; the retry is bounded; validation is never off; mutation proven"
