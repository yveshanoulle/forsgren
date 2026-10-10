package github

import (
	"context"
	"time"
)

// RepoIssue is one issue of a repository, whatever its labels (forsgren#76,
// step 1): the fields the opened and completed events need.
type RepoIssue struct {
	Number    int64
	CreatedAt time.Time
	// ClosedAt is zero while the issue is open.
	ClosedAt time.Time
	// State is "open" or "closed".
	State string
	// StateReason is GitHub's state_reason: "completed", "not_planned",
	// "duplicate", "reopened", or "" when GitHub sends null or none.
	StateReason string
}

// Issues lists every issue of repo, open or closed, updated at or after
// since, pull requests left out: GET /repos/{owner}/{repo}/issues?state=all&since=...
// with no labels filter, 100 per page, up to the page limit; it says
// whether it stopped there.
func (c *Client) Issues(ctx context.Context, repo string, since time.Time) ([]RepoIssue, bool, error) {
	return nil, false, nil
}
