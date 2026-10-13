package github

import (
	"context"
	"net/url"
	"slices"
	"testing"
)

// bugIssuesBody is GitHub's answer to the bug label filter: two issues, one
// closed, and a pull request that carries the label too.
const bugIssuesBody = `[
  {"number": 31, "state": "open", "labels": [{"name": "bug"}], "created_at": "2026-09-20T09:00:00Z", "closed_at": null},
  {"number": 30, "state": "open", "labels": [{"name": "bug"}], "created_at": "2026-09-19T09:00:00Z", "closed_at": null,
   "pull_request": {"url": "https://api.github.com/repos/acme/app/pulls/30"}},
  {"number": 12, "state": "closed", "labels": [{"name": "bug"}], "created_at": "2026-08-01T09:00:00Z",
   "closed_at": "2026-08-02T09:00:00Z", "state_reason": "completed"}
]`

// TestBugIssuesAsksForTheBugLabelWithoutSince (forsgren#126): GET
// /repos/{o}/{r}/issues with labels=bug, state=all and 100 per page, no
// since; a pull request is not an issue.
func TestBugIssuesAsksForTheBugLabelWithoutSince(t *testing.T) {
	f := newFake(t)
	f.on(issuesPath, reply{body: bugIssuesBody})
	got, truncated, err := f.client(t, DefaultMaxPages).BugIssues(context.Background(), "acme/app")
	if err != nil || truncated {
		t.Fatalf("want the bug issues, got truncated=%v, %v", truncated, err)
	}
	if want := []int64{31, 12}; !slices.Equal(numbersOf(got), want) {
		t.Errorf("want the issues %v, the pull request left out, got %v", want, numbersOf(got))
	}
	wantQuery(t, f, url.Values{"labels": {"bug"}, "state": {"all"}, "per_page": {"100"}})
	wantNoParameter(t, f, "since")
}
