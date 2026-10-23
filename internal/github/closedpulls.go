package github

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"time"
)

// ClosedPullRequest is one closed pull request of a repository, merged or
// not (forsgren#255, step 1): what Mainline Lead Time needs of it. Nothing
// else is read: no title, no body, no author.
type ClosedPullRequest struct {
	Number int64
	// HeadBranch is the name of the branch the pull request was opened from
	// (head.ref).
	HeadBranch string
	CreatedAt  time.Time
	// MergedAt is zero for a pull request closed without a merge.
	MergedAt time.Time
	// MergeCommit is the SHA of the commit the merge made (merge_commit_sha),
	// empty for a pull request closed without a merge: GitHub's
	// merge_commit_sha of one is a test merge that never landed, and is not
	// read.
	MergeCommit string
	UpdatedAt   time.Time
}

// closedPull is one item of GitHub's answer, the fields ClosedPullRequests
// reads. A null merged_at is a pull request closed without a merge.
type closedPull struct {
	Number int64 `json:"number"`
	Head   struct {
		Ref string `json:"ref"`
	} `json:"head"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
	MergedAt       *time.Time `json:"merged_at"`
	MergeCommitSHA string     `json:"merge_commit_sha"`
}

// ClosedPullRequests lists the closed pull requests of repo updated at or
// after since, merged or not, newest updated first: GET
// /repos/{owner}/{repo}/pulls?state=closed&sort=updated&direction=desc, 100
// per page, up to the page limit; it says whether it stopped there. GitHub's
// pull request list has no since filter, so the read ends at the first pull
// request updated before since, which is left out. A 403 is the token missing
// pull-requests: read, ErrAccess and ErrPullRequestsDenied (explainDenied),
// unless it is GitHub's rate limit, which stays ErrRateLimit. A pull request
// with no number, head branch, created_at or updated_at, or merged without a
// merge commit SHA, is ErrAnswer.
func (c *Client) ClosedPullRequests(ctx context.Context, repo string, since time.Time) (
	[]ClosedPullRequest, bool, error,
) {
	query := url.Values{"state": {"closed"}, "sort": {"updated"}, "direction": {"desc"}}
	t, err := c.endpoint(repo, query, "pulls")
	if err != nil {
		return nil, false, err
	}
	var pulls []ClosedPullRequest
	updated := func(p ClosedPullRequest) time.Time { return p.UpdatedAt }
	truncated, err := c.list(ctx, t, func(body []byte) (bool, error) {
		page, err := readClosedPulls(body)
		if err != nil {
			return false, err
		}
		return keep(&pulls, page, Span{Since: since}, updated), nil
	})
	if err != nil {
		return nil, false, explainDenied(repo, t, err)
	}
	return pulls, truncated, nil
}

// readClosedPulls is the ClosedPullRequest of each item of one page.
func readClosedPulls(body []byte) ([]ClosedPullRequest, error) {
	var items []closedPull
	if err := json.Unmarshal(body, &items); err != nil {
		return nil, err
	}
	page := make([]ClosedPullRequest, 0, len(items))
	for _, item := range items {
		p, err := item.toClosedPullRequest()
		if err != nil {
			return nil, err
		}
		page = append(page, p)
	}
	return page, nil
}

// toClosedPullRequest is the ClosedPullRequest of one item, its times in UTC,
// or the error of an item that cannot be stored.
func (p closedPull) toClosedPullRequest() (ClosedPullRequest, error) {
	if !p.complete() {
		return ClosedPullRequest{}, fmt.Errorf("pull request %d has no number, head branch, created_at or updated_at",
			p.Number)
	}
	out := ClosedPullRequest{Number: p.Number, HeadBranch: p.Head.Ref, CreatedAt: p.CreatedAt.UTC(),
		UpdatedAt: p.UpdatedAt.UTC()}
	if p.MergedAt == nil {
		return out, nil
	}
	if !isSHA(p.MergeCommitSHA) {
		return ClosedPullRequest{}, fmt.Errorf("merged pull request %d has no merge commit SHA", p.Number)
	}
	out.MergedAt, out.MergeCommit = p.MergedAt.UTC(), p.MergeCommitSHA
	return out, nil
}

// complete says whether the item has what every closed pull request needs.
func (p closedPull) complete() bool {
	return p.Number > 0 && p.Head.Ref != "" && !p.CreatedAt.IsZero() && !p.UpdatedAt.IsZero()
}
