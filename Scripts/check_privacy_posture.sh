#!/usr/bin/env bash
# canon: check_privacy_posture v4
# v4 (forsgren#654, step 2): srcset on img and source (every candidate, parsed the WHATWG way), audio src, track src, embed src and object data are judged under the same host policy, by Scripts/check_privacy_posture_urls.mjs; the checks of v3 are unchanged, and the header now states what a static check cannot see
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_site_settings.sh
source Scripts/lib_site_settings.sh

# check_privacy_posture.sh — does this site collect anything?
#
# The canon version, byte-identical across the estate's repositories
# Per-repo values live in data: the site directory in
# Scripts/site_settings.txt, the allowed embeds in
# Scripts/privacy_posture_exceptions.txt.
#
# WHY. A gate order file may declare the privacy pages n/a on the grounds that
# nothing is collected: no forms, no analytics, no cookies, no third-party
# assets, fonts served from this repo. That is true the day it is written.
# Nothing else stops a Google Fonts link or an analytics snippet arriving the
# next day and leaving a false exemption on the record. An exemption nothing
# enforces is a belief, and this gate re-proves the claim every run.
#
# It asserts something narrower than a check of a privacy page's CONTENT: that
# the WEBSITE itself collects nothing. Both can be true, and both should be
# checked: a correct privacy page says nothing about a tracking script somebody
# adds to the site.
#
# EMBEDS. An iframe loads from another party on page view, before any click, so
# it is a finding UNLESS its host is a row of Scripts/privacy_posture_exceptions.txt.
# One row per host: `host|reason`, the reason required (what the embed is and
# where it is documented). There is no blanket rule: a page that documents one
# embed does not thereby allow another. A repository with no embed keeps the
# file with comments only. The file is read on every run and its absence is red:
# a gate that skips its allow-list when the file is gone has no allow-list.
# Only an exact host with an https double-quoted src is matched; a relative,
# protocol-relative, unquoted or missing src is a finding.
#
# MEDIA. An img, video or source loads on page view just as an iframe does, and
# so does a poster. Each src and poster of those tags, in any letter case and
# over any number of lines, is a finding unless it is a double-quoted relative
# path or an https URL on one of the site's OWN hosts. Unquoted, single-quoted,
# protocol-relative, backslashed or http values are findings, as they are for an
# iframe, and so is a value with a character reference other than &amp;. A tag
# with neither attribute loads nothing by them and is no finding.
# OWN HOSTS are data, rows of the same exceptions file, kept apart from the
# embeds so that neither allows the other: `own:host|reason` is that exact host,
# `own:*.host|reason` every subdomain of it and not the host itself, which needs
# its own row. A file with no own row allows relative paths only; a missing file
# is exit 2, like any run without its allow-list.
#
# RESOURCES. A srcset on an img or source, an audio src, a track src, an embed
# src and an object data load on page view too, under the same policy: a
# double-quoted relative path or https on an own host passes. A srcset is a list:
# every candidate URL is judged, a later one as much as the first, and a data URL
# in a candidate passes, since it contacts no host (it does not pass anywhere
# else: an embed or object could run a data: document). Node reads these, in
# Scripts/check_privacy_posture_urls.mjs: the WHATWG srcset algorithm, because a
# data URL holds commas, and the WHATWG URL parser for the host. A run in which
# that script cannot finish is exit 2, never a pass.
#
# THE BOUNDARY OF THIS CHECK. It reads static HTML and CSS. It cannot guarantee
# that JavaScript will never start a request to a third party: a script can build
# a URL at run time and no static reading sees it. That guarantee needs runtime
# network monitoring, and this gate does not give it.
#
# WHAT IS DELIBERATELY NOT A FINDING: outbound links (ticketing, social
# platforms). A link transmits nothing until someone clicks it, and then they
# are plainly somewhere else. What matters is what the page loads or stores
# WITHOUT being asked, which is also why a third-party font stylesheet IS a
# finding: it sends every visitor's IP before anything is clicked, and it looks
# exactly like a local style link.
#
# Exit: 0 clean, 1 finding, 2 target, settings or exceptions file missing or
# malformed.
# Usage: check_privacy_posture.sh [site-dir [exceptions-file]]
#   site-dir default: site_dir in Scripts/site_settings.txt

if [ $# -ge 1 ]; then
  SITE="$1"
else
  SITE="$(site_settings_get Scripts/site_settings.txt site_dir)" || exit 2
fi
EXCEPTIONS="${2:-Scripts/privacy_posture_exceptions.txt}"

if [ ! -d "$SITE" ]; then
  echo "privacy-posture: site dir not found: $SITE" >&2
  exit 2
fi

# The allow-list is read and validated first, on every run, even with no
# iframe on the site: a malformed or missing file is red, never skipped.
if [ ! -f "$EXCEPTIONS" ]; then
  echo "privacy-posture: exceptions file not found: $EXCEPTIONS" >&2
  exit 2
fi
allowed_hosts=" "
own_hosts=" "
own_suffixes=" "
n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  case "$line" in '' | '#'*) continue ;; esac
  case "$line" in
    own:*)
      if ! [[ "$line" =~ ^own:(\*\.)?([A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*)\|[^[:space:]].*$ ]]; then
        echo "privacy-posture: malformed row ${n} in ${EXCEPTIONS} (want own:host|reason or own:*.host|reason, the reason required): ${line}" >&2
        exit 2
      fi
      wild="${BASH_REMATCH[1]}"
      host="$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]')"
      if [ -n "$wild" ]; then
        case "$own_suffixes" in
          *" ${host} "*) echo "privacy-posture: duplicate host '*.${host}' (row ${n} of ${EXCEPTIONS})" >&2; exit 2 ;;
        esac
        own_suffixes="${own_suffixes}${host} "
      else
        case "$own_hosts" in
          *" ${host} "*) echo "privacy-posture: duplicate host 'own:${host}' (row ${n} of ${EXCEPTIONS})" >&2; exit 2 ;;
        esac
        own_hosts="${own_hosts}${host} "
      fi
      continue
      ;;
  esac
  if ! [[ "$line" =~ ^([A-Za-z0-9.-]+)\|[^[:space:]].*$ ]]; then
    echo "privacy-posture: malformed row ${n} in ${EXCEPTIONS} (want host|reason, the reason required): ${line}" >&2
    exit 2
  fi
  host="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
  case "$allowed_hosts" in
    *" ${host} "*) echo "privacy-posture: duplicate host '${host}' (row ${n} of ${EXCEPTIONS})" >&2; exit 2 ;;
  esac
  allowed_hosts="${allowed_hosts}${host} "
done < "$EXCEPTIONS"

findings=0

report() {
  # report <what> <why> <matches>
  echo "FINDING: $1" >&2
  echo "  $2" >&2
  printf '%s\n' "$3" | sed 's/^/    /' >&2
  findings=$((findings + 1))
}

scan() {
  # scan <pattern> — HTML and CSS, filenames included so a finding is locatable
  grep -rInE "$1" "$SITE" --include='*.html' --include='*.css' 2>/dev/null || true
}

hits="$(scan '<form[[:space:]>]')"
[ -n "$hits" ] && report "a form collects input" \
  "A form makes this site a collector. The n/a in gate_report_order.txt says it is not." "$hits"

# iframe_unlisted: one line per iframe tag whose src host is not allowed, as
# `file: tag`. The tag is read across line breaks (the src is often on the line
# after `<iframe`), and a file with an `<iframe` that no complete tag explains is
# reported whole.
iframe_unlisted() {
  local file tags tag host total found
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    tags="$(tr '\n\r' '  ' < "$file" | grep -oiE '<iframe[^>]*>' || true)"
    total="$(grep -oi '<iframe' "$file" | wc -l | tr -d ' ')"
    found=0
    while IFS= read -r tag; do
      [ -n "$tag" ] || continue
      found=$((found + 1))
      host="$(printf '%s' "$tag" | sed -nE 's#.*[[:space:]]src[[:space:]]*=[[:space:]]*"https://([A-Za-z0-9.-]+)([/:?#"].*)?$#\1#p' | tr '[:upper:]' '[:lower:]')"
      case "$allowed_hosts" in
        *" ${host:-none} "*) [ -n "$host" ] && continue ;;
      esac
      echo "${file}: ${tag}"
    done <<< "$tags"
    if [ "$found" -ne "$total" ]; then
      echo "${file}: an <iframe that is not a complete tag"
    fi
  done < <(grep -rIil '<iframe' "$SITE" --include='*.html' --include='*.css' 2>/dev/null | sort)
}

hits="$(iframe_unlisted)"
[ -n "$hits" ] && report "an embedded third party" \
  "An iframe loads from another party on page view, before any click. Allowed only for a host listed with a reason in ${EXCEPTIONS}." "$hits"

# The tags media_unlisted reads, in one place.
MEDIA_TAGS='img|video|source'

# host_is_own <lower-case host>
host_is_own() {
  local suffix
  case "$own_hosts" in
    *" $1 "*) return 0 ;;
  esac
  for suffix in $own_suffixes; do
    case "$1" in
      ?*".${suffix}") return 0 ;;
    esac
  done
  return 1
}

# media_value_ok <value>: a relative path, or https on an own host. A browser
# drops white space around and inside a URL and reads a backslash as a slash,
# so this does too before it decides what is relative.
media_value_ok() {
  local value="${1//[[:space:]]/}" re_https='^https://([A-Za-z0-9.-]+)(:[0-9]+)?([/?#].*)?$' re_scheme='^[A-Za-z][A-Za-z0-9+.-]*:'
  case "${value//&amp;/}" in
    *'&'*) return 1 ;;
  esac
  case "$value" in
    //* | \\* | /\\*) return 1 ;;
  esac
  [[ "$value" =~ $re_scheme ]] || return 0 # a relative path
  [[ "$value" =~ $re_https ]] || return 1
  host_is_own "$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
}

# media_tag_ok <tag>: 0 when every src and poster of the tag passes. It walks
# the attributes, so data-src, or src="..." inside another attribute's value,
# is not read as src; an attribute given twice is judged both times.
media_tag_ok() {
  local rest name value re_name='^<[A-Za-z]+' re_bare='^[^[:space:]=/>]+'
  local re_attr='^([^[:space:]=/>]+)[[:space:]]*=[[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]>]*)'
  [[ "$1" =~ $re_name ]] || return 1
  rest="${1:${#BASH_REMATCH[0]}}"
  while :; do
    rest="${rest#"${rest%%[![:space:]/]*}"}"
    case "$rest" in
      '' | '>'*) return 0 ;;
    esac
    if [[ "$rest" =~ $re_attr ]]; then
      value="${BASH_REMATCH[2]}"
      name="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
      rest="${rest:${#BASH_REMATCH[0]}}"
      case "$name" in
        src|poster)
          case "$value" in
            '"'*'"') media_value_ok "${value:1:${#value}-2}" || return 1 ;;
            *) return 1 ;;
          esac
          ;;
      esac
    elif [[ "$rest" =~ $re_bare ]]; then
      rest="${rest:${#BASH_REMATCH[0]}}"
    else
      return 1
    fi
  done
}

# media_unlisted: one line per media tag that fails, as `file: tag`. Like the
# iframes, the tag is read across line breaks and a file with a media tag no
# complete tag explains is reported whole. The tag pattern knows quotes, so a
# > inside an attribute value does not end the tag early.
media_unlisted() {
  local file joined tags tag total found
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    joined="$(tr '\n\r\t' '   ' < "$file")"
    tags="$(grep -oiE "<(${MEDIA_TAGS})([[:space:]/]([^>\"']|\"[^\"]*\"|'[^']*')*)?>" <<< "$joined" || true)"
    total="$(grep -oiE "<(${MEDIA_TAGS})[[:space:]/>]" <<< "$joined" | wc -l | tr -d ' ')"
    found=0
    while IFS= read -r tag; do
      [ -n "$tag" ] || continue
      found=$((found + 1))
      media_tag_ok "$tag" || echo "${file}: ${tag}"
    done <<< "$tags"
    if [ "$found" -ne "$total" ]; then
      echo "${file}: a media tag that is not a complete tag"
    fi
  done < <(grep -rIilE "<(${MEDIA_TAGS})([[:space:]/>]|\$)" "$SITE" --include='*.html' --include='*.css' 2>/dev/null | sort)
}

hits="$(media_unlisted)"
[ -n "$hits" ] && report "media from another host" \
  "An image, video or poster from another host sends every visitor's IP there on page view. Only a double-quoted relative path or an https URL on a host declared own:host|reason in ${EXCEPTIONS} passes." "$hits"

# The files the URL script reads: all of the site's HTML and CSS, as the scans
# above. It always runs, so a machine without Node is red on any site.
resource_files="$(find "$SITE" -type f \( -name '*.html' -o -name '*.css' \) 2>/dev/null | sort)"
hits="$(node Scripts/check_privacy_posture_urls.mjs "$own_hosts" "$own_suffixes" <<< "$resource_files")"
urls_rc=$?
if [ "$urls_rc" -ne 0 ]; then
  echo "privacy-posture: Scripts/check_privacy_posture_urls.mjs failed (exit ${urls_rc}), so srcset, audio, track, embed and object were not judged" >&2
  exit 2
fi
[ -n "$hits" ] && report "a resource from another host" \
  "A srcset candidate, audio, track, embed or object from another host sends every visitor's IP there on page view. Only a double-quoted relative path or an https URL on a host declared own:host|reason in ${EXCEPTIONS} passes (and, in a srcset, a data URL)." "$hits"

hits="$(scan '<(script|link)[^>]+(src|href)="https?://')"
[ -n "$hits" ] && report "a third-party asset is loaded" \
  "A script or stylesheet from another host sends every visitor's IP there on page view. Self-host it, as the fonts in this repo are." "$hits"

hits="$(scan 'url\([\"'"'"']?https?://')"
[ -n "$hits" ] && report "a stylesheet fetches from another host" \
  "An @font-face or background url() pointing off-site transmits on render." "$hits"

hits="$(scan 'document\.cookie|localStorage|sessionStorage')"
[ -n "$hits" ] && report "cookies or browser storage" \
  "Storing anything on the visitor's device is exactly what the exemption says this site does not do." "$hits"

hits="$(scan 'gtag\(|googletagmanager|google-analytics|matomo|plausible\.io|hotjar|segment\.(io|com)|clarity\.ms')"
[ -n "$hits" ] && report "an analytics or tracking snippet" \
  "Inline analytics carries no src attribute, so it hides from the third-party-asset check above." "$hits"

if [ "$findings" -ne 0 ]; then
  echo "" >&2
  echo "privacy-posture: ${findings} finding(s) in ${SITE}." >&2
  echo "  The privacy pages row in Scripts/gate_report_order.txt says the website" >&2
  echo "  collects nothing beyond what ${EXCEPTIONS} lists. That is no longer" >&2
  echo "  true. Either remove the collection, or extend the privacy pages to say" >&2
  echo "  what is collected and by whom, and list a documented embed's host there." >&2
  exit 1
fi

# --- INFORMATION, not findings. None of the below fails the gate.
#
# "No third-party assets" is a claim about an ABSENCE, and an absence is the
# hardest thing for a reader to check. Showing the fonts this repo serves and
# the hosts visitors are sent to makes the verdict inspectable rather than
# trusted — the same reason the duplication ratchet prints its percentage on a
# green run. It also means a NEW outbound destination shows up in the report
# the day it lands, without the gate having to decide whether it is acceptable.
echo ""
echo "INFO — what this site loads and where it points (none of this is a finding):"

font_files="$(find "$SITE" -type f \( -name '*.woff' -o -name '*.woff2' -o -name '*.otf' -o -name '*.ttf' -o -name '*.eot' \) 2>/dev/null | wc -l | tr -d ' ')"
font_faces="$(grep -rhoE '@font-face' "$SITE" --include='*.css' --include='*.html' 2>/dev/null | wc -l | tr -d ' ')"
echo "  fonts   ${font_faces} @font-face rule(s), ${font_files} font file(s) served from this repo"
echo "          (self-hosted: a font stylesheet from another host would send every"
echo "           visitor's IP there on page view, which is why that IS a finding)"

echo "  embeds  hosts allowed by ${EXCEPTIONS}:"
if [ "$allowed_hosts" = " " ]; then
  echo "            (none)"
else
  grep -vE '^(#|$|own:)' "$EXCEPTIONS" | sed 's/^/            /'
fi

echo "  media   the site's own hosts, from ${EXCEPTIONS} (anything else must be a relative path):"
if [ "$own_hosts$own_suffixes" = "  " ]; then
  echo "            (none)"
else
  grep -E '^own:' "$EXCEPTIONS" | sed -E 's/^own:/            /'
fi

echo "  links   outbound destinations visitors can choose to follow:"
# The HTML is joined into one line first: a formatter puts href on a later line
# than `<a`, and a line-by-line scan would miss that link and then print the
# false "links nowhere" below.
outbound="$(find "$SITE" -type f -name '*.html' -exec cat {} + 2>/dev/null \
  | tr '\n' ' ' \
  | grep -oE '<a[[:space:]][^>]*href="https?://[^"]+"' \
  | grep -oE 'https?://[a-zA-Z0-9.-]+' \
  | sed -E 's#https?://##' \
  | sort | uniq -c | sort -rn || true)"
if [ -z "$outbound" ]; then
  # An empty list must SAY it is empty. A header with nothing under it reads
  # as a rendering failure, and "no outbound links at all" is a real and
  # unusual property worth stating rather than leaving as whitespace.
  echo "            (none — this site links nowhere off itself)"
else
  printf '%s\n' "$outbound" | while read -r n host; do
    printf '            %-34s %s link(s)\n' "$host" "$n"
  done
fi

echo ""
echo "OK: privacy posture (no forms, no third-party assets, no cookies or storage, no analytics in ${SITE})"
exit 0
