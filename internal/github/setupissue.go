package github

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
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

// CreateIssue creates an issue in repo with title, body and labels:
// POST /repos/{owner}/{repo}/issues with the JSON body {title, body,
// labels}, and returns the number of the new issue.
//
// Sure, from GitHub's REST reference for POST /repos/{owner}/{repo}/issues:
// it answers 201 with the created issue, whose number is its number in the
// repository.
func (c *Client) CreateIssue(ctx context.Context, repo, title, body string, labels []string) (int64, error) {
	payload := newIssue{Title: title, Body: body, Labels: labels}
	answer, t, err := c.sendJSON(ctx, http.MethodPost, repo, payload, "issues")
	if err != nil {
		return 0, err
	}
	var created struct {
		Number int64 `json:"number"`
	}
	if err := json.Unmarshal(answer, &created); err != nil {
		return 0, fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), err)
	}
	return created.Number, nil
}

// newIssue is the JSON body of POST /repos/{owner}/{repo}/issues.
type newIssue struct {
	Title  string   `json:"title"`
	Body   string   `json:"body"`
	Labels []string `json:"labels"`
}

// UpdateIssue sets the title and the body of issue number of repo:
// PATCH /repos/{owner}/{repo}/issues/{number} with the JSON body {title,
// body}. It does not send the state; reopening is a step of its own.
//
// Sure, from GitHub's REST reference for PATCH /repos/{owner}/{repo}/issues/
// {issue_number}: it answers 200 with the updated issue, and a field left
// out of the body is left as it is.
func (c *Client) UpdateIssue(ctx context.Context, repo string, number int64, title, body string) error {
	payload := updatedIssue{Title: title, Body: body}
	_, _, err := c.sendJSON(ctx, http.MethodPatch, repo, payload, "issues", strconv.FormatInt(number, 10))
	return err
}

// updatedIssue is the JSON body of PATCH /repos/{owner}/{repo}/issues/{number}:
// no state, so the issue stays open or closed as it is.
type updatedIssue struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

// sendJSON sends payload as JSON with method to the endpoint of repo under
// segments, and returns the answer's body and the target it went to.
func (c *Client) sendJSON(
	ctx context.Context, method, repo string, payload any, segments ...string,
) ([]byte, target, error) {
	t, err := c.endpoint(repo, nil, segments...)
	if err != nil {
		return nil, target{}, err
	}
	// A struct of strings always marshals, so the error is dropped, as exchange does.
	raw, _ := json.Marshal(payload)
	answer, _, err := c.do(ctx, call{method: method, accept: jsonMedia, t: t, body: bytes.NewReader(raw)})
	return answer, t, err
}
