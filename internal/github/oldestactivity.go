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
func (c *Client) OldestActivity(ctx context.Context, repo, branch string) (Oldest, error) {
	t, err := c.endpoint(repo, url.Values{"ref": {"refs/heads/" + branch}, "direction": {"asc"}}, "activity")
	if err != nil {
		return Oldest{}, err
	}
	var oldest Oldest
	_, err = c.listUpTo(ctx, t, 1, func(body []byte) (bool, error) {
		page, err := readActivities(body)
		oldest = oldestOf(page)
		return true, err
	})
	if err != nil {
		return Oldest{}, c.explainPushesDenied(repo, t, err)
	}
	return oldest, nil
}

// Oldest is the start of the activity list: the time of its oldest push, pull
// request merge or force push (zero for none), and whether its oldest item is
// the creation of the branch, so the list is whole (forsgren#583, step 3).
type Oldest struct {
	At      time.Time
	Created bool
}

// oldestOf is the start of an oldest-first page.
func oldestOf(page []Activity) Oldest {
	var oldest Oldest
	if wanted := wantedActivities(page); len(wanted) > 0 {
		oldest.At = wanted[0].PushedAt
	}
	oldest.Created = len(page) > 0 && page[0].Kind == activityBranchCreation
	return oldest
}
