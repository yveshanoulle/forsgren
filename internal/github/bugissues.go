package github

import (
	"context"
	"net/url"
)

// BugIssues lists the issues of repo that carry the bug label, open or
// closed, without a time cut, pull requests left out: GET
// /repos/{owner}/{repo}/issues?labels=bug&state=all, 100 per page, up to
// FullReadMaxPages pages; it says whether it stopped there (forsgren#126).
func (c *Client) BugIssues(ctx context.Context, repo string) ([]RepoIssue, bool, error) {
	return c.repoIssues(ctx, repo, url.Values{"labels": {"bug"}, "state": {"all"}}, FullReadMaxPages)
}
