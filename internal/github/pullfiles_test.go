package github

import (
	"context"
	"errors"
	"net/http"
	"testing"
)

// updateCalls are the three calls the update guard reads a pull request and
// a release with, on repo, by name.
func updateCalls(repo string) map[string]func(*Client) error {
	ctx := context.Background()
	return map[string]func(*Client) error{
		"pull request author": func(c *Client) error {
			_, err := c.PullRequestAuthor(ctx, repo, 7)
			return err
		},
		"pull request files": func(c *Client) error {
			_, _, err := c.PullRequestFiles(ctx, repo, 7)
			return err
		},
		"published release": func(c *Client) error {
			_, err := c.PublishedRelease(ctx, repo, "v1.2.0")
			return err
		},
	}
}

// updatePaths are the paths of the three calls on acme/app.
var updatePaths = map[string]string{
	"pull request author": "/repos/acme/app/pulls/7",
	"pull request files":  "/repos/acme/app/pulls/7/files",
	"published release":   "/repos/acme/app/releases/tags/v1.2.0",
}

// TestUpdateCallsRefuseARepositoryThatIsNoName: a name that is not one
// owner/name never becomes a URL, in any of the three calls.
func TestUpdateCallsRefuseARepositoryThatIsNoName(t *testing.T) {
	f := newFake(t)
	c := f.client(t, DefaultMaxPages)
	for name, call := range updateCalls("acme") {
		if err := call(c); !errors.Is(err, ErrRepositoryName) {
			t.Errorf("%s: want ErrRepositoryName, got %v", name, err)
		}
	}
	if n := len(f.seen()); n != 0 {
		t.Errorf("want no request, got %d", n)
	}
}

// TestUpdateCallsPassAnErrorAnswerOn: a 500 is a status error and a 401 an
// access error, each naming the repository and the path; no call takes
// either for an answer.
func TestUpdateCallsPassAnErrorAnswerOn(t *testing.T) {
	want := map[int]error{http.StatusInternalServerError: ErrStatus, http.StatusUnauthorized: ErrAccess}
	for status, sentinel := range want {
		for name, call := range updateCalls("acme/app") {
			f := newFake(t)
			f.on(updatePaths[name], reply{status: status, body: `{"message":"no"}`})
			wantError(t, call(f.client(t, DefaultMaxPages)), sentinel, "acme/app: ", updatePaths[name])
		}
	}
}

// TestUpdateCallsThatReadJSONNameTheRepositoryForMalformedJSON: the author
// and the files; the release's answer is not read.
func TestUpdateCallsThatReadJSONNameTheRepositoryForMalformedJSON(t *testing.T) {
	calls := updateCalls("acme/app")
	for _, name := range []string{"pull request author", "pull request files"} {
		f := newFake(t)
		f.on(updatePaths[name], reply{body: `[{"id": "not a number"`})
		wantError(t, calls[name](f.client(t, DefaultMaxPages)), ErrAnswer, "acme/app: ")
	}
}

// TestPullRequestFilesSaysItStoppedAtThePageLimit: with a limit of one page
// and a next page left, the files of the first page and truncated.
func TestPullRequestFilesSaysItStoppedAtThePageLimit(t *testing.T) {
	f := newFake(t)
	path := pullsPath + "/7/files"
	f.on(path, reply{header: next(path, "2"), body: `[{"filename": "a.yml", "patch": "@@ -1 +1 @@\n-x\n+y\n"}]`})
	got, truncated, err := f.client(t, 1).PullRequestFiles(context.Background(), "acme/data", 7)
	if err != nil {
		t.Fatal(err)
	}
	if !truncated {
		t.Errorf("want truncated, got the files %+v", got)
	}
	if len(got) != 1 {
		t.Errorf("want the one file of the first page, got %+v", got)
	}
}
