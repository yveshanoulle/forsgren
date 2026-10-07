package github

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

// SetupIssue is the setup issue of an installation (forsgren#73): the one
// issue, open or closed, whose body holds the machine-owned marker.
// Issue has no State, Title or Body, so it is not reused.
//
// From GitHub's REST reference for GET /repos/{owner}/{repo}/issues (read
// 2026-10-07): each item has a number, a state ("open" or "closed"), a title
// and a body that is a string or null (null is read as ""), and the list
// holds pull requests too, each with a pull_request key.
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
		if !isMarkedIssue(i, marker) {
			continue
		}
		if best.Number == 0 || i.Number < best.Number {
			best = SetupIssue{Number: i.Number, State: i.State, Title: i.Title, Body: *i.Body}
		}
	}
	return best
}

// isMarkedIssue says whether i is an issue, not a pull request, whose body
// holds marker; a null body (nil) holds none.
func isMarkedIssue(i issue, marker string) bool {
	return !isPullRequest(i) && i.Body != nil && strings.Contains(*i.Body, marker)
}

// IssueText is the text of an issue that forsgren writes: its title and its
// body.
type IssueText struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

// CreateIssue creates an issue in repo with text and labels:
// POST /repos/{owner}/{repo}/issues with the JSON body {title, body,
// labels}, and returns the number of the new issue.
//
// From GitHub's REST reference for POST /repos/{owner}/{repo}/issues (read
// 2026-10-07): it answers 201 Created with the created issue, whose number is
// its number in the repository.
func (c *Client) CreateIssue(ctx context.Context, repo string, text IssueText, labels []string) (int64, error) {
	var created struct {
		Number int64 `json:"number"`
	}
	posted := step{http.MethodPost, []string{"issues"}, newIssue{IssueText: text, Labels: labels}}
	if err := c.exchange(ctx, repo, posted, &created); err != nil {
		return 0, err
	}
	return created.Number, nil
}

// newIssue is the JSON body of POST /repos/{owner}/{repo}/issues.
type newIssue struct {
	IssueText
	Labels []string `json:"labels"`
}

// UpdateIssue sets the title and the body of issue number of repo to text:
// PATCH /repos/{owner}/{repo}/issues/{number} with the JSON body {title,
// body}. It does not send the state; reopening is a step of its own.
//
// From GitHub's REST reference for PATCH /repos/{owner}/{repo}/issues/
// {issue_number} (read 2026-10-07): it answers 200 OK with the updated
// issue. That a field left out of the body is left as it is, the state here,
// is PATCH's usual meaning; the reference does not say it in words.
func (c *Client) UpdateIssue(ctx context.Context, repo string, number int64, text IssueText) error {
	return c.patchIssue(ctx, repo, number, text)
}

// ReopenIssue reopens issue number of repo and sets its title and body to
// text in the same call: PATCH /repos/{owner}/{repo}/issues/{number} with
// the JSON body {title, body, state: "open"}. It is one call because the
// title, the body and the state change together: the one setup issue of an
// installation is reopened and updated, never replaced (forsgren#73).
func (c *Client) ReopenIssue(ctx context.Context, repo string, number int64, text IssueText) error {
	return c.patchIssue(ctx, repo, number, reopenedIssue{IssueText: text, State: "open"})
}

// reopenedIssue is the JSON body of PATCH /repos/{owner}/{repo}/issues/{number}
// that reopens the issue: the title and the body, and the state "open".
type reopenedIssue struct {
	IssueText
	State string `json:"state"`
}

// patchIssue sends payload as PATCH /repos/{owner}/{repo}/issues/{number}
// and drops the answer; UpdateIssue, ReopenIssue and CloseIssue go through it.
func (c *Client) patchIssue(ctx context.Context, repo string, number int64, payload any) error {
	patched := step{http.MethodPatch, []string{"issues", strconv.FormatInt(number, 10)}, payload}
	return c.exchange(ctx, repo, patched, nil)
}

// CloseIssue closes issue number of repo with comment: first POST
// /repos/{owner}/{repo}/issues/{number}/comments with the JSON body {body:
// comment}, then PATCH /repos/{owner}/{repo}/issues/{number} with the JSON
// body {state: "closed"}. The comment comes first so that a reader sees why
// the issue was closed; when the comment fails the issue stays open
// (forsgren#73).
func (c *Client) CloseIssue(ctx context.Context, repo string, number int64, comment string) error {
	posted := step{http.MethodPost, []string{"issues", strconv.FormatInt(number, 10), "comments"},
		commentBody{Body: comment}}
	if err := c.exchange(ctx, repo, posted, nil); err != nil {
		return err
	}
	return c.patchIssue(ctx, repo, number, closedIssue{State: "closed"})
}

// commentBody is the JSON body of POST /repos/{owner}/{repo}/issues/{number}/comments.
type commentBody struct {
	Body string `json:"body"`
}

// closedIssue is the JSON body of PATCH /repos/{owner}/{repo}/issues/{number}
// that closes the issue: the state "closed" alone.
type closedIssue struct {
	State string `json:"state"`
}
