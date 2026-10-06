package main

import (
	"bytes"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunWithoutCommandIsUsageError(t *testing.T) {
	var stderr bytes.Buffer
	if got := run(nil, &bytes.Buffer{}, &stderr); got != 2 {
		t.Errorf("want exit 2, got %d", got)
	}
	if !strings.Contains(stderr.String(), "usage: forsgren render --out <dir>") {
		t.Errorf("want the usage line, got %q", stderr.String())
	}
}

func TestRenderWithoutOutIsUsageError(t *testing.T) {
	var stderr bytes.Buffer
	if got := run([]string{"render"}, &bytes.Buffer{}, &stderr); got != 2 {
		t.Errorf("want exit 2, got %d", got)
	}
	if !strings.Contains(stderr.String(), "--out <dir> is required") {
		t.Errorf("want the missing --out reason, got %q", stderr.String())
	}
}

func TestRenderWritesTheSite(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "site")
	var stdout bytes.Buffer
	if got := run([]string{"render", "--out", dir}, &stdout, &bytes.Buffer{}); got != 0 {
		t.Fatalf("want exit 0, got %d", got)
	}
	if _, err := os.Stat(filepath.Join(dir, "index.html")); err != nil {
		t.Errorf("want index.html written: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "legend.html")); err != nil {
		t.Errorf("want legend.html written: %v", err)
	}
	if !strings.Contains(stdout.String(), "rendered 5 page(s)") {
		t.Errorf("want the page count on stdout, got %q", stdout.String())
	}
}

// TestRenderedPageShowsTheVersion is walking-skeleton step 1 (#3): the page
// forsgren writes says which forsgren wrote it, from the one version
// variable in this package.
func TestRenderedPageShowsTheVersion(t *testing.T) {
	dir := t.TempDir()
	if got := run([]string{"render", "--out", dir}, &bytes.Buffer{}, &bytes.Buffer{}); got != 0 {
		t.Fatalf("want exit 0, got %d", got)
	}
	html, err := fs.ReadFile(os.DirFS(dir), "index.html")
	if err != nil {
		t.Fatalf("read index.html: %v", err)
	}
	if !strings.Contains(string(html), "Forsgren 0.3.7") {
		t.Errorf("want the page to say Forsgren 0.3.7, got:\n%s", html)
	}
}

func TestRenderFailureExitsOne(t *testing.T) {
	file := filepath.Join(t.TempDir(), "not-a-dir")
	if err := os.WriteFile(file, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	if got := run([]string{"render", "--out", file}, &bytes.Buffer{}, &stderr); got != 1 {
		t.Errorf("want exit 1, got %d", got)
	}
	if !strings.Contains(stderr.String(), "render:") {
		t.Errorf("want the failure reason on stderr, got %q", stderr.String())
	}
}
