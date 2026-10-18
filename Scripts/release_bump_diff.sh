#!/usr/bin/env bash
# Scripts/release_bump_diff.sh
#
# The check of a release's bump commit (forsgren#230, step 1 of 2): the bump
# commit holds nothing but the version bump. The Release workflow runs it on
# the commit Scripts/release_commit.sh pushed, before the commit is released.
#
# Usage: Scripts/release_bump_diff.sh <bump-sha> <green-parent-sha> <old-version> <new-version>
#
# Green (exit 0, `OK: ...`) only when
#   - the bump commit has one parent, and it IS <green-parent-sha> (the commit
#     Quality was green on): a bump on top of anything else was never tested;
#   - every changed file is one the bump may change, the list of
#     Scripts/release_bump_scope.txt that Scripts/release_bump.sh rewrites from,
#     and is only modified (not added, deleted or renamed, its mode unchanged).
#     SHIPPED.md is not in it: the bump does not write it, its entry is prose
#     written per release;
#   - every hunk removes as many lines as it adds, and each added line is its
#     removed line with the version replaced the way the bump replaces it:
#     the old version by the new one and the newer-release example (the patch
#     after the old version) by the one after the new version, whole version
#     tokens only. Any other change in such a line is a red.
# Red (exit 1): one `❌ FAIL: bump diff: ...` line per violation (a merge
# commit, a wrong parent, a file outside the set, a line that changes more than
# the version, naming file and line). Exit 2: usage.
# It works on the repository the script lives in. Self-test:
# Scripts/test_release_bump_diff.sh.

set -uo pipefail

COMPLETED=0
trap '[ "$COMPLETED" -eq 1 ] || { echo "❌ FAIL: release_bump_diff.sh aborted before completing (COMPLETED was never set)" >&2; exit 1; }' EXIT

cd "$(dirname "$0")/.." || exit 1
# shellcheck source=Scripts/lib_release_bump_scope.sh
source Scripts/lib_release_bump_scope.sh

usage() {
  echo "usage: Scripts/release_bump_diff.sh <bump-sha> <green-parent-sha> <old-version> <new-version>   (X.Y.Z)" >&2
  COMPLETED=1
  exit 2
}

[ "$#" -eq 4 ] || usage
SEMVER='^([0-9]+)\.([0-9]+)\.([0-9]+)$'
[[ "$3" =~ $SEMVER ]] || usage
O_MAJOR="${BASH_REMATCH[1]}"
O_MINOR="${BASH_REMATCH[2]}"
O_PATCH="${BASH_REMATCH[3]}"
[[ "$4" =~ $SEMVER ]] || usage
N_MAJOR="${BASH_REMATCH[1]}"
N_MINOR="${BASH_REMATCH[2]}"
N_PATCH="${BASH_REMATCH[3]}"
OLD="$3"
NEW="$4"
export OLD NEW
export OLD_EXAMPLE="${O_MAJOR}.${O_MINOR}.$((O_PATCH + 1))"
export NEW_EXAMPLE="${N_MAJOR}.${N_MINOR}.$((N_PATCH + 1))"
PREFIX="❌ FAIL: bump diff: "
export PREFIX
FAILED=0

red() {
  echo "${PREFIX}$*"
  FAILED=1
}

# resolve <rev>: the commit full sha, nothing when there is none.
resolve() {
  git rev-parse --verify -q "$1^{commit}"
}
BUMP="$(resolve "$1")"
if [ -z "$BUMP" ]; then
  echo "${PREFIX}$1 is no commit of this repository"
  COMPLETED=1
  exit 1
fi
GREEN="$(resolve "$2")"
if [ -z "$GREEN" ]; then
  echo "${PREFIX}$2 is no commit of this repository"
  COMPLETED=1
  exit 1
fi

# The parent: exactly one, and the green one.
read -r -a COMMIT_AND_PARENTS < <(git rev-list --parents -n 1 "$BUMP")
if [ "${#COMMIT_AND_PARENTS[@]}" -gt 2 ]; then
  red "${BUMP} is a merge commit (${#COMMIT_AND_PARENTS[@]} words: it has $(( ${#COMMIT_AND_PARENTS[@]} - 1 )) parents), a bump has one"
elif [ "${#COMMIT_AND_PARENTS[@]}" -lt 2 ]; then
  red "${BUMP} has no parent, a bump has one"
else
  PARENT="${COMMIT_AND_PARENTS[1]}"
  if [ "$PARENT" != "$GREEN" ]; then
    red "the parent is ${PARENT}, not the green ${GREEN}"
  fi
fi

# The lines of one file: a perl reader of the unified diff (-U0). Each hunk
# removes and adds the same number of lines, and the removed line with the
# bump's own replacement applied (the newer-release example first, then the
# version, as release_bump.sh does) is the added line. It prints one red
# line per offender, with the number of the added line.
LINE_CHECK="$(cat <<'PERL'
sub token { my $v = quotemeta(shift); return qr/(?<![0-9.])$v(?![0-9]|\.[0-9])/; }
my ($old_ex, $new_ex, $old, $new) = ($ENV{OLD_EXAMPLE}, $ENV{NEW_EXAMPLE}, $ENV{OLD}, $ENV{NEW});
my ($t_old_ex, $t_old) = (token($old_ex), token($old));
sub bump { my $l = shift; $l =~ s/$t_old_ex/$new_ex/g; $l =~ s/$t_old/$new/g; return $l; }
my ($file, $start, $hunks) = ($ENV{FILE}, 0, 0);
my (@rem, @add);
my $in = 0;
sub flush {
  return unless $in;
  if (@rem != @add) {
    print "$ENV{PREFIX}$file:$start changes more than the version (" . scalar(@rem) . " lines removed, " . scalar(@add) . " added)\n";
  } else {
    for my $i (0 .. $#rem) {
      if (bump($rem[$i]) ne $add[$i]) { print "$ENV{PREFIX}$file:" . ($start + $i) . " changes more than the version\n"; }
    }
  }
  @rem = (); @add = ();
}
while (my $l = <STDIN>) {
  chomp $l;
  if ($l =~ /^\@\@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? \@\@/) { flush(); $start = $1; $in = 1; $hunks++; next; }
  next unless $in;
  if ($l =~ /^-/) { push @rem, substr($l, 1); }
  elsif ($l =~ /^\+/) { push @add, substr($l, 1); }
}
flush();
print "$ENV{PREFIX}$file: no changed line to read, it changes more than the version\n" if $hunks == 0;
PERL
)"

if [ -n "${PARENT:-}" ]; then
  while IFS=$'\t' read -r META FILE; do
    # META: ":<old mode> <new mode> <old sha> <new sha> <status>"
    read -r OLD_MODE NEW_MODE _ _ STATUS <<< "${META#:}"
    if [ "$STATUS" != "M" ]; then
      red "${FILE}: the bump ${STATUS}, it only modifies files"
    elif ! bump_scope_allows "$FILE"; then
      red "${FILE}: is not a file the bump changes (Scripts/release_bump_scope.txt)"
    elif [ "$OLD_MODE" != "$NEW_MODE" ]; then
      red "${FILE}: the mode changed from ${OLD_MODE} to ${NEW_MODE}"
    else
      export FILE
      while IFS= read -r line; do
        echo "$line"
        FAILED=1
      done < <(git diff -U0 --no-color --no-ext-diff --no-renames "$PARENT" "$BUMP" -- "$FILE" | perl -e "$LINE_CHECK")
    fi
  done < <(git diff --raw --no-abbrev --no-renames "$PARENT" "$BUMP")
fi

if [ "$FAILED" -ne 0 ]; then
  COMPLETED=1
  exit 1
fi
echo "OK: ${BUMP} only bumps ${OLD} to ${NEW} on top of the green ${GREEN}"
COMPLETED=1
