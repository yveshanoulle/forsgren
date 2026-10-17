package page

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestWriteSiteWritesTheFaviconNextToTheStylesheet (forsgren#218): favicon.svg
// is written beside styles.css with the embedded bytes, a small SVG.
func TestWriteSiteWritesTheFaviconNextToTheStylesheet(t *testing.T) {
	dir := t.TempDir()
	if _, err := WriteSite(dir, Placeholder("1.9.2")); err != nil {
		t.Fatalf("WriteSite: %v", err)
	}
	got, err := os.ReadFile(filepath.Clean(filepath.Join(dir, "favicon.svg")))
	if err != nil {
		t.Fatalf("want favicon.svg in the site: %v", err)
	}
	if !bytes.Equal(got, Favicon()) || !bytes.HasPrefix(got, []byte("<svg ")) {
		t.Errorf("want the embedded favicon (an <svg ...>), got %q", got)
	}
	if len(got) > 1024 {
		t.Errorf("want a tiny favicon, got %d bytes", len(got))
	}
}

// TestEveryPageLinksTheFaviconByItsRelativePath (forsgren#218): each page's
// head links favicon.svg through Base, ../ one folder down.
func TestEveryPageLinksTheFaviconByItsRelativePath(t *testing.T) {
	for _, name := range PageNames() {
		base := strings.Repeat("../", strings.Count(name, "/"))
		want := `<link rel="icon" href="` + base + `favicon.svg" type="image/svg+xml">`
		wantAll(t, name, rendered(t, name, Placeholder("1.9.2")), want)
	}
}

// TestWriteSiteFailsWhenTheFaviconCannotBeWritten (forsgren#218): a folder
// where favicon.svg goes is an error, never a site without its icon.
func TestWriteSiteFailsWhenTheFaviconCannotBeWritten(t *testing.T) {
	dir := t.TempDir()
	if err := os.Mkdir(filepath.Join(dir, "favicon.svg"), 0o750); err != nil {
		t.Fatal(err)
	}
	if _, err := WriteSite(dir, Placeholder("1.9.2")); err == nil {
		t.Error("want an error when favicon.svg cannot be written, got none")
	}
}
