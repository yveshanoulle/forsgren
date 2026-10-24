package main

import (
	"runtime/debug"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/buildversion"
)

// withBuildInfo makes the binary look as built with info (nil: a binary with
// no build information), restored afterwards.
func withBuildInfo(t *testing.T, info *debug.BuildInfo) {
	t.Helper()
	old := buildInfo
	buildInfo = func() (*debug.BuildInfo, bool) { return info, info != nil }
	t.Cleanup(func() { buildInfo = old })
}

// TestRunningVersionComesFromOneResolver (forsgren#237, #340): an ldflags
// value wins; else a clean vX.Y.Z of the build information, without its v;
// else the development build, never a release number written in the code.
func TestRunningVersionComesFromOneResolver(t *testing.T) {
	ldflags := []debug.BuildSetting{{Key: "-ldflags", Value: "-X main.version=9.9.9"}}
	cases := []struct {
		name     string
		main     string
		settings []debug.BuildSetting
		want     string
	}{
		{"a clean module version is the version without its v", "v8.8.8", nil, "8.8.8"},
		{"a pseudo-version without a commit is a development build", "v0.0.0-20261020-abcdef123456", nil, buildversion.Dev},
		{"(devel) is a development build", "(devel)", nil, buildversion.Dev},
		{"an empty version is a development build", "", nil, buildversion.Dev},
		{"a pre-release is a development build", "v8.8.8-rc1", nil, buildversion.Dev},
		{"a +incompatible or dirty suffix is a development build", "v8.8.8+dirty", nil, buildversion.Dev},
		{"an ldflags value wins over the build information", "v8.8.8", ldflags, "9.9.9"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			withBuildInfo(t, &debug.BuildInfo{Main: debug.Module{Version: c.main}, Settings: c.settings})
			setVersion(t, "")
			if c.want == "9.9.9" {
				setVersion(t, "9.9.9")
			}
			if got := runningVersion(); got != c.want {
				t.Errorf("runningVersion() = %q, want %q (Main.Version %q)", got, c.want, c.main)
			}
		})
	}
}

// TestRunningVersionWithoutBuildInformationIsDev (forsgren#340): a binary
// with no build information, and one with nothing usable in it, say dev and
// no release, whatever the last release was.
func TestRunningVersionWithoutBuildInformationIsDev(t *testing.T) {
	withBuildInfo(t, nil)
	setVersion(t, "")
	if got := runningVersion(); got != buildversion.Dev {
		t.Errorf("runningVersion() = %q, want %q", got, buildversion.Dev)
	}
}

// TestRunningVersionOfAnInstallationByCommit (forsgren#237, step 2): the
// module versions the go tool recorded, measured with go install of
// github.com/yveshanoulle/forsgren/cmd/forsgren on 2026-10-20: at the commit
// a tag points at, and at the tag, it records the tag; at an untagged commit
// of main it records a pseudo-version of the next patch release, such as
// v<tag with its patch plus one>-0.20261020113112-fc3b9cd8afaa, which names no
// tag it can show without a commit (forsgren#340: a development build).
func TestRunningVersionOfAnInstallationByCommit(t *testing.T) {
	cases := []struct{ name, module, want string }{
		{"the commit of a tag is the tag", "v" + testVersion, testVersion},
		{"an untagged commit of main is a development build",
			"v" + newerRelease + "-0.20261020113112-fc3b9cd8afaa", buildversion.Dev},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			withBuildInfo(t, &debug.BuildInfo{Main: debug.Module{Version: c.module}})
			setVersion(t, "")
			if got := runningVersion(); got != c.want {
				t.Errorf("runningVersion() = %q, want %q (Main.Version %q)", got, c.want, c.module)
			}
		})
	}
}

// TestRunningVersionOfACheckoutBuildIsTheLastTag (forsgren#237, step 7): a
// build made from a checkout records the commit and, since the go tool
// derives the module version from the tags, a pseudo-version of the NEXT
// patch release after the last tag: measured with go build on 2026-10-20,
// vA.B.(C+1)-0.20261020211502-a9eb14f9a07c with the tag vA.B.C behind it (and
// +dirty after a modified tree). The version of that build is the last tag
// (the +dev and the commit are the footer's); with no commit recorded (an
// installation's go install of an untagged commit) or no tag behind it, the
// build is a development build (forsgren#340).
func TestRunningVersionOfACheckoutBuildIsTheLastTag(t *testing.T) {
	const commit = "c41db9e0a1b2c3d4e5f60718293a4b5c6d7e8f90"
	cases := []struct {
		name, module string
		revision     string
		want         string
	}{
		{"a pseudo-version after a tag is the tag", "v4.5.7-0.20261020211502-a9eb14f9a07c", commit, "4.5.6"},
		{"a modified tree is the same tag", "v4.5.7-0.20261020211502-a9eb14f9a07c+dirty", commit, "4.5.6"},
		{"the first patch after a minor release", "v4.6.1-0.20261020211502-a9eb14f9a07c", commit, "4.6.0"},
		{
			"no commit recorded is a development build, an installation names no tag",
			"v4.5.7-0.20261020211502-a9eb14f9a07c", "", buildversion.Dev,
		},
		{"a pseudo-version of no tag is a development build", "v0.0.0-20261020211502-a9eb14f9a07c", commit, buildversion.Dev},
		{"a patch of 0 cannot follow a tag", "v4.5.0-0.20261020211502-a9eb14f9a07c", commit, buildversion.Dev},
		{"a pre-release base is a development build", "v4.5.7-rc.1.0.20261020211502-a9eb14f9a07c", commit, buildversion.Dev},
		{"(devel) is a development build", "(devel)", commit, buildversion.Dev},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			info := &debug.BuildInfo{Main: debug.Module{Version: c.module}}
			if c.revision != "" {
				info.Settings = []debug.BuildSetting{{Key: "vcs.revision", Value: c.revision}}
			}
			withBuildInfo(t, info)
			setVersion(t, "")
			if got := runningVersion(); got != c.want {
				t.Errorf("runningVersion() = %q, want %q (Main.Version %q, commit %q)", got, c.want, c.module, c.revision)
			}
		})
	}
}

// TestNoReleaseNumberIsWrittenInTheCode (forsgren#340): var version holds no
// default, so a build whose version information is missing can only say dev.
func TestNoReleaseNumberIsWrittenInTheCode(t *testing.T) {
	if releasedVersion != "" {
		t.Errorf("var version = %q as built, want it empty: a development build must not claim a release", releasedVersion)
	}
}
