#!/usr/bin/env bash
# Scripts/test_dependabot_config.sh
#
# The shape of .github/dependabot.yml (forsgren#86): forsgren's own. Dependabot
# opens version-update pull requests only for ecosystems this file names, so a
# missing file, a missing ecosystem or a wrong directory silently means no
# updates (the go1.27.1 to go1.27.2 question that started forsgren#86).
#
# Per ecosystem, gomod, github-actions and npm (the gate tooling in
# package.json and package-lock.json, forsgren#605), all at directory / :
#   1. the ecosystem is declared, with directory: /;
#   2. schedule: interval: cron with a cronjob and timezone UTC, so a
#      weekend release is seen too (interval daily runs Monday to Friday only);
#   3. commit-message with a prefix;
#   4. groups with at least one patterns: entry, so one release run does not
#      open several pull requests;
#   5. cooldown with default-days: 3 (the documented default, written out);
#   6. a comment line directly above schedule:, commit-message:, groups: and
#      cooldown:, one per choice;
#   7. npm only (forsgren#638): a group with the patterns stylelint and
#      stylelint-config-*, update-types major, minor and patch, placed before
#      every group with the pattern "*". stylelint-config-standard has a peer
#      range on stylelint's major, so the two majors must share one pull
#      request, and Dependabot puts a dependency in the first group it matches.
# Synthetic files show each broken shape red, with its reason, and the real
# file green. Mutation proofs: a judge that skips the comment check must accept
# the uncommented file, one that skips the cooldown check the file without it,
# one that skips the groups check the file without groups, one that skips the
# npm check the file without the npm entry, one that skips the order check the
# file with the stylelint group after npm-tooling, one that skips the
# update-types check the file whose stylelint group lacks major.

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "dependabot config self-test"

# judge_file <file> — prints one line per problem; none when the file is right.
judge_file() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "${f}: there is no dependabot.yml"
    return
  fi
  awk -v file="$f" -v skip="${SKIP:-}" '
    function skipped(w) { return index("," skip ",", "," w ",") > 0 }
    function iscomment(s) { return s ~ /^[[:space:]]*#/ }
    function hasword(s, w) { return s ~ ("(^|[^a-z])" w "([^a-z]|$)") }
    # The npm group for stylelint and stylelint-config-* (forsgren#638).
    function stylelint_group(   k, parts, g, sg) {
      sg = ""
      for (k in gorder) {
        split(k, parts, SUBSEP)
        if (parts[1] != "npm") continue
        g = parts[2]
        if (index(pats["npm", g], ",stylelint,") && index(pats["npm", g], ",stylelint-config-*,")) sg = g
      }
      if (sg == "") { print file ": npm: no group with the patterns stylelint and stylelint-config-*"; return }
      if (!skipped("major") && !(hasword(types["npm", sg], "major") && hasword(types["npm", sg], "minor") && hasword(types["npm", sg], "patch")))
        print file ": npm: the stylelint group " sg " does not cover the update types major, minor and patch"
      if (skipped("order")) return
      for (k in gorder) {
        split(k, parts, SUBSEP)
        if (parts[1] != "npm") continue
        g = parts[2]
        if (index(pats["npm", g], ",*,") && gorder["npm", g] < gorder["npm", sg])
          print file ": npm: the stylelint group " sg " comes after " g ", which takes stylelint first"
      }
    }
    function needcomment(key) {
      if (!skipped("comments") && !iscomment(prev))
        print file ": " eco ": no comment line directly above " key
    }
    /^  - package-ecosystem:/ {
      eco = $3; seen[eco] = 1; ingrp = 0; gname = ""; skey = ""
    }
    eco != "" && !iscomment($0) {
      if ($0 ~ /^    directory:/) dir[eco] = $2
      if ($0 ~ /^    schedule:/) { needcomment("schedule:"); sched[eco] = 1 }
      if ($0 ~ /^      interval:/) interval[eco] = $2
      if ($0 ~ /^      cronjob:/) cron[eco] = 1
      if ($0 ~ /^      timezone:/) tz[eco] = $2
      if ($0 ~ /^    commit-message:/) { needcomment("commit-message:"); cm[eco] = 1 }
      if ($0 ~ /^      prefix:/) prefix[eco] = 1
      if ($0 ~ /^    groups:/) { needcomment("groups:"); grp[eco] = 1 }
      if ($0 ~ /^        patterns:/) pat[eco] = 1
      if ($0 ~ /^    cooldown:/) { needcomment("cooldown:"); cd[eco] = 1 }
      if ($0 ~ /^      default-days:/) days[eco] = $2
      # Inside groups: a group name, its keys, and its patterns and
      # update-types (flow [a, b] or one per line).
      if ($0 ~ /^    [^ ]/) ingrp = ($0 ~ /^    groups:/)
      if (ingrp && $0 ~ /^      [^ ][^:]*:[[:space:]]*$/) {
        gname = $1; sub(/:$/, "", gname); gorder[eco, gname] = ++gcount[eco]; skey = ""
      }
      if (ingrp && $0 ~ /^        [^ ]/) {
        skey = $1; sub(/:.*/, "", skey)
        if (skey == "update-types") { t = $0; sub(/^ *update-types:/, "", t); types[eco, gname] = types[eco, gname] " " t }
      }
      if (ingrp && $0 ~ /^          - /) {
        v = $0; sub(/[[:space:]]+#.*/, "", v); sub(/^ *- */, "", v); gsub(/["\047]/, "", v)
        if (skey == "patterns") pats[eco, gname] = pats[eco, gname] "," v ","
        if (skey == "update-types") types[eco, gname] = types[eco, gname] " " v
      }
    }
    NF { prev = $0 }
    END {
      n = split("gomod github-actions npm", want, " ")
      for (i = 1; i <= n; i++) {
        e = want[i]
        if (skipped(e)) continue
        if (!seen[e]) { print file ": the " e " ecosystem is not declared"; continue }
        if (dir[e] != "/") print file ": " e ": directory is not /"
        if (interval[e] != "cron" || !cron[e] || tz[e] != "UTC")
          print file ": " e ": schedule is not interval: cron with a cronjob and timezone: UTC"
        if (!cm[e] || !prefix[e]) print file ": " e ": no commit-message prefix"
        if (!skipped("groups") && (!grp[e] || !pat[e])) print file ": " e ": no groups with patterns"
        if (!skipped("cooldown") && days[e] != "3") print file ": " e ": no cooldown with default-days: 3"
        if (e == "npm") stylelint_group()
      }
    }
  ' "$f"
}

# block <eco> <prefix> <dir> <comments:1|0> <groups> <cooldown:1|0> — one ecosystem entry.
# <groups>: 0 none; 1 one group for "*"; and for npm (forsgren#638) 2 the
# stylelint group then npm-tooling, 3 npm-tooling then the stylelint group,
# 4 the stylelint group without major, then npm-tooling.
block() {
  local c=""
  [[ "$4" == 1 ]] && c="    # a choice, explained"
  printf '  - package-ecosystem: %s\n    directory: %s\n' "$1" "$3"
  [[ -n "$c" ]] && printf '%s\n' "$c"
  printf '    schedule:\n      interval: cron\n      cronjob: "0 4 * * *"\n      timezone: UTC\n'
  [[ -n "$c" ]] && printf '%s\n' "$c"
  printf '    commit-message:\n      prefix: %s\n' "$2"
  if [[ "$5" != 0 ]]; then
    [[ -n "$c" ]] && printf '%s\n' "$c"
    printf '    groups:\n'
    case "$5" in
      1) printf '      all:\n        patterns:\n          - "*"\n' ;;
      2) stylelint_group "major, minor, patch"; tooling_group ;;
      3) tooling_group; stylelint_group "major, minor, patch" ;;
      4) stylelint_group "minor, patch"; tooling_group ;;
    esac
  fi
  if [[ "$6" == 1 ]]; then
    [[ -n "$c" ]] && printf '%s\n' "$c"
    printf '    cooldown:\n      default-days: 3\n'
  fi
}

# stylelint_group <update-types> / tooling_group — the npm groups of block.
stylelint_group() {
  printf '      stylelint:\n        patterns:\n          - "stylelint"\n          - "stylelint-config-*"\n        update-types: [%s]\n' "$1"
}
tooling_group() {
  printf '      npm-tooling:\n        patterns:\n          - "*"\n        update-types: [minor, patch]\n'
}

# synth <name> <block-args...> [-- <block-args...>]... — writes a file with one
# ecosystem entry per group of block arguments (an empty group writes none),
# sets WF.
synth() {
  local name="$1"; shift
  local args=()
  WF="${TMP}/${name}.yml"
  printf 'version: 2\nupdates:\n' > "$WF"
  for x in "$@" --; do
    if [[ "$x" != -- ]]; then args+=("$x"); continue; fi
    if [[ ${#args[@]} -gt 0 ]]; then block "${args[@]}" >> "$WF"; fi
    args=()
  done
}

# The npm entry, complete, for the cases that break another ecosystem.
NPM=(npm npm / 1 2 1)

# judge <file> — sets OUT and RC (1 when there are problems).
judge() {
  OUT="$(judge_file "$1")"
  if [[ -n "$OUT" ]]; then RC=1; else RC=0; fi
}

synth good gomod go / 1 1 1 -- github-actions actions / 1 1 1 -- "${NPM[@]}"
judge "$WF"
want_rc "1. the three ecosystems at /, cron schedule, prefix, groups, cooldown, comments is accepted" 0

judge "${TMP}/absent.yml"
want_red "2. no file" "there is no dependabot.yml"

synth nogomod -- github-actions actions / 1 1 1 -- "${NPM[@]}"
judge "$WF"
want_red "3. no gomod ecosystem" "the gomod ecosystem is not declared"

synth noactions gomod go / 1 1 1 -- -- "${NPM[@]}"
judge "$WF"
want_red "4. no github-actions ecosystem" "the github-actions ecosystem is not declared"

synth subdir gomod go /sub 1 1 1 -- github-actions actions / 1 1 1 -- "${NPM[@]}"
judge "$WF"
want_red "5. gomod at another directory" "gomod: directory is not /"

synth nocooldown gomod go / 1 1 0 -- github-actions actions / 1 1 1 -- "${NPM[@]}"
judge "$WF"
want_red "6. no cooldown" "gomod: no cooldown with default-days: 3"
COOLDOWN_WF="$WF"

synth nogroups gomod go / 1 1 1 -- github-actions actions / 1 0 1 -- "${NPM[@]}"
judge "$WF"
want_red "7. no groups" "github-actions: no groups with patterns"
GROUPS_WF="$WF"

synth nocomments gomod go / 0 1 1 -- github-actions actions / 0 1 1 -- "${NPM[@]}"
judge "$WF"
want_red "8. no comment above a choice" "gomod: no comment line directly above schedule:"
COMMENTS_WF="$WF"

# The schedule: daily skips weekends, so it is refused.
sed 's/interval: cron/interval: daily/' "${TMP}/good.yml" > "${TMP}/daily.yml"
judge "${TMP}/daily.yml"
want_red "9. interval daily instead of cron" "schedule is not interval: cron"

synth nonpm gomod go / 1 1 1 -- github-actions actions / 1 1 1
judge "$WF"
want_red "10. no npm ecosystem" "the npm ecosystem is not declared"
NPM_WF="$WF"

synth npmuncommented gomod go / 1 1 1 -- github-actions actions / 1 1 1 -- npm npm / 0 2 1
judge "$WF"
want_red "11. npm entry without a comment above a choice" "npm: no comment line directly above schedule:"

synth npmnostylelint gomod go / 1 1 1 -- github-actions actions / 1 1 1 -- npm npm / 1 1 1
judge "$WF"
want_red "12. npm without a stylelint group" "npm: no group with the patterns stylelint and stylelint-config-*"

synth npmafter gomod go / 1 1 1 -- github-actions actions / 1 1 1 -- npm npm / 1 3 1
judge "$WF"
want_red "13. the stylelint group after npm-tooling" "npm: the stylelint group stylelint comes after npm-tooling, which takes stylelint first"
ORDER_WF="$WF"

synth npmnomajor gomod go / 1 1 1 -- github-actions actions / 1 1 1 -- npm npm / 1 4 1
judge "$WF"
want_red "14. the stylelint group without major" "npm: the stylelint group stylelint does not cover the update types major, minor and patch"
MAJOR_WF="$WF"

# The real file.
judge .github/dependabot.yml
want_rc "15. .github/dependabot.yml has the three ecosystems with every choice commented, and the npm stylelint group" 0

# --- mutation proofs ----------------------------------------------------------
SKIP=comments judge "$COMMENTS_WF"
if [[ "$RC" -eq 0 ]]; then
  echo "  ok: mutation proof: without the comment check the uncommented file is accepted, so case 8 is red because of it"
else
  fail "mutation proof: the comment-blind judge still refused the uncommented file. Output: ${OUT}"
fi
SKIP=cooldown judge "$COOLDOWN_WF"
if [[ "$RC" -eq 0 ]]; then
  echo "  ok: mutation proof: without the cooldown check a file with no cooldown is accepted, so case 6 is red because of it"
else
  fail "mutation proof: the cooldown-blind judge still refused the file. Output: ${OUT}"
fi
SKIP=groups judge "$GROUPS_WF"
if [[ "$RC" -eq 0 ]]; then
  echo "  ok: mutation proof: without the groups check a file with no groups is accepted, so case 7 is red because of it"
else
  fail "mutation proof: the groups-blind judge still refused the file. Output: ${OUT}"
fi

SKIP=npm judge "$NPM_WF"
if [[ "$RC" -eq 0 ]]; then
  echo "  ok: mutation proof: without the npm check a file with no npm entry is accepted, so case 10 is red because of it"
else
  fail "mutation proof: the npm-blind judge still refused the file. Output: ${OUT}"
fi

SKIP=order judge "$ORDER_WF"
if [[ "$RC" -eq 0 ]]; then
  echo "  ok: mutation proof: without the order check the stylelint group after npm-tooling is accepted, so case 13 is red because of it"
else
  fail "mutation proof: the order-blind judge still refused the file. Output: ${OUT}"
fi
SKIP=major judge "$MAJOR_WF"
if [[ "$RC" -eq 0 ]]; then
  echo "  ok: mutation proof: without the update-types check the stylelint group without major is accepted, so case 14 is red because of it"
else
  fail "mutation proof: the update-types-blind judge still refused the file. Output: ${OUT}"
fi

selftest_end "the dependabot config does not hold" \
  "dependabot config: gomod, github-actions and npm at /, cron schedule, commit-message prefix, groups, cooldown and a comment per choice, npm with stylelint and stylelint-config-* in one group for every update type before npm-tooling; each broken shape is red; mutation proven"
