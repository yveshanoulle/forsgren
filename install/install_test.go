package install

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
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
