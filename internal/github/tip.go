package github

import (
	"context"
	"net/http"
)

// BranchTip is the SHA of the commit branch of repo is at: GET
// /repos/{owner}/{repo}/git/ref/heads/{branch}. Files read at it, and a
// commit written on it (BranchCommit.Base), are of one and the same commit,
// whatever lands on the branch meanwhile.
func (c *Client) BranchTip(ctx context.Context, repo, branch string) (string, error) {
	var ref struct {
		Object shaOf `json:"object"`
	}
	read := step{method: http.MethodGet, segments: branchPath("ref", branch)}
	if err := c.exchange(ctx, repo, read, &ref); err != nil {
		return "", err
	}
	return ref.Object.SHA, nil
}
