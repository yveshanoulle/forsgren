package github

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"strconv"
	"testing"
	"time"
)

const closedPullsPath = "/repos/acme/app/pulls"

// closedItem is one item of a page of closed pull requests, created on
// 2026-07-01: numbered number, from branch ref, updated at updated, merged at
// merged (a JSON value: "null" is closed without a merge) with the merge
// commit sha (a JSON value too).
type closedItem struct {
	number                    int
	ref, updated, merged, sha string
}

// json is the item as GitHub answers it, with fields that are not read.
func (i closedItem) json() string {
	return `{"number": ` + strconv.Itoa(i.number) + `, "state": "closed", "title": "not read", ` +
		`"user": {"login": "acme-dev", "type": "User"}, "head": {"ref": "` + i.ref + `", "sha": "` + shaHead + `"}, ` +
		`"created_at": "2026-07-01T08:00:00Z", "updated_at": "` + i.updated + `", ` +
		`"merged_at": ` + i.merged + `, "merge_commit_sha": ` + i.sha + `}`
}

// merged45 is pull request 45, merged on 2026-08-02, in the window from since.
var merged45 = closedItem{45, "fix/login", "2026-08-02T09:00:00Z", `"2026-08-02T08:00:00Z"`, `"` + shaBase + `"`}

// wantClosedQuery holds the first of requests to state=closed,
// sort=updated, direction=desc and 100 per page.
func wantClosedQuery(t *testing.T, requests []*http.Request) {
	t.Helper()
	query := requests[0].URL.Query()
	want := map[string]string{"state": "closed", "sort": "updated", "direction": "desc", "per_page": "100"}
	for key, value := range want {
		if query.Get(key) != value {
			t.Errorf("want %s=%s, got %q", key, value, query.Get(key))
		}
	}
}

// utcOf is the UTC time of an RFC 3339 text of the tests.
func utcOf(t *testing.T, text string) time.Time {
	t.Helper()
	v, err := time.Parse(time.RFC3339, text)
	if err != nil {
		t.Fatal(err)
	}
	return v.UTC()
}

// closedPulls is ClosedPullRequests of acme/app from since on the fake.
func closedPulls(t *testing.T, f *fakeGitHub, maxPages int) ([]ClosedPullRequest, bool, error) {
	t.Helper()
	return f.client(t, maxPages).ClosedPullRequests(context.Background(), "acme/app", since)
}

// TestClosedPullRequestsReadsTheClosedOnesNewestUpdatedFirst (forsgren#255,
// step 1): GET /repos/{o}/{r}/pulls with state=closed, sort=updated,
// direction=desc, following Link rel="next"; each pull request's number,
// created, merged and updated time in UTC, its merge commit, and its
// author's account type (forsgren#345). One closed without a merge is read
// too, with no merge time and no merge commit, never the test merge GitHub
// still names for it.
func TestClosedPullRequestsReadsTheClosedOnesNewestUpdatedFirst(t *testing.T) {
	f := newFake(t)
	f.on(closedPullsPath, reply{header: next(closedPullsPath, "2"), body: fixture(t, "closed-pulls.json")})
	f.onPage(closedPullsPath, "2", reply{body: "[" + merged45.json() + "]"})
	got, truncated, err := closedPulls(t, f, DefaultMaxPages)
	if err != nil || truncated {
		t.Fatalf("want the closed pull requests, got truncated=%v, %v", truncated, err)
	}
	want := []ClosedPullRequest{
		{Number: 48, CreatedAt: utcOf(t, "2026-09-20T08:00:00Z"),
			MergedAt: utcOf(t, "2026-09-22T08:30:00Z"), MergeCommit: "4848484848484848484848484848484848484848",
			UpdatedAt: utcOf(t, "2026-09-22T11:00:00Z"), UserType: "User"},
		{Number: 47, CreatedAt: utcOf(t, "2026-09-19T08:00:00Z"),
			UpdatedAt: utcOf(t, "2026-09-21T09:00:00Z"), UserType: "Bot"},
		{Number: 45, CreatedAt: utcOf(t, "2026-07-01T08:00:00Z"),
			MergedAt: utcOf(t, "2026-08-02T08:00:00Z"), MergeCommit: shaBase, UpdatedAt: utcOf(t, "2026-08-02T09:00:00Z"),
			UserType: "User"},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
	requests := f.seen()
	if len(requests) != 2 {
		t.Fatalf("want two pages read, got %d requests", len(requests))
	}
	wantClosedQuery(t, requests)
}

// TestClosedPullRequestsStopAtTheFirstOneUpdatedBeforeSince: the list is
// newest updated first, so a pull request updated before since ends the read:
// it is left out and the next page is never asked for.
func TestClosedPullRequestsStopAtTheFirstOneUpdatedBeforeSince(t *testing.T) {
	f := newFake(t)
	old := closedItem{44, "fix/old", "2026-07-30T09:00:00Z", `"2026-07-30T08:00:00Z"`, `"` + shaHead + `"`}
	f.on(closedPullsPath, reply{header: next(closedPullsPath, "2"), body: "[" + merged45.json() + ", " + old.json() + "]"})
	f.onPage(closedPullsPath, "2", reply{body: "[]"})
	got, truncated, err := closedPulls(t, f, DefaultMaxPages)
	if err != nil || truncated {
		t.Fatalf("want the read to end at the old one, got truncated=%v, %v", truncated, err)
	}
	if len(got) != 1 || got[0].Number != 45 {
		t.Errorf("want pull request 45 alone, got %+v", got)
	}
	if n := len(f.seen()); n != 1 {
		t.Errorf("want one request, got %d", n)
	}
}

// TestClosedPullRequestsSayTheyStoppedAtThePageLimit: a next page left
// unread at the limit is a cut list.
func TestClosedPullRequestsSayTheyStoppedAtThePageLimit(t *testing.T) {
	f := newFake(t)
	f.on(closedPullsPath, reply{header: next(closedPullsPath, "2"), body: fixture(t, "closed-pulls.json")})
	got, truncated, err := closedPulls(t, f, 1)
	if err != nil {
		t.Fatal(err)
	}
	if !truncated || len(got) != 2 {
		t.Errorf("want the first page's 2 and a cut list, got %d, truncated=%v", len(got), truncated)
	}
}

// TestClosedPullRequestsNameTheMissingPermission: a 403 is the token without
// pull-requests: read, ErrAccess and ErrPullRequestsDenied naming it, as for
// the open pull requests (explainDenied).
func TestClosedPullRequestsNameTheMissingPermission(t *testing.T) {
	f := newFake(t)
	f.on(closedPullsPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
	_, _, err := closedPulls(t, f, DefaultMaxPages)
	wantError(t, err, ErrPullRequestsDenied, "acme/app", "pull-requests: read")
	wantError(t, err, ErrAccess)
}

// TestClosedPullRequestsTellTheRateLimitFromTheMissingPermission: a 403 with
// no request left stays ErrRateLimit, never ErrPullRequestsDenied.
func TestClosedPullRequestsTellTheRateLimitFromTheMissingPermission(t *testing.T) {
	f := newFake(t)
	f.on(closedPullsPath, reply{status: 403, header: http.Header{"X-Ratelimit-Remaining": {"0"}},
		body: `{"message":"API rate limit exceeded"}`})
	_, _, err := closedPulls(t, f, DefaultMaxPages)
	wantError(t, err, ErrRateLimit, "acme/app")
	if errors.Is(err, ErrPullRequestsDenied) {
		t.Errorf("want no missing permission for a rate limit, got %v", err)
	}
}

// TestClosedPullRequestsRefuseAnAnswerTheyCannotStore: a pull request with no
// number, no created or updated time, or merged without a merge commit SHA,
// is ErrAnswer naming the path, never a pull request with a hole in it.
func TestClosedPullRequestsRefuseAnAnswerTheyCannotStore(t *testing.T) {
	with := func(change func(*closedItem)) string {
		item := merged45
		change(&item)
		return item.json()
	}
	for name, item := range map[string]string{
		"no number":       with(func(i *closedItem) { i.number = 0 }),
		"no updated time": with(func(i *closedItem) { i.updated = "0001-01-01T00:00:00Z" }),
		"no created time": `{"number": 45, "head": {"ref": "fix/login"}, ` +
			`"updated_at": "2026-08-02T09:00:00Z", "merged_at": null}`,
		"merged, no SHA":  with(func(i *closedItem) { i.sha = "null" }),
		"merged, bad SHA": with(func(i *closedItem) { i.sha = `"not-a-sha"` }),
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(closedPullsPath, reply{body: "[" + item + "]"})
			_, _, err := closedPulls(t, f, DefaultMaxPages)
			wantError(t, err, ErrAnswer, "acme/app: ", closedPullsPath, "pull request")
		})
	}
}

// TestClosedPullRequestsReadOneWithoutAHeadBranch (forsgren#320, decision
// #322): the head branch is not read, so a pull request whose head.ref is
// empty, or that has no head at all, is read like any other.
func TestClosedPullRequestsReadOneWithoutAHeadBranch(t *testing.T) {
	noRef := merged45
	noRef.ref = ""
	for name, c := range map[string]struct{ item, userType string }{
		"an empty head.ref": {noRef.json(), "User"},
		"no head": {`{"number": 45, "created_at": "2026-07-01T08:00:00Z", "updated_at": "2026-08-02T09:00:00Z", ` +
			`"merged_at": "2026-08-02T08:00:00Z", "merge_commit_sha": "` + shaBase + `"}`, ""},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(closedPullsPath, reply{body: "[" + c.item + "]"})
			got, _, err := closedPulls(t, f, DefaultMaxPages)
			want := []ClosedPullRequest{{Number: 45, CreatedAt: utcOf(t, "2026-07-01T08:00:00Z"),
				MergedAt: utcOf(t, "2026-08-02T08:00:00Z"), MergeCommit: shaBase, UpdatedAt: utcOf(t, "2026-08-02T09:00:00Z"),
				UserType: c.userType}}
			if !slices.Equal(got, want) {
				t.Errorf("want %+v, got %+v (%v)", want, got, err)
			}
		})
	}
}
