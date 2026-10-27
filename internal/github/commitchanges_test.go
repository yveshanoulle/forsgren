package github

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"testing"
)

const commitChangesPath = "/repos/acme/app/commits/" + shaHead

// changedFiles is CommitChangedFiles of shaHead in acme/app on the fake.
func changedFiles(t *testing.T, f *fakeGitHub, maxPages int) ([]string, bool, error) {
	t.Helper()
	return f.client(t, maxPages).CommitChangedFiles(context.Background(), "acme/app", shaHead)
}

// TestCommitChangedFilesReadsEveryPageAndTheOldNameOfARename (forsgren#496):
// the filename of each file, and for a renamed one its previous_filename too,
// from every page of GET /repos/{o}/{r}/commits/{sha}.
func TestCommitChangedFilesReadsEveryPageAndTheOldNameOfARename(t *testing.T) {
	f := newFake(t)
	f.on(commitChangesPath, reply{header: next(commitChangesPath, "2"), body: fixture(t, "commit-files.json")})
	f.onPage(commitChangesPath, "2", reply{body: `{"files": [{"filename": "docs/readme.md"}]}`})
	got, cut, err := changedFiles(t, f, DefaultMaxPages)
	wantRead(t, cut, false, err)
	want := []string{"api/handler.go", "web/index.html", "api/index.html", "go.mod", "docs/readme.md"}
	if !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
	wantRequests(t, f, 2)
}

// TestCommitChangedFilesSayTheyStoppedAtThePageLimit: files left on a later
// page than the limit reads are cut.
func TestCommitChangedFilesSayTheyStoppedAtThePageLimit(t *testing.T) {
	f := newFake(t)
	f.on(commitChangesPath, reply{header: next(commitChangesPath, "2"), body: fixture(t, "commit-files.json")})
	got, cut, err := changedFiles(t, f, 1)
	wantRead(t, cut, true, err)
	if len(got) != 4 {
		t.Errorf("want the first page's 4 paths, got %v", got)
	}
}

// TestCommitChangedFilesOfACommitWithNoFilesIsEmpty: a merge commit may list
// no file, which is not an error.
func TestCommitChangedFilesOfACommitWithNoFilesIsEmpty(t *testing.T) {
	f := newFake(t)
	f.on(commitChangesPath, reply{body: `{"sha": "` + shaHead + `"}`})
	got, cut, err := changedFiles(t, f, DefaultMaxPages)
	wantRead(t, cut, false, err)
	if len(got) != 0 {
		t.Errorf("want no path, got %v", got)
	}
}

// TestCommitChangedFilesNameAMissingCommit: a 404 and a 422 are
// ErrMissingCommit naming the SHA.
func TestCommitChangedFilesNameAMissingCommit(t *testing.T) {
	for _, status := range []int{http.StatusNotFound, http.StatusUnprocessableEntity} {
		f := newFake(t)
		f.on(commitChangesPath, reply{status: status, body: `{"message":"No commit found"}`})
		_, _, err := changedFiles(t, f, DefaultMaxPages)
		wantError(t, err, ErrMissingCommit, "acme/app", shaHead)
	}
}

// TestCommitChangedFilesNameTheTokenAndItsFix: a 403 is ErrAccess and
// ErrCommitFilesDenied naming Contents: read for the token that was refused.
func TestCommitChangedFilesNameTheTokenAndItsFix(t *testing.T) {
	for _, c := range []deniedCase{
		{"GITHUB_TOKEN", "the job's token needs contents: read", "Contents: Read"},
		{"FORSGREN_TOKEN", "the repository permission Contents: Read", "contents: read"},
	} {
		f := newFake(t)
		f.on(commitChangesPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
		_, _, err := f.client(t, DefaultMaxPages).WithTokenName(c.tokenName).
			CommitChangedFiles(context.Background(), "acme/app", shaHead)
		wantDeniedFix(t, c, err, ErrCommitFilesDenied)
	}
}

// TestCommitChangedFilesRefuseARepositoryThatIsNoName: it never becomes a URL.
func TestCommitChangedFilesRefuseARepositoryThatIsNoName(t *testing.T) {
	f := newFake(t)
	_, _, err := f.client(t, DefaultMaxPages).CommitChangedFiles(context.Background(), "acme", shaHead)
	wantError(t, err, ErrRepositoryName)
	wantRequests(t, f, 0)
}

// TestCommitChangedFilesKeepTheRateLimitAndRefuseJunk: a 403 with no request
// left stays ErrRateLimit, and an answer that is no commit is ErrAnswer.
func TestCommitChangedFilesKeepTheRateLimitAndRefuseJunk(t *testing.T) {
	f := newFake(t)
	f.on(commitChangesPath, reply{status: 403, header: http.Header{"X-Ratelimit-Remaining": {"0"}},
		body: `{"message":"API rate limit exceeded"}`})
	_, _, err := changedFiles(t, f, DefaultMaxPages)
	wantError(t, err, ErrRateLimit)
	if errors.Is(err, ErrCommitFilesDenied) {
		t.Errorf("want no missing permission for a rate limit, got %v", err)
	}
	g := newFake(t)
	g.on(commitChangesPath, reply{body: `[1]`})
	_, _, err = changedFiles(t, g, DefaultMaxPages)
	wantError(t, err, ErrAnswer, "acme/app: ")
}
