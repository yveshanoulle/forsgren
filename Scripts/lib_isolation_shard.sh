#!/usr/bin/env bash
# Scripts/lib_isolation_shard.sh (forsgren#446). Not canon: forsgren only.
#
# SOURCED, never run. It sets no shell options.
#   shard_assign <n> <m> <weights-file>
#     Reads self-test paths on stdin, one per line, and prints, in the order read,
#     the ones that fall in shard n of m (1 <= n <= m). The split is greedy by
#     weight: the self-tests are taken heaviest first (equal weights by name, C
#     order) and each goes to the shard that weighs least so far (a tie to the
#     lowest shard). A weight is the seconds in the weights file, one line
#     `<self-test> <seconds>`, with a line `default <seconds>` for every self-test
#     that has no row, so a new self-test lands in one shard with nothing to edit.
#     The split depends on the list and the file alone, never on the commit.
#     A missing file, no default row or a weight that is not a whole number of
#     seconds is an error on stderr and exit 2.
shard_assign() {
  local n="$1" m="$2" file="$3"
  if [[ ! -f "$file" ]]; then
    echo "shard_assign: the weights file ${file} does not exist" >&2
    return 2
  fi
  LC_ALL=C awk -v n="$n" -v m="$m" '
    FNR == NR {
      if ($0 ~ /^[[:space:]]*(#|$)/) next
      if ($2 !~ /^[1-9][0-9]*$/) { bad = $1 " " $2; next }
      if ($1 == "default") { def = $2 + 0; have = 1 } else { w[$1] = $2 + 0 }
      next
    }
    NF {
      c++; name[c] = $1
      wt[c] = ($1 in w) ? w[$1] : def
    }
    END {
      if (bad != "") { print "shard_assign: not a whole number of seconds: " bad > "/dev/stderr"; exit 2 }
      if (!have) { print "shard_assign: the weights file has no default row" > "/dev/stderr"; exit 2 }
      for (s = 1; s <= m; s++) load[s] = 0
      for (k = 1; k <= c; k++) {
        best = 0
        for (i = 1; i <= c; i++) {
          if (done[i]) continue
          if (best == 0 || wt[i] > wt[best] || (wt[i] == wt[best] && name[i] < name[best])) best = i
        }
        done[best] = 1
        low = 1
        for (s = 2; s <= m; s++) if (load[s] < load[low]) low = s
        load[low] += wt[best]
        shard[best] = low
      }
      for (i = 1; i <= c; i++) if (shard[i] == n) print name[i]
    }' "$file" -
}
