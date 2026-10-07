package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/needs"
)

// workflowWithoutIssuesWrite is the template's workflow shape: its job
// declares permissions, without issues: write.
const workflowWithoutIssuesWrite = `name: Forsgren
on:
  schedule:
    - cron: "0 5 * * *"
jobs:
  metrics:
    permissions:
      contents: write
      pages: write
      id-token: write
    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@0123456789abcdef0123456789abcdef01234567
`

// setupServer answers the setup issue lookup with no issue and the write of
// one with createCode; it keeps the bodies of the POSTs it got.
type setupServer struct {
	posts []string
}

func newSetupServer(t *testing.T, createCode int) *setupServer {
	t.Helper()
	fake := &setupServer{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost && r.URL.Path == "/repos/acme/data/issues" {
			body, _ := io.ReadAll(r.Body)
			fake.posts = append(fake.posts, string(body))
			w.WriteHeader(createCode)
			_, _ = io.WriteString(w, `{"number": 7}`)
			return
		}
		_, _ = io.WriteString(w, `[]`)
	}))
	t.Cleanup(srv.Close)
	setGithubAPI(t, srv.URL)
	return fake
}

// installationWithoutIssuesWrite makes a checkout the working directory of
// the test: the workflow without issues: write and a minimal config.
func installationWithoutIssuesWrite(t *testing.T) {
	t.Helper()
	installationWithWorkflow(t, workflowWithoutIssuesWrite)
}

// installationWithIssuesWrite is the same checkout with issues: write on the
// job: every need of 0.4.0 is in place.
func installationWithIssuesWrite(t *testing.T) {
	t.Helper()
	installationWithWorkflow(t, strings.Replace(workflowWithoutIssuesWrite,
		"      pages: write\n", "      issues: write\n      pages: write\n", 1))
}

// installationWithWorkflow makes a checkout the working directory of the
// test: the workflow and a minimal config.
func installationWithWorkflow(t *testing.T, workflow string) {
	t.Helper()
	dir := t.TempDir()
	t.Chdir(dir)
	if err := os.MkdirAll(filepath.Join(dir, ".github", "workflows"), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".github", "workflows", "forsgren.yml"),
		[]byte(workflow), 0o600); err != nil {
		t.Fatal(err)
	}
	config := []byte("version: 1\nprojects: []\n")
	if err := os.WriteFile(filepath.Join(dir, "forsgren.config.yml"), config, 0o600); err != nil {
		t.Fatal(err)
	}
}

// TestCheckNeedsWritesTheSetupIssueAndRecordsHowItWent (forsgren#73, step
// 15): with issues: write missing, check-needs creates the setup issue and
// records ok; a refused write is the status no-access, never a red run, and
// its note names GITHUB_TOKEN, the token check-needs writes with.
// The test pins the version at 0.4.0, the release that introduced the need.
func TestCheckNeedsWritesTheSetupIssueAndRecordsHowItWent(t *testing.T) {
	cases := []struct {
		name       string
		createCode int
		wantStatus string
		wantStderr string
	}{
		{"written", http.StatusCreated, statusOK, ""},
		{"refused", http.StatusForbidden, statusNoAccess, "check GITHUB_TOKEN's access to acme/data"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			setVersion(t, "0.4.0")
			t.Setenv("GITHUB_TOKEN", testToken)
			fake := newSetupServer(t, c.createCode)
			installationWithoutIssuesWrite(t)
			code, _, stderr := runCommand("check-needs", "--config", "forsgren.config.yml",
				"--repository", "acme/data", "--status", "needs-status.txt")
			if code != 0 {
				t.Errorf("want exit 0, got %d, stderr %q", code, stderr)
			}
			if !strings.Contains(stderr, c.wantStderr) {
				t.Errorf("stderr %q, want it to contain %q", stderr, c.wantStderr)
			}
			wantCreatedWithMarker(t, fake)
			if got := readFile(t, "needs-status.txt"); got != c.wantStatus {
				t.Errorf("status = %q, want %q", got, c.wantStatus)
			}
		})
	}
}

// wantCreatedWithMarker fails the test unless exactly one issue was posted
// and its body starts with the marker.
func wantCreatedWithMarker(t *testing.T, fake *setupServer) {
	t.Helper()
	if len(fake.posts) != 1 {
		t.Fatalf("want one POST of the setup issue, got %d", len(fake.posts))
	}
	var posted struct{ Body string }
	if err := json.Unmarshal([]byte(fake.posts[0]), &posted); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(posted.Body, needs.Marker) {
		t.Errorf("posted body %q, want it to start with the marker", posted.Body)
	}
}

// newOpenIssueServer answers the setup issue lookup with the open, marked
// issue 7 and every write to it, the comment of its close first, with 500.
func newOpenIssueServer(t *testing.T) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		_, _ = io.WriteString(w, `[{"number": 7, "state": "open", "title": "Setup", "created_at": "2026-10-01T00:00:00Z", `+
			`"body": "`+needs.Marker+`\nsomething"}]`)
	}))
	t.Cleanup(srv.Close)
	setGithubAPI(t, srv.URL)
}

// TestCheckNeedsNothingMissingIsOkWhateverTheCloseDid (forsgren#73, step
// 19, Yves's ruling): with every need in place the status is ok even when
// closing the open setup issue fails; the failed close is a note on stderr.
func TestCheckNeedsNothingMissingIsOkWhateverTheCloseDid(t *testing.T) {
	setVersion(t, "0.4.0")
	t.Setenv("GITHUB_TOKEN", testToken)
	newOpenIssueServer(t)
	installationWithIssuesWrite(t)
	code, _, stderr := runCommand("check-needs", "--config", "forsgren.config.yml",
		"--repository", "acme/data", "--status", "needs-status.txt")
	if code != 0 {
		t.Errorf("want exit 0, got %d, stderr %q", code, stderr)
	}
	if !strings.Contains(stderr, "the setup issue could not be closed") {
		t.Errorf("stderr %q, want a note that the setup issue could not be closed", stderr)
	}
	if got := readFile(t, "needs-status.txt"); got != statusOK {
		t.Errorf("status = %q, want %q", got, statusOK)
	}
}

// TestCheckNeedsFailuresAreStatusesNeverARedRun (forsgren#73, step 15): a
// check that cannot run is the status failed and a note on stderr, an
// unreadable config only a note, a missing flag a usage error, and an
// unwritable status file a note: exit 0 once the flags are valid.
func TestCheckNeedsFailuresAreStatusesNeverARedRun(t *testing.T) {
	cases := []failureCase{
		{"no repository", nil, []string{"--config", "forsgren.config.yml"}, 2,
			"--repository <owner/name> is required", ""},
		{"unknown flag", nil, []string{"--nope"}, 2, "flag provided but not defined", ""},
		{"no config", nil, []string{"--repository", "acme/data"}, 2, "--config <path> is required", ""},
		{"unreadable config", nil, []string{"--config", "nope.yml", "--repository", "acme/data",
			"--status", "needs-status.txt"}, 0, "the config keys are unknown", statusOK},
		{"unknown version", func(t *testing.T) { setVersion(t, "dev") },
			[]string{"--config", "forsgren.config.yml", "--repository", "acme/data", "--status", "needs-status.txt"}, 0,
			"is not three dot-separated numbers", statusFailed},
		{"bad api address", func(t *testing.T) { setGithubAPI(t, "not a url") },
			[]string{"--config", "forsgren.config.yml", "--repository", "acme/data", "--status", "needs-status.txt"}, 0,
			"not a url", statusFailed},
		{"unwritable status", nil, []string{"--config", "forsgren.config.yml", "--repository", "acme/data",
			"--status", "no-such-dir/status.txt"}, 0, "cannot write the status", ""},
	}
	for _, c := range cases {
		t.Run(c.name, c.run)
	}
}

// failureCase is one row of the failure table: the setup it needs, the
// arguments of check-needs and what the run must show.
type failureCase struct {
	name       string
	setup      func(t *testing.T)
	args       []string
	wantCode   int
	wantStderr string
	wantStatus string
}

// run sets the row up and runs check-needs with its arguments.
func (c failureCase) run(t *testing.T) {
	t.Helper()
	setVersion(t, "0.4.0")
	t.Setenv("GITHUB_TOKEN", testToken)
	newSetupServer(t, http.StatusCreated)
	installationWithoutIssuesWrite(t)
	if c.setup != nil {
		c.setup(t)
	}
	code, stdout, stderr := runCommand(append([]string{"check-needs"}, c.args...)...)
	c.want(t, code, stdout, stderr)
}

// want fails the test unless the run ended as the row says.
func (c failureCase) want(t *testing.T, code int, stdout, stderr string) {
	t.Helper()
	if code != c.wantCode {
		t.Errorf("want exit %d, got %d", c.wantCode, code)
	}
	if !strings.Contains(stderr, c.wantStderr) {
		t.Errorf("stderr %q, want it to contain %q", stderr, c.wantStderr)
	}
	if c.wantStatus != "" {
		wantStatusLine(t, stdout, c.wantStatus)
	}
}

// wantStatusLine fails the test unless stdout names the status and the file
// holds it.
func wantStatusLine(t *testing.T, stdout, status string) {
	t.Helper()
	if !strings.Contains(stdout, "check-needs: "+status+"\n") {
		t.Errorf("stdout %q, want the status %q", stdout, status)
	}
	if got := readFile(t, "needs-status.txt"); got != status {
		t.Errorf("status file = %q, want %q", got, status)
	}
}

// setVersion runs the test as forsgren version v, restored afterwards.
func setVersion(t *testing.T, v string) {
	t.Helper()
	old := version
	version = v
	t.Cleanup(func() { version = old })
}

// setGithubAPI points the GitHub client at url, restored afterwards.
func setGithubAPI(t *testing.T, url string) {
	t.Helper()
	old := githubAPI
	githubAPI = url
	t.Cleanup(func() { githubAPI = old })
}
