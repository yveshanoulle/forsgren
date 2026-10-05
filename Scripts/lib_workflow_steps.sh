#!/usr/bin/env bash
# Scripts/lib_workflow_steps.sh
#
# forsgren's own (forsgren#59, refactor): the awk readers of a workflow file
# that the pins of the two reusable workflows share,
# Scripts/test_metrics_workflow.sh and Scripts/test_auto_update_workflow.sh.
# Each carried its own byte-identical copy; this is that code, once. A
# workflow is read with awk, not a YAML parser: PyYAML is a module, not a
# command, and nothing here installs it. The readers know the layout both
# workflows share: a step's dash line six spaces in, its keys eight.
#
# Not shared: install_outcome. The auto-update pin's copy also requires the
# ::error line on a refusal and GOBIN on the GITHUB_PATH file on an install;
# the metrics pin's does not, and its mutation proofs are built on that.
# Unifying them would loosen one pin or change the other's verdicts.
#
# SOURCED, never run. It judges nothing on its own: the two pins that source
# it are its test. It sets no shell options and no traps; the sourcing
# script owns those.

# on_events <file>: the event names of the column-0 `on:` block, one per line.
on_events() {
  awk '
    /^on:[[:space:]]*$/ { inon=1; next }
    inon && /^[^[:space:]#]/ { inon=0 }
    inon && /^  [A-Za-z_]+:/ { s=$0; sub(/^  /, "", s); sub(/:.*$/, "", s); print s }
  ' "$1"
}

# run_blocks <file>: every run: line and the lines of its block, as
# <lineno>:<text>, so a finding names its line.
run_blocks() {
  awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    inrun && $0 !~ /^[[:space:]]*$/ && indent($0) <= runind { inrun=0 }
    inrun { print NR ":" $0; next }
    /^[[:space:]]*(- )?run:/ {
      print NR ":" $0
      runind = indent($0)
      if ($0 ~ /- run:/) runind += 2
      if ($0 ~ /run:[[:space:]]*[|>][-+]?[[:space:]]*$/) inrun=1
    }
  ' "$1"
}

# step_block <file> <step name> <key>: the block under that step's key
# (run or env), its lines dedented; nothing when there is no such step.
step_block() {
  awk -v name="$2" -v key="$3" '
    function indent(s) { match(s, /^ */); return RLENGTH }
    /^      - / { instep = ($0 == "      - name: " name); inb=0; next }
    instep && inb && $0 !~ /^[[:space:]]*$/ && indent($0) <= 8 { inb=0 }
    instep && inb { if (!cut) { match($0, /^ */); cut = RLENGTH } print substr($0, cut + 1); next }
    instep && $0 ~ ("^        " key ":[[:space:]]*\\|?[[:space:]]*$") { inb=1 }
  ' "$1"
}

# step_text <file> <step name>: every line of that step, the dash line
# included; nothing when there is no such step.
step_text() {
  awk -v name="$2" '
    /^      - / { instep = ($0 == "      - name: " name) }
    instep { print }
  ' "$1"
}

# line_of <file> <fixed text>: the line number of its first occurrence.
line_of() {
  grep -nF -- "$2" "$1" | head -1 | cut -d: -f1
}

# later <line> <other line>: true when both are known and the first comes
# after the second.
later() {
  [[ -n "$1" && -n "$2" && "$1" -gt "$2" ]]
}
