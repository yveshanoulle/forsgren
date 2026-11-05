#!/usr/bin/env bash
# Fixture (estate issue 610): the temporary forwarder FullBuildAndPush.sh passes
# every argument to FBP.sh unchanged (spaces, quotes, empty arguments, a
# leading dash) and returns FBP.sh's exit code. The sandbox holds a copy of
# the real forwarder next to a fake FBP.sh that records its arguments, one per
# line, and exits with the code the test asks for. The real FBP.sh is never run.
#
# Runs in CI from the repository's validate workflow.
# Local invocation: ./Scripts/test_fullbuildandpush_forwarder.sh

set -uo pipefail
# shellcheck source=Scripts/lib_tmp.sh
. "$(dirname "$0")/lib_tmp.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(tmp_dir test_fullbuildandpush_forwarder)" || exit 1
trap 'rm -rf "$SANDBOX"' EXIT

cp "${ROOT}/FullBuildAndPush.sh" "${SANDBOX}/FullBuildAndPush.sh"
chmod +x "${SANDBOX}/FullBuildAndPush.sh"
cat > "${SANDBOX}/FBP.sh" <<'FAKE'
#!/usr/bin/env bash
: > "$(dirname "$0")/args.txt"
for a in "$@"; do printf '%s\n' "$a" >> "$(dirname "$0")/args.txt"; done
exit "${FAKE_FBP_EXIT:-0}"
FAKE
chmod +x "${SANDBOX}/FBP.sh"

failed=0
fail() { echo "FAIL: $1"; failed=1; }

# Arguments with a space, quotes, an empty argument, a leading dash, a double space.
expected="$(printf '%s\n' 'fix: a message with spaces' "it's \"quoted\"" '' '--all' 'x  y')"
FAKE_FBP_EXIT=0 "${SANDBOX}/FullBuildAndPush.sh" 'fix: a message with spaces' "it's \"quoted\"" '' '--all' 'x  y'
rc=$?
actual="$(cat "${SANDBOX}/args.txt")"
if [ "$actual" = "$expected" ]; then
  echo "OK: all arguments reach FBP.sh unchanged"
else
  fail "arguments changed on the way; got: ${actual}"
fi
if [ "$rc" -eq 0 ]; then
  echo "OK: exit 0 is returned"
else
  fail "exit 0 became ${rc}"
fi

# No arguments at all.
FAKE_FBP_EXIT=0 "${SANDBOX}/FullBuildAndPush.sh"
if [ -f "${SANDBOX}/args.txt" ] && [ ! -s "${SANDBOX}/args.txt" ]; then
  echo "OK: no arguments stays no arguments"
else
  fail "a call without arguments reached FBP.sh with arguments"
fi

# Exit codes pass through.
for code in 1 2 7 143; do
  FAKE_FBP_EXIT="$code" "${SANDBOX}/FullBuildAndPush.sh" x
  rc=$?
  if [ "$rc" -eq "$code" ]; then
    echo "OK: exit ${code} is returned"
  else
    fail "FBP.sh exited ${code}, the forwarder returned ${rc}"
  fi
done

# Called through a relative path, it still finds the FBP.sh next to itself.
(cd "$SANDBOX" && FAKE_FBP_EXIT=5 ./FullBuildAndPush.sh rel)
rc=$?
if [ "$rc" -eq 5 ] && [ "$(cat "${SANDBOX}/args.txt")" = "rel" ]; then
  echo "OK: finds FBP.sh next to itself via a relative path"
else
  fail "relative call: exit ${rc}, args '$(cat "${SANDBOX}/args.txt")'"
fi

if [ "$failed" -ne 0 ]; then
  echo "❌ FAIL: the FullBuildAndPush.sh forwarder does not pass through faithfully"
  exit 1
fi
echo "OK: the FullBuildAndPush.sh forwarder passes arguments and exit code through"
