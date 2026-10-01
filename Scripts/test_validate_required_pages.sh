#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Self-test for validate_required_pages.sh.
#
# internal/page/required-pages.json is part of the release artifact: promotion to live
# reads it from the promoted release and verifies every declared page over
# HTTP. A malformed manifest must therefore be caught BEFORE the release is
# promotable — otherwise promotion silently degrades into an ambiguous partial
# check, which is the weak verification this whole arc exists to remove.
#
# Every case below is a way a manifest can be wrong while still looking
# plausible in a diff.

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILURES=0
check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✅ $name"
  else
    echo "  ❌ $name — expected exit $expected, got $actual"
    FAILURES=$((FAILURES + 1))
  fi
}

# Runs the validator without set -e killing the fixture on the expected reds.
run_validator() { # <manifest-path> -> sets OUT and RC
  set +e
  OUT="$(./Scripts/validate_required_pages.sh "$1" 2>&1)"
  RC=$?
  set -e
}

write_manifest() { # <name> <json body>
  printf '%s\n' "$2" > "$TMP/$1.json"
  echo "$TMP/$1.json"
}

echo "test_validate_required_pages"

# --- Accepts a well-formed manifest ---------------------------------------
m="$(write_manifest valid '{"requiredPages":["/","/privacy.html","/privacy_nl.html"]}')"
run_validator "$m"
check "accepts a well-formed manifest" 0 "$RC"

# --- The shipped manifest must itself be valid ----------------------------
# Without this the validator could be green while the file it guards is not.
run_validator "internal/page/required-pages.json"
check "accepts the shipped internal/page/required-pages.json" 0 "$RC"

# --- Missing file ---------------------------------------------------------
# For Konenki the manifest is mandatory: absence is an invalid release, never a
# quiet fallback to index-only verification.
run_validator "$TMP/does-not-exist.json"
check "rejects a missing manifest" 1 "$RC"

# --- Not JSON at all ------------------------------------------------------
m="$(write_manifest broken '{"requiredPages": ["/",}')"
run_validator "$m"
check "rejects invalid JSON" 1 "$RC"

# --- Schema: the key is absent -------------------------------------------
m="$(write_manifest nokey '{"pages":["/"]}')"
run_validator "$m"
check "rejects a manifest without requiredPages" 1 "$RC"

# --- Schema: not an array -------------------------------------------------
m="$(write_manifest notarray '{"requiredPages":"/privacy.html"}')"
run_validator "$m"
check "rejects requiredPages that is not an array" 1 "$RC"

# --- Empty list -----------------------------------------------------------
# An empty list would make promotion verify nothing and still report success.
m="$(write_manifest empty '{"requiredPages":[]}')"
run_validator "$m"
check "rejects an empty requiredPages list" 1 "$RC"

# --- Non-string entry -----------------------------------------------------
m="$(write_manifest nonstring '{"requiredPages":["/",42]}')"
run_validator "$m"
check "rejects a non-string entry" 1 "$RC"

# --- Absolute URL ---------------------------------------------------------
# A scheme/host would let a manifest point verification at a site other than
# the one being promoted — a green promotion proving nothing about live.
m="$(write_manifest scheme '{"requiredPages":["/","https://example.com/privacy.html"]}')"
run_validator "$m"
check "rejects an entry with a scheme and host" 1 "$RC"

# --- Protocol-relative URL ------------------------------------------------
m="$(write_manifest protorel '{"requiredPages":["/","//example.com/privacy.html"]}')"
run_validator "$m"
check "rejects a protocol-relative entry" 1 "$RC"

# --- Not root-relative ----------------------------------------------------
# Entries are joined onto a base URL, so a missing leading slash silently
# changes which path is checked.
m="$(write_manifest noslash '{"requiredPages":["privacy.html"]}')"
run_validator "$m"
check "rejects an entry without a leading slash" 1 "$RC"

# --- Path traversal -------------------------------------------------------
m="$(write_manifest traversal '{"requiredPages":["/","/../etc/passwd"]}')"
run_validator "$m"
check "rejects a path containing .." 1 "$RC"

# --- Duplicates -----------------------------------------------------------
# Harmless to check twice, but a duplicate usually means an edit went wrong,
# and it inflates the summary's page count without adding coverage.
m="$(write_manifest dupes '{"requiredPages":["/","/privacy.html","/privacy.html"]}')"
run_validator "$m"
check "rejects duplicate paths" 1 "$RC"

# --- The failure has to say WHICH entry ----------------------------------
# A bare non-zero exit sends whoever hits this hunting through the file. The
# existing deployed-pages gate names the offending page for the same reason.
m="$(write_manifest named '{"requiredPages":["/","https://example.com/privacy.html"]}')"
run_validator "$m"
if grep -qF "https://example.com/privacy.html" <<<"$OUT"; then
  echo "  ✅ names the offending entry in its output"
else
  echo "  ❌ output does not name the offending entry — the reason would be invisible"
  # Parameter expansion rather than sed: every line gets the same prefix, and
  # the newline substitution says so without spawning a process to say it.
  printf '       %s\n' "${OUT//$'\n'/$'\n'       }"
  FAILURES=$((FAILURES + 1))
fi

# --- forsgren: the zero and missing reds carry their reason --------------
# Added in forsgren (ported 2026-10-01, forsgren#1 ladder step 9); everything
# above is konenki-website's, with the manifest path as the only change. The
# cases above pin the EXIT CODE of a missing manifest and of an empty list,
# not why: a validator that crashed on the missing file, or redded an empty
# list for some other reason, would pass them. These pin the named reason, and
# each mutation proof removes the check that names it and shows the reason
# gone, so the reason is pinned to that check.
expect_reason() { # <case> <needle>
  if [[ "$RC" -eq 1 ]] && grep -qF -- "$2" <<<"$OUT"; then
    echo "  ✅ $1"
  else
    echo "  ❌ $1 — expected exit 1 naming '$2', got exit $RC: $OUT"
    FAILURES=$((FAILURES + 1))
  fi
}

run_validator "$TMP/does-not-exist.json"
expect_reason "a missing manifest is red as not found" \
  "FAIL manifest not found: $TMP/does-not-exist.json"

m="$(write_manifest empty-reason '{"requiredPages":[]}')"
run_validator "$m"
expect_reason "an empty list is red as empty" \
  "FAIL requiredPages is empty"

# mutant <name> <sed-expression> — a copy of the validator with one check
# removed; refuses a sed that changed nothing (a proof that proves nothing).
mutant() {
  sed "$2" Scripts/validate_required_pages.sh > "$TMP/$1.sh"
  chmod +x "$TMP/$1.sh"
  if cmp -s Scripts/validate_required_pages.sh "$TMP/$1.sh"; then
    echo "  ❌ mutation $1: the sed changed nothing — this proof proves nothing"
    FAILURES=$((FAILURES + 1))
    return 1
  fi
}

# Mutation proof A: without the existence check, the missing manifest no
# longer reds as "not found".
if mutant no-exist-check 's/\[\[ ! -f "\$MANIFEST" \]\]/false/'; then
  set +e
  OUT="$("$TMP/no-exist-check.sh" "$TMP/does-not-exist.json" 2>&1)"
  set -e
  if grep -qF "FAIL manifest not found" <<<"$OUT"; then
    echo "  ❌ mutation A: the reason survives without the existence check, so it does not come from that check"
    FAILURES=$((FAILURES + 1))
  else
    echo "  ✅ mutation A: without the existence check, 'manifest not found' is gone"
  fi
fi

# Mutation proof B: without the empty-list check, an empty list turns green.
if mutant no-empty-check 's/^if not pages:/if False:/'; then
  set +e
  OUT="$("$TMP/no-empty-check.sh" "$TMP/empty-reason.json" 2>&1)"
  RC=$?
  set -e
  if [[ "$RC" -eq 0 ]]; then
    echo "  ✅ mutation B: without the empty-list check, an empty list turns green"
  else
    echo "  ❌ mutation B: an empty list is still red (exit $RC) without the empty-list check, so its red does not come from that check: $OUT"
    FAILURES=$((FAILURES + 1))
  fi
fi

echo
if [[ $FAILURES -ne 0 ]]; then
  echo "❌ test_validate_required_pages: $FAILURES failing case(s)"
  exit 1
fi
echo "✅ test_validate_required_pages"
