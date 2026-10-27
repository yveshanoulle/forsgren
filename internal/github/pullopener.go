package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
)

// ErrPullRequestGone is a pull request GitHub answers 404 or 410 for: gone,
// or one the token cannot see (forsgren#500).
var ErrPullRequestGone = errors.New("the pull request is gone")

// pullOpener is the answer of GET pulls/{number}, the one field
// PullRequestUserType reads. A null user is no author named, its type empty.
type pullOpener struct {
	User struct {
		Type string `json:"type"`
	} `json:"user"`
}

// PullRequestUserType is GitHub's account type of the opener of pull request
// number of repo (user.type: "User", "Bot", "Organization"), empty when
// GitHub names no author or no type, as ClosedPullRequests reads it; the
// login is never read. GET /repos/{owner}/{repo}/pulls/{number}, one request
// (forsgren#500). A 403 is ErrAccess and ErrPullRequestsDenied
// (explainDenied), a rate limit stays ErrRateLimit; a 404 or 410 is
// ErrPullRequestGone naming the pull request; a body that is no JSON object
// is ErrAnswer.
func (c *Client) PullRequestUserType(ctx context.Context, repo string, number int64) (string, error) {
	t, err := c.endpoint(repo, nil, "pulls", strconv.FormatInt(number, 10))
	if err != nil {
		return "", err
	}
	body, _, err := c.get(ctx, t, jsonMedia)
	if err != nil {
		return "", gonePull(c.explainDenied(repo, t, err), repo, number)
	}
	var p pullOpener
	if err := json.Unmarshal(body, &p); err != nil {
		return "", fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), err)
	}
	return p.User.Type, nil
}

// gonePull is err as ErrPullRequestGone when GitHub answered 404 or 410
// for pull request number of repo; any other error is returned as it is.
func gonePull(err error, repo string, number int64) error {
	if answer, ok := errors.AsType[*answerError](err); ok &&
		(answer.code == http.StatusNotFound || answer.code == http.StatusGone) {
		return fmt.Errorf("%s: pull request %d: %w: %w", repo, number, ErrPullRequestGone, err)
	}
	return err
}
