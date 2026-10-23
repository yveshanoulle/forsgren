package github

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
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

// firstCommit is FirstCommitTime of pull request 45 of acme/app on the fake.
func firstCommit(t *testing.T, f *fakeGitHub, maxPages int) (time.Time, bool, error) {
	t.Helper()
	return f.client(t, maxPages).FirstCommitTime(context.Background(), "acme/app", 45)
}

// firstAnswer is the answer FirstCommitTime should give: the first commit
// time, an RFC 3339 text, and whether the answer is cut.
type firstAnswer struct {
	at  string
	cut bool
}

// wantFirstCommit holds FirstCommitTime of pull request 45 on the fake, read
// up to maxPages pages, to want, with no error.
func wantFirstCommit(t *testing.T, f *fakeGitHub, maxPages int, want firstAnswer) {
	t.Helper()
	got, truncated, err := firstCommit(t, f, maxPages)
	if err != nil {
		t.Fatalf("want the first commit time, got %v", err)
	}
	if truncated != want.cut {
		t.Errorf("want cut=%v, got cut=%v", want.cut, truncated)
	}
	if at := utcOf(t, want.at); got != at {
		t.Errorf("want %v, got %v", at, got)
	}
}

// TestFirstCommitTimeIsTheEarliestAuthorDate (forsgren#255, step 2): GET
// /repos/{o}/{r}/pulls/{n}/commits, 100 per page, following Link
// rel="next"; the first commit time is the earliest author date of every
// commit read, in UTC: not the first commit of the list (a rebase can put an
// older one later) and never a committer date, which a rebase moves.
func TestFirstCommitTimeIsTheEarliestAuthorDate(t *testing.T) {
	f := newFake(t)
	f.on(pullCommitsPath, reply{header: next(pullCommitsPath, "2"), body: fixture(t, "pull-commits.json")})
	f.onPage(pullCommitsPath, "2", reply{body: pullCommitItems(1, "2026-07-27T22:00:00+02:00")})
	wantFirstCommit(t, f, DefaultMaxPages, firstAnswer{"2026-07-27T20:00:00Z", false})
	requests := f.seen()
	if len(requests) != 2 {
		t.Fatalf("want two pages read, got %d requests", len(requests))
	}
	if n := requests[0].URL.Query().Get("per_page"); n != "100" {
		t.Errorf("want 100 per page, got %q", n)
	}
}

// TestFirstCommitTimeIsCutAtGitHubsCapOf250: GitHub lists at most 250
// commits of a pull request, so a list of 250 may have left the first commit
// out: it is a cut answer, never a complete one; 249 is complete.
func TestFirstCommitTimeIsCutAtGitHubsCapOf250(t *testing.T) {
	for last, cut := range map[int]bool{49: false, 50: true} {
		f := newFake(t)
		f.on(pullCommitsPath, reply{header: next(pullCommitsPath, "2"), body: pullCommitItems(100, "2026-07-30T08:00:00Z")})
		f.onPage(pullCommitsPath, "2", reply{header: next(pullCommitsPath, "3"),
			body: pullCommitItems(100, "2026-07-30T08:00:00Z")})
		f.onPage(pullCommitsPath, "3", reply{body: pullCommitItems(last, "2026-07-29T08:00:00Z")})
		t.Run(strconv.Itoa(200+last)+" commits", func(t *testing.T) {
			wantFirstCommit(t, f, DefaultMaxPages, firstAnswer{"2026-07-29T08:00:00Z", cut})
		})
	}
}

// TestFirstCommitTimeSaysItStoppedAtThePageLimit: a next page left unread
// at the limit is a cut answer.
func TestFirstCommitTimeSaysItStoppedAtThePageLimit(t *testing.T) {
	f := newFake(t)
	f.on(pullCommitsPath, reply{header: next(pullCommitsPath, "2"), body: fixture(t, "pull-commits.json")})
	wantFirstCommit(t, f, 1, firstAnswer{"2026-07-28T10:00:00Z", true})
}

// TestFirstCommitTimeNamesTheMissingPermission: a 403 is the token without
// pull-requests: read (explainDenied), a rate limit stays ErrRateLimit.
func TestFirstCommitTimeNamesTheMissingPermission(t *testing.T) {
	f := newFake(t)
	f.on(pullCommitsPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
	_, _, err := firstCommit(t, f, DefaultMaxPages)
	wantError(t, err, ErrPullRequestsDenied, "acme/app", pullCommitsPath, "pull-requests: read")
	wantError(t, err, ErrAccess)

	limited := newFake(t)
	limited.on(pullCommitsPath, reply{status: 403, header: http.Header{"Retry-After": {"60"}}})
	_, _, err = firstCommit(t, limited, DefaultMaxPages)
	wantError(t, err, ErrRateLimit, "acme/app")
	if strings.Contains(err.Error(), "pull-requests: read") {
		t.Errorf("want no missing permission for a rate limit, got %v", err)
	}
}

// TestFirstCommitTimeRefusesAnAnswerWithoutOne: a pull request with no
// commit, or a commit with no author date, has no first commit time: it is
// ErrAnswer naming the path, never a zero time.
func TestFirstCommitTimeRefusesAnAnswerWithoutOne(t *testing.T) {
	for name, body := range map[string]string{
		"no commits":     "[]",
		"no author date": `[{"sha": "` + shaHead + `", "commit": {"committer": {"date": "2026-08-02T07:00:00Z"}}}]`,
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(pullCommitsPath, reply{body: body})
			_, _, err := firstCommit(t, f, DefaultMaxPages)
			wantError(t, err, ErrAnswer, "acme/app: ", pullCommitsPath, "pull request 45")
		})
	}
}
