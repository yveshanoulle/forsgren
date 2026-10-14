package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
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
	// Labels are the names of the issue's labels (forsgren#155).
	Labels []string
}

// Issues lists every issue of repo, open or closed, updated at or after
// since, pull requests left out: GET
// /repos/{owner}/{repo}/issues?state=all&since=... with no labels filter,
// 100 per page, up to the page limit; it says whether it stopped there.
func (c *Client) Issues(ctx context.Context, repo string, since time.Time) ([]RepoIssue, bool, error) {
	query := url.Values{"state": {"all"}, "since": {since.UTC().Format(time.RFC3339)}}
	return c.repoIssues(ctx, repo, query, c.maxPages)
}

// repoIssues is the RepoIssue of each issue that issueItems lists for query,
// up to pages pages; it says whether it stopped there.
func (c *Client) repoIssues(ctx context.Context, repo string, query url.Values, pages int) ([]RepoIssue, bool, error) {
	items, truncated, err := c.issueItems(ctx, repo, query, pages)
	if err != nil {
		return nil, false, err
	}
	issues := make([]RepoIssue, 0, len(items))
	for _, i := range items {
		issues = append(issues, i.toRepoIssue())
	}
	return issues, truncated, nil
}

// FullReadMaxPages is how many pages of 100 the one full read of a repository's
// issues reads at most, apart from the client's limit for the daily reads:
// 10,000 issues (forsgren#76, decision #109).
const FullReadMaxPages = 100

// AllIssues lists every issue of repo, open or closed, without a time cut,
// pull requests left out: GET /repos/{owner}/{repo}/issues?state=all, no
// since and no labels filter, 100 per page, up to FullReadMaxPages pages; it
// says whether it stopped there. It is the one read of a repository's whole
// history.
func (c *Client) AllIssues(ctx context.Context, repo string) ([]RepoIssue, bool, error) {
	return c.repoIssues(ctx, repo, url.Values{"state": {"all"}}, FullReadMaxPages)
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
	for _, l := range i.Labels {
		out.Labels = append(out.Labels, l.Name)
	}
	return out
}

// goneIssue is err as ErrIssueGone when GitHub answered 410 (deleted) or 404
// (deleted or transferred) for one issue. A 404 is also GitHub's answer for a
// repository the token cannot see, so the caller must have read the
// repository's issues in the same run before it takes a 404 for a gone issue.
// Any other error, a 403 and the rate limit among them, is returned as it is.
func goneIssue(err error, repo string, number int64) error {
	var answer *answerError
	if errors.As(err, &answer) && isGone(answer.code) {
		return fmt.Errorf("%s: issue #%d: %w: %w", repo, number, ErrIssueGone, err)
	}
	return err
}

// isGone says whether code is GitHub's answer for an issue that is not there:
// 410 Gone or 404 Not Found.
func isGone(code int) bool { return code == http.StatusGone || code == http.StatusNotFound }

// IssueByNumber reads one issue of repo as it is now, labels and state_reason
// included: GET /repos/{owner}/{repo}/issues/{number}, one request
// (forsgren#155). A 410 or 404 for the issue is ErrIssueGone (goneIssue); an
// answer without a number or a created_at is ErrAnswer.
func (c *Client) IssueByNumber(ctx context.Context, repo string, number int64) (RepoIssue, error) {
	t, err := c.endpoint(repo, nil, "issues", strconv.FormatInt(number, 10))
	if err != nil {
		return RepoIssue{}, err
	}
	body, _, err := c.get(ctx, t, jsonMedia)
	if err != nil {
		return RepoIssue{}, goneIssue(err, repo, number)
	}
	var i issue
	if err := json.Unmarshal(body, &i); err != nil {
		return RepoIssue{}, fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), err)
	}
	if i.Number <= 0 || i.CreatedAt.IsZero() {
		return RepoIssue{}, fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), errIssueFields)
	}
	return i.toRepoIssue(), nil
}
