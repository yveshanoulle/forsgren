#!/usr/bin/env bash
# Scripts/lib_dco_api.sh — sourced, never run (forsgren#287).
#
# dco_api <what> <gh api arguments...>: one GitHub API call of the DCO
# workflow's scripts (Scripts/dco_push_check.sh, Scripts/dco_pr_commits.sh),
# asked once more when it fails. GitHub once answered a pull request lookup
# with an empty body; gh --jq failed on it (unexpected end of JSON input) and
# a signed-off push turned red, while the re-run was green.
#   - the call answers: the answer on stdout, status 0, one call;
#   - it fails, then answers after DCO_RETRY_PAUSE seconds (default 5; the
#     self-tests set 0): the answer on stdout, and on stderr one warning line
#     naming the first failure, status 0;
#   - it fails twice: one red line on stderr naming both reasons (gh's own
#     first line of each), status 1, nothing on stdout. A real outage or a
#     missing permission still turns the check red and shows its cause.
# The gh command is DCO_GH (default gh), the seam the self-tests stub.
# Fixtures: Scripts/test_check_dco.sh and Scripts/test_check_commit_messages.sh.

# dco_api_try <dir> <gh api arguments...>: one call, the answer in
# <dir>/answer and gh's error output in <dir>/reason.
dco_api_try() {
  local dir="$1"
  shift
  "${DCO_GH:-gh}" api "$@" > "$dir/answer" 2> "$dir/reason"
}

# dco_api_reason <dir>: the first line of the last call's error output.
dco_api_reason() {
  local reason
  reason="$(head -n 1 "$1/reason" | tr -d '\r')"
  printf '%s' "${reason:-gh exited with an error}"
}

# The mutation proof in Scripts/test_check_dco.sh rewrites the retry line
# (the `if` indented four spaces below): keep it alone on its line.
dco_api() {
  local what="$1" dir first
  shift
  dir="$(mktemp -d)" || return 1
  if ! dco_api_try "$dir" "$@"; then
    first="$(dco_api_reason "$dir")"
    sleep "${DCO_RETRY_PAUSE:-5}"
    if ! dco_api_try "$dir" "$@"; then
      echo "❌ FAIL: DCO: the GitHub API call for ${what} failed: ${first}; the retry failed too: $(dco_api_reason "$dir") — what cannot be looked up is not judged, so this is red" >&2
      rm -rf "$dir"
      return 1
    fi
    echo "⚠️  DCO: the GitHub API call for ${what} failed: ${first}; the retry answered, so the check goes on" >&2
  fi
  cat "$dir/answer"
  rm -rf "$dir"
}
