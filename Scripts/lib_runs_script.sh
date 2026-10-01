#!/usr/bin/env bash
# Scripts/lib_runs_script.sh
#
# Ported from konenki-website 2026-10-01 (forsgren#1, ladder step 14). The
# function is byte-identical; only this header's comments are adapted, for
# forsgren's script-reference guard (Scripts/check_script_references.sh),
# which reads every Scripts path a comment names: konenki's own files are
# named with the repository first, and the illustrations use Scripts/<x>.sh,
# which the guard does not read as a path. Issue numbers are konenki's.
# forsgren has one consumer, Scripts/test_gate_wiring.sh, and no
# report_ci_step.sh: the `--` rule below is kept, unused here.
#
# Issue #18: runs_script, the one definition of "this file RUNS
# Scripts/<script>", extracted from konenki's test_gate_wiring.sh so that
# its two consumers, the gate-wiring check and Part A of
# konenki-website/Scripts/test_report_npm_audit_step.sh, judge an invocation
# by the same filter (item 8: that Part A used to drop comment lines only, so
# it accepted an echo that the gate-wiring check rejected). Not every check
# that asks "is X invoked" uses it yet: Part A of
# konenki-website/Scripts/test_report_ci_step.sh and the pins in
# konenki-website/Scripts/test_deploy_feta_workflow.sh still grep on their
# own.
#
# SOURCED, never run. It judges nothing on its own. Scripts/test_gate_wiring.sh
# exempts this file as a sourced helper, requires its consumer to
# source it, and, in the same run as its verdicts on the real runners (after
# them, and not in its mutation re-runs), feeds the matcher sample files it
# must reject or accept.
#
# It sets no shell options and no traps; the sourcing script owns those.

# runs_script <file> <script>: succeeds when <file> RUNS Scripts/<script>
# (issues #13 (2), #15 and #18). A mention is not an invocation, so this is
# a small tokenizer rather than a line filter: it reads the file the way the
# shell would split it into commands and counts only a word that stands
# where a command stands.
#
# Which file it is comes from the extension. A .yml or .yaml file is a
# workflow: only the value of a run: key is shell, whether one-line
# (`- run: ./Scripts/<x>.sh`) or a `run: |` block scalar. Every other key
# (name:, if:, uses:, and the block scalars under env: or with:), comment
# lines and list items are text. Any other file is a shell script.
#
# Inside the shell, the tokenizer tracks single and double quotes across
# lines, backslash escapes and line continuations, comments (a # that starts
# a word), heredoc bodies (skipped up to their delimiter line) and $( )
# command substitutions (a new command inside the word, so
# `out="$(./Scripts/<x>.sh)"` is a call). A command starts at the start of a
# line and after ; & && | || ( ) { ! and the keywords if then do else elif
# while until time. Its first word is the command, after any NAME=value
# prefixes; bash, sh, source, ., exec, command, env and nohup hand the
# command position on to their next word that is not an option. One
# repo-specific rule: konenki-website/Scripts/report_ci_step.sh runs the command that
# follows its `--` (quality.yml's gate steps), so the word after that `--`
# is a command too. Array elements (`a=(x y)`) and redirection targets are
# never commands.
#
# So what it rejects is anything that is not a command word: the path as an
# argument (chmod +x, cp, test -x, [ -x ], :, echo, printf, another script),
# comments after code, heredoc bodies, the continuation lines of a
# multi-line string or of a backslash-continued echo. A pipe starts a new
# command, so `printf x | ./Scripts/<x>.sh` counts.
#
# The command word matches when, quotes removed, it is exactly
# Scripts/<script> or ends in /Scripts/<script>: `./Scripts/<x>.sh` and
# `${ROOT}/Scripts/<x>.sh` count, `./Scripts/<x>.sh.bak` and
# `./LegacyScripts/<x>.sh` do not, and the basename alone does not (see the
# header of Scripts/test_gate_wiring.sh).
#
# It is not a full shell parser. Not modelled, with the verdict each gives:
#   - case patterns: a pattern that starts a line or follows | stands where
#     a command stands, so a pattern naming the script counts; inside $( )
#     the ) of a pattern closes the substitution;
#   - $'...' strings holding an escaped quote: the escaped quote ends the
#     string;
#   - a backtick is only a command boundary, not a nested substitution;
#   - a wrapper option that takes an argument (bash -o pipefail, env -u
#     NAME, time -p) hands the command position to that argument, so the
#     script after it does not count; command -v and bash -n followed by
#     the script count, although they run nothing;
#   - commands that run their arguments (xargs, timeout, sudo, eval, find
#     -exec) and a script fed to a shell on stdin (bash -s < Scripts/<x>.sh)
#     do not count; neither does a $( ) inside an unquoted heredoc body,
#     which the shell does run;
#   - in a workflow, a folded `run: >` block is read line by line, though
#     YAML joins its lines into one command; a run: key nested under with:
#     is read as shell; a quoted one-line run: value is unquoted the shell
#     way, so `run: './Scripts/<x>.sh arg'` is one word and does not count.
# No line runs_script is asked about today hits one of these (issue #18
# review). The samples in Scripts/test_gate_wiring.sh pin what it must
# reject and accept.
runs_script() {
  local yaml=0
  case "$1" in
    *.yml | *.yaml) yaml=1 ;;
  esac
  # q carries the single-quote character, because the program below is one
  # single-quoted shell string and cannot contain one.
  awk -v script="$2" -v yaml="$yaml" -v q="'" '
    BEGIN {
      target = "Scripts/" script
      tlen = length(target)
      # Runs of characters with no meaning to the tokenizer, consumed at once.
      plain_re = "^[^ \t\"\\\\$`;&|()<>#" q "]+"
      dq_re = "^[^\"\\\\$`]+"
      sq_re = "^[^" q "]+"
      assign_re = "^[A-Za-z_][A-Za-z0-9_]*(\\[[^]]*\\])?[+]?="
      n = split("if then do else elif while until ! { } time", tmp, " ")
      for (k = 1; k <= n; k++) keyword[tmp[k]] = 1
      n = split("bash sh source . exec command env nohup", tmp, " ")
      for (k = 1; k <= n; k++) wrapper[tmp[k]] = 1
      found = 0
      in_block = 0
      shell_begin()
    }

    { if (yaml == 1) yaml_line($0); else shell_line($0); if (found) exit }

    END { exit found ? 0 : 1 }

    # --- the verdict ------------------------------------------------------
    function is_target(w, n) {
      n = length(w)
      if (n < tlen || substr(w, n - tlen + 1) != target) return 0
      return n == tlen || substr(w, n - tlen, 1) == "/"
    }
    function basename(w) {
      sub(/.*\//, "", w)
      return w
    }

    # --- shell tokenizer state ------------------------------------------
    # Context d is the command being read; each $( pushes a new one.
    function new_context(k) {
      in_sq[k] = 0; in_dq[k] = 0; word[k] = ""; in_word[k] = 0
      cmd_pos[k] = 1; head[k] = ""; wrapped[k] = 0; redirect[k] = 0
      heredoc_word[k] = 0; heredoc_dash[k] = 0; parens[k] = 0; in_array[k] = 0
    }
    function shell_begin() {
      d = 0; new_context(0)
      heredoc_n = 0; heredoc_cur = 1; in_heredoc = 0; continued = 0
    }
    # A command boundary: the next word is a command again.
    function separate() {
      end_word()
      cmd_pos[d] = 1; head[d] = ""; wrapped[d] = 0; redirect[d] = 0
    }
    # Judge the word just finished by where it stands.
    function end_word(w) {
      if (!in_word[d]) return
      w = word[d]; word[d] = ""; in_word[d] = 0
      if (heredoc_word[d]) {
        heredoc_word[d] = 0
        heredoc_delim[++heredoc_n] = w
        heredoc_strip[heredoc_n] = heredoc_dash[d]
        return
      }
      if (redirect[d]) { redirect[d] = 0; return }
      if (in_array[d]) return
      if (!cmd_pos[d]) {
        if (w == "--" && head[d] == "report_ci_step.sh") cmd_pos[d] = 1
        return
      }
      if (wrapped[d] && w ~ /^-/) return
      if (w ~ assign_re) return
      if (!wrapped[d] && (w in keyword)) return
      if (is_target(w)) found = 1
      head[d] = basename(w); cmd_pos[d] = 0; wrapped[d] = 0
      if (w in wrapper) { wrapped[d] = 1; cmd_pos[d] = 1 }
    }
    function push() {
      in_word[d] = 1
      new_context(++d)
    }

    # --- shell tokenizer: one line ----------------------------------------
    # src is the line being read and pos its next character; each read_
    # function below consumes from pos, and the line ends past src_len.
    function shell_line(line) {
      if (in_heredoc) { heredoc_body_line(line); return }
      continued = 0
      src = line; src_len = length(line); pos = 1
      while (pos <= src_len) {
        if (in_sq[d]) read_single_quoted()
        else if (in_dq[d]) read_double_quoted()
        else read_unquoted()
      }
      end_line()
    }

    # A heredoc body line is data. The delimiter line of each heredoc the
    # command opened ends that heredoc, in order; after the last, shell again.
    function heredoc_body_line(line, l) {
      l = line
      if (heredoc_strip[heredoc_cur]) sub(/^\t+/, "", l)
      if (l == heredoc_delim[heredoc_cur] && ++heredoc_cur > heredoc_n) {
        in_heredoc = 0; heredoc_n = 0; heredoc_cur = 1
      }
    }

    # Appends the run matching re at pos to the word; 0 when there is none.
    function take(re) {
      if (!match(substr(src, pos), re)) return 0
      word[d] = word[d] substr(src, pos, RLENGTH); pos += RLENGTH
      return 1
    }

    # Inside single quotes everything up to the closing quote is text.
    function read_single_quoted() {
      if (take(sq_re)) return
      in_sq[d] = 0; pos++
    }

    # Inside double quotes a backslash escapes and $( ) still substitutes.
    function read_double_quoted(c, c2) {
      if (take(dq_re)) return
      c = substr(src, pos, 1); c2 = substr(src, pos + 1, 1)
      if (c == "\"") { in_dq[d] = 0; pos++; return }
      if (c == "\\") { word[d] = word[d] c2; pos += 2; return }
      if (c == "$" && c2 == "(") { push(); pos += 2; return }
      word[d] = word[d] c; pos++
    }

    # Outside quotes: word characters, blanks, quotes, escapes, comments,
    # substitutions, redirections, command boundaries and parentheses.
    function read_unquoted(c, c2) {
      if (take(plain_re)) { in_word[d] = 1; return }
      c = substr(src, pos, 1); c2 = substr(src, pos + 1, 1)
      if (c == " " || c == "\t") { end_word(); pos++; return }
      if (c == q) { in_sq[d] = 1; in_word[d] = 1; pos++; return }
      if (c == "\"") { in_dq[d] = 1; in_word[d] = 1; pos++; return }
      if (c == "\\") {
        if (pos == src_len) { continued = 1; pos++; return }
        word[d] = word[d] c2; in_word[d] = 1; pos += 2; return
      }
      if (c == "#") {
        if (!in_word[d]) { pos = src_len + 1; return }
        word[d] = word[d] c; pos++; return
      }
      if (c == "$" && c2 == "(") { push(); pos += 2; return }
      if (c == ">" || c == "<") { read_redirect(c, c2); return }
      if (c == "&" && c2 == ">") { end_word(); redirect[d] = 1; pos += 2; return }
      if (c == ";" || c == "&" || c == "|" || c == "`") { separate(); pos++; return }
      if (c == "(") { open_paren(); return }
      if (c == ")") { close_paren(); return }
      word[d] = word[d] c; in_word[d] = 1; pos++
    }

    # A redirection operator. Its target word is never a command; << and
    # <<- instead take the next word as a heredoc delimiter.
    function read_redirect(c, c2) {
      # A file-descriptor number before the operator is not a word.
      if (in_word[d] && word[d] ~ /^[0-9]+$/) { word[d] = ""; in_word[d] = 0 } else end_word()
      if (c == "<" && c2 == "<") {
        if (substr(src, pos + 2, 1) == "<") { redirect[d] = 1; pos += 3; return }
        pos += 2
        heredoc_dash[d] = 0
        if (substr(src, pos, 1) == "-") { heredoc_dash[d] = 1; pos++ }
        heredoc_word[d] = 1
        return
      }
      pos++
      while (pos <= src_len && index(">&|", substr(src, pos, 1))) pos++
      redirect[d] = 1
    }

    # ( after NAME= opens an array assignment; anywhere else a subshell.
    function open_paren() {
      pos++
      if (in_word[d] && word[d] ~ /=$/) { in_array[d] = 1; word[d] = ""; in_word[d] = 0; return }
      end_word(); parens[d]++; separate()
    }

    # ) closes an array, a subshell, or the $( ) that pushed this context.
    function close_paren() {
      pos++
      if (in_array[d]) { end_word(); in_array[d] = 0; return }
      end_word()
      if (parens[d] > 0) { parens[d]--; separate() }
      else if (d > 0) d--
      else separate()
    }

    # A line ends the command unless a backslash continues it or a quote is
    # still open (then the newline belongs to the word). A heredoc opened on
    # it starts on the next line.
    function end_line() {
      if (continued) return
      if (in_sq[d] || in_dq[d]) { word[d] = word[d] "\n"; return }
      separate()
      if (heredoc_n > 0) in_heredoc = 1
    }

    # --- workflow layer ---------------------------------------------------
    function indent_of(line) {
      match(line, /^ */)
      return RLENGTH
    }

    # One workflow line: a content line of the open block scalar, else a
    # key line, else text.
    function yaml_line(line, ind) {
      if (in_block) {
        if (line ~ /^[ \t]*$/) { if (block_is_run) shell_line(""); return }
        ind = indent_of(line)
        if (ind > key_indent) { block_line(line, ind); return }
        in_block = 0
      }
      if (line ~ /^ *(- +)?[A-Za-z_][A-Za-z0-9_.-]*:([ \t]|$)/) key_line(line)
    }

    # A content line of a block scalar, the indentation of its first
    # content line removed. Only a run: block is shell.
    function block_line(line, ind) {
      if (content_indent < 0) content_indent = ind
      if (block_is_run) shell_line(substr(line, (ind < content_indent ? ind : content_indent) + 1))
    }

    # A key line: `key: value` or `- key: value`, key indent = its column.
    # A | or > value opens a block scalar; a one-line run: value is shell.
    function key_line(line, rest, key, value) {
      match(line, /^ *(- +)?/)
      key_indent = RLENGTH
      rest = substr(line, RLENGTH + 1)
      key = substr(rest, 1, index(rest, ":") - 1)
      value = substr(rest, index(rest, ":") + 1)
      sub(/^[ \t]+/, "", value)
      if (value ~ /^[|>][-+0-9]*[ \t]*(#.*)?$/) {
        in_block = 1; block_is_run = (key == "run"); content_indent = -1
        if (block_is_run) shell_begin()
      } else if (key == "run" && value != "") {
        shell_begin(); shell_line(value)
      }
    }
  ' "$1"
}
