#!/usr/bin/env bash
# canon: test_validate_required_pages v1
set -euo pipefail

cd "$(dirname "$0")/.."

# Self-test for validate_required_pages.sh.
#
# The required-pages manifest is part of the release artifact: it ships with
# the site, with no packaging change. Promotion to live reads it from the
# promoted release and verifies every declared page over HTTP. A malformed
# manifest must therefore be caught BEFORE the release is promotable —
# otherwise promotion silently degrades into an ambiguous partial check, which
# is the weak verification this whole arc exists to remove.
#
# Every case below is a way a manifest can be wrong while still looking
# plausible in a diff.
#
# MUTATION PROOF, at the end: the same cases run against weakened copies of the
# validator (an empty list, a duplicate, a traversal, a scheme, a missing slash
# or a missing file accepted, invalid JSON accepted, every finding ignored), and
# each copy must be red. A fixture that passes a validator which cannot fail is
# decoration. The validator under test is the optional first argument; without
# one it is the real validator and the mutation proof runs.

VALIDATOR="${1:-./Scripts/validate_required_pages.sh}"
SELF="${PWD}/Scripts/test_validate_required_pages.sh"
TMP="$(mktemp -d)"
# COMPLETED is set by the last statement. On bash 3.2 an abort under set -eu can
# end with status 0; the trap turns an exit of 0 without COMPLETED into exit 1.
COMPLETED=0
cleanup() {
  local exit_code=$?
  rm -rf "$TMP"
  if [ "$exit_code" -eq 0 ] && [ "$COMPLETED" -ne 1 ]; then
    echo "❌ test_validate_required_pages aborted before completing" >&2
    exit 1
  fi
}
trap cleanup EXIT

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
  OUT="$("$VALIDATOR" "$1" 2>&1)"
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
# shellcheck source=Scripts/lib_site_settings.sh
source Scripts/lib_site_settings.sh
SHIPPED="$(site_settings_get Scripts/site_settings.txt required_pages_manifest)"
run_validator "${PWD}/${SHIPPED}"
check "accepts the shipped manifest (${SHIPPED})" 0 "$RC"

# The order file names the bare script, so the default must find the same file.
set +e; "$VALIDATOR" >/dev/null 2>&1; RC=$?; set -e
check "accepts the shipped manifest with no argument" 0 "$RC"

# An explicit empty argument is a usage error, never the default.
set +e; "$VALIDATOR" "" >/dev/null 2>&1; RC=$?; set -e
check "an explicit empty argument is a usage error" 2 "$RC"

# --- Missing file ---------------------------------------------------------
# The manifest is mandatory: absence is an invalid release, never a quiet
# fallback to index-only verification.
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

# A scheme behind a leading slash is root-relative to the eye, so only the
# scheme check can reject it.
m="$(write_manifest slashscheme '{"requiredPages":["/","/https://example.com/privacy.html"]}')"
run_validator "$m"
check "rejects a scheme and host behind a leading slash" 1 "$RC"

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
  printf '       %s\n' "${OUT//$'\n'/$'\n'       }"
  FAILURES=$((FAILURES + 1))
fi

# --- Mutation proof: weakened copies of the validator must be red here.
# Only for the real validator; the copies are judged by this same file, run on
# them. A copy lives in a root of its own (the validator works from its parent
# directory and sources the settings reader there), with the manifest's top
# directory linked in so the shipped-manifest cases still find it.
if [[ $# -eq 0 ]]; then
  mutant_must_fail() { # <label> <sed-expression>
    local dir="$TMP/mutant-$RANDOM" m
    mkdir -p "$dir/Scripts"
    cp Scripts/lib_site_settings.sh Scripts/site_settings.txt "$dir/Scripts/"
    ln -s "${PWD}/${SHIPPED%%/*}" "$dir/${SHIPPED%%/*}"
    m="$dir/Scripts/validate_required_pages.sh"
    sed "$2" "$VALIDATOR" > "$m"
    chmod +x "$m"
    if cmp -s "$VALIDATOR" "$m"; then
      echo "  ❌ mutation '$1' changed nothing — it proves nothing"; FAILURES=$((FAILURES+1)); return
    fi
    if "$SELF" "$m" >/dev/null 2>&1; then
      echo "  ❌ mutation '$1' PASSED this fixture — the cases do not guard it"; FAILURES=$((FAILURES+1))
    else
      echo "  ✅ mutation '$1' is red"
    fi
  }
  mutant_must_fail "an empty list is accepted" 's/^if not pages:$/if False:/'
  mutant_must_fail "a duplicate is accepted" 's/^    if entry in seen:$/    if False:/'
  mutant_must_fail "a .. segment is accepted" 's/^    if ".." in entry.split("\/"):$/    if False:/'
  mutant_must_fail "a scheme and host is accepted" 's/^    if "[:]\/\/" in entry:$/    if False:/'
  mutant_must_fail "a missing leading slash is accepted" 's/^    elif not entry.startswith("\/"):$/    elif False:/'
  mutant_must_fail "invalid JSON is accepted" '/except json.JSONDecodeError/,/sys.exit(1)/ s/sys.exit(1)/sys.exit(0)/'
  mutant_must_fail "a missing manifest is accepted" '/^if \[\[ ! -f "[$]MANIFEST" \]\]; then$/,/^fi$/ s/exit 1/exit 0/'
  mutant_must_fail "every finding is ignored" 's/^if problems:$/if False:/'
fi

echo
if [[ $FAILURES -ne 0 ]]; then
  echo "❌ test_validate_required_pages: $FAILURES failing case(s)"
  exit 1
fi
echo "✅ test_validate_required_pages"
COMPLETED=1
