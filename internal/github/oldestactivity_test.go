package github

import (
	"context"
	"testing"
	"time"
)

// oldestActivityBody is one page of the activity list oldest first: the
// branch creation, then a push and a pull request merge.
const oldestActivityBody = `[
 {"timestamp": "2025-12-09T16:46:10Z", "activity_type": "branch_creation",
  "before": "0000000000000000000000000000000000000000", "after": "1111111111111111111111111111111111111111"},
 {"timestamp": "2025-12-09T16:49:29Z", "activity_type": "push",
  "before": "1111111111111111111111111111111111111111", "after": "2222222222222222222222222222222222222222"},
 {"timestamp": "2025-12-10T08:00:00Z", "activity_type": "pr_merge",
  "before": "2222222222222222222222222222222222222222", "after": "3333333333333333333333333333333333333333"}
]`

// oldest is OldestActivity of acme/app's main on the fake.
func oldest(t *testing.T, f *fakeGitHub) (time.Time, error) {
	t.Helper()
	return f.client(t, DefaultMaxPages).OldestActivity(context.Background(), "acme/app", "main")
}

// TestOldestActivityReadsOnePageOldestFirst (forsgren#583, step 1): one GET
// of the activity list with direction=asc gives the time of the oldest push,
// pull request merge or force push, the branch creation left out; a next page
// is not asked for.
func TestOldestActivityReadsOnePageOldestFirst(t *testing.T) {
	f := newFake(t)
	f.on(activityPath, reply{header: next(activityPath, "2"), body: oldestActivityBody})
	got, err := oldest(t, f)
	if err != nil || !got.Equal(utcOf(t, "2025-12-09T16:49:29Z")) {
		t.Errorf("want the push of 2025-12-09T16:49:29Z, got %v, %v", got, err)
	}
	wantRequests(t, f, 1)
	query := f.seen()[0].URL.Query()
	if query.Get("direction") != "asc" || query.Get("ref") != "refs/heads/main" {
		t.Errorf("want direction=asc for refs/heads/main, got %v", query)
	}
}

// TestOldestActivityOfAnEmptyListIsNone: no push at all is the zero time.
func TestOldestActivityOfAnEmptyListIsNone(t *testing.T) {
	f := newFake(t)
	f.on(activityPath, reply{body: "[]"})
	if got, err := oldest(t, f); err != nil || !got.IsZero() {
		t.Errorf("want none, got %v, %v", got, err)
	}
}

// TestOldestActivityNamesTheMissingPermission: a 403 is ErrPushesDenied, as
// for BranchActivities.
func TestOldestActivityNamesTheMissingPermission(t *testing.T) {
	f := newFake(t)
	f.on(activityPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
	_, err := oldest(t, f)
	wantError(t, err, ErrPushesDenied, "acme/app")
}
