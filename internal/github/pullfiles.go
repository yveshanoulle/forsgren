package github

import "context"

// ChangedFile is one file a pull request changes: its path and the unified
// patch text GitHub answers with, which starts at the first hunk header.
type ChangedFile struct {
	Filename string
	Patch    string
}

// PullRequestAuthor is the login of the author of pull request number of
// repo: GET /repos/{owner}/{repo}/pulls/{number}. Scaffold: it reads nothing.
func (c *Client) PullRequestAuthor(_ context.Context, _ string, _ int64) (string, error) {
	return "", nil
}

// PullRequestFiles lists the files pull request number of repo changes, and
// says whether it stopped at the page limit with files left unread. Scaffold:
// it reads nothing.
func (c *Client) PullRequestFiles(_ context.Context, _ string, _ int64) ([]ChangedFile, bool, error) {
	return nil, false, nil
}

// PublishedRelease says whether repo has a published release for tag.
// Scaffold: it reads nothing.
func (c *Client) PublishedRelease(_ context.Context, _, _ string) (bool, error) {
	return false, nil
}
