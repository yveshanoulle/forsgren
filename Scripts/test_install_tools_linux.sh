#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Scripts/test_install_tools_linux.sh (forsgren#427), forsgren's own.
#
# Fixture for the Linux tool installer, Scripts/install_tools_linux.sh, which installs the
# pinned builds in Scripts/linux_tool_pins.txt. The Lint gates job relies on it
# on ubuntu-latest, so this runs on the Mac too, with the download and the
# Python seams stubbed: nothing here touches the network.
#
# THE CASES
#   1. every pinned tool installs from its archive or requirements file, runs,
#      reports its pinned version, and the tool directory is added to GITHUB_PATH
#   2. a download whose sha256 is not the pin is refused, and nothing is
#      installed (the tool is not in the tool directory)
#   3. a tool that installs but reports another version is red, naming both
#   4. a tool with no row in the pin list is red, naming it
#   5. an empty tool list is red (a list that went empty must not read as done)
#   6. a CPU other than x86_64 is red, naming it
#   7. a requirements file with no --hash line is red
#   8. the real pin list: a row per tool of Scripts/required_tools_linux.txt, of
#      Scripts/required_tools_linux_gates.txt (forsgren#447, step 3) and of the
#      three browser jobs' lists (forsgren#642), each archive with a version
#      that is in its URL, a 64-hex sha256 and an https GitHub release URL, each
#      pip tool with a requirements file with hashes, each setup tool with a
#      source the installer knows (.nvmrc or go.mod) that exists; and each tool
#      of a Linux list is also in the Homebrew list, so the two machines install
#      the same tools
#  10. a setup tool (forsgren#642: node from actions/setup-node, go from
#      actions/setup-go, installed by the job before the installer runs): it is
#      run from PATH and must report the version its source pins (.nvmrc's
#      major, go.mod's toolchain line); another version is red, naming both; a
#      setup tool not on PATH is red; a source the installer does not know is red
# MUTATION PROOF: the installer with its checksum comparison removed, with its
# version check removed, and with the version check of a setup tool removed,
# ACCEPTS the corresponding bad fixture, so cases 2, 3 and 10 are what stands
# between a wrong build and the gates.

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
selftest_begin "Linux tool install self-test"

INSTALLER="${PWD}/Scripts/install_tools_linux.sh"
FIX="${TMP}/fixtures"
mkdir -p "$FIX"

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# make_archive <file-name> <member> <output>: a tar.gz whose member prints <output>.
make_archive() {
  local d="${TMP}/mk_$1"
  mkdir -p "${d}/$(dirname "$2")"
  printf '#!/bin/sh\necho "%s"\n' "$3" > "${d}/$2"
  chmod 755 "${d}/$2"
  tar -czf "${FIX}/$1" -C "$d" "$2"
}

make_archive shellcheck.tar.gz shellcheck-v9.9.9/shellcheck "version: 9.9.9"
make_archive actionlint.tar.gz actionlint "9.9.9"
make_archive zizmor.tar.gz zizmor "zizmor 9.9.9"
make_archive zizmor_old.tar.gz zizmor "zizmor 1.0.0"

cat > "${FIX}/reqs.txt" <<'R'
yamllint==9.9.9 \
    --hash=sha256:0000000000000000000000000000000000000000000000000000000000000000
R
printf 'yamllint==9.9.9\n' > "${FIX}/reqs_nohash.txt"

# A stub curl: copies the fixture named like the URL's last segment to -o.
cat > "${TMP}/curl" <<'S'
#!/usr/bin/env bash
out=""; url=""
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac
done
src="${FIXTURES}/$(basename "$url")"
[ -f "$src" ] || exit 22
cp "$src" "$out"
S
# A stub python3: `-m venv DIR` makes a DIR/bin/pip whose `install` makes the yamllint it was asked for.
cat > "${TMP}/python3" <<'S'
#!/usr/bin/env bash
dir="$3"
mkdir -p "${dir}/bin"
cat > "${dir}/bin/pip" <<'P'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
printf '#!/bin/sh\necho "yamllint %s"\n' "${FAKE_YAMLLINT_VERSION:-9.9.9}" > "${d}/yamllint"
chmod 755 "${d}/yamllint"
P
chmod 755 "${dir}/bin/pip"
S
chmod 755 "${TMP}/curl" "${TMP}/python3"

# pin_rows <tool> <version> <file> <member> <sha>: the archive rows of a made-up pin.
pin_rows() {
  printf '%s|version|%s\n%s|kind|archive\n%s|release|https://example.invalid\n' "$1" "$2" "$1" "$1"
  printf '%s|file|%s\n%s|sha256|%s\n%s|member|%s\n' "$1" "$3" "$1" "$5" "$1" "$4"
}

# write_pins <file> <zizmor-archive> <zizmor-sha-or-empty> <reqs-file>
write_pins() {
  local zsha="${3:-$(sha_of "${FIX}/$2")}"
  {
    pin_rows shellcheck 9.9.9 shellcheck.tar.gz shellcheck-v9.9.9/shellcheck "$(sha_of "${FIX}/shellcheck.tar.gz")"
    pin_rows actionlint 9.9.9 actionlint.tar.gz actionlint "$(sha_of "${FIX}/actionlint.tar.gz")"
    pin_rows zizmor 9.9.9 "$2" zizmor "$zsha"
    printf 'yamllint|version|9.9.9\nyamllint|kind|pip\nyamllint|source|%s\n' "$4"
  } > "$1"
}

printf 'shellcheck\nyamllint\nactionlint\nzizmor\n' > "${TMP}/tools4.txt"

# run_installer <pins> <tools> [more env]: runs the installer in a fresh tool directory.
run_installer() {
  local pins="$1" tools="$2"
  shift 2
  rm -rf "${TMP}/inst"
  mkdir -p "${TMP}/inst"
  : > "${TMP}/inst/github_path"
  capture env FIXTURES="$FIX" CURL="${TMP}/curl" PYTHON3="${TMP}/python3" PINS_FILE="$pins" \
    INSTALL_TOOLS_BIN="${TMP}/inst/bin" GITHUB_PATH="${TMP}/inst/github_path" \
    INSTALL_TOOLS_ARCH=x86_64 RUNNER_TEMP="${TMP}/inst" "$@" "${RUN_INSTALLER:-$INSTALLER}" "$tools"
}

write_pins "${TMP}/pins_good.txt" zizmor.tar.gz "" "${FIX}/reqs.txt"

# --- Case 1: everything installs.
run_installer "${TMP}/pins_good.txt" "${TMP}/tools4.txt"
want_green "installs the four pinned tools" "OK: 4 required tools present"
want_said "  ... shellcheck reported its pinned version" "shellcheck 9.9.9"
want_said "  ... yamllint reported its pinned version" "yamllint 9.9.9"
if [[ "$(cat "${TMP}/inst/github_path")" == "${TMP}/inst/bin" ]]; then
  echo "  ok: the tool directory is added to GITHUB_PATH"
else
  fail "GITHUB_PATH holds '$(cat "${TMP}/inst/github_path")', not the tool directory"
fi
for t in shellcheck yamllint actionlint zizmor; do
  [[ -x "${TMP}/inst/bin/${t}" ]] || fail "${t} is not an executable in the tool directory"
done

# --- Case 2: a checksum that is not the pin.
write_pins "${TMP}/pins_badsum.txt" zizmor.tar.gz "$(printf '0%.0s' {1..64})" "${FIX}/reqs.txt"
run_installer "${TMP}/pins_badsum.txt" "${TMP}/tools4.txt"
want_red "refuses a download whose sha256 is not the pin" "the pin says"
if [[ -e "${TMP}/inst/bin/zizmor" ]]; then
  fail "zizmor was installed although its checksum did not match"
else
  echo "  ok: nothing was installed from the refused download"
fi

# --- Case 3: installed, but another version than the pin.
write_pins "${TMP}/pins_oldver.txt" zizmor_old.tar.gz "" "${FIX}/reqs.txt"
run_installer "${TMP}/pins_oldver.txt" "${TMP}/tools4.txt"
want_red "is red for a tool that reports another version than the pin" "not 9.9.9"
run_installer "${TMP}/pins_good.txt" "${TMP}/tools4.txt" FAKE_YAMLLINT_VERSION=1.2.3
want_red "is red for a Python tool that reports another version" "yamllint was installed but reports"

# --- Case 4: a tool with no pin.
printf 'shellcheck\ngitleaks\n' > "${TMP}/tools_nopin.txt"
run_installer "${TMP}/pins_good.txt" "${TMP}/tools_nopin.txt"
want_red "names a tool with no pin" "gitleaks has no pin"

# --- Case 5: an empty list.
printf '# nothing\n' > "${TMP}/tools_empty.txt"
run_installer "${TMP}/pins_good.txt" "${TMP}/tools_empty.txt"
want_red "is red for a tool list that declares no tools" "declares no tools"

# --- Case 6: another CPU.
run_installer "${TMP}/pins_good.txt" "${TMP}/tools4.txt" INSTALL_TOOLS_ARCH=aarch64
want_red "is red on a CPU the pins are not built for" "this machine is aarch64"

# --- Case 7: a requirements file without hashes.
write_pins "${TMP}/pins_nohash.txt" zizmor.tar.gz "" "${FIX}/reqs_nohash.txt"
run_installer "${TMP}/pins_nohash.txt" "${TMP}/tools4.txt"
want_red "is red for a requirements file with no --hash line" "carries no --hash line"

# --- Case 8: the real pin list, for each Linux tool list: the lint job's and the
# one of the other Linux gate jobs (forsgren#447, step 3).
PINS=Scripts/linux_tool_pins.txt
for LIST in Scripts/required_tools_linux.txt Scripts/required_tools_linux_gates.txt \
  Scripts/required_tools_browser_1_gates.txt Scripts/required_tools_browser_2_gates.txt \
  Scripts/required_tools_browser_3_gates.txt; do
  [[ -f "$LIST" ]] || selftest_abort "${LIST} does not exist"
  real_tools=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -n "$line" ]] && real_tools+=("$line")
  done < "$LIST"
  [[ "${#real_tools[@]}" -gt 0 ]] || selftest_abort "${LIST} declares no tools"
  # pin <tool> <field>: that field of the real pin list.
  pin() { sed -n "s/^$1|$2|//p" "$PINS"; }
  for t in "${real_tools[@]}"; do
    version="$(pin "$t" version)"
    kind="$(pin "$t" kind)"
    if [[ "$kind" == setup ]]; then
      src="$(pin "$t" source)"
      case "$(basename "$src")" in
        .nvmrc | go.mod) [[ -f "$src" ]] || fail "${t}: the setup source ${src} does not exist" ;;
        *) fail "${t}: the setup source '${src}' is neither .nvmrc nor go.mod" ;;
      esac
      [[ -z "$version" ]] || fail "${t}: a setup tool takes its version from ${src}, not from a version row"
    elif [[ -z "$version" ]]; then
      fail "${t} (in ${LIST}) has no pin in ${PINS}"
      continue
    elif [[ "$kind" == archive ]]; then
      url="$(pin "$t" release)/$(pin "$t" file)"
      sha="$(pin "$t" sha256)"
      gh_release='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/releases/download/v'
      [[ "$url" =~ $gh_release ]] || fail "${t}: the URL is not a GitHub release download: ${url}"
      [[ "$url" == *"$version"* ]] || fail "${t}: the version ${version} is not in its URL ${url}"
      [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || fail "${t}: the sha256 '${sha}' is not 64 hex digits"
      [[ -n "$(pin "$t" member)" ]] || fail "${t}: no archive member named"
    elif [[ "$kind" == pip ]]; then
      reqs="$(pin "$t" source)"
      [[ -f "$reqs" ]] || fail "${t}: the requirements file ${reqs} does not exist"
      grep -q -- "^${t}==${version} " "$reqs" || fail "${t}: ${reqs} does not pin ${t}==${version}"
      if grep -v '^#' "$reqs" | grep -E '^[A-Za-z]' | has -vE '==[0-9]'; then
        fail "${reqs}: a requirement is not pinned with =="
      fi
      grep -q -- '--hash=sha256:[0-9a-f]\{64\}' "$reqs" || fail "${t}: ${reqs} carries no sha256 hash"
    elif [[ "$kind" != setup ]]; then
      fail "${t}: kind '${kind}' is neither archive, pip nor setup"
    fi
    grep -qxF "$t" <(grep -v '^#' Scripts/required_tools.txt | tr -d ' ') \
      || fail "${t} is in ${LIST} but not in Scripts/required_tools.txt: the machines would install different tools"
  done
  echo "  ok: the real pin list covers the ${#real_tools[@]} tools of ${LIST}"
done

# --- Case 9: an abort after the trap is set exits non-zero (bash 3.2 can end such an abort with 0).
mkdir -p "${TMP}/abort/Scripts"
selftest_mutant "$INSTALLER" "${TMP}/abort/Scripts/install_tools_linux.sh" \
  's/^mkdir -p "[$]BIN"$/&; false/'
RUN_INSTALLER="${TMP}/abort/Scripts/install_tools_linux.sh" run_installer "${TMP}/pins_good.txt" "${TMP}/tools4.txt"
want_red "an unexpected abort after the cleanup trap is set exits non-zero" "aborted before completing"

# --- Case 10: the setup tools (forsgren#642), stubbed on PATH: node prints
# FAKE_NODE_VERSION for --version, go prints FAKE_GO_VERSION for `version`.
STUBS="${TMP}/stubs"
mkdir -p "${STUBS}" "${FIX}/src"
cat > "${STUBS}/node" <<'S'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && echo "${FAKE_NODE_VERSION:-v26.13.0}"
S
cat > "${STUBS}/go" <<'S'
#!/usr/bin/env bash
[ "${1:-}" = version ] && echo "go version ${FAKE_GO_VERSION:-go1.27.3} linux/amd64"
S
chmod 755 "${STUBS}/node" "${STUBS}/go"
printf '26\n' > "${FIX}/src/.nvmrc"
printf 'module example.invalid/m\n\ngo 1.27\n\ntoolchain go1.27.3\n' > "${FIX}/src/go.mod"
printf 'node|kind|setup\nnode|source|%s\ngo|kind|setup\ngo|source|%s\n' "${FIX}/src/.nvmrc" "${FIX}/src/go.mod" > "${TMP}/pins_setup.txt"
printf 'go\nnode\n' > "${TMP}/tools_setup.txt"
SETUP_PATH="PATH=${STUBS}:${PATH}"
run_installer "${TMP}/pins_setup.txt" "${TMP}/tools_setup.txt" "$SETUP_PATH"
want_green "10: the setup tools report the versions their sources pin" "OK: 2 required tools present"
want_said "  ... node is checked against .nvmrc" "node: v26.13.0 (installed by the job's setup step, as ${FIX}/src/.nvmrc pins it)"
want_said "  ... go is checked against go.mod" "go: go version go1.27.3 linux/amd64 (installed by the job's setup step, as ${FIX}/src/go.mod pins it)"
run_installer "${TMP}/pins_setup.txt" "${TMP}/tools_setup.txt" "$SETUP_PATH" FAKE_NODE_VERSION=v24.1.0
want_red "10b: a setup node of another major" "node reports 'v24.1.0', not the v26 that ${FIX}/src/.nvmrc pins"
run_installer "${TMP}/pins_setup.txt" "${TMP}/tools_setup.txt" "$SETUP_PATH" FAKE_GO_VERSION=go1.26.0
want_red "10c: a setup go of another toolchain" "go reports 'go version go1.26.0 linux/amd64', not the go1.27.3 that ${FIX}/src/go.mod pins"
printf 'nosuchtool|kind|setup\nnosuchtool|source|%s\n' "${FIX}/src/.nvmrc" > "${TMP}/pins_nosuch.txt"
printf 'nosuchtool\n' > "${TMP}/tools_nosuch.txt"
run_installer "${TMP}/pins_nosuch.txt" "${TMP}/tools_nosuch.txt" "$SETUP_PATH"
want_red "10d: a setup tool that is not on PATH" "nosuchtool: not on PATH"
printf 'node|kind|setup\nnode|source|%s\n' "${FIX}/reqs.txt" > "${TMP}/pins_badsrc.txt"
printf 'node\n' > "${TMP}/tools_node.txt"
run_installer "${TMP}/pins_badsrc.txt" "${TMP}/tools_node.txt" "$SETUP_PATH"
want_red "10e: a setup source the installer does not know" "node: the setup source ${FIX}/reqs.txt is neither .nvmrc nor go.mod"

# --- Mutation proof: a blind installer accepts the bad fixture.
MROOT="${TMP}/mut"
mkdir -p "${MROOT}/Scripts"
mutant_accepts() {
  local label="$1" expr="$2" pins="$3" tools="${TMP}/tools4.txt"
  shift 3
  if [[ "$#" -gt 0 ]]; then
    tools="$1"
    shift
  fi
  if selftest_mutant "$INSTALLER" "${MROOT}/Scripts/install_tools_linux.sh" "$expr"; then
    RUN_INSTALLER="${MROOT}/Scripts/install_tools_linux.sh" run_installer "$pins" "$tools" "$@"
    if [[ "$RC" -eq 0 ]]; then
      echo "  ok: mutation proof: ${label}"
    else
      fail "mutation proof: ${label} (exit ${RC}) — the case is not what refuses the bad fixture. Output: ${OUT}"
    fi
  fi
}
mutant_accepts "an installer that does not compare the checksum accepts a wrong build" \
  's/^  \[ "[$]got" = "[$]want" \] || die .*$/  true/' "${TMP}/pins_badsum.txt"
mutant_accepts "an installer that does not read the version accepts another one" \
  's/^    \*"[$]{version}"\*) echo/    *) echo/' "${TMP}/pins_oldver.txt"
mutant_accepts "an installer that does not read a setup tool's version accepts another major" \
  's/^  \[ "[$]matched" = yes \] || die .*$/  true/' "${TMP}/pins_setup.txt" "${TMP}/tools_node.txt" \
  "$SETUP_PATH" FAKE_NODE_VERSION=v24.1.0

selftest_end "the Linux tool install is not what the pins promise" \
  "the Linux tool install installs only the pinned, verified builds (and each wrong shape is still detected)"
