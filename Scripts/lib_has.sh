#!/usr/bin/env bash
# canon: lib_has v1
# Scripts/lib_has.sh
#
# The one way a script asks "does this stream hold this pattern", whatever
# writes the stream (forsgren#428, found in forsgren#425):
#
#   producer | has -qE 'pattern'
#
# A plain pipe into `grep -q` lets grep leave at its first match; under
# `set -o pipefail` the writer, still writing, then dies of SIGPIPE and the
# pipeline reads as failed: a pattern that IS there reads as missing. It
# shows only once the producer writes more than the pipe buffer (about 16 KB),
# so a check can pass for years and then break when a file grows.
#
# has <grep args>: reads ALL of stdin first, then runs `grep -q` with the
# arguments on it. Any grep flags go through (-E, -F, -x, -v, -i ...), so a
# call moves from the old form by changing `grep` to `has`. The exit status is
# grep's: 0 a line matched, 1 none did, 2 an error.
#
# Scripts/check_pipe_grep_q.sh refuses the plain form in Scripts/, and its
# self-test Scripts/test_check_pipe_grep_q.sh proves has finds a pattern
# after more output than a pipe holds. It reads stdin only, so a call that
# names a file stays a plain `grep -q pattern file`, which has no producer.
#
# SOURCED, never run. It sets no shell options and no traps; the sourcing
# script owns those.

# The text is handed over exactly as read (the trailing newlines survive, and
# empty input stays no line at all, so `-v` and `-x ''` judge what a plain
# pipe would), through a process substitution: it is no part of a pipeline, so
# its SIGPIPE cannot become the status.
has() {
  local in
  in="$(cat; printf x)"
  grep -q "$@" < <(printf '%s' "${in%x}")
}
