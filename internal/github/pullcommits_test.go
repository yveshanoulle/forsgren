package github

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"
)

const pullCommitsPath = "/repos/acme/app/pulls/45/commits"

// pullCommitItems is a page of n commits of a pull request, each authored at
// authored, as GitHub answers them, with a committer date that is not read.
func pullCommitItems(n int, authored string) string {
	item := `{"sha": "` + shaHead + `", "commit": {"author": {"name": "Acme Dev", "date": "` + authored + `"}, ` +
		`"committer": {"date": "2026-08-02T07:00:00Z"}}}`
	items := make([]string, n)
	for i := range items {
		items[i] = item
	}
	return "[" + strings.Join(items, ", ") + "]"
}

// pullCommitsError is the error of PullCommits of pull request 45 of
// acme/app on the fake.
func pullCommitsError(t *testing.T, f *fakeGitHub) error {
	t.Helper()
	_, _, err := f.client(t, DefaultMaxPages).PullCommits(context.Background(), "acme/app", 45)
	return err
}

// TestPullCommitsNamesTheMissingPermission: a 403 is the token without
// pull-requests: read (explainDenied), a rate limit stays ErrRateLimit.
func TestPullCommitsNamesTheMissingPermission(t *testing.T) {
	f := newFake(t)
	f.on(pullCommitsPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
	err := pullCommitsError(t, f)
	wantError(t, err, ErrPullRequestsDenied, "acme/app", pullCommitsPath, "Pull requests: Read")
	wantError(t, err, ErrAccess)

	limited := newFake(t)
	limited.on(pullCommitsPath, reply{status: 403, header: http.Header{"Retry-After": {"60"}}})
	err = pullCommitsError(t, limited)
	wantError(t, err, ErrRateLimit, "acme/app")
	if strings.Contains(err.Error(), "Pull requests: Read") {
		t.Errorf("want no missing permission for a rate limit, got %v", err)
	}
}

// TestPullCommitsRefusesAnAnswerWithoutOne: a pull request with no commit, or
// a commit with no author date, has no commits to give: it is ErrAnswer
// naming the path, never an empty list, and ErrNoCommitDate, which tells it
// from an answer that cannot be read (forsgren#320, decision #313).
func TestPullCommitsRefusesAnAnswerWithoutOne(t *testing.T) {
	for name, body := range map[string]string{
		"no commits":     "[]",
		"no author date": `[{"sha": "` + shaHead + `", "commit": {"committer": {"date": "2026-08-02T07:00:00Z"}}}]`,
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(pullCommitsPath, reply{body: body})
			err := pullCommitsError(t, f)
			wantError(t, err, ErrAnswer, "acme/app: ", pullCommitsPath, "pull request 45")
			wantError(t, err, ErrNoCommitDate)
		})
	}
}

// TestPullCommitsTellsAnUnreadableAnswerFromAMissingDate (forsgren#320,
// decision #313): a page that is not a list of commits, or a commit whose
// fields have the wrong shape, is ErrAnswer naming the path, never
// ErrNoCommitDate, so collect can warn about it apart.
func TestPullCommitsTellsAnUnreadableAnswerFromAMissingDate(t *testing.T) {
	for name, body := range map[string]string{
		"not a list":     `{"message": "not a list"}`,
		"not JSON":       `[{"sha": `,
		"a date of text": `[{"sha": "` + shaHead + `", "commit": {"author": {"date": "yesterday"}}}]`,
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(pullCommitsPath, reply{body: body})
			err := pullCommitsError(t, f)
			wantError(t, err, ErrAnswer, "acme/app: ", pullCommitsPath)
			if errors.Is(err, ErrNoCommitDate) {
				t.Errorf("want an unreadable answer, not a missing date, got %v", err)
			}
		})
	}
}
