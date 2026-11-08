#!/usr/bin/env bash
# canon: test_check_privacy_posture v4
# v4 (forsgren#654): the media cases and their proofs, for check_privacy_posture v3
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
#  15. a video src, a source src, an img src and a poster from another host
#                                                 -> red each
#  16. the same, in upper case, split over lines, unquoted, single quoted,
#      protocol-relative, http, backslashed, spelled with a character
#      reference, behind a > in an earlier attribute -> red each
#  17. a host that only looks like an own host, a subdomain nobody declared,
#      an embed host used for media, an own host used for an iframe -> red each
#  18. an own host on each tag and attribute, a declared subdomain, relative
#      paths, no src at all, data-src, a tag that only starts like one -> green
#  19. no own host declared: a relative path green, an own host red; the
#      exceptions file missing: exit 2
#  20. a malformed or duplicate own row -> exit 2 each, named
# Mutation proofs (a weakened copy of the gate must turn the case green):
#   A. the blanket rule (any iframe passes when privacy.html exists): case 6
#   B. the allow-list skipped when its file is missing: case 13
#   C. the reason not required: case 12, the row without a reason
#   D. the src host matched as a part of a listed host instead of exactly: case 10
#   E. the HTML read line by line: the split anchor is missed and the INFO
#      block claims the site links nowhere (case 14)
#   F, G, H. video, source, img dropped from the tag list: case 15 for that tag
#   I. poster no longer read: case 15, the poster
#   J. own rows not honoured: the own-host case of 18 turns red
#   K. a relative path no longer passes: the relative case of 18 turns red
#   L. a subdomain matched without its dot: the lookalike of 17
#   M. anything allowed between the host and the path: the userinfo of 17
#   N. the media tags read line by line: the split tag of 16

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
EXC_OWN="${EXC_OK}own:media.site.example|the site's own media host
own:*.cdn.site.example|the site's own media subdomains
"
THIRD="https://other.example/a"

# mkroot <name> [exceptions-content | -]: a root with the gate copy, the
# settings lib and file, an empty Site/, and the exceptions file (none when "-").
mkroot() {
  local root="${TMP}/$1"
  mkdir -p "${root}/Scripts" "${root}/Site"
  cp "$GATE" "${root}/Scripts/check_privacy_posture.sh"
  cp Scripts/lib_site_settings.sh "${root}/Scripts/lib_site_settings.sh"
  printf 'site_dir=Site\nhtml_dupl_target=Site\nhtml_dupl_ceiling_jscpd4=1.0\nrequired_pages_manifest=m.json\n' > "${root}/Scripts/site_settings.txt"
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

# media_root <name> <html> [exceptions]: a root declaring the own hosts of
# EXC_OWN (or the given exceptions), the html appended to its index page.
media_root() {
  local root
  root="$(mkroot "$1" "${3-$EXC_OWN}")"
  printf '%s\n' "$2" >> "${root}/Site/index.html"
  echo "$root"
}

# media_red <name> <html>: the html's media is a finding.
media_red() {
  gate_in "$(media_root "$1" "$2")" Site
  want_red "${1}: ${2} is red" "media from another host"
}

# media_green <name> <html> [exceptions]: the html's media passes.
media_green() {
  gate_in "$(media_root "$1" "$2" "${3-$EXC_OWN}")" Site
  want_green_ok "${1}: ${2} is green"
}

# --- 15. media from another host, one case per tag and attribute
media_red red-video "<video src=\"${THIRD}.mp4\"></video>"
want_said "the finding names the host" "other.example"
media_red red-source "<video><source src=\"${THIRD}.mp4\" type=\"video/mp4\"></video>"
media_red red-img "<img src=\"${THIRD}.png\" alt=\"\">"
media_red red-poster "<video src=\"a.mp4\" poster=\"${THIRD}.jpg\"></video>"

# --- 16. the same tags, however they are written
media_red red-upper "<IMG SRC=\"${THIRD}.png\">"
media_red red-upper-tag "<VIDEO src=\"${THIRD}.mp4\"></VIDEO>"
media_red red-lines "<img
  alt=\"\"
  src=\"${THIRD}.png\">"
media_red red-unquoted "<img src=${THIRD}.png>"
media_red red-single "<img src='${THIRD}.png'>"
media_red red-spaces "<img src = \"${THIRD}.png\">"
media_red red-leading "<img src=\" ${THIRD}.png\">"
media_red red-protorel '<img src="//other.example/a.png">'
media_red red-http-own '<img src="http://media.site.example/a.png">'
media_red red-backslash '<img src="\\other.example/a.png">'
media_red red-backslash2 '<img src="/\other.example/a.png">'
media_red red-charref '<img src="https&#58;//other.example/a.png">'
media_red red-gt-attr "<img alt=\"a>b\" src=\"${THIRD}.png\">"
media_red red-scheme '<img src="ftp://media.site.example/a.png">'
media_red red-twice "<img src=\"a.png\" src=\"${THIRD}.png\">"
media_green green-upper-rel '<IMG SRC="a.png">'
media_green green-lines-own '<img
  src="https://media.site.example/a.png">'

# --- 17. not an own host
media_red red-apex-of-wild '<img src="https://cdn.site.example/a.png">'
media_red red-undeclared-sub '<img src="https://www.media.site.example/a.png">'
media_red red-suffix '<img src="https://media.site.example.other.example/a.png">'
media_red red-prefix '<img src="https://evilmedia.site.example/a.png">'
media_red red-nodot '<img src="https://badcdn.site.example/a.png">'
media_red red-userinfo '<img src="https://media.site.example@other.example/a.png">'
media_red red-userinfo-port '<img src="https://media.site.example:x@other.example/a.png">'
media_red red-embed-host '<img src="https://barcamp.io/a.png">'
R="$(media_root iframe-own '<iframe src="https://media.site.example/e"></iframe>')"
gate_in "$R" Site
want_red "an own-host row does not allow an iframe" "an embedded third party"

# --- 18. what passes
media_green green-own-video '<video src="https://media.site.example/a.mp4"></video>'
media_green green-own-source '<video><source src="https://media.site.example/a.mp4"></video>'
media_green green-own-img '<img src="https://MEDIA.site.example/a.png">'
media_green green-own-poster '<video src="a.mp4" poster="https://media.site.example/p.jpg"></video>'
media_green green-own-port '<img src="https://media.site.example:8443/a.png">'
media_green green-sub '<img src="https://a.cdn.site.example/x.png">'
media_green green-subsub '<img src="https://a.b.cdn.site.example/x.png">'
media_green green-relative '<img src="a.png"><img src="/m/a.png"><img src="./a.png"><img src="../a.png">'
media_green green-relative-query '<img src="a.png?x=1&amp;y=2">'
media_green green-relative-media '<video src="a.mp4" poster="p.jpg"><source src="/b.mp4"></video>'
media_green green-no-src '<video></video><img alt=""><source srcset="a.webp">'
media_green green-data-src "<img data-src=\"${THIRD}.png\" src=\"a.png\">"
media_green green-custom-tag "<video-player src=\"${THIRD}.mp4\"></video-player>"
R="$(media_root info-own '<img src="https://media.site.example/a.png">')"
gate_in "$R" Site
want_said "the report lists the own hosts" "media.site.example"
want_said "the report marks a subdomain row" "*.cdn.site.example"
if grep -qF "own:" <<< "$OUT"; then
  fail "the report prints an own row as an embed. Output: ${OUT}"
else
  echo "  ok: an own row is not listed among the embeds"
fi

# --- 19. no own host declared, no data file
media_green none-relative '<img src="a.png">' "$EXC_OK"
gate_in "$(media_root none-own '<img src="https://media.site.example/a.png">' "$EXC_OK")" Site
want_red "with no own host declared, an absolute media URL is red" "media from another host"
gate_in "$(media_root none-empty "<img src=\"${THIRD}.png\">" "# nothing declared
")" Site
want_red "a comments-only file allows no media host" "media from another host"
gate_in "$(media_root none-file "<img src=\"${THIRD}.png\">" -)" Site
want_exit "a missing exceptions file with third-party media is exit 2, never a pass" 2 "exceptions file not found"

# --- 20. malformed own rows
for row in 'own:media.site.example|' 'own:media.site.example|   ' 'own:|x' 'own:*.|x' 'own:media.site.example' 'own:*media.site.example|x' 'own:a b|x'; do
  R="$(mkroot "bad-own-${#row}-${row:4:3}" "${row}
")"
  gate_in "$R" Site
  want_exit "the own row '${row}' is exit 2" 2 "malformed row 1"
done
R="$(mkroot dup-own "own:media.site.example|one
own:MEDIA.site.example|two
")"
gate_in "$R" Site
want_exit "a duplicate own host is exit 2" 2 "duplicate host"
R="$(mkroot dup-own-wild "own:*.cdn.site.example|one
own:*.CDN.site.example|two
")"
gate_in "$R" Site
want_exit "a duplicate own subdomain row is exit 2" 2 "duplicate host"

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

R="$(media_root mut-video "<video src=\"${THIRD}.mp4\"></video>")"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  "s/^MEDIA_TAGS='img|video|source'/MEDIA_TAGS='img|source'/" \
  "${R}/Site" \
  "video dropped from the tag list turns the third-party video src green" \
  "the copy without video did not turn the video case green"

R="$(media_root mut-source "<video><source src=\"${THIRD}.mp4\"></video>")"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  "s/^MEDIA_TAGS='img|video|source'/MEDIA_TAGS='img|video'/" \
  "${R}/Site" \
  "source dropped from the tag list turns the third-party source src green" \
  "the copy without source did not turn the source case green"

R="$(media_root mut-img "<img src=\"${THIRD}.png\">")"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  "s/^MEDIA_TAGS='img|video|source'/MEDIA_TAGS='video|source'/" \
  "${R}/Site" \
  "img dropped from the tag list turns the third-party img src green" \
  "the copy without img did not turn the img case green"

R="$(media_root mut-poster "<video src=\"a.mp4\" poster=\"${THIRD}.jpg\"></video>")"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  's/src|poster)/src)/' \
  "${R}/Site" \
  "a copy that does not read poster turns the third-party poster green" \
  "the copy without poster did not turn the poster case green"

R="$(media_root mut-own '<img src="https://media.site.example/a.png">')"
if selftest_mutant "$GATE" "${R}/Scripts/check_privacy_posture.sh" "s/^ *own_hosts=\"${DOLLAR}{own_hosts}.*${DOLLAR}/:/"; then
  gate_in "$R" Site
  want_red "mutation proof: a copy that ignores the own rows turns the own-host case red" "media from another host"
fi

R="$(media_root mut-relative '<img src="a.png">')"
if selftest_mutant "$GATE" "${R}/Scripts/check_privacy_posture.sh" 's/return 0 # a relative path/return 1/'; then
  gate_in "$R" Site
  want_red "mutation proof: a copy that refuses relative paths turns the relative case red" "media from another host"
fi

R="$(media_root mut-nodot '<img src="https://badcdn.site.example/a.png">')"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  "s/?\*\"\.${DOLLAR}{suffix}\"/*\"${DOLLAR}{suffix}\"/" \
  "${R}/Site" \
  "a subdomain matched without its dot turns the lookalike green" \
  "the copy without the dot did not turn the lookalike green"

R="$(media_root mut-userinfo '<img src="https://media.site.example:x@other.example/a.png">')"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  's/(:\[0-9\]+)?/(:[^\/]*)?/' \
  "${R}/Site" \
  "anything allowed between the host and the path turns the userinfo case green" \
  "the copy without the port rule did not turn the userinfo case green"

R="$(media_root mut-lines "<img
  src=\"${THIRD}.png\">")"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  "s/joined=\"${DOLLAR}(tr .*${DOLLAR}/joined=\"${DOLLAR}(cat \"${DOLLAR}file\")\"/" \
  "${R}/Site" \
  "the media tags read line by line turn the split tag green" \
  "the line-by-line copy did not turn the split tag green"

selftest_end "privacy posture gate" "privacy posture gate proven on synthetic sites (iframes by host list, media by own host or relative path, malformed and missing exceptions red, fourteen weakened copies caught, links true for a split anchor)"
