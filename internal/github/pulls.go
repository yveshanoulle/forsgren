package github

import (
	"context"
	"errors"
)

// PullRequest is one open pull request: its number, its author's login and
// its head branch. Nothing else is read: no title, no body, no repository
// name for the page.
type PullRequest struct {
	Number int64
	Author string
	Branch string
}

// OpenPullRequests lists the open pull requests of repo: GET
// /repos/{owner}/{repo}/pulls?state=open, every page up to the limit, and
// says whether it stopped there. A 403 is the token missing
// pull-requests: read, ErrAccess naming that permission.
// STUB (forsgren#40 step 5 red): the green implements it.
func (c *Client) OpenPullRequests(ctx context.Context, repo string) ([]PullRequest, bool, error) {
	return nil, false, errors.New("OpenPullRequests is not implemented")
}

// ForsgrenBump is the number of the open pull request, among prs, that
// Dependabot opened to bump forsgren's pin to exactly version, and false
// when there is none.
// STUB (forsgren#40 step 5 red): the green implements it.
func ForsgrenBump(prs []PullRequest, version string) (int64, bool) { return 0, false }
