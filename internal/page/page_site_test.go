package page

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

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
	err := Render(&bytes.Buffer{}, "missing.html", Placeholder(testVersion))
	if err == nil || !strings.Contains(err.Error(), "missing.html") {
		t.Errorf("want an error naming missing.html, got %v", err)
	}
}

// TestWriteSiteWritesFourteenPagesAndStyles (forsgren#253, #55, #46, #47, #84, #76, #123, #128, #579): the
// root page, the legend, the settings page, the days page and the issues page, and each
// view's page, standard, numbers and scoring, in its own folder, and the numbers and scoring page.
func TestWriteSiteWritesFourteenPagesAndStyles(t *testing.T) {
	dir := t.TempDir()
	n, err := WriteSite(dir, Placeholder(testVersion))
	if err != nil {
		t.Fatalf("WriteSite: %v", err)
	}
	if n != 14 {
		t.Errorf("want 14 pages written, got %d", n)
	}
	for _, name := range []string{
		"index.html", "legend.html", "settings.html", "days.html", "issues.html", "standard/index.html",
		"numbers/index.html", "scoring/index.html", "numbers-scoring/index.html", "history.html", "tbd.html",
		"week.html", "data.html", "dictionary.html", "styles.css",
	} {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			t.Errorf("want %s in the site: %v", name, err)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "months.html")); err == nil {
		t.Error("want no months.html in the site: it is issues.html now (forsgren#128)")
	}
}

func TestWriteSiteFailsWhenDirIsAFile(t *testing.T) {
	file := filepath.Join(t.TempDir(), "not-a-dir")
	if err := os.WriteFile(file, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if n, err := WriteSite(file, Placeholder(testVersion)); err == nil {
		t.Errorf("want an error when the output is a regular file, got %d pages", n)
	}
}

// TestTablePageOpensWithTheTable (forsgren#41, step 1; forsgren#135): the table
// page has no Calculated paragraph above its table, only the heading (the
// version is in the footer).
func TestTablePageOpensWithTheTable(t *testing.T) {
	wantNone(t, "index.html", rendered(t, "index.html", acmeTable()), "counts back from the time in the footer")
}

// TestNoProjectsPageShowsAHowTo (forsgren#41, step 3): where the table would
// be, a page with no projects says that forsgren.config.yml lists them, shows
// a small example with the optional label, and links straight to
// docs/configuration.md; the one-line message is gone.
func TestNoProjectsPageShowsAHowTo(t *testing.T) {
	data := Placeholder(testVersion)
	data.NoProjects = true
	got := rendered(t, "index.html", data)
	wantAll(t, "index.html", got,
		"forsgren.config.yml lists the projects",
		"<pre><code>version: 1\nprojects:\n  - name: Acme Shop\n    repositories:\n",
		"        label: iOS\n",
		`<a href="https://forsgren.be/#configuration">`,
	)
	wantNone(t, "index.html", got, "No projects configured yet")
}
