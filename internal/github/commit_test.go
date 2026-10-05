package github

import (
	"context"
	"encoding/json"
	"reflect"
	"slices"
	"strings"
	"testing"
)

// The made-up commits and trees of the fake's branch main.
const (
	baseCommit = "1111111111111111111111111111111111111111"
	baseTree   = "2222222222222222222222222222222222222222"
	newTree    = "3333333333333333333333333333333333333333"
	newCommit  = "4444444444444444444444444444444444444444"
)

// bodyOfRequest is the JSON body of the last request with method to path,
// decoded.
func bodyOfRequest(t *testing.T, f *fakeGitHub, method, path string) map[string]any {
	t.Helper()
	var body map[string]any
	if err := json.Unmarshal([]byte(f.bodyOf(method, path)), &body); err != nil {
		t.Fatalf("want a JSON body of %s %s, got %q: %v", method, path, f.bodyOf(method, path), err)
	}
	return body
}

// gitData is the path of the git data API of acme/data on the fake.
const gitData = "/repos/acme/data/git/"

// branchFake is a fake whose branch main is at baseCommit, with the answers
// that create the tree and the commit; the answer to moving the ref is the
// test's.
func branchFake(t *testing.T) *fakeGitHub {
	t.Helper()
	f := newFake(t)
	f.on(gitData+"ref/heads/main", reply{body: `{"ref": "refs/heads/main", "object": {"sha": "` + baseCommit + `"}}`})
	f.on(gitData+"commits/"+baseCommit, reply{body: `{"sha": "` + baseCommit + `", "tree": {"sha": "` + baseTree + `"}}`})
	f.on(gitData+"trees", reply{status: 201, body: `{"sha": "` + newTree + `"}`})
	f.on(gitData+"commits", reply{status: 201, body: `{"sha": "` + newCommit + `"}`})
	return f
}

// forsgrenUpdate is the commit the tests write.
var forsgrenUpdate = BranchCommit{
	Branch: "main", Message: "forsgren: update to v0.1.4",
	Files: map[string]string{".github/workflows/forsgren.yml": "b\n", ".github/workflows/auto.yml": "a\n"},
}

// TestCommitFilesWritesTheFilesInOneCommitAndMovesTheBranchWithoutForce
// (forsgren#62, step 4): the branch's commit is read, a tree with the files'
// content over the commit's tree and a commit with the old one as its parent
// are created, and the ref is moved to it with force false; the SHA of the
// commit is returned, and the tree's entries are sorted by path.
func TestCommitFilesWritesTheFilesInOneCommitAndMovesTheBranchWithoutForce(t *testing.T) {
	git := gitData
	f := branchFake(t)
	f.on(git+"refs/heads/main", reply{body: `{"ref": "refs/heads/main", "object": {"sha": "` + newCommit + `"}}`})
	got, err := f.client(t, DefaultMaxPages).CommitFiles(context.Background(), "acme/data", forsgrenUpdate)
	if err != nil || got != newCommit {
		t.Fatalf("want %s, got %q, %v", newCommit, got, err)
	}
	entry := func(path, content string) map[string]any {
		return map[string]any{"path": path, "mode": "100644", "type": "blob", "content": content}
	}
	wantTree := map[string]any{"base_tree": baseTree, "tree": []any{
		entry(".github/workflows/auto.yml", "a\n"), entry(".github/workflows/forsgren.yml", "b\n")}}
	if tree := bodyOfRequest(t, f, "POST", git+"trees"); !reflect.DeepEqual(tree, wantTree) {
		t.Errorf("want the tree %v, got %v", wantTree, tree)
	}
	wantCommit := map[string]any{"message": "forsgren: update to v0.1.4", "tree": newTree, "parents": []any{baseCommit}}
	if commit := bodyOfRequest(t, f, "POST", git+"commits"); !reflect.DeepEqual(commit, wantCommit) {
		t.Errorf("want the commit %v, got %v", wantCommit, commit)
	}
	wantRef := map[string]any{"sha": newCommit, "force": false}
	if ref := bodyOfRequest(t, f, "PATCH", git+"refs/heads/main"); !reflect.DeepEqual(ref, wantRef) {
		t.Errorf("want the ref update %v, got %v", wantRef, ref)
	}
}

// TestCommitFilesNamesTheBranchWhenTheRefUpdateIsRefused: a 422 on moving the
// ref (a branch that moved, or a protected one) is an error that names the
// branch, with no SHA.
func TestCommitFilesNamesTheBranchWhenTheRefUpdateIsRefused(t *testing.T) {
	f := branchFake(t)
	f.on(gitData+"refs/heads/main", reply{status: 422, body: `{"message": "Update is not a fast forward"}`})
	got, err := f.client(t, DefaultMaxPages).CommitFiles(context.Background(), "acme/data", forsgrenUpdate)
	if got != "" {
		t.Errorf("want no SHA, got %q", got)
	}
	if err == nil || !strings.Contains(err.Error(), "main") {
		t.Errorf("want an error naming the branch main, got %v", err)
	}
}

// TestCommitFilesStopsAtTheStepThatFails: a 500 on any request before the
// ref's update is that request's status error, naming the repository and the
// path, and no later request is made.
func TestCommitFilesStopsAtTheStepThatFails(t *testing.T) {
	paths := []string{
		gitData + "ref/heads/main", gitData + "commits/" + baseCommit, gitData + "trees", gitData + "commits",
	}
	for _, path := range paths {
		f := branchFake(t)
		f.on(path, reply{status: 500, body: `{"message": "boom"}`})
		got, err := f.client(t, DefaultMaxPages).CommitFiles(context.Background(), "acme/data", forsgrenUpdate)
		wantError(t, err, ErrStatus, "acme/data: ", path)
		if got != "" || f.bodyOf("PATCH", gitData+"refs/heads/main") != "" {
			t.Errorf("%s: want no SHA and no ref update, got %q", path, got)
		}
	}
}

// TestCommitFilesRefusesAMalformedAnswerAndANonRepository: an answer that is
// not the JSON asked for is an answer error, and a name that is not one
// owner/name never becomes a request.
func TestCommitFilesRefusesAMalformedAnswerAndANonRepository(t *testing.T) {
	f := branchFake(t)
	f.on(gitData+"ref/heads/main", reply{body: `{"object": 7}`})
	_, err := f.client(t, DefaultMaxPages).CommitFiles(context.Background(), "acme/data", forsgrenUpdate)
	wantError(t, err, ErrAnswer, "acme/data: ", gitData+"ref/heads/main")
	_, err = f.client(t, DefaultMaxPages).CommitFiles(context.Background(), "acme", forsgrenUpdate)
	wantError(t, err, ErrRepositoryName)
}

// TestCommitFilesFollowsTheBaseItIsGivenNotTheBranchsHead: with Base set, the
// branch's ref is not read, the commit's tree is the one of Base's commit and
// its parent is Base, so files read at Base are never written over a commit
// that landed since; the ref update, which is no fast-forward then, is the
// server's to refuse. Here the branch has moved on to another commit.
func TestCommitFilesFollowsTheBaseItIsGivenNotTheBranchsHead(t *testing.T) {
	const moved = "9999999999999999999999999999999999999999"
	f := branchFake(t)
	f.on(gitData+"ref/heads/main", reply{body: `{"object": {"sha": "` + moved + `"}}`})
	f.on(gitData+"refs/heads/main", reply{body: `{"object": {"sha": "` + newCommit + `"}}`})
	based := forsgrenUpdate
	based.Base = baseCommit
	got, err := f.client(t, DefaultMaxPages).CommitFiles(context.Background(), "acme/data", based)
	if err != nil || got != newCommit {
		t.Fatalf("want %s, got %q, %v", newCommit, got, err)
	}
	if asked := pathsAsked(f); slices.Contains(asked, gitData+"ref/heads/main") {
		t.Errorf("want the branch's ref not read, got %v", asked)
	}
	if tree := bodyOfRequest(t, f, "POST", gitData+"trees"); tree["base_tree"] != baseTree {
		t.Errorf("want the tree over %s, got %v", baseTree, tree)
	}
	wantOnlyParent(t, bodyOfRequest(t, f, "POST", gitData+"commits"), baseCommit)
}

// wantOnlyParent fails unless commit, a request body, has exactly the one
// parent.
func wantOnlyParent(t *testing.T, commit map[string]any, parent string) {
	t.Helper()
	if parents, _ := commit["parents"].([]any); !reflect.DeepEqual(parents, []any{parent}) {
		t.Errorf("want the one parent %s, got %v", parent, commit["parents"])
	}
}

// pathsAsked are the paths of the requests the fake has seen.
func pathsAsked(f *fakeGitHub) []string {
	var paths []string
	for _, r := range f.seen() {
		paths = append(paths, r.URL.Path)
	}
	return paths
}
