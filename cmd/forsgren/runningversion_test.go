package main

import (
	"runtime/debug"
	"testing"
)

// TestRunningVersionComesFromOneResolver (forsgren#237): an ldflags value
// wins; else a clean vX.Y.Z of the build information, without its v; else
// the var version.
func TestRunningVersionComesFromOneResolver(t *testing.T) {
	ldflags := []debug.BuildSetting{{Key: "-ldflags", Value: "-X main.version=9.9.9"}}
	cases := []struct {
		name     string
		main     string
		settings []debug.BuildSetting
		want     string
	}{
		{"a clean module version is the version without its v", "v8.8.8", nil, "8.8.8"},
		{"a pseudo-version falls back to the var", "v0.0.0-20261020-abcdef123456", nil, testVersion},
		{"(devel) falls back to the var", "(devel)", nil, testVersion},
		{"an empty version falls back to the var", "", nil, testVersion},
		{"a pre-release falls back to the var", "v8.8.8-rc1", nil, testVersion},
		{"a +incompatible or dirty suffix falls back", "v8.8.8+dirty", nil, testVersion},
		{"an ldflags value wins over the build information", "v8.8.8", ldflags, "9.9.9"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			old := buildInfo
			buildInfo = func() (*debug.BuildInfo, bool) {
				return &debug.BuildInfo{Main: debug.Module{Version: c.main}, Settings: c.settings}, true
			}
			t.Cleanup(func() { buildInfo = old })
			setVersion(t, testVersion)
			if c.want == "9.9.9" {
				setVersion(t, "9.9.9")
			}
			if got := runningVersion(); got != c.want {
				t.Errorf("runningVersion() = %q, want %q (Main.Version %q)", got, c.want, c.main)
			}
		})
	}
}

func TestRunningVersionWithoutBuildInformationIsTheVar(t *testing.T) {
	old := buildInfo
	buildInfo = func() (*debug.BuildInfo, bool) { return nil, false }
	t.Cleanup(func() { buildInfo = old })
	setVersion(t, testVersion)
	if got := runningVersion(); got != testVersion {
		t.Errorf("runningVersion() = %q, want %s", got, testVersion)
	}
}

// TestRunningVersionOfAnInstallationByCommit (forsgren#237, step 2): the
// module versions the go tool recorded, measured with go install of
// github.com/yveshanoulle/forsgren/cmd/forsgren on 2026-10-20: at the commit
// a tag points at, and at the tag, it records the tag; at an untagged commit
// of main it records a pseudo-version of the next patch release, such as
// v<tag with its patch plus one>-0.20261020113112-fc3b9cd8afaa. The var is set apart
// from both, so the answer can only come from the build information.
func TestRunningVersionOfAnInstallationByCommit(t *testing.T) {
	cases := []struct{ name, module, want string }{
		{"the commit of a tag is the tag", "v" + testVersion, testVersion},
		{"an untagged commit of main is the var", "v" + newerRelease + "-0.20261020113112-fc3b9cd8afaa", "0.0.0-test"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			old := buildInfo
			buildInfo = func() (*debug.BuildInfo, bool) {
				return &debug.BuildInfo{Main: debug.Module{Version: c.module}}, true
			}
			t.Cleanup(func() { buildInfo = old })
			setVersion(t, "0.0.0-test")
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
// installation's go install of an untagged commit) or no tag behind it, the var.
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
			"no commit recorded is the var, an installation names no tag",
			"v4.5.7-0.20261020211502-a9eb14f9a07c", "", testVersion,
		},
		{"a pseudo-version of no tag is the var", "v0.0.0-20261020211502-a9eb14f9a07c", commit, testVersion},
		{"a patch of 0 cannot follow a tag", "v4.5.0-0.20261020211502-a9eb14f9a07c", commit, testVersion},
		{"a pre-release base is the var", "v4.5.7-rc.1.0.20261020211502-a9eb14f9a07c", commit, testVersion},
		{"(devel) is the var", "(devel)", commit, testVersion},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			old := buildInfo
			buildInfo = func() (*debug.BuildInfo, bool) {
				info := &debug.BuildInfo{Main: debug.Module{Version: c.module}}
				if c.revision != "" {
					info.Settings = []debug.BuildSetting{{Key: "vcs.revision", Value: c.revision}}
				}
				return info, true
			}
			t.Cleanup(func() { buildInfo = old })
			setVersion(t, testVersion)
			if got := runningVersion(); got != c.want {
				t.Errorf("runningVersion() = %q, want %q (Main.Version %q, commit %q)", got, c.want, c.module, c.revision)
			}
		})
	}
}
