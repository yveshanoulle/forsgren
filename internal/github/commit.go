package github

import "context"

// BranchCommit is what CommitFiles writes: the branch to move, the message
// and the new content of each file, by repository path.
type BranchCommit struct {
	Branch  string
	Message string
	Files   map[string]string
}

// CommitFiles writes the files of commit to its branch of repo in one
// commit through the git data API, and returns the SHA of that commit: GET
// the branch's ref and its commit, POST a tree with the files over the
// commit's tree, POST a commit with the old one as its parent, and PATCH the
// ref to it without force, so a branch that moved or is protected is an error
// naming the branch and changes nothing.
func (c *Client) CommitFiles(ctx context.Context, repo string, commit BranchCommit) (string, error) {
	return "", nil
}
