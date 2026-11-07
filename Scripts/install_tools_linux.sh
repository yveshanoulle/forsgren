#!/usr/bin/env bash
# Scripts/install_tools_linux.sh [tools-file]
#
# The Linux counterpart of Scripts/install_tools.sh (forsgren#427), not canon:
# forsgren's own. The Lint gates job of quality.yml calls it with a tools file
# in place of install_tools.sh, which stays the estate's byte-identical copy;
# Homebrew is not used here.
#
# Each tool named in the tools file is installed from the pinned build in
# Scripts/linux_tool_pins.txt:
#   - an archive is downloaded, its sha256 compared with the pin BEFORE
#     anything is unpacked, and the one member the pin names is copied out;
#   - a Python tool (yamllint) is installed into its own virtual environment
#     with `pip install --require-hashes --only-binary=:all: --no-deps` from a
#     requirements file whose every line carries a hash;
#   - a setup tool (forsgren#642: node and go for the browser jobs) is not
#     installed here: the job's own pinned setup step installed it before this
#     one (actions/setup-node from .nvmrc, actions/setup-go from go.mod), and
#     this script runs it from PATH and holds it to the version that file pins.
# Nothing is piped into a shell and no package manager is asked for "the
# newest". After the install each tool is RUN and must report the pinned
# version: a tool that is present but another version is red, because the hosted
# image ships its own shellcheck and it must not be the one the gates use.
#
# The tools go to a directory of their own (INSTALL_TOOLS_BIN, default
# ${RUNNER_TEMP:-/tmp}/pinned-tools/bin), which is put first on PATH here and
# appended to GITHUB_PATH for the steps after this one.
#
# Seams for Scripts/test_install_tools_linux.sh: CURL, PYTHON3, PINS_FILE,
# INSTALL_TOOLS_BIN, INSTALL_TOOLS_ARCH (default `uname -m`).

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

TOOLS_FILE="${1:-Scripts/required_tools_linux.txt}"
PINS_FILE="${PINS_FILE:-Scripts/linux_tool_pins.txt}"
CURL="${CURL:-curl}"
PYTHON3="${PYTHON3:-python3}"
ARCH="${INSTALL_TOOLS_ARCH:-$(uname -m)}"
BIN="${INSTALL_TOOLS_BIN:-${RUNNER_TEMP:-/tmp}/pinned-tools/bin}"

# shellcheck source=Scripts/lib_tmp.sh
source Scripts/lib_tmp.sh
WORK="$(tmp_dir install_tools_linux_work)"
# The trap is set before any check, so every exit, a refusal included, cleans up.
# COMPLETED is the last statement of a finished run. The trap turns an abort
# that would otherwise end with exit 0 (bash 3.2 under set -e) into exit 1.
COMPLETED=0
cleanup() {
  local rc=$?
  rm -rf "$WORK"
  if [ "$COMPLETED" -ne 1 ]; then
    echo "❌ FAIL: the Linux tool install aborted before completing" >&2
    [ "$rc" -ne 0 ] || rc=1
    exit "$rc"
  fi
}
trap cleanup EXIT

die() {
  echo "❌ FAIL: $*" >&2
  exit 1
}

case "$ARCH" in
  x86_64 | amd64) ;;
  *) die "the pins in ${PINS_FILE} are x86_64 Linux builds, this machine is ${ARCH} — \
a build for another CPU needs its own pin and checksum" ;;
esac

[ -f "$TOOLS_FILE" ] || die "no tool list at ${TOOLS_FILE} — the gates needing a tool would run against \
whatever happens to be on this machine"
[ -f "$PINS_FILE" ] || die "no pin list at ${PINS_FILE} — nothing says which build of a tool to trust"

tools=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [ -n "$line" ] || continue
  tools+=("$line")
done < "$TOOLS_FILE"

# Non-vacuity, before any expansion of the array (empty is fatal on bash 3.2).
[ "${#tools[@]}" -gt 0 ] || die "${TOOLS_FILE} declares no tools — this run would install nothing, \
check nothing, and report success"

# sha256_of <file>: sha256sum on Linux, shasum where that is what exists.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# pin_get <tool> <field>: the value of that field of the tool's pin, empty
# when the pin list has none.
pin_get() {
  local row
  while IFS= read -r row || [ -n "$row" ]; do
    case "$row" in '' | '#'*) continue ;; esac
    case "$row" in
      "$1|$2|"*)
        printf '%s\n' "${row#"$1|$2|"}"
        return 0
        ;;
    esac
  done < "$PINS_FILE"
}

mkdir -p "$BIN"

install_archive() {
  local tool="$1" url="$2" want="$3" member="$4" file got dir
  dir="${WORK}/${tool}"
  mkdir -p "$dir"
  file="${dir}/archive.tar.gz"
  "$CURL" -fsSL --retry 3 -o "$file" "$url" || die "${tool}: the download of ${url} failed"
  got="$(sha256_of "$file")"
  [ "$got" = "$want" ] || die "${tool}: the sha256 of ${url} is ${got}, the pin says ${want} — refusing to unpack it"
  mkdir -p "${dir}/x"
  tar -xzf "$file" -C "${dir}/x" "$member" || die "${tool}: ${member} is not in the archive"
  cp "${dir}/x/${member}" "${BIN}/${tool}"
  chmod 755 "${BIN}/${tool}"
}

install_pip() {
  local tool="$1" reqs="$2" venv
  [ -f "$reqs" ] || die "${tool}: no requirements file at ${reqs}"
  grep -q -- '--hash=sha256:' "$reqs" || die "${tool}: ${reqs} carries no --hash line — \
an unhashed install would trust whatever PyPI serves"
  # The environment lives next to the tools: its scripts name their own path.
  venv="$(dirname "$BIN")/${tool}-venv"
  rm -rf "$venv"
  "$PYTHON3" -m venv "$venv" || die "${tool}: creating the virtual environment failed"
  "${venv}/bin/pip" install --quiet --disable-pip-version-check --require-hashes \
    --only-binary=:all: --no-deps -r "$reqs" \
    || die "${tool}: pip install from ${reqs} failed"
  ln -sf "${venv}/bin/${tool}" "${BIN}/${tool}"
}

# check_setup <tool> <source>: a tool the job's setup step installed. It must be
# on PATH and report the version <source> pins: .nvmrc holds Node's major (node
# --version starts with v<major>.), go.mod's toolchain line the exact Go (go
# version names it). A source of another name has no version to read: red.
check_setup() {
  local tool="$1" src="$2" want reported matched=no
  command -v "$tool" >/dev/null 2>&1 || die "${tool}: not on PATH — its pin says the job's own setup step \
installs it (from ${src}), and no such step put it there before this one"
  case "$(basename "$src")" in
    .nvmrc)
      [ -f "$src" ] || die "${tool}: no ${src} to read the Node major from"
      want="v$(tr -d '[:space:]' < "$src")"
      reported="$("$tool" --version 2>&1 | head -1)" || true
      case "$reported" in "${want}."*) matched=yes ;; esac
      ;;
    go.mod)
      want="$(Scripts/go_toolchain.sh "$src")" || die "${tool}: ${src} names no toolchain"
      reported="$("$tool" version 2>&1 | head -1)" || true
      case "$reported" in *" ${want} "*) matched=yes ;; esac
      ;;
    *) die "${tool}: the setup source ${src} is neither .nvmrc nor go.mod — there is no version to hold it to" ;;
  esac
  [ "$matched" = yes ] || die "${tool} reports '${reported}', not the ${want} that ${src} pins: the gates would run another version"
  echo "✅ ${tool}: ${reported} (installed by the job's setup step, as ${src} pins it)"
}

for tool in "${tools[@]}"; do
  kind="$(pin_get "$tool" kind)"
  if [ "$kind" = setup ]; then
    check_setup "$tool" "$(pin_get "$tool" source)"
    continue
  fi
  version="$(pin_get "$tool" version)"
  [ -n "$version" ] || die "${tool} has no pin in ${PINS_FILE} — there is no pinned Linux build to install, \
and the gates needing it would run against nothing"
  src="$(pin_get "$tool" source)"
  url="$(pin_get "$tool" release)/$(pin_get "$tool" file)"
  case "$kind" in
    archive) install_archive "$tool" "$url" "$(pin_get "$tool" sha256)" "$(pin_get "$tool" member)" ;;
    pip) install_pip "$tool" "$src" ;;
    *) die "${tool}: the pin has kind '${kind}', not archive or pip" ;;
  esac
  # THE CHECK THIS SCRIPT EXISTS FOR: run the tool, from the directory it was
  # installed to, and read the version it reports.
  reported="$(PATH="${BIN}:${PATH}" "${BIN}/${tool}" --version 2>&1 | head -3 | tr '\n' ' ')" || true
  case "$reported" in
    *"${version}"*) echo "✅ ${tool} ${version} (installed from the pinned build)" ;;
    *) die "${tool} was installed but reports '${reported}', not ${version} — \
the gates would run another version than the pin" ;;
  esac
done

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$BIN" >> "$GITHUB_PATH"
fi

echo "OK: ${#tools[@]} required tools present (Linux, pinned builds in ${BIN})"
COMPLETED=1
