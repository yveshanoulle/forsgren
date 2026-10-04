package main

import (
	"strings"
	"testing"
)

// TestRenderNamesTheLatestReleaseItIsGiven (forsgren#40, step 4, option 2):
// render takes the newest forsgren release as --latest, so it needs no
// network; a newer one is named in the footer of both pages.
func TestRenderNamesTheLatestReleaseItIsGiven(t *testing.T) {
	dir := t.TempDir()
	if code, _, stderr := runCommand("render", "--out", dir, "--latest", "0.0.10"); code != 0 {
		t.Fatalf("want exit 0, got %d, %q", code, stderr)
	}
	for _, name := range []string{"index.html", "legend.html"} {
		if got := readFile(t, dir+"/"+name); !strings.Contains(got, version+" · 0.0.10 is available") {
			t.Errorf("%s: want %q in the footer, got:\n%s", name, version+" · 0.0.10 is available", got)
		}
	}
}

// TestRenderSaysNothingWhenNoNewerReleaseIsKnown (forsgren#40, step 4): no
// --latest, the version itself, an older one, or one that is not a version
// (a lookup that failed): the page renders as before, exit 0, nothing added.
func TestRenderSaysNothingWhenNoNewerReleaseIsKnown(t *testing.T) {
	for _, latest := range []string{version, "0.0.1", "banana", ""} {
		code, stderr, index := renderWith(t, "--latest", latest)
		if code != 0 || strings.Contains(index, "available") {
			t.Errorf("latest %q: want exit 0 and no news of a release, got %d, %q, page:\n%s", latest, code, stderr, index)
		}
	}
	if code, _, index := renderWith(t); code != 0 || strings.Contains(index, "available") {
		t.Errorf("no --latest: want exit 0 and no news of a release, got %d, page:\n%s", code, index)
	}
}

const latestPath = "/repos/yveshanoulle/forsgren/releases/latest"

// TestLatestReleasePrintsTheNewestVersion (forsgren#40, step 4): the
// command reads forsgren's own latest release, which is public, with no
// token, and prints its version without the leading v.
func TestLatestReleasePrintsTheNewestVersion(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", "")
	fakeAPI(t, map[string]string{latestPath: `{"id": 7, "tag_name": "v0.0.10"}`}, 0)
	code, stdout, stderr := runCommand("latest-release")
	if code != 0 || stdout != "0.0.10\n" {
		t.Errorf("want exit 0 and 0.0.10, got %d, %q, stderr %q", code, stdout, stderr)
	}
}

// TestALatestReleaseLookupThatFailsIsNotAnError (forsgren#40, step 4): when
// GitHub cannot answer (an error status, or a tag that is not a version),
// the command prints nothing on stdout, says why on stderr and exits 0, so a
// workflow renders the page without news of a release.
func TestALatestReleaseLookupThatFailsIsNotAnError(t *testing.T) {
	cases := map[string]struct {
		bodies map[string]string
		code   int
	}{
		"server error":      {map[string]string{latestPath: `{"message":"boom"}`}, 500},
		"no release":        {map[string]string{}, 0},
		"tag not a version": {map[string]string{latestPath: `{"id": 7, "tag_name": "nightly"}`}, 0},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			t.Setenv("FORSGREN_TOKEN", "")
			fakeAPI(t, c.bodies, c.code)
			code, stdout, stderr := runCommand("latest-release")
			if code != 0 || stdout != "" || !strings.Contains(stderr, "latest release") {
				t.Errorf("want exit 0, no stdout and a note on stderr, got %d, %q, %q", code, stdout, stderr)
			}
		})
	}
}
