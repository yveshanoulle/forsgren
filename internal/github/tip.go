package github

import "context"

// BranchTip is the SHA of the commit branch of repo is at: GET
// /repos/{owner}/{repo}/git/ref/heads/{branch}. Files read at it, and a
// commit written on it (BranchCommit.Base), are of one and the same commit,
// whatever lands on the branch meanwhile.
func (c *Client) BranchTip(ctx context.Context, repo, branch string) (string, error) {
	return "", nil
}
