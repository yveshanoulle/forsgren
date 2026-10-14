package page

import (
	"os"
	"path/filepath"
	"testing"
)

// TestWriteSiteLeavesOutHiddenPagesAndRemovesStaleOnes (forsgren#159): a
// hidden issues or days page is not written and not counted, and a file of it
// left in a reused out dir is removed; the other pages are written.
func TestWriteSiteLeavesOutHiddenPagesAndRemovesStaleOnes(t *testing.T) {
	cases := map[string]struct {
		hidden map[string]bool
		gone   []string
		kept   []string
		pages  int
	}{
		"days":   {map[string]bool{"days": true}, []string{"days.html"}, []string{"issues.html"}, 7},
		"issues": {map[string]bool{"issues": true}, []string{"issues.html"}, []string{"days.html"}, 7},
		"both":   {map[string]bool{"days": true, "issues": true}, []string{"days.html", "issues.html"}, nil, 6},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			writeStale(t, dir)
			data := Placeholder("1.2.0")
			data.Hidden = tc.hidden
			n, err := WriteSite(dir, data)
			if err != nil || n != tc.pages {
				t.Fatalf("want %d pages and no error, got %d, %v", tc.pages, n, err)
			}
			wantGone(t, dir, tc.gone)
			wantRendered(t, dir, append(tc.kept, "index.html", "legend.html", "settings.html"))
		})
	}
}

// TestWriteSiteFailsWhenAHiddenPageCannotBeRemoved (forsgren#159): a hidden
// page whose name is a folder with files in it cannot be removed, and the
// write fails instead of leaving the page behind unnoticed.
func TestWriteSiteFailsWhenAHiddenPageCannotBeRemoved(t *testing.T) {
	dir := t.TempDir()
	folder := filepath.Join(dir, "days.html")
	if err := os.MkdirAll(folder, 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(folder, "x"), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	data := Placeholder("1.2.0")
	data.Hidden = map[string]bool{"days": true}
	if n, err := WriteSite(dir, data); err == nil {
		t.Errorf("want an error when days.html cannot be removed, got %d pages", n)
	}
}

// TestWriteSiteHidesAPageThatWasNeverWritten (forsgren#159): a hidden page
// with no file in a fresh out dir is no error.
func TestWriteSiteHidesAPageThatWasNeverWritten(t *testing.T) {
	data := Placeholder("1.2.0")
	data.Hidden = map[string]bool{"days": true}
	if n, err := WriteSite(t.TempDir(), data); err != nil || n != 7 {
		t.Errorf("want 7 pages and no error, got %d, %v", n, err)
	}
}

// writeStale leaves an old days.html and issues.html in dir.
func writeStale(t *testing.T, dir string) {
	t.Helper()
	for _, stale := range []string{"days.html", "issues.html"} {
		if err := os.WriteFile(filepath.Join(dir, stale), []byte("old"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
}

// wantRendered fails t for each of files that is missing from dir or still
// holds the old content.
func wantRendered(t *testing.T, dir string, files []string) {
	t.Helper()
	for _, f := range files {
		b, err := os.ReadFile(filepath.Clean(filepath.Join(dir, f)))
		if err != nil || string(b) == "old" {
			t.Errorf("want %s rendered, got %q, %v", f, b, err)
		}
	}
}

// wantGone fails t for each of files that is still in dir.
func wantGone(t *testing.T, dir string, files []string) {
	t.Helper()
	for _, f := range files {
		if _, err := os.Stat(filepath.Join(dir, f)); !os.IsNotExist(err) {
			t.Errorf("want %s gone from the site, got %v", f, err)
		}
	}
}
