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
#   F. a go:embed of a _test.go file in a temp copy     -> red, naming the file;
#   G. a directory pattern that holds a testdata file   -> red, naming the file (go list).
#
# named_files, closure and the readers of the list are Scripts/lib_gate_select.sh's
# (forsgren#262, step 2); nothing is copied here.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_git_sandbox.sh
source Scripts/lib_git_sandbox.sh
# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_summary_writers.sh
source Scripts/lib_summary_writers.sh
# shellcheck source=Scripts/lib_gate_select.sh
source Scripts/lib_gate_select.sh
selftest_begin "browser gate inputs self-test"

INPUTS="Scripts/gate_inputs.txt"
ORDER="Scripts/gate_report_order.txt"
LABELS=(
  "browser gate self-test"
  "browser gate"
  "browser gate (fixture site) self-test"
  "browser gate (fixture site)"
  "release workflow"
  "step summary isolation"
)

# The gate that discovers its inputs (forsgren#264): the scripts that write the step
# summary and the self-tests that name them are found by Scripts/lib_summary_writers.sh,
# as the gate finds them, and the closure of each is a read of the gate.
DISCOVERING="step summary isolation"

# Gates that must not enumerate the repository (forsgren#263): a gate that lists
# the tracked files and searches them reads every file, which no list of inputs
# can state, so the selector could never skip it. Its script is searched for the
# commands that do.
NO_ENUMERATION=("release workflow")
ENUMERATING='git (ls-files|grep|ls-tree)|find (\.|\$|"|Scripts|cmd|internal)|grep (-[A-Za-z]*[rR][A-Za-z]* )'

if [[ ! -f "$INPUTS" ]]; then
  selftest_abort "browser gate inputs self-test: ${INPUTS} is missing"
fi

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
    if [[ -z "$(gate_input_rows "$inputs" "$label" in)" ]]; then
      echo "problem: '${label}' has no input rows in ${inputs}"
      bad=1
      continue
    fi
    while IFS= read -r p; do
      if [[ ! -e "${p%/}" ]]; then
        echo "problem: '${label}' lists ${p}, which does not exist"
        bad=1
      fi
    done < <(gate_input_rows "$inputs" "$label" in)
    while IFS= read -r p; do
      if ! gate_input_covered "$inputs" "$label" "$p"; then
        echo "problem: '${label}' reads ${p} (the closure of ${script}) but does not list it"
        bad=1
      fi
    done < <(closure "$script")
    if gate_input_rows "$inputs" "$label" in | grep -qE '^(cmd|internal)/$'; then
      for p in '*_test.go' 'cmd/**/testdata/' 'internal/**/testdata/'; do
        if ! gate_input_rows "$inputs" "$label" out | grep -qxF -- "$p"; then
          echo "problem: '${label}' lists cmd/ or internal/ but does not exclude ${p}"
          bad=1
        fi
      done
    fi
  done
  return "$bad"
}

# check_discovered <inputs-file> [<dir>]: prints one `problem:` line per file the
# discovering gate runs or reads (summary_reads of Scripts/lib_summary_writers.sh) that
# its rows do not list. <dir> is a
# repository root to look in (the default is this one).
check_discovered() {
  local found
  found="$(
    cd "${2:-.}" || exit 0
    summary_reads "$(basename "$(script_of "$DISCOVERING")")" | sort -u | while IFS=$'\t' read -r t p; do
      if ! gate_input_covered "$1" "$DISCOVERING" "$t"; then
        echo "problem: '${DISCOVERING}' runs or reads ${t} (found through ${p}, a script that writes the step summary or a self-test that names one) but does not list it"
      fi
    done
  )"
  [[ -z "$found" ]] || echo "$found"
  [[ -z "$found" ]]
}

# check_enumeration <order-file>: prints one `problem:` line per gate of NO_ENUMERATION
# whose script (comments left out) lists or searches the repository.
check_enumeration() {
  local label script hit bad=0
  for label in "${NO_ENUMERATION[@]}"; do
    script="$(awk -F'|' -v l="$label" '$1 == l { print $2 }' "$1")"
    [[ -f "$script" ]] || continue
    hit="$(grep -v '^[[:space:]]*#' "$script" | grep -E "$ENUMERATING" | head -1 || true)"
    if [[ -n "$hit" ]]; then
      echo "problem: '${label}' (${script}) enumerates the repository, so it reads files no list can name: ${hit}"
      bad=1
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
  # The patterns above name what is written; this is what go build embeds, which a
  # directory pattern (//go:embed templates) can widen to a testdata/ inside it.
  if [[ -f "${root}/go.mod" ]] && command -v go > /dev/null 2>&1; then
    while IFS= read -r f; do
      if [[ "$f" == */testdata/* || "$f" == *_test.go ]]; then
        echo "problem: go build embeds ${f#"${root}"/}, a test file or testdata"
        bad=1
      fi
    done < <(cd "$root" && go list -f '{{range .EmbedFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}' ./... 2> /dev/null)
  fi
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

# 6b
capture check_discovered "$INPUTS"
want_green "6b: everything the step summary isolation gate discovers and runs is listed"

# 6
capture check_enumeration "$ORDER"
want_green "6: no gate that must stay listable lists or searches the repository"

# Mutation proofs.
# H: a gate that lists the tracked files and searches them.
printf '%s\n' '#!/usr/bin/env bash' 'git ls-files | grep -F removed_name' > "${TMP}/h_script.sh"
sed "s#^release workflow|[^|]*|#release workflow|${TMP}/h_script.sh|#" "$ORDER" > "${TMP}/h_order.txt"
if cmp -s "$ORDER" "${TMP}/h_order.txt"; then fail "mutation H changed nothing: the proof would be vacuous"; fi
capture check_enumeration "${TMP}/h_order.txt"
want_red "mutation proof H: a gate that lists the tracked files" "problem: 'release workflow' (${TMP}/h_script.sh) enumerates the repository"

# I: a script the discovery finds, dropped from the rows.
W1="$(summary_writer_names | head -1)"
sed "/^step summary isolation|in|Scripts\/${W1}\$/d" "$INPUTS" > "${TMP}/i.txt"
if cmp -s "$INPUTS" "${TMP}/i.txt"; then fail "mutation I changed nothing: the proof would be vacuous"; fi
capture check_discovered "${TMP}/i.txt"
want_red "mutation proof I: a step summary writer dropped from the rows" "problem: 'step summary isolation' runs or reads Scripts/${W1} (found through Scripts/${W1},"

# J, K: a new writer, and a new self-test that names a writer, in a copy of Scripts/.
DISC="${TMP}/disc"
mkdir -p "${DISC}"
cp -R Scripts "${DISC}/Scripts"
printf '#!/usr/bin/env bash\necho x >> "$%s"\n' GITHUB_STEP_SUMMARY > "${DISC}/Scripts/zz_new_writer.sh"
capture check_discovered "$INPUTS" "$DISC"
want_red "mutation proof J: a new script that writes the step summary" "problem: 'step summary isolation' runs or reads Scripts/zz_new_writer.sh (found through Scripts/zz_new_writer.sh,"
rm -f "${DISC}/Scripts/zz_new_writer.sh"
printf '#!/usr/bin/env bash\nbash Scripts/%s\n' "$W1" > "${DISC}/Scripts/test_zz_new.sh"
capture check_discovered "$INPUTS" "$DISC"
want_red "mutation proof K: a new self-test that runs a step summary writer" "problem: 'step summary isolation' runs or reads Scripts/test_zz_new.sh (found through Scripts/test_zz_new.sh,"

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
cp -R cmd internal install go.mod go.sum "${ROOT}/"
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

# G: a directory pattern (//go:embed templates) that now holds a testdata file: the
# written pattern names no testdata, only go list sees it.
mkdir -p "${ROOT}/internal/page/templates/testdata"
echo '<p>golden</p>' > "${ROOT}/internal/page/templates/testdata/x.html"
capture guard "$ROOT"
want_red "mutation proof G: a directory pattern that holds a testdata file" "problem: go build embeds internal/page/templates/testdata/x.html, a test file or testdata"
rm -rf "${ROOT}/internal/page/templates/testdata"

{ cat Scripts/build_site.sh; echo 'cp internal/page/testdata/legend.golden out/'; } > "${ROOT}/Scripts/build_site.sh"
if cmp -s Scripts/build_site.sh "${ROOT}/Scripts/build_site.sh"; then fail "mutation D changed nothing: the proof would be vacuous"; fi
capture guard "$ROOT"
want_red "mutation proof D: a build script reading a testdata file" "problem: Scripts/build_site.sh reads a test file or testdata: cp internal/page/testdata/legend.golden"

selftest_end "the browser gate inputs self-test failed" "gate inputs: six labels listed, every path exists, every closure listed, everything the step summary isolation gate discovers is listed, the release workflow gate does not enumerate the repository, the guard holds, eleven mutations seen"
