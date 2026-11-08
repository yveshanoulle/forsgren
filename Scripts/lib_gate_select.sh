#!/usr/bin/env bash
# canon: lib_gate_select v2
# Scripts/lib_gate_select.sh. The gate selection shared by the sibling sites: the
# code is the same text in each. changed_files and the reason gate_select gives when
# it fails are fail-closed: a failing git diff or ls-files is no change set, and a
# rename lists both its paths.
#
# SOURCED, never run. It sets no shell options. The one place that turns the
# files a commit changed into the gates that need to run:
#   changed_files          the files changed against the merge base with origin/main
#   named_files <file>     the repository files a script names
#   closure <file>         a script and everything it names, transitively
#   gate_input_rows, gate_input_covered, gate_input_excluded
#                          readers of Scripts/gate_inputs.txt
#   gate_select <label>    prints `run: [<code>] <reason>` or `skip: [<code>] <reason>`, exit 0
#
# Scripts/test_gate_inputs.sh sources named_files and closure from here.
#
# No loop here reads a process substitution: on bash 3.2 that, called hundreds of
# times inside a captured pipeline, silently cut the tail of the captured output. A producer is
# read into a variable first and looped over with `done <<< "$rows"`; an empty row is skipped.
#
# gate_select reads Scripts/gate_inputs.txt (SFL_GATE_INPUTS names another file).
# The answer is one line: the word `run:` or `skip:`, then the stable reason code
# in square brackets, then the reason in words. The code never changes while the
# words may; a consumer that parses the line reads the word before the first colon
# and keeps the rest (code included) as the reason it shows. The codes, one per rule:
#   ci_full, forced_full, list_unreadable, no_in_rows, unknown_file, closure,
#   in_row, grep_row (all `run`), no_changes, none_changed (both `skip`).
# The order of its answers:
#   1. GITHUB_ACTIONS=true            run[ci_full]  (Quality runs every gate)
#   2. SFL_GATE_SELECT_FULL=1         run[forced_full]  (forced)
#   3. no origin/main to compare with run[list_unreadable]  (nothing to compare is
#      not nothing changed; a failing diff or file listing is the same)
#   4. the label has no `in` row      run[no_in_rows]  (a gate nobody listed is never skipped)
#   5. FAIL-SAFE: a changed file that no label's list names, neither as an `in`
#      path of any label nor as an `out` pattern of any label, selects every
#      listed gate, naming the file. What is not known to be irrelevant is
#      assumed relevant (unknown_file; closure when it is a Scripts/ file that a
#      listed gate's script names and the list forgot). Known to be irrelevant: a file an `out` row names (the
#      `none|out|...` rows of the list are the files no gate reads), and a file
#      under Scripts/ that is in the closure of no listed gate's script
#      (gate_unrelated_script).
#   6a. a changed script of Scripts/ whose text matches a `grep` row of the label
#      (a gate that finds its inputs by what a file says) run[grep_row]
#   6. a changed file under one of the label's `in` paths and matching none of its
#      `out` patterns          run[in_row]  (naming the file)
#   7. otherwise                      skip[no_changes] when no file changed, else
#      skip[none_changed]  (saying how many files changed)
# Where a rule says run[code] the answer is `run: [code] <reason>`.
# An `out` pattern is a glob (`*` within a name, `**/` any depth). Markdown never
# counts as a change (changed_files drops it): the gates that read markdown have
# no `in` rows, so they always run.

# named_files <file>: the repository files a script's non-comment lines name,
# one path per line. A token that looks like a file name is resolved to
# Scripts/<name>, .github/workflows/<name>, or the path itself when it exists.
named_files() {
  local code token tokens
  code="$(grep -v '^[[:space:]]*#' "$1" || true)"
  tokens="$(grep -oE '[A-Za-z0-9_./-]+[.](sh|mjs|js|py|awk|txt|json|toml|env|yml|yaml|go)' <<< "$code" | sort -u)"
  while IFS= read -r token; do
    token="${token#./}"
    [[ -z "$token" ]] && continue
    if [[ -f "$token" ]]; then
      echo "$token"
    elif [[ -f "Scripts/${token##*/}" ]]; then
      echo "Scripts/${token##*/}"
    elif [[ -f ".github/workflows/${token##*/}" ]]; then
      echo ".github/workflows/${token##*/}"
    fi
  done <<< "$tokens"
}

# closure <file>: the file and every file it names, transitively.
closure() {
  local seen=$'\n'"$1"$'\n' queue=("$1") i=0 f n names
  while [[ "$i" -lt "${#queue[@]}" ]]; do
    f="${queue[$i]}"
    i=$((i + 1))
    case "$f" in *.sh | *.mjs | *.js | *.py | *.awk) ;; *) continue ;; esac
    names="$(named_files "$f")"
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      if [[ "$seen" != *$'\n'"$n"$'\n'* ]]; then
        seen+="${n}"$'\n'
        queue+=("$n")
      fi
    done <<< "$names"
  done
  printf '%s' "$seen" | sed '/^$/d'
}

# changed_files: against the merge base with origin/main, the tracked changes
# (committed, staged and unstaged) and the untracked files git does not ignore.
# Non-zero when there is no origin/main to compare against, or when git cannot
# list the changes: each command runs on its own, because a `{ a; b; } |` group
# reports only b's status and would read a failing git diff as "nothing changed".
# --no-renames lists both the old and the new path of a rename. Markdown is prose.
changed_files() {
  local base tracked untracked
  base="$(git merge-base HEAD origin/main 2> /dev/null)" || return 1
  tracked="$(git diff --no-renames --name-only "$base" --)" || return 1
  untracked="$(git ls-files --others --exclude-standard)" || return 1
  printf '%s\n%s\n' "$tracked" "$untracked" | { grep -v '[.]md$' || true; } | { grep -v '^$' || true; } | sort -u
}

# gate_input_rows <inputs-file> <label> <kind>: the paths of a gate's rows of one kind.
# An empty label reads the rows of every gate.
gate_input_rows() {
  awk -F'|' -v l="$2" -v k="$3" '/^[[:space:]]*#/ || NF == 0 { next } (l == "" || $1 == l) && $2 == k { print $3 }' "$1"
}

# gate_input_covered <inputs-file> <label> <path>: the path is a listed `in`
# file of the label, or under a listed directory (a path ending in /).
gate_input_covered() {
  local p rows
  rows="$(gate_input_rows "$1" "$2" in)"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ "$p" == "$3" ]] || { [[ "$p" == */ ]] && [[ "$3" == "$p"* ]]; }; then return 0; fi
  done <<< "$rows"
  return 1
}

# gate_input_excluded <inputs-file> <label> <path>: the path matches an `out`
# pattern of the label. `*_test.go` matches at any depth; `a/**/testdata/` is a
# testdata directory anywhere under a/.
gate_input_excluded() {
  local p re rows star='[^/]*' deep='(.*/)?'
  rows="$(gate_input_rows "$1" "$2" out)"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    re="${p%/}"
    re="${re//./\\.}"
    re="${re//\*\*\//@@}"
    if [[ "$re" == *'/**' ]]; then re="${re%/\*\*}/@@@"; fi
    re="${re//\*/$star}"
    re="${re//@@@/.*}"
    re="${re//@@/$deep}"
    if [[ "$p" == */ ]]; then
      re="^${re}/"
    else
      re="(^|/)${re}\$"
    fi
    if [[ "$3" =~ $re ]]; then return 0; fi
  done <<< "$rows"
  return 1
}

# gate_input_grepped <inputs-file> <label> <path>: the path is a script of Scripts/
# that exists and whose text matches a `grep` row of the label. It is
# for a gate that discovers its inputs by what a file says (the scripts that write
# the step summary), so a file added tomorrow, in no list yet, still selects it.
gate_input_grepped() {
  local re rows
  [[ "$3" == Scripts/*.sh && -f "$3" ]] || return 1
  rows="$(gate_input_rows "$1" "$2" grep)"
  while IFS= read -r re; do
    [[ -z "$re" ]] && continue
    if grep -qE -- "$re" "$3"; then return 0; fi
  done <<< "$rows"
  return 1
}

# gate_unrelated_script <file>: a file under Scripts/ that is in the closure of no
# listed gate's script (the scripts come from the order file; SFL_GATE_ORDER
# names another). A script a browser gate reads is in its closure; a new one only
# becomes read when a closure file changes, which itself selects the gate. A file
# that is in a closure is not unrelated, even when the list forgot it.
gate_unrelated_script() {
  local inputs="${SFL_GATE_INPUTS:-Scripts/gate_inputs.txt}"
  local order="${SFL_GATE_ORDER:-Scripts/gate_report_order.txt}" label script related="" labels
  [[ "$1" == Scripts/* ]] || return 1
  labels="$(awk -F'|' '/^[[:space:]]*#/ || NF == 0 { next } $2 == "in" { print $1 }' "$inputs" | sort -u)"
  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    script="$(awk -F'|' -v l="$label" '$1 == l { print $2; exit }' "$order" 2> /dev/null)"
    [[ -f "$script" ]] && related+="$(closure "$script")"$'\n'
  done <<< "$labels"
  if grep -qxF -- "$1" <<< "$related"; then return 1; fi
  return 0
}

# gate_select <label>: one line, `run: [<code>] <reason>` or `skip: [<code>] <reason>`; exit 0.
gate_select() {
  local label="$1" inputs="${SFL_GATE_INPUTS:-Scripts/gate_inputs.txt}" changed c n=0
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "run: [ci_full] full run (Quality runs every gate)"
    return 0
  fi
  if [[ "${SFL_GATE_SELECT_FULL:-}" == "1" ]]; then
    echo "run: [forced_full] full run (SFL_GATE_SELECT_FULL=1)"
    return 0
  fi
  if ! changed="$(changed_files)"; then
    echo "run: [list_unreadable] full run (the change set could not be read: no origin/main to compare against, or git failed)"
    return 0
  fi
  if [[ -z "$(gate_input_rows "$inputs" "$label" in)" ]]; then
    echo "run: [no_in_rows] ${label} has no input list in ${inputs}"
    return 0
  fi
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    n=$((n + 1))
    if ! gate_input_covered "$inputs" "" "$c" && ! gate_input_excluded "$inputs" "" "$c"; then
      if ! gate_unrelated_script "$c"; then
        if [[ "$c" == Scripts/* ]]; then
          echo "run: [closure] ${c} is named by no gate's list, so every gate runs"
        else
          echo "run: [unknown_file] ${c} is named by no gate's list, so every gate runs"
        fi
        return 0
      fi
    fi
  done <<< "$changed"
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    if gate_input_covered "$inputs" "$label" "$c" && ! gate_input_excluded "$inputs" "$label" "$c"; then
      echo "run: [in_row] ${c} is an input of ${label}"
      return 0
    fi
    if gate_input_grepped "$inputs" "$label" "$c"; then
      echo "run: [grep_row] ${c} says what ${label} discovers its inputs by"
      return 0
    fi
  done <<< "$changed"
  if [[ "$n" -eq 0 ]]; then
    echo "skip: [no_changes] none of the 0 changed files is an input of ${label}"
  else
    echo "skip: [none_changed] none of the ${n} changed files is an input of ${label}"
  fi
}
