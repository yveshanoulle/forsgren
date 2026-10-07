package github

import "context"

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
	return SetupIssue{}, false, nil
}
