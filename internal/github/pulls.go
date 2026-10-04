package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
)

// ErrPullRequestsDenied is the 403 of OpenPullRequests: the token has no
// pull-requests: read. It comes with ErrAccess, which it narrows.
var ErrPullRequestsDenied = errors.New("pull requests are not readable")

// PullRequest is one open pull request: its number, its author's login and
// its head branch. Nothing else is read: no title, no body, no repository
// name for the page.
type PullRequest struct {
	Number int64
	Author string
	Branch string
}

// pullRequest is one item of GitHub's answer, the fields OpenPullRequests
// reads.
type pullRequest struct {
	Number int64 `json:"number"`
	User   struct {
		Login string `json:"login"`
	} `json:"user"`
	Head struct {
		Ref string `json:"ref"`
	} `json:"head"`
}

// OpenPullRequests lists the open pull requests of repo: GET
// /repos/{owner}/{repo}/pulls?state=open, every page up to the limit, and
// says whether it stopped there. A 403 is the token missing
// pull-requests: read, ErrAccess and ErrPullRequestsDenied naming that
// permission.
func (c *Client) OpenPullRequests(ctx context.Context, repo string) ([]PullRequest, bool, error) {
	t, err := c.endpoint(repo, url.Values{"state": {"open"}}, "pulls")
	if err != nil {
		return nil, false, err
	}
	var pulls []PullRequest
	truncated, err := c.list(ctx, t, readPullRequests(&pulls))
	if forbidden, ok := errors.AsType[*answerError](err); ok && forbidden.code == http.StatusForbidden {
		return nil, false, fmt.Errorf("%s: %w: %w: %s for %s; the job's token needs pull-requests: read",
			repo, ErrAccess, ErrPullRequestsDenied, forbidden.status(), t.path())
	}
	if err != nil {
		return nil, false, err
	}
	return pulls, truncated, nil
}

// readPullRequests is the page reader of OpenPullRequests: it adds each
// item of a page to pulls and asks for the next page while pages are not
// empty.
func readPullRequests(pulls *[]PullRequest) func([]byte) (bool, error) {
	return func(body []byte) (bool, error) {
		var page []pullRequest
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		for _, p := range page {
			*pulls = append(*pulls, PullRequest{Number: p.Number, Author: p.User.Login, Branch: p.Head.Ref})
		}
		return len(page) > 0, nil
	}
}

// dependabotLogin is Dependabot's login in GitHub's REST answers, and
// bumpBranchPrefix the head branches it gives a bump of forsgren's pin.
const (
	dependabotLogin  = "dependabot[bot]"
	bumpBranchPrefix = "dependabot/github_actions/yveshanoulle/forsgren/"
)

// ForsgrenBump is the number of the open pull request, among prs, that
// Dependabot opened to bump forsgren's pin to exactly version, and false
// when there is none. The rule: its author is dependabot[bot] and its head
// branch starts with dependabot/github_actions/yveshanoulle/forsgren/ and
// ends with /metrics.yml- plus the version. Titles are not read (an
// installation can prefix them). Of several the highest number wins.
func ForsgrenBump(prs []PullRequest, version string) (int64, bool) {
	var found int64
	for _, p := range prs {
		if isBumpTo(p, version) {
			found = max(found, p.Number)
		}
	}
	return found, found != 0
}

// isBumpTo says whether p is Dependabot's pull request bumping forsgren's
// pin to exactly version.
func isBumpTo(p PullRequest, version string) bool {
	if version == "" || p.Author != dependabotLogin {
		return false
	}
	return strings.HasPrefix(p.Branch, bumpBranchPrefix) && strings.HasSuffix(p.Branch, "/metrics.yml-"+version)
}
