package github

import (
	"context"
	"testing"
)

// TestBranchTipIsTheCommitTheBranchIsAt: GET .../git/ref/heads/{branch}
// answers the ref, whose object.sha is the commit; a 500 is its status error.
func TestBranchTipIsTheCommitTheBranchIsAt(t *testing.T) {
	f := branchFake(t)
	got, err := f.client(t, DefaultMaxPages).BranchTip(context.Background(), "acme/data", "main")
	if err != nil || got != baseCommit {
		t.Fatalf("want %s, got %q, %v", baseCommit, got, err)
	}
	f.on(gitData+"ref/heads/main", reply{status: 500, body: `{"message": "boom"}`})
	_, err = f.client(t, DefaultMaxPages).BranchTip(context.Background(), "acme/data", "main")
	wantError(t, err, ErrStatus, "acme/data: ", gitData+"ref/heads/main")
}
