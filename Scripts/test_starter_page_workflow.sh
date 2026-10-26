#!/usr/bin/env bash
# Scripts/test_starter_page_workflow.sh
#
# Pins .github/workflows/starter_page.yml, the workflow that renders README.md
# and publishes it to GitHub Pages as forsgren.be (forsgren#132, decision
# forsgren#149). forsgren's own. Nothing in sfl or Quality runs it, so this
# pin is what proves it, on every run, in the shape of
# Scripts/test_metrics_workflow.sh: the real file must hold every pin, and
# each pin is proved by a mutant of the real file that breaks it and must be
# named. The pins:
#   1. it triggers on push, release and workflow_dispatch, and on nothing else
#   2. no pull-request event appears anywhere in it
#   3. the push is to main only, filtered to the README, the renderer, the
#      stylesheet, the build script and this file; the release is `published`
#   4. permissions: contents: read at the top; pages: write and id-token:
#      write on the deploy job only, and no other write anywhere
#   5. every job runs on ubuntu-latest (GitHub-hosted)
#   6. every action is pinned by a full commit and is the very commit
#      metrics.yml pins for it; only the four actions it uses are used
#   7. the checkout does not persist credentials
#   8. setup-go installs exactly the Go of go.mod's toolchain line, no cache
#   9. the build step runs exactly ./Scripts/build_starter_page.sh and the
#      upload is .build/starter
#  10. no run: block expands a ${{ }} expression (template injection)
#  11. the deploy job needs the build job and deploys to github-pages
#  12. the concurrency group is pages and a run in flight is not cancelled
#  13. the order: checkout, Go, build, upload, then the deploy job's step
#  14. a release-triggered deploy skips explicitly while GitHub Pages is not
#      enabled (Yves's ruling on decision forsgren#149, acceptance item 3):
#      the step "Check that GitHub Pages is enabled" runs only for a release,
#      takes the job token and the repository through env: only, and its
#      run: block, EXECUTED here with a stub gh, asks `gh api
#      repos/<repository>/pages` and outputs enabled=true on success;
#      enabled=false with a ::notice naming the cause on a 404 (the deploy
#      step is then skipped, the job stays green, nothing configures Pages);
#      and fails with an ::error on any other failure, so a token or API
#      problem is never read as "not enabled". The deploy step runs for every
#      event but a release, and for a release only when enabled=true. No
#      permission is added for it: the deploy job already holds pages: write.
#  15. the live check (forsgren#205, ruling item 3): a third job, live-check,
#      needs deploy and runs only when the deploy step really published
#      (the deploy job's `deployed` output is that step's outcome being
#      success, so a release run that skipped the deploy skips the check);
#      it holds contents: read and nothing else, checks out without
#      persisting credentials, and runs exactly
#      ./Scripts/live_check.sh https://forsgren.be with no ${{ }} in the run.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

WORKFLOW=".github/workflows/starter_page.yml"
METRICS=".github/workflows/metrics.yml"

# shellcheck source=Scripts/lib_selftest.sh
source Scripts/lib_selftest.sh
# shellcheck source=Scripts/lib_has.sh
source Scripts/lib_has.sh
# shellcheck source=Scripts/lib_workflow_steps.sh
source Scripts/lib_workflow_steps.sh
selftest_begin "starter page workflow pin"

[[ -f "$WORKFLOW" ]] || selftest_abort "${WORKFLOW} does not exist: nothing publishes the starter page"
[[ -f "$METRICS" ]] || selftest_abort "${METRICS} does not exist: the action pins have nothing to be compared with"

TOOLCHAIN="$(./Scripts/go_toolchain.sh)"
GO_VERSION="${TOOLCHAIN#go}"

# code <file>: the file without its comment lines.
code() {
  grep -vE '^[[:space:]]*#' "$1"
}

# pin_of <file> <action>: the commit the file pins an action at.
pin_of() {
  code "$1" | grep -E "uses: actions/$2@" | head -1 | sed -E 's/.*@([0-9a-f]{40}).*/\1/'
}

# trigger_findings <file> — pins 1 to 3.
trigger_findings() {
  local events
  events="$(on_events "$1" | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$events" == "push release workflow_dispatch " ]] || echo "triggers: want push, release and workflow_dispatch, got: ${events:-none}"
  if code "$1" | has -qE 'pull_request'; then
    echo "pull_request: a pull-request event appears in the workflow"
  fi
  code "$1" | has -qxF '    branches: [main]' || echo "push branches: the push is not to main only"
  code "$1" | has -qxF '    types: [published]' || echo "release types: the release is not limited to published"
  local path
  for path in README.md 'cmd/readmepage/**' 'internal/readmepage/**' internal/page/styles.css \
    Scripts/build_starter_page.sh .github/workflows/starter_page.yml; do
    code "$1" | has -qxF "      - ${path}" || echo "push paths: ${path} is not in the filter"
  done
}

# permission_findings <file> — pins 4 and 5.
permission_findings() {
  if ! awk '/^permissions:/ { getline; if ($0 == "  contents: read") ok=1 } END { exit !ok }' "$1"; then
    echo "permissions: the top level is not contents: read"
  fi
  [[ "$(code "$1" | grep -c ': write')" == 2 ]] || echo "write permissions: want exactly pages and id-token, once each"
  if ! awk '/^  deploy:/ { d=1 } d && /pages: write/ { p=1 } d && /id-token: write/ { i=1 } END { exit !(p && i) }' "$1"; then
    echo "deploy permissions: the deploy job lacks pages: write or id-token: write"
  fi
  if code "$1" | has -qE 'write-all|pull-requests:'; then
    echo "permissions: write-all or pull-requests appears"
  fi
  local hosts
  hosts="$(code "$1" | grep -E '^[[:space:]]+runs-on:' | sed -E 's/.*runs-on:[[:space:]]*//' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
  [[ "$hosts" == " 3 ubuntu-latest;" ]] || echo "runs-on: every job must run on ubuntu-latest, got: ${hosts}"
}

# action_findings <file> — pins 6 to 8.
action_findings() {
  local action want got used
  used="$(code "$1" | grep -E '^[[:space:]]+(- )?uses:' | sed -E 's/.*uses:[[:space:]]*([^@ ]+)@.*/\1/' | LC_ALL=C sort -u | tr '\n' ' ')"
  [[ "$used" == "actions/checkout actions/deploy-pages actions/setup-go actions/upload-pages-artifact " ]] \
    || echo "actions: want checkout, setup-go, upload-pages-artifact and deploy-pages only, got: ${used}"
  if code "$1" | grep -E 'uses:' | has -vqE '@[0-9a-f]{40}  # v[0-9]'; then
    echo "pins: an action is not pinned by a full commit with its version comment"
  fi
  for action in checkout setup-go upload-pages-artifact deploy-pages; do
    want="$(pin_of "$METRICS" "$action")"
    got="$(pin_of "$1" "$action")"
    [[ -n "$want" && "$got" == "$want" ]] || echo "pin of ${action}: ${got:-none} is not metrics.yml's ${want:-none}"
  done
  step_text "$1" "Check out" | has -qF 'persist-credentials: false' || echo "checkout: credentials are persisted"
  step_text "$1" "Set up Go" | has -qF "go-version: '${GO_VERSION}'" || echo "setup-go: not Go ${GO_VERSION} from go.mod's toolchain"
  step_text "$1" "Set up Go" | has -qF 'cache: false' || echo "setup-go: a cache is restored"
}

# step_findings <file> — pins 9 to 13.
step_findings() {
  step_text "$1" "Build the starter page" | has -qxF '        run: ./Scripts/build_starter_page.sh' \
    || echo "build: the step does not run exactly ./Scripts/build_starter_page.sh"
  step_text "$1" "Upload the page" | has -qxF '          path: .build/starter' || echo "upload: the path is not .build/starter"
  if run_blocks "$1" | has -qF -- "\${{"; then
    echo "injection: a run: block expands a \${{ }} expression"
  fi
  code "$1" | has -qxF '    needs: build' || echo "deploy: the job does not need the build job"
  code "$1" | has -qxF '      name: github-pages' || echo "deploy: the environment is not github-pages"
  code "$1" | has -qxF '  group: pages' || echo "concurrency: the group is not pages"
  code "$1" | has -qxF '  cancel-in-progress: false' || echo "concurrency: a run in flight is cancelled"
  local checkout gosetup build upload deploy
  checkout="$(line_of "$1" "name: Check out")"
  gosetup="$(line_of "$1" "name: Set up Go")"
  build="$(line_of "$1" "name: Build the starter page")"
  upload="$(line_of "$1" "name: Upload the page")"
  deploy="$(line_of "$1" "name: Publish to GitHub Pages")"
  if ! { later "$gosetup" "$checkout" && later "$build" "$gosetup" && later "$upload" "$build" && later "$deploy" "$upload"; }; then
    echo "order: want checkout, Go, build, upload, deploy"
  fi
}

# run_pages_check <file> <mode> — pin 14: the check step's run: block,
# executed with a stub gh that answers like the API in <mode> (ok, 404, 403).
# PAGES_RC, PAGES_STDOUT, PAGES_OUTPUT (the step's outputs file) and
# PAGES_GH_ARGS (the arguments gh was called with) are set.
run_pages_check() {
  local dir="${TMP}/pages-$2-$$-${RANDOM}"
  mkdir -p "${dir}/bin"
  step_block "$1" "Check that GitHub Pages is enabled" run > "${dir}/step.sh"
  cat > "${dir}/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_LOG:?}"
case "${STUB_MODE:?}" in
  ok) echo '{}' ;;
  404) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  *) echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1 ;;
esac
STUB
  chmod +x "${dir}/bin/gh"
  : > "${dir}/output"
  : > "${dir}/gh.log"
  PAGES_RC=0
  PAGES_STDOUT="$(PATH="${dir}/bin:${PATH}" STUB_MODE="$2" STUB_LOG="${dir}/gh.log" GH_TOKEN=token \
    REPOSITORY=acme/app GITHUB_OUTPUT="${dir}/output" bash "${dir}/step.sh" 2>&1)" || PAGES_RC=$?
  PAGES_OUTPUT="$(cat "${dir}/output")"
  PAGES_GH_ARGS="$(cat "${dir}/gh.log")"
}

# release_findings <file> — pin 14.
release_findings() {
  local name="Check that GitHub Pages is enabled" token="\${{ github.token }}" repo="\${{ github.repository }}"
  step_text "$1" "$name" | has -qxF "        if: github.event_name == 'release'" || echo "pages check: the step does not run only for a release"
  step_text "$1" "$name" | has -qxF "          GH_TOKEN: ${token}" || echo "pages check: the job token does not reach gh through env:"
  step_text "$1" "$name" | has -qxF "          REPOSITORY: ${repo}" || echo "pages check: the repository does not reach the shell through env:"
  step_text "$1" "$name" | has -qxF '        id: pages' || echo "pages check: the step has no id: pages"
  step_text "$1" "Publish to GitHub Pages" \
    | has -qxF "        if: github.event_name != 'release' || steps.pages.outputs.enabled == 'true'" \
    || echo "pages check: the deploy step is not skipped for a release with Pages not enabled"
  later "$(line_of "$1" "name: Publish to GitHub Pages")" "$(line_of "$1" "name: ${name}")" \
    || echo "pages check: the check does not come before the deploy step"
  run_pages_check "$1" ok
  { [[ "$PAGES_RC" -eq 0 && "$PAGES_OUTPUT" == "enabled=true" && "$PAGES_GH_ARGS" == "api repos/acme/app/pages" ]]; } \
    || echo "pages check: a site that exists must output enabled=true after asking repos/<repository>/pages (exit ${PAGES_RC}, output '${PAGES_OUTPUT}', gh '${PAGES_GH_ARGS}')"
  run_pages_check "$1" 404
  { [[ "$PAGES_RC" -eq 0 && "$PAGES_OUTPUT" == "enabled=false" && "$PAGES_STDOUT" == "::notice title=GitHub Pages is not enabled::"* ]]; } \
    || echo "pages check: a 404 must output enabled=false with a ::notice and exit 0 (exit ${PAGES_RC}, output '${PAGES_OUTPUT}')"
  run_pages_check "$1" 403
  { [[ "$PAGES_RC" -ne 0 && -z "$PAGES_OUTPUT" && "$PAGES_STDOUT" == "::error title=GitHub Pages check failed::"* ]]; } \
    || echo "pages check: any other failure must be an ::error and a failed step, never 'not enabled' (exit ${PAGES_RC}, output '${PAGES_OUTPUT}')"
}

# live_check_findings <file> — pin 15.
live_check_findings() {
  local job
  job="$(awk '/^  live-check:/ { j=1; print; next } j && /^  [a-z]/ { j=0 } j { print }' "$1")"
  if [[ -z "$job" ]]; then
    echo "live check: there is no live-check job"
    return 0
  fi
  grep -qxF '    needs: deploy' <<< "$job" || echo "live check: the job does not need the deploy job"
  grep -qxF "    if: needs.deploy.result == 'success' && needs.deploy.outputs.deployed == 'true'" <<< "$job" \
    || echo "live check: the job does not run only when the deploy step published"
  grep -qxF "      deployed: \${{ steps.deployment.outcome == 'success' }}" <(code "$1") \
    || echo "live check: the deploy job's deployed output is not the publish step's success"
  grep -qxF '      contents: read' <<< "$job" || echo "live check: the job does not hold contents: read"
  if grep -qE ': (write|admin)' <<< "$job"; then
    echo "live check: the job holds a write permission"
  fi
  grep -qxF '          persist-credentials: false' <<< "$job" || echo "live check: the checkout persists credentials"
  grep -qxF '        run: ./Scripts/live_check.sh https://forsgren.be' <<< "$job" \
    || echo "live check: the step does not run exactly ./Scripts/live_check.sh https://forsgren.be"
  later "$(line_of "$1" "  live-check:")" "$(line_of "$1" "  deploy:")" || echo "live check: the job does not come after the deploy job"
}

# findings <file>: every pin the file breaks, one line each.
findings() {
  trigger_findings "$1"
  permission_findings "$1"
  action_findings "$1"
  step_findings "$1"
  release_findings "$1"
  live_check_findings "$1"
}

OUT="$(findings "$WORKFLOW")"
if [[ -z "$OUT" ]]; then
  echo "  ok: the real workflow holds every pin"
else
  fail "the real workflow breaks a pin:"$'\n'"$OUT"
fi

# mutant <name> <sed-expression> <finding>: a copy of the workflow with the
# expression applied must break the pin that <finding> names.
mutant() {
  local file="${TMP}/$1.yml"
  sed "$2" "$WORKFLOW" > "$file"
  if cmp -s "$WORKFLOW" "$file"; then
    fail "the mutation $2 changed nothing: the proof of '$1' would be vacuous"
    return 0
  fi
  OUT="$(findings "$file")"
  if grep -qF -- "$3" <<< "$OUT"; then
    echo "  ok: mutation proof: $1"
  else
    fail "mutation proof: '$1' was not named '$3'. Findings: ${OUT:-none}"
  fi
}

mutant "a pull_request trigger" 's/^  workflow_dispatch:/  pull_request:/' "pull_request: a pull-request event"
mutant "no release trigger" 's/^  release:/  published:/' "triggers: want push, release"
mutant "a push to every branch" 's/^    branches: \[main\]/    branches: [main, dev]/' "push branches:"
mutant "the README out of the filter" 's/^      - README.md/      - README.mdx/' "push paths: README.md"
mutant "a release that is not published" 's/types: \[published\]/types: [created]/' "release types:"
mutant "a write token at the top" 's/^  contents: read/  contents: write/' "permissions: the top level"
mutant "no Pages permission" 's/pages: write/pages: read/' "deploy permissions:"
mutant "write-all" 's/pages: write/write-all/' "permissions: write-all"
mutant "a self-hosted runner" 's/runs-on: ubuntu-latest/runs-on: self-hosted/' "runs-on: every job"
mutant "an unpinned checkout" 's/checkout@[0-9a-f]\{40\}/checkout@v7/' "pins: an action is not pinned"
mutant "another commit of setup-go" 's/setup-go@b7ad/setup-go@b7ae/' "pin of setup-go:"
mutant "persisted credentials" 's/persist-credentials: false/persist-credentials: true/' "checkout: credentials are persisted"
mutant "another Go" "s/go-version: '${GO_VERSION}'/go-version: '1.26.0'/" "setup-go: not Go"
mutant "a Go cache" 's/cache: false/cache: true/' "setup-go: a cache"
mutant "another build command" 's#run: ./Scripts/build_starter_page.sh#run: ./Scripts/build_site.sh#' "build: the step does not run exactly"
mutant "a template expression in run" "s#run: ./Scripts/build_starter_page.sh#run: ./Scripts/build_starter_page.sh \${{ github.sha }}#" "injection:"
mutant "another upload path" 's#path: .build/starter#path: .build/site#' "upload: the path"
mutant "a deploy that needs nothing" 's/needs: build/needs: []/' "deploy: the job does not need"
mutant "another environment" 's/name: github-pages/name: production/' "deploy: the environment"
mutant "another concurrency group" 's/group: pages/group: pages-x/' "concurrency: the group"
mutant "a cancelled run in flight" 's/cancel-in-progress: false/cancel-in-progress: true/' "concurrency: a run in flight"

mutant "a deploy that ignores the Pages check" "s/if: github.event_name != 'release' || steps.pages.outputs.enabled == 'true'/if: true/" "pages check: the deploy step is not skipped"
mutant "a check on every event" "s/if: github.event_name == 'release'/if: true/" "pages check: the step does not run only for a release"
mutant "a 404 that is not recognised" 's/HTTP 404/HTTP 405/' "pages check: a 404 must output enabled=false"
mutant "a check that never says enabled" 's/enabled=true/enabled=maybe/' "pages check: a site that exists"
mutant "any failure read as not enabled" 's/\*"HTTP 404"\*/*/' "pages check: any other failure"

mutant "a live check that needs only the build" 's/needs: deploy/needs: build/' "live check: the job does not need the deploy job"
mutant "a live check that runs after a skipped deploy" "s/ && needs.deploy.outputs.deployed == 'true'//" "live check: the job does not run only when the deploy step published"
mutant "a deployed output that is always true" "s/steps.deployment.outcome == 'success'/true/" "live check: the deploy job's deployed output"
mutant "a live check with a write token" '/^  live-check:/,$ s/      contents: read/      contents: write/' "live check: the job holds a write permission"
mutant "a live check that persists credentials" '/^  live-check:/,$ s/persist-credentials: false/persist-credentials: true/' "live check: the checkout persists credentials"
mutant "a live check of another URL" 's#live_check.sh https://forsgren.be#live_check.sh https://example.org#' "live check: the step does not run exactly"
mutant "a live check of the http URL" 's#live_check.sh https://forsgren.be#live_check.sh http://forsgren.be#' "live check: the step does not run exactly"
mutant "a live check job renamed away" 's/^  live-check:/  live-look:/' "live check: there is no live-check job"

selftest_end "the starter page workflow pin found failures" "starter page workflow pin (the real file holds every pin; each mutant is named)"
