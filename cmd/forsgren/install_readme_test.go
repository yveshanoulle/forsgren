package main

import (
	"path/filepath"
	"strings"
	"testing"
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
