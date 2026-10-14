package main

import (
	"errors"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// expiryFile is the file --token-expiry names, in a fresh directory.
func expiryFile(t *testing.T) string { return filepath.Join(t.TempDir(), "token-expiry") }

// TestCollectWritesTheTokenExpiryToTheFile (forsgren#177): with
// --token-expiry, the date GitHub's header names is written to the file as
// one UTC RFC 3339 line, for the check-needs step to read.
func TestCollectWritesTheTokenExpiryToTheFile(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	header := http.Header{"Github-Authentication-Token-Expiration": {"2027-01-12 08:35:47 UTC"}}
	fakeAPIWithHeader(t, acmeApp, 0, header)
	file := expiryFile(t)
	got := collectRun("--config", writeConfig(t, oneRepository), "--data", dataPath(t), "--token-expiry", file)
	if got.code != 0 {
		t.Fatalf("want exit 0, got %+v", got)
	}
	content, err := os.ReadFile(filepath.Clean(file))
	if err != nil || string(content) != "2027-01-12T08:35:47Z\n" {
		t.Errorf("want the expiry line, got %q (%v)", content, err)
	}
}

// TestCollectRemovesTheTokenExpiryFileWhenNoExpiryIsKnown (forsgren#177): an
// answer without the header (route A, a token that never expires) leaves no
// file, and takes a stale one away.
func TestCollectRemovesTheTokenExpiryFileWhenNoExpiryIsKnown(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	fakeAPI(t, acmeApp, 0)
	file := expiryFile(t)
	if err := os.WriteFile(file, []byte("2020-01-01T00:00:00Z\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	got := collectRun("--config", writeConfig(t, oneRepository), "--data", dataPath(t), "--token-expiry", file)
	if _, err := os.Stat(file); got.code != 0 || !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want exit 0 and no file, got %+v and %v", got, err)
	}
}

// TestCollectFailsWhenTheTokenExpiryFileCannotBeWritten (forsgren#177): a
// file that cannot be written, or a stale one that cannot be removed, is
// exit 1 with collect's own message, not silence.
func TestCollectFailsWhenTheTokenExpiryFileCannotBeWritten(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	header := http.Header{"Github-Authentication-Token-Expiration": {"2027-01-12 08:35:47 UTC"}}
	cases := map[string]struct {
		header http.Header
		path   string
	}{
		"write":  {header, filepath.Join(t.TempDir(), "missing", "token-expiry")},
		"remove": {nil, nonEmptyDir(t)},
	}
	for name, c := range cases {
		fakeAPIWithHeader(t, acmeApp, 0, c.header)
		got := collectRun("--config", writeConfig(t, oneRepository), "--data", dataPath(t), "--token-expiry", c.path)
		if got.code != 1 || !strings.HasPrefix(got.stderr, "collect: ") {
			t.Errorf("%s: want exit 1 and collect's message, got %+v", name, got)
		}
	}
}

// nonEmptyDir is a directory that os.Remove cannot remove.
func nonEmptyDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "x"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	return dir
}
