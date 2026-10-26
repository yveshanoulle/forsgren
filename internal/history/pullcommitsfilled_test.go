package history

import (
	"path/filepath"
	"testing"
	"time"
)

// TestThePullCommitsFilledMarkFileRoundTrips (forsgren#470, step 1): the mark
// file keeps one time per repository under its own version line, and a
// missing file is empty.
func TestThePullCommitsFilledMarkFileRoundTrips(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pull_commits_filled.csv")
	if got, err := LoadPullCommitsFilled(path); err != nil || len(got) != 0 {
		t.Fatalf("want an empty mark for a missing file, got %v, %v", got, err)
	}
	at := time.Date(2026, 10, 26, 6, 0, 0, 0, time.UTC)
	if err := SavePullCommitsFilled(path, Reach{"acme/app": at}); err != nil {
		t.Fatal(err)
	}
	got, err := LoadPullCommitsFilled(path)
	if err != nil || !got["acme/app"].Equal(at) {
		t.Errorf("want acme/app at %v, got %v, %v", at, got, err)
	}
}
