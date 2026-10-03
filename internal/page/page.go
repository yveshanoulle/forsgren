// Package page renders forsgren's static status page.
//
// The templates are html/template files embedded into the binary, laid out
// as in MenoPower's admin: shared chrome in templates/layout/*.html (each
// file one {{define}}), one file per page in templates/pages/*.html. Every
// page is parsed onto its own clone of the layout set, so two pages can
// never see each other's definitions.
//
// html/template, never text/template: the page is meant to be public, and
// html/template escapes every value by context. TestRenderEscapesFields
// pins that.
package page

import (
	"bytes"
	"embed"
	"fmt"
	"html/template"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

//go:embed templates styles.css
var files embed.FS

// Data is what a page shows: the placeholder (see Placeholder), and with an
// installation's history, each project's DORA numbers.
type Data struct {
	Title   string
	Version string
	Message string
	// NoProjects makes the page say that no projects are configured yet:
	// the installation's forsgren.config.yml lists none (forsgren#12).
	NoProjects bool
	// Projects, when set, replace Message with one section per project, in
	// this order (forsgren#12, step 7; forsgren#16, step 5; forsgren#17;
	// forsgren#18).
	// The page shows
	// their project names, numbers, durations and dates only.
	Projects []Project
	// AsOf is the UTC minute (2006-01-02 15:04) the numbers were calculated
	// at, which is also the moment their windows were counted back from; the
	// page shows it with Projects only.
	AsOf string
}

// Project is one project's section: its deployment frequency (whose fields
// the template reads directly), its lead time for changes, its failed
// deployment recovery time and its change fail rate.
type Project struct {
	metrics.Frequency
	LeadTime   metrics.LeadTime
	Recovery   metrics.Recovery
	ChangeFail metrics.ChangeFailRate
}

// Placeholder is the data of the page forsgren renders before it has any
// metrics, for the forsgren release version. It carries no timestamp, so
// two renders are byte-identical.
func Placeholder(version string) Data {
	return Data{Title: "forsgren", Version: version, Message: "no data yet"}
}

// pagesGlob matches one template file per page, named as the page it
// renders. parsePages and PageNames read the same set through it.
const pagesGlob = "templates/pages/*.html"

// pages maps a page's file name (index.html) to its parsed template set.
var pages = parsePages()

// parsePages parses the layout once and clones it per page. A malformed
// template fails at start-up through template.Must, never at render time.
func parsePages() map[string]*template.Template {
	layout := template.Must(template.ParseFS(files, "templates/layout/*.html"))
	out := map[string]*template.Template{}
	// fs.Glob only errors on a malformed pattern; this one is constant.
	names, _ := fs.Glob(files, pagesGlob)
	for _, name := range names {
		set := template.Must(template.Must(layout.Clone()).ParseFS(files, name))
		out[path.Base(name)] = set
	}
	return out
}

// PageNames returns the pages WriteSite writes, in a fixed (sorted) order.
func PageNames() []string {
	names, _ := fs.Glob(files, pagesGlob)
	for i, name := range names {
		names[i] = path.Base(name)
	}
	return names
}

// Render writes the named page, filled with data, to w.
func Render(w io.Writer, name string, data Data) error {
	set, ok := pages[name]
	if !ok {
		return fmt.Errorf("page %q not found", name)
	}
	return set.ExecuteTemplate(w, name, data)
}

// WriteSite renders every page and copies styles.css into dir, creating
// dir when needed. It returns how many pages it wrote; styles.css is not a
// page and is not counted.
func WriteSite(dir string, data Data) (int, error) {
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return 0, err
	}
	if err := copyStyles(dir); err != nil {
		return 0, err
	}
	written := 0
	for _, name := range PageNames() {
		if err := writePage(dir, name, data); err != nil {
			return written, err
		}
		written++
	}
	return written, nil
}

// writePage renders one page into memory first, so a failing template never
// leaves a half-written file behind.
func writePage(dir, name string, data Data) error {
	var buf bytes.Buffer
	if err := Render(&buf, name, data); err != nil {
		return fmt.Errorf("render %s: %w", name, err)
	}
	return os.WriteFile(filepath.Join(dir, name), buf.Bytes(), 0o600)
}

func copyStyles(dir string) error {
	css, err := files.ReadFile("styles.css")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "styles.css"), css, 0o600)
}
