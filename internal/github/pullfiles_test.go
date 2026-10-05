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

// TestUpdateCallsThatReadJSONNameTheRepositoryForMalformedJSON: the author,
// the files and the release.
func TestUpdateCallsThatReadJSONNameTheRepositoryForMalformedJSON(t *testing.T) {
	calls := updateCalls("acme/app")
	for _, name := range []string{"pull request author", "pull request files", "published release"} {
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

// TestPullRequestAuthorReadsTheLoginOfOnePullRequest: GET
// /repos/{o}/{r}/pulls/{n} answers the pull request, whose user.login is its
// author.
func TestPullRequestAuthorReadsTheLoginOfOnePullRequest(t *testing.T) {
	f := newFake(t)
	f.on(pullsPath+"/7", reply{body: pullItem(7, "dependabot[bot]", dependabotBranch("0.1.4"))})
	got, err := f.client(t, DefaultMaxPages).PullRequestAuthor(context.Background(), "acme/data", 7)
	if err != nil || got != "dependabot[bot]" {
		t.Errorf("want dependabot[bot], got %q, %v", got, err)
	}
}

// TestPublishedReleaseIsTrueForATagWithARelease: GET
// /repos/{o}/{r}/releases/tags/{tag} answering a release says it is published.
func TestPublishedReleaseIsTrueForATagWithARelease(t *testing.T) {
	f := newFake(t)
	f.on(updatePaths["published release"], reply{body: `{"id": 7, "tag_name": "v1.2.0"}`})
	got, err := f.client(t, DefaultMaxPages).PublishedRelease(context.Background(), "acme/app", "v1.2.0")
	if err != nil || !got {
		t.Errorf("want a published release, got %v, %v", got, err)
	}
}

// TestPublishedReleaseIsFalseForATagWithNoPublishedRelease: a 404 is a tag
// with no release, and a draft (which GitHub answers with 200 to a token that
// may push) or a prerelease is no published one; none is an error.
func TestPublishedReleaseIsFalseForATagWithNoPublishedRelease(t *testing.T) {
	answers := map[string]reply{
		"a 404":        {status: http.StatusNotFound, body: `{"message":"Not Found"}`},
		"a draft":      {body: `{"id": 7, "tag_name": "v1.2.0", "draft": true}`},
		"a prerelease": {body: `{"id": 7, "tag_name": "v1.2.0", "prerelease": true}`},
	}
	for name, answer := range answers {
		f := newFake(t)
		f.on(updatePaths["published release"], answer)
		got, err := f.client(t, DefaultMaxPages).PublishedRelease(context.Background(), "acme/app", "v1.2.0")
		if err != nil || got {
			t.Errorf("%s: want no published release and no error, got %v, %v", name, got, err)
		}
	}
}

// TestIsRepositoryNameIsTheNameEveryCallRequires: one owner/name, never .. as
// the name.
func TestIsRepositoryNameIsTheNameEveryCallRequires(t *testing.T) {
	for repo, want := range map[string]bool{"acme/app": true, "acme": false, "acme/..": false} {
		if got := IsRepositoryName(repo); got != want {
			t.Errorf("IsRepositoryName(%q) = %v, want %v", repo, got, want)
		}
	}
}
