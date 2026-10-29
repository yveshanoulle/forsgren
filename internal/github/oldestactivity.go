package github

import (
	"context"
	"net/url"
	"time"
)

// OldestActivity is the time of the oldest push, pull request merge or force
// push that GitHub's activity list of branch of repo holds (forsgren#583,
// step 1): one GET of /repos/{owner}/{repo}/activity, oldest first
// (direction=asc), 100 per page, its first page only; the zero time for none.
// Errors are BranchActivities' (a 403 is ErrPushesDenied).
func (c *Client) OldestActivity(ctx context.Context, repo, branch string) (time.Time, error) {
	t, err := c.endpoint(repo, url.Values{"ref": {"refs/heads/" + branch}, "direction": {"asc"}}, "activity")
	if err != nil {
		return time.Time{}, err
	}
	var oldest time.Time
	_, err = c.listUpTo(ctx, t, 1, func(body []byte) (bool, error) {
		page, err := readActivities(body)
		if wanted := wantedActivities(page); err == nil && len(wanted) > 0 {
			oldest = wanted[0].PushedAt
		}
		return true, err
	})
	if err != nil {
		return time.Time{}, c.explainPushesDenied(repo, t, err)
	}
	return oldest, nil
}
