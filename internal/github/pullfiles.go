package github

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
)

// ChangedFile is one file a pull request changes: its path and the unified
// patch text GitHub answers with, which starts at the first hunk header.
type ChangedFile struct {
	Filename string
	Patch    string
}

// changedFile is one item of GitHub's answer, the fields PullRequestFiles
// reads.
type changedFile struct {
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
		var page []changedFile
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		for _, f := range page {
			*files = append(*files, ChangedFile{Filename: f.Filename, Patch: f.Patch})
		}
		return len(page) > 0, nil
	}
}

// PublishedRelease says whether repo has a published release for tag: GET
// /repos/{owner}/{repo}/releases/tags/{tag} answered with a release.
func (c *Client) PublishedRelease(ctx context.Context, repo, tag string) (bool, error) {
	t, err := c.endpoint(repo, nil, "releases", "tags", tag)
	if err != nil {
		return false, err
	}
	if _, _, err := c.get(ctx, t, jsonMedia); err != nil {
		return false, err
	}
	return true, nil
}
