// Package page renders forsgren's static status page.
//
// The templates are html/template files embedded into the binary, laid out
// as in another estate repository's admin: shared chrome in templates/layout/*.html (each
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
	"cmp"
	"embed"
	"fmt"
	"html/template"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"slices"

	"github.com/yveshanoulle/forsgren/internal/config"
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
	// Rows, when set, replace Message with one table, the five DORA metrics
	// as columns and these rows, in this order (forsgren#38; see Table).
	// The page shows project names, the owner's labels and the numbers
	// only, never a repository's or a task's own name.
	Rows []Row
	// AsOf is the UTC minute (2006-01-02 15:04) the numbers were calculated
	// at, which is also the moment their windows were counted back from; the
	// page shows it whenever it is set, with Rows or without (forsgren#41).
	AsOf string
	// Latest is the newest forsgren release, "0.0.10" or "v0.0.10", as the
	// caller looked it up; empty when unknown. The footer names it when it
	// is newer than Version (forsgren#40, option 2).
	Latest string
	// WaitingPR is the number of the open Dependabot pull request that bumps
	// the installation's forsgren pin to Latest, 0 when there is none; the
	// footer names it instead of "is available" (forsgren#40, option 1).
	WaitingPR int
	// NeedsCheck is how the check of what this version needs went (ok,
	// no-access, rate-limited or failed), empty when unknown; the footer says
	// so when the setup issue could not be written (forsgren#73).
	NeedsCheck string
	// WorkingHours is the hours of a working day and WorkingHoursSet says
	// whether the config sets it; the legend states both and derives the
	// on-demand threshold from it (forsgren#71).
	WorkingHours    int
	WorkingHoursSet bool
	// Settings are the config's optional keys with the values in use; the
	// settings page lists them, marking those the file does not set
	// (forsgren#74, #84).
	Settings []config.Setting
	// IssueDays are the issue counts per UTC day, newest first, that the
	// issues page tabulates (forsgren#76).
	IssueDays []metrics.IssueDay
	// View is the view the root page shows, "standard", "numbers" or
	// "scoring", with the view switch in its table's caption (forsgren#51);
	// empty for the plain root page, with no switch (forsgren#46).
	View string
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
// metrics, for the forsgren release version. It carries no timestamp (AsOf is
// the caller's clock), so two renders of it are byte-identical.
func Placeholder(version string) Data {
	return Data{Title: "forsgren", Version: version, Message: "no data yet"}
}

// WorkingDay is the hours of a working day, 8 when Data holds none.
func (d Data) WorkingDay() int { return metrics.WorkingDay(d.WorkingHours) }

// OnDemandFrom is the lowest 30-day count on demand for the working day.
func (d Data) OnDemandFrom() int { return metrics.OnDemandFrom(d.WorkingHours) }

// HourlyToDailyTo is the highest 30-day count between once per hour and once
// per day, one below OnDemandFrom.
func (d Data) HourlyToDailyTo() int { return d.OnDemandFrom() - 1 }

// pagesGlob matches one template file per page, named as the page it
// renders. parsePages and PageNames read the same set through it.
const pagesGlob = "templates/pages/*.html"

// issuesPage is the file of the issues page, the one page that is not a
// table and shows the view switch (forsgren#76).
const issuesPage = "issues.html"

// The views of the table page (forsgren#46): the standard cells, the numbers
// only, and (forsgren#47) each metric's DORA Quick Check score with an
// Overall Performance column.
const (
	viewStandard = "standard"
	viewNumbers  = "numbers"
	viewScoring  = "scoring"
)

// views are the views of the table page, in the switch's order, each
// rendered from index.html at its own address, /standard/, /numbers/ and
// /scoring/, one folder below the root.
var views = []string{viewStandard, viewNumbers, viewScoring}

// viewBase is the way back from a view's folder to the root.
const viewBase = "../"

// pageData is what a template sees: the page's Data, the prefix of its
// links to the root's files, and its view, empty on the root pages.
type pageData struct {
	Data
	// Base prefixes the links to styles.css, settings.html and legend.html:
	// empty at the root, viewBase in a view's folder.
	Base string
	// View is "standard", "numbers" or "scoring" on a view's page, and shows
	// the view switch; empty on the root pages.
	View string
	// Issues says whether the page is the issues page, which the view
	// switch names as its current entry (forsgren#76).
	Issues bool
}

// Numbers says whether the page is the numbers view, its cells the numbers
// only.
func (p pageData) Numbers() bool { return p.View == viewNumbers }

// Scoring says whether the page is the scoring view, its cells the scores
// and its last column Overall Performance.
func (p pageData) Scoring() bool { return p.View == viewScoring }

// Views are the views the switch names, in its order.
func (pageData) Views() []string { return views }

// Current is the switch's aria-current for the current view: "page" on the
// view's own page, "true" on the root, which shows the view but is not its
// page (Yves's ruling, forsgren#46).
func (p pageData) Current() string {
	if p.Base == viewBase {
		return "page"
	}
	return "true"
}

// page is a page's parsed template set, the template it executes, the
// view it shows and the prefix of its links to the root's files.
type page struct {
	set  *template.Template
	file string
	view string
	base string
}

// pages maps a page's name (index.html, standard/index.html) to its parsed
// template set.
var pages = parsePages()

// parsePages parses the layout once and clones it per page. A malformed
// template fails at start-up through template.Must, never at render time.
func parsePages() map[string]page {
	layout := template.Must(template.ParseFS(files, "templates/layout/*.html"))
	out := map[string]page{}
	// fs.Glob only errors on a malformed pattern; this one is constant.
	names, _ := fs.Glob(files, pagesGlob)
	for _, name := range names {
		set := template.Must(template.Must(layout.Clone()).ParseFS(files, name))
		out[path.Base(name)] = page{set: set, file: path.Base(name)}
	}
	for _, view := range views {
		out[view+"/index.html"] = page{set: out["index.html"].set, file: "index.html", view: view, base: viewBase}
	}
	return out
}

// PageNames returns the pages WriteSite writes, in a fixed (sorted) order.
func PageNames() []string {
	names := make([]string, 0, len(pages))
	for name := range pages {
		names = append(names, name)
	}
	slices.Sort(names)
	return names
}

// Render writes the named page, filled with data, to w.
func Render(w io.Writer, name string, data Data) error {
	p, ok := pages[name]
	if !ok {
		return fmt.Errorf("page %q not found", name)
	}
	shown := pageData{Data: data, Base: p.base, View: cmp.Or(p.view, data.View), Issues: p.file == issuesPage}
	return p.set.ExecuteTemplate(w, p.file, shown)
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
	file := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(file), 0o750); err != nil {
		return err
	}
	return os.WriteFile(file, buf.Bytes(), 0o600)
}

func copyStyles(dir string) error {
	css, err := files.ReadFile("styles.css")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "styles.css"), css, 0o600)
}
