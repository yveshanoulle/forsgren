package github

import (
	"context"
	"slices"
	"testing"
)

// afterLink is a Link header whose rel="next" continues the activity list
// after cursor.
func afterLink(cursor string) map[string][]string {
	return map[string][]string{"Link": {`<{base}` + activityPath + `?after=` + cursor + `&per_page=100>; rel="next"`}}
}

// activityPageOf is ActivityPage of acme/app's main from cursor on the fake.
func activityPageOf(t *testing.T, f *fakeGitHub, cursor string) ([]Activity, string, error) {
	t.Helper()
	page, err := f.client(t, DefaultMaxPages).ActivityPage(context.Background(), "acme/app", "main", cursor)
	return page.Activities, page.Next, err
}

// TestActivityPageSaysWhenItHoldsTheBranchCreation (forsgren#583, step 3): a
// page with the creation of the branch says so, the end of a complete list;
// one without does not.
func TestActivityPageSaysWhenItHoldsTheBranchCreation(t *testing.T) {
	f := newFake(t)
	f.onPage(activityPath, "c1", reply{body: fixture(t, "activity.json")})
	f.onPage(activityPath, "c2", reply{body: "[]"})
	client := f.client(t, DefaultMaxPages)
	for cursor, want := range map[string]bool{"c1": true, "c2": false} {
		page, err := client.ActivityPage(context.Background(), "acme/app", "main", cursor)
		if err != nil || page.Created != want {
			t.Errorf("after %s: want Created %v, got %+v, %v", cursor, want, page, err)
		}
	}
}

// TestActivityPageReadsOnePageAndGivesTheNextCursor (forsgren#583, step 2):
// one GET of the activity list after the cursor, the pushes, merges and force
// pushes of that page newest first, and the after cursor of the next page;
// none when the list ends.
func TestActivityPageReadsOnePageAndGivesTheNextCursor(t *testing.T) {
	f := newFake(t)
	f.onPage(activityPath, "c1", reply{header: afterLink("c2"), body: fixture(t, "activity.json")})
	got, next, err := activityPageOf(t, f, "c1")
	if err != nil {
		t.Fatal(err)
	}
	if next != "c2" || len(got) != 4 {
		t.Fatalf("want 4 activities and the cursor c2, got %d, %q", len(got), next)
	}
	if !slices.IsSortedFunc(got, func(a, b Activity) int { return b.PushedAt.Compare(a.PushedAt) }) {
		t.Errorf("want newest first, got %+v", got)
	}
	wantAfterAsked(t, f, "c1")
}

// wantAfterAsked fails unless the fake got one request, for the page of main
// after cursor.
func wantAfterAsked(t *testing.T, f *fakeGitHub, cursor string) {
	t.Helper()
	wantRequests(t, f, 1)
	if q := f.seen()[0].URL.Query(); q.Get("after") != cursor || q.Get("ref") != "refs/heads/main" {
		t.Errorf("want after=%s for refs/heads/main, got %v", cursor, q)
	}
}

// TestActivityPageAtTheEndHasNoNextCursor: no next link, no cursor.
func TestActivityPageAtTheEndHasNoNextCursor(t *testing.T) {
	f := newFake(t)
	f.onPage(activityPath, "c2", reply{body: "[]"})
	if _, next, err := activityPageOf(t, f, "c2"); err != nil || next != "" {
		t.Errorf("want no next cursor at the end, got %q, %v", next, err)
	}
}

// TestActivityPageWithoutACursorStartsAtTheTop: an empty cursor asks for the
// newest page, without an after parameter.
func TestActivityPageWithoutACursorStartsAtTheTop(t *testing.T) {
	f := newFake(t)
	f.on(activityPath, reply{body: "[]"})
	if _, _, err := activityPageOf(t, f, ""); err != nil {
		t.Fatal(err)
	}
	if q := f.seen()[0].URL.Query(); q.Has("after") {
		t.Errorf("want no after parameter, got %v", q)
	}
}

// TestActivityPageNamesTheMissingPermission: a 403 is ErrPushesDenied.
func TestActivityPageNamesTheMissingPermission(t *testing.T) {
	f := newFake(t)
	f.on(activityPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
	_, _, err := activityPageOf(t, f, "")
	wantError(t, err, ErrPushesDenied, "acme/app")
}
