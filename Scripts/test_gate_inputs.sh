#!/usr/bin/env bash
# Scripts/test_gate_inputs.sh (forsgren#262, step 1 of 3). Not canon: forsgren only.
#
# Self-test for Scripts/gate_inputs.txt, the list of what each of the four
# browser gates reads. Nothing runs a gate from that list yet; this holds the
# list true, so the selector of step 2 can trust it:
#   1. each of the four labels has a row in Scripts/gate_report_order.txt and
#      at least one `in` row in the list;
#   2. every `in` path exists;
#   3. each gate's script closure (the script, and every Scripts/ file it
#      names, followed transitively) is inside that gate's `in` rows;
#   4. a gate that lists cmd/ or internal/ excludes *_test.go, cmd/**/testdata/
#      and internal/**/testdata/ (forsgren#281);
#   5. THE GUARD (forsgren#281): no go:embed line of a non-test Go file under
#      cmd/, internal/ or install/ names testdata/ or a _test.go file, and
#      neither Scripts/build_site.sh nor Scripts/build_fixture_site.sh reads
#      testdata/ or a _test.go file (the fixture's own Scripts/testdata/fixture_site
#      is the one allowed path). This is what makes the exclusion in 4 safe: the
#      moment such a line exists, the exclusion would hide a real input.
# Mutation proofs (each is red BECAUSE of the change, and says the reason):
#   A. a script dropped from a gate's rows              -> red, naming it;
#   B. a listed path that does not exist                -> red, naming it;
#   C. a go:embed of a testdata file in a temp copy     -> red, naming the file;
#   D. a build script reading a testdata file           -> red, naming it;
#   E. the *_test.go exclusion dropped                  -> red, naming the gate;
#   F. a go:embed of a _test.go file in a temp copy     -> red, naming the file.
#
# named_files and closure are copies of the ones in the sandbox isolation
# self-test; step 2 of forsgren#262 moves both into a shared gate-selection library
# and this self-test sources them from there.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "browser gate inputs self-test"

INPUTS="Scripts/gate_inputs.txt"
ORDER="Scripts/gate_report_order.txt"
LABELS=(
  "browser gate self-test"
  "browser gate"
  "browser gate (fixture site) self-test"
  "browser gate (fixture site)"
)

if [[ ! -f "$INPUTS" ]]; then
  selftest_abort "browser gate inputs self-test: ${INPUTS} is missing"
fi

# named_files <file>: the repository files a script's non-comment lines name.
named_files() {
  local code token
  code="$(grep -v '^[[:space:]]*#' "$1" || true)"
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    if [[ -f "$token" ]]; then
      echo "$token"
    elif [[ -f "Scripts/${token##*/}" ]]; then
      echo "Scripts/${token##*/}"
    elif [[ -f ".github/workflows/${token##*/}" ]]; then
      echo ".github/workflows/${token##*/}"
    fi
  done < <(grep -oE '[A-Za-z0-9_./-]+[.](sh|mjs|js|py|txt|json|yml|yaml|go)' <<< "$code" | sort -u)
}

# closure <file>: the file and every file it names, transitively.
closure() {
  local seen=$'\n'"$1"$'\n' queue=("$1") i=0 f n
  while [[ "$i" -lt "${#queue[@]}" ]]; do
    f="${queue[$i]}"
    i=$((i + 1))
    case "$f" in *.sh | *.mjs | *.js | *.py) ;; *) continue ;; esac
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      if [[ "$seen" != *$'\n'"$n"$'\n'* ]]; then
        seen+="${n}"$'\n'
        queue+=("$n")
      fi
    done < <(named_files "$f")
  done
  printf '%s' "$seen" | sed '/^$/d'
}

# rows <inputs-file> <label> <kind>: the paths of a gate's rows of one kind.
rows() {
  awk -F'|' -v l="$2" -v k="$3" '/^[[:space:]]*#/ || NF == 0 { next } $1 == l && $2 == k { print $3 }' "$1"
}

# covered <inputs-file> <label> <path>: the path is a listed `in` file, or under a listed directory.
covered() {
  local p
  while IFS= read -r p; do
    if [[ "$p" == "$3" ]] || { [[ "$p" == */ ]] && [[ "$3" == "$p"* ]]; }; then return 0; fi
  done < <(rows "$1" "$2" in)
  return 1
}

# script_of <label>: the script the order file runs for the label.
script_of() {
  awk -F'|' -v l="$1" '$1 == l { print $2 }' "$ORDER"
}

# check_inputs <inputs-file>: prints one `problem:` line per fault, returns 1 if any.
check_inputs() {
  local inputs="$1" label script p bad=0
  for label in "${LABELS[@]}"; do
    script="$(script_of "$label")"
    if [[ -z "$script" ]]; then
      echo "problem: '${label}' has no row in ${ORDER}"
      bad=1
      continue
    fi
    if [[ -z "$(rows "$inputs" "$label" in)" ]]; then
      echo "problem: '${label}' has no input rows in ${inputs}"
      bad=1
      continue
    fi
    while IFS= read -r p; do
      if [[ ! -e "${p%/}" ]]; then
        echo "problem: '${label}' lists ${p}, which does not exist"
        bad=1
      fi
    done < <(rows "$inputs" "$label" in)
    while IFS= read -r p; do
      if ! covered "$inputs" "$label" "$p"; then
        echo "problem: '${label}' reads ${p} (the closure of ${script}) but does not list it"
        bad=1
      fi
    done < <(closure "$script")
    if rows "$inputs" "$label" in | grep -qE '^(cmd|internal)/$'; then
      for p in '*_test.go' 'cmd/**/testdata/' 'internal/**/testdata/'; do
        if ! rows "$inputs" "$label" out | grep -qxF -- "$p"; then
          echo "problem: '${label}' lists cmd/ or internal/ but does not exclude ${p}"
          bad=1
        fi
      done
    fi
  done
  return "$bad"
}

# guard <root>: prints one `problem:` line per fault, returns 1 if any. A go:embed
# line that names testdata/ or a _test.go file, or a build script that does.
guard() {
  local root="$1" f line bad=0 code
  while IFS= read -r f; do
    while IFS= read -r line; do
      if [[ "$line" == *testdata* || "$line" == *_test.go* ]]; then
        echo "problem: ${f#"${root}"/} embeds a test file or testdata: ${line}"
        bad=1
      fi
    done < <(grep -E '^[[:space:]]*//go:embed' "$f" || true)
  done < <(find "$root/cmd" "$root/internal" "$root/install" -name '*.go' ! -name '*_test.go' 2> /dev/null | sort)
  for f in Scripts/build_site.sh Scripts/build_fixture_site.sh; do
    [[ -f "${root}/${f}" ]] || continue
    # The fixture's own directory is the one declared input under testdata/.
    code="$(grep -v '^[[:space:]]*#' "${root}/${f}" | sed 's|Scripts/testdata/fixture_site||g' || true)"
    while IFS= read -r line; do
      echo "problem: ${f} reads a test file or testdata: ${line}"
      bad=1
    done < <(grep -E 'testdata|_test[.]go' <<< "$code" || true)
  done
  return "$bad"
}

# 1-4
capture check_inputs "$INPUTS"
want_green "1-4: every label has a row, every path exists, every closure is listed, the Go trees exclude tests"
for label in "${LABELS[@]}"; do
  echo "  ok: ${label}: $(closure "$(script_of "$label")" | wc -l | tr -d ' ') files in its closure"
done

# 5
capture guard "."
want_green "5: no go:embed and no build script reads testdata/ or a test file"

# Mutation proofs.
# A: a script dropped from a gate's rows.
sed '/^browser gate|in|Scripts\/lib_site_settings.sh$/d' "$INPUTS" > "${TMP}/a.txt"
if cmp -s "$INPUTS" "${TMP}/a.txt"; then fail "mutation A changed nothing: the proof would be vacuous"; fi
capture check_inputs "${TMP}/a.txt"
want_red "mutation proof A: a script dropped from a gate's rows" "problem: 'browser gate' reads Scripts/lib_site_settings.sh (the closure of Scripts/gate_browser.sh) but does not list it"

# B: a listed path that does not exist.
{ cat "$INPUTS"; echo 'browser gate|in|Scripts/no_such_input.txt'; } > "${TMP}/b.txt"
capture check_inputs "${TMP}/b.txt"
want_red "mutation proof B: a listed path that does not exist" "problem: 'browser gate' lists Scripts/no_such_input.txt, which does not exist"

# E: the *_test.go exclusion dropped from one gate.
sed '/^browser gate (fixture site)|out|\*_test.go$/d' "$INPUTS" > "${TMP}/e.txt"
if cmp -s "$INPUTS" "${TMP}/e.txt"; then fail "mutation E changed nothing: the proof would be vacuous"; fi
capture check_inputs "${TMP}/e.txt"
want_red "mutation proof E: the *_test.go exclusion dropped" "problem: 'browser gate (fixture site)' lists cmd/ or internal/ but does not exclude *_test.go"

# C, D, F: a temp copy of the trees the guard reads.
ROOT="${TMP}/root"
mkdir -p "${ROOT}/Scripts"
cp -R cmd internal install "${ROOT}/"
cp Scripts/build_site.sh Scripts/build_fixture_site.sh "${ROOT}/Scripts/"
capture guard "$ROOT"
want_green "5b: the unchanged copy is clean"

printf 'package page\n\nimport _ "embed"\n\n//go:embed testdata/legend.golden\nvar zz string\n' > "${ROOT}/internal/page/zz_embed.go"
capture guard "$ROOT"
want_red "mutation proof C: a go:embed of a testdata file" "problem: internal/page/zz_embed.go embeds a test file or testdata: //go:embed testdata/legend.golden"
rm -f "${ROOT}/internal/page/zz_embed.go"

printf 'package page\n\nimport _ "embed"\n\n//go:embed page_test.go\nvar zz string\n' > "${ROOT}/internal/page/zz_embed.go"
capture guard "$ROOT"
want_red "mutation proof F: a go:embed of a _test.go file" "problem: internal/page/zz_embed.go embeds a test file or testdata: //go:embed page_test.go"
rm -f "${ROOT}/internal/page/zz_embed.go"

{ cat Scripts/build_site.sh; echo 'cp internal/page/testdata/legend.golden out/'; } > "${ROOT}/Scripts/build_site.sh"
if cmp -s Scripts/build_site.sh "${ROOT}/Scripts/build_site.sh"; then fail "mutation D changed nothing: the proof would be vacuous"; fi
capture guard "$ROOT"
want_red "mutation proof D: a build script reading a testdata file" "problem: Scripts/build_site.sh reads a test file or testdata: cp internal/page/testdata/legend.golden"

selftest_end "the browser gate inputs self-test failed" "browser gate inputs: four labels listed, every path exists, every closure listed, the guard holds, six mutations seen"
