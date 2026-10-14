package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// TestRenderDoesNotTakeTheTokenExpiry (forsgren#177, decision #179): the
// settings page has no Token expires row, so render does not know
// --token-expiry and nothing in the workflow can pass it; the file is for
// collect and check-needs.
func TestRenderDoesNotTakeTheTokenExpiry(t *testing.T) {
	t.Chdir(t.TempDir())
	out := filepath.Join(t.TempDir(), "site")
	code, _, stderr := runCommand("render", "--out", out, "--token-expiry", writeExpiry(t, "2027-01-12T23:35:47Z\n"))
	if code != 2 || !strings.Contains(stderr, "flag provided but not defined: -token-expiry") {
		t.Errorf("want exit 2 and the unknown flag, got %d, %q", code, stderr)
	}
}
