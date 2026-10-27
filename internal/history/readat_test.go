package history

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// markFile is a mark file as the tests see it: its name, its version and
// column lines, and how it is written and read.
type markFile struct {
	name, header string
	save         func(string, Reach) error
	load         func(string) (Reach, error)
}

// checkMissingIsEmpty fails unless f reads a file that is not there as empty.
func (f markFile) checkMissingIsEmpty(t *testing.T, path string) {
	t.Helper()
	if got, err := f.load(path); err != nil || len(got) != 0 {
		t.Fatalf("want an empty mark for a missing file, got %v, %v", got, err)
	}
}

// checkRoundTrip fails unless f writes acme/app at 2026-09-20T08:00:00Z as its
// header and one line, and reads it back; a missing file reads as empty
// (forsgren#385, #470).
func (f markFile) checkRoundTrip(t *testing.T) {
	t.Helper()
	path := filepath.Join(t.TempDir(), f.name)
	f.checkMissingIsEmpty(t, path)
	at := time.Date(2026, 9, 20, 8, 0, 0, 0, time.UTC)
	if err := f.save(path, Reach{"acme/app": at}); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(filepath.Clean(path))
	if want := f.header + "acme/app,2026-09-20T08:00:00Z\n"; string(raw) != want {
		t.Errorf("want %q, got %q", want, raw)
	}
	if got, err := f.load(path); err != nil || !got["acme/app"].Equal(at) {
		t.Errorf("want acme/app at %v, got %v, %v", at, got, err)
	}
}

// TestMarkFilesKeepTheirOwnHeaderAndRoundTrip (forsgren#67, #76, #255): each
// mark file, failures_read.csv, issues_full.csv and pulls_read.csv among
// them, has its own version and column lines, and is read back as written.
// pulls_denied.csv and pushes_denied.csv have a token column (forsgren#321, #414), see
// pullsdenied_test.go.
func TestMarkFilesKeepTheirOwnHeaderAndRoundTrip(t *testing.T) {
	for _, f := range []markFile{
		{"failures_read.csv", "# forsgren failures read v1\nrepository,read_at\n", SaveReadAt, LoadReadAt},
		{"issues_full.csv", "# forsgren issues full v1\nrepository,full_at\n", SaveFullAt, LoadFullAt},
		{"issue_bugs_cut.csv", "# forsgren bugs cut v1\nrepository,cut_at\n", SaveBugsCut, LoadBugsCut},
		{"cut_runs.csv", "# forsgren cut runs v1\nrepository,first_cut_at\n", SaveCutRuns, LoadCutRuns},
		{"starts_checked.csv", "# forsgren starts checked v1\nrepository,checked_at\n", SaveStartsChecked, LoadStartsChecked},
		{"commits_backfilled.csv", "# forsgren commits backfilled v1\nrepository,backfilled_at\n",
			SaveCommitsBackfilled, LoadCommitsBackfilled},
		{"pull_commits_filled.csv", "# forsgren pull commits filled v1\nrepository,filled_at\n",
			SavePullCommitsFilled, LoadPullCommitsFilled},
		{"commit_files_filled.csv", "# forsgren commit files filled v1\nrepository,filled_at\n",
			SaveCommitFilesFilled, LoadCommitFilesFilled},
		{"pulls_read.csv", "# forsgren pulls read v1\nrepository,read_at\n", SavePullsRead, LoadPullsRead},
		{"pushes_read.csv", "# forsgren pushes read v1\nrepository,read_at\n", SavePushesRead, LoadPushesRead},
	} {
		t.Run(f.name, f.checkRoundTrip)
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
