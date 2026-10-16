package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
)

// ErrPullRequestsDenied is the 403 of OpenPullRequests or PullRequestFiles:
// the token has no pull-requests: read. It comes with ErrAccess, which it
// narrows.
var ErrPullRequestsDenied = errors.New("pull requests are not readable")

// PullRequest is one open pull request: its number and its author's login.
// Nothing else is read: no title, no body, no branch, no repository name for
// the page.
type PullRequest struct {
	Number int64
	Author string
}

// pullRequest is one item of GitHub's answer, the fields OpenPullRequests
// reads.
type pullRequest struct {
	Number int64 `json:"number"`
	User   struct {
		Login string `json:"login"`
	} `json:"user"`
}

// OpenPullRequests lists the open pull requests of repo: GET
// /repos/{owner}/{repo}/pulls?state=open, every page up to the limit, and
// says whether it stopped there. A 403 is the token missing
// pull-requests: read, ErrAccess and ErrPullRequestsDenied naming that
// permission, unless it is GitHub's rate limit, which stays ErrRateLimit.
func (c *Client) OpenPullRequests(ctx context.Context, repo string) ([]PullRequest, bool, error) {
	t, err := c.endpoint(repo, url.Values{"state": {"open"}}, "pulls")
	if err != nil {
		return nil, false, err
	}
	var pulls []PullRequest
	truncated, err := c.list(ctx, t, readPullRequests(&pulls))
	if err != nil {
		return nil, false, explainDenied(repo, t, err)
	}
	return pulls, truncated, nil
}

// explainDenied is err, or, when err is the 403 of a token without
// pull-requests: read (not GitHub's rate limit), the error that says so:
// ErrAccess and ErrPullRequestsDenied, naming that permission.
func explainDenied(repo string, t target, err error) error {
	forbidden, ok := errors.AsType[*answerError](err)
	if !ok || !isDenied(forbidden) {
		return err
	}
	return fmt.Errorf("%s: %w: %w: %s for %s; the job's token needs pull-requests: read",
		repo, ErrAccess, ErrPullRequestsDenied, forbidden.status(), t.path())
}

// isDenied says whether GitHub's error answer to a pull request read is the
// token missing pull-requests: read: a 403 that is not a rate limit,
// which keeps its ErrRateLimit (forsgren#40, review of step 7).
func isDenied(e *answerError) bool {
	return e.code == http.StatusForbidden && !errors.Is(e, ErrRateLimit)
}

// IsRefused says whether err is GitHub refusing the token with a 403 that is
// not its rate limit (an answerError, however wrapped): the token lacks a
// permission, whichever call it was (forsgren#73). A rate limit, any other
// status and a nil error are not.
func IsRefused(err error) bool {
	refused, ok := errors.AsType[*answerError](err)
	return ok && isDenied(refused)
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
			*pulls = append(*pulls, PullRequest{Number: p.Number, Author: p.User.Login})
		}
		return len(page) > 0, nil
	}
}

// dependabotLogin is Dependabot's login in GitHub's REST answers.
const dependabotLogin = "dependabot[bot]"

// DependabotPulls are the pulls among prs that Dependabot opened, in their
// order (forsgren#42).
func DependabotPulls(prs []PullRequest) []PullRequest {
	var out []PullRequest
	for _, p := range prs {
		if p.Author == dependabotLogin {
			out = append(out, p)
		}
	}
	return out
}
