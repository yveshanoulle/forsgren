package main

import (
	"regexp"
	"runtime/debug"
)

// buildInfo reads how this binary was built; a var so a test can say it was
// built from a checkout or not (forsgren#224).
var buildInfo = debug.ReadBuildInfo

// revision is a commit as git writes it in the go tool's build information:
// lower-case hex, at least the seven digits the page shows.
var revision = regexp.MustCompile(`^[0-9a-f]{7,64}$`)

// shortCommitLength is how many digits of the commit the footer shows.
const shortCommitLength = 7

// devCommit is the short commit a development build is built from, empty for
// a release build (forsgren#224). The go tool records the commit only for a
// build made in a git checkout (go build or go install of a directory), as
// the preview's; a release is installed as a module at a pinned commit
// (go install <module>/cmd/forsgren@<commit>), which records none, so the
// footer of a release stays the version alone.
func devCommit(info *debug.BuildInfo, ok bool) string {
	if !ok || info == nil {
		return ""
	}
	for _, s := range info.Settings {
		if s.Key == "vcs.revision" && revision.MatchString(s.Value) {
			return s.Value[:shortCommitLength]
		}
	}
	return ""
}
