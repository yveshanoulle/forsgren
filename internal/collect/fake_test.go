package collect

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// now is the moment every test collects at.
var now = time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)

const (
	shaA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	shaB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	shaC = "cccccccccccccccccccccccccccccccccccccccc"
)

// gitHub is a fake GitHub that answers each path with one body (status 200),
// or 404 for a path it does not know, and records every request. A path in
// paged also gets a Link to its page 2. A repository's issues it has no body
// for are an empty list: collect reads every repository's failure issues
// (forsgren#18), and a test about deployments has none.
type gitHub struct {
	srv      *httptest.Server
	mu       sync.Mutex
	bodies   map[string]string
	status   map[string]int
	paged    map[string]bool
	requests []string // path?query
}

func newGitHub(t *testing.T) *gitHub {
	t.Helper()
	g := &gitHub{bodies: map[string]string{}, status: map[string]int{}, paged: map[string]bool{}}
	g.srv = httptest.NewServer(http.HandlerFunc(g.serve))
	t.Cleanup(g.srv.Close)
	return g
}

func (g *gitHub) serve(w http.ResponseWriter, r *http.Request) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.requests = append(g.requests, r.URL.RequestURI())
	body, ok := g.bodies[r.URL.Path]
	if !ok && strings.HasSuffix(r.URL.Path, "/issues") {
		body, ok = "[]", true
	}
	if !ok {
		w.WriteHeader(http.StatusNotFound)
		_, _ = io.WriteString(w, `{"message":"Not Found"}`)
		return
	}
	if g.paged[r.URL.Path] {
		w.Header().Set("Link", "<"+g.srv.URL+r.URL.Path+`?page=2>; rel="next"`)
	}
	if code := g.status[r.URL.Path]; code != 0 {
		w.WriteHeader(code)
	}
	_, _ = io.WriteString(w, body)
}

// seen is the requests so far whose path?query starts with prefix.
func (g *gitHub) seen(prefix string) []string {
	g.mu.Lock()
	defer g.mu.Unlock()
	var out []string
	for _, r := range g.requests {
		if strings.HasPrefix(r, prefix) {
			out = append(out, r)
		}
	}
	return out
}

// The JSON of GitHub's REST API, with the fields collect reads (names from
// GitHub's REST reference) and a few it does not.

func deployment(id int64, sha, task, created string) string {
	return fmt.Sprintf(`{"id": %d, "sha": %q, "ref": "main", "task": %q, "environment": "production", `+
		`"created_at": %q, "updated_at": %q}`, id, sha, task, created, created)
}

func status(id int64, state, created string) string {
	return fmt.Sprintf(`{"id": %d, "state": %q, "description": "", "environment": "production", "created_at": %q}`,
		id, state, created)
}

// run is a workflow run of acme/app on trunk; an empty conclusion is null.
func run(id int64, sha, state, conclusion, started string) string {
	c := "null"
	if conclusion != "" {
		c = fmt.Sprintf("%q", conclusion)
	}
	return fmt.Sprintf(`{"id": %d, "name": "Deploy", "head_branch": "trunk", "head_sha": %q, "event": "push", `+
		`"status": %q, "conclusion": %s, "created_at": %q, "updated_at": %q, "run_started_at": %q, `+
		`"head_repository": {"full_name": "acme/app"}}`, id, sha, state, c, started, started, started)
}

// release is a release of acme/app; an empty published time is null.
func release(id int64, tag string, draft, prerelease bool, published string) string {
	p := "null"
	if published != "" {
		p = fmt.Sprintf("%q", published)
	}
	return fmt.Sprintf(`{"id": %d, "tag_name": %q, "target_commitish": "main", "name": %q, "draft": %t, `+
		`"prerelease": %t, "created_at": "2026-09-01T00:00:00Z", "published_at": %s}`,
		id, tag, tag, draft, prerelease, p)
}

func list(items ...string) string { return "[" + strings.Join(items, ",") + "]" }

func runs(items ...string) string {
	return fmt.Sprintf(`{"total_count": %d, "workflow_runs": %s}`, len(items), list(items...))
}

// repository is one repository of the project Shop.
func repository(name string, kind config.DeploymentKind, deploymentName string) config.Repository {
	return config.Repository{Name: name, Deployment: config.Deployment{Kind: kind, Name: deploymentName}}
}

func shop(repos ...config.Repository) config.Config {
	return config.Config{
		Version:          1,
		HistoryDays:      config.DefaultHistoryDays,
		HistoryChunkDays: config.DefaultHistoryChunkDays,
		Projects:         []config.Project{{Name: "Shop", Repositories: repos}},
	}
}

// result is what one collect run printed and returned.
type result struct {
	stdout, stderr string
	err            error
}

// collect runs Run against the fake, with the history at path.
func (g *gitHub) collect(t *testing.T, cfg config.Config, path string, maxPages int) result {
	t.Helper()
	client, err := github.New(g.srv.URL, "sesame-sesame-sesame", maxPages)
	if err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	o := Options{Client: client, History: path, Now: now, Stdout: &stdout, Stderr: &stderr}
	err = Run(context.Background(), cfg, o)
	return result{stdout.String(), stderr.String(), err}
}

func historyPath(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "data", "deployments.csv")
}

// wantRecords fails unless the history at path holds want, in order.
func wantRecords(t *testing.T, path string, want ...history.Record) {
	t.Helper()
	got, err := history.Load(path)
	if err != nil {
		t.Fatalf("want a history, got %v", err)
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the records\n%v\ngot\n%v", want, got)
	}
}

func wantStdout(t *testing.T, r result, want string) {
	t.Helper()
	if r.err != nil || r.stdout != want {
		t.Errorf("want stdout %q and no error, got %q, %v (stderr %q)", want, r.stdout, r.err, r.stderr)
	}
}

func at(day, hour, minute int) time.Time {
	return time.Date(2026, 9, day, hour, minute, 0, 0, time.UTC)
}

// record is a record of acme/app in the project Shop.
func record(kind history.Kind, name string, id int64, commit string, created time.Time, state history.State,
	task string) history.Record {
	return history.Record{Project: "Shop", Repository: "acme/app", Kind: kind, Name: name, ID: id, Commit: commit,
		CreatedAt: created, State: state, Task: task}
}
