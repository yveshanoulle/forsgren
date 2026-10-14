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
	"errors"
	"fmt"
	"html/template"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"

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
	// days page tabulates (forsgren#76, forsgren#123, forsgren#128).
	IssueDays []metrics.IssueDay
	// IssueRows are the rows of the issues page by kind, days, weeks and
	// months, newest first in that order (forsgren#76, forsgren#89,
	// decision #118, forsgren#123).
	IssueRows []metrics.IssueRow
	// View is the view the root page shows, "standard", "numbers" or
	// "scoring", marked in the menu (forsgren#46, forsgren#128); empty for the
	// plain root page, whose menu marks no view.
	View string
	// Hidden are the pages the site leaves out, by page name (IssuesPage,
	// DaysPage); the zero value hides none (forsgren#159).
	Hidden map[string]bool
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

// IssueTableRow is a row of the issues page: the counts of an IssueDay under
// the Label of its kind.
type IssueTableRow struct {
	Label string
	metrics.IssueDay
}

// IssueTableRows are the rows of the issues page, IssueRows labelled: a day
// by its date, a week by the ISO number of its Monday ("Week 41"), a month by
// its name and year, a year by the year.
func (d Data) IssueTableRows() []IssueTableRow {
	table := make([]IssueTableRow, len(d.IssueRows))
	for i, r := range d.IssueRows {
		table[i] = IssueTableRow{Label: issueRowLabel(r), IssueDay: r.IssueDay}
	}
	return table
}

// issueRowLabel is the label of r's kind: the date of a day, "Week 41" for a
// week, "September 2026" for a month, "2025" for a year.
func issueRowLabel(r metrics.IssueRow) string {
	switch r.Kind {
	case metrics.KindWeek:
		_, week := r.Date.ISOWeek()
		return fmt.Sprintf("Week %d", week)
	case metrics.KindMonth:
		return r.Date.Format("January 2006")
	case metrics.KindYear:
		return r.Date.Format("2006")
	}
	return r.Date.Format("2006-01-02")
}

// AnyIssueDayActive says whether some day of IssueDays is Active, that is
// whether the days page has a row to show (forsgren#108).
func (d Data) AnyIssueDayActive() bool {
	return slices.ContainsFunc(d.IssueDays, func(day metrics.IssueDay) bool { return day.Active })
}

// AnyIssueRowActive says whether some row of the issues page, of any kind, is
// Active, that is whether it has a row to show (forsgren#108, forsgren#123).
func (d Data) AnyIssueRowActive() bool {
	return slices.ContainsFunc(d.IssueRows, func(r metrics.IssueRow) bool { return r.Active })
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

// issuePage is a page that tabulates issues, not metrics: its file is
// <Name>.html and the menu calls it Label.
type issuePage struct{ Name, Label string }

// issuePages are the pages that tabulate issues, in the order the menu names
// them after the views: the issues page (forsgren#123, forsgren#128: the
// weeks, months and years) and the days page (forsgren#76, forsgren#128: the
// last 30 days, labelled Daily).
var issuePages = []issuePage{{IssuesPage, "Issues"}, {DaysPage, "Daily"}}

// IssuesPage and DaysPage are the names of the two issue pages, the keys of
// Data.Hidden (forsgren#159).
const (
	IssuesPage = "issues"
	DaysPage   = "days"
)

// The views of the table page (forsgren#46): the standard cells, the numbers
// only, and (forsgren#47) each metric's DORA Quick Check score with an
// Overall Performance column.
const (
	viewStandard = "standard"
	viewNumbers  = "numbers"
	viewScoring  = "scoring"
)

// views are the views of the table page, in the menu's order, each
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
	// View is the view the page shows and its menu marks, "standard",
	// "numbers" or "scoring" on a view's page and the root's; empty on the
	// other pages (forsgren#128).
	View string
	// Page is the page's name, its file without ".html": the menu marks
	// the one of issuePages it names as current (forsgren#76, forsgren#123,
	// forsgren#128).
	Page string
}

// Numbers says whether the page is the numbers view, its cells the numbers
// only.
func (p pageData) Numbers() bool { return p.View == viewNumbers }

// Scoring says whether the page is the scoring view, its cells the scores
// and its last column Overall Performance.
func (p pageData) Scoring() bool { return p.View == viewScoring }

// menuItem is one entry of the menu: its address from the root, its label,
// and its aria-current, empty for an entry that is a link.
type menuItem struct{ Href, Label, Current string }

// Menu is the menu at the top of the page (forsgren#128, decision #133): the
// views, each labelled by its name with a capital (its address stays lower
// case), then the issuePages the site shows (forsgren#159). The view the
// page shows is marked current, and the issue page the page is marked "page";
// every other entry is a link.
func (p pageData) Menu() []menuItem {
	menu := make([]menuItem, 0, len(views)+len(issuePages))
	for _, view := range views {
		label := strings.ToUpper(view[:1]) + view[1:]
		menu = append(menu, menuItem{view + "/", label, markIf(view == p.View, p.viewCurrent())})
	}
	for _, issues := range issuePages {
		if p.Hidden[issues.Name] {
			continue
		}
		menu = append(menu, menuItem{issues.Name + ".html", issues.Label, markIf(issues.Name == p.Page, "page")})
	}
	return menu
}

// markIf is the aria-current mark of the entry the page is on, empty for the
// others.
func markIf(on bool, mark string) string {
	if on {
		return mark
	}
	return ""
}

// viewCurrent is the menu's aria-current for the view the page shows: "page"
// on the view's own page, "true" on the root, which shows the view but is not
// its page (Yves's ruling, forsgren#46).
func (p pageData) viewCurrent() string {
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

// templateFuncs are the functions the templates call: "trend", the arrow of
// the issues tables (trend.go), and "possible", the settings page's Possible
// values cell (settings.go).
var templateFuncs = template.FuncMap{"trend": trendViewOf, "possible": possibleOf}

// parsePages parses the layout once and clones it per page. A malformed
// template fails at start-up through template.Must, never at render time.
func parsePages() map[string]page {
	layout := template.Must(template.New("layout").Funcs(templateFuncs).ParseFS(files, "templates/layout/*.html"))
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

// name is the page's name, its file without ".html": "index" for the root
// and each view's page.
func (p page) name() string { return strings.TrimSuffix(p.file, ".html") }

// viewShown is the view the page shows and its menu marks: a view's page its
// own, the root the configured one, and every other page none, so its menu
// links all three views (forsgren#76, decision #102, forsgren#128).
func (p page) viewShown(data Data) string {
	if p.file != "index.html" {
		return ""
	}
	return cmp.Or(p.view, data.View)
}

// Render writes the named page, filled with data, to w.
func Render(w io.Writer, name string, data Data) error {
	p, ok := pages[name]
	if !ok {
		return fmt.Errorf("page %q not found", name)
	}
	shown := pageData{Data: data, Base: p.base, View: p.viewShown(data), Page: p.name()}
	return p.set.ExecuteTemplate(w, p.file, shown)
}

// WriteSite renders every page and copies styles.css into dir, creating
// dir when needed. It returns how many pages it wrote; styles.css is not a
// page and is not counted.
func WriteSite(dir string, data Data) (int, error) {
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return 0, err
	}
	site := siteDir(dir)
	if err := copyStyles(site); err != nil {
		return 0, err
	}
	written := 0
	for _, name := range PageNames() {
		wrote, err := writeOrRemovePage(site, name, data)
		if err != nil {
			return written, err
		}
		if wrote {
			written++
		}
	}
	return written, nil
}

// writeOrRemovePage writes the page, or removes its file when the site hides
// it; it says whether it wrote the page (forsgren#159).
func writeOrRemovePage(dir siteDir, name string, data Data) (bool, error) {
	if data.hides(name) {
		return false, removePage(dir, name)
	}
	return true, writePage(dir, name, data)
}

// hides says whether the site leaves out the page called name (its file
// without ".html"), forsgren#159.
func (d Data) hides(name string) bool { return d.Hidden[strings.TrimSuffix(name, ".html")] }

// removePage deletes the file of a hidden page from a reused out dir; a page
// that was never written is not an error.
func removePage(dir siteDir, name string) error {
	err := os.Remove(filepath.Join(string(dir), name))
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	return err
}

// siteDir is the folder WriteSite writes the site into.
type siteDir string

// writePage renders one page into memory first, so a failing template never
// leaves a half-written file behind.
func writePage(dir siteDir, name string, data Data) error {
	var buf bytes.Buffer
	if err := Render(&buf, name, data); err != nil {
		return fmt.Errorf("render %s: %w", name, err)
	}
	file := filepath.Join(string(dir), name)
	if err := os.MkdirAll(filepath.Dir(file), 0o750); err != nil {
		return err
	}
	return os.WriteFile(file, buf.Bytes(), 0o600)
}

// stylesheet is styles.css as authored, for Styles.
//
//go:embed styles.css
var stylesheet []byte

// Styles is the one stylesheet every page of the site links, as authored.
// The starter page (forsgren#132) is styled with it too.
func Styles() []byte {
	return stylesheet
}

func copyStyles(dir siteDir) error {
	return os.WriteFile(filepath.Join(string(dir), "styles.css"), Styles(), 0o600)
}
