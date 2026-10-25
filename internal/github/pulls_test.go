package github

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"testing"
)

const pullsPath = "/repos/acme/data/pulls"

// pullItem is one item of a page of pull requests: numbered number, opened
// by login, with a head branch that is not read.
func pullItem(number int, login string) string {
	return `{"number": ` + strconv.Itoa(number) + `, "state": "open", "title": "not read", ` +
		`"user": {"login": "` + login + `", "type": "Bot"}, "head": {"ref": "not-read"}}`
}

// TestOpenPullRequestsReadsEveryPageOfTheOpenOnes (forsgren#40, step 5):
// GET /repos/{o}/{r}/pulls with state=open, following Link rel="next"; each
// pull request's number and author login.
func TestOpenPullRequestsReadsEveryPageOfTheOpenOnes(t *testing.T) {
	f := newFake(t)
	first := pullItem(7, "dependabot[bot]")
	f.on(pullsPath, reply{header: next(pullsPath, "2"), body: "[" + first + "]"})
	f.onPage(pullsPath, "2", reply{body: "[" + pullItem(5, "acme-dev") + "]"})
	got, truncated, err := f.client(t, DefaultMaxPages).OpenPullRequests(context.Background(), "acme/data")
	if err != nil || truncated {
		t.Fatalf("want the pull requests, got truncated=%v, %v", truncated, err)
	}
	want := []PullRequest{
		{Number: 7, Author: "dependabot[bot]"},
		{Number: 5, Author: "acme-dev"},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
	if state := f.seen()[0].URL.Query().Get("state"); state != "open" {
		t.Errorf("want state=open, got %q", state)
	}
}

// deniedCase is a refused read made with the token tokenName: the message
// wants the fix of that token (want) and never the other's (wantNot).
type deniedCase struct{ tokenName, want, wantNot string }

// wantDeniedFix fails when err does not name the fix of c's token.
func wantDeniedFix(t *testing.T, c deniedCase, err, denied error) {
	t.Helper()
	wantError(t, err, ErrAccess, c.want)
	if !errors.Is(err, denied) || strings.Contains(err.Error(), c.wantNot) {
		t.Errorf("want %v and no %q, got %v", denied, c.wantNot, err)
	}
}

// TestARefusedPullRequestReadNamesTheTokenAndItsFix (forsgren#318, the
// message of forsgren#40 step 5): a 403 names the token that was refused and
// the permission that token needs, where it is set: the job's permissions for
// GITHUB_TOKEN, the token's own repository permission for FORSGREN_TOKEN, a
// fine-grained token. Never the other token's fix.
func TestARefusedPullRequestReadNamesTheTokenAndItsFix(t *testing.T) {
	for _, c := range []deniedCase{
		{"GITHUB_TOKEN", "GITHUB_TOKEN was refused: the job's token needs pull-requests: read " +
			"in the permissions of the workflow job", "Pull requests: Read"},
		{"FORSGREN_TOKEN", "FORSGREN_TOKEN was refused: it needs the repository permission " +
			"Pull requests: Read", "pull-requests: read"},
	} {
		t.Run(c.tokenName, func(t *testing.T) {
			f := newFake(t)
			f.on(pullsPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
			client := f.client(t, DefaultMaxPages).WithTokenName(c.tokenName)
			_, _, err := client.OpenPullRequests(context.Background(), "acme/data")
			wantDeniedFix(t, c, err, ErrPullRequestsDenied)
		})
	}
}

// TestOpenPullRequestsNamesTheMissingPermission (forsgren#40, step 5): a 403
// is the job token without pull-requests: read, an access error that says
// so, not FORSGREN_TOKEN's access.
func TestOpenPullRequestsNamesTheMissingPermission(t *testing.T) {
	f := newFake(t)
	f.on(pullsPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
	_, _, err := f.client(t, DefaultMaxPages).OpenPullRequests(context.Background(), "acme/data")
	wantError(t, err, ErrAccess, "acme/data", "Pull requests: Read")
}

// TestOpenPullRequestsTellsTheRateLimitFromTheMissingPermission
// (forsgren#40, review of step 7): a 403 with no request left is GitHub's
// rate limit, ErrRateLimit, never ErrPullRequestsDenied, so nobody is asked
// to grant a permission the token already has.
func TestOpenPullRequestsTellsTheRateLimitFromTheMissingPermission(t *testing.T) {
	f := newFake(t)
	f.on(pullsPath, reply{status: 403, header: http.Header{"X-Ratelimit-Remaining": {"0"}},
		body: `{"message":"API rate limit exceeded"}`})
	_, _, err := f.client(t, DefaultMaxPages).OpenPullRequests(context.Background(), "acme/data")
	wantError(t, err, ErrRateLimit, "acme/data")
	if errors.Is(err, ErrPullRequestsDenied) {
		t.Errorf("want no missing permission for a rate limit, got %v", err)
	}
}

// TestIsRefusedIsTrueOnlyForAForbiddenThatIsNotTheRateLimit (forsgren#73,
// step 14): the 403 of an issue write that is not the rate limit.
func TestIsRefusedIsTrueOnlyForAForbiddenThatIsNotTheRateLimit(t *testing.T) {
	cases := []struct {
		name   string
		status int
		header http.Header
		want   bool
	}{
		{"refused 403", 403, nil, true},
		{"rate-limited 403", 403, http.Header{"X-Ratelimit-Remaining": {"0"}}, false},
		{"500", 500, nil, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := newFake(t)
			f.on("/repos/acme/data/issues", reply{status: c.status, header: c.header, body: `{"message":"no"}`})
			text := IssueText{Title: "t", Body: "b"}
			_, err := f.client(t, DefaultMaxPages).CreateIssue(context.Background(), "acme/data", text, nil)
			if got := IsRefused(err); got != c.want {
				t.Errorf("IsRefused(%v) = %v, want %v", err, got, c.want)
			}
		})
	}
	if IsRefused(nil) {
		t.Error("IsRefused(nil) = true, want false")
	}
}

// TestDependabotPullsAreTheOnesDependabotOpened (forsgren#42): the pull
// requests of dependabot[bot], in their order.
func TestDependabotPullsAreTheOnesDependabotOpened(t *testing.T) {
	prs := []PullRequest{
		{Number: 3, Author: "acme-dev"},
		{Number: 7, Author: "dependabot[bot]"},
		{Number: 9, Author: "dependabot[bot]"},
	}
	var numbers []int64
	for _, p := range DependabotPulls(prs) {
		numbers = append(numbers, p.Number)
	}
	if !slices.Equal(numbers, []int64{7, 9}) {
		t.Errorf("want pull requests 7 and 9, got %v", numbers)
	}
	if got := DependabotPulls(nil); got != nil {
		t.Errorf("want none, got %v", got)
	}
}
