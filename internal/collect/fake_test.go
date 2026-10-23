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
	"strconv"
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
// paged also gets a Link to its page 2. A repository's issues, an issue's
// comments and a repository's pull requests it has no body for are an empty
// list: collect reads every repository's failure issues (forsgren#18) and
// pull requests (forsgren#255), and a test about deployments has none.
type gitHub struct {
	srv     *httptest.Server
	mu      sync.Mutex
	bodies  map[string]string
	status  map[string]int
	paged   map[string]bool
	limited map[string]bool // paths answered with Retry-After: 60, GitHub's secondary rate limit
	left    map[string]int  // paths answered with X-RateLimit-Remaining: n, of 5000, resetting at resetAt
	resetAt time.Time
	// allow, when above 0, makes every answer say how many requests are left of
	// 5000: the margin of 250 plus allow, less the requests since the run began
	// (used), so a run may send allow requests, and one more (forsgren#64).
	allow, used int
	// report is what the latest run left incomplete (forsgren#64, step 3b).
	report Report
	// noReport makes the run pass no Report (the option is optional).
	noReport bool
	requests []string // path?query
}

func newGitHub(t *testing.T) *gitHub {
	t.Helper()
	g := &gitHub{bodies: map[string]string{}, status: map[string]int{}, paged: map[string]bool{},
		limited: map[string]bool{}, left: map[string]int{},
		resetAt: time.Now().Add(40 * time.Minute).Truncate(time.Second)}
	g.srv = httptest.NewServer(http.HandlerFunc(g.serve))
	t.Cleanup(g.srv.Close)
	return g
}

// setHeaders sets the Link to page 2 of a path in paged, the Retry-After of a
// path in limited and the rate-limit headers of a path in left.
func (g *gitHub) setHeaders(w http.ResponseWriter, r *http.Request, key string) {
	if g.paged[key] {
		next := r.URL.Query()
		next.Set("page", "2")
		w.Header().Set("Link", "<"+g.srv.URL+r.URL.Path+"?"+next.Encode()+`>; rel="next"`)
	}
	if g.limited[key] {
		w.Header().Set("Retry-After", "60")
	}
	n, ok := g.left[key]
	if g.allow > 0 {
		n, ok = 250+g.allow-g.used, true
	}
	if ok {
		w.Header().Set("X-RateLimit-Remaining", strconv.Itoa(n))
		w.Header().Set("X-RateLimit-Limit", "5000")
		w.Header().Set("X-RateLimit-Reset", strconv.FormatInt(g.resetAt.Unix(), 10))
	}
}

func (g *gitHub) serve(w http.ResponseWriter, r *http.Request) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.requests = append(g.requests, r.URL.RequestURI())
	g.used++
	key := keyOf(r)
	body, ok := g.bodies[key]
	if !ok && listsNothingByDefault(r.URL.Path) {
		body, ok = "[]", true
	}
	if !ok {
		w.WriteHeader(http.StatusNotFound)
		_, _ = io.WriteString(w, `{"message":"Not Found"}`)
		return
	}
	g.setHeaders(w, r, key)
	if code := g.status[key]; code != 0 {
		w.WriteHeader(code)
	}
	_, _ = io.WriteString(w, body)
}

// listsNothingByDefault says whether the fake answers an empty list to the
// path when it has no body for it: a repository's issues, an issue's
// comments and a repository's pull requests (forsgren#255).
func listsNothingByDefault(path string) bool {
	return strings.HasSuffix(path, "/issues") || strings.HasSuffix(path, "/comments") ||
		strings.HasSuffix(path, "/pulls")
}

// allIssues marks the fake's answers to a repository's issues listed
// without a labels filter (forsgren#76); the issues of one label, the
// failure issues, keep the plain path. allIssuesPath is acme/app's key.
const (
	allIssues     = "#all"
	allIssuesPath = issuesPath + allIssues
	// fullIssues marks the answers to the one full read, which asks for no
	// since (forsgren#76, decision #109).
	fullIssues     = "#full"
	fullIssuesPath = issuesPath + fullIssues
	// bugIssues marks the answers to the read of the issues labelled bug
	// (forsgren#126); an unset one is an empty list.
	bugIssues     = "#bug"
	bugIssuesPath = issuesPath + bugIssues
)

// keyOf is the key in bodies, status and paged of the answer to r: its path,
// with bugIssues for the list of the bug label, and for a list of issues without a labels parameter that path with
// allIssues, or with fullIssues when it asks for no since.
func keyOf(r *http.Request) string {
	query := r.URL.Query()
	switch {
	case strings.HasSuffix(r.URL.Path, "/issues") && query.Get("labels") == "bug":
		return r.URL.Path + bugIssues
	case !strings.HasSuffix(r.URL.Path, "/issues") || query.Has("labels"):
		return r.URL.Path
	case query.Has("since"):
		return r.URL.Path + allIssues
	}
	return r.URL.Path + fullIssues
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
	g.used = 0
	var stdout, stderr bytes.Buffer
	g.report = Report{}
	o := Options{Client: client, History: path, Now: now, Stdout: &stdout, Stderr: &stderr, Report: &g.report}
	if g.noReport {
		o.Report = nil
	}
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
