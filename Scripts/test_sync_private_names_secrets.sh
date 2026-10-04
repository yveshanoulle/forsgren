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
#   2. a missing names file -> exit 2, a FAIL line naming the file path, no gh call.
#   3. a file with no names (zero bytes; only comments) -> exit 2, no gh call.
#   4. the Actions `gh secret set` fails -> exit 1, a FAIL line about the
#      Actions secret, and the Dependabot call is NOT made.
#   5. Actions succeeds, the Dependabot call fails -> exit 1, a FAIL line
#      about the Dependabot secret.
#   6. in every case, success included, the output holds no name (checked
#      case-insensitively).
#   7. mutation proofs: for each of 2-6 a mutant of the script that breaks
#      exactly that behaviour must fail the very check the case uses.

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
# stdin to numbered files under GH_LOG, and succeeds, unless GH_FAIL_ON names
# its number.
FAKE_BIN="${TMP}/bin"
GH_LOG="${TMP}/gh-log"
mkdir -p "$FAKE_BIN" "$GH_LOG"
cat > "${FAKE_BIN}/gh" <<'FAKE'
#!/usr/bin/env bash
n=$(( $(find "$GH_LOG" -name 'args-*' | wc -l) + 1 ))
printf '%s\n' "$*" > "${GH_LOG}/args-${n}"
cat > "${GH_LOG}/stdin-${n}"
# GH_FAIL_ON=<n>: call number <n> fails (after it was recorded).
[[ "${GH_FAIL_ON:-}" != "$n" ]]
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

# run_sync <script> <names file> [fail-on]: a fresh gh log, then the script
# on that names file; gh call number [fail-on] (default: none) fails.
run_sync() {
  rm -f "${GH_LOG}"/args-* "${GH_LOG}"/stdin-*
  capture env -u FORSGREN_PRIVATE_NAMES HOME="${TMP}/empty-home" \
    FORSGREN_PRIVATE_NAMES_FILE="$2" GH_LOG="$GH_LOG" GH_FAIL_ON="${3:-}" \
    PATH="${FAKE_BIN}:${PATH}" "$1"
}

run_sync "$SYNC" "$NAMES_FILE"

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

# --- the failure paths. Each case_* runs the script given as $1 on its
# scenario and succeeds when the behaviour holds; on failure REASON says what
# was seen. The real script must hold every case; its mutant must not.

# no_name_in_output: succeeds when OUT holds neither name, in any letter case.
no_name_in_output() {
  ! grep -qiF -e "$NAME_A" -e "$NAME_B" <<< "$OUT"
}

# case_missing_file <script>
case_missing_file() {
  local missing="${TMP}/no-such-names-file"
  run_sync "$1" "$missing"
  if [[ "$RC" != "2" ]]; then
    REASON="a missing names file exited ${RC}, not 2. Output: ${OUT}"
  elif ! grep -qF -- "❌ FAIL" <<< "$OUT" || ! grep -qF -- "$missing" <<< "$OUT"; then
    REASON="a missing names file did not give a FAIL line naming ${missing}. Output: ${OUT}"
  elif [[ "$(calls)" != "0" ]]; then
    REASON="a missing names file still made $(calls) gh call(s)"
  else
    return 0
  fi
  return 1
}

# case_no_names <script> <content>: a names file holding only <content>.
case_no_names() {
  printf '%s' "$2" > "${TMP}/no-names-file"
  run_sync "$1" "${TMP}/no-names-file"
  if [[ "$RC" != "2" ]]; then
    REASON="a names file with no names exited ${RC}, not 2. Output: ${OUT}"
  elif ! grep -qF -- "❌ FAIL" <<< "$OUT"; then
    REASON="a names file with no names gave no FAIL line. Output: ${OUT}"
  elif [[ "$(calls)" != "0" ]]; then
    REASON="a names file with no names still made $(calls) gh call(s)"
  else
    return 0
  fi
  return 1
}
case_zero_bytes() { case_no_names "$1" ""; }
case_only_comments() { case_no_names "$1" "$(printf '%s\n# another comment\n\n' "$COMMENT")"; }

# case_actions_fails <script>
case_actions_fails() {
  run_sync "$1" "$NAMES_FILE" 1
  if [[ "$RC" != "1" ]]; then
    REASON="a failing Actions secret exited ${RC}, not 1. Output: ${OUT}"
  elif ! grep -qF -- "❌ FAIL" <<< "$OUT" || ! grep -qF -- "Actions secret" <<< "$OUT"; then
    REASON="a failing Actions secret gave no FAIL line about the Actions secret. Output: ${OUT}"
  elif [[ "$(calls)" != "1" ]]; then
    REASON="after the Actions failure there were $(calls) gh calls, not 1 (the Dependabot call must not be made)"
  elif ! no_name_in_output; then
    REASON="a failing Actions secret printed a name. Output: ${OUT}"
  else
    return 0
  fi
  return 1
}

# case_dependabot_fails <script>
case_dependabot_fails() {
  run_sync "$1" "$NAMES_FILE" 2
  if [[ "$RC" != "1" ]]; then
    REASON="a failing Dependabot secret exited ${RC}, not 1. Output: ${OUT}"
  elif ! grep -qF -- "❌ FAIL" <<< "$OUT" || ! grep -qF -- "Dependabot secret" <<< "$OUT"; then
    REASON="a failing Dependabot secret gave no FAIL line about the Dependabot secret. Output: ${OUT}"
  elif ! no_name_in_output; then
    REASON="a failing Dependabot secret printed a name. Output: ${OUT}"
  else
    return 0
  fi
  return 1
}

# case_output_has_no_name <script>: success, and every failure path above.
case_output_has_no_name() {
  local scenario
  for scenario in "" "1" "2"; do
    run_sync "$1" "$NAMES_FILE" "$scenario"
    if ! no_name_in_output; then
      REASON="the output (gh fails on call '${scenario:-none}') holds a name. Output: ${OUT}"
      return 1
    fi
  done
  run_sync "$1" "${TMP}/no-such-names-file"
  if ! no_name_in_output; then
    REASON="the output of a missing names file holds a name. Output: ${OUT}"
    return 1
  fi
  return 0
}

# holds <case> <function> [args]: the real script holds the case.
holds() {
  local label="$1" fn="$2"
  if "$fn" "$SYNC"; then
    echo "  ok: ${label}"
  else
    fail "${label}: ${REASON}"
  fi
}

holds "a missing names file exits 2, names the file, makes no gh call" case_missing_file
holds "a zero-byte names file exits 2 with no gh call" case_zero_bytes
holds "a comments-only names file exits 2 with no gh call" case_only_comments
holds "a failing Actions secret exits 1, says so, and skips the Dependabot call" case_actions_fails
holds "a failing Dependabot secret exits 1 and says so" case_dependabot_fails
holds "the output never holds a name (success and every failure path)" case_output_has_no_name

# mutation_proof <label> <sed-expression> <case function>: a mutant of the
# script that breaks the behaviour must NOT hold the case, so the case can fail.
MUTANT_N=0
mutation_proof() {
  local label="$1" expr="$2" fn="$3" mutant
  MUTANT_N=$((MUTANT_N + 1))
  mutant="${TMP}/mutant${MUTANT_N}/Scripts/sync_private_names_secrets.sh"
  if selftest_mutant "$SYNC" "$mutant" "$expr"; then
    # The script sources its list parser from beside itself; so does the mutant.
    cp Scripts/lib_private_names.sh "$(dirname "$mutant")/"
    if "$fn" "$mutant"; then
      fail "mutation proof: ${label} was not caught by ${fn}"
    else
      echo "  ok: mutation proof: ${label} is caught (${REASON%%. Output*})"
    fi
  fi
}

mutation_proof "a script that exits 0 on a missing file" \
  '/does not exist/{n;s/exit 2/exit 0/;}' case_missing_file
mutation_proof "a script that skips the no-names count check" \
  's/-eq 0 \]\]; then/-eq 99 ]]; then/' case_zero_bytes
mutation_proof "a script that skips the no-names count check (comments only)" \
  's/-eq 0 \]\]; then/-eq 99 ]]; then/' case_only_comments
mutation_proof "a script that goes on after the Actions failure" \
  's/^    exit 1$/    :/' case_actions_fails
mutation_proof "a script that exits 1 only after it also made the Dependabot call" \
  "s/^    exit 1\$/    FAILED=1/;s/^echo \"OK: synced/[[ -z \"\${FAILED:-}\" ]] || exit 1; \&/" case_actions_fails
mutation_proof "a script that ignores the Dependabot failure" \
  "s/^    exit 1\$/    if [[ \"\$kind\" == Actions ]]; then exit 1; fi/" case_dependabot_fails
mutation_proof "a script that echoes the names on success" \
  "s/^echo \"OK: synced/echo \"\$PRIVATE_NAMES\"; echo \"OK: synced/" case_output_has_no_name
mutation_proof "a script that echoes the names in its FAIL line" \
  "s/could not set the \${kind} secret \${SECRET}/could not set \${PRIVATE_NAMES}/" case_output_has_no_name

selftest_end "the secret sync does not hold its success and failure paths" \
  "secret sync sets FORSGREN_PRIVATE_NAMES for Actions and Dependabot from the names file, comments dropped, names on stdin; fails safe, without printing a name"
