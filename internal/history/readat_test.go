package history

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestReadAtKeepsItsOwnHeaderAndRoundTrips (forsgren#67): failures_read.csv
// has its own version and column lines, and is read back as written.
func TestReadAtKeepsItsOwnHeaderAndRoundTrips(t *testing.T) {
	path := filepath.Join(t.TempDir(), "failures_read.csv")
	at := time.Date(2026, 9, 20, 8, 0, 0, 0, time.UTC)
	if err := SaveReadAt(path, Reach{"acme/app": at}); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(filepath.Clean(path))
	want := "# forsgren failures read v1\nrepository,read_at\nacme/app,2026-09-20T08:00:00Z\n"
	if string(raw) != want {
		t.Errorf("want %q, got %q", want, raw)
	}
	if got, err := LoadReadAt(path); err != nil || !got["acme/app"].Equal(at) {
		t.Errorf("want acme/app at %v, got %v, %v", at, got, err)
	}
}
