package main

import (
	"net/http"
	"net/http/httptest"
	"runtime/debug"
	"strings"
	"testing"
)

// TestFooterOfABuildWithoutAVersionIsDev (forsgren#340): a build that names
// no release (no ldflags value, no tag it can use) says dev, with its short
// commit when the go tool recorded one, and never a release number.
func TestFooterOfABuildWithoutAVersionIsDev(t *testing.T) {
	const commit = "c41db9e0a1b2c3d4e5f60718293a4b5c6d7e8f90"
	withCommit := &debug.BuildInfo{Settings: []debug.BuildSetting{{Key: "vcs.revision", Value: commit}}}
	cases := []struct {
		name string
		info *debug.BuildInfo
		want string
	}{
		{"with its commit", withCommit, "Forsgren</a> dev (c41db9e) Metrics from GitHub data."},
		{"without a commit", &debug.BuildInfo{}, "Forsgren</a> dev Metrics from GitHub data."},
		{"without build information", nil, "Forsgren</a> dev Metrics from GitHub data."},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			withBuildInfo(t, c.info)
			setVersion(t, "")
			code, stderr, index := renderWith(t)
			if code != 0 {
				t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
			}
			if !strings.Contains(index, c.want) {
				t.Errorf("want %q in the footer, got:\n%s", c.want, index)
			}
			if strings.Contains(index, "+dev") {
				t.Errorf("want no +dev: dev names no release it builds on, got:\n%s", index)
			}
		})
	}
}

// TestFooterOfADevelopmentBuildPromisesNoUpdate (forsgren#340): dev is no
// release, so no release is newer than it and the footer names none.
func TestFooterOfADevelopmentBuildPromisesNoUpdate(t *testing.T) {
	withBuildInfo(t, nil)
	setVersion(t, "")
	code, stderr, index := renderWith(t, "--latest", newerRelease)
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	if strings.Contains(index, "is available") {
		t.Errorf("want no update named on a development build, got:\n%s", index)
	}
}

// TestRunSummaryOfADevelopmentBuild (forsgren#340): the summary names the
// build as dev, says its update state is unknown, and says the setup was not
// checked, since a development build does not know what it needs.
func TestRunSummaryOfADevelopmentBuild(t *testing.T) {
	pinNow(t)
	withBuildInfo(t, nil)
	setVersion(t, "")
	_, stdout, _ := runCommand("run-summary", "--latest", newerRelease, "--pr-check", "ok", "--needs-check", statusSkipped)
	for _, want := range []string{
		"- Built with: forsgren dev\n",
		"- Update: unknown (a development build)\n",
		"- Setup: not checked, a development build does not know what it needs\n",
	} {
		if !strings.Contains(stdout, want) {
			t.Errorf("want %q in the summary, got:\n%s", want, stdout)
		}
	}
	if strings.Contains(stdout, "up to date") {
		t.Errorf("want no claim that a development build is up to date, got:\n%s", stdout)
	}
}

// TestCheckNeedsOfADevelopmentBuildLeavesTheSetupIssueAlone (forsgren#340):
// an unknown version is unknown, not an older release: check-needs says so on
// stderr, records skipped, and makes no request, so no setup issue is opened,
// updated or closed on it.
func TestCheckNeedsOfADevelopmentBuildLeavesTheSetupIssueAlone(t *testing.T) {
	withBuildInfo(t, nil)
	setVersion(t, "")
	t.Setenv("GITHUB_TOKEN", testToken)
	requests := 0
	srv := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { requests++ }))
	t.Cleanup(srv.Close)
	setGithubAPI(t, srv.URL)
	installationWithoutIssuesWrite(t)
	code, stdout, stderr := runCommand("check-needs", "--config", "forsgren.config.yml",
		"--repository", "acme/data", "--status", "needs-status.txt")
	if code != 0 {
		t.Errorf("want exit 0, got %d, stderr %q", code, stderr)
	}
	if want := "a development build does not know what it needs"; !strings.Contains(stderr, want) {
		t.Errorf("stderr %q, want it to contain %q", stderr, want)
	}
	wantStatusLine(t, stdout, statusSkipped)
	if requests != 0 {
		t.Errorf("want no request to GitHub for a development build, got %d", requests)
	}
}

// TestInstallReadmeOfADevelopmentBuildNamesNoRelease (forsgren#340): the
// README of a development build says so where a release's names its version.
func TestInstallReadmeOfADevelopmentBuildNamesNoRelease(t *testing.T) {
	withBuildInfo(t, nil)
	setVersion(t, "")
	out := t.TempDir() + "/README.md"
	if code, _, stderr := runCommand("install-readme", "--out", out); code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	if want := "for forsgren dev (a development build):"; !strings.Contains(readFile(t, out), want) {
		t.Errorf("want %q in the README, got:\n%s", want, readFile(t, out))
	}
}
