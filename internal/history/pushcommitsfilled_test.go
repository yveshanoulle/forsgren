package history

import (
	"path/filepath"
	"testing"
	"time"
)

// TestThePushCommitsFilledMarkFileRoundTrips (forsgren#470, step 2): the mark
// file keeps one time per repository under its own version line, and a
// missing file is empty.
func TestThePushCommitsFilledMarkFileRoundTrips(t *testing.T) {
	path := filepath.Join(t.TempDir(), "push_commits_filled.csv")
	if got, err := LoadPushCommitsFilled(path); err != nil || len(got) != 0 {
		t.Fatalf("want an empty mark for a missing file, got %v, %v", got, err)
	}
	at := time.Date(2026, 10, 26, 6, 0, 0, 0, time.UTC)
	if err := SavePushCommitsFilled(path, Reach{"acme/app": at}); err != nil {
		t.Fatal(err)
	}
	got, err := LoadPushCommitsFilled(path)
	if err != nil || !got["acme/app"].Equal(at) {
		t.Errorf("want acme/app at %v, got %v, %v", at, got, err)
	}
}
