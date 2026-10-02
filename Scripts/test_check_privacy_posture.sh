#!/usr/bin/env bash
set -euo pipefail

# Fixture for check_privacy_posture.sh.
#
# WHY THIS GATE EXISTS. This repo declares `privacy pages|n/a` on the grounds
# that the page collects nothing: no forms, no analytics or tracking, no
# cookies or storage, no third-party assets or embeds. Nothing else stops
# someone pasting a Google Fonts link or an analytics snippet the next day, at
# which point the exemption would be false and still on the record.
#
# Yves ruled privacy into the canon so every site must answer the question
# rather than only the site that thought of it. This is the other half: the
# ANSWER is checked too. An exemption nothing enforces is a belief.
#
# It is NOT konenki's check_privacy_pages.sh, which validates the CONTENT of a
# privacy page. Different question, different site: konenki has such a page
# because konenki.be handles health data; this one asserts there is nothing to
# write a page about.
#
# Deliberately NOT flagged: outbound LINKS. forsgren's page has none today;
# the cases below borrow konenki-website's (pretix.eu, a social platform) as
# made-up examples. A link transmits nothing until someone clicks it and then
# they are plainly somewhere else. What matters is what the page loads or
# stores WITHOUT being asked.
#
# Exit: 0 clean, 1 finding, 2 tooling/target missing.
#
# Local invocation: ./Scripts/test_check_privacy_posture.sh

CHECK="./Scripts/check_privacy_posture.sh"
if [[ ! -f "$CHECK" ]]; then
  echo "FAIL: script not found at $CHECK" >&2
  exit 1
fi

TMP="$(mktemp -d)"
COMPLETED=0
cleanup() {
  rm -rf "$TMP"
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: privacy posture fixture aborted before completing all cases" >&2
    exit 1
  fi
}
trap cleanup EXIT

failures=0
check() {
  if [[ "$2" == "$3" ]]; then echo "  ✅ $1"; else echo "  ❌ $1 — expected exit $2, got $3"; failures=$((failures+1)); fi
}
run() { set +e; OUT="$("$CHECK" "$@" 2>&1)"; RC=$?; set -e; }

echo "test_check_privacy_posture"

clean_site() {
  local d="$1"
  mkdir -p "$d"
  printf '<!doctype html><html><head><style>@font-face{font-family:x;src:url(Fonts/x.otf)}</style></head><body><a href="https://pretix.eu/tickets">Tickets</a></body></html>\n' > "$d/index.html"
}

# --- the real site must pass; if it does not, the n/a in the order file is
# false and this gate is the thing that says so.
# forsgren: the site is generated, not committed, and this self-test runs in
# pre, before Scripts/build_site.sh has written .build/site. So the case builds
# its own copy into the temp dir (binary and page-count sink there too, as in
# Scripts/test_build_site.sh) and checks that.
set +e
SITE_PAGE_COUNT_FILE="$TMP/built.count" FORSGREN_BIN_DIR="$TMP/bin" \
  ./Scripts/build_site.sh "$TMP/built" > "$TMP/built.log" 2>&1
BUILD_RC=$?
set -e
check "the generated site builds" 0 "$BUILD_RC"
[[ "$BUILD_RC" -eq 0 ]] || sed 's/^/    /' "$TMP/built.log"
run "$TMP/built"
check "the shipped site collects nothing" 0 "$RC"
[[ "$RC" -eq 0 ]] || printf '%s\n' "$OUT" | sed 's/^/    /'

# --- A PASSING RUN MUST SAY WHAT THE SITE DOES LOAD AND LINK.
# "no third-party assets" is a claim about an absence, and an absence is the
# hardest thing to read. Showing the fonts served from this repo and the hosts
# visitors are sent to makes the verdict checkable instead of trusted — the
# same reason the duplication ratchet prints its percentage on a green run.
# These are INFORMATION, not findings: none of them fails the gate.
# Driven against the SYNTHETIC site, not the real one: the destinations a
# given site links to are its own business and differ per repo, so asserting a
# specific host here would make this fixture unportable — which is exactly the
# hard-coded-page-names problem the deployed-pages fixture already had.
D="$TMP/info"; clean_site "$D"
run "$D"
if grep -q "INFO" <<<"$OUT"; then
  echo "  ✅ a passing run reports what is loaded and linked"
else
  echo "  ❌ a passing run says nothing about the site's actual external surface"
  failures=$((failures+1))
fi
grep -qi "font" <<<"$OUT" \
  || { echo "  ❌ the report does not mention the locally served fonts"; failures=$((failures+1)); }
grep -q "pretix.eu" <<<"$OUT" \
  || { echo "  ❌ the report does not name the outbound destinations visitors are sent to"; failures=$((failures+1)); }

# --- a form appears
D="$TMP/form"; clean_site "$D"
printf '<form action="/subscribe"><input name="email"></form>\n' >> "$D/index.html"
run "$D"
check "rejects a form" 1 "$RC"
grep -qi "form" <<<"$OUT" || { echo "  ❌ the finding does not name the form"; failures=$((failures+1)); }

# --- an analytics snippet appears
D="$TMP/analytics"; clean_site "$D"
printf '<script src="https://www.googletagmanager.com/gtag/js?id=G-X"></script>\n' >> "$D/index.html"
run "$D"
check "rejects an analytics script" 1 "$RC"

# --- Google Fonts: the classic one. A stylesheet from fonts.googleapis.com
# sends every visitor's IP to a third party before anything is clicked, and it
# looks exactly like a local style link.
D="$TMP/gfonts"; clean_site "$D"
printf '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter">\n' >> "$D/index.html"
run "$D"
check "rejects a third-party font stylesheet" 1 "$RC"

# --- an iframe embed
D="$TMP/iframe"; clean_site "$D"
printf '<iframe src="https://www.youtube.com/embed/x"></iframe>\n' >> "$D/index.html"
run "$D"
check "rejects an embedded third party" 1 "$RC"

# --- cookies / storage
D="$TMP/cookie"; clean_site "$D"
printf '<script>document.cookie="seen=1";</script>\n' >> "$D/index.html"
run "$D"
check "rejects cookie or storage use" 1 "$RC"

# --- outbound links are NOT findings: a link transmits nothing until clicked.
D="$TMP/links"; clean_site "$D"
printf '<a href="https://pretix.eu/x">buy</a><a href="https://www.linkedin.com/y">in</a>\n' >> "$D/index.html"
run "$D"
check "an outbound link is not a finding" 0 "$RC"

# --- fail closed on a missing target, never a clean 0
run "$TMP/does-not-exist"
check "exits 2 on a missing site dir, never 0" 2 "$RC"

COMPLETED=1
if [[ "$failures" -ne 0 ]]; then
  echo ""
  echo "FAIL: check_privacy_posture contract"
  exit 1
fi
echo ""
echo "✅ test_check_privacy_posture"
