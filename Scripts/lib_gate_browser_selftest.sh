#!/usr/bin/env bash
# canon: lib_gate_browser_selftest v1
# Scripts/lib_gate_browser_selftest.sh
#
# What the two browser gate self-tests share (forsgren#386, decision #411 A):
# the browser gate self-test (the checks of the gate) and the browser gate
# process self-test (the exits: signals and a killed Chrome). Once, so the two
# cannot drift: the seconds on every case line, the check that the gate and its
# dependencies exist, the clean fixture page and the fixture site around it.
#
# SOURCED, never run, after Scripts/lib_selftest.sh and before selftest_begin.
# It sets no shell options. It defines `echo` (see below), so a script that
# sources it reports through that.
#
# Needs from the sourcing self-test: TMP (selftest_begin) for make_site.

# Seconds per case: every ok and FAIL line of this run ends with the seconds
# since the line before it, which is the duration of the case it reports, so the
# CI log shows what is slow (forsgren#386). echo is shadowed here, so the
# helpers of lib_selftest.sh (want_*, fail) report through it too.
LAP=$SECONDS
echo() {
  case "${1-}" in
    "  ok: "* | "❌ FAIL: "*)
      builtin echo "$* ($((SECONDS - LAP)) s)"
      LAP=$SECONDS
      ;;
    *) builtin echo "$@" ;;
  esac
}

# browser_selftest_require <path>...: every path exists, else the self-test
# stops with one red naming the first that is missing (the gate under test, the
# engine, puppeteer-core and axe-core from npm ci).
browser_selftest_require() {
  local need
  for need in "$@"; do
    if [[ ! -e "$need" ]]; then
      selftest_abort "${SELFTEST_WHAT}: ${need} is missing"
    fi
  done
}

# page <body-extra> <head-extra> [doctype] [charset]: a clean page, one part changed.
page() {
  local body="$1" head="$2" doctype="${3-<!doctype html>}" charset="${4-<meta charset=\"utf-8\">}"
  cat <<HTML
${doctype}
<html lang="en">
<head>
${charset}
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>fixture</title>
<link rel="icon" href="data:,">
<link rel="stylesheet" href="/styles.css">
${head}
</head>
<body>
<main>
<h1>Fixture</h1>
<p>Plain text.</p>
${body}
</main>
</body>
</html>
HTML
}

# make_site <name> <index.html content>: a site with that page, a stylesheet,
# a manifest of "/" and an empty exceptions file, under $TMP/<name>.
make_site() {
  local dir="${TMP}/$1"
  mkdir -p "$dir/site"
  printf '%s\n' "$2" > "$dir/site/index.html"
  printf 'body { color: #111; background: #fff; }\n' > "$dir/site/styles.css"
  printf '{"requiredPages": ["/"]}\n' > "$dir/manifest.json"
  : > "$dir/exceptions.txt"
  : > "$dir/baseline.txt"
  printf 'light|scheme:light\n' > "$dir/variants.txt"
}
