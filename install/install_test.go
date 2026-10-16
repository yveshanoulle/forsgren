package install

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestWriteCreatesTheReadmeOfTheVersion: a missing file is created with the
// README text of the version, which names it and has no placeholder left
// (forsgren#110).
func TestWriteCreatesTheReadmeOfTheVersion(t *testing.T) {
	path := filepath.Join(t.TempDir(), "README.md")
	outcome, err := Write(path, "7.8.9")
	if outcome != Created || err != nil {
		t.Fatalf("want %q and no error, got %q, %v", Created, outcome, err)
	}
	got, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != Text("7.8.9") {
		t.Errorf("want the README text of 7.8.9, got %q", got)
	}
}

// TestTextNamesTheVersionAndHoldsNoPlaceholder: the version is written where
// the README says which forsgren it is for, and nothing of the token is left.
func TestTextNamesTheVersionAndHoldsNoPlaceholder(t *testing.T) {
	got := Text("7.8.9")
	if !strings.Contains(got, "for forsgren 7.8.9:") || strings.Contains(got, "{{") {
		t.Errorf("want the version named and no placeholder left, got %q", got)
	}
}

// TestWriteFailsWithoutADirectory: a directory that is not there is an error
// that names the path and wraps ErrWrite, and nothing is created.
func TestWriteFailsWithoutADirectory(t *testing.T) {
	path := filepath.Join(t.TempDir(), "typo", "README.md")
	outcome, err := Write(path, "7.8.9")
	if outcome != "" {
		t.Errorf("want no outcome, got %q", outcome)
	}
	if !errors.Is(err, ErrWrite) || !strings.HasPrefix(err.Error(), path+": ") {
		t.Errorf("want an ErrWrite error naming the path, got %v", err)
	}
}

// writeReadme puts text at a README.md in a new directory and returns its path.
func writeReadme(t *testing.T, text string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "README.md")
	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// wantWrite fails the test unless Write(path, "7.8.9") reports outcome.
func wantWrite(t *testing.T, path, outcome string) {
	t.Helper()
	if got, err := Write(path, "7.8.9"); got != outcome || err != nil {
		t.Fatalf("want %q and no error, got %q, %v", outcome, got, err)
	}
}

// TestWriteReplacesADifferentFile: another text, a hand edit, is replaced
// and reported so.
func TestWriteReplacesADifferentFile(t *testing.T) {
	path := writeReadme(t, "mine")
	wantWrite(t, path, Replaced)
	got, err := os.ReadFile(filepath.Clean(path))
	if err != nil || string(got) != Text("7.8.9") {
		t.Errorf("want the README text of 7.8.9, got %q, %v", got, err)
	}
}

// TestWriteKeepsTheSameFile: the text already there is Unchanged and its
// modification time is kept.
func TestWriteKeepsTheSameFile(t *testing.T) {
	path := writeReadme(t, Text("7.8.9"))
	old := time.Now().Add(-48 * time.Hour).Truncate(time.Second)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
	wantWrite(t, path, Unchanged)
	info, err := os.Stat(path)
	if err != nil || !info.ModTime().Equal(old) {
		t.Errorf("want mtime %v kept, got %v, %v", old, info, err)
	}
}

// TestWriteRefusesADirectoryAndLeavesNoTemporaryFile: a directory at path is
// an ErrWrite error.
func TestWriteRefusesADirectoryAndLeavesNoTemporaryFile(t *testing.T) {
	dir := t.TempDir()
	if _, err := Write(dir, "7.8.9"); !errors.Is(err, ErrWrite) {
		t.Errorf("want an ErrWrite error, got %v", err)
	}
	if entries, err := os.ReadDir(dir); err != nil || len(entries) != 0 {
		t.Errorf("want nothing left in the directory, got %v, %v", entries, err)
	}
}
