#!/usr/bin/env bash
# Scripts/lib_summary_writers.sh (forsgren#264). Not canon: forsgren only.
#
# SOURCED, never run. It sets no shell options. The one place that finds the
# scripts that append to the step summary and the self-tests that run them:
# Scripts/test_step_summary_isolation.sh runs those self-tests, and
# Scripts/test_gate_inputs.sh holds Scripts/gate_inputs.txt to list what they read,
# so a script added tomorrow cannot be missing from the list.
#
# summary_writer_names             every non-test, non-library script of Scripts/ that
#                                  mentions GITHUB_STEP_SUMMARY, by file name
# summary_selftests <skip> <name>...
#                                  the Scripts/test_*.sh that name one of the scripts,
#                                  except the self-test called <skip>
# summary_reads <skip>             every file the gate runs or reads, `<file><TAB><through>`

summary_writer_names() {
  { grep -l 'GITHUB_STEP_SUMMARY' Scripts/*.sh | grep -v '/test_' | grep -v '/lib_'; } | sed 's#^Scripts/##'
}

summary_selftests() {
  local skip="$1" t name
  shift
  for t in Scripts/test_*.sh; do
    [[ "$(basename "$t")" == "$skip" ]] && continue
    for name in "$@"; do
      if grep -qF -- "$name" "$t"; then echo "$t"; break; fi
    done
  done
}

# SUMMARY_TEXT_ONLY: the self-tests that read the other scripts as text and run none
# of them, so what they read is the file and what it sources, not its closure.
# The wiring pin of every gate names nearly all of them; it greps them, and what it
# runs is fixtures it writes itself. Following its names would make every script of
# the repository an input of the gate. The names are written without the extension
# so that this library's own closure does not follow them.
SUMMARY_TEXT_ONLY=("test_gate_wiring")

# summary_reads <skip>: needs Scripts/lib_gate_select.sh sourced (closure). One line
# per file the gate runs or reads, `<file><TAB><through>`: each writer, each self-test
# that names one, and the closure of each (the sourced files only for a text-only one).
summary_reads() {
  local skip="$1" names=() w t f text
  while IFS= read -r w; do names+=("$w"); done < <(summary_writer_names)
  for w in "${names[@]}"; do
    while IFS= read -r f; do printf '%s\t%s\n' "$f" "Scripts/${w}"; done < <(closure "Scripts/${w}")
  done
  while IFS= read -r t; do
    text=0
    for f in "${SUMMARY_TEXT_ONLY[@]}"; do [[ "$(basename "$t" .sh)" == "$f" ]] && text=1; done
    if [[ "$text" == 1 ]]; then
      printf '%s\t%s\n' "$t" "$t"
      while IFS= read -r f; do printf '%s\t%s\n' "$f" "$t"; done < <(grep -E '^source Scripts/' "$t" | awk '{ print $2 }')
    else
      while IFS= read -r f; do printf '%s\t%s\n' "$f" "$t"; done < <(closure "$t")
    fi
  done < <(summary_selftests "$skip" "${names[@]}")
}
