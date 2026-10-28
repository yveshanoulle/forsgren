package page

import (
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The Week page (forsgren#531, step 2, decisions #532 A, #533 A, #534 A): a
// table with a row per project and per label, service and rule, the commits
// and deployments of the DORA window per weekday.

// weekPageData is the Week page's data: Acme Shop's total, its Website
// label, its API service without paths (commits not attributed), and Acme
// Docs with deployments and no commit. The made-up counts differ so no cell repeats.
func weekPageData() Data {
	data := calculated()
	data.Week = metrics.Week{
		Start: time.Date(2026, 9, 3, 12, 0, 0, 0, time.UTC),
		End:   time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC),
		Rows: []metrics.WeekRow{
			{Level: metrics.ProjectRow, Name: "Acme Shop", Project: "Acme Shop",
				Commits:     [7]int{31, 40, 1234, 8, 17, 6, 2},
				Deployments: [7]int{4, 5, 9, 1, 0, 3, 7},
				Failed:      [7]int{1, 0, 3, 0, 0, 0, 3}},
			{Level: metrics.LabelRow, Name: "Website", Project: "Acme Shop",
				Commits:     [7]int{3, 0, 1, 0, 2, 2, 1},
				Deployments: [7]int{2, 3, 1, 5, 4, 6, 7}},
			{Level: metrics.LabelRow, Name: "API", Project: "Acme Shop", Service: true, PerRepository: true,
				Deployments: [7]int{3, 1, 4, 2, 12, 5, 9},
				Failed:      [7]int{0, 0, 1, 0, 2, 0, 0}},
			{Level: metrics.ProjectRow, Name: "Acme Docs", Project: "Acme Docs",
				Deployments: [7]int{1, 3, 2, 6, 5, 4, 8}},
		},
	}
	data.WeekCommits = true
	return data
}

func TestWeekPageMatchesGolden(t *testing.T) {
	checkPageGolden(t, "week.html", "testdata/week.golden.html", weekPageData())
}

func TestWeekPageWithoutProjectsMatchesGolden(t *testing.T) {
	data := calculated()
	data.NoProjects = true
	checkPageGolden(t, "week.html", "testdata/week.no-projects.golden.html", data)
}

func TestWeekPageWithoutDataMatchesGolden(t *testing.T) {
	checkPageGolden(t, "week.html", "testdata/week.no-data.golden.html", calculated())
}

func TestWeekPageWithoutSubRowsMatchesGolden(t *testing.T) {
	data := weekPageData()
	data.HideSubRows = true
	checkPageGolden(t, "week.html", "testdata/week.no-sub-rows.golden.html", data)
}

// TestWeekPageHasNoExplanationLines (forsgren#544): the reading line and the window
// sentence are the legend's; the page is its h1 and the table, or its one message.
func TestWeekPageHasNoExplanationLines(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantNone(t, "week.html", got, "Total is the commits", "every weekday of that window", "The last 30 days")
	wantAll(t, "week.html", got, "</h1>\n    <div class=\"table-scroll\"")
	data := calculated()
	data.NoProjects = true
	wantAll(t, "week.html", rendered(t, "week.html", data), "</h1>\n    <p>No projects are listed yet")
}

// TestWeekPageHasTwoHeaderRows (forsgren#540, decision #541): Project
// spans both rows, Total and the seven weekdays in full are
// column groups of four, and each group has Commits, Deployments, Failed and Fail rate under it, the
// cell headers naming their group for a screen reader.
func TestWeekPageHasTwoHeaderRows(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got, `<h1 id="week-heading">Week</h1>`,
		`<th scope="col" rowspan="2">Project</th>`,
		`<th scope="colgroup" colspan="4">Total</th>`, `<th scope="colgroup" colspan="4">Monday</th>`,
		`<th scope="colgroup" colspan="4">Thursday</th>`, `<th scope="colgroup" colspan="4">Sunday</th>`,
		`<th scope="col" aria-label="Total commits" class="num">Commits</th>`,
		`<th scope="col" aria-label="Total deployments" class="num">Deployments</th>`,
		`<th scope="col" aria-label="Monday commits" class="num">Commits</th>`,
		`<th scope="col" aria-label="Sunday deployments" class="num">Deployments</th>`,
		`<th scope="col" aria-label="Total failed deployments" class="num">Failed</th>`,
		`<th scope="col" aria-label="Total fail rate" class="num">Fail rate</th>`,
		`<th scope="col" aria-label="Monday failed deployments" class="num">Failed</th>`,
		`<th scope="col" aria-label="Sunday fail rate" class="num">Fail rate</th>`)
	wantNone(t, "week.html", got, ">Mon<", ">Sun<", "commits · deployments")
	wantCount(t, got, `<th scope="colgroup" colspan="4">`, 8)
	wantCount(t, got, `<th scope="col" aria-label=`, 32)
	wantCount(t, got, `<th scope="col" rowspan="2"`, 1)
	wantNone(t, "week.html", got, "Weekend share", "Deploys")
}

// TestWeekPageCellsAreTotalsAndPercentages: the Total as counts with the
// thousands space, the weekday cells as percents written as the TBD shares are, 0% for a
// day without any, a dash for a row with no
// commits.
func TestWeekPageCellsAreTotalsAndPercentages(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got,
		"<td class=\"num\">1"+metrics.ThousandsSpace+"338</td>", "<td class=\"num\">29</td>",
		"<td class=\"num\">2.3%</td>", "<td class=\"num\">13%</td>",
		"<td class=\"num\">33%</td>", "<td class=\"num\">0%</td>",
		"<td class=\"num\">-</td>")
}

// TestWeekPageRowPerRepositoryKeepsItsDeployments: the commits side reads an
// en dash, the deployments are the row's own percentages, and the weekend
func TestWeekPageRowPerRepositoryKeepsItsDeployments(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got, "<td>\u2013</td>", "<td class=\"num\">2.7%</td>",
		"<td class=\"num\">33%</td>")
	wantCount(t, got, "<td>\u2013</td>", 8)
}

// TestWeekPageHeadsLabelRowsAsTheTbdPageDoes: a label or service row is
// class label with the project visually hidden before it.
func TestWeekPageHeadsLabelRowsAsTheTbdPageDoes(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got, `<th scope="row">Acme Shop</th>`, `<th scope="row">Acme Docs</th>`,
		`<tr class="label">`, `<span class="visually-hidden">Acme Shop: </span>`)
	wantCount(t, got, `<tr class="label">`, 2)
}

// TestWeekPageLeavesOutSubRowsWithSubRowsOff (forsgren#482, sub_rows: false).
func TestWeekPageLeavesOutSubRowsWithSubRowsOff(t *testing.T) {
	data := weekPageData()
	data.HideSubRows = true
	got := rendered(t, "week.html", data)
	wantNone(t, "week.html", got, "Website", "API", `class="label"`, "\u2013")
	wantAll(t, "week.html", got, `<th scope="row">Acme Shop</th>`, `<th scope="row">Acme Docs</th>`)
}

// TestWeekPageSaysWhyThereIsNoTable: no projects, or nothing read yet.
func TestWeekPageSaysWhyThereIsNoTable(t *testing.T) {
	noProjects := calculated()
	noProjects.NoProjects = true
	got := rendered(t, "week.html", noProjects)
	wantAll(t, "week.html", got, "No projects are listed yet, so there is no week to show.")
	wantNone(t, "week.html", got, "<table")
	got = rendered(t, "week.html", calculated())
	wantAll(t, "week.html", got, "No commits or deployments have been collected yet, so there is no week to show.")
	wantNone(t, "week.html", got, "<table")
}

// TestWeekPageIsListedAfterTbdInTheMenu: the menu names Week last.
func TestWeekPageIsListedAfterTbdInTheMenu(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	if !strings.Contains(got, `<a href="tbd.html">TBD</a> · <span aria-current="page">Week</span></nav>`) {
		t.Errorf("want Week after TBD, current, got:\n%s", got)
	}
}
