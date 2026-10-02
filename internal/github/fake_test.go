package github

import (
	"cmp"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
)

// token is the made-up token of every test: one plain word, so the secret
// scan does not take it for a real one, and easy to find in any output.
const token = "sesame-sesame-sesame"

// since is the window start of the tests: older items are not wanted.
var since = time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)

// reply is what the fake GitHub answers to one page of one path. In header
// values and the body, {base} is the fake's own URL.
type reply struct {
	status int
	header http.Header
	body   string
}

// fakeGitHub is a test server that answers by path and page, and records
// every request it gets. A path it has no reply for is GitHub's 404.
type fakeGitHub struct {
	srv      *httptest.Server
	mu       sync.Mutex
	replies  map[string]reply
	requests []*http.Request
}

func newFake(t *testing.T) *fakeGitHub {
	t.Helper()
	f := &fakeGitHub{replies: map[string]reply{}}
	f.srv = httptest.NewServer(http.HandlerFunc(f.serve))
	t.Cleanup(f.srv.Close)
	return f
}

// pageKey is the key of a reply: the path, and the page ("" for the first).
func pageKey(path, page string) string { return path + "#" + page }

// on sets the reply to the first page of path.
func (f *fakeGitHub) on(path string, r reply) { f.replies[pageKey(path, "")] = r }

// onPage sets the reply to page n of path.
func (f *fakeGitHub) onPage(path, page string, r reply) { f.replies[pageKey(path, page)] = r }

func (f *fakeGitHub) serve(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	f.requests = append(f.requests, r.Clone(r.Context()))
	rep, ok := f.replies[pageKey(r.URL.Path, r.URL.Query().Get("page"))]
	f.mu.Unlock()
	if !ok {
		rep = reply{status: http.StatusNotFound, body: `{"message":"Not Found"}`}
	}
	for name, values := range rep.header {
		for _, v := range values {
			w.Header().Add(name, strings.ReplaceAll(v, "{base}", f.srv.URL))
		}
	}
	w.WriteHeader(cmp.Or(rep.status, http.StatusOK))
	_, _ = io.WriteString(w, strings.ReplaceAll(rep.body, "{base}", f.srv.URL))
}

// seen is the requests so far.
func (f *fakeGitHub) seen() []*http.Request {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.requests)
}

// client is a client of the fake with the test token.
func (f *fakeGitHub) client(t *testing.T, maxPages int) *Client {
	t.Helper()
	c, err := New(f.srv.URL, token, maxPages)
	if err != nil {
		t.Fatal(err)
	}
	return c
}

// fixture is the content of a file in testdata/.
func fixture(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Clean(filepath.Join("testdata", name)))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// next is a Link header whose rel="next" is page of path on the fake.
func next(path, page string) http.Header {
	return http.Header{"Link": {`<{base}` + path + `?page=` + page + `&per_page=100>; rel="next", ` +
		`<{base}` + path + `?page=9&per_page=100>; rel="last"`}}
}

// calls is every call of the client on repo, by name.
func calls(repo string) map[string]func(*Client) error {
	ctx := context.Background()
	return map[string]func(*Client) error{
		"deployments": func(c *Client) error {
			_, _, err := c.Deployments(ctx, repo, "production", since)
			return err
		},
		"statuses": func(c *Client) error {
			_, err := c.DeploymentStatuses(ctx, repo, 1003)
			return err
		},
		"default branch": func(c *Client) error {
			_, err := c.DefaultBranch(ctx, repo)
			return err
		},
		"runs": func(c *Client) error {
			_, _, err := c.Runs(ctx, repo, "deploy.yml", "trunk", since)
			return err
		},
		"releases": func(c *Client) error {
			_, _, err := c.Releases(ctx, repo, since)
			return err
		},
		"tag commit": func(c *Client) error {
			_, err := c.TagCommit(ctx, repo, "v1.2.0")
			return err
		},
	}
}
