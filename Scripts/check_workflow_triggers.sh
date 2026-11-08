#!/usr/bin/env bash
# canon: check_workflow_triggers v3
# Scripts/check_workflow_triggers.sh
#
# The workflow-trigger gate, byte-identical across the
# estate's repositories.
#
# THE RULE: a workflow with a job on a self-hosted runner never triggers on a
# pull-request event. On such a trigger a pull request from a fork runs its own
# code on that runner, a machine someone keeps, once the repository is public.
# On a GitHub-hosted runner it runs on a machine thrown away after the job.
# the quality-workflow self-test pins the shape quality.yml must have;
# this gate bans the one shape no workflow may have, whatever the file, except
# where a job-level guard (v3, below) or a row of the exceptions file says
# otherwise.
#
# THE GUARD (v3, forsgren#645, Yves's ruling, option C): on `pull_request`, and
# on no other pull-request event, a job off GitHub-hosted runners is allowed
# when its own job-level `if:` is an accepted guard: an expression that is
# false for a fork's pull request because it positively establishes that the
# pull request's head repository is this repository. GitHub evaluates a
# job-level `if:` before it allocates a runner, so a skipped job never reaches
# one. Only the job's own key counts:
#   - a step-level `if:` does not (the runner is allocated before any step);
#   - a `needs:` dependency does not (a job that needs a skipped job can still
#     run, under always() or a status function, and needs: is never read here);
#   - a reusable-workflow job (job-level `uses:`) is protected by its own
#     accepted guard, which skips the whole called workflow; without one the
#     called file is inspected when it is local (`./.github/workflows/<file>`,
#     read from the workflows dir this gate scans), each of its jobs judged by
#     these same rules, levels deep, a cycle red; a remote one, one named by an
#     expression, or a missing file is red, since this gate cannot read it;
#   - a runner this gate cannot classify (below) needs the guard as a
#     self-hosted one does.
# The accepted guards, token for token (GUARD_HEAD, GUARD_BASE, GUARD_EVENT
# and GUARD_LITERAL below), with S and N the two atoms:
#   S  github.event.pull_request.head.repo.full_name == github.repository
#      (the operands in either order)
#   N  github.event_name != 'pull_request'   (the operands in either order)
# An expression E is a guard when, after the parentheses around it are
# dropped:
#   - E is S; or
#   - E is A1 || A2 || ... at its top level, every Ai is N or a guard, and at
#     least one Ai is a guard (so `N || S` and `S || N`: both sides false for
#     a fork; `S || X` with any other X is red, X could be true for a fork,
#     and `N || N` is red, it establishes nothing about the head); or
#   - E is C1 && C2 && ... at its top level and at least one Ci is a guard
#     (a conjunction with a guard is false whenever the guard is).
# && binds tighter than || (GitHub's precedence), so `S && X || Y` is the
# disjunction `(S && X) || Y`, red. Nothing else counts: a negation `!` over a
# guard, `!=` in S, `==` in N, another property (`head.repo.fork`,
# `base.repo.full_name`, a misspelling), another literal (another event's
# name), a function (`contains(...)`), index syntax, or a comparison inside a
# larger term. The value is read as YAML would give it: plain, single-quoted
# ('' an escaped quote) or double-quoted without escapes, a trailing comment
# dropped, then wholly inside `${{ }}` or not at all (`${{ S }} && X` mixes
# the two, and GitHub does not evaluate it as one expression). A value that
# is empty, spans several lines, starts with a YAML indicator (`!` is a YAML
# tag), does not tokenize (an unbalanced parenthesis, an unknown character),
# or a job with two `if:` keys is red, named. A guard never needs an
# exception row, and an exception row for a guarded job excuses nothing, so
# it is red as any unused row.
#
# EXCEPTIONS are data, never edited copies: Scripts/workflow_trigger_exceptions.txt,
# one row per workflow file and event, workflow|event|reason. The reason is
# required (why the trigger stays, and the issue that makes it safe); a row
# without one is red. An exception covers exactly that file and that event: a
# NEW pull-request event in the same file, or the same event in another file,
# is a finding again. A row that excuses nothing (the trigger is gone, or the
# job moved to a hosted runner, or every job is guarded) is red too, so an
# exception cannot outlive its reason. A missing exceptions file is exit 2; a
# repository with none keeps the file with comments only.
#
# Pull-request events: pull_request and pull_request_target, the two the
# ruling names, plus pull_request_review and pull_request_review_comment.
# Those two also run for a fork's pull request and check out its merge commit
# by default, so they open the same door. Other events (workflow_run,
# issue_comment) run the default branch's workflow and code, and are not
# judged here.
#
# FAIL-CLOSED ON THE RUNNER. A job counts as GitHub-hosted only when its
# runs-on is one plain label of a GitHub-hosted image (ubuntu-*, windows-*,
# macos-*). Everything else is judged as if self-hosted: the self-hosted
# label, a list of labels, a custom label alone (only a self-hosted runner
# carries one), a runner group, an expression such as ${{ matrix.os }} (this
# gate cannot evaluate it), a job with no runs-on, and a reusable-workflow job
# (job-level uses:, whose runner is decided in the file it calls). A larger
# GitHub-hosted runner, named by its own label, is therefore red too; a
# workflow that needs one says so here first.
#
# READ WITH AWK, NOT A YAML PARSER, on purpose, as
# the quality-workflow self-test does. PyYAML is a Python module, not a command, so
# Scripts/required_tools.txt (commands only) cannot declare it and
# Scripts/install_tools.sh cannot install it, and a gate that dies on a
# missing module on another Mac or on a fresh hosted runner has stopped
# gating. The shapes it reads, and its limits:
#   - `on:` is a top-level key at column 0 (bare, "on" or 'on'); the trigger
#     section is the rest of that line plus every line after it up to the
#     next column-0 key. Comments are dropped (a # at line start or after
#     whitespace). What is left is split into words, and a word that is a
#     pull-request event name is a trigger. That reads the scalar, flow
#     list, flow map, block list and block map forms alike. Its limit is on
#     the safe side: a branch or path literally named pull_request inside the
#     section is red too.
#   - No `on:` key at column 0 is red: a trigger this gate cannot read is not
#     a trigger it has cleared.
#   - Jobs are the keys one level under the column-0 `jobs:`; a job's own
#     keys sit one level deeper (the indent of its first key). runs-on, uses
#     and if are read at that level: runs-on inline or as the block lines
#     under it, uses and if inline only. A job written in flow style shows no
#     keys here, so it has no guard this gate can see.
#
# Usage: Scripts/check_workflow_triggers.sh [workflows-dir [exceptions-file]]
#        (default: .github/workflows; the *.yml and *.yaml files directly in
#        it, the only ones GitHub runs)
# Exit: 0 clean, 1 a finding, a bad or unused exception row, or a scan over
# nothing, 2 workflows dir or exceptions file missing.
# Fixture: Scripts/test_check_workflow_triggers.sh.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

DIR="${1:-.github/workflows}"
EXCEPTIONS="${2:-Scripts/workflow_trigger_exceptions.txt}"

# The pull-request events, one alternation for grep -xE. The row starts at
# column 0 with PR_EVENTS=: Scripts/test_check_workflow_triggers.sh's mutation
# proof replaces it by that anchor.
PR_EVENTS='pull_request|pull_request_target|pull_request_review|pull_request_review_comment'

# A GitHub-hosted image label, the one runs-on value judged as not
# self-hosted.
HOSTED_LABEL='^(ubuntu|windows|macos)-[A-Za-z0-9._-]+$'

# The one event a job-level guard counts for (v3).
GUARDED_EVENT='pull_request'

# The tokens of the guard's two atoms (see THE GUARD above). Each row starts
# at column 0: the self-test's mutation proofs replace them.
GUARD_HEAD='github.event.pull_request.head.repo.full_name'
GUARD_BASE='github.repository'
GUARD_EVENT='github.event_name'
GUARD_LITERAL="'pull_request'"

# How deep a chain of local reusable workflows is followed before it is red.
MAX_CALL_DEPTH=10

if [ ! -d "$DIR" ]; then
  echo "❌ FAIL: workflows dir not found: ${DIR}"
  exit 2
fi
if [ ! -f "$EXCEPTIONS" ]; then
  echo "❌ FAIL: exceptions file not found: ${EXCEPTIONS} (keep it with comments only when there is no exception)"
  exit 2
fi

# The exception rows, workflow|event|reason. EXC_ROWS holds the valid ones; a
# row with a missing field or an empty reason is a finding. Strings, not
# arrays: an empty array under set -u is fatal on bash 3.2.
EXC_ROWS=""
EXC_USED=""
findings=0
guarded=0
while IFS= read -r row; do
  case "$row" in ''|\#*) continue ;; esac
  IFS='|' read -r ex_name ex_event ex_reason <<<"$row"
  ex_has_reason="$(printf '%s' "${ex_reason:-}" | tr -d '[:space:]')"
  if [ -z "${ex_name:-}" ] || [ -z "${ex_event:-}" ] || [ -z "$ex_has_reason" ]; then
    echo "❌ FAIL: ${EXCEPTIONS}: bad row '${row}' — wanted workflow|event|reason, with a reason"
    findings=$((findings + 1))
    continue
  fi
  EXC_ROWS="${EXC_ROWS}${ex_name}|${ex_event}|${ex_reason}"$'\n'
done < "$EXCEPTIONS"

# excepted <workflow> <event> — 0 when a row covers exactly this file and event.
excepted() {
  awk -F'|' -v n="$1" -v e="$2" '$1 == n && $2 == e { f = 1 } END { exit !f }' <<<"$EXC_ROWS"
}

# exception_reason <workflow> <event> — the row's reason.
exception_reason() {
  awk -F'|' -v n="$1" -v e="$2" '$1 == n && $2 == e { print $3; exit }' <<<"$EXC_ROWS"
}

# trigger_events <file> — the pull-request events its `on:` section names,
# one per line; NO_ON_KEY when the file has no `on:` key at column 0.
trigger_events() {
  local section
  section="$(awk -v q="'" '
    function uncomment(s) {
      if (s ~ /^[ \t]*#/) return ""
      sub(/[ \t]+#.*$/, "", s)
      return s
    }
    BEGIN { onkey = "^(on|\"on\"|" q "on" q "):" }
    state == 0 && $0 ~ onkey {
      found = 1; state = 1
      rest = $0; sub(/^[^:]*:/, "", rest)
      print uncomment(rest)
      next
    }
    state == 1 && $0 ~ /^[^ \t#]/ { state = 2 }
    state == 1 { print uncomment($0) }
    END { if (!found) print "NO_ON_KEY" }
  ' "$1")"
  if [ "$section" = "NO_ON_KEY" ]; then
    echo "NO_ON_KEY"
    return 0
  fi
  printf '%s\n' "$section" | tr -c 'A-Za-z0-9_-' '\n' | grep -xE "$PR_EVENTS" | sort -u
}

# job_table <file> — one line per job, five fields parted by the unit
# separator (\037, so an empty field stays a field): the job; its runs-on (the
# inline value, the block lines under it joined by spaces, USES for a
# reusable-workflow job, or NONE); its uses: value; the state of its
# job-level if: (none, one, twice, or multi for a value over several lines);
# and the if: value as written, its comment kept.
job_table() {
  awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function uncomment(s) { sub(/[ \t]+#.*$/, "", s); return s }
    function flush() {
      if (job == "") return
      if (ro != "") v = ro; else if (uses != "") v = "USES"; else v = "NONE"
      if (ifs == "") ifs = "none"
      gsub(/[\t\037]/, " ", ifraw)
      printf "%s\037%s\037%s\037%s\037%s\n", job, v, uses, ifs, ifraw
      job = ""
    }
    BEGIN { state = "before"; J = -1 }
    state == "before" { if ($0 ~ /^jobs:[ \t]*$/) state = "jobs"; next }
    $0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]*#/ { next }
    {
      ind = indent($0)
      if (ind == 0) exit
      if (J < 0) J = ind
      if (ind < J) exit
      if (ind == J) {
        flush()
        job = trim($0); sub(/:.*$/, "", job); gsub(/["\047]/, "", job)
        K = -1; ro = ""; uses = ""; inro = 0; inif = 0; ifs = ""; ifraw = ""
        next
      }
      if (K < 0) K = ind
      if (ind == K) {
        inro = 0; inif = 0
        line = trim(uncomment($0))
        if (line ~ /^runs-on:/) {
          sub(/^runs-on:[ \t]*/, "", line)
          if (line == "") inro = 1; else ro = line
        } else if (line ~ /^uses:/) {
          sub(/^uses:[ \t]*/, "", line)
          uses = (line == "") ? "?" : line
        } else if (line ~ /^if:/) {
          raw = trim($0); sub(/^if:[ \t]*/, "", raw)
          if (ifs == "") { ifs = "one"; ifraw = raw; inif = 1 } else ifs = "twice"
        }
        next
      }
      if (ind > K && inro) ro = trim(ro " " trim(uncomment($0)))
      if (ind > K && inif && ifs == "one") ifs = "multi"
    }
    END { flush() }
  ' "$1"
}

# hosted <runs-on> — 0 when it is one GitHub-hosted image label.
hosted() {
  local label="$1"
  label="${label#\"}"; label="${label%\"}"
  label="${label#\'}"; label="${label%\'}"
  grep -qE "$HOSTED_LABEL" <<< "$label"
}

# runner_words <runs-on> — how a finding names the job's runner.
runner_words() {
  case "$1" in
    USES) echo "a reusable workflow (job-level uses:), whose runner this file does not show" ;;
    NONE) echo "no runs-on this gate could read" ;;
    *)    echo "runs-on $1" ;;
  esac
}

# guard_verdict <if-value> — OK when the value, read as YAML gives it, is an
# accepted guard (see THE GUARD above); otherwise the reason it is not. The
# value reaches awk through the environment, so no backslash is reinterpreted.
guard_verdict() {
  GV_EXPR="$1" GV_HEAD="$GUARD_HEAD" GV_BASE="$GUARD_BASE" GV_EVENT="$GUARD_EVENT" GV_LITERAL="$GUARD_LITERAL" awk '
    function red(why) { print why; exit }
    function unread(why) { red("it cannot be read as an expression: " why) }
    function count(s, x,   c, p) {
      c = 0
      while ((p = index(s, x)) > 0) { c++; s = substr(s, p + length(x)) }
      return c
    }
    function cls(x) {
      if (x == "&&" || x == "||" || x == "==" || x == "!=" || x == "<" || x == "<=" || x == ">" || x == ">=") return "bin"
      if (x == "!") return "not"
      if (x == "(") return "lp"
      if (x == ")") return "rp"
      if (x == ",") return "comma"
      if (substr(x, 1, 1) == "\047") return "str"
      return "ident"
    }
    # topop(a, b): the operator at the top level of tokens a..b: || when
    # there is one, else && when there is one, else "".
    function topop(a, b,   i, and) {
      and = 0
      for (i = a; i <= b; i++) {
        if (t[i] == "(") { i = m[i]; continue }
        if (t[i] == "||") return "||"
        if (t[i] == "&&") and = 1
      }
      return and ? "&&" : ""
    }
    function isS(a, b) {
      while (a < b && t[a] == "(" && m[a] == b) { a++; b-- }
      return b == a + 2 && t[a + 1] == "==" && ((t[a] == H && t[b] == B) || (t[a] == B && t[b] == H))
    }
    function isN(a, b) {
      while (a < b && t[a] == "(" && m[a] == b) { a++; b-- }
      return b == a + 2 && t[a + 1] == "!=" && ((t[a] == EV && t[b] == L) || (t[a] == L && t[b] == EV))
    }
    # F(a, b): tokens a..b are a guard.
    function F(a, b,   i, s, anyF, op) {
      while (a < b && t[a] == "(" && m[a] == b) { a++; b-- }
      if (a > b) return 0
      if (isS(a, b)) return 1
      op = topop(a, b)
      if (op == "") return 0
      s = a; anyF = 0
      for (i = a; i <= b + 1; i++) {
        if (i <= b && t[i] == "(") { i = m[i]; continue }
        if (i > b || t[i] == op) {
          if (s > i - 1) return 0
          if (F(s, i - 1)) anyF = 1
          else if (op == "&&") anyF = anyF
          else if (!isN(s, i - 1)) return 0
          s = i + 1
        }
      }
      return anyF
    }
    BEGIN {
      v = ENVIRON["GV_EXPR"]; H = ENVIRON["GV_HEAD"]; B = ENVIRON["GV_BASE"]
      EV = ENVIRON["GV_EVENT"]; L = ENVIRON["GV_LITERAL"]
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      c = substr(v, 1, 1)
      if (c == "|" || c == ">") red("it is a YAML block scalar, over several lines, which this gate does not read")
      if (c == "\047") {
        out = ""; i = 2; closed = 0
        while (i <= length(v)) {
          d = substr(v, i, 1)
          if (d == "\047") { if (substr(v, i + 1, 1) == "\047") { out = out "\047"; i += 2; continue } closed = i; break }
          out = out d; i++
        }
        if (!closed) unread("a YAML single quote without its end")
        if (substr(v, closed + 1) !~ /^([ \t]+#.*)?[ \t]*$/) unread("text after the closing YAML quote")
        v = out
      } else if (c == "\"") {
        closed = index(substr(v, 2), "\"")
        if (!closed) unread("a YAML double quote without its end")
        out = substr(v, 2, closed - 1)
        if (index(out, "\\") > 0) unread("a backslash escape in a double-quoted YAML value")
        if (substr(v, closed + 2) !~ /^([ \t]+#.*)?[ \t]*$/) unread("text after the closing YAML quote")
        v = out
      } else {
        if (c == "#") v = ""
        if (c ~ /[!&*@`%{\[]/) red("YAML reads a plain value that starts with " c " as something other than the expression (a tag, an anchor, an alias, a flow collection or a reserved character); quote it or wrap it in ${{ }}")
        if (match(v, /[ \t]#/)) v = substr(v, 1, RSTART - 1)
        if (index(v, ": ") > 0) unread("\": \" in a plain YAML value")
      }
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (v == "") red("an empty job-level if:, which guards nothing")
      if (index(v, "${{") > 0 || index(v, "}}") > 0) {
        if (substr(v, 1, 3) == "${{" && substr(v, length(v) - 1) == "}}" && count(v, "${{") == 1 && count(v, "}}") == 1) v = substr(v, 4, length(v) - 5)
        else red("it mixes ${{ }} with other text, and GitHub does not evaluate that as one expression")
      }
      n = 0; i = 1; len = length(v)
      while (i <= len) {
        c = substr(v, i, 1); two = substr(v, i, 2)
        if (c == " " || c == "\t") { i++; continue }
        if (two == "&&" || two == "||" || two == "==" || two == "!=" || two == "<=" || two == ">=") { t[++n] = two; i += 2; continue }
        if (c == "!") { t[++n] = "!"; i++; continue }
        if (c == "(" || c == ")" || c == "," || c == "<" || c == ">") { t[++n] = c; i++; continue }
        if (c == "\047") {
          j = i + 1; lit = "\047"; ok = 0
          while (j <= len) {
            d = substr(v, j, 1)
            if (d == "\047") { if (substr(v, j + 1, 1) == "\047") { lit = lit "\047\047"; j += 2; continue } ok = 1; break }
            lit = lit d; j++
          }
          if (!ok) unread("a string without its closing quote")
          t[++n] = lit "\047"; i = j + 1; continue
        }
        if (c ~ /[A-Za-z0-9_]/) {
          j = i
          while (j <= len && substr(v, j, 1) ~ /[A-Za-z0-9_.*-]/) j++
          t[++n] = substr(v, i, j - i); i = j; continue
        }
        unread("the character " c " is not one this gate reads")
      }
      depth = 0; prev = "start"
      for (k = 1; k <= n; k++) {
        x = cls(t[k])
        if (prev == "start" || prev == "bin" || prev == "not" || prev == "lp" || prev == "comma") {
          if (!(x == "ident" || x == "str" || x == "not" || x == "lp" || (x == "rp" && prev == "lp" && call[stack[depth]]))) unread("\"" t[k] "\" where an operand belongs")
        } else if (prev == "ident") {
          if (x == "not" || x == "ident" || x == "str") unread("\"" t[k] "\" right after an operand")
        } else if (!(x == "bin" || x == "rp" || x == "comma")) unread("\"" t[k] "\" right after an operand")
        if (x == "lp") { stack[++depth] = k; call[k] = (prev == "ident") }
        if (x == "rp") {
          if (depth == 0) unread("a ) without its (")
          m[stack[depth]] = k; m[k] = stack[depth]; depth--
        }
        if (x == "comma" && (depth == 0 || !call[stack[depth]])) unread("a comma outside a function call")
        prev = x
      }
      if (depth != 0) unread("a ( without its )")
      if (!(prev == "ident" || prev == "str" || prev == "rp")) unread("it ends with an operator")
      if (F(1, n)) { print "OK"; exit }
      hasH = 0
      for (k = 1; k <= n; k++) if (t[k] == H) hasH = 1
      if (!hasH) red("it does not compare " H " with " B " as the accepted guard does")
      a = 1; b = n
      while (a < b && t[a] == "(" && m[a] == b) { a++; b-- }
      op = topop(a, b)
      if (op == "||") red("one side of a top-level || is neither the guard nor " EV " != " L ", and that side can be true for a fork")
      if (op == "&&") red("no part joined by && is the guard (an inverted, wrapped or changed comparison does not count)")
      if (t[a] == "!") red("the guard is inverted (!), which makes it true for a fork")
      red("it is not one of the accepted guard forms (the comparison must stand alone, with == and the operands as the header names them)")
    }
  '
}

# job_problems <file> <job> <runs-on> <uses> <if-state> <if-value> <chain> —
# why the job is not protected from a fork's pull request, one reason per
# line; nothing when it is. <chain> is the workflow files called so far.
job_problems() {
  local verdict=""
  case "$5" in
    twice) echo "has two job-level if: keys, so which one GitHub reads is not clear"; return 0 ;;
    multi) echo "has a job-level if: over several lines (a block or folded scalar), which this gate does not read"; return 0 ;;
    one) verdict="$(guard_verdict "$6")"; [ "$verdict" = "OK" ] && return 0 ;;
  esac
  if [ "$3" = "USES" ]; then
    reusable_problems "$4" "$7"
    return 0
  fi
  case "$5" in
    none) echo "has no job-level if: guard (a step-level if: or a needs: dependency does not count)" ;;
    *) echo "has the job-level if: ${6} — ${verdict}" ;;
  esac
}

# reusable_problems <uses> <chain> — why a reusable-workflow job without an
# accepted guard of its own is not protected: its callee inspected when local,
# rejected otherwise.
reusable_problems() {
  local u="$1" chain="$2" n target
  u="${u#\"}"; u="${u%\"}"; u="${u#\'}"; u="${u%\'}"
  case "$u" in
    *'$'\{\{*)
      echo "calls a reusable workflow named by an expression (${u}), which this gate cannot inspect: give the calling job an accepted job-level guard"
      ;;
    ./.github/workflows/*)
      n="${u#./.github/workflows/}"
      case "$n" in
        */*|*@*) echo "calls ${u}, which this gate cannot inspect: give the calling job an accepted job-level guard"; return 0 ;;
        *.yml|*.yaml) ;;
        *) echo "calls ${u}, which this gate cannot inspect: give the calling job an accepted job-level guard"; return 0 ;;
      esac
      target="${DIR}/${n}"
      if [ ! -f "$target" ]; then
        echo "calls ${u}, which is not in ${DIR}, so this gate cannot inspect it"
        return 0
      fi
      case " ${chain} " in
        *" ${n} "*) echo "calls ${u} in a cycle (${chain} ${n})"; return 0 ;;
      esac
      if [ "$(awk '{ print NF }' <<<"$chain")" -gt "$MAX_CALL_DEPTH" ]; then
        echo "calls ${u} deeper than ${MAX_CALL_DEPTH} levels (${chain}), which this gate does not follow"
        return 0
      fi
      callee_problems "$target" "${chain} ${n}" "$u"
      ;;
    *) echo "calls ${u}, a reusable workflow outside this repository, which this gate cannot inspect: give the calling job an accepted job-level guard" ;;
  esac
}

# callee_problems <file> <chain> <uses> — the problems of every job of a
# called workflow off GitHub-hosted runners, each line naming the call and
# the job.
callee_problems() {
  local table job ro uses ifstate ifraw p found=0
  table="$(job_table "$1")"
  while IFS=$'\037' read -r job ro uses ifstate ifraw; do
    [ -n "$job" ] || continue
    found=1
    hosted "$ro" && continue
    while IFS= read -r p; do
      [ -n "$p" ] && echo "calls ${3}, where job '${job}' ($(runner_words "$ro")) ${p}"
    done < <(job_problems "$1" "$job" "$ro" "$uses" "$ifstate" "$ifraw" "$2")
  done <<<"$table"
  [ "$found" -eq 1 ] || echo "calls ${3}, in which this gate finds no job under jobs:"
}

files=()
while IFS= read -r f; do
  [ -n "$f" ] && files+=("$f")
done < <(find "$DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "❌ FAIL: no .yml or .yaml workflow in ${DIR} — a scan over nothing is not a clean scan"
  exit 1
fi

selfhosted_files=""
for wf in "${files[@]}"; do
  name="$(basename "$wf")"
  events="$(trigger_events "$wf")"
  if [ "$events" = "NO_ON_KEY" ]; then
    echo "❌ FAIL: ${name}: no on: key at column 0 — this gate cannot read its triggers, and a trigger it cannot read is not one it has cleared"
    findings=$((findings + 1))
    continue
  fi

  table="$(job_table "$wf")"
  not_hosted=""
  while IFS=$'\037' read -r job ro uses ifstate ifraw; do
    [ -n "$job" ] || continue
    hosted "$ro" || not_hosted="${not_hosted}${job}"$'\037'"${ro}"$'\037'"${uses}"$'\037'"${ifstate}"$'\037'"${ifraw}"$'\n'
  done <<<"$table"
  if [ -z "$table" ]; then
    not_hosted="(none)"$'\037'"NONE"$'\037\037'"none"$'\037'$'\n'
  fi
  [ -n "$not_hosted" ] && selfhosted_files="${selfhosted_files} ${name}"

  [ -n "$events" ] || continue
  [ -n "$not_hosted" ] || continue
  while IFS=$'\037' read -r job ro uses ifstate ifraw; do
    [ -n "$job" ] || continue
    runner="$(runner_words "$ro")"
    [ "$job" = "(none)" ] && runner="no job found under jobs:"
    while IFS= read -r event; do
      [ -n "$event" ] || continue
      problems=""
      if [ "$event" = "$GUARDED_EVENT" ]; then
        problems="$(job_problems "$wf" "$job" "$ro" "$uses" "$ifstate" "$ifraw" "$name")"
        if [ -z "$problems" ]; then
          echo "guarded: ${name}: ${event} with job '${job}' (${runner}) — its job-level guard keeps a fork's pull request off the runner"
          guarded=$((guarded + 1))
          continue
        fi
      fi
      if excepted "$name" "$event"; then
        EXC_USED="${EXC_USED}${name}|${event}"$'\n'
        echo "excepted: ${name}: ${event} with job '${job}' (${runner}) — $(exception_reason "$name" "$event")"
        continue
      fi
      if [ -n "$problems" ]; then
        while IFS= read -r p; do
          [ -n "$p" ] || continue
          echo "❌ FAIL: ${name}: triggers on ${event} and job '${job}' (${runner}) ${p} — a pull request from a fork could run its own code on a self-hosted runner. Give the job an accepted job-level guard (the header of this gate lists them), remove the trigger, or record an exception row with its reason in ${EXCEPTIONS}."
          findings=$((findings + 1))
        done <<<"$problems"
        continue
      fi
      echo "❌ FAIL: ${name}: triggers on ${event} and job '${job}' has ${runner}, not a GitHub-hosted image label — a pull request from a fork would run its own code on the self-hosted runner, and a job-level guard counts for pull_request only. Remove the trigger, or record an exception row with its reason in ${EXCEPTIONS}."
      findings=$((findings + 1))
    done <<<"$events"
  done <<<"$not_hosted"
done

# An exception row nothing used excuses nothing: red.
while IFS='|' read -r ex_name ex_event ex_reason; do
  [ -n "$ex_name" ] || continue
  if ! grep -qxF -- "${ex_name}|${ex_event}" <<<"$EXC_USED"; then
    echo "❌ FAIL: ${EXCEPTIONS}: ${ex_name}|${ex_event} excuses no finding — the trigger is gone, its job is on a hosted runner, or its job is guarded; remove the row"
    findings=$((findings + 1))
  fi
done <<<"$EXC_ROWS"

if [ "$findings" -ne 0 ]; then
  echo ""
  echo "workflow triggers: ${findings} finding(s) in ${DIR}."
  exit 1
fi

echo "✅ workflow triggers: ${#files[@]} workflow file(s) in ${DIR}; no unexcused pull-request event reaches an unguarded job off GitHub-hosted runners (self-hosted or unproven runners in:${selfhosted_files:- none}; guarded jobs: ${guarded}; exceptions used: $(printf '%s' "$EXC_USED" | grep -c . || true))"
exit 0
