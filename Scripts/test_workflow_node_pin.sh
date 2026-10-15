#!/usr/bin/env bash
# Scripts/test_workflow_node_pin.sh
#
# The Node pin in CI (forsgren#2, decision #190): every workflow that runs npm
# or node gets its Node from .nvmrc, the file sfl's Scripts/check_node_pin.sh
# enforces locally, through actions/setup-node. Without it CI runs whatever
# Node Homebrew has that day, and the "Node pin" row goes red the day Homebrew
# moves to another major.
#
# Per workflow file under .github/workflows that has a run line using npm,
# npx or node, there must be a step that:
#   1. uses actions/setup-node pinned by a 40-hex commit sha with a `# vX.Y.Z`
#      comment (a tag can be re-pointed; the sha cannot);
#   2. sets node-version-file: .nvmrc, the one source of the pin;
#   3. comes before the first step that runs Scripts/install_tools.sh or npm.
# Synthetic workflows show each broken shape red, and the real workflows green.
# Mutation proof: a judge that skips the sha check must accept a tag pin.

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
selftest_begin "workflow node pin self-test"

# judge_file <workflow-file> — prints one line per problem; none when the file
# needs no Node or sets it up properly.
judge_file() {
  awk -v file="$1" -v checksha="${CHECK_SHA:-1}" '
    function code(s) { return s !~ /^[[:space:]]*#/ }
    /^      - / { step++ }
    code($0) && $0 ~ /(^|[[:space:];&|(])(npm|npx|node)[[:space:]]/ && $0 ~ /run:|^[[:space:]]+[a-z]/ && $0 !~ /uses:/ { needs = 1 }
    code($0) && $0 ~ /uses:[[:space:]]*actions\/setup-node@/ {
      sn = step; usesline = $0
    }
    sn && step == sn && code($0) && $0 ~ /node-version-file:/ { vf = $0 }
    code($0) && !first && ($0 ~ /Scripts\/install_tools\.sh/ || $0 ~ /npm ci/) { first = step }
    END {
      if (!needs) exit
      if (!sn) { print file ": runs npm or node but has no actions/setup-node step"; exit }
      if (checksha == 1 && usesline !~ /setup-node@[0-9a-f]{40}[[:space:]]+# v[0-9]+\.[0-9]+\.[0-9]+/)
        print file ": actions/setup-node is not pinned by a 40-hex commit sha with a # vX.Y.Z comment"
      if (vf !~ /node-version-file:[[:space:]]*\.nvmrc[[:space:]]*$/)
        print file ": actions/setup-node does not set node-version-file: .nvmrc"
      if (first && sn >= first) print file ": actions/setup-node comes after the first step that installs tools or runs npm"
    }
  ' "$1"
}

SHA="820762786026740c76f36085b0efc47a31fe5020"

# synth <name> <uses-ref-and-comment> <version-file-line> <order: before|after|none> — writes a workflow.
synth() {
  local f="${TMP}/$1.yml" setup install
  setup="      - uses: actions/setup-node@$2
        with:
          $3
"
  install="      - name: Install tools
        run: ./Scripts/install_tools.sh
      - name: Install dependencies
        run: npm ci
"
  {
    printf 'name: t\non: push\njobs:\n  j:\n    runs-on: macos-latest\n    steps:\n'
    printf '      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1\n'
    printf '      # Scripts/install_tools.sh and npm ci in a comment do not count\n'
    case "$4" in
      before) printf '%s%s' "$setup" "$install" ;;
      after) printf '%s%s' "$install" "$setup" ;;
      none) printf '%s' "$install" ;;
    esac
  } > "$f"
  WF="$f"
}

# judge <case> <wf> — sets OUT and RC (RC 1 when there are problems).
judge() {
  OUT="$(judge_file "$2")"
  if [[ -n "$OUT" ]]; then RC=1; else RC=0; fi
}

synth good "${SHA}  # v7.0.0" "node-version-file: .nvmrc" before
judge good "$WF"
want_rc "1. sha-pinned setup-node on .nvmrc before the installs is accepted" 0

synth none "${SHA}  # v7.0.0" "node-version-file: .nvmrc" none
judge none "$WF"
want_red "2. no setup-node step" "has no actions/setup-node step"

synth tag "v7" "node-version-file: .nvmrc" before
judge tag "$WF"
want_red "3. a tag instead of a sha" "not pinned by a 40-hex commit sha"
TAG_WF="$WF"

synth nocomment "${SHA}" "node-version-file: .nvmrc" before
judge nocomment "$WF"
want_red "3b. a sha without the version comment" "not pinned by a 40-hex commit sha"

synth literal "${SHA}  # v7.0.0" "node-version: 26" before
judge literal "$WF"
want_red "4. a literal node-version instead of the file" "does not set node-version-file: .nvmrc"

synth otherfile "${SHA}  # v7.0.0" "node-version-file: .node-version" before
judge otherfile "$WF"
want_red "5. another version file" "does not set node-version-file: .nvmrc"

synth late "${SHA}  # v7.0.0" "node-version-file: .nvmrc" after
judge late "$WF"
want_red "6. setup-node after the installs" "comes after the first step"

# The real workflows: every file that uses node or npm is covered.
for wf in .github/workflows/*.yml; do
  judge "real" "$wf"
  want_rc "7. ${wf}: needs no Node, or sets it up from .nvmrc" 0
done
if ! grep -qE 'actions/setup-node@' .github/workflows/quality.yml; then
  fail "7. quality.yml runs npm ci and has no actions/setup-node step"
fi

# --- mutation proof: no sha check -> the tag pin is accepted ------------------
CHECK_SHA=0 judge tagmut "$TAG_WF"
if [[ "$RC" -eq 0 ]]; then
  echo "  ok: mutation proof: without the sha check a tag pin is accepted, so case 3 is red because of it"
else
  fail "mutation proof: the sha-blind judge still refused a tag pin. Output: ${OUT}"
fi

selftest_end "the workflow Node pin does not hold" \
  "workflow node pin: a workflow that runs npm or node sets Node up from .nvmrc with a sha-pinned actions/setup-node before its installs; each broken shape is red; mutation proven"
