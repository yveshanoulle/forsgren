#!/usr/bin/env bash
# canon: test_quality_trigger_scope v2
set -euo pipefail

cd "$(dirname "$0")/.."

# The gates must actually be reachable.
#
# quality.yml runs the repository's gates, so on paper CI checks everything sfl
# checks. A workflow gated behind a narrow paths filter (say the site directory
# plus the workflow file) runs only the gates that read those paths, and the
# fixtures that pin the release shape and the deploy workflow would run ONLY in
# sfl: nothing but a local run would stand between a broken deploy pin and main.
#
# The sharp edge is not the fixtures going unrun. It is that the fixtures exist
# to pin deploy-feta.yml, and a commit changing ONLY deploy-feta.yml fires
# neither Quality nor the deploy (which chains off the completion of Quality):
# **the file the checks guard sits outside the trigger of the workflow that
# checks it.** A green CI then means "nothing ran", which is indistinguishable
# from "everything passed".
#
# A separate workflow just to avoid widening Quality was weighed and rejected:
# two mechanisms for one job is how the next person fails to find where a check
# lives. An occasional extra feta deploy after a gate edit is accepted.
#
# THE RULE: either Quality has no paths filter, or the filter covers every
# path the gates read. A filter is allowed — an incorrect one is not.
# v2 (estate issue 301): a workflow with no paths and no paths-ignore filter on
# push and pull_request reaches everything and passes, and then neither the
# settings nor the extra globs are read (a repository that deliberately runs
# every gate on every change keeps none of them); a paths-ignore filter is
# rejected, because an ignored path is a change that runs no gate.
#
# Pull requests: Quality keeps its pull_request trigger (a ruling, recorded in
# Scripts/workflow_trigger_exceptions.txt), and it must keep one. judge() only
# inspects events that EXIST: an absent event has no paths filter to be wrong
# about, so a repo with no pull_request trigger would score perfectly while
# checking nothing before merge. That gap is its own assertion (Pin 2).
#
# Self-proving: the same check runs against a synthetic narrow-filter workflow
# at the end and MUST reject it, and against the real workflow with each
# required glob removed, one at a time. Without that this file would pass the
# moment the filter was removed and could never be shown failing again.
#
# Per-repo values are data: the site directory (Scripts/site_settings.txt) and
# any extra globs (Scripts/quality_trigger_globs.txt). The rest is canon.

# Entries the filter must contain LITERALLY. Deliberately not a prefix test:
# `.github/workflows/quality.yml` starts with `.github/workflows/` while
# covering none of the other workflows, so a prefix match would call the
# current, broken filter correct. What is required is a glob spanning the
# whole directory.
CANON_GLOBS=(
  "Scripts/**"                        # every gate, its test, the order file, the data files
  "sfl.sh"                            # the local gate the CI loop mirrors
  "FullBuildAndPush.sh"               # read by the --no-push self-test
  ".github/workflows/**"              # every workflow the fixtures pin
  ".github/zizmor.yml"                # zizmor's configuration: the gate reads it, no workflow glob covers it
  "package.json"                      # what npm ci installs
  "package-lock.json"
  ".nvmrc"                            # the Node pin
  ".htmlhintrc"                       # lint and scan configuration the gates read
  ".stylelintrc*"
  ".yamllint*"
  ".gitleaks.toml"
  ".actionlint.yaml"
  "**/*.md"                           # the markdown-links gate reads every *.md
)

COMPLETED=0
finish() {
  if [[ "$COMPLETED" -ne 1 ]]; then
    echo "FAIL: quality trigger scope check aborted before completing" >&2
    exit 1
  fi
}
trap finish EXIT

failed=0
fail() { echo "❌ FAIL: $*"; failed=1; }

# load_required_globs <extra-globs-file>: fills REQUIRED_GLOBS with the canon
# list, the site directory's glob (read from data) and the repo's extra globs
# (data). Fails closed: a missing settings or extras file is an error.
load_required_globs() {
  local extras="$1" site line
  site="$(site_settings_get Scripts/site_settings.txt site_dir)" || return 1
  [[ -f "$extras" ]] || { echo "extra globs file is missing: ${extras}" >&2; return 1; }
  REQUIRED_GLOBS=("${CANON_GLOBS[@]}" "${site}/**")
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in '' | '#'*) continue ;; esac
    REQUIRED_GLOBS+=("$line")
  done < "$extras"
}

# paths_of <workflow-file> <event>: the globs of that event's paths filter,
# one per line; empty when the event has none.
paths_of() {
  awk -v ev="$2" '
    $0 ~ "^  " ev ":[[:space:]]*$" { inev=1; next }
    inev && /^  [a-z_]+:/           { inev=0 }
    inev && /^    paths:[[:space:]]*$/ { inpaths=1; next }
    inpaths && /^    [a-z_-]+:/     { inpaths=0 }
    inpaths && /^      - / {
      line=$0
      sub(/^      - /, "", line)
      gsub(/"/, "", line)
      print line
    }
  ' "$1"
}

# has_key <workflow-file> <event> <key>: succeeds when that event has the key
# (for example paths-ignore) at its own indentation.
has_key() {
  awk -v ev="$2" -v key="$3" '
    $0 ~ "^  " ev ":[[:space:]]*$" { inev=1; next }
    inev && /^  [a-z_]+:/           { inev=0 }
    inev && $0 ~ "^    " key ":"    { found=1 }
    END { exit found ? 0 : 1 }
  ' "$1"
}

# judge <workflow-file> -> prints one problem per line; silent when the
# trigger reaches every required glob.
#
# Read with awk rather than a YAML parser on purpose: pyyaml is not
# guaranteed on the self-hosted runner, and a fixture that dies on a missing
# module is a gate that stopped gating. The shape it reads is the one these
# repos write — `paths:` under push/pull_request, one `- "glob"` per line.
judge() {
  local wf="$1" event paths want
  for event in push pull_request; do
    # A paths-ignore filter leaves the ignored paths without a gate run.
    if has_key "$wf" "$event" paths-ignore; then
      echo "${event}: has a paths-ignore filter — a change to an ignored path runs no gate at all, and a CI that never ran looks exactly like a CI that passed"
    fi

    # The paths block for this event, or empty when there is none.
    paths="$(paths_of "$wf" "$event")"

    # No paths block: this event triggers on everything. Nothing to check.
    [[ -z "$paths" ]] && continue

    for want in "${REQUIRED_GLOBS[@]}"; do
      if ! grep -qxF -- "$want" <<< "$paths"; then
        echo "${event}: paths does not contain ${want}"
      fi
    done
  done
}

WF=".github/workflows/quality.yml"
EXTRAS="Scripts/quality_trigger_globs.txt"
if [[ ! -f "$WF" ]]; then
  echo "FAIL: $WF not found" >&2
  exit 1
fi

# NOFILTER: no paths and no paths-ignore filter on push or pull_request, so
# every change runs every gate. Then there is no glob to check, and the
# settings and the extras file are not read at all.
NOFILTER=0
if ! has_key "$WF" push paths && ! has_key "$WF" push paths-ignore \
  && ! has_key "$WF" pull_request paths && ! has_key "$WF" pull_request paths-ignore; then
  NOFILTER=1
fi
if [[ "$NOFILTER" -eq 0 ]]; then
  # shellcheck source=Scripts/lib_site_settings.sh
  source Scripts/lib_site_settings.sh
  load_required_globs "$EXTRAS" || { echo "FAIL: the required globs could not be loaded" >&2; exit 1; }
fi

out="$(judge "$WF")"
if [[ -n "$out" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && fail "${WF} ${line} — a change there runs no gate at all, and a CI that never ran looks exactly like a CI that passed"
  done <<< "$out"
fi

# --- Pin 2: pull_request must be a trigger at all (see the header).
if ! grep -qE '^  pull_request:' "$WF"; then
  fail "${WF} has no pull_request trigger — every gate here would be push-to-main only, so a pull request is checked by nothing and the first run happens after the change has already landed"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; finish' EXIT

if [[ "$NOFILTER" -eq 0 ]]; then
# --- Self-proof 1: a deliberately narrow filter MUST be rejected.
cat > "${TMP}/narrow.yml" <<'YML'
name: Narrow
on:
  push:
    branches: ["main"]
    paths:
      - "Site/**"
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
YML
if [[ -z "$(judge "${TMP}/narrow.yml")" ]]; then
  fail "the synthetic narrow-filter workflow was ACCEPTED — this check cannot detect the defect it exists for"
else
  echo "  ok: synthetic narrow filter correctly rejected"
fi

# --- Self-proof 2: the real workflow with ONE required glob removed MUST be
# rejected, for EVERY required glob (the canon list, the site glob and the
# extras), and the rejection must name that glob.
for glob in "${REQUIRED_GLOBS[@]}"; do
  grep -vF -- "- \"${glob}\"" "$WF" > "${TMP}/without.yml" || true
  if cmp -s "$WF" "${TMP}/without.yml"; then
    fail "removing ${glob} from a copy of ${WF} changed nothing — the proof matches nothing"
  elif ! grep -qF -- "does not contain ${glob}" <<< "$(judge "${TMP}/without.yml")"; then
    fail "a quality.yml without ${glob} was ACCEPTED — the scope check cannot see that glob"
  else
    echo "  ok: a filter without ${glob} is rejected"
  fi
done

# --- Self-proof 3: a glob from the extras file is required like a canon one,
# and a missing extras file is an error, not an empty list.
printf '# an extra glob\nNope/**\n' > "${TMP}/extras.txt"
saved=("${REQUIRED_GLOBS[@]}")
load_required_globs "${TMP}/extras.txt"
if grep -qF -- "does not contain Nope/**" <<< "$(judge "$WF")"; then
  echo "  ok: a glob from the extras file is required"
else
  fail "an extra glob the workflow lacks was ACCEPTED — the extras file is read but not enforced"
fi
REQUIRED_GLOBS=("${saved[@]}")
if load_required_globs "${TMP}/absent.txt" 2>/dev/null; then
  fail "a missing extras file was accepted — the data has no default"
else
  echo "  ok: a missing extras file is an error"
fi
REQUIRED_GLOBS=("${saved[@]}")
else
  echo "  ok: ${WF} has no paths or paths-ignore filter on push or pull_request, so it reaches everything"
fi

# --- Self-proof 4: the real workflow without its pull_request trigger MUST be
# rejected by Pin 2's test (the event name is the only thing changed).
sed 's/^  pull_request:/  pull_requested:/' "$WF" > "${TMP}/no_pr.yml"
if cmp -s "$WF" "${TMP}/no_pr.yml"; then
  fail "renaming the pull_request trigger in a copy changed nothing — the proof matches nothing"
elif grep -qE '^  pull_request:' "${TMP}/no_pr.yml"; then
  fail "a quality.yml without a pull_request trigger still passes Pin 2's test"
else
  echo "  ok: a workflow without a pull_request trigger is rejected by Pin 2"
fi

# --- Self-proof 5 (estate issue 301): the trigger judged in throwaway roots.
# Each case runs a copy of this very script in a root whose quality.yml is the
# workflow under test (QTS_NESTED stops the copy from nesting again), because
# the real quality.yml may carry a filter or not.
#   a. no paths filter on push and pull_request reaches everything and PASSES,
#      in a root with no settings or globs file at all (nothing is read when
#      there is no filter);
#   b. a Site/**-only filter is still rejected, naming Scripts/**;
#   c. a paths-ignore filter is rejected, naming paths-ignore: an ignored path
#      is a change that runs no gate;
#   d. mutations: with the no-filter branch switched off the no-filter root
#      fails because the settings library it no longer skips is absent; with the
#      paths-ignore check switched off the paths-ignore root is accepted.
if [[ -z "${QTS_NESTED:-}" ]]; then
  # sandbox_run <name> <script> <workflow-file> <with-settings: yes|no>: runs
  # <script> in a root with that workflow; output in sb_out, exit status in sb_rc.
  sandbox_run() {
    local root="${TMP}/sb_$1"
    mkdir -p "${root}/Scripts" "${root}/.github/workflows"
    if [[ "$4" == yes ]]; then
      cp Scripts/lib_site_settings.sh Scripts/site_settings.txt Scripts/quality_trigger_globs.txt "${root}/Scripts/"
    fi
    cp "$2" "${root}/Scripts/test_quality_trigger_scope.sh"
    cp "$3" "${root}/.github/workflows/quality.yml"
    sb_rc=0
    sb_out="$(QTS_NESTED=1 bash "${root}/Scripts/test_quality_trigger_scope.sh" 2>&1)" || sb_rc=$?
  }
  cat > "${TMP}/nofilter.yml" <<'YML'
name: Quality
on:
  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
YML
  sed 's#^    branches: \["main"\]$#&\n    paths:\n      - "Site/**"#' "${TMP}/nofilter.yml" > "${TMP}/onlysite.yml"
  cat > "${TMP}/ignore.yml" <<'YML'
name: Quality
on:
  push:
    branches: ["main"]
    paths-ignore:
      - "**.md"
  pull_request:
    branches: ["main"]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
YML

  sandbox_run nofilter "$0" "${TMP}/nofilter.yml" no
  if [[ "$sb_rc" -eq 0 ]]; then
    echo "  ok: a quality.yml with no paths filter reaches everything and passes, with no globs file read"
  else
    fail "a quality.yml with no paths filter on push and pull_request was REJECTED (exit ${sb_rc}) — no filter means every change runs every gate: $(grep -m1 'FAIL' <<< "$sb_out")"
  fi

  sandbox_run narrowroot "$0" "${TMP}/onlysite.yml" yes
  if [[ "$sb_rc" -ne 0 ]] && grep -qF -- "paths does not contain Scripts/**" <<< "$sb_out"; then
    echo "  ok: a Site/**-only filter is still rejected, naming Scripts/**"
  else
    fail "a quality.yml filtered to Site/** only was ACCEPTED or rejected for another reason (exit ${sb_rc}) — a filter must still cover every path the gates read"
  fi

  sandbox_run ignoreroot "$0" "${TMP}/ignore.yml" yes
  if [[ "$sb_rc" -ne 0 ]] && grep -qF -- "push: has a paths-ignore filter" <<< "$sb_out"; then
    echo "  ok: a paths-ignore filter is rejected, naming paths-ignore"
  else
    fail "a quality.yml with a paths-ignore filter on push was ACCEPTED or rejected for another reason (exit ${sb_rc}) — an ignored path is a change that runs no gate"
  fi

  sed 's/^\( *\)NOFILTER=1$/\1NOFILTER=0/' "$0" > "${TMP}/mutant_nofilter.sh"
  if cmp -s "$0" "${TMP}/mutant_nofilter.sh"; then
    fail "the mutation switching the no-filter branch off changed nothing — this script has no line that sets NOFILTER to 1"
  else
    sandbox_run mutnofilter "${TMP}/mutant_nofilter.sh" "${TMP}/nofilter.yml" no
    if [[ "$sb_rc" -ne 0 ]] && grep -qF -- "lib_site_settings.sh" <<< "$sb_out"; then
      echo "  ok: without the no-filter branch the no-filter workflow fails, naming the settings library it can no longer skip"
    else
      fail "a script without the no-filter branch still passed the no-filter workflow (exit ${sb_rc}) — the branch is not what makes it pass"
    fi
  fi

  sed 's/has_key [^;]* paths-ignore/false/' "$0" > "${TMP}/mutant_ignore.sh"
  if cmp -s "$0" "${TMP}/mutant_ignore.sh"; then
    fail "the mutation switching the paths-ignore check off changed nothing — this script does not test paths-ignore through has_key"
  else
    sandbox_run mutignore "${TMP}/mutant_ignore.sh" "${TMP}/ignore.yml" yes
    if [[ "$sb_rc" -eq 0 ]]; then
      echo "  ok: without the paths-ignore check a paths-ignore workflow is accepted, so that check is what rejects it"
    else
      fail "a script without the paths-ignore check still rejected the paths-ignore workflow (exit ${sb_rc}) — something else rejects it: $(grep -m1 'FAIL' <<< "$sb_out")"
    fi
  fi
fi

COMPLETED=1

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "FAIL: quality.yml's trigger does not reach everything its gates check"
  exit 1
fi

echo "OK: quality.yml triggers on every path its gates read (and a narrow filter is still detected)"
