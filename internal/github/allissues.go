package github

import (
	"context"
	"net/url"
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
// since, pull requests left out: GET
// /repos/{owner}/{repo}/issues?state=all&since=... with no labels filter, 100 per page, up to the page limit; it says
// whether it stopped there.
func (c *Client) Issues(ctx context.Context, repo string, since time.Time) ([]RepoIssue, bool, error) {
	query := url.Values{"state": {"all"}, "since": {since.UTC().Format(time.RFC3339)}}
	items, truncated, err := c.issueItems(ctx, repo, query)
	if err != nil {
		return nil, false, err
	}
	issues := make([]RepoIssue, 0, len(items))
	for _, i := range items {
		issues = append(issues, i.toRepoIssue())
	}
	return issues, truncated, nil
}

// toRepoIssue is the RepoIssue of one item.
func (i issue) toRepoIssue() RepoIssue {
	out := RepoIssue{Number: i.Number, CreatedAt: i.CreatedAt.UTC(), State: i.State}
	if i.ClosedAt != nil {
		out.ClosedAt = i.ClosedAt.UTC()
	}
	if i.StateReason != nil {
		out.StateReason = *i.StateReason
	}
	return out
}
