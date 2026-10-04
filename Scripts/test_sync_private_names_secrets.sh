#!/usr/bin/env bash
# Scripts/test_sync_private_names_secrets.sh
#
# Self-test for Scripts/sync_private_names_secrets.sh (forsgren#52, step 3).
# The script copies the private-names list from its local file into the two
# GitHub secrets the private-names gate reads in CI: the Actions secret and
# the Dependabot secret, both named FORSGREN_PRIVATE_NAMES. Every name below
# is made up (acme-data, widget-app); none is a real repository.
#
# The script's interface, as pinned here:
#   Scripts/sync_private_names_secrets.sh
#   list source: the file FORSGREN_PRIVATE_NAMES_FILE, else
#   $HOME/.config/forsgren/private-names (the rule of check_private_names.sh);
#   lines starting with # are not names.
#   It calls `gh` twice, the list on stdin, never as an argument:
#     gh secret set FORSGREN_PRIVATE_NAMES -R yveshanoulle/forsgren
#     gh secret set FORSGREN_PRIVATE_NAMES --app dependabot -R yveshanoulle/forsgren
#   and never prints a name.
#
#   1. a file with a comment and two names -> exactly two gh calls (Actions,
#      Dependabot), each fed the two names and not the comment on stdin.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

SYNC="$(pwd)/Scripts/sync_private_names_secrets.sh"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "private-names secret sync self-test"

if [[ ! -x "$SYNC" ]]; then
  selftest_abort "Scripts/sync_private_names_secrets.sh is missing or not executable: nothing to test"
fi

NAME_A="acme-data"
NAME_B="widget-app"
COMMENT="# made-up private names"

NAMES_FILE="${TMP}/names-file"
printf '%s\n%s\n%s\n' "$COMMENT" "$NAME_A" "$NAME_B" > "$NAMES_FILE"

# A fake gh first on PATH: each call writes its arguments (one line) and its
# stdin to numbered files under GH_LOG, and succeeds.
FAKE_BIN="${TMP}/bin"
GH_LOG="${TMP}/gh-log"
mkdir -p "$FAKE_BIN" "$GH_LOG"
cat > "${FAKE_BIN}/gh" <<'FAKE'
#!/usr/bin/env bash
n=$(( $(find "$GH_LOG" -name 'args-*' | wc -l) + 1 ))
printf '%s\n' "$*" > "${GH_LOG}/args-${n}"
cat > "${GH_LOG}/stdin-${n}"
FAKE
chmod +x "${FAKE_BIN}/gh"

# calls: the number of gh calls recorded.
calls() {
  find "$GH_LOG" -name 'args-*' | wc -l | tr -d ' '
}

# call_has_args <n> <args>: succeeds when gh call <n> had exactly the argument text <args>.
call_has_args() {
  [[ -f "${GH_LOG}/args-$1" ]] && grep -qxF -- "$2" "${GH_LOG}/args-$1"
}

# call_stdin_is_names <n>: succeeds when stdin of call <n> was exactly the two names.
call_stdin_is_names() {
  [[ -f "${GH_LOG}/stdin-$1" ]] \
    && [[ "$(cat "${GH_LOG}/stdin-$1")" == "$(printf '%s\n%s' "$NAME_A" "$NAME_B")" ]]
}

capture env -u FORSGREN_PRIVATE_NAMES HOME="${TMP}/empty-home" \
  FORSGREN_PRIVATE_NAMES_FILE="$NAMES_FILE" GH_LOG="$GH_LOG" \
  PATH="${FAKE_BIN}:${PATH}" "$SYNC"

want_rc "the sync of a names file succeeds" 0

if [[ "$(calls)" == "2" ]]; then
  echo "  ok: exactly two gh calls"
else
  fail "expected exactly 2 gh calls, got $(calls). Output: ${OUT}"
fi

ARGS_ACTIONS="secret set FORSGREN_PRIVATE_NAMES -R yveshanoulle/forsgren"
ARGS_DEPENDABOT="secret set FORSGREN_PRIVATE_NAMES --app dependabot -R yveshanoulle/forsgren"
if call_has_args 1 "$ARGS_ACTIONS" && call_has_args 2 "$ARGS_DEPENDABOT"; then
  echo "  ok: the calls are the Actions secret, then the Dependabot secret"
else
  fail "expected gh call 1 '${ARGS_ACTIONS}' and call 2 '${ARGS_DEPENDABOT}'; got: $(cat "${GH_LOG}"/args-* 2>/dev/null | tr '\n' ';')"
fi

for n in 1 2; do
  if call_stdin_is_names "$n"; then
    echo "  ok: gh call ${n} got the two names, without the comment, on stdin"
  else
    fail "gh call ${n} did not get exactly the two names on stdin. Stdin: $(cat "${GH_LOG}/stdin-${n}" 2>/dev/null || echo '(no such call)')"
  fi
done

selftest_end "the secret sync does not hand the names, without comments, to both the Actions and the Dependabot secret" \
  "secret sync sets FORSGREN_PRIVATE_NAMES for Actions and Dependabot from the names file, comments dropped, names on stdin"
