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

// TestLatestReleaseTakesNoArgumentsAndSurvivesABadAPI (forsgren#40, step 4):
// an argument is a usage error; an API address that is no URL is a lookup
// that failed, not an error.
func TestLatestReleaseTakesNoArgumentsAndSurvivesABadAPI(t *testing.T) {
	code, _, stderr := runCommand("latest-release", "now")
	if code != 2 || !strings.Contains(stderr, "usage: forsgren latest-release") {
		t.Errorf("want exit 2 and the usage, got %d, %q", code, stderr)
	}
	old := githubAPI
	githubAPI = "not a url"
	t.Cleanup(func() { githubAPI = old })
	code, stdout, stderr := runCommand("latest-release")
	if code != 0 || stdout != "" || !strings.Contains(stderr, "latest release") {
		t.Errorf("want exit 0, no stdout and a note, got %d, %q, %q", code, stdout, stderr)
	}
}

// TestRenderNamesTheWaitingPullRequestItIsGiven (forsgren#40, step 5): with
// --latest newer and --waiting-pr, the footer names the pull request's
// number instead of "is available"; --waiting-pr 0 is none.
func TestRenderNamesTheWaitingPullRequestItIsGiven(t *testing.T) {
	cases := []struct {
		name, latest, pr string
		want, notWant    string
	}{
		{"waiting", "0.0.10", "7", version + " · 0.0.10 is waiting in pull request #7 (merge it to update)", " is available"},
		{"none given", "0.0.10", "0", "0.0.10 is available", "waiting"},
		{"up to date", version, "7", version + " The five", "pull request #"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			code, stderr, index := renderWith(t, "--latest", c.latest, "--waiting-pr", c.pr)
			if code != 0 || !strings.Contains(index, c.want) || strings.Contains(index, c.notWant) {
				t.Errorf("want exit 0, %q and not %q, got %d, %q, page:\n%s", c.want, c.notWant, code, stderr, index)
			}
		})
	}
}

const waitingPath = "/repos/acme/data/pulls"

// dependabotPulls is two open pull requests of acme/data: a person's, and
// Dependabot's bump of forsgren's pin to 0.0.10.
const dependabotPulls = `[
 {"number": 3, "user": {"login": "acme-dev"}, "head": {"ref": "feature/x"}},
 {"number": 7, "user": {"login": "dependabot[bot]"},
  "head": {"ref": "dependabot/github_actions/yveshanoulle/forsgren/dot-github/workflows/metrics.yml-0.0.10"}}
]`

// TestWaitingPullRequestPrintsTheNumber (forsgren#40, step 5): the command
// reads the open pull requests of GITHUB_REPOSITORY and prints the number of
// Dependabot's bump to --version, and nothing when there is none.
func TestWaitingPullRequestPrintsTheNumber(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	t.Setenv("GITHUB_TOKEN", testToken)
	fakeAPI(t, map[string]string{waitingPath: dependabotPulls}, 0)
	code, stdout, stderr := runCommand("waiting-pull-request", "--version", "0.0.10")
	if code != 0 || stdout != "7\n" {
		t.Errorf("want exit 0 and 7, got %d, %q, stderr %q", code, stdout, stderr)
	}
	code, stdout, stderr = runCommand("waiting-pull-request", "--version", "0.0.11")
	if code != 0 || stdout != "" || stderr != "" {
		t.Errorf("want exit 0 and silence for a version with no pull request, got %d, %q, %q", code, stdout, stderr)
	}
}

// TestAWaitingPullRequestLookupThatFailsIsNotAnError (forsgren#40, step 5):
// a token without pull-requests: read (403), another failure, or no
// GITHUB_REPOSITORY: nothing on stdout, why on stderr, exit 0, so the page
// keeps option 2's "is available"; the 403 names the permission.
func TestAWaitingPullRequestLookupThatFailsIsNotAnError(t *testing.T) {
	cases := map[string]struct {
		repository string
		code       int
		note       string
	}{
		"no permission": {"acme/data", 403, "pull-requests: read"},
		"server error":  {"acme/data", 500, "waiting pull request"},
		"no repository": {"", 0, "GITHUB_REPOSITORY"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			t.Setenv("GITHUB_REPOSITORY", c.repository)
			fakeAPI(t, map[string]string{waitingPath: `{"message":"no"}`}, c.code)
			code, stdout, stderr := runCommand("waiting-pull-request", "--version", "0.0.10")
			if code != 0 || stdout != "" || !strings.Contains(stderr, c.note) {
				t.Errorf("want exit 0, no stdout and %q on stderr, got %d, %q, %q", c.note, code, stdout, stderr)
			}
		})
	}
}

// TestWaitingPullRequestNeedsAVersion (forsgren#40, step 5): without
// --version, or with one that is not a version, it is a usage error.
func TestWaitingPullRequestNeedsAVersion(t *testing.T) {
	for _, args := range [][]string{{"waiting-pull-request"}, {"waiting-pull-request", "--version", "banana"}} {
		if code, _, stderr := runCommand(args...); code != 2 || !strings.Contains(stderr, "--version") {
			t.Errorf("%v: want exit 2 naming --version, got %d, %q", args, code, stderr)
		}
	}
}
