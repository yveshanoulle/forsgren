package github

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"strconv"
	"testing"
)

const pullsPath = "/repos/acme/data/pulls"

// pullItem is one item of a page of pull requests: numbered number, opened
// by login, from the head branch.
func pullItem(number int, login, branch string) string {
	return `{"number": ` + strconv.Itoa(number) + `, "state": "open", "title": "not read", ` +
		`"user": {"login": "` + login + `", "type": "Bot"}, "head": {"ref": "` + branch + `"}}`
}

// dependabotBranch is the head branch Dependabot gives forsgren's pin bump
// to version (seen on a downstream repository's pull requests #1 to #3).
func dependabotBranch(version string) string {
	return "dependabot/github_actions/yveshanoulle/forsgren/dot-github/workflows/metrics.yml-" + version
}

// TestOpenPullRequestsReadsEveryPageOfTheOpenOnes (forsgren#40, step 5):
// GET /repos/{o}/{r}/pulls with state=open, following Link rel="next"; each
// pull request's number, author login and head branch.
func TestOpenPullRequestsReadsEveryPageOfTheOpenOnes(t *testing.T) {
	f := newFake(t)
	first := pullItem(7, "dependabot[bot]", dependabotBranch("0.0.10"))
	f.on(pullsPath, reply{header: next(pullsPath, "2"), body: "[" + first + "]"})
	f.onPage(pullsPath, "2", reply{body: "[" + pullItem(5, "acme-dev", "feature/x") + "]"})
	got, truncated, err := f.client(t, DefaultMaxPages).OpenPullRequests(context.Background(), "acme/data")
	if err != nil || truncated {
		t.Fatalf("want the pull requests, got truncated=%v, %v", truncated, err)
	}
	want := []PullRequest{
		{Number: 7, Author: "dependabot[bot]", Branch: dependabotBranch("0.0.10")},
		{Number: 5, Author: "acme-dev", Branch: "feature/x"},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %+v,\n got %+v", want, got)
	}
	if state := f.seen()[0].URL.Query().Get("state"); state != "open" {
		t.Errorf("want state=open, got %q", state)
	}
}

// TestOpenPullRequestsNamesTheMissingPermission (forsgren#40, step 5): a 403
// is the job token without pull-requests: read, an access error that says
// so, not FORSGREN_TOKEN's access.
func TestOpenPullRequestsNamesTheMissingPermission(t *testing.T) {
	f := newFake(t)
	f.on(pullsPath, reply{status: 403, body: `{"message":"Resource not accessible by integration"}`})
	_, _, err := f.client(t, DefaultMaxPages).OpenPullRequests(context.Background(), "acme/data")
	wantError(t, err, ErrAccess, "acme/data", "pull-requests: read")
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

// TestForsgrenBumpFindsTheDependabotPullRequestForExactlyThatVersion
// (forsgren#40, step 5). The rule: an open pull request by dependabot[bot]
// whose head branch is dependabot/github_actions/yveshanoulle/forsgren/ plus
// a path and "metrics.yml-" plus exactly the version. Titles are not read
// (an installation can prefix them), nor is any older or newer version; of
// several matches the highest number wins.
func TestForsgrenBumpFindsTheDependabotPullRequestForExactlyThatVersion(t *testing.T) {
	const bot = "dependabot[bot]"
	bump := func(number int64, version string) PullRequest {
		return PullRequest{Number: number, Author: bot, Branch: dependabotBranch(version)}
	}
	other := "dependabot/github_actions/actions/checkout-0.0.10"
	npm := "dependabot/npm_and_yarn/yveshanoulle/forsgren/metrics.yml-0.0.10"
	cases := []struct {
		name    string
		prs     []PullRequest
		version string
		want    int64
	}{
		{"the bump", []PullRequest{bump(7, "0.0.10")}, "0.0.10", 7},
		{"among others", []PullRequest{{3, "acme-dev", "feature/x"}, bump(7, "0.0.10")}, "0.0.10", 7},
		{"the highest number of two", []PullRequest{bump(6, "0.0.10"), bump(8, "0.0.10")}, "0.0.10", 8},
		{"an older version", []PullRequest{bump(7, "0.0.9")}, "0.0.10", 0},
		{"a version that only ends alike", []PullRequest{bump(7, "10.0.10")}, "0.0.10", 0},
		{"a version that only starts alike", []PullRequest{bump(7, "0.0.100")}, "0.0.10", 0},
		{"a person on that branch", []PullRequest{{7, "acme-dev", dependabotBranch("0.0.10")}}, "0.0.10", 0},
		{"another action", []PullRequest{{7, bot, other}}, "0.0.10", 0},
		{"another ecosystem", []PullRequest{{7, bot, npm}}, "0.0.10", 0},
		{"no pull request", nil, "0.0.10", 0},
		{"no version", []PullRequest{bump(7, "0.0.10")}, "", 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, ok := ForsgrenBump(c.prs, c.version)
			if got != c.want || ok != (c.want != 0) {
				t.Errorf("ForsgrenBump(%+v, %q) = %d, %v, want %d", c.prs, c.version, got, ok, c.want)
			}
		})
	}
}
