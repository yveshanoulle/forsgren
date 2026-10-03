package main

import (
	"bytes"
	"errors"
	"io"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// testToken is the made-up FORSGREN_TOKEN of these tests: plain words, so
// the secret scan does not take it for a real one.
const testToken = "sesame-sesame-sesame"

const oneRepository = `version: 1
projects:
  - name: Shop
    repositories:
      - name: acme/app
`

// fakeAPI points the command at a test server that answers each path with
// its body, and at a fixed now, for this test only.
func fakeAPI(t *testing.T, bodies map[string]string, code int) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, ok := bodies[r.URL.Path]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
		}
		if ok && code != 0 {
			w.WriteHeader(code)
		}
		_, _ = io.WriteString(w, body)
	}))
	t.Cleanup(srv.Close)
	oldAPI, oldNow := githubAPI, now
	githubAPI, now = srv.URL, func() time.Time { return time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC) }
	t.Cleanup(func() { githubAPI, now = oldAPI, oldNow })
}

// acmeApp is one production deployment of acme/app, a success.
var acmeApp = map[string]string{
	"/repos/acme/app/deployments": `[{"id": 1001, "sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "task": "deploy",
	  "environment": "production", "created_at": "2026-09-21T10:00:00Z"}]`,
	"/repos/acme/app/deployments/1001/statuses": `[{"id": 6, "state": "success", "created_at": "2026-09-21T10:05:00Z"}]`,
}

type outcome struct {
	code           int
	stdout, stderr string
}

func collectRun(args ...string) outcome {
	var stdout, stderr bytes.Buffer
	code := run(append([]string{"collect"}, args...), &stdout, &stderr)
	return outcome{code, stdout.String(), stderr.String()}
}

func dataPath(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "data", "deployments.csv")
}

// TestCollectStoresDeploymentsAndSaysHowMany: one line per repository, the
// history written and, next to it, the commits file (forsgren#16, step 3:
// a first deployment has no commits, so it holds its header only); a
// second run finds nothing new.
func TestCollectStoresDeploymentsAndSaysHowMany(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	fakeAPI(t, acmeApp, 0)
	cfg, data := writeConfig(t, oneRepository), dataPath(t)
	for _, want := range []string{"acme/app: 1 new, 0 skipped (not final), 0 commits\n",
		"acme/app: 0 new, 0 skipped (not final), 0 commits\n"} {
		if got := collectRun("--config", cfg, "--data", data); got.code != 0 || got.stdout != want {
			t.Errorf("want exit 0 and %q, got %+v", want, got)
		}
	}
	// One deployment, and no commit: the first deployment has no previous.
	wantFile(t, data, "# forsgren history v1\n", 3)
	wantFile(t, filepath.Join(filepath.Dir(data), "commits.csv"), "# forsgren commits v1\n", 2)
}

// wantFile fails unless the file at path starts with the version line
// version and has lines lines, the column line included.
func wantFile(t *testing.T, path, version string, lines int) {
	t.Helper()
	content, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		t.Fatalf("want %s, got %v", path, err)
	}
	if !strings.HasPrefix(string(content), version) || strings.Count(string(content), "\n") != lines {
		t.Errorf("want %s with %q and %d lines, got %q", path, version, lines, content)
	}
}

// TestCollectWithNoProjectsDoesNothing: no token needed, no file, exit 0.
func TestCollectWithNoProjectsDoesNothing(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", "")
	data := dataPath(t)
	got := collectRun("--config", writeConfig(t, "version: 1\nprojects: []\n"), "--data", data)
	if got.code != 0 || got.stdout != "" || got.stderr != "" {
		t.Errorf("want exit 0 and no output, got %+v", got)
	}
	if _, err := os.Stat(data); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
}

// TestCollectWithoutATokenFails: a repository to read and no token is exit 1
// with what to set, before anything is written.
func TestCollectWithoutATokenFails(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", "")
	data := dataPath(t)
	got := collectRun("--config", writeConfig(t, oneRepository), "--data", data)
	want := "collect: FORSGREN_TOKEN is not set: collect needs a read-only GitHub token for the configured repositories"
	if got.code != 1 || !strings.Contains(got.stderr, want) {
		t.Errorf("want exit 1 and %q, got %+v", want, got)
	}
	if _, err := os.Stat(data); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
}

// TestCollectFailsByNameAndNeverPrintsTheToken: a refused repository is
// exit 1 with what to check, and the token is in no output.
func TestCollectFailsByNameAndNeverPrintsTheToken(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	fakeAPI(t, map[string]string{"/repos/acme/app/deployments": `{"message": "Bad credentials ` + testToken + `"}`},
		http.StatusUnauthorized)
	got := collectRun("--config", writeConfig(t, oneRepository), "--data", dataPath(t))
	if got.code != 1 {
		t.Errorf("want exit 1, got %+v", got)
	}
	for _, want := range []string{"check FORSGREN_TOKEN's access to acme/app", "collect: 1 of 1 repositories failed"} {
		if !strings.Contains(got.stderr, want) {
			t.Errorf("want %q on stderr, got %q", want, got.stderr)
		}
	}
	if strings.Contains(got.stdout+got.stderr, testToken) {
		t.Errorf("the token is in the output: %+v", got)
	}
}

// TestCollectUsage: both flags are required; an invalid config is exit 1.
func TestCollectUsage(t *testing.T) {
	cfg := writeConfig(t, oneRepository)
	for name, c := range map[string]struct {
		args   []string
		code   int
		stderr string
	}{
		"no --data":      {[]string{"--config", cfg}, 2, "collect: --data <path> is required"},
		"no --config":    {[]string{"--data", "x.csv"}, 2, "collect: --config <path> is required"},
		"unknown flag":   {[]string{"--out", "x"}, 2, "flag provided but not defined: -out"},
		"invalid config": {[]string{"--config", writeConfig(t, "version: 2\n"), "--data", "x.csv"}, 1, "unsupported version"},
	} {
		t.Run(name, func(t *testing.T) {
			if got := collectRun(c.args...); got.code != c.code || !strings.Contains(got.stderr, c.stderr) {
				t.Errorf("want exit %d and %q, got %+v", c.code, c.stderr, got)
			}
		})
	}
}
