package main

import (
	"runtime/debug"
	"strings"
	"testing"
)

// builtFrom makes the binary look as built by the go tool from a checkout at
// revision (a build from a module version, as an installation's go install
// does, has no revision and is built from "").
func builtFrom(t *testing.T, revision string) {
	t.Helper()
	old := buildInfo
	buildInfo = func() (*debug.BuildInfo, bool) {
		info := &debug.BuildInfo{}
		if revision != "" {
			info.Settings = []debug.BuildSetting{{Key: "vcs", Value: "git"}, {Key: "vcs.revision", Value: revision}}
		}
		return info, true
	}
	t.Cleanup(func() { buildInfo = old })
}

// TestFooterOfADevelopmentBuildNamesItsCommit (forsgren#224): a build made
// from a checkout, as the preview's, shows the version with +dev and the short commit,
// as text: the repository-links gate allows no link into a repository.
func TestFooterOfADevelopmentBuildNamesItsCommit(t *testing.T) {
	builtFrom(t, "c41db9e0a1b2c3d4e5f60718293a4b5c6d7e8f90")
	code, stderr, index := renderWith(t)
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	if want := "Forsgren</a> " + testVersion + "+dev (c41db9e) Metrics from GitHub data."; !strings.Contains(index, want) {
		t.Errorf("want %q in the footer, got:\n%s", want, index)
	}
	if strings.Contains(index, "github.com/") {
		t.Errorf("want no github.com path on the page, got:\n%s", index)
	}
}

// TestFooterOfAReleaseBuildIsUnchanged (forsgren#224): a build with no
// revision, as an installation's go install of a pinned commit, shows the
// version alone.
func TestFooterOfAReleaseBuildIsUnchanged(t *testing.T) {
	builtFrom(t, "")
	code, stderr, index := renderWith(t)
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	if want := "Forsgren</a> " + testVersion + " Metrics from GitHub data."; !strings.Contains(index, want) {
		t.Errorf("want %q in the footer, got:\n%s", want, index)
	}
	if strings.Contains(index, "+dev") {
		t.Errorf("want no +dev on a release page, got:\n%s", index)
	}
}

func TestDevCommitIsTheShortRevisionOrNothing(t *testing.T) {
	setting := func(key, value string) *debug.BuildInfo {
		return &debug.BuildInfo{Settings: []debug.BuildSetting{{Key: key, Value: value}}}
	}
	for _, c := range []struct {
		name string
		info *debug.BuildInfo
		ok   bool
		want string
	}{
		{"full revision", setting("vcs.revision", "c41db9e0a1b2c3d4"), true, "c41db9e"},
		{"seven digits", setting("vcs.revision", "c41db9e"), true, "c41db9e"},
		{"no build info", nil, false, ""},
		{"build info not ok", setting("vcs.revision", "c41db9e0a1b2"), false, ""},
		{"no revision", &debug.BuildInfo{}, true, ""},
		{"empty revision", setting("vcs.revision", ""), true, ""},
		{"too short", setting("vcs.revision", "c41db9"), true, ""},
		{"not hex", setting("vcs.revision", "not-a-commit-at-all"), true, ""},
		{"other setting", setting("vcs.time", "c41db9e0a1b2"), true, ""},
	} {
		if got := devCommit(c.info, c.ok); got != c.want {
			t.Errorf("%s: want %q, got %q", c.name, c.want, got)
		}
	}
}
