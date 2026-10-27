package page

import (
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The Week page (forsgren#531, step 2, decisions #532 A, #533 A, #534 A): a
// table with a row per project and per label, service and rule, the commits
// and deployments of the DORA window per weekday, and a weekend share.

// weekPageData is the Week page's data: Acme Shop's total, its Website
// label, its API service without paths (commits Per repository), and Acme
// Docs with deployments and no commit. The made-up counts differ so no cell repeats.
func weekPageData() Data {
	data := calculated()
	data.Week = metrics.Week{
		Start: time.Date(2026, 9, 3, 0, 0, 0, 0, time.UTC),
		End:   time.Date(2026, 10, 3, 0, 0, 0, 0, time.UTC),
		Rows: []metrics.WeekRow{
			{Level: metrics.ProjectRow, Name: "Acme Shop", Project: "Acme Shop",
				Commits:     [7]int{31, 40, 1234, 8, 17, 6, 2},
				Deployments: [7]int{4, 5, 9, 1, 0, 3, 7}},
			{Level: metrics.LabelRow, Name: "Website", Project: "Acme Shop",
				Commits:     [7]int{3, 0, 1, 0, 2, 2, 1},
				Deployments: [7]int{1, 0, 0, 2, 0, 0, 5}},
			{Level: metrics.LabelRow, Name: "API", Project: "Acme Shop", Service: true, PerRepository: true,
				Deployments: [7]int{0, 1, 0, 0, 12, 0, 0}},
			{Level: metrics.ProjectRow, Name: "Acme Docs", Project: "Acme Docs",
				Deployments: [7]int{0, 0, 1, 0, 2, 0, 0}},
		},
	}
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

// TestWeekPageSaysItsWindow: the date range of the DORA window above the
// table, naming dora_days, and that every weekday of it is counted.
func TestWeekPageSaysItsWindow(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got,
		"The last 30 days, from 2026-09-03 to 2026-10-03, every weekday of that window counted (UTC).")
	data := weekPageData()
	data.DoraDays = 90
	wantAll(t, "week.html", rendered(t, "week.html", data), "The last 90 days, from 2026-09-03 to 2026-10-03,")
}

// TestWeekPageHasTheHeadersAndTheReadingLine: Project, the seven weekdays and
// the weekend share, the figure columns classed num, and the line on reading
// a cell under the h1.
func TestWeekPageHasTheHeadersAndTheReadingLine(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got, `<h1 id="week-heading">Week</h1>`, `<th scope="col">Project</th>`,
		`<th scope="col" class="num">Mon</th>`, `<th scope="col" class="num">Thu</th>`,
		`<th scope="col" class="num">Sun</th>`, `<th scope="col" class="num">Weekend share</th>`,
		"Each day shows commits · deployments")
	wantCount(t, got, `<th scope="col"`, 9)
}

// TestWeekPageCellsAreCommitsAndDeployments: the day cells, 0 · 0 for a day
// without activity, a thousands space for 1000 and more, the weekend share
// as a percent, a dash for a row with no commits.
func TestWeekPageCellsAreCommitsAndDeployments(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got,
		"<td class=\"num\">31 · 4</td>", "<td class=\"num\">1 234 · 9</td>",
		"<td class=\"num\">0 · 0</td>", "<td class=\"num\">33%</td>", "<td class=\"num\">0.59%</td>",
		"<td class=\"num\">-</td>")
}

// TestWeekPageRowPerRepositoryKeepsItsDeployments: the commits side reads Per
// repository, the deployments are the row's own, and the weekend share is the
// repository's.
func TestWeekPageRowPerRepositoryKeepsItsDeployments(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got, "<td>– · 1</td>", "<td>– · 12</td>",
		"<td>Per repository</td>")
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
	wantNone(t, "week.html", got, "Website", "API", `class="label"`, "Per repository")
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
