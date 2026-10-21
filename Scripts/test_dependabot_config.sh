#!/usr/bin/env bash
# Scripts/test_dependabot_config.sh
#
# The shape of .github/dependabot.yml (forsgren#86): forsgren's own. Dependabot
# opens version-update pull requests only for ecosystems this file names, so a
# missing file, a missing ecosystem or a wrong directory silently means no
# updates (the go1.27.1 to go1.27.2 question that started forsgren#86).
#
# Per ecosystem, gomod and github-actions, both at directory / :
#   1. the ecosystem is declared, with directory: /;
#   2. schedule: interval: cron with a cronjob and timezone UTC, so a
#      weekend release is seen too (interval daily runs Monday to Friday only);
#   3. commit-message with a prefix;
#   4. groups with at least one patterns: entry, so one release run does not
#      open several pull requests;
#   5. cooldown with default-days: 3 (the documented default, written out);
#   6. a comment line directly above schedule:, commit-message:, groups: and
#      cooldown:, one per choice.
# Synthetic files show each broken shape red, with its reason, and the real
# file green. Mutation proofs: a judge that skips the comment check must accept
# the uncommented file, one that skips the cooldown check the file without it,
# one that skips the groups check the file without groups.

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
    function needcomment(key) {
      if (!skipped("comments") && !iscomment(prev))
        print file ": " eco ": no comment line directly above " key
    }
    /^  - package-ecosystem:/ {
      eco = $3; seen[eco] = 1
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
    }
    NF { prev = $0 }
    END {
      n = split("gomod github-actions", want, " ")
      for (i = 1; i <= n; i++) {
        e = want[i]
        if (!seen[e]) { print file ": the " e " ecosystem is not declared"; continue }
        if (dir[e] != "/") print file ": " e ": directory is not /"
        if (interval[e] != "cron" || !cron[e] || tz[e] != "UTC")
          print file ": " e ": schedule is not interval: cron with a cronjob and timezone: UTC"
        if (!cm[e] || !prefix[e]) print file ": " e ": no commit-message prefix"
        if (!skipped("groups") && (!grp[e] || !pat[e])) print file ": " e ": no groups with patterns"
        if (!skipped("cooldown") && days[e] != "3") print file ": " e ": no cooldown with default-days: 3"
      }
    }
  ' "$f"
}

# block <eco> <prefix> <dir> <comments:1|0> <groups:1|0> <cooldown:1|0> — one ecosystem entry.
block() {
  local c=""
  [[ "$4" == 1 ]] && c="    # a choice, explained"
  printf '  - package-ecosystem: %s\n    directory: %s\n' "$1" "$3"
  [[ -n "$c" ]] && printf '%s\n' "$c"
  printf '    schedule:\n      interval: cron\n      cronjob: "0 4 * * *"\n      timezone: UTC\n'
  [[ -n "$c" ]] && printf '%s\n' "$c"
  printf '    commit-message:\n      prefix: %s\n' "$2"
  if [[ "$5" == 1 ]]; then
    [[ -n "$c" ]] && printf '%s\n' "$c"
    printf '    groups:\n      all:\n        patterns:\n          - "*"\n'
  fi
  if [[ "$6" == 1 ]]; then
    [[ -n "$c" ]] && printf '%s\n' "$c"
    printf '    cooldown:\n      default-days: 3\n'
  fi
}

# synth <name> <gomod-args...> -- <actions-args...> — writes a file, sets WF.
synth() {
  local name="$1"; shift
  local g=() a=() side=g
  for x in "$@"; do
    if [[ "$x" == -- ]]; then side=a; continue; fi
    if [[ "$side" == g ]]; then g+=("$x"); else a+=("$x"); fi
  done
  WF="${TMP}/${name}.yml"
  {
    printf 'version: 2\nupdates:\n'
    [[ ${#g[@]} -gt 0 ]] && block "${g[@]}"
    [[ ${#a[@]} -gt 0 ]] && block "${a[@]}"
  } > "$WF"
  return 0
}

# judge <file> — sets OUT and RC (1 when there are problems).
judge() {
  OUT="$(judge_file "$1")"
  if [[ -n "$OUT" ]]; then RC=1; else RC=0; fi
}

synth good gomod go / 1 1 1 -- github-actions actions / 1 1 1
judge "$WF"
want_rc "1. both ecosystems at /, cron schedule, prefix, groups, cooldown, comments is accepted" 0

judge "${TMP}/absent.yml"
want_red "2. no file" "there is no dependabot.yml"

synth nogomod -- github-actions actions / 1 1 1
judge "$WF"
want_red "3. no gomod ecosystem" "the gomod ecosystem is not declared"

synth noactions gomod go / 1 1 1 --
judge "$WF"
want_red "4. no github-actions ecosystem" "the github-actions ecosystem is not declared"

synth subdir gomod go /sub 1 1 1 -- github-actions actions / 1 1 1
judge "$WF"
want_red "5. gomod at another directory" "gomod: directory is not /"

synth nocooldown gomod go / 1 1 0 -- github-actions actions / 1 1 1
judge "$WF"
want_red "6. no cooldown" "gomod: no cooldown with default-days: 3"
COOLDOWN_WF="$WF"

synth nogroups gomod go / 1 1 1 -- github-actions actions / 1 0 1
judge "$WF"
want_red "7. no groups" "github-actions: no groups with patterns"
GROUPS_WF="$WF"

synth nocomments gomod go / 0 1 1 -- github-actions actions / 0 1 1
judge "$WF"
want_red "8. no comment above a choice" "gomod: no comment line directly above schedule:"
COMMENTS_WF="$WF"

# The schedule: daily skips weekends, so it is refused.
sed 's/interval: cron/interval: daily/' "${TMP}/good.yml" > "${TMP}/daily.yml"
judge "${TMP}/daily.yml"
want_red "9. interval daily instead of cron" "schedule is not interval: cron"

# The real file.
judge .github/dependabot.yml
want_rc "10. .github/dependabot.yml has both ecosystems with every choice commented" 0

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

selftest_end "the dependabot config does not hold" \
  "dependabot config: gomod and github-actions at /, cron schedule, commit-message prefix, groups, cooldown and a comment per choice; each broken shape is red; mutation proven"
