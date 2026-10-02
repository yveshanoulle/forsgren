#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Non-vacuity proof for Scripts/test_workflow_checkout_pins.sh (forsgren#1,
# ladder step 17), run in pre before the gate it validates, as the canon row
# `mutation: checkout pins`.
#
# PORTED from coachretreat-website (its units 368 and 400), the estate's
# best-shape copy: konenki-website's has the two checkout pins only, and
# coachretreat's adds the synthetic second-action case below. Adapted, not
# byte-identical:
#   - a missing or non-executable gate is red, with its own FAIL line, before
#     any case runs (the estate copy would read every rejection as "correctly
#     rejected" when the gate is simply not there);
#   - every rejection asserts its REASON, the gate's own finding text, not
#     only a non-zero exit, so a case red for something else in its file
#     cannot pass as proof;
#   - forsgren's cases at the end: a branch ref, a short SHA, a full SHA with
#     its version comment, a local action, a docker:// reference, a directory
#     with no workflow file, and a mutation of the gate itself.
#
# WHY THIS EXISTS. This fixture has already been wrong once in the direction
# that matters least: it reported a violation that was not there. The
# dangerous direction is the other one: reporting clean when a checkout has
# lost its sha pin or its persist-credentials setting. Nothing proves that
# unless the check is watched failing.
#
# The inherited version scanned forward from the `uses:` line while indent
# was strictly greater, which only works where `uses` sits on the dash line.
# It was testing an authoring style, not a property, and it would have gone
# green on a repo with NO persist-credentials anywhere the moment that repo
# wrote its steps with `- name:` first. That is exactly the failure this
# proof is here to catch.

FIXTURE="./Scripts/test_workflow_checkout_pins.sh"

if [[ ! -x "$FIXTURE" ]]; then
  echo "❌ FAIL: ${FIXTURE} not found or not executable — the action-pin gate this proof validates does not exist, so nothing keeps a workflow action off a tag its maintainer can re-point"
  exit 1
fi

TMP="$(mktemp -d)"

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: checkout-pin mutation proof aborted before completing all cases" >&2
    exit 1
  fi
}
trap 'rm -rf "$TMP"; finish' EXIT

failed=0
fail() { echo "❌ FAIL: $*"; failed=1; }

# rejected <label> <gate> <dir> <reason>: the gate must exit non-zero on <dir>
# AND print <reason>, the finding that names why. A red without the reason is
# a red for something else, and proves nothing about this case.
rejected() {
  local label="$1" gate="$2" dir="$3" reason="$4" out rc
  set +e; out="$("$gate" "$dir" 2>&1)"; rc=$?; set -e
  if [[ "$rc" -eq 0 ]]; then
    fail "${label} PASSED the gate — that pin does not actually guard it"
  elif ! grep -qF -- "$reason" <<< "$out"; then
    fail "${label} was rejected, but not for the expected reason (${reason}). Output: ${out}"
  else
    echo "  ok: ${label} correctly rejected"
  fi
}

# accepted <label> <gate> <dir>: the gate must exit 0 on <dir>.
accepted() {
  local label="$1" gate="$2" dir="$3" out rc
  set +e; out="$("$gate" "$dir" 2>&1)"; rc=$?; set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "  ok: ${label} accepted"
  else
    fail "${label} was REJECTED. Output: ${out}"
  fi
}

# mutate <label> <reason> <sed-expression>
mutate() {
  local label="$1" reason="$2" expr="$3"
  local dir="${TMP}/wf"
  rm -rf "$dir"; mkdir -p "$dir"
  cp .github/workflows/*.yml "$dir"/
  sed -E -i '' "$expr" "$dir"/*.yml 2>/dev/null || sed -E -i "$expr" "$dir"/*.yml

  if diff -rq .github/workflows "$dir" >/dev/null 2>&1; then
    fail "mutation '${label}' changed nothing — the sed no longer matches, so this case proves nothing"
    return
  fi

  rejected "mutation '${label}'" "$FIXTURE" "$dir" "$reason"
}

echo "Mutation proof — each case must be rejected by ${FIXTURE}:"

mutate "persist-credentials removed from every checkout" \
  "checkout does not set persist-credentials: false" \
  '/persist-credentials/d'

mutate "checkout back on a floating tag instead of a sha" \
  "checkout is not sha-pinned" \
  's#actions/checkout@[0-9a-f]{40}#actions/checkout@v4#'

# --- The scan must judge the PROPERTY, not the authoring style.
#
# konenki puts `uses` ON the dash line, coachretreat writes `- name:` first
# with `uses:` below it. The inherited scan walked forward while indent was
# strictly greater, which only reads the first form: it reported
# persist-credentials missing in coachretreat while the setting sat three
# lines below. BOTH forms are asserted, as in every repo of the estate: a repo
# that only tests its own form cannot notice the scan becoming style-bound
# again.
for form in dash name; do
  dir="${TMP}/form_${form}"
  rm -rf "$dir"; mkdir -p "$dir"
  if [ "$form" = "dash" ]; then
    cat > "$dir/wf.yml" <<'YML'
name: uses on the dash line
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
YML
  else
    cat > "$dir/wf.yml" <<'YML'
name: name first, uses below
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
YML
  fi
  accepted "a compliant checkout in the '${form}' form" "$FIXTURE" "$dir"
done

# --- The gate must judge the PROPERTY, not one action's name.
#
# coachretreat's unit 400, from agilelean-website, where
# `actions/setup-node@v4` sat outside a scan that grepped the literal string
# `actions/checkout`. SYNTHETIC, and it has to be: forsgren's workflow uses
# `actions/checkout` and nothing else, so mutating it can only ever exercise
# the checkout pins again.
#
# second_action <case-dir> <uses-ref>: one workflow, a compliant checkout,
# then a second step on <uses-ref>, alone in its own dir.
second_action() {
  local dir="${TMP}/$1"
  rm -rf "$dir"; mkdir -p "$dir"
  cat > "$dir/wf.yml" <<YML
name: a second action alongside checkout
on:
  push:
    branches: ["main"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          persist-credentials: false
      - uses: $2
YML
}

PIN_REASON="action is not sha-pinned"

second_action tag "actions/setup-node@v4"
rejected "a non-checkout action on a tag (@v4)" "$FIXTURE" "${TMP}/tag" "${PIN_REASON}: actions/setup-node@v4"

second_action full "actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020  # v4.4.0"
accepted "a non-checkout action on a full 40-hex SHA with its version comment" "$FIXTURE" "${TMP}/full"

# --- forsgren's cases.

# A branch moves with every push to it: a looser pin than a tag.
second_action branch "actions/setup-node@main"
rejected "a non-checkout action on a branch (@main)" "$FIXTURE" "${TMP}/branch" "${PIN_REASON}: actions/setup-node@main"

# A short SHA is resolved by prefix, and a prefix can become ambiguous or be
# matched by a commit pushed later to a fork in the same network.
second_action short "actions/setup-node@49933ea"
rejected "a non-checkout action on a short SHA" "$FIXTURE" "${TMP}/short" "${PIN_REASON}: actions/setup-node@49933ea"

# The source's rule for a local reference: skipped. It is this repository's
# own content at the commit being built, with no upstream to re-point.
second_action local "./.github/actions/setup"
accepted "a local action (./...)" "$FIXTURE" "${TMP}/local"

# The source's rule has no docker exception: anything that is not local must
# end in @<40 hex>, so a docker:// reference is red. An image tag is as
# re-pointable as an action tag.
second_action docker "docker://alpine:3.20"
rejected "a docker:// action on an image tag" "$FIXTURE" "${TMP}/docker" "${PIN_REASON}: docker://alpine:3.20"

# A scan over nothing is not clean.
mkdir -p "${TMP}/empty"
rejected "a directory with no workflow file" "$FIXTURE" "${TMP}/empty" "no actions/checkout found in"

# The gate itself, mutated: with Pin 3's SHA pattern replaced by one that
# matches anything, the tag case must turn GREEN. So the tag case above is red
# BECAUSE its ref is not a full SHA, not for something else in its file.
gate_copy="${TMP}/gatecopy/Scripts/test_workflow_checkout_pins.sh"
mkdir -p "$(dirname "$gate_copy")"
sed "s/grep -qE '@\[0-9a-f\]{40}\$'/grep -qE '.'/" "$FIXTURE" > "$gate_copy"
chmod +x "$gate_copy"
if cmp -s "$FIXTURE" "$gate_copy"; then
  fail "the gate mutation changed nothing — its sed no longer matches Pin 3, so this case proves nothing"
else
  accepted "the tag case, against a gate whose Pin 3 accepts any ref," "$gate_copy" "${TMP}/tag"
fi

# Control: untouched copies must PASS, or the rejections above are worthless.
dir="${TMP}/control"
mkdir -p "$dir"
cp .github/workflows/*.yml "$dir"/
accepted "the unmutated control (this repository's workflows)" "$FIXTURE" "$dir"

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: checkout pins are not all load-bearing"
  exit 1
fi

echo "OK: all three action pins are load-bearing (checkout sha, persist-credentials, and a non-checkout action on a tag, a branch, a short SHA or a docker tag each rejected for its reason; both authoring forms, a full SHA, a local action and the control accepted; a gate that accepts any ref lets the tag through)"
