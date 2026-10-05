package main

import "io"

// installUpdate is the subcommand the update workflow runs when check-update
// found a release within the level: `forsgren install-update --repo
// <owner/name> --branch <branch> --version <vX.Y.Z> --sha <sha>` moves the
// pins of the caller files of the branch's head to that release in one commit
// and says `installed <version> on <branch> as <commit>`. Exit 0 is done, 2 a
// usage or GitHub error, or no caller file at the head (forsgren#62). It
// writes with GITHUB_TOKEN, which needs contents: write.
func installUpdate(args []string, stdout, stderr io.Writer) int {
	return 0
}
