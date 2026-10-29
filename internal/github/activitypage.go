package github

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
)

// ActivityPage is one page of the activity list of branch of repo
// (forsgren#583, step 2): one GET of /repos/{owner}/{repo}/activity, newest
// first, 100 per page, after cursor (the newest page for an empty one). It
// gives the page's pushes, pull request merges and force pushes, as
// BranchActivities reads them, and the after cursor of the next page, empty
// when the list ends there. GitHub pages this list by that cursor, which
// holds its place across runs. Errors are BranchActivities' (a 403 is
// ErrPushesDenied).
func (c *Client) ActivityPage(ctx context.Context, repo, branch, cursor string) (ActivityList, error) {
	t, err := c.endpoint(repo, activityQuery(branch, cursor), "activity")
	if err != nil {
		return ActivityList{}, err
	}
	body, header, err := c.get(ctx, t, jsonMedia)
	if err != nil {
		return ActivityList{}, c.explainPushesDenied(repo, t, err)
	}
	page, err := readActivities(body)
	if err != nil {
		return ActivityList{}, fmt.Errorf("%s: %w for %s: %w", t.repo, ErrAnswer, t.path(), err)
	}
	next, err := c.nextCursor(t, header)
	return ActivityList{Activities: wantedActivities(page), Next: next, Created: holdsCreation(page)}, err
}

// activityBranchCreation is GitHub's activity_type of the creation of a branch.
const activityBranchCreation = "branch_creation"

// holdsCreation says page holds the creation of the branch.
func holdsCreation(page []Activity) bool {
	for _, a := range page {
		if a.Kind == activityBranchCreation {
			return true
		}
	}
	return false
}

// ActivityList is one page of the activity list: its pushes, merges and force
// pushes, the after cursor of the next page (empty at the end), and whether
// the page holds the creation of the branch, the first item of a complete
// list (forsgren#583, step 3).
type ActivityList struct {
	Activities []Activity
	Next       string
	Created    bool
}

// activityQuery is the query of the activity list of branch after cursor,
// with no after parameter for the newest page.
func activityQuery(branch, cursor string) url.Values {
	query := url.Values{"ref": {"refs/heads/" + branch}}
	if cursor != "" {
		query.Set("after", cursor)
	}
	return query
}

// nextCursor is the after cursor of the Link header's next page in the
// answer to t, empty when there is none.
func (c *Client) nextCursor(t target, h http.Header) (string, error) {
	next, err := c.nextPage(t, h)
	if next == nil {
		return "", err
	}
	return next.Query().Get("after"), nil
}
