package main

import (
	"regexp"
	"runtime/debug"
	"strconv"
	"strings"
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

// cleanRelease is a module version of a release: vX.Y.Z, no pre-release, no
// pseudo-version, no build suffix.
var cleanRelease = regexp.MustCompile(`^v(\d+\.\d+\.\d+)$`)

// ldflagsVersion is how the go tool records an ldflags value for the version.
const ldflagsVersion = "main.version="

// checkoutPseudo is the module version the go tool records for a build made in
// a checkout after a release tag: the next patch release with a pre-release
// part of the commit, vX.Y.(Z+1)-0.<time>-<commit>, and +dirty for a modified
// tree. Only the three numbers matter.
var checkoutPseudo = regexp.MustCompile(`^v(\d+)\.(\d+)\.([1-9]\d*)-0\.\d{14}-[0-9a-f]{12}(\+dirty)?$`)

// lastTagOfCheckout is the release tag behind a build made from a checkout
// (forsgren#237, step 7): the pseudo-version's patch minus one. Empty when the
// build records no commit (an installation's go install of an untagged commit
// names no tag it can show) or its module version is no such pseudo-version.
func lastTagOfCheckout(info *debug.BuildInfo) string {
	if devCommit(info, true) == "" {
		return ""
	}
	m := checkoutPseudo.FindStringSubmatch(info.Main.Version)
	if m == nil {
		return ""
	}
	patch, _ := strconv.Atoi(m[3])
	return m[1] + "." + m[2] + "." + strconv.Itoa(patch-1)
}

// runningVersion is the version this binary reports, from one place
// (forsgren#237): an ldflags value of var version as is; else the build
// information's module version when it is a clean vX.Y.Z, without its v; else
// the last release tag of a build made from a checkout (the footer adds +dev
// and the commit); else var version.
func runningVersion() string {
	info := usableBuildInfo()
	if info == nil {
		return version
	}
	if m := cleanRelease.FindStringSubmatch(info.Main.Version); m != nil {
		return m[1]
	}
	if tag := lastTagOfCheckout(info); tag != "" {
		return tag
	}
	return version
}

// usableBuildInfo is the build information the version may be read from: none
// when the binary has none, or when an ldflags value set the version.
func usableBuildInfo() *debug.BuildInfo {
	info, ok := buildInfo()
	if !ok || info == nil {
		return nil
	}
	if setByLdflags(info) {
		return nil
	}
	return info
}

// setByLdflags is whether the build was given -X main.version.
func setByLdflags(info *debug.BuildInfo) bool {
	for _, s := range info.Settings {
		if s.Key == "-ldflags" && strings.Contains(s.Value, ldflagsVersion) {
			return true
		}
	}
	return false
}
