#!/usr/bin/env bash
# Scripts/lib_gate_select.sh (forsgren#262, step 2 of 3). Not canon: forsgren only.
#
# SOURCED, never run. It sets no shell options. The one place that turns the
# files a commit changed into the gates that need to run:
#   changed_files          the files changed against the merge base with origin/main
#   named_files <file>     the repository files a script names
#   closure <file>         a script and everything it names, transitively
#   gate_input_rows, gate_input_covered, gate_input_excluded
#                          readers of Scripts/gate_inputs.txt
#   gate_select <label>    prints `run: <reason>` or `skip: <reason>`, exit 0
#
# changed_files, named_files and closure were Scripts/test_git_sandbox_isolation.sh's
# (forsgren#251); it sources them from here now, as Scripts/test_gate_inputs.sh does.
#
# No loop here reads a process substitution (forsgren#459): on bash 3.2 that, called hundreds of
# times inside a captured pipeline, silently cut the tail of the captured output. A producer is
# read into a variable first and looped over with `done <<< "$rows"`; an empty row is skipped.
#
# gate_select reads Scripts/gate_inputs.txt (FORSGREN_GATE_INPUTS names another file).
# The order of its answers:
#   1. GITHUB_ACTIONS=true            run  (Quality runs every gate)
#   2. FORSGREN_GATE_SELECT_FULL=1    run  (forced)
#   3. no origin/main to compare with run  (nothing to compare is not nothing changed)
#   4. the label has no `in` row      run  (a gate nobody listed is never skipped)
#   5. FAIL-SAFE: a changed file that no label's list names, neither as an `in`
#      path of any label nor as an `out` pattern of any label, selects every
#      listed gate, naming the file. What is not known to be irrelevant is
#      assumed relevant. Known to be irrelevant: a file an `out` row names (the
#      `none|out|...` rows of the list are the files no gate reads: workflows,
#      docs, the release scripts, sfl.sh and FBP.sh), and a file under Scripts/ that is in the
#      closure of no gate's script (gate_unrelated_script).
#   6a. a changed script of Scripts/ whose text matches a `grep` row of the label
#      (forsgren#264: the gate finds its inputs by what a file says) run
#   6. a changed file under one of the label's `in` paths and matching none of its
#      `out` patterns          run  (naming the file)
#   7. otherwise                      skip (saying how many files changed)
# *_test.go and testdata/ are `out` patterns of the browser gates (forsgren#281):
# they never select them, and are not unknown either. Markdown never counts as a
# change (changed_files drops it), as in the isolation gate.

# named_files <file>: the repository files a script's non-comment lines name,
# one path per line. A token that looks like a file name is resolved to
# Scripts/<name>, .github/workflows/<name>, or the path itself when it exists.
named_files() {
  local code token tokens
  code="$(grep -v '^[[:space:]]*#' "$1" || true)"
  tokens="$(grep -oE '[A-Za-z0-9_./-]+[.](sh|mjs|js|py|txt|json|yml|yaml|go)' <<< "$code" | sort -u)"
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
    case "$f" in *.sh | *.mjs | *.js | *.py) ;; *) continue ;; esac
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
# Non-zero when there is no origin/main to compare against. Markdown is prose.
changed_files() {
  local base
  base="$(git merge-base HEAD origin/main 2> /dev/null)" || return 1
  { git diff --name-only "$base" --; git ls-files --others --exclude-standard; } | { grep -v '[.]md$' || true; } | sort -u
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
# that exists and whose text matches a `grep` row of the label (forsgren#264). It is
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
# listed gate's script (the scripts come from the order file; FORSGREN_GATE_ORDER
# names another). A script a browser gate reads is in its closure; a new one only
# becomes read when a closure file changes, which itself selects the gate. A file
# that is in a closure is not unrelated, even when the list forgot it.
gate_unrelated_script() {
  local inputs="${FORSGREN_GATE_INPUTS:-Scripts/gate_inputs.txt}"
  local order="${FORSGREN_GATE_ORDER:-Scripts/gate_report_order.txt}" label script related="" labels
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

# gate_select <label>: one line, `run: <reason>` or `skip: <reason>`; exit 0.
gate_select() {
  local label="$1" inputs="${FORSGREN_GATE_INPUTS:-Scripts/gate_inputs.txt}" changed c n=0
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "run: full run (Quality runs every gate)"
    return 0
  fi
  if [[ "${FORSGREN_GATE_SELECT_FULL:-}" == "1" ]]; then
    echo "run: full run (FORSGREN_GATE_SELECT_FULL=1)"
    return 0
  fi
  if ! changed="$(changed_files)"; then
    echo "run: full run (no origin/main to compare against)"
    return 0
  fi
  if [[ -z "$(gate_input_rows "$inputs" "$label" in)" ]]; then
    echo "run: ${label} has no input list in ${inputs}"
    return 0
  fi
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    n=$((n + 1))
    if ! gate_input_covered "$inputs" "" "$c" && ! gate_input_excluded "$inputs" "" "$c"; then
      if ! gate_unrelated_script "$c"; then
        echo "run: ${c} is named by no gate's list, so every gate runs"
        return 0
      fi
    fi
  done <<< "$changed"
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    if gate_input_covered "$inputs" "$label" "$c" && ! gate_input_excluded "$inputs" "$label" "$c"; then
      echo "run: ${c} is an input of ${label}"
      return 0
    fi
    if gate_input_grepped "$inputs" "$label" "$c"; then
      echo "run: ${c} says what ${label} discovers its inputs by"
      return 0
    fi
  done <<< "$changed"
  echo "skip: none of the ${n} changed files is an input of ${label}"
}
