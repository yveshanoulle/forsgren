package github

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"net/http"
	"slices"
	"strings"
)

// BranchCommit is what CommitFiles writes: the branch to move, the commit the
// files were read at and so the one the new commit follows (Base), the
// message and the new content of each file, by repository path.
type BranchCommit struct {
	Branch  string
	Base    string
	Message string
	Files   map[string]string
}

// CommitFiles writes the files of commit to its branch of repo in one
// commit through the git data API, and returns the SHA of that commit: GET
// the commit the new one follows, commit.Base or, when that is empty, the
// commit the branch is at, POST a tree with the files over its tree, POST a
// commit with it as its parent, and PATCH the ref to the new commit without
// force, so a branch that moved or is protected is an error naming the branch
// and changes nothing.
func (c *Client) CommitFiles(ctx context.Context, repo string, commit BranchCommit) (string, error) {
	base, err := c.baseOf(ctx, repo, commit)
	if err != nil {
		return "", err
	}
	sha, err := c.createCommit(ctx, repo, commit, base)
	if err != nil {
		return "", err
	}
	move := step{http.MethodPatch, branchPath("refs", commit.Branch), refUpdate{SHA: sha, Force: false}}
	if err := c.exchange(ctx, repo, move, new(struct{})); err != nil {
		return "", fmt.Errorf("%s: moving the branch %s: %w", repo, commit.Branch, err)
	}
	return sha, nil
}

// head is a branch's commit and the tree of that commit.
type head struct {
	commit string
	tree   string
}

// shaOf is an object of the git data API's answers, of which only the SHA is
// read.
type shaOf struct {
	SHA string `json:"sha"`
}

// baseOf is the commit the new commit of commit follows and its tree: the
// commit's Base, or the tip of its branch when it has none.
func (c *Client) baseOf(ctx context.Context, repo string, commit BranchCommit) (head, error) {
	base := commit.Base
	if base == "" {
		tip, err := c.BranchTip(ctx, repo, commit.Branch)
		if err != nil {
			return head{}, err
		}
		base = tip
	}
	var tip struct {
		Tree shaOf `json:"tree"`
	}
	readTip := step{method: http.MethodGet, segments: []string{"git", "commits", base}}
	if err := c.exchange(ctx, repo, readTip, &tip); err != nil {
		return head{}, err
	}
	return head{commit: base, tree: tip.Tree.SHA}, nil
}

// createCommit creates the tree of commit's files over base's tree and a
// commit of it with base's commit as its parent, and returns its SHA.
func (c *Client) createCommit(ctx context.Context, repo string, commit BranchCommit, base head) (string, error) {
	var tree shaOf
	newTree := step{http.MethodPost, []string{"git", "trees"},
		treeRequest{BaseTree: base.tree, Tree: treeEntries(commit.Files)}}
	if err := c.exchange(ctx, repo, newTree, &tree); err != nil {
		return "", err
	}
	var made shaOf
	newCommit := step{http.MethodPost, []string{"git", "commits"},
		commitRequest{Message: commit.Message, Tree: tree.SHA, Parents: []string{base.commit}}}
	if err := c.exchange(ctx, repo, newCommit, &made); err != nil {
		return "", err
	}
	return made.SHA, nil
}

// branchPath is the path segments of the git data API's kind (ref or refs)
// of a branch, whose name may hold slashes.
func branchPath(kind, branch string) []string {
	return append([]string{"git", kind, "heads"}, strings.Split(branch, "/")...)
}

// treeEntries are the files as the entries of a tree, sorted by path, each a
// regular file with its content inline.
func treeEntries(files map[string]string) []treeEntry {
	var entries []treeEntry
	for _, path := range slices.Sorted(maps.Keys(files)) {
		entries = append(entries, treeEntry{Path: path, Mode: "100644", Type: "blob", Content: files[path]})
	}
	return entries
}

// treeEntry is one file of a tree to create.
type treeEntry struct {
	Path    string `json:"path"`
	Mode    string `json:"mode"`
	Type    string `json:"type"`
	Content string `json:"content"`
}

// treeRequest is the body of the request that creates a tree.
type treeRequest struct {
	BaseTree string      `json:"base_tree"`
	Tree     []treeEntry `json:"tree"`
}

// commitRequest is the body of the request that creates a commit.
type commitRequest struct {
	Message string   `json:"message"`
	Tree    string   `json:"tree"`
	Parents []string `json:"parents"`
}

// refUpdate is the body of the request that moves a ref; Force stays false,
// so only a fast-forward moves it.
type refUpdate struct {
	SHA   string `json:"sha"`
	Force bool   `json:"force"`
}

// step is one request of the git data API: the method, the path segments
// under the repository and the JSON body, nil for none.
type step struct {
	method   string
	segments []string
	in       any
}

// exchange sends the step to repo and decodes the JSON answer into out. A
// malformed answer names the repository and the path.
func (c *Client) exchange(ctx context.Context, repo string, s step, out any) error {
	t, err := c.endpoint(repo, nil, s.segments...)
	if err != nil {
		return err
	}
	k := call{method: s.method, accept: jsonMedia, t: t}
	if s.in != nil {
		raw, _ := json.Marshal(s.in)
		k.body = bytes.NewReader(raw)
	}
	body, _, err := c.do(ctx, k)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), err)
	}
	return nil
}
