package main

import (
	"strings"
	"testing"
)

// wantLookup runs args and fails the test unless the command exits 0, prints
// exactly stdout, and says note on stderr (nothing at all when note is
// empty): the contract of a lookup, which is never an error, and of any
// command that succeeds.
func wantLookup(t *testing.T, stdout, note string, args ...string) {
	t.Helper()
	wantExit(t, exit{0, stdout, note}, args...)
}

// exit is what a command is expected to end with: its exit status, exactly
// what it prints on stdout, and a note on stderr (nothing at all when note is
// empty).
type exit struct {
	code         int
	stdout, note string
}

// wantExit runs args and fails the test unless the command ends as want says.
func wantExit(t *testing.T, want exit, args ...string) {
	t.Helper()
	code, stdout, stderr := runCommand(args...)
	if code != want.code {
		t.Errorf("%v: want exit %d, got %d, stderr %q", args, want.code, code, stderr)
	}
	if stdout != want.stdout {
		t.Errorf("%v: want stdout %q, got %q", args, want.stdout, stdout)
	}
	if !saysNote(stderr, want.note) {
		t.Errorf("%v: want %q on stderr, got %q", args, want.note, stderr)
	}
}

// saysNote says whether stderr holds note, or is empty when note is.
func saysNote(stderr, note string) bool {
	if note == "" {
		return stderr == ""
	}
	return strings.Contains(stderr, note)
}

// wantPage renders with args and fails the test unless the render exits 0
// and the page has want but not notWant.
func wantPage(t *testing.T, want, notWant string, args ...string) {
	t.Helper()
	code, stderr, index := renderWith(t, args...)
	if code != 0 {
		t.Errorf("%v: want exit 0, got %d, %q", args, code, stderr)
	}
	if !strings.Contains(index, want) {
		t.Errorf("%v: want %q on the page, got:\n%s", args, want, index)
	}
	if notWant != "" && strings.Contains(index, notWant) {
		t.Errorf("%v: want no %q on the page, got:\n%s", args, notWant, index)
	}
}

// TestRenderNamesTheLatestReleaseItIsGiven (forsgren#40, step 4, option 2):
// render takes the newest forsgren release as --latest, so it needs no
// network; a newer one is named in the footer of both pages.
func TestRenderNamesTheLatestReleaseItIsGiven(t *testing.T) {
	dir := t.TempDir()
	if code, _, stderr := runCommand("render", "--out", dir, "--latest", "0.6.1"); code != 0 {
		t.Fatalf("want exit 0, got %d, %q", code, stderr)
	}
	for _, name := range []string{"index.html", "legend.html"} {
		if got := readFile(t, dir+"/"+name); !strings.Contains(got, version+" · 0.6.1 is available") {
			t.Errorf("%s: want %q in the footer, got:\n%s", name, version+" · 0.6.1 is available", got)
		}
	}
}

// TestRenderSaysNothingWhenNoNewerReleaseIsKnown (forsgren#40, step 4): no
// --latest, the version itself, an older one, or one that is not a version
// (a lookup that failed): the page renders as before, exit 0, nothing added.
func TestRenderSaysNothingWhenNoNewerReleaseIsKnown(t *testing.T) {
	for _, latest := range []string{version, "0.0.1", "banana", ""} {
		wantPage(t, "Forsgren</a> "+version+" Metrics", "available", "--latest", latest)
	}
	wantPage(t, "Forsgren</a> "+version+" Metrics", "available")
}

const latestPath = "/repos/yveshanoulle/forsgren/releases/latest"

// TestLatestReleasePrintsTheNewestVersion (forsgren#40, step 4): the
// command reads forsgren's own latest release, which is public, with no
// token, and prints its version without the leading v.
func TestLatestReleasePrintsTheNewestVersion(t *testing.T) {
	t.Setenv("GITHUB_TOKEN", "")
	fakeAPI(t, map[string]string{latestPath: `{"id": 7, "tag_name": "v0.0.10"}`}, 0)
	wantLookup(t, "0.0.10\n", "", "latest-release")
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
			t.Setenv("GITHUB_TOKEN", "")
			fakeAPI(t, c.bodies, c.code)
			wantLookup(t, "", "latest release", "latest-release")
		})
	}
}

// pointAtABadAPI makes the commands' API address something that is no URL,
// for this test only.
func pointAtABadAPI(t *testing.T) {
	t.Helper()
	old := githubAPI
	githubAPI = "not a url"
	t.Cleanup(func() { githubAPI = old })
}

// TestLatestReleaseTakesNoArgumentsAndSurvivesABadAPI (forsgren#40, step 4):
// an argument is a usage error; an API address that is no URL is a lookup
// that failed, not an error.
func TestLatestReleaseTakesNoArgumentsAndSurvivesABadAPI(t *testing.T) {
	code, _, stderr := runCommand("latest-release", "now")
	if code != 2 || !strings.Contains(stderr, "usage: forsgren latest-release") {
		t.Errorf("want exit 2 and the usage, got %d, %q", code, stderr)
	}
	pointAtABadAPI(t)
	wantLookup(t, "", "latest release", "latest-release")
}

// TestRenderNamesTheWaitingPullRequestItIsGiven (forsgren#40, step 5): with
// --latest newer and --waiting-pr, the footer names the pull request's
// number instead of "is available"; without --waiting-pr there is none.
func TestRenderNamesTheWaitingPullRequestItIsGiven(t *testing.T) {
	waiting := version + " · 0.6.1 is waiting in pull request #7 (merge it to update)"
	wantPage(t, waiting, " is available", "--latest", "0.6.1", "--waiting-pr", "7")
	wantPage(t, "0.6.1 is available", "waiting", "--latest", "0.6.1")
	wantPage(t, version+" Metrics", "pull request #", "--latest", version, "--waiting-pr", "7")
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
	wantLookup(t, "7\n", "", "waiting-pull-request", "--version", "0.0.10")
	wantLookup(t, "", "", "waiting-pull-request", "--version", "0.0.11")
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
			wantLookup(t, "", c.note, "waiting-pull-request", "--version", "0.0.10")
		})
	}
}

// TestWaitingPullRequestNeedsAVersion (forsgren#40, step 5): without
// --version, or with one that is not a version, it is a usage error.
func TestWaitingPullRequestNeedsAVersion(t *testing.T) {
	for _, args := range [][]string{{"waiting-pull-request"}, {"waiting-pull-request", "--version", "banana"}} {
		code, _, stderr := runCommand(args...)
		if code != 2 || !strings.Contains(stderr, "--version") {
			t.Errorf("%v: want exit 2 naming --version, got %d, %q", args, code, stderr)
		}
	}
}

// TestWaitingPullRequestSurvivesABadAPI (forsgren#40, step 5): an API
// address that is no URL is a lookup that failed, not an error.
func TestWaitingPullRequestSurvivesABadAPI(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	pointAtABadAPI(t)
	wantLookup(t, "", "waiting pull request", "waiting-pull-request", "--version", "0.0.10")
}

// TestRenderSaysWhenThisVersionNeedsMoreConfiguration (forsgren#73, step 18):
// with --needs-check no-access, rate-limited or failed (the setup issue could
// not be written) the footer sends the reader to the run's job summary, as
// it names a newer release; with ok, or without the flag, it says nothing.
func TestRenderSaysWhenThisVersionNeedsMoreConfiguration(t *testing.T) {
	line := " · needs more configuration: see the job summary of this run."
	for _, check := range []string{"no-access", "rate-limited", "failed"} {
		wantPage(t, "Forsgren</a> "+version+line, "", "--needs-check", check)
	}
	wantPage(t, version+" Metrics", "needs more configuration", "--needs-check", "ok")
	wantPage(t, version+" Metrics", "needs more configuration")
}

// TestRenderJoinsTheUpdateAndWhatThisVersionNeeds (forsgren#73, step 18): when
// the footer names a newer release and the version needs more configuration,
// both clauses show, the update's sentence first.
func TestRenderJoinsTheUpdateAndWhatThisVersionNeeds(t *testing.T) {
	wantPage(t, "Forsgren</a> "+version+" · 99.0.0 is available."+
		" · needs more configuration: see the job summary of this run. Metrics",
		"", "--latest", "99.0.0", "--needs-check", "failed")
}
