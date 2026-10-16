package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	installreadme "github.com/yveshanoulle/forsgren/install"
)

// TestInstallReadmeWritesTheReadmeOfThisVersion drives
// `forsgren install-readme --out <path>` on a missing file: it is created
// with forsgren's installation README, which names the version this binary
// is and holds no placeholder, and the command says so (forsgren#110).
func TestInstallReadmeWritesTheReadmeOfThisVersion(t *testing.T) {
	path := filepath.Join(t.TempDir(), "README.md")
	wantLookup(t, "created "+path+"\n", "", "install-readme", "--out", path)
	got := readFile(t, path)
	if !strings.Contains(got, "written by the daily run for forsgren "+version+":") {
		t.Errorf("want the README to name forsgren %s, got %q", version, got)
	}
	if strings.Contains(got, "{{") {
		t.Errorf("want no placeholder left in the README, got %q", got)
	}
}

// TestInstallReadmeFailsWhenItCannotWriteTheFile: a directory that is not
// there is an error naming the command and the path, exit 1, and nothing is
// created (forsgren#110).
func TestInstallReadmeFailsWhenItCannotWriteTheFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "typo", "README.md")
	wantExit(t, exit{1, "", "install-readme: " + path + ": cannot write the README"}, "install-readme", "--out", path)
}

// TestInstallReadmeNeedsOut: without --out it is a usage error, exit 2.
func TestInstallReadmeNeedsOut(t *testing.T) {
	wantExit(t, exit{2, "", "install-readme: --out <path> is required"}, "install-readme")
}

// TestInstallReadmeReplacesADifferingReadme: a README that is not this
// version's text, a hand edit or an older version's, is replaced, and the
// command says so (forsgren#110).
func TestInstallReadmeReplacesADifferingReadme(t *testing.T) {
	path := filepath.Join(t.TempDir(), "README.md")
	if err := os.WriteFile(path, []byte("my own README\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	wantLookup(t, "replaced "+path+"\n", "", "install-readme", "--out", path)
	if got := readFile(t, path); got != installreadme.Text(version) {
		t.Errorf("want this version's README, got %q", got)
	}
}

// TestInstallReadmeLeavesAnIdenticalReadmeUntouched: the text already there
// is not written again: `unchanged`, and its modification time is kept.
func TestInstallReadmeLeavesAnIdenticalReadmeUntouched(t *testing.T) {
	path := filepath.Join(t.TempDir(), "README.md")
	wantLookup(t, "created "+path+"\n", "", "install-readme", "--out", path)
	old := time.Now().Add(-48 * time.Hour).Truncate(time.Second)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
	wantLookup(t, "unchanged "+path+"\n", "", "install-readme", "--out", path)
	if info, err := os.Stat(path); err != nil || !info.ModTime().Equal(old) {
		t.Errorf("want mtime %v kept, got %v, %v", old, info, err)
	}
}
