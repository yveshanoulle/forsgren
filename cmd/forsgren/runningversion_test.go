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
		{"a clean module version is the version without its v", "v1.12.0", nil, "1.12.0"},
		{"a pseudo-version falls back to the var", "v0.0.0-20261020-abcdef123456", nil, "1.11.1"},
		{"(devel) falls back to the var", "(devel)", nil, "1.11.1"},
		{"an empty version falls back to the var", "", nil, "1.11.1"},
		{"a pre-release falls back to the var", "v1.12.0-rc1", nil, "1.11.1"},
		{"a +incompatible or dirty suffix falls back", "v1.12.0+dirty", nil, "1.11.1"},
		{"an ldflags value wins over the build information", "v1.12.0", ldflags, "9.9.9"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			old := buildInfo
			buildInfo = func() (*debug.BuildInfo, bool) {
				return &debug.BuildInfo{Main: debug.Module{Version: c.main}, Settings: c.settings}, true
			}
			t.Cleanup(func() { buildInfo = old })
			setVersion(t, "1.11.1")
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
	setVersion(t, "1.11.1")
	if got := runningVersion(); got != "1.11.1" {
		t.Errorf("runningVersion() = %q, want 1.11.1", got)
	}
}

// TestRunningVersionOfAnInstallationByCommit (forsgren#237, step 2): the
// module versions the go tool recorded, measured with go install of
// github.com/yveshanoulle/forsgren/cmd/forsgren on 2026-10-20: at the commit
// the tag v1.11.1 points at, and at the tag, it records v1.11.1; at an
// untagged commit of main it records a pseudo-version. The var is set apart
// from both, so the answer can only come from the build information.
func TestRunningVersionOfAnInstallationByCommit(t *testing.T) {
	cases := []struct{ name, module, want string }{
		{"the commit of a tag is the tag", "v1.11.1", "1.11.1"},
		{"an untagged commit of main is the var", "v1.11.2-0.20261020113112-fc3b9cd8afaa", "0.0.0-test"},
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
