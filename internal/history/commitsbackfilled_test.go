package history

import (
	"path/filepath"
	"testing"
	"time"
)

// TestTheCommitsBackfilledMarkFileRoundTrips (forsgren#385): the mark file
// keeps one time per repository under its own version line, and a missing
// file is empty.
func TestTheCommitsBackfilledMarkFileRoundTrips(t *testing.T) {
	path := filepath.Join(t.TempDir(), "commits_backfilled.csv")
	if got, err := LoadCommitsBackfilled(path); err != nil || len(got) != 0 {
		t.Fatalf("want an empty mark for a missing file, got %v, %v", got, err)
	}
	at := time.Date(2026, 10, 24, 6, 0, 0, 0, time.UTC)
	if err := SaveCommitsBackfilled(path, Reach{"acme/app": at}); err != nil {
		t.Fatal(err)
	}
	got, err := LoadCommitsBackfilled(path)
	if err != nil || !got["acme/app"].Equal(at) {
		t.Errorf("want acme/app at %v, got %v, %v", at, got, err)
	}
}
