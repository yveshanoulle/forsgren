package main

import "io"

// checkUpdate is the subcommand the update workflow runs on Dependabot's pull
// request in an installation's data repository (forsgren#58, step 16): exit 0
// when the guard says merge, 1 when the pull request is left for a human, 2
// on a usage, config or network error. Scaffold: it merges nothing yet.
func checkUpdate(_ []string, _, _ io.Writer) int {
	return 1
}
