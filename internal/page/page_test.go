package page

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// -update rewrites the golden files from the current output. Use it only
// after reading the diff the failing golden test printed.
var update = flag.Bool("update", false, "rewrite testdata/*.golden.html")

func TestPlaceholderMatchesGolden(t *testing.T) {
	checkGolden(t, "testdata/index.golden.html", Placeholder("0.0.2"))
}

// TestNoProjectsPageMatchesGolden (forsgren#12): the page of an installation
// whose config lists no projects says so, besides its version.
func TestNoProjectsPageMatchesGolden(t *testing.T) {
	data := Placeholder("0.0.2")
	data.NoProjects = true
	checkGolden(t, "testdata/index.no-projects.golden.html", data)
}

// checkGolden renders index.html with data and compares it with the golden
// file, rewriting it first under -update.
func checkGolden(t *testing.T, golden string, data Data) {
	t.Helper()
	var got bytes.Buffer
	if err := Render(&got, "index.html", data); err != nil {
		t.Fatalf("Render: %v", err)
	}
	if *update {
		if err := os.WriteFile(golden, got.Bytes(), 0o600); err != nil {
			t.Fatalf("update golden: %v", err)
		}
	}
	want, err := os.ReadFile(filepath.Clean(golden))
	if err != nil {
		t.Fatalf("read golden: %v", err)
	}
	if !bytes.Equal(got.Bytes(), want) {
		t.Errorf("index.html differs from %s\n--- got ---\n%s\n--- want ---\n%s", golden, got.String(), want)
	}
}

func TestRenderEscapesFields(t *testing.T) {
	var got bytes.Buffer
	data := Data{Title: "forsgren", Message: `<script>alert("x")</script>`}
	if err := Render(&got, "index.html", data); err != nil {
		t.Fatalf("Render: %v", err)
	}
	if strings.Contains(got.String(), "<script>") {
		t.Errorf("a <script> in a field reached the page unescaped:\n%s", got.String())
	}
	if !strings.Contains(got.String(), "&lt;script&gt;") {
		t.Errorf("want the field escaped as &lt;script&gt;, got:\n%s", got.String())
	}
}

func TestRenderUnknownPage(t *testing.T) {
	err := Render(&bytes.Buffer{}, "missing.html", Placeholder("0.0.2"))
	if err == nil || !strings.Contains(err.Error(), "missing.html") {
		t.Errorf("want an error naming missing.html, got %v", err)
	}
}

func TestWriteSiteWritesOnePageAndStyles(t *testing.T) {
	dir := t.TempDir()
	n, err := WriteSite(dir, Placeholder("0.0.2"))
	if err != nil {
		t.Fatalf("WriteSite: %v", err)
	}
	if n != 1 {
		t.Errorf("want 1 page written, got %d", n)
	}
	for _, name := range []string{"index.html", "styles.css"} {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			t.Errorf("want %s in the site: %v", name, err)
		}
	}
}

func TestWriteSiteFailsWhenDirIsAFile(t *testing.T) {
	file := filepath.Join(t.TempDir(), "not-a-dir")
	if err := os.WriteFile(file, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if n, err := WriteSite(file, Placeholder("0.0.2")); err == nil {
		t.Errorf("want an error when the output is a regular file, got %d pages", n)
	}
}
