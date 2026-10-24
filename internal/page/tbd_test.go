package page

import (
	"bytes"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// tbdData is the TBD page's data: Acme Shop with 4 commits and a deviation,
// Acme Tools with 2 commits, so a mean and no deviation, and Acme Docs with
// no commit; their Mainline Lead Times (tbdLeads), their Developers, and the
// push and deployment groups of forsgren#397, step 5: Acme Shop with every
// figure, Acme Tools with a mean only, Acme Docs with its push read refused
// and Acme Web with no push collected yet. Acme Shop has half of its commits
// timed by author date, so a plain note; Acme Web has more than half, so the
// cell says so (forsgren#345, step 3).
func tbdData() Data {
	return tbdDataWith(tbdLeads())
}

// tbdLeads are the Mainline Lead Times of tbdData (forsgren#256, step 2):
// Acme Shop's 5 pull requests all within 24 hours, Acme Tools' one cut pull
// request, no human one for Acme Docs but 2 of bots, and Acme Web's 12 with
// one timed by its created time, next to 3 of bots and 1 of unknown author
// (forsgren#345, step 2).
func tbdLeads() []metrics.MainlineLeadTime {
	return []metrics.MainlineLeadTime{
		{Project: "Acme Shop", PullRequests: 5, Mean: 3 * time.Hour, Deviation: time.Hour, WithinReference: 5},
		{Project: "Acme Tools", PullRequests: 1, Mean: 30 * time.Hour, Cut: 1},
		{Project: "Acme Docs", Bots: 2},
		{Project: "Acme Web", PullRequests: 12, Mean: 20 * time.Hour, Deviation: 10 * time.Hour, WithinReference: 7,
			CreatedStandsIn: 1, Bots: 3, UnknownAuthors: 1},
	}
}

// tbdDataWith is tbdData with the Mainline Lead Times leads.
func tbdDataWith(leads []metrics.MainlineLeadTime) Data {
	data := calculated()
	data.Mainline = []metrics.MainlineInterval{
		{Project: "Acme Shop", Commits: 4, Gaps: 3, Mean: 2 * time.Hour, Deviation: time.Hour, Median: 2 * time.Hour,
			ByAuthorDate: 2},
		{Project: "Acme Tools", Commits: 2, Gaps: 1, Mean: 2 * time.Hour},
		{Project: "Acme Docs"},
		{Project: "Acme Web", Commits: 13, Gaps: 12, Mean: 24 * time.Minute, Deviation: 2*time.Hour + 24*time.Minute,
			Median: 5 * time.Minute, P90: time.Hour, ByAuthorDate: 7},
	}
	data.Developers = []metrics.Developers{
		{Project: "Acme Shop", Count: 3, Commits: 4},
		{Project: "Acme Tools", Count: 1, Commits: 2},
		{Project: "Acme Docs", Count: 1, Commits: 1},
		{Project: "Acme Web", Count: 12, Commits: 20},
	}
	data.MainlineLead = leads
	data.PushMeasures = tbdPushes()
	data.DeployMeasures = tbdDeploys()
	data.DeploymentVolumes = []metrics.DeploymentVolume{
		{Project: "Acme Shop", Count: 85, Releases: true}, {Project: "Acme Tools", Count: 7},
		{Project: "Acme Docs", Count: 2}, {Project: "Acme Web", Count: 1, Releases: true},
	}
	return data
}

// tbdPushes are the push measures of tbdData's projects.
func tbdPushes() []metrics.PushMeasures {
	return []metrics.PushMeasures{
		{Project: "Acme Shop", Pushes: 20, Commits: 40, PullRequests: 10, Direct: 30, UnknownAuthors: 4,
			TimeToMain: metrics.DurationSpread{Count: 40, Mean: time.Hour, Median: 30 * time.Minute, P90: 3 * time.Hour},
			PerPush:    metrics.CountSpread{Count: 20, Mean: 2, Median: 1.5, P90: 6}},
		{Project: "Acme Tools", Pushes: 1, Commits: 1, Direct: 1,
			TimeToMain: metrics.DurationSpread{Count: 1, Mean: 2 * time.Hour},
			PerPush:    metrics.CountSpread{Count: 1, Mean: 1}},
		{Project: "Acme Docs", NotReadable: true},
		{Project: "Acme Web", Uncollected: true},
	}
}

// tbdDeploys are the deployment measures of tbdData's projects: Acme Shop
// with ten deployments, so every figure, Acme Tools with one, Acme Docs with
// two and Acme Web with one.
func tbdDeploys() []metrics.DeployMeasures {
	return []metrics.DeployMeasures{
		{Project: "Acme Shop", Commits: 50, Deployments: 10,
			TimeToDeploy:  metrics.DurationSpread{Count: 50, Mean: 2 * time.Hour, Median: time.Hour, P90: 5 * time.Hour},
			PerDeployment: metrics.CountSpread{Count: 10, Mean: 5, Median: 4.5, P90: 12}},
		{Project: "Acme Tools", Commits: 3, Deployments: 1,
			TimeToDeploy:  metrics.DurationSpread{Count: 3, Mean: time.Hour, Median: time.Hour},
			PerDeployment: metrics.CountSpread{Count: 1, Mean: 3}},
		{Project: "Acme Docs", Commits: 2, Deployments: 2,
			TimeToDeploy:  metrics.DurationSpread{Count: 2, Mean: 30 * time.Minute, Median: 30 * time.Minute},
			PerDeployment: metrics.CountSpread{Count: 2, Mean: 1, Median: 1}},
		{Project: "Acme Web", Commits: 1, Deployments: 1,
			TimeToDeploy:  metrics.DurationSpread{Count: 1, Mean: 10 * time.Minute},
			PerDeployment: metrics.CountSpread{Count: 1, Mean: 2}},
	}
}

// tbdPushCells are the cells of tbdData's projects before the pull requests
// cell, parted by " | ": volume (commits, pushes, deployments), shares
// (direct, pull requests, unknown authors), time to main, commits per push,
// time to deploy, commits per deployment (mean, median, p90 each). A cell
// starting with @ is the one cell across the push groups, nine columns wide.
var tbdPushCells = map[string]string{
	"Acme Shop": "40 | 20 | 85 releases | 75% | 25% | 10% | 1 h | 30 min | 3 h | 2 | 1.5 | 6 | " +
		"2 h | 1 h | 5 h | 5 | 4.5 | 12",
	"Acme Tools": "1 | 1 | 7 | 100% | 0% | 0% | 2 h | - | - | 1 | - | - | 1 h | 1 h | - | 3 | - | -",
	"Acme Docs":  "- | - | 2 | @Push activity not readable | 30 min | 30 min | - | 1 | 1 | -",
	"Acme Web":   "- | - | 1 release | @Pushes not collected yet | 10 min | - | - | 2 | - | -",
}

// noLeads are the Mainline Lead Times of tbdData's projects without a pull
// request merged in the window.
func noLeads() []metrics.MainlineLeadTime {
	leads := tbdLeads()
	for i := range leads {
		leads[i] = metrics.MainlineLeadTime{Project: leads[i].Project}
	}
	return leads
}

// uncollected is tbdData with no data/pulls.csv beside the history: the pull
// requests have not been collected yet (forsgren#256, step 2).
func uncollected() Data {
	data := tbdDataWith(noLeads())
	data.PullsUncollected = true
	return data
}

// notReadable is tbdData with collect refused the pull request read of a
// repository of Acme Tools and of Acme Docs (forsgren#337, step 2): Acme
// Tools' cut pull request stays read, Acme Docs has none.
func notReadable() Data {
	data := tbdData()
	data.MainlineLead[1].NotReadable = true
	data.MainlineLead[2].NotReadable = true
	return data
}

// tbdRow is the TBD page's row of project, as the template writes it: the
// cells of tbdPushCells, its pull requests cell lead, its five Mainline
// Interval cells (interval, parted by " | ", forsgren#387, step 1) and its
// Developers count (forsgren#397, step 5).
func tbdRow(project, interval, lead, developers string) string {
	return "<th scope=\"row\">" + project + "</th>\n            " + tds(tbdPushCells[project]) +
		"\n            <td>" + lead + "</td>\n            " + tds(interval) + "\n            " + tds(developers) + "\n"
}

// tds are the cells of cells, parted by " | ", as the template writes a row's
// cells: one td on each line; a cell starting with @ is the push groups' one
// cell across nine columns.
func tds(cells string) string {
	parts := strings.Split(cells, " | ")
	for i, c := range parts {
		if text, spans := strings.CutPrefix(c, "@"); spans {
			parts[i] = "<td colspan=\"9\">" + text + "</td>"
		} else {
			parts[i] = "<td>" + c + "</td>"
		}
	}
	return strings.Join(parts, "\n            ")
}

// tbdGroups are the group headers of the TBD table in order, each with its
// columns' headers (forsgren#397, step 5, Yves's ruling on #401): the units
// are in the names, durations and counts of commits.
var tbdGroups = []struct {
	name    string
	columns []string
	hidden  string // the measure, said after each column's word in its accessible name
}{
	{"Volume", []string{"Commits", "Pushes", "Deployments"}, ""},
	{"Shares of commits", []string{"Direct", "Pull requests", "Unknown authors"}, ""},
	{"Time to main per commit (duration)", []string{"mean", "median", "p90"}, "time to main"},
	{"Commits per push", []string{"mean", "median", "p90"}, "commits per push"},
	{"Time to deploy per commit (duration)", []string{"mean", "median", "p90"}, "time to deploy"},
	{"Commits per deployment", []string{"mean", "median", "p90"}, "commits per deployment"},
	{"Mainline Lead Time", []string{"pull requests"}, ""},
	{"Mainline Interval", []string{"mean", "deviation", "median", "p90", "gaps"}, ""},
	{"Developers", []string{"developers"}, ""},
}

// tbdHeaders are the two header rows' cells of the TBD table as the template
// writes them: Project over both, the groups on top, their columns beneath.
func tbdHeaders() (top, beneath string) {
	const indent = "\n            "
	tops := []string{`<th scope="col" rowspan="2">Project</th>`}
	var columns []string
	for _, g := range tbdGroups {
		tops = append(tops, `<th scope="colgroup" colspan="`+strconv.Itoa(len(g.columns))+`">`+g.name+`</th>`)
		for _, c := range g.columns {
			label := ""
			if g.hidden != "" {
				label = ` aria-label="` + c + ` ` + g.hidden + `"`
			}
			columns = append(columns, `<th scope="col"`+label+`>`+c+`</th>`)
		}
	}
	return strings.Join(tops, indent), strings.Join(columns, indent)
}

// within is the end of a Mainline Lead Time cell after its count: the share of
// the pull requests merged within 24 hours in whole percent, then how many of
// how many (forsgren#345, step 2, #343).
func within(percent, counts string) string {
	return " · " + percent + "% (" + counts + ") pull requests merged within 24 hours of their first commit"
}

// shopInterval and webInterval are the Mainline Interval cells of Acme Shop,
// half of its commits timed by author date, and of Acme Web, more than half
// (forsgren#345, step 3).
const (
	shopInterval  = "2 h | 1 h | 2 h | - | 3 · 2 commits timed by author date"
	toolsInterval = "2 h | - | - | - | 1"
	noInterval    = "- | - | - | - | -"
	webInterval   = "24 min | 2 h 24 min | 5 min | 1 h | 12 · " +
		"Mostly estimated: 7 of 13 commits timed by author date."
)

// noHumanPulls is the pull requests cell of a project without a human pull
// request in the window: a dash (forsgren#390, step 2).
const noHumanPulls = "-"

// TestTbdPageHasTwoLevelHeadersWithTheUnitsInTheGroupNames (forsgren#397,
// step 5, Yves's ruling on #401): the groups on top in the order of the
// ruling, each scoped as a column group, mean, median and p90 beneath each
// measure; durations say so, batch sizes are commits per push and per
// deployment; the old direct and batch size columns and the unknown authors
// of Developers are gone.
func TestTbdPageHasTwoLevelHeadersWithTheUnitsInTheGroupNames(t *testing.T) {
	top, beneath := tbdHeaders()
	got := rendered(t, "tbd.html", tbdData())
	const open, between, end = "<thead>\n          <tr>\n            ", "\n          </tr>\n          <tr>\n            ",
		"\n          </tr>\n        </thead>"
	wantAll(t, "tbd.html", got, open+top+between+beneath+end)
	wantNone(t, "tbd.html", got, `<th scope="col">direct</th>`, `<th scope="col">batch size</th>`,
		`<th scope="col">unknown authors</th>`)
}

// TestTbdPageShowsTheRowsOfEachProject (forsgren#397, step 5): volume,
// shares, the four measures, the pull requests lead time, the Mainline
// Interval and the developers count; a project whose push read was refused,
// or with no push collected yet, has one cell across the push groups and no
// deployment number in its place; releases are named in the Deployments cell
// of a project measured by them alone.
func TestTbdPageShowsTheRowsOfEachProject(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got,
		tbdRow("Acme Shop", shopInterval, "3 h ± 1 h (5)"+within("100", "5 of 5"), "3"),
		tbdRow("Acme Tools", toolsInterval,
			"1 d 6 h ± - (1, 1 cut)"+within("0", "0 of 1")+" · the mean is a lower bound", "1"),
		tbdRow("Acme Docs", noInterval, noHumanPulls+" · 2 bot pull requests not counted", "1"),
		tbdRow("Acme Web", webInterval,
			"20 h ± 10 h (12)"+within("58", "7 of 12")+" · 1 pull request timed by its created time"+
				" · 3 bot pull requests not counted · 1 pull request of unknown author not counted", "12"))
}

// TestTbdPageSaysThePullRequestsAreNotCollectedYet (forsgren#256, step 2):
// without data/pulls.csv beside the history, every Mainline Lead Time cell
// says the pull requests have not been collected yet, never a dash, which is
// a project without a pull request merged in the window.
func TestTbdPageSaysThePullRequestsAreNotCollectedYet(t *testing.T) {
	const notYet = "No pull requests have been collected yet"
	got := rendered(t, "tbd.html", uncollected())
	wantAll(t, "uncollected", got, tbdRow("Acme Shop", shopInterval, notYet, "3"),
		tbdRow("Acme Docs", noInterval, notYet, "1"), tbdRow("Acme Web", webInterval, notYet, "12"))
	noneInWindow := rendered(t, "tbd.html", tbdDataWith(noLeads()))
	wantNone(t, "collected, none in the window", noneInWindow, notYet)
	wantAll(t, "collected, none in the window", noneInWindow, tbdRow("Acme Docs", noInterval, noHumanPulls, "1"))
}

// TestTbdPageSaysThePullRequestsAreNotReadable (forsgren#337, step 2): a
// project collect was refused the pull request read of shows "Pull requests
// not readable" in its Mainline Lead Time cell, never the lead time of what
// was read nor the dash of no pull request, also while data/pulls.csv is
// absent; the other projects keep their cell.
func TestTbdPageSaysThePullRequestsAreNotReadable(t *testing.T) {
	const refused, notYet = "Pull requests not readable", "No pull requests have been collected yet"
	got := rendered(t, "tbd.html", notReadable())
	wantAll(t, "not readable", got, tbdRow("Acme Tools", toolsInterval, refused, "1"),
		tbdRow("Acme Docs", noInterval, refused, "1"),
		tbdRow("Acme Shop", shopInterval, "3 h ± 1 h (5)"+within("100", "5 of 5"), "3"))
	uncollectedRefused := notReadable()
	uncollectedRefused.PullsUncollected = true
	got = rendered(t, "tbd.html", uncollectedRefused)
	wantAll(t, "not collected yet", got, tbdRow("Acme Docs", noInterval, refused, "1"),
		tbdRow("Acme Shop", shopInterval, notYet, "3"))
}

// TestTbdPageRefusesMeasuresOfOtherProjects (forsgren#273, step 3;
// forsgren#397, step 5): the Developers, the Mainline Lead Times, the push and
// deployment measures and the deployment volumes are paired with the Mainline
// Intervals by project, so a render whose any of them is missing, one too
// many, or names another project in a row, fails instead of showing a number
// in the wrong row.
func TestTbdPageRefusesMeasuresOfOtherProjects(t *testing.T) {
	cases := map[string]func(*Data){
		"developers missing": func(d *Data) { d.Developers = d.Developers[:3] },
		"developers extra": func(d *Data) {
			d.Developers = append(d.Developers, metrics.Developers{Project: "Acme Gone", Count: 1})
		},
		"developers swapped": func(d *Data) { d.Developers[0], d.Developers[1] = d.Developers[1], d.Developers[0] },
		"leads missing":      func(d *Data) { d.MainlineLead = d.MainlineLead[:3] },
		"leads extra": func(d *Data) {
			d.MainlineLead = append(d.MainlineLead, metrics.MainlineLeadTime{Project: "Acme Gone"})
		},
		"leads swapped":   func(d *Data) { d.MainlineLead[0], d.MainlineLead[1] = d.MainlineLead[1], d.MainlineLead[0] },
		"pushes missing":  func(d *Data) { d.PushMeasures = d.PushMeasures[:3] },
		"pushes swapped":  func(d *Data) { d.PushMeasures[0], d.PushMeasures[1] = d.PushMeasures[1], d.PushMeasures[0] },
		"deploys missing": func(d *Data) { d.DeployMeasures = d.DeployMeasures[:3] },
		"deploys swapped": func(d *Data) {
			d.DeployMeasures[0], d.DeployMeasures[1] = d.DeployMeasures[1], d.DeployMeasures[0]
		},
		"volumes missing": func(d *Data) { d.DeploymentVolumes = d.DeploymentVolumes[:3] },
		"volumes swapped": func(d *Data) {
			d.DeploymentVolumes[0], d.DeploymentVolumes[1] = d.DeploymentVolumes[1], d.DeploymentVolumes[0]
		},
	}
	for name, change := range cases {
		data := tbdData()
		change(&data)
		var got bytes.Buffer
		if err := Render(&got, "tbd.html", data); err == nil {
			t.Errorf("%s: want the render to fail, got:\n%s", name, got.String())
		}
	}
}

// TestTbdPageGolden (forsgren#253, step 4 of 7): the TBD page is a root page,
// tbd.html, with a table of a row per project; with no projects, or no
// Mainline Interval read yet, one line says why in place of the table. Its
// Mainline Lead Time column (forsgren#256, step 2) has a golden with data,
// one with no pull request in the window, one before the pull requests were
// collected and one with refused pull request reads (forsgren#337, step 2);
// the golden with data holds the push groups of forsgren#397, step 5, with
// both of their states.
func TestTbdPageGolden(t *testing.T) {
	noProjects := calculated()
	noProjects.NoProjects = true
	checkPageGolden(t, "tbd.html", "testdata/tbd.golden.html", tbdData())
	checkPageGolden(t, "tbd.html", "testdata/tbd.no-data.golden.html", calculated())
	checkPageGolden(t, "tbd.html", "testdata/tbd.no-projects.golden.html", noProjects)
	checkPageGolden(t, "tbd.html", "testdata/tbd.lead-no-data.golden.html", tbdDataWith(noLeads()))
	checkPageGolden(t, "tbd.html", "testdata/tbd.lead-not-collected.golden.html", uncollected())
	checkPageGolden(t, "tbd.html", "testdata/tbd.lead-not-readable.golden.html", notReadable())
}

// TestTbdPageHasItsHeadingAndTable (forsgren#253): the title and the h1 (id
// tbd-heading) name trunk-based development; the table is the h1's region,
// with no caption, and a row header for each project.
func TestTbdPageHasItsHeadingAndTable(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got, "<title>Trunk-based development [TBD] (BETA) · ",
		`<h1 id="tbd-heading">Trunk-based development [TBD] (BETA)</h1>`, `aria-labelledby="tbd-heading"`,
		`<th scope="col" rowspan="2">Project</th>`, `<th scope="row">Acme Shop</th>`,
		`<th scope="row">Acme Tools</th>`, `<th scope="row">Acme Docs</th>`, `<th scope="row">Acme Web</th>`)
	wantNone(t, "tbd.html", got, "<caption", "metrics are coming to this page")
}

// TestTbdPageHasNoExplanationAndNoLeadTimeLine (forsgren#271): the h1 is
// followed by the table, or by its one line; the explanation of the Mainline
// Interval and of the Mainline Lead Time is the legend's, not the page's.
func TestTbdPageHasNoExplanationAndNoLeadTimeLine(t *testing.T) {
	for name, data := range map[string]Data{"data": tbdData(), "no data": calculated()} {
		wantNone(t, name, rendered(t, "tbd.html", data), "sample standard deviation", "deployments of the last",
			"Mainline Lead Time is", "A dash is", "each commit once", "lower bound, so")
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

// TestTbdTableWrapsItsCells (forsgren#350): the TBD table's cells carry long
// notes, so the table is class wraps, never no-wrap: its cells break and its
// columns share the page's width, at a laptop and at a phone width alike.
func TestTbdTableWrapsItsCells(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got, `<table class="wraps">`)
	wantNone(t, "tbd.html", got, `class="no-wrap"`)
}
