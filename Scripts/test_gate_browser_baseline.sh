#!/usr/bin/env bash
# Scripts/test_gate_browser_baseline.sh (forsgren#642). Not canon: forsgren only.
#
# The browser baselines hold widths in px, and fonts render differently on
# macOS and on Linux, so each site has a baseline file per platform:
# Scripts/gate_browser.sh reads Scripts/browser_gate_baseline.txt on Darwin
# (the local FBP) and Scripts/browser_gate_baseline_linux.txt on Linux
# (Quality's browser jobs on ubuntu-latest), and Scripts/gate_browser_fixture.sh
# the same with browser_gate_fixture_baseline.txt and its _linux twin. The
# choice is Scripts/lib_browser_baseline.sh's, by `uname -s`. This self-test runs
# each real wrapper in a sandbox with `uname` and `node` faked on PATH (the
# fake node prints the baseline it was given and opens no Chrome), so it needs
# neither Chrome nor npm ci and runs on any machine.
#
# CASES, for each wrapper:
#   1. Darwin -> the macOS file
#   2. Linux -> the Linux file
#   3. another platform (FreeBSD) -> exit 2, the platform named, the engine
#      never started (no silent fallback to the macOS file)
#   4. a baseline given as the fourth argument wins on Linux too (the
#      self-tests of the gate pass their own)
#   5. the real Linux file exists (the engine refuses a missing baseline)
# MUTATION PROOFS (each must make a case red for its reason):
#   A. a wrapper that always reads the macOS file: case 2 reads the macOS file
#   B. a library that falls back to the macOS file on an unknown platform:
#      case 3 ends with exit 0 on the macOS file

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "browser gate baseline choice self-test"

LIB="Scripts/lib_browser_baseline.sh"
[[ -f "$LIB" ]] || selftest_abort "${LIB} does not exist"

# The fakes: uname prints FAKE_UNAME; node prints its fifth argument,
# the baseline the wrapper hands Scripts/browser_gate.mjs, and exits 0.
FAKES="${TMP}/fakes"
mkdir -p "$FAKES"
cat > "${FAKES}/uname" <<'S'
#!/usr/bin/env bash
echo "${FAKE_UNAME}"
S
cat > "${FAKES}/node" <<'S'
#!/usr/bin/env bash
echo "engine baseline=${5:-}"
S
chmod 755 "${FAKES}/uname" "${FAKES}/node"

# sandbox <name> [wrapper-source] [lib-source]: a copy of the repository files a
# wrapper needs, the wrapper and the library from the given sources (a mutant)
# or the real ones, with an empty node_modules/puppeteer-core and axe-core.
sandbox() {
  local root="${TMP}/$1" wrapper="${2:-}" lib="${3:-$LIB}" w
  mkdir -p "${root}/Scripts" "${root}/node_modules/puppeteer-core" "${root}/node_modules/axe-core" "${root}/site"
  cp Scripts/lib_tmp.sh Scripts/lib_site_settings.sh Scripts/site_settings.txt "${root}/Scripts/"
  cp "$lib" "${root}/Scripts/lib_browser_baseline.sh"
  for w in gate_browser gate_browser_fixture; do
    cp "Scripts/${w}.sh" "${root}/Scripts/${w}.sh"
  done
  if [[ -n "$wrapper" ]]; then
    cp "$wrapper" "${root}/Scripts/$(basename "$wrapper")"
  fi
  echo "$root"
}

# run_wrapper <root> <wrapper> <platform> [baseline]: OUT and RC of the wrapper
# on the sandbox's site, with the fakes first on PATH.
run_wrapper() {
  local root="$1" wrapper="$2" platform="$3"
  shift 3
  capture env PATH="${FAKES}:${PATH}" FAKE_UNAME="$platform" "${root}/Scripts/${wrapper}.sh" "${root}/site" "" "" "$@"
}

# choice_why <want>: empty when the last run handed the engine <want>, else why
# not. <want> `refused` means exit 2 with the platform named and no engine.
choice_why() {
  local got
  got="$(sed -n 's/^engine baseline=//p' <<< "$OUT")"
  if [[ "$1" == refused ]]; then
    [[ -z "$got" ]] || { echo "the engine was started with ${got} on ${PLATFORM} (a fallback, not a refusal)"; return 0; }
    [[ "$RC" -eq 2 ]] || { echo "exit ${RC}, not 2, on ${PLATFORM}"; return 0; }
    grep -qF -- "no baseline for the platform '${PLATFORM}'" <<< "$OUT" || echo "the refusal does not name ${PLATFORM}: ${OUT}"
    return 0
  fi
  [[ "$RC" -eq 0 ]] || { echo "exit ${RC} on ${PLATFORM}: ${OUT}"; return 0; }
  [[ "$got" == "$1" ]] || echo "read ${got:-nothing}, not $1, on ${PLATFORM}"
}

# expect <label> <want>: the last run's choice is <want>.
expect() {
  local why
  why="$(choice_why "$2")"
  if [[ -z "$why" ]]; then echo "  ok: $1"; else fail "$1: ${why}"; fi
}

# The wrappers and their two files.
WRAPPERS=(
  "gate_browser|Scripts/browser_gate_baseline.txt|Scripts/browser_gate_baseline_linux.txt"
  "gate_browser_fixture|Scripts/browser_gate_fixture_baseline.txt|Scripts/browser_gate_fixture_baseline_linux.txt"
)
REAL="$(sandbox real)"
for entry in "${WRAPPERS[@]}"; do
  IFS='|' read -r w mac linux <<< "$entry"
  PLATFORM=Darwin
  run_wrapper "$REAL" "$w" "$PLATFORM"
  expect "1: ${w}.sh on Darwin reads ${mac}" "$mac"
  PLATFORM=Linux
  run_wrapper "$REAL" "$w" "$PLATFORM"
  expect "2: ${w}.sh on Linux reads ${linux}" "$linux"
  PLATFORM=FreeBSD
  run_wrapper "$REAL" "$w" "$PLATFORM"
  expect "3: ${w}.sh on another platform refuses, naming it" refused
  PLATFORM=Linux
  run_wrapper "$REAL" "$w" "$PLATFORM" "${TMP}/given.txt"
  expect "4: ${w}.sh on Linux reads a baseline given as its fourth argument" "${TMP}/given.txt"
  if [[ -f "$linux" ]]; then
    echo "  ok: 5: ${linux} exists"
  else
    fail "5: ${linux} does not exist: the browser jobs on ubuntu-latest would stop with exit 2"
  fi
done

# A: each wrapper made to read its macOS file on every platform.
for entry in "${WRAPPERS[@]}"; do
  IFS='|' read -r w mac linux <<< "$entry"
  if selftest_mutant "Scripts/${w}.sh" "${TMP}/mut_a/${w}.sh" "s#${linux}#${mac}#"; then
    root="$(sandbox "a_${w}" "${TMP}/mut_a/${w}.sh")"
    PLATFORM=Linux
    run_wrapper "$root" "$w" "$PLATFORM"
    why="$(choice_why "$linux")"
    if [[ "$why" == "read ${mac}, not ${linux}, on Linux" ]]; then
      echo "  ok: mutation proof A: ${w}.sh reading the macOS file on Linux is red (${why})"
    else
      fail "mutation proof A: ${w}.sh reading the macOS file on Linux was not red for that reason (${why:-green})"
    fi
  fi
done

# B: the library falling back to the macOS file on a platform it does not know.
# The refusal's `return 2` becomes a print of the first argument, the macOS file.
FALLBACK_EXPR="s#^      return 2\$#      printf '%s\\\\n' \"\$1\"#"
if selftest_mutant "$LIB" "${TMP}/mut_b/lib_browser_baseline.sh" "$FALLBACK_EXPR"; then
  root="$(sandbox b "" "${TMP}/mut_b/lib_browser_baseline.sh")"
  for entry in "${WRAPPERS[@]}"; do
    IFS='|' read -r w mac linux <<< "$entry"
    PLATFORM=FreeBSD
    run_wrapper "$root" "$w" "$PLATFORM"
    why="$(choice_why refused)"
    if [[ "$why" == "the engine was started with ${mac} on FreeBSD (a fallback, not a refusal)" ]]; then
      echo "  ok: mutation proof B: ${w}.sh falling back to the macOS file on FreeBSD is red (${why})"
    else
      fail "mutation proof B: ${w}.sh falling back on FreeBSD was not red for that reason (${why:-green})"
    fi
  done
fi

selftest_end "the browser gates do not read the baseline of their platform" \
  "each browser gate reads the baseline of its platform, Darwin's or Linux's, and refuses any other (and each wrong shape is still detected)"
