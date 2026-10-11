package history

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestMarkFilesKeepTheirOwnHeaderAndRoundTrip (forsgren#67, #76): each mark
// file, failures_read.csv and issues_full.csv, has its own version and column
// lines, and is read back as written.
func TestMarkFilesKeepTheirOwnHeaderAndRoundTrip(t *testing.T) {
	for _, c := range []struct {
		name, header string
		save         func(string, Reach) error
		load         func(string) (Reach, error)
	}{
		{"failures_read.csv", "# forsgren failures read v1\nrepository,read_at\n", SaveReadAt, LoadReadAt},
		{"issues_full.csv", "# forsgren issues full v1\nrepository,full_at\n", SaveFullAt, LoadFullAt},
	} {
		t.Run(c.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), c.name)
			at := time.Date(2026, 9, 20, 8, 0, 0, 0, time.UTC)
			if err := c.save(path, Reach{"acme/app": at}); err != nil {
				t.Fatal(err)
			}
			raw, _ := os.ReadFile(filepath.Clean(path))
			if want := c.header + "acme/app,2026-09-20T08:00:00Z\n"; string(raw) != want {
				t.Errorf("want %q, got %q", want, raw)
			}
			if got, err := c.load(path); err != nil || !got["acme/app"].Equal(at) {
				t.Errorf("want acme/app at %v, got %v, %v", at, got, err)
			}
		})
	}
}

// TestLoadFullAtReadsItsOwnHeader (forsgren#76, decision #109):
// issues_full.csv has its own version and column lines.
func TestLoadFullAtReadsItsOwnHeader(t *testing.T) {
	path := filepath.Join(t.TempDir(), "issues_full.csv")
	raw := "# forsgren issues full v1\nrepository,full_at\nacme/app,2026-09-20T08:00:00Z\n"
	if err := os.WriteFile(path, []byte(raw), 0o600); err != nil {
		t.Fatal(err)
	}
	at := time.Date(2026, 9, 20, 8, 0, 0, 0, time.UTC)
	if got, err := LoadFullAt(path); err != nil || !got["acme/app"].Equal(at) {
		t.Errorf("want acme/app at %v, got %v, %v", at, got, err)
	}
}
