package page

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// tbdData is the TBD page's data: Acme Shop with 4 commits and a deviation,
// Acme Tools with 2 commits, so a mean and no deviation, and Acme Docs with
// no commit.
func tbdData() Data {
	data := calculated()
	data.Mainline = []metrics.MainlineInterval{
		{Project: "Acme Shop", Commits: 4, Gaps: 3, Mean: 2 * time.Hour, Deviation: time.Hour},
		{Project: "Acme Tools", Commits: 2, Gaps: 1, Mean: 2 * time.Hour},
		{Project: "Acme Docs"},
	}
	return data
}

// TestTbdPageGolden (forsgren#253, step 4 of 7): the TBD page is a root page,
// tbd.html, with a table of a row per project and one column, the Mainline
// Interval, and a line that says Mainline Lead Time comes later; with no
// projects, or no Mainline Interval read yet, one line says why in place of
// the table.
func TestTbdPageGolden(t *testing.T) {
	noProjects := calculated()
	noProjects.NoProjects = true
	checkPageGolden(t, "tbd.html", "testdata/tbd.golden.html", tbdData())
	checkPageGolden(t, "tbd.html", "testdata/tbd.no-data.golden.html", calculated())
	checkPageGolden(t, "tbd.html", "testdata/tbd.no-projects.golden.html", noProjects)
}

// TestTbdPageHasItsHeadingAndTable (forsgren#253): the title and the h1 (id
// tbd-heading) name trunk-based development; the table is the h1's region,
// with no caption, columns Project and Mainline Interval and no Mainline Lead
// Time column; each project's cell is the metric's own, "-" below two commits.
func TestTbdPageHasItsHeadingAndTable(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got, "<title>Trunk-based development (TBD) · ",
		`<h1 id="tbd-heading">Trunk-based development (TBD)</h1>`, `aria-labelledby="tbd-heading"`,
		`<th scope="col">Project</th>`, `<th scope="col">Mainline Interval</th>`,
		`<th scope="row">Acme Shop</th>`, "<td>2 h ± 1 h (3)</td>",
		`<th scope="row">Acme Tools</th>`, "<td>2 h ± - (1)</td>",
		`<th scope="row">Acme Docs</th>`, "<td>-</td>")
	wantNone(t, "tbd.html", got, "<caption", `<th scope="col">Mainline Lead Time`, "metrics are coming to this page")
}

// TestTbdPageSaysWhatItCountsAndWhatComesLater (forsgren#253): under the
// heading, one line names the window (the DORA window in force) and that the
// commits are the deployed ones; another says Mainline Lead Time is coming.
func TestTbdPageSaysWhatItCountsAndWhatComesLater(t *testing.T) {
	data := tbdData()
	data.DoraDays = 90
	wantAll(t, "tbd.html", rendered(t, "tbd.html", data), "commits that deployments of the last 90 days shipped",
		"<p>Mainline Lead Time is coming later.</p>")
	wantAll(t, "tbd.html", rendered(t, "tbd.html", tbdData()), "deployments of the last 30 days")
}

// TestTbdPageSaysWhyItHasNoTable (forsgren#253): with no projects, or no
// Mainline Interval read, the page shows one line and no table.
func TestTbdPageSaysWhyItHasNoTable(t *testing.T) {
	noProjects := calculated()
	noProjects.NoProjects = true
	for name, c := range map[string]struct {
		data Data
		want string
	}{
		"no projects": {noProjects, "No projects are listed yet, so there is no Mainline Interval to show."},
		"no data":     {calculated(), "No commits have been collected yet, so there is no Mainline Interval to show."},
	} {
		got := rendered(t, "tbd.html", c.data)
		wantAll(t, name, got, "<p>"+c.want+"</p>", "<p>Mainline Lead Time is coming later.</p>")
		wantNone(t, name, got, "<table")
	}
}

// TestTbdPageIsAfterHistoryInTheRootPages (forsgren#253): the page is one of
// the root pages, labelled TBD, after the History page.
func TestTbdPageIsAfterHistoryInTheRootPages(t *testing.T) {
	last := rootPages[len(rootPages)-1]
	if last.Name != TbdPage || last.Label != "TBD" {
		t.Errorf("want the last root page %q labelled TBD, got %+v", TbdPage, last)
	}
}
