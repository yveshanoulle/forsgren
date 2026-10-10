package github

import (
	"context"
	"net/url"
	"slices"
	"testing"
	"time"
)

// TestIssuesReadsEveryIssueWithoutPullRequests (forsgren#76, step 1): GET
// /repos/{o}/{r}/issues with state=all, since and 100 per page and no labels
// filter; a pull request is not an issue. Each issue keeps its number,
// created_at, closed_at (zero while open), state and state_reason ("" when
// null or absent, as on an old issue).
func TestIssuesReadsEveryIssueWithoutPullRequests(t *testing.T) {
	f := newFake(t)
	f.on(issuesPath, reply{body: fixture(t, "all-issues.json")})
	got, truncated, err := f.client(t, DefaultMaxPages).Issues(context.Background(), "acme/app", since)
	if err != nil || truncated {
		t.Fatalf("want the issues, got truncated=%v, %v", truncated, err)
	}
	day := func(d, h, m int) time.Time { return at(d, h, m, 0) }
	want := []RepoIssue{
		{Number: 56, CreatedAt: day(24, 10, 0), State: "open"},
		{Number: 55, CreatedAt: day(23, 9, 0), ClosedAt: day(24, 12, 30), State: "closed", StateReason: "completed"},
		{Number: 54, CreatedAt: day(22, 9, 0), ClosedAt: day(22, 18, 0), State: "closed", StateReason: "not_planned"},
		{Number: 53, CreatedAt: day(21, 9, 0), ClosedAt: day(21, 10, 15), State: "closed", StateReason: "duplicate"},
		{Number: 12, CreatedAt: time.Date(2024, 3, 1, 8, 0, 0, 0, time.UTC), ClosedAt: time.Date(2024, 3, 5, 8, 0, 0, 0, time.UTC), State: "closed"},
		{Number: 40, CreatedAt: day(10, 8, 0), State: "open", StateReason: "reopened"},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
	wantQuery(t, f, url.Values{"state": {"all"}, "since": {"2026-08-01T00:00:00Z"}, "per_page": {"100"}})
	if _, has := f.seen()[0].URL.Query()["labels"]; has {
		t.Errorf("want no labels parameter, got %q", f.seen()[0].URL.RawQuery)
	}
}
