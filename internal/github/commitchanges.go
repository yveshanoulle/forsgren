package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
)

// ErrCommitFilesDenied is the 403 of CommitChangedFiles: the token cannot
// read the repository's commits (Contents: read). It comes with ErrAccess,
// which it narrows.
var ErrCommitFilesDenied = errors.New("a commit's files are not readable")

// commitFiles is the part of GitHub's commit that CommitChangedFiles reads.
type commitFiles struct {
	Files []struct {
		Filename         string `json:"filename"`
		PreviousFilename string `json:"previous_filename"`
	} `json:"files"`
}

// CommitChangedFiles lists the paths the commit sha of repo changes
// (forsgren#496): GET /repos/{owner}/{repo}/commits/{sha}, the filename of
// each file and, for a renamed one, its previous_filename too, so a file moved
// out of a folder still belongs to it. GitHub pages the files of this answer
// (300 a page, at most 3000); every page up to the limit is read, and cut says
// it stopped there with files left unread. A 404 or 422 is ErrMissingCommit
// naming the SHA, a 403 the token missing Contents: read (ErrAccess and
// ErrCommitFilesDenied, naming the token and its fix) unless it is GitHub's
// rate limit, which stays ErrRateLimit, and an unreadable answer is ErrAnswer.
func (c *Client) CommitChangedFiles(ctx context.Context, repo, sha string) ([]string, bool, error) {
	t, err := c.endpoint(repo, url.Values{}, "commits", sha)
	if err != nil {
		return nil, false, err
	}
	var paths []string
	cut, err := c.list(ctx, t, func(body []byte) (bool, error) {
		var page commitFiles
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		paths = appendPaths(paths, page)
		return true, nil
	})
	if err != nil {
		return nil, false, c.explainCommitFiles(repo, sha, t, err)
	}
	return paths, cut, nil
}

// appendPaths adds the paths of one page to paths.
func appendPaths(paths []string, page commitFiles) []string {
	for _, f := range page.Files {
		paths = append(paths, f.Filename)
		if f.PreviousFilename != "" {
			paths = append(paths, f.PreviousFilename)
		}
	}
	return paths
}

// explainCommitFiles is err, or the error that names the commit GitHub does
// not have, or the token that was refused and its fix.
func (c *Client) explainCommitFiles(repo, sha string, t target, err error) error {
	if missing, ok := errors.AsType[*answerError](err); ok && isMissingRef(missing.code) {
		return fmt.Errorf("%s: %w: %s not found: %s for %s; was history rewritten?",
			repo, ErrMissingCommit, sha, missing.status(), t.path())
	}
	return c.explainRefusal(repo, t, err, permission{"contents", "Contents", ErrCommitFilesDenied})
}
