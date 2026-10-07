package github

import (
	"context"
	"encoding/json"
	"net/url"
	"strings"
)

// SetupIssue is the setup issue of an installation (forsgren#73): the one
// issue, open or closed, whose body holds the machine-owned marker.
// Issue has no State, Title or Body, so it is not reused.
//
// Sure, from GitHub's REST reference for GET /repos/{owner}/{repo}/issues:
// number, state ("open" or "closed"), title and body (null when empty,
// read as ""), and that the list holds pull requests too, each with a
// pull_request field.
type SetupIssue struct {
	Number int64
	// State is "open" or "closed", as GitHub names it.
	State string
	Title string
	Body  string
}

// FindIssueByMarker finds the issue of repo that carries label and whose
// body contains marker: GET /repos/{owner}/{repo}/issues?labels=<label>&
// state=all, so a closed issue is found too (it is reopened, never
// replaced), every page up to the page limit. The marker is the identity;
// title and body text are presentation. An issue with the label and
// without the marker is never returned, and a pull request is not an
// issue. When several carry the marker, the lowest number wins, the first
// one created. It says whether one was found.
func (c *Client) FindIssueByMarker(ctx context.Context, repo, label, marker string) (SetupIssue, bool, error) {
	query := url.Values{"labels": {label}, "state": {"all"}}
	t, err := c.endpoint(repo, query, "issues")
	if err != nil {
		return SetupIssue{}, false, err
	}
	var best SetupIssue
	_, err = c.list(ctx, t, func(body []byte) (bool, error) {
		var page []issue
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		best = lowestMarked(best, page, marker)
		return len(page) > 0, nil
	})
	if err != nil {
		return SetupIssue{}, false, err
	}
	// GitHub numbers issues from 1, so a zero Number means none was found.
	return best, best.Number != 0, nil
}

// lowestMarked is best, or the lowest-numbered issue of page that is not a
// pull request and whose body holds marker, when that is lower than best
// (a zero best has none yet).
func lowestMarked(best SetupIssue, page []issue, marker string) SetupIssue {
	for _, i := range page {
		if isPullRequest(i) || i.Body == nil || !strings.Contains(*i.Body, marker) {
			continue
		}
		if best.Number == 0 || i.Number < best.Number {
			best = SetupIssue{Number: i.Number, State: i.State, Title: i.Title, Body: *i.Body}
		}
	}
	return best
}
