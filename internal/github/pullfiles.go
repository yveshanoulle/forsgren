package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"

	"github.com/yveshanoulle/forsgren/internal/update"
)

// ChangedFile is one file a pull request changes: its path and the unified
// patch text GitHub answers with, which starts at the first hunk header; it
// is the item of GitHub's answer, the fields PullRequestFiles reads.
type ChangedFile struct {
	Filename string `json:"filename"`
	Patch    string `json:"patch"`
}

// PullRequestAuthor is the login of the author of pull request number of
// repo: GET /repos/{owner}/{repo}/pulls/{number}.
func (c *Client) PullRequestAuthor(ctx context.Context, repo string, number int64) (string, error) {
	t, err := c.endpoint(repo, nil, "pulls", strconv.FormatInt(number, 10))
	if err != nil {
		return "", err
	}
	body, _, err := c.get(ctx, t, jsonMedia)
	if err != nil {
		return "", err
	}
	var p pullRequest
	if err := json.Unmarshal(body, &p); err != nil {
		return "", fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), err)
	}
	return p.User.Login, nil
}

// PullRequestFiles lists the files pull request number of repo changes: GET
// /repos/{owner}/{repo}/pulls/{number}/files, every page up to the limit,
// and says whether it stopped there with files left unread.
func (c *Client) PullRequestFiles(ctx context.Context, repo string, number int64) ([]ChangedFile, bool, error) {
	t, err := c.endpoint(repo, url.Values{}, "pulls", strconv.FormatInt(number, 10), "files")
	if err != nil {
		return nil, false, err
	}
	var files []ChangedFile
	truncated, err := c.list(ctx, t, readChangedFiles(&files))
	if err != nil {
		return nil, false, err
	}
	return files, truncated, nil
}

// readChangedFiles is the page reader of PullRequestFiles: it adds each item
// of a page to files and asks for the next page while pages are not empty.
func readChangedFiles(files *[]ChangedFile) func([]byte) (bool, error) {
	return func(body []byte) (bool, error) {
		var page []ChangedFile
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		*files = append(*files, page...)
		return len(page) > 0, nil
	}
}

// releaseState is the part of GitHub's release that says whether it is
// published: a draft and a prerelease are not.
type releaseState struct {
	Draft      bool `json:"draft"`
	Prerelease bool `json:"prerelease"`
}

// published says whether the release is neither a draft nor a prerelease.
func (r releaseState) published() bool { return !r.Draft && !r.Prerelease }

// PublishedRelease says whether repo has a published release for tag: GET
// /repos/{owner}/{repo}/releases/tags/{tag} answered with a release that is
// neither a draft nor a prerelease. A 404, which is also how GitHub answers a
// draft to a token that may not push, is a tag with no published release, not
// an error; any other error answer is one.
func (c *Client) PublishedRelease(ctx context.Context, repo, tag string) (bool, error) {
	t, err := c.endpoint(repo, nil, "releases", "tags", tag)
	if err != nil {
		return false, err
	}
	body, _, err := c.get(ctx, t, jsonMedia)
	if isNotFound(err) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	var r releaseState
	if err := json.Unmarshal(body, &r); err != nil {
		return false, fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), err)
	}
	return r.published(), nil
}

// isNotFound says whether err is GitHub's 404 answer.
func isNotFound(err error) bool {
	e, ok := errors.AsType[*answerError](err)
	return ok && e.code == http.StatusNotFound
}

// PublishedReleases lists the releases of repo with the commit each tag
// points at: GET /repos/{owner}/{repo}/releases, the first page of 100 only,
// which is enough for the newest releases of forsgren, newest first. A draft
// and a prerelease are listed with their flags and no SHA; the tag of every
// other release is resolved to its commit by TagCommit.
func (c *Client) PublishedReleases(ctx context.Context, repo string) ([]update.Published, error) {
	return nil, nil
}
