package page

import (
	"bytes"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// tbdData is the TBD page's data: Acme Shop with 4 commits and a deviation,
// Acme Tools with 2 commits, so a mean and no deviation, and Acme Docs with
// no commit; their Developers, with commits without a known author for Acme
// Tools and Acme Web.
func tbdData() Data {
	data := calculated()
	data.Mainline = []metrics.MainlineInterval{
		{Project: "Acme Shop", Commits: 4, Gaps: 3, Mean: 2 * time.Hour, Deviation: time.Hour, Median: 2 * time.Hour},
		{Project: "Acme Tools", Commits: 2, Gaps: 1, Mean: 2 * time.Hour},
		{Project: "Acme Docs"},
		{Project: "Acme Web", Commits: 13, Gaps: 12, Mean: 24 * time.Minute, Deviation: 2*time.Hour + 24*time.Minute,
			Median: 5 * time.Minute, P90: time.Hour},
	}
	data.Developers = []metrics.Developers{
		{Project: "Acme Shop", Count: 3},
		{Project: "Acme Tools", Count: 1, Unknown: 1},
		{Project: "Acme Docs"},
		{Project: "Acme Web", Count: 12, Unknown: 2},
	}
	return data
}

// tbdRow is the TBD page's row of project, its Mainline Interval cell then its
// Developers cell, as the template writes it.
func tbdRow(project, interval, developers string) string {
	return "<th scope=\"row\">" + project + "</th>\n            <td>" + interval + "</td>\n            <td>" +
		developers + "</td>\n"
}

// TestTbdPageShowsTheDevelopersNextToTheInterval (forsgren#273, step 3): a
// Developers column follows the Mainline Interval, each project's cell its
// count, then the note on the commits without a known author when there are,
// in the same row as the project's interval.
func TestTbdPageShowsTheDevelopersNextToTheInterval(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got,
		"<th scope=\"col\">Mainline Interval</th>\n            <th scope=\"col\">Developers</th>\n",
		tbdRow("Acme Shop", "2 h ± 1 h (3) · median 2 h · p90 -", "3"),
		tbdRow("Acme Tools", "2 h ± - (1) · median - · p90 -", "1 · 1 commit without a known author is not counted"),
		tbdRow("Acme Docs", "-", "0"),
		tbdRow("Acme Web", "24 min ± 2 h 24 min (12) · median 5 min · p90 1 h",
			"12 · 2 commits without a known author are not counted"))
}

// TestTbdPageRefusesDevelopersOfOtherProjects (forsgren#273, step 3): the
// Developers are paired with the Mainline Intervals by project, so a render
// whose Developers are missing, one too many, or name another project in a
// row, fails instead of showing a count in the wrong row.
func TestTbdPageRefusesDevelopersOfOtherProjects(t *testing.T) {
	missing := tbdData()
	missing.Developers = missing.Developers[:3]
	extra := tbdData()
	extra.Developers = append(extra.Developers, metrics.Developers{Project: "Acme Gone", Count: 1})
	swapped := tbdData()
	swapped.Developers[0], swapped.Developers[1] = swapped.Developers[1], swapped.Developers[0]
	for name, data := range map[string]Data{"missing": missing, "extra": extra, "swapped": swapped} {
		var got bytes.Buffer
		if err := Render(&got, "tbd.html", data); err == nil {
			t.Errorf("%s: want the render to fail, got:\n%s", name, got.String())
		}
	}
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
// with no caption, columns Project and Mainline Interval (and Developers,
// forsgren#273) and no Mainline Lead Time column; each project's cell is the metric's own, "-" below two commits.
func TestTbdPageHasItsHeadingAndTable(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got, "<title>Trunk-based development [TBD] (BETA) · ",
		`<h1 id="tbd-heading">Trunk-based development [TBD] (BETA)</h1>`, `aria-labelledby="tbd-heading"`,
		`<th scope="col">Project</th>`, `<th scope="col">Mainline Interval</th>`,
		`<th scope="row">Acme Shop</th>`, "<td>2 h ± 1 h (3) · median 2 h · p90 -</td>",
		`<th scope="row">Acme Tools</th>`, "<td>2 h ± - (1) · median - · p90 -</td>",
		`<th scope="row">Acme Docs</th>`, "<td>-</td>",
		`<th scope="row">Acme Web</th>`, "<td>24 min ± 2 h 24 min (12) · median 5 min · p90 1 h</td>")
	wantNone(t, "tbd.html", got, "<caption", "Mainline Lead Time", "metrics are coming to this page")
}

// TestTbdPageHasNoExplanationAndNoLeadTimeLine (forsgren#271): the h1 is
// followed by the table, or by its one line; the explanation of the Mainline
// Interval and the line on Mainline Lead Time are the legend's, not the page's.
func TestTbdPageHasNoExplanationAndNoLeadTimeLine(t *testing.T) {
	for name, data := range map[string]Data{"data": tbdData(), "no data": calculated()} {
		wantNone(t, name, rendered(t, "tbd.html", data), "sample standard deviation", "deployments of the last",
			"Mainline Lead Time", "A dash is", "each commit once")
	}
}

// TestTbdTitleIsYvesWording (forsgren#271): the title and the h1 of the TBD
// page read exactly "Trunk-based development [TBD] (BETA)", the BETA in
// capitals as Yves wrote it, the same marker the History page reads (forsgren#198).
func TestTbdTitleIsYvesWording(t *testing.T) {
	const want = "Trunk-based development [TBD] (BETA)"
	if got := calculated().TbdTitle(); got != want {
		t.Errorf("want the title %q, got %q", want, got)
	}
	history := rendered(t, "history.html", historyData())
	wantAll(t, "history.html", history, `<h1 id="history-heading">History (BETA)</h1>`)
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
		wantAll(t, name, got, "<p>"+c.want+"</p>")
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
