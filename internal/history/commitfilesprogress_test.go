package history

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// TestCommitFilesProgressRoundTrips (forsgren#594, step 1):
// data/commit_files_progress.csv holds, per repository whose commit files
// read is still going, how many of its commits are read and how many are
// left, written and read back as is.
func TestCommitFilesProgressRoundTrips(t *testing.T) {
	path := filepath.Join(t.TempDir(), "commit_files_progress.csv")
	progress := CommitFilesProgress{"acme/app": {Read: 4199, Left: 3925}}
	if err := SaveCommitFilesProgress(path, progress); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(filepath.Clean(path))
	want := "# forsgren commit files progress v1\nrepository,read,left\nacme/app,4199,3925\n"
	if string(raw) != want {
		t.Errorf("want %q, got %q", want, raw)
	}
	got, err := LoadCommitFilesProgress(path)
	if err != nil || got["acme/app"] != progress["acme/app"] {
		t.Errorf("want %+v back, got %+v, %v", progress, got, err)
	}
}

// TestCommitFilesProgressRefusesCountsThatAreNoProgress: a read count below
// zero or a line with no commit left is no read still going, and a count that
// is no whole number is not in the format.
func TestCommitFilesProgressRefusesCountsThatAreNoProgress(t *testing.T) {
	path := filepath.Join(t.TempDir(), "commit_files_progress.csv")
	for _, bad := range []FilesProgress{{Read: -1, Left: 2}, {Read: 3, Left: 0}} {
		if err := SaveCommitFilesProgress(path, CommitFilesProgress{"acme/app": bad}); err == nil {
			t.Errorf("want %+v refused", bad)
		}
	}
	raw := "# forsgren commit files progress v1\nrepository,read,left\nacme/app,x,2\n"
	if err := os.WriteFile(path, []byte(raw), 0o600); err != nil {
		t.Fatal(err)
	}
	var malformed *MalformedError
	if _, err := LoadCommitFilesProgress(path); !errors.As(err, &malformed) {
		t.Errorf("want a count that is no number malformed, got %v", err)
	}
}

// TestLoadCommitFilesProgressOfNoFileIsEmpty: a missing file holds no read
// still going.
func TestLoadCommitFilesProgressOfNoFileIsEmpty(t *testing.T) {
	got, err := LoadCommitFilesProgress(filepath.Join(t.TempDir(), "none.csv"))
	if err != nil || len(got) != 0 {
		t.Errorf("want none, got %+v, %v", got, err)
	}
}
