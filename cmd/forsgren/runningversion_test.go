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
