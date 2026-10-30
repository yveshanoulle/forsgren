#!/usr/bin/env bash
# Scripts/test_release_verify_install.sh
#
# Self-test for Scripts/release_verify_install.sh (forsgren#237, step 5a): after
# a release is published and before any pin moves, `go install` of the module
# at the released sha must report the release (vX.Y.Z), not a pseudo-version.
# No network: a stub go on PATH installs a fake binary and answers
# `go version -m` with the module version the case sets (STUB_MOD).
#   1. the release version                                 -> OK, installed by the sha
#   2. a pseudo-version                                    -> red, and the ::error:: says
#      what installations show meanwhile (dev, a development build),
#      that resume: pins reruns the check and that no pin must move
#   3. a pseudo-version first, the release on the 2nd try  -> OK (the proxy catches up)
#   4. a pseudo-version every time                         -> red after exactly the tries
#   5. go install fails                                    -> red
#   6. the install goes to a temporary GOBIN, never the caller's
#   7. usage errors                                        -> exit 2
#   8. the install leaves a read-only module cache in its temporary GOPATH,
#      as the go tool does                                 -> OK, the
#      temporary directory is gone and no rm line is printed (forsgren#575)
#   9. the temporary directory cannot be removed           -> red, named
# Mutation proofs: a copy that accepts any module version must let the
# pseudo-version pass; a copy that does not retry must refuse case 3; a copy
# that removes the temporary directory without making it writable first must
# fail case 8 on that removal, named.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "release verify install self-test"

VERIFY="Scripts/release_verify_install.sh"
[[ -f "$VERIFY" ]] || selftest_abort "${VERIFY} does not exist — a pin could move onto a sha that reports a pseudo-version"

D='$'
SHA="0123456789abcdef0123456789abcdef01234567"
PSEUDO="v1.11.2-0.20261020113112-0123456789ab"

STUBS="${TMP}/bin"
mkdir -p "$STUBS"
cat > "${STUBS}/go" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  install)
    printf 'install %s GOBIN=%s\n' "$2" "${GOBIN:-}" >> "${STUB_LOG:?}"
    if [ -f "${STUB_DIR:?}/install_fails" ]; then echo "go: module not found" >&2; exit 1; fi
    mkdir -p "$GOBIN"
    : > "${GOBIN}/forsgren"
    if [ -f "${STUB_DIR}/modcache" ]; then
      mkdir -p "${GOPATH:?}/pkg/mod/github.com/acme/dep@v1.0.0"
      : > "${GOPATH}/pkg/mod/github.com/acme/dep@v1.0.0/dep.go"
      chmod -R a-w "${GOPATH}/pkg/mod"
    fi
    ;;
  version)
    n=$(($(cat "${STUB_DIR}/count" 2> /dev/null || echo 0) + 1))
    echo "$n" > "${STUB_DIR}/count"
    mods="${STUB_MODS:?}"
    mod="$(printf '%s\n' "$mods" | sed -n "${n}p")"
    [ -n "$mod" ] || mod="$(printf '%s\n' "$mods" | tail -n 1)"
    printf '%s: go1.26\n\tpath\tgithub.com/acme/forsgren/cmd/forsgren\n\tmod\tgithub.com/acme/forsgren\t%s\th1:abc\n' "$3" "$mod"
    ;;
esac
STUB
chmod +x "${STUBS}/go"
# A stub rm: refuses the temporary directory itself when the case asks it to,
# and hands every other call to the real rm.
REAL_RM="$(command -v rm)"
cat > "${STUBS}/rm" <<STUB
#!/usr/bin/env bash
last="${D}{*: -1}"
if [ -f "${D}{STUB_DIR:?}/rm_fails" ] && [[ "${D}last" == */forsgren-verify.* && "${D}last" != */bin ]]; then
  echo "rm: ${D}last: Operation not permitted" >&2
  exit 1
fi
exec "${REAL_RM}" "${D}@"
STUB
chmod +x "${STUBS}/rm"

# setup <mod>...: one module version per `go version -m` call; the last repeats.
setup() {
  rm -rf "${TMP}/stub"
  mkdir -p "${TMP}/stub"
  : > "${TMP}/go.log"
  STUB_MODS="$(printf '%s\n' "$@")"
  export STUB_MODS
}

run() {
  mkdir -p "${TMP}/verify-tmp"
  TMPDIR="${TMP}/verify-tmp" GITHUB_REPOSITORY=acme/forsgren PATH="${STUBS}:${PATH}" STUB_LOG="${TMP}/go.log" STUB_DIR="${TMP}/stub" \
    RELEASE_VERIFY_TRIES="${TRIES:-3}" RELEASE_VERIFY_DELAY=0 capture "${SCRIPT:-$VERIFY}" "$@"
}

setup v1.12.0
run 1.12.0 "$SHA"
want_green "the release version" "OK: go install at ${SHA} reports v1.12.0"
if grep -qF "install github.com/acme/forsgren/cmd/forsgren@${SHA} " "${TMP}/go.log"; then
  echo "  ok: the module is installed by the sha"
else
  fail "go was not asked to install the module at the sha. Log: $(cat "${TMP}/go.log")"
fi
if grep -qE "GOBIN=/.*/forsgren-verify[.]" "${TMP}/go.log"; then
  echo "  ok: the install goes to a temporary GOBIN, never the caller's"
else
  fail "the install did not use its own temporary GOBIN. Log: $(cat "${TMP}/go.log")"
fi

setup "$PSEUDO"
run 1.12.0 "$SHA"
want_red "a pseudo-version" "::error::"
want_said "it names what go reports" "reports ${PSEUDO}, not v1.12.0"
want_said "it says what installations show meanwhile" "installations show dev (a development build"
want_said "it names no release" "that names no release; forsgren#340"
want_said "it says resume pins reruns the check" "resume: pins"
want_said "it says no pin may move" "Do not move any pin"

setup "$PSEUDO" v1.12.0
run 1.12.0 "$SHA"
want_green "a pseudo-version, then the release" "OK: go install at ${SHA} reports v1.12.0"

setup "$PSEUDO"
TRIES=2 run 1.12.0 "$SHA"
want_red "a pseudo-version every time" "after 2 tries"
if [[ "$(grep -c '^install' "${TMP}/go.log")" -ne 2 ]]; then fail "the tries were not exactly 2. Log: $(cat "${TMP}/go.log")"; else echo "  ok: the tries are bounded"; fi

setup v1.12.0
touch "${TMP}/stub/install_fails"
run 1.12.0 "$SHA"
want_red "go install fails" "go install failed"

# leftover: the temporary install directories a run left behind, made
# writable so the self-test's own cleanup can remove them.
leftover() {
  find "${TMP}/verify-tmp" -mindepth 1 -maxdepth 1 -name 'forsgren-verify.*' | wc -l | tr -d ' '
}
clear_leftover() {
  chmod -R u+w "${TMP}/verify-tmp"
  "$REAL_RM" -rf "${TMP}/verify-tmp"
}

clear_leftover
setup v1.12.0
touch "${TMP}/stub/modcache"
run 1.12.0 "$SHA"
want_green "a read-only module cache in the temporary GOPATH" "OK: go install at ${SHA} reports v1.12.0"
if [[ "$(leftover)" -ne 0 ]]; then
  fail "the temporary install directory was left behind with its module cache: $(ls "${TMP}/verify-tmp")"
else
  echo "  ok: the temporary install directory and its read-only module cache are removed"
fi
if grep -qF "cannot remove" <<< "$OUT" || grep -qF "Permission denied" <<< "$OUT"; then
  fail "the cleanup printed rm errors. Output: ${OUT}"
else
  echo "  ok: the cleanup prints no rm error"
fi
clear_leftover

setup v1.12.0
touch "${TMP}/stub/rm_fails"
run 1.12.0 "$SHA"
want_red "the temporary directory cannot be removed" "❌ FAIL: release verify install: cannot remove the temporary install directory"
want_said "it names the cause" "Operation not permitted"
clear_leftover

run 1.12 "$SHA"
want_exit "a malformed version" 2 "usage"
run 1.12.0 abc
want_exit "a short sha" 2 "usage"
run 1.12.0
want_exit "no sha" 2 "usage"

# Mutation proofs.
mutant() {
  selftest_mutant "$VERIFY" "${TMP}/mut/$1/release_verify_install.sh" "$2" || return 1
  SCRIPT="${TMP}/mut/$1/release_verify_install.sh"
}
if mutant anyversion "s/if \\[ \"[\$]found\" = \"v[\$]{VERSION}\" \\]; then/if [ -n \"${D}found\" ]; then/"; then
  setup "$PSEUDO"
  run 1.12.0 "$SHA"
  if [[ "$RC" -ne 0 ]]; then
    fail "mutation proof: the mutant that accepts any module version still refused a pseudo-version. Output: ${OUT}"
  else
    echo "  ok: mutation proof: without the version check a pseudo-version passes"
  fi
fi
if mutant noretry "s/while \\[ \"[\$]try\" -lt \"[\$]TRIES\" \\]; do/while [ \"${D}try\" -lt 1 ]; do/"; then
  setup "$PSEUDO" v1.12.0
  run 1.12.0 "$SHA"
  if [[ "$RC" -eq 0 ]]; then
    fail "mutation proof: the mutant that tries once still accepted the second try"
  else
    echo "  ok: mutation proof: without the retry the late tag is missed"
  fi
fi
if mutant nochmod "s/chmod -R u+w \"[\$]WORK\" 2>&1 \&\& //"; then
  setup v1.12.0
  touch "${TMP}/stub/modcache"
  run 1.12.0 "$SHA"
  if [[ "$RC" -ne 0 ]] && grep -qF "cannot remove the temporary install directory" <<< "$OUT"; then
    echo "  ok: mutation proof: without making the module cache writable the removal fails, named"
  else
    fail "mutation proof: the mutant that does not make the module cache writable did not fail on its removal (exit ${RC}). Output: ${OUT}"
  fi
  clear_leftover
fi
unset SCRIPT

selftest_end "the install check does not hold" "release verify install: the release version passes and its temporary directory is removed, a pseudo-version, a failed install, a failed cleanup and bad arguments are refused"
