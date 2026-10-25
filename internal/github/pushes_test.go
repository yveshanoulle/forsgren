package github

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"testing"
)

const activityPath = "/repos/acme/app/activity"

// activities is BranchActivities of acme/app's main from since on the fake.
func activities(t *testing.T, f *fakeGitHub, maxPages int) ([]Activity, bool, error) {
	t.Helper()
	return f.client(t, maxPages).BranchActivities(context.Background(), "acme/app", "main", since)
}

// TestBranchActivitiesReadsPushesMergesAndForcePushesNewestFirst
// (forsgren#397, step 2): GET /repos/{o}/{r}/activity for refs/heads/main,
// following Link rel="next"; a push, a pull request merge and a force push
// are read with their time in UTC, their two SHAs and the actor's account
// type, never a login; a branch creation is left out.
func TestBranchActivitiesReadsPushesMergesAndForcePushesNewestFirst(t *testing.T) {
	f := newFake(t)
	f.on(activityPath, reply{header: next(activityPath, "2"), body: fixture(t, "activity.json")})
	f.onPage(activityPath, "2", reply{body: "[]"})
	got, truncated, err := activities(t, f, DefaultMaxPages)
	wantRead(t, truncated, false, err)
	want := []Activity{
		{ActivityPush, utcOf(t, "2026-09-03T10:00:00Z"), shaBase, shaMiddle, "User"},
		{ActivityPRMerge, utcOf(t, "2026-09-03T06:00:00Z"), shaMiddle, shaHead, "User"},
		{ActivityForcePush, utcOf(t, "2026-09-02T09:00:00Z"), shaHead, shaLater, "Bot"},
		{ActivityPush, utcOf(t, "2026-08-15T09:00:00Z"), shaBase, "6666666666666666666666666666666666666666", ""},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
	wantRequests(t, f, 2)
	query := f.seen()[0].URL.Query()
	if query.Get("ref") != "refs/heads/main" || query.Get("per_page") != "100" {
		t.Errorf("want ref=refs/heads/main and 100 per page, got %v", query)
	}
}

// wantRead fails unless a read ended with the truncated flag want and no
// error.
func wantRead(t *testing.T, truncated, want bool, err error) {
	t.Helper()
	if err != nil || truncated != want {
		t.Fatalf("want an ended read with truncated=%v, got truncated=%v, %v", want, truncated, err)
	}
}

// wantRequests fails unless the fake got n requests.
func wantRequests(t *testing.T, f *fakeGitHub, n int) {
	t.Helper()
	if got := len(f.seen()); got != n {
		t.Fatalf("want %d requests, got %d", n, got)
	}
}

// TestBranchActivitiesStopAtTheFirstOneBeforeSince: newest first, so an
// activity before since ends the read and the next page is not asked for.
func TestBranchActivitiesStopAtTheFirstOneBeforeSince(t *testing.T) {
	f := newFake(t)
	old := `{"before": "` + shaBase + `", "after": "` + shaHead + `", "timestamp": "2026-07-30T09:00:00Z", ` +
		`"activity_type": "push", "actor": {"type": "User"}}`
	f.on(activityPath, reply{header: next(activityPath, "2"), body: "[" + old + "]"})
	got, truncated, err := activities(t, f, DefaultMaxPages)
	wantRead(t, truncated, false, err)
	wantRequests(t, f, 1)
	if len(got) != 0 {
		t.Errorf("want nothing, got %v", got)
	}
}

// TestBranchActivitiesSayTheyStoppedAtThePageLimit.
func TestBranchActivitiesSayTheyStoppedAtThePageLimit(t *testing.T) {
	f := newFake(t)
	f.on(activityPath, reply{header: next(activityPath, "2"), body: fixture(t, "activity.json")})
	got, truncated, err := activities(t, f, 1)
	wantRead(t, truncated, true, err)
	if len(got) != 4 {
		t.Errorf("want the first page's 4, got %d", len(got))
	}
}

// TestARefusedPushReadNamesTheTokenAndItsFix (forsgren#318): as for the pull
// request read, a 403 names the token that was refused and where it gets
// Contents: read, the job's permissions or its own repository permission.
func TestARefusedPushReadNamesTheTokenAndItsFix(t *testing.T) {
	for _, c := range []deniedCase{
		{"GITHUB_TOKEN", "GITHUB_TOKEN was refused: the job's token needs contents: read " +
			"in the permissions of the workflow job", "Contents: Read"},
		{"FORSGREN_TOKEN", "FORSGREN_TOKEN was refused: it needs the repository permission " +
			"Contents: Read", "contents: read"},
	} {
		t.Run(c.tokenName, func(t *testing.T) {
			f := newFake(t)
			f.on(activityPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
			client := f.client(t, DefaultMaxPages).WithTokenName(c.tokenName)
			_, _, err := client.BranchActivities(context.Background(), "acme/app", "main", since)
			wantDeniedFix(t, c, err, ErrPushesDenied)
		})
	}
}

// TestBranchActivitiesNameTheMissingPermission: a 403 is the token without
// Contents: read, ErrAccess and ErrPushesDenied naming it.
func TestBranchActivitiesNameTheMissingPermission(t *testing.T) {
	f := newFake(t)
	f.on(activityPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
	_, _, err := activities(t, f, DefaultMaxPages)
	wantError(t, err, ErrPushesDenied, "acme/app", "Contents: Read")
	wantError(t, err, ErrAccess)
	if errors.Is(err, ErrPullRequestsDenied) {
		t.Errorf("want no pull request permission named, got %v", err)
	}
}

// TestBranchActivitiesKeepTheRateLimit: a 403 with no request left stays
// ErrRateLimit, never ErrPushesDenied.
func TestBranchActivitiesKeepTheRateLimit(t *testing.T) {
	f := newFake(t)
	f.on(activityPath, reply{status: 403, header: http.Header{"X-Ratelimit-Remaining": {"0"}},
		body: `{"message":"API rate limit exceeded"}`})
	_, _, err := activities(t, f, DefaultMaxPages)
	wantError(t, err, ErrRateLimit)
	if errors.Is(err, ErrPushesDenied) {
		t.Errorf("want no missing permission for a rate limit, got %v", err)
	}
}

// TestBranchActivitiesRefuseAnItemWithoutATimeOrSHA: a push with no
// timestamp, or a SHA that is none, is ErrAnswer.
func TestBranchActivitiesRefuseAnItemWithoutATimeOrSHA(t *testing.T) {
	for name, body := range map[string]string{
		"no time": `[{"before": "` + shaBase + `", "after": "` + shaHead + `", "activity_type": "push"}]`,
		"bad sha": `[{"before": "x", "after": "` + shaHead + `", "timestamp": "2026-09-03T10:00:00Z", ` +
			`"activity_type": "push"}]`,
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(activityPath, reply{body: body})
			_, _, err := activities(t, f, DefaultMaxPages)
			wantError(t, err, ErrAnswer, "acme/app: ")
		})
	}
}
