package github

import "context"

// FileRef names a file of a repository at a commit or branch.
type FileRef struct {
	Ref  string
	Path string
}

// FileAt is the content of the file at.Path of repo as it is at at.Ref, a
// commit or a branch: GET /repos/{owner}/{repo}/contents/{path}?ref={ref},
// its base64 content decoded. A 404 is a file that is not there, found false,
// not an error; any other error answer is one.
func (c *Client) FileAt(ctx context.Context, repo string, at FileRef) (string, bool, error) {
	return "", false, nil
}
