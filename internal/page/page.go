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
	// Rows, when set, replace Message with one table, the four DORA metrics
	// as columns and these rows, in this order (forsgren#38; see Table).
	// The page shows project names, the owner's labels and the numbers
	// only, never a repository's or a task's own name.
	Rows []Row
	// AsOf is the UTC minute (2006-01-02 15:04) the numbers were calculated
	// at, which is also the moment their windows were counted back from; the
	// page shows it with Rows only.
	AsOf string
}

// Row is one row of the table: its numbers, the heading the page gives it,
// and for a label's row the project it is under.
type Row struct {
	metrics.Row
	Heading string
	Project string
}

// IsLabel says whether the row is a label's, under its project's total.
func (r Row) IsLabel() bool { return r.Level == metrics.LabelRow }

// Table is the page's rows for the metrics' rows, in their order: a
// project's row is headed by its name, "Acme Shop (total)" when label rows
// follow it, and a label's row by the label, with its project's name for
// a screen reader.
func Table(rows []metrics.Row) []Row {
	out := make([]Row, len(rows))
	var total *Row
	for i, r := range rows {
		out[i] = Row{Row: r, Heading: r.Name}
		switch {
		case r.Level == metrics.ProjectRow:
			total = &out[i]
		case total != nil:
			out[i].Project = total.Name
			total.Heading = total.Name + " (total)"
		}
	}
	return out
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
