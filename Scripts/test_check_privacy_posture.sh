#!/usr/bin/env bash
# canon: test_check_privacy_posture v2
# Scripts/test_check_privacy_posture.sh
#
# Self-test for Scripts/check_privacy_posture.sh, the
# canon version, byte-identical across the estate's repositories. Run in pre,
# before the gate it validates. The gate judges the real site in post; this
# test judges the GATE, on synthetic sites.
#
# WHY THE GATE EXISTS. A gate order file may declare the privacy pages n/a on
# the grounds that the site collects nothing. That claim is true the day it is
# written; nothing else stops someone pasting a Google Fonts link or an
# analytics snippet the next day. An exemption nothing enforces is a belief.
#
# The gate anchors itself with `cd "$(dirname "$0")/.."`, so each case runs a
# copy of it in Scripts/ of a throwaway root that holds the settings lib, a
# site_settings.txt (site_dir=Site) and the exceptions file the case names.
#
# Cases:
#   1. a clean site                               -> green, and the INFO block
#                                                    names fonts, embeds, links
#   2. a form, an analytics script, a Google Fonts stylesheet, cookie use
#                                                 -> red each, naming the finding
#   3. an outbound link                           -> green (a link is no finding)
#   4. a missing site dir                         -> exit 2
#   5. no argument: the site dir comes from site_settings.txt; no settings
#      file is exit 2
#   6. an iframe from a host not listed, privacy.html present
#                                                 -> red (no blanket rule)
#   7. an iframe from a listed host, src on the line after `<iframe`
#                                                 -> green, the INFO block lists it
#   8. a listed iframe and an unlisted one        -> red naming the unlisted
#   9. a relative src, an http src, an unquoted src, no src
#                                                 -> red each
#  10. a lookalike host (longer, and a part of a listed host)
#                                                -> red each
#  11. an empty exceptions file: an iframe red, no iframe green
#  12. a row without a reason, a row whose reason is blank, a malformed row,
#      a duplicate host                           -> exit 2 each, named
#  13. a missing exceptions file                  -> exit 2 (fail closed)
#  14. an anchor split over lines is a link; "links nowhere" only for none
# Mutation proofs (a weakened copy of the gate must turn the case green):
#   A. the blanket rule (any iframe passes when privacy.html exists): case 6
#   B. the allow-list skipped when its file is missing: case 13
#   C. the reason not required: case 12, the row without a reason
#   D. the src host matched as a part of a listed host instead of exactly: case 10
#   E. the HTML read line by line: the split anchor is missed and the INFO
#      block claims the site links nowhere (case 14)

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="$(pwd)/Scripts/check_privacy_posture.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "privacy posture self-test"

[[ -f "$GATE" ]] || selftest_abort "${GATE} does not exist — the privacy posture has no gate to validate"

DOLLAR='$'
EXC_OK="# comment
barcamp.io|embedded agenda viewer, documented on the privacy page
"

# mkroot <name> [exceptions-content | -]: a root with the gate copy, the
# settings lib and file, an empty Site/, and the exceptions file (none when "-").
mkroot() {
  local root="${TMP}/$1"
  mkdir -p "${root}/Scripts" "${root}/Site"
  cp "$GATE" "${root}/Scripts/check_privacy_posture.sh"
  cp Scripts/lib_site_settings.sh "${root}/Scripts/lib_site_settings.sh"
  printf 'site_dir=Site\nhtml_dupl_target=Site\nhtml_dupl_ceiling=1.0\nrequired_pages_manifest=m.json\n' > "${root}/Scripts/site_settings.txt"
  if [[ "${2-$EXC_OK}" != "-" ]]; then
    printf '%s' "${2-$EXC_OK}" > "${root}/Scripts/privacy_posture_exceptions.txt"
  fi
  printf '<!doctype html><html><head><style>@font-face{font-family:x;src:url(Fonts/x.otf)}</style></head><body><a href="https://ticketing.example/tickets">Tickets</a></body></html>\n' > "${root}/Site/index.html"
  printf '<html><body>privacy</body></html>\n' > "${root}/Site/privacy.html"
  echo "$root"
}

# gate_in <root> [args...]: runs the root's gate copy, from the root.
gate_in() {
  local root="$1"
  shift
  capture "${root}/Scripts/check_privacy_posture.sh" "$@"
}

# from_root <root> <command...>: runs the command with the root as working directory.
from_root() {
  local root="$1"
  shift
  (cd "$root" && "$@")
}

# --- 1. clean
R="$(mkroot clean)"
gate_in "$R" Site
want_green_ok "a clean site passes"
want_said "the report mentions the locally served fonts" "@font-face"
want_said "the report names the outbound destinations" "ticketing.example"
want_said "the report lists the allowed embeds" "barcamp.io"

# --- 2. findings
R="$(mkroot form)"
printf '<form action="/subscribe"><input name="email"></form>\n' >> "${R}/Site/index.html"
gate_in "$R" Site
want_red "rejects a form" "a form collects input"

R="$(mkroot analytics)"
printf '<script src="https://www.googletagmanager.com/gtag/js?id=G-X"></script>\n' >> "${R}/Site/index.html"
gate_in "$R" Site
want_red "rejects an analytics script" "FINDING"

R="$(mkroot gfonts)"
printf '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter">\n' >> "${R}/Site/index.html"
gate_in "$R" Site
want_red "rejects a third-party font stylesheet" "a third-party asset is loaded"

R="$(mkroot cookie)"
printf '<script>document.cookie="seen=1";</script>\n' >> "${R}/Site/index.html"
gate_in "$R" Site
want_red "rejects cookie or storage use" "cookies or browser storage"

# --- 3. a link is no finding
R="$(mkroot links)"
printf '<a href="https://other.example/x">buy</a><a href="https://social.example/y">in</a>\n' >> "${R}/Site/index.html"
gate_in "$R" Site
want_green_ok "an outbound link is not a finding"

# --- 4. a missing site dir
R="$(mkroot nosite)"
gate_in "$R" "${R}/does-not-exist"
want_exit "exits 2 on a missing site dir, never 0" 2 "site dir not found"

# --- 5. the site dir from the settings
R="$(mkroot settings)"
printf '<form action="/s"></form>\n' >> "${R}/Site/index.html"
capture from_root "$R" ./Scripts/check_privacy_posture.sh
want_red "no argument: the site dir comes from site_settings.txt (a form in Site/ is red)" "a form collects input"
rm "${R}/Scripts/site_settings.txt"
capture from_root "$R" ./Scripts/check_privacy_posture.sh
want_rc "no argument and no settings file is exit 2" 2

# --- 6. an unlisted host is red even with privacy.html present
UNLISTED='<iframe src="https://video.example/embed/x"></iframe>'
R="$(mkroot unlisted)"
printf '%s\n' "$UNLISTED" >> "${R}/Site/index.html"
gate_in "$R" Site
want_red "an iframe from an unlisted host is red although privacy.html exists" "an embedded third party"
want_said "the finding names the iframe" "video.example"

# --- 7. a listed host, the src on the line after <iframe
R="$(mkroot listed)"
printf '<iframe\n  src="https://barcamp.io/event/embed"\n  title="agenda"\n></iframe>\n' >> "${R}/Site/index.html"
gate_in "$R" Site
want_green_ok "an iframe from a listed host passes, src on the next line"

# --- 8. a listed and an unlisted one
R="$(mkroot mixed)"
printf '<iframe src="https://barcamp.io/e"></iframe>\n%s\n' "$UNLISTED" >> "${R}/Site/index.html"
gate_in "$R" Site
want_red "a listed iframe does not allow an unlisted one" "video.example"

# --- 9. a src that cannot be read as an https host
for variant in 'src="/local/embed.html"' 'src="http://barcamp.io/e"' 'src=https://barcamp.io/e' 'title="no source"'; do
  R="$(mkroot "bad-${#variant}-${variant:0:5}")"
  printf '<iframe %s></iframe>\n' "$variant" >> "${R}/Site/index.html"
  gate_in "$R" Site
  want_red "an iframe with ${variant} is red" "an embedded third party"
done

# --- 10. lookalike hosts
for host in barcamp.io.evil.example evilbarcamp.io camp.io; do
  R="$(mkroot "look-${host}")"
  printf '<iframe src="https://%s/e"></iframe>\n' "$host" >> "${R}/Site/index.html"
  gate_in "$R" Site
  want_red "the lookalike host ${host} is red" "an embedded third party"
done

# --- 11. an empty exceptions file
R="$(mkroot empty "# no embeds
")"
gate_in "$R" Site
want_green_ok "an empty exceptions file and no iframe is green"
printf '%s\n' '<iframe src="https://barcamp.io/e"></iframe>' >> "${R}/Site/index.html"
gate_in "$R" Site
want_red "an empty exceptions file allows no iframe" "an embedded third party"

# --- 12. malformed rows
R="$(mkroot noreason "barcamp.io|
")"
gate_in "$R" Site
want_exit "a row without a reason is exit 2" 2 "malformed row 1"
R="$(mkroot blankreason "barcamp.io|   
")"
gate_in "$R" Site
want_exit "a row whose reason is blank is exit 2" 2 "malformed row 1"
R="$(mkroot nobar "barcamp.io embedded viewer
")"
gate_in "$R" Site
want_exit "a row without a bar is exit 2" 2 "malformed row 1"
R="$(mkroot dup "barcamp.io|first
BARCAMP.io|second
")"
gate_in "$R" Site
want_exit "a duplicate host is exit 2" 2 "duplicate host"

# --- 13. a missing exceptions file fails closed
R="$(mkroot nofile -)"
gate_in "$R" Site
want_exit "a missing exceptions file is exit 2, never a pass" 2 "exceptions file not found"

# --- 14. the links INFO is true: an anchor split over lines is still a link
# The INFO block says what the site points at; "links nowhere off itself" must
# only be printed for a site that really has no outbound link, and an anchor
# whose href sits on a later line than `<a` (a formatter does this) is one.
R="$(mkroot splitlink)"
printf '<!doctype html><html><body>\n<a class="store"\n   rel="noopener"\n   href="https://store.example/app/1">App</a>\n</body></html>\n' > "${R}/Site/index.html"
gate_in "$R" Site
want_green_ok "an outbound link split over lines is not a finding"
want_said "the report names the destination of a link split over lines" "store.example"
if grep -qF "links nowhere" <<< "$OUT"; then
  fail "the report claims the site links nowhere although it has a link. Output: ${OUT}"
else
  echo "  ok: the report does not claim the site links nowhere"
fi

R="$(mkroot nolinks)"
printf '<!doctype html><html><body><p>no links here</p></body></html>\n' > "${R}/Site/index.html"
gate_in "$R" Site
want_green_ok "a site without any outbound link is green"
want_said "and the report says it links nowhere off itself" "links nowhere off itself"

# --- Mutation proofs
R="$(mkroot mut-blanket)"
printf '%s\n' "$UNLISTED" >> "${R}/Site/index.html"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  "s|^hits=\"${DOLLAR}(iframe_unlisted)\"${DOLLAR}|&; [ -f \"${DOLLAR}SITE/privacy.html\" ] \\&\\& hits=\"\"|" \
  "${R}/Site" \
  "the blanket rule (any iframe passes when privacy.html exists) turns case 6 green, so it is red BECAUSE of the host list" \
  "the blanket copy did not turn case 6 green"

R="$(mkroot mut-nofile -)"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  '/exceptions file not found/{n;s/exit 2/:/;}' \
  "${R}/Site" \
  "a copy that carries on without its exceptions file turns case 13 green" \
  "the copy without the missing-file exit did not turn case 13 green"

R="$(mkroot mut-reason "barcamp.io|
")"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  's/\[^\[:space:\]\]/[^|]*/' \
  "${R}/Site" \
  "a copy that does not require the reason turns the row-without-reason case green" \
  "the copy without the reason requirement did not turn the case green"

R="$(mkroot mut-substring)"
printf '<iframe src="https://camp.io/e"></iframe>\n' >> "${R}/Site/index.html"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  "s/\" ${DOLLAR}{host:-none} \"/\"${DOLLAR}{host:-none}\"/" \
  "${R}/Site" \
  "a match of the src host as a part of a listed host turns the lookalike case green" \
  "the substring-match copy did not turn the lookalike case green"

R="$(mkroot mut-splitlink)"
printf '<a class="store"\n   href="https://store.example/app/1">App</a>\n' > "${R}/Site/index.html"
if selftest_mutant "$GATE" "${R}/Scripts/check_privacy_posture.sh" 's/^  [|] tr .*$/  | cat \\/'; then
  gate_in "$R" Site
  if grep -qF "links nowhere" <<< "$OUT"; then
    echo "  ok: mutation proof: a copy that reads the HTML line by line prints the false 'links nowhere' for a split anchor"
  else
    fail "mutation proof: the line-by-line copy still names the split anchor, so the split-link case proves nothing. Output: $OUT"
  fi
fi

selftest_end "privacy posture gate" "privacy posture gate proven on synthetic sites (iframes by host list, malformed and missing exceptions red, five weakened copies caught, links true for a split anchor)"
