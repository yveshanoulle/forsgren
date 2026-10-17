#!/usr/bin/env bash
# Scripts/lib_go_tool.sh
#
# forsgren's own (forsgren#216): how the four Go-tool gates
# (Scripts/check_govulncheck.sh, Scripts/check_deadcode.sh,
# Scripts/check_go_lint.sh, Scripts/check_test_dupl.sh) find and run a tool
# that go.mod pins with a `tool` directive. The version stays where it was,
# in go.mod and go.sum; this only fixes the two steps they each did their own
# way, and forsgren#210 showed how that goes wrong: on a cold runner the
# "go: downloading ..." lines of `go tool -n` ended up in the tool path.
#
#   go_tool_path <tool>
#     GO_TOOL_BIN is what `go tool -n <tool>` prints on STDOUT, nothing else:
#     its stderr is not captured, so download lines stay in the log. Run it
#     from the repository root (the gates cd there first). It returns
#       0  GO_TOOL_BIN is an executable file,
#       1  `go tool -n <tool>` failed (the tool is not pinned in go.mod),
#       2  it printed a path that is not an executable file (not built).
#     The caller keeps its own FAIL line and exit code for 1 and 2.
#
#   go_tool_run <args...>
#     runs GO_TOOL_BIN with the arguments; its stdout and stderr together are
#     this function's output, and the return status is the tool's own exit
#     code, unchanged. Call it as out="$(go_tool_run ...)"; rc=$? so the code
#     is read next to the output. What 0, 1 or 3 mean differs per tool, and a
#     code the caller does not know is a tool that did not run.
#
# SOURCED, never run. It judges nothing on its own: Scripts/test_lib_go_tool.sh
# is its test (with mutation proofs), and each gate's self-test proves that
# gate's verdicts through it. It sets no shell options and no traps; the
# sourcing script owns those.

go_tool_path() {
  GO_TOOL_BIN=""
  if ! GO_TOOL_BIN="$(go tool -n "$1")"; then
    return 1
  fi
  if [ ! -f "$GO_TOOL_BIN" ] || [ ! -x "$GO_TOOL_BIN" ]; then
    return 2
  fi
  return 0
}

go_tool_run() {
  "$GO_TOOL_BIN" "$@" 2>&1
}
