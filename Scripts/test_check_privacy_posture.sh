#!/usr/bin/env bash
# canon: test_check_privacy_posture v7
# v7 (forsgren#659): the CSS @import, input type=image and SVG href cases and their proofs, for check_privacy_posture v6 and check_privacy_posture_urls v3
# v6 (forsgren#656): the user name and password cases of every resource attribute and their proofs, for check_privacy_posture v5 and check_privacy_posture_urls v2
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
#  21. a planted URL in srcset on img, srcset on source (a later candidate too,
#      after descriptors and after a data URL), audio, track, embed and object
#                                                 -> red each, naming the host
#  22. the same mechanisms however they are written: letter case, split over
#      lines, unquoted, single quoted, protocol-relative, http, backslashed,
#      a character reference, a user name, a lookalike host, a tag never closed
#                                                 -> red each
#  23. a data URL outside a srcset candidate      -> red
#  24. what passes: relative paths, own hosts, a declared subdomain, descriptors
#      (1x, 200w), data URLs with commas in a candidate, a comma inside
#      parentheses, no value, data-srcset, a tag that only starts like one
#  25. the URL script missing                     -> exit 2 (fail closed)
#  26. a user name or password in every resource attribute (iframe, img, source,
#      video, audio, track, embed, object, script, link, poster, srcset and CSS
#      url()), an allowed host before the @ and an allowed host after it
#                                                 -> red each, naming the rule
#  27. the same however it is written: letter case, split over lines, quotes,
#      protocol-relative, character references, CSS escapes -> red each
#  28. no user-info: URLs with an @ in the path, query or a data URL, an allowed
#      iframe, a port, a link, a tag never closed, the old quote rules -> green;
#      an absolute script or url() on an own host stays red, as it was
#  29. CSS @import from another host, in a style element and in a .css file:
#      quoted, url() in each spelling, letter case, comments, white space,
#      escapes, protocol-relative, http, a user name, a data URL -> red each
#  30. an @import nothing can read, a style element never closed, markup or a
#      character reference inside a style element -> red each (fail closed)
#  31. what passes: relative paths, an own host, an @import in a comment or a
#      string, a longer name, text outside a style element, an ampersand
#  32. input type=image: letter case, a reference in the type, src first, quotes,
#      every URL rule -> red each; relative, own host, no src, another type -> green
#  33. href and xlink:href on every SVG element that takes one -> red each;
#      #symbol-id, relative, own host, an SVG <a>, another attribute -> green
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
#   M. anything allowed between the host and the path, with the URL script's
#      user-info rule off for img src: the userinfo of 17
#   N. the media tags read line by line: the split tag of 16
#   O to T. srcset on img, srcset on source, audio, track, embed, object
#      dropped from the table of the URL script: case 21 for that one
#   U. only a srcset's first candidate judged: the later candidate of 21
#   V. a srcset split on commas: the data URL with a URL inside it of 24 turns red
#   W. a trailing comma not ending the candidate: the later candidate of 21
#   X. parentheses in a descriptor ignored: the comma inside them of 24 turns red
#   Y. data URLs refused in a srcset: the data URL of 24 turns red
#   Z. data URLs allowed everywhere: case 23
#   AA. a relative path no longer passes: the relative case of 24 turns red
#   AB. own rows not honoured: the own-host case of 24 turns red
#   AC. a subdomain matched without its dot: the lookalike of 22
#   AD. a URL with a user name allowed: the user name case of 22
#   AE. the protocol-relative check dropped: the own host of 22
#   AF. the quote rule dropped: the unquoted own host of 22
#   AG. the character reference rule dropped: the case of 22
#   AH. the tag count dropped: the tag never closed of 22
#   AI. the gate carries on when the URL script fails: case 25
#   AJ, AK, AL. iframe, script, link dropped from the user-info table: case 26
#      or 27 for that tag turns green
#   AM to AR. src and poster of img, video and source dropped from that table:
#      the finding of case 26 is gone (the media check keeps those red)
#   AS. CSS url() no longer read: case 27
#   AT. a user name in a srcset allowed: case 26 turns green
#   AU. character references not read before the URL is parsed: case 27
#   AV. CSS escapes not read: case 27
#   AW. only the https base asked: the scheme-relative case of 27
#   AX. the host policy applied to the tags of the user-info table: the allowed
#      iframe of 28 turns red
#   AY. a tag never closed counted against the user-info tags: case 28 turns red
#   AZ, BA. .css files, style elements no longer read for @import: case 29
#   BB, BC. CSS comments, CSS strings no longer skipped: case 31 turns red
#   BD, BE, BF. escapes not read in a name, a string, a bare url(): case 29
#   BG. an @import nothing can read skipped: case 30
#   BH. a url() token not read whole: the stray quote of 29 hides the import
#   BI. an ampersand of CSS read as a reference: case 31 turns red
#   BJ. a reference allowed in a style element: case 30
#   BK. a style element read past: the opening in a comment of 30 hides the next
#   BL. input dropped from the table: case 32
#   BM, BN. the type read with its case, without its references: case 32
#   BO. every input read whatever its type: case 32 turns red
#   BP, BQ, BR. image, use, feImage dropped: case 33 for that one
#   BS, BT. href, xlink:href no longer read: case 33
#   BU. a local reference no longer passing: the fragment of 33 turns red

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GATE="$(pwd)/Scripts/check_privacy_posture.sh"
URLS="$(pwd)/Scripts/check_privacy_posture_urls.mjs"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "privacy posture self-test"

[[ -f "$GATE" ]] || selftest_abort "${GATE} does not exist — the privacy posture has no gate to validate"
[[ -f "$URLS" ]] || selftest_abort "${URLS} does not exist — the gate has no URL script to call"

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
  cp "$URLS" "${root}/Scripts/check_privacy_posture_urls.mjs"
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

# resource_red <name> <html> [text]: the html's resource is a finding, saying
# the text (by default the planted host).
resource_red() {
  gate_in "$(media_root "$1" "$2")" Site
  want_red "${1}: ${2} is red" "a resource from another host"
  want_said "${1}: the finding says ${3:-other.example}" "${3:-other.example}"
}

# --- 21. a planted URL in each newly covered mechanism
resource_red red-srcset-img "<img src=\"a.png\" srcset=\"${THIRD}.png 1x\">"
resource_red red-srcset-source "<picture><source srcset=\"${THIRD}.webp\"><img src=\"a.png\"></picture>"
resource_red red-srcset-img-later "<img src=\"a.png\" srcset=\"a.png 1x, b.png 2x, ${THIRD}.png 3x\">"
resource_red red-srcset-source-later "<picture><source srcset=\"a.webp 200w, ${THIRD}.webp 400w\"><img src=\"a.png\"></picture>"
resource_red red-srcset-after-comma "<img src=\"a.png\" srcset=\"a.png, ${THIRD}.png\">"
resource_red red-srcset-no-space "<img src=\"a.png\" srcset=\"a.png 1x,${THIRD}.png 2x\">"
resource_red red-srcset-after-data "<img src=\"a.png\" srcset=\"data:image/gif;base64,R0lG,ODlh 1x, ${THIRD}.png 2x\">"
resource_red red-audio "<audio src=\"${THIRD}.mp3\"></audio>"
resource_red red-track "<video src=\"a.mp4\"><track src=\"${THIRD}.vtt\"></video>"
resource_red red-embed "<embed src=\"${THIRD}.swf\">"
resource_red red-object "<object data=\"${THIRD}.pdf\"></object>"

# --- 22. the same mechanisms, however they are written
resource_red red-res-upper "<AUDIO SRC=\"${THIRD}.mp3\"></AUDIO>"
resource_red red-res-upper-srcset "<IMG SRCSET=\"${THIRD}.png 1x\" SRC=\"a.png\">"
resource_red red-res-lines "<object
  type=\"application/pdf\"
  data=\"${THIRD}.pdf\"></object>"
resource_red red-res-srcset-lines "<img src=\"a.png\" srcset=\"a.png 1x,
  ${THIRD}.png 2x\">"
resource_red red-res-unquoted "<audio src=${THIRD}.mp3></audio>"
resource_red red-res-single "<embed src='${THIRD}.swf'>"
resource_red red-res-own-unquoted '<audio src=https://media.site.example/a.mp3></audio>' 'not double-quoted'
resource_red red-res-protorel '<track src="//other.example/a.vtt">' 'protocol-relative'
resource_red red-res-own-protorel '<audio src="//media.site.example/a.mp3"></audio>' 'protocol-relative'
resource_red red-res-http-own '<embed src="http://media.site.example/a.swf">' 'not https'
resource_red red-res-backslash '<object data="\\other.example/a.pdf"></object>' 'protocol-relative'
resource_red red-res-charref '<audio src="https&#58;//other.example/a.mp3"></audio>' 'character reference'
resource_red red-res-userinfo '<audio src="https://user@media.site.example/a.mp3"></audio>' 'user name'
resource_red red-res-suffix '<embed src="https://media.site.example.other.example/a.swf">'
resource_red red-res-prefix '<object data="https://evilmedia.site.example/a.pdf"></object>' 'evilmedia.site.example'
resource_red red-res-nodot '<audio src="https://badcdn.site.example/a.mp3"></audio>' 'badcdn.site.example'
resource_red red-res-apex '<img src="a.png" srcset="https://cdn.site.example/a.png 1x">' 'cdn.site.example'
resource_red red-res-embed-host '<audio src="https://barcamp.io/a.mp3"></audio>' 'barcamp.io'
resource_red red-res-twice "<audio src=\"a.mp3\" src=\"${THIRD}.mp3\"></audio>"
resource_red red-res-never-closed "<audio src=\"${THIRD}.mp3" 'not a complete tag'

# --- 23. a data URL is only for a srcset candidate
resource_red red-data-audio '<audio src="data:audio/mpeg;base64,AA"></audio>' 'not https'
resource_red red-data-embed '<embed src="data:text/html,hello">' 'not https'
resource_red red-data-object '<object data="data:text/html,hello"></object>' 'not https'

# --- 24. what passes
media_green green-res-relative '<audio src="a.mp3"></audio><track src="/t/a.vtt"><embed src="./a.swf"><object data="../a.pdf"></object>'
media_green green-res-query '<audio src="a.mp3?x=1&amp;y=2"></audio>'
media_green green-res-own '<audio src="https://media.site.example/a.mp3"></audio><track src="https://MEDIA.site.example/a.vtt"><embed src="https://media.site.example:8443/a.swf"><object data="https://a.cdn.site.example/a.pdf"></object>'
media_green green-srcset-relative '<img src="a.png" srcset="a.png, /b.png, ./c.png, ../d.png">'
media_green green-srcset-descriptors '<img src="a.png" srcset="a.png 1x, b.png 2x, c.png 200w, d.png 1.5x 300w"><picture><source srcset="a.webp 480w, b.webp 960w"></picture>'
media_green green-srcset-own '<img src="a.png" srcset="https://media.site.example/a.png 1x, https://a.cdn.site.example/b.png 2x">'
media_green green-srcset-data '<img src="a.png" srcset="data:image/gif;base64,R0lG,ODlh,AAAA 1x, b.png 2x">'
media_green green-srcset-data-url-inside '<img src="a.png" srcset="data:text/plain,https://other.example/x 1x">'
media_green green-srcset-data-last '<img src="a.png" srcset="a.png 1x, data:image/gif;base64,R0lG,ODlh">'
media_green green-srcset-parens '<img src="a.png" srcset="a.png 1x (note, https://other.example/b.png), c.png 2x">'
media_green green-srcset-newlines '<img src="a.png"
  srcset="a.png 1x,
          b.png 2x">'
media_green green-res-empty '<img src="a.png" srcset=""><audio></audio><track><embed><object></object><audio src></audio>'
media_green green-res-data-srcset "<img src=\"a.png\" data-srcset=\"${THIRD}.png 1x\"><audio data-src=\"${THIRD}.mp3\"></audio><object data-data=\"${THIRD}.pdf\"></object>"
media_green green-res-custom-tag "<audio-player src=\"${THIRD}.mp3\"></audio-player><object-view data=\"${THIRD}.pdf\"></object-view>"
media_green green-res-gt-attr '<audio title="a>b" src="a.mp3"></audio>'

# --- 25. the URL script missing: never a pass
R="$(mkroot urls-missing)"
rm "${R}/Scripts/check_privacy_posture_urls.mjs"
gate_in "$R" Site
want_exit "the URL script missing is exit 2, never a pass" 2 "check_privacy_posture_urls.mjs failed"

# userinfo_red <name> <html> [exceptions]: the html's URL is a finding for its
# user name or password.
userinfo_red() {
  gate_in "$(media_root "$1" "$2" "${3-$EXC_OWN}")" Site
  want_red "${1}: ${2} is red" "a resource from another host"
  want_said "${1}: the finding names the user name or password" "a user name or password"
}

EXC_ALLOWED="allowed.example|the host the user-info cases name
"

# --- 26. a user name or password in every resource attribute
userinfo_red ui-issue-password '<iframe src="https://allowed.example:x@other.example/"></iframe>' "$EXC_ALLOWED"
userinfo_red ui-issue-username '<iframe src="https://allowed.example@other.example/"></iframe>' "$EXC_ALLOWED"
userinfo_red ui-allowed-after '<iframe src="https://user@allowed.example/"></iframe>' "$EXC_ALLOWED"
n=0
for ui in 'media.site.example:x@other.example' 'media.site.example@other.example' 'user:secret@media.site.example'; do
  n=$((n + 1))
  userinfo_red "ui-${n}-iframe" "<iframe src=\"https://${ui}/e\"></iframe>"
  userinfo_red "ui-${n}-img" "<img src=\"https://${ui}/a.png\">"
  userinfo_red "ui-${n}-img-poster" "<img src=\"a.png\" poster=\"https://${ui}/p.jpg\">"
  userinfo_red "ui-${n}-img-srcset" "<img src=\"a.png\" srcset=\"https://${ui}/a.png 1x\">"
  userinfo_red "ui-${n}-img-srcset-later" "<img src=\"a.png\" srcset=\"a.png 1x, https://${ui}/b.png 2x\">"
  userinfo_red "ui-${n}-source" "<video><source src=\"https://${ui}/a.mp4\"></video>"
  userinfo_red "ui-${n}-source-poster" "<video><source src=\"a.mp4\" poster=\"https://${ui}/p.jpg\"></video>"
  userinfo_red "ui-${n}-source-srcset" "<picture><source srcset=\"a.webp 1x, https://${ui}/b.webp 2x\"></picture>"
  userinfo_red "ui-${n}-video" "<video src=\"https://${ui}/a.mp4\"></video>"
  userinfo_red "ui-${n}-poster" "<video src=\"a.mp4\" poster=\"https://${ui}/p.jpg\"></video>"
  userinfo_red "ui-${n}-audio" "<audio src=\"https://${ui}/a.mp3\"></audio>"
  userinfo_red "ui-${n}-track" "<track src=\"https://${ui}/a.vtt\">"
  userinfo_red "ui-${n}-embed" "<embed src=\"https://${ui}/a.swf\">"
  userinfo_red "ui-${n}-object" "<object data=\"https://${ui}/a.pdf\"></object>"
  userinfo_red "ui-${n}-script" "<script src=\"https://${ui}/a.js\"></script>"
  userinfo_red "ui-${n}-link" "<link rel=\"stylesheet\" href=\"https://${ui}/a.css\">"
  userinfo_red "ui-${n}-css-url" "<style>a{background:url(\"https://${ui}/a.png\")}</style>"
done
R="$(mkroot ui-css-file)"
printf 'a{background:url(//user@other.example/a.png)}\n' > "${R}/Site/a.css"
gate_in "$R" Site
want_red "a user name in a url() of a .css file is red" "a user name or password"

# --- 27. the same, however it is written
userinfo_red ui-upper '<IFRAME SRC="https://barcamp.io:x@other.example/e"></IFRAME>'
userinfo_red ui-lines '<iframe
  title="agenda"
  src="https://barcamp.io:x@other.example/e"></iframe>'
userinfo_red ui-tab-in-url "<iframe src=\"https://barcamp.io:x$(printf '\t')@other.example/e\"></iframe>"
userinfo_red ui-script-single "<script src='https://user@other.example/a.js'></script>"
userinfo_red ui-script-bare '<script src=https://user@other.example/a.js></script>'
userinfo_red ui-script-protorel '<script src="//user@other.example/a.js"></script>'
userinfo_red ui-script-scheme-relative '<script src="https:user@other.example/a.js"></script>'
userinfo_red ui-link-protorel "<link href='//user@other.example/a.css'>"
userinfo_red ui-ref-decimal '<iframe src="https://barcamp.io:x&#64;other.example/e"></iframe>'
userinfo_red ui-ref-hex '<iframe src="https://barcamp.io:x&#x40;other.example/e"></iframe>'
userinfo_red ui-ref-named '<iframe src="https://barcamp.io:x&commat;other.example/e"></iframe>'
userinfo_red ui-ref-script '<script src="https&#58;//user@other.example/a.js"></script>'
userinfo_red ui-css-bare '<style>a{background:url(//user@other.example/a.png)}</style>'
userinfo_red ui-css-single "<style>a{background:url('//user@other.example/a.png')}</style>"
userinfo_red ui-css-upper '<style>a{background:URL( "//user@other.example/a.png" )}</style>'
userinfo_red ui-css-escaped '<style>a{background:url("https\3a //user\40 other.example/a.png")}</style>'

# --- 28. no user-info: nothing else changed
media_green green-ui-iframe '<iframe src="https://barcamp.io/e"></iframe>'
media_green green-ui-iframe-port '<iframe src="https://barcamp.io:8443/e"></iframe>'
media_green green-ui-at-media '<img src="a@b.png"><img src="https://media.site.example/a@2x.png?u=a%40b"><video src="a@1.mp4" poster="p@1.jpg"><source src="s@1.mp4"></video>'
media_green green-ui-at-srcset '<img src="a.png" srcset="a@1x.png 1x, https://media.site.example/b@2x.png 2x, data:text/plain,a@b 3x">'
media_green green-ui-at-resources '<audio src="a@b.mp3"></audio><track src="t@1.vtt"><embed src="e@1.swf"><object data="o@1.pdf"></object>'
media_green green-ui-at-script '<script src="a.js?u=a@b"></script><link rel="stylesheet" href="/x@y.css">'
media_green green-ui-old-quotes "<script src='a.js'></script><link href=b.css>"
media_green green-ui-css '<style>a{background:url(a@b.png)}b{background:url("/c@d.png");mask:url(#m)}c{background:url(data:image/svg+xml,a@b)}</style>'
media_green green-ui-outbound '<a href="https://user@other.example/x">a link is not a resource</a>'
media_green green-ui-reference '<script src="a.js?x=1&#38;y=2"></script>'
media_green green-ui-never-closed '<link href="a.css"'
gate_in "$(media_root red-ui-script-own '<script src="https://media.site.example/a.js"></script>')" Site
want_red "an absolute script on an own host stays red" "a third-party asset is loaded"
gate_in "$(media_root red-ui-css-own '<style>a{background:url(https://media.site.example/a.png)}</style>')" Site
want_red "an absolute url() on an own host stays red" "a stylesheet fetches from another host"

# css_red <name> <css> [text]: the CSS is a finding in a <style> element and in
# a .css file, each saying the text (by default the planted host).
css_red() {
  local root
  resource_red "$1" "<style>$2</style>" "${3:-other.example}"
  root="$(mkroot "${1}-file" "$EXC_OWN")"
  printf '%s\n' "$2" > "${root}/Site/a.css"
  gate_in "$root" Site
  want_red "${1}: in a .css file: ${2} is red" "a resource from another host"
  want_said "${1}: in a .css file: the finding says ${3:-other.example}" "${3:-other.example}"
}

# css_green <name> <css>: the CSS passes in a <style> element and in a .css file.
css_green() {
  local root
  media_green "$1" "<style>$2</style>"
  root="$(mkroot "${1}-file" "$EXC_OWN")"
  printf '%s\n' "$2" > "${root}/Site/a.css"
  gate_in "$root" Site
  want_green_ok "${1}: in a .css file: ${2} is green"
}

IMPORT_UNREADABLE='an @import whose URL cannot be read'

# --- 29. CSS @import from another host, every way of writing the URL
css_red red-import-double "@import \"${THIRD}.css\";"
css_red red-import-single "@import '${THIRD}.css';"
css_red red-import-url-bare "@import url(${THIRD}.css);"
css_red red-import-url-double "@import url(\"${THIRD}.css\");"
css_red red-import-url-single "@import url('${THIRD}.css');"
css_red red-import-url-spaces "@import url(  \"${THIRD}.css\"  );"
css_red red-import-url-spaces-bare "@import url(  ${THIRD}.css  );"
css_red red-import-upper "@IMPORT URL(\"${THIRD}.css\");"
css_red red-import-no-space "@import\"${THIRD}.css\";"
css_red red-import-lines "@import
  \"${THIRD}.css\"
  ;"
css_red red-import-comment "@import/* a */\"${THIRD}.css\";"
css_red red-import-comment-after-url "@import url(\"${THIRD}.css\"/* b */);"
css_red red-import-media "@import \"${THIRD}.css\" screen and (min-width: 1px);"
css_red red-import-layer "@import url(${THIRD}.css) layer(a) supports(display: grid);"
css_red red-import-after-rule "a{color:red}@import \"${THIRD}.css\";"
css_red red-import-second "@import \"a.css\";@import \"${THIRD}.css\";"
css_red red-import-escaped-keyword "@\\69mport \"${THIRD}.css\";"
css_red red-import-escaped-url-name "@import u\\72l(${THIRD}.css);"
css_red red-import-escaped-colon '@import "https\3a //other.example/a.css";'
css_red red-import-escaped-bare '@import url(https\3a\2f\2fother.example/a.css);'
css_red red-import-escaped-char '@import "https:\/\/other.example/a.css";'
css_red red-import-continuation '@import "https://oth\
er.example/a.css";'
css_red red-import-backslashes '@import "\\\\other.example/a.css";' 'protocol-relative'
css_red red-import-protorel '@import "//other.example/a.css";' 'protocol-relative'
css_red red-import-own-protorel '@import "//media.site.example/a.css";' 'protocol-relative'
css_red red-import-http-own '@import "http://media.site.example/a.css";' 'not https'
css_red red-import-scheme '@import "ftp://media.site.example/a.css";' 'not https'
css_red red-import-data '@import "data:text/css,a{}";' 'not https'
css_red red-import-userinfo '@import "https://media.site.example:x@other.example/a.css";' 'a user name or password'
css_red red-import-userinfo-escaped '@import "https://user\40 media.site.example/a.css";' 'a user name or password'
css_red red-import-suffix '@import "https://media.site.example.other.example/a.css";'
css_red red-import-after-bad-url "a{background:url(x'y)}@import \"${THIRD}.css\";"
css_red red-import-after-bad-url-paren "a{background:url(x y)}@import \"${THIRD}.css\";"
gate_in "$(media_root red-import-url-own '<style>@import url(https://media.site.example/a.css);</style>')" Site
want_red "an absolute @import url() on an own host stays red, as every absolute url() is" "a stylesheet fetches from another host"

# --- 30. an @import nothing can read is a finding, never skipped
css_red red-import-no-url '@import;' "$IMPORT_UNREADABLE"
css_red red-import-end '@import' "$IMPORT_UNREADABLE"
css_red red-import-bare-word '@import a.css;' "$IMPORT_UNREADABLE"
css_red red-import-url-space '@import url (a.css);' "$IMPORT_UNREADABLE"
css_red red-import-url-comment '@import url/* a */(a.css);' "$IMPORT_UNREADABLE"
css_red red-import-comment-in-url "@import url(/* not a comment */\"${THIRD}.css\");" "$IMPORT_UNREADABLE"
css_red red-import-other-function '@import src("a.css");' "$IMPORT_UNREADABLE"
css_red red-import-two-strings '@import url("a.css" "b.css");' "$IMPORT_UNREADABLE"
css_red red-import-url-modifier '@import url("a.css" crossorigin);' "$IMPORT_UNREADABLE"
css_red red-import-bare-space '@import url(a b.css);' "$IMPORT_UNREADABLE"
css_red red-import-bare-quote '@import url(a"b.css);' "$IMPORT_UNREADABLE"
css_red red-import-bare-paren '@import url(a(b.css);' "$IMPORT_UNREADABLE"
css_red red-import-bare-newline '@import url(a\
b.css);' "$IMPORT_UNREADABLE"
css_red red-import-unclosed-url '@import url(a.css' "$IMPORT_UNREADABLE"
css_red red-import-unclosed-string '@import "a.css' "$IMPORT_UNREADABLE"
css_red red-import-newline-string '@import "a
.css";' "$IMPORT_UNREADABLE"
resource_red red-style-never-closed '<style media="a' 'not a complete tag'
resource_red red-style-reference "<svg><style>&#64;import \"${THIRD}.css\";</style></svg>" 'inside a style element'
resource_red red-style-named-reference "<svg><style>@import \"https&colon;//other.example/a.css\";</style></svg>" 'inside a style element'
resource_red red-style-quot "<svg><style>a{content:\"&quot}@import \"${THIRD}.css\";b{content:\"&quot}</style></svg>" 'inside a style element'
resource_red red-style-comment "<svg><style><!-- /* --> @import \"${THIRD}.css\";</style></svg>" 'inside a style element'
resource_red red-style-markup "<svg><style>@im<b></b>port \"${THIRD}.css\";</style></svg>" 'inside a style element'
resource_red red-style-after-style-in-comment "<!-- <style>/* --><style>@import \"${THIRD}.css\";</style>"

# --- 31. what an @import passes, and what only looks like one
css_green green-import-relative '@import "a.css";@import '"'"'/b.css'"'"';@import url(c.css);@import url("./d.css");@import url( '"'"'../e.css'"'"' );'
css_green green-import-own '@import "https://media.site.example/a.css";@import "https://a.cdn.site.example/b.css";'
css_green green-import-media '@import "a.css" screen and (min-width: 1px);@import url(b.css) layer(a);'
css_green green-import-escaped-url-name '@import u\72l(a.css);'
css_green green-import-escaped-value '@import "a\62.css";@import url(a\ b.css);'
css_green green-import-comment-between '@import/* a */"a.css"/* b */;'
css_green green-import-amp '@import "a.css?x=1&y=2";@import url(b.css?x=1&y=2);'
css_green green-import-at '@import "a@2x.css";'
css_green green-import-in-comment "/* @import \"${THIRD}.css\"; */a{color:red}"
css_green green-import-unclosed-comment "a{color:red}/* @import \"${THIRD}.css\";"
css_green green-import-in-string "a{content:\"@import '${THIRD}.css';\"}b{content:'@import \"${THIRD}.css\";'}"
css_green green-import-in-string-quote "a{content:\"\\\"@import '${THIRD}.css'\"}"
css_green green-import-in-url 'a{background:url(a@import.png)}'
css_green green-import-longer-name "@importance \"${THIRD}.css\";"
css_green green-import-escaped-at "\\40 import \"${THIRD}.css\";"
css_green green-import-other-at '@charset "utf-8";@font-face{font-family:x;src:url(a.woff2)}@media screen{a{color:red}}'
media_green green-import-outside-style "<p>@import \"${THIRD}.css\";</p><img src=\"a.png\" alt=\"@import '${THIRD}.css';\">"
media_green green-import-style-tag-like "<style-sheet>@import \"${THIRD}.css\";</style-sheet>"
media_green green-style-nesting '<style>a{&:hover{color:red}&.b{color:blue}}</style>'
media_green green-style-less-than '<style>@media (width<600px){a{content:"<"}}</style>'
media_green green-style-amp-entity '<style>@import "a.css?x=1&amp;y=2";</style>'
media_green green-style-after-close "<style>a{}</style><p>@import \"${THIRD}.css\";</p>"
R="$(media_root green-css-file-reference '')"
printf '@import "a&#46;css";\na{content:"<b>"}\n' > "${R}/Site/a.css"
gate_in "$R" Site
want_green_ok "a .css file is CSS, not HTML: a reference and markup in it mean nothing"

# --- 32. input type=image, however it is written
resource_red red-input "<input type=\"image\" src=\"${THIRD}.png\" alt=\"go\">"
resource_red red-input-upper "<input type=\"IMAGE\" src=\"${THIRD}.png\">"
resource_red red-input-mixed "<INPUT TYPE=\"ImAgE\" SRC=\"${THIRD}.png\">"
resource_red red-input-bare-type "<input type=image src=\"${THIRD}.png\">"
resource_red red-input-single-type "<input type='image' src=\"${THIRD}.png\">"
resource_red red-input-reference-type "<input type=\"&#105;mage\" src=\"${THIRD}.png\">"
resource_red red-input-src-first "<input src=\"${THIRD}.png\" type=\"image\">"
resource_red red-input-lines "<input
  type=\"image\"
  src=\"${THIRD}.png\">"
resource_red red-input-self-closed "<input type=\"image\" src=\"${THIRD}.png\"/>"
resource_red red-input-gt-attr "<input alt=\"a>b\" type=\"image\" src=\"${THIRD}.png\">"
resource_red red-input-twice "<input type=\"image\" src=\"a.png\" src=\"${THIRD}.png\">"
resource_red red-input-unquoted "<input type=\"image\" src=${THIRD}.png>"
resource_red red-input-single-src "<input type=\"image\" src='${THIRD}.png'>"
resource_red red-input-own-unquoted '<input type="image" src=https://media.site.example/a.png>' 'not double-quoted'
resource_red red-input-protorel '<input type="image" src="//other.example/a.png">' 'protocol-relative'
resource_red red-input-http-own '<input type="image" src="http://media.site.example/a.png">' 'not https'
resource_red red-input-backslash '<input type="image" src="\\other.example/a.png">' 'protocol-relative'
resource_red red-input-reference '<input type="image" src="https&#58;//other.example/a.png">' 'character reference'
resource_red red-input-userinfo '<input type="image" src="https://media.site.example:x@other.example/a.png">' 'a user name or password'
resource_red red-input-data '<input type="image" src="data:image/gif;base64,R0lG">' 'not https'
resource_red red-input-broken-url '<input type="image" src="https://[/a.png">' 'not a URL a browser can read'
resource_red red-input-never-closed "<input type=\"image\" src=\"${THIRD}.png" 'not a complete tag'
media_green green-input-relative '<input type="image" src="a.png" alt="go"><input type="IMAGE" src="/b.png"><input type=image src="./c.png">'
media_green green-input-own '<input type="image" src="https://media.site.example/a.png"><input type="image" src="https://a.cdn.site.example/b.png">'
media_green green-input-no-src '<input type="image"><input type="image" src>'
media_green green-input-other-type "<input src=\"${THIRD}.png\"><input type=\"text\" src=\"${THIRD}.png\"><input type src=\"${THIRD}.png\">"
media_green green-input-spaced-type "<input type=\" image\" src=\"${THIRD}.png\">"
media_green green-input-data-src "<input type=\"image\" src=\"a.png\" data-src=\"${THIRD}.png\">"
media_green green-input-custom-tag "<input-image type=\"image\" src=\"${THIRD}.png\"></input-image>"

# --- 33. SVG href and xlink:href, on every SVG element that takes one but <a>
for tag in image use feImage script linearGradient radialGradient pattern filter textPath tref altGlyph glyphRef cursor font-face-uri color-profile mpath animate animateMotion animateColor animateTransform set discard hatch; do
  resource_red "red-svg-href-${tag}" "<svg><${tag} href=\"${THIRD}.svg#a\"/></svg>"
  resource_red "red-svg-xlink-${tag}" "<svg><${tag} xlink:href=\"${THIRD}.svg#a\"/></svg>"
done
resource_red red-svg-upper "<svg><USE HREF=\"${THIRD}.svg#a\"/></svg>"
resource_red red-svg-xlink-upper "<svg><Image XLINK:HREF=\"${THIRD}.png\"/></svg>"
resource_red red-svg-lines "<svg><use
  x=\"0\"
  href=\"${THIRD}.svg#a\"/></svg>"
resource_red red-svg-twice "<svg><use href=\"#a\" xlink:href=\"${THIRD}.svg#a\"/></svg>"
resource_red red-svg-unquoted "<svg><use href=${THIRD}.svg#a></use></svg>"
resource_red red-svg-single "<svg><image xlink:href='${THIRD}.png'/></svg>"
resource_red red-svg-own-unquoted '<svg><use href=https://media.site.example/a.svg#a></use></svg>' 'not double-quoted'
resource_red red-svg-protorel '<svg><use href="//other.example/a.svg#a"/></svg>' 'protocol-relative'
resource_red red-svg-http-own '<svg><image href="http://media.site.example/a.png"/></svg>' 'not https'
resource_red red-svg-backslash '<svg><image href="\\other.example/a.png"/></svg>' 'protocol-relative'
resource_red red-svg-reference '<svg><use href="https&#58;//other.example/a.svg#a"/></svg>' 'character reference'
resource_red red-svg-reference-fragment '<svg><use href="&#35;a"/></svg>' 'character reference'
resource_red red-svg-userinfo '<svg><image xlink:href="https://media.site.example@other.example/a.png"/></svg>' 'a user name or password'
resource_red red-svg-data '<svg><image href="data:image/png;base64,AA"/></svg>' 'not https'
resource_red red-svg-broken-url '<svg><use href="https://[/a.svg#a"/></svg>' 'not a URL a browser can read'
resource_red red-svg-never-closed "<svg><use href=\"${THIRD}.svg#a" 'not a complete tag'
media_green green-svg-fragment '<svg><use href="#symbol-id"/><use xlink:href="#symbol-id"/><linearGradient href="#g"/><image href="#i"/><animate xlink:href="#a"/><textPath href="#p"></textPath></svg>'
media_green green-svg-relative '<svg><use href="sprite.svg#a"/><use xlink:href="/sprite.svg#a"/><image href="./a.png"/><image xlink:href="../a.png"/></svg>'
media_green green-svg-own '<svg><use href="https://media.site.example/a.svg#a"/><image xlink:href="https://a.cdn.site.example/b.png"/></svg>'
media_green green-svg-no-value '<svg><use/><use href/><image></image></svg>'
media_green green-svg-link "<svg><a href=\"${THIRD}\"><text>a</text></a><a xlink:href=\"${THIRD}\"><text>b</text></a></svg>"
media_green green-svg-data-href "<svg><use href=\"#a\" data-href=\"${THIRD}.svg\"/></svg>"
media_green green-svg-other-prefix "<svg><use href=\"#a\" other:href=\"${THIRD}.svg\"/></svg>"
media_green green-svg-custom-tag "<use-thing href=\"${THIRD}\"></use-thing><image-view href=\"${THIRD}\"></image-view>"

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

# The URL script finds this user name too, so it is weakened first: the proof is
# of the media check's own port rule.
R="$(media_root mut-userinfo '<img src="https://media.site.example:x@other.example/a.png">')"
if selftest_mutant "$URLS" "${R}/Scripts/check_privacy_posture_urls.mjs" "s/img: \['src', 'poster'\]/img: ['poster']/"; then
  selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
    's/(:\[0-9\]+)?/(:[^\/]*)?/' \
    "${R}/Site" \
    "anything allowed between the host and the path turns the userinfo case green" \
    "the copy without the port rule did not turn the userinfo case green"
fi

R="$(media_root mut-lines "<img
  src=\"${THIRD}.png\">")"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  "s/joined=\"${DOLLAR}(tr .*${DOLLAR}/joined=\"${DOLLAR}(cat \"${DOLLAR}file\")\"/" \
  "${R}/Site" \
  "the media tags read line by line turn the split tag green" \
  "the line-by-line copy did not turn the split tag green"

# urls_mutant_unsaid <name> <html> <sed> <ok text>: the gate's own media check
# keeps the fixture red with or without this script's finding, so the proof is
# that the finding names the rule, and is gone once the script is weakened.
urls_mutant_unsaid() {
  local root
  root="$(media_root "$1" "$2")"
  gate_in "$root" Site
  want_said "mutation proof: $1: the URL script names the rule" "a user name or password"
  if selftest_mutant "$URLS" "${root}/Scripts/check_privacy_posture_urls.mjs" "$3"; then
    gate_in "$root" Site
    if grep -qF "a user name or password" <<< "$OUT"; then
      fail "mutation proof: $1: the weakened URL script still names the rule. Output: $OUT"
    else
      echo "  ok: mutation proof: $4"
    fi
  fi
}

# urls_mutant_green <name> <html> <sed> <ok text>: the fixture is red, and turns
# green once the URL script is weakened, so it was red BECAUSE of that rule.
urls_mutant_green() {
  local root
  root="$(media_root "$1" "$2")"
  if selftest_mutant "$URLS" "${root}/Scripts/check_privacy_posture_urls.mjs" "$3"; then
    gate_in "$root" Site
    if [[ "$RC" -eq 0 ]]; then
      echo "  ok: mutation proof: $4"
    else
      fail "mutation proof: $1: the weakened URL script did not turn the case green (exit $RC). Output: $OUT"
    fi
  fi
}

# urls_mutant_red <name> <html> <sed> <ok text>: the fixture is green, and turns
# red once the URL script is weakened, so it was green BECAUSE of that rule.
urls_mutant_red() {
  local root
  root="$(media_root "$1" "$2")"
  if selftest_mutant "$URLS" "${root}/Scripts/check_privacy_posture_urls.mjs" "$3"; then
    gate_in "$root" Site
    want_red "mutation proof: $4" "a resource from another host"
  fi
}

urls_mutant_green mut-srcset-img "<img src=\"a.png\" srcset=\"${THIRD}.png 1x\">" \
  "s/img: \['srcset'\]/img: []/" "srcset dropped from img turns the third-party candidate green"
urls_mutant_green mut-srcset-source "<picture><source srcset=\"${THIRD}.webp\"></picture>" \
  "s/source: \['srcset'\]/source: []/" "srcset dropped from source turns the third-party candidate green"
urls_mutant_green mut-audio "<audio src=\"${THIRD}.mp3\"></audio>" \
  "s/audio: \['src'\]/audio: []/" "audio dropped turns the third-party audio src green"
urls_mutant_green mut-track "<track src=\"${THIRD}.vtt\">" \
  "s/track: \['src'\]/track: []/" "track dropped turns the third-party track src green"
urls_mutant_green mut-embed "<embed src=\"${THIRD}.swf\">" \
  "s/embed: \['src'\]/embed: []/" "embed dropped turns the third-party embed src green"
urls_mutant_green mut-object "<object data=\"${THIRD}.pdf\"></object>" \
  "s/object: \['data'\]/object: []/" "object dropped turns the third-party object data green"
urls_mutant_green mut-first-only "<img src=\"a.png\" srcset=\"a.png 1x, ${THIRD}.png 2x\">" \
  's/srcsetCandidateUrls(attribute.value)/srcsetCandidateUrls(attribute.value).slice(0, 1)/' \
  "judging only the first candidate turns the later candidate green"
urls_mutant_red mut-naive-split '<img src="a.png" srcset="data:text/plain,https://other.example/x 1x">' \
  's/srcsetCandidateUrls(attribute.value)/attribute.value.split(",")/' \
  "a srcset split on commas turns a valid data URL red"
urls_mutant_green mut-trailing-comma "<img src=\"a.png\" srcset=\"a.png, ${THIRD}.png\">" \
  "s/if (url.endsWith(',')) {/if (false) {/" \
  "a trailing comma that does not end the candidate turns the later candidate green"
urls_mutant_red mut-parens '<img src="a.png" srcset="a.png 1x (note, https://other.example/b.png), c.png 2x">' \
  "s/} else if (c === '(') {/} else if (false) {/" \
  "parentheses in a descriptor ignored turn the comma inside them into a candidate boundary"
urls_mutant_red mut-data-refused '<img src="a.png" srcset="data:image/gif;base64,R0lG,ODlh 1x">' \
  's/dataAllowed: true/dataAllowed: false/' "data URLs refused in a srcset turn the valid data URL red"
urls_mutant_green mut-data-everywhere '<embed src="data:text/html,hello">' \
  's/dataAllowed: false/dataAllowed: true/' "data URLs allowed everywhere turn the embed data URL green"
urls_mutant_red mut-res-relative '<audio src="a.mp3"></audio>' \
  's/BASE_TWO.host) return null/BASE_TWO.host) return "refused"/' "a copy that refuses relative paths turns the relative case red"
urls_mutant_red mut-res-own '<audio src="https://media.site.example/a.mp3"></audio>' \
  's/own.hosts.has(host)/false/' "a copy that ignores the own rows turns the own-host case red"
urls_mutant_green mut-res-nodot '<audio src="https://badcdn.site.example/a.mp3"></audio>' \
  "s/host.endsWith(\`.${DOLLAR}{suffix}\`)/host.endsWith(suffix)/" "a subdomain matched without its dot turns the lookalike green"
urls_mutant_green mut-res-userinfo '<audio src="https://user@media.site.example/a.mp3"></audio>' \
  "s/url.username !== '' || url.password !== ''/false/" "a URL with a user name allowed turns that case green"
urls_mutant_green mut-res-protorel '<audio src="//media.site.example/a.mp3"></audio>' \
  's/first.protocol !== second.protocol/false/' "the protocol-relative check dropped turns the own host green"
urls_mutant_green mut-res-quote '<audio src=https://media.site.example/a.mp3></audio>' \
  "s/attribute.quote !== '\"'/false/" "the quote rule dropped turns the unquoted own host green"
urls_mutant_green mut-res-charref '<audio src="https&#58;//other.example/a.mp3"></audio>' \
  "s/if (raw.replaceAll('&amp;', '').includes('&')) return/if (false) return/" "the character reference rule dropped turns that case green"
urls_mutant_green mut-res-count "<audio src=\"${THIRD}.mp3" \
  's/if (found !== total)/if (false)/' "the tag count dropped turns the tag never closed green"

urls_mutant_green mut-ui-iframe '<iframe src="https://barcamp.io:x@other.example/e"></iframe>' \
  "s/iframe: \['src'\]/iframe: []/" "iframe dropped from the user-info table turns the allowed name before the @ green"
urls_mutant_green mut-ui-script "<script src='https://user@other.example/a.js'></script>" \
  "s/script: \['src'\]/script: []/" "script dropped from the user-info table turns the single-quoted user name green"
urls_mutant_green mut-ui-link "<link href='//user@other.example/a.css'>" \
  "s/link: \['href'\]/link: []/" "link dropped from the user-info table turns the protocol-relative user name green"
urls_mutant_unsaid mut-ui-img-src '<img src="https://user@media.site.example/a.png">' \
  "s/img: \['src', 'poster'\]/img: ['poster']/" "img src dropped from the user-info table removes its finding"
urls_mutant_unsaid mut-ui-img-poster '<img src="a.png" poster="https://user@media.site.example/p.jpg">' \
  "s/img: \['src', 'poster'\]/img: ['src']/" "img poster dropped from the user-info table removes its finding"
urls_mutant_unsaid mut-ui-video-src '<video src="https://user@media.site.example/a.mp4"></video>' \
  "s/video: \['src', 'poster'\]/video: ['poster']/" "video src dropped from the user-info table removes its finding"
urls_mutant_unsaid mut-ui-video-poster '<video src="a.mp4" poster="https://user@media.site.example/p.jpg"></video>' \
  "s/video: \['src', 'poster'\]/video: ['src']/" "video poster dropped from the user-info table removes its finding"
urls_mutant_unsaid mut-ui-source-src '<video><source src="https://user@media.site.example/a.mp4"></video>' \
  "s/source: \['src', 'poster'\]/source: ['poster']/" "source src dropped from the user-info table removes its finding"
urls_mutant_unsaid mut-ui-source-poster '<video><source src="a.mp4" poster="https://user@media.site.example/p.jpg"></video>' \
  "s/source: \['src', 'poster'\]/source: ['src']/" "source poster dropped from the user-info table removes its finding"
urls_mutant_green mut-ui-css '<style>a{background:url(//user@other.example/a.png)}</style>' \
  's/text.matchAll(CSS_URL)/[]/' "CSS url() no longer read turns its user name green"
urls_mutant_green mut-ui-srcset '<img src="a.png" srcset="https://user@media.site.example/a.png 1x">' \
  "s/url.username !== '' || url.password !== ''/false/" "a user name in a srcset candidate allowed turns that case green"
urls_mutant_green mut-ui-references '<iframe src="https://barcamp.io:x&#64;other.example/e"></iframe>' \
  's/const value = decodeReferences(raw);/const value = raw;/' "character references not read turn the spelled-out @ green"
urls_mutant_green mut-ui-css-escapes '<style>a{background:url("https\3a //user\40 other.example/a.png")}</style>' \
  's/unescapeCss(match/(match/' "CSS escapes not read turn the escaped user name green"
urls_mutant_green mut-ui-one-base '<script src="https:user@other.example/a.js"></script>' \
  's/\[BASE_ONE, BASE_TWO\]\.some/[BASE_ONE].some/' "only the https base asked turns the scheme-relative user name green"
urls_mutant_red mut-ui-host-judged '<iframe src="https://barcamp.io/e"></iframe>' \
  's/if (!hostJudged) return null;//' "the host policy applied to the user-info tags turns the allowed iframe red"
urls_mutant_red mut-ui-never-closed '<link href="a.css"' \
  's/if (tag === null) continue;/if (tag === null) { lines.push(file); continue; }/' "a never-closed user-info tag counted turns the green case red"

R="$(mkroot mut-import-css-file "$EXC_OWN")"
printf '@import "%s.css";\n' "$THIRD" > "${R}/Site/a.css"
if selftest_mutant "$URLS" "${R}/Scripts/check_privacy_posture_urls.mjs" "s/file.endsWith('.css')/false/"; then
  gate_in "$R" Site
  if [[ "$RC" -eq 0 ]]; then
    echo "  ok: mutation proof: a .css file no longer read for @import turns its third-party import green"
  else
    fail "mutation proof: mut-import-css-file: the weakened URL script did not turn the case green (exit $RC). Output: $OUT"
  fi
fi
urls_mutant_green mut-import-style "<style>@import \"${THIRD}.css\";</style>" \
  's/const open = tagOpening(STYLE_TAG);/return lines;/' "a style element no longer read turns its third-party import green"
urls_mutant_red mut-import-comment "<style>/* @import \"${THIRD}.css\"; */</style>" \
  's/!css.startsWith(CSS_COMMENT_OPEN, pos)/true/' "CSS comments no longer skipped turn a commented import red"
urls_mutant_red mut-import-string "<style>a{content:\"@import '${THIRD}.css';\"}</style>" \
  's/pos = cssString(css, pos).end;/pos += 1;/' "CSS strings no longer skipped turn a quoted import red"
urls_mutant_green mut-import-keyword "<style>@\\69mport \"${THIRD}.css\";</style>" \
  's/value: unescapeCss(found\[0\])/value: found[0]/' "escapes in a CSS name not read turn the escaped @import green"
urls_mutant_green mut-import-value '<style>@import "https\3a //other.example/a.css";</style>' \
  's/text: unescapeCss(found\[1\])/text: found[1]/' "escapes in a CSS string not read turn the escaped URL green"
urls_mutant_green mut-import-bare-value '<style>@import url(https\3a\2f\2fother.example/a.css);</style>' \
  's/url: unescapeCss(found\[0\])/url: found[0]/' "escapes in a bare url() not read turn the escaped URL green"
urls_mutant_green mut-import-unreadable '<style>@import a.css;</style>' \
  's/if (item.url === null) {/if (item.url === null) continue; if (false) {/' "an @import nothing can read skipped turns that case green"
urls_mutant_green mut-import-bad-url "<style>a{background:url(x'y)}@import \"${THIRD}.css\";</style>" \
  's/pos = isCssUrl(css, name) ? cssUrlValue(css, name.end + 1).end : name.end;/pos = name.end;/' "a url() token no longer read whole lets a stray quote hide the next import"
urls_mutant_red mut-import-amp '<style>@import "a.css?x=1&y=2";</style>' \
  "s/item.url.replaceAll('&', '\&amp;')/item.url/" "an ampersand of CSS read as a character reference turns the plain query red"
urls_mutant_green mut-style-markup "<svg><style>&#64;import \"${THIRD}.css\";</style></svg>" \
  's/if (STYLE_NOT_CSS.test(body))/if (false)/' "a reference inside a style element allowed turns the spelled-out import green"
urls_mutant_green mut-style-overlap "<!-- <style>/* --><style>@import \"${THIRD}.css\";</style>" \
  's/const body = text.slice(tag.end, styleEnd(text, tag.end));/open.lastIndex = text.length; const body = text.slice(tag.end, styleEnd(text, tag.end));/' "a style element read past lets an earlier opening hide the next one"
urls_mutant_green mut-input "<input type=\"image\" src=\"${THIRD}.png\">" \
  "s/input: \['src'\]/input: []/" "input dropped turns the third-party image input green"
urls_mutant_green mut-input-case "<input type=\"IMAGE\" src=\"${THIRD}.png\">" \
  's/decodeReferences(attribute.value).toLowerCase()/decodeReferences(attribute.value)/' "the type read with its letter case turns the upper-case type green"
urls_mutant_green mut-input-reference "<input type=\"&#105;mage\" src=\"${THIRD}.png\">" \
  's/decodeReferences(attribute.value).toLowerCase()/attribute.value.toLowerCase()/' "references in the type not read turn the spelled-out type green"
urls_mutant_red mut-input-any-type "<input type=\"text\" src=\"${THIRD}.png\">" \
  's/if (READ_WHEN\[tagName\]?.(attributes) === false) return findings;//' "every input read turns a text input with a src red"
urls_mutant_green mut-svg-image "<svg><image href=\"${THIRD}.png\"/></svg>" \
  "s/'image', //" "image dropped turns the third-party image green"
urls_mutant_green mut-svg-use "<svg><use href=\"${THIRD}.svg#a\"/></svg>" \
  "s/'use', //" "use dropped turns the third-party use green"
urls_mutant_green mut-svg-feimage "<svg><feImage href=\"${THIRD}.png\"/></svg>" \
  "s/'feimage', //" "feImage dropped turns the third-party feImage green"
urls_mutant_green mut-svg-href "<svg><use href=\"${THIRD}.svg#a\"/></svg>" \
  "s/\['href', 'xlink:href'\]/['xlink:href']/" "href no longer read turns the third-party use green"
urls_mutant_green mut-svg-xlink "<svg><use xlink:href=\"${THIRD}.svg#a\"/></svg>" \
  "s/\['href', 'xlink:href'\]/['href']/" "xlink:href no longer read turns the third-party use green"
urls_mutant_red mut-svg-fragment '<svg><use href="#symbol-id"/></svg>' \
  's/BASE_TWO.host) return null/BASE_TWO.host) return "refused"/' "a local reference no longer passing turns the fragment red"

R="$(mkroot mut-urls-missing)"
rm "${R}/Scripts/check_privacy_posture_urls.mjs"
selftest_mutant_green "$GATE" "${R}/Scripts/check_privacy_posture.sh" \
  '/urls.mjs failed/{n;s/exit 2/:/;}' \
  "${R}/Site" \
  "a copy that carries on when the URL script fails turns case 25 green" \
  "the copy that ignores a failed URL script did not turn case 25 green"

selftest_end "privacy posture gate" "privacy posture gate proven on synthetic sites (iframes by host list, media by own host or relative path, srcset, audio, track, embed, object, CSS @import, image inputs and SVG references by the same policy, user names and passwords in every resource attribute, malformed and missing exceptions red, seventy-three weakened copies caught, links true for a split anchor)"
